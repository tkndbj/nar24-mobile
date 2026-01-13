// functions/test/cart-total/cart-total-utils.test.js
//
// Unit tests for cart total price calculation utility functions
// Tests the EXACT logic from cart total cloud function
//
// Run: npx jest test/cart-total/cart-total-utils.test.js

const {
    DEFAULT_CURRENCY,
    RATE_LIMIT_WINDOW_MS,
    RATE_LIMIT_MAX_CALLS,
    BATCH_SIZE,
  
    getUnitPrice,
    getQuantity,
    getCurrency,
    roundPrice,
  
    getBulkDiscountParams,
    shouldApplyBulkDiscount,
    applyBulkDiscount,
    calculateDiscountedPrice,
  
    calculateItemTotal,
    buildItemTotalEntry,
  
    extractBundleIds,
    hasAllBundleProducts,
    calculateBundleSavings,

    findApplicableBundles,
    selectBestBundle,
  
    getMinBundleQuantity,
    calculateBundleLineTotal,
    buildBundleTotalEntry,
    calculateRemainingQuantity,
  
    calculateCartTotal,
    isValidTotal,
    processCartItems,

  
    buildEmptyResponse,
    buildAppliedBundleInfo,

  
    filterRecentCalls,
    isRateLimited,
    addCallTimestamp,
  
    validateSelectedProductIds,
    shouldReturnEmpty,
  
    chunkArray,
    needsBatching,
  
    calculateFullCartTotal,
  } = require('./cart-total-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('DEFAULT_CURRENCY is TL', () => {
      expect(DEFAULT_CURRENCY).toBe('TL');
    });
  
    test('RATE_LIMIT_WINDOW_MS is 10000', () => {
      expect(RATE_LIMIT_WINDOW_MS).toBe(10000);
    });
  
    test('RATE_LIMIT_MAX_CALLS is 5', () => {
      expect(RATE_LIMIT_MAX_CALLS).toBe(5);
    });
  
    test('BATCH_SIZE is 10', () => {
      expect(BATCH_SIZE).toBe(10);
    });
  });
  
  // ============================================================================
  // PRICE HELPERS TESTS
  // ============================================================================
  describe('getUnitPrice', () => {
    test('returns unitPrice when available', () => {
      expect(getUnitPrice({ unitPrice: 100 })).toBe(100);
    });
  
    test('falls back to cachedPrice', () => {
      expect(getUnitPrice({ cachedPrice: 80 })).toBe(80);
    });
  
    test('returns 0 when no price', () => {
      expect(getUnitPrice({})).toBe(0);
    });
  
    test('prefers unitPrice over cachedPrice', () => {
      expect(getUnitPrice({ unitPrice: 100, cachedPrice: 80 })).toBe(100);
    });
  });
  
  describe('getQuantity', () => {
    test('returns quantity when available', () => {
      expect(getQuantity({ quantity: 5 })).toBe(5);
    });
  
    test('defaults to 1', () => {
      expect(getQuantity({})).toBe(1);
    });
  });
  
  describe('getCurrency', () => {
    test('returns item currency', () => {
      expect(getCurrency({ currency: 'USD' })).toBe('USD');
    });
  
    test('returns default when missing', () => {
      expect(getCurrency({}, 'TL')).toBe('TL');
    });
  });
  
  describe('roundPrice', () => {
    test('rounds to 2 decimals', () => {
      expect(roundPrice(99.999)).toBe(100);
      expect(roundPrice(99.994)).toBe(99.99);
      expect(roundPrice(99.995)).toBe(100);
    });
  });
  
  // ============================================================================
  // BULK DISCOUNT TESTS
  // ============================================================================
  describe('getBulkDiscountParams', () => {
    test('extracts direct params', () => {
      const item = { discountThreshold: 5, bulkDiscountPercentage: 10 };
      const params = getBulkDiscountParams(item);
      
      expect(params.discountThreshold).toBe(5);
      expect(params.bulkDiscountPercentage).toBe(10);
    });
  
    test('extracts cached params', () => {
      const item = { cachedDiscountThreshold: 3, cachedBulkDiscountPercentage: 15 };
      const params = getBulkDiscountParams(item);
      
      expect(params.discountThreshold).toBe(3);
      expect(params.bulkDiscountPercentage).toBe(15);
    });
  
    test('returns null for missing params', () => {
      const params = getBulkDiscountParams({});
      expect(params.discountThreshold).toBe(null);
    });
  });
  
  describe('shouldApplyBulkDiscount', () => {
    test('returns true when quantity meets threshold', () => {
      expect(shouldApplyBulkDiscount(5, 5, 10)).toBe(true);
      expect(shouldApplyBulkDiscount(10, 5, 10)).toBe(true);
    });
  
    test('returns false when under threshold', () => {
      expect(shouldApplyBulkDiscount(3, 5, 10)).toBe(false);
    });
  
    test('returns false when params missing', () => {
      expect(shouldApplyBulkDiscount(10, null, 10)).toBe(false);
      expect(shouldApplyBulkDiscount(10, 5, null)).toBe(false);
    });
  });
  
  describe('applyBulkDiscount', () => {
    test('applies 10% discount', () => {
      expect(applyBulkDiscount(100, 10)).toBe(90);
    });
  
    test('applies 25% discount', () => {
      expect(applyBulkDiscount(200, 25)).toBe(150);
    });
  
    test('applies 50% discount', () => {
      expect(applyBulkDiscount(100, 50)).toBe(50);
    });
  });
  
  describe('calculateDiscountedPrice', () => {
    test('returns base price when no discount', () => {
      const item = { unitPrice: 100 };
      expect(calculateDiscountedPrice(item, 1)).toBe(100);
    });
  
    test('applies discount when threshold met', () => {
      const item = { unitPrice: 100, discountThreshold: 5, bulkDiscountPercentage: 20 };
      expect(calculateDiscountedPrice(item, 5)).toBe(80);
    });
  
    test('no discount when under threshold', () => {
      const item = { unitPrice: 100, discountThreshold: 5, bulkDiscountPercentage: 20 };
      expect(calculateDiscountedPrice(item, 3)).toBe(100);
    });
  });
  
  // ============================================================================
  // ITEM TOTAL TESTS
  // ============================================================================
  describe('calculateItemTotal', () => {
    test('calculates simple total', () => {
      const item = { unitPrice: 50, quantity: 3 };
      expect(calculateItemTotal(item)).toBe(150);
    });
  
    test('calculates with discount', () => {
      const item = { unitPrice: 100, quantity: 5, discountThreshold: 5, bulkDiscountPercentage: 10 };
      expect(calculateItemTotal(item)).toBe(450); // 90 * 5
    });
  });
  
  describe('buildItemTotalEntry', () => {
    test('builds entry correctly', () => {
      const item = { productId: 'p1' };
      const entry = buildItemTotalEntry(item, 100, 300, 3, false);
      
      expect(entry.productId).toBe('p1');
      expect(entry.unitPrice).toBe(100);
      expect(entry.total).toBe(300);
      expect(entry.quantity).toBe(3);
      expect(entry.isBundle).toBe(false);
    });
  });
  
  // ============================================================================
  // BUNDLE DETECTION TESTS
  // ============================================================================
  describe('extractBundleIds', () => {
    test('extracts bundle IDs from items', () => {
      const items = [
        { productId: 'p1', bundleData: [{ bundleId: 'b1' }, { bundleId: 'b2' }] },
        { productId: 'p2', bundleData: [{ bundleId: 'b1' }] },
        { productId: 'p3' },
      ];
      
      const ids = extractBundleIds(items);
      expect(ids).toContain('b1');
      expect(ids).toContain('b2');
      expect(ids.length).toBe(2); // Unique
    });
  
    test('returns empty for no bundles', () => {
      expect(extractBundleIds([{ productId: 'p1' }])).toEqual([]);
    });
  });
  
  describe('hasAllBundleProducts', () => {
    test('returns true when all present', () => {
      expect(hasAllBundleProducts(['p1', 'p2'], ['p1', 'p2', 'p3'])).toBe(true);
    });
  
    test('returns false when missing', () => {
      expect(hasAllBundleProducts(['p1', 'p2', 'p4'], ['p1', 'p2', 'p3'])).toBe(false);
    });
  });
  
  describe('calculateBundleSavings', () => {
    test('calculates savings correctly', () => {
      const bundle = { totalOriginalPrice: 200, totalBundlePrice: 150 };
      expect(calculateBundleSavings(bundle)).toBe(50);
    });
  
    test('handles missing values', () => {
      expect(calculateBundleSavings({})).toBe(0);
    });
  });
  
  describe('findApplicableBundles', () => {
    test('finds applicable bundles', () => {
      const bundles = [
        { id: 'b1', products: [{ productId: 'p1' }, { productId: 'p2' }], totalOriginalPrice: 200, totalBundlePrice: 150 },
        { id: 'b2', products: [{ productId: 'p3' }, { productId: 'p4' }], totalOriginalPrice: 300, totalBundlePrice: 250 },
      ];
      const cartItems = [{ productId: 'p1' }, { productId: 'p2' }];
      
      const applicable = findApplicableBundles(bundles, cartItems);
      expect(applicable.length).toBe(1);
      expect(applicable[0].bundleId).toBe('b1');
    });
  });
  
  describe('selectBestBundle', () => {
    test('selects highest savings', () => {
      const bundles = [
        { bundleId: 'b1', savings: 30 },
        { bundleId: 'b2', savings: 50 },
        { bundleId: 'b3', savings: 20 },
      ];
      
      const best = selectBestBundle(bundles);
      expect(best.bundleId).toBe('b2');
    });
  
    test('returns null for empty', () => {
      expect(selectBestBundle([])).toBe(null);
      expect(selectBestBundle(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // BUNDLE TOTAL TESTS
  // ============================================================================
  describe('getMinBundleQuantity', () => {
    test('gets minimum quantity', () => {
      const items = [
        { productId: 'p1', quantity: 3 },
        { productId: 'p2', quantity: 2 },
        { productId: 'p3', quantity: 5 },
      ];
      const bundledIds = new Set(['p1', 'p2']);
      
      expect(getMinBundleQuantity(items, bundledIds)).toBe(2);
    });
  
    test('returns 0 for no matches', () => {
      expect(getMinBundleQuantity([], new Set(['p1']))).toBe(0);
    });
  });
  
  describe('calculateBundleLineTotal', () => {
    test('calculates bundle total', () => {
      const bundle = { totalBundlePrice: 150 };
      expect(calculateBundleLineTotal(bundle, 2)).toBe(300);
    });
  });
  
  describe('buildBundleTotalEntry', () => {
    test('builds bundle entry', () => {
      const bundle = { bundleId: 'b1', totalBundlePrice: 150, productIds: ['p1', 'p2'] };
      const entry = buildBundleTotalEntry(bundle, 2, 300);
      
      expect(entry.bundleId).toBe('b1');
      expect(entry.isBundle).toBe(true);
      expect(entry.productIds).toEqual(['p1', 'p2']);
    });
  });
  
  describe('calculateRemainingQuantity', () => {
    test('calculates remaining', () => {
      expect(calculateRemainingQuantity(5, 2)).toBe(3);
    });
  
    test('returns 0 for none remaining', () => {
      expect(calculateRemainingQuantity(2, 2)).toBe(0);
      expect(calculateRemainingQuantity(1, 2)).toBe(0);
    });
  });
  
  // ============================================================================
  // CART TOTAL TESTS
  // ============================================================================
  describe('calculateCartTotal', () => {
    test('sums totals', () => {
      const items = [{ total: 100 }, { total: 200 }, { total: 50 }];
      expect(calculateCartTotal(items)).toBe(350);
    });
  
    test('returns 0 for empty', () => {
      expect(calculateCartTotal([])).toBe(0);
    });
  });
  
  describe('isValidTotal', () => {
    test('returns true for valid totals', () => {
      expect(isValidTotal(100)).toBe(true);
      expect(isValidTotal(0)).toBe(true);
    });
  
    test('returns false for negative', () => {
      expect(isValidTotal(-1)).toBe(false);
    });
  
    test('returns false for NaN', () => {
      expect(isValidTotal(NaN)).toBe(false);
    });
  });
  
  describe('processCartItems', () => {
    test('processes non-bundled items', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 2 },
        { productId: 'p2', unitPrice: 50, quantity: 1, currency: 'USD' },
      ];
      
      const result = processCartItems(items, new Set());
      
      expect(result.total).toBe(250);
      expect(result.itemTotals.length).toBe(2);
      expect(result.currency).toBe('USD');
    });
  
    test('skips bundled items', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 2 },
        { productId: 'p2', unitPrice: 50, quantity: 1 },
      ];
      
      const result = processCartItems(items, new Set(['p1']));
      
      expect(result.total).toBe(50);
      expect(result.itemTotals.length).toBe(1);
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildEmptyResponse', () => {
    test('builds empty response', () => {
      const response = buildEmptyResponse();
      
      expect(response.total).toBe(0);
      expect(response.currency).toBe('TL');
      expect(response.items).toEqual([]);
      expect(response.calculatedAt).toBeDefined();
    });
  });
  
  describe('buildAppliedBundleInfo', () => {
    test('builds bundle info', () => {
      const bundle = { bundleId: 'b1', savings: 50, productIds: ['p1', 'p2'] };
      const info = buildAppliedBundleInfo(bundle);
      
      expect(info.bundleId).toBe('b1');
      expect(info.savings).toBe(50);
      expect(info.productCount).toBe(2);
    });
  
    test('returns null for no bundle', () => {
      expect(buildAppliedBundleInfo(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // RATE LIMITING TESTS
  // ============================================================================
  describe('filterRecentCalls', () => {
    const now = 10000;
    
    test('filters old calls', () => {
      // Window is 5000ms, now is 10000
      // Calls within window: now - timestamp < windowMs
      // 10000 - 1000 = 9000 (not < 5000, filtered out)
      // 10000 - 5000 = 5000 (not < 5000, filtered out - exactly at boundary)
      // 10000 - 9000 = 1000 (< 5000, kept)
      // 10000 - 9500 = 500 (< 5000, kept)
      const calls = [1000, 5000, 9000, 9500];
      const recent = filterRecentCalls(calls, 5000, now);
      
      expect(recent).toEqual([9000, 9500]);
    });
  
    test('handles null', () => {
      expect(filterRecentCalls(null, 5000, now)).toEqual([]);
    });
  });
  
  describe('isRateLimited', () => {
    test('returns true at limit', () => {
      expect(isRateLimited([1, 2, 3, 4, 5], 5)).toBe(true);
    });
  
    test('returns false under limit', () => {
      expect(isRateLimited([1, 2, 3], 5)).toBe(false);
    });
  });
  
  describe('addCallTimestamp', () => {
    test('adds timestamp', () => {
      const calls = [1000, 2000];
      const updated = addCallTimestamp(calls, 3000);
      
      expect(updated).toEqual([1000, 2000, 3000]);
    });
  });
  
  // ============================================================================
  // INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateSelectedProductIds', () => {
    test('returns valid for array', () => {
      expect(validateSelectedProductIds(['p1', 'p2']).isValid).toBe(true);
    });
  
    test('returns invalid for non-array', () => {
      expect(validateSelectedProductIds('not array').isValid).toBe(false);
    });
  
    test('returns invalid for empty', () => {
      expect(validateSelectedProductIds([]).isValid).toBe(false);
    });
  });
  
  describe('shouldReturnEmpty', () => {
    test('returns true for empty/invalid', () => {
      expect(shouldReturnEmpty([])).toBe(true);
      expect(shouldReturnEmpty(null)).toBe(true);
    });
  
    test('returns false for valid', () => {
      expect(shouldReturnEmpty(['p1'])).toBe(false);
    });
  });
  
  // ============================================================================
  // BATCHING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks correctly', () => {
      const arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      const chunks = chunkArray(arr, 5);
      
      expect(chunks.length).toBe(3);
      expect(chunks[0].length).toBe(5);
      expect(chunks[2].length).toBe(2);
    });
  });
  
  describe('needsBatching', () => {
    test('returns true for > 10', () => {
      expect(needsBatching(Array(15).fill('p'))).toBe(true);
    });
  
    test('returns false for <= 10', () => {
      expect(needsBatching(Array(10).fill('p'))).toBe(false);
    });
  });
  
  // ============================================================================
  // FULL CALCULATION TESTS
  // ============================================================================
  describe('calculateFullCartTotal', () => {
    test('calculates simple cart', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 2 },
        { productId: 'p2', unitPrice: 50, quantity: 1 },
      ];
      
      const result = calculateFullCartTotal(items);
      
      expect(result.total).toBe(250);
      expect(result.items.length).toBe(2);
      expect(result.appliedBundle).toBe(null);
    });
  
    test('returns empty for no items', () => {
      const result = calculateFullCartTotal([]);
      expect(result.total).toBe(0);
    });
  
    test('applies bundle', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 1 },
        { productId: 'p2', unitPrice: 100, quantity: 1 },
      ];
      const bundles = [{
        id: 'b1',
        products: [{ productId: 'p1' }, { productId: 'p2' }],
        totalOriginalPrice: 200,
        totalBundlePrice: 150,
      }];
      
      const result = calculateFullCartTotal(items, bundles);
      
      expect(result.total).toBe(150);
      expect(result.appliedBundle).not.toBe(null);
      expect(result.appliedBundle.savings).toBe(50);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('cart with bulk discount', () => {
      const items = [
        { productId: 'p1', unitPrice: 50, quantity: 10, discountThreshold: 5, bulkDiscountPercentage: 20 },
      ];
      
      const result = calculateFullCartTotal(items);
      
      // 50 * 0.8 * 10 = 400
      expect(result.total).toBe(400);
    });
  
    test('cart with bundle and extra quantities', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 3 },
        { productId: 'p2', unitPrice: 100, quantity: 2 },
      ];
      const bundles = [{
        id: 'b1',
        products: [{ productId: 'p1' }, { productId: 'p2' }],
        totalOriginalPrice: 200,
        totalBundlePrice: 150,
        currency: 'TL',
      }];
      
      const result = calculateFullCartTotal(items, bundles);
      
      // Bundle qty: min(3, 2) = 2, so bundle = 150 * 2 = 300
      // Extra p1: 1 * 100 = 100
      // Total: 400
      expect(result.total).toBe(400);
      expect(result.appliedBundle.bundleId).toBe('b1');
    });
  
    test('selects best bundle from multiple', () => {
      const items = [
        { productId: 'p1', unitPrice: 100, quantity: 1 },
        { productId: 'p2', unitPrice: 100, quantity: 1 },
      ];
      const bundles = [
        {
          id: 'b1',
          products: [{ productId: 'p1' }, { productId: 'p2' }],
          totalOriginalPrice: 200,
          totalBundlePrice: 180, // 20 savings
        },
        {
          id: 'b2',
          products: [{ productId: 'p1' }, { productId: 'p2' }],
          totalOriginalPrice: 200,
          totalBundlePrice: 150, // 50 savings - BEST
        },
      ];
      
      const result = calculateFullCartTotal(items, bundles);
      
      expect(result.appliedBundle.bundleId).toBe('b2');
      expect(result.total).toBe(150);
    });
  });
