// functions/test/boost-payment/boost-payment-utils.test.js
//
// Unit tests for boost payment and logic utility functions
// Tests the EXACT logic from boost cloud functions
//
// Run: npx jest test/boost-payment/boost-payment-utils.test.js

const {
    BASE_PRICE_PER_PRODUCT,
    MAX_BOOST_DURATION_MINUTES,
    MAX_ITEMS_PER_BOOST,
    BATCH_SIZE,
    VALID_COLLECTIONS,

    PROMOTION_SCORE_BOOST,
  
    validateBoostItems,
    validateBoostDuration,
    validatePaymentInitInput,
  
    calculateBoostPrice,
    calculatePricePerItem,
    formatAmount,
  
    generateOrderNumber,
    parseOrderNumber,
  
    checkProductPermission,
    checkShopMembership,
    getShopMembers,
  
    isAlreadyBoosted,
    getBoostTimeRemaining,
  
    calculateBoostEndTime,
    calculateScheduleTime,
    isWithinExpirationTolerance,

  
    generateTaskName,
    parseTaskName,
  
    buildBoostUpdateData,
    buildBoostExpirationData,
  
    buildBoostHistoryData,
    getHistoryCollectionPath,
  
    
    calculateImpressionsDuringBoost,
    calculateClicksDuringBoost,
   
  
    buildBoostExpiredNotification,
  
    buildBoostResult,

    groupItemsByOwner,
  
    sanitizeCustomerName,
  
    isStaleTask,
    shouldSkipExpiration,
  } = require('./boost-payment-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('BASE_PRICE_PER_PRODUCT is 1.0', () => {
      expect(BASE_PRICE_PER_PRODUCT).toBe(1.0);
    });
  
    test('MAX_BOOST_DURATION_MINUTES is 10080 (7 days)', () => {
      expect(MAX_BOOST_DURATION_MINUTES).toBe(10080);
    });
  
    test('MAX_ITEMS_PER_BOOST is 50', () => {
      expect(MAX_ITEMS_PER_BOOST).toBe(50);
    });
  
    test('BATCH_SIZE is 10', () => {
      expect(BATCH_SIZE).toBe(10);
    });
  
    test('VALID_COLLECTIONS contains products and shop_products', () => {
      expect(VALID_COLLECTIONS).toContain('products');
      expect(VALID_COLLECTIONS).toContain('shop_products');
    });
  
    test('PROMOTION_SCORE_BOOST is 1000', () => {
      expect(PROMOTION_SCORE_BOOST).toBe(1000);
    });
  });
  
  // ============================================================================
  // ITEMS VALIDATION TESTS
  // ============================================================================
  describe('validateBoostItems', () => {
    test('returns invalid for null', () => {
      const result = validateBoostItems(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for non-array', () => {
      const result = validateBoostItems('not-array');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_array');
    });
  
    test('returns invalid for empty array', () => {
      const result = validateBoostItems([]);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty');
    });
  
    test('returns invalid for > 50 items', () => {
      const items = Array(51).fill({ itemId: 'test', collection: 'products' });
      const result = validateBoostItems(items);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('too_many');
    });
  
    test('returns invalid for missing itemId', () => {
      const items = [{ collection: 'products' }];
      const result = validateBoostItems(items);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_items');
    });
  
    test('returns invalid for invalid collection', () => {
      const items = [{ itemId: 'test', collection: 'invalid' }];
      const result = validateBoostItems(items);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for shop_products without shopId', () => {
      const items = [{ itemId: 'test', collection: 'shop_products' }];
      const result = validateBoostItems(items);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for correct products item', () => {
      const items = [{ itemId: 'test', collection: 'products' }];
      expect(validateBoostItems(items).isValid).toBe(true);
    });
  
    test('returns valid for correct shop_products item', () => {
      const items = [{ itemId: 'test', collection: 'shop_products', shopId: 'shop123' }];
      expect(validateBoostItems(items).isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // DURATION VALIDATION TESTS
  // ============================================================================
  describe('validateBoostDuration', () => {
    test('returns invalid for null', () => {
      expect(validateBoostDuration(null).isValid).toBe(false);
    });
  
    test('returns invalid for non-number', () => {
      expect(validateBoostDuration('30').isValid).toBe(false);
    });
  
    test('returns invalid for zero', () => {
      expect(validateBoostDuration(0).isValid).toBe(false);
    });
  
    test('returns invalid for negative', () => {
      expect(validateBoostDuration(-30).isValid).toBe(false);
    });
  
    test('returns invalid for > 10080', () => {
      expect(validateBoostDuration(10081).isValid).toBe(false);
    });
  
    test('returns valid for 30 minutes', () => {
      expect(validateBoostDuration(30).isValid).toBe(true);
    });
  
    test('returns valid for 10080 (max)', () => {
      expect(validateBoostDuration(10080).isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // COMPLETE VALIDATION TESTS
  // ============================================================================
  describe('validatePaymentInitInput', () => {
    test('returns valid for complete input', () => {
      const data = {
        items: [{ itemId: 'test', collection: 'products' }],
        boostDuration: 30,
      };
      expect(validatePaymentInitInput(data).isValid).toBe(true);
    });
  
    test('returns multiple errors', () => {
      const data = { items: [], boostDuration: 0 };
      const result = validatePaymentInitInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBe(2);
    });
  });
  
  // ============================================================================
  // PRICE CALCULATION TESTS
  // ============================================================================
  describe('calculateBoostPrice', () => {
    test('calculates price correctly', () => {
      expect(calculateBoostPrice(5, 30)).toBe(150); // 5 * 30 * 1.0
    });
  
    test('calculates with custom price', () => {
      expect(calculateBoostPrice(5, 30, 2.0)).toBe(300); // 5 * 30 * 2.0
    });
  
    test('handles single item', () => {
      expect(calculateBoostPrice(1, 60)).toBe(60);
    });
  });
  
  describe('calculatePricePerItem', () => {
    test('calculates price per item', () => {
      expect(calculatePricePerItem(30)).toBe(30);
    });
  });
  
  describe('formatAmount', () => {
    test('rounds and converts to string', () => {
      expect(formatAmount(150.5)).toBe('151');
      expect(formatAmount(150.4)).toBe('150');
    });
  });
  
  // ============================================================================
  // ORDER NUMBER TESTS
  // ============================================================================
  describe('generateOrderNumber', () => {
    test('generates order number format', () => {
      const orderNumber = generateOrderNumber('user123456789', 1234567890);
      expect(orderNumber).toBe('BOOST-1234567890-user1234');
    });
  
    test('handles missing userId', () => {
      const orderNumber = generateOrderNumber(null, 1234567890);
      expect(orderNumber).toBe('BOOST-1234567890-unknown');
    });
  });
  
  describe('parseOrderNumber', () => {
    test('parses valid order number', () => {
      const parsed = parseOrderNumber('BOOST-1234567890-user1234');
      expect(parsed.type).toBe('BOOST');
      expect(parsed.timestamp).toBe(1234567890);
      expect(parsed.userPrefix).toBe('user1234');
    });
  
    test('returns null for invalid format', () => {
      expect(parseOrderNumber('INVALID-123')).toBe(null);
    });
  });
  
  // ============================================================================
  // PERMISSION TESTS
  // ============================================================================
  describe('checkProductPermission', () => {
    test('returns true for admin', () => {
      expect(checkProductPermission('products', {}, 'user1', true)).toBe(true);
    });
  
    test('returns true for product owner', () => {
      expect(checkProductPermission('products', { userId: 'user1' }, 'user1', false)).toBe(true);
    });
  
    test('returns false for non-owner', () => {
      expect(checkProductPermission('products', { userId: 'user2' }, 'user1', false)).toBe(false);
    });
  
    test('returns false for shop_products (needs separate check)', () => {
      expect(checkProductPermission('shop_products', {}, 'user1', false)).toBe(false);
    });
  });
  
  describe('checkShopMembership', () => {
    test('returns true for owner', () => {
      expect(checkShopMembership({ ownerId: 'user1' }, 'user1')).toBe(true);
    });
  
    test('returns true for editor', () => {
      expect(checkShopMembership({ ownerId: 'user2', editors: ['user1'] }, 'user1')).toBe(true);
    });
  
    test('returns true for coOwner', () => {
      expect(checkShopMembership({ ownerId: 'user2', coOwners: ['user1'] }, 'user1')).toBe(true);
    });
  
    test('returns true for viewer', () => {
      expect(checkShopMembership({ ownerId: 'user2', viewers: ['user1'] }, 'user1')).toBe(true);
    });
  
    test('returns false for non-member', () => {
      expect(checkShopMembership({ ownerId: 'user2' }, 'user1')).toBe(false);
    });
  
    test('returns false for null shopData', () => {
      expect(checkShopMembership(null, 'user1')).toBe(false);
    });
  });
  
  describe('getShopMembers', () => {
    test('collects all members', () => {
      const shopData = {
        ownerId: 'owner',
        coOwners: ['co1', 'co2'],
        editors: ['ed1'],
        viewers: ['v1'],
      };
      const members = getShopMembers(shopData);
      expect(members.size).toBe(5);
      expect(members.has('owner')).toBe(true);
      expect(members.has('co1')).toBe(true);
    });
  
    test('returns empty set for null', () => {
      expect(getShopMembers(null).size).toBe(0);
    });
  });
  
  // ============================================================================
  // BOOST STATUS TESTS
  // ============================================================================
  describe('isAlreadyBoosted', () => {
    const futureTime = new Date(Date.now() + 60000);
    const pastTime = new Date(Date.now() - 60000);
  
    test('returns true for boosted with future end time', () => {
      const productData = { isBoosted: true, boostEndTime: futureTime };
      expect(isAlreadyBoosted(productData)).toBe(true);
    });
  
    test('returns false for not boosted', () => {
      const productData = { isBoosted: false, boostEndTime: futureTime };
      expect(isAlreadyBoosted(productData)).toBe(false);
    });
  
    test('returns false for expired boost', () => {
      const productData = { isBoosted: true, boostEndTime: pastTime };
      expect(isAlreadyBoosted(productData)).toBe(false);
    });
  
    test('handles Firestore timestamp', () => {
      const productData = {
        isBoosted: true,
        boostEndTime: { toDate: () => futureTime },
      };
      expect(isAlreadyBoosted(productData)).toBe(true);
    });
  });
  
  describe('getBoostTimeRemaining', () => {
    test('returns remaining time', () => {
      const now = Date.now();
      const futureTime = new Date(now + 60000);
      const productData = { isBoosted: true, boostEndTime: futureTime };
      const remaining = getBoostTimeRemaining(productData, now);
      expect(remaining).toBeGreaterThan(59000);
      expect(remaining).toBeLessThanOrEqual(60000);
    });
  
    test('returns 0 for not boosted', () => {
      const productData = { isBoosted: false };
      expect(getBoostTimeRemaining(productData)).toBe(0);
    });
  });
  
  // ============================================================================
  // TIME CALCULATION TESTS
  // ============================================================================
  describe('calculateBoostEndTime', () => {
    test('calculates end time correctly', () => {
      const start = Date.now();
      const end = calculateBoostEndTime(30, start);
      expect(end.getTime() - start).toBe(30 * 60 * 1000);
    });
  });
  
  describe('calculateScheduleTime', () => {
    test('schedules before end time', () => {
      const endTime = new Date(Date.now() + 60000);
      const scheduleTime = calculateScheduleTime(endTime, 10000);
      expect(endTime.getTime() - scheduleTime.getTime()).toBe(10000);
    });
  });
  
  describe('isWithinExpirationTolerance', () => {
    test('returns true when within tolerance', () => {
      const scheduledEnd = new Date(Date.now() - 10000); // 10 sec ago
      expect(isWithinExpirationTolerance(scheduledEnd)).toBe(true);
    });
  
    test('returns false when too early', () => {
      const scheduledEnd = new Date(Date.now() + 60000); // 60 sec in future
      expect(isWithinExpirationTolerance(scheduledEnd)).toBe(false);
    });
  });
  
  // ============================================================================
  // TASK NAME TESTS
  // ============================================================================
  describe('generateTaskName', () => {
    test('generates task name format', () => {
      const taskName = generateTaskName('products', 'item123', 1234567890);
      expect(taskName).toMatch(/^expire-boost-products-item123-1234567890-[a-z0-9]+$/);
    });
  });
  
  describe('parseTaskName', () => {
    test('parses valid task name', () => {
      const parsed = parseTaskName('expire-boost-products-item123-1234567890-abc123');
      expect(parsed.collection).toBe('products');
      expect(parsed.itemId).toBe('item123');
    });
  
    test('returns null for invalid', () => {
      expect(parseTaskName('invalid-task')).toBe(null);
    });
  });
  
  // ============================================================================
  // BOOST UPDATE DATA TESTS
  // ============================================================================
  describe('buildBoostUpdateData', () => {
    test('builds update data correctly', () => {
      const productData = {
        boostedImpressionCount: 100,
        clickCount: 50,
        rankingScore: 500,
      };
      const result = buildBoostUpdateData(
        productData, 30, new Date(), new Date(), 'task123', true
      );
  
      expect(result.isBoosted).toBe(true);
      expect(result.boostDuration).toBe(30);
      expect(result.boostImpressionCountAtStart).toBe(100);
      expect(result.boostClickCountAtStart).toBe(50);
      expect(result.boostScreen).toBe('shop_product');
      expect(result.promotionScore).toBe(1500);
      expect(result.boostExpirationTaskName).toBe('task123');
    });
  
    test('handles unverified user', () => {
      const result = buildBoostUpdateData({}, 30, new Date(), new Date(), 'task123', false);
      expect(result.boostScreen).toBe('product');
      expect(result.screenType).toBe('product');
    });
  });
  
  describe('buildBoostExpirationData', () => {
    test('builds expiration data', () => {
      const productData = { promotionScore: 1500 };
      const result = buildBoostExpirationData(productData);
      expect(result.isBoosted).toBe(false);
      expect(result.promotionScore).toBe(500);
    });
  
    test('does not go below 0', () => {
      const productData = { promotionScore: 500 };
      const result = buildBoostExpirationData(productData);
      expect(result.promotionScore).toBe(0);
    });
  });
  
  // ============================================================================
  // BOOST HISTORY TESTS
  // ============================================================================
  describe('buildBoostHistoryData', () => {
    test('builds history data', () => {
      const productData = {
        productName: 'Test Product',
        boostedImpressionCount: 100,
        clickCount: 50,
      };
      const result = buildBoostHistoryData(
        'user1', 'item1', 'products', productData, 30, new Date(), new Date()
      );
  
      expect(result.userId).toBe('user1');
      expect(result.itemId).toBe('item1');
      expect(result.itemType).toBe('product');
      expect(result.itemName).toBe('Test Product');
      expect(result.boostPrice).toBe(30);
    });
  
    test('handles shop_products', () => {
      const result = buildBoostHistoryData(
        'user1', 'item1', 'shop_products', {}, 30, new Date(), new Date()
      );
      expect(result.itemType).toBe('shop_product');
    });
  });
  
  describe('getHistoryCollectionPath', () => {
    test('returns shop path for shop_products', () => {
      expect(getHistoryCollectionPath('shop_products', 'shop123')).toBe('shops/shop123/boostHistory');
    });
  
    test('returns user path for products', () => {
      expect(getHistoryCollectionPath('products', 'user123')).toBe('users/user123/boostHistory');
    });
  });
  
  // ============================================================================
  // METRICS TESTS
  // ============================================================================
  describe('calculateImpressionsDuringBoost', () => {
    test('calculates impressions gained', () => {
      const productData = {
        boostedImpressionCount: 150,
        boostImpressionCountAtStart: 100,
      };
      expect(calculateImpressionsDuringBoost(productData)).toBe(50);
    });
  
    test('returns 0 for negative', () => {
      const productData = {
        boostedImpressionCount: 50,
        boostImpressionCountAtStart: 100,
      };
      expect(calculateImpressionsDuringBoost(productData)).toBe(0);
    });
  });
  
  describe('calculateClicksDuringBoost', () => {
    test('calculates clicks gained', () => {
      const productData = {
        clickCount: 75,
        boostClickCountAtStart: 50,
      };
      expect(calculateClicksDuringBoost(productData)).toBe(25);
    });
  });
  
  // ============================================================================
  // NOTIFICATION TESTS
  // ============================================================================
  describe('buildBoostExpiredNotification', () => {
    test('builds notification', () => {
      const notification = buildBoostExpiredNotification(
        'user1', 'Product Name', 'item1', 'products'
      );
      expect(notification.userId).toBe('user1');
      expect(notification.type).toBe('boost_expired');
      expect(notification.message_en).toContain('Product Name');
      expect(notification.message_tr).toContain('Product Name');
      expect(notification.itemType).toBe('product');
    });
  
    test('includes shopId for shop_products', () => {
      const notification = buildBoostExpiredNotification(
        'user1', 'Product', 'item1', 'shop_products', 'shop123'
      );
      expect(notification.shopId).toBe('shop123');
      expect(notification.itemType).toBe('shop_product');
    });
  });
  
  // ============================================================================
  // RESULT BUILDING TESTS
  // ============================================================================
  describe('buildBoostResult', () => {
    test('builds complete result', () => {
      const validatedItems = [
        { itemId: 'i1', collection: 'products' },
        { itemId: 'i2', collection: 'shop_products', shopId: 'shop1' },
      ];
      const failedItems = [{ itemId: 'i3', error: 'Failed' }];
      const items = [...validatedItems, ...failedItems];
  
      const result = buildBoostResult(validatedItems, failedItems, items, 30, new Date());
  
      expect(result.boostedItemsCount).toBe(2);
      expect(result.totalRequestedItems).toBe(3);
      expect(result.failedItemsCount).toBe(1);
      expect(result.boostDuration).toBe(30);
      expect(result.totalPrice).toBe(60);
      expect(result.pricePerItem).toBe(30);
      expect(result.boostedItems.length).toBe(2);
      expect(result.failedItems.length).toBe(1);
    });
  
    test('excludes failedItems when empty', () => {
      const result = buildBoostResult([{ itemId: 'i1' }], [], [{}], 30, new Date());
      expect(result.failedItems).toBeUndefined();
    });
  });
  
  // ============================================================================
  // RECEIPT TESTS
  // ============================================================================
  describe('groupItemsByOwner', () => {
    test('groups by shopId', () => {
      const items = [
        { itemId: 'i1', shopId: 'shop1' },
        { itemId: 'i2', shopId: 'shop1' },
        { itemId: 'i3', shopId: 'shop2' },
        { itemId: 'i4' }, // No shopId
      ];
      const groups = groupItemsByOwner(items, 'defaultUser');
  
      expect(Object.keys(groups).length).toBe(3);
      expect(groups.shop1.items.length).toBe(2);
      expect(groups.shop1.ownerType).toBe('shop');
      expect(groups.shop2.items.length).toBe(1);
      expect(groups.defaultUser.items.length).toBe(1);
      expect(groups.defaultUser.ownerType).toBe('user');
    });
  });
  
  // ============================================================================
  // CUSTOMER NAME TESTS
  // ============================================================================
  describe('sanitizeCustomerName', () => {
    test('returns Customer for null', () => {
      expect(sanitizeCustomerName(null)).toBe('Customer');
    });
  
    test('transliterates Turkish characters', () => {
      expect(sanitizeCustomerName('Çağrı')).toBe('Cagri');
      expect(sanitizeCustomerName('Şükrü')).toBe('Sukru');
      expect(sanitizeCustomerName('Öğretmen')).toBe('Ogretmen');
    });
  
    test('removes special characters', () => {
      expect(sanitizeCustomerName('John@Doe!')).toBe('JohnDoe');
    });
  
    test('truncates to 50 chars', () => {
      const longName = 'A'.repeat(60);
      expect(sanitizeCustomerName(longName).length).toBe(50);
    });
  });
  
  // ============================================================================
  // STALE TASK TESTS
  // ============================================================================
  describe('isStaleTask', () => {
    test('returns true for different task name', () => {
      expect(isStaleTask({ boostExpirationTaskName: 'task1' }, 'task2')).toBe(true);
    });
  
    test('returns false for same task name', () => {
      expect(isStaleTask({ boostExpirationTaskName: 'task1' }, 'task1')).toBe(false);
    });
  
    test('returns false for no stored task', () => {
      expect(isStaleTask({}, 'task1')).toBe(false);
    });
  });
  
  describe('shouldSkipExpiration', () => {
    const now = Date.now();
  
    test('skips stale task', () => {
      const result = shouldSkipExpiration(
        { boostExpirationTaskName: 'task1', isBoosted: true },
        'task2',
        new Date(now - 10000),
        now
      );
      expect(result.skip).toBe(true);
      expect(result.reason).toBe('stale_task');
    });
  
    test('skips not boosted', () => {
      const result = shouldSkipExpiration(
        { isBoosted: false },
        'task1',
        new Date(now - 10000),
        now
      );
      expect(result.skip).toBe(true);
      expect(result.reason).toBe('not_boosted');
    });
  
    test('skips too early', () => {
      const result = shouldSkipExpiration(
        { isBoosted: true },
        'task1',
        new Date(now + 60000), // 60 sec in future
        now
      );
      expect(result.skip).toBe(true);
      expect(result.reason).toBe('too_early');
    });
  
    test('does not skip valid expiration', () => {
      const result = shouldSkipExpiration(
        { isBoosted: true, boostEndTime: { toDate: () => new Date(now - 5000) } },
        'task1',
        new Date(now - 10000),
        now
      );
      expect(result.skip).toBe(false);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete boost payment flow', () => {
      const input = {
        items: [
          { itemId: 'product1', collection: 'products' },
          { itemId: 'product2', collection: 'shop_products', shopId: 'shop1' },
        ],
        boostDuration: 60,
      };
  
      // Validate input
      const validation = validatePaymentInitInput(input);
      expect(validation.isValid).toBe(true);
  
      // Calculate price
      const totalPrice = calculateBoostPrice(input.items.length, input.boostDuration);
      expect(totalPrice).toBe(120); // 2 * 60 * 1.0
  
      // Generate order number
      const orderNumber = generateOrderNumber('user12345678');
      expect(orderNumber).toMatch(/^BOOST-\d+-user1234$/);
  
      // Sanitize customer name
      const customerName = sanitizeCustomerName('Müşteri Adı');
      expect(customerName).toBe('Musteri Adi');
    });
  
    test('boost expiration flow', () => {
      const now = Date.now();
      const productData = {
        isBoosted: true,
        boostEndTime: { toDate: () => new Date(now - 5000) },
        boostExpirationTaskName: 'task123',
        boostedImpressionCount: 150,
        boostImpressionCountAtStart: 100,
        clickCount: 75,
        boostClickCountAtStart: 50,
        promotionScore: 1500,
      };
  
      // Check if should expire
      const skipResult = shouldSkipExpiration(
        productData,
        'task123',
        new Date(now - 10000),
        now
      );
      expect(skipResult.skip).toBe(false);
  
      // Calculate metrics
      expect(calculateImpressionsDuringBoost(productData)).toBe(50);
      expect(calculateClicksDuringBoost(productData)).toBe(25);
  
      // Build expiration data
      const expirationData = buildBoostExpirationData(productData);
      expect(expirationData.isBoosted).toBe(false);
      expect(expirationData.promotionScore).toBe(500);
    });
  
    test('permission check flow for shop product', () => {
      const shopData = {
        ownerId: 'owner1',
        coOwners: ['coowner1'],
        editors: ['editor1'],
        viewers: ['viewer1'],
      };
  
      // Owner can access
      expect(checkShopMembership(shopData, 'owner1')).toBe(true);
      // Editor can access
      expect(checkShopMembership(shopData, 'editor1')).toBe(true);
      // Random user cannot
      expect(checkShopMembership(shopData, 'random')).toBe(false);
  
      // Get all members for notifications
      const members = getShopMembers(shopData);
      expect(members.size).toBe(4);
    });
  });
