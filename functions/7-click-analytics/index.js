import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {ShardHelper} from './utils/shardHelper.js';
import {BatchProcessor} from './utils/batchProcessor.js';
import {DistributedRateLimiter} from './utils/rateLimiter.js';


let rateLimiterInstance;
function getRateLimiter() {
  if (!rateLimiterInstance) {
    rateLimiterInstance = new DistributedRateLimiter(admin.firestore());
  }
  return rateLimiterInstance;
}

/**
 * ✅ PRODUCTION-READY: Batch click updates with idempotency
 */
export const batchUpdateClicks = onCall({
  timeoutSeconds: 60,
  memory: '512MiB',
  region: 'europe-west3',
  maxInstances: 100,
  concurrency: 80,
  cors: true,
},
async (request) => {
  const startTime = Date.now();
  
  try {
    const userId = request.auth?.uid || request.rawRequest.ip || 'anonymous';
    
    // Rate limiting
    const rateLimiter = getRateLimiter();
    const canProceed = await rateLimiter.consume(userId, 10, 60000);

    if (!canProceed) {
      throw new HttpsError(
        'resource-exhausted',
        'Rate limit exceeded. Maximum 10 requests per minute.',
      );
    }

    const data = request.data;

    if (!data || typeof data !== 'object') {
      throw new HttpsError('invalid-argument', 'Invalid click data');
    }

    const {
      batchId, // ✅ NEW: Client provides deterministic ID
      productClicks = {},
      shopProductClicks = {},
      shopClicks = {},
      shopIds = {},
    } = data;

    // ✅ NEW: Validate batch ID
    if (!batchId || typeof batchId !== 'string') {
      throw new HttpsError('invalid-argument', 'Missing or invalid batchId');
    }

    // ✅ NEW: Check if batch already processed (idempotency)
    const shardId = ShardHelper.getCurrentShardId();
    const subShard = ShardHelper.hashCode(userId) % 10;
    const fullShardId = `${shardId}_sub${subShard}`;
    
    const existingBatch = await admin.firestore()
      .collection('click_analytics')
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

    // Validate click counts
    const MAX_CLICKS_PER_ITEM = 100;
    const MAX_ITEMS = 1000;
    
    const validateClicks = (clicks, type) => {
      const entries = Object.entries(clicks);
      
      if (entries.length > MAX_ITEMS) {
        throw new HttpsError(
          'invalid-argument',
          `Too many ${type} items. Maximum ${MAX_ITEMS}.`,
        );
      }
      
      for (const [id, count] of entries) {
        if (!id || typeof id !== 'string') {
          throw new HttpsError('invalid-argument', `Invalid ${type} ID`);
        }
        
        if (typeof count !== 'number' || count < 1 || count > MAX_CLICKS_PER_ITEM) {
          throw new HttpsError(
            'invalid-argument',
            `Invalid ${type} count for ${id}: ${count}`,
          );
        }
      }
    };

    validateClicks(productClicks, 'product');
    validateClicks(shopProductClicks, 'shop_product');
    validateClicks(shopClicks, 'shop');

    const totalClicks = 
      Object.keys(productClicks).length +
      Object.keys(shopProductClicks).length +
      Object.keys(shopClicks).length;

    if (totalClicks === 0) {
      return {
        success: true,
        processed: 0,
        message: 'No clicks to process',
      };
    }

    // Payload size check
    const payloadSize = JSON.stringify(data).length;
    const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024;

    if (payloadSize > MAX_PAYLOAD_SIZE) {
      throw new HttpsError(
        'invalid-argument',
        `Payload too large: ${(payloadSize / 1024 / 1024).toFixed(2)}MB. Max: 5MB`,
      );
    }

    const batchesRef = admin.firestore()
      .collection('click_analytics')
      .doc(fullShardId)
      .collection('batches');

    const batchData = {
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      processed: false,
      createdBy: request.auth?.uid || 'anonymous',
      createdAt: Date.now(),
      retryCount: 0,
    };

    if (Object.keys(productClicks).length > 0) {
      batchData.productClicks = productClicks;
    }

    if (Object.keys(shopProductClicks).length > 0) {
      batchData.shopProductClicks = shopProductClicks;
    }

    if (Object.keys(shopClicks).length > 0) {
      batchData.shopClicks = shopClicks;
    }

    if (Object.keys(shopIds).length > 0) {
      batchData.shopIds = shopIds;
    }

    // ✅ Use client-provided batch ID
    await batchesRef.doc(batchId).set(batchData);

// ✅ NEW: Track pending count for this shard
await admin.firestore()
  .collection('click_analytics')
  .doc(`${shardId}_metadata`)
  .set({
    pendingCount: admin.firestore.FieldValue.increment(1),
    lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

const duration = Date.now() - startTime;

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'batch_clicks_received',
      batchId,
      userId: request.auth?.uid || 'anonymous',
      clickCount: totalClicks,
      payloadSizeKB: Math.round(payloadSize / 1024),
      duration,
    }));

    return {
      success: true,
      processed: totalClicks,
      batchId,
      shardId,
      duration,
    };
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'batch_clicks_failed',
      error: error.message,
      code: error.code,
      userId: request.auth?.uid || 'unknown',
    }));
    
    if (error instanceof HttpsError) {
      throw error;
    }
    
    throw new HttpsError('internal', 'Failed to process clicks');
  }
});

/**
 * ✅ OPTIMIZED: Faster sync with monitoring
 */
