// functions/test/click-analytics/click-analytics-utils.js
//
// EXTRACTED PURE LOGIC from click analytics cloud functions
// These functions are EXACT COPIES of logic from the click analytics functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source click analytics functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const MAX_CLICKS_PER_ITEM = 100;
const MAX_ITEMS = 1000;
const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024; // 5MB
const MAX_BATCHES_PER_RUN = 100;
const MAX_RETRY_COUNT = 5;
const CHUNK_SIZE = 450; // Stay under Firestore's 500 limit
const SUB_SHARD_COUNT = 10;
const CLEANUP_DAYS = 7;
const RATE_LIMIT_MAX_ENTRIES = 100000;


// ============================================================================
// SHARD HELPER - ID GENERATION
// ============================================================================

function getCurrentShardId(now = new Date()) {
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

function generateBatchId(timestamp = Date.now()) {
  const random = Math.random().toString(36).substr(2, 9);
  return `batch_${timestamp}_${random}`;
}

function parseShardId(shardId) {
  if (!shardId || typeof shardId !== 'string') return null;

  const match = shardId.match(/^(\d{4})-(\d{2})-(\d{2})_(00h|12h)$/);
  if (!match) return null;

  return {
    year: parseInt(match[1], 10),
    month: parseInt(match[2], 10),
    day: parseInt(match[3], 10),
    hour: match[4] === '00h' ? 0 : 12,
  };
}

// ============================================================================
// SHARD HELPER - HASHING
// ============================================================================

function hashCode(str) {
  if (!str || typeof str !== 'string') return 0;

  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0; // Convert to 32-bit integer
  }
  return Math.abs(hash);
}

function getSubShardIndex(userId, subShardCount = SUB_SHARD_COUNT) {
  if (!userId) return Math.floor(Math.random() * subShardCount);
  return hashCode(userId) % subShardCount;
}

function getFullShardId(shardId, subShardIndex) {
  return `${shardId}_sub${subShardIndex}`;
}

// ============================================================================
// VALIDATION
// ============================================================================

function validateBatchId(batchId) {
  if (!batchId) {
    return { isValid: false, reason: 'missing', message: 'Missing or invalid batchId' };
  }

  if (typeof batchId !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Missing or invalid batchId' };
  }

  return { isValid: true };
}

function validateClicks(clicks, type) {
  const errors = [];

  if (!clicks || typeof clicks !== 'object') {
    return { isValid: true, entries: [] }; // Empty is valid
  }

  const entries = Object.entries(clicks);

  if (entries.length > MAX_ITEMS) {
    return {
      isValid: false,
      reason: 'too_many_items',
      message: `Too many ${type} items. Maximum ${MAX_ITEMS}.`,
    };
  }

  for (const [id, count] of entries) {
    if (!id || typeof id !== 'string') {
      errors.push({ id, reason: 'invalid_id', message: `Invalid ${type} ID` });
      continue;
    }

    if (typeof count !== 'number' || count < 1 || count > MAX_CLICKS_PER_ITEM) {
      errors.push({
        id,
        reason: 'invalid_count',
        message: `Invalid ${type} count for ${id}: ${count}`,
      });
    }
  }

  if (errors.length > 0) {
    return { isValid: false, errors, firstError: errors[0] };
  }

  return { isValid: true, entries };
}

function validatePayloadSize(data) {
  const payloadSize = JSON.stringify(data).length;

  if (payloadSize > MAX_PAYLOAD_SIZE) {
    return {
      isValid: false,
      reason: 'too_large',
      message: `Payload too large: ${(payloadSize / 1024 / 1024).toFixed(2)}MB. Max: 5MB`,
      size: payloadSize,
    };
  }

  return { isValid: true, size: payloadSize };
}

function countTotalClicks(productClicks, shopProductClicks, shopClicks) {
  return (
    Object.keys(productClicks || {}).length +
    Object.keys(shopProductClicks || {}).length +
    Object.keys(shopClicks || {}).length
  );
}

