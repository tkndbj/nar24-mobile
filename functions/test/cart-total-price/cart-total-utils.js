// functions/test/cart-total/cart-total-utils.js
//
// EXTRACTED PURE LOGIC from cart total price calculation cloud function
// These functions are EXACT COPIES of logic from the cart total function,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source cart total function.

// ============================================================================
// CONSTANTS
// ============================================================================

const DEFAULT_CURRENCY = 'TL';
const RATE_LIMIT_WINDOW_MS = 10000; // 10 seconds
const RATE_LIMIT_MAX_CALLS = 5;
const BATCH_SIZE = 10;

// ============================================================================
// PRICE HELPERS
// ============================================================================

function getUnitPrice(item) {
  return item.unitPrice || item.cachedPrice || 0;
}

function getQuantity(item) {
  return item.quantity || 1;
}

function getCurrency(item, defaultCurrency = DEFAULT_CURRENCY) {
  return item.currency || defaultCurrency;
}

function roundPrice(price) {
  return Math.round(price * 100) / 100;
}

// ============================================================================
// BULK DISCOUNT
// ============================================================================

function getBulkDiscountParams(item) {
  return {
    discountThreshold: item.discountThreshold || item.cachedDiscountThreshold || null,
    bulkDiscountPercentage: item.bulkDiscountPercentage || item.cachedBulkDiscountPercentage || null,
  };
}

function shouldApplyBulkDiscount(quantity, discountThreshold, bulkDiscountPercentage) {
  if (!discountThreshold || !bulkDiscountPercentage) return false;
  return quantity >= discountThreshold;
}

function applyBulkDiscount(unitPrice, discountPercentage) {
  return unitPrice * (1 - discountPercentage / 100);
}

function calculateDiscountedPrice(item, quantity = null) {
  const qty = quantity !== null ? quantity : getQuantity(item);
  let unitPrice = getUnitPrice(item);

  const { discountThreshold, bulkDiscountPercentage } = getBulkDiscountParams(item);

  if (shouldApplyBulkDiscount(qty, discountThreshold, bulkDiscountPercentage)) {
    unitPrice = applyBulkDiscount(unitPrice, bulkDiscountPercentage);
  }

  return unitPrice;
}

// ============================================================================
// ITEM TOTAL CALCULATION
// ============================================================================

function calculateItemTotal(item) {
  const quantity = getQuantity(item);
  const unitPrice = calculateDiscountedPrice(item, quantity);
  return unitPrice * quantity;
}

function buildItemTotalEntry(item, unitPrice, total, quantity, isBundle = false) {
  return {
    productId: item.productId,
    unitPrice,
    total,
    quantity,
    isBundle,
  };
}

// ============================================================================
// BUNDLE DETECTION
// ============================================================================

function extractBundleIds(cartItems) {
  const bundleIds = new Set();

  for (const item of cartItems) {
    if (item.bundleData && Array.isArray(item.bundleData)) {
      item.bundleData.forEach((bd) => {
        if (bd.bundleId) {
          bundleIds.add(bd.bundleId);
        }
      });
    }
  }

  return Array.from(bundleIds);
}

function hasAllBundleProducts(bundleProductIds, cartProductIds) {
  return bundleProductIds.every((id) => cartProductIds.includes(id));
}

function calculateBundleSavings(bundle) {
  const original = bundle.totalOriginalPrice || 0;
  const discounted = bundle.totalBundlePrice || 0;
  return original - discounted;
}

function buildApplicableBundle(bundleDoc, cartProductIds) {
  const bundleProductIds = bundleDoc.products.map((p) => p.productId);

  if (!hasAllBundleProducts(bundleProductIds, cartProductIds)) {
    return null;
  }

  return {
    bundleId: bundleDoc.id || bundleDoc.bundleId,
    ...bundleDoc,
    productIds: bundleProductIds,
    savings: calculateBundleSavings(bundleDoc),
  };
}

function findApplicableBundles(bundleDocs, cartItems) {
  const cartProductIds = cartItems.map((item) => item.productId);
  const applicableBundles = [];

  for (const bundle of bundleDocs) {
    const applicable = buildApplicableBundle(bundle, cartProductIds);
    if (applicable) {
      applicableBundles.push(applicable);
    }
  }

  return applicableBundles;
}

