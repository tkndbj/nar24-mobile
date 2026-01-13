// functions/src/utils/purchase-utils.js
//
// EXTRACTED PURE LOGIC from purchase cloud functions
// These functions are EXACT COPIES of logic from the main purchase functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source purchase functions.
// Any changes to business logic in the main functions should be reflected here.
//
// Usage in main functions:
//   const { validateAddress, validateStock, ... } = require('./utils/purchase-utils');
//
// Usage in tests:
//   const { validateAddress, validateStock, ... } = require('../src/utils/purchase-utils');

const crypto = require('crypto');

// ============================================================================
// SHOP MEMBER EXTRACTION
// Mirrors: getShopMemberIdsFromData() in purchase functions
// ============================================================================

function getShopMemberIdsFromData(shopData) {
  if (!shopData) return [];

  const memberIds = [];
  if (shopData.ownerId) memberIds.push(shopData.ownerId);
  if (Array.isArray(shopData.coOwners)) memberIds.push(...shopData.coOwners);
  if (Array.isArray(shopData.editors)) memberIds.push(...shopData.editors);
  if (Array.isArray(shopData.viewers)) memberIds.push(...shopData.viewers);

  return [...new Set(memberIds)];
}

// ============================================================================
// OBJECT SANITIZATION
// Mirrors: removeUndefined() in purchase functions
// ============================================================================

function removeUndefined(obj, options = {}) {
  const {
    isTimestamp = (v) => v && v.constructor && v.constructor.name === 'Timestamp',
    isGeoPoint = (v) => v && v.constructor && v.constructor.name === 'GeoPoint',
    isFieldValue = (v) => v && v.constructor && v.constructor.name === 'FieldValue',
  } = options;

  if (Array.isArray(obj)) {
    return obj.map((item) => removeUndefined(item, options));
  }

  if (!obj || typeof obj !== 'object') {
    return obj;
  }

  // Preserve Firestore special types
  if (isTimestamp(obj) || isGeoPoint(obj)) {
    return obj;
  }

  if (isFieldValue(obj)) {
    return obj;
  }

  const cleaned = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined) {
      if (isFieldValue(value)) {
        cleaned[key] = value;
      } else if (value && typeof value === 'object') {
        cleaned[key] = removeUndefined(value, options);
      } else {
        cleaned[key] = value;
      }
    }
  }
  return cleaned;
}

// ============================================================================
// HASH GENERATION FOR ISBANK
// Mirrors: generateHashVer3() in purchase functions
// ============================================================================

function generateHashVer3(params, storeKey) {
  // Get all parameter keys except 'hash' and 'encoding'
  const keys = Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => {
      // Case-insensitive sort - convert both to lowercase for comparison
      return a.toLowerCase().localeCompare(b.toLowerCase());
    });

  // Build the plain text with pipe separators
  const values = keys.map((key) => {
    let value = String(params[key] || '');
    // Escape special characters as per documentation
    value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
    return value;
  });

  const plainText = values.join('|') + '|' + storeKey;

  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

function getHashKeyOrder(params) {
  return Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
}

function buildHashPlainText(params, storeKey) {
  const keys = getHashKeyOrder(params);

  const values = keys.map((key) => {
    let value = String(params[key] || '');
    value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
    return value;
  });

  return values.join('|') + '|' + storeKey;
}

// ============================================================================
// PAYMENT STATUS VALIDATION
// Mirrors: isbankPaymentCallback status checks
// ============================================================================

/**
 * Valid 3D Secure authentication status codes
 * '1' = Full 3D authentication successful
 * '2' = Card not enrolled, proceeding without 3D
 * '3' = Card issuer not participating in 3D
 * '4' = Cardholder not enrolled, proceeding without 3D
 */
const VALID_MD_STATUS_CODES = ['1', '2', '3', '4'];

function isAuthSuccess(mdStatus) {
  return VALID_MD_STATUS_CODES.includes(mdStatus);
}


