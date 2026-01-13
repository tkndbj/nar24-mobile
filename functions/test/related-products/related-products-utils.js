// functions/test/related-products/related-products-utils.js
//
// EXTRACTED PURE LOGIC from related products rebuild cloud functions
// These functions are EXACT COPIES of logic from the related products functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source related products functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_CONCURRENCY = 20;
const MAX_CONSECUTIVE_ERRORS = 3;
const MAX_RETRY_ATTEMPTS = 3;
const DAYS_BEFORE_REFRESH = 7;
const MAX_RELATED_PRODUCTS = 20;
const TIMEOUT_MS = 10000;
const ERROR_RATE_THRESHOLD = 0.1; // 10%

const ALGOLIA_PREFIXES = ['shop_products_', 'products_'];

const SCORE_WEIGHTS = {
  PRIMARY_WITH_GENDER: 100,
  PRIMARY_WITHOUT_GENDER: 80,
  SUBSUBCATEGORY_MATCH: 60,
  PRICE_RANGE_MATCH: 40,
  MATCH_COUNT_BONUS: 10,
  PROMOTION_SCORE_WEIGHT: 0.5,
  PRICE_CLOSE_BONUS: 15,      // < 20% difference
  PRICE_MEDIUM_BONUS: 5,       // < 40% difference
};

// ============================================================================
// ID CLEANING
// ============================================================================

function cleanAlgoliaId(id) {
  if (!id || typeof id !== 'string') return id;

  for (const prefix of ALGOLIA_PREFIXES) {
    if (id.startsWith(prefix)) {
      return id.replace(prefix, '');
    }
  }
  return id;
}

function cleanAlgoliaIds(ids) {
  if (!Array.isArray(ids)) return [];
  return ids.map(cleanAlgoliaId);
}

function hasAlgoliaPrefix(id) {
  if (!id || typeof id !== 'string') return false;
  return ALGOLIA_PREFIXES.some((prefix) => id.startsWith(prefix));
}

// ============================================================================
// PRODUCT VALIDATION
// ============================================================================

function validateProductForRelated(productData) {
  const errors = [];

  if (!productData) {
    return { isValid: false, errors: ['Product data is required'] };
  }

  if (!productData.category) {
    errors.push('Missing category');
  }

  if (!productData.subcategory) {
    errors.push('Missing subcategory');
  }

  if (!productData.price || productData.price <= 0) {
    errors.push('Invalid price');
  }

  if (errors.length > 0) {
    return { isValid: false, errors };
  }

  return { isValid: true };
}

function isValidForRelatedProducts(productData) {
  return validateProductForRelated(productData).isValid;
}

// ============================================================================
// SKIP LOGIC
// ============================================================================

function shouldSkipProduct(productData, dayThreshold = DAYS_BEFORE_REFRESH, nowMs = Date.now()) {
  if (!productData.relatedLastUpdated) return false;

  const lastUpdate = productData.relatedLastUpdated.toDate ? productData.relatedLastUpdated.toDate() : new Date(productData.relatedLastUpdated);

  const daysSinceUpdate = (nowMs - lastUpdate.getTime()) / (1000 * 60 * 60 * 24);
  return daysSinceUpdate < dayThreshold;
}

function getDaysSinceUpdate(lastUpdated, nowMs = Date.now()) {
  if (!lastUpdated) return Infinity;

  const lastUpdateMs = lastUpdated.toDate ? lastUpdated.toDate().getTime() : new Date(lastUpdated).getTime();

  return (nowMs - lastUpdateMs) / (1000 * 60 * 60 * 24);
}

// ============================================================================
// ALGOLIA FILTER BUILDING
// ============================================================================

function buildPrimaryFilter(category, subcategory, gender) {
  if (!category || !subcategory) return null;

  const baseFilter = `category:"${category}" AND subcategory:"${subcategory}"`;
  
  if (gender) {
    return `${baseFilter} AND gender:"${gender}"`;
  }
  
  return baseFilter;
}

function buildSubsubcategoryFilter(category, subsubcategory) {
  if (!category || !subsubcategory) return null;
  return `category:"${category}" AND subsubcategory:"${subsubcategory}"`;
}

