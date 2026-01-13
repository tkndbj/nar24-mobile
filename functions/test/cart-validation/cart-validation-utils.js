// functions/test/cart-validation/cart-validation-utils.js
//
// EXTRACTED PURE LOGIC from cart validation cloud functions
// These functions are EXACT COPIES of logic from the cart validation functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source cart validation functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const MAX_CART_ITEMS = 500;
const MIN_QUANTITY = 1;
const PRICE_TOLERANCE = 0.01;
const RATE_LIMIT_WINDOW_MS = 60000;
const VALIDATION_RATE_LIMIT = 30;
const UPDATE_RATE_LIMIT = 20;
const RESERVATION_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
const TRANSACTION_CHUNK_SIZE = 100;
const BATCH_SIZE = 500;
const FETCH_BATCH_SIZE = 10;

const ALLOWED_UPDATE_FIELDS = [
  'cachedPrice',
  'cachedBundleData',
  'cachedBundlePrice',
  'cachedDiscountPercentage',
  'cachedDiscountThreshold',
  'cachedBulkDiscountPercentage',
  'cachedMaxQuantity',
  'discountPercentage',
  'discountThreshold',
  'bulkDiscountPercentage',
  'maxQuantity',
  'unitPrice',
  'bundlePrice',
  'bundleData',
  'bundleIds',
  'updatedAt',
];

const ERROR_KEYS = {
  PRODUCT_NOT_AVAILABLE: 'product_not_available',
  PRODUCT_UNAVAILABLE: 'product_unavailable',
  OUT_OF_STOCK: 'out_of_stock',
  INSUFFICIENT_STOCK: 'insufficient_stock',
  MAX_QUANTITY_EXCEEDED: 'max_quantity_exceeded',
  RESERVATION_FAILED: 'reservation_failed',
};

const WARNING_KEYS = {
  PRICE_CHANGED: 'price_changed',
  BUNDLE_PRICE_CHANGED: 'bundle_price_changed',
  DISCOUNT_UPDATED: 'discount_updated',
  DISCOUNT_THRESHOLD_CHANGED: 'discount_threshold_changed',
  BULK_DISCOUNT_CHANGED: 'bulk_discount_changed',
  MAX_QUANTITY_REDUCED: 'max_quantity_reduced',
};

// ============================================================================
// SAFE VALUE HELPERS
// ============================================================================

function safeNumber(value, defaultValue = 0) {
  if (value === null || value === undefined || isNaN(value)) {
    return defaultValue;
  }
  return Number(value);
}

function safePrice(value) {
  const num = safeNumber(value, 0);
  return num.toFixed(2);
}

function safeString(value, defaultValue = '') {
  if (value === null || value === undefined) {
    return defaultValue;
  }
  return String(value);
}

// ============================================================================
// CHANGE DETECTION
// ============================================================================

function hasChanged(cachedValue, currentValue) {
  // If cached value is undefined, we never cached it - no change detection
  if (cachedValue === undefined) return false;

  // Both null/undefined - no change
  if (cachedValue == null && currentValue == null) return false;

  // One is null, other isn't - changed
  if ((cachedValue == null) !== (currentValue == null)) return true;

  // Both have values - compare them
  return cachedValue !== currentValue;
}

function hasPriceChanged(cachedPrice, currentPrice, tolerance = PRICE_TOLERANCE) {
  // If cached price is undefined, we never cached it
  if (cachedPrice === undefined) return false;

  const cached = safeNumber(cachedPrice);
  const current = safeNumber(currentPrice);

  return Math.abs(cached - current) > tolerance;
}

function hasMaxQuantityReduced(cachedMax, currentMax) {
  if (cachedMax === undefined) return false;
  if (currentMax === undefined || currentMax === null) return false;
  return currentMax < cachedMax;
}

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateCartItems(cartItems) {
  const errors = [];

  if (!Array.isArray(cartItems)) {
    return { isValid: false, errors: [{ reason: 'not_array', message: 'cartItems must be a non-empty array' }] };
  }

  if (cartItems.length === 0) {
    return { isValid: false, errors: [{ reason: 'empty', message: 'cartItems must be a non-empty array' }] };
  }

  if (cartItems.length > MAX_CART_ITEMS) {
    return { isValid: false, errors: [{ reason: 'too_many', message: `Cannot validate more than ${MAX_CART_ITEMS} items at once` }] };
  }

  for (let i = 0; i < cartItems.length; i++) {
    const item = cartItems[i];

    if (!item.productId || typeof item.productId !== 'string') {
      errors.push({ index: i, reason: 'invalid_product_id', message: 'Each cart item must have a valid productId' });
    }

    if (!item.quantity || typeof item.quantity !== 'number' || item.quantity < MIN_QUANTITY) {
      errors.push({ index: i, reason: 'invalid_quantity', message: 'Each cart item must have a valid quantity >= 1' });
    }
  }

  if (errors.length > 0) {
    return { isValid: false, errors };
  }

  return { isValid: true };
}

