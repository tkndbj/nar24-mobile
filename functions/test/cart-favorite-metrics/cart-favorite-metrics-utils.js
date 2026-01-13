// functions/test/cart-favorite-metrics/cart-favorite-metrics-utils.js
//
// EXTRACTED PURE LOGIC from cart & favorite metrics cloud functions
// These functions are EXACT COPIES of logic from the cart/fav metrics functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const VALID_EVENT_TYPES = [
    'cart_added',
    'cart_removed',
    'favorite_added',
    'favorite_removed',
  ];
  
  const MAX_EVENTS_PER_BATCH = 100;
  const SHARD_COUNT = 10;
  const SHARD_ROTATION_SECONDS = 120; // 2 minutes
  const RATE_LIMIT_MAX_REQUESTS = 20;
  const RATE_LIMIT_WINDOW_MS = 60000;
  const CHUNK_SIZE = 450;
  const MAX_RETRIES = 3;
  const CLEANUP_DAYS = 7;
  
  // ============================================================================
  // SHARD HELPERS
  // ============================================================================
  
  function getQueueShard(timestamp = Date.now()) {
    // Rotate every 2 minutes across 10 shards
    const shardIndex = Math.floor(timestamp / 1000 / SHARD_ROTATION_SECONDS) % SHARD_COUNT;
    return `pending_batches_${shardIndex}`;
  }
  
  function getShardIndex(timestamp = Date.now()) {
    return Math.floor(timestamp / 1000 / SHARD_ROTATION_SECONDS) % SHARD_COUNT;
  }
  
  function getPreviousShard(timestamp = Date.now()) {
    const previousTimestamp = timestamp - (SHARD_ROTATION_SECONDS * 1000);
    return getQueueShard(previousTimestamp);
  }
  
  function getShardsToProcess(timestamp = Date.now()) {
    const currentShard = getQueueShard(timestamp);
    const previousShard = getPreviousShard(timestamp);
  
    const shards = [currentShard];
    if (previousShard !== currentShard) {
      shards.push(previousShard);
    }
  
    return shards;
  }
  
  // ============================================================================
  // EVENT VALIDATION
  // ============================================================================
  
  function isValidEventType(type) {
    return VALID_EVENT_TYPES.includes(type);
  }
  
  function validateEvent(event) {
    const errors = [];
  
    if (!event) {
      return { isValid: false, errors: ['Event is required'] };
    }
  
    if (!isValidEventType(event.type)) {
      errors.push(`Invalid event type: ${event.type}`);
    }
  
    if (!event.productId || typeof event.productId !== 'string') {
      errors.push('Each event must have a valid productId');
    }
  
    if (event.shopId !== undefined && event.shopId !== null && typeof event.shopId !== 'string') {
      errors.push('shopId must be a string if provided');
    }
  
    if (errors.length > 0) {
      return { isValid: false, errors };
    }
  
    return { isValid: true };
  }
  
  function validateEvents(events) {
    if (!Array.isArray(events)) {
      return { isValid: false, reason: 'not_array', message: 'Events array is required' };
    }
  
    if (events.length === 0) {
      return { isValid: false, reason: 'empty', message: 'Events array is required' };
    }
  
    if (events.length > MAX_EVENTS_PER_BATCH) {
      return { isValid: false, reason: 'too_many', message: `Maximum ${MAX_EVENTS_PER_BATCH} events per batch` };
    }
  
    const eventErrors = [];
    for (let i = 0; i < events.length; i++) {
      const result = validateEvent(events[i]);
      if (!result.isValid) {
        eventErrors.push({ index: i, errors: result.errors });
      }
    }
  
    if (eventErrors.length > 0) {
      return { isValid: false, reason: 'invalid_events', eventErrors };
    }
  
    return { isValid: true };
  }
  
  function validateBatchId(batchId) {
    if (!batchId || typeof batchId !== 'string') {
      return { isValid: false, message: 'Missing or invalid batchId' };
    }
    return { isValid: true };
  }
  
  // ============================================================================
  // EVENT TYPE HELPERS
  // ============================================================================
  
  function isAdditionEvent(type) {
    return type.includes('_added');
  }
  
  function isRemovalEvent(type) {
    return type.includes('_removed');
  }
  
  function isCartEvent(type) {
    return type.startsWith('cart_');
  }
  
  function isFavoriteEvent(type) {
    return type.startsWith('favorite_');
  }
  
  function calculateDelta(type) {
    return isAdditionEvent(type) ? 1 : -1;
  }
  
  function isShopProduct(event) {
    return !!event.shopId;
  }
  
  // ============================================================================
  // EVENT AGGREGATION
  // ============================================================================
  
  function createProductDelta() {
    return { cartDelta: 0, favDelta: 0 };
  }
  
  function createShopDelta() {
    return { cartAdditions: 0, favAdditions: 0 };
  }
  
  function updateProductDelta(delta, eventType) {
    const change = calculateDelta(eventType);
  
    if (isCartEvent(eventType)) {
      delta.cartDelta += change;
    } else if (isFavoriteEvent(eventType)) {
      delta.favDelta += change;
    }
  
    return delta;
  }
  
  function updateShopDelta(delta, eventType) {
    // Shops only track additions (lifetime metrics)
    if (!isAdditionEvent(eventType)) return delta;
  
    if (eventType === 'cart_added') {
      delta.cartAdditions += 1;
    } else if (eventType === 'favorite_added') {
      delta.favAdditions += 1;
    }
  
    return delta;
  }
  
  function aggregateEvents(batchDocs) {
    const productDeltas = new Map(); // products collection (no shopId)
    const shopProductDeltas = new Map(); // shop_products collection (has shopId)
    const shopDeltas = new Map(); // shops collection
  
    for (const doc of batchDocs) {
      const data = typeof doc.data === 'function' ? doc.data() : doc;
      const events = data.events || [];
  
      for (const event of events) {
        const { type, productId, shopId } = event;
        const hasShopId = !!shopId;
  
        if (hasShopId) {
          // Shop product - update shop_products collection
          if (!shopProductDeltas.has(productId)) {
            shopProductDeltas.set(productId, createProductDelta());
          }
          updateProductDelta(shopProductDeltas.get(productId), type);
  
          // Also update shop metrics for additions
          if (isAdditionEvent(type)) {
            if (!shopDeltas.has(shopId)) {
              shopDeltas.set(shopId, createShopDelta());
            }
            updateShopDelta(shopDeltas.get(shopId), type);
          }
        } else {
          // Regular product - update products collection
          if (!productDeltas.has(productId)) {
            productDeltas.set(productId, createProductDelta());
          }
          updateProductDelta(productDeltas.get(productId), type);
        }
      }
    }
  
    return { productDeltas, shopProductDeltas, shopDeltas };
  }
  
  // ============================================================================
  // DELTA BUILDING
  // ============================================================================
  
  function buildProductUpdateData(deltas) {
    const updateData = {};
  
    if (deltas.cartDelta !== 0) {
      updateData.cartCountIncrement = deltas.cartDelta;
    }
  
    if (deltas.favDelta !== 0) {
      updateData.favoritesCountIncrement = deltas.favDelta;
    }
  
    return updateData;
  }
  
  function buildShopUpdateData(deltas) {
    const updateData = {};
  
    if (deltas.cartAdditions > 0) {
      updateData.totalCartAdditionsIncrement = deltas.cartAdditions;
    }
  
    if (deltas.favAdditions > 0) {
      updateData.totalFavoriteAdditionsIncrement = deltas.favAdditions;
    }
  
    return updateData;
  }
  
  function hasUpdates(updateData) {
    return Object.keys(updateData).length > 0;
  }
  
  // ============================================================================
  // NEGATIVE COUNT PROTECTION
  // ============================================================================
  
  function needsNegativeCountFix(value) {
    return value != null && value < 0;
  }
  
  function buildNegativeCountFixes(data, collection) {
    const fixes = {};
  
    if (collection === 'shops') {
      // Shops have nested metrics
      if (data.metrics) {
        if (needsNegativeCountFix(data.metrics.totalCartAdditions)) {
          fixes['metrics.totalCartAdditions'] = 0;
        }
        if (needsNegativeCountFix(data.metrics.totalFavoriteAdditions)) {
          fixes['metrics.totalFavoriteAdditions'] = 0;
        }
      }
    } else {
      // Products and shop_products have flat structure
      if (needsNegativeCountFix(data.cartCount)) {
        fixes.cartCount = 0;
      }
      if (needsNegativeCountFix(data.favoritesCount)) {
        fixes.favoritesCount = 0;
      }
    }
  
    return fixes;
  }
  
  // ============================================================================
  // RETRY LOGIC
  // ============================================================================
  
  function getExponentialBackoff(attempt, baseMs = 1000, maxMs = 10000) {
    return Math.min(Math.pow(2, attempt - 1) * baseMs, maxMs);
  }
  
  function shouldRetryError(errorCode, errorMessage) {
    if (errorCode === 5) return true; // NOT_FOUND
    if (errorMessage?.includes('NOT_FOUND')) return true;
    return true; // Retry most errors
  }
  
  function isNotFoundError(errorCode, errorMessage) {
    return errorCode === 5 || errorMessage?.includes('NOT_FOUND');
  }
  
  // ============================================================================
  // RATE LIMITING
  // ============================================================================
  
  function createRateLimitEntry(now = Date.now()) {
    return { count: 1, windowStart: now };
  }
  
  function isWindowExpired(windowStart, windowMs, now = Date.now()) {
    return (now - windowStart) > windowMs;
  }
  
  function canConsume(userData, maxRequests, windowMs, now = Date.now()) {
    if (!userData) {
      return { allowed: true, reason: 'new_user' };
    }
  
    if (isWindowExpired(userData.windowStart, windowMs, now)) {
      return { allowed: true, reason: 'window_expired' };
    }
  
    if (userData.count >= maxRequests) {
      return { allowed: false, reason: 'limit_exceeded' };
    }
  
    return { allowed: true, reason: 'under_limit' };
  }
  
  function shouldCleanupEntry(windowStart, expiryMs = 10 * 60 * 1000, now = Date.now()) {
    return (now - windowStart) > expiryMs;
  }
  
  // ============================================================================
  // RESPONSE BUILDING
  // ============================================================================
  
  function buildBatchReceivedResponse(batchId, eventCount, duration) {
    return {
      success: true,
      processed: eventCount,
      batchId,
      duration,
    };
  }
  
  function buildSyncMetrics(batchesProcessed, shardsProcessed, productResult, shopProductResult, shopResult, duration) {
    const totalUpdates = productResult.success + shopProductResult.success + shopResult.success;
    const totalFailed = productResult.failed.length + shopProductResult.failed.length + shopResult.failed.length;
    const failureRate = totalUpdates > 0 ? (totalFailed / (totalUpdates + totalFailed)) * 100 : 0;
  
    return {
      batchesProcessed,
      shardsProcessed,
      productsUpdated: productResult.success,
      shopProductsUpdated: shopProductResult.success,
      shopsUpdated: shopResult.success,
      failureRate: failureRate.toFixed(2) + '%',
      duration,
    };
  }
  
  function isHighFailureRate(failureRate, threshold = 5) {
    return failureRate > threshold;
  }
  
  function isApproachingTimeout(duration, threshold = 100000) {
    return duration > threshold;
  }
  
  // ============================================================================
  // BATCHING
  // ============================================================================
  
  function chunkArray(array, size = CHUNK_SIZE) {
    if (!Array.isArray(array)) return [];
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
  
  // ============================================================================
  // CLEANUP
  // ============================================================================
  
  function getCleanupCutoffMs(days = CLEANUP_DAYS, now = Date.now()) {
    return now - (days * 24 * 60 * 60 * 1000);
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Constants
    VALID_EVENT_TYPES,
    MAX_EVENTS_PER_BATCH,
    SHARD_COUNT,
    SHARD_ROTATION_SECONDS,
    RATE_LIMIT_MAX_REQUESTS,
    RATE_LIMIT_WINDOW_MS,
    CHUNK_SIZE,
    MAX_RETRIES,
    CLEANUP_DAYS,
  
    // Shard helpers
    getQueueShard,
    getShardIndex,
    getPreviousShard,
    getShardsToProcess,
  
    // Event validation
    isValidEventType,
    validateEvent,
    validateEvents,
    validateBatchId,
  
    // Event type helpers
    isAdditionEvent,
    isRemovalEvent,
    isCartEvent,
    isFavoriteEvent,
    calculateDelta,
    isShopProduct,
  
    // Aggregation
    createProductDelta,
    createShopDelta,
    updateProductDelta,
    updateShopDelta,
    aggregateEvents,
  
    // Delta building
    buildProductUpdateData,
    buildShopUpdateData,
    hasUpdates,
  
    // Negative count protection
    needsNegativeCountFix,
    buildNegativeCountFixes,
  
    // Retry logic
    getExponentialBackoff,
    shouldRetryError,
    isNotFoundError,
  
    // Rate limiting
    createRateLimitEntry,
    isWindowExpired,
    canConsume,
    shouldCleanupEntry,
  
    // Response building
    buildBatchReceivedResponse,
    buildSyncMetrics,
    isHighFailureRate,
    isApproachingTimeout,
  
    // Batching
    chunkArray,
  
    // Cleanup
    getCleanupCutoffMs,
  };
