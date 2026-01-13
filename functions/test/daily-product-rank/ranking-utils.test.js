// functions/test/daily-product-rank/ranking-utils.test.js
//
// Unit tests for product ranking utility functions
// Tests the EXACT logic from daily ranking cloud functions
//
// Run: npx jest test/daily-product-rank/ranking-utils.test.js

const {
    // Constants
    STATIC_THRESHOLDS,
    RANKING_WEIGHTS,
    BONUSES,
    METRIC_THRESHOLDS,
  
    // Normalization
    normalizeToThreshold,
    normalizePurchases,
    normalizeCart,
    normalizeFavorites,
    normalizeRating,
  
    // CTR and conversion
    calculateCTR,
    calculateConversionRate,
  
    // Time-based
    calculateAgeDays,
    calculateRecencyBoost,
    calculateColdStartBonus,
    calculateTrendingBonus,
  
    // Boost
    getBoostMultiplier,
    calculatePromotionScore,
  
    // Main calculation
    hasMeaningfulMetrics,
    calculateBaseScore,
    computeRankingScore,
    computeRankingScoreProduction,
  
    // Batch helpers
    calculateCutoffTimestamp,
    getOptimalBatchSize,
  } = require('./ranking-utils');
  
  // ============================================================================
  // HELPER: Create mock Firestore Timestamp
  // ============================================================================
  function createMockTimestamp(date) {
    const ms = date instanceof Date ? date.getTime() : date;
    return {
      toMillis: () => ms,
    };
  }
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('STATIC_THRESHOLDS has correct values', () => {
      expect(STATIC_THRESHOLDS.purchaseP95).toBe(100);
      expect(STATIC_THRESHOLDS.cartP95).toBe(50);
      expect(STATIC_THRESHOLDS.favP95).toBe(50);
    });
  
    test('RANKING_WEIGHTS sum to 1.0', () => {
      const sum = Object.values(RANKING_WEIGHTS).reduce((a, b) => a + b, 0);
      expect(sum).toBeCloseTo(1.0, 5);
    });
  
    test('BONUSES has correct values', () => {
      expect(BONUSES.coldStart).toBe(0.2);
      expect(BONUSES.trending).toBe(0.15);
      expect(BONUSES.boostMultiplier).toBe(1.5);
      expect(BONUSES.promotionOffset).toBe(1000);
    });
  
    test('METRIC_THRESHOLDS has correct values', () => {
      expect(METRIC_THRESHOLDS.minImpressionsForCTR).toBe(10);
      expect(METRIC_THRESHOLDS.minClicksForConversion).toBe(5);
      expect(METRIC_THRESHOLDS.coldStartDays).toBe(7);
      expect(METRIC_THRESHOLDS.trendingDailyClicks).toBe(10);
    });
  });
  
  // ============================================================================
  // NORMALIZATION TESTS
  // ============================================================================
  describe('normalizeToThreshold', () => {
    test('returns 0 for null value', () => {
      expect(normalizeToThreshold(null, 100)).toBe(0);
    });
  
    test('returns 0 for negative value', () => {
      expect(normalizeToThreshold(-10, 100)).toBe(0);
    });
  
    test('returns correct ratio', () => {
      expect(normalizeToThreshold(50, 100)).toBe(0.5);
    });
  
    test('caps at 1.0', () => {
      expect(normalizeToThreshold(200, 100)).toBe(1.0);
    });
  
    test('returns 0 for zero threshold', () => {
      expect(normalizeToThreshold(50, 0)).toBe(0);
    });
  });
  
  describe('normalizePurchases', () => {
    test('normalizes to threshold', () => {
      expect(normalizePurchases(50)).toBe(0.5); // 50/100
    });
  
    test('caps at 1.0', () => {
      expect(normalizePurchases(150)).toBe(1.0);
    });
  
    test('handles null', () => {
      expect(normalizePurchases(null)).toBe(0);
    });
  
    test('handles custom threshold', () => {
      expect(normalizePurchases(25, { purchaseP95: 50 })).toBe(0.5);
    });
  });
  
  describe('normalizeCart', () => {
    test('normalizes to threshold', () => {
      expect(normalizeCart(25)).toBe(0.5); // 25/50
    });
  
    test('caps at 1.0', () => {
      expect(normalizeCart(100)).toBe(1.0);
    });
  });
  
  describe('normalizeFavorites', () => {
    test('normalizes to threshold', () => {
      expect(normalizeFavorites(25)).toBe(0.5); // 25/50
    });
  
    test('caps at 1.0', () => {
      expect(normalizeFavorites(100)).toBe(1.0);
    });
  });
  
  describe('normalizeRating', () => {
    test('normalizes 5-star to 1.0', () => {
      expect(normalizeRating(5)).toBe(1.0);
    });
  
    test('normalizes 0-star to 0', () => {
      expect(normalizeRating(0)).toBe(0);
    });
  
    test('normalizes 4-star to 0.8', () => {
      expect(normalizeRating(4)).toBe(0.8);
    });
  
    test('handles null', () => {
      expect(normalizeRating(null)).toBe(0);
    });
  
    test('handles decimal ratings', () => {
      expect(normalizeRating(4.5)).toBe(0.9);
    });
  });
  
  // ============================================================================
  // CTR AND CONVERSION TESTS
  // ============================================================================
  describe('calculateCTR', () => {
    test('returns 0 for insufficient impressions', () => {
      expect(calculateCTR(5, 10)).toBe(0); // Exactly 10 impressions, needs > 10
    });
  
    test('calculates CTR correctly', () => {
      expect(calculateCTR(10, 100)).toBe(0.1); // 10%
    });
  
    test('caps at 1.0', () => {
      expect(calculateCTR(200, 100)).toBe(1.0);
    });
  
    test('handles null clicks', () => {
      expect(calculateCTR(null, 100)).toBe(0);
    });
  
    test('handles zero impressions', () => {
      expect(calculateCTR(10, 0)).toBe(0); // Falls below threshold
    });
  
    test('returns CTR for 11 impressions', () => {
      expect(calculateCTR(1, 11)).toBeCloseTo(0.0909, 3);
    });
  });
  
  describe('calculateConversionRate', () => {
    test('returns 0 for insufficient clicks', () => {
      expect(calculateConversionRate(2, 5)).toBe(0); // Exactly 5 clicks, needs > 5
    });
  
    test('calculates conversion correctly', () => {
      expect(calculateConversionRate(5, 50)).toBe(0.1); // 10%
    });
  
    test('caps at 1.0', () => {
      expect(calculateConversionRate(100, 50)).toBe(1.0);
    });
  
    test('handles null purchases', () => {
      expect(calculateConversionRate(null, 100)).toBe(0);
    });
  
    test('returns conversion for 6 clicks', () => {
      expect(calculateConversionRate(3, 6)).toBe(0.5);
    });
  });
  
  // ============================================================================
  // TIME-BASED CALCULATION TESTS
  // ============================================================================
  describe('calculateAgeDays', () => {
    test('calculates days correctly', () => {
      const now = Date.now();
      const sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;
      const createdAt = createMockTimestamp(sevenDaysAgo);
  
      expect(calculateAgeDays(createdAt, now)).toBeCloseTo(7, 1);
    });
  
    test('returns 0 for null createdAt', () => {
      expect(calculateAgeDays(null)).toBe(0);
    });
  
    test('returns 0 for invalid createdAt', () => {
      expect(calculateAgeDays({ invalid: true })).toBe(0);
    });
  
    test('handles very old products', () => {
      const now = Date.now();
      const oneYearAgo = now - 365 * 24 * 60 * 60 * 1000;
      const createdAt = createMockTimestamp(oneYearAgo);
  
      expect(calculateAgeDays(createdAt, now)).toBeCloseTo(365, 1);
    });
  });
  
  describe('calculateRecencyBoost', () => {
    test('returns 1.0 for brand new product', () => {
      expect(calculateRecencyBoost(0)).toBe(1.0);
    });
  
    test('returns ~0.5 for 30-day old product', () => {
      // e^(-30/30) = e^(-1) ≈ 0.368
      expect(calculateRecencyBoost(30)).toBeCloseTo(0.368, 2);
    });
  
    test('returns ~0.135 for 60-day old product', () => {
      // e^(-60/30) = e^(-2) ≈ 0.135
      expect(calculateRecencyBoost(60)).toBeCloseTo(0.135, 2);
    });
  
    test('approaches 0 for very old products', () => {
      expect(calculateRecencyBoost(365)).toBeLessThan(0.01);
    });
  });
  
  describe('calculateColdStartBonus', () => {
    test('returns 0.2 for product ≤ 7 days old', () => {
      expect(calculateColdStartBonus(0)).toBe(0.2);
      expect(calculateColdStartBonus(3)).toBe(0.2);
      expect(calculateColdStartBonus(7)).toBe(0.2);
    });
  
    test('returns 0 for product > 7 days old', () => {
      expect(calculateColdStartBonus(8)).toBe(0);
      expect(calculateColdStartBonus(30)).toBe(0);
    });
  });
  
  describe('calculateTrendingBonus', () => {
    test('returns 0.15 for ≥ 10 daily clicks', () => {
      expect(calculateTrendingBonus(10)).toBe(0.15);
      expect(calculateTrendingBonus(100)).toBe(0.15);
    });
  
    test('returns 0 for < 10 daily clicks', () => {
      expect(calculateTrendingBonus(9)).toBe(0);
      expect(calculateTrendingBonus(0)).toBe(0);
    });
  
    test('handles null', () => {
      expect(calculateTrendingBonus(null)).toBe(0);
    });
  });
  
  // ============================================================================
  // BOOST TESTS
  // ============================================================================
  describe('getBoostMultiplier', () => {
    test('returns 1.5 for boosted products', () => {
      expect(getBoostMultiplier(true)).toBe(1.5);
    });
  
    test('returns 1.0 for non-boosted products', () => {
      expect(getBoostMultiplier(false)).toBe(1.0);
    });
  
    test('returns 1.0 for undefined', () => {
      expect(getBoostMultiplier(undefined)).toBe(1.0);
    });
  });
  
  describe('calculatePromotionScore', () => {
    test('adds 1000 for boosted products', () => {
      expect(calculatePromotionScore(0.5, true)).toBe(1000.5);
    });
  
    test('returns same score for non-boosted', () => {
      expect(calculatePromotionScore(0.5, false)).toBe(0.5);
    });
  });
  
  // ============================================================================
  // MEANINGFUL METRICS TESTS
  // ============================================================================
  describe('hasMeaningfulMetrics', () => {
    test('returns true if clickCount exists', () => {
      expect(hasMeaningfulMetrics({ clickCount: 1 })).toBe(true);
    });
  
    test('returns true if purchaseCount exists', () => {
      expect(hasMeaningfulMetrics({ purchaseCount: 1 })).toBe(true);
    });
  
    test('returns true if dailyClickCount exists', () => {
      expect(hasMeaningfulMetrics({ dailyClickCount: 1 })).toBe(true);
    });
  
    test('returns false if no metrics', () => {
      expect(hasMeaningfulMetrics({})).toBe(false);
    });
  
    test('returns false if all metrics are 0', () => {
      expect(hasMeaningfulMetrics({ clickCount: 0, purchaseCount: 0, dailyClickCount: 0 })).toBe(false);
    });
  });
  
  // ============================================================================
  // BASE SCORE CALCULATION TESTS
  // ============================================================================
  describe('calculateBaseScore', () => {
    test('calculates weighted sum correctly', () => {
      const components = {
        purchaseNorm: 1.0,    // 0.20 * 1.0 = 0.20
        ctr: 1.0,             // 0.15 * 1.0 = 0.15
        conversionRate: 1.0,  // 0.10 * 1.0 = 0.10
        ratingNorm: 1.0,      // 0.10 * 1.0 = 0.10
        cartNorm: 1.0,        // 0.10 * 1.0 = 0.10
        favNorm: 1.0,         // 0.10 * 1.0 = 0.10
        recencyBoost: 1.0,    // 0.25 * 1.0 = 0.25
      };
  
      expect(calculateBaseScore(components)).toBeCloseTo(1.0, 5);
    });
  
    test('calculates partial scores correctly', () => {
      const components = {
        purchaseNorm: 0.5,
        ctr: 0.5,
        conversionRate: 0.5,
        ratingNorm: 0.5,
        cartNorm: 0.5,
        favNorm: 0.5,
        recencyBoost: 0.5,
      };
  
      expect(calculateBaseScore(components)).toBeCloseTo(0.5, 5);
    });
  
    test('handles all zeros', () => {
      const components = {
        purchaseNorm: 0,
        ctr: 0,
        conversionRate: 0,
        ratingNorm: 0,
        cartNorm: 0,
        favNorm: 0,
        recencyBoost: 0,
      };
  
      expect(calculateBaseScore(components)).toBe(0);
    });
  });
  
  // ============================================================================
  // MAIN RANKING CALCULATION TESTS
  // ============================================================================
  describe('computeRankingScore', () => {
    const now = Date.now();
    const threeDaysAgo = now - 3 * 24 * 60 * 60 * 1000;
  
    test('returns null for product with no metrics', () => {
      const data = { productName: 'Test' };
      expect(computeRankingScore(data)).toBe(null);
    });
  
    test('calculates score for product with clicks', () => {
      const data = {
        clickCount: 10,
        impressionCount: 100,
        createdAt: createMockTimestamp(threeDaysAgo),
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result).not.toBe(null);
      expect(result.rankingScore).toBeGreaterThan(0);
      expect(result.promotionScore).toBe(result.rankingScore);
    });
  
    test('applies cold start bonus for new products', () => {
      const data = {
        clickCount: 10,
        createdAt: createMockTimestamp(now - 2 * 24 * 60 * 60 * 1000), // 2 days ago
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result._debug.coldStartBonus).toBe(0.2);
    });
  
    test('no cold start bonus for old products', () => {
      const data = {
        clickCount: 10,
        createdAt: createMockTimestamp(now - 30 * 24 * 60 * 60 * 1000), // 30 days ago
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result._debug.coldStartBonus).toBe(0);
    });
  
    test('applies trending bonus for high daily clicks', () => {
      const data = {
        clickCount: 10,
        dailyClickCount: 15,
        createdAt: createMockTimestamp(threeDaysAgo),
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result._debug.trendingBonus).toBe(0.15);
    });
  
    test('applies boost multiplier for boosted products', () => {
      const data = {
        clickCount: 10,
        isBoosted: true,
        createdAt: createMockTimestamp(threeDaysAgo),
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result._debug.boostMultiplier).toBe(1.5);
    });
  
    test('adds promotion offset for boosted products', () => {
      const data = {
        clickCount: 10,
        isBoosted: true,
        createdAt: createMockTimestamp(threeDaysAgo),
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result.promotionScore).toBe(result.rankingScore + 1000);
    });
  
    test('caps ranking score at 2.0', () => {
      const data = {
        clickCount: 1000,
        purchaseCount: 500,
        impressionCount: 1000,
        averageRating: 5,
        cartCount: 200,
        favoritesCount: 200,
        dailyClickCount: 100,
        isBoosted: true,
        createdAt: createMockTimestamp(now), // Brand new
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result.rankingScore).toBeLessThanOrEqual(2.0);
    });
  
    test('handles all metrics', () => {
      const data = {
        clickCount: 50,
        purchaseCount: 25,
        impressionCount: 500,
        averageRating: 4.5,
        cartCount: 30,
        favoritesCount: 20,
        dailyClickCount: 5,
        isBoosted: false,
        createdAt: createMockTimestamp(now - 15 * 24 * 60 * 60 * 1000),
      };
  
      const result = computeRankingScore(data, STATIC_THRESHOLDS, now);
  
      expect(result.rankingScore).toBeGreaterThan(0);
      expect(result._debug.purchaseNorm).toBe(0.25); // 25/100
      expect(result._debug.ratingNorm).toBe(0.9);    // 4.5/5
      expect(result._debug.cartNorm).toBe(0.6);      // 30/50
      expect(result._debug.favNorm).toBe(0.4);       // 20/50
    });
  });
  
  describe('computeRankingScoreProduction', () => {
    test('returns only production fields', () => {
      const data = {
        clickCount: 10,
        createdAt: createMockTimestamp(Date.now() - 24 * 60 * 60 * 1000),
      };
  
      const result = computeRankingScoreProduction(data);
  
      expect(result.rankingScore).toBeDefined();
      expect(result.promotionScore).toBeDefined();
      expect(result._debug).toBeUndefined();
    });
  
    test('returns null for no metrics', () => {
      expect(computeRankingScoreProduction({})).toBe(null);
    });
  });
  
  // ============================================================================
  // BATCH HELPERS TESTS
  // ============================================================================
  describe('calculateCutoffTimestamp', () => {
    test('calculates 12 hours ago', () => {
      const now = Date.now();
      const cutoff = calculateCutoffTimestamp(12, now);
      expect(cutoff).toBe(now - 12 * 60 * 60 * 1000);
    });
  
    test('calculates 24 hours ago', () => {
      const now = Date.now();
      const cutoff = calculateCutoffTimestamp(24, now);
      expect(cutoff).toBe(now - 24 * 60 * 60 * 1000);
    });
  });
  
  describe('getOptimalBatchSize', () => {
    test('returns update count if below max', () => {
      expect(getOptimalBatchSize(100)).toBe(100);
    });
  
    test('returns max if update count exceeds', () => {
      expect(getOptimalBatchSize(500)).toBe(450);
    });
  
    test('respects custom max batch size', () => {
      expect(getOptimalBatchSize(300, 200)).toBe(200);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    const now = Date.now();
  
    test('brand new product gets visibility boost', () => {
      const newProduct = {
        clickCount: 5,
        purchaseCount: 1,
        impressionCount: 50,
        averageRating: 4.0,
        dailyClickCount: 5,
        createdAt: createMockTimestamp(now - 2 * 24 * 60 * 60 * 1000), // 2 days old
      };
  
      const result = computeRankingScore(newProduct, STATIC_THRESHOLDS, now);
  
      // Should have cold start bonus
      expect(result._debug.coldStartBonus).toBe(0.2);
      // Should have high recency boost
      expect(result._debug.recencyBoost).toBeGreaterThan(0.9);
    });
  
    test('trending product gets bonus', () => {
      const trendingProduct = {
        clickCount: 100,
        purchaseCount: 10,
        impressionCount: 1000,
        dailyClickCount: 50, // High daily clicks
        createdAt: createMockTimestamp(now - 30 * 24 * 60 * 60 * 1000),
      };
  
      const result = computeRankingScore(trendingProduct, STATIC_THRESHOLDS, now);
  
      expect(result._debug.trendingBonus).toBe(0.15);
    });
  
    test('boosted product outranks non-boosted', () => {
      const baseData = {
        clickCount: 50,
        purchaseCount: 10,
        impressionCount: 500,
        averageRating: 4.0,
        createdAt: createMockTimestamp(now - 14 * 24 * 60 * 60 * 1000),
      };
  
      const normalResult = computeRankingScore(
        { ...baseData, isBoosted: false },
        STATIC_THRESHOLDS,
        now
      );
  
      const boostedResult = computeRankingScore(
        { ...baseData, isBoosted: true },
        STATIC_THRESHOLDS,
        now
      );
  
      expect(boostedResult.rankingScore).toBeGreaterThan(normalResult.rankingScore);
      expect(boostedResult.promotionScore).toBeGreaterThan(1000);
    });
  
    test('high-quality product with good metrics', () => {
      const qualityProduct = {
        clickCount: 200,
        purchaseCount: 50,        // 25% conversion
        impressionCount: 2000,    // 10% CTR
        averageRating: 4.8,
        cartCount: 40,
        favoritesCount: 35,
        dailyClickCount: 12,
        createdAt: createMockTimestamp(now - 7 * 24 * 60 * 60 * 1000),
      };
  
      const result = computeRankingScore(qualityProduct, STATIC_THRESHOLDS, now);
  
      // Should have decent scores across the board
      expect(result._debug.purchaseNorm).toBe(0.5);      // 50/100
      expect(result._debug.ctr).toBe(0.1);               // 200/2000
      expect(result._debug.ratingNorm).toBe(0.96);       // 4.8/5
      expect(result._debug.coldStartBonus).toBe(0.2);   // Exactly 7 days
      expect(result._debug.trendingBonus).toBe(0.15);   // 12 daily clicks
    });
  
    test('old product with low engagement', () => {
      const oldProduct = {
        clickCount: 20,
        purchaseCount: 2,
        impressionCount: 500,
        averageRating: 3.0,
        createdAt: createMockTimestamp(now - 180 * 24 * 60 * 60 * 1000), // 6 months old
      };
  
      const result = computeRankingScore(oldProduct, STATIC_THRESHOLDS, now);
  
      // Should have low scores
      expect(result._debug.coldStartBonus).toBe(0);
      expect(result._debug.trendingBonus).toBe(0);
      expect(result._debug.recencyBoost).toBeLessThan(0.01);
      expect(result.rankingScore).toBeLessThan(0.5);
    });
  
    test('product comparison for search ranking', () => {
      const products = [
        {
          name: 'New Trending',
          clickCount: 30,
          dailyClickCount: 15,
          createdAt: createMockTimestamp(now - 3 * 24 * 60 * 60 * 1000),
        },
        {
          name: 'Old Popular',
          clickCount: 500,
          purchaseCount: 100,
          impressionCount: 5000,
          averageRating: 4.5,
          createdAt: createMockTimestamp(now - 90 * 24 * 60 * 60 * 1000),
        },
        {
          name: 'Boosted Average',
          clickCount: 20,
          isBoosted: true,
          createdAt: createMockTimestamp(now - 30 * 24 * 60 * 60 * 1000),
        },
      ];
  
      const scores = products.map((p) => ({
        name: p.name,
        ...computeRankingScore(p, STATIC_THRESHOLDS, now),
      }));
  
      // Boosted should have highest promotion score
      const boosted = scores.find((s) => s.name === 'Boosted Average');
      expect(boosted.promotionScore).toBeGreaterThan(1000);
  
      // All should have positive ranking scores
      scores.forEach((s) => {
        expect(s.rankingScore).toBeGreaterThan(0);
      });
    });
  });
