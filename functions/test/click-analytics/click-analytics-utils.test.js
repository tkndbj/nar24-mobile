// functions/test/click-analytics/click-analytics-utils.test.js
//
// Unit tests for click analytics utility functions
// Tests the EXACT logic from click analytics cloud functions
//
// Run: npx jest test/click-analytics/click-analytics-utils.test.js

const {
    MAX_CLICKS_PER_ITEM,
    MAX_ITEMS,
    MAX_PAYLOAD_SIZE,

    CHUNK_SIZE,
    SUB_SHARD_COUNT,
    CLEANUP_DAYS,
  
    getCurrentShardId,
    getShardIdForDate,
    generateBatchId,
    parseShardId,
  
    hashCode,
    getSubShardIndex,
    getFullShardId,
  
    validateBatchId,
    validateClicks,
    validatePayloadSize,
    countTotalClicks,
  
    aggregateClicks,
    extractShopIds,
    aggregateShopProductViews,
  
    chunkArray,
    calculateChunkCount,
  
    isStuckBatch,
    getExponentialBackoff,
    shouldRetryError,
  
    createRateLimiterEntry,
    canConsumeRateLimit,
    isRateLimitExpired,
    shouldCleanupRateLimiter,
  
    calculateFailureRate,
    isHighFailureRate,
    isApproachingTimeout,
    buildSyncMetrics,
  
    buildBatchData,

  
    buildSuccessResponse,
    buildIdempotentResponse,
    buildNoClicksResponse,
  
    getCleanupCutoffDate,
    isShardOlderThan,
  } = require('./click-analytics-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MAX_CLICKS_PER_ITEM is 100', () => {
      expect(MAX_CLICKS_PER_ITEM).toBe(100);
    });
  
    test('MAX_ITEMS is 1000', () => {
      expect(MAX_ITEMS).toBe(1000);
    });
  
    test('MAX_PAYLOAD_SIZE is 5MB', () => {
      expect(MAX_PAYLOAD_SIZE).toBe(5 * 1024 * 1024);
    });
  
    test('CHUNK_SIZE is 450', () => {
      expect(CHUNK_SIZE).toBe(450);
    });
  
    test('SUB_SHARD_COUNT is 10', () => {
      expect(SUB_SHARD_COUNT).toBe(10);
    });
  
    test('CLEANUP_DAYS is 7', () => {
      expect(CLEANUP_DAYS).toBe(7);
    });
  });
  
  // ============================================================================
  // SHARD ID TESTS
  // ============================================================================
  describe('getCurrentShardId', () => {
    test('generates morning shard (before noon UTC)', () => {
      const morning = new Date('2024-06-15T08:30:00Z');
      const shardId = getCurrentShardId(morning);
      expect(shardId).toBe('2024-06-15_00h');
    });
  
    test('generates afternoon shard (after noon UTC)', () => {
      const afternoon = new Date('2024-06-15T14:30:00Z');
      const shardId = getCurrentShardId(afternoon);
      expect(shardId).toBe('2024-06-15_12h');
    });
  
    test('generates shard at exactly noon', () => {
      const noon = new Date('2024-06-15T12:00:00Z');
      const shardId = getCurrentShardId(noon);
      expect(shardId).toBe('2024-06-15_12h');
    });
  
    test('pads month and day with zeros', () => {
      const date = new Date('2024-01-05T10:00:00Z');
      const shardId = getCurrentShardId(date);
      expect(shardId).toBe('2024-01-05_00h');
    });
  });
  
  describe('getShardIdForDate', () => {
    test('generates same format as getCurrentShardId', () => {
      const date = new Date('2024-06-15T08:30:00Z');
      expect(getShardIdForDate(date)).toBe('2024-06-15_00h');
    });
  });
  
  describe('generateBatchId', () => {
    test('generates unique IDs', () => {
      const id1 = generateBatchId();
      const id2 = generateBatchId();
      expect(id1).not.toBe(id2);
    });
  
    test('starts with batch_', () => {
      const id = generateBatchId();
      expect(id).toMatch(/^batch_/);
    });
  
    test('includes timestamp', () => {
      const timestamp = 1234567890;
      const id = generateBatchId(timestamp);
      expect(id).toContain('1234567890');
    });
  });
  
  describe('parseShardId', () => {
    test('parses valid morning shard', () => {
      const parsed = parseShardId('2024-06-15_00h');
      expect(parsed).toEqual({ year: 2024, month: 6, day: 15, hour: 0 });
    });
  
    test('parses valid afternoon shard', () => {
      const parsed = parseShardId('2024-06-15_12h');
      expect(parsed).toEqual({ year: 2024, month: 6, day: 15, hour: 12 });
    });
  
    test('returns null for invalid format', () => {
      expect(parseShardId('invalid')).toBe(null);
      expect(parseShardId('2024-06-15')).toBe(null);
      expect(parseShardId(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // HASHING TESTS
  // ============================================================================
  describe('hashCode', () => {
    test('returns same hash for same string', () => {
      expect(hashCode('user123')).toBe(hashCode('user123'));
    });
  
    test('returns different hash for different strings', () => {
      expect(hashCode('user123')).not.toBe(hashCode('user456'));
    });
  
    test('returns positive number', () => {
      expect(hashCode('test')).toBeGreaterThanOrEqual(0);
      expect(hashCode('negative-test-string')).toBeGreaterThanOrEqual(0);
    });
  
    test('returns 0 for null or empty', () => {
      expect(hashCode(null)).toBe(0);
      expect(hashCode('')).toBe(0);
    });
  });
  
  describe('getSubShardIndex', () => {
    test('returns index 0-9', () => {
      const index = getSubShardIndex('user123');
      expect(index).toBeGreaterThanOrEqual(0);
      expect(index).toBeLessThan(10);
    });
  
    test('same user gets same shard', () => {
      expect(getSubShardIndex('user123')).toBe(getSubShardIndex('user123'));
    });
  
    test('returns random for null user', () => {
      const index = getSubShardIndex(null);
      expect(index).toBeGreaterThanOrEqual(0);
      expect(index).toBeLessThan(10);
    });
  });
  
  describe('getFullShardId', () => {
    test('combines shard ID and sub-shard', () => {
      expect(getFullShardId('2024-06-15_00h', 5)).toBe('2024-06-15_00h_sub5');
    });
  });
  
  // ============================================================================
  // VALIDATION TESTS
  // ============================================================================
  describe('validateBatchId', () => {
    test('returns invalid for null', () => {
      const result = validateBatchId(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      const result = validateBatchId(123);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for string', () => {
      const result = validateBatchId('batch_123');
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('validateClicks', () => {
    test('returns valid for empty object', () => {
      const result = validateClicks({}, 'product');
      expect(result.isValid).toBe(true);
    });
  
    test('returns valid for correct clicks', () => {
      const clicks = { prod1: 5, prod2: 10 };
      const result = validateClicks(clicks, 'product');
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid for too many items', () => {
      const clicks = {};
      for (let i = 0; i < 1001; i++) {
        clicks[`prod${i}`] = 1;
      }
      const result = validateClicks(clicks, 'product');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_many_items');
    });
  
    test('returns invalid for count > 100', () => {
      const clicks = { prod1: 101 };
      const result = validateClicks(clicks, 'product');
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for count < 1', () => {
      const clicks = { prod1: 0 };
      const result = validateClicks(clicks, 'product');
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-number count', () => {
      const clicks = { prod1: 'five' };
      const result = validateClicks(clicks, 'product');
      expect(result.isValid).toBe(false);
    });
  });
  
  describe('validatePayloadSize', () => {
    test('returns valid for small payload', () => {
      const data = { clicks: { a: 1 } };
      const result = validatePayloadSize(data);
      expect(result.isValid).toBe(true);
    });
  
    test('returns size in result', () => {
      const data = { clicks: { a: 1 } };
      const result = validatePayloadSize(data);
      expect(result.size).toBeGreaterThan(0);
    });
  });
  
  describe('countTotalClicks', () => {
    test('counts all click types', () => {
      const count = countTotalClicks(
        { a: 1, b: 2 },
        { c: 3 },
        { d: 4, e: 5, f: 6 }
      );
      expect(count).toBe(6);
    });
  
    test('handles null values', () => {
      expect(countTotalClicks(null, null, null)).toBe(0);
    });
  });
  
  // ============================================================================
  // AGGREGATION TESTS
  // ============================================================================
  describe('aggregateClicks', () => {
    test('aggregates clicks from multiple batches', () => {
      const batches = [
        { productClicks: { p1: 5, p2: 3 }, shopProductClicks: { sp1: 2 } },
        { productClicks: { p1: 2, p3: 1 }, shopClicks: { s1: 4 } },
      ];
  
      const result = aggregateClicks(batches);
  
      expect(result.productClicks.get('p1')).toBe(7);
      expect(result.productClicks.get('p2')).toBe(3);
      expect(result.productClicks.get('p3')).toBe(1);
      expect(result.shopProductClicks.get('sp1')).toBe(2);
      expect(result.shopClicks.get('s1')).toBe(4);
    });
  
    test('handles empty batches', () => {
      const result = aggregateClicks([]);
      expect(result.productClicks.size).toBe(0);
    });
  
    test('handles batches with data() method', () => {
      const batches = [
        { data: () => ({ productClicks: { p1: 5 } }) },
      ];
  
      const result = aggregateClicks(batches);
      expect(result.productClicks.get('p1')).toBe(5);
    });
  });
  
  describe('extractShopIds', () => {
    test('extracts shop IDs from batches', () => {
      const batches = [
        { shopIds: { prod1: 'shop1', prod2: 'shop2' } },
        { shopIds: { prod3: 'shop1' } },
      ];
  
      const result = extractShopIds(batches);
      expect(result.get('prod1')).toBe('shop1');
      expect(result.get('prod3')).toBe('shop1');
    });
  });
  
  describe('aggregateShopProductViews', () => {
    test('aggregates by shop ID', () => {
      const clicks = new Map([['prod1', 5], ['prod2', 3], ['prod3', 2]]);
      const shopIds = new Map([['prod1', 'shop1'], ['prod2', 'shop1'], ['prod3', 'shop2']]);
  
      const result = aggregateShopProductViews(clicks, shopIds);
  
      expect(result.get('shop1')).toBe(8);
      expect(result.get('shop2')).toBe(2);
    });
  
    test('ignores products without shop ID', () => {
      const clicks = new Map([['prod1', 5], ['prod2', 3]]);
      const shopIds = new Map([['prod1', 'shop1']]);
  
      const result = aggregateShopProductViews(clicks, shopIds);
      expect(result.get('shop1')).toBe(5);
      expect(result.has('prod2')).toBe(false);
    });
  });
  
  // ============================================================================
  // CHUNKING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks array correctly', () => {
      const arr = [1, 2, 3, 4, 5];
      const chunks = chunkArray(arr, 2);
      
      expect(chunks).toEqual([[1, 2], [3, 4], [5]]);
    });
  
    test('handles array smaller than chunk size', () => {
      const arr = [1, 2, 3];
      const chunks = chunkArray(arr, 10);
      
      expect(chunks).toEqual([[1, 2, 3]]);
    });
  
    test('handles empty array', () => {
      expect(chunkArray([], 10)).toEqual([]);
    });
  
    test('handles non-array', () => {
      expect(chunkArray(null, 10)).toEqual([]);
    });
  });
  
  describe('calculateChunkCount', () => {
    test('calculates correct count', () => {
      expect(calculateChunkCount(1000, 450)).toBe(3);
      expect(calculateChunkCount(450, 450)).toBe(1);
      expect(calculateChunkCount(451, 450)).toBe(2);
    });
  
    test('returns 0 for empty', () => {
      expect(calculateChunkCount(0, 450)).toBe(0);
    });
  });
  
  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  describe('isStuckBatch', () => {
    test('returns true at max retries', () => {
      expect(isStuckBatch(5, 5)).toBe(true);
    });
  
    test('returns false under max', () => {
      expect(isStuckBatch(4, 5)).toBe(false);
    });
  
    test('handles null', () => {
      expect(isStuckBatch(null, 5)).toBe(false);
    });
  });
  
  describe('getExponentialBackoff', () => {
    test('calculates exponential delays', () => {
      expect(getExponentialBackoff(1)).toBe(1000);
      expect(getExponentialBackoff(2)).toBe(2000);
      expect(getExponentialBackoff(3)).toBe(4000);
      expect(getExponentialBackoff(4)).toBe(8000);
    });
  
    test('caps at max', () => {
      expect(getExponentialBackoff(10, 1000, 10000)).toBe(10000);
    });
  });
  
  describe('shouldRetryError', () => {
    test('returns false for PERMISSION_DENIED', () => {
      expect(shouldRetryError(7, '')).toBe(false);
    });
  
    test('returns true for NOT_FOUND', () => {
      expect(shouldRetryError(5, '')).toBe(true);
      expect(shouldRetryError(null, 'NOT_FOUND')).toBe(true);
    });
  
    test('returns true for other errors', () => {
      expect(shouldRetryError(null, 'Random error')).toBe(true);
    });
  });
  
  // ============================================================================
  // RATE LIMITER TESTS
  // ============================================================================
  describe('createRateLimiterEntry', () => {
    test('creates entry with count 1', () => {
      const now = 1000;
      const entry = createRateLimiterEntry(60000, now);
      
      expect(entry.count).toBe(1);
      expect(entry.resetAt).toBe(61000);
    });
  });
  
  describe('canConsumeRateLimit', () => {
    test('returns true for null entry', () => {
      const result = canConsumeRateLimit(null, 10);
      expect(result.canConsume).toBe(true);
      expect(result.reason).toBe('new_window');
    });
  
    test('returns true for expired entry', () => {
      const entry = { count: 10, resetAt: 1000 };
      const result = canConsumeRateLimit(entry, 10, 2000);
      expect(result.canConsume).toBe(true);
    });
  
    test('returns false when limit exceeded', () => {
      const entry = { count: 10, resetAt: 5000 };
      const result = canConsumeRateLimit(entry, 10, 1000);
      expect(result.canConsume).toBe(false);
      expect(result.reason).toBe('limit_exceeded');
    });
  
    test('returns true when under limit', () => {
      const entry = { count: 5, resetAt: 5000 };
      const result = canConsumeRateLimit(entry, 10, 1000);
      expect(result.canConsume).toBe(true);
      expect(result.reason).toBe('under_limit');
    });
  });
  
  describe('isRateLimitExpired', () => {
    test('returns true for null', () => {
      expect(isRateLimitExpired(null)).toBe(true);
    });
  
    test('returns true when past resetAt', () => {
      expect(isRateLimitExpired({ resetAt: 1000 }, 2000)).toBe(true);
    });
  
    test('returns false when before resetAt', () => {
      expect(isRateLimitExpired({ resetAt: 5000 }, 1000)).toBe(false);
    });
  });
  
  describe('shouldCleanupRateLimiter', () => {
    test('returns true when over max', () => {
      expect(shouldCleanupRateLimiter(100001, 100000)).toBe(true);
    });
  
    test('returns false when under max', () => {
      expect(shouldCleanupRateLimiter(50000, 100000)).toBe(false);
    });
  });
  
  // ============================================================================
  // METRICS TESTS
  // ============================================================================
  describe('calculateFailureRate', () => {
    test('calculates percentage', () => {
      expect(calculateFailureRate(5, 100)).toBe(5);
      expect(calculateFailureRate(10, 50)).toBe(20);
    });
  
    test('returns 0 for zero total', () => {
      expect(calculateFailureRate(5, 0)).toBe(0);
    });
  });
  
  describe('isHighFailureRate', () => {
    test('returns true for high rate', () => {
      expect(isHighFailureRate(6, 5)).toBe(true);
    });
  
    test('returns false for acceptable rate', () => {
      expect(isHighFailureRate(4, 5)).toBe(false);
    });
  });
  
  describe('isApproachingTimeout', () => {
    test('returns true when near timeout', () => {
      expect(isApproachingTimeout(490000, 540000, 480000)).toBe(true);
    });
  
    test('returns false when safe', () => {
      expect(isApproachingTimeout(300000, 540000, 480000)).toBe(false);
    });
  });
  
  describe('buildSyncMetrics', () => {
    test('builds complete metrics', () => {
      const metrics = buildSyncMetrics(10, 100, 50, 5, 60000, 2);
      
      expect(metrics.batchesProcessed).toBe(10);
      expect(metrics.productsUpdated).toBe(100);
      expect(metrics.shopsUpdated).toBe(50);
      expect(metrics.duration).toBe(60000);
      expect(metrics.stuckBatches).toBe(2);
      expect(metrics.failureRate).toMatch(/^\d+\.\d+%$/);
    });
  });
  
  // ============================================================================
  // BATCH DATA TESTS
  // ============================================================================
  describe('buildBatchData', () => {
    test('builds batch with all click types', () => {
      const data = buildBatchData(
        { p1: 5 },
        { sp1: 3 },
        { s1: 2 },
        { p1: 's1' },
        'user123'
      );
  
      expect(data.productClicks).toEqual({ p1: 5 });
      expect(data.shopProductClicks).toEqual({ sp1: 3 });
      expect(data.shopClicks).toEqual({ s1: 2 });
      expect(data.shopIds).toEqual({ p1: 's1' });
      expect(data.createdBy).toBe('user123');
      expect(data.processed).toBe(false);
    });
  
    test('omits empty click types', () => {
      const data = buildBatchData({ p1: 5 }, {}, null, null, 'user');
      
      expect(data.productClicks).toEqual({ p1: 5 });
      expect(data.shopProductClicks).toBeUndefined();
      expect(data.shopClicks).toBeUndefined();
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildSuccessResponse', () => {
    test('builds complete response', () => {
      const response = buildSuccessResponse(100, 'batch_123', 'shard_1', 500);
      
      expect(response.success).toBe(true);
      expect(response.processed).toBe(100);
      expect(response.batchId).toBe('batch_123');
      expect(response.duration).toBe(500);
    });
  });
  
  describe('buildIdempotentResponse', () => {
    test('builds idempotent response', () => {
      const response = buildIdempotentResponse('batch_123');
      
      expect(response.success).toBe(true);
      expect(response.processed).toBe(0);
      expect(response.message).toContain('idempotent');
    });
  });
  
  describe('buildNoClicksResponse', () => {
    test('builds no clicks response', () => {
      const response = buildNoClicksResponse();
      
      expect(response.success).toBe(true);
      expect(response.processed).toBe(0);
    });
  });
  
  // ============================================================================
  // CLEANUP TESTS
  // ============================================================================
  describe('getCleanupCutoffDate', () => {
    test('returns date 7 days ago', () => {
      const now = new Date('2024-06-15T12:00:00Z');
      const cutoff = getCleanupCutoffDate(7, now);
      expect(cutoff.toISOString()).toBe('2024-06-08T12:00:00.000Z');
    });
  });
  
  describe('isShardOlderThan', () => {
    test('compares shard IDs', () => {
      expect(isShardOlderThan('2024-06-01_00h', '2024-06-08_00h')).toBe(true);
      expect(isShardOlderThan('2024-06-10_00h', '2024-06-08_00h')).toBe(false);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete click batch flow', () => {
      // 1. Generate shard ID
      const shardId = getCurrentShardId(new Date('2024-06-15T10:00:00Z'));
      expect(shardId).toBe('2024-06-15_00h');
  
      // 2. Generate batch ID
      const batchId = generateBatchId();
      expect(validateBatchId(batchId).isValid).toBe(true);
  
      // 3. Validate clicks
      const clicks = { prod1: 5, prod2: 10 };
      expect(validateClicks(clicks, 'product').isValid).toBe(true);
  
      // 4. Build batch data
      const batchData = buildBatchData(clicks, {}, {}, {}, 'user123');
      expect(batchData.processed).toBe(false);
  
      // 5. Build response
      const response = buildSuccessResponse(2, batchId, shardId, 100);
      expect(response.success).toBe(true);
    });
  
    test('aggregation and sync flow', () => {
      // Multiple batches to aggregate
      const batches = [
        { productClicks: { p1: 5 }, shopProductClicks: { sp1: 3 }, shopIds: { sp1: 'shop1' } },
        { productClicks: { p1: 2, p2: 1 }, shopProductClicks: { sp1: 2 }, shopIds: { sp1: 'shop1' } },
      ];
  
      // Aggregate clicks
      const aggregated = aggregateClicks(batches);
      expect(aggregated.productClicks.get('p1')).toBe(7);
      expect(aggregated.shopProductClicks.get('sp1')).toBe(5);
  
      // Extract shop IDs
      const shopIds = extractShopIds(batches);
      expect(shopIds.get('sp1')).toBe('shop1');
  
      // Aggregate shop views
      const shopViews = aggregateShopProductViews(aggregated.shopProductClicks, shopIds);
      expect(shopViews.get('shop1')).toBe(5);
  
      // Chunk for processing
      const entries = Array.from(aggregated.productClicks.entries());
      const chunks = chunkArray(entries, 450);
      expect(chunks.length).toBe(1);
    });
  
    test('rate limiting flow', () => {
      const now = 1000;
      const windowMs = 60000;
      const maxRequests = 10;
  
      // First request - allowed
      let entry = null;
      let result = canConsumeRateLimit(entry, maxRequests, now);
      expect(result.canConsume).toBe(true);
  
      // Create entry
      entry = createRateLimiterEntry(windowMs, now);
      expect(entry.count).toBe(1);
  
      // Simulate 9 more requests
      entry.count = 10;
  
      // 11th request - denied
      result = canConsumeRateLimit(entry, maxRequests, now + 1000);
      expect(result.canConsume).toBe(false);
  
      // After window expires - allowed
      result = canConsumeRateLimit(entry, maxRequests, now + windowMs + 1);
      expect(result.canConsume).toBe(true);
    });
  });
