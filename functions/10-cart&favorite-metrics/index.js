import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {CartFavBatchProcessor} from './utils/cartFavBatchProcessor.js';
import {DistributedRateLimiter} from './utils/rateLimiter.js';

let rateLimiterInstance;
function getRateLimiter() {
  if (!rateLimiterInstance) {
    rateLimiterInstance = new DistributedRateLimiter();
  }
  return rateLimiterInstance;
}

function getQueueShard(timestamp = Date.now()) {
  // Rotate every 2 minutes across 10 shards
  // This gives us 20 minutes before we loop back
  const shardIndex = Math.floor(timestamp / 1000 / 120) % 10;
  return `pending_batches_${shardIndex}`;
}

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

    // ✅ Use sharded queue
    const queueDocId = getQueueShard(Date.now());
    const queueRef = admin.firestore()
      .collection('_event_queue')
      .doc(queueDocId);

    await admin.firestore().runTransaction(async (transaction) => {
      const queueDoc = await transaction.get(queueRef);
      
      // Check idempotency
      if (queueDoc.exists) {
        const batches = queueDoc.data()?.batches || {};
        if (batches[batchId]) {
          console.log(`⏭️ Batch ${batchId} already exists, skipping`);
          return;
        }
      }

      // Add batch to queue
      transaction.set(queueRef, {
        batches: {
          [batchId]: {
            userId,
            events,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: Date.now(),
          },
        },
        shardId: queueDocId,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });

    const duration = Date.now() - startTime;

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cart_fav_batch_received',
      batchId,
      userId,
      eventCount: events.length,
      queueShard: queueDocId,
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
  const processor = new CartFavBatchProcessor(admin.firestore());

  try {
    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cart_fav_sync_started',
    }));

    // ✅ Process current and previous shards (handles clock skew/delays)
    const now = Date.now();
    const currentShard = getQueueShard(now);
    const previousShard = getQueueShard(now - 120000); // 2 minutes ago

    const shardsToProcess = [currentShard];
    if (previousShard !== currentShard) {
      shardsToProcess.push(previousShard);
    }

    console.log(`📦 Checking shards: ${shardsToProcess.join(', ')}`);

    const allBatchEntries = [];
    const shardRefs = [];

    // Read all relevant shards
    for (const shardId of shardsToProcess) {
      const queueRef = admin.firestore()
        .collection('_event_queue')
        .doc(shardId);

      const queueDoc = await queueRef.get();

      if (queueDoc.exists && queueDoc.data()?.batches) {
        const batches = queueDoc.data().batches;
        const batchEntries = Object.entries(batches);
        
        if (batchEntries.length > 0) {
          allBatchEntries.push(...batchEntries);
          shardRefs.push({ref: queueRef, batchIds: batchEntries.map(([id]) => id)});
        }
      }
    }

    if (allBatchEntries.length === 0) {
      console.log('✅ No pending batches found');
      await getRateLimiter().cleanup();
      return {success: true, message: 'No batches to process'};
    }

    console.log(`📦 Processing ${allBatchEntries.length} batches from ${shardRefs.length} shards`);

    // Convert to format expected by processor
    const batchDocs = allBatchEntries.map(([batchId, batchData]) => ({
      id: batchId,
      data: () => batchData,
    }));

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

    // ✅ Remove processed batches from all shards
    for (const {ref, batchIds} of shardRefs) {
      await admin.firestore().runTransaction(async (transaction) => {
        const currentQueue = await transaction.get(ref);
        
        if (!currentQueue.exists) return;

        const currentBatches = currentQueue.data()?.batches || {};
        
        // Remove processed batches
        for (const batchId of batchIds) {
          delete currentBatches[batchId];
        }

        // If empty, delete the shard document
        if (Object.keys(currentBatches).length === 0) {
          transaction.delete(ref);
        } else {
          transaction.set(ref, {
            batches: currentBatches,
            lastProcessed: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      });
    }

    console.log(`✅ Removed ${allBatchEntries.length} processed batches from ${shardRefs.length} shards`);

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
    await getRateLimiter().cleanup();

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
      batchesProcessed: allBatchEntries.length,
      shardsProcessed: shardRefs.length,
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
