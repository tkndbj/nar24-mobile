// functions/test/generate-receipt/receipt-utils.test.js
//
// Unit tests for receipt generation utility functions
// Tests the EXACT logic from receipt generation cloud functions
//
// Run: npx jest test/generate-receipt/receipt-utils.test.js

const {
    // Constants
    SUPPORTED_LANGUAGES,
    DEFAULT_LANGUAGE,
    RECEIPT_TYPES,
    OWNER_TYPES,
    DELIVERY_OPTIONS,
    RECEIPT_LABELS,
 
    MAX_RETRY_COUNT,
  
    // Language utilities
    getSupportedLanguages,
    isValidLanguage,
    getEffectiveLanguage,
  
    // Labels
    getReceiptLabels,
    getLabel,
  
    // Delivery option
    formatDeliveryOption,
  
    // Duration formatting
    formatDuration,
    formatItemCount,
  
    // Price and totals
    calculateTotals,
    formatPrice,
    isDeliveryFree,
    getDeliveryPriceText,
  
    // Date formatting
    getLocaleCode,
    formatReceiptDate,
  
    // File paths
    getReceiptFilePath,
    getReceiptCollectionPath,
  
    // Receipt document
    buildReceiptDocument,
  
    // Buyer info
    getBuyerPhone,
    getBuyerNameLabel,
  
    // Attributes
    isSystemField,
    filterDisplayableAttributes,
    localizeAttributeKey,

    formatAttributes,
  
    // Retry logic
    getTaskStatusAfterError,
    shouldRetryTask,
  
    // Receipt type checks
    isBoostReceipt,
    isOrderReceipt,
    shouldShowDelivery,
  } = require('./receipt-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('SUPPORTED_LANGUAGES contains en, tr, ru', () => {
      expect(SUPPORTED_LANGUAGES).toContain('en');
      expect(SUPPORTED_LANGUAGES).toContain('tr');
      expect(SUPPORTED_LANGUAGES).toContain('ru');
    });
  
    test('DEFAULT_LANGUAGE is en', () => {
      expect(DEFAULT_LANGUAGE).toBe('en');
    });
  
    test('RECEIPT_TYPES has correct values', () => {
      expect(RECEIPT_TYPES.ORDER).toBe('order');
      expect(RECEIPT_TYPES.BOOST).toBe('boost');
    });
  
    test('OWNER_TYPES has correct values', () => {
      expect(OWNER_TYPES.SHOP).toBe('shop');
      expect(OWNER_TYPES.USER).toBe('user');
    });
  
    test('DELIVERY_OPTIONS has correct values', () => {
      expect(DELIVERY_OPTIONS.NORMAL).toBe('normal');
      expect(DELIVERY_OPTIONS.EXPRESS).toBe('express');
      expect(DELIVERY_OPTIONS.PICKUP).toBe('pickup');
    });
  
    test('MAX_RETRY_COUNT is 3', () => {
      expect(MAX_RETRY_COUNT).toBe(3);
    });
  
    test('RECEIPT_LABELS has all languages', () => {
      SUPPORTED_LANGUAGES.forEach((lang) => {
        expect(RECEIPT_LABELS[lang]).toBeDefined();
        expect(RECEIPT_LABELS[lang].title).toBeDefined();
        expect(RECEIPT_LABELS[lang].total).toBeDefined();
      });
    });
  });
  
  // ============================================================================
  // LANGUAGE UTILITIES TESTS
  // ============================================================================
  describe('getSupportedLanguages', () => {
    test('returns supported languages', () => {
      expect(getSupportedLanguages()).toEqual(['en', 'tr', 'ru']);
    });
  });
  
  describe('isValidLanguage', () => {
    test('returns true for supported languages', () => {
      expect(isValidLanguage('en')).toBe(true);
      expect(isValidLanguage('tr')).toBe(true);
      expect(isValidLanguage('ru')).toBe(true);
    });
  
    test('returns false for unsupported languages', () => {
      expect(isValidLanguage('de')).toBe(false);
      expect(isValidLanguage('fr')).toBe(false);
      expect(isValidLanguage('')).toBe(false);
    });
  });
  
  describe('getEffectiveLanguage', () => {
    test('returns language if valid', () => {
      expect(getEffectiveLanguage('tr')).toBe('tr');
    });
  
    test('returns default for invalid language', () => {
      expect(getEffectiveLanguage('de')).toBe('en');
      expect(getEffectiveLanguage(null)).toBe('en');
    });
  });
  
  // ============================================================================
  // LABEL TESTS
  // ============================================================================
  describe('getReceiptLabels', () => {
    test('returns labels for valid language', () => {
      const enLabels = getReceiptLabels('en');
      expect(enLabels.title).toBe('Nar24 Receipt');
  
      const trLabels = getReceiptLabels('tr');
      expect(trLabels.title).toBe('Nar24 Fatura');
  
      const ruLabels = getReceiptLabels('ru');
      expect(ruLabels.title).toBe('Nar24 Счет');
    });
  
    test('returns English for unknown language', () => {
      const labels = getReceiptLabels('unknown');
      expect(labels.title).toBe('Nar24 Receipt');
    });
  });
  
  describe('getLabel', () => {
    test('returns specific label', () => {
      expect(getLabel('en', 'total')).toBe('Total');
      expect(getLabel('tr', 'total')).toBe('Toplam');
      expect(getLabel('ru', 'total')).toBe('Итого');
    });
  
    test('returns key if label not found', () => {
      expect(getLabel('en', 'unknownKey')).toBe('unknownKey');
    });
  });
  
  // ============================================================================
  // DELIVERY OPTION TESTS
  // ============================================================================
  describe('formatDeliveryOption', () => {
    test('formats normal delivery in English', () => {
      expect(formatDeliveryOption('normal', 'en')).toBe('Normal Delivery');
    });
  
    test('formats express delivery in Turkish', () => {
      expect(formatDeliveryOption('express', 'tr')).toBe('Express Teslimat');
    });
  
    test('formats normal delivery in Russian', () => {
      expect(formatDeliveryOption('normal', 'ru')).toBe('Обычная доставка');
    });
  
    test('defaults to English for unknown language', () => {
      expect(formatDeliveryOption('normal', 'unknown')).toBe('Normal Delivery');
    });
  
    test('returns original option for unknown option', () => {
      expect(formatDeliveryOption('unknown_option', 'en')).toBe('Normal Delivery');
    });
  });
  
  // ============================================================================
  // DURATION FORMATTING TESTS
  // ============================================================================
  describe('formatDuration', () => {
    test('formats in English', () => {
      expect(formatDuration(30, 'en')).toBe('30 minutes');
    });
  
    test('formats in Turkish', () => {
      expect(formatDuration(30, 'tr')).toBe('30 dakika');
    });
  
    test('formats in Russian', () => {
      expect(formatDuration(30, 'ru')).toBe('30 минут');
    });
  });
  
  describe('formatItemCount', () => {
    test('formats in English', () => {
      expect(formatItemCount(5, 'en')).toBe('5 items');
    });
  
    test('formats in Turkish', () => {
      expect(formatItemCount(5, 'tr')).toBe('5 ürün');
    });
  
    test('formats in Russian', () => {
      expect(formatItemCount(5, 'ru')).toBe('5 товаров');
    });
  });
  
  // ============================================================================
  // PRICE AND TOTALS TESTS
  // ============================================================================
  describe('calculateTotals', () => {
    test('calculates with explicit subtotal', () => {
      const data = {
        totalPrice: 150,
        itemsSubtotal: 130,
        deliveryPrice: 20,
      };
      const result = calculateTotals(data);
      expect(result.subtotal).toBe(130);
      expect(result.deliveryPrice).toBe(20);
      expect(result.grandTotal).toBe(150);
    });
  
    test('calculates subtotal from total and delivery', () => {
      const data = {
        totalPrice: 150,
        deliveryPrice: 20,
      };
      const result = calculateTotals(data);
      expect(result.subtotal).toBe(130);
      expect(result.grandTotal).toBe(150);
    });
  
    test('handles zero delivery price', () => {
      const data = {
        totalPrice: 100,
        itemsSubtotal: 100,
      };
      const result = calculateTotals(data);
      expect(result.deliveryPrice).toBe(0);
      expect(result.grandTotal).toBe(100);
    });
  });
  
  describe('formatPrice', () => {
    test('formats price with currency', () => {
      expect(formatPrice(100, 'TL')).toBe('100 TL');
      expect(formatPrice(99.5, 'TL')).toBe('100 TL');
    });
  
    test('handles zero', () => {
      expect(formatPrice(0, 'TL')).toBe('0 TL');
    });
  
    test('handles null', () => {
      expect(formatPrice(null, 'TL')).toBe('0 TL');
    });
  });
  
  describe('isDeliveryFree', () => {
    test('returns true for zero', () => {
      expect(isDeliveryFree(0)).toBe(true);
    });
  
    test('returns true for null', () => {
      expect(isDeliveryFree(null)).toBe(true);
    });
  
    test('returns false for positive value', () => {
      expect(isDeliveryFree(20)).toBe(false);
    });
  });
  
  describe('getDeliveryPriceText', () => {
    test('returns Free for zero delivery', () => {
      expect(getDeliveryPriceText(0, 'TL', 'en')).toBe('Free');
      expect(getDeliveryPriceText(0, 'TL', 'tr')).toBe('Ücretsiz');
      expect(getDeliveryPriceText(0, 'TL', 'ru')).toBe('Бесплатно');
    });
  
    test('returns formatted price for positive delivery', () => {
      expect(getDeliveryPriceText(20, 'TL', 'en')).toBe('20 TL');
    });
  });
  
  // ============================================================================
  // DATE FORMATTING TESTS
  // ============================================================================
  describe('getLocaleCode', () => {
    test('returns correct locale codes', () => {
      expect(getLocaleCode('en')).toBe('en-US');
      expect(getLocaleCode('tr')).toBe('tr-TR');
      expect(getLocaleCode('ru')).toBe('ru-RU');
    });
  
    test('defaults to en-US', () => {
      expect(getLocaleCode('unknown')).toBe('en-US');
    });
  });
  
  describe('formatReceiptDate', () => {
    test('formats date in English', () => {
      const date = new Date('2024-06-15T14:30:00');
      const result = formatReceiptDate(date, 'en');
      expect(result).toContain('2024');
      expect(result).toContain('June');
    });
  
    test('returns N/A for null date', () => {
      expect(formatReceiptDate(null, 'en')).toBe('N/A');
    });
  
    test('returns N/A for non-Date', () => {
      expect(formatReceiptDate('not a date', 'en')).toBe('N/A');
    });
  });
  
  // ============================================================================
  // FILE PATH TESTS
  // ============================================================================
  describe('getReceiptFilePath', () => {
    test('generates correct path', () => {
      expect(getReceiptFilePath('order123')).toBe('receipts/order123.pdf');
    });
  });
  
  describe('getReceiptCollectionPath', () => {
    test('returns shop path for shop owner', () => {
      expect(getReceiptCollectionPath('shop', 'shop123')).toBe('shops/shop123/receipts');
    });
  
    test('returns user path for user owner', () => {
      expect(getReceiptCollectionPath('user', 'user456')).toBe('users/user456/receipts');
    });
  
    test('defaults to user path for unknown owner type', () => {
      expect(getReceiptCollectionPath('unknown', 'id123')).toBe('users/id123/receipts');
    });
  });
  
  // ============================================================================
  // RECEIPT DOCUMENT TESTS
  // ============================================================================
  describe('buildReceiptDocument', () => {
    test('builds basic order receipt', () => {
      const taskData = {
        orderId: 'order123',
        buyerId: 'buyer456',
        totalPrice: 150,
        itemsSubtotal: 130,
        deliveryPrice: 20,
        currency: 'TL',
        paymentMethod: 'credit_card',
      };
  
      const doc = buildReceiptDocument('receipt789', taskData, 'receipts/order123.pdf');
  
      expect(doc.receiptId).toBe('receipt789');
      expect(doc.receiptType).toBe('order');
      expect(doc.orderId).toBe('order123');
      expect(doc.totalPrice).toBe(150);
      expect(doc.filePath).toBe('receipts/order123.pdf');
    });
  
    test('builds boost receipt with boost data', () => {
      const taskData = {
        receiptType: 'boost',
        orderId: 'boost123',
        buyerId: 'buyer456',
        totalPrice: 50,
        itemsSubtotal: 50,
        currency: 'TL',
        paymentMethod: 'credit_card',
        boostData: {
          boostDuration: 30,
          itemCount: 5,
        },
      };
  
      const doc = buildReceiptDocument('receipt789', taskData, 'receipts/boost123.pdf');
  
      expect(doc.receiptType).toBe('boost');
      expect(doc.boostDuration).toBe(30);
      expect(doc.itemCount).toBe(5);
    });
  
    test('builds receipt with pickup point', () => {
      const taskData = {
        orderId: 'order123',
        buyerId: 'buyer456',
        totalPrice: 100,
        itemsSubtotal: 100,
        currency: 'TL',
        paymentMethod: 'cash',
        deliveryOption: 'pickup',
        pickupPoint: {
          name: 'Downtown Store',
          address: '123 Main St',
        },
      };
  
      const doc = buildReceiptDocument('receipt789', taskData, 'path');
  
      expect(doc.pickupPointName).toBe('Downtown Store');
      expect(doc.pickupPointAddress).toBe('123 Main St');
    });
  
    test('builds receipt with delivery address', () => {
      const taskData = {
        orderId: 'order123',
        buyerId: 'buyer456',
        totalPrice: 120,
        itemsSubtotal: 100,
        deliveryPrice: 20,
        currency: 'TL',
        paymentMethod: 'credit_card',
        buyerAddress: {
          addressLine1: '456 Oak Ave',
          city: 'Istanbul',
        },
      };
  
      const doc = buildReceiptDocument('receipt789', taskData, 'path');
  
      expect(doc.deliveryAddress).toBe('456 Oak Ave, Istanbul');
    });
  });
  
  // ============================================================================
  // BUYER INFO TESTS
  // ============================================================================
  describe('getBuyerPhone', () => {
    test('returns buyerPhone if available', () => {
      expect(getBuyerPhone({ buyerPhone: '555-1234' })).toBe('555-1234');
    });
  
    test('returns phone from buyerAddress', () => {
      expect(getBuyerPhone({ buyerAddress: { phoneNumber: '555-5678' } })).toBe('555-5678');
    });
  
    test('returns N/A if no phone', () => {
      expect(getBuyerPhone({})).toBe('N/A');
    });
  });
  
  describe('getBuyerNameLabel', () => {
    test('returns Name for order receipt', () => {
      expect(getBuyerNameLabel({ receiptType: 'order' }, 'en')).toBe('Name');
    });
  
    test('returns Shop Name for shop boost receipt', () => {
      expect(getBuyerNameLabel({ receiptType: 'boost', ownerType: 'shop' }, 'en')).toBe('Shop Name');
    });
  
    test('returns Name for user boost receipt', () => {
      expect(getBuyerNameLabel({ receiptType: 'boost', ownerType: 'user' }, 'en')).toBe('Name');
    });
  
    test('localizes correctly', () => {
      expect(getBuyerNameLabel({ receiptType: 'boost', ownerType: 'shop' }, 'tr')).toBe('Dükkan İsmi');
    });
  });
  
  // ============================================================================
  // ATTRIBUTE TESTS
  // ============================================================================
  describe('isSystemField', () => {
    test('returns true for system fields', () => {
      expect(isSystemField('productId')).toBe(true);
      expect(isSystemField('quantity')).toBe(true);
      expect(isSystemField('sellerId')).toBe(true);
    });
  
    test('returns false for display fields', () => {
      expect(isSystemField('color')).toBe(false);
      expect(isSystemField('size')).toBe(false);
    });
  });
  
  describe('filterDisplayableAttributes', () => {
    test('filters out system fields', () => {
      const attrs = {
        color: 'Red',
        size: 'M',
        productId: '123',
        quantity: 2,
      };
      const result = filterDisplayableAttributes(attrs);
      expect(result.color).toBe('Red');
      expect(result.size).toBe('M');
      expect(result.productId).toBeUndefined();
    });
  
    test('filters out empty values', () => {
      const attrs = {
        color: 'Red',
        size: '',
        material: null,
      };
      const result = filterDisplayableAttributes(attrs);
      expect(result.color).toBe('Red');
      expect(result.size).toBeUndefined();
      expect(result.material).toBeUndefined();
    });
  
    test('handles null input', () => {
      expect(filterDisplayableAttributes(null)).toEqual({});
    });
  });
  
  describe('localizeAttributeKey', () => {
    test('localizes known keys', () => {
      expect(localizeAttributeKey('color', 'en')).toBe('Color');
      expect(localizeAttributeKey('color', 'tr')).toBe('Renk');
      expect(localizeAttributeKey('color', 'ru')).toBe('Цвет');
    });
  
    test('returns original for unknown keys', () => {
      expect(localizeAttributeKey('customAttr', 'en')).toBe('customAttr');
    });
  
    test('is case-insensitive', () => {
      expect(localizeAttributeKey('COLOR', 'en')).toBe('Color');
      expect(localizeAttributeKey('Size', 'en')).toBe('Size');
    });
  });
  
  describe('formatAttributes', () => {
    test('formats attributes as string', () => {
      const attrs = { color: 'Red', size: 'M' };
      const result = formatAttributes(attrs, 'en');
      expect(result).toContain('Color: Red');
      expect(result).toContain('Size: M');
    });
  
    test('returns dash for empty attributes', () => {
      expect(formatAttributes({}, 'en')).toBe('-');
      expect(formatAttributes(null, 'en')).toBe('-');
    });
  });
  
  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  describe('getTaskStatusAfterError', () => {
    test('returns pending for retryCount < 3', () => {
      expect(getTaskStatusAfterError(0)).toBe('pending');
      expect(getTaskStatusAfterError(1)).toBe('pending');
      expect(getTaskStatusAfterError(2)).toBe('pending');
    });
  
    test('returns failed for retryCount >= 3', () => {
      expect(getTaskStatusAfterError(3)).toBe('failed');
      expect(getTaskStatusAfterError(5)).toBe('failed');
    });
  });
  
  describe('shouldRetryTask', () => {
    test('returns true for retryCount < 3', () => {
      expect(shouldRetryTask(0)).toBe(true);
      expect(shouldRetryTask(1)).toBe(true);
      expect(shouldRetryTask(2)).toBe(true);
    });
  
    test('returns false for retryCount >= 3', () => {
      expect(shouldRetryTask(3)).toBe(false);
      expect(shouldRetryTask(5)).toBe(false);
    });
  });
  
  // ============================================================================
  // RECEIPT TYPE CHECKS TESTS
  // ============================================================================
  describe('isBoostReceipt', () => {
    test('returns true for boost receipt', () => {
      expect(isBoostReceipt({ receiptType: 'boost' })).toBe(true);
    });
  
    test('returns false for order receipt', () => {
      expect(isBoostReceipt({ receiptType: 'order' })).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isBoostReceipt(null)).toBe(false);
    });
  });
  
  describe('isOrderReceipt', () => {
    test('returns true for order receipt', () => {
      expect(isOrderReceipt({ receiptType: 'order' })).toBe(true);
    });
  
    test('returns true for no receiptType (default)', () => {
      expect(isOrderReceipt({})).toBe(true);
    });
  
    test('returns false for boost receipt', () => {
      expect(isOrderReceipt({ receiptType: 'boost' })).toBe(false);
    });
  });
  
  describe('shouldShowDelivery', () => {
    test('returns true for order receipt', () => {
      expect(shouldShowDelivery({ receiptType: 'order' })).toBe(true);
    });
  
    test('returns false for boost receipt', () => {
      expect(shouldShowDelivery({ receiptType: 'boost' })).toBe(false);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete order receipt flow', () => {
      const taskData = {
        orderId: 'ORD-2024-001',
        buyerId: 'user123',
        totalPrice: 250,
        itemsSubtotal: 230,
        deliveryPrice: 20,
        currency: 'TL',
        paymentMethod: 'credit_card',
        language: 'tr',
        buyerAddress: {
          addressLine1: 'Atatürk Cad. No:123',
          city: 'Istanbul',
          phoneNumber: '555-1234',
        },
      };
  
      // 1. Get effective language
      const lang = getEffectiveLanguage(taskData.language);
      expect(lang).toBe('tr');
  
      // 2. Get labels
      const labels = getReceiptLabels(lang);
      expect(labels.title).toBe('Nar24 Fatura');
  
      // 3. Format delivery option
      const deliveryText = formatDeliveryOption('normal', lang);
      expect(deliveryText).toBe('Normal Teslimat');
  
      // 4. Calculate totals
      const totals = calculateTotals(taskData);
      expect(totals.grandTotal).toBe(250);
  
      // 5. Get delivery price text
      const deliveryPriceText = getDeliveryPriceText(totals.deliveryPrice, taskData.currency, lang);
      expect(deliveryPriceText).toBe('20 TL');
  
      // 6. Get file path
      const filePath = getReceiptFilePath(taskData.orderId);
      expect(filePath).toBe('receipts/ORD-2024-001.pdf');
  
      // 7. Build receipt document
      const doc = buildReceiptDocument('receipt123', taskData, filePath);
      expect(doc.deliveryAddress).toBe('Atatürk Cad. No:123, Istanbul');
    });
  
    test('complete boost receipt flow', () => {
      const taskData = {
        receiptType: 'boost',
        ownerType: 'shop',
        orderId: 'BOOST-2024-001',
        buyerId: 'shop456',
        totalPrice: 150,
        itemsSubtotal: 150,
        currency: 'TL',
        paymentMethod: 'credit_card',
        language: 'en',
        boostData: {
          boostDuration: 60,
          itemCount: 10,
          items: [{ productName: 'Item 1', unitPrice: 15, totalPrice: 15 }],
        },
      };
  
      // 1. Check receipt type
      expect(isBoostReceipt(taskData)).toBe(true);
      expect(shouldShowDelivery(taskData)).toBe(false);
  
      // 2. Format duration
      const duration = formatDuration(taskData.boostData.boostDuration, 'en');
      expect(duration).toBe('60 minutes');
  
      // 3. Format item count
      const itemCount = formatItemCount(taskData.boostData.itemCount, 'en');
      expect(itemCount).toBe('10 items');
  
      // 4. Get buyer name label (should be Shop Name for shop boost)
      const nameLabel = getBuyerNameLabel(taskData, 'en');
      expect(nameLabel).toBe('Shop Name');
  
      // 5. Build receipt document
      const doc = buildReceiptDocument('receipt456', taskData, 'receipts/BOOST-2024-001.pdf');
      expect(doc.receiptType).toBe('boost');
      expect(doc.boostDuration).toBe(60);
      expect(doc.itemCount).toBe(10);
    });
  
    test('receipt with pickup point', () => {
      const taskData = {
        orderId: 'ORD-PICKUP-001',
        buyerId: 'user789',
        totalPrice: 100,
        itemsSubtotal: 100,
        currency: 'TL',
        paymentMethod: 'cash',
        deliveryOption: 'pickup',
        pickupPoint: {
          name: 'Central Station Pickup',
          address: 'Central Station, Platform 5',
          phone: '555-9999',
        },
      };
  
      const doc = buildReceiptDocument('receipt789', taskData, 'path');
      
      expect(doc.pickupPointName).toBe('Central Station Pickup');
      expect(doc.pickupPointAddress).toBe('Central Station, Platform 5');
      expect(doc.deliveryAddress).toBeUndefined();
    });
  
    test('retry logic scenario', () => {
      // First attempt
      let retryCount = 0;
      expect(shouldRetryTask(retryCount)).toBe(true);
      expect(getTaskStatusAfterError(retryCount)).toBe('pending');
  
      // Second attempt
      retryCount = 1;
      expect(shouldRetryTask(retryCount)).toBe(true);
  
      // Third attempt
      retryCount = 2;
      expect(shouldRetryTask(retryCount)).toBe(true);
  
      // Fourth attempt (should fail permanently)
      retryCount = 3;
      expect(shouldRetryTask(retryCount)).toBe(false);
      expect(getTaskStatusAfterError(retryCount)).toBe('failed');
    });
  
    test('attribute formatting scenario', () => {
      const selectedAttributes = {
        color: 'Navy Blue',
        size: 'XL',
        material: 'Cotton',
        productId: 'prod123', // System field - should be filtered
        quantity: 2,          // System field - should be filtered
        brand: '',            // Empty - should be filtered
      };
  
      // Filter and format
      const filtered = filterDisplayableAttributes(selectedAttributes);
      expect(Object.keys(filtered)).toHaveLength(3);
      expect(filtered.productId).toBeUndefined();
  
      // Format for display
      const formatted = formatAttributes(selectedAttributes, 'tr');
      expect(formatted).toContain('Renk: Navy Blue');
      expect(formatted).toContain('Beden: XL');
      expect(formatted).not.toContain('productId');
    });
  });
