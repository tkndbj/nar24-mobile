import admin from 'firebase-admin';

class BatchProcessor {
  constructor(db) {
    this.db = db;
    this.processedBatchCache = new Map(); // In-memory cache for this run
  }

  aggregateClicks(batchDocs) {
    const productClicks = new Map();
    const shopProductClicks = new Map();
    const shopClicks = new Map();

    for (const doc of batchDocs) {
      const data = doc.data();
      
      if (data.productClicks) {
        Object.entries(data.productClicks).forEach(([id, count]) => {
          productClicks.set(id, (productClicks.get(id) || 0) + count);
        });
      }

      if (data.shopProductClicks) {
        Object.entries(data.shopProductClicks).forEach(([id, count]) => {
          shopProductClicks.set(id, (shopProductClicks.get(id) || 0) + count);
        });
      }

      if (data.shopClicks) {
        Object.entries(data.shopClicks).forEach(([id, count]) => {
          shopClicks.set(id, (shopClicks.get(id) || 0) + count);
        });
      }
    }

    return {productClicks, shopProductClicks, shopClicks};
  }

  async isBatchProcessed(batchId, collection) {
    // Check in-memory cache first
    const cacheKey = `${collection}_${batchId}`;
    if (this.processedBatchCache.has(cacheKey)) {
      return true;
    }

    // Check Firestore
    const processedDoc = await this.db
      .collection('_processed_batches')
      .doc(cacheKey)
      .get();

    if (processedDoc.exists) {
      this.processedBatchCache.set(cacheKey, true);
      return true;
    }

    return false;
  }

  async markBatchProcessed(batchId, collection, itemCount) {
    const cacheKey = `${collection}_${batchId}`;
    
    await this.db
      .collection('_processed_batches')
      .doc(cacheKey)
      .set({
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        itemCount,
        collection,
      });

    this.processedBatchCache.set(cacheKey, true);
  }

