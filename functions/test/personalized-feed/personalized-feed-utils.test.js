// functions/test/personalized-feed/personalized-feed-utils.test.js
//
// Unit tests for personalized feed utility functions
// Tests the EXACT logic from personalized feed cloud functions
//
// Run: npx jest test/personalized-feed/personalized-feed-utils.test.js

const {
    CONFIG,
    BASE_WEIGHTS,
    PERSONALIZATION_CONFIG,
  
    validateWeights,
    getBaseWeightSum,
  
    calculatePersonalizationStrength,
    isFullyPersonalized,
    hasMinimumActivity,
  
    calculateDynamicWeights,
  

    calculateCategoryMatch,

  
    calculateBrandMatch,

  
    calculatePriceMatch,
    getPriceRange,
    isInPriceRange,
  
    calculateRecencyPenalty,
    wasRecentlyViewed,
  
    scoreProduct,
    rankProducts,

  
    shouldUpdateFeed,

    isFeedStale,
    hasSignificantNewActivity,
  
    meetsActivityThreshold,
    getActivityCount,
  
    getTopCategories,
    sanitizeCategoryKey,
  
    buildFeedOutput,
    calculateAverageScore,
    getWeightsInfo,
  
    chunkArray,
  
    getRetryDelay,
    shouldRetryError,
  } = require('./personalized-feed-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('CONFIG has correct values', () => {
      expect(CONFIG.FEED_SIZE).toBe(200);
      expect(CONFIG.MIN_ACTIVITY_THRESHOLD).toBe(3);
      expect(CONFIG.REFRESH_INTERVAL_DAYS).toBe(2);
    });
  
    test('BASE_WEIGHTS sum to 1.0', () => {
      const sum = getBaseWeightSum();
      expect(sum).toBeCloseTo(1.0, 5);
    });
  
    test('PERSONALIZATION_CONFIG has thresholds', () => {
      expect(PERSONALIZATION_CONFIG.MIN_EVENTS_FOR_PERSONALIZATION).toBe(3);
      expect(PERSONALIZATION_CONFIG.FULL_PERSONALIZATION_EVENTS).toBe(50);
      expect(PERSONALIZATION_CONFIG.SUBCATEGORY_BONUS_RATIO).toBe(0.3);
    });
  });
  
  // ============================================================================
  // PERSONALIZATION STRENGTH TESTS
  // ============================================================================
  describe('calculatePersonalizationStrength', () => {
    test('returns 0 for new users', () => {
      expect(calculatePersonalizationStrength(0)).toBe(0);
      expect(calculatePersonalizationStrength(2)).toBe(0);
    });
  
    test('returns partial strength for active users', () => {
      const strength = calculatePersonalizationStrength(25);
      expect(strength).toBeGreaterThan(0);
      expect(strength).toBeLessThan(1);
    });
  
    test('returns 1.0 for fully engaged users', () => {
      expect(calculatePersonalizationStrength(50)).toBe(1.0);
      expect(calculatePersonalizationStrength(100)).toBe(1.0);
    });
  
    test('scales linearly between thresholds', () => {
      // At 3 events: 0
      // At 50 events: 1.0
      // At 26.5 events: 0.5
      const midpoint = (3 + 50) / 2; // 26.5
      const strength = calculatePersonalizationStrength(Math.round(midpoint));
      expect(strength).toBeCloseTo(0.5, 1);
    });
  });
  
  describe('isFullyPersonalized', () => {
    test('returns true at threshold', () => {
      expect(isFullyPersonalized(50)).toBe(true);
      expect(isFullyPersonalized(100)).toBe(true);
    });
  
    test('returns false below threshold', () => {
      expect(isFullyPersonalized(49)).toBe(false);
    });
  });
  
  describe('hasMinimumActivity', () => {
    test('returns true at minimum', () => {
      expect(hasMinimumActivity(3)).toBe(true);
      expect(hasMinimumActivity(10)).toBe(true);
    });
  
    test('returns false below minimum', () => {
      expect(hasMinimumActivity(2)).toBe(false);
    });
  });
  
  // ============================================================================
  // DYNAMIC WEIGHTS TESTS
  // ============================================================================
  describe('calculateDynamicWeights', () => {
    test('returns base weights for new users', () => {
      const weights = calculateDynamicWeights(0);
      
      // Weights should be normalized, close to base
      expect(weights.CATEGORY_MATCH).toBeCloseTo(BASE_WEIGHTS.CATEGORY_MATCH, 2);
      expect(weights.TRENDING_SCORE).toBeCloseTo(BASE_WEIGHTS.TRENDING_SCORE, 2);
    });
  
    test('increases category weight for engaged users', () => {
      const newUserWeights = calculateDynamicWeights(0);
      const engagedWeights = calculateDynamicWeights(50);
      
      expect(engagedWeights.CATEGORY_MATCH).toBeGreaterThan(newUserWeights.CATEGORY_MATCH);
    });
  
    test('decreases trending weight for engaged users', () => {
      const newUserWeights = calculateDynamicWeights(0);
      const engagedWeights = calculateDynamicWeights(50);
      
      expect(engagedWeights.TRENDING_SCORE).toBeLessThan(newUserWeights.TRENDING_SCORE);
    });
  
    test('weights always sum to 1.0', () => {
      for (const activityCount of [0, 10, 25, 50, 100]) {
        const weights = calculateDynamicWeights(activityCount);
        const result = validateWeights(weights);
        expect(result.isValid).toBe(true);
      }
    });
  
    test('includes personalization metadata', () => {
      const weights = calculateDynamicWeights(25);
      expect(weights._personalizationStrength).toBeDefined();
      expect(weights._activityCount).toBe(25);
    });
  });
  
  // ============================================================================
  // CATEGORY MATCHING TESTS
  // ============================================================================
  describe('calculateCategoryMatch', () => {
    test('returns 0 for no category scores', () => {
      const product = { category: 'Electronics' };
      const userProfile = { categoryScores: {} };
      
      expect(calculateCategoryMatch(product, userProfile)).toBe(0);
    });
  
    test('returns normalized score for matching category', () => {
      const product = { category: 'Electronics' };
      const userProfile = { categoryScores: { Electronics: 50, Clothing: 100 } };
      
      const match = calculateCategoryMatch(product, userProfile);
      expect(match).toBe(0.5); // 50/100
    });
  
    test('adds subcategory bonus', () => {
      const product = { category: 'Electronics', subcategory: 'Phones' };
      const userProfile = { categoryScores: { Electronics: 100, Phones: 100 } };
      
      const match = calculateCategoryMatch(product, userProfile);
      // 1.0 (category) + 0.3 (30% subcategory bonus) = 1.0 (capped)
      expect(match).toBe(1.0);
    });
  
    test('caps at 1.0', () => {
      const product = { category: 'Electronics', subcategory: 'Phones' };
      const userProfile = { categoryScores: { Electronics: 100, Phones: 100 } };
      
      expect(calculateCategoryMatch(product, userProfile)).toBeLessThanOrEqual(1.0);
    });
  
    test('returns 0 for non-matching category', () => {
      const product = { category: 'Sports' };
      const userProfile = { categoryScores: { Electronics: 100 } };
      
      expect(calculateCategoryMatch(product, userProfile)).toBe(0);
    });
  });
  
  // ============================================================================
  // BRAND MATCHING TESTS
  // ============================================================================
  describe('calculateBrandMatch', () => {
    test('returns 0 for no brand', () => {
      const product = {};
      const userProfile = { brandScores: { Apple: 100 } };
      
      expect(calculateBrandMatch(product, userProfile)).toBe(0);
    });
  
    test('returns 0 for non-matching brand', () => {
      const product = { brand: 'Samsung' };
      const userProfile = { brandScores: { Apple: 100 } };
      
      expect(calculateBrandMatch(product, userProfile)).toBe(0);
    });
  
    test('returns normalized score for matching brand', () => {
      const product = { brand: 'Apple' };
      const userProfile = { brandScores: { Apple: 50, Samsung: 100 } };
      
      expect(calculateBrandMatch(product, userProfile)).toBe(0.5);
    });
  });
  
  // ============================================================================
  // PRICE MATCHING TESTS
  // ============================================================================
  describe('calculatePriceMatch', () => {
    test('returns 0.5 for unknown price preference', () => {
      const product = { price: 100 };
      const userProfile = { preferences: {} };
      
      expect(calculatePriceMatch(product, userProfile)).toBe(0.5);
    });
  
    test('returns 1.0 for exact match', () => {
      const product = { price: 100 };
      const userProfile = { preferences: { avgPurchasePrice: 100 } };
      
      expect(calculatePriceMatch(product, userProfile)).toBe(1.0);
    });
  
    test('decreases for price difference', () => {
      const product = { price: 150 };
      const userProfile = { preferences: { avgPurchasePrice: 100 } };
      
      // 50% difference = 0.5 score
      expect(calculatePriceMatch(product, userProfile)).toBe(0.5);
    });
  
    test('returns 0 for 100%+ difference', () => {
      const product = { price: 200 };
      const userProfile = { preferences: { avgPurchasePrice: 100 } };
      
      expect(calculatePriceMatch(product, userProfile)).toBe(0);
    });
  });
  
  describe('getPriceRange', () => {
    test('calculates range correctly', () => {
      const range = getPriceRange(100, 0.5, 2.0);
      expect(range.min).toBe(50);
      expect(range.max).toBe(200);
    });
  
    test('returns max range for no avgPrice', () => {
      const range = getPriceRange(0);
      expect(range.min).toBe(0);
      expect(range.max).toBe(Number.MAX_SAFE_INTEGER);
    });
  });
  
  describe('isInPriceRange', () => {
    test('returns true for price in range', () => {
      expect(isInPriceRange(100, 100, 0.5, 2.0)).toBe(true);
      expect(isInPriceRange(50, 100, 0.5, 2.0)).toBe(true);
      expect(isInPriceRange(200, 100, 0.5, 2.0)).toBe(true);
    });
  
    test('returns false for price out of range', () => {
      expect(isInPriceRange(49, 100, 0.5, 2.0)).toBe(false);
      expect(isInPriceRange(201, 100, 0.5, 2.0)).toBe(false);
    });
  });
  
  // ============================================================================
  // RECENCY PENALTY TESTS
  // ============================================================================
  describe('calculateRecencyPenalty', () => {
    test('returns 1.0 for not recently viewed', () => {
      const product = { id: 'p1' };
      const userProfile = { recentlyViewed: [] };
      
      expect(calculateRecencyPenalty(product, userProfile)).toBe(1.0);
    });
  
    test('returns 0.5 for recently viewed', () => {
      const product = { id: 'p1' };
      const userProfile = { recentlyViewed: [{ productId: 'p1' }] };
      
      expect(calculateRecencyPenalty(product, userProfile)).toBe(0.5);
    });
  
    test('only checks last 50', () => {
      const product = { id: 'p1' };
      const recentlyViewed = Array(60).fill(null).map((_, i) => ({ productId: `other${i}` }));
      recentlyViewed[5] = { productId: 'p1' }; // Early in list (outside last 50)
      
      const userProfile = { recentlyViewed };
      expect(calculateRecencyPenalty(product, userProfile)).toBe(1.0);
    });
  });
  
  describe('wasRecentlyViewed', () => {
    test('finds product in list', () => {
      const list = [{ productId: 'p1' }, { productId: 'p2' }];
      expect(wasRecentlyViewed('p1', list)).toBe(true);
    });
  
    test('returns false for empty list', () => {
      expect(wasRecentlyViewed('p1', [])).toBe(false);
      expect(wasRecentlyViewed('p1', null)).toBe(false);
    });
  });
  
  // ============================================================================
  // PRODUCT SCORING TESTS
  // ============================================================================
  describe('scoreProduct', () => {
    const weights = calculateDynamicWeights(25);
    const trendingScores = new Map([['p1', 0.8]]);
  
    test('calculates combined score', () => {
      const product = {
        id: 'p1',
        category: 'Electronics',
        brand: 'Apple',
        price: 100,
      };
      const userProfile = {
        categoryScores: { Electronics: 100 },
        brandScores: { Apple: 100 },
        preferences: { avgPurchasePrice: 100 },
        recentlyViewed: [],
      };
  
      const result = scoreProduct(product, userProfile, trendingScores, weights);
  
      expect(result.score).toBeGreaterThan(0);
      expect(result.breakdown).toBeDefined();
      expect(result.breakdown.category).toBeDefined();
    });
  
    test('includes all breakdown components', () => {
      const product = { id: 'p1', category: 'Electronics', price: 100 };
      const userProfile = { categoryScores: { Electronics: 100 }, preferences: {} };
  
      const result = scoreProduct(product, userProfile, new Map(), weights);
  
      expect(result.breakdown.category).toBeDefined();
      expect(result.breakdown.brand).toBeDefined();
      expect(result.breakdown.trending).toBeDefined();
      expect(result.breakdown.price).toBeDefined();
      expect(result.breakdown.recency).toBeDefined();
    });
  });
  
  describe('rankProducts', () => {
    test('ranks by score descending', () => {
      const products = [
        { id: 'p1', category: 'Electronics', price: 100 },
        { id: 'p2', category: 'Electronics', price: 100 },
      ];
      const userProfile = {
        categoryScores: { Electronics: 100 },
        preferences: { avgPurchasePrice: 100 },
      };
      const trendingScores = new Map([['p2', 0.9], ['p1', 0.1]]);
      const weights = calculateDynamicWeights(0);
  
      const ranked = rankProducts(products, userProfile, trendingScores, weights);
  
      expect(ranked[0].id).toBe('p2'); // Higher trending
    });
  });
  
  // ============================================================================
  // FEED REFRESH TESTS
  // ============================================================================
  describe('shouldUpdateFeed', () => {
    const now = Date.now();
  
    test('returns true for no existing feed', () => {
      const result = shouldUpdateFeed({}, null, now);
      expect(result.shouldUpdate).toBe(true);
      expect(result.reason).toBe('no_existing_feed');
    });
  
    test('returns true for stale feed', () => {
      const threeDaysAgo = now - (3 * 24 * 60 * 60 * 1000);
      const existingFeed = { lastComputed: threeDaysAgo };
      
      const result = shouldUpdateFeed({}, existingFeed, now);
      expect(result.shouldUpdate).toBe(true);
      expect(result.reason).toBe('stale_feed');
    });
  
    test('returns true for significant new activity', () => {
      const oneDayAgo = now - (1 * 24 * 60 * 60 * 1000);
      const existingFeed = { lastComputed: oneDayAgo, stats: { userActivityCount: 10 } };
      const userProfile = { stats: { totalEvents: 20 } };
      
      const result = shouldUpdateFeed(userProfile, existingFeed, now);
      expect(result.shouldUpdate).toBe(true);
      expect(result.reason).toBe('new_activity');
    });
  
    test('returns false for fresh feed', () => {
      const oneHourAgo = now - (1 * 60 * 60 * 1000);
      const existingFeed = { lastComputed: oneHourAgo, stats: { userActivityCount: 10 } };
      const userProfile = { stats: { totalEvents: 12 } };
      
      const result = shouldUpdateFeed(userProfile, existingFeed, now);
      expect(result.shouldUpdate).toBe(false);
      expect(result.reason).toBe('feed_fresh');
    });
  });
  
  describe('isFeedStale', () => {
    const now = Date.now();
  
    test('returns true for old feed', () => {
      const threeDaysAgo = now - (3 * 24 * 60 * 60 * 1000);
      expect(isFeedStale({ lastComputed: threeDaysAgo }, 2, now)).toBe(true);
    });
  
    test('returns false for fresh feed', () => {
      const oneHourAgo = now - (1 * 60 * 60 * 1000);
      expect(isFeedStale({ lastComputed: oneHourAgo }, 2, now)).toBe(false);
    });
  });
  
  describe('hasSignificantNewActivity', () => {
    test('returns true for significant increase', () => {
      const userProfile = { stats: { totalEvents: 20 } };
      const existingFeed = { stats: { userActivityCount: 10 } };
      
      expect(hasSignificantNewActivity(userProfile, existingFeed, 5)).toBe(true);
    });
  
    test('returns false for small increase', () => {
      const userProfile = { stats: { totalEvents: 13 } };
      const existingFeed = { stats: { userActivityCount: 10 } };
      
      expect(hasSignificantNewActivity(userProfile, existingFeed, 5)).toBe(false);
    });
  });
  
  // ============================================================================
  // ACTIVITY THRESHOLD TESTS
  // ============================================================================
  describe('meetsActivityThreshold', () => {
    test('returns true at threshold', () => {
      expect(meetsActivityThreshold({ stats: { totalEvents: 3 } }, 3)).toBe(true);
    });
  
    test('returns false below threshold', () => {
      expect(meetsActivityThreshold({ stats: { totalEvents: 2 } }, 3)).toBe(false);
    });
  });
  
  describe('getActivityCount', () => {
    test('returns event count', () => {
      expect(getActivityCount({ stats: { totalEvents: 25 } })).toBe(25);
    });
  
    test('returns 0 for missing stats', () => {
      expect(getActivityCount({})).toBe(0);
    });
  });
  
  // ============================================================================
  // CANDIDATE SELECTION TESTS
  // ============================================================================
  describe('getTopCategories', () => {
    test('extracts top categories', () => {
      const userProfile = {
        preferences: {
          topCategories: [
            { category: 'Electronics', score: 100 },
            { category: 'Clothing', score: 80 },
            { category: 'Sports', score: 60 },
            { category: 'Books', score: 40 },
          ],
        },
      };
  
      const top = getTopCategories(userProfile, 3);
      expect(top).toEqual(['Electronics', 'Clothing', 'Sports']);
    });
  
    test('returns empty for no preferences', () => {
      expect(getTopCategories({})).toEqual([]);
    });
  });
  
  describe('sanitizeCategoryKey', () => {
    test('replaces dots and slashes', () => {
      expect(sanitizeCategoryKey('Electronics.Phones')).toBe('Electronics_Phones');
    });
  
    test('returns Other for null', () => {
      expect(sanitizeCategoryKey(null)).toBe('Other');
    });
  });
  
  // ============================================================================
  // OUTPUT BUILDING TESTS
  // ============================================================================
  describe('buildFeedOutput', () => {
    test('extracts ids and scores', () => {
      const products = [
        { id: 'p1', score: 0.9 },
        { id: 'p2', score: 0.8 },
      ];
  
      const output = buildFeedOutput(products);
  
      expect(output.productIds).toEqual(['p1', 'p2']);
      expect(output.scores).toEqual([0.9, 0.8]);
    });
  });
  
  describe('calculateAverageScore', () => {
    test('calculates average', () => {
      const products = [{ score: 0.8 }, { score: 0.6 }];
      expect(calculateAverageScore(products)).toBe(0.7);
    });
  
    test('returns 0 for empty', () => {
      expect(calculateAverageScore([])).toBe(0);
    });
  });
  
  describe('getWeightsInfo', () => {
    test('formats weights for output', () => {
      const weights = calculateDynamicWeights(25);
      const info = getWeightsInfo(weights);
  
      expect(info.category).toBeDefined();
      expect(info.brand).toBeDefined();
      expect(info.personalizationStrength).toBeDefined();
    });
  });
  
  // ============================================================================
  // BATCHING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks correctly', () => {
      const arr = [1, 2, 3, 4, 5, 6, 7];
      const chunks = chunkArray(arr, 3);
      
      expect(chunks.length).toBe(3);
      expect(chunks[0]).toEqual([1, 2, 3]);
      expect(chunks[2]).toEqual([7]);
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
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('new user gets trending-heavy feed', () => {
      const weights = calculateDynamicWeights(0);
      
      // New user should have equal or higher trending weight (base weights are equal)
      expect(weights.TRENDING_SCORE).toBeGreaterThanOrEqual(weights.CATEGORY_MATCH);
      // And trending should be at its maximum for new users
      expect(weights.TRENDING_SCORE).toBeCloseTo(BASE_WEIGHTS.TRENDING_SCORE, 2);
    });
  
    test('engaged user gets personalized feed', () => {
      const weights = calculateDynamicWeights(50);
      
      // Engaged user should have higher category weight
      expect(weights.CATEGORY_MATCH).toBeGreaterThan(weights.TRENDING_SCORE);
    });
  
    test('complete feed scoring flow', () => {
      // 1. User with activity
      const userProfile = {
        stats: { totalEvents: 30 },
        categoryScores: { Electronics: 100, Phones: 80 },
        brandScores: { Apple: 100 },
        preferences: { avgPurchasePrice: 500 },
        recentlyViewed: [],
      };
  
      // 2. Calculate dynamic weights
      const weights = calculateDynamicWeights(30);
      expect(weights._personalizationStrength).toBeGreaterThan(0);
  
      // 3. Score products
      const products = [
        { id: 'p1', category: 'Electronics', subcategory: 'Phones', brand: 'Apple', price: 500 },
        { id: 'p2', category: 'Clothing', brand: 'Nike', price: 100 },
      ];
      const trendingScores = new Map([['p1', 0.5], ['p2', 0.8]]);
  
      const ranked = rankProducts(products, userProfile, trendingScores, weights);
  
      // p1 should rank higher (category + subcategory + brand + price match)
      expect(ranked[0].id).toBe('p1');
    });
  
    test('subcategory bonus improves ranking', () => {
      // Use scores where category match is less than 1.0 so bonus can be visible
      const userProfile = {
        categoryScores: { Electronics: 50, Phones: 50 }, // Max is 50, so Electronics = 1.0
        brandScores: {},
        preferences: {},
      };
  
      const productWithSubcategory = {
        id: 'p1',
        category: 'Electronics',
        subcategory: 'Phones',
      };
  
      const productWithoutSubcategory = {
        id: 'p2',
        category: 'Electronics',
      };
  
      const matchWith = calculateCategoryMatch(productWithSubcategory, userProfile);
      const matchWithout = calculateCategoryMatch(productWithoutSubcategory, userProfile);
  
      // Both have category match = 50/50 = 1.0
      // With subcategory: 1.0 + (1.0 * 0.3) = 1.3 -> capped at 1.0
      // Both end up at 1.0 due to cap, so use >= 
      expect(matchWith).toBeGreaterThanOrEqual(matchWithout);
      
      // Better test: use partial category match
      const userProfile2 = {
        categoryScores: { Electronics: 50, Phones: 50, Clothing: 100 }, // Max is 100
      };
      
      const matchWith2 = calculateCategoryMatch(productWithSubcategory, userProfile2);
      const matchWithout2 = calculateCategoryMatch(productWithoutSubcategory, userProfile2);
      
      // Without: Electronics = 50/100 = 0.5
      // With: Electronics (0.5) + Phones bonus (0.5 * 0.3 = 0.15) = 0.65
      expect(matchWith2).toBeGreaterThan(matchWithout2);
    });
  });
