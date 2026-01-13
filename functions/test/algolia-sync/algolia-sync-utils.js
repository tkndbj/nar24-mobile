// functions/test/algolia-sync/algolia-sync-utils.js
//
// EXTRACTED PURE LOGIC from Algolia sync cloud functions
// These functions are EXACT COPIES of logic from the sync functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source sync functions.

// ============================================================================
// SUPPORTED LOCALES
// ============================================================================

const SUPPORTED_LOCALES = ['en', 'tr', 'ru'];

// ============================================================================
// OBJECT ID GENERATION
// Mirrors: objectID creation in syncDocumentToAlgolia
// ============================================================================


function generateObjectID(collectionName, documentId) {
  return `${collectionName}_${documentId}`;
}

function parseObjectID(objectID) {
  if (!objectID || typeof objectID !== 'string') return null;

  const underscoreIndex = objectID.indexOf('_');
  if (underscoreIndex === -1) return null;

  return {
    collectionName: objectID.substring(0, underscoreIndex),
    documentId: objectID.substring(underscoreIndex + 1),
  };
}

// ============================================================================
// SYNC ACTION DETECTION
// Mirrors: logic in syncDocumentToAlgolia
// ============================================================================

/**
 * Sync action types
 */
const SYNC_ACTIONS = {
  CREATE: 'create',
  UPDATE: 'update',
  DELETE: 'delete',
  NONE: 'none',
};


function detectSyncAction(beforeData, afterData) {
  if (!beforeData && afterData) {
    return SYNC_ACTIONS.CREATE;
  } else if (beforeData && afterData) {
    return SYNC_ACTIONS.UPDATE;
  } else if (beforeData && !afterData) {
    return SYNC_ACTIONS.DELETE;
  }
  return SYNC_ACTIONS.NONE;
}

// ============================================================================
// RELEVANT CHANGES DETECTION
// Mirrors: hasRelevantChanges logic in sync functions
// ============================================================================

/**
 * Search fields for products collection
 */
const PRODUCT_SEARCH_FIELDS = [
  'productName', 'category', 'subcategory',
  'price', 'description', 'brandModel',
  'subsubcategory', 'averageRating',
];

/**
 * Search fields for shop_products collection
 */
const SHOP_PRODUCT_SEARCH_FIELDS = [
  'productName', 'category', 'subcategory',
  'price', 'description', 'brandModel',
  'subsubcategory', 'averageRating',
  'discountPercentage', 'campaignName', 'isBoosted',
];

/**
 * Relevant fields for shops collection
 */
const SHOP_RELEVANT_FIELDS = ['name', 'profileImageUrl', 'isActive'];

/**
 * Search fields for orders collection
 */
const ORDER_SEARCH_FIELDS = [
  'productName', 'category', 'subcategory', 'subsubcategory',
  'price', 'brandModel', 'condition', 'shipmentStatus',
  'buyerName', 'sellerName',
  'needsAnyReview', 'needsProductReview', 'needsSellerReview',
];


function hasRelevantChanges(beforeData, afterData, fields) {
  if (!beforeData || !afterData || !Array.isArray(fields)) {
    return true; // If we can't compare, assume changes
  }

  return fields.some((field) => beforeData[field] !== afterData[field]);
}


function shouldSyncProduct(beforeData, afterData) {
  // Always sync creates and deletes
  if (!beforeData || !afterData) return true;

  return hasRelevantChanges(beforeData, afterData, PRODUCT_SEARCH_FIELDS);
}


function shouldSyncShopProduct(beforeData, afterData) {
  if (!beforeData || !afterData) return true;

  return hasRelevantChanges(beforeData, afterData, SHOP_PRODUCT_SEARCH_FIELDS);
}


function shouldSyncShop(beforeData, afterData) {
  if (!beforeData || !afterData) return true;

  return hasRelevantChanges(beforeData, afterData, SHOP_RELEVANT_FIELDS);
}


function shouldSyncOrder(beforeData, afterData) {
  if (!beforeData || !afterData) return true;

  return hasRelevantChanges(beforeData, afterData, ORDER_SEARCH_FIELDS);
}

