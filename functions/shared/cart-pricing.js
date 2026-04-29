// functions/shared/cart-pricing.js
//
// Single source of truth for cart pricing.
//
// Used by:
//   - 9-cart-total-price (display totals from user's cart subcollection)
//   - 29-product-payment (server-authoritative totals at payment + order time)
//
// Items can be cart docs (unitPrice/cachedPrice) or product docs (price).
// All helpers normalize across these field names.

/**
 * Round to 2 decimal places for currency precision.
 * @param {number} value
 * @return {number}
 */
export function roundCurrency(value) {
  return Math.round(value * 100) / 100;
}

/**
 * Resolve unit price for an item, applying bulk discount if threshold met.
 * Works for both cart-doc and product-doc shapes.
 * @param {Object} item
 * @param {number} quantity
 * @return {{unitPrice: number, itemTotal: number, discountApplied: boolean}}
 */
export function calculateItemPrice(item, quantity) {
  let unitPrice = parseFloat(item.unitPrice) ||
                  parseFloat(item.cachedPrice) ||
                  parseFloat(item.price) ||
                  0;

  unitPrice = Math.max(0, unitPrice);
  let discountApplied = false;

  const discountThreshold = parseInt(
    item.discountThreshold ?? item.cachedDiscountThreshold,
    10,
  );
  const bulkDiscountPercentage = parseInt(
    item.bulkDiscountPercentage ?? item.cachedBulkDiscountPercentage,
    10,
  );

  if (discountThreshold > 0 &&
      bulkDiscountPercentage > 0 &&
      bulkDiscountPercentage <= 100 &&
      quantity >= discountThreshold) {
    unitPrice = unitPrice * (1 - bulkDiscountPercentage / 100);
    discountApplied = true;
  }

  const itemTotal = unitPrice * quantity;
  return { unitPrice, itemTotal, discountApplied };
}

/**
 * Find the bundle with highest savings that's fully satisfied by the cart.
 * Returns null if no bundle qualifies.
 * @param {FirebaseFirestore.Firestore} db
 * @param {Array<Object>} cartItems
 * @param {string} [requestId]
 * @return {Promise<Object|null>}
 */
export async function findBestApplicableBundle(db, cartItems, requestId = '') {
  const uniqueBundleIds = new Set();

  cartItems.forEach((item) => {
    if (Array.isArray(item.bundleData)) {
      item.bundleData.forEach((bd) => {
        if (bd?.bundleId && typeof bd.bundleId === 'string') {
          uniqueBundleIds.add(bd.bundleId);
        }
      });
    }
    if (Array.isArray(item.bundleIds)) {
      item.bundleIds.forEach((id) => {
        if (typeof id === 'string' && id.trim()) {
          uniqueBundleIds.add(id.trim());
        }
      });
    }
  });

  if (uniqueBundleIds.size === 0) return null;

  if (requestId) {
    console.log(`🔍 [${requestId}] Checking ${uniqueBundleIds.size} potential bundles`);
  }

  const bundleDocs = await Promise.all(
    Array.from(uniqueBundleIds).map((id) =>
      db.collection('bundles').doc(id).get(),
    ),
  );

  const cartProductIds = new Set(cartItems.map((item) => item.productId));
  const applicableBundles = [];

  bundleDocs.forEach((doc) => {
    if (!doc.exists) return;
    const bundleData = doc.data();

    if (!Array.isArray(bundleData?.products)) return;
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
    if (!hasAllProducts || bundleProductIds.length === 0) return;

    const savings = bundleData.totalOriginalPrice - bundleData.totalBundlePrice;
    if (savings <= 0) return;

    applicableBundles.push({
      bundleId: doc.id,
      ...bundleData,
      productIds: bundleProductIds,
      savings,
    });
  });

  if (applicableBundles.length === 0) return null;

  applicableBundles.sort((a, b) => b.savings - a.savings);
  const best = applicableBundles[0];

  if (requestId) {
    console.log(`💰 [${requestId}] Best bundle: ${best.bundleId} (saves ${best.savings})`);
  }
  return best;
}