function isTransactionSuccess(response, procReturnCode) {
  return response === 'Approved' && procReturnCode === '00';
}

function validatePaymentStatus(paymentResponse) {
  const { Response, mdStatus, ProcReturnCode, ErrMsg } = paymentResponse;

  const authOk = isAuthSuccess(mdStatus);
  const transactionOk = isTransactionSuccess(Response, ProcReturnCode);

  if (!authOk) {
    return {
      isSuccess: false,
      reason: 'auth_failed',
      message: `3D authentication failed with status: ${mdStatus}`,
    };
  }

  if (!transactionOk) {
    return {
      isSuccess: false,
      reason: 'transaction_failed',
      message: ErrMsg || `Transaction failed: ${Response} (${ProcReturnCode})`,
    };
  }

  return {
    isSuccess: true,
    reason: 'approved',
    message: 'Payment approved',
  };
}

// ============================================================================
// PAYMENT HASH VERIFICATION
// Mirrors: isbankPaymentCallback hash verification
// ============================================================================

function verifyCallbackHash(receivedHash, hashParamsVal, storeKey) {
  if (!hashParamsVal || !receivedHash) {
    return {
      isValid: null, // Cannot verify without params
      skipped: true,
      message: 'Hash verification skipped - missing HASHPARAMSVAL',
    };
  }

  const hashParams = hashParamsVal + storeKey;
  const calculatedHash = crypto.createHash('sha512').update(hashParams, 'utf8').digest('base64');

  return {
    isValid: calculatedHash === receivedHash,
    skipped: false,
    calculatedHash,
    receivedHash,
  };
}

// ============================================================================
// CUSTOMER NAME SANITIZATION
// Mirrors: initializeIsbankPayment name sanitization
// ============================================================================

function sanitizeCustomerName(customerName, transliterateFn = (s) => s) {
  if (!customerName) return 'Customer';

  const sanitized = transliterateFn(customerName)
    .replace(/[^a-zA-Z0-9\s]/g, '')
    .trim()
    .substring(0, 50);

  return sanitized || 'Customer'; // Fallback if sanitization results in empty string
}

// ============================================================================
// ADDRESS VALIDATION
// Mirrors: createOrderTransaction address validation
// ============================================================================

const REQUIRED_ADDRESS_FIELDS = ['addressLine1', 'city', 'phoneNumber', 'location'];


function validateAddress(address) {
  if (!address || typeof address !== 'object') {
    return {
      isValid: false,
      reason: 'invalid_type',
      message: 'A valid address object is required.',
      missingFields: REQUIRED_ADDRESS_FIELDS,
    };
  }

  const missingFields = [];
  REQUIRED_ADDRESS_FIELDS.forEach((f) => {
    if (!(f in address)) {
      missingFields.push(f);
    }
  });

  if (missingFields.length > 0) {
    return {
      isValid: false,
      reason: 'missing_fields',
      message: `Missing address field: ${missingFields[0]}`,
      missingFields,
    };
  }

  return {
    isValid: true,
    missingFields: [],
  };
}

// ============================================================================
// PICKUP POINT VALIDATION
// Mirrors: createOrderTransaction pickup point validation
// ============================================================================

const REQUIRED_PICKUP_FIELDS = ['pickupPointId', 'pickupPointName', 'pickupPointAddress'];

function validatePickupPoint(pickupPoint) {
  if (!pickupPoint || typeof pickupPoint !== 'object') {
    return {
      isValid: false,
      reason: 'invalid_type',
      message: 'Pickup point is required for pickup delivery.',
      missingFields: REQUIRED_PICKUP_FIELDS,
    };
  }

  const missingFields = [];
  REQUIRED_PICKUP_FIELDS.forEach((f) => {
    if (!(f in pickupPoint)) {
      missingFields.push(f);
    }
  });

  if (missingFields.length > 0) {
    return {
      isValid: false,
      reason: 'missing_fields',
      message: `Missing pickup point field: ${missingFields[0]}`,
      missingFields,
    };
  }

  return {
    isValid: true,
    missingFields: [],
  };
}