  async updateProductsWithRetry(productClicks, shopProductClicks, batchId, maxRetries = 3) {
    let success = 0;
    const failed = [];

    // Process shop_products
    const shopProductEntries = Array.from(shopProductClicks.entries());
    const shopProductChunks = this.chunkArray(shopProductEntries, 450);

    for (const [index, chunk] of shopProductChunks.entries()) {
      const chunkBatchId = `${batchId}_shop_products_${index}`;
      
      // ✅ Check if already processed
      if (await this.isBatchProcessed(chunkBatchId, 'shop_products')) {
        console.log(`⏭️ Chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processChunkWithRetry(
        chunk,
        'shop_products',
        maxRetries,
        chunkBatchId,
      );
      success += result.success;
      failed.push(...result.failed);
    }

    // Process products
    const productEntries = Array.from(productClicks.entries());
    const productChunks = this.chunkArray(productEntries, 450);

    for (const [index, chunk] of productChunks.entries()) {
      const chunkBatchId = `${batchId}_products_${index}`;
      
      // ✅ Check if already processed
      if (await this.isBatchProcessed(chunkBatchId, 'products')) {
        console.log(`⏭️ Chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processChunkWithRetry(
        chunk,
        'products',
        maxRetries,
        chunkBatchId,
      );
      success += result.success;
      failed.push(...result.failed);
    }

    return {success, failed};
  }

  async processChunkWithRetry(chunk, collection, maxRetries, chunkBatchId) {
    let attempt = 0;
    let remainingChunk = [...chunk];
    
    while (attempt < maxRetries) {
      try {
        const batch = this.db.batch();
  
        for (const [productId, count] of remainingChunk) {
          const ref = this.db.collection(collection).doc(productId);
          batch.update(ref, {
            clickCount: admin.firestore.FieldValue.increment(count),
            lastClickDate: admin.firestore.FieldValue.serverTimestamp(),
            metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // ✅ Mark as processed atomically
        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`${collection}_${chunkBatchId}`);
        
        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection,
        });
  
        await batch.commit();
        
        // ✅ Cache the processed state
        this.processedBatchCache.set(`${collection}_${chunkBatchId}`, true);
        
        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(
          `Chunk processing failed (attempt ${attempt}/${maxRetries}):`,
          error.message,
        );
        
        // Handle NOT_FOUND errors by filtering out missing docs
        if (error.code === 5 || 
            error.message.includes('NOT_FOUND') || 
            error.message.includes('No document to update')) {
          console.log(`🔍 Batch reading ${remainingChunk.length} documents...`);
          
          const refs = remainingChunk.map(([id]) => 
            this.db.collection(collection).doc(id),
          );
          
          const docs = await this.db.getAll(...refs);
          
          const validItems = [];
          const invalidIds = [];
          
          remainingChunk.forEach(([productId, count], index) => {
            if (docs[index].exists) {
              validItems.push([productId, count]);
            } else {
              invalidIds.push(productId);
            }
          });
          
          if (invalidIds.length > 0) {
            console.log(`⚠️ Found ${invalidIds.length} non-existent docs, retrying with ${validItems.length}`);
            remainingChunk = validItems;
            
            // Don't count as retry if we filtered out invalid docs
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }
        
        // ✅ IMPROVED: Don't retry on certain errors
        if (error.code === 7) { // PERMISSION_DENIED
          console.error('❌ Permission denied, not retrying');
          return {
            success: 0,
            failed: remainingChunk.map(([id]) => id),
          };
        }
        
        if (attempt >= maxRetries) {
          return {
            success: 0,
            failed: remainingChunk.map(([id]) => id),
          };
        }
        
        // Exponential backoff
        const backoffMs = Math.min(Math.pow(2, attempt - 1) * 1000, 10000);
        await this.sleep(backoffMs);
      }
    }
  
    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  async updateShopsWithRetry(shopProductClicks, shopClicks, shopIds, batchId, maxRetries = 3) {
    const shopProductViews = new Map();
    
    for (const [productId, count] of shopProductClicks.entries()) {
      const shopId = shopIds.get(productId);
      if (shopId) {
        shopProductViews.set(
          shopId,
          (shopProductViews.get(shopId) || 0) + count,
        );
      }
    }

    const allShopIds = new Set([
      ...shopProductViews.keys(),
      ...shopClicks.keys(),
    ]);

    const shopUpdates = Array.from(allShopIds).map((shopId) => {
      const productViews = shopProductViews.get(shopId) || 0;
      const directClicks = shopClicks.get(shopId) || 0;
      return [shopId, productViews, directClicks];
    });

    const chunks = this.chunkArray(shopUpdates, 450);
    let success = 0;
    const failed = [];

    for (const [index, chunk] of chunks.entries()) {
      const chunkBatchId = `${batchId}_shops_${index}`;
      
      // ✅ Check if already processed
      if (await this.isBatchProcessed(chunkBatchId, 'shops')) {
        console.log(`⏭️ Shop chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processShopChunkWithRetry(chunk, maxRetries, chunkBatchId);
      success += result.success;
      failed.push(...result.failed);
    }

    return {success, failed};
  }

  async processShopChunkWithRetry(chunk, maxRetries, chunkBatchId) {
    let attempt = 0;
    let remainingChunk = [...chunk];
    
    while (attempt < maxRetries) {
      try {
        const batch = this.db.batch();
  
        for (const [shopId, productViews, directClicks] of remainingChunk) {
          const ref = this.db.collection('shops').doc(shopId);
          
          const updateData = {
            'metrics.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
          };
  
          if (productViews > 0) {
            updateData['metrics.totalProductViews'] = 
              admin.firestore.FieldValue.increment(productViews);
          }
  
          if (directClicks > 0) {
            updateData.clickCount = 
              admin.firestore.FieldValue.increment(directClicks);
          }
  
          batch.update(ref, updateData);
        }

        // ✅ Mark as processed atomically
        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`shops_${chunkBatchId}`);
        
        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'shops',
        });
  
        await batch.commit();
        
        // ✅ Cache the processed state
        this.processedBatchCache.set(`shops_${chunkBatchId}`, true);
        
        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(
          `Shop chunk processing failed (attempt ${attempt}/${maxRetries}):`,
          error.message,
        );
        
        if (error.code === 5 || 
            error.message.includes('NOT_FOUND') || 
            error.message.includes('No document to update')) {
          console.log(`🔍 Batch reading ${remainingChunk.length} shops...`);
          
          const refs = remainingChunk.map(([shopId]) => 
            this.db.collection('shops').doc(shopId),
          );
          
          const docs = await this.db.getAll(...refs);
          
          const validItems = [];
          const invalidIds = [];
          
          remainingChunk.forEach(([shopId, productViews, directClicks], index) => {
            if (docs[index].exists) {
              validItems.push([shopId, productViews, directClicks]);
            } else {
              invalidIds.push(shopId);
            }
          });
          
          if (invalidIds.length > 0) {
            console.log(`⚠️ Found ${invalidIds.length} missing shops`);
            console.warn(`Missing shops:`, invalidIds.slice(0, 20));
            
            remainingChunk = validItems;
            attempt = Math.max(0, attempt - 1);
            
            if (validItems.length === 0) {
              return {success: 0, failed: invalidIds};
            }
            
            continue;
          }
        }
        
        if (attempt >= maxRetries) {
          return {
            success: 0,
            failed: remainingChunk.map(([shopId]) => shopId),
          };
        }
        
        const backoffMs = Math.min(Math.pow(2, attempt - 1) * 1000, 10000);
        await this.sleep(backoffMs);
      }
    }
  
    return {success: 0, failed: remainingChunk.map(([shopId]) => shopId)};
  }

  chunkArray(array, size) {
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }

  sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /**
   * ✅ NEW: Cleanup old processed batch records (keep 7 days)
   */
  async cleanupProcessedBatches() {
    const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    );

    const oldBatches = await this.db
      .collection('_processed_batches')
      .where('processedAt', '<', sevenDaysAgo)
      .limit(500)
      .get();

    if (oldBatches.empty) return;

    console.log(`🧹 Cleaning up ${oldBatches.size} old processed batch records`);

    const chunks = this.chunkArray(oldBatches.docs, 500);
    for (const chunk of chunks) {
      const batch = this.db.batch();
      chunk.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
  }
}

export {BatchProcessor};