function selectBestBundle(applicableBundles) {
  if (!applicableBundles || applicableBundles.length === 0) {
    return null;
  }

  // Sort by savings descending
  const sorted = [...applicableBundles].sort((a, b) => b.savings - a.savings);
  return sorted[0];
}

// ============================================================================
// BUNDLE TOTAL CALCULATION
// ============================================================================

function getMinBundleQuantity(cartItems, bundledProductIds) {
  const bundleItems = cartItems.filter((item) => bundledProductIds.has(item.productId));

  if (bundleItems.length === 0) return 0;

  return Math.min(...bundleItems.map((item) => getQuantity(item)));
}

function calculateBundleLineTotal(bundle, quantity) {
  return bundle.totalBundlePrice * quantity;
}

function buildBundleTotalEntry(bundle, quantity, total) {
  return {
    bundleId: bundle.bundleId,
    bundleName: `Bundle (${bundle.productIds.length} products)`,
    unitPrice: bundle.totalBundlePrice,
    total,
    quantity,
    isBundle: true,
    productIds: bundle.productIds,
  };
}

function calculateRemainingQuantity(itemQuantity, bundleQuantity) {
  return Math.max(0, itemQuantity - bundleQuantity);
}

// ============================================================================
// CART TOTAL CALCULATION
// ============================================================================

function calculateCartTotal(itemTotals) {
  return itemTotals.reduce((sum, item) => sum + (item.total || 0), 0);
}

function isValidTotal(total) {
  return typeof total === 'number' && !isNaN(total) && total >= 0;
}

function processCartItems(cartItems, bundledProductIds = new Set()) {
  const itemTotals = [];
  let total = 0;
  let currency = DEFAULT_CURRENCY;

  for (const item of cartItems) {
    // Skip bundled products
    if (bundledProductIds.has(item.productId)) continue;

    const quantity = getQuantity(item);
    const unitPrice = calculateDiscountedPrice(item, quantity);
    const itemTotal = unitPrice * quantity;

    total += itemTotal;
    currency = getCurrency(item, currency);

    itemTotals.push({
      productId: item.productId,
      unitPrice,
      total: itemTotal,
      quantity,
      isBundle: false,
    });
  }

  return { itemTotals, total, currency };
}