export const syncClickAnalytics = onSchedule({
  schedule: 'every 5 minutes',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '1GiB',
  region: 'europe-west3',
  maxInstances: 5,
},
async () => {
  const startTime = Date.now();
  const processor = new BatchProcessor(admin.firestore());

  try {
    const shardId = ShardHelper.getCurrentShardId();
    console.log(JSON.stringify({
      level: 'INFO',
      event: 'sync_started',
      shardId,
    }));

    const metadataDoc = await admin.firestore()
  .collection('click_analytics')
  .doc(`${shardId}_metadata`)
  .get();

if (!metadataDoc.exists || (metadataDoc.data()?.pendingCount ?? 0) === 0) {
  console.log('⏭️ No pending batches (metadata check), skipping sub-shard queries');
  
  await Promise.all([
    ShardHelper.cleanupOldShards(admin.firestore()),
    processor.cleanupProcessedBatches(),
    getRateLimiter().cleanup(),
  ]);
  
  return {success: true, message: 'No batches to process'};
}

const MAX_BATCHES_PER_RUN = 500;
const batchDocs = await ShardHelper.getUnprocessedBatches(
  admin.firestore(), 
  shardId, 
  MAX_BATCHES_PER_RUN,
);

    if (batchDocs.length === 0) {
      console.log('✅ No unprocessed batches found');
      
      await Promise.all([
        ShardHelper.cleanupOldShards(admin.firestore()),
        processor.cleanupProcessedBatches(),
        getRateLimiter().cleanup(),
      ]);
      
      return {success: true, message: 'No batches to process'};
    }

    console.log(`📦 Processing ${batchDocs.length} batches`);

    // Identify stuck batches
    const stuckBatches = [];
    const validBatchDocs = [];

    for (const doc of batchDocs) {
      const retryCount = doc.data().retryCount || 0;
      if (retryCount >= 5) {
        stuckBatches.push(doc);
      } else {
        validBatchDocs.push(doc);
      }
    }

    if (stuckBatches.length > 0) {
      console.error(JSON.stringify({
        level: 'ERROR',
        event: 'stuck_batches_detected',
        count: stuckBatches.length,
        alert: true, // ✅ NEW: Flag for monitoring
      }));

      await ShardHelper.markBatchesAsFailed(admin.firestore(), stuckBatches, 'Max retries exceeded');
    }

    if (validBatchDocs.length === 0) {
      console.log('⚠️ All batches are stuck');
      return {success: true, message: 'All batches stuck'};
    }

    // Aggregate clicks
    const aggregated = processor.aggregateClicks(validBatchDocs);

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'clicks_aggregated',
      products: aggregated.productClicks.size,
      shopProducts: aggregated.shopProductClicks.size,
      shops: aggregated.shopClicks.size,
    }));

    // Extract shop mappings
    const shopIds = new Map();
    for (const doc of validBatchDocs) {
      const data = doc.data();
      if (data.shopIds) {
        Object.entries(data.shopIds).forEach(([productId, shopId]) => {
          shopIds.set(productId, shopId);
        });
      }
    }

    const syncBatchId = `sync_${shardId}_${Date.now()}`;

    // Process in parallel
    const [productResult, shopResult] = await Promise.all([
      processor.updateProductsWithRetry(
        aggregated.productClicks,
        aggregated.shopProductClicks,
        syncBatchId,
      ),
      processor.updateShopsWithRetry(
        aggregated.shopProductClicks,
        aggregated.shopClicks,
        shopIds,
        syncBatchId,
      ),
    ]);

    console.log(`✅ Products: ${productResult.success} success, ${productResult.failed.length} failed`);
    console.log(`✅ Shops: ${shopResult.success} success, ${shopResult.failed.length} failed`);

    await ShardHelper.markBatchesProcessed(admin.firestore(), validBatchDocs);

    console.log(`✅ Marked ${validBatchDocs.length} batches as processed`);

    if (productResult.failed.length > 0 || shopResult.failed.length > 0) {
      console.warn(JSON.stringify({
        level: 'WARN',
        event: 'partial_failure',
        productsFailed: productResult.failed.slice(0, 10),
        shopsFailed: shopResult.failed.slice(0, 10),
      }));
    }

    await Promise.all([
      ShardHelper.cleanupOldShards(admin.firestore()),
      processor.cleanupProcessedBatches(),
      getRateLimiter().cleanup(),
    ]);

    const duration = Date.now() - startTime;
    const totalUpdates = productResult.success + shopResult.success;
    const totalFailed = productResult.failed.length + shopResult.failed.length;
    const failureRate = totalUpdates > 0 ? (totalFailed / (totalUpdates + totalFailed)) * 100 : 0;

    // ✅ NEW: Structured monitoring metrics
    const metrics = {
      batchesProcessed: validBatchDocs.length,
      productsUpdated: productResult.success,
      shopsUpdated: shopResult.success,
      failureRate: failureRate.toFixed(2) + '%',
      duration,
      stuckBatches: stuckBatches.length,
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

    if (duration > 480000) {
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
      event: 'sync_completed',
      shardId,
      metrics,
    }));

    return {
      success: true,
      shardId,
      ...metrics,
      failed: {
        products: productResult.failed.length,
        shops: shopResult.failed.length,
      },
    };
  } catch (error) {
    const duration = Date.now() - startTime;
    
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'sync_failed',
      error: error.message,
      stack: error.stack,
      duration,
      alert: true, // ✅ NEW: Alert on total failure
    }));
    
    return {
      success: false,
      error: error.message,
      duration,
    };
  }
});
