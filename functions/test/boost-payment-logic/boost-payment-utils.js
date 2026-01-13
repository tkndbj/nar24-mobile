// functions/test/boost-payment/boost-payment-utils.js
//
// EXTRACTED PURE LOGIC from boost payment and logic cloud functions
// These functions are EXACT COPIES of logic from the boost functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source boost functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const BASE_PRICE_PER_PRODUCT = 1.0;
const MAX_BOOST_DURATION_MINUTES = 10080; // 7 days
const MAX_ITEMS_PER_BOOST = 50;
const BATCH_SIZE = 10;
const VALID_COLLECTIONS = ['products', 'shop_products'];
const EXECUTION_TOLERANCE_MS = 30 * 1000; // 30 seconds
const SCHEDULE_BUFFER_MS = 10 * 1000; // 10 seconds before expiry
const PROMOTION_SCORE_BOOST = 1000;

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateBoostItems(items) {
  if (!items) {
    return { isValid: false, reason: 'missing', message: 'Items array is required and must not be empty.' };
  }

  if (!Array.isArray(items)) {
    return { isValid: false, reason: 'not_array', message: 'Items array is required and must not be empty.' };
  }

  if (items.length === 0) {
    return { isValid: false, reason: 'empty', message: 'Items array is required and must not be empty.' };
  }

  if (items.length > MAX_ITEMS_PER_BOOST) {
    return { isValid: false, reason: 'too_many', message: 'Cannot boost more than 50 items at once.' };
  }

  // Validate each item
  const errors = [];
  items.forEach((item, index) => {
    if (!item.itemId || typeof item.itemId !== 'string') {
      errors.push({ index, field: 'itemId', message: 'Each item must have a valid itemId.' });
    }
    if (!item.collection || !VALID_COLLECTIONS.includes(item.collection)) {
      errors.push({ index, field: 'collection', message: 'Each item must specify a valid collection.' });
    }
    if (item.collection === 'shop_products' && (!item.shopId || typeof item.shopId !== 'string')) {
      errors.push({ index, field: 'shopId', message: 'Shop products must include a valid shopId.' });
    }
  });

  if (errors.length > 0) {
    return { isValid: false, reason: 'invalid_items', errors, message: errors[0].message };
  }

  return { isValid: true };
}

function validateBoostDuration(duration) {
  if (!duration) {
    return { isValid: false, reason: 'missing', message: 'Boost duration must be a positive number (max 10080 minutes).' };
  }

  if (typeof duration !== 'number') {
    return { isValid: false, reason: 'not_number', message: 'Boost duration must be a positive number (max 10080 minutes).' };
  }

  if (duration <= 0) {
    return { isValid: false, reason: 'not_positive', message: 'Boost duration must be a positive number (max 10080 minutes).' };
  }

  if (duration > MAX_BOOST_DURATION_MINUTES) {
    return { isValid: false, reason: 'too_long', message: 'Boost duration must be a positive number (max 10080 minutes).' };
  }

  return { isValid: true };
}

function validatePaymentInitInput(data) {
  const errors = [];

  const itemsResult = validateBoostItems(data.items);
  if (!itemsResult.isValid) {
    errors.push({ field: 'items', ...itemsResult });
  }

  const durationResult = validateBoostDuration(data.boostDuration);
  if (!durationResult.isValid) {
    errors.push({ field: 'boostDuration', ...durationResult });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, firstError: errors[0] };
  }

  return { isValid: true };
}

// ============================================================================
// PRICE CALCULATION
// ============================================================================

function calculateBoostPrice(itemCount, boostDuration, pricePerProduct = BASE_PRICE_PER_PRODUCT) {
  return itemCount * boostDuration * pricePerProduct;
}

function calculatePricePerItem(boostDuration, pricePerProduct = BASE_PRICE_PER_PRODUCT) {
  return boostDuration * pricePerProduct;
}

function formatAmount(amount) {
  return Math.round(amount).toString();
}