function processExtraBundleQuantities(cartItems, bundledProductIds, bundleQuantity) {
  const extraTotals = [];
  let extraTotal = 0;

  const bundleItems = cartItems.filter((item) => bundledProductIds.has(item.productId));

  for (const item of bundleItems) {
    const remainingQty = calculateRemainingQuantity(getQuantity(item), bundleQuantity);

    if (remainingQty > 0) {
      const unitPrice = calculateDiscountedPrice(item, remainingQty);
      const itemTotal = unitPrice * remainingQty;

      extraTotal += itemTotal;

      extraTotals.push({
        productId: item.productId,
        unitPrice,
        total: itemTotal,
        quantity: remainingQty,
        isBundle: false,
      });
    }
  }

  return { extraTotals, extraTotal };
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildEmptyResponse() {
  return {
    total: 0,
    currency: DEFAULT_CURRENCY,
    items: [],
    calculatedAt: new Date().toISOString(),
  };
}

function buildAppliedBundleInfo(bundle) {
  if (!bundle) return null;

  return {
    bundleId: bundle.bundleId,
    savings: bundle.savings,
    productCount: bundle.productIds.length,
  };
}

function buildCartTotalResponse(total, currency, itemTotals, appliedBundle) {
  return {
    total: roundPrice(total),
    currency,
    items: itemTotals,
    appliedBundle: buildAppliedBundleInfo(appliedBundle),
    calculatedAt: new Date().toISOString(),
  };
}

// ============================================================================
// RATE LIMITING
// ============================================================================

function filterRecentCalls(calls, windowMs, now = Date.now()) {
  if (!Array.isArray(calls)) return [];
  return calls.filter((timestamp) => now - timestamp < windowMs);
}

function isRateLimited(recentCalls, maxCalls) {
  return recentCalls.length >= maxCalls;
}

function addCallTimestamp(calls, now = Date.now()) {
  return [...calls, now];
}

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateSelectedProductIds(selectedProductIds) {
  if (!Array.isArray(selectedProductIds)) {
    return { isValid: false, reason: 'not_array' };
  }

  if (selectedProductIds.length === 0) {
    return { isValid: false, reason: 'empty' };
  }

  return { isValid: true };
}

function shouldReturnEmpty(selectedProductIds) {
  return !Array.isArray(selectedProductIds) || selectedProductIds.length === 0;
}

// ============================================================================
// BATCHING
// ============================================================================

function chunkArray(array, size = BATCH_SIZE) {
  if (!Array.isArray(array)) return [];
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

function needsBatching(productIds, batchSize = BATCH_SIZE) {
  return productIds.length > batchSize;
}

// ============================================================================
// FULL CALCULATION (ORCHESTRATION)
// ============================================================================

function calculateFullCartTotal(cartItems, bundles = []) {
  if (cartItems.length === 0) {
    return buildEmptyResponse();
  }

  // Find applicable bundles
  const applicableBundles = findApplicableBundles(bundles, cartItems);
  const selectedBundle = selectBestBundle(applicableBundles);

  const bundledProductIds = new Set(selectedBundle ? selectedBundle.productIds : []);
  const itemTotals = [];
  let total = 0;
  let currency = DEFAULT_CURRENCY;

  // Process bundle if selected
  if (selectedBundle) {
    const bundleQuantity = getMinBundleQuantity(cartItems, bundledProductIds);
    const bundleTotal = calculateBundleLineTotal(selectedBundle, bundleQuantity);

    total += bundleTotal;
    currency = selectedBundle.currency || DEFAULT_CURRENCY;

    itemTotals.push(buildBundleTotalEntry(selectedBundle, bundleQuantity, bundleTotal));

    // Process extra quantities beyond bundle
    const { extraTotals, extraTotal } = processExtraBundleQuantities(
      cartItems,
      bundledProductIds,
      bundleQuantity
    );

    total += extraTotal;
    itemTotals.push(...extraTotals);
  }

  // Process non-bundled items
  const { itemTotals: nonBundledTotals, total: nonBundledTotal, currency: itemCurrency } =
    processCartItems(cartItems, bundledProductIds);

  total += nonBundledTotal;
  if (nonBundledTotals.length > 0) {
    currency = itemCurrency;
  }
  itemTotals.push(...nonBundledTotals);

  // Validate
  if (!isValidTotal(total)) {
    throw new Error('Invalid total calculated');
  }

  return buildCartTotalResponse(total, currency, itemTotals, selectedBundle);
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  DEFAULT_CURRENCY,
  RATE_LIMIT_WINDOW_MS,
  RATE_LIMIT_MAX_CALLS,
  BATCH_SIZE,

  // Price helpers
  getUnitPrice,
  getQuantity,
  getCurrency,
  roundPrice,

  // Bulk discount
  getBulkDiscountParams,
  shouldApplyBulkDiscount,
  applyBulkDiscount,
  calculateDiscountedPrice,

  // Item total
  calculateItemTotal,
  buildItemTotalEntry,

  // Bundle detection
  extractBundleIds,
  hasAllBundleProducts,
  calculateBundleSavings,
  buildApplicableBundle,
  findApplicableBundles,
  selectBestBundle,

  // Bundle total
  getMinBundleQuantity,
  calculateBundleLineTotal,
  buildBundleTotalEntry,
  calculateRemainingQuantity,

  // Cart total
  calculateCartTotal,
  isValidTotal,
  processCartItems,
  processExtraBundleQuantities,

  // Response
  buildEmptyResponse,
  buildAppliedBundleInfo,
  buildCartTotalResponse,

  // Rate limiting
  filterRecentCalls,
  isRateLimited,
  addCallTimestamp,

  // Input validation
  validateSelectedProductIds,
  shouldReturnEmpty,

  // Batching
  chunkArray,
  needsBatching,

  // Full calculation
  calculateFullCartTotal,
};