// ============================================================================
// LOCALIZED FIELDS BUILDING
// Mirrors: localized field building in sync functions
// ============================================================================


function buildLocalizedFieldName(fieldName, locale) {
  return `${fieldName}_${locale}`;
}


function buildLocalizedField(fieldType, fieldName, value, locales, localizeFn) {
  const result = {};

  if (!value) return result;

  for (const locale of locales) {
    const localizedKey = buildLocalizedFieldName(fieldName, locale);
    try {
      result[localizedKey] = localizeFn(fieldType, value, locale);
    } catch (error) {
      // Fallback to original value on error
      result[localizedKey] = value;
    }
  }

  return result;
}


function buildLocalizedArrayField(fieldType, fieldName, values, locales, localizeFn) {
  const result = {};

  if (!Array.isArray(values) || values.length === 0) return result;

  for (const locale of locales) {
    const localizedKey = buildLocalizedFieldName(fieldName, locale);
    result[localizedKey] = values.map((val) => {
      try {
        return localizeFn(fieldType, val, locale);
      } catch (error) {
        return val;
      }
    });
  }

  return result;
}


function buildProductLocalizedFields(productData, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  let result = {};

  // Category
  if (productData.category) {
    result = {
      ...result,
      ...buildLocalizedField('category', 'category', productData.category, locales, localizeFn),
    };
  }

  // Subcategory
  if (productData.subcategory) {
    result = {
      ...result,
      ...buildLocalizedField('subcategory', 'subcategory', productData.subcategory, locales, localizeFn),
    };
  }

  // Subsubcategory
  if (productData.subsubcategory) {
    result = {
      ...result,
      ...buildLocalizedField('subSubcategory', 'subsubcategory', productData.subsubcategory, locales, localizeFn),
    };
  }

  // Jewelry type (single)
  if (productData.jewelryType) {
    result = {
      ...result,
      ...buildLocalizedField('jewelryType', 'jewelryType', productData.jewelryType, locales, localizeFn),
    };
  }

  // Jewelry materials (array)
  if (Array.isArray(productData.jewelryMaterials)) {
    result = {
      ...result,
      ...buildLocalizedArrayField('jewelryMaterial', 'jewelryMaterials', productData.jewelryMaterials, locales, localizeFn),
    };
  }

  return result;
}


function buildShopLocalizedFields(shopData, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  if (!Array.isArray(shopData.categories)) return {};

  return buildLocalizedArrayField('category', 'categories', shopData.categories, locales, localizeFn);
}


function buildOrderLocalizedFields(orderData, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  let result = {};

  // Category
  if (orderData.category) {
    result = {
      ...result,
      ...buildLocalizedField('category', 'category', orderData.category, locales, localizeFn),
    };
  }

  // Subcategory
  if (orderData.subcategory) {
    result = {
      ...result,
      ...buildLocalizedField('subcategory', 'subcategory', orderData.subcategory, locales, localizeFn),
    };
  }

  // Subsubcategory
  if (orderData.subsubcategory) {
    result = {
      ...result,
      ...buildLocalizedField('subSubcategory', 'subsubcategory', orderData.subsubcategory, locales, localizeFn),
    };
  }

  // Condition
  if (orderData.condition) {
    result = {
      ...result,
      ...buildLocalizedField('condition', 'condition', orderData.condition, locales, localizeFn),
    };
  }

  // Shipment status
  if (orderData.shipmentStatus) {
    result = {
      ...result,
      ...buildLocalizedField('shipmentStatus', 'shipmentStatus', orderData.shipmentStatus, locales, localizeFn),
    };
  }

  return result;
}

// ============================================================================
// SEARCHABLE TEXT BUILDING
// Mirrors: searchableText creation in sync functions
// ============================================================================


function buildSearchableText(fields) {
  return fields.filter(Boolean).join(' ');
}


function buildShopSearchableText(shopData) {
  return buildSearchableText([
    shopData.name,
    ...(shopData.categories || []),
  ]);
}


