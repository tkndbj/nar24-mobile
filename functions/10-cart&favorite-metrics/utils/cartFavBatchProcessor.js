import admin from 'firebase-admin';

class CartFavBatchProcessor {
  constructor(db) {
    this.db = db;
    this.processedBatchCache = new Map();
  }

  aggregateEvents(batchDocs) {
    const productDeltas = new Map(); // products collection
    const shopProductDeltas = new Map(); // shop_products collection
    const shopDeltas = new Map(); // shops collection

    for (const doc of batchDocs) {
      const data = doc.data();
      const events = data.events || [];

      for (const event of events) {
        const {type, productId, shopId} = event;

        const isAddition = type.includes('_added');
        const delta = isAddition ? 1 : -1;

        // ✅ FIX 1: Determine which collection this product belongs to
        const isShopProduct = !!shopId;

        if (isShopProduct) {
          // ✅ Only update shop_products for shop products
          if (!shopProductDeltas.has(productId)) {
            shopProductDeltas.set(productId, {cartDelta: 0, favDelta: 0});
          }
          const shopProductDelta = shopProductDeltas.get(productId);
          
          if (type.startsWith('cart_')) {
            shopProductDelta.cartDelta += delta;
          } else if (type.startsWith('favorite_')) {
            shopProductDelta.favDelta += delta;
          }

          // ✅ FIX 2: Shop metrics - only increment for shop products
          if (isAddition) {
            if (!shopDeltas.has(shopId)) {
              shopDeltas.set(shopId, {cartAdditions: 0, favAdditions: 0});
            }
            const shopDelta = shopDeltas.get(shopId);
            
            if (type === 'cart_added') {
              shopDelta.cartAdditions += 1;
            } else if (type === 'favorite_added') {
              shopDelta.favAdditions += 1;
            }
          }
        } else {
          // ✅ Only update products for regular user products (no shopId)
          if (!productDeltas.has(productId)) {
            productDeltas.set(productId, {cartDelta: 0, favDelta: 0});
          }
          const productDelta = productDeltas.get(productId);
          
          if (type.startsWith('cart_')) {
            productDelta.cartDelta += delta;
          } else if (type.startsWith('favorite_')) {
            productDelta.favDelta += delta;
          }
        }
      }
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'events_aggregated',
      regularProducts: productDeltas.size,
      shopProducts: shopProductDeltas.size,
      shops: shopDeltas.size,
    }));

    return {productDeltas, shopProductDeltas, shopDeltas};
  }

  async ensureNonNegativeCounts(collection, docIds) {
    if (docIds.length === 0) return;
    
    const refs = docIds.map((id) => this.db.collection(collection).doc(id));
    const docs = await this.db.getAll(...refs);
    
    const fixBatch = this.db.batch();
    let fixCount = 0;
    
    docs.forEach((doc) => {
      if (!doc.exists) return;
      
      const data = doc.data();
      const updates = {};
      
      // For products and shop_products
      if (data.cartCount != null && data.cartCount < 0) {
        updates.cartCount = 0;
        fixCount++;
      }
      if (data.favoritesCount != null && data.favoritesCount < 0) {
        updates.favoritesCount = 0;
        fixCount++;
      }
      
      // For shops (nested in metrics object)
      if (collection === 'shops' && data.metrics) {
        if (data.metrics.totalCartAdditions != null && data.metrics.totalCartAdditions < 0) {
          updates['metrics.totalCartAdditions'] = 0;
          fixCount++;
        }
        if (data.metrics.totalFavoriteAdditions != null && data.metrics.totalFavoriteAdditions < 0) {
          updates['metrics.totalFavoriteAdditions'] = 0;
          fixCount++;
        }
      }
      
      if (Object.keys(updates).length > 0) {
        fixBatch.update(doc.ref, updates);
      }
    });
    
    if (fixCount > 0) {
      await fixBatch.commit();
    }
  }

  async updateProductsWithRetry(productDeltas, batchId, maxRetries = 3) {
    if (productDeltas.size === 0) {
      console.log('✅ No regular products to update');
      return {success: 0, failed: []};
    }

    const entries = Array.from(productDeltas.entries());
    const chunks = this.chunkArray(entries, 450);
    
    let success = 0;
    const failed = [];

    for (const [index, chunk] of chunks.entries()) {
      const chunkBatchId = `${batchId}_products_${index}`;
      
      if (await this.isBatchProcessed(chunkBatchId, 'products')) {
        console.log(`⏭️ Chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processProductChunkWithRetry(
        chunk,
        maxRetries,
        chunkBatchId,
      );
      success += result.success;
      failed.push(...result.failed);
    }

    return {success, failed};
  }

  async processProductChunkWithRetry(chunk, maxRetries, chunkBatchId) {
    let attempt = 0;
    let remainingChunk = [...chunk];
    
    while (attempt < maxRetries) {
      try {
        const batch = this.db.batch();
  
        for (const [productId, deltas] of remainingChunk) {
          const ref = this.db.collection('products').doc(productId);
          
          const updateData = {
            metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          if (deltas.cartDelta !== 0) {
            updateData.cartCount = admin.firestore.FieldValue.increment(deltas.cartDelta);
          }

          if (deltas.favDelta !== 0) {
            updateData.favoritesCount = admin.firestore.FieldValue.increment(deltas.favDelta);
          }

          batch.update(ref, updateData);
        }

        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`products_${chunkBatchId}`);
        
        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'products',
        });
  
        await batch.commit();

        await this.ensureNonNegativeCounts('products', remainingChunk.map(([id]) => id));
        
        this.processedBatchCache.set(`products_${chunkBatchId}`, true);
        
        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(
          `Products chunk failed (attempt ${attempt}/${maxRetries}):`,
          error.message,
        );
        
        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          console.log(`🔍 Validating ${remainingChunk.length} products...`);
          
          const refs = remainingChunk.map(([id]) => 
            this.db.collection('products').doc(id),
          );
          
          const docs = await this.db.getAll(...refs);
          
          const validItems = [];
          const invalidIds = [];
          
          remainingChunk.forEach(([productId, deltas], index) => {
            if (docs[index].exists) {
              validItems.push([productId, deltas]);
            } else {
              invalidIds.push(productId);
            }
          });
          
          if (invalidIds.length > 0) {
            console.warn(`⚠️ Skipping ${invalidIds.length} deleted/missing products: ${invalidIds.slice(0, 5).join(', ')}`);
            remainingChunk = validItems;
            
            // Don't retry if all products are invalid
            if (validItems.length === 0) {
              return {success: 0, failed: []};
            }
            
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }
        
        if (attempt >= maxRetries) {
          return {
            success: 0,
            failed: remainingChunk.map(([id]) => id),
          };
        }
        
        const backoffMs = Math.min(Math.pow(2, attempt - 1) * 1000, 10000);
        await this.sleep(backoffMs);
      }
    }
  
    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  async updateShopProductsWithRetry(shopProductDeltas, batchId, maxRetries = 3) {
    if (shopProductDeltas.size === 0) {
      console.log('✅ No shop products to update');
      return {success: 0, failed: []};
    }

    const entries = Array.from(shopProductDeltas.entries());
    const chunks = this.chunkArray(entries, 450);
    
    let success = 0;
    const failed = [];

    for (const [index, chunk] of chunks.entries()) {
      const chunkBatchId = `${batchId}_shop_products_${index}`;
      
      if (await this.isBatchProcessed(chunkBatchId, 'shop_products')) {
        console.log(`⏭️ Chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processShopProductChunkWithRetry(
        chunk,
        maxRetries,
        chunkBatchId,
      );
      success += result.success;
      failed.push(...result.failed);
    }

    return {success, failed};
  }

  async processShopProductChunkWithRetry(chunk, maxRetries, chunkBatchId) {
    let attempt = 0;
    let remainingChunk = [...chunk];
    
    while (attempt < maxRetries) {
      try {
        const batch = this.db.batch();
  
        for (const [productId, deltas] of remainingChunk) {
          const ref = this.db.collection('shop_products').doc(productId);
          
          const updateData = {
            metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          if (deltas.cartDelta !== 0) {
            updateData.cartCount = admin.firestore.FieldValue.increment(deltas.cartDelta);
          }

          if (deltas.favDelta !== 0) {
            updateData.favoritesCount = admin.firestore.FieldValue.increment(deltas.favDelta);
          }

          batch.update(ref, updateData);
        }

        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`shop_products_${chunkBatchId}`);
        
        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'shop_products',
        });
  
        await batch.commit();

        await this.ensureNonNegativeCounts('shop_products', remainingChunk.map(([id]) => id));
        
        this.processedBatchCache.set(`shop_products_${chunkBatchId}`, true);
        
        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(
          `Shop products chunk failed (attempt ${attempt}/${maxRetries}):`,
          error.message,
        );
        
        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          console.log(`🔍 Validating ${remainingChunk.length} shop products...`);
          
          const refs = remainingChunk.map(([id]) => 
            this.db.collection('shop_products').doc(id),
          );
          
          const docs = await this.db.getAll(...refs);
          
          const validItems = [];
          const invalidIds = [];
          
          remainingChunk.forEach(([productId, deltas], index) => {
            if (docs[index].exists) {
              validItems.push([productId, deltas]);
            } else {
              invalidIds.push(productId);
            }
          });
          
          if (invalidIds.length > 0) {
            console.warn(`⚠️ Skipping ${invalidIds.length} deleted/missing shop products: ${invalidIds.slice(0, 5).join(', ')}`);
            remainingChunk = validItems;
            
            if (validItems.length === 0) {
              return {success: 0, failed: []};
            }
            
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }
        
        if (attempt >= maxRetries) {
          return {
            success: 0,
            failed: remainingChunk.map(([id]) => id),
          };
        }
        
        const backoffMs = Math.min(Math.pow(2, attempt - 1) * 1000, 10000);
        await this.sleep(backoffMs);
      }
    }
  
    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  async updateShopsWithRetry(shopDeltas, batchId, maxRetries = 3) {
    if (shopDeltas.size === 0) {
      console.log('✅ No shops to update');
      return {success: 0, failed: []};
    }

    const entries = Array.from(shopDeltas.entries());
    const chunks = this.chunkArray(entries, 450);
    
    let success = 0;
    const failed = [];

    for (const [index, chunk] of chunks.entries()) {
      const chunkBatchId = `${batchId}_shops_${index}`;
      
      if (await this.isBatchProcessed(chunkBatchId, 'shops')) {
        console.log(`⏭️ Shop chunk ${chunkBatchId} already processed, skipping`);
        success += chunk.length;
        continue;
      }

      const result = await this.processShopChunkWithRetry(
        chunk,
        maxRetries,
        chunkBatchId,
      );
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
  
        for (const [shopId, deltas] of remainingChunk) {
          const ref = this.db.collection('shops').doc(shopId);
          
          const updateData = {
            'metrics.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
          };

          // ✅ Only lifetime additions (never decrement)
          if (deltas.cartAdditions > 0) {
            updateData['metrics.totalCartAdditions'] = 
              admin.firestore.FieldValue.increment(deltas.cartAdditions);
          }

          if (deltas.favAdditions > 0) {
            updateData['metrics.totalFavoriteAdditions'] = 
              admin.firestore.FieldValue.increment(deltas.favAdditions);
          }

          batch.update(ref, updateData);
        }

        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`shops_${chunkBatchId}`);
        
        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'shops',
        });
  
        await batch.commit();

        await this.ensureNonNegativeCounts('shops', remainingChunk.map(([id]) => id));
        
        this.processedBatchCache.set(`shops_${chunkBatchId}`, true);
        
        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(
          `Shop chunk failed (attempt ${attempt}/${maxRetries}):`,
          error.message,
        );
        
        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          console.log(`🔍 Validating ${remainingChunk.length} shops...`);
          
          const refs = remainingChunk.map(([id]) => 
            this.db.collection('shops').doc(id),
          );
          
          const docs = await this.db.getAll(...refs);
          
          const validItems = [];
          const invalidIds = [];
          
          remainingChunk.forEach(([shopId, deltas], index) => {
            if (docs[index].exists) {
              validItems.push([shopId, deltas]);
            } else {
              invalidIds.push(shopId);
            }
          });
          
          if (invalidIds.length > 0) {
            console.warn(`⚠️ Skipping ${invalidIds.length} missing shops: ${invalidIds.slice(0, 5).join(', ')}`);
            remainingChunk = validItems;
            
            if (validItems.length === 0) {
              return {success: 0, failed: []};
            }
            
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }
        
        if (attempt >= maxRetries) {
          return {
            success: 0,
            failed: remainingChunk.map(([id]) => id),
          };
        }
        
        const backoffMs = Math.min(Math.pow(2, attempt - 1) * 1000, 10000);
        await this.sleep(backoffMs);
      }
    }
  
    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  async isBatchProcessed(batchId, collection) {
    const cacheKey = `${collection}_${batchId}`;
    if (this.processedBatchCache.has(cacheKey)) {
      return true;
    }

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

  async cleanupProcessedBatches() {
    const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    );

    // Cleanup event queue
    const oldEventBatches = await this.db
      .collection('_event_queue')
      .where('lastUpdated', '<', sevenDaysAgo)
      .limit(500)
      .get();

    if (!oldEventBatches.empty) {
      console.log(`🧹 Cleaning up ${oldEventBatches.size} old event queue docs`);
      const chunks = this.chunkArray(oldEventBatches.docs, 500);
      for (const chunk of chunks) {
        const batch = this.db.batch();
        chunk.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
      }
    }

    // Cleanup processed batch tracking
    const oldProcessedBatches = await this.db
      .collection('_processed_batches')
      .where('processedAt', '<', sevenDaysAgo)
      .limit(500)
      .get();

    if (!oldProcessedBatches.empty) {
      console.log(`🧹 Cleaning up ${oldProcessedBatches.size} old processed batch records`);
      const chunks = this.chunkArray(oldProcessedBatches.docs, 500);
      for (const chunk of chunks) {
        const batch = this.db.batch();
        chunk.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
      }
    }
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
}

export {CartFavBatchProcessor};