// ============================================================================
// ORDER NUMBER GENERATION
// ============================================================================

function generateOrderNumber(userId, timestamp = Date.now()) {
  const userPrefix = userId ? userId.substring(0, 8) : 'unknown';
  return `BOOST-${timestamp}-${userPrefix}`;
}

function parseOrderNumber(orderNumber) {
  const parts = orderNumber.split('-');
  if (parts.length !== 3 || parts[0] !== 'BOOST') {
    return null;
  }
  return {
    type: parts[0],
    timestamp: parseInt(parts[1], 10),
    userPrefix: parts[2],
  };
}

// ============================================================================
// PERMISSION CHECKING
// ============================================================================

function checkProductPermission(collection, productData, userId, isAdmin) {
  if (isAdmin) return true;

  if (collection === 'products') {
    return productData.userId === userId;
  }

  return false; // Shop products require separate shop membership check
}

function checkShopMembership(shopData, userId) {
  if (!shopData) return false;

  if (shopData.ownerId === userId) return true;
  if (shopData.editors && shopData.editors.includes(userId)) return true;
  if (shopData.coOwners && shopData.coOwners.includes(userId)) return true;
  if (shopData.viewers && shopData.viewers.includes(userId)) return true;

  return false;
}

function getShopMembers(shopData) {
  if (!shopData) return new Set();

  const members = new Set();
  if (shopData.ownerId) members.add(shopData.ownerId);
  if (shopData.coOwners) shopData.coOwners.forEach((id) => members.add(id));
  if (shopData.editors) shopData.editors.forEach((id) => members.add(id));
  if (shopData.viewers) shopData.viewers.forEach((id) => members.add(id));

  return members;
}

// ============================================================================
// BOOST STATUS CHECKING
// ============================================================================

function isAlreadyBoosted(productData, nowMs = Date.now()) {
  if (!productData.isBoosted) return false;
  if (!productData.boostEndTime) return false;

  const boostEndTime = productData.boostEndTime.toDate ? productData.boostEndTime.toDate() : new Date(productData.boostEndTime);

  return boostEndTime.getTime() > nowMs;
}

function getBoostTimeRemaining(productData, nowMs = Date.now()) {
  if (!isAlreadyBoosted(productData, nowMs)) return 0;

  const boostEndTime = productData.boostEndTime.toDate ? productData.boostEndTime.toDate() : new Date(productData.boostEndTime);

  return Math.max(0, boostEndTime.getTime() - nowMs);
}

// ============================================================================
// TIME CALCULATION
// ============================================================================

function calculateBoostEndTime(boostDurationMinutes, startMs = Date.now()) {
  return new Date(startMs + (boostDurationMinutes * 60 * 1000));
}

function calculateScheduleTime(boostEndTime, bufferMs = SCHEDULE_BUFFER_MS) {
  const endMs = boostEndTime instanceof Date ? boostEndTime.getTime() : boostEndTime;
  return new Date(endMs - bufferMs);
}

function isWithinExpirationTolerance(scheduledEndTime, nowMs = Date.now()) {
  const tolerantEndTime = new Date(scheduledEndTime.getTime() - EXECUTION_TOLERANCE_MS);
  return nowMs >= tolerantEndTime.getTime();
}

function isTooEarlyToExpire(scheduledEndTime, nowMs = Date.now()) {
  return !isWithinExpirationTolerance(scheduledEndTime, nowMs);
}

// ============================================================================
// TASK NAME GENERATION
// ============================================================================

function generateTaskName(collection, itemId, timestamp = Date.now()) {
  const randomSuffix = Math.random().toString(36).substr(2, 9);
  return `expire-boost-${collection}-${itemId}-${timestamp}-${randomSuffix}`;
}

function parseTaskName(taskName) {
  const parts = taskName.split('-');
  if (parts.length < 5 || parts[0] !== 'expire' || parts[1] !== 'boost') {
    return null;
  }
  return {
    collection: parts[2],
    itemId: parts[3],
    timestamp: parseInt(parts[4], 10),
  };
}