// ============================================================================
// DELIVERY OPTION VALIDATION
// Mirrors: createOrderTransaction delivery option validation
// ============================================================================

const VALID_DELIVERY_OPTIONS = ['normal', 'express'];

function validateDeliveryOption(deliveryOption) {
  const isValid = VALID_DELIVERY_OPTIONS.includes(deliveryOption);

  return {
    isValid,
    message: isValid ? 'Valid delivery option' : 'Invalid delivery option.',
    validOptions: VALID_DELIVERY_OPTIONS,
  };
}

// ============================================================================
// CART ITEMS VALIDATION
// Mirrors: createOrderTransaction items validation
// ============================================================================

function validateCartItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    return {
      isValid: false,
      message: 'Cart must contain at least one item.',
    };
  }

  return {
    isValid: true,
    itemCount: items.length,
  };
}

function validateCartItem(item) {
  const { productId } = item || {};

  if (!productId || typeof productId !== 'string') {
    return {
      isValid: false,
      message: 'Each cart item needs a valid productId.',
    };
  }

  return {
    isValid: true,
    productId,
  };
}

// ============================================================================
// STOCK VALIDATION
// Mirrors: createOrderTransaction stock validation
// ============================================================================

function hasColorVariant(colorKey, productData) {
    return !!(colorKey &&
           productData.colorQuantities &&
           Object.prototype.hasOwnProperty.call(productData.colorQuantities, colorKey));
  }

function getAvailableStock(colorKey, productData) {
  const hasColor = hasColorVariant(colorKey, productData);
  return hasColor ? (productData.colorQuantities[colorKey] || 0) : (productData.quantity || 0);
}

function validateStock(item, productData) {
  const qty = Math.max(1, item.quantity || 1);
  const colorKey = item.selectedColor;

  const hasColor = hasColorVariant(colorKey, productData);
  const available = getAvailableStock(colorKey, productData);

  if (available < qty) {
    const stockInfo = hasColor ? `color '${colorKey}' stock: ${available}` : `general stock: ${available}`;

    return {
      isValid: false,
      available,
      requested: qty,
      hasColorVariant: hasColor,
      colorKey: colorKey || null,
      message: `Not enough stock for ${productData.productName}. ` +
               `Requested: ${qty}, Available: ${available} (${stockInfo})`,
    };
  }

  return {
    isValid: true,
    available,
    requested: qty,
    hasColorVariant: hasColor,
    colorKey: colorKey || null,
  };
}

// ============================================================================
// DYNAMIC ATTRIBUTES EXTRACTION
// Mirrors: createOrderTransaction dynamic attributes extraction
// ============================================================================

/**
 * System fields that should NOT be included in dynamic attributes
 * EXACT COPY from production code
 */
const SYSTEM_FIELDS = new Set([
  'productId', 'quantity', 'addedAt', 'updatedAt',
  'sellerId', 'sellerName', 'isShop',
  'salePreferences', 'calculatedUnitPrice', 'calculatedTotal', 'isBundleItem',
  'price', 'finalPrice', 'unitPrice', 'totalPrice', 'currency',
  'bundleInfo', 'isBundle', 'bundleId', 'mainProductPrice', 'bundlePrice',
  'selectedColorImage', 'productImage',
  'productName', 'brandModel', 'brand', 'category', 'subcategory',
  'subsubcategory', 'condition', 'averageRating', 'productAverageRating',
  'reviewCount', 'productReviewCount', 'clothingType',
  'clothingFit', 'gender',
  'shipmentStatus', 'deliveryOption', 'needsProductReview',
  'needsSellerReview', 'needsAnyReview', 'timestamp',
  'availableStock', 'maxQuantityAllowed', 'ourComission', 'sellerContactNo', 'showSellerHeader',
]);

