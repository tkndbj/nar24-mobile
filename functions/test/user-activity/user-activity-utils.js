// functions/test/user-activity/user-activity-utils.js
//
// EXTRACTED PURE LOGIC from user activity tracking cloud functions
// These functions are EXACT COPIES of logic from the user activity functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const ACTIVITY_WEIGHTS = {
    click: 1,
    view: 2,
    addToCart: 5,
    removeFromCart: -2,
    favorite: 3,
    unfavorite: -1,
    purchase: 10,
    search: 1,
  };
  
  const CONFIG = {
    RATE_LIMIT_WINDOW_MS: 60000,
    RATE_LIMIT_MAX_REQUESTS: 20,
    MAX_EVENTS_PER_BATCH: 100,
    MAX_EVENT_AGE_MS: 24 * 60 * 60 * 1000, // 24 hours
    RETENTION_DAYS: 90,
    DLQ_MAX_RETRIES: 5,
    MAX_CATEGORIES: 100,
    MAX_BRANDS: 50,
    MIN_SCORE_THRESHOLD: 5,
    TOP_CATEGORIES_COUNT: 10,
    TOP_BRANDS_COUNT: 10,
    MAX_RECENT_PRODUCTS: 20,
  };
  
  const TRACKABLE_PRODUCT_EVENTS = ['click', 'view', 'addToCart', 'favorite'];
  
  // ============================================================================
  // EVENT VALIDATION
  // ============================================================================
  
  function isValidEventType(type) {
    return Object.hasOwn(ACTIVITY_WEIGHTS, type);
  }
  
  function getEventWeight(type) {
    return ACTIVITY_WEIGHTS[type] || 0;
  }
  
  function isEventTooOld(eventTimestamp, maxAgeMs = CONFIG.MAX_EVENT_AGE_MS, now = Date.now()) {
    return (now - eventTimestamp) > maxAgeMs;
  }
  
  function validateEvent(event, now = Date.now()) {
    const errors = [];
  
    if (!event) {
      return { isValid: false, errors: ['Event is required'] };
    }
  
    if (!event.eventId) {
      errors.push('Missing eventId');
    }
  
    if (!event.type) {
      errors.push('Missing type');
    } else if (!isValidEventType(event.type)) {
      errors.push(`Invalid event type: ${event.type}`);
    }
  
    if (!event.timestamp) {
      errors.push('Missing timestamp');
    } else if (isEventTooOld(event.timestamp, CONFIG.MAX_EVENT_AGE_MS, now)) {
      errors.push('Event too old');
    }
  
    if (errors.length > 0) {
      return { isValid: false, errors };
    }
  
    return { isValid: true };
  }
  
  function validateEvents(events) {
    if (!Array.isArray(events)) {
      return { isValid: false, reason: 'not_array' };
    }
  
    if (events.length === 0) {
      return { isValid: false, reason: 'empty' };
    }
  
    if (events.length > CONFIG.MAX_EVENTS_PER_BATCH) {
      return { isValid: false, reason: 'too_many', message: `Maximum ${CONFIG.MAX_EVENTS_PER_BATCH} events per batch` };
    }
  
    return { isValid: true };
  }
  
  function filterValidEvents(events, now = Date.now()) {
    if (!Array.isArray(events)) return [];
  
    return events.filter((event) => {
      if (!event.eventId || !event.type || !event.timestamp) return false;
      if (!isValidEventType(event.type)) return false;
      if (isEventTooOld(event.timestamp, CONFIG.MAX_EVENT_AGE_MS, now)) return false;
      return true;
    });
  }
  
  // ============================================================================
  // KEY SANITIZATION
  // ============================================================================
  
  function sanitizeFirestoreKey(key) {
    if (!key || typeof key !== 'string') return '';
    return key.replace(/[./]/g, '_');
  }
  
  function sanitizeSearchQuery(query) {
    if (!query || typeof query !== 'string') return '';
    return query
      .toLowerCase()
      .trim()
      .substring(0, 50)
      .replace(/[./]/g, '_');
  }
  
  // ============================================================================
  // SCORE AGGREGATION
  // ============================================================================
  
  function createScoreMap() {
    return new Map();
  }
  
  function addScore(scoreMap, key, score) {
    if (!key || score <= 0) return; // Only add positive scores
    const current = scoreMap.get(key) || 0;
    scoreMap.set(key, current + score);
  }
  
  function aggregateCategoryScores(events) {
    const scores = createScoreMap();
  
    for (const event of events) {
      const weight = getEventWeight(event.type);
      if (weight <= 0) continue; // Only positive weights
  
      if (event.category) {
        addScore(scores, event.category, weight);
      }
      if (event.subcategory) {
        addScore(scores, event.subcategory, weight);
      }
    }
  
    return scores;
  }
  
  function aggregateBrandScores(events) {
    const scores = createScoreMap();
  
    for (const event of events) {
      const weight = getEventWeight(event.type);
      if (weight <= 0) continue; // Only positive weights
  
      if (event.brand) {
        addScore(scores, event.brand, weight);
      }
    }
  
    return scores;
  }
  
  function aggregateAllScores(events) {
    return {
      categoryScores: aggregateCategoryScores(events),
      brandScores: aggregateBrandScores(events),
    };
  }
  
  // ============================================================================
  // RECENT PRODUCTS
  // ============================================================================
  
  function isTrackableProductEvent(type) {
    return TRACKABLE_PRODUCT_EVENTS.includes(type);
  }
  
  function extractRecentProducts(events, limit = CONFIG.MAX_RECENT_PRODUCTS) {
    const products = [];
  
    for (const event of events) {
      if (event.productId && isTrackableProductEvent(event.type)) {
        products.push({
          productId: event.productId,
          timestamp: event.timestamp,
        });
      }
    }
  
    // Sort by timestamp descending and limit
    return products
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, limit);
  }
  
  // ============================================================================
  // PURCHASE TRACKING
  // ============================================================================
  
  function extractPurchaseStats(events) {
    let count = 0;
    let totalValue = 0;
  
    for (const event of events) {
      if (event.type === 'purchase') {
        count++;
        totalValue += event.totalValue || 0;
      }
    }
  
    return { count, totalValue };
  }
  
  function calculateItemTotal(price, quantity) {
    return (price || 0) * (quantity || 1);
  }
  
  // ============================================================================
  // SEARCH TRACKING
  // ============================================================================
  
  function extractSearchQueries(events) {
    const queries = [];
  
    for (const event of events) {
      if (event.type === 'search' && event.searchQuery) {
        queries.push(event.searchQuery);
      }
    }
  
    return queries;
  }
  
  // ============================================================================
  // TOP N EXTRACTION
  // ============================================================================
  
  function getTopN(scoreMap, n) {
    return Array.from(scoreMap.entries())
      .map(([key, score]) => ({ key, score }))
      .sort((a, b) => b.score - a.score)
      .slice(0, n);
  }
  
  function getTopCategories(categoryScores, n = CONFIG.TOP_CATEGORIES_COUNT) {
    return getTopN(categoryScores, n).map(({ key, score }) => ({
      category: key,
      score,
    }));
  }
  
  function getTopBrands(brandScores, n = CONFIG.TOP_BRANDS_COUNT) {
    return getTopN(brandScores, n).map(({ key, score }) => ({
      brand: key,
      score,
    }));
  }
  
  // ============================================================================
  // SCORE PRUNING
  // ============================================================================
  
  function pruneScores(scores, maxEntries, minScore = CONFIG.MIN_SCORE_THRESHOLD) {
    if (!scores || typeof scores !== 'object') return {};
  
    const entries = Object.entries(scores);
  
    // Sort by score descending, take top N, filter by min score
    const pruned = {};
    entries
      .sort((a, b) => b[1] - a[1])
      .slice(0, maxEntries)
      .forEach(([key, score]) => {
        if (score >= minScore) {
          pruned[key] = score;
        }
      });
  
    return pruned;
  }
  
  function pruneCategoryScores(scores) {
    return pruneScores(scores, CONFIG.MAX_CATEGORIES, CONFIG.MIN_SCORE_THRESHOLD);
  }
  
  function pruneBrandScores(scores) {
    return pruneScores(scores, CONFIG.MAX_BRANDS, CONFIG.MIN_SCORE_THRESHOLD);
  }
  
  // ============================================================================
  // AVERAGE CALCULATION
  // ============================================================================
  
  function calculateAveragePurchasePrice(totalSpent, totalPurchases) {
    if (!totalPurchases || totalPurchases <= 0) return null;
    return totalSpent / totalPurchases;
  }
  
  // ============================================================================
  // RATE LIMITING
  // ============================================================================
  
  function createRateLimitEntry(now = Date.now()) {
    return { count: 1, windowStart: now };
  }
  
  function isRateLimitWindowExpired(windowStart, windowMs = CONFIG.RATE_LIMIT_WINDOW_MS, now = Date.now()) {
    return (now - windowStart) > windowMs;
  }
  
  function isRateLimited(entry, maxRequests = CONFIG.RATE_LIMIT_MAX_REQUESTS, windowMs = CONFIG.RATE_LIMIT_WINDOW_MS, now = Date.now()) {
    if (!entry) return false;
  
    if (isRateLimitWindowExpired(entry.windowStart, windowMs, now)) {
      return false; // Window expired, not limited
    }
  
    return entry.count >= maxRequests;
  }
  
  function shouldCleanupRateLimitEntry(windowStart, cleanupMultiplier = 2, windowMs = CONFIG.RATE_LIMIT_WINDOW_MS, now = Date.now()) {
    return (now - windowStart) > (windowMs * cleanupMultiplier);
  }
  
  // ============================================================================
  // DLQ (DEAD LETTER QUEUE)
  // ============================================================================
  
  function shouldRetryDLQItem(retryCount, maxRetries = CONFIG.DLQ_MAX_RETRIES) {
    return retryCount < maxRetries;
  }
  
  function getDLQStatus(retryCount, maxRetries = CONFIG.DLQ_MAX_RETRIES) {
    if (retryCount >= maxRetries) return 'failed';
    return 'pending';
  }
  
  function buildDLQEntry(userId, events, error) {
    return {
      userId,
      events,
      error: error?.message || 'Unknown error',
      retryCount: 0,
      status: 'pending',
    };
  }
  
  // ============================================================================
  // RETRY LOGIC
  // ============================================================================
  
  function getRetryDelay(attempt, baseDelay = 100) {
    return baseDelay * Math.pow(2, attempt - 1);
  }
  
  function shouldRetryError(errorCode) {
    // Don't retry validation or permission errors
    if (errorCode === 'invalid-argument') return false;
    if (errorCode === 'permission-denied') return false;
    return true;
  }
  
  // ============================================================================
  // DATE HELPERS
  // ============================================================================
  
  function getTodayDateString(now = new Date()) {
    return now.toISOString().split('T')[0];
  }
  
  function getRetentionCutoffDate(retentionDays = CONFIG.RETENTION_DAYS, now = new Date()) {
    const cutoff = new Date(now);
    cutoff.setDate(cutoff.getDate() - retentionDays);
    return cutoff.toISOString().split('T')[0];
  }
  
  function getDLQCleanupCutoff(days = 7, now = new Date()) {
    const cutoff = new Date(now);
    cutoff.setDate(cutoff.getDate() - days);
    return cutoff;
  }
  
  // ============================================================================
  // PROFILE UPDATE BUILDING
  // ============================================================================
  
  function buildCategoryScoresUpdate(categoryScores) {
    if (categoryScores.size === 0) return null;
  
    const update = {};
    for (const [category, score] of categoryScores.entries()) {
      const safeKey = sanitizeFirestoreKey(category);
      if (safeKey) {
        update[safeKey] = score;
      }
    }
  
    return Object.keys(update).length > 0 ? update : null;
  }
  
  function buildBrandScoresUpdate(brandScores) {
    if (brandScores.size === 0) return null;
  
    const update = {};
    for (const [brand, score] of brandScores.entries()) {
      const safeKey = sanitizeFirestoreKey(brand);
      if (safeKey) {
        update[safeKey] = score;
      }
    }
  
    return Object.keys(update).length > 0 ? update : null;
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Constants
    ACTIVITY_WEIGHTS,
    CONFIG,
    TRACKABLE_PRODUCT_EVENTS,
  
    // Event validation
    isValidEventType,
    getEventWeight,
    isEventTooOld,
    validateEvent,
    validateEvents,
    filterValidEvents,
  
    // Key sanitization
    sanitizeFirestoreKey,
    sanitizeSearchQuery,
  
    // Score aggregation
    createScoreMap,
    addScore,
    aggregateCategoryScores,
    aggregateBrandScores,
    aggregateAllScores,
  
    // Recent products
    isTrackableProductEvent,
    extractRecentProducts,
  
    // Purchase tracking
    extractPurchaseStats,
    calculateItemTotal,
  
    // Search tracking
    extractSearchQueries,
  
    // Top N extraction
    getTopN,
    getTopCategories,
    getTopBrands,
  
    // Score pruning
    pruneScores,
    pruneCategoryScores,
    pruneBrandScores,
  
    // Average calculation
    calculateAveragePurchasePrice,
  
    // Rate limiting
    createRateLimitEntry,
    isRateLimitWindowExpired,
    isRateLimited,
    shouldCleanupRateLimitEntry,
  
    // DLQ
    shouldRetryDLQItem,
    getDLQStatus,
    buildDLQEntry,
  
    // Retry logic
    getRetryDelay,
    shouldRetryError,
  
    // Date helpers
    getTodayDateString,
    getRetentionCutoffDate,
    getDLQCleanupCutoff,
  
    // Profile update building
    buildCategoryScoresUpdate,
    buildBrandScoresUpdate,
  };
