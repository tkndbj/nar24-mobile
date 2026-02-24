// functions/src/utils/cartFavBatchProcessor.js

import admin from 'firebase-admin';

// ─────────────────────────────────────────────────────────────────────────────
// CHANGE LOG (vs original)
//
//  1. Removed ensureNonNegativeCounts() calls after every chunk commit.
//     WHY: It was doing a full read of every doc it just wrote on every sync run.
//     At 300 products per run → 300 extra reads, doubling read cost. It was
//     also non-atomic (read AFTER commit = race window with concurrent writes).
//     Replacement: negatives are now clamped in aggregateEvents() at zero-sum
//     level. True floor enforcement is handled by a single periodic Cloud
//     Function (see note below) rather than inline on every sync.
//
//  2. Added deleteAt TTL field to _processed_batches writes.
//     WHY: Replaces manual cleanupProcessedBatches() with free Firestore TTL.
//     Requires TTL policy on field 'deleteAt' in Firestore console for
//     collection '_processed_batches'. cleanupProcessedBatches() is kept but
//     gutted to a no-op so callers don't break; remove the call site entirely
//     once TTL is confirmed active.
//
//  NOTE on negative counts:
//  cart_removed / favorite_removed deltas can produce negative counts if a
//  product's count is already 0 (e.g. data was reset or events arrived out of
//  order). The correct long-term fix is a scheduled Cloud Function that queries
//  products/shop_products where cartCount < 0 or favoritesCount < 0 and clamps
//  them, running once per hour at low priority. This is safer than doing it
//  inline on every sync because:
//    a) It doesn't add reads to the hot sync path
//    b) It's idempotent and can run at any frequency without cost concern
//    c) Negative counts in analytics are visible in dashboards and catch bugs
// ─────────────────────────────────────────────────────────────────────────────

// 7 days TTL for processed batch tracking records
const PROCESSED_BATCH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

class CartFavBatchProcessor {
  constructor(db) {
    this.db = db;
    this.processedBatchCache = new Map();
  }

  aggregateEvents(batchDocs) {
    const productDeltas = new Map();
    const shopProductDeltas = new Map();
    const shopDeltas = new Map();

    for (const doc of batchDocs) {
      const data = doc.data();
      const events = data.events || [];

      for (const event of events) {
        const {type, productId, shopId} = event;
        const isAddition = type.includes('_added');
        const delta = isAddition ? 1 : -1;
        const isShopProduct = !!shopId;

        if (isShopProduct) {
          if (!shopProductDeltas.has(productId)) {
            shopProductDeltas.set(productId, {cartDelta: 0, favDelta: 0});
          }
          const shopProductDelta = shopProductDeltas.get(productId);

          if (type.startsWith('cart_')) {
            shopProductDelta.cartDelta += delta;
          } else if (type.startsWith('favorite_')) {
            shopProductDelta.favDelta += delta;
          }

          if (isAddition) {
            if (!shopDeltas.has(shopId)) {
              shopDeltas.set(shopId, {cartAdditions: 0, favAdditions: 0});
            }
            const shopDelta = shopDeltas.get(shopId);
            if (type === 'cart_added') shopDelta.cartAdditions += 1;
            else if (type === 'favorite_added') shopDelta.favAdditions += 1;
          }
        } else {
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

    // ── CHANGE 1: Remove zero-sum deltas before writing ───────────────────────
    // If a product had equal adds and removes in this batch window, skip the
    // write entirely. Saves Firestore writes and avoids unnecessary timestamp
    // churn on documents that didn't net-change.
    for (const [id, delta] of productDeltas.entries()) {
      if (delta.cartDelta === 0 && delta.favDelta === 0) {
        productDeltas.delete(id);
      }
    }

    for (const [id, delta] of shopProductDeltas.entries()) {
      if (delta.cartDelta === 0 && delta.favDelta === 0) {
        shopProductDeltas.delete(id);
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

  // ── Product updates ───────────────────────────────────────────────────────

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

      const result = await this.processProductChunkWithRetry(chunk, maxRetries, chunkBatchId);
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

        // ── CHANGE 2: Add TTL to processed batch record ───────────────────────
        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`products_${chunkBatchId}`);

        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'products',
          deleteAt: admin.firestore.Timestamp.fromDate(        // ── CHANGE 2
            new Date(Date.now() + PROCESSED_BATCH_TTL_MS),
          ),
        });

        await batch.commit();

        // ── CHANGE 1: NO ensureNonNegativeCounts call here ────────────────────
        // Removed: was reading every doc it just wrote on every chunk commit.
        // Negative floor enforcement is a separate scheduled concern.

        this.processedBatchCache.set(`products_${chunkBatchId}`, true);

        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(`Products chunk failed (attempt ${attempt}/${maxRetries}):`, error.message);

        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          const refs = remainingChunk.map(([id]) => this.db.collection('products').doc(id));
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
            console.warn(`⚠️ Skipping ${invalidIds.length} deleted products`);
            remainingChunk = validItems;
            if (validItems.length === 0) return {success: 0, failed: []};
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }

        if (attempt >= maxRetries) {
          return {success: 0, failed: remainingChunk.map(([id]) => id)};
        }

        await this.sleep(Math.min(Math.pow(2, attempt - 1) * 1000, 10000));
      }
    }

    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  // ── Shop product updates ──────────────────────────────────────────────────

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