function validateProductUpdates(productUpdates) {
  const errors = [];

  if (!Array.isArray(productUpdates)) {
    return { isValid: false, errors: [{ reason: 'not_array', message: 'productUpdates must be a non-empty array' }] };
  }

  if (productUpdates.length === 0) {
    return { isValid: false, errors: [{ reason: 'empty', message: 'productUpdates must be a non-empty array' }] };
  }

  if (productUpdates.length > MAX_CART_ITEMS) {
    return { isValid: false, errors: [{ reason: 'too_many', message: `Cannot update more than ${MAX_CART_ITEMS} items at once` }] };
  }

  for (let i = 0; i < productUpdates.length; i++) {
    const update = productUpdates[i];

    if (!update.productId || typeof update.productId !== 'string') {
      errors.push({ index: i, reason: 'invalid_product_id', message: 'Each update must have a valid productId' });
    }
  }

  if (errors.length > 0) {
    return { isValid: false, errors };
  }

  return { isValid: true };
}

function filterAllowedFields(updates) {
  if (!updates || typeof updates !== 'object') return {};

  const safeUpdates = {};
  for (const [key, value] of Object.entries(updates)) {
    if (ALLOWED_UPDATE_FIELDS.includes(key)) {
      safeUpdates[key] = value;
    }
  }
  return safeUpdates;
}

// ============================================================================
// STOCK CALCULATION
// ============================================================================

function calculateAvailableStock(product, selectedColor) {
  if (!product) return 0;

  // Check color-specific stock first
  if (selectedColor && product.colorQuantities && product.colorQuantities[selectedColor] !== undefined) {
    return safeNumber(product.colorQuantities[selectedColor]);
  }

  // Fall back to general stock
  return safeNumber(product.quantity);
}

function isProductAvailable(product) {
  if (!product) return false;
  if (product.paused === true) return false;
  return true;
}

function hasStock(product, selectedColor) {
  return calculateAvailableStock(product, selectedColor) > 0;
}

function hasSufficientStock(product, selectedColor, requestedQuantity) {
  const available = calculateAvailableStock(product, selectedColor);
  return available >= requestedQuantity;
}

function isWithinMaxQuantity(product, requestedQuantity) {
  if (!product.maxQuantity) return true; // No limit
  return requestedQuantity <= product.maxQuantity;
}

// ============================================================================
// PRICE CALCULATION
// ============================================================================

function calculateFinalUnitPrice(product, quantity) {
  let price = safeNumber(product.price);

  // Apply bulk discount if applicable
  if (product.discountThreshold && product.bulkDiscountPercentage) {
    if (quantity >= product.discountThreshold) {
      price = price * (1 - product.bulkDiscountPercentage / 100);
    }
  }

  return price;
}

function calculateItemTotal(unitPrice, quantity) {
  return unitPrice * quantity;
}

function calculateCartTotal(validatedItems) {
  return validatedItems.reduce((sum, item) => sum + item.total, 0);
}

function extractBundlePrice(product) {
  if (product.bundleData && Array.isArray(product.bundleData) && product.bundleData.length > 0) {
    return product.bundleData[0].bundlePrice || null;
  }
  return null;
}

// ============================================================================
// COLOR IMAGE EXTRACTION
// ============================================================================

function getColorImage(product, selectedColor) {
  if (!selectedColor) return null;
  if (!product.colorImages) return null;
  if (!product.colorImages[selectedColor]) return null;
  if (!Array.isArray(product.colorImages[selectedColor])) return null;
  if (product.colorImages[selectedColor].length === 0) return null;

  return product.colorImages[selectedColor][0];
}

function getProductImage(product) {
  if (product.imageUrls && Array.isArray(product.imageUrls) && product.imageUrls.length > 0) {
    return product.imageUrls[0];
  }
  return '';
}

// ============================================================================
// VALIDATION RESULT BUILDING
// ============================================================================

function createValidationResult() {
  return {
    isValid: true,
    errors: {},
    warnings: {},
    validatedItems: [],
    totalPrice: 0,
    currency: 'TL',
  };
}

