// functions/test/algolia-sync/algolia-sync-utils.test.js
//
// Unit tests for Algolia sync utility functions
// Tests the EXACT logic from Algolia sync cloud functions
//
// Run: npx jest test/algolia-sync/algolia-sync-utils.test.js

const {
    // Constants
    SUPPORTED_LOCALES,
    SYNC_ACTIONS,
    PRODUCT_SEARCH_FIELDS,
    SHOP_PRODUCT_SEARCH_FIELDS,
    SHOP_RELEVANT_FIELDS,
 
  
    // Object ID
    generateObjectID,
    parseObjectID,
  
    // Sync action
    detectSyncAction,
  
    // Relevant changes
    hasRelevantChanges,
    shouldSyncProduct,
    shouldSyncShopProduct,
    shouldSyncShop,
    shouldSyncOrder,
  
    // Localized fields
    buildLocalizedFieldName,
    buildLocalizedField,
    buildLocalizedArrayField,
    buildProductLocalizedFields,
    buildShopLocalizedFields,
    buildOrderLocalizedFields,
  
    // Searchable text
    buildSearchableText,
    buildShopSearchableText,
    buildOrderSearchableText,
  
    // Minimal/augmented data
    buildMinimalShopData,
    buildShopAlgoliaDocument,
    calculateItemTotal,
    getTimestampForSorting,
    buildAugmentedOrderItem,
    buildAugmentedProduct,
  
    // Document building
    buildAlgoliaDocument,
  } = require('./algolia-sync-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('SUPPORTED_LOCALES contains expected locales', () => {
      expect(SUPPORTED_LOCALES).toContain('en');
      expect(SUPPORTED_LOCALES).toContain('tr');
      expect(SUPPORTED_LOCALES).toContain('ru');
      expect(SUPPORTED_LOCALES.length).toBe(3);
    });
  
    test('SYNC_ACTIONS has all action types', () => {
      expect(SYNC_ACTIONS.CREATE).toBe('create');
      expect(SYNC_ACTIONS.UPDATE).toBe('update');
      expect(SYNC_ACTIONS.DELETE).toBe('delete');
      expect(SYNC_ACTIONS.NONE).toBe('none');
    });
  
    test('PRODUCT_SEARCH_FIELDS contains expected fields', () => {
      expect(PRODUCT_SEARCH_FIELDS).toContain('productName');
      expect(PRODUCT_SEARCH_FIELDS).toContain('category');
      expect(PRODUCT_SEARCH_FIELDS).toContain('price');
      expect(PRODUCT_SEARCH_FIELDS).toContain('averageRating');
    });
  
    test('SHOP_PRODUCT_SEARCH_FIELDS extends product fields', () => {
      expect(SHOP_PRODUCT_SEARCH_FIELDS).toContain('productName');
      expect(SHOP_PRODUCT_SEARCH_FIELDS).toContain('discountPercentage');
      expect(SHOP_PRODUCT_SEARCH_FIELDS).toContain('campaignName');
      expect(SHOP_PRODUCT_SEARCH_FIELDS).toContain('isBoosted');
    });
  
    test('SHOP_RELEVANT_FIELDS contains expected fields', () => {
      expect(SHOP_RELEVANT_FIELDS).toContain('name');
      expect(SHOP_RELEVANT_FIELDS).toContain('profileImageUrl');
      expect(SHOP_RELEVANT_FIELDS).toContain('isActive');
    });
  });
  
  // ============================================================================
  // OBJECT ID TESTS
  // ============================================================================
  describe('generateObjectID', () => {
    test('generates correct format', () => {
      expect(generateObjectID('products', 'abc123')).toBe('products_abc123');
    });
  
    test('handles shop_products collection', () => {
      expect(generateObjectID('shop_products', 'xyz789')).toBe('shop_products_xyz789');
    });
  
    test('handles special characters in document ID', () => {
      expect(generateObjectID('products', 'id_with_underscore')).toBe('products_id_with_underscore');
    });
  });
  
  describe('parseObjectID', () => {
    test('parses valid objectID', () => {
      const result = parseObjectID('products_abc123');
      expect(result).toEqual({
        collectionName: 'products',
        documentId: 'abc123',
      });
    });
  
    test('parses objectID with underscore in document ID', () => {
      const result = parseObjectID('products_id_with_underscore');
      expect(result).toEqual({
        collectionName: 'products',
        documentId: 'id_with_underscore',
      });
    });
  
    test('returns null for invalid format', () => {
      expect(parseObjectID('nounderscore')).toBe(null);
    });
  
    test('returns null for null input', () => {
      expect(parseObjectID(null)).toBe(null);
    });
  
    test('returns null for non-string input', () => {
      expect(parseObjectID(12345)).toBe(null);
    });
  });
  
  // ============================================================================
  // SYNC ACTION DETECTION TESTS
  // ============================================================================
  describe('detectSyncAction', () => {
    test('returns CREATE when no before data', () => {
      expect(detectSyncAction(null, { name: 'new' })).toBe(SYNC_ACTIONS.CREATE);
    });
  
    test('returns UPDATE when both before and after data exist', () => {
      expect(detectSyncAction({ name: 'old' }, { name: 'new' })).toBe(SYNC_ACTIONS.UPDATE);
    });
  
    test('returns DELETE when no after data', () => {
      expect(detectSyncAction({ name: 'old' }, null)).toBe(SYNC_ACTIONS.DELETE);
    });
  
    test('returns NONE when both are null', () => {
      expect(detectSyncAction(null, null)).toBe(SYNC_ACTIONS.NONE);
    });
  
    test('handles undefined as no data', () => {
      expect(detectSyncAction(undefined, { name: 'new' })).toBe(SYNC_ACTIONS.CREATE);
      expect(detectSyncAction({ name: 'old' }, undefined)).toBe(SYNC_ACTIONS.DELETE);
    });
  });
  
  // ============================================================================
  // RELEVANT CHANGES DETECTION TESTS
  // ============================================================================
  describe('hasRelevantChanges', () => {
    const fields = ['name', 'price', 'category'];
  
    test('returns true when field changed', () => {
      const before = { name: 'Old', price: 100 };
      const after = { name: 'New', price: 100 };
      expect(hasRelevantChanges(before, after, fields)).toBe(true);
    });
  
    test('returns false when no relevant fields changed', () => {
      const before = { name: 'Same', price: 100, description: 'old' };
      const after = { name: 'Same', price: 100, description: 'new' };
      expect(hasRelevantChanges(before, after, fields)).toBe(false);
    });
  
    test('returns true when price changed', () => {
      const before = { name: 'Same', price: 100 };
      const after = { name: 'Same', price: 200 };
      expect(hasRelevantChanges(before, after, fields)).toBe(true);
    });
  
    test('returns true for null before data', () => {
      expect(hasRelevantChanges(null, { name: 'new' }, fields)).toBe(true);
    });
  
    test('returns true for null after data', () => {
      expect(hasRelevantChanges({ name: 'old' }, null, fields)).toBe(true);
    });
  
    test('returns true for invalid fields array', () => {
      expect(hasRelevantChanges({}, {}, null)).toBe(true);
    });
  
    test('detects change from undefined to value', () => {
      const before = { name: 'Same' };
      const after = { name: 'Same', category: 'Electronics' };
      expect(hasRelevantChanges(before, after, fields)).toBe(true);
    });
  });
  
  describe('shouldSyncProduct', () => {
    test('returns true for create (no before)', () => {
      expect(shouldSyncProduct(null, { productName: 'New' })).toBe(true);
    });
  
    test('returns true for delete (no after)', () => {
      expect(shouldSyncProduct({ productName: 'Old' }, null)).toBe(true);
    });
  
    test('returns true when productName changed', () => {
      expect(shouldSyncProduct(
        { productName: 'Old Name' },
        { productName: 'New Name' }
      )).toBe(true);
    });
  
    test('returns true when price changed', () => {
      expect(shouldSyncProduct(
        { productName: 'Same', price: 100 },
        { productName: 'Same', price: 200 }
      )).toBe(true);
    });
  
    test('returns false when only irrelevant field changed', () => {
      expect(shouldSyncProduct(
        { productName: 'Same', price: 100, quantity: 10 },
        { productName: 'Same', price: 100, quantity: 5 }
      )).toBe(false);
    });
  });
  
  describe('shouldSyncShopProduct', () => {
    test('returns true when discountPercentage changed', () => {
      expect(shouldSyncShopProduct(
        { productName: 'Same', discountPercentage: 0 },
        { productName: 'Same', discountPercentage: 20 }
      )).toBe(true);
    });
  
    test('returns true when isBoosted changed', () => {
      expect(shouldSyncShopProduct(
        { productName: 'Same', isBoosted: false },
        { productName: 'Same', isBoosted: true }
      )).toBe(true);
    });
  
    test('returns true when campaignName changed', () => {
      expect(shouldSyncShopProduct(
        { productName: 'Same', campaignName: null },
        { productName: 'Same', campaignName: 'Summer Sale' }
      )).toBe(true);
    });
  });
  
  describe('shouldSyncShop', () => {
    test('returns true when name changed', () => {
      expect(shouldSyncShop(
        { name: 'Old Shop' },
        { name: 'New Shop' }
      )).toBe(true);
    });
  
    test('returns true when profileImageUrl changed', () => {
      expect(shouldSyncShop(
        { name: 'Shop', profileImageUrl: 'old.jpg' },
        { name: 'Shop', profileImageUrl: 'new.jpg' }
      )).toBe(true);
    });
  
    test('returns true when isActive changed', () => {
      expect(shouldSyncShop(
        { name: 'Shop', isActive: true },
        { name: 'Shop', isActive: false }
      )).toBe(true);
    });
  
    test('returns false when only irrelevant field changed', () => {
      expect(shouldSyncShop(
        { name: 'Shop', description: 'old' },
        { name: 'Shop', description: 'new' }
      )).toBe(false);
    });
  });
  
  describe('shouldSyncOrder', () => {
    test('returns true when shipmentStatus changed', () => {
      expect(shouldSyncOrder(
        { productName: 'Item', shipmentStatus: 'pending' },
        { productName: 'Item', shipmentStatus: 'shipped' }
      )).toBe(true);
    });
  
    test('returns true when needsAnyReview changed', () => {
      expect(shouldSyncOrder(
        { productName: 'Item', needsAnyReview: true },
        { productName: 'Item', needsAnyReview: false }
      )).toBe(true);
    });
  });
  
  // ============================================================================
  // LOCALIZED FIELDS TESTS
  // ============================================================================
  describe('buildLocalizedFieldName', () => {
    test('builds correct field name', () => {
      expect(buildLocalizedFieldName('category', 'en')).toBe('category_en');
      expect(buildLocalizedFieldName('category', 'tr')).toBe('category_tr');
    });
  });
  
  describe('buildLocalizedField', () => {
    const mockLocalize = (type, value, locale) => `${value}_${locale}`;
  
    test('builds localized fields for all locales', () => {
      const result = buildLocalizedField('category', 'category', 'Electronics', ['en', 'tr'], mockLocalize);
      expect(result).toEqual({
        category_en: 'Electronics_en',
        category_tr: 'Electronics_tr',
      });
    });
  
    test('returns empty object for null value', () => {
      const result = buildLocalizedField('category', 'category', null, ['en', 'tr'], mockLocalize);
      expect(result).toEqual({});
    });
  
    test('falls back to original value on localization error', () => {
      const errorLocalize = () => {
        throw new Error('Localization failed');
    };
      const result = buildLocalizedField('category', 'category', 'Electronics', ['en'], errorLocalize);
      expect(result).toEqual({ category_en: 'Electronics' });
    });
  });
  
  describe('buildLocalizedArrayField', () => {
    const mockLocalize = (type, value, locale) => `${value}_${locale}`;
  
    test('builds localized array fields', () => {
      const result = buildLocalizedArrayField('category', 'categories', ['A', 'B'], ['en', 'tr'], mockLocalize);
      expect(result).toEqual({
        categories_en: ['A_en', 'B_en'],
        categories_tr: ['A_tr', 'B_tr'],
      });
    });
  
    test('returns empty object for non-array', () => {
      const result = buildLocalizedArrayField('category', 'categories', 'not array', ['en'], mockLocalize);
      expect(result).toEqual({});
    });
  
    test('returns empty object for empty array', () => {
      const result = buildLocalizedArrayField('category', 'categories', [], ['en'], mockLocalize);
      expect(result).toEqual({});
    });
  });
  
  describe('buildProductLocalizedFields', () => {
    const mockLocalize = (type, value, locale) => `${value}_${locale}`;
  
    test('builds all product localized fields', () => {
      const product = {
        category: 'Electronics',
        subcategory: 'Phones',
        subsubcategory: 'Smartphones',
        jewelryType: 'Ring',
        jewelryMaterials: ['Gold', 'Silver'],
      };
  
      const result = buildProductLocalizedFields(product, ['en'], mockLocalize);
  
      expect(result.category_en).toBe('Electronics_en');
      expect(result.subcategory_en).toBe('Phones_en');
      expect(result.subsubcategory_en).toBe('Smartphones_en');
      expect(result.jewelryType_en).toBe('Ring_en');
      expect(result.jewelryMaterials_en).toEqual(['Gold_en', 'Silver_en']);
    });
  
    test('skips missing fields', () => {
      const product = { category: 'Electronics' };
      const result = buildProductLocalizedFields(product, ['en'], mockLocalize);
  
      expect(result.category_en).toBe('Electronics_en');
      expect(result.subcategory_en).toBeUndefined();
    });
  });
  
  describe('buildShopLocalizedFields', () => {
    const mockLocalize = (type, value, locale) => `${value}_${locale}`;
  
    test('builds localized categories', () => {
      const shop = { categories: ['Fashion', 'Electronics'] };
      const result = buildShopLocalizedFields(shop, ['en', 'tr'], mockLocalize);
  
      expect(result.categories_en).toEqual(['Fashion_en', 'Electronics_en']);
      expect(result.categories_tr).toEqual(['Fashion_tr', 'Electronics_tr']);
    });
  
    test('returns empty for missing categories', () => {
      const result = buildShopLocalizedFields({}, ['en'], mockLocalize);
      expect(result).toEqual({});
    });
  });
  
  describe('buildOrderLocalizedFields', () => {
    const mockLocalize = (type, value, locale) => `${value}_${locale}`;
  
    test('builds all order localized fields', () => {
      const order = {
        category: 'Electronics',
        subcategory: 'Phones',
        condition: 'New',
        shipmentStatus: 'Shipped',
      };
  
      const result = buildOrderLocalizedFields(order, ['en'], mockLocalize);
  
      expect(result.category_en).toBe('Electronics_en');
      expect(result.condition_en).toBe('New_en');
      expect(result.shipmentStatus_en).toBe('Shipped_en');
    });
  });
  
  // ============================================================================
  // SEARCHABLE TEXT TESTS
  // ============================================================================
  describe('buildSearchableText', () => {
    test('joins non-empty fields with space', () => {
      expect(buildSearchableText(['Hello', 'World'])).toBe('Hello World');
    });
  
    test('filters out null and undefined', () => {
      expect(buildSearchableText(['Hello', null, 'World', undefined])).toBe('Hello World');
    });
  
    test('filters out empty strings', () => {
      expect(buildSearchableText(['Hello', '', 'World'])).toBe('Hello World');
    });
  
    test('returns empty string for empty array', () => {
      expect(buildSearchableText([])).toBe('');
    });
  });
  
  describe('buildShopSearchableText', () => {
    test('includes name and categories', () => {
      const shop = { name: 'My Shop', categories: ['Fashion', 'Electronics'] };
      const result = buildShopSearchableText(shop);
      expect(result).toBe('My Shop Fashion Electronics');
    });
  
    test('handles missing categories', () => {
      const shop = { name: 'My Shop' };
      const result = buildShopSearchableText(shop);
      expect(result).toBe('My Shop');
    });
  });
  
  describe('buildOrderSearchableText', () => {
    test('includes all order fields', () => {
      const order = {
        productName: 'iPhone',
        buyerName: 'John',
        sellerName: 'Jane',
        brandModel: 'Apple',
        category: 'Electronics',
      };
      const result = buildOrderSearchableText(order);
      expect(result).toContain('iPhone');
      expect(result).toContain('John');
      expect(result).toContain('Jane');
      expect(result).toContain('Apple');
    });
  });
  
  // ============================================================================
  // MINIMAL DATA TESTS
  // ============================================================================
  describe('buildMinimalShopData', () => {
    test('extracts required fields', () => {
      const shop = {
        name: 'Test Shop',
        profileImageUrl: 'image.jpg',
        categories: ['Fashion'],
        isActive: true,
        extraField: 'ignored',
      };
  
      const result = buildMinimalShopData(shop);
  
      expect(result).toEqual({
        name: 'Test Shop',
        profileImageUrl: 'image.jpg',
        categories: ['Fashion'],
        isActive: true,
      });
      expect(result.extraField).toBeUndefined();
    });
  
    test('defaults isActive to true', () => {
      const shop = { name: 'Shop' };
      const result = buildMinimalShopData(shop);
      expect(result.isActive).toBe(true);
    });
  
    test('defaults profileImageUrl to null', () => {
      const shop = { name: 'Shop' };
      const result = buildMinimalShopData(shop);
      expect(result.profileImageUrl).toBe(null);
    });
  
    test('defaults categories to empty array', () => {
      const shop = { name: 'Shop' };
      const result = buildMinimalShopData(shop);
      expect(result.categories).toEqual([]);
    });
  
    test('returns null for null input', () => {
      expect(buildMinimalShopData(null)).toBe(null);
    });
  });
  
  describe('buildShopAlgoliaDocument', () => {
    test('builds complete shop document', () => {
      const shop = {
        name: 'Test Shop',
        categories: ['Fashion'],
      };
  
      const result = buildShopAlgoliaDocument(shop, ['en'], (t, v) => v);
  
      expect(result.name).toBe('Test Shop');
      expect(result.categories_en).toEqual(['Fashion']);
      expect(result.searchableText).toBe('Test Shop Fashion');
    });
  
    test('returns null for null shop', () => {
      expect(buildShopAlgoliaDocument(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // ITEM TOTAL AND TIMESTAMP TESTS
  // ============================================================================
  describe('calculateItemTotal', () => {
    test('calculates price * quantity', () => {
      expect(calculateItemTotal(100, 2)).toBe(200);
    });
  
    test('defaults quantity to 1', () => {
      expect(calculateItemTotal(100, null)).toBe(100);
      expect(calculateItemTotal(100, undefined)).toBe(100);
    });
  
    test('defaults price to 0', () => {
      expect(calculateItemTotal(null, 5)).toBe(0);
      expect(calculateItemTotal(undefined, 5)).toBe(0);
    });
  
    test('handles zero values', () => {
        expect(calculateItemTotal(0, 5)).toBe(0);        // 0 * 5 = 0
        expect(calculateItemTotal(100, 0)).toBe(100);   // 100 * 1 (0 defaults to 1)
      });
  });
  
  describe('getTimestampForSorting', () => {
    test('extracts seconds from Firestore timestamp', () => {
      const timestamp = { seconds: 1234567890, nanoseconds: 0 };
      expect(getTimestampForSorting(timestamp)).toBe(1234567890);
    });
  
    test('returns current time for null', () => {
      const before = Math.floor(Date.now() / 1000);
      const result = getTimestampForSorting(null);
      const after = Math.floor(Date.now() / 1000);
  
      expect(result).toBeGreaterThanOrEqual(before);
      expect(result).toBeLessThanOrEqual(after);
    });
  
    test('returns current time for invalid timestamp', () => {
      const result = getTimestampForSorting({});
      expect(typeof result).toBe('number');
    });
  });
  
  // ============================================================================
  // AUGMENTED ORDER ITEM TESTS
  // ============================================================================
  describe('buildAugmentedOrderItem', () => {
    test('includes all order context fields', () => {
      const item = {
        productName: 'iPhone',
        price: 1000,
        quantity: 2,
        category: 'Electronics',
      };
  
      const order = {
        totalPrice: 2000,
        totalQuantity: 2,
        paymentMethod: 'card',
        address: { city: 'Istanbul' },
      };
  
      const result = buildAugmentedOrderItem(item, order, ['en'], (t, v) => v);
  
      expect(result.productName).toBe('iPhone');
      expect(result.orderTotalPrice).toBe(2000);
      expect(result.orderTotalQuantity).toBe(2);
      expect(result.orderPaymentMethod).toBe('card');
      expect(result.orderAddress).toEqual({ city: 'Istanbul' });
      expect(result.itemTotal).toBe(2000);
      expect(result.searchableText).toContain('iPhone');
      expect(result.category_en).toBe('Electronics');
    });
  
    test('handles missing order data', () => {
      const item = { productName: 'Test', price: 100 };
      const result = buildAugmentedOrderItem(item, {}, ['en'], (t, v) => v);
  
      expect(result.orderTotalPrice).toBe(0);
      expect(result.orderPaymentMethod).toBe('');
    });
  });
  
  // ============================================================================
  // AUGMENTED PRODUCT TESTS
  // ============================================================================
  describe('buildAugmentedProduct', () => {
    test('includes original data and localized fields', () => {
      const product = {
        productName: 'Test Product',
        category: 'Electronics',
        price: 100,
      };
  
      const result = buildAugmentedProduct(product, ['en'], (t, v) => `${v}_localized`);
  
      expect(result.productName).toBe('Test Product');
      expect(result.price).toBe(100);
      expect(result.category_en).toBe('Electronics_localized');
    });
  });
  
  // ============================================================================
  // ALGOLIA DOCUMENT BUILDING TESTS
  // ============================================================================
  describe('buildAlgoliaDocument', () => {
    test('adds objectID and collection', () => {
      const result = buildAlgoliaDocument('products', 'abc123', { name: 'Test' });
  
      expect(result.objectID).toBe('products_abc123');
      expect(result.collection).toBe('products');
      expect(result.name).toBe('Test');
    });
  
    test('preserves all original data', () => {
      const data = { a: 1, b: 2, c: 3 };
      const result = buildAlgoliaDocument('products', 'id', data);
  
      expect(result.a).toBe(1);
      expect(result.b).toBe(2);
      expect(result.c).toBe(3);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('product create flow', () => {
      const productData = {
        productName: 'iPhone 15',
        category: 'Electronics',
        subcategory: 'Phones',
        price: 1000,
        description: 'Latest iPhone',
      };
  
      // 1. Detect action
      const action = detectSyncAction(null, productData);
      expect(action).toBe(SYNC_ACTIONS.CREATE);
  
      // 2. Build localized fields
      const localized = buildProductLocalizedFields(productData, ['en', 'tr'], (t, v) => v);
      expect(localized.category_en).toBe('Electronics');
      expect(localized.category_tr).toBe('Electronics');
  
      // 3. Build document
      const doc = buildAlgoliaDocument('products', 'prod123', { ...productData, ...localized });
      expect(doc.objectID).toBe('products_prod123');
      expect(doc.collection).toBe('products');
    });
  
    test('product update with no relevant changes skips sync', () => {
      const before = { productName: 'iPhone', price: 1000, quantity: 10 };
      const after = { productName: 'iPhone', price: 1000, quantity: 5 }; // Only quantity changed
  
      const shouldSync = shouldSyncProduct(before, after);
      expect(shouldSync).toBe(false);
    });
  
    test('shop sync with minimal data', () => {
      const shopData = {
        name: 'Fashion Store',
        profileImageUrl: 'logo.jpg',
        categories: ['Fashion', 'Accessories'],
        isActive: true,
        ownerId: 'user123',
        createdAt: new Date(),
        products: [],
      };
  
      // 1. Build minimal data
      const minimal = buildMinimalShopData(shopData);
      expect(minimal.ownerId).toBeUndefined();
      expect(minimal.createdAt).toBeUndefined();
  
      // 2. Build complete document
      const doc = buildShopAlgoliaDocument(shopData, ['en'], (t, v) => v);
      expect(doc.searchableText).toBe('Fashion Store Fashion Accessories');
    });
  
    test('order item with full context', () => {
      const orderItem = {
        productName: 'T-Shirt',
        price: 50,
        quantity: 3,
        category: 'Fashion',
        subcategory: 'Clothing',
        buyerName: 'John Doe',
        sellerName: 'Fashion Shop',
        shipmentStatus: 'shipped',
        timestamp: { seconds: 1700000000 },
      };
  
      const orderContext = {
        totalPrice: 150,
        totalQuantity: 3,
        paymentMethod: 'credit_card',
      };
  
      const augmented = buildAugmentedOrderItem(orderItem, orderContext, ['en', 'tr'], (t, v) => v);
  
      expect(augmented.itemTotal).toBe(150);
      expect(augmented.orderTotalPrice).toBe(150);
      expect(augmented.timestampForSorting).toBe(1700000000);
      expect(augmented.searchableText).toContain('T-Shirt');
      expect(augmented.searchableText).toContain('John Doe');
    });
  
    test('delete flow', () => {
      const beforeData = { productName: 'Old Product' };
  
      // 1. Detect delete
      const action = detectSyncAction(beforeData, null);
      expect(action).toBe(SYNC_ACTIONS.DELETE);
  
      // 2. Generate objectID for deletion
      const objectID = generateObjectID('products', 'prod123');
      expect(objectID).toBe('products_prod123');
    });
  });