function buildOrderSearchableText(orderData) {
  return buildSearchableText([
    orderData.productName,
    orderData.buyerName,
    orderData.sellerName,
    orderData.brandModel,
    orderData.category,
    orderData.subcategory,
    orderData.subsubcategory,
    orderData.condition,
    orderData.shipmentStatus,
  ]);
}

// ============================================================================
// MINIMAL DATA EXTRACTION
// Mirrors: minimal data building in syncShopsWithAlgolia
// ============================================================================


function buildMinimalShopData(shopData) {
  if (!shopData) return null;

  return {
    name: shopData.name,
    profileImageUrl: shopData.profileImageUrl || null,
    categories: shopData.categories || [],
    isActive: shopData.isActive ?? true,
  };
}


function buildShopAlgoliaDocument(shopData, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  const minimal = buildMinimalShopData(shopData);
  if (!minimal) return null;

  const localizedFields = buildShopLocalizedFields(shopData, locales, localizeFn);
  const searchableText = buildShopSearchableText(shopData);

  return {
    ...minimal,
    ...localizedFields,
    searchableText,
  };
}

// ============================================================================
// AUGMENTED ORDER DATA
// Mirrors: augmented order building in syncOrdersWithAlgolia
// ============================================================================


function calculateItemTotal(price, quantity) {
  return (price || 0) * (quantity || 1);
}


function getTimestampForSorting(timestamp) {
  if (timestamp?.seconds) {
    return timestamp.seconds;
  }
  return Math.floor(Date.now() / 1000);
}


function buildAugmentedOrderItem(itemData, orderData = {}, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  const localizedFields = buildOrderLocalizedFields(itemData, locales, localizeFn);
  const searchableText = buildOrderSearchableText(itemData);

  return {
    ...itemData,
    ...localizedFields,
    // Order-level data
    orderTotalPrice: orderData.totalPrice || 0,
    orderTotalQuantity: orderData.totalQuantity || 0,
    orderPaymentMethod: orderData.paymentMethod || '',
    orderTimestamp: orderData.timestamp || itemData.timestamp,
    orderAddress: orderData.address || null,
    // Calculated fields
    itemTotal: calculateItemTotal(itemData.price, itemData.quantity),
    searchableText,
    timestampForSorting: getTimestampForSorting(itemData.timestamp),
  };
}

// ============================================================================
// PRODUCT AUGMENTATION
// ============================================================================


function buildAugmentedProduct(productData, locales = SUPPORTED_LOCALES, localizeFn = (t, v) => v) {
  const localizedFields = buildProductLocalizedFields(productData, locales, localizeFn);

  return {
    ...productData,
    ...localizedFields,
  };
}

// ============================================================================
// ALGOLIA DOCUMENT BUILDING
// ============================================================================


function buildAlgoliaDocument(collectionName, documentId, data) {
  return {
    objectID: generateObjectID(collectionName, documentId),
    ...data,
    collection: collectionName,
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  SUPPORTED_LOCALES,
  SYNC_ACTIONS,
  PRODUCT_SEARCH_FIELDS,
  SHOP_PRODUCT_SEARCH_FIELDS,
  SHOP_RELEVANT_FIELDS,
  ORDER_SEARCH_FIELDS,

  // Object ID
  generateObjectID,
  parseObjectID,

  // Sync action
  detectSyncAction,

  // Relevant changes
  hasRelevantChanges,
  shouldSyncProduct,
  shouldSyncShopProduct,
  shouldSyncShop,
  shouldSyncOrder,

  // Localized fields
  buildLocalizedFieldName,
  buildLocalizedField,
  buildLocalizedArrayField,
  buildProductLocalizedFields,
  buildShopLocalizedFields,
  buildOrderLocalizedFields,

  // Searchable text
  buildSearchableText,
  buildShopSearchableText,
  buildOrderSearchableText,

  // Minimal/augmented data
  buildMinimalShopData,
  buildShopAlgoliaDocument,
  calculateItemTotal,
  getTimestampForSorting,
  buildAugmentedOrderItem,
  buildAugmentedProduct,

  // Document building
  buildAlgoliaDocument,
};
