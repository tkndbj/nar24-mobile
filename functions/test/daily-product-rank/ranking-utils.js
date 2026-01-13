// functions/test/daily-product-rank/ranking-utils.js
//
// EXTRACTED PURE LOGIC from daily ranking cloud functions
// These functions are EXACT COPIES of logic from the ranking functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source ranking functions.

// ============================================================================
// STATIC THRESHOLDS
// Mirrors: STATIC_THRESHOLDS in ranking functions
// ============================================================================

/**
 * Static thresholds for normalization - update quarterly
 * EXACT COPY from production code
 */
const STATIC_THRESHOLDS = {
    purchaseP95: 100,
    cartP95: 50,
    favP95: 50,
  };
  
  /**
   * Ranking score weights
   */
  const RANKING_WEIGHTS = {
    purchase: 0.20,
    ctr: 0.15,
    conversion: 0.10,
    rating: 0.10,
    cart: 0.10,
    favorites: 0.10,
    recency: 0.25,
  };
  
  /**
   * Bonus values
   */
  const BONUSES = {
    coldStart: 0.2,        // New products (≤7 days)
    trending: 0.15,        // High daily clicks (≥10)
    boostMultiplier: 1.5,  // Boosted products
    promotionOffset: 1000, // Added to boosted products
  };
  
  /**
   * Thresholds for metric calculations
   */
  const METRIC_THRESHOLDS = {
    minImpressionsForCTR: 10,
    minClicksForConversion: 5,
    coldStartDays: 7,
    trendingDailyClicks: 10,
    recencyHalfLifeDays: 30,
    maxRankingScore: 2.0,
  };
  
  // ============================================================================
  // NORMALIZATION FUNCTIONS
  // Mirrors: normalization logic in computeRankingScore
  // ============================================================================
  

  function normalizeToThreshold(value, threshold) {
    if (!threshold || threshold <= 0) return 0;
    return Math.min(Math.max(value || 0, 0) / threshold, 1.0);
  }
  
 
  function normalizePurchases(purchases, thresholds = STATIC_THRESHOLDS) {
    const value = Math.max(purchases || 0, 0);
    return Math.min(value / thresholds.purchaseP95, 1.0);
  }
  

  function normalizeCart(cartCount, thresholds = STATIC_THRESHOLDS) {
    return Math.min((cartCount || 0) / thresholds.cartP95, 1.0);
  }
  

  function normalizeFavorites(favoritesCount, thresholds = STATIC_THRESHOLDS) {
    return Math.min((favoritesCount || 0) / thresholds.favP95, 1.0);
  }
  

  function normalizeRating(rating) {
    return (rating || 0) / 5;
  }
  
  // ============================================================================
  // CTR AND CONVERSION CALCULATIONS
  // Mirrors: CTR and conversion logic in computeRankingScore
  // ============================================================================
  

  function calculateCTR(clicks, impressions) {
    const safeImpressions = Math.max(impressions || 0, 1);
    const safeClicks = Math.max(clicks || 0, 0);
  
    // Require minimum impressions for meaningful CTR
    if (safeImpressions <= METRIC_THRESHOLDS.minImpressionsForCTR) {
      return 0;
    }
  
    return Math.min(safeClicks / safeImpressions, 1.0);
  }
  

  function calculateConversionRate(purchases, clicks) {
    const safeClicks = Math.max(clicks || 0, 0);
    const safePurchases = Math.max(purchases || 0, 0);
  
    // Require minimum clicks for meaningful conversion
    if (safeClicks <= METRIC_THRESHOLDS.minClicksForConversion) {
      return 0;
    }
  
    return Math.min(safePurchases / safeClicks, 1.0);
  }
  
  // ============================================================================
  // TIME-BASED CALCULATIONS
  // Mirrors: recency and bonus logic in computeRankingScore
  // ============================================================================
  

  function calculateAgeDays(createdAt, now = Date.now()) {
    if (!createdAt || typeof createdAt.toMillis !== 'function') {
      return 0;
    }
    return (now - createdAt.toMillis()) / (1000 * 60 * 60 * 24);
  }
  

  function calculateRecencyBoost(ageDays) {
    return Math.exp(-ageDays / METRIC_THRESHOLDS.recencyHalfLifeDays);
  }
  

  function calculateColdStartBonus(ageDays) {
    return ageDays <= METRIC_THRESHOLDS.coldStartDays ? BONUSES.coldStart : 0;
  }
  

  function calculateTrendingBonus(dailyClicks) {
    return (dailyClicks || 0) >= METRIC_THRESHOLDS.trendingDailyClicks ? BONUSES.trending : 0;
  }
  
  // ============================================================================
  // BOOST CALCULATIONS
  // Mirrors: boost logic in computeRankingScore
  // ============================================================================
  

  function getBoostMultiplier(isBoosted) {
    return isBoosted ? BONUSES.boostMultiplier : 1.0;
  }
  

  function calculatePromotionScore(rankingScore, isBoosted) {
    return isBoosted ? rankingScore + BONUSES.promotionOffset : rankingScore;
  }
  
  // ============================================================================
  // MAIN RANKING CALCULATION
  // Mirrors: computeRankingScore in production code
  // ============================================================================
  

  function hasMeaningfulMetrics(data) {
    return !!(data.clickCount || data.purchaseCount || data.dailyClickCount);
  }
  

  function calculateBaseScore(components) {
    const {
      purchaseNorm,
      ctr,
      conversionRate,
      ratingNorm,
      cartNorm,
      favNorm,
      recencyBoost,
    } = components;
  
    return (
      RANKING_WEIGHTS.purchase * purchaseNorm +
      RANKING_WEIGHTS.ctr * ctr +
      RANKING_WEIGHTS.conversion * conversionRate +
      RANKING_WEIGHTS.rating * ratingNorm +
      RANKING_WEIGHTS.cart * cartNorm +
      RANKING_WEIGHTS.favorites * favNorm +
      RANKING_WEIGHTS.recency * recencyBoost
    );
  }
  

  function computeRankingScore(data, thresholds = STATIC_THRESHOLDS, now = Date.now()) {
    // Skip if no meaningful metrics changed
    if (!hasMeaningfulMetrics(data)) {
      return null;
    }
  
    // Extract and normalize metrics
    const impressions = Math.max(data.impressionCount || 0, 1);
    const clicks = Math.max(data.clickCount || 0, 0);
    const purchases = Math.max(data.purchaseCount || 0, 0);
    const dailyClicks = Math.max(data.dailyClickCount || 0, 0);
  
    // Normalized components
    const purchaseNorm = normalizePurchases(purchases, thresholds);
    const ctr = calculateCTR(clicks, impressions);
    const conversionRate = calculateConversionRate(purchases, clicks);
    const ratingNorm = normalizeRating(data.averageRating);
    const cartNorm = normalizeCart(data.cartCount, thresholds);
    const favNorm = normalizeFavorites(data.favoritesCount, thresholds);
  
    // Time-based calculations
    const ageDays = calculateAgeDays(data.createdAt, now);
    const recencyBoost = calculateRecencyBoost(ageDays);
    const coldStartBonus = calculateColdStartBonus(ageDays);
    const trendingBonus = calculateTrendingBonus(dailyClicks);
  
    // Calculate scores
    const baseScore = calculateBaseScore({
      purchaseNorm,
      ctr,
      conversionRate,
      ratingNorm,
      cartNorm,
      favNorm,
      recencyBoost,
    });
  
    const enhancedScore = baseScore + coldStartBonus + trendingBonus;
    const boostMultiplier = getBoostMultiplier(data.isBoosted);
    const rankingScore = Math.min(enhancedScore * boostMultiplier, METRIC_THRESHOLDS.maxRankingScore);
    const promotionScore = calculatePromotionScore(rankingScore, data.isBoosted);
  
    return {
      rankingScore,
      promotionScore,
      // Components for debugging/testing
      _debug: {
        purchaseNorm,
        ctr,
        conversionRate,
        ratingNorm,
        cartNorm,
        favNorm,
        recencyBoost,
        coldStartBonus,
        trendingBonus,
        baseScore,
        enhancedScore,
        boostMultiplier,
      },
    };
  }
  

  function computeRankingScoreProduction(data, thresholds = STATIC_THRESHOLDS, now = Date.now()) {
    const result = computeRankingScore(data, thresholds, now);
    if (!result) return null;
  
    // Return only production fields
    return {
      rankingScore: result.rankingScore,
      promotionScore: result.promotionScore,
    };
  }
  
  // ============================================================================
  // BATCH PROCESSING HELPERS
  // ============================================================================
  

  function calculateCutoffTimestamp(hoursAgo, now = Date.now()) {
    return now - hoursAgo * 60 * 60 * 1000;
  }
  

  function getOptimalBatchSize(updateCount, maxBatchSize = 450) {
    return Math.min(updateCount, maxBatchSize);
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
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
  };
