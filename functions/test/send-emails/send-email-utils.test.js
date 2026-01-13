// functions/test/send-emails/send-email-utils.test.js
//
// Unit tests for email sending utility functions
// Tests the EXACT logic from email sending cloud functions
//
// Run: npx jest test/send-emails/send-email-utils.test.js

const {
    SUPPORTED_LANGUAGES,
    DEFAULT_LANGUAGE,
    PDF_URL_EXPIRY_DAYS,
    WELCOME_IMAGE_EXPIRY_DAYS,
    RECEIPT_EMAIL_CONTENT,
    REPORT_EMAIL_CONTENT,

  
    validateReceiptEmailInput,
    validateReportEmailInput,
    validateShopWelcomeInput,
  
    formatIdShort,
    formatOrderIdShort,
    formatReceiptIdShort,
    formatReportIdShort,
  
    getLocaleCode,
    formatDateForLocale,
    formatDateRange,
  
    getLocalizedContent,
    getReportLocalizedContent,
  
    getReceiptFilePath,
    getReportFilePath,
    getReportSearchPrefix,
  
    calculatePdfUrlExpiry,
    calculateWelcomeImageExpiry,
    getExpiryDays,
  
    buildReceiptMailDocument,
    buildReportMailDocument,
    buildShopWelcomeMailDocument,
  
    formatPrice,
  
    canAccessReceipt,
    canAccessReport,
  
    getReceiptCollectionPath,
    getReportCollectionPath,
  
    buildSuccessResponse,
    buildWelcomeSuccessResponse,
  
    getWelcomeEmailImages,
    getImagePath,
    getImageKey,
  
    extractDisplayName,
    extractLanguageCode,
    extractShopName,
    extractOwnerName,
  
    getIncludedDataBadges,
  } = require('./send-email-utils');
  
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
  
    test('PDF_URL_EXPIRY_DAYS is 7', () => {
      expect(PDF_URL_EXPIRY_DAYS).toBe(7);
    });
  
    test('WELCOME_IMAGE_EXPIRY_DAYS is 30', () => {
      expect(WELCOME_IMAGE_EXPIRY_DAYS).toBe(30);
    });
  
    test('RECEIPT_EMAIL_CONTENT has all languages', () => {
      expect(RECEIPT_EMAIL_CONTENT.en).toBeDefined();
      expect(RECEIPT_EMAIL_CONTENT.tr).toBeDefined();
      expect(RECEIPT_EMAIL_CONTENT.ru).toBeDefined();
    });
  
    test('REPORT_EMAIL_CONTENT has all languages', () => {
      expect(REPORT_EMAIL_CONTENT.en).toBeDefined();
      expect(REPORT_EMAIL_CONTENT.tr).toBeDefined();
      expect(REPORT_EMAIL_CONTENT.ru).toBeDefined();
    });
  });
  
  // ============================================================================
  // INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateReceiptEmailInput', () => {
    test('returns valid for complete input', () => {
      const data = { receiptId: 'r1', orderId: 'o1', email: 'test@example.com' };
      expect(validateReceiptEmailInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing receiptId', () => {
      const data = { orderId: 'o1', email: 'test@example.com' };
      const result = validateReceiptEmailInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'receiptId')).toBe(true);
    });
  
    test('returns invalid for missing orderId', () => {
      const data = { receiptId: 'r1', email: 'test@example.com' };
      const result = validateReceiptEmailInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'orderId')).toBe(true);
    });
  
    test('returns invalid for missing email', () => {
      const data = { receiptId: 'r1', orderId: 'o1' };
      const result = validateReceiptEmailInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'email')).toBe(true);
    });
  });
  
  describe('validateReportEmailInput', () => {
    test('returns valid for complete input', () => {
      const data = { reportId: 'r1', shopId: 's1', email: 'test@example.com' };
      expect(validateReportEmailInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing fields', () => {
      const result = validateReportEmailInput({});
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBe(3);
    });
  });
  
  describe('validateShopWelcomeInput', () => {
    test('returns valid for complete input', () => {
      const data = { shopId: 's1', email: 'test@example.com' };
      expect(validateShopWelcomeInput(data).isValid).toBe(true);
    });
  
    test('returns invalid for missing shopId', () => {
      const data = { email: 'test@example.com' };
      const result = validateShopWelcomeInput(data);
      expect(result.isValid).toBe(false);
    });
  });
  
  // ============================================================================
  // ID FORMATTING TESTS
  // ============================================================================
  describe('formatIdShort', () => {
    test('formats ID to uppercase', () => {
      expect(formatIdShort('abcd1234efgh', 8)).toBe('ABCD1234');
    });
  
    test('handles short IDs', () => {
      expect(formatIdShort('abc', 8)).toBe('ABC');
    });
  
    test('handles null', () => {
      expect(formatIdShort(null, 8)).toBe('');
    });
  
    test('handles non-string', () => {
      expect(formatIdShort(123, 8)).toBe('');
    });
  });
  
  describe('formatOrderIdShort', () => {
    test('formats order ID', () => {
      expect(formatOrderIdShort('order12345678')).toBe('ORDER123');
    });
  });
  
  describe('formatReceiptIdShort', () => {
    test('formats receipt ID', () => {
      expect(formatReceiptIdShort('receipt12345678')).toBe('RECEIPT1');
    });
  });
  
  describe('formatReportIdShort', () => {
    test('formats report ID', () => {
      expect(formatReportIdShort('report12345678')).toBe('REPORT12');
    });
  });
  
  // ============================================================================
  // DATE FORMATTING TESTS
  // ============================================================================
  describe('getLocaleCode', () => {
    test('returns en-US for en', () => {
      expect(getLocaleCode('en')).toBe('en-US');
    });
  
    test('returns tr-TR for tr', () => {
      expect(getLocaleCode('tr')).toBe('tr-TR');
    });
  
    test('returns ru-RU for ru', () => {
      expect(getLocaleCode('ru')).toBe('ru-RU');
    });
  
    test('defaults to en-US', () => {
      expect(getLocaleCode('unknown')).toBe('en-US');
    });
  });
  
  describe('formatDateForLocale', () => {
    test('formats date', () => {
      const date = new Date('2024-06-15');
      const result = formatDateForLocale(date, 'en');
      expect(result).toContain('2024');
      expect(result).toContain('June');
    });
  
    test('handles null date', () => {
      const result = formatDateForLocale(null, 'en');
      expect(result).toBeTruthy();
    });
  });
  
  describe('formatDateRange', () => {
    test('formats date range', () => {
      const start = new Date('2024-01-01');
      const end = new Date('2024-01-31');
      const result = formatDateRange(start, end);
      expect(result).toContain(' - ');
    });
  
    test('returns empty for null dates', () => {
      expect(formatDateRange(null, null)).toBe('');
    });
  });
  
  // ============================================================================
  // LOCALIZED CONTENT TESTS
  // ============================================================================
  describe('getLocalizedContent', () => {
    test('returns English content', () => {
      const content = getLocalizedContent('en');
      expect(content.greeting).toBe('Hello');
      expect(content.subject).toBe('Your Receipt');
    });
  
    test('returns Turkish content', () => {
      const content = getLocalizedContent('tr');
      expect(content.greeting).toBe('Merhaba');
      expect(content.subject).toBe('Faturanız');
    });
  
    test('returns Russian content', () => {
      const content = getLocalizedContent('ru');
      expect(content.greeting).toBe('Здравствуйте');
      expect(content.subject).toBe('Ваш чек');
    });
  
    test('defaults to English', () => {
      const content = getLocalizedContent('unknown');
      expect(content.greeting).toBe('Hello');
    });
  });
  
  describe('getReportLocalizedContent', () => {
    test('returns English content', () => {
      const content = getReportLocalizedContent('en');
      expect(content.reportReady).toBe('Report Ready!');
    });
  
    test('returns Turkish content', () => {
      const content = getReportLocalizedContent('tr');
      expect(content.reportReady).toBe('Rapor Hazır!');
    });
  
    test('returns Russian content', () => {
      const content = getReportLocalizedContent('ru');
      expect(content.reportReady).toBe('Отчет готов!');
    });
  });
  
  // ============================================================================
  // FILE PATH TESTS
  // ============================================================================
  describe('getReceiptFilePath', () => {
    test('returns existing file path if provided', () => {
      expect(getReceiptFilePath('order123', 'custom/path.pdf')).toBe('custom/path.pdf');
    });
  
    test('generates default path if no existing path', () => {
      expect(getReceiptFilePath('order123')).toBe('receipts/order123.pdf');
    });
  
    test('generates default path for null existing path', () => {
      expect(getReceiptFilePath('order123', null)).toBe('receipts/order123.pdf');
    });
  });
  
  describe('getReportFilePath', () => {
    test('generates correct path', () => {
      expect(getReportFilePath('shop123', 'report456')).toBe('reports/shop123/report456.pdf');
    });
  });
  
  describe('getReportSearchPrefix', () => {
    test('generates correct prefix', () => {
      expect(getReportSearchPrefix('shop123', 'report456')).toBe('reports/shop123/report456');
    });
  });
  
  // ============================================================================
  // URL EXPIRY TESTS
  // ============================================================================
  describe('calculatePdfUrlExpiry', () => {
    test('calculates 7 days from now', () => {
      const now = Date.now();
      const expiry = calculatePdfUrlExpiry(now);
      const diff = expiry - now;
      expect(diff).toBe(7 * 24 * 60 * 60 * 1000);
    });
  });
  
  describe('calculateWelcomeImageExpiry', () => {
    test('calculates 30 days from now', () => {
      const now = Date.now();
      const expiry = calculateWelcomeImageExpiry(now);
      const diff = expiry - now;
      expect(diff).toBe(30 * 24 * 60 * 60 * 1000);
    });
  });
  
  describe('getExpiryDays', () => {
    test('returns 30 for welcome_image', () => {
      expect(getExpiryDays('welcome_image')).toBe(30);
    });
  
    test('returns 7 for other types', () => {
      expect(getExpiryDays('pdf')).toBe(7);
      expect(getExpiryDays('report')).toBe(7);
    });
  });
  
  // ============================================================================
  // MAIL DOCUMENT TESTS
  // ============================================================================
  describe('buildReceiptMailDocument', () => {
    test('builds mail document', () => {
      const content = getLocalizedContent('en');
      const doc = buildReceiptMailDocument('test@example.com', 'ORDER123', content);
  
      expect(doc.to).toEqual(['test@example.com']);
      expect(doc.message.subject).toContain('Your Receipt');
      expect(doc.message.subject).toContain('ORDER123');
      expect(doc.template.name).toBe('receipt');
    });
  });
  
  describe('buildReportMailDocument', () => {
    test('builds mail document', () => {
      const content = getReportLocalizedContent('en');
      const doc = buildReportMailDocument('test@example.com', 'Sales Report', content);
  
      expect(doc.to).toEqual(['test@example.com']);
      expect(doc.message.subject).toContain('Your Business Report');
      expect(doc.message.subject).toContain('Sales Report');
      expect(doc.template.name).toBe('report');
    });
  });
  
  describe('buildShopWelcomeMailDocument', () => {
    test('builds mail document', () => {
      const doc = buildShopWelcomeMailDocument('test@example.com', 'shop123', 'My Shop');
  
      expect(doc.to).toEqual(['test@example.com']);
      expect(doc.message.subject).toContain('Tebrikler');
      expect(doc.template.data.shopId).toBe('shop123');
      expect(doc.template.data.shopName).toBe('My Shop');
    });
  });
  
  // ============================================================================
  // PRICE FORMATTING TESTS
  // ============================================================================
  describe('formatPrice', () => {
    test('formats price with currency', () => {
      expect(formatPrice(100, 'TL')).toBe('100 TL');
    });
  
    test('rounds to integer', () => {
      expect(formatPrice(99.5, 'TL')).toBe('100 TL');
    });
  
    test('handles null', () => {
      expect(formatPrice(null, 'TL')).toBe('0 TL');
    });
  
    test('uses TL as default currency', () => {
      expect(formatPrice(100)).toBe('100 TL');
    });
  });
  
  // ============================================================================
  // OWNERSHIP VERIFICATION TESTS
  // ============================================================================
  describe('canAccessReceipt', () => {
    test('returns true for shop receipt with shopId', () => {
      expect(canAccessReceipt({}, 'user1', true, 'shop1')).toBe(true);
    });
  
    test('returns true if buyerId matches uid', () => {
      expect(canAccessReceipt({ buyerId: 'user1' }, 'user1', false, null)).toBe(true);
    });
  
    test('returns false if buyerId does not match', () => {
      expect(canAccessReceipt({ buyerId: 'user2' }, 'user1', false, null)).toBe(false);
    });
  });
  
  describe('canAccessReport', () => {
    test('returns true for owner', () => {
      expect(canAccessReport({ ownerId: 'user1' }, 'user1')).toBe(true);
    });
  
    test('returns true for manager', () => {
      expect(canAccessReport({ ownerId: 'user2', managers: ['user1'] }, 'user1')).toBe(true);
    });
  
    test('returns false for non-owner/non-manager', () => {
      expect(canAccessReport({ ownerId: 'user2', managers: [] }, 'user1')).toBe(false);
    });
  
    test('returns false for null shopData', () => {
      expect(canAccessReport(null, 'user1')).toBe(false);
    });
  });
  
  // ============================================================================
  // COLLECTION PATH TESTS
  // ============================================================================
  describe('getReceiptCollectionPath', () => {
    test('returns shop path for shop receipt', () => {
      expect(getReceiptCollectionPath(true, 'shop123', 'user456')).toBe('shops/shop123/receipts');
    });
  
    test('returns user path for user receipt', () => {
      expect(getReceiptCollectionPath(false, null, 'user456')).toBe('users/user456/receipts');
    });
  });
  
  describe('getReportCollectionPath', () => {
    test('returns correct path', () => {
      expect(getReportCollectionPath('shop123')).toBe('shops/shop123/reports');
    });
  });
  
  // ============================================================================
  // RESPONSE BUILDING TESTS
  // ============================================================================
  describe('buildSuccessResponse', () => {
    test('builds default success response', () => {
      const response = buildSuccessResponse();
      expect(response.success).toBe(true);
      expect(response.message).toBe('Email sent successfully');
    });
  
    test('builds custom message response', () => {
      const response = buildSuccessResponse('Custom message');
      expect(response.message).toBe('Custom message');
    });
  });
  
  describe('buildWelcomeSuccessResponse', () => {
    test('builds welcome success response', () => {
      const response = buildWelcomeSuccessResponse('My Shop');
      expect(response.success).toBe(true);
      expect(response.message).toBe('Welcome email sent successfully');
      expect(response.shopName).toBe('My Shop');
    });
  });
  
  // ============================================================================
  // WELCOME EMAIL IMAGES TESTS
  // ============================================================================
  describe('getWelcomeEmailImages', () => {
    test('returns image list', () => {
      const images = getWelcomeEmailImages();
      expect(images).toContain('shopwelcome.png');
      expect(images).toContain('shopproducts.png');
      expect(images).toContain('shopboost.png');
    });
  });
  
  describe('getImagePath', () => {
    test('returns correct path', () => {
      expect(getImagePath('shopwelcome.png')).toBe('functions/shop-email-icons/shopwelcome.png');
    });
  });
  
  describe('getImageKey', () => {
    test('removes .png extension', () => {
      expect(getImageKey('shopwelcome.png')).toBe('shopwelcome');
    });
  });
  
  // ============================================================================
  // DATA EXTRACTION TESTS
  // ============================================================================
  describe('extractDisplayName', () => {
    test('extracts display name', () => {
      expect(extractDisplayName({ displayName: 'John Doe' })).toBe('John Doe');
    });
  
    test('returns default for missing', () => {
      expect(extractDisplayName({}, 'Default')).toBe('Default');
    });
  
    test('returns Customer as default', () => {
      expect(extractDisplayName({})).toBe('Customer');
    });
  });
  
  describe('extractLanguageCode', () => {
    test('extracts language code', () => {
      expect(extractLanguageCode({ languageCode: 'tr' })).toBe('tr');
    });
  
    test('returns en as default', () => {
      expect(extractLanguageCode({})).toBe('en');
    });
  });
  
  describe('extractShopName', () => {
    test('extracts shop name', () => {
      expect(extractShopName({ name: 'My Shop' })).toBe('My Shop');
    });
  
    test('returns default for missing', () => {
      expect(extractShopName({})).toBe('Unknown Shop');
    });
  });
  
  describe('extractOwnerName', () => {
    test('extracts owner name', () => {
      expect(extractOwnerName({ ownerName: 'John' })).toBe('John');
    });
  
    test('returns Turkish default', () => {
      expect(extractOwnerName({})).toBe('Değerli Satıcı');
    });
  });
  
  // ============================================================================
  // DATA BADGES TESTS
  // ============================================================================
  describe('getIncludedDataBadges', () => {
    const content = getReportLocalizedContent('en');
  
    test('returns products badge', () => {
      const badges = getIncludedDataBadges({ includeProducts: true }, content);
      expect(badges).toHaveLength(1);
      expect(badges[0].label).toBe('Products');
    });
  
    test('returns all badges', () => {
      const reportData = {
        includeProducts: true,
        includeOrders: true,
        includeBoostHistory: true,
      };
      const badges = getIncludedDataBadges(reportData, content);
      expect(badges).toHaveLength(3);
    });
  
    test('returns empty for no included data', () => {
      const badges = getIncludedDataBadges({}, content);
      expect(badges).toHaveLength(0);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete receipt email flow', () => {
      const input = {
        receiptId: 'receipt123456789',
        orderId: 'order987654321',
        email: 'customer@example.com',
      };
  
      // Validate input
      const validation = validateReceiptEmailInput(input);
      expect(validation.isValid).toBe(true);
  
      // Format IDs
      const orderIdShort = formatOrderIdShort(input.orderId);
      const receiptIdShort = formatReceiptIdShort(input.receiptId);
      expect(orderIdShort).toBe('ORDER987');
      expect(receiptIdShort).toBe('RECEIPT1');
  
      // Get content
      const content = getLocalizedContent('tr');
      expect(content.subject).toBe('Faturanız');
  
      // Build mail document
      const mailDoc = buildReceiptMailDocument(input.email, orderIdShort, content);
      expect(mailDoc.to).toEqual(['customer@example.com']);
  
      // Get file path
      const filePath = getReceiptFilePath(input.orderId);
      expect(filePath).toBe('receipts/order987654321.pdf');
    });
  
    test('complete report email flow', () => {
      const input = {
        reportId: 'report123456789',
        shopId: 'shop456',
        email: 'owner@example.com',
      };
  
      // Validate
      expect(validateReportEmailInput(input).isValid).toBe(true);
  
      // Check access
      const shopData = { ownerId: 'user123', managers: ['user456'] };
      expect(canAccessReport(shopData, 'user123')).toBe(true);
      expect(canAccessReport(shopData, 'user456')).toBe(true);
      expect(canAccessReport(shopData, 'user789')).toBe(false);
  
      // Get content
      const content = getReportLocalizedContent('en');
      expect(content.downloadButton).toBe('Download Report');
  
      // Build mail document
      const mailDoc = buildReportMailDocument(input.email, 'Monthly Sales', content);
      expect(mailDoc.message.subject).toContain('Monthly Sales');
    });
  
    test('shop welcome email flow', () => {
      const input = {
        shopId: 'shop789',
        email: 'newshop@example.com',
      };
  
      // Validate
      expect(validateShopWelcomeInput(input).isValid).toBe(true);
  
      // Extract data
      const shopData = { name: 'Fashion Store', ownerName: 'Ahmet' };
      expect(extractShopName(shopData)).toBe('Fashion Store');
      expect(extractOwnerName(shopData)).toBe('Ahmet');
  
      // Get images
      const images = getWelcomeEmailImages();
      expect(images.length).toBe(3);
      expect(getImagePath(images[0])).toContain('functions/shop-email-icons/');
  
      // Build response
      const response = buildWelcomeSuccessResponse('Fashion Store');
      expect(response.shopName).toBe('Fashion Store');
    });
  });
