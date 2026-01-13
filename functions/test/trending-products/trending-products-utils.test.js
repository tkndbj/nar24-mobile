// functions/test/trending-products/trending-products-utils.test.js
//
// Unit tests for trending products utility functions
// Tests the EXACT logic from trending products cloud functions
//
// Run: npx jest test/trending-products/trending-products-utils.test.js

const {
    CONFIG,
    WEIGHTS,
  
    validateWeights,
    getWeightSum,
  
    normalize,

  
    calculateRecencyBoost,
    calculateDaysOld,

  
    calculateStats,
  
    calculateTrendingScore,

  
    meetsEngagementThreshold,
    filterEligibleProducts,
  
    rankProducts,
    getTopProducts,
  
    sanitizeCategoryKey,
    groupProductsByCategory,
  
    shouldUseCache,
    getHoursSinceUpdate,
  
    generateLookbackDates,
    getVersionString,
  
    mergePurchaseCounts,
    enrichProductsWithPurchases,
  
    buildTrendingOutput,
    buildStatsOutput,
    calculateAverageScore,
  
    getRetryDelay,
    shouldRetryError,
  
    getCleanupCutoffDate,
  } = require('./trending-products-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('CONFIG has correct values', () => {
      expect(CONFIG.TOP_PRODUCTS_COUNT).toBe(200);
      expect(CONFIG.LOOKBACK_DAYS).toBe(7);
      expect(CONFIG.MIN_ENGAGEMENT_THRESHOLD).toBe(5);
    });
  
    test('WEIGHTS has all components', () => {
      expect(WEIGHTS.CLICKS).toBe(0.30);
      expect(WEIGHTS.CART_ADDITIONS).toBe(0.25);
      expect(WEIGHTS.FAVORITES).toBe(0.20);
      expect(WEIGHTS.PURCHASES).toBe(0.15);
      expect(WEIGHTS.RECENCY).toBe(0.10);
    });
  
    test('WEIGHTS sum to 1.0', () => {
      const sum = getWeightSum();
      expect(sum).toBeCloseTo(1.0, 5);
    });
  });
  
  describe('validateWeights', () => {
    test('returns valid for correct weights', () => {
      const result = validateWeights(WEIGHTS);
      expect(result.isValid).toBe(true);
      expect(result.sum).toBeCloseTo(1.0, 3);
    });
  
    test('returns invalid for wrong sum', () => {
      const badWeights = { A: 0.5, B: 0.3 };
      const result = validateWeights(badWeights);
      expect(result.isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // NORMALIZATION TESTS
  // ============================================================================
  describe('normalize', () => {
    test('normalizes to 0-1 range', () => {
      expect(normalize(50, 0, 100)).toBe(0.5);
      expect(normalize(0, 0, 100)).toBe(0);
      expect(normalize(100, 0, 100)).toBe(1);
    });
  
    test('returns 0.5 when min equals max', () => {
      expect(normalize(50, 50, 50)).toBe(0.5);
    });
  
    test('clamps values outside range', () => {
      expect(normalize(-10, 0, 100)).toBe(0);
      expect(normalize(150, 0, 100)).toBe(1);
    });
  
    test('handles negative ranges', () => {
      expect(normalize(0, -100, 100)).toBe(0.5);
    });
  });
  
  // ============================================================================
  // RECENCY TESTS
  // ============================================================================
  describe('calculateRecencyBoost', () => {
    test('returns 1.0 for brand new products', () => {
      expect(calculateRecencyBoost(0)).toBe(1.0);
    });
  
    test('returns 1.0 for future dates', () => {
      expect(calculateRecencyBoost(-5)).toBe(1.0);
    });
  
    test('decays over time', () => {
      const day0 = calculateRecencyBoost(0);
      const day7 = calculateRecencyBoost(7);
      const day30 = calculateRecencyBoost(30);
      const day60 = calculateRecencyBoost(60);
  
      expect(day7).toBeLessThan(day0);
      expect(day30).toBeLessThan(day7);
      expect(day60).toBeLessThan(day30);
    });
  
    test('returns 0.5 at 30 days', () => {
      expect(calculateRecencyBoost(30)).toBe(0.5);
    });
  });
  
  describe('calculateDaysOld', () => {
    test('calculates days correctly', () => {
      const now = Date.now();
      const sevenDaysAgo = now - (7 * 24 * 60 * 60 * 1000);
      
      const days = calculateDaysOld(sevenDaysAgo, now);
      expect(days).toBeCloseTo(7, 1);
    });
  
    test('handles Date objects', () => {
      const now = Date.now();
      const date = new Date(now - (3 * 24 * 60 * 60 * 1000));
      
      const days = calculateDaysOld(date, now);
      expect(days).toBeCloseTo(3, 1);
    });
  });
  
  // ============================================================================
  // STATS CALCULATION TESTS
  // ============================================================================
  describe('calculateStats', () => {
    test('calculates min/max for all metrics', () => {
      const products = [
        { clicks: 10, cartCount: 5, favoritesCount: 3, purchaseCount: 1 },
        { clicks: 50, cartCount: 20, favoritesCount: 15, purchaseCount: 5 },
        { clicks: 30, cartCount: 10, favoritesCount: 8, purchaseCount: 2 },
      ];
  
      const stats = calculateStats(products);
  
      expect(stats.minClicks).toBe(10);
      expect(stats.maxClicks).toBe(50);
      expect(stats.minCart).toBe(5);
      expect(stats.maxCart).toBe(20);
      expect(stats.minFavorites).toBe(3);
      expect(stats.maxFavorites).toBe(15);
      expect(stats.minPurchases).toBe(1);
      expect(stats.maxPurchases).toBe(5);
    });
  
    test('returns zeros for empty array', () => {
      const stats = calculateStats([]);
      expect(stats.minClicks).toBe(0);
      expect(stats.maxClicks).toBe(0);
    });
  
    test('handles missing properties', () => {
      const products = [{ clicks: 10 }, { cartCount: 5 }];
      const stats = calculateStats(products);
      
      expect(stats.minClicks).toBe(0);
      expect(stats.maxClicks).toBe(10);
    });
  });
  
  // ============================================================================
  // TRENDING SCORE TESTS
  // ============================================================================
  describe('calculateTrendingScore', () => {
    const stats = {
      minClicks: 0, maxClicks: 100,
      minCart: 0, maxCart: 50,
      minFavorites: 0, maxFavorites: 30,
      minPurchases: 0, maxPurchases: 20,
    };
  
    test('calculates weighted score', () => {
      const product = {
        clicks: 50,
        cartCount: 25,
        favoritesCount: 15,
        purchaseCount: 10,
        createdAt: new Date(),
      };
  
      const result = calculateTrendingScore(product, stats);
  
      expect(result.score).toBeGreaterThan(0);
      expect(result.score).toBeLessThanOrEqual(1);
      expect(result.breakdown).toBeDefined();
    });
  
    test('returns breakdown with all components', () => {
      const product = {
        clicks: 100,
        cartCount: 50,
        favoritesCount: 30,
        purchaseCount: 20,
        createdAt: new Date(),
      };
  
      const result = calculateTrendingScore(product, stats);
  
      expect(result.breakdown.clicks).toBeDefined();
      expect(result.breakdown.cart).toBeDefined();
      expect(result.breakdown.favorites).toBeDefined();
      expect(result.breakdown.purchases).toBeDefined();
      expect(result.breakdown.recency).toBeDefined();
    });
  
    test('max engagement gives high score', () => {
      const maxProduct = {
        clicks: 100,
        cartCount: 50,
        favoritesCount: 30,
        purchaseCount: 20,
        createdAt: new Date(),
      };
  
      const minProduct = {
        clicks: 0,
        cartCount: 0,
        favoritesCount: 0,
        purchaseCount: 0,
        createdAt: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000), // 1 year old
      };
  
      const maxScore = calculateTrendingScore(maxProduct, stats).score;
      const minScore = calculateTrendingScore(minProduct, stats).score;
  
      expect(maxScore).toBeGreaterThan(minScore);
    });
  });
  
  // ============================================================================
  // PRODUCT FILTERING TESTS
  // ============================================================================
  describe('meetsEngagementThreshold', () => {
    test('returns true when above threshold', () => {
      expect(meetsEngagementThreshold({ clicks: 10 }, 5)).toBe(true);
    });
  
    test('returns false when below threshold', () => {
      expect(meetsEngagementThreshold({ clicks: 3 }, 5)).toBe(false);
    });
  
    test('returns true at exactly threshold', () => {
      expect(meetsEngagementThreshold({ clicks: 5 }, 5)).toBe(true);
    });
  });
  
  describe('filterEligibleProducts', () => {
    test('filters products below threshold', () => {
      const products = [
        { id: 'p1', clicks: 10 },
        { id: 'p2', clicks: 3 },
        { id: 'p3', clicks: 5 },
      ];
  
      const eligible = filterEligibleProducts(products, 5);
  
      expect(eligible.length).toBe(2);
      expect(eligible.map((p) => p.id)).toEqual(['p1', 'p3']);
    });
  });
  
  // ============================================================================
  // RANKING TESTS
  // ============================================================================
  describe('rankProducts', () => {
    test('ranks products by score descending', () => {
      const products = [
        { id: 'p1', clicks: 10, cartCount: 5, favoritesCount: 3, purchaseCount: 1, createdAt: new Date() },
        { id: 'p2', clicks: 100, cartCount: 50, favoritesCount: 30, purchaseCount: 20, createdAt: new Date() },
        { id: 'p3', clicks: 50, cartCount: 25, favoritesCount: 15, purchaseCount: 10, createdAt: new Date() },
      ];
  
      const stats = calculateStats(products);
      const ranked = rankProducts(products, stats);
  
      expect(ranked[0].id).toBe('p2'); // Highest engagement
      expect(ranked[1].id).toBe('p3');
      expect(ranked[2].id).toBe('p1');
    });
  
    test('includes metrics in output', () => {
      const products = [
        { id: 'p1', clicks: 10, cartCount: 5, favoritesCount: 3, purchaseCount: 1, createdAt: new Date() },
      ];
  
      const stats = calculateStats(products);
      const ranked = rankProducts(products, stats);
  
      expect(ranked[0].metrics.clicks).toBe(10);
      expect(ranked[0].metrics.cart).toBe(5);
    });
  });
  
  describe('getTopProducts', () => {
    test('returns top N products', () => {
      const products = Array(300).fill(null).map((_, i) => ({
        id: `p${i}`,
        score: 300 - i,
      }));
  
      const top = getTopProducts(products, 200);
  
      expect(top.length).toBe(200);
      expect(top[0].id).toBe('p0');
    });
  
    test('returns all if less than count', () => {
      const products = [{ id: 'p1', score: 1 }];
      const top = getTopProducts(products, 200);
      expect(top.length).toBe(1);
    });
  });
  
  // ============================================================================
  // CATEGORY TESTS
  // ============================================================================
  describe('sanitizeCategoryKey', () => {
    test('replaces dots and slashes', () => {
      expect(sanitizeCategoryKey('Electronics.Phones')).toBe('Electronics_Phones');
      expect(sanitizeCategoryKey('Men/Women')).toBe('Men_Women');
    });
  
    test('returns Other for null', () => {
      expect(sanitizeCategoryKey(null)).toBe('Other');
    });
  });
  
  describe('groupProductsByCategory', () => {
    test('groups products by category', () => {
      const products = [
        { id: 'p1', category: 'Electronics' },
        { id: 'p2', category: 'Electronics' },
        { id: 'p3', category: 'Clothing' },
      ];
  
      const grouped = groupProductsByCategory(products, 50);
  
      expect(grouped.get('Electronics')).toEqual(['p1', 'p2']);
      expect(grouped.get('Clothing')).toEqual(['p3']);
    });
  
    test('limits per category', () => {
      const products = Array(100).fill(null).map((_, i) => ({
        id: `p${i}`,
        category: 'Electronics',
      }));
  
      const grouped = groupProductsByCategory(products, 50);
  
      expect(grouped.get('Electronics').length).toBe(50);
    });
  });
  
  // ============================================================================
  // CACHE TESTS
  // ============================================================================
  describe('shouldUseCache', () => {
    test('returns true when within threshold', () => {
      const now = Date.now();
      const twoHoursAgo = now - (2 * 60 * 60 * 1000);
      
      expect(shouldUseCache(twoHoursAgo, 6, now)).toBe(true);
    });
  
    test('returns false when past threshold', () => {
      const now = Date.now();
      const sevenHoursAgo = now - (7 * 60 * 60 * 1000);
      
      expect(shouldUseCache(sevenHoursAgo, 6, now)).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(shouldUseCache(null, 6)).toBe(false);
    });
  });
  
  describe('getHoursSinceUpdate', () => {
    test('calculates hours correctly', () => {
      const now = Date.now();
      const threeHoursAgo = now - (3 * 60 * 60 * 1000);
      
      const hours = getHoursSinceUpdate(threeHoursAgo, now);
      expect(hours).toBeCloseTo(3, 1);
    });
  
    test('returns Infinity for null', () => {
      expect(getHoursSinceUpdate(null)).toBe(Infinity);
    });
  });
  
  // ============================================================================
  // DATE HELPERS TESTS
  // ============================================================================
  describe('generateLookbackDates', () => {
    test('generates correct number of dates', () => {
      const dates = generateLookbackDates(7);
      expect(dates.length).toBe(7);
    });
  
    test('starts with today', () => {
      const now = new Date('2024-06-15');
      const dates = generateLookbackDates(3, now);
      
      expect(dates[0]).toBe('2024-06-15');
      expect(dates[1]).toBe('2024-06-14');
      expect(dates[2]).toBe('2024-06-13');
    });
  });
  
  describe('getVersionString', () => {
    test('returns YYYY-MM-DD format', () => {
      const date = new Date('2024-06-15T10:30:00Z');
      expect(getVersionString(date)).toBe('2024-06-15');
    });
  });
  
  // ============================================================================
  // PURCHASE AGGREGATION TESTS
  // ============================================================================
  describe('mergePurchaseCounts', () => {
    test('merges multiple maps', () => {
      const map1 = new Map([['p1', 5], ['p2', 3]]);
      const map2 = new Map([['p1', 2], ['p3', 1]]);
  
      const merged = mergePurchaseCounts([map1, map2]);
  
      expect(merged.get('p1')).toBe(7);
      expect(merged.get('p2')).toBe(3);
      expect(merged.get('p3')).toBe(1);
    });
  });
  
  describe('enrichProductsWithPurchases', () => {
    test('adds purchase counts to products', () => {
      const products = [
        { id: 'p1', clicks: 10 },
        { id: 'p2', clicks: 20 },
      ];
      const purchases = new Map([['p1', 5]]);
  
      const enriched = enrichProductsWithPurchases(products, purchases);
  
      expect(enriched[0].purchaseCount).toBe(5);
      expect(enriched[1].purchaseCount).toBe(0);
    });
  });
  
  // ============================================================================
  // OUTPUT BUILDING TESTS
  // ============================================================================
  describe('buildTrendingOutput', () => {
    test('extracts ids and scores', () => {
      const products = [
        { id: 'p1', score: 0.9 },
        { id: 'p2', score: 0.8 },
      ];
  
      const output = buildTrendingOutput(products);
  
      expect(output.products).toEqual(['p1', 'p2']);
      expect(output.scores).toEqual([0.9, 0.8]);
    });
  });
  
  describe('buildStatsOutput', () => {
    test('builds complete stats', () => {
      const stats = buildStatsOutput(1000, 5000, 200, 1500, 0.654, false);
  
      expect(stats.totalCandidates).toBe(1000);
      expect(stats.totalProcessed).toBe(5000);
      expect(stats.topCount).toBe(200);
      expect(stats.computationTimeMs).toBe(1500);
      expect(stats.avgTrendScore).toBe(0.654);
      expect(stats.cached).toBe(false);
    });
  });
  
  describe('calculateAverageScore', () => {
    test('calculates average', () => {
      const products = [
        { score: 0.8 },
        { score: 0.6 },
        { score: 0.4 },
      ];
  
      expect(calculateAverageScore(products)).toBeCloseTo(0.6, 3);
    });
  
    test('returns 0 for empty', () => {
      expect(calculateAverageScore([])).toBe(0);
    });
  });
  
  // ============================================================================
  // RETRY TESTS
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
    });
  });
  
  // ============================================================================
  // CLEANUP TESTS
  // ============================================================================
  describe('getCleanupCutoffDate', () => {
    test('returns date N days ago', () => {
      const now = new Date('2024-06-15');
      const cutoff = getCleanupCutoffDate(7, now);
      
      expect(cutoff.toISOString().split('T')[0]).toBe('2024-06-08');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete trending calculation flow', () => {
      const now = Date.now();
      
      // 1. Sample products
      const products = [
        { id: 'p1', clicks: 100, cartCount: 50, favoritesCount: 30, purchaseCount: 20, createdAt: new Date(now - 1 * 24 * 60 * 60 * 1000) },
        { id: 'p2', clicks: 80, cartCount: 40, favoritesCount: 25, purchaseCount: 15, createdAt: new Date(now - 7 * 24 * 60 * 60 * 1000) },
        { id: 'p3', clicks: 50, cartCount: 20, favoritesCount: 10, purchaseCount: 5, createdAt: new Date(now - 30 * 24 * 60 * 60 * 1000) },
        { id: 'p4', clicks: 3, cartCount: 1, favoritesCount: 1, purchaseCount: 0, createdAt: new Date() }, // Below threshold
      ];
  
      // 2. Filter eligible
      const eligible = filterEligibleProducts(products, 5);
      expect(eligible.length).toBe(3);
  
      // 3. Calculate stats
      const stats = calculateStats(eligible);
      expect(stats.maxClicks).toBe(100);
  
      // 4. Rank products
      const ranked = rankProducts(eligible, stats);
      
      // p1 should be first (highest engagement + newest)
      expect(ranked[0].id).toBe('p1');
  
      // 5. Build output
      const output = buildTrendingOutput(ranked);
      expect(output.products.length).toBe(3);
    });
  
    test('recency affects ranking', () => {
      const now = Date.now();
      
      // Same engagement, different ages
      const products = [
        { id: 'old', clicks: 50, cartCount: 25, favoritesCount: 15, purchaseCount: 10, createdAt: new Date(now - 60 * 24 * 60 * 60 * 1000) },
        { id: 'new', clicks: 50, cartCount: 25, favoritesCount: 15, purchaseCount: 10, createdAt: new Date(now - 1 * 24 * 60 * 60 * 1000) },
      ];
  
      const stats = calculateStats(products);
      const ranked = rankProducts(products, stats);
  
      // Newer product should rank higher
      expect(ranked[0].id).toBe('new');
    });
  });