// ============================================================================
// BOOST UPDATE DATA BUILDING
// ============================================================================

function buildBoostUpdateData(productData, boostDuration, boostStartTime, boostEndTime, taskName, isVerified) {
  const currentImpressions = productData.boostedImpressionCount || 0;
  const currentClicks = productData.clickCount || 0;
  const boostScreen = isVerified ? 'shop_product' : 'product';
  const screenType = isVerified ? 'shop_product' : 'product';

  return {
    boostStartTime,
    boostEndTime,
    boostDuration,
    isBoosted: true,
    boostImpressionCountAtStart: currentImpressions,
    boostClickCountAtStart: currentClicks,
    boostScreen,
    screenType,
    boostExpirationTaskName: taskName,
    promotionScore: (productData.rankingScore || 0) + PROMOTION_SCORE_BOOST,
  };
}

function buildBoostExpirationData(productData) {
  return {
    isBoosted: false,
    lastBoostExpiredAt: new Date(),
    promotionScore: Math.max((productData.promotionScore || 0) - PROMOTION_SCORE_BOOST, 0),
  };
}

// ============================================================================
// BOOST HISTORY DATA BUILDING
// ============================================================================

function buildBoostHistoryData(userId, itemId, collection, productData, boostDuration, boostStartTime, boostEndTime) {
  const currentImpressions = productData.boostedImpressionCount || 0;
  const currentClicks = productData.clickCount || 0;
  const itemName = productData.productName || 'Unnamed Product';

  return {
    userId,
    itemId,
    itemType: collection === 'shop_products' ? 'shop_product' : 'product',
    itemName,
    boostStartTime,
    boostEndTime,
    boostDuration,
    pricePerMinutePerItem: BASE_PRICE_PER_PRODUCT,
    boostPrice: boostDuration * BASE_PRICE_PER_PRODUCT,
    boostImpressionCountAtStart: currentImpressions,
    boostClickCountAtStart: currentClicks,
    finalImpressions: 0,
    finalClicks: 0,
    totalImpressionCount: 0,
    totalClickCount: 0,
    demographics: {},
    viewerAgeGroups: {},
  };
}

function getHistoryCollectionPath(collection, targetId) {
  if (collection === 'shop_products' && targetId) {
    return `shops/${targetId}/boostHistory`;
  }
  return `users/${targetId}/boostHistory`;
}

// ============================================================================
// EXPIRATION PAYLOAD BUILDING
// ============================================================================

function buildExpirationPayload(item, userId, boostEndDate, taskName) {
  return {
    itemId: item.itemId,
    collection: item.collection,
    shopId: item.shopId || null,
    userId,
    boostEndTime: boostEndDate.toISOString(),
    taskName,
    scheduledAt: new Date().toISOString(),
  };
}

// ============================================================================
// METRICS CALCULATION
// ============================================================================

function calculateImpressionsDuringBoost(productData) {
  const current = productData.boostedImpressionCount || 0;
  const atStart = productData.boostImpressionCountAtStart || 0;
  return Math.max(0, current - atStart);
}

function calculateClicksDuringBoost(productData) {
  const current = productData.clickCount || 0;
  const atStart = productData.boostClickCountAtStart || 0;
  return Math.max(0, current - atStart);
}

function buildHistoryUpdateData(productData) {
  return {
    impressionsDuringBoost: calculateImpressionsDuringBoost(productData),
    clicksDuringBoost: calculateClicksDuringBoost(productData),
    totalImpressionCount: productData.boostedImpressionCount || 0,
    totalClickCount: productData.clickCount || 0,
    finalImpressions: productData.boostImpressionCountAtStart || 0,
    finalClicks: productData.boostClickCountAtStart || 0,
    itemName: productData.productName || 'Unnamed Product',
    productImage: (productData.imageUrls && productData.imageUrls.length > 0) ? productData.imageUrls[0] : null,
    averageRating: productData.averageRating || 0,
    price: productData.price || 0,
    currency: productData.currency || 'TL',
  };
}

