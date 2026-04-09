import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {checkRateLimit as redisRateLimit} from '../shared/redis.js';

/**
 * Calculate cart totals for the authenticated user.
 *
 * This function fetches ALL cart items directly from the user's cart subcollection,
 * applies bundle discounts, bulk discounts, and returns the final total.
 *
 * @param {Object} request - The request object from Firebase callable function
 * @param {Object} request.data - Request data
 * @param {string[]} [request.data.excludedProductIds] - Product IDs to exclude from calculation
 * @returns {Promise<Object>} Cart totals with itemized breakdown
 */
export const calculateCartTotals = onCall(
  {
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 60,
    maxInstances: 100,
    concurrency: 80,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const startTime = Date.now();

    // ═══════════════════════════════════════════════════════════════════════
    // 1. AUTHENTICATION CHECK
    // ═══════════════════════════════════════════════════════════════════════
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be logged in to calculate cart totals'
      );
    }

    const userId = request.auth.uid;
    const requestId = `${userId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    console.log(`📊 [${requestId}] Cart totals calculation started for user: ${userId}`);
    const db = admin.firestore();

    // ═══════════════════════════════════════════════════════════════════════
    // 3. RATE LIMITING (Redis)
    // ═══════════════════════════════════════════════════════════════════════
    // 5 requests per 10 seconds per user (same as original sliding window)
    const rateLimitPassed = await redisRateLimit(`cart_totals:${userId}`, 5, 10);
    if (!rateLimitPassed) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many requests. Please wait a few seconds and try again.'
      );
    }

   // ═══════════════════════════════════════════════════════════════════════════
// 4. FETCH SELECTED CART ITEMS (Direct lookup — no collection scan)
// ═══════════════════════════════════════════════════════════════════════════
const cartItems = [];

let selectedProductIds = [];

if (request.data?.selectedProductIds) {
  if (!Array.isArray(request.data.selectedProductIds)) {
    throw new HttpsError('invalid-argument', 'selectedProductIds must be an array');
  }
  selectedProductIds = request.data.selectedProductIds
    .filter((id) => typeof id === 'string' && id.trim().length > 0)
    .map((id) => id.trim())
    .slice(0, 500);
}

if (selectedProductIds.length === 0) {
  console.log(`📭 [${requestId}] No selected items`);
  return createEmptyResponse(requestId, startTime);
}

try {
  const cartRef = db.collection('users').doc(userId).collection('cart');
  const docRefs = selectedProductIds.map((id) => cartRef.doc(id));
  const docs = await db.getAll(...docRefs);

  docs.forEach((doc) => {
    if (!doc.exists) {
      console.warn(`⚠️ [${requestId}] Cart item not found: ${doc.id}`);
      return;
    }

    const data = doc.data();

    if (!data || typeof data.unitPrice === 'undefined') {
      console.warn(`⚠️ [${requestId}] Skipping invalid cart item: ${doc.id} — unitPrice missing`);
      return;
    }

    if (parseFloat(data.unitPrice) === 0) {
      console.warn(`⚠️ [${requestId}] Zero price detected for item: ${doc.id}`);
    }

    cartItems.push({ productId: doc.id, ...data });
  });

  console.log(`📦 [${requestId}] Fetched ${cartItems.length}/${selectedProductIds.length} cart items`);

  if (cartItems.length === 0) {
    return createEmptyResponse(requestId, startTime);
  }
} catch (error) {
  console.error(`❌ [${requestId}] Failed to fetch cart items:`, error);
  throw new HttpsError('internal', 'Failed to fetch cart items. Please try again.');
}

    // ═══════════════════════════════════════════════════════════════════════
    // 5. FETCH & EVALUATE BUNDLES
    // ═══════════════════════════════════════════════════════════════════════
    let selectedBundle = null;

    try {
      selectedBundle = await findBestApplicableBundle(db, cartItems, requestId);
    } catch (error) {
      console.warn(`⚠️ [${requestId}] Bundle evaluation failed, continuing without bundles: ${error.message}`);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6. CALCULATE TOTALS
    // ═══════════════════════════════════════════════════════════════════════
    let result;

    try {
      result = calculateTotalsWithDiscounts(cartItems, selectedBundle, requestId);
    } catch (error) {
      console.error(`❌ [${requestId}] Calculation error:`, error);
      throw new HttpsError(
        'internal',
        'Failed to calculate totals. Please try again.'
      );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7. FINAL VALIDATION
    // ═══════════════════════════════════════════════════════════════════════
    if (result.total < 0) {
      console.error(`❌ [${requestId}] CRITICAL: Negative total detected!`, {
        total: result.total,
        itemCount: result.items.length,
      });
      throw new HttpsError(
        'internal',
        'Invalid total calculated. Please contact support.'
      );
    }

    const MAX_CART_TOTAL = 10000000;
    if (result.total > MAX_CART_TOTAL) {
      console.error(`❌ [${requestId}] CRITICAL: Suspiciously high total!`, {
        total: result.total,
      });
      throw new HttpsError(
        'internal',
        'Cart total exceeds maximum allowed. Please contact support.'
      );
    }

    const duration = Date.now() - startTime;
    console.log(`✅ [${requestId}] Calculation complete in ${duration}ms: ${result.total} ${result.currency}`);

    return {
      ...result,
      requestId,
      calculatedAt: new Date().toISOString(),
      processingTimeMs: duration,
    };
  }
);


// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════


/**
 * Find the best applicable bundle with highest savings
 * @param {FirebaseFirestore.Firestore} db - Firestore database instance
 * @param {Array<Object>} cartItems - Array of cart items
 * @param {string} requestId - Unique request ID for logging
 * @return {Promise<Object|null>} Best applicable bundle or null if none found
 */
async function findBestApplicableBundle(db, cartItems, requestId) {
  const uniqueBundleIds = new Set();

  cartItems.forEach((item) => {
    if (item.bundleData && Array.isArray(item.bundleData)) {
      item.bundleData.forEach((bd) => {
        if (bd?.bundleId && typeof bd.bundleId === 'string') {
          uniqueBundleIds.add(bd.bundleId);
        }
      });
    }

    if (item.bundleIds && Array.isArray(item.bundleIds)) {
      item.bundleIds.forEach((id) => {
        if (typeof id === 'string' && id.trim()) {
          uniqueBundleIds.add(id.trim());
        }
      });
    }
  });

  if (uniqueBundleIds.size === 0) {
    return null;
  }

  console.log(`🔍 [${requestId}] Checking ${uniqueBundleIds.size} potential bundles`);

  const bundlePromises = Array.from(uniqueBundleIds).map((bundleId) =>
    db.collection('bundles').doc(bundleId).get()
  );

  const bundleDocs = await Promise.all(bundlePromises);
  const cartProductIds = new Set(cartItems.map((item) => item.productId));
  const applicableBundles = [];

  bundleDocs.forEach((doc) => {
    if (!doc.exists) return;

    const bundleData = doc.data();

    if (!bundleData?.products || !Array.isArray(bundleData.products)) return;
    if (typeof bundleData.totalBundlePrice !== 'number') return;
    if (typeof bundleData.totalOriginalPrice !== 'number') return;

    if (bundleData.isActive === false) return;

    if (bundleData.expiresAt) {
      const expiryDate = bundleData.expiresAt.toDate ?
        bundleData.expiresAt.toDate() :
        new Date(bundleData.expiresAt);
      if (expiryDate < new Date()) return;
    }

    const bundleProductIds = bundleData.products
      .map((p) => p?.productId)
      .filter((id) => typeof id === 'string');

    const hasAllProducts = bundleProductIds.every((id) => cartProductIds.has(id));

    if (hasAllProducts && bundleProductIds.length > 0) {
      const savings = bundleData.totalOriginalPrice - bundleData.totalBundlePrice;

      if (savings > 0) {
        applicableBundles.push({
          bundleId: doc.id,
          ...bundleData,
          productIds: bundleProductIds,
          savings,
        });
      }
    }
  });

  if (applicableBundles.length === 0) {
    return null;
  }

  applicableBundles.sort((a, b) => b.savings - a.savings);
  const bestBundle = applicableBundles[0];

  console.log(`💰 [${requestId}] Best bundle: ${bestBundle.bundleId} (saves ${bestBundle.savings})`);

  return bestBundle;
}

/**
 * Calculate totals with all applicable discounts
 * @param {Array<Object>} cartItems - Array of cart items
 * @param {Object|null} selectedBundle - Selected bundle to apply, or null
 * @param {string} requestId - Unique request ID for logging
 * @return {Object} Calculated totals with itemized breakdown
 */
function calculateTotalsWithDiscounts(cartItems, selectedBundle, requestId) {
  const itemTotals = [];
  let total = 0;
  let currency = 'TL';

  const bundledProductIds = new Set(
    selectedBundle ? selectedBundle.productIds : []
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Process bundle items first
  // ─────────────────────────────────────────────────────────────────────────
  if (selectedBundle) {
    const bundleItems = cartItems.filter((item) =>
      bundledProductIds.has(item.productId)
    );

    const quantities = bundleItems.map((item) =>
      Math.max(1, parseInt(item.quantity, 10) || 1)
    );
    const minQuantity = Math.min(...quantities);
    selectedBundle._appliedQuantity = minQuantity;

    const bundlePrice = parseFloat(selectedBundle.totalBundlePrice) || 0;
    const bundleTotal = bundlePrice * minQuantity;

    total += bundleTotal;
    currency = selectedBundle.currency || 'TL';

    itemTotals.push({
      bundleId: selectedBundle.bundleId,
      bundleName: selectedBundle.name || `Bundle (${selectedBundle.productIds.length} products)`,
      unitPrice: roundCurrency(bundlePrice),
      total: roundCurrency(bundleTotal),
      quantity: minQuantity,
      isBundle: true,
      isBundleItem: true,
      productIds: selectedBundle.productIds,
      savings: roundCurrency(selectedBundle.savings * (selectedBundle._appliedQuantity || 1)),
    });

    for (const item of bundleItems) {
      const itemQty = Math.max(1, parseInt(item.quantity, 10) || 1);
      const remainingQty = itemQty - minQuantity;

      if (remainingQty > 0) {
        const {unitPrice, itemTotal} = calculateItemPrice(item, remainingQty);

        total += itemTotal;

        itemTotals.push({
          productId: item.productId,
          productName: item.productName || 'Unknown Product',
          unitPrice: roundCurrency(unitPrice),
          total: roundCurrency(itemTotal),
          quantity: remainingQty,
          isBundle: false,
          isBundleItem: false,
          isExtraBundleQuantity: true,
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Process non-bundled products
  // ─────────────────────────────────────────────────────────────────────────
  for (const item of cartItems) {
    if (bundledProductIds.has(item.productId)) continue;

    const quantity = Math.max(1, parseInt(item.quantity, 10) || 1);
    const {unitPrice, itemTotal, discountApplied} = calculateItemPrice(item, quantity);

    total += itemTotal;
    currency = item.currency || currency;

    itemTotals.push({
      productId: item.productId,
      productName: item.productName || 'Unknown Product',
      unitPrice: roundCurrency(unitPrice),
      total: roundCurrency(itemTotal),
      quantity,
      isBundle: false,
      isBundleItem: false,
      bulkDiscountApplied: discountApplied,
    });
  }

  const totalItemCount = cartItems.reduce((sum, item) => {
    return sum + Math.max(1, parseInt(item.quantity, 10) || 1);
  }, 0);

  return {
    total: roundCurrency(total),
    currency,
    items: itemTotals,
    itemCount: totalItemCount,
    uniqueProductCount: cartItems.length,
    appliedBundle: selectedBundle ? {
      bundleId: selectedBundle.bundleId,
      bundleName: selectedBundle.name,
      savings: roundCurrency(selectedBundle.savings * (selectedBundle._appliedQuantity || 1)),
      productCount: selectedBundle.productIds.length,
    } : null,
  };
}

/**
 * Calculate price for a single item with bulk discounts
 * @param {Object} item - Cart item object
 * @param {number} quantity - Quantity of the item
 * @return {Object} Object containing unitPrice, itemTotal, and discountApplied flag
 */
function calculateItemPrice(item, quantity) {
  let unitPrice = parseFloat(item.unitPrice) ||
                  parseFloat(item.cachedPrice) ||
                  parseFloat(item.price) ||
                  0;

  unitPrice = Math.max(0, unitPrice);

  let discountApplied = false;

  const discountThreshold = parseInt(item.discountThreshold || item.cachedDiscountThreshold, 10);
  const bulkDiscountPercentage = parseInt(item.bulkDiscountPercentage || item.cachedBulkDiscountPercentage, 10);

  if (discountThreshold > 0 &&
      bulkDiscountPercentage > 0 &&
      bulkDiscountPercentage <= 100 &&
      quantity >= discountThreshold) {
    unitPrice = unitPrice * (1 - bulkDiscountPercentage / 100);
    discountApplied = true;
  }

  const itemTotal = unitPrice * quantity;

  return {
    unitPrice,
    itemTotal,
    discountApplied,
  };
}

/**
 * Round to 2 decimal places for currency precision
 * @param {number} value - The value to round
 * @return {number} Value rounded to 2 decimal places
 */
function roundCurrency(value) {
  return Math.round(value * 100) / 100;
}

/**
 * Create empty response object when cart is empty
 * @param {string} requestId - Unique request ID for tracking
 * @param {number} startTime - Timestamp when request started
 * @return {Object} Empty cart totals response
 */
function createEmptyResponse(requestId, startTime) {
  return {
    total: 0,
    currency: 'TL',
    items: [],
    itemCount: 0,
    uniqueProductCount: 0,
    appliedBundle: null,
    requestId,
    calculatedAt: new Date().toISOString(),
    processingTimeMs: Date.now() - startTime,
  };
}
