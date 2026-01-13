// functions/test/personalized-feed/personalized-feed-utils.js
//
// EXTRACTED PURE LOGIC from personalized feed cloud functions
// These functions are EXACT COPIES of logic from the personalized feed functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const CONFIG = {
    FEED_SIZE: 200,
    BATCH_SIZE: 50,
    MAX_CANDIDATES: 1000,
    REFRESH_INTERVAL_DAYS: 2,
    MIN_ACTIVITY_THRESHOLD: 3,
    MAX_RETRIES: 3,
    CATEGORY_TRENDING_LIMIT: 50,
  };
  
  // Base weights (will be dynamically adjusted)
  const BASE_WEIGHTS = {
    CATEGORY_MATCH: 0.25,
    BRAND_MATCH: 0.20,
    TRENDING_SCORE: 0.25,
    PRICE_RANGE_MATCH: 0.15,
    RECENCY_PENALTY: 0.15,
  };
  
  // Progressive personalization config
  const PERSONALIZATION_CONFIG = {
    MIN_EVENTS_FOR_PERSONALIZATION: 3,
    FULL_PERSONALIZATION_EVENTS: 50,
    CATEGORY_WEIGHT_MAX: 0.40,
    BRAND_WEIGHT_MAX: 0.30,
    TRENDING_WEIGHT_MIN: 0.10,
    SUBCATEGORY_BONUS_RATIO: 0.3,
  };
  
  // ============================================================================
  // WEIGHT VALIDATION
  // ============================================================================
  
  function validateWeights(weights) {
    const sum = Object.entries(weights)
      .filter(([key]) => !key.startsWith('_'))
      .reduce((acc, [, val]) => acc + val, 0);
    const isValid = Math.abs(sum - 1.0) < 0.01;
    return { isValid, sum };
  }
  
  function getBaseWeightSum() {
    return Object.values(BASE_WEIGHTS).reduce((acc, val) => acc + val, 0);
  }
  
  // ============================================================================
  // PERSONALIZATION STRENGTH
  // ============================================================================
  
  function calculatePersonalizationStrength(activityCount) {
    const { MIN_EVENTS_FOR_PERSONALIZATION, FULL_PERSONALIZATION_EVENTS } = PERSONALIZATION_CONFIG;
  
    if (activityCount < MIN_EVENTS_FOR_PERSONALIZATION) {
      return 0;
    }
  
    const strength = (activityCount - MIN_EVENTS_FOR_PERSONALIZATION) /
      (FULL_PERSONALIZATION_EVENTS - MIN_EVENTS_FOR_PERSONALIZATION);
  
    return Math.min(1.0, Math.max(0, strength));
  }
  
  function isFullyPersonalized(activityCount) {
    return activityCount >= PERSONALIZATION_CONFIG.FULL_PERSONALIZATION_EVENTS;
  }
  
  function hasMinimumActivity(activityCount) {
    return activityCount >= PERSONALIZATION_CONFIG.MIN_EVENTS_FOR_PERSONALIZATION;
  }
  
  // ============================================================================
  // DYNAMIC WEIGHTS CALCULATION
  // ============================================================================
  
  function calculateDynamicWeights(activityCount) {
    const {
      CATEGORY_WEIGHT_MAX,
      BRAND_WEIGHT_MAX,
      TRENDING_WEIGHT_MIN,
    } = PERSONALIZATION_CONFIG;
  
    const personalizationStrength = calculatePersonalizationStrength(activityCount);
  
    // Scale weights based on personalization strength
    const categoryWeight =
      BASE_WEIGHTS.CATEGORY_MATCH +
      (CATEGORY_WEIGHT_MAX - BASE_WEIGHTS.CATEGORY_MATCH) * personalizationStrength;
  
    const brandWeight =
      BASE_WEIGHTS.BRAND_MATCH +
      (BRAND_WEIGHT_MAX - BASE_WEIGHTS.BRAND_MATCH) * personalizationStrength;
  
    const trendingWeight =
      BASE_WEIGHTS.TRENDING_SCORE -
      (BASE_WEIGHTS.TRENDING_SCORE - TRENDING_WEIGHT_MIN) * personalizationStrength;
  
    // Fixed weights
    const priceWeight = BASE_WEIGHTS.PRICE_RANGE_MATCH;
    const recencyWeight = BASE_WEIGHTS.RECENCY_PENALTY;
  
    // Normalize to ensure sum = 1.0
    const total = categoryWeight + brandWeight + trendingWeight + priceWeight + recencyWeight;
  
    return {
      CATEGORY_MATCH: categoryWeight / total,
      BRAND_MATCH: brandWeight / total,
      TRENDING_SCORE: trendingWeight / total,
      PRICE_RANGE_MATCH: priceWeight / total,
      RECENCY_PENALTY: recencyWeight / total,
      _personalizationStrength: personalizationStrength,
      _activityCount: activityCount,
    };
  }
  
  // ============================================================================
  // NORMALIZATION
  // ============================================================================
  
  function normalize(value, min, max) {
    if (max === min) return 0.5;
    return Math.max(0, Math.min(1, (value - min) / (max - min)));
  }
  
  // ============================================================================
  // CATEGORY MATCHING
  // ============================================================================
  
  function calculateCategoryMatch(product, userProfile) {
    const categoryScores = userProfile.categoryScores || {};
    const productCategory = product.category;
    const productSubcategory = product.subcategory;
  
    // No category preference data
    if (Object.keys(categoryScores).length === 0) {
      return 0.0;
    }
  
    const maxScore = Math.max(...Object.values(categoryScores), 1);
  
    // Base category match (0 to 1)
    let categoryMatch = 0.0;
    if (productCategory && categoryScores[productCategory]) {
      categoryMatch = categoryScores[productCategory] / maxScore;
    }
  
    // Subcategory bonus (adds up to 30% more to the category score)
    let subcategoryBonus = 0.0;
    if (productSubcategory && categoryScores[productSubcategory]) {
      const subcategoryMatch = categoryScores[productSubcategory] / maxScore;
      subcategoryBonus = subcategoryMatch * PERSONALIZATION_CONFIG.SUBCATEGORY_BONUS_RATIO;
    }
  
    // Combined score (capped at 1.0)
    return Math.min(1.0, categoryMatch + subcategoryBonus);
  }
  
  function getMaxCategoryScore(categoryScores) {
    if (!categoryScores || Object.keys(categoryScores).length === 0) {
      return 1;
    }
    return Math.max(...Object.values(categoryScores), 1);
  }
  
  // ============================================================================
  // BRAND MATCHING
  // ============================================================================
  
  function calculateBrandMatch(product, userProfile) {
    const brandScores = userProfile.brandScores || {};
    const productBrand = product.brand;
  
    if (!productBrand || !brandScores[productBrand]) {
      return 0.0;
    }
  
    const maxScore = Math.max(...Object.values(brandScores), 1);
    return brandScores[productBrand] / maxScore;
  }
  
  function getMaxBrandScore(brandScores) {
    if (!brandScores || Object.keys(brandScores).length === 0) {
      return 1;
    }
    return Math.max(...Object.values(brandScores), 1);
  }
  
  // ============================================================================
  // PRICE MATCHING
  // ============================================================================
  
  function calculatePriceMatch(product, userProfile) {
    const avgPrice = userProfile.preferences?.avgPurchasePrice;
  
    if (!avgPrice || avgPrice === 0) {
      return 0.5; // Neutral score for unknown price preference
    }
  
    const priceDiff = Math.abs(product.price - avgPrice);
    const priceRatio = priceDiff / avgPrice;
  
    return Math.max(0, 1 - priceRatio);
  }
  
  function getPriceRange(avgPrice, minMultiplier = 0.5, maxMultiplier = 2.0) {
    if (!avgPrice || avgPrice === 0) {
      return { min: 0, max: Number.MAX_SAFE_INTEGER };
    }
    return {
      min: avgPrice * minMultiplier,
      max: avgPrice * maxMultiplier,
    };
  }
  
  function isInPriceRange(price, avgPrice, minMultiplier = 0.5, maxMultiplier = 2.0) {
    const range = getPriceRange(avgPrice, minMultiplier, maxMultiplier);
    return price >= range.min && price <= range.max;
  }
  
  // ============================================================================
  // RECENCY PENALTY
  // ============================================================================
  
  function calculateRecencyPenalty(product, userProfile) {
    const recentlyViewed = userProfile.recentlyViewed || [];
  
    const wasRecentlyViewed = recentlyViewed
      .slice(-50)
      .some((item) => item.productId === product.id);
  
    return wasRecentlyViewed ? 0.5 : 1.0;
  }
  
  function wasRecentlyViewed(productId, recentlyViewed, limit = 50) {
    if (!recentlyViewed || !Array.isArray(recentlyViewed)) {
      return false;
    }
    return recentlyViewed
      .slice(-limit)
      .some((item) => item.productId === productId);
  }
  
  // ============================================================================
  // PRODUCT SCORING
  // ============================================================================
  
  function scoreProduct(product, userProfile, trendingScores, weights) {
    const categoryMatch = calculateCategoryMatch(product, userProfile);
    const brandMatch = calculateBrandMatch(product, userProfile);
    const priceMatch = calculatePriceMatch(product, userProfile);
    const recencyPenalty = calculateRecencyPenalty(product, userProfile);
  
    const trendingScore = trendingScores?.get(product.id) || 0;
  
    const score =
      categoryMatch * weights.CATEGORY_MATCH +
      brandMatch * weights.BRAND_MATCH +
      trendingScore * weights.TRENDING_SCORE +
      priceMatch * weights.PRICE_RANGE_MATCH +
      recencyPenalty * weights.RECENCY_PENALTY;
  
    return {
      score,
      breakdown: {
        category: parseFloat(categoryMatch.toFixed(3)),
        brand: parseFloat(brandMatch.toFixed(3)),
        trending: parseFloat(trendingScore.toFixed(3)),
        price: parseFloat(priceMatch.toFixed(3)),
        recency: parseFloat(recencyPenalty.toFixed(3)),
      },
    };
  }
  
  function rankProducts(products, userProfile, trendingScores, weights) {
    return products
      .map((product) => {
        const { score, breakdown } = scoreProduct(product, userProfile, trendingScores, weights);
        return { id: product.id, score, breakdown };
      })
      .sort((a, b) => b.score - a.score);
  }
  
  function getTopProducts(rankedProducts, count = CONFIG.FEED_SIZE) {
    return rankedProducts.slice(0, count);
  }
  
  // ============================================================================
  // FEED REFRESH LOGIC
  // ============================================================================
  
  function shouldUpdateFeed(userProfile, existingFeed, now = Date.now()) {
    if (!existingFeed) {
      return { shouldUpdate: true, reason: 'no_existing_feed' };
    }
  
    const feedAge = now - (existingFeed.lastComputed?.toMillis?.() || existingFeed.lastComputed || 0);
    const daysSinceFeed = feedAge / (1000 * 60 * 60 * 24);
  
    if (daysSinceFeed > CONFIG.REFRESH_INTERVAL_DAYS) {
      return { shouldUpdate: true, reason: 'stale_feed' };
    }
  
    const userActivityCount = userProfile.stats?.totalEvents || 0;
    const feedActivityCount = existingFeed.stats?.userActivityCount || 0;
  
    if (userActivityCount > feedActivityCount + 5) {
      return { shouldUpdate: true, reason: 'new_activity' };
    }
  
    return { shouldUpdate: false, reason: 'feed_fresh' };
  }
  
  function getFeedAge(existingFeed, now = Date.now()) {
    if (!existingFeed || !existingFeed.lastComputed) {
      return Infinity;
    }
    const lastComputed = existingFeed.lastComputed?.toMillis?.() || existingFeed.lastComputed;
    return now - lastComputed;
  }
  
  function isFeedStale(existingFeed, maxAgeDays = CONFIG.REFRESH_INTERVAL_DAYS, now = Date.now()) {
    const ageMs = getFeedAge(existingFeed, now);
    const ageDays = ageMs / (1000 * 60 * 60 * 24);
    return ageDays > maxAgeDays;
  }
  
  function hasSignificantNewActivity(userProfile, existingFeed, threshold = 5) {
    const userActivityCount = userProfile.stats?.totalEvents || 0;
    const feedActivityCount = existingFeed?.stats?.userActivityCount || 0;
    return userActivityCount > feedActivityCount + threshold;
  }
  
  // ============================================================================
  // ACTIVITY THRESHOLD
  // ============================================================================
  
  function meetsActivityThreshold(userProfile, threshold = CONFIG.MIN_ACTIVITY_THRESHOLD) {
    const activityCount = userProfile.stats?.totalEvents || 0;
    return activityCount >= threshold;
  }
  
  function getActivityCount(userProfile) {
    return userProfile.stats?.totalEvents || 0;
  }
  
  // ============================================================================
  // CANDIDATE SELECTION
  // ============================================================================
  
  function getTopCategories(userProfile, count = 3) {
    return userProfile.preferences?.topCategories?.slice(0, count).map((c) => c.category) || [];
  }
  
  function sanitizeCategoryKey(category) {
    if (!category || typeof category !== 'string') return 'Other';
    return category.replace(/[./]/g, '_');
  }
  
  // ============================================================================
  // OUTPUT BUILDING
  // ============================================================================
  
  function buildFeedOutput(rankedProducts) {
    return {
      productIds: rankedProducts.map((p) => p.id),
      scores: rankedProducts.map((p) => p.score),
    };
  }
  
  function buildFeedStats(productsScored, computationTimeMs, userActivityCount, topCategories, avgScore, personalizationStrength, appliedWeights) {
    return {
      productsScored,
      computationTimeMs,
      userActivityCount,
      topCategories,
      avgScore: parseFloat(avgScore.toFixed(3)),
      personalizationStrength: parseFloat(personalizationStrength.toFixed(3)),
      appliedWeights,
    };
  }
  
  function calculateAverageScore(products) {
    if (!products || products.length === 0) return 0;
    const sum = products.reduce((acc, p) => acc + (p.score || 0), 0);
    return sum / products.length;
  }
  
  function getWeightsInfo(weights) {
    return {
      category: parseFloat(weights.CATEGORY_MATCH.toFixed(3)),
      brand: parseFloat(weights.BRAND_MATCH.toFixed(3)),
      trending: parseFloat(weights.TRENDING_SCORE.toFixed(3)),
      price: parseFloat(weights.PRICE_RANGE_MATCH.toFixed(3)),
      recency: parseFloat(weights.RECENCY_PENALTY.toFixed(3)),
      personalizationStrength: parseFloat((weights._personalizationStrength || 0).toFixed(3)),
    };
  }
  
  // ============================================================================
  // BATCHING
  // ============================================================================
  
  function chunkArray(array, size) {
    if (!Array.isArray(array)) return [];
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
  
  // ============================================================================
  // RETRY LOGIC
  // ============================================================================
  
  function getRetryDelay(attempt, baseDelay = 100) {
    return baseDelay * Math.pow(2, attempt - 1);
  }
  
  function shouldRetryError(errorCode) {
    if (errorCode === 'invalid-argument') return false;
    if (errorCode === 'permission-denied') return false;
    return true;
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Constants
    CONFIG,
    BASE_WEIGHTS,
    PERSONALIZATION_CONFIG,
  
    // Weight validation
    validateWeights,
    getBaseWeightSum,
  
    // Personalization strength
    calculatePersonalizationStrength,
    isFullyPersonalized,
    hasMinimumActivity,
  
    // Dynamic weights
    calculateDynamicWeights,
  
    // Normalization
    normalize,
  
    // Category matching
    calculateCategoryMatch,
    getMaxCategoryScore,
  
    // Brand matching
    calculateBrandMatch,
    getMaxBrandScore,
  
    // Price matching
    calculatePriceMatch,
    getPriceRange,
    isInPriceRange,
  
    // Recency penalty
    calculateRecencyPenalty,
    wasRecentlyViewed,
  
    // Product scoring
    scoreProduct,
    rankProducts,
    getTopProducts,
  
    // Feed refresh
    shouldUpdateFeed,
    getFeedAge,
    isFeedStale,
    hasSignificantNewActivity,
  
    // Activity threshold
    meetsActivityThreshold,
    getActivityCount,
  
    // Candidate selection
    getTopCategories,
    sanitizeCategoryKey,
  
    // Output building
    buildFeedOutput,
    buildFeedStats,
    calculateAverageScore,
    getWeightsInfo,
  
    // Batching
    chunkArray,
  
    // Retry
    getRetryDelay,
    shouldRetryError,
  };