// ============================================================================
// BATCH AGGREGATION
// ============================================================================

function aggregateClicks(batchDocs) {
  const productClicks = new Map();
  const shopProductClicks = new Map();
  const shopClicks = new Map();

  for (const doc of batchDocs) {
    const data = typeof doc.data === 'function' ? doc.data() : doc;

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

  return { productClicks, shopProductClicks, shopClicks };
}

function extractShopIds(batchDocs) {
  const shopIds = new Map();

  for (const doc of batchDocs) {
    const data = typeof doc.data === 'function' ? doc.data() : doc;

    if (data.shopIds) {
      Object.entries(data.shopIds).forEach(([productId, shopId]) => {
        shopIds.set(productId, shopId);
      });
    }
  }

  return shopIds;
}

function aggregateShopProductViews(shopProductClicks, shopIds) {
  const shopProductViews = new Map();

  for (const [productId, count] of shopProductClicks.entries()) {
    const shopId = shopIds.get(productId);
    if (shopId) {
      shopProductViews.set(shopId, (shopProductViews.get(shopId) || 0) + count);
    }
  }

  return shopProductViews;
}

// ============================================================================
// CHUNKING
// ============================================================================

function chunkArray(array, size = CHUNK_SIZE) {
  if (!Array.isArray(array)) return [];
  if (size <= 0) return [array];

  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

function calculateChunkCount(totalItems, chunkSize = CHUNK_SIZE) {
  if (totalItems <= 0) return 0;
  return Math.ceil(totalItems / chunkSize);
}

// ============================================================================
// RETRY LOGIC
// ============================================================================

function isStuckBatch(retryCount, maxRetries = MAX_RETRY_COUNT) {
  return (retryCount || 0) >= maxRetries;
}

function getExponentialBackoff(attempt, baseMs = 1000, maxMs = 10000) {
  const backoff = Math.min(Math.pow(2, attempt - 1) * baseMs, maxMs);
  return backoff;
}

function shouldRetryError(errorCode, errorMessage) {
  // Don't retry permission errors
  if (errorCode === 7) return false; // PERMISSION_DENIED

  // Retry NOT_FOUND (might be transient)
  if (errorCode === 5) return true;
  if (errorMessage?.includes('NOT_FOUND')) return true;
  if (errorMessage?.includes('No document to update')) return true;

  // Retry other errors
  return true;
}

// ============================================================================
// RATE LIMITER
// ============================================================================

function createRateLimiterEntry(windowMs, now = Date.now()) {
  return {
    count: 1,
    resetAt: now + windowMs,
  };
}

function canConsumeRateLimit(entry, maxRequests, now = Date.now()) {
  // First request or window expired
  if (!entry || now > entry.resetAt) {
    return { canConsume: true, reason: 'new_window' };
  }

  // Limit exceeded
  if (entry.count >= maxRequests) {
    return { canConsume: false, reason: 'limit_exceeded' };
  }

  return { canConsume: true, reason: 'under_limit' };
}

function isRateLimitExpired(entry, now = Date.now()) {
  if (!entry) return true;
  return now > entry.resetAt;
}

function shouldCleanupRateLimiter(size, maxSize = RATE_LIMIT_MAX_ENTRIES) {
  return size > maxSize;
}

// ============================================================================
// METRICS & MONITORING
// ============================================================================

function calculateFailureRate(failed, total) {
  if (total <= 0) return 0;
  return (failed / total) * 100;
}

function isHighFailureRate(failureRate, threshold = 5) {
  return failureRate > threshold;
}

function isApproachingTimeout(duration, timeoutMs = 540000, threshold = 480000) {
  return duration > threshold;
}

function buildSyncMetrics(batchesProcessed, productsUpdated, shopsUpdated, failed, duration, stuckBatches) {
  const total = productsUpdated + shopsUpdated + failed;
  const failureRate = calculateFailureRate(failed, total);

  return {
    batchesProcessed,
    productsUpdated,
    shopsUpdated,
    failureRate: failureRate.toFixed(2) + '%',
    duration,
    stuckBatches,
  };
}

// ============================================================================
// BATCH DATA BUILDING
// ============================================================================

function buildBatchData(productClicks, shopProductClicks, shopClicks, shopIds, userId) {
  const batchData = {
    processed: false,
    createdBy: userId || 'anonymous',
    createdAt: Date.now(),
    retryCount: 0,
  };

  if (Object.keys(productClicks || {}).length > 0) {
    batchData.productClicks = productClicks;
  }

  if (Object.keys(shopProductClicks || {}).length > 0) {
    batchData.shopProductClicks = shopProductClicks;
  }

  if (Object.keys(shopClicks || {}).length > 0) {
    batchData.shopClicks = shopClicks;
  }

  if (Object.keys(shopIds || {}).length > 0) {
    batchData.shopIds = shopIds;
  }

  return batchData;
}

function buildClickUpdateData(count) {
  return {
    clickCountIncrement: count,
  };
}

function buildShopUpdateData(productViews, directClicks) {
  const updateData = {};

  if (productViews > 0) {
    updateData.totalProductViewsIncrement = productViews;
  }

  if (directClicks > 0) {
    updateData.clickCountIncrement = directClicks;
  }

  return updateData;
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildSuccessResponse(processed, batchId, shardId, duration) {
  return {
    success: true,
    processed,
    batchId,
    shardId,
    duration,
  };
}

function buildIdempotentResponse(batchId) {
  return {
    success: true,
    processed: 0,
    batchId,
    message: 'Batch already processed (idempotent)',
  };
}

function buildNoClicksResponse() {
  return {
    success: true,
    processed: 0,
    message: 'No clicks to process',
  };
}

function buildSyncResultResponse(shardId, metrics, failed) {
  return {
    success: true,
    shardId,
    ...metrics,
    failed,
  };
}

// ============================================================================
// CLEANUP
// ============================================================================

function getCleanupCutoffDate(days = CLEANUP_DAYS, now = new Date()) {
  return new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
}

function isShardOlderThan(shardId, cutoffShardId) {
  return shardId < cutoffShardId;
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  MAX_CLICKS_PER_ITEM,
  MAX_ITEMS,
  MAX_PAYLOAD_SIZE,
  MAX_BATCHES_PER_RUN,
  MAX_RETRY_COUNT,
  CHUNK_SIZE,
  SUB_SHARD_COUNT,
  CLEANUP_DAYS,
  RATE_LIMIT_MAX_ENTRIES,

  // Shard ID generation
  getCurrentShardId,
  getShardIdForDate,
  generateBatchId,
  parseShardId,

  // Hashing
  hashCode,
  getSubShardIndex,
  getFullShardId,

  // Validation
  validateBatchId,
  validateClicks,
  validatePayloadSize,
  countTotalClicks,

  // Aggregation
  aggregateClicks,
  extractShopIds,
  aggregateShopProductViews,

  // Chunking
  chunkArray,
  calculateChunkCount,

  // Retry logic
  isStuckBatch,
  getExponentialBackoff,
  shouldRetryError,

  // Rate limiter
  createRateLimiterEntry,
  canConsumeRateLimit,
  isRateLimitExpired,
  shouldCleanupRateLimiter,

  // Metrics
  calculateFailureRate,
  isHighFailureRate,
  isApproachingTimeout,
  buildSyncMetrics,

  // Batch data
  buildBatchData,
  buildClickUpdateData,
  buildShopUpdateData,

  // Response
  buildSuccessResponse,
  buildIdempotentResponse,
  buildNoClicksResponse,
  buildSyncResultResponse,

  // Cleanup
  getCleanupCutoffDate,
  isShardOlderThan,
};
