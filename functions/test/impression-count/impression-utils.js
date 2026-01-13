// functions/test/impression-count/impression-utils.js
//
// EXTRACTED PURE LOGIC from impression count cloud functions
// These functions are EXACT COPIES of logic from the impression functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source impression functions.

// ============================================================================
// CONSTANTS
// ============================================================================

/**
 * Maximum unique products per request
 */
const MAX_UNIQUE_PRODUCTS = 100;

/**
 * Chunk size for Cloud Tasks
 */
const CHUNK_SIZE = 25;

/**
 * Maximum Firestore batch operations (with buffer)
 */
const MAX_BATCH_SIZE = 400;

/**
 * Firestore batch limit
 */
const FIRESTORE_BATCH_LIMIT = 500;

// ============================================================================
// INPUT VALIDATION
// Mirrors: validation in incrementImpressionCount
// ============================================================================


function validateProductIds(productIds) {
  if (!Array.isArray(productIds)) {
    return {
      isValid: false,
      reason: 'not_array',
      message: 'The function must be called with a non-empty array of productIds.',
    };
  }

  if (productIds.length === 0) {
    return {
      isValid: false,
      reason: 'empty_array',
      message: 'The function must be called with a non-empty array of productIds.',
    };
  }

  return {
    isValid: true,
    count: productIds.length,
  };
}


function validateWorkerRequest(data) {
  const products = data?.products || data?.data?.products;

  if (!Array.isArray(products) || products.length === 0) {
    return {
      isValid: false,
      reason: 'empty_products',
      message: 'Task received empty products',
    };
  }

  return {
    isValid: true,
    productCount: products.length,
  };
}

// ============================================================================
// DEDUPLICATION AND COUNTING
// Mirrors: deduplication logic in incrementImpressionCount
// ============================================================================


function deduplicateAndCount(productIds) {
  const productCounts = new Map();

  productIds.forEach((id) => {
    productCounts.set(id, (productCounts.get(id) || 0) + 1);
  });

  return Array.from(productCounts.entries()).map(([productId, count]) => ({
    productId,
    count,
  }));
}


function limitProducts(products, max = MAX_UNIQUE_PRODUCTS) {
  if (products.length <= max) {
    return {
      products,
      trimmed: false,
      originalCount: products.length,
    };
  }

  return {
    products: products.slice(0, max),
    trimmed: true,
    originalCount: products.length,
  };
}

// ============================================================================
// CHUNKING
// Mirrors: chunking logic in incrementImpressionCount
// ============================================================================


function chunkArray(array, size = CHUNK_SIZE) {
  const chunks = [];

  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }

  return chunks;
}


function calculateChunkCount(totalItems, chunkSize = CHUNK_SIZE) {
  return Math.ceil(totalItems / chunkSize);
}

// ============================================================================
// PRODUCT ID NORMALIZATION
// Mirrors: normalizeId in impressionqueueWorker
// ============================================================================

/**
 * Collection prefixes
 */
const COLLECTION_PREFIXES = {
  SHOP_PRODUCTS: 'shop_products_',
  PRODUCTS: 'products_',
};


function normalizeProductId(id) {
  if (!id || typeof id !== 'string') {
    return null;
  }

  if (id.startsWith(COLLECTION_PREFIXES.SHOP_PRODUCTS)) {
    return {
      collection: 'shop_products',
      id: id.slice(COLLECTION_PREFIXES.SHOP_PRODUCTS.length),
    };
  }

  if (id.startsWith(COLLECTION_PREFIXES.PRODUCTS)) {
    return {
      collection: 'products',
      id: id.slice(COLLECTION_PREFIXES.PRODUCTS.length),
    };
  }

  return null;
}

function hasKnownPrefix(id) {
  return normalizeProductId(id) !== null;
}


function getCollectionFromId(id) {
  const normalized = normalizeProductId(id);
  return normalized ? normalized.collection : null;
}

// ============================================================================
// GROUPING BY COLLECTION
// Mirrors: grouping logic in impressionqueueWorker
// ============================================================================


function groupByCollection(products) {
  const groups = {
    products: [],
    shop_products: [],
    unknown: [],
  };

  products.forEach(({ productId, count }) => {
    const norm = normalizeProductId(productId);
    if (norm) {
      groups[norm.collection].push({ id: norm.id, count });
    } else {
      groups.unknown.push({ id: productId, count });
    }
  });

  return groups;
}


function countByCollection(groups) {
  return {
    products: groups.products.length,
    shop_products: groups.shop_products.length,
    unknown: groups.unknown.length,
    total: groups.products.length + groups.shop_products.length + groups.unknown.length,
  };
}

// ============================================================================
// AGE GROUP CALCULATION
// Mirrors: getAgeGroup in impressionqueueWorker
// ============================================================================

/**
 * Age group boundaries and labels
 */