// ============================================================================
// NOTIFICATION BUILDING
// ============================================================================

function buildBoostExpiredNotification(userId, productName, itemId, collection, shopId = null) {
  const notification = {
    userId,
    type: 'boost_expired',
    message_en: `${productName} boost has expired.`,
    message_tr: `${productName} boost süresi doldu.`,
    message_ru: `У объявления ${productName} закончился буст.`,
    isRead: false,
    productId: itemId,
    itemType: collection === 'shop_products' ? 'shop_product' : 'product',
  };

  if (shopId) {
    notification.shopId = shopId;
  }

  return notification;
}

// ============================================================================
// RESULT BUILDING
// ============================================================================

function buildBoostResult(validatedItems, failedItems, items, boostDuration, startTime) {
  const endTime = calculateBoostEndTime(boostDuration, startTime.getTime());
  const totalPrice = calculateBoostPrice(validatedItems.length, boostDuration);

  return {
    boostedItemsCount: validatedItems.length,
    totalRequestedItems: items.length,
    failedItemsCount: failedItems.length,
    boostDuration,
    boostStartTime: startTime,
    boostEndTime: endTime,
    totalPrice,
    pricePerItem: calculatePricePerItem(boostDuration),
    boostedItems: validatedItems.map((item) => ({
      itemId: item.itemId,
      collection: item.collection,
      shopId: item.shopId || null,
    })),
    failedItems: failedItems.length > 0 ? failedItems : undefined,
  };
}

function buildPaymentInitResponse(gatewayUrl, paymentParams, orderNumber, totalPrice, itemCount) {
  return {
    success: true,
    gatewayUrl,
    paymentParams,
    orderNumber,
    totalPrice,
    itemCount,
  };
}

function buildPaymentStatusResponse(orderNumber, status, boostResult, errorMessage, boostError) {
  return {
    orderNumber,
    status,
    boostResult: boostResult || null,
    errorMessage: errorMessage || null,
    boostError: boostError || null,
  };
}

// ============================================================================
// RECEIPT DATA BUILDING
// ============================================================================

function buildReceiptTaskData(ownerId, ownerType, orderId, buyerInfo, boostData, items) {
  const itemsSubtotal = items.length * boostData.boostDuration * boostData.basePricePerProduct;

  return {
    receiptType: 'boost',
    orderId,
    ownerId,
    ownerType,
    buyerName: buyerInfo.name,
    buyerEmail: buyerInfo.email,
    buyerPhone: buyerInfo.phone,
    totalPrice: itemsSubtotal,
    itemsSubtotal,
    deliveryPrice: 0,
    currency: 'TRY',
    paymentMethod: 'isbank_3d',
    language: 'tr',
    boostData: {
      boostDuration: boostData.boostDuration,
      itemCount: items.length,
      items: items.map((item) => ({
        itemId: item.itemId,
        collection: item.collection,
        productName: item.productName,
        boostDuration: boostData.boostDuration,
        unitPrice: boostData.basePricePerProduct,
        totalPrice: boostData.boostDuration * boostData.basePricePerProduct,
        shopId: item.shopId || null,
      })),
    },
    status: 'pending',
  };
}

function groupItemsByOwner(boostedItems, defaultUserId) {
  const groups = {};

  for (const item of boostedItems) {
    const ownerId = (item.shopId && typeof item.shopId === 'string' && item.shopId.trim() !== '') ? item.shopId : defaultUserId;
    const ownerType = (item.shopId && typeof item.shopId === 'string' && item.shopId.trim() !== '') ? 'shop' : 'user';

    if (!groups[ownerId]) {
      groups[ownerId] = {
        ownerId,
        ownerType,
        items: [],
      };
    }

    groups[ownerId].items.push(item);
  }

  return groups;
}