function addError(result, productId, errorKey, params = {}) {
  result.errors[productId] = { key: errorKey, params };
  result.isValid = false;
}

function addWarning(result, productId, warningKey, params = {}) {
  result.warnings[productId] = { key: warningKey, params };
}

function buildValidatedItem(cartItem, product, unitPrice, total, colorImage, bundlePrice) {
  return {
    productId: cartItem.productId,
    quantity: cartItem.quantity,
    availableStock: calculateAvailableStock(product, cartItem.selectedColor),
    unitPrice,
    total,
    currency: product.currency || 'TL',
    productName: product.productName || 'Unknown Product',
    imageUrl: getProductImage(product),
    selectedColor: cartItem.selectedColor || null,
    colorImage,
    discountPercentage: product.discountPercentage ?? null,
    discountThreshold: product.discountThreshold ?? null,
    bulkDiscountPercentage: product.bulkDiscountPercentage ?? null,
    maxQuantity: product.maxQuantity ?? null,
    bundlePrice: bundlePrice ?? null,
  };
}

function finalizeResult(result, processingTimeMs) {
  return {
    ...result,
    hasWarnings: Object.keys(result.warnings).length > 0,
    processingTimeMs,
  };
}

// ============================================================================
// RATE LIMITING
// ============================================================================

function shouldRateLimit(count, limit) {
  return count >= limit;
}

function isWindowExpired(windowStart, windowMs = RATE_LIMIT_WINDOW_MS, now = Date.now()) {
  return now - windowStart > windowMs;
}

function createRateLimitEntry(now = Date.now()) {
  return { count: 1, windowStart: now };
}

// ============================================================================
// RESERVATION
// ============================================================================

function calculateReservationExpiry(nowMs = Date.now()) {
  return nowMs + RESERVATION_EXPIRY_MS;
}

function buildReservationItem(cartItem) {
  return {
    productId: cartItem.productId,
    quantity: cartItem.quantity,
    selectedColor: cartItem.selectedColor || null,
  };
}

function buildStockDecrementUpdate(selectedColor, quantity) {
  if (selectedColor) {
    return { field: `colorQuantities.${selectedColor}`, decrement: quantity };
  }
  return { field: 'quantity', decrement: quantity };
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

function calculateBatchCount(totalItems, batchSize = BATCH_SIZE) {
  return Math.ceil(totalItems / batchSize);
}

// ============================================================================
// UPDATE RESULTS
// ============================================================================

function createUpdateResult() {
  return {
    updated: [],
    failed: [],
    skipped: [],
  };
}

function buildUpdateResponse(results, processingTimeMs) {
  return {
    success: true,
    updated: results.updated.length,
    skipped: results.skipped.length,
    failed: results.failed.length,
    failedItems: results.failed,
    processingTimeMs,
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  MAX_CART_ITEMS,
  MIN_QUANTITY,
  PRICE_TOLERANCE,
  RATE_LIMIT_WINDOW_MS,
  VALIDATION_RATE_LIMIT,
  UPDATE_RATE_LIMIT,
  RESERVATION_EXPIRY_MS,
  TRANSACTION_CHUNK_SIZE,
  BATCH_SIZE,
  FETCH_BATCH_SIZE,
  ALLOWED_UPDATE_FIELDS,
  ERROR_KEYS,
  WARNING_KEYS,

  // Safe value helpers
  safeNumber,
  safePrice,
  safeString,

  // Change detection
  hasChanged,
  hasPriceChanged,
  hasMaxQuantityReduced,

  // Input validation
  validateCartItems,
  validateProductUpdates,
  filterAllowedFields,

  // Stock calculation
  calculateAvailableStock,
  isProductAvailable,
  hasStock,
  hasSufficientStock,
  isWithinMaxQuantity,

  // Price calculation
  calculateFinalUnitPrice,
  calculateItemTotal,
  calculateCartTotal,
  extractBundlePrice,

  // Image extraction
  getColorImage,
  getProductImage,

  // Result building
  createValidationResult,
  addError,
  addWarning,
  buildValidatedItem,
  finalizeResult,

  // Rate limiting
  shouldRateLimit,
  isWindowExpired,
  createRateLimitEntry,

  // Reservation
  calculateReservationExpiry,
  buildReservationItem,
  buildStockDecrementUpdate,

  // Batching
  chunkArray,
  calculateBatchCount,

  // Update results
  createUpdateResult,
  buildUpdateResponse,
};