const AGE_GROUPS = {
  UNDER_18: 'under18',
  AGE_18_24: '18-24',
  AGE_25_34: '25-34',
  AGE_35_44: '35-44',
  AGE_45_54: '45-54',
  AGE_55_PLUS: '55plus',
  UNKNOWN: 'unknown',
};


function getAgeGroup(age) {
  if (!age) return AGE_GROUPS.UNKNOWN;
  if (age < 18) return AGE_GROUPS.UNDER_18;
  if (age < 25) return AGE_GROUPS.AGE_18_24;
  if (age < 35) return AGE_GROUPS.AGE_25_34;
  if (age < 45) return AGE_GROUPS.AGE_35_44;
  if (age < 55) return AGE_GROUPS.AGE_45_54;
  return AGE_GROUPS.AGE_55_PLUS;
}


function getAllAgeGroups() {
  return Object.values(AGE_GROUPS);
}

function isValidAgeGroup(ageGroup) {
  return getAllAgeGroups().includes(ageGroup);
}

// ============================================================================
// GENDER NORMALIZATION
// Mirrors: gender normalization in impressionqueueWorker
// ============================================================================


function normalizeGender(gender) {
  return (gender || 'unknown').toLowerCase();
}

// ============================================================================
// BOOSTED PRODUCT CLASSIFICATION
// Mirrors: boosted product logic in impressionqueueWorker
// ============================================================================


function isBoostedProduct(productData) {
  return !!(productData?.isBoosted && productData?.boostStartTime);
}

function classifyProducts(resolvedProducts) {
  const boostedUserProducts = {};   // userId -> products
  const boostedShopProducts = {};   // shopId -> products
  const regularProducts = [];

  resolvedProducts.forEach(({ ref, data, collection, count }) => {
    if (isBoostedProduct(data)) {
      if (collection === 'shop_products' && data.shopId) {
        if (!boostedShopProducts[data.shopId]) {
          boostedShopProducts[data.shopId] = [];
        }
        boostedShopProducts[data.shopId].push({
          ref,
          data,
          itemId: ref?.id,
          boostStartTime: data.boostStartTime,
          count,
        });
      } else if (collection === 'products' && data.userId) {
        if (!boostedUserProducts[data.userId]) {
          boostedUserProducts[data.userId] = [];
        }
        boostedUserProducts[data.userId].push({
          ref,
          data,
          itemId: ref?.id,
          boostStartTime: data.boostStartTime,
          count,
        });
      } else {
        // Boosted but no owner info
        regularProducts.push({ ref, data, isBoosted: true, count });
      }
    } else {
      regularProducts.push({ ref, data, isBoosted: false, count });
    }
  });

  return {
    boostedUserProducts,
    boostedShopProducts,
    regularProducts,
  };
}

// ============================================================================
// BATCH SIZE MANAGEMENT
// Mirrors: batch management in impressionqueueWorker
// ============================================================================


function shouldCommitBatch(currentCount, maxSize = MAX_BATCH_SIZE) {
  return currentCount >= maxSize;
}


function calculateOperationsNeeded(productCount, boostHistoryCount = 0) {
  // Each product update = 1 operation
  // Each boost history update = 1 operation
  return productCount + boostHistoryCount;
}


function willFitInBatch(currentCount, neededOperations, maxSize = MAX_BATCH_SIZE) {
  return (currentCount + neededOperations) <= maxSize;
}

// ============================================================================
// DEMOGRAPHICS FIELD PATHS
// Mirrors: field paths in impressionqueueWorker
// ============================================================================


function buildDemographicsPath(gender) {
  return `demographics.${gender}`;
}


function buildAgeGroupPath(ageGroup) {
  return `viewerAgeGroups.${ageGroup}`;
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================


function buildSuccessResponse(queuedCount, totalImpressions) {
  return {
    success: true,
    queued: queuedCount,
    totalImpressions,
    message: 'Impressions are being recorded',
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  MAX_UNIQUE_PRODUCTS,
  CHUNK_SIZE,
  MAX_BATCH_SIZE,
  FIRESTORE_BATCH_LIMIT,
  COLLECTION_PREFIXES,
  AGE_GROUPS,

  // Validation
  validateProductIds,
  validateWorkerRequest,

  // Deduplication
  deduplicateAndCount,
  limitProducts,

  // Chunking
  chunkArray,
  calculateChunkCount,

  // Product ID normalization
  normalizeProductId,
  hasKnownPrefix,
  getCollectionFromId,

  // Grouping
  groupByCollection,
  countByCollection,

  // Age group
  getAgeGroup,
  getAllAgeGroups,
  isValidAgeGroup,

  // Gender
  normalizeGender,

  // Boosted products
  isBoostedProduct,
  classifyProducts,

  // Batch management
  shouldCommitBatch,
  calculateOperationsNeeded,
  willFitInBatch,

  // Field paths
  buildDemographicsPath,
  buildAgeGroupPath,

  // Response
  buildSuccessResponse,
};