function buildPriceRangeFilter(category, price, rangePercent = 0.3) {
  if (!category || !price || price <= 0) return null;

  const priceMin = Math.floor(price * (1 - rangePercent));
  const priceMax = Math.ceil(price * (1 + rangePercent));
  
  return `category:"${category}" AND price:${priceMin} TO ${priceMax}`;
}

function getPriceRange(price, rangePercent = 0.3) {
  if (!price || price <= 0) return null;
  
  return {
    min: Math.floor(price * (1 - rangePercent)),
    max: Math.ceil(price * (1 + rangePercent)),
  };
}

// ============================================================================
// PRODUCT MAP OPERATIONS
// ============================================================================

function addProduct(map, hit, baseScore) {
  if (!map || !hit || !hit.objectID) return;

  const existing = map.get(hit.objectID);

  if (!existing) {
    map.set(hit.objectID, {
      baseScore,
      promotionScore: hit.promotionScore || 0,
      price: hit.price || 0,
      matchCount: 1,
    });
  } else {
    existing.baseScore = Math.max(existing.baseScore, baseScore);
    existing.matchCount++;
  }
}

function createProductEntry(hit, baseScore) {
  return {
    baseScore,
    promotionScore: hit.promotionScore || 0,
    price: hit.price || 0,
    matchCount: 1,
  };
}

function updateProductEntry(existing, baseScore) {
  return {
    ...existing,
    baseScore: Math.max(existing.baseScore, baseScore),
    matchCount: existing.matchCount + 1,
  };
}

// ============================================================================
// SCORING
// ============================================================================

function calculateFinalScore(data, originalProduct) {
  let score = data.baseScore || 0;

  // Match count bonus
  score += (data.matchCount || 0) * SCORE_WEIGHTS.MATCH_COUNT_BONUS;

  // Promotion score bonus
  score += (data.promotionScore || 0) * SCORE_WEIGHTS.PROMOTION_SCORE_WEIGHT;

  // Price similarity bonus
  if (originalProduct.price && data.price) {
    const priceDiff = Math.abs(data.price - originalProduct.price) / originalProduct.price;
    
    if (priceDiff < 0.2) {
      score += SCORE_WEIGHTS.PRICE_CLOSE_BONUS;
    } else if (priceDiff < 0.4) {
      score += SCORE_WEIGHTS.PRICE_MEDIUM_BONUS;
    }
  }

  return score;
}

function calculatePriceDifference(price1, price2) {
  if (!price1 || !price2 || price1 <= 0) return 1; // Max difference
  return Math.abs(price1 - price2) / price1;
}

function getPriceBonus(priceDiff) {
  if (priceDiff < 0.2) return SCORE_WEIGHTS.PRICE_CLOSE_BONUS;
  if (priceDiff < 0.4) return SCORE_WEIGHTS.PRICE_MEDIUM_BONUS;
  return 0;
}

function getBaseScoreForMatch(matchType, hasGenderMatch = false) {
  switch (matchType) {
    case 'primary':
      return hasGenderMatch ? SCORE_WEIGHTS.PRIMARY_WITH_GENDER : SCORE_WEIGHTS.PRIMARY_WITHOUT_GENDER;
    case 'subsubcategory':
      return SCORE_WEIGHTS.SUBSUBCATEGORY_MATCH;
    case 'price_range':
      return SCORE_WEIGHTS.PRICE_RANGE_MATCH;
    default:
      return 0;
  }
}

// ============================================================================
// RANKING
// ============================================================================

