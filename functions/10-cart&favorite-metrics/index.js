import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {CartFavBatchProcessor} from './utils/cartFavBatchProcessor.js';
import {DistributedRateLimiter} from './utils/rateLimiter.js';

// ============================================================================
// CONFIGURATION
// ============================================================================

const NUM_SUB_SHARDS = 10;
const MAX_BATCHES_PER_RUN = 500;
const QUEUE_COLLECTION = '_cart_fav_queue';

// ============================================================================
// SHARD HELPERS
// ============================================================================

function getCurrentShardId() {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  const hour = now.getUTCHours() < 12 ? '00h' : '12h';
  return `${year}-${month}-${day}_${hour}`;
}

function getShardIdForDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  const hour = date.getUTCHours() < 12 ? '00h' : '12h';
  return `${year}-${month}-${day}_${hour}`;
}

function hashCode(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash);
}

function getSubShardIndex(userId) {
  return hashCode(userId) % NUM_SUB_SHARDS;
}

function chunkArray(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

// ============================================================================
// RATE LIMITER SINGLETON
// ============================================================================

let rateLimiterInstance;
function getRateLimiter() {
  if (!rateLimiterInstance) {
    rateLimiterInstance = new DistributedRateLimiter();
  }
  return rateLimiterInstance;
}

// ============================================================================
// BATCH CART/FAVORITE EVENTS
//
// ✅ SCALE FIX: Replaced single-doc transaction with sub-sharded subcollections
//    Old: All concurrent users write to same _event_queue doc via transaction
//         → contention at ~1 write/sec/doc → fails at 100K MAU
//    New: Users hash to 1 of 10 sub-shards, each batch is its own subcollection doc
//         → 10x write throughput, no transactions needed
// ============================================================================

export const batchCartFavoriteEvents = onCall({
  timeoutSeconds: 30,
  memory: '256MiB',
  region: 'europe-west3',
  maxInstances: 50,
  concurrency: 80,
  cors: true,
},
async (request) => {
  const startTime = Date.now();

  try {
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError('unauthenticated', 'Authentication required');
    }

    // Rate limiting
    const rateLimiter = getRateLimiter();
    const canProceed = await rateLimiter.consume(userId, 20, 60000);

    if (!canProceed) {
      throw new HttpsError(
        'resource-exhausted',
        'Rate limit exceeded. Maximum 20 requests per minute.',
      );
    }

    const data = request.data;

    if (!data || typeof data !== 'object') {
      throw new HttpsError('invalid-argument', 'Invalid request data');
    }

    const {
      batchId,
      events = [],
    } = data;

    // Validate batch ID
    if (!batchId || typeof batchId !== 'string') {
      throw new HttpsError('invalid-argument', 'Missing or invalid batchId');
    }

    // Validate events array
    if (!Array.isArray(events) || events.length === 0) {
      throw new HttpsError('invalid-argument', 'Events array is required');
    }

    if (events.length > 100) {
      throw new HttpsError(
        'invalid-argument',
        'Maximum 100 events per batch',
      );
    }

    // Validate each event
    const VALID_TYPES = [
      'cart_added',
      'cart_removed',
      'favorite_added',
      'favorite_removed',
    ];

    for (const event of events) {
      if (!VALID_TYPES.includes(event.type)) {
        throw new HttpsError(
          'invalid-argument',
          `Invalid event type: ${event.type}`,
        );
      }

      if (!event.productId || typeof event.productId !== 'string') {
        throw new HttpsError(
          'invalid-argument',
          'Each event must have a valid productId',
        );
      }

      if (event.shopId && typeof event.shopId !== 'string') {
        throw new HttpsError(
          'invalid-argument',
          'shopId must be a string if provided',
        );
      }
    }

    // ✅ Sub-sharded write — no transaction needed
    const db = admin.firestore();
    const shardId = getCurrentShardId();
    const subShard = getSubShardIndex(userId);
    const fullShardId = `${shardId}_sub${subShard}`;

    // Idempotency check (simple get, not a transaction)
    const existingBatch = await db
      .collection(QUEUE_COLLECTION)
      .doc(fullShardId)
      .collection('batches')
      .doc(batchId)
      .get();

    if (existingBatch.exists) {
      console.log(`⏭️ Batch ${batchId} already exists, skipping`);
      return {
        success: true,
        processed: 0,
        batchId,
        message: 'Batch already processed (idempotent)',
      };
    }

    // Write batch as its own subcollection doc
    await db
      .collection(QUEUE_COLLECTION)
      .doc(fullShardId)
      .collection('batches')
      .doc(batchId)
      .set({
        userId,
        events,
        processed: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: Date.now(),
      });

    // Track pending count for early exit optimization
    await db
      .collection(QUEUE_COLLECTION)
      .doc(`${shardId}_metadata`)
      .set({
        pendingCount: admin.firestore.FieldValue.increment(1),
        lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

    const duration = Date.now() - startTime;

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cart_fav_batch_received',
      batchId,
      userId,
      eventCount: events.length,
      shard: fullShardId,
      duration,
    }));

    return {
      success: true,
      processed: events.length,
      batchId,
      duration,
    };
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'cart_fav_batch_failed',
      error: error.message,
      code: error.code,
      userId: request.auth?.uid || 'unknown',
    }));

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError('internal', 'Failed to process events');
  }
});