function extractDynamicAttributes(item) {
  const dynamicAttributes = {};

  Object.keys(item).forEach((key) => {
    if (!SYSTEM_FIELDS.has(key) &&
        item[key] !== undefined &&
        item[key] !== null &&
        item[key] !== '') {
      dynamicAttributes[key] = item[key];
    }
  });

  return dynamicAttributes;
}

function isSystemField(fieldName) {
  return SYSTEM_FIELDS.has(fieldName);
}

// ============================================================================
// PRODUCT IMAGE SELECTION
// Mirrors: createOrderTransaction product image selection
// ============================================================================

function getProductImages(colorKey, productData) {
  let productImage = '';
  let selectedColorImage = '';

  if (colorKey && productData.colorImages && productData.colorImages[colorKey] &&
      Array.isArray(productData.colorImages[colorKey]) && productData.colorImages[colorKey].length > 0) {
    productImage = productData.colorImages[colorKey][0];
    selectedColorImage = productData.colorImages[colorKey][0];
  } else if (Array.isArray(productData.imageUrls) && productData.imageUrls.length > 0) {
    productImage = productData.imageUrls[0];
  }

  return {
    productImage,
    selectedColorImage: selectedColorImage || null,
  };
}

// ============================================================================
// BUNDLE INFO BUILDER
// Mirrors: createOrderTransaction bundle info building
// ============================================================================

function buildBundleInfo(item, productData) {
  if (item.isBundleItem && item.calculatedUnitPrice && item.calculatedUnitPrice < productData.price) {
    return {
      wasInBundle: true,
      originalPrice: productData.price,
      bundlePrice: item.calculatedUnitPrice,
      bundleDiscount: Math.round(((productData.price - item.calculatedUnitPrice) / productData.price) * 100),
      bundleDiscountAmount: productData.price - item.calculatedUnitPrice,
      originalBundleDiscountPercentage: productData.bundleDiscount || null,
    };
  }
  return null;
}

// ============================================================================
// SALE PREFERENCE INFO BUILDER
// Mirrors: createOrderTransaction sale preference info building
// ============================================================================

function buildSalePreferenceInfo(item, productData) {
  const salePrefs = item.salePreferences;
  if (salePrefs && salePrefs.discountThreshold && salePrefs.discountPercentage) {
    const quantity = Math.max(1, item.quantity || 1);
    const meetsThreshold = quantity >= salePrefs.discountThreshold;
    return {
      discountThreshold: salePrefs.discountThreshold,
      discountPercentage: salePrefs.discountPercentage,
      discountApplied: meetsThreshold,
      wasSalePrefUsed: item.calculatedUnitPrice &&
                       item.calculatedUnitPrice < (productData.price * (1 - (salePrefs.discountPercentage / 100))) + 0.01,
    };
  }
  return null;
}

// ============================================================================
// CART CLEAR TASK VALIDATION
// Mirrors: clearPurchasedCartItems input validation
// ============================================================================

function validateCartClearRequest(requestBody) {
  const { buyerId, purchasedProductIds } = requestBody || {};

  if (!buyerId) {
    return {
      isValid: false,
      message: 'Invalid request parameters',
      reason: 'missing_buyer_id',
    };
  }

  if (!Array.isArray(purchasedProductIds) || purchasedProductIds.length === 0) {
    return {
      isValid: false,
      message: 'Invalid request parameters',
      reason: 'invalid_product_ids',
    };
  }

  return {
    isValid: true,
    buyerId,
    productCount: purchasedProductIds.length,
  };
}

// ============================================================================
// BATCH SIZE CALCULATOR
// Mirrors: clearPurchasedCartItems batch chunking
// ============================================================================

const FIRESTORE_WRITE_BATCH_SIZE = 500;

function calculateBatchCount(itemCount, batchSize = FIRESTORE_WRITE_BATCH_SIZE) {
  return Math.ceil(itemCount / batchSize);
}

