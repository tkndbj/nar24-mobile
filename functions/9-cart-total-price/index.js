import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {checkRateLimit as redisRateLimit} from '../shared/redis.js';
import {
  calculateTotalsWithDiscounts,
  findBestApplicableBundle,
} from '../shared/cart-pricing.js';

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
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create empty response object when cart is empty.
 * @param {string} requestId
 * @param {number} startTime
 * @return {Object}
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