/**
 * Compute cart subtotal with bulk + bundle discounts.
 *
 * Returns:
 *   - total, currency: subtotal sum and currency code
 *   - items:           display breakdown (bundle as single entry + extras)
 *   - itemPrices:      per-cartItem resolved prices (one entry per input item).
 *                      Used by payment CF to write authoritative per-item prices
 *                      into order docs/receipts. Bundle items get the equal-split
 *                      price for the bundled portion, plus bulk price for any
 *                      extra quantity above the bundle multiple, blended to a
 *                      single unitPrice covering the full quantity.
 *   - itemCount, uniqueProductCount, appliedBundle: as before
 *
 * @param {Array<Object>} cartItems
 * @param {Object|null} selectedBundle
 * @param {string} [requestId]
 * @return {Object}
 */
export function calculateTotalsWithDiscounts(cartItems, selectedBundle, requestId = '') {
  const itemTotals = [];
  const itemPrices = [];
  let total = 0;
  let currency = 'TL';

  const bundledProductIds = new Set(
    selectedBundle ? selectedBundle.productIds : [],
  );

  // ── Bundle items first ──────────────────────────────────────────────────
  if (selectedBundle) {
    const bundleItems = cartItems.filter((item) =>
      bundledProductIds.has(item.productId));

    const quantities = bundleItems.map((item) =>
      Math.max(1, parseInt(item.quantity, 10) || 1));
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

    // Equal-split per-product price for the bundled portion.
    const splitUnitPrice = bundlePrice / selectedBundle.productIds.length;

    for (const item of bundleItems) {
      const itemQty = Math.max(1, parseInt(item.quantity, 10) || 1);
      const bundleQty = minQuantity;
      const remainingQty = itemQty - bundleQty;

      let itemTotalForCharge = splitUnitPrice * bundleQty;

      if (remainingQty > 0) {
        const { unitPrice, itemTotal: extraTotal } = calculateItemPrice(item, remainingQty);
        total += extraTotal;
        itemTotalForCharge += extraTotal;

        itemTotals.push({
          productId: item.productId,
          productName: item.productName || 'Unknown Product',
          unitPrice: roundCurrency(unitPrice),
          total: roundCurrency(extraTotal),
          quantity: remainingQty,
          isBundle: false,
          isBundleItem: false,
          isExtraBundleQuantity: true,
        });
      }

      itemPrices.push({
        productId: item.productId,
        quantity: itemQty,
        unitPrice: roundCurrency(itemTotalForCharge / itemQty),
        itemTotal: roundCurrency(itemTotalForCharge),
        isBundleItem: true,
        currency,
      });
    }
  }

  // ── Non-bundled products ────────────────────────────────────────────────
  for (const item of cartItems) {
    if (bundledProductIds.has(item.productId)) continue;

    const quantity = Math.max(1, parseInt(item.quantity, 10) || 1);
    const { unitPrice, itemTotal, discountApplied } = calculateItemPrice(item, quantity);

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

    itemPrices.push({
      productId: item.productId,
      quantity,
      unitPrice: roundCurrency(unitPrice),
      itemTotal: roundCurrency(itemTotal),
      isBundleItem: false,
      currency,
    });
  }

  const totalItemCount = cartItems.reduce(
    (sum, item) => sum + Math.max(1, parseInt(item.quantity, 10) || 1),
    0,
  );

  return {
    total: roundCurrency(total),
    currency,
    items: itemTotals,
    itemPrices,
    itemCount: totalItemCount,
    uniqueProductCount: cartItems.length,
    appliedBundle: selectedBundle ? {
      bundleId: selectedBundle.bundleId,
      // Fallback so the field is never undefined — Firestore writes reject undefined values.
      bundleName: selectedBundle.name || `Bundle (${selectedBundle.productIds.length} products)`,
      savings: roundCurrency(selectedBundle.savings * (selectedBundle._appliedQuantity || 1)),
      productCount: selectedBundle.productIds.length,
      productIds: selectedBundle.productIds,
    } : null,
  };
}