function chunkArray(array, chunkSize = FIRESTORE_WRITE_BATCH_SIZE) {
  const chunks = [];
  for (let i = 0; i < array.length; i += chunkSize) {
    chunks.push(array.slice(i, i + chunkSize));
  }
  return chunks;
}

// ============================================================================
// SELLER ADDRESS EXTRACTION
// Mirrors: batchFetchSellers seller address extraction
// ============================================================================

function extractShopSellerAddress(shopData) {
  if (!shopData) return null;

  return {
    addressLine1: shopData.address || 'N/A',
    location: (shopData.latitude && shopData.longitude) ? {
      lat: shopData.latitude,
      lng: shopData.longitude,
    } : null,
  };
}

function extractUserSellerAddress(userData) {
  if (!userData || !userData.sellerInfo) return null;

  return {
    addressLine1: userData.sellerInfo.address || 'N/A',
    location: (userData.sellerInfo.latitude && userData.sellerInfo.longitude) ? {
      lat: userData.sellerInfo.latitude,
      lng: userData.sellerInfo.longitude,
    } : null,
  };
}

// ============================================================================
// AMOUNT FORMATTING
// Mirrors: initializeIsbankPayment amount formatting
// ============================================================================

function formatPaymentAmount(amount) {
  return Math.round(parseFloat(amount)).toString();
}

// ============================================================================
// IDEMPOTENCY KEY VALIDATION
// Mirrors: createOrderTransaction duplicate order prevention
// ============================================================================

function isValidPaymentOrderId(paymentOrderId) {
    return !!(paymentOrderId && typeof paymentOrderId === 'string' && paymentOrderId.length > 0);
  }

// ============================================================================
// NOTIFICATION DATA BUILDER
// Mirrors: createOrderTransaction notification data collection
// ============================================================================

function getNotificationRecipients(productMeta, buyerId) {
  if (productMeta.shopMembers && productMeta.shopMembers.length > 0) {
    // Shop product: notify all shop members except buyer
    return productMeta.shopMembers.filter((id) => id !== buyerId);
  } else if (productMeta.data && productMeta.data.userId && productMeta.data.userId !== buyerId) {
    // User product: notify seller
    return [productMeta.data.userId];
  }
  return [];
}

// ============================================================================
// INVENTORY UPDATE CHECK
// Mirrors: createOrderTransaction inventory update logic
// ============================================================================

function shouldSkipStockDeduction(productData) {
  return productData.subsubcategory === 'Curtains';
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Shop members
  getShopMemberIdsFromData,

  // Object sanitization
  removeUndefined,

  // Hash generation
  generateHashVer3,
  getHashKeyOrder,
  buildHashPlainText,

  // Payment status
  VALID_MD_STATUS_CODES,
  isAuthSuccess,
  isTransactionSuccess,
  validatePaymentStatus,
  verifyCallbackHash,

  // Customer name
  sanitizeCustomerName,

  // Validation
  REQUIRED_ADDRESS_FIELDS,
  validateAddress,
  REQUIRED_PICKUP_FIELDS,
  validatePickupPoint,
  VALID_DELIVERY_OPTIONS,
  validateDeliveryOption,
  validateCartItems,
  validateCartItem,
  validateCartClearRequest,

  // Stock
  hasColorVariant,
  getAvailableStock,
  validateStock,

  // Dynamic attributes
  SYSTEM_FIELDS,
  extractDynamicAttributes,
  isSystemField,

  // Product images
  getProductImages,

  // Bundle & sale preference
  buildBundleInfo,
  buildSalePreferenceInfo,

  // Batch processing
  FIRESTORE_WRITE_BATCH_SIZE,
  calculateBatchCount,
  chunkArray,

  // Seller address
  extractShopSellerAddress,
  extractUserSellerAddress,

  // Payment formatting
  formatPaymentAmount,

  // Idempotency
  isValidPaymentOrderId,

  // Notifications
  getNotificationRecipients,

  // Inventory
  shouldSkipStockDeduction,
};
