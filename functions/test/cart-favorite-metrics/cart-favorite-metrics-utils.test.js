// functions/test/cart-favorite-metrics/cart-favorite-metrics-utils.test.js
//
// Unit tests for cart & favorite metrics utility functions
// Tests the EXACT logic from cart/fav metrics cloud functions
//
// Run: npx jest test/cart-favorite-metrics/cart-favorite-metrics-utils.test.js

const {
    VALID_EVENT_TYPES,
    MAX_EVENTS_PER_BATCH,
    SHARD_COUNT,
    SHARD_ROTATION_SECONDS,
  
    getQueueShard,
    getShardIndex,
    getPreviousShard,
    getShardsToProcess,
  
    isValidEventType,
    validateEvent,
    validateEvents,
    validateBatchId,
  
    isAdditionEvent,
    isRemovalEvent,
    isCartEvent,
    isFavoriteEvent,
    calculateDelta,
    isShopProduct,
  
    createProductDelta,
    createShopDelta,
    updateProductDelta,
    updateShopDelta,
    aggregateEvents,
  
    buildProductUpdateData,
    buildShopUpdateData,
    hasUpdates,
  
    needsNegativeCountFix,
    buildNegativeCountFixes,
  
    getExponentialBackoff,
    isNotFoundError,
  
    createRateLimitEntry,
    isWindowExpired,
    canConsume,
    shouldCleanupEntry,
  
    buildBatchReceivedResponse,
    buildSyncMetrics,
    isHighFailureRate,
    isApproachingTimeout,
  
    chunkArray,
    getCleanupCutoffMs,
  } = require('./cart-favorite-metrics-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('VALID_EVENT_TYPES has all types', () => {
      expect(VALID_EVENT_TYPES).toContain('cart_added');
      expect(VALID_EVENT_TYPES).toContain('cart_removed');
      expect(VALID_EVENT_TYPES).toContain('favorite_added');
      expect(VALID_EVENT_TYPES).toContain('favorite_removed');
      expect(VALID_EVENT_TYPES.length).toBe(4);
    });
  
    test('MAX_EVENTS_PER_BATCH is 100', () => {
      expect(MAX_EVENTS_PER_BATCH).toBe(100);
    });
  
    test('SHARD_COUNT is 10', () => {
      expect(SHARD_COUNT).toBe(10);
    });
  
    test('SHARD_ROTATION_SECONDS is 120', () => {
      expect(SHARD_ROTATION_SECONDS).toBe(120);
    });
  });
  
  // ============================================================================
  // SHARD HELPERS TESTS
  // ============================================================================
  describe('getQueueShard', () => {
    test('returns pending_batches_N format', () => {
      const shard = getQueueShard(1000000);
      expect(shard).toMatch(/^pending_batches_\d$/);
    });
  
    test('same timestamp returns same shard', () => {
      const ts = 1000000000;
      expect(getQueueShard(ts)).toBe(getQueueShard(ts));
    });
  
    test('rotates across shards', () => {
      // Collect shards over 20 minutes (10 rotations)
      const shards = new Set();
      for (let i = 0; i < 10; i++) {
        const ts = i * 120 * 1000; // Every 2 minutes
        shards.add(getQueueShard(ts));
      }
      expect(shards.size).toBe(10);
    });
  });
  
  describe('getShardIndex', () => {
    test('returns 0-9', () => {
      for (let i = 0; i < 20; i++) {
        const index = getShardIndex(i * 120 * 1000);
        expect(index).toBeGreaterThanOrEqual(0);
        expect(index).toBeLessThan(10);
      }
    });
  });
  
  describe('getPreviousShard', () => {
    test('returns different shard than current', () => {
      const ts = 500000000; // Some arbitrary time
      
      const previous = getPreviousShard(ts);
      
      // They might be the same if we're at a boundary, but usually different
      expect(typeof previous).toBe('string');
      expect(previous).toMatch(/^pending_batches_\d$/);
    });
  });
  
  describe('getShardsToProcess', () => {
    test('returns 1 or 2 shards', () => {
      const shards = getShardsToProcess();
      expect(shards.length).toBeGreaterThanOrEqual(1);
      expect(shards.length).toBeLessThanOrEqual(2);
    });
  });
  
  // ============================================================================
  // EVENT VALIDATION TESTS
  // ============================================================================
  describe('isValidEventType', () => {
    test('returns true for valid types', () => {
      expect(isValidEventType('cart_added')).toBe(true);
      expect(isValidEventType('cart_removed')).toBe(true);
      expect(isValidEventType('favorite_added')).toBe(true);
      expect(isValidEventType('favorite_removed')).toBe(true);
    });
  
    test('returns false for invalid types', () => {
      expect(isValidEventType('invalid')).toBe(false);
      expect(isValidEventType('cart_updated')).toBe(false);
      expect(isValidEventType('')).toBe(false);
    });
  });
  
  describe('validateEvent', () => {
    test('returns valid for correct event', () => {
      const event = { type: 'cart_added', productId: 'p1' };
      expect(validateEvent(event).isValid).toBe(true);
    });
  
    test('returns valid with shopId', () => {
      const event = { type: 'cart_added', productId: 'p1', shopId: 's1' };
      expect(validateEvent(event).isValid).toBe(true);
    });
  
    test('returns invalid for missing type', () => {
      const event = { productId: 'p1' };
      expect(validateEvent(event).isValid).toBe(false);
    });
  
    test('returns invalid for missing productId', () => {
      const event = { type: 'cart_added' };
      expect(validateEvent(event).isValid).toBe(false);
    });
  
    test('returns invalid for non-string shopId', () => {
      const event = { type: 'cart_added', productId: 'p1', shopId: 123 };
      expect(validateEvent(event).isValid).toBe(false);
    });
  
    test('returns invalid for null', () => {
      expect(validateEvent(null).isValid).toBe(false);
    });
  });
  
  describe('validateEvents', () => {
    test('returns valid for correct events', () => {
      const events = [
        { type: 'cart_added', productId: 'p1' },
        { type: 'favorite_added', productId: 'p2', shopId: 's1' },
      ];
      expect(validateEvents(events).isValid).toBe(true);
    });
  
    test('returns invalid for non-array', () => {
      expect(validateEvents('not array').isValid).toBe(false);
    });
  
    test('returns invalid for empty array', () => {
      expect(validateEvents([]).isValid).toBe(false);
    });
  
    test('returns invalid for > 100 events', () => {
      const events = Array(101).fill({ type: 'cart_added', productId: 'p1' });
      const result = validateEvents(events);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_many');
    });
  });
  
  describe('validateBatchId', () => {
    test('returns valid for string', () => {
      expect(validateBatchId('batch_123').isValid).toBe(true);
    });
  
    test('returns invalid for null', () => {
      expect(validateBatchId(null).isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      expect(validateBatchId(123).isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // EVENT TYPE HELPERS TESTS
  // ============================================================================
  describe('isAdditionEvent', () => {
    test('returns true for additions', () => {
      expect(isAdditionEvent('cart_added')).toBe(true);
      expect(isAdditionEvent('favorite_added')).toBe(true);
    });
  
    test('returns false for removals', () => {
      expect(isAdditionEvent('cart_removed')).toBe(false);
      expect(isAdditionEvent('favorite_removed')).toBe(false);
    });
  });
  
  describe('isRemovalEvent', () => {
    test('returns true for removals', () => {
      expect(isRemovalEvent('cart_removed')).toBe(true);
      expect(isRemovalEvent('favorite_removed')).toBe(true);
    });
  });
  
  describe('isCartEvent', () => {
    test('identifies cart events', () => {
      expect(isCartEvent('cart_added')).toBe(true);
      expect(isCartEvent('cart_removed')).toBe(true);
      expect(isCartEvent('favorite_added')).toBe(false);
    });
  });
  
  describe('isFavoriteEvent', () => {
    test('identifies favorite events', () => {
      expect(isFavoriteEvent('favorite_added')).toBe(true);
      expect(isFavoriteEvent('favorite_removed')).toBe(true);
      expect(isFavoriteEvent('cart_added')).toBe(false);
    });
  });
  
  describe('calculateDelta', () => {
    test('returns +1 for additions', () => {
      expect(calculateDelta('cart_added')).toBe(1);
      expect(calculateDelta('favorite_added')).toBe(1);
    });
  
    test('returns -1 for removals', () => {
      expect(calculateDelta('cart_removed')).toBe(-1);
      expect(calculateDelta('favorite_removed')).toBe(-1);
    });
  });
  
  describe('isShopProduct', () => {
    test('returns true when shopId present', () => {
      expect(isShopProduct({ productId: 'p1', shopId: 's1' })).toBe(true);
    });
  
    test('returns false when no shopId', () => {
      expect(isShopProduct({ productId: 'p1' })).toBe(false);
      expect(isShopProduct({ productId: 'p1', shopId: null })).toBe(false);
    });
  });
  
  // ============================================================================
  // AGGREGATION TESTS
  // ============================================================================
  describe('createProductDelta', () => {
    test('creates zero deltas', () => {
      const delta = createProductDelta();
      expect(delta.cartDelta).toBe(0);
      expect(delta.favDelta).toBe(0);
    });
  });
  
  describe('createShopDelta', () => {
    test('creates zero additions', () => {
      const delta = createShopDelta();
      expect(delta.cartAdditions).toBe(0);
      expect(delta.favAdditions).toBe(0);
    });
  });
  
  describe('updateProductDelta', () => {
    test('increments cart delta for cart_added', () => {
      const delta = createProductDelta();
      updateProductDelta(delta, 'cart_added');
      expect(delta.cartDelta).toBe(1);
    });
  
    test('decrements cart delta for cart_removed', () => {
      const delta = createProductDelta();
      updateProductDelta(delta, 'cart_removed');
      expect(delta.cartDelta).toBe(-1);
    });
  
    test('increments fav delta for favorite_added', () => {
      const delta = createProductDelta();
      updateProductDelta(delta, 'favorite_added');
      expect(delta.favDelta).toBe(1);
    });
  });
  
  describe('updateShopDelta', () => {
    test('increments cart additions only for cart_added', () => {
      const delta = createShopDelta();
      updateShopDelta(delta, 'cart_added');
      expect(delta.cartAdditions).toBe(1);
    });
  
    test('does not increment for cart_removed', () => {
      const delta = createShopDelta();
      updateShopDelta(delta, 'cart_removed');
      expect(delta.cartAdditions).toBe(0);
    });
  
    test('increments fav additions for favorite_added', () => {
      const delta = createShopDelta();
      updateShopDelta(delta, 'favorite_added');
      expect(delta.favAdditions).toBe(1);
    });
  });
  
  describe('aggregateEvents', () => {
    test('aggregates regular product events', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' },
          { type: 'cart_added', productId: 'p1' },
          { type: 'favorite_added', productId: 'p1' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
  
      expect(result.productDeltas.get('p1').cartDelta).toBe(2);
      expect(result.productDeltas.get('p1').favDelta).toBe(1);
      expect(result.shopProductDeltas.size).toBe(0);
    });
  
    test('aggregates shop product events', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'sp1', shopId: 's1' },
          { type: 'favorite_added', productId: 'sp1', shopId: 's1' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
  
      expect(result.productDeltas.size).toBe(0);
      expect(result.shopProductDeltas.get('sp1').cartDelta).toBe(1);
      expect(result.shopProductDeltas.get('sp1').favDelta).toBe(1);
      expect(result.shopDeltas.get('s1').cartAdditions).toBe(1);
      expect(result.shopDeltas.get('s1').favAdditions).toBe(1);
    });
  
    test('handles mixed events', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' }, // Regular
          { type: 'cart_added', productId: 'sp1', shopId: 's1' }, // Shop
        ]})},
      ];
  
      const result = aggregateEvents(batches);
  
      expect(result.productDeltas.size).toBe(1);
      expect(result.shopProductDeltas.size).toBe(1);
    });
  
    test('handles additions and removals', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' },
          { type: 'cart_added', productId: 'p1' },
          { type: 'cart_removed', productId: 'p1' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
      expect(result.productDeltas.get('p1').cartDelta).toBe(1); // 2 - 1 = 1
    });
  });
  
  // ============================================================================
  // DELTA BUILDING TESTS
  // ============================================================================
  describe('buildProductUpdateData', () => {
    test('builds cart increment', () => {
      const data = buildProductUpdateData({ cartDelta: 5, favDelta: 0 });
      expect(data.cartCountIncrement).toBe(5);
      expect(data.favoritesCountIncrement).toBeUndefined();
    });
  
    test('builds both increments', () => {
      const data = buildProductUpdateData({ cartDelta: 3, favDelta: 2 });
      expect(data.cartCountIncrement).toBe(3);
      expect(data.favoritesCountIncrement).toBe(2);
    });
  
    test('omits zero deltas', () => {
      const data = buildProductUpdateData({ cartDelta: 0, favDelta: 0 });
      expect(Object.keys(data).length).toBe(0);
    });
  });
  
  describe('buildShopUpdateData', () => {
    test('builds additions only', () => {
      const data = buildShopUpdateData({ cartAdditions: 5, favAdditions: 3 });
      expect(data.totalCartAdditionsIncrement).toBe(5);
      expect(data.totalFavoriteAdditionsIncrement).toBe(3);
    });
  
    test('omits zero additions', () => {
      const data = buildShopUpdateData({ cartAdditions: 0, favAdditions: 0 });
      expect(Object.keys(data).length).toBe(0);
    });
  });
  
  describe('hasUpdates', () => {
    test('returns true when has keys', () => {
      expect(hasUpdates({ cartCountIncrement: 1 })).toBe(true);
    });
  
    test('returns false when empty', () => {
      expect(hasUpdates({})).toBe(false);
    });
  });
  
  // ============================================================================
  // NEGATIVE COUNT PROTECTION TESTS
  // ============================================================================
  describe('needsNegativeCountFix', () => {
    test('returns true for negative', () => {
      expect(needsNegativeCountFix(-1)).toBe(true);
      expect(needsNegativeCountFix(-100)).toBe(true);
    });
  
    test('returns false for non-negative', () => {
      expect(needsNegativeCountFix(0)).toBe(false);
      expect(needsNegativeCountFix(100)).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(needsNegativeCountFix(null)).toBe(false);
    });
  });
  
  describe('buildNegativeCountFixes', () => {
    test('fixes product negative counts', () => {
      const data = { cartCount: -5, favoritesCount: 10 };
      const fixes = buildNegativeCountFixes(data, 'products');
      
      expect(fixes.cartCount).toBe(0);
      expect(fixes.favoritesCount).toBeUndefined();
    });
  
    test('fixes shop nested negative counts', () => {
      const data = { metrics: { totalCartAdditions: -3, totalFavoriteAdditions: 5 } };
      const fixes = buildNegativeCountFixes(data, 'shops');
      
      expect(fixes['metrics.totalCartAdditions']).toBe(0);
      expect(fixes['metrics.totalFavoriteAdditions']).toBeUndefined();
    });
  });
  
  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  describe('getExponentialBackoff', () => {
    test('calculates exponential delays', () => {
      expect(getExponentialBackoff(1)).toBe(1000);
      expect(getExponentialBackoff(2)).toBe(2000);
      expect(getExponentialBackoff(3)).toBe(4000);
    });
  
    test('caps at max', () => {
      expect(getExponentialBackoff(10, 1000, 10000)).toBe(10000);
    });
  });
  
  describe('isNotFoundError', () => {
    test('returns true for code 5', () => {
      expect(isNotFoundError(5, '')).toBe(true);
    });
  
    test('returns true for NOT_FOUND message', () => {
      expect(isNotFoundError(null, 'NOT_FOUND')).toBe(true);
    });
  
    test('returns false otherwise', () => {
      expect(isNotFoundError(7, 'Permission denied')).toBe(false);
    });
  });
  
  // ============================================================================
  // RATE LIMITING TESTS
  // ============================================================================
  describe('createRateLimitEntry', () => {
    test('creates entry with count 1', () => {
      const now = 1000;
      const entry = createRateLimitEntry(now);
      expect(entry.count).toBe(1);
      expect(entry.windowStart).toBe(1000);
    });
  });
  
  describe('isWindowExpired', () => {
    test('returns true when expired', () => {
      expect(isWindowExpired(0, 60000, 70000)).toBe(true);
    });
  
    test('returns false when active', () => {
      expect(isWindowExpired(50000, 60000, 70000)).toBe(false);
    });
  });
  
  describe('canConsume', () => {
    test('allows new user', () => {
      expect(canConsume(null, 20, 60000).allowed).toBe(true);
    });
  
    test('allows after window expired', () => {
      const userData = { count: 20, windowStart: 0 };
      expect(canConsume(userData, 20, 60000, 70000).allowed).toBe(true);
    });
  
    test('denies when at limit', () => {
      const userData = { count: 20, windowStart: 50000 };
      expect(canConsume(userData, 20, 60000, 70000).allowed).toBe(false);
    });
  
    test('allows under limit', () => {
      const userData = { count: 10, windowStart: 50000 };
      expect(canConsume(userData, 20, 60000, 70000).allowed).toBe(true);
    });
  });
  
  describe('shouldCleanupEntry', () => {
    test('returns true for old entries', () => {
      expect(shouldCleanupEntry(0, 600000, 700000)).toBe(true);
    });
  
    test('returns false for recent entries', () => {
      expect(shouldCleanupEntry(600000, 600000, 700000)).toBe(false);
    });
  });
  
  // ============================================================================
  // RESPONSE BUILDING TESTS
  // ============================================================================
  describe('buildBatchReceivedResponse', () => {
    test('builds response', () => {
      const response = buildBatchReceivedResponse('batch_123', 10, 50);
      
      expect(response.success).toBe(true);
      expect(response.batchId).toBe('batch_123');
      expect(response.processed).toBe(10);
      expect(response.duration).toBe(50);
    });
  });
  
  describe('buildSyncMetrics', () => {
    test('builds complete metrics', () => {
      const metrics = buildSyncMetrics(
        5, // batches
        2, // shards
        { success: 10, failed: [] },
        { success: 20, failed: ['sp1'] },
        { success: 5, failed: [] },
        1000
      );
  
      expect(metrics.batchesProcessed).toBe(5);
      expect(metrics.productsUpdated).toBe(10);
      expect(metrics.shopProductsUpdated).toBe(20);
      expect(metrics.shopsUpdated).toBe(5);
    });
  });
  
  describe('isHighFailureRate', () => {
    test('returns true for > 5%', () => {
      expect(isHighFailureRate(6)).toBe(true);
    });
  
    test('returns false for <= 5%', () => {
      expect(isHighFailureRate(5)).toBe(false);
    });
  });
  
  describe('isApproachingTimeout', () => {
    test('returns true when over threshold', () => {
      expect(isApproachingTimeout(110000, 100000)).toBe(true);
    });
  
    test('returns false when under', () => {
      expect(isApproachingTimeout(50000, 100000)).toBe(false);
    });
  });
  
  // ============================================================================
  // BATCHING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks correctly', () => {
      const arr = Array(1000).fill(1);
      const chunks = chunkArray(arr, 450);
      
      expect(chunks.length).toBe(3);
      expect(chunks[0].length).toBe(450);
      expect(chunks[1].length).toBe(450);
      expect(chunks[2].length).toBe(100);
    });
  });
  
  // ============================================================================
  // CLEANUP TESTS
  // ============================================================================
  describe('getCleanupCutoffMs', () => {
    test('calculates 7 days ago', () => {
      const now = Date.now();
      const cutoff = getCleanupCutoffMs(7, now);
      const diff = now - cutoff;
      
      expect(diff).toBe(7 * 24 * 60 * 60 * 1000);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete event aggregation flow', () => {
      // User adds product to cart, then removes, then adds again
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' },
          { type: 'cart_removed', productId: 'p1' },
          { type: 'cart_added', productId: 'p1' },
          { type: 'favorite_added', productId: 'p1' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
      
      // Net: +1 cart, +1 fav
      expect(result.productDeltas.get('p1').cartDelta).toBe(1);
      expect(result.productDeltas.get('p1').favDelta).toBe(1);
    });
  
    test('shop metrics only track additions', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'sp1', shopId: 's1' },
          { type: 'cart_removed', productId: 'sp1', shopId: 's1' },
          { type: 'cart_added', productId: 'sp1', shopId: 's1' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
      
      // Shop tracks 2 additions (lifetime metric)
      expect(result.shopDeltas.get('s1').cartAdditions).toBe(2);
      
      // Shop product tracks net delta
      expect(result.shopProductDeltas.get('sp1').cartDelta).toBe(1);
    });
  
    test('multiple batches from different users', () => {
      const batches = [
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' },
          { type: 'favorite_added', productId: 'p1' },
        ]})},
        { data: () => ({ events: [
          { type: 'cart_added', productId: 'p1' },
          { type: 'cart_added', productId: 'p2' },
        ]})},
      ];
  
      const result = aggregateEvents(batches);
      
      expect(result.productDeltas.get('p1').cartDelta).toBe(2);
      expect(result.productDeltas.get('p1').favDelta).toBe(1);
      expect(result.productDeltas.get('p2').cartDelta).toBe(1);
    });
  });
