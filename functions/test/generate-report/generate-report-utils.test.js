// functions/test/generate-report/generate-report-utils.test.js
//
// Unit tests for PDF report generation utility functions
// Tests the EXACT logic from report generation cloud functions
//
// Run: npx jest test/generate-report/generate-report-utils.test.js

const {
    SUPPORTED_LANGUAGES,
    DEFAULT_LANGUAGE,
    MAX_ITEMS_PER_SECTION,
    BATCH_SIZE,
    PDF_URL_EXPIRY_DAYS,
    ReportTranslations,
  
  
    t,
    getTranslation,
    getSupportedLanguages,
    isValidLanguage,
    getEffectiveLanguage,
  
    getLocaleCode,
    formatDate,
    formatDateTime,
    formatDateRange,
  
    extractDate,
    sortProducts,
    sortOrders,
    sortBoosts,
  
    localizeShipmentStatus,
    getStatusKey,
  
    getReportLocalizedContent,
  
    validateReportInput,
  
    generateReportFilePath,
    calculatePdfUrlExpiry,
  
    buildReportSummary,
  
    buildProductRow,
    buildOrderRow,
    buildBoostRow,
  
    getProductHeaders,
    getOrderHeaders,
    getBoostHeaders,
  
    buildSuccessResponse,
    buildErrorResponse,
  
    limitItems,
    shouldShowTruncationMessage,
    getTruncationMessage,
  } = require('./generate-report-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('SUPPORTED_LANGUAGES contains en, tr, ru', () => {
      expect(SUPPORTED_LANGUAGES).toEqual(['en', 'tr', 'ru']);
    });
  
    test('DEFAULT_LANGUAGE is en', () => {
      expect(DEFAULT_LANGUAGE).toBe('en');
    });
  
    test('MAX_ITEMS_PER_SECTION is 100', () => {
      expect(MAX_ITEMS_PER_SECTION).toBe(100);
    });
  
    test('BATCH_SIZE is 500', () => {
      expect(BATCH_SIZE).toBe(500);
    });
  
    test('PDF_URL_EXPIRY_DAYS is 7', () => {
      expect(PDF_URL_EXPIRY_DAYS).toBe(7);
    });
  
    test('ReportTranslations has all languages', () => {
      expect(ReportTranslations.en).toBeDefined();
      expect(ReportTranslations.tr).toBeDefined();
      expect(ReportTranslations.ru).toBeDefined();
    });
  });
  
  // ============================================================================
  // TRANSLATION TESTS
  // ============================================================================
  describe('t (translation helper)', () => {
    test('returns English translation', () => {
      expect(t('en', 'products')).toBe('Products');
      expect(t('en', 'orders')).toBe('Orders');
    });
  
    test('returns Turkish translation', () => {
      expect(t('tr', 'products')).toBe('Ürünler');
      expect(t('tr', 'orders')).toBe('Siparişler');
    });
  
    test('returns Russian translation', () => {
      expect(t('ru', 'products')).toBe('Товары');
      expect(t('ru', 'orders')).toBe('Заказы');
    });
  
    test('falls back to English for unknown language', () => {
      expect(t('de', 'products')).toBe('Products');
    });
  
    test('returns key if not found', () => {
      expect(t('en', 'unknownKey')).toBe('unknownKey');
    });
  
    test('handles function translations', () => {
      const result = t('en', 'showingFirstItemsOfTotal', 50, 200);
      expect(result).toBe('Showing first 50 items of 200 total');
    });
  
    test('handles function translations in Turkish', () => {
      const result = t('tr', 'showingFirstItemsOfTotal', 50, 200);
      expect(result).toContain('50');
      expect(result).toContain('200');
    });
  });
  
  describe('getTranslation', () => {
    test('returns translation', () => {
      expect(getTranslation('en', 'generated')).toBe('Generated');
    });
  });
  
  describe('Language utilities', () => {
    test('getSupportedLanguages returns all languages', () => {
      expect(getSupportedLanguages()).toEqual(['en', 'tr', 'ru']);
    });
  
    test('isValidLanguage returns true for valid', () => {
      expect(isValidLanguage('en')).toBe(true);
      expect(isValidLanguage('tr')).toBe(true);
      expect(isValidLanguage('ru')).toBe(true);
    });
  
    test('isValidLanguage returns false for invalid', () => {
      expect(isValidLanguage('de')).toBe(false);
      expect(isValidLanguage('')).toBe(false);
    });
  
    test('getEffectiveLanguage returns valid language', () => {
      expect(getEffectiveLanguage('tr')).toBe('tr');
    });
  
    test('getEffectiveLanguage falls back to en', () => {
      expect(getEffectiveLanguage('de')).toBe('en');
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
  
  describe('formatDate', () => {
    test('formats date object', () => {
      const date = new Date('2024-06-15');
      const result = formatDate(date, 'en');
      expect(result).toContain('2024');
    });
  
    test('handles Firestore timestamp-like object', () => {
      const firestoreDate = {
        toDate: () => new Date('2024-06-15'),
      };
      const result = formatDate(firestoreDate, 'en');
      expect(result).toContain('2024');
    });
  
    test('returns notSpecified for null', () => {
      expect(formatDate(null, 'en')).toBe('Not specified');
      expect(formatDate(null, 'tr')).toBe('Belirtilmemiş');
    });
  });
  
  describe('formatDateTime', () => {
    test('formats date with time', () => {
      const date = new Date('2024-06-15T14:30:00');
      const result = formatDateTime(date, 'en');
      expect(result).toContain('2024');
    });
  
    test('returns notSpecified for null', () => {
      expect(formatDateTime(null, 'en')).toBe('Not specified');
    });
  });
  
  describe('formatDateRange', () => {
    test('formats date range', () => {
      const start = new Date('2024-01-01');
      const end = new Date('2024-01-31');
      const result = formatDateRange(start, end, 'en');
      expect(result).toContain(' - ');
      expect(result).toContain('2024');
    });
  });
  
  // ============================================================================
  // SORTING TESTS
  // ============================================================================
  describe('extractDate', () => {
    test('extracts date from Date object', () => {
      const item = { createdAt: new Date('2024-06-15') };
      const result = extractDate(item, 'createdAt');
      expect(result.getFullYear()).toBe(2024);
    });
  
    test('extracts date from Firestore timestamp', () => {
      const item = { createdAt: { toDate: () => new Date('2024-06-15') } };
      const result = extractDate(item, 'createdAt');
      expect(result.getFullYear()).toBe(2024);
    });
  
    test('returns epoch for missing field', () => {
      const item = {};
      const result = extractDate(item, 'createdAt');
      expect(result.getFullYear()).toBe(1970);
    });
  });
  
  describe('sortProducts', () => {
    const products = [
      { productName: 'A', price: 100, purchaseCount: 5, clickCount: 10, favoritesCount: 3, cartCount: 2 },
      { productName: 'B', price: 200, purchaseCount: 10, clickCount: 5, favoritesCount: 1, cartCount: 8 },
      { productName: 'C', price: 50, purchaseCount: 2, clickCount: 20, favoritesCount: 5, cartCount: 1 },
    ];
  
    test('sorts by price descending', () => {
      const sorted = sortProducts(products, 'price', true);
      expect(sorted[0].productName).toBe('B');
      expect(sorted[2].productName).toBe('C');
    });
  
    test('sorts by price ascending', () => {
      const sorted = sortProducts(products, 'price', false);
      expect(sorted[0].productName).toBe('C');
      expect(sorted[2].productName).toBe('B');
    });
  
    test('sorts by purchaseCount', () => {
      const sorted = sortProducts(products, 'purchaseCount', true);
      expect(sorted[0].productName).toBe('B');
    });
  
    test('sorts by clickCount', () => {
      const sorted = sortProducts(products, 'clickCount', true);
      expect(sorted[0].productName).toBe('C');
    });
  
    test('sorts by favoritesCount', () => {
      const sorted = sortProducts(products, 'favoritesCount', true);
      expect(sorted[0].productName).toBe('C');
    });
  
    test('sorts by cartCount', () => {
      const sorted = sortProducts(products, 'cartCount', true);
      expect(sorted[0].productName).toBe('B');
    });
  
    test('handles null input', () => {
      expect(sortProducts(null, 'price', true)).toEqual([]);
    });
  
    test('does not mutate original array', () => {
      const original = [...products];
      sortProducts(products, 'price', true);
      expect(products).toEqual(original);
    });
  });
  
  describe('sortOrders', () => {
    const orders = [
      { productName: 'A', price: 100 },
      { productName: 'B', price: 200 },
      { productName: 'C', price: 50 },
    ];
  
    test('sorts by price descending', () => {
      const sorted = sortOrders(orders, 'price', true);
      expect(sorted[0].productName).toBe('B');
    });
  
    test('sorts by price ascending', () => {
      const sorted = sortOrders(orders, 'price', false);
      expect(sorted[0].productName).toBe('C');
    });
  
    test('handles null input', () => {
      expect(sortOrders(null, 'price', true)).toEqual([]);
    });
  });
  
  describe('sortBoosts', () => {
    const boosts = [
      { itemName: 'A', boostDuration: 30, boostPrice: 100, impressionsDuringBoost: 500, clicksDuringBoost: 20 },
      { itemName: 'B', boostDuration: 60, boostPrice: 200, impressionsDuringBoost: 300, clicksDuringBoost: 50 },
      { itemName: 'C', boostDuration: 15, boostPrice: 50, impressionsDuringBoost: 800, clicksDuringBoost: 10 },
    ];
  
    test('sorts by duration descending', () => {
      const sorted = sortBoosts(boosts, 'duration', true);
      expect(sorted[0].itemName).toBe('B');
    });
  
    test('sorts by price descending', () => {
      const sorted = sortBoosts(boosts, 'price', true);
      expect(sorted[0].itemName).toBe('B');
    });
  
    test('sorts by impressionCount descending', () => {
      const sorted = sortBoosts(boosts, 'impressionCount', true);
      expect(sorted[0].itemName).toBe('C');
    });
  
    test('sorts by clickCount descending', () => {
      const sorted = sortBoosts(boosts, 'clickCount', true);
      expect(sorted[0].itemName).toBe('B');
    });
  
    test('handles null input', () => {
      expect(sortBoosts(null, 'price', true)).toEqual([]);
    });
  });
  
  // ============================================================================
  // STATUS LOCALIZATION TESTS
  // ============================================================================
  describe('localizeShipmentStatus', () => {
    test('localizes pending status', () => {
      expect(localizeShipmentStatus('pending', 'en')).toBe('Pending');
      expect(localizeShipmentStatus('pending', 'tr')).toBe('Beklemede');
      expect(localizeShipmentStatus('pending', 'ru')).toBe('В ожидании');
    });
  
    test('localizes delivered status', () => {
      expect(localizeShipmentStatus('delivered', 'en')).toBe('Delivered');
      expect(localizeShipmentStatus('delivered', 'tr')).toBe('Teslim Edildi');
    });
  
    test('handles case insensitivity', () => {
      expect(localizeShipmentStatus('PENDING', 'en')).toBe('Pending');
      expect(localizeShipmentStatus('Delivered', 'en')).toBe('Delivered');
    });
  
    test('returns notSpecified for null', () => {
      expect(localizeShipmentStatus(null, 'en')).toBe('Not specified');
    });
  
    test('capitalizes unknown status', () => {
      expect(localizeShipmentStatus('customstatus', 'en')).toBe('Customstatus');
    });
  });
  
  describe('getStatusKey', () => {
    test('returns status key for known statuses', () => {
      expect(getStatusKey('pending')).toBe('statusPending');
      expect(getStatusKey('delivered')).toBe('statusDelivered');
    });
  
    test('returns null for unknown status', () => {
      expect(getStatusKey('unknown')).toBe(null);
    });
  
    test('returns null for null', () => {
      expect(getStatusKey(null)).toBe(null);
    });
  });
  
  // ============================================================================
  // EMAIL CONTENT TESTS
  // ============================================================================
  describe('getReportLocalizedContent', () => {
    test('returns English content', () => {
      const content = getReportLocalizedContent('en');
      expect(content.reportReady).toBe('Your Report is Ready!');
      expect(content.subject).toBe('Your Shop Report');
    });
  
    test('returns Turkish content', () => {
      const content = getReportLocalizedContent('tr');
      expect(content.reportReady).toBe('Raporunuz Hazır!');
    });
  
    test('returns Russian content', () => {
      const content = getReportLocalizedContent('ru');
      expect(content.reportReady).toBe('Ваш отчет готов!');
    });
  
    test('defaults to English', () => {
      const content = getReportLocalizedContent('unknown');
      expect(content.reportReady).toBe('Your Report is Ready!');
    });
  });
  
  // ============================================================================
  // INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateReportInput', () => {
    test('returns valid for complete input', () => {
      const data = { reportId: 'r1', shopId: 's1' };
      expect(validateReportInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing reportId', () => {
      const data = { shopId: 's1' };
      const result = validateReportInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'reportId')).toBe(true);
    });
  
    test('returns invalid for missing shopId', () => {
      const data = { reportId: 'r1' };
      const result = validateReportInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'shopId')).toBe(true);
    });
  });
  
  // ============================================================================
  // FILE PATH TESTS
  // ============================================================================
  describe('generateReportFilePath', () => {
    test('generates correct path', () => {
      const path = generateReportFilePath('shop123', 'report456', 1234567890);
      expect(path).toBe('reports/shop123/report456_1234567890.pdf');
    });
  });
  
  describe('calculatePdfUrlExpiry', () => {
    test('calculates 7 days from now', () => {
      const now = Date.now();
      const expiry = calculatePdfUrlExpiry(now);
      expect(expiry - now).toBe(7 * 24 * 60 * 60 * 1000);
    });
  });
  
  // ============================================================================
  // SUMMARY TESTS
  // ============================================================================
  describe('buildReportSummary', () => {
    test('builds summary with counts', () => {
      const reportData = {
        products: [1, 2, 3],
        orders: [1, 2],
        boostHistory: [1],
      };
      const summary = buildReportSummary(reportData);
      expect(summary.productsCount).toBe(3);
      expect(summary.ordersCount).toBe(2);
      expect(summary.boostsCount).toBe(1);
    });
  
    test('handles missing data', () => {
      const summary = buildReportSummary({});
      expect(summary.productsCount).toBe(0);
      expect(summary.ordersCount).toBe(0);
      expect(summary.boostsCount).toBe(0);
    });
  });
  
  // ============================================================================
  // ROW BUILDER TESTS
  // ============================================================================
  describe('buildProductRow', () => {
    test('builds product row', () => {
      const item = {
        productName: 'Test Product',
        price: 100,
        currency: 'TL',
        quantity: 5,
        clickCount: 10,
        purchaseCount: 3,
        favoritesCount: 2,
        cartCount: 1,
      };
      const row = buildProductRow(item, 'en');
      expect(row[0]).toBe('Test Product');
      expect(row[1]).toBe('100 TL');
      expect(row[2]).toBe('5');
    });
  
    test('handles missing values', () => {
      const row = buildProductRow({}, 'en');
      expect(row[0]).toBe('Not specified');
      expect(row[1]).toBe('0 TL');
    });
  });
  
  describe('buildOrderRow', () => {
    test('builds order row', () => {
      const item = {
        productName: 'Test Product',
        buyerName: 'John Doe',
        quantity: 2,
        price: 50,
        currency: 'TL',
        shipmentStatus: 'delivered',
      };
      const row = buildOrderRow(item, 'en');
      expect(row[0]).toBe('Test Product');
      expect(row[1]).toBe('John Doe');
      expect(row[4]).toBe('Delivered');
    });
  });
  
  describe('buildBoostRow', () => {
    test('builds boost row', () => {
      const item = {
        itemName: 'Boosted Item',
        boostDuration: 30,
        boostPrice: 100,
        currency: 'TL',
        impressionsDuringBoost: 500,
        clicksDuringBoost: 20,
      };
      const row = buildBoostRow(item, 'en');
      expect(row[0]).toBe('Boosted Item');
      expect(row[1]).toBe('30');
      expect(row[2]).toBe('100 TL');
    });
  });
  
  // ============================================================================
  // HEADER TESTS
  // ============================================================================
  describe('getProductHeaders', () => {
    test('returns English headers', () => {
      const headers = getProductHeaders('en');
      expect(headers).toContain('Product Name');
      expect(headers).toContain('Price');
    });
  
    test('returns Turkish headers', () => {
      const headers = getProductHeaders('tr');
      expect(headers).toContain('Ürün Adı');
      expect(headers).toContain('Fiyat');
    });
  });
  
  describe('getOrderHeaders', () => {
    test('returns headers', () => {
      const headers = getOrderHeaders('en');
      expect(headers).toContain('Product');
      expect(headers).toContain('Buyer');
      expect(headers).toContain('Status');
    });
  });
  
  describe('getBoostHeaders', () => {
    test('returns headers', () => {
      const headers = getBoostHeaders('en');
      expect(headers).toContain('Item');
      expect(headers).toContain('Duration (min)');
      expect(headers).toContain('Impressions');
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildSuccessResponse', () => {
    test('builds success response', () => {
      const response = buildSuccessResponse('https://example.com/report.pdf', 'en');
      expect(response.success).toBe(true);
      expect(response.pdfUrl).toBe('https://example.com/report.pdf');
      expect(response.message).toBe('Report generated successfully');
    });
  
    test('uses localized message', () => {
      const response = buildSuccessResponse('url', 'tr');
      expect(response.message).toBe('Rapor başarıyla oluşturuldu');
    });
  });
  
  describe('buildErrorResponse', () => {
    test('builds error response', () => {
      const response = buildErrorResponse('en');
      expect(response.success).toBe(false);
      expect(response.message).toBe('Report generation failed');
    });
  });
  
  // ============================================================================
  // PAGINATION TESTS
  // ============================================================================
  describe('limitItems', () => {
    test('limits items to max', () => {
      const items = Array(150).fill(1);
      const limited = limitItems(items, 100);
      expect(limited.length).toBe(100);
    });
  
    test('returns all if under limit', () => {
      const items = Array(50).fill(1);
      const limited = limitItems(items, 100);
      expect(limited.length).toBe(50);
    });
  
    test('handles null', () => {
      expect(limitItems(null)).toEqual([]);
    });
  });
  
  describe('shouldShowTruncationMessage', () => {
    test('returns true if over limit', () => {
      const items = Array(150).fill(1);
      expect(shouldShowTruncationMessage(items, 100)).toBe(true);
    });
  
    test('returns false if under limit', () => {
      const items = Array(50).fill(1);
      expect(shouldShowTruncationMessage(items, 100)).toBe(false);
    });
  });
  
  describe('getTruncationMessage', () => {
    test('returns formatted message', () => {
      const message = getTruncationMessage(100, 200, 'en');
      expect(message).toContain('100');
      expect(message).toContain('200');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete report generation flow', () => {
      const input = { reportId: 'report123', shopId: 'shop456' };
  
      // Validate
      expect(validateReportInput(input).isValid).toBe(true);
  
      // Generate file path
      const filePath = generateReportFilePath(input.shopId, input.reportId, 1234567890);
      expect(filePath).toContain('shop456');
      expect(filePath).toContain('report123');
  
      // Mock report data
      const reportData = {
        products: [
          { productName: 'P1', price: 100, purchaseCount: 10 },
          { productName: 'P2', price: 200, purchaseCount: 5 },
        ],
        orders: [
          { productName: 'P1', buyerName: 'John', price: 100 },
        ],
        boostHistory: [],
      };
  
      // Sort products
      const sorted = sortProducts(reportData.products, 'purchaseCount', true);
      expect(sorted[0].productName).toBe('P1');
  
      // Build summary
      const summary = buildReportSummary(reportData);
      expect(summary.productsCount).toBe(2);
      expect(summary.ordersCount).toBe(1);
  
      // Build response
      const response = buildSuccessResponse('https://example.com/report.pdf', 'tr');
      expect(response.success).toBe(true);
      expect(response.message).toBe('Rapor başarıyla oluşturuldu');
    });
  
    test('multilingual report headers', () => {
      ['en', 'tr', 'ru'].forEach((lang) => {
        const productHeaders = getProductHeaders(lang);
        const orderHeaders = getOrderHeaders(lang);
        const boostHeaders = getBoostHeaders(lang);
  
        expect(productHeaders.length).toBe(7);
        expect(orderHeaders.length).toBe(6);
        expect(boostHeaders.length).toBe(6);
      });
    });
  
    test('order status localization across languages', () => {
      const statuses = ['pending', 'processing', 'shipped', 'delivered', 'cancelled', 'returned'];
  
      statuses.forEach((status) => {
        const en = localizeShipmentStatus(status, 'en');
        const tr = localizeShipmentStatus(status, 'tr');
        const ru = localizeShipmentStatus(status, 'ru');
  
        expect(en).not.toBe(status); // Should be localized
        expect(tr).not.toBe(status);
        expect(ru).not.toBe(status);
      });
    });
  });