function rankAndLimitProducts(productMap, originalProduct, maxProducts = MAX_RELATED_PRODUCTS) {
  if (!productMap || productMap.size === 0) return [];

  const ranked = Array.from(productMap.entries())
    .map(([id, data]) => ({
      id,
      score: calculateFinalScore(data, originalProduct),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, maxProducts)
    .map((item) => item.id);

  return ranked;
}

function needsMoreProducts(currentCount, targetCount = MAX_RELATED_PRODUCTS) {
  return currentCount < targetCount;
}

// ============================================================================
// CIRCUIT BREAKER
// ============================================================================

function shouldTriggerCircuitBreaker(consecutiveErrors, maxErrors = MAX_CONSECUTIVE_ERRORS) {
  return consecutiveErrors >= maxErrors;
}

function calculateErrorRate(errors, processed) {
  if (processed <= 0) return 0;
  return errors / processed;
}

function isErrorRateAcceptable(errors, processed, threshold = ERROR_RATE_THRESHOLD) {
  if (processed <= 0) return true; // No processing, no errors
  return calculateErrorRate(errors, processed) <= threshold;
}

function getRetryDelay(attempt) {
  // Exponential backoff: 1s, 2s, 4s, ...
  return 1000 * Math.pow(2, attempt - 1);
}

function shouldRetry(attempt, maxAttempts = MAX_RETRY_ATTEMPTS) {
  return attempt < maxAttempts;
}

// ============================================================================
// CHECKPOINT
// ============================================================================

function buildCheckpointData(lastProcessedId) {
  return {
    lastProcessedId,
  };
}

function hasCheckpoint(checkpointData) {
  return checkpointData && checkpointData.lastProcessedId;
}

// ============================================================================
// RESULT DATA BUILDING
// ============================================================================

function buildRelatedProductsUpdate(productIds) {
  return {
    relatedProductIds: productIds,
    relatedCount: productIds.length,
  };
}

function buildLogEntry(type, processed, skipped, errors, duration) {
  return {
    type,
    processed,
    skipped,
    errors,
    duration: parseFloat(duration.toFixed(2)),
  };
}

function buildErrorLogEntry(type, error) {
  return {
    type,
    error: error.message || String(error),
    stack: error.stack || null,
  };
}

// ============================================================================
// STATISTICS
// ============================================================================

function calculateDuration(startTime, endTime = Date.now()) {
  return (endTime - startTime) / 1000;
}

function formatDuration(seconds) {
  return seconds.toFixed(2);
}

function buildSummary(processed, skipped, errors, duration) {
  return {
    processed,
    skipped,
    errors,
    total: processed + skipped + errors,
    duration,
    successRate: processed > 0 ? ((processed - errors) / processed * 100).toFixed(1) : '0.0',
  };
}

// ============================================================================
// FILTERING HITS
// ============================================================================

function filterSelfFromHits(hits, currentProductId) {
  if (!Array.isArray(hits)) return [];

  return hits.filter((hit) => {
    const cleanId = cleanAlgoliaId(hit.objectID);
    return cleanId !== currentProductId;
  });
}

function extractHitIds(hits) {
  if (!Array.isArray(hits)) return [];
  return hits.map((hit) => hit.objectID);
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  DEFAULT_BATCH_SIZE,
  DEFAULT_CONCURRENCY,
  MAX_CONSECUTIVE_ERRORS,
  MAX_RETRY_ATTEMPTS,
  DAYS_BEFORE_REFRESH,
  MAX_RELATED_PRODUCTS,
  TIMEOUT_MS,
  ERROR_RATE_THRESHOLD,
  ALGOLIA_PREFIXES,
  SCORE_WEIGHTS,

  // ID cleaning
  cleanAlgoliaId,
  cleanAlgoliaIds,
  hasAlgoliaPrefix,

  // Validation
  validateProductForRelated,
  isValidForRelatedProducts,

  // Skip logic
  shouldSkipProduct,
  getDaysSinceUpdate,

  // Filter building
  buildPrimaryFilter,
  buildSubsubcategoryFilter,
  buildPriceRangeFilter,
  getPriceRange,

  // Product map
  addProduct,
  createProductEntry,
  updateProductEntry,

  // Scoring
  calculateFinalScore,
  calculatePriceDifference,
  getPriceBonus,
  getBaseScoreForMatch,

  // Ranking
  rankAndLimitProducts,
  needsMoreProducts,

  // Circuit breaker
  shouldTriggerCircuitBreaker,
  calculateErrorRate,
  isErrorRateAcceptable,
  getRetryDelay,
  shouldRetry,

  // Checkpoint
  buildCheckpointData,
  hasCheckpoint,

  // Result building
  buildRelatedProductsUpdate,
  buildLogEntry,
  buildErrorLogEntry,

  // Statistics
  calculateDuration,
  formatDuration,
  buildSummary,

  // Hit filtering
  filterSelfFromHits,
  extractHitIds,
};
