// functions/test/fcm-notification/notification-utils.test.js
//
// Unit tests for FCM notification utility functions
// Tests the EXACT logic from FCM notification cloud functions
//
// Run: npx jest test/fcm-notification/notification-utils.test.js

const {
    // Constants
    TEMPLATES,
    SUPPORTED_LOCALES,
    DEFAULT_LOCALE,

    DEFAULT_ROUTE,
  
    // Template functions
    getSupportedLocales,
    isValidLocale,
    getLocaleSet,
    getTemplate,
    getNotificationTypes,
    isValidNotificationType,
  
    // Interpolation
    replacePlaceholder,
    interpolateTemplate,
    getNotificationContent,
  
    // Routing
    getRouteForType,
  
    // FCM tokens
    extractFcmTokens,
    getUserLocale,
  
    // Data payload
    buildDataPayload,
    serializeForPayload,
  
    // Bad tokens
    isBadTokenError,
    extractBadTokens,
    buildTokenDeletionUpdates,
  
    // FCM message
    buildFcmMessage,
  } = require('./notification-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('SUPPORTED_LOCALES contains en, tr, ru', () => {
      expect(SUPPORTED_LOCALES).toContain('en');
      expect(SUPPORTED_LOCALES).toContain('tr');
      expect(SUPPORTED_LOCALES).toContain('ru');
    });
  
    test('DEFAULT_LOCALE is en', () => {
      expect(DEFAULT_LOCALE).toBe('en');
    });
  
    test('DEFAULT_ROUTE is /notifications', () => {
      expect(DEFAULT_ROUTE).toBe('/notifications');
    });
  
    test('TEMPLATES has all supported locales', () => {
      SUPPORTED_LOCALES.forEach((locale) => {
        expect(TEMPLATES[locale]).toBeDefined();
      });
    });
  
    test('each locale has default template', () => {
      SUPPORTED_LOCALES.forEach((locale) => {
        expect(TEMPLATES[locale].default).toBeDefined();
        expect(TEMPLATES[locale].default.title).toBeDefined();
        expect(TEMPLATES[locale].default.body).toBeDefined();
      });
    });
  });
  
  // ============================================================================
  // TEMPLATE FUNCTION TESTS
  // ============================================================================
  describe('getSupportedLocales', () => {
    test('returns supported locales', () => {
      const locales = getSupportedLocales();
      expect(locales).toEqual(['en', 'tr', 'ru']);
    });
  });
  
  describe('isValidLocale', () => {
    test('returns true for supported locales', () => {
      expect(isValidLocale('en')).toBe(true);
      expect(isValidLocale('tr')).toBe(true);
      expect(isValidLocale('ru')).toBe(true);
    });
  
    test('returns false for unsupported locales', () => {
      expect(isValidLocale('de')).toBe(false);
      expect(isValidLocale('fr')).toBe(false);
      expect(isValidLocale('')).toBe(false);
    });
  });
  
  describe('getLocaleSet', () => {
    test('returns correct locale set', () => {
      const enSet = getLocaleSet('en');
      expect(enSet.default.title).toBe('New Notification');
  
      const trSet = getLocaleSet('tr');
      expect(trSet.default.title).toBe('Yeni Bildirim');
  
      const ruSet = getLocaleSet('ru');
      expect(ruSet.default.title).toBe('Новое Уведомление');
    });
  
    test('falls back to English for unknown locale', () => {
      const set = getLocaleSet('unknown');
      expect(set.default.title).toBe('New Notification');
    });
  });
  
  describe('getTemplate', () => {
    test('returns correct template for type', () => {
      const template = getTemplate('en', 'product_sold_shop');
      expect(template.title).toBe('Shop Product Sold! 🎉');
    });
  
    test('returns default template for unknown type', () => {
      const template = getTemplate('en', 'unknown_type');
      expect(template.title).toBe('New Notification');
    });
  
    test('returns localized template', () => {
      const enTemplate = getTemplate('en', 'boost_expired');
      const trTemplate = getTemplate('tr', 'boost_expired');
  
      expect(enTemplate.title).toBe('Boost Expired ⚠️');
      expect(trTemplate.title).toBe('Boost Süresi Doldu ⚠️');
    });
  });
  
  describe('getNotificationTypes', () => {
    test('returns all notification types', () => {
      const types = getNotificationTypes();
      expect(types).toContain('product_out_of_stock');
      expect(types).toContain('product_sold_shop');
      expect(types).toContain('ad_approved');
      expect(types).toContain('default');
    });
  });
  
  describe('isValidNotificationType', () => {
    test('returns true for valid types', () => {
      expect(isValidNotificationType('product_sold_shop')).toBe(true);
      expect(isValidNotificationType('ad_approved')).toBe(true);
    });
  
    test('returns false for invalid types', () => {
      expect(isValidNotificationType('invalid_type')).toBe(false);
    });
  });
  
  // ============================================================================
  // INTERPOLATION TESTS
  // ============================================================================
  describe('replacePlaceholder', () => {
    test('replaces placeholder in text', () => {
      const result = replacePlaceholder('Hello {name}!', 'name', 'John');
      expect(result).toBe('Hello John!');
    });
  
    test('returns original if no value', () => {
      const result = replacePlaceholder('Hello {name}!', 'name', null);
      expect(result).toBe('Hello {name}!');
    });
  
    test('returns original if no text', () => {
      const result = replacePlaceholder(null, 'name', 'John');
      expect(result).toBe(null);
    });
  });
  
  describe('interpolateTemplate', () => {
    test('interpolates productName', () => {
      const template = {
        title: 'Product Sold',
        body: 'Your product "{productName}" was sold!',
      };
      const result = interpolateTemplate(template, { productName: 'iPhone 15' });
      expect(result.body).toBe('Your product "iPhone 15" was sold!');
    });
  
    test('interpolates multiple placeholders', () => {
      const template = {
        title: 'Shop Invitation',
        body: 'Join {shopName} as {role}',
      };
      const result = interpolateTemplate(template, {
        shopName: 'Fashion Store',
        role: 'editor',
      });
      expect(result.body).toBe('Join Fashion Store as editor');
    });
  
    test('handles missing data', () => {
      const template = {
        title: 'Hello',
        body: 'World',
      };
      const result = interpolateTemplate(template, null);
      expect(result.title).toBe('Hello');
      expect(result.body).toBe('World');
    });
  
    test('interpolates campaignName and campaignDescription', () => {
      const template = {
        title: '🎉 New Campaign: {campaignName}',
        body: '{campaignDescription}',
      };
      const result = interpolateTemplate(template, {
        campaignName: 'Summer Sale',
        campaignDescription: '50% off everything!',
      });
      expect(result.title).toBe('🎉 New Campaign: Summer Sale');
      expect(result.body).toBe('50% off everything!');
    });
  
    test('interpolates rejectionReason', () => {
      const template = {
        title: 'Ad Rejected',
        body: 'Reason: {rejectionReason}',
      };
      const result = interpolateTemplate(template, {
        rejectionReason: 'Image quality too low',
      });
      expect(result.body).toBe('Reason: Image quality too low');
    });
  
    test('interpolates receiptNo', () => {
      const template = {
        title: 'Refund Approved',
        body: 'Receipt #{receiptNo}',
      };
      const result = interpolateTemplate(template, { receiptNo: '12345' });
      expect(result.body).toBe('Receipt #12345');
    });
  });
  
  describe('getNotificationContent', () => {
    test('returns fully interpolated content', () => {
      const result = getNotificationContent('en', 'product_sold_shop', {
        productName: 'Test Product',
      });
      expect(result.title).toBe('Shop Product Sold! 🎉');
      expect(result.body).toBe('Your product "Test Product" was sold!');
    });
  
    test('uses correct locale', () => {
      const result = getNotificationContent('tr', 'product_sold_shop', {
        productName: 'Test Ürün',
      });
      expect(result.title).toBe('Mağaza Ürünü Satıldı! 🎉');
      expect(result.body).toBe('Ürününüz "Test Ürün" satıldı!');
    });
  });
  
  // ============================================================================
  // ROUTING TESTS
  // ============================================================================
  describe('getRouteForType', () => {
    test('product_out_of_stock returns /myproducts', () => {
      expect(getRouteForType('product_out_of_stock')).toBe('/myproducts');
    });
  
    test('product_out_of_stock_seller_panel with shopId', () => {
      const route = getRouteForType('product_out_of_stock_seller_panel', { shopId: 'shop123' });
      expect(route).toBe('/seller-panel?shopId=shop123&tab=2');
    });
  
    test('product_out_of_stock_seller_panel without shopId', () => {
      const route = getRouteForType('product_out_of_stock_seller_panel', {});
      expect(route).toBe('/notifications');
    });
  
    test('boost_expired returns /notifications', () => {
      expect(getRouteForType('boost_expired')).toBe('/notifications');
    });
  
    test('product_review_shop with shopId', () => {
      const route = getRouteForType('product_review_shop', { shopId: 'shop123' });
      expect(route).toBe('/seller_panel_reviews/shop123');
    });
  
    test('product_review_user with productId', () => {
      const route = getRouteForType('product_review_user', { productId: 'prod123' });
      expect(route).toBe('/product/prod123');
    });
  
    test('seller_review_shop with shopId', () => {
      const route = getRouteForType('seller_review_shop', { shopId: 'shop123' });
      expect(route).toBe('/seller_panel_reviews/shop123');
    });
  
    test('seller_review_user with sellerId', () => {
      const route = getRouteForType('seller_review_user', { sellerId: 'seller123' });
      expect(route).toBe('/seller_reviews/seller123');
    });
  
    test('product_sold_shop with shopId', () => {
      const route = getRouteForType('product_sold_shop', { shopId: 'shop123' });
      expect(route).toBe('/seller-panel?shopId=shop123&tab=3');
    });
  
    test('product_sold_user returns /my_orders?tab=1', () => {
      expect(getRouteForType('product_sold_user')).toBe('/my_orders?tab=1');
    });
  
    test('shop_invitation returns /notifications', () => {
      expect(getRouteForType('shop_invitation')).toBe('/notifications');
    });
  
    test('campaign returns /seller-panel?tab=0', () => {
      expect(getRouteForType('campaign')).toBe('/seller-panel?tab=0');
    });
  
    test('product_question for shop product', () => {
      const route = getRouteForType('product_question', { isShopProduct: true, shopId: 'shop123' });
      expect(route).toBe('/seller_panel_product_questions/shop123');
    });
  
    test('product_question for user product', () => {
      const route = getRouteForType('product_question', { isShopProduct: false });
      expect(route).toBe('/user-product-questions');
    });
  
    test('ad_approved returns /notifications', () => {
      expect(getRouteForType('ad_approved')).toBe('/notifications');
    });
  
    test('ad_rejected returns /notifications', () => {
      expect(getRouteForType('ad_rejected')).toBe('/notifications');
    });
  
    test('ad_expired with shopId', () => {
      const route = getRouteForType('ad_expired', { shopId: 'shop123' });
      expect(route).toBe('/seller-panel?shopId=shop123&tab=5');
    });
  
    test('unknown type returns default route', () => {
      expect(getRouteForType('unknown_type')).toBe('/notifications');
    });
  
    test('handles missing data gracefully', () => {
      expect(getRouteForType('product_review_shop')).toBe('/notifications');
      expect(getRouteForType('product_review_shop', {})).toBe('/notifications');
    });
  });
  
  // ============================================================================
  // FCM TOKEN TESTS
  // ============================================================================
  describe('extractFcmTokens', () => {
    test('extracts token keys from object', () => {
      const userData = {
        fcmTokens: {
          'token1': { createdAt: Date.now() },
          'token2': { createdAt: Date.now() },
        },
      };
      const tokens = extractFcmTokens(userData);
      expect(tokens).toEqual(['token1', 'token2']);
    });
  
    test('returns empty array for null userData', () => {
      expect(extractFcmTokens(null)).toEqual([]);
    });
  
    test('returns empty array for missing fcmTokens', () => {
      expect(extractFcmTokens({})).toEqual([]);
    });
  
    test('returns empty array for non-object fcmTokens', () => {
      expect(extractFcmTokens({ fcmTokens: 'invalid' })).toEqual([]);
      expect(extractFcmTokens({ fcmTokens: null })).toEqual([]);
    });
  });
  
  describe('getUserLocale', () => {
    test('returns user languageCode', () => {
      expect(getUserLocale({ languageCode: 'tr' })).toBe('tr');
    });
  
    test('returns default for missing languageCode', () => {
      expect(getUserLocale({})).toBe('en');
    });
  
    test('returns default for null userData', () => {
      expect(getUserLocale(null)).toBe('en');
    });
  });
  
  // ============================================================================
  // DATA PAYLOAD TESTS
  // ============================================================================
  describe('buildDataPayload', () => {
    test('builds payload with notificationId and route', () => {
      const payload = buildDataPayload('notif123', '/myproducts', {});
      expect(payload.notificationId).toBe('notif123');
      expect(payload.route).toBe('/myproducts');
    });
  
    test('includes notification data as strings', () => {
      const payload = buildDataPayload('notif123', '/route', {
        productName: 'iPhone',
        count: 5,
        nested: { key: 'value' },
      });
      expect(payload.productName).toBe('iPhone');
      expect(payload.count).toBe('5');
      expect(payload.nested).toBe('{"key":"value"}');
    });
  
    test('handles null notification data', () => {
      const payload = buildDataPayload('notif123', '/route', null);
      expect(payload.notificationId).toBe('notif123');
      expect(payload.route).toBe('/route');
    });
  });
  
  describe('serializeForPayload', () => {
    test('returns string as-is', () => {
      expect(serializeForPayload('hello')).toBe('hello');
    });
  
    test('stringifies non-string values', () => {
      expect(serializeForPayload(123)).toBe('123');
      expect(serializeForPayload({ a: 1 })).toBe('{"a":1}');
      expect(serializeForPayload(true)).toBe('true');
    });
  });
  
  // ============================================================================
  // BAD TOKEN TESTS
  // ============================================================================
  describe('isBadTokenError', () => {
    test('returns true for invalid-registration-token', () => {
      expect(isBadTokenError('messaging/invalid-registration-token')).toBe(true);
    });
  
    test('returns true for registration-token-not-registered', () => {
      expect(isBadTokenError('messaging/registration-token-not-registered')).toBe(true);
    });
  
    test('returns false for other errors', () => {
      expect(isBadTokenError('messaging/internal-error')).toBe(false);
      expect(isBadTokenError('unknown')).toBe(false);
    });
  });
  
  describe('extractBadTokens', () => {
    test('extracts tokens with bad token errors', () => {
      const responses = [
        { success: true },
        { error: { code: 'messaging/invalid-registration-token' } },
        { success: true },
        { error: { code: 'messaging/registration-token-not-registered' } },
        { error: { code: 'messaging/internal-error' } },
      ];
      const tokens = ['t1', 't2', 't3', 't4', 't5'];
  
      const badTokens = extractBadTokens(responses, tokens);
      expect(badTokens).toEqual(['t2', 't4']);
    });
  
    test('returns empty array for all successful', () => {
      const responses = [{ success: true }, { success: true }];
      const tokens = ['t1', 't2'];
      expect(extractBadTokens(responses, tokens)).toEqual([]);
    });
  });
  
  describe('buildTokenDeletionUpdates', () => {
    test('builds update object for tokens', () => {
      const updates = buildTokenDeletionUpdates(['token1', 'token2']);
      expect(updates['fcmTokens.token1']).toBe(null);
      expect(updates['fcmTokens.token2']).toBe(null);
    });
  
    test('handles empty array', () => {
      const updates = buildTokenDeletionUpdates([]);
      expect(Object.keys(updates)).toHaveLength(0);
    });
  });
  
  // ============================================================================
  // FCM MESSAGE TESTS
  // ============================================================================
  describe('buildFcmMessage', () => {
    test('builds complete FCM message', () => {
      const message = buildFcmMessage(
        ['token1', 'token2'],
        'Test Title',
        'Test Body',
        { key: 'value' }
      );
  
      expect(message.tokens).toEqual(['token1', 'token2']);
      expect(message.notification.title).toBe('Test Title');
      expect(message.notification.body).toBe('Test Body');
      expect(message.data.key).toBe('value');
    });
  
    test('includes APNS config', () => {
      const message = buildFcmMessage(['t1'], 'Title', 'Body', {});
      expect(message.apns.headers['apns-priority']).toBe('10');
      expect(message.apns.payload.aps.sound).toBe('default');
      expect(message.apns.payload.aps.badge).toBe(1);
    });
  
    test('includes Android config', () => {
      const message = buildFcmMessage(['t1'], 'Title', 'Body', {});
      expect(message.android.priority).toBe('high');
      expect(message.android.notification.channelId).toBe('high_importance_channel');
      expect(message.android.notification.sound).toBe('default');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete notification flow - product sold (English)', () => {
      const userData = {
        languageCode: 'en',
        fcmTokens: { 'device_token_1': true, 'device_token_2': true },
      };
      const notificationData = {
        type: 'product_sold_shop',
        productName: 'Vintage Jacket',
        shopId: 'shop456',
      };
  
      // 1. Extract tokens
      const tokens = extractFcmTokens(userData);
      expect(tokens).toHaveLength(2);
  
      // 2. Get locale
      const locale = getUserLocale(userData);
      expect(locale).toBe('en');
  
      // 3. Get content
      const { title, body } = getNotificationContent(locale, notificationData.type, notificationData);
      expect(title).toBe('Shop Product Sold! 🎉');
      expect(body).toBe('Your product "Vintage Jacket" was sold!');
  
      // 4. Get route
      const route = getRouteForType(notificationData.type, notificationData);
      expect(route).toBe('/seller-panel?shopId=shop456&tab=3');
  
      // 5. Build payload
      const payload = buildDataPayload('notif123', route, notificationData);
      expect(payload.route).toBe('/seller-panel?shopId=shop456&tab=3');
  
      // 6. Build message
      const message = buildFcmMessage(tokens, title, body, payload);
      expect(message.tokens).toHaveLength(2);
    });
  
    test('complete notification flow - ad rejected (Turkish)', () => {
      const userData = {
        languageCode: 'tr',
        fcmTokens: { 'turkish_device': true },
      };
      const notificationData = {
        type: 'ad_rejected',
        shopName: 'Moda Dükkanı',
        rejectionReason: 'Resim kalitesi düşük',
      };
  
      const locale = getUserLocale(userData);
      const { title, body } = getNotificationContent(locale, notificationData.type, notificationData);
  
      expect(title).toBe('Reklam Reddedildi ❌');
      expect(body).toBe('Moda Dükkanı için reklamınız reddedildi. Neden: Resim kalitesi düşük');
    });
  
    test('complete notification flow - shop invitation (Russian)', () => {
      const userData = {
        languageCode: 'ru',
        fcmTokens: { 'russian_device': true },
      };
      const notificationData = {
        type: 'shop_invitation',
        shopName: 'Модный Магазин',
        role: 'редактор',
      };
  
      const locale = getUserLocale(userData);
      const { title, body } = getNotificationContent(locale, notificationData.type, notificationData);
  
      expect(title).toBe('Приглашение в Магазин 🏪');
      expect(body).toBe('Вас пригласили присоединиться к Модный Магазин как редактор');
    });
  
    test('handles FCM response with bad tokens', () => {
      const tokens = ['good_token', 'invalid_token', 'unregistered_token'];
      const responses = [
        { success: true },
        { error: { code: 'messaging/invalid-registration-token' } },
        { error: { code: 'messaging/registration-token-not-registered' } },
      ];
  
      const badTokens = extractBadTokens(responses, tokens);
      expect(badTokens).toEqual(['invalid_token', 'unregistered_token']);
  
      const updates = buildTokenDeletionUpdates(badTokens);
      expect(Object.keys(updates)).toHaveLength(2);
    });
  
    test('fallback to default for unknown notification type', () => {
      const userData = { languageCode: 'en' };
      const notificationData = { type: 'completely_unknown_type' };
  
      const locale = getUserLocale(userData);
      const { title, body } = getNotificationContent(locale, notificationData.type, notificationData);
      const route = getRouteForType(notificationData.type, notificationData);
  
      expect(title).toBe('New Notification');
      expect(body).toBe('You have a new notification!');
      expect(route).toBe('/notifications');
    });
  
    test('all notification types have templates in all locales', () => {
      const types = getNotificationTypes();
      const locales = getSupportedLocales();
  
      locales.forEach((locale) => {
        types.forEach((type) => {
          const template = getTemplate(locale, type);
          expect(template.title).toBeDefined();
          expect(template.body).toBeDefined();
        });
      });
    });
  });