// ============================================================================
// SYNC CART/FAVORITE METRICS
//
// ✅ SCALE FIX: Queries all sub-shards in parallel with metadata early exit
//    Mirrors proven click analytics pattern
// ============================================================================

export const syncCartFavoriteMetrics = onSchedule({
  schedule: 'every 2 minutes',
  timeZone: 'UTC',
  timeoutSeconds: 120,
  memory: '512MiB',
  region: 'europe-west3',
  maxInstances: 3,
},
async () => {
  const startTime = Date.now();
  const db = admin.firestore();
  const processor = new CartFavBatchProcessor(db);

  try {
    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cart_fav_sync_started',
    }));

    // ✅ Check current and previous shards (handles 12h boundary crossing)
    const now = new Date();
    const currentShardId = getCurrentShardId();
    const previousShardId = getShardIdForDate(
      new Date(now.getTime() - 12 * 60 * 60 * 1000),
    );

    const shardsToCheck = [currentShardId];
    if (previousShardId !== currentShardId) {
      shardsToCheck.push(previousShardId);
    }

    // ✅ Metadata check for early exit (avoids querying all sub-shards)
    let hasPending = false;
    for (const shardId of shardsToCheck) {
      const metadataDoc = await db
        .collection(QUEUE_COLLECTION)
        .doc(`${shardId}_metadata`)
        .get();

      if (metadataDoc.exists && (metadataDoc.data()?.pendingCount ?? 0) > 0) {
        hasPending = true;
        break;
      }
    }

    if (!hasPending) {
      console.log('⏭️ No pending batches (metadata check), skipping');

      await Promise.all([
        cleanupOldShards(db),
        processor.cleanupProcessedBatches(),
        getRateLimiter().cleanup(),
      ]);

      return {success: true, message: 'No batches to process'};
    }

    // ✅ Query all sub-shards across relevant time shards in parallel
    const allDocs = [];

    for (const shardId of shardsToCheck) {
      const subShardPromises = [];

      for (let i = 0; i < NUM_SUB_SHARDS; i++) {
        const fullShardId = `${shardId}_sub${i}`;

        subShardPromises.push(
          db.collection(QUEUE_COLLECTION)
            .doc(fullShardId)
            .collection('batches')
            .where('processed', '==', false)
            .orderBy('timestamp', 'asc')
            .limit(Math.ceil(MAX_BATCHES_PER_RUN / NUM_SUB_SHARDS))
            .get(),
        );
      }

      const snapshots = await Promise.all(subShardPromises);

      for (const snapshot of snapshots) {
        allDocs.push(...snapshot.docs);
      }
    }

    if (allDocs.length === 0) {
      console.log('✅ No unprocessed batches found');

      await Promise.all([
        cleanupOldShards(db),
        processor.cleanupProcessedBatches(),
        getRateLimiter().cleanup(),
      ]);

      return {success: true, message: 'No batches to process'};
    }

    // Sort by timestamp and cap at limit
    allDocs.sort((a, b) => {
      const aTime = a.data().timestamp?.toMillis() || 0;
      const bTime = b.data().timestamp?.toMillis() || 0;
      return aTime - bTime;
    });

    const batchDocs = allDocs.slice(0, MAX_BATCHES_PER_RUN);

    console.log(`📦 Processing ${batchDocs.length} batches`);

    // Aggregate events
    const aggregated = processor.aggregateEvents(batchDocs);

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'events_aggregated',
      products: aggregated.productDeltas.size,
      shopProducts: aggregated.shopProductDeltas.size,
      shops: aggregated.shopDeltas.size,
    }));

    const syncBatchId = `sync_${Date.now()}`;

    // Process in parallel
    const [productResult, shopProductResult, shopResult] = await Promise.all([
      processor.updateProductsWithRetry(
        aggregated.productDeltas,
        syncBatchId,
      ),
      processor.updateShopProductsWithRetry(
        aggregated.shopProductDeltas,
        syncBatchId,
      ),
      processor.updateShopsWithRetry(
        aggregated.shopDeltas,
        syncBatchId,
      ),
    ]);

    console.log(`✅ Products: ${productResult.success} success, ${productResult.failed.length} failed`);
    console.log(`✅ Shop Products: ${shopProductResult.success} success, ${shopProductResult.failed.length} failed`);
    console.log(`✅ Shops: ${shopResult.success} success, ${shopResult.failed.length} failed`);

    // ✅ Mark batches as processed and decrement metadata
    await markBatchesProcessed(db, batchDocs);

    console.log(`✅ Marked ${batchDocs.length} batches as processed`);

    // Log failures
    if (productResult.failed.length > 0 ||
        shopProductResult.failed.length > 0 ||
        shopResult.failed.length > 0) {
      console.warn(JSON.stringify({
        level: 'WARN',
        event: 'partial_failure',
        productsFailed: productResult.failed.slice(0, 10),
        shopProductsFailed: shopProductResult.failed.slice(0, 10),
        shopsFailed: shopResult.failed.slice(0, 10),
      }));
    }

    // Cleanup
    await Promise.all([
      cleanupOldShards(db),
      processor.cleanupProcessedBatches(),
      getRateLimiter().cleanup(),
    ]);

    const duration = Date.now() - startTime;
    const totalUpdates =
      productResult.success +
      shopProductResult.success +
      shopResult.success;
    const totalFailed =
      productResult.failed.length +
      shopProductResult.failed.length +
      shopResult.failed.length;
    const failureRate = totalUpdates > 0 ?
      (totalFailed / (totalUpdates + totalFailed)) * 100 :
      0;

    const metrics = {
      batchesProcessed: batchDocs.length,
      productsUpdated: productResult.success,
      shopProductsUpdated: shopProductResult.success,
      shopsUpdated: shopResult.success,
      failureRate: failureRate.toFixed(2) + '%',
      duration,
    };

    // Alerts
    if (failureRate > 5) {
      console.error(JSON.stringify({
        level: 'ERROR',
        event: 'high_failure_rate',
        failureRate: failureRate.toFixed(2) + '%',
        alert: true,
        ...metrics,
      }));
    }

    if (duration > 100000) {
      console.error(JSON.stringify({
        level: 'ERROR',
        event: 'approaching_timeout',
        duration,
        alert: true,
        ...metrics,
      }));
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cart_fav_sync_completed',
      metrics,
    }));

    return {
      success: true,
      ...metrics,
      failed: {
        products: productResult.failed.length,
        shopProducts: shopProductResult.failed.length,
        shops: shopResult.failed.length,
      },
    };
  } catch (error) {
    const duration = Date.now() - startTime;

    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'cart_fav_sync_failed',
      error: error.message,
      stack: error.stack,
      duration,
      alert: true,
    }));

    return {
      success: false,
      error: error.message,
      duration,
    };
  }
});