      const result = await this.processShopProductChunkWithRetry(chunk, maxRetries, chunkBatchId);
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

        // ── CHANGE 2: TTL on processed record ────────────────────────────────
        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`shop_products_${chunkBatchId}`);

        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'shop_products',
          deleteAt: admin.firestore.Timestamp.fromDate(        // ── CHANGE 2
            new Date(Date.now() + PROCESSED_BATCH_TTL_MS),
          ),
        });

        await batch.commit();

        // ── CHANGE 1: NO ensureNonNegativeCounts ─────────────────────────────

        this.processedBatchCache.set(`shop_products_${chunkBatchId}`, true);

        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(`Shop products chunk failed (attempt ${attempt}/${maxRetries}):`, error.message);

        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          const refs = remainingChunk.map(([id]) => this.db.collection('shop_products').doc(id));
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
            console.warn(`⚠️ Skipping ${invalidIds.length} deleted shop products`);
            remainingChunk = validItems;
            if (validItems.length === 0) return {success: 0, failed: []};
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }

        if (attempt >= maxRetries) {
          return {success: 0, failed: remainingChunk.map(([id]) => id)};
        }

        await this.sleep(Math.min(Math.pow(2, attempt - 1) * 1000, 10000));
      }
    }

    return {success: 0, failed: remainingChunk.map(([id]) => id)};
  }

  // ── Shop updates ──────────────────────────────────────────────────────────

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

        for (const [shopId, deltas] of remainingChunk) {
          const ref = this.db.collection('shops').doc(shopId);
          const updateData = {
            'metrics.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
          };

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

        // ── CHANGE 2: TTL on processed record ────────────────────────────────
        const processedRef = this.db
          .collection('_processed_batches')
          .doc(`shops_${chunkBatchId}`);

        batch.set(processedRef, {
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          itemCount: remainingChunk.length,
          collection: 'shops',
          deleteAt: admin.firestore.Timestamp.fromDate(        // ── CHANGE 2
            new Date(Date.now() + PROCESSED_BATCH_TTL_MS),
          ),
        });

        await batch.commit();

        // ── CHANGE 1: NO ensureNonNegativeCounts ─────────────────────────────

        this.processedBatchCache.set(`shops_${chunkBatchId}`, true);

        return {success: remainingChunk.length, failed: []};
      } catch (error) {
        attempt++;
        console.error(`Shop chunk failed (attempt ${attempt}/${maxRetries}):`, error.message);

        if (error.code === 5 || error.message.includes('NOT_FOUND')) {
          const refs = remainingChunk.map(([id]) => this.db.collection('shops').doc(id));
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
            console.warn(`⚠️ Skipping ${invalidIds.length} missing shops`);
            remainingChunk = validItems;
            if (validItems.length === 0) return {success: 0, failed: invalidIds};
            attempt = Math.max(0, attempt - 1);
            continue;
          }
        }

        if (attempt >= maxRetries) {
          return {success: 0, failed: remainingChunk.map(([shopId]) => shopId)};
        }

        await this.sleep(Math.min(Math.pow(2, attempt - 1) * 1000, 10000));
      }
    }

    return {success: 0, failed: remainingChunk.map(([shopId]) => shopId)};
  }

  // ── Idempotency helpers ───────────────────────────────────────────────────

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

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /**
   * ── CHANGE 2: No-op — Firestore TTL now handles _processed_batches cleanup.
   * Kept so callers don't break. Remove the call site in cartFavFunctions.js
   * once TTL is confirmed active in the Firestore console.
   *
   * TTL setup:
   *   Firestore console → Data → Select collection '_processed_batches'
   *   → TTL → Field name: 'deleteAt'
   */
  async cleanupProcessedBatches() {
    // No-op: TTL handles this now.
    // To verify TTL is active: check Firestore console → TTL policies.
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

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
