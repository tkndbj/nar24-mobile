// functions/test/purchase-utils.test.js
//
// Unit tests for purchase utility functions
// Tests the EXACT logic from purchase cloud functions
//
// Run: npm test (or: npx jest test/purchase-utils.test.js)

const {
    // Shop members
    getShopMemberIdsFromData,
  
    // Object sanitization
    removeUndefined,
  
    // Hash generation
    generateHashVer3,
    getHashKeyOrder,
    buildHashPlainText,
  
    // Payment status
    
    isAuthSuccess,
    isTransactionSuccess,
    validatePaymentStatus,
    verifyCallbackHash,
  
    // Customer name
    sanitizeCustomerName,
  
    // Validation
    
    validateAddress,
 
    validatePickupPoint,
  
    validateDeliveryOption,
    validateCartItems,
    validateCartItem,
    validateCartClearRequest,
  
    // Stock
    hasColorVariant,
    getAvailableStock,
    validateStock,
  
    // Dynamic attributes

    extractDynamicAttributes,
    isSystemField,
  
    // Product images
    getProductImages,
  
    // Bundle & sale preference
    buildBundleInfo,
    buildSalePreferenceInfo,
  
    // Batch processing

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
  } = require('./purchase-utils');
  
  // ============================================================================
  // SHOP MEMBER EXTRACTION TESTS
  // ============================================================================
  describe('getShopMemberIdsFromData', () => {
    test('returns empty array for null shop data', () => {
      expect(getShopMemberIdsFromData(null)).toEqual([]);
    });
  
    test('returns empty array for undefined shop data', () => {
      expect(getShopMemberIdsFromData(undefined)).toEqual([]);
    });
  
    test('returns owner ID when only owner exists', () => {
      const shopData = { ownerId: 'owner123' };
      expect(getShopMemberIdsFromData(shopData)).toEqual(['owner123']);
    });
  
    test('returns owner and coOwners', () => {
      const shopData = {
        ownerId: 'owner123',
        coOwners: ['coowner1', 'coowner2'],
      };
      const result = getShopMemberIdsFromData(shopData);
      expect(result).toContain('owner123');
      expect(result).toContain('coowner1');
      expect(result).toContain('coowner2');
      expect(result.length).toBe(3);
    });
  
    test('returns all member types', () => {
      const shopData = {
        ownerId: 'owner123',
        coOwners: ['coowner1'],
        editors: ['editor1', 'editor2'],
        viewers: ['viewer1'],
      };
      const result = getShopMemberIdsFromData(shopData);
      expect(result).toContain('owner123');
      expect(result).toContain('coowner1');
      expect(result).toContain('editor1');
      expect(result).toContain('editor2');
      expect(result).toContain('viewer1');
      expect(result.length).toBe(5);
    });
  
    test('removes duplicate IDs', () => {
      const shopData = {
        ownerId: 'user123',
        coOwners: ['user123', 'user456'], // owner is also coOwner
        editors: ['user456'], // duplicate
      };
      const result = getShopMemberIdsFromData(shopData);
      expect(result.length).toBe(2);
      expect(result).toContain('user123');
      expect(result).toContain('user456');
    });
  
    test('handles empty arrays', () => {
      const shopData = {
        ownerId: 'owner123',
        coOwners: [],
        editors: [],
        viewers: [],
      };
      expect(getShopMemberIdsFromData(shopData)).toEqual(['owner123']);
    });
  
    test('handles non-array coOwners gracefully', () => {
      const shopData = {
        ownerId: 'owner123',
        coOwners: 'not-an-array',
      };
      // Should not throw
      const result = getShopMemberIdsFromData(shopData);
      expect(result).toContain('owner123');
    });
  });
  
  // ============================================================================
  // REMOVE UNDEFINED TESTS
  // ============================================================================
  describe('removeUndefined', () => {
    test('removes undefined values from object', () => {
      const obj = { a: 1, b: undefined, c: 'hello' };
      const result = removeUndefined(obj);
      expect(result).toEqual({ a: 1, c: 'hello' });
      expect('b' in result).toBe(false);
    });
  
    test('keeps null values', () => {
      const obj = { a: 1, b: null };
      const result = removeUndefined(obj);
      expect(result).toEqual({ a: 1, b: null });
    });
  
    test('keeps empty strings', () => {
      const obj = { a: 1, b: '' };
      const result = removeUndefined(obj);
      expect(result).toEqual({ a: 1, b: '' });
    });
  
    test('keeps zero values', () => {
      const obj = { a: 0, b: 1 };
      const result = removeUndefined(obj);
      expect(result).toEqual({ a: 0, b: 1 });
    });
  
    test('keeps false values', () => {
      const obj = { a: false, b: true };
      const result = removeUndefined(obj);
      expect(result).toEqual({ a: false, b: true });
    });
  
    test('recursively removes undefined in nested objects', () => {
      const obj = {
        a: 1,
        nested: {
          b: 2,
          c: undefined,
          deep: {
            d: undefined,
            e: 3,
          },
        },
      };
      const result = removeUndefined(obj);
      expect(result).toEqual({
        a: 1,
        nested: {
          b: 2,
          deep: {
            e: 3,
          },
        },
      });
    });
  
    test('handles arrays', () => {
      const arr = [{ a: 1, b: undefined }, { c: undefined, d: 2 }];
      const result = removeUndefined(arr);
      expect(result).toEqual([{ a: 1 }, { d: 2 }]);
    });
  
    test('returns primitives unchanged', () => {
      expect(removeUndefined(42)).toBe(42);
      expect(removeUndefined('hello')).toBe('hello');
      expect(removeUndefined(null)).toBe(null);
    });
  
    test('preserves mock Timestamp', () => {
      const mockTimestamp = { seconds: 123, nanoseconds: 456 };
      mockTimestamp.constructor = { name: 'Timestamp' };
      
      const obj = { time: mockTimestamp, other: undefined };
      const result = removeUndefined(obj, {
        isTimestamp: (v) => v && v.constructor && v.constructor.name === 'Timestamp',
      });
      
      expect(result.time).toBe(mockTimestamp);
    });
  
    test('preserves mock FieldValue', () => {
      const mockFieldValue = { _methodName: 'increment' };
      mockFieldValue.constructor = { name: 'FieldValue' };
      
      const obj = { count: mockFieldValue, other: undefined };
      const result = removeUndefined(obj, {
        isFieldValue: (v) => v && v.constructor && v.constructor.name === 'FieldValue',
      });
      
      expect(result.count).toBe(mockFieldValue);
    });
  });
  
  // ============================================================================
  // HASH GENERATION TESTS (CRITICAL - PAYMENT SECURITY)
  // ============================================================================
  describe('generateHashVer3', () => {
    const TEST_STORE_KEY = 'TEST_STORE_KEY_123';
  
    test('generates consistent hash for same params', () => {
      const params = {
        amount: '100',
        currency: '949',
        oid: 'ORDER123',
      };
      const hash1 = generateHashVer3(params, TEST_STORE_KEY);
      const hash2 = generateHashVer3(params, TEST_STORE_KEY);
      expect(hash1).toBe(hash2);
    });
  
    test('generates different hash for different params', () => {
      const params1 = { amount: '100', oid: 'ORDER1' };
      const params2 = { amount: '200', oid: 'ORDER1' };
      
      const hash1 = generateHashVer3(params1, TEST_STORE_KEY);
      const hash2 = generateHashVer3(params2, TEST_STORE_KEY);
      
      expect(hash1).not.toBe(hash2);
    });
  
    test('generates different hash for different store keys', () => {
      const params = { amount: '100', oid: 'ORDER1' };
      
      const hash1 = generateHashVer3(params, 'KEY1');
      const hash2 = generateHashVer3(params, 'KEY2');
      
      expect(hash1).not.toBe(hash2);
    });
  
    test('excludes hash and encoding from calculation', () => {
      const params1 = { amount: '100', oid: 'ORDER1' };
      const params2 = { amount: '100', oid: 'ORDER1', hash: 'ignored', encoding: 'utf-8' };
      
      const hash1 = generateHashVer3(params1, TEST_STORE_KEY);
      const hash2 = generateHashVer3(params2, TEST_STORE_KEY);
      
      expect(hash1).toBe(hash2);
    });
  
    test('sorts keys case-insensitively', () => {
        const params1 = { Amount: '100', amount: '100', AMOUNT: '100' };
        const params2 = { AMOUNT: '100', amount: '100', Amount: '100' };
        
        // Should produce same order
        const keys1 = getHashKeyOrder(params1);
        const keys2 = getHashKeyOrder(params2);
        
        // Both should have 3 keys sorted case-insensitively
        expect(keys1.length).toBe(3);
        expect(keys2.length).toBe(3);
        // All are 'amount' variations, grouped together
        expect(keys1.map((k) => k.toLowerCase())).toEqual(['amount', 'amount', 'amount']);
      });
  
    test('escapes pipe characters in values', () => {
      const params = { value: 'hello|world' };
      const plainText = buildHashPlainText(params, TEST_STORE_KEY);
      
      // Pipe should be escaped as \|
      expect(plainText).toContain('hello\\|world');
    });
  
    test('escapes backslash characters in values', () => {
      const params = { path: 'C:\\Users\\test' };
      const plainText = buildHashPlainText(params, TEST_STORE_KEY);
      
      // Backslash should be escaped as \\
      expect(plainText).toContain('C:\\\\Users\\\\test');
    });
  
    test('handles empty values', () => {
      const params = { amount: '100', email: '' };
      const plainText = buildHashPlainText(params, TEST_STORE_KEY);
      
      // Should have empty value between pipes
      expect(plainText).toContain('|');
    });
  
    test('returns base64 encoded string', () => {
      const params = { amount: '100' };
      const hash = generateHashVer3(params, TEST_STORE_KEY);
      
      // Should be valid base64
      expect(() => Buffer.from(hash, 'base64')).not.toThrow();
    });
  });
  
  describe('getHashKeyOrder', () => {
    test('sorts keys alphabetically case-insensitive', () => {
      const params = {
        Zebra: 1,
        apple: 2,
        BANANA: 3,
      };
      const keys = getHashKeyOrder(params);
      expect(keys).toEqual(['apple', 'BANANA', 'Zebra']);
    });
  
    test('excludes hash and encoding', () => {
      const params = {
        amount: 1,
        hash: 'excluded',
        encoding: 'excluded',
        oid: 'ORDER1',
      };
      const keys = getHashKeyOrder(params);
      expect(keys).not.toContain('hash');
      expect(keys).not.toContain('encoding');
    });
  });
  
  // ============================================================================
  // PAYMENT STATUS VALIDATION TESTS (CRITICAL - MONEY)
  // ============================================================================
  describe('isAuthSuccess', () => {
    test('returns true for mdStatus 1', () => {
      expect(isAuthSuccess('1')).toBe(true);
    });
  
    test('returns true for mdStatus 2', () => {
      expect(isAuthSuccess('2')).toBe(true);
    });
  
    test('returns true for mdStatus 3', () => {
      expect(isAuthSuccess('3')).toBe(true);
    });
  
    test('returns true for mdStatus 4', () => {
      expect(isAuthSuccess('4')).toBe(true);
    });
  
    test('returns false for mdStatus 0', () => {
      expect(isAuthSuccess('0')).toBe(false);
    });
  
    test('returns false for mdStatus 5', () => {
      expect(isAuthSuccess('5')).toBe(false);
    });
  
    test('returns false for empty string', () => {
      expect(isAuthSuccess('')).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isAuthSuccess(null)).toBe(false);
    });
  
    test('returns false for undefined', () => {
      expect(isAuthSuccess(undefined)).toBe(false);
    });
  
    test('returns false for numeric 1 (type matters)', () => {
      expect(isAuthSuccess(1)).toBe(false);
    });
  });
  
  describe('isTransactionSuccess', () => {
    test('returns true for Approved and 00', () => {
      expect(isTransactionSuccess('Approved', '00')).toBe(true);
    });
  
    test('returns false for Declined', () => {
      expect(isTransactionSuccess('Declined', '00')).toBe(false);
    });
  
    test('returns false for wrong proc code', () => {
      expect(isTransactionSuccess('Approved', '01')).toBe(false);
    });
  
    test('returns false for Error response', () => {
      expect(isTransactionSuccess('Error', '00')).toBe(false);
    });
  
    test('returns false for null response', () => {
      expect(isTransactionSuccess(null, '00')).toBe(false);
    });
  
    test('is case sensitive - lowercase fails', () => {
      expect(isTransactionSuccess('approved', '00')).toBe(false);
    });
  });
  
  describe('validatePaymentStatus', () => {
    test('returns success for valid payment', () => {
      const result = validatePaymentStatus({
        Response: 'Approved',
        mdStatus: '1',
        ProcReturnCode: '00',
      });
      expect(result.isSuccess).toBe(true);
      expect(result.reason).toBe('approved');
    });
  
    test('returns auth_failed for bad mdStatus', () => {
      const result = validatePaymentStatus({
        Response: 'Approved',
        mdStatus: '0',
        ProcReturnCode: '00',
      });
      expect(result.isSuccess).toBe(false);
      expect(result.reason).toBe('auth_failed');
    });
  
    test('returns transaction_failed for declined', () => {
      const result = validatePaymentStatus({
        Response: 'Declined',
        mdStatus: '1',
        ProcReturnCode: '05',
        ErrMsg: 'Insufficient funds',
      });
      expect(result.isSuccess).toBe(false);
      expect(result.reason).toBe('transaction_failed');
      expect(result.message).toBe('Insufficient funds');
    });
  });
  
  describe('verifyCallbackHash', () => {
    test('returns skipped when hashParamsVal is missing', () => {
      const result = verifyCallbackHash('somehash', null, 'storekey');
      expect(result.skipped).toBe(true);
    });
  
    test('returns skipped when hash is missing', () => {
      const result = verifyCallbackHash(null, 'params', 'storekey');
      expect(result.skipped).toBe(true);
    });
  
    test('returns valid for matching hash', () => {
      const storeKey = 'testkey';
      const hashParamsVal = 'testvalue';
      const crypto = require('crypto');
      const expectedHash = crypto.createHash('sha512')
        .update(hashParamsVal + storeKey, 'utf8')
        .digest('base64');
      
      const result = verifyCallbackHash(expectedHash, hashParamsVal, storeKey);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid for non-matching hash', () => {
      const result = verifyCallbackHash('wronghash', 'testvalue', 'testkey');
      expect(result.isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // CUSTOMER NAME SANITIZATION TESTS
  // ============================================================================
  describe('sanitizeCustomerName', () => {
    test('returns Customer for null', () => {
      expect(sanitizeCustomerName(null)).toBe('Customer');
    });
  
    test('returns Customer for empty string', () => {
      expect(sanitizeCustomerName('')).toBe('Customer');
    });
  
    test('returns Customer for undefined', () => {
      expect(sanitizeCustomerName(undefined)).toBe('Customer');
    });
  
    test('keeps alphanumeric characters', () => {
      expect(sanitizeCustomerName('John123')).toBe('John123');
    });
  
    test('keeps spaces', () => {
      expect(sanitizeCustomerName('John Doe')).toBe('John Doe');
    });
  
    test('removes special characters', () => {
      expect(sanitizeCustomerName('John@Doe!')).toBe('JohnDoe');
    });
  
    test('removes Turkish special characters without transliteration', () => {
      // Without transliteration, Turkish chars are removed
      expect(sanitizeCustomerName('Ömer Çelik')).toBe('mer elik');
    });
  
    test('uses transliteration function when provided', () => {
      const transliterate = (s) => s.replace(/ö/g, 'o').replace(/ç/g, 'c').replace(/Ö/g, 'O').replace(/Ç/g, 'C');
      expect(sanitizeCustomerName('Ömer Çelik', transliterate)).toBe('Omer Celik');
    });
  
    test('trims whitespace', () => {
      expect(sanitizeCustomerName('  John Doe  ')).toBe('John Doe');
    });
  
    test('truncates to 50 characters', () => {
      const longName = 'A'.repeat(100);
      expect(sanitizeCustomerName(longName).length).toBe(50);
    });
  
    test('returns Customer if sanitization results in empty string', () => {
      expect(sanitizeCustomerName('!!!@@@###')).toBe('Customer');
    });
  });
  
  // ============================================================================
  // ADDRESS VALIDATION TESTS
  // ============================================================================
  describe('validateAddress', () => {
    test('returns invalid for null', () => {
      const result = validateAddress(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_type');
    });
  
    test('returns invalid for string', () => {
      const result = validateAddress('not an object');
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for complete address', () => {
      const address = {
        addressLine1: '123 Main St',
        city: 'Istanbul',
        phoneNumber: '+905551234567',
        location: { lat: 41.0, lng: 29.0 },
      };
      const result = validateAddress(address);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid when missing addressLine1', () => {
      const address = {
        city: 'Istanbul',
        phoneNumber: '+905551234567',
        location: { lat: 41.0, lng: 29.0 },
      };
      const result = validateAddress(address);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('addressLine1');
    });
  
    test('returns invalid when missing city', () => {
      const address = {
        addressLine1: '123 Main St',
        phoneNumber: '+905551234567',
        location: { lat: 41.0, lng: 29.0 },
      };
      const result = validateAddress(address);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('city');
    });
  
    test('returns invalid when missing phoneNumber', () => {
      const address = {
        addressLine1: '123 Main St',
        city: 'Istanbul',
        location: { lat: 41.0, lng: 29.0 },
      };
      const result = validateAddress(address);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('phoneNumber');
    });
  
    test('returns invalid when missing location', () => {
      const address = {
        addressLine1: '123 Main St',
        city: 'Istanbul',
        phoneNumber: '+905551234567',
      };
      const result = validateAddress(address);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('location');
    });
  
    test('reports first missing field in message', () => {
      const result = validateAddress({});
      expect(result.message).toContain(result.missingFields[0]);
    });
  });
  
  // ============================================================================
  // PICKUP POINT VALIDATION TESTS
  // ============================================================================
  describe('validatePickupPoint', () => {
    test('returns invalid for null', () => {
      const result = validatePickupPoint(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for complete pickup point', () => {
      const pickupPoint = {
        pickupPointId: 'PP123',
        pickupPointName: 'Mall Pickup',
        pickupPointAddress: '456 Mall Ave',
      };
      const result = validatePickupPoint(pickupPoint);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid when missing pickupPointId', () => {
      const pickupPoint = {
        pickupPointName: 'Mall Pickup',
        pickupPointAddress: '456 Mall Ave',
      };
      const result = validatePickupPoint(pickupPoint);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('pickupPointId');
    });
  
    test('returns invalid when missing pickupPointName', () => {
      const pickupPoint = {
        pickupPointId: 'PP123',
        pickupPointAddress: '456 Mall Ave',
      };
      const result = validatePickupPoint(pickupPoint);
      expect(result.isValid).toBe(false);
      expect(result.missingFields).toContain('pickupPointName');
    });
  });
  
  // ============================================================================
  // DELIVERY OPTION VALIDATION TESTS
  // ============================================================================
  describe('validateDeliveryOption', () => {
    test('returns valid for normal', () => {
      expect(validateDeliveryOption('normal').isValid).toBe(true);
    });
  
    test('returns valid for express', () => {
      expect(validateDeliveryOption('express').isValid).toBe(true);
    });
  
    test('returns invalid for pickup', () => {
      // Note: 'pickup' is handled differently, not in VALID_DELIVERY_OPTIONS
      expect(validateDeliveryOption('pickup').isValid).toBe(false);
    });
  
    test('returns invalid for empty string', () => {
      expect(validateDeliveryOption('').isValid).toBe(false);
    });
  
    test('returns invalid for null', () => {
      expect(validateDeliveryOption(null).isValid).toBe(false);
    });
  
    test('is case sensitive', () => {
      expect(validateDeliveryOption('Normal').isValid).toBe(false);
      expect(validateDeliveryOption('EXPRESS').isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // CART ITEMS VALIDATION TESTS
  // ============================================================================
  describe('validateCartItems', () => {
    test('returns invalid for null', () => {
      expect(validateCartItems(null).isValid).toBe(false);
    });
  
    test('returns invalid for empty array', () => {
      expect(validateCartItems([]).isValid).toBe(false);
    });
  
    test('returns invalid for non-array', () => {
      expect(validateCartItems('not array').isValid).toBe(false);
    });
  
    test('returns valid for array with items', () => {
      const result = validateCartItems([{ productId: 'p1' }]);
      expect(result.isValid).toBe(true);
      expect(result.itemCount).toBe(1);
    });
  });
  
  describe('validateCartItem', () => {
    test('returns invalid for null item', () => {
      expect(validateCartItem(null).isValid).toBe(false);
    });
  
    test('returns invalid for missing productId', () => {
      expect(validateCartItem({}).isValid).toBe(false);
    });
  
    test('returns invalid for non-string productId', () => {
      expect(validateCartItem({ productId: 123 }).isValid).toBe(false);
    });
  
    test('returns invalid for empty productId', () => {
      expect(validateCartItem({ productId: '' }).isValid).toBe(false);
    });
  
    test('returns valid for valid item', () => {
      const result = validateCartItem({ productId: 'product123' });
      expect(result.isValid).toBe(true);
      expect(result.productId).toBe('product123');
    });
  });
  
  // ============================================================================
  // STOCK VALIDATION TESTS (CRITICAL - PREVENTS OVERSELLING)
  // ============================================================================
  describe('hasColorVariant', () => {
    test('returns false for null colorKey', () => {
      expect(hasColorVariant(null, { colorQuantities: { red: 5 } })).toBe(false);
    });
  
    test('returns false when colorQuantities missing', () => {
      expect(hasColorVariant('red', {})).toBe(false);
    });
  
    test('returns false when color not in colorQuantities', () => {
      expect(hasColorVariant('blue', { colorQuantities: { red: 5 } })).toBe(false);
    });
  
    test('returns true when color exists in colorQuantities', () => {
      expect(hasColorVariant('red', { colorQuantities: { red: 5 } })).toBe(true);
    });
  
    test('returns true even when quantity is 0', () => {
      // Color exists, just out of stock
      expect(hasColorVariant('red', { colorQuantities: { red: 0 } })).toBe(true);
    });
  });
  
  describe('getAvailableStock', () => {
    test('returns color quantity when color variant exists', () => {
      expect(getAvailableStock('red', { colorQuantities: { red: 10 } })).toBe(10);
    });
  
    test('returns 0 when color quantity is 0', () => {
      expect(getAvailableStock('red', { colorQuantities: { red: 0 } })).toBe(0);
    });
  
    test('returns general quantity when no color selected', () => {
      expect(getAvailableStock(null, { quantity: 15 })).toBe(15);
    });
  
    test('returns general quantity when color not found', () => {
      expect(getAvailableStock('blue', { colorQuantities: { red: 5 }, quantity: 15 })).toBe(15);
    });
  
    test('returns 0 when no stock info', () => {
      expect(getAvailableStock(null, {})).toBe(0);
    });
  });
  
  describe('validateStock', () => {
    test('returns valid when enough general stock', () => {
      const result = validateStock(
        { quantity: 2 },
        { productName: 'Test', quantity: 5 }
      );
      expect(result.isValid).toBe(true);
      expect(result.available).toBe(5);
      expect(result.requested).toBe(2);
    });
  
    test('returns invalid when not enough general stock', () => {
      const result = validateStock(
        { quantity: 10 },
        { productName: 'Test Product', quantity: 5 }
      );
      expect(result.isValid).toBe(false);
      expect(result.available).toBe(5);
      expect(result.requested).toBe(10);
      expect(result.message).toContain('Not enough stock');
      expect(result.message).toContain('Test Product');
    });
  
    test('returns valid when enough color stock', () => {
      const result = validateStock(
        { quantity: 2, selectedColor: 'red' },
        { productName: 'Test', colorQuantities: { red: 5 } }
      );
      expect(result.isValid).toBe(true);
      expect(result.hasColorVariant).toBe(true);
      expect(result.colorKey).toBe('red');
    });
  
    test('returns invalid when not enough color stock', () => {
      const result = validateStock(
        { quantity: 10, selectedColor: 'red' },
        { productName: 'Test', colorQuantities: { red: 3 } }
      );
      expect(result.isValid).toBe(false);
      expect(result.message).toContain('color \'red\' stock: 3');
    });
  
    test('uses minimum quantity of 1', () => {
      const result = validateStock(
        { quantity: 0 }, // Invalid quantity
        { productName: 'Test', quantity: 1 }
      );
      expect(result.requested).toBe(1); // Clamped to 1
      expect(result.isValid).toBe(true);
    });
  
    test('handles missing quantity as 1', () => {
      const result = validateStock(
        {}, // No quantity specified
        { productName: 'Test', quantity: 1 }
      );
      expect(result.requested).toBe(1);
      expect(result.isValid).toBe(true);
    });
  
    test('returns invalid when color does not exist', () => {
      const result = validateStock(
        { quantity: 1, selectedColor: 'purple' }, // Color doesn't exist
        { productName: 'Test', colorQuantities: { red: 5 }, quantity: 10 }
      );
      // Falls back to general quantity since purple doesn't exist
      expect(result.hasColorVariant).toBe(false);
      expect(result.isValid).toBe(true); // General stock is 10
    });
  });
  
  // ============================================================================
  // DYNAMIC ATTRIBUTES TESTS
  // ============================================================================
  describe('extractDynamicAttributes', () => {
    test('extracts non-system fields', () => {
      const item = {
        productId: 'p1', // system field
        quantity: 2, // system field
        selectedColor: 'red', // dynamic
        selectedSize: 'M', // dynamic
      };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ selectedColor: 'red', selectedSize: 'M' });
    });
  
    test('excludes undefined values', () => {
      const item = {
        customField: undefined,
        validField: 'value',
      };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ validField: 'value' });
    });
  
    test('excludes null values', () => {
      const item = {
        customField: null,
        validField: 'value',
      };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ validField: 'value' });
    });
  
    test('excludes empty strings', () => {
      const item = {
        customField: '',
        validField: 'value',
      };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ validField: 'value' });
    });
  
    test('keeps zero values', () => {
      const item = { customNumber: 0 };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ customNumber: 0 });
    });
  
    test('keeps false values', () => {
      const item = { customBool: false };
      const result = extractDynamicAttributes(item);
      expect(result).toEqual({ customBool: false });
    });
  });
  
  describe('isSystemField', () => {
    test('returns true for productId', () => {
      expect(isSystemField('productId')).toBe(true);
    });
  
    test('returns true for quantity', () => {
      expect(isSystemField('quantity')).toBe(true);
    });
  
    test('returns true for calculatedUnitPrice', () => {
      expect(isSystemField('calculatedUnitPrice')).toBe(true);
    });
  
    test('returns false for selectedColor', () => {
      expect(isSystemField('selectedColor')).toBe(false);
    });
  
    test('returns false for custom fields', () => {
      expect(isSystemField('customAttribute')).toBe(false);
    });
  });
  
  // ============================================================================
  // PRODUCT IMAGES TESTS
  // ============================================================================
  describe('getProductImages', () => {
    test('returns color image when color selected and available', () => {
      const result = getProductImages('red', {
        colorImages: { red: ['red1.jpg', 'red2.jpg'] },
        imageUrls: ['default.jpg'],
      });
      expect(result.productImage).toBe('red1.jpg');
      expect(result.selectedColorImage).toBe('red1.jpg');
    });
  
    test('falls back to default image when color not available', () => {
      const result = getProductImages('blue', {
        colorImages: { red: ['red1.jpg'] },
        imageUrls: ['default.jpg'],
      });
      expect(result.productImage).toBe('default.jpg');
      expect(result.selectedColorImage).toBe(null);
    });
  
    test('falls back to default when no color selected', () => {
      const result = getProductImages(null, {
        imageUrls: ['default.jpg', 'default2.jpg'],
      });
      expect(result.productImage).toBe('default.jpg');
      expect(result.selectedColorImage).toBe(null);
    });
  
    test('returns empty strings when no images available', () => {
      const result = getProductImages(null, {});
      expect(result.productImage).toBe('');
      expect(result.selectedColorImage).toBe(null);
    });
  
    test('handles empty colorImages array', () => {
      const result = getProductImages('red', {
        colorImages: { red: [] },
        imageUrls: ['default.jpg'],
      });
      expect(result.productImage).toBe('default.jpg');
    });
  });
  
  // ============================================================================
  // BUNDLE INFO TESTS
  // ============================================================================
  describe('buildBundleInfo', () => {
    test('returns null when not a bundle item', () => {
      const result = buildBundleInfo(
        { isBundleItem: false },
        { price: 100 }
      );
      expect(result).toBe(null);
    });
  
    test('returns null when price is not reduced', () => {
      const result = buildBundleInfo(
        { isBundleItem: true, calculatedUnitPrice: 100 },
        { price: 100 }
      );
      expect(result).toBe(null);
    });
  
    test('returns bundle info when discounted', () => {
      const result = buildBundleInfo(
        { isBundleItem: true, calculatedUnitPrice: 80 },
        { price: 100, bundleDiscount: 20 }
      );
      expect(result).toEqual({
        wasInBundle: true,
        originalPrice: 100,
        bundlePrice: 80,
        bundleDiscount: 20, // 20% discount
        bundleDiscountAmount: 20,
        originalBundleDiscountPercentage: 20,
      });
    });
  
    test('calculates correct discount percentage', () => {
      const result = buildBundleInfo(
        { isBundleItem: true, calculatedUnitPrice: 75 },
        { price: 100 }
      );
      expect(result.bundleDiscount).toBe(25); // 25% off
    });
  });
  
  // ============================================================================
  // SALE PREFERENCE INFO TESTS
  // ============================================================================
  describe('buildSalePreferenceInfo', () => {
    test('returns null when no sale preferences', () => {
      const result = buildSalePreferenceInfo({ quantity: 2 }, { price: 100 });
      expect(result).toBe(null);
    });
  
    test('returns null when missing discountThreshold', () => {
      const result = buildSalePreferenceInfo(
        { salePreferences: { discountPercentage: 10 } },
        { price: 100 }
      );
      expect(result).toBe(null);
    });
  
    test('returns info when quantity meets threshold', () => {
      const result = buildSalePreferenceInfo(
        {
          quantity: 5,
          salePreferences: { discountThreshold: 5, discountPercentage: 10 },
          calculatedUnitPrice: 90,
        },
        { price: 100 }
      );
      expect(result.discountApplied).toBe(true);
      expect(result.discountThreshold).toBe(5);
      expect(result.discountPercentage).toBe(10);
    });
  
    test('returns info when quantity below threshold', () => {
      const result = buildSalePreferenceInfo(
        {
          quantity: 2,
          salePreferences: { discountThreshold: 5, discountPercentage: 10 },
        },
        { price: 100 }
      );
      expect(result.discountApplied).toBe(false);
    });
  });
  
  // ============================================================================
  // BATCH PROCESSING TESTS
  // ============================================================================
  describe('calculateBatchCount', () => {
    test('returns 1 for items under batch size', () => {
      expect(calculateBatchCount(100)).toBe(1);
    });
  
    test('returns 1 for exactly batch size', () => {
      expect(calculateBatchCount(500)).toBe(1);
    });
  
    test('returns 2 for items over batch size', () => {
      expect(calculateBatchCount(501)).toBe(2);
    });
  
    test('handles large numbers', () => {
      expect(calculateBatchCount(1500)).toBe(3);
    });
  
    test('respects custom batch size', () => {
      expect(calculateBatchCount(250, 100)).toBe(3);
    });
  });
  
  describe('chunkArray', () => {
    test('returns single chunk for small array', () => {
      const result = chunkArray([1, 2, 3], 500);
      expect(result).toEqual([[1, 2, 3]]);
    });
  
    test('splits array into correct chunks', () => {
      const arr = [1, 2, 3, 4, 5];
      const result = chunkArray(arr, 2);
      expect(result).toEqual([[1, 2], [3, 4], [5]]);
    });
  
    test('handles empty array', () => {
      expect(chunkArray([])).toEqual([]);
    });
  
    test('handles array exactly divisible by chunk size', () => {
      const result = chunkArray([1, 2, 3, 4], 2);
      expect(result).toEqual([[1, 2], [3, 4]]);
    });
  });
  
  // ============================================================================
  // SELLER ADDRESS TESTS
  // ============================================================================
  describe('extractShopSellerAddress', () => {
    test('returns null for null shop data', () => {
      expect(extractShopSellerAddress(null)).toBe(null);
    });
  
    test('returns N/A when address missing', () => {
      const result = extractShopSellerAddress({});
      expect(result.addressLine1).toBe('N/A');
    });
  
    test('extracts address and location', () => {
      const result = extractShopSellerAddress({
        address: '123 Shop St',
        latitude: 41.0,
        longitude: 29.0,
      });
      expect(result.addressLine1).toBe('123 Shop St');
      expect(result.location).toEqual({ lat: 41.0, lng: 29.0 });
    });
  
    test('returns null location when coordinates missing', () => {
      const result = extractShopSellerAddress({ address: '123 Shop St' });
      expect(result.location).toBe(null);
    });
  });
  
  describe('extractUserSellerAddress', () => {
    test('returns null for null user data', () => {
      expect(extractUserSellerAddress(null)).toBe(null);
    });
  
    test('returns null when sellerInfo missing', () => {
      expect(extractUserSellerAddress({})).toBe(null);
    });
  
    test('extracts seller address from sellerInfo', () => {
      const result = extractUserSellerAddress({
        sellerInfo: {
          address: '456 Seller St',
          latitude: 40.0,
          longitude: 28.0,
        },
      });
      expect(result.addressLine1).toBe('456 Seller St');
      expect(result.location).toEqual({ lat: 40.0, lng: 28.0 });
    });
  });
  
  // ============================================================================
  // PAYMENT FORMATTING TESTS
  // ============================================================================
  describe('formatPaymentAmount', () => {
    test('formats integer amount', () => {
      expect(formatPaymentAmount(100)).toBe('100');
    });
  
    test('rounds decimal amount', () => {
      expect(formatPaymentAmount(99.99)).toBe('100');
    });
  
    test('handles string amount', () => {
      expect(formatPaymentAmount('150.5')).toBe('151');
    });
  
    test('rounds down at .4', () => {
      expect(formatPaymentAmount(99.4)).toBe('99');
    });
  
    test('rounds up at .5', () => {
      expect(formatPaymentAmount(99.5)).toBe('100');
    });
  });
  
  // ============================================================================
  // IDEMPOTENCY TESTS
  // ============================================================================
  describe('isValidPaymentOrderId', () => {
    test('returns false for null', () => {
      expect(isValidPaymentOrderId(null)).toBe(false);
    });
  
    test('returns false for undefined', () => {
      expect(isValidPaymentOrderId(undefined)).toBe(false);
    });
  
    test('returns false for empty string', () => {
      expect(isValidPaymentOrderId('')).toBe(false);
    });
  
    test('returns false for non-string', () => {
      expect(isValidPaymentOrderId(12345)).toBe(false);
    });
  
    test('returns true for valid order ID', () => {
      expect(isValidPaymentOrderId('ORDER123')).toBe(true);
    });
  });
  
  // ============================================================================
  // NOTIFICATION RECIPIENTS TESTS
  // ============================================================================
  describe('getNotificationRecipients', () => {
    test('returns shop members excluding buyer', () => {
      const result = getNotificationRecipients(
        { shopMembers: ['owner', 'coowner', 'buyer123'] },
        'buyer123'
      );
      expect(result).toEqual(['owner', 'coowner']);
    });
  
    test('returns seller for user products', () => {
      const result = getNotificationRecipients(
        { data: { userId: 'seller456' } },
        'buyer123'
      );
      expect(result).toEqual(['seller456']);
    });
  
    test('excludes seller if seller is buyer', () => {
      const result = getNotificationRecipients(
        { data: { userId: 'sameUser' } },
        'sameUser'
      );
      expect(result).toEqual([]);
    });
  
    test('returns empty array when no recipients', () => {
      const result = getNotificationRecipients({}, 'buyer123');
      expect(result).toEqual([]);
    });
  });
  
  // ============================================================================
  // INVENTORY SKIP TESTS
  // ============================================================================
  describe('shouldSkipStockDeduction', () => {
    test('returns true for Curtains', () => {
      expect(shouldSkipStockDeduction({ subsubcategory: 'Curtains' })).toBe(true);
    });
  
    test('returns false for other categories', () => {
      expect(shouldSkipStockDeduction({ subsubcategory: 'Shirts' })).toBe(false);
    });
  
    test('returns false when subsubcategory missing', () => {
      expect(shouldSkipStockDeduction({})).toBe(false);
    });
  });
  
  // ============================================================================
  // CART CLEAR VALIDATION TESTS
  // ============================================================================
  describe('validateCartClearRequest', () => {
    test('returns invalid for null body', () => {
      const result = validateCartClearRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing buyerId', () => {
      const result = validateCartClearRequest({ purchasedProductIds: ['p1'] });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_buyer_id');
    });
  
    test('returns invalid for non-array productIds', () => {
      const result = validateCartClearRequest({ buyerId: 'b1', purchasedProductIds: 'not array' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_product_ids');
    });
  
    test('returns invalid for empty productIds array', () => {
      const result = validateCartClearRequest({ buyerId: 'b1', purchasedProductIds: [] });
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for correct request', () => {
      const result = validateCartClearRequest({
        buyerId: 'buyer123',
        purchasedProductIds: ['p1', 'p2'],
      });
      expect(result.isValid).toBe(true);
      expect(result.productCount).toBe(2);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete order validation flow', () => {
      // Validate cart items
      const itemsResult = validateCartItems([
        { productId: 'product1', quantity: 2, selectedColor: 'red' },
      ]);
      expect(itemsResult.isValid).toBe(true);
  
      // Validate delivery option
      const deliveryResult = validateDeliveryOption('express');
      expect(deliveryResult.isValid).toBe(true);
  
      // Validate address
      const addressResult = validateAddress({
        addressLine1: '123 Main St',
        city: 'Istanbul',
        phoneNumber: '+905551234567',
        location: { lat: 41.0, lng: 29.0 },
      });
      expect(addressResult.isValid).toBe(true);
  
      // Validate stock
      const stockResult = validateStock(
        { quantity: 2, selectedColor: 'red' },
        { productName: 'Test Product', colorQuantities: { red: 10 } }
      );
      expect(stockResult.isValid).toBe(true);
    });
  
    test('payment callback validation flow', () => {
      const paymentResponse = {
        Response: 'Approved',
        mdStatus: '1',
        ProcReturnCode: '00',
      };
  
      const statusResult = validatePaymentStatus(paymentResponse);
      expect(statusResult.isSuccess).toBe(true);
    });
  
    test('overselling prevention with color variants', () => {
      // Customer tries to buy 5 red items when only 3 in stock
      const stockResult = validateStock(
        { quantity: 5, selectedColor: 'red' },
        {
          productName: 'Limited Edition Shirt',
          colorQuantities: { red: 3, blue: 10 },
          quantity: 50, // General stock is high but red is low
        }
      );
  
      expect(stockResult.isValid).toBe(false);
      expect(stockResult.available).toBe(3);
      expect(stockResult.requested).toBe(5);
      expect(stockResult.hasColorVariant).toBe(true);
      expect(stockResult.message).toContain('color \'red\' stock: 3');
    });
  
    test('hash generation for İşbank payment', () => {
      const params = {
        BillToName: 'John Doe',
        amount: '15000',
        callbackurl: 'https://example.com/callback',
        clientid: 'CLIENT123',
        currency: '949',
        email: 'john@example.com',
        failurl: 'https://example.com/fail',
        hashAlgorithm: 'ver3',
        islemtipi: 'Auth',
        lang: 'tr',
        oid: 'ORDER-1234567890',
        okurl: 'https://example.com/ok',
        rnd: '1234567890',
        storetype: '3d_pay_hosting',
        taksit: '',
        tel: '+905551234567',
      };
  
      const hash = generateHashVer3(params, 'SECRET_STORE_KEY');
  
      // Hash should be consistent
      expect(hash).toBe(generateHashVer3(params, 'SECRET_STORE_KEY'));
  
      // Hash should be different with different key
      expect(hash).not.toBe(generateHashVer3(params, 'DIFFERENT_KEY'));
    });
  });