// ============================================================================
// CUSTOMER NAME SANITIZATION
// ============================================================================

function sanitizeCustomerName(customerName) {
  if (!customerName) return 'Customer';

  // Simple transliteration for common Turkish characters
  const translitMap = {
    'ç': 'c', 'Ç': 'C',
    'ğ': 'g', 'Ğ': 'G',
    'ı': 'i', 'İ': 'I',
    'ö': 'o', 'Ö': 'O',
    'ş': 's', 'Ş': 'S',
    'ü': 'u', 'Ü': 'U',
  };

  let sanitized = customerName;
  for (const [from, to] of Object.entries(translitMap)) {
    sanitized = sanitized.replace(new RegExp(from, 'g'), to);
  }

  sanitized = sanitized
    .replace(/[^a-zA-Z0-9\s]/g, '')
    .trim()
    .substring(0, 50);

  return sanitized || 'Customer';
}

// ============================================================================
// STALE TASK CHECKING
// ============================================================================

function isStaleTask(productData, taskName) {
  if (!productData.boostExpirationTaskName) return false;
  return productData.boostExpirationTaskName !== taskName;
}

function shouldSkipExpiration(productData, taskName, scheduledEndTime, nowMs = Date.now()) {
  // Check for stale task
  if (isStaleTask(productData, taskName)) {
    return { skip: true, reason: 'stale_task' };
  }

  // Check if already not boosted
  if (!productData.isBoosted) {
    return { skip: true, reason: 'not_boosted' };
  }

  // Check if too early
  if (isTooEarlyToExpire(scheduledEndTime, nowMs)) {
    return { skip: true, reason: 'too_early' };
  }

  // Check if database boost end time is far in future
  if (productData.boostEndTime) {
    const dbBoostEndTime = productData.boostEndTime.toDate ? productData.boostEndTime.toDate() : new Date(productData.boostEndTime);
    
    if (dbBoostEndTime.getTime() - nowMs > 60000) {
      return { skip: true, reason: 'end_time_too_far' };
    }
  }

  return { skip: false };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  BASE_PRICE_PER_PRODUCT,
  MAX_BOOST_DURATION_MINUTES,
  MAX_ITEMS_PER_BOOST,
  BATCH_SIZE,
  VALID_COLLECTIONS,
  EXECUTION_TOLERANCE_MS,
  SCHEDULE_BUFFER_MS,
  PROMOTION_SCORE_BOOST,

  // Input validation
  validateBoostItems,
  validateBoostDuration,
  validatePaymentInitInput,

  // Price calculation
  calculateBoostPrice,
  calculatePricePerItem,
  formatAmount,

  // Order number
  generateOrderNumber,
  parseOrderNumber,

  // Permission checking
  checkProductPermission,
  checkShopMembership,
  getShopMembers,

  // Boost status
  isAlreadyBoosted,
  getBoostTimeRemaining,

  // Time calculation
  calculateBoostEndTime,
  calculateScheduleTime,
  isWithinExpirationTolerance,
  isTooEarlyToExpire,

  // Task name
  generateTaskName,
  parseTaskName,

  // Boost update data
  buildBoostUpdateData,
  buildBoostExpirationData,

  // Boost history
  buildBoostHistoryData,
  getHistoryCollectionPath,

  // Expiration payload
  buildExpirationPayload,

  // Metrics
  calculateImpressionsDuringBoost,
  calculateClicksDuringBoost,
  buildHistoryUpdateData,

  // Notification
  buildBoostExpiredNotification,

  // Result building
  buildBoostResult,
  buildPaymentInitResponse,
  buildPaymentStatusResponse,

  // Receipt
  buildReceiptTaskData,
  groupItemsByOwner,

  // Customer name
  sanitizeCustomerName,

  // Stale task
  isStaleTask,
  shouldSkipExpiration,
};
