// functions/test/user-activity/user-activity-utils.test.js
//
// Unit tests for user activity tracking utility functions
// Tests the EXACT logic from user activity cloud functions
//
// Run: npx jest test/user-activity/user-activity-utils.test.js

const {
    ACTIVITY_WEIGHTS,
    CONFIG,
    TRACKABLE_PRODUCT_EVENTS,
  
    isValidEventType,
    getEventWeight,
    isEventTooOld,
    validateEvent,
    validateEvents,
    filterValidEvents,
  
    sanitizeFirestoreKey,
    sanitizeSearchQuery,
  
    createScoreMap,
    addScore,
    aggregateCategoryScores,
    aggregateBrandScores,
    aggregateAllScores,
  
    isTrackableProductEvent,
    extractRecentProducts,
  
    extractPurchaseStats,
    calculateItemTotal,
  
    extractSearchQueries,
  
    getTopN,
    getTopCategories,
    getTopBrands,
  
    pruneScores,
    pruneCategoryScores,
  
  
    calculateAveragePurchasePrice,
  
    createRateLimitEntry,
    isRateLimitWindowExpired,
    isRateLimited,

  
    shouldRetryDLQItem,
    getDLQStatus,
    buildDLQEntry,
  
    getRetryDelay,
    shouldRetryError,
  
    getTodayDateString,
    getRetentionCutoffDate,

  
    buildCategoryScoresUpdate,

  } = require('./user-activity-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('ACTIVITY_WEIGHTS has all event types', () => {
      expect(ACTIVITY_WEIGHTS.click).toBe(1);
      expect(ACTIVITY_WEIGHTS.view).toBe(2);
      expect(ACTIVITY_WEIGHTS.addToCart).toBe(5);
      expect(ACTIVITY_WEIGHTS.removeFromCart).toBe(-2);
      expect(ACTIVITY_WEIGHTS.favorite).toBe(3);
      expect(ACTIVITY_WEIGHTS.unfavorite).toBe(-1);
      expect(ACTIVITY_WEIGHTS.purchase).toBe(10);
      expect(ACTIVITY_WEIGHTS.search).toBe(1);
    });
  
    test('CONFIG has correct values', () => {
      expect(CONFIG.MAX_EVENTS_PER_BATCH).toBe(100);
      expect(CONFIG.RETENTION_DAYS).toBe(90);
      expect(CONFIG.DLQ_MAX_RETRIES).toBe(5);
    });
  
    test('TRACKABLE_PRODUCT_EVENTS includes correct events', () => {
      expect(TRACKABLE_PRODUCT_EVENTS).toContain('click');
      expect(TRACKABLE_PRODUCT_EVENTS).toContain('view');
      expect(TRACKABLE_PRODUCT_EVENTS).toContain('addToCart');
      expect(TRACKABLE_PRODUCT_EVENTS).toContain('favorite');
      expect(TRACKABLE_PRODUCT_EVENTS).not.toContain('purchase');
    });
  });
  
  // ============================================================================
  // EVENT VALIDATION TESTS
  // ============================================================================
  describe('isValidEventType', () => {
    test('returns true for valid types', () => {
      expect(isValidEventType('click')).toBe(true);
      expect(isValidEventType('purchase')).toBe(true);
      expect(isValidEventType('addToCart')).toBe(true);
    });
  
    test('returns false for invalid types', () => {
      expect(isValidEventType('invalid')).toBe(false);
      expect(isValidEventType('')).toBe(false);
      expect(isValidEventType(null)).toBe(false);
    });
  });
  
  describe('getEventWeight', () => {
    test('returns correct weights', () => {
      expect(getEventWeight('click')).toBe(1);
      expect(getEventWeight('purchase')).toBe(10);
      expect(getEventWeight('removeFromCart')).toBe(-2);
    });
  
    test('returns 0 for invalid type', () => {
      expect(getEventWeight('invalid')).toBe(0);
    });
  });
  
  describe('isEventTooOld', () => {
    const now = Date.now();
    const maxAge = 24 * 60 * 60 * 1000; // 24 hours
  
    test('returns false for recent event', () => {
      const recentTimestamp = now - (1 * 60 * 60 * 1000); // 1 hour ago
      expect(isEventTooOld(recentTimestamp, maxAge, now)).toBe(false);
    });
  
    test('returns true for old event', () => {
      const oldTimestamp = now - (25 * 60 * 60 * 1000); // 25 hours ago
      expect(isEventTooOld(oldTimestamp, maxAge, now)).toBe(true);
    });
  });
  
  describe('validateEvent', () => {
    const now = Date.now();
  
    test('returns valid for correct event', () => {
      const event = { eventId: 'e1', type: 'click', timestamp: now - 1000 };
      expect(validateEvent(event, now).isValid).toBe(true);
    });
  
    test('returns invalid for missing eventId', () => {
      const event = { type: 'click', timestamp: now };
      expect(validateEvent(event, now).isValid).toBe(false);
    });
  
    test('returns invalid for missing type', () => {
      const event = { eventId: 'e1', timestamp: now };
      expect(validateEvent(event, now).isValid).toBe(false);
    });
  
    test('returns invalid for invalid type', () => {
      const event = { eventId: 'e1', type: 'invalid', timestamp: now };
      expect(validateEvent(event, now).isValid).toBe(false);
    });
  
    test('returns invalid for old event', () => {
      const oldTimestamp = now - (25 * 60 * 60 * 1000);
      const event = { eventId: 'e1', type: 'click', timestamp: oldTimestamp };
      expect(validateEvent(event, now).isValid).toBe(false);
    });
  });
  
  describe('validateEvents', () => {
    test('returns valid for correct array', () => {
      const events = [{ eventId: 'e1', type: 'click', timestamp: Date.now() }];
      expect(validateEvents(events).isValid).toBe(true);
    });
  
    test('returns invalid for non-array', () => {
      expect(validateEvents('not array').isValid).toBe(false);
    });
  
    test('returns invalid for empty array', () => {
      expect(validateEvents([]).isValid).toBe(false);
    });
  
    test('returns invalid for > 100 events', () => {
      const events = Array(101).fill({ eventId: 'e1', type: 'click', timestamp: Date.now() });
      expect(validateEvents(events).isValid).toBe(false);
    });
  });
  
  describe('filterValidEvents', () => {
    const now = Date.now();
  
    test('filters out invalid events', () => {
      const events = [
        { eventId: 'e1', type: 'click', timestamp: now - 1000 },
        { eventId: 'e2', type: 'invalid', timestamp: now },
        { eventId: 'e3', type: 'view', timestamp: now - 1000 },
        { type: 'click', timestamp: now }, // Missing eventId
      ];
  
      const valid = filterValidEvents(events, now);
      expect(valid.length).toBe(2);
    });
  
    test('returns empty for null', () => {
      expect(filterValidEvents(null)).toEqual([]);
    });
  });
  
  // ============================================================================
  // KEY SANITIZATION TESTS
  // ============================================================================
  describe('sanitizeFirestoreKey', () => {
    test('replaces dots and slashes', () => {
      expect(sanitizeFirestoreKey('category.sub/cat')).toBe('category_sub_cat');
    });
  
    test('returns empty for null', () => {
      expect(sanitizeFirestoreKey(null)).toBe('');
    });
  
    test('preserves valid characters', () => {
      expect(sanitizeFirestoreKey('Electronics')).toBe('Electronics');
    });
  });
  
  describe('sanitizeSearchQuery', () => {
    test('lowercases and trims', () => {
      expect(sanitizeSearchQuery('  HELLO World  ')).toBe('hello world');
    });
  
    test('truncates to 50 chars', () => {
      const long = 'a'.repeat(60);
      expect(sanitizeSearchQuery(long).length).toBe(50);
    });
  
    test('replaces dots and slashes', () => {
      expect(sanitizeSearchQuery('test.query/here')).toBe('test_query_here');
    });
  });
  
  // ============================================================================
  // SCORE AGGREGATION TESTS
  // ============================================================================
  describe('addScore', () => {
    test('adds score to map', () => {
      const map = createScoreMap();
      addScore(map, 'Electronics', 5);
      addScore(map, 'Electronics', 3);
      expect(map.get('Electronics')).toBe(8);
    });
  
    test('ignores negative scores', () => {
      const map = createScoreMap();
      addScore(map, 'Electronics', -5);
      expect(map.has('Electronics')).toBe(false);
    });
  
    test('ignores null key', () => {
      const map = createScoreMap();
      addScore(map, null, 5);
      expect(map.size).toBe(0);
    });
  });
  
  describe('aggregateCategoryScores', () => {
    test('aggregates category and subcategory', () => {
      const events = [
        { type: 'click', category: 'Electronics', subcategory: 'Phones' },
        { type: 'view', category: 'Electronics' },
        { type: 'addToCart', category: 'Clothing' },
      ];
  
      const scores = aggregateCategoryScores(events);
  
      expect(scores.get('Electronics')).toBe(3); // 1 + 2
      expect(scores.get('Phones')).toBe(1);
      expect(scores.get('Clothing')).toBe(5);
    });
  
    test('ignores negative weight events', () => {
      const events = [
        { type: 'removeFromCart', category: 'Electronics' },
        { type: 'unfavorite', category: 'Clothing' },
      ];
  
      const scores = aggregateCategoryScores(events);
      expect(scores.size).toBe(0);
    });
  });
  
  describe('aggregateBrandScores', () => {
    test('aggregates brand scores', () => {
      const events = [
        { type: 'click', brand: 'Apple' },
        { type: 'purchase', brand: 'Apple' },
        { type: 'view', brand: 'Samsung' },
      ];
  
      const scores = aggregateBrandScores(events);
  
      expect(scores.get('Apple')).toBe(11); // 1 + 10
      expect(scores.get('Samsung')).toBe(2);
    });
  });
  
  // ============================================================================
  // RECENT PRODUCTS TESTS
  // ============================================================================
  describe('isTrackableProductEvent', () => {
    test('returns true for trackable events', () => {
      expect(isTrackableProductEvent('click')).toBe(true);
      expect(isTrackableProductEvent('view')).toBe(true);
      expect(isTrackableProductEvent('addToCart')).toBe(true);
      expect(isTrackableProductEvent('favorite')).toBe(true);
    });
  
    test('returns false for non-trackable', () => {
      expect(isTrackableProductEvent('purchase')).toBe(false);
      expect(isTrackableProductEvent('search')).toBe(false);
    });
  });
  
  describe('extractRecentProducts', () => {
    test('extracts and sorts by timestamp', () => {
      const events = [
        { type: 'click', productId: 'p1', timestamp: 1000 },
        { type: 'view', productId: 'p2', timestamp: 3000 },
        { type: 'addToCart', productId: 'p3', timestamp: 2000 },
      ];
  
      const recent = extractRecentProducts(events, 20);
  
      expect(recent[0].productId).toBe('p2'); // Most recent
      expect(recent[1].productId).toBe('p3');
      expect(recent[2].productId).toBe('p1');
    });
  
    test('limits to specified count', () => {
      const events = Array(30).fill(null).map((_, i) => ({
        type: 'click',
        productId: `p${i}`,
        timestamp: i,
      }));
  
      const recent = extractRecentProducts(events, 20);
      expect(recent.length).toBe(20);
    });
  
    test('ignores non-trackable events', () => {
      const events = [
        { type: 'purchase', productId: 'p1', timestamp: 1000 },
        { type: 'search', productId: 'p2', timestamp: 2000 },
      ];
  
      const recent = extractRecentProducts(events);
      expect(recent.length).toBe(0);
    });
  });
  
  // ============================================================================
  // PURCHASE TRACKING TESTS
  // ============================================================================
  describe('extractPurchaseStats', () => {
    test('extracts count and total value', () => {
      const events = [
        { type: 'purchase', totalValue: 100 },
        { type: 'purchase', totalValue: 50 },
        { type: 'click' },
      ];
  
      const stats = extractPurchaseStats(events);
  
      expect(stats.count).toBe(2);
      expect(stats.totalValue).toBe(150);
    });
  
    test('handles missing totalValue', () => {
      const events = [{ type: 'purchase' }];
      const stats = extractPurchaseStats(events);
      expect(stats.totalValue).toBe(0);
    });
  });
  
  describe('calculateItemTotal', () => {
    test('calculates correctly', () => {
      expect(calculateItemTotal(100, 3)).toBe(300);
    });
  
    test('handles null values', () => {
      expect(calculateItemTotal(null, 3)).toBe(0);
      expect(calculateItemTotal(100, null)).toBe(100);
    });
  });
  
  // ============================================================================
  // SEARCH TRACKING TESTS
  // ============================================================================
  describe('extractSearchQueries', () => {
    test('extracts search queries', () => {
      const events = [
        { type: 'search', searchQuery: 'shoes' },
        { type: 'search', searchQuery: 'bags' },
        { type: 'click' },
      ];
  
      const queries = extractSearchQueries(events);
  
      expect(queries).toEqual(['shoes', 'bags']);
    });
  
    test('ignores empty queries', () => {
      const events = [
        { type: 'search', searchQuery: '' },
        { type: 'search' },
      ];
  
      const queries = extractSearchQueries(events);
      expect(queries.length).toBe(0);
    });
  });
  
  // ============================================================================
  // TOP N EXTRACTION TESTS
  // ============================================================================
  describe('getTopN', () => {
    test('returns top N sorted by score', () => {
      const map = new Map([
        ['a', 10],
        ['b', 30],
        ['c', 20],
      ]);
  
      const top = getTopN(map, 2);
  
      expect(top[0]).toEqual({ key: 'b', score: 30 });
      expect(top[1]).toEqual({ key: 'c', score: 20 });
      expect(top.length).toBe(2);
    });
  });
  
  describe('getTopCategories', () => {
    test('formats as category objects', () => {
      const map = new Map([['Electronics', 50], ['Clothing', 30]]);
      const top = getTopCategories(map, 2);
  
      expect(top[0]).toEqual({ category: 'Electronics', score: 50 });
    });
  });
  
  describe('getTopBrands', () => {
    test('formats as brand objects', () => {
      const map = new Map([['Apple', 100], ['Samsung', 80]]);
      const top = getTopBrands(map, 2);
  
      expect(top[0]).toEqual({ brand: 'Apple', score: 100 });
    });
  });
  
  // ============================================================================
  // SCORE PRUNING TESTS
  // ============================================================================
  describe('pruneScores', () => {
    test('keeps top entries and filters by min score', () => {
      const scores = { a: 100, b: 50, c: 3, d: 2 };
      const pruned = pruneScores(scores, 10, 5);
  
      expect(pruned.a).toBe(100);
      expect(pruned.b).toBe(50);
      expect(pruned.c).toBeUndefined(); // Below min score
      expect(pruned.d).toBeUndefined();
    });
  
    test('limits to max entries', () => {
      const scores = {};
      for (let i = 0; i < 200; i++) {
        scores[`cat${i}`] = 100 - i;
      }
  
      const pruned = pruneScores(scores, 50, 0);
      expect(Object.keys(pruned).length).toBe(50);
    });
  });
  
  // ============================================================================
  // AVERAGE CALCULATION TESTS
  // ============================================================================
  describe('calculateAveragePurchasePrice', () => {
    test('calculates average', () => {
      expect(calculateAveragePurchasePrice(300, 3)).toBe(100);
    });
  
    test('returns null for zero purchases', () => {
      expect(calculateAveragePurchasePrice(100, 0)).toBe(null);
    });
  });
  
  // ============================================================================
  // RATE LIMITING TESTS
  // ============================================================================
  describe('createRateLimitEntry', () => {
    test('creates entry with count 1', () => {
      const entry = createRateLimitEntry(1000);
      expect(entry.count).toBe(1);
      expect(entry.windowStart).toBe(1000);
    });
  });
  
  describe('isRateLimitWindowExpired', () => {
    test('returns true when expired', () => {
      expect(isRateLimitWindowExpired(0, 60000, 70000)).toBe(true);
    });
  
    test('returns false when active', () => {
      expect(isRateLimitWindowExpired(50000, 60000, 70000)).toBe(false);
    });
  });
  
  describe('isRateLimited', () => {
    test('returns false for null entry', () => {
      expect(isRateLimited(null, 20, 60000, 1000)).toBe(false);
    });
  
    test('returns true when at limit', () => {
      const entry = { count: 20, windowStart: 50000 };
      expect(isRateLimited(entry, 20, 60000, 70000)).toBe(true);
    });
  
    test('returns false when window expired', () => {
      const entry = { count: 20, windowStart: 0 };
      expect(isRateLimited(entry, 20, 60000, 70000)).toBe(false);
    });
  });
  
  // ============================================================================
  // DLQ TESTS
  // ============================================================================
  describe('shouldRetryDLQItem', () => {
    test('returns true under max retries', () => {
      expect(shouldRetryDLQItem(3, 5)).toBe(true);
    });
  
    test('returns false at max retries', () => {
      expect(shouldRetryDLQItem(5, 5)).toBe(false);
    });
  });
  
  describe('getDLQStatus', () => {
    test('returns failed at max retries', () => {
      expect(getDLQStatus(5, 5)).toBe('failed');
    });
  
    test('returns pending under max', () => {
      expect(getDLQStatus(3, 5)).toBe('pending');
    });
  });
  
  describe('buildDLQEntry', () => {
    test('builds entry correctly', () => {
      const entry = buildDLQEntry('user1', [{ type: 'click' }], new Error('Test error'));
  
      expect(entry.userId).toBe('user1');
      expect(entry.events.length).toBe(1);
      expect(entry.error).toBe('Test error');
      expect(entry.status).toBe('pending');
      expect(entry.retryCount).toBe(0);
    });
  });
  
  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  describe('getRetryDelay', () => {
    test('calculates exponential delay', () => {
      expect(getRetryDelay(1, 100)).toBe(100);
      expect(getRetryDelay(2, 100)).toBe(200);
      expect(getRetryDelay(3, 100)).toBe(400);
    });
  });
  
  describe('shouldRetryError', () => {
    test('returns false for validation errors', () => {
      expect(shouldRetryError('invalid-argument')).toBe(false);
      expect(shouldRetryError('permission-denied')).toBe(false);
    });
  
    test('returns true for other errors', () => {
      expect(shouldRetryError('internal')).toBe(true);
      expect(shouldRetryError('unavailable')).toBe(true);
    });
  });
  
  // ============================================================================
  // DATE HELPERS TESTS
  // ============================================================================
  describe('getTodayDateString', () => {
    test('returns YYYY-MM-DD format', () => {
      const date = new Date('2024-06-15T10:30:00Z');
      expect(getTodayDateString(date)).toBe('2024-06-15');
    });
  });
  
  describe('getRetentionCutoffDate', () => {
    test('returns date N days ago', () => {
      const now = new Date('2024-06-15');
      const cutoff = getRetentionCutoffDate(90, now);
      expect(cutoff).toBe('2024-03-17');
    });
  });
  
  // ============================================================================
  // PROFILE UPDATE BUILDING TESTS
  // ============================================================================
  describe('buildCategoryScoresUpdate', () => {
    test('builds update with sanitized keys', () => {
      const scores = new Map([
        ['Electronics.Phones', 10],
        ['Clothing', 5],
      ]);
  
      const update = buildCategoryScoresUpdate(scores);
  
      expect(update['Electronics_Phones']).toBe(10);
      expect(update['Clothing']).toBe(5);
    });
  
    test('returns null for empty map', () => {
      expect(buildCategoryScoresUpdate(new Map())).toBe(null);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete user activity flow', () => {
      const now = Date.now();
      const events = [
        { eventId: 'e1', type: 'view', timestamp: now - 1000, productId: 'p1', category: 'Electronics', brand: 'Apple' },
        { eventId: 'e2', type: 'addToCart', timestamp: now - 500, productId: 'p1', category: 'Electronics', brand: 'Apple' },
        { eventId: 'e3', type: 'search', timestamp: now - 200, searchQuery: 'iphone' },
        { eventId: 'e4', type: 'purchase', timestamp: now - 100, productId: 'p1', totalValue: 999, category: 'Electronics' },
      ];
  
      // 1. Validate events
      const valid = filterValidEvents(events, now);
      expect(valid.length).toBe(4);
  
      // 2. Aggregate scores
      const { categoryScores, brandScores } = aggregateAllScores(valid);
      expect(categoryScores.get('Electronics')).toBe(17); // 2 + 5 + 10
      expect(brandScores.get('Apple')).toBe(7); // 2 + 5
  
      // 3. Extract recent products
      const recent = extractRecentProducts(valid);
      expect(recent.length).toBe(2); // view and addToCart
  
      // 4. Extract purchase stats
      const purchaseStats = extractPurchaseStats(valid);
      expect(purchaseStats.count).toBe(1);
      expect(purchaseStats.totalValue).toBe(999);
  
      // 5. Extract searches
      const searches = extractSearchQueries(valid);
      expect(searches).toEqual(['iphone']);
    });
  
    test('preference computation with pruning', () => {
      // Simulate accumulated scores
      const categoryScores = {};
      for (let i = 0; i < 150; i++) {
        categoryScores[`Category${i}`] = 150 - i;
      }
  
      // Prune to top 100 with min score 5
      const pruned = pruneCategoryScores(categoryScores);
  
      expect(Object.keys(pruned).length).toBeLessThanOrEqual(100);
  
      // Get top 10
      const map = new Map(Object.entries(pruned));
      const top = getTopCategories(map, 10);
  
      expect(top.length).toBe(10);
      expect(top[0].category).toBe('Category0');
      expect(top[0].score).toBe(150);
    });
  });
