// functions/test/trending-products/trending-products-utils.js
//
// EXTRACTED PURE LOGIC from trending products cloud functions
// These functions are EXACT COPIES of logic from the trending products functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const CONFIG = {
    TOP_PRODUCTS_COUNT: 200,
    LOOKBACK_DAYS: 7,
    STREAM_CHUNK_SIZE: 500,
    MIN_ENGAGEMENT_THRESHOLD: 5,
    MAX_RETRIES: 3,
    INCREMENTAL_UPDATE_HOURS: 6,
    CATEGORY_TOP_COUNT: 50,
  };
  
  // Scoring weights (must sum to 1.0)
  const WEIGHTS = {
    CLICKS: 0.30,
    CART_ADDITIONS: 0.25,
    FAVORITES: 0.20,
    PURCHASES: 0.15,
    RECENCY: 0.10,
  };
  
  // ============================================================================
  // WEIGHT VALIDATION
  // ============================================================================
  
  function validateWeights(weights) {
    const sum = Object.values(weights).reduce((acc, val) => acc + val, 0);
    const isValid = Math.abs(sum - 1.0) < 0.001; // Allow tiny floating point error
    return { isValid, sum };
  }
  
  function getWeightSum() {
    return Object.values(WEIGHTS).reduce((acc, val) => acc + val, 0);
  }
  
  // ============================================================================
  // NORMALIZATION
  // ============================================================================
  
  function normalize(value, min, max) {
    if (max === min) return 0.5; // Avoid division by zero
    const normalized = (value - min) / (max - min);
    return Math.max(0, Math.min(1, normalized)); // Clamp to [0, 1]
  }
  
  function normalizeScore(value, min, max) {
    return normalize(value, min, max);
  }
  
  // ============================================================================
  // RECENCY CALCULATION
  // ============================================================================
  
  function calculateRecencyBoost(daysOld) {
    if (daysOld < 0) return 1.0; // Future dates get max boost
    return 1.0 / (1 + daysOld / 30);
  }
  
  function calculateDaysOld(createdAt, now = Date.now()) {
    const createdTime = createdAt instanceof Date ? createdAt.getTime() : createdAt;
    return (now - createdTime) / (1000 * 60 * 60 * 24);
  }
  
  function getRecencyScore(createdAt, now = Date.now()) {
    const daysOld = calculateDaysOld(createdAt, now);
    return calculateRecencyBoost(daysOld);
  }
  
  // ============================================================================
  // STATS CALCULATION
  // ============================================================================
  
  function calculateStats(products) {
    if (!products || products.length === 0) {
      return {
        minClicks: 0,
        maxClicks: 0,
        minCart: 0,
        maxCart: 0,
        minFavorites: 0,
        maxFavorites: 0,
        minPurchases: 0,
        maxPurchases: 0,
      };
    }
  
    const clicks = products.map((p) => p.clicks || 0);
    const carts = products.map((p) => p.cartCount || 0);
    const favorites = products.map((p) => p.favoritesCount || 0);
    const purchases = products.map((p) => p.purchaseCount || 0);
  
    return {
      minClicks: Math.min(...clicks),
      maxClicks: Math.max(...clicks),
      minCart: Math.min(...carts),
      maxCart: Math.max(...carts),
      minFavorites: Math.min(...favorites),
      maxFavorites: Math.max(...favorites),
      minPurchases: Math.min(...purchases),
      maxPurchases: Math.max(...purchases),
    };
  }
  
  // ============================================================================
  // TRENDING SCORE CALCULATION
  // ============================================================================
  
  function calculateTrendingScore(product, stats, weights = WEIGHTS, now = Date.now()) {
    // Normalize each metric
    const clickScore = normalize(product.clicks || 0, stats.minClicks, stats.maxClicks);
    const cartScore = normalize(product.cartCount || 0, stats.minCart, stats.maxCart);
    const favoriteScore = normalize(product.favoritesCount || 0, stats.minFavorites, stats.maxFavorites);
    const purchaseScore = normalize(product.purchaseCount || 0, stats.minPurchases, stats.maxPurchases);
  
    // Calculate recency
    const createdAt = product.createdAt instanceof Date ? product.createdAt : new Date(product.createdAt || now);
    const daysOld = calculateDaysOld(createdAt, now);
    const recencyScore = calculateRecencyBoost(daysOld);
  
    // Weighted sum
    const trendingScore =
      clickScore * weights.CLICKS +
      cartScore * weights.CART_ADDITIONS +
      favoriteScore * weights.FAVORITES +
      purchaseScore * weights.PURCHASES +
      recencyScore * weights.RECENCY;
  
    return {
      score: trendingScore,
      breakdown: {
        clicks: parseFloat(clickScore.toFixed(3)),
        cart: parseFloat(cartScore.toFixed(3)),
        favorites: parseFloat(favoriteScore.toFixed(3)),
        purchases: parseFloat(purchaseScore.toFixed(3)),
        recency: parseFloat(recencyScore.toFixed(3)),
      },
    };
  }
  
  function calculateScoreBreakdown(product, stats, weights = WEIGHTS) {
    const { breakdown } = calculateTrendingScore(product, stats, weights);
    return breakdown;
  }
  
  // ============================================================================
  // PRODUCT FILTERING
  // ============================================================================
  
  function meetsEngagementThreshold(product, threshold = CONFIG.MIN_ENGAGEMENT_THRESHOLD) {
    return (product.clicks || 0) >= threshold;
  }
  
  function filterEligibleProducts(products, threshold = CONFIG.MIN_ENGAGEMENT_THRESHOLD) {
    return products.filter((p) => meetsEngagementThreshold(p, threshold));
  }
  
  // ============================================================================
  // RANKING
  // ============================================================================
  
  function rankProducts(products, stats, weights = WEIGHTS) {
    return products
      .map((product) => {
        const { score, breakdown } = calculateTrendingScore(product, stats, weights);
        return {
          id: product.id,
          score,
          breakdown,
          metrics: {
            clicks: product.clicks || 0,
            cart: product.cartCount || 0,
            favorites: product.favoritesCount || 0,
            purchases: product.purchaseCount || 0,
          },
        };
      })
      .sort((a, b) => b.score - a.score);
  }
  
  function getTopProducts(rankedProducts, count = CONFIG.TOP_PRODUCTS_COUNT) {
    return rankedProducts.slice(0, count);
  }
  
  // ============================================================================
  // CATEGORY HANDLING
  // ============================================================================
  
  function sanitizeCategoryKey(category) {
    if (!category || typeof category !== 'string') return 'Other';
    return category.replace(/[./]/g, '_');
  }
  
  function groupProductsByCategory(products, maxPerCategory = CONFIG.CATEGORY_TOP_COUNT) {
    const categoryMap = new Map();
  
    for (const product of products) {
      const category = product.category || product.metrics?.category || 'Other';
  
      if (!categoryMap.has(category)) {
        categoryMap.set(category, []);
      }
  
      if (categoryMap.get(category).length < maxPerCategory) {
        categoryMap.get(category).push(product.id);
      }
    }
  
    return categoryMap;
  }
  
  // ============================================================================
  // INCREMENTAL UPDATE LOGIC
  // ============================================================================
  
  function shouldUseCache(lastComputedMs, thresholdHours = CONFIG.INCREMENTAL_UPDATE_HOURS, now = Date.now()) {
    if (!lastComputedMs) return false;
    const hoursSinceUpdate = (now - lastComputedMs) / (1000 * 60 * 60);
    return hoursSinceUpdate < thresholdHours;
  }
  
  function getHoursSinceUpdate(lastComputedMs, now = Date.now()) {
    if (!lastComputedMs) return Infinity;
    return (now - lastComputedMs) / (1000 * 60 * 60);
  }
  
  // ============================================================================
  // DATE HELPERS
  // ============================================================================
  
  function generateLookbackDates(daysBack = CONFIG.LOOKBACK_DAYS, now = new Date()) {
    const dates = [];
    for (let i = 0; i < daysBack; i++) {
      const date = new Date(now);
      date.setDate(date.getDate() - i);
      dates.push(date.toISOString().split('T')[0]);
    }
    return dates;
  }
  
  function getVersionString(now = new Date()) {
    return now.toISOString().split('T')[0];
  }
  
  // ============================================================================
  // PURCHASE AGGREGATION
  // ============================================================================
  
  function mergePurchaseCounts(purchaseMaps) {
    const merged = new Map();
  
    for (const map of purchaseMaps) {
      for (const [productId, count] of map.entries()) {
        merged.set(productId, (merged.get(productId) || 0) + count);
      }
    }
  
    return merged;
  }
  
  function enrichProductsWithPurchases(products, purchaseCounts) {
    return products.map((product) => ({
      ...product,
      purchaseCount: purchaseCounts.get(product.id) || 0,
    }));
  }
  
  // ============================================================================
  // OUTPUT BUILDING
  // ============================================================================
  
  function buildTrendingOutput(rankedProducts) {
    return {
      products: rankedProducts.map((p) => p.id),
      scores: rankedProducts.map((p) => p.score),
    };
  }
  
  function buildStatsOutput(totalCandidates, totalProcessed, topCount, computationTimeMs, avgScore, cached = false) {
    return {
      totalCandidates,
      totalProcessed,
      topCount,
      computationTimeMs,
      avgTrendScore: parseFloat(avgScore.toFixed(3)),
      cached,
    };
  }
  
  function calculateAverageScore(products) {
    if (!products || products.length === 0) return 0;
    const sum = products.reduce((acc, p) => acc + (p.score || 0), 0);
    return sum / products.length;
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
  // CLEANUP
  // ============================================================================
  
  function getCleanupCutoffDate(days = 7, now = new Date()) {
    const cutoff = new Date(now);
    cutoff.setDate(cutoff.getDate() - days);
    return cutoff;
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Constants
    CONFIG,
    WEIGHTS,
  
    // Weight validation
    validateWeights,
    getWeightSum,
  
    // Normalization
    normalize,
    normalizeScore,
  
    // Recency
    calculateRecencyBoost,
    calculateDaysOld,
    getRecencyScore,
  
    // Stats
    calculateStats,
  
    // Trending score
    calculateTrendingScore,
    calculateScoreBreakdown,
  
    // Product filtering
    meetsEngagementThreshold,
    filterEligibleProducts,
  
    // Ranking
    rankProducts,
    getTopProducts,
  
    // Category
    sanitizeCategoryKey,
    groupProductsByCategory,
  
    // Incremental update
    shouldUseCache,
    getHoursSinceUpdate,
  
    // Date helpers
    generateLookbackDates,
    getVersionString,
  
    // Purchase aggregation
    mergePurchaseCounts,
    enrichProductsWithPurchases,
  
    // Output building
    buildTrendingOutput,
    buildStatsOutput,
    calculateAverageScore,
  
    // Retry
    getRetryDelay,
    shouldRetryError,
  
    // Cleanup
    getCleanupCutoffDate,
  };
