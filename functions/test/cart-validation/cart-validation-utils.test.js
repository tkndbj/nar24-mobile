// functions/test/cart-validation/cart-validation-utils.test.js
//
// Unit tests for cart validation utility functions
// Tests the EXACT logic from cart validation cloud functions
//
// Run: npx jest test/cart-validation/cart-validation-utils.test.js

const {
    MAX_CART_ITEMS,
    MIN_QUANTITY,
    PRICE_TOLERANCE,
    ALLOWED_UPDATE_FIELDS,
    ERROR_KEYS,
    WARNING_KEYS,
  
    safeNumber,
    safePrice,
    safeString,
  
    hasChanged,
    hasPriceChanged,
    hasMaxQuantityReduced,
  
    validateCartItems,
    validateProductUpdates,
    filterAllowedFields,
  
    calculateAvailableStock,
    isProductAvailable,
    hasStock,
    hasSufficientStock,
    isWithinMaxQuantity,
  
    calculateFinalUnitPrice,
    calculateItemTotal,
    calculateCartTotal,
    extractBundlePrice,
  
    getColorImage,
    getProductImage,
  
    createValidationResult,
    addError,
    addWarning,

    finalizeResult,
  
    shouldRateLimit,
    isWindowExpired,
    createRateLimitEntry,
  

    buildReservationItem,
    buildStockDecrementUpdate,
  
    chunkArray,
    calculateBatchCount,
  
    createUpdateResult,
    buildUpdateResponse,
  } = require('./cart-validation-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MAX_CART_ITEMS is 500', () => {
      expect(MAX_CART_ITEMS).toBe(500);
    });
  
    test('MIN_QUANTITY is 1', () => {
      expect(MIN_QUANTITY).toBe(1);
    });
  
    test('PRICE_TOLERANCE is 0.01', () => {
      expect(PRICE_TOLERANCE).toBe(0.01);
    });
  
    test('ERROR_KEYS has all error types', () => {
      expect(ERROR_KEYS.PRODUCT_NOT_AVAILABLE).toBe('product_not_available');
      expect(ERROR_KEYS.OUT_OF_STOCK).toBe('out_of_stock');
      expect(ERROR_KEYS.INSUFFICIENT_STOCK).toBe('insufficient_stock');
    });
  
    test('WARNING_KEYS has all warning types', () => {
      expect(WARNING_KEYS.PRICE_CHANGED).toBe('price_changed');
      expect(WARNING_KEYS.DISCOUNT_UPDATED).toBe('discount_updated');
    });
  
    test('ALLOWED_UPDATE_FIELDS contains expected fields', () => {
      expect(ALLOWED_UPDATE_FIELDS).toContain('cachedPrice');
      expect(ALLOWED_UPDATE_FIELDS).toContain('cachedBundlePrice');
      expect(ALLOWED_UPDATE_FIELDS).toContain('maxQuantity');
    });
  });
  
  // ============================================================================
  // SAFE VALUE HELPERS TESTS
  // ============================================================================
  describe('safeNumber', () => {
    test('returns number for valid number', () => {
      expect(safeNumber(42)).toBe(42);
      expect(safeNumber(3.14)).toBe(3.14);
    });
  
    test('returns default for null', () => {
      expect(safeNumber(null)).toBe(0);
      expect(safeNumber(null, 10)).toBe(10);
    });
  
    test('returns default for undefined', () => {
      expect(safeNumber(undefined)).toBe(0);
    });
  
    test('returns default for NaN', () => {
      expect(safeNumber(NaN)).toBe(0);
    });
  
    test('converts string to number', () => {
      expect(safeNumber('42')).toBe(42);
    });
  });
  
  describe('safePrice', () => {
    test('formats price with 2 decimals', () => {
      expect(safePrice(100)).toBe('100.00');
      expect(safePrice(99.9)).toBe('99.90');
      expect(safePrice(99.999)).toBe('100.00');
    });
  
    test('handles null', () => {
      expect(safePrice(null)).toBe('0.00');
    });
  });
  
  describe('safeString', () => {
    test('returns string value', () => {
      expect(safeString('test')).toBe('test');
    });
  
    test('returns default for null', () => {
      expect(safeString(null)).toBe('');
      expect(safeString(null, 'default')).toBe('default');
    });
  });
  
  // ============================================================================
  // CHANGE DETECTION TESTS
  // ============================================================================
  describe('hasChanged', () => {
    test('returns false if cached is undefined', () => {
      expect(hasChanged(undefined, 100)).toBe(false);
    });
  
    test('returns false if both null', () => {
      expect(hasChanged(null, null)).toBe(false);
    });
  
    test('returns true if only one is null', () => {
      expect(hasChanged(100, null)).toBe(true);
      expect(hasChanged(null, 100)).toBe(true);
    });
  
    test('returns true if values differ', () => {
      expect(hasChanged(100, 200)).toBe(true);
    });
  
    test('returns false if values same', () => {
      expect(hasChanged(100, 100)).toBe(false);
    });
  
    test('works with strings', () => {
      expect(hasChanged('red', 'blue')).toBe(true);
      expect(hasChanged('red', 'red')).toBe(false);
    });
  });
  
  describe('hasPriceChanged', () => {
    test('returns false if cached undefined', () => {
      expect(hasPriceChanged(undefined, 100)).toBe(false);
    });
  
    test('returns false within tolerance', () => {
      expect(hasPriceChanged(100, 100.005)).toBe(false);
    });
  
    test('returns true outside tolerance', () => {
      expect(hasPriceChanged(100, 100.02)).toBe(true);
    });
  
    test('handles null values', () => {
      expect(hasPriceChanged(null, 100)).toBe(true);
    });
  });
  
  describe('hasMaxQuantityReduced', () => {
    test('returns false if cached undefined', () => {
      expect(hasMaxQuantityReduced(undefined, 5)).toBe(false);
    });
  
    test('returns false if current undefined', () => {
      expect(hasMaxQuantityReduced(10, undefined)).toBe(false);
    });
  
    test('returns true if reduced', () => {
      expect(hasMaxQuantityReduced(10, 5)).toBe(true);
    });
  
    test('returns false if increased', () => {
      expect(hasMaxQuantityReduced(5, 10)).toBe(false);
    });
  
    test('returns false if same', () => {
      expect(hasMaxQuantityReduced(10, 10)).toBe(false);
    });
  });
  
  // ============================================================================
  // INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateCartItems', () => {
    test('returns invalid for non-array', () => {
      const result = validateCartItems('not array');
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for empty array', () => {
      const result = validateCartItems([]);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for > 500 items', () => {
      const items = Array(501).fill({ productId: 'p1', quantity: 1 });
      const result = validateCartItems(items);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing productId', () => {
      const result = validateCartItems([{ quantity: 1 }]);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for invalid quantity', () => {
      const result = validateCartItems([{ productId: 'p1', quantity: 0 }]);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for correct items', () => {
      const items = [{ productId: 'p1', quantity: 2 }];
      const result = validateCartItems(items);
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('validateProductUpdates', () => {
    test('returns valid for correct updates', () => {
      const updates = [{ productId: 'p1', updates: { cachedPrice: 100 } }];
      const result = validateProductUpdates(updates);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid for missing productId', () => {
      const updates = [{ updates: { cachedPrice: 100 } }];
      const result = validateProductUpdates(updates);
      expect(result.isValid).toBe(false);
    });
  });
  
  describe('filterAllowedFields', () => {
    test('filters out non-allowed fields', () => {
      const updates = {
        cachedPrice: 100,
        maliciousField: 'bad',
        maxQuantity: 10,
      };
      const filtered = filterAllowedFields(updates);
      
      expect(filtered.cachedPrice).toBe(100);
      expect(filtered.maxQuantity).toBe(10);
      expect(filtered.maliciousField).toBeUndefined();
    });
  
    test('returns empty object for null', () => {
      expect(filterAllowedFields(null)).toEqual({});
    });
  });
  
  // ============================================================================
  // STOCK CALCULATION TESTS
  // ============================================================================
  describe('calculateAvailableStock', () => {
    test('returns color quantity when selected', () => {
      const product = { quantity: 100, colorQuantities: { red: 25, blue: 30 } };
      expect(calculateAvailableStock(product, 'red')).toBe(25);
    });
  
    test('returns general quantity when no color', () => {
      const product = { quantity: 100 };
      expect(calculateAvailableStock(product, null)).toBe(100);
    });
  
    test('returns general quantity when color not found', () => {
      const product = { quantity: 100, colorQuantities: { red: 25 } };
      expect(calculateAvailableStock(product, 'green')).toBe(100);
    });
  
    test('returns 0 for null product', () => {
      expect(calculateAvailableStock(null, null)).toBe(0);
    });
  });
  
  describe('isProductAvailable', () => {
    test('returns false for null product', () => {
      expect(isProductAvailable(null)).toBe(false);
    });
  
    test('returns false for paused product', () => {
      expect(isProductAvailable({ paused: true })).toBe(false);
    });
  
    test('returns true for active product', () => {
      expect(isProductAvailable({ paused: false })).toBe(true);
      expect(isProductAvailable({})).toBe(true);
    });
  });
  
  describe('hasStock', () => {
    test('returns true when stock > 0', () => {
      expect(hasStock({ quantity: 10 }, null)).toBe(true);
    });
  
    test('returns false when stock = 0', () => {
      expect(hasStock({ quantity: 0 }, null)).toBe(false);
    });
  });
  
  describe('hasSufficientStock', () => {
    test('returns true when enough stock', () => {
      expect(hasSufficientStock({ quantity: 10 }, null, 5)).toBe(true);
    });
  
    test('returns false when not enough', () => {
      expect(hasSufficientStock({ quantity: 5 }, null, 10)).toBe(false);
    });
  });
  
  describe('isWithinMaxQuantity', () => {
    test('returns true when no limit', () => {
      expect(isWithinMaxQuantity({}, 100)).toBe(true);
    });
  
    test('returns true when within limit', () => {
      expect(isWithinMaxQuantity({ maxQuantity: 10 }, 5)).toBe(true);
    });
  
    test('returns false when over limit', () => {
      expect(isWithinMaxQuantity({ maxQuantity: 5 }, 10)).toBe(false);
    });
  });
  
  // ============================================================================
  // PRICE CALCULATION TESTS
  // ============================================================================
  describe('calculateFinalUnitPrice', () => {
    test('returns base price without discount', () => {
      const product = { price: 100 };
      expect(calculateFinalUnitPrice(product, 1)).toBe(100);
    });
  
    test('applies bulk discount when threshold met', () => {
      const product = { price: 100, discountThreshold: 5, bulkDiscountPercentage: 10 };
      expect(calculateFinalUnitPrice(product, 5)).toBe(90);
    });
  
    test('no discount when under threshold', () => {
      const product = { price: 100, discountThreshold: 5, bulkDiscountPercentage: 10 };
      expect(calculateFinalUnitPrice(product, 3)).toBe(100);
    });
  
    test('handles 50% discount', () => {
      const product = { price: 200, discountThreshold: 10, bulkDiscountPercentage: 50 };
      expect(calculateFinalUnitPrice(product, 10)).toBe(100);
    });
  });
  
  describe('calculateItemTotal', () => {
    test('calculates correctly', () => {
      expect(calculateItemTotal(100, 3)).toBe(300);
      expect(calculateItemTotal(49.99, 2)).toBeCloseTo(99.98, 2);
    });
  });
  
  describe('calculateCartTotal', () => {
    test('sums all item totals', () => {
      const items = [{ total: 100 }, { total: 200 }, { total: 50 }];
      expect(calculateCartTotal(items)).toBe(350);
    });
  
    test('returns 0 for empty', () => {
      expect(calculateCartTotal([])).toBe(0);
    });
  });
  
  describe('extractBundlePrice', () => {
    test('extracts from bundleData array', () => {
      const product = { bundleData: [{ bundlePrice: 150 }] };
      expect(extractBundlePrice(product)).toBe(150);
    });
  
    test('returns null for missing bundleData', () => {
      expect(extractBundlePrice({})).toBe(null);
    });
  
    test('returns null for empty bundleData', () => {
      expect(extractBundlePrice({ bundleData: [] })).toBe(null);
    });
  });
  
  // ============================================================================
  // IMAGE EXTRACTION TESTS
  // ============================================================================
  describe('getColorImage', () => {
    test('returns first image for selected color', () => {
      const product = { colorImages: { red: ['red1.jpg', 'red2.jpg'] } };
      expect(getColorImage(product, 'red')).toBe('red1.jpg');
    });
  
    test('returns null for no selected color', () => {
      const product = { colorImages: { red: ['red1.jpg'] } };
      expect(getColorImage(product, null)).toBe(null);
    });
  
    test('returns null for missing color', () => {
      const product = { colorImages: { red: ['red1.jpg'] } };
      expect(getColorImage(product, 'blue')).toBe(null);
    });
  });
  
  describe('getProductImage', () => {
    test('returns first image', () => {
      const product = { imageUrls: ['img1.jpg', 'img2.jpg'] };
      expect(getProductImage(product)).toBe('img1.jpg');
    });
  
    test('returns empty string for no images', () => {
      expect(getProductImage({})).toBe('');
    });
  });
  
  // ============================================================================
  // RESULT BUILDING TESTS
  // ============================================================================
  describe('createValidationResult', () => {
    test('creates initial result', () => {
      const result = createValidationResult();
      
      expect(result.isValid).toBe(true);
      expect(result.errors).toEqual({});
      expect(result.warnings).toEqual({});
      expect(result.validatedItems).toEqual([]);
      expect(result.totalPrice).toBe(0);
    });
  });
  
  describe('addError', () => {
    test('adds error and sets invalid', () => {
      const result = createValidationResult();
      addError(result, 'prod1', 'out_of_stock', {});
      
      expect(result.isValid).toBe(false);
      expect(result.errors.prod1.key).toBe('out_of_stock');
    });
  });
  
  describe('addWarning', () => {
    test('adds warning without changing validity', () => {
      const result = createValidationResult();
      addWarning(result, 'prod1', 'price_changed', { oldPrice: 100, newPrice: 120 });
      
      expect(result.isValid).toBe(true);
      expect(result.warnings.prod1.key).toBe('price_changed');
    });
  });
  
  describe('finalizeResult', () => {
    test('adds hasWarnings and processingTime', () => {
      const result = createValidationResult();
      addWarning(result, 'p1', 'price_changed', {});
      
      const final = finalizeResult(result, 150);
      
      expect(final.hasWarnings).toBe(true);
      expect(final.processingTimeMs).toBe(150);
    });
  });
  
  // ============================================================================
  // RATE LIMITING TESTS
  // ============================================================================
  describe('shouldRateLimit', () => {
    test('returns true when at limit', () => {
      expect(shouldRateLimit(30, 30)).toBe(true);
    });
  
    test('returns false when under limit', () => {
      expect(shouldRateLimit(20, 30)).toBe(false);
    });
  });
  
  describe('isWindowExpired', () => {
    test('returns true when past window', () => {
      const now = Date.now();
      const windowStart = now - 70000;
      expect(isWindowExpired(windowStart, 60000, now)).toBe(true);
    });
  
    test('returns false when in window', () => {
      const now = Date.now();
      const windowStart = now - 30000;
      expect(isWindowExpired(windowStart, 60000, now)).toBe(false);
    });
  });
  
  describe('createRateLimitEntry', () => {
    test('creates entry with count 1', () => {
      const now = 1000;
      const entry = createRateLimitEntry(now);
      
      expect(entry.count).toBe(1);
      expect(entry.windowStart).toBe(1000);
    });
  });
  
  // ============================================================================
  // RESERVATION TESTS
  // ============================================================================
  describe('buildReservationItem', () => {
    test('builds item correctly', () => {
      const cartItem = { productId: 'p1', quantity: 3, selectedColor: 'red' };
      const item = buildReservationItem(cartItem);
      
      expect(item.productId).toBe('p1');
      expect(item.quantity).toBe(3);
      expect(item.selectedColor).toBe('red');
    });
  
    test('handles null color', () => {
      const cartItem = { productId: 'p1', quantity: 2 };
      const item = buildReservationItem(cartItem);
      
      expect(item.selectedColor).toBe(null);
    });
  });
  
  describe('buildStockDecrementUpdate', () => {
    test('builds color-specific update', () => {
      const update = buildStockDecrementUpdate('red', 5);
      expect(update.field).toBe('colorQuantities.red');
      expect(update.decrement).toBe(5);
    });
  
    test('builds general update', () => {
      const update = buildStockDecrementUpdate(null, 5);
      expect(update.field).toBe('quantity');
    });
  });
  
  // ============================================================================
  // BATCHING TESTS
  // ============================================================================
  describe('chunkArray', () => {
    test('chunks correctly', () => {
      const arr = [1, 2, 3, 4, 5];
      const chunks = chunkArray(arr, 2);
      expect(chunks).toEqual([[1, 2], [3, 4], [5]]);
    });
  
    test('handles empty', () => {
      expect(chunkArray([], 10)).toEqual([]);
    });
  });
  
  describe('calculateBatchCount', () => {
    test('calculates correctly', () => {
      expect(calculateBatchCount(1000, 500)).toBe(2);
      expect(calculateBatchCount(501, 500)).toBe(2);
    });
  });
  
  // ============================================================================
  // UPDATE RESULTS TESTS
  // ============================================================================
  describe('createUpdateResult', () => {
    test('creates empty result', () => {
      const result = createUpdateResult();
      expect(result.updated).toEqual([]);
      expect(result.failed).toEqual([]);
      expect(result.skipped).toEqual([]);
    });
  });
  
  describe('buildUpdateResponse', () => {
    test('builds response correctly', () => {
      const results = { updated: ['p1', 'p2'], failed: [], skipped: ['p3'] };
      const response = buildUpdateResponse(results, 100);
      
      expect(response.success).toBe(true);
      expect(response.updated).toBe(2);
      expect(response.skipped).toBe(1);
      expect(response.failed).toBe(0);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete cart validation flow', () => {
      // 1. Validate cart items
      const cartItems = [
        { productId: 'p1', quantity: 2, selectedColor: 'red', cachedPrice: 100 },
        { productId: 'p2', quantity: 1 },
      ];
      expect(validateCartItems(cartItems).isValid).toBe(true);
  
      // 2. Create validation result
      const result = createValidationResult();
  
      // 3. Check product availability
      const product = { 
        price: 110, 
        quantity: 50, 
        colorQuantities: { red: 10 },
        colorImages: { red: ['red.jpg'] },
        productName: 'Test Product',
      };
      expect(isProductAvailable(product)).toBe(true);
  
      // 4. Check stock
     
      expect(hasSufficientStock(product, 'red', 2)).toBe(true);
  
      // 5. Check price change
      expect(hasPriceChanged(100, 110)).toBe(true);
      addWarning(result, 'p1', 'price_changed', { oldPrice: 100, newPrice: 110 });
  
      // 6. Calculate price
      const unitPrice = calculateFinalUnitPrice(product, 2);
      const total = calculateItemTotal(unitPrice, 2);
      expect(total).toBe(220);
  
      // 7. Get color image
      const colorImage = getColorImage(product, 'red');
      expect(colorImage).toBe('red.jpg');
  
      // 8. Finalize result
      const final = finalizeResult(result, 150);
      expect(final.hasWarnings).toBe(true);
    });
  
    test('bulk discount scenario', () => {
      const product = {
        price: 50,
        discountThreshold: 10,
        bulkDiscountPercentage: 20,
        quantity: 100,
      };
  
      // Under threshold
      expect(calculateFinalUnitPrice(product, 5)).toBe(50);
      
      // At threshold
      expect(calculateFinalUnitPrice(product, 10)).toBe(40);
      
      // Over threshold
      expect(calculateFinalUnitPrice(product, 20)).toBe(40);
    });
  
    test('stock validation with colors', () => {
      const product = {
        quantity: 100,
        colorQuantities: { red: 5, blue: 20, green: 0 },
      };
  
      // Color with stock
      expect(calculateAvailableStock(product, 'red')).toBe(5);
      expect(hasSufficientStock(product, 'red', 3)).toBe(true);
      expect(hasSufficientStock(product, 'red', 10)).toBe(false);
  
      // Color out of stock
      expect(calculateAvailableStock(product, 'green')).toBe(0);
      expect(hasStock(product, 'green')).toBe(false);
  
      // No color - use general
      expect(calculateAvailableStock(product, null)).toBe(100);
    });
  });