// ============================================================================
// QUEUE MANAGEMENT HELPERS
// ============================================================================

async function markBatchesProcessed(db, batchDocs) {
  if (batchDocs.length === 0) return;

  // Group batches by their sub-shard (from document reference path)
  const batchesBySubShard = new Map();

  for (const doc of batchDocs) {
    const subShardId = doc.ref.parent.parent.id;

    if (!batchesBySubShard.has(subShardId)) {
      batchesBySubShard.set(subShardId, []);
    }
    batchesBySubShard.get(subShardId).push(doc.id);
  }

  console.log(
    `Marking ${batchDocs.length} batches across ${batchesBySubShard.size} sub-shards`,
  );

  // Update each sub-shard in parallel
  const updatePromises = [];

  for (const [subShardId, batchIds] of batchesBySubShard.entries()) {
    const chunks = chunkArray(batchIds, 500);

    for (const chunk of chunks) {
      const promise = (async () => {
        const batch = db.batch();

        for (const batchId of chunk) {
          const ref = db
            .collection(QUEUE_COLLECTION)
            .doc(subShardId)
            .collection('batches')
            .doc(batchId);

          batch.update(ref, {
            processed: true,
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      })();

      updatePromises.push(promise);
    }
  }

  const results = await Promise.allSettled(updatePromises);

  const failures = results.filter((r) => r.status === 'rejected');
  if (failures.length > 0) {
    console.error(
      `Failed to mark ${failures.length} batch chunks:`,
      failures.map((f) => f.reason),
    );
  }

  // Decrement metadata pending count per shard
  const batchCountPerShard = new Map();

  for (const doc of batchDocs) {
    const subShardId = doc.ref.parent.parent.id;
    const shardId = subShardId.split('_sub')[0];
    batchCountPerShard.set(
      shardId,
      (batchCountPerShard.get(shardId) || 0) + 1,
    );
  }

  for (const [shardId, count] of batchCountPerShard.entries()) {
    await db
      .collection(QUEUE_COLLECTION)
      .doc(`${shardId}_metadata`)
      .update({
        pendingCount: admin.firestore.FieldValue.increment(-count),
      })
      .catch(() => {
        // Ignore if metadata doesn't exist
      });
  }
}

async function cleanupOldShards(db) {
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const cutoffShardId = getShardIdForDate(sevenDaysAgo);

  const snapshot = await db
    .collection(QUEUE_COLLECTION)
    .where(admin.firestore.FieldPath.documentId(), '<', cutoffShardId)
    .limit(100)
    .get();

  if (snapshot.empty) return;

  console.log(`🧹 Cleaning up ${snapshot.size} old cart/fav queue documents`);

  let deletedCount = 0;

  const deletePromises = snapshot.docs.map(async (doc) => {
    try {
      let hasMore = true;
      let totalBatchesDeleted = 0;

      while (hasMore) {
        const batchesSnapshot = await doc.ref
          .collection('batches')
          .limit(500)
          .get();

        if (batchesSnapshot.empty) {
          hasMore = false;
          break;
        }

        const chunks = chunkArray(batchesSnapshot.docs, 500);
        await Promise.all(chunks.map(async (chunk) => {
          const batch = db.batch();
          chunk.forEach((batchDoc) => batch.delete(batchDoc.ref));
          await batch.commit();
          totalBatchesDeleted += chunk.length;
        }));
      }

      await doc.ref.delete();
      deletedCount++;

      console.log(
        `✅ Deleted cart/fav shard: ${doc.id} (${totalBatchesDeleted} batches)`,
      );
    } catch (error) {
      console.error(
        `❌ Error deleting cart/fav shard ${doc.id}: ${error.message}`,
      );
    }
  });

  await Promise.allSettled(deletePromises);

  console.log(JSON.stringify({
    level: 'INFO',
    event: 'cart_fav_shard_cleanup_completed',
    deleted: deletedCount,
  }));
}
