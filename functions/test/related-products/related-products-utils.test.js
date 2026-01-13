// functions/test/related-products/related-products-utils.test.js
//
// Unit tests for related products rebuild utility functions
// Tests the EXACT logic from related products cloud functions
//
// Run: npx jest test/related-products/related-products-utils.test.js

const {
    DEFAULT_BATCH_SIZE,
    DEFAULT_CONCURRENCY,
    MAX_CONSECUTIVE_ERRORS,

    DAYS_BEFORE_REFRESH,
    MAX_RELATED_PRODUCTS,
    ERROR_RATE_THRESHOLD,
    SCORE_WEIGHTS,
  
    cleanAlgoliaId,
    cleanAlgoliaIds,
    hasAlgoliaPrefix,
  
    validateProductForRelated,
    isValidForRelatedProducts,
  
    shouldSkipProduct,
    getDaysSinceUpdate,
  
    buildPrimaryFilter,
    buildSubsubcategoryFilter,
    buildPriceRangeFilter,
    getPriceRange,
  
    addProduct,
    createProductEntry,

  
    calculateFinalScore,
    calculatePriceDifference,
    getPriceBonus,
    getBaseScoreForMatch,
  
    rankAndLimitProducts,
    needsMoreProducts,
  
    shouldTriggerCircuitBreaker,
    calculateErrorRate,
    isErrorRateAcceptable,
    getRetryDelay,
    shouldRetry,
  
    buildCheckpointData,
    hasCheckpoint,
  
    buildRelatedProductsUpdate,
    buildLogEntry,

    calculateDuration,
    formatDuration,
    buildSummary,
  
    filterSelfFromHits,
    extractHitIds,
  } = require('./related-products-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('DEFAULT_BATCH_SIZE is 50', () => {
      expect(DEFAULT_BATCH_SIZE).toBe(50);
    });
  
    test('DEFAULT_CONCURRENCY is 20', () => {
      expect(DEFAULT_CONCURRENCY).toBe(20);
    });
  
    test('MAX_CONSECUTIVE_ERRORS is 3', () => {
      expect(MAX_CONSECUTIVE_ERRORS).toBe(3);
    });
  
    test('DAYS_BEFORE_REFRESH is 7', () => {
      expect(DAYS_BEFORE_REFRESH).toBe(7);
    });
  
    test('MAX_RELATED_PRODUCTS is 20', () => {
      expect(MAX_RELATED_PRODUCTS).toBe(20);
    });
  
    test('ERROR_RATE_THRESHOLD is 0.1', () => {
      expect(ERROR_RATE_THRESHOLD).toBe(0.1);
    });
  
    test('SCORE_WEIGHTS has all values', () => {
      expect(SCORE_WEIGHTS.PRIMARY_WITH_GENDER).toBe(100);
      expect(SCORE_WEIGHTS.PRIMARY_WITHOUT_GENDER).toBe(80);
      expect(SCORE_WEIGHTS.SUBSUBCATEGORY_MATCH).toBe(60);
      expect(SCORE_WEIGHTS.PRICE_RANGE_MATCH).toBe(40);
    });
  });
  
  // ============================================================================
  // ID CLEANING TESTS
  // ============================================================================
  describe('cleanAlgoliaId', () => {
    test('removes shop_products_ prefix', () => {
      expect(cleanAlgoliaId('shop_products_abc123')).toBe('abc123');
    });
  
    test('removes products_ prefix', () => {
      expect(cleanAlgoliaId('products_xyz789')).toBe('xyz789');
    });
  
    test('returns unchanged if no prefix', () => {
      expect(cleanAlgoliaId('abc123')).toBe('abc123');
    });
  
    test('handles null', () => {
      expect(cleanAlgoliaId(null)).toBe(null);
    });
  
    test('handles non-string', () => {
      expect(cleanAlgoliaId(123)).toBe(123);
    });
  });
  
  describe('cleanAlgoliaIds', () => {
    test('cleans array of IDs', () => {
      const ids = ['shop_products_a', 'products_b', 'c'];
      expect(cleanAlgoliaIds(ids)).toEqual(['a', 'b', 'c']);
    });
  
    test('returns empty array for non-array', () => {
      expect(cleanAlgoliaIds(null)).toEqual([]);
    });
  });
  
  describe('hasAlgoliaPrefix', () => {
    test('returns true for prefixed ID', () => {
      expect(hasAlgoliaPrefix('shop_products_abc')).toBe(true);
      expect(hasAlgoliaPrefix('products_abc')).toBe(true);
    });
  
    test('returns false for clean ID', () => {
      expect(hasAlgoliaPrefix('abc123')).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(hasAlgoliaPrefix(null)).toBe(false);
    });
  });
  
  // ============================================================================
  // VALIDATION TESTS
  // ============================================================================
  describe('validateProductForRelated', () => {
    test('returns valid for complete product', () => {
      const product = { category: 'Electronics', subcategory: 'Phones', price: 100 };
      expect(validateProductForRelated(product).isValid).toBe(true);
    });
  
    test('returns invalid for missing category', () => {
      const product = { subcategory: 'Phones', price: 100 };
      const result = validateProductForRelated(product);
      expect(result.isValid).toBe(false);
      expect(result.errors).toContain('Missing category');
    });
  
    test('returns invalid for missing subcategory', () => {
      const product = { category: 'Electronics', price: 100 };
      const result = validateProductForRelated(product);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for invalid price', () => {
      const product = { category: 'Electronics', subcategory: 'Phones', price: 0 };
      const result = validateProductForRelated(product);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for null', () => {
      expect(validateProductForRelated(null).isValid).toBe(false);
    });
  });
  
  describe('isValidForRelatedProducts', () => {
    test('returns true for valid', () => {
      expect(isValidForRelatedProducts({ category: 'A', subcategory: 'B', price: 50 })).toBe(true);
    });
  
    test('returns false for invalid', () => {
      expect(isValidForRelatedProducts({})).toBe(false);
    });
  });
  
  // ============================================================================
  // SKIP LOGIC TESTS
  // ============================================================================
  describe('shouldSkipProduct', () => {
    const now = Date.now();
    const threeDaysAgo = new Date(now - 3 * 24 * 60 * 60 * 1000);
    const tenDaysAgo = new Date(now - 10 * 24 * 60 * 60 * 1000);
  
    test('returns true if updated recently', () => {
      const product = { relatedLastUpdated: { toDate: () => threeDaysAgo } };
      expect(shouldSkipProduct(product, 7, now)).toBe(true);
    });
  
    test('returns false if updated long ago', () => {
      const product = { relatedLastUpdated: { toDate: () => tenDaysAgo } };
      expect(shouldSkipProduct(product, 7, now)).toBe(false);
    });
  
    test('returns false if never updated', () => {
      expect(shouldSkipProduct({}, 7, now)).toBe(false);
    });
  });
  
  describe('getDaysSinceUpdate', () => {
    test('calculates days correctly', () => {
      const now = Date.now();
      const fiveDaysAgo = new Date(now - 5 * 24 * 60 * 60 * 1000);
      const days = getDaysSinceUpdate({ toDate: () => fiveDaysAgo }, now);
      expect(days).toBeCloseTo(5, 0);
    });
  
    test('returns Infinity for null', () => {
      expect(getDaysSinceUpdate(null)).toBe(Infinity);
    });
  });
  
  // ============================================================================
  // FILTER BUILDING TESTS
  // ============================================================================
  describe('buildPrimaryFilter', () => {
    test('builds filter without gender', () => {
      const filter = buildPrimaryFilter('Electronics', 'Phones', null);
      expect(filter).toBe('category:"Electronics" AND subcategory:"Phones"');
    });
  
    test('builds filter with gender', () => {
      const filter = buildPrimaryFilter('Clothing', 'Shirts', 'male');
      expect(filter).toContain('gender:"male"');
    });
  
    test('returns null for missing category', () => {
      expect(buildPrimaryFilter(null, 'Phones', null)).toBe(null);
    });
  });
  
  describe('buildSubsubcategoryFilter', () => {
    test('builds correct filter', () => {
      const filter = buildSubsubcategoryFilter('Electronics', 'Smartphones');
      expect(filter).toBe('category:"Electronics" AND subsubcategory:"Smartphones"');
    });
  
    test('returns null for missing params', () => {
      expect(buildSubsubcategoryFilter(null, 'Smartphones')).toBe(null);
    });
  });
  
  describe('buildPriceRangeFilter', () => {
    test('builds correct filter', () => {
      const filter = buildPriceRangeFilter('Electronics', 100, 0.3);
      expect(filter).toContain('category:"Electronics"');
      expect(filter).toContain('price:70 TO 130');
    });
  
    test('returns null for invalid price', () => {
      expect(buildPriceRangeFilter('Electronics', 0, 0.3)).toBe(null);
    });
  });
  
  describe('getPriceRange', () => {
    test('calculates range correctly', () => {
      const range = getPriceRange(100, 0.3);
      expect(range.min).toBe(70);
      expect(range.max).toBe(130);
    });
  
    test('returns null for invalid price', () => {
      expect(getPriceRange(0)).toBe(null);
    });
  });
  
  // ============================================================================
  // PRODUCT MAP TESTS
  // ============================================================================
  describe('addProduct', () => {
    test('adds new product to map', () => {
      const map = new Map();
      const hit = { objectID: 'prod1', promotionScore: 10, price: 100 };
      addProduct(map, hit, 80);
      
      expect(map.has('prod1')).toBe(true);
      expect(map.get('prod1').baseScore).toBe(80);
      expect(map.get('prod1').matchCount).toBe(1);
    });
  
    test('updates existing product with higher score', () => {
      const map = new Map();
      const hit = { objectID: 'prod1', promotionScore: 10, price: 100 };
      
      addProduct(map, hit, 60);
      addProduct(map, hit, 80);
      
      expect(map.get('prod1').baseScore).toBe(80);
      expect(map.get('prod1').matchCount).toBe(2);
    });
  
    test('keeps higher score', () => {
      const map = new Map();
      const hit = { objectID: 'prod1', price: 100 };
      
      addProduct(map, hit, 80);
      addProduct(map, hit, 60); // Lower score
      
      expect(map.get('prod1').baseScore).toBe(80); // Should keep 80
    });
  });
  
  describe('createProductEntry', () => {
    test('creates entry with defaults', () => {
      const hit = { objectID: 'p1', promotionScore: 5, price: 50 };
      const entry = createProductEntry(hit, 100);
      
      expect(entry.baseScore).toBe(100);
      expect(entry.promotionScore).toBe(5);
      expect(entry.matchCount).toBe(1);
    });
  });
  
  // ============================================================================
  // SCORING TESTS
  // ============================================================================
  describe('calculateFinalScore', () => {
    test('calculates base score', () => {
      const data = { baseScore: 80, matchCount: 1, promotionScore: 0, price: 100 };
      const original = { price: 100 };
      const score = calculateFinalScore(data, original);
      
      // 80 + 10 (match) + 0 (promo) + 15 (price close)
      expect(score).toBe(105);
    });
  
    test('adds match count bonus', () => {
      const data = { baseScore: 80, matchCount: 3, promotionScore: 0, price: 100 };
      const original = { price: 100 };
      const score = calculateFinalScore(data, original);
      
      // 80 + 30 (3 matches * 10) + 15 (price)
      expect(score).toBe(125);
    });
  
    test('adds promotion score bonus', () => {
      const data = { baseScore: 80, matchCount: 1, promotionScore: 100, price: 100 };
      const original = { price: 100 };
      const score = calculateFinalScore(data, original);
      
      // 80 + 10 + 50 (100 * 0.5) + 15
      expect(score).toBe(155);
    });
  
    test('adds medium price bonus for 30% diff', () => {
      const data = { baseScore: 80, matchCount: 1, promotionScore: 0, price: 130 };
      const original = { price: 100 };
      const score = calculateFinalScore(data, original);
      
      // 80 + 10 + 0 + 5 (30% diff)
      expect(score).toBe(95);
    });
  
    test('no price bonus for large diff', () => {
      const data = { baseScore: 80, matchCount: 1, promotionScore: 0, price: 200 };
      const original = { price: 100 };
      const score = calculateFinalScore(data, original);
      
      // 80 + 10 + 0 + 0 (100% diff)
      expect(score).toBe(90);
    });
  });
  
  describe('calculatePriceDifference', () => {
    test('calculates correct difference', () => {
      expect(calculatePriceDifference(100, 120)).toBeCloseTo(0.2, 2);
      expect(calculatePriceDifference(100, 80)).toBeCloseTo(0.2, 2);
    });
  
    test('returns 1 for invalid price', () => {
      expect(calculatePriceDifference(0, 100)).toBe(1);
    });
  });
  
  describe('getPriceBonus', () => {
    test('returns 15 for < 20% diff', () => {
      expect(getPriceBonus(0.1)).toBe(15);
    });
  
    test('returns 5 for < 40% diff', () => {
      expect(getPriceBonus(0.3)).toBe(5);
    });
  
    test('returns 0 for >= 40% diff', () => {
      expect(getPriceBonus(0.5)).toBe(0);
    });
  });
  
  describe('getBaseScoreForMatch', () => {
    test('returns correct scores', () => {
      expect(getBaseScoreForMatch('primary', true)).toBe(100);
      expect(getBaseScoreForMatch('primary', false)).toBe(80);
      expect(getBaseScoreForMatch('subsubcategory')).toBe(60);
      expect(getBaseScoreForMatch('price_range')).toBe(40);
      expect(getBaseScoreForMatch('unknown')).toBe(0);
    });
  });
  
  // ============================================================================
  // RANKING TESTS
  // ============================================================================
  describe('rankAndLimitProducts', () => {
    test('ranks products by score', () => {
      const map = new Map();
      map.set('p1', { baseScore: 60, matchCount: 1, promotionScore: 0, price: 100 });
      map.set('p2', { baseScore: 100, matchCount: 1, promotionScore: 0, price: 100 });
      map.set('p3', { baseScore: 80, matchCount: 1, promotionScore: 0, price: 100 });
  
      const ranked = rankAndLimitProducts(map, { price: 100 });
      
      expect(ranked[0]).toBe('p2'); // Highest score
      expect(ranked[1]).toBe('p3');
      expect(ranked[2]).toBe('p1');
    });
  
    test('limits to maxProducts', () => {
      const map = new Map();
      for (let i = 0; i < 30; i++) {
        map.set(`p${i}`, { baseScore: i, matchCount: 1, promotionScore: 0, price: 100 });
      }
  
      const ranked = rankAndLimitProducts(map, { price: 100 }, 20);
      expect(ranked.length).toBe(20);
    });
  
    test('returns empty array for empty map', () => {
      expect(rankAndLimitProducts(new Map(), { price: 100 })).toEqual([]);
    });
  });
  
  describe('needsMoreProducts', () => {
    test('returns true when under target', () => {
      expect(needsMoreProducts(10, 20)).toBe(true);
    });
  
    test('returns false when at target', () => {
      expect(needsMoreProducts(20, 20)).toBe(false);
    });
  });
  
  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  describe('shouldTriggerCircuitBreaker', () => {
    test('returns true at max errors', () => {
      expect(shouldTriggerCircuitBreaker(3, 3)).toBe(true);
    });
  
    test('returns false under max', () => {
      expect(shouldTriggerCircuitBreaker(2, 3)).toBe(false);
    });
  });
  
  describe('calculateErrorRate', () => {
    test('calculates rate correctly', () => {
      expect(calculateErrorRate(10, 100)).toBe(0.1);
    });
  
    test('returns 0 for no processed', () => {
      expect(calculateErrorRate(5, 0)).toBe(0);
    });
  });
  
  describe('isErrorRateAcceptable', () => {
    test('returns true for acceptable rate', () => {
      expect(isErrorRateAcceptable(5, 100, 0.1)).toBe(true);
    });
  
    test('returns false for high rate', () => {
      expect(isErrorRateAcceptable(20, 100, 0.1)).toBe(false);
    });
  });
  
  describe('getRetryDelay', () => {
    test('returns exponential backoff', () => {
      expect(getRetryDelay(1)).toBe(1000);
      expect(getRetryDelay(2)).toBe(2000);
      expect(getRetryDelay(3)).toBe(4000);
    });
  });
  
  describe('shouldRetry', () => {
    test('returns true under max', () => {
      expect(shouldRetry(2, 3)).toBe(true);
    });
  
    test('returns false at max', () => {
      expect(shouldRetry(3, 3)).toBe(false);
    });
  });
  
  // ============================================================================
  // CHECKPOINT TESTS
  // ============================================================================
  describe('buildCheckpointData', () => {
    test('builds checkpoint', () => {
      const data = buildCheckpointData('doc123');
      expect(data.lastProcessedId).toBe('doc123');
    });
  });
  
  describe('hasCheckpoint', () => {
    test('returns truthy for valid checkpoint', () => {
      expect(hasCheckpoint({ lastProcessedId: 'doc123' })).toBeTruthy();
    });
  
    test('returns falsy for null', () => {
      expect(hasCheckpoint(null)).toBeFalsy();
    });
  });
  
  // ============================================================================
  // RESULT BUILDING TESTS
  // ============================================================================
  describe('buildRelatedProductsUpdate', () => {
    test('builds update object', () => {
      const ids = ['p1', 'p2', 'p3'];
      const update = buildRelatedProductsUpdate(ids);
      
      expect(update.relatedProductIds).toEqual(ids);
      expect(update.relatedCount).toBe(3);
    });
  });
  
  describe('buildLogEntry', () => {
    test('builds log entry', () => {
      const entry = buildLogEntry('rebuild', 100, 20, 5, 60.123);
      
      expect(entry.type).toBe('rebuild');
      expect(entry.processed).toBe(100);
      expect(entry.duration).toBe(60.12);
    });
  });
  
  // ============================================================================
  // STATISTICS TESTS
  // ============================================================================
  describe('calculateDuration', () => {
    test('calculates duration in seconds', () => {
      const start = Date.now() - 5000;
      const duration = calculateDuration(start);
      expect(duration).toBeGreaterThanOrEqual(4.9);
      expect(duration).toBeLessThanOrEqual(5.5);
    });
  });
  
  describe('formatDuration', () => {
    test('formats to 2 decimal places', () => {
      expect(formatDuration(60.1234)).toBe('60.12');
    });
  });
  
  describe('buildSummary', () => {
    test('builds complete summary', () => {
      const summary = buildSummary(100, 20, 5, 60);
      
      expect(summary.processed).toBe(100);
      expect(summary.skipped).toBe(20);
      expect(summary.errors).toBe(5);
      expect(summary.total).toBe(125);
      expect(summary.successRate).toBe('95.0');
    });
  });
  
  // ============================================================================
  // HIT FILTERING TESTS
  // ============================================================================
  describe('filterSelfFromHits', () => {
    test('filters out current product', () => {
      const hits = [
        { objectID: 'shop_products_prod1' },
        { objectID: 'shop_products_prod2' },
        { objectID: 'prod3' },
      ];
      const filtered = filterSelfFromHits(hits, 'prod1');
      
      expect(filtered.length).toBe(2);
      expect(filtered.some((h) => cleanAlgoliaId(h.objectID) === 'prod1')).toBe(false);
    });
  
    test('handles empty array', () => {
      expect(filterSelfFromHits([], 'prod1')).toEqual([]);
    });
  });
  
  describe('extractHitIds', () => {
    test('extracts objectIDs', () => {
      const hits = [{ objectID: 'a' }, { objectID: 'b' }];
      expect(extractHitIds(hits)).toEqual(['a', 'b']);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete related products build flow', () => {
      const product = {
        category: 'Electronics',
        subcategory: 'Phones',
        subsubcategory: 'Smartphones',
        gender: null,
        price: 500,
      };
  
      // 1. Validate product
      expect(isValidForRelatedProducts(product)).toBe(true);
  
      // 2. Build filters
      const primaryFilter = buildPrimaryFilter(product.category, product.subcategory, product.gender);
      expect(primaryFilter).toContain('Electronics');
  
      // 3. Build product map with hits
      const map = new Map();
      const hits = [
        { objectID: 'p1', promotionScore: 50, price: 480 },
        { objectID: 'p2', promotionScore: 10, price: 600 },
        { objectID: 'p3', promotionScore: 0, price: 450 },
      ];
  
      hits.forEach((hit) => addProduct(map, hit, 80));
  
      // 4. Rank products
      const ranked = rankAndLimitProducts(map, product, 20);
      expect(ranked.length).toBe(3);
  
      // 5. Clean IDs
      const cleaned = cleanAlgoliaIds(ranked);
      expect(cleaned.every((id) => !hasAlgoliaPrefix(id))).toBe(true);
  
      // 6. Build update
      const update = buildRelatedProductsUpdate(cleaned);
      expect(update.relatedCount).toBe(3);
    });
  
    test('circuit breaker and retry flow', () => {
      let consecutiveErrors = 0;
  
      // First error
      consecutiveErrors++;
      expect(shouldTriggerCircuitBreaker(consecutiveErrors)).toBe(false);
      expect(shouldRetry(1)).toBe(true);
      expect(getRetryDelay(1)).toBe(1000);
  
      // Second error
      consecutiveErrors++;
      expect(shouldTriggerCircuitBreaker(consecutiveErrors)).toBe(false);
  
      // Third error - circuit breaker
      consecutiveErrors++;
      expect(shouldTriggerCircuitBreaker(consecutiveErrors)).toBe(true);
  
      // Error rate check
      expect(isErrorRateAcceptable(5, 100)).toBe(true);
      expect(isErrorRateAcceptable(15, 100)).toBe(false);
    });
  });
