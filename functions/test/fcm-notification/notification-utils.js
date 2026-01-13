// functions/test/fcm-notification/notification-utils.js
//
// EXTRACTED PURE LOGIC from FCM notification cloud functions
// These functions are EXACT COPIES of logic from the notification functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source notification functions.

// ============================================================================
// NOTIFICATION TEMPLATES
// EXACT COPY from production code
// ============================================================================

const TEMPLATES = {
    en: {
      product_out_of_stock: {
        title: 'Out of Stock ⚠️',
        body: 'Your product is out of stock.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Shop Item Out of Stock ⚠️',
        body: 'A product is out of stock in your shop.',
      },
      boost_expired: {
        title: 'Boost Expired ⚠️',
        body: 'Your boost has expired.',
      },
      product_review_shop: {
        title: 'New Product Review ⭐',
        body: 'Your product "{productName}" received a new review',
      },
      product_review_user: {
        title: 'New Product Review ⭐',
        body: 'Your product "{productName}" received a new review',
      },
      seller_review_shop: {
        title: 'New Shop Review ⭐',
        body: 'Your shop received a new review',
      },
      seller_review_user: {
        title: 'New Seller Review ⭐',
        body: 'You received a new seller review',
      },
      product_sold_shop: {
        title: 'Shop Product Sold! 🎉',
        body: 'Your product "{productName}" was sold!',
      },
      product_sold_user: {
        title: 'Product Sold! 🎉',
        body: 'Your product "{productName}" was sold!',
      },
      shipment_update: {
        title: 'Shipment Status Updated! ✅',
        body: 'Your shipment status has been updated!',
      },
      campaign: {
        title: '🎉 New Campaign: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'New Product Question 💬',
        body: 'Someone asked a question about your product: {productName}',
      },
      shop_invitation: {
        title: 'Shop Invitation 🏪',
        body: 'You have been invited to join {shopName} as {role}',
      },
      ad_expired: {
        title: 'Ad Expired ⚠️',
        body: 'Your ad for {shopName} has expired.',
      },
      ad_approved: {
        title: 'Ad Approved! 🎉',
        body: 'Your ad for {shopName} has been approved. Click to proceed with payment.',
      },
      ad_rejected: {
        title: 'Ad Rejected ❌',
        body: 'Your ad for {shopName} was rejected. Reason: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'Refund Request Approved ✅',
        body: 'Your refund request for receipt #{receiptNo} has been approved.',
      },
      refund_request_rejected: {
        title: 'Refund Request Rejected ❌',
        body: 'Your refund request for receipt #{receiptNo} has been rejected.',
      },
      default: {
        title: 'New Notification',
        body: 'You have a new notification!',
      },
    },
  
    tr: {
      product_out_of_stock: {
        title: 'Ürün Stoğu Tükendi ⚠️',
        body: 'Ürününüz stokta kalmadı.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Mağaza Ürünü Stoğu Tükendi ⚠️',
        body: 'Mağanızdaki bir ürün stokta kalmadı.',
      },
      boost_expired: {
        title: 'Boost Süresi Doldu ⚠️',
        body: 'Öne çıkarılan ürünün süresi doldu.',
      },
      product_review_shop: {
        title: 'Yeni Ürün Değerlendirmesi ⭐',
        body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
      },
      product_review_user: {
        title: 'Yeni Ürün Değerlendirmesi ⭐',
        body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
      },
      seller_review_shop: {
        title: 'Yeni Mağaza Değerlendirmesi ⭐',
        body: 'Mağazanız yeni bir değerlendirme aldı',
      },
      seller_review_user: {
        title: 'Yeni Satıcı Değerlendirmesi ⭐',
        body: 'Yeni bir satıcı değerlendirmesi aldınız',
      },
      product_sold_shop: {
        title: 'Mağaza Ürünü Satıldı! 🎉',
        body: 'Ürününüz "{productName}" satıldı!',
      },
      product_sold_user: {
        title: 'Ürün Satıldı! 🎉',
        body: 'Ürününüz "{productName}" satıldı!',
      },
      shipment_update: {
        title: 'Gönderi Durumu Güncellendi! ✅',
        body: 'Gönderi durumunuz güncellendi!',
      },
      campaign: {
        title: '🎉 Yeni Kampanya: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'Yeni Ürün Sorusu 💬',
        body: 'Ürününüz hakkında soru soruldu: {productName}',
      },
      shop_invitation: {
        title: 'Mağaza Daveti 🏪',
        body: '{shopName} mağazasına {role} olarak katılmaya davet edildiniz',
      },
      ad_expired: {
        title: 'Reklam Süresi Doldu ⚠️',
        body: '{shopName} reklamınızın süresi doldu.',
      },
      ad_approved: {
        title: 'Reklam Onaylandı! 🎉',
        body: '{shopName} için reklamınız onaylandı. Ödeme yapmak için tıklayın.',
      },
      ad_rejected: {
        title: 'Reklam Reddedildi ❌',
        body: '{shopName} için reklamınız reddedildi. Neden: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'İade Talebi Onaylandı ✅',
        body: 'Fiş no #{receiptNo} için iade talebiniz onaylandı.',
      },
      refund_request_rejected: {
        title: 'İade Talebi Reddedildi ❌',
        body: 'Fiş no #{receiptNo} için iade talebiniz reddedildi.',
      },
      default: {
        title: 'Yeni Bildirim',
        body: 'Yeni bir bildiriminiz var!',
      },
    },
  
    ru: {
      product_out_of_stock: {
        title: 'Товар Распродан',
        body: 'Ваш продукт "{productName}" распродан.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Запасы Магазина Исчерпаны',
        body: 'Товар "{productName}" отсутствует в вашем магазине.',
      },
      boost_expired: {
        title: 'Срок Буста Истек',
        body: 'Время действия буста "{itemType}" истекло.',
      },
      product_review_shop: {
        title: 'Новый Отзыв о Продукте ⭐',
        body: 'Ваш продукт "{productName}" получил новый отзыв',
      },
      product_review_user: {
        title: 'Новый Отзыв о Продукте ⭐',
        body: 'Ваш продукт "{productName}" получил новый отзыв',
      },
      seller_review_shop: {
        title: 'Новый Отзыв о Магазине ⭐',
        body: 'Ваш магазин получил новый отзыв',
      },
      seller_review_user: {
        title: 'Новый Отзыв Продавца ⭐',
        body: 'Вы получили новый отзыв продавца',
      },
      product_sold_shop: {
        title: 'Товар Магазина Продан! 🎉',
        body: 'Ваш товар "{productName}" был продан!',
      },
      product_sold_user: {
        title: 'Продукт Продан! 🎉',
        body: 'Ваш продукт "{productName}" был продан!',
      },
      shipment_update: {
        title: 'Статус Доставки Обновлен!',
        body: 'Статус вашей доставки был обновлен!',
      },
      campaign: {
        title: '🎉 Новая Кампания: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'Новый Вопрос о Продукте 💬',
        body: 'Кто-то задал вопрос о вашем продукте: {productName}',
      },
      shop_invitation: {
        title: 'Приглашение в Магазин 🏪',
        body: 'Вас пригласили присоединиться к {shopName} как {role}',
      },
      ad_expired: {
        title: 'Срок Рекламы Истек ⚠️',
        body: 'Срок действия вашего объявления для {shopName} истек.',
      },
      ad_approved: {
        title: 'Реклама Одобрена! 🎉',
        body: 'Ваше объявление для {shopName} было одобрено. Нажмите, чтобы перейти к оплате.',
      },
      ad_rejected: {
        title: 'Реклама Отклонена ❌',
        body: 'Ваше объявление для {shopName} было отклонено. Причина: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'Запрос на Возврат Одобрен ✅',
        body: 'Ваш запрос на возврат для чека #{receiptNo} был одобрен.',
      },
      refund_request_rejected: {
        title: 'Запрос на Возврат Отклонен ❌',
        body: 'Ваш запрос на возврат для чека #{receiptNo} был отклонен.',
      },
      default: {
        title: 'Новое Уведомление',
        body: 'У вас новое уведомление!',
      },
    },
  };
  
  // ============================================================================
  // SUPPORTED LOCALES
  // ============================================================================
  
  const SUPPORTED_LOCALES = ['en', 'tr', 'ru'];
  const DEFAULT_LOCALE = 'en';
  
  // ============================================================================
  // NOTIFICATION TYPES
  // ============================================================================
  
  const NOTIFICATION_TYPES = [
    'product_out_of_stock',
    'product_out_of_stock_seller_panel',
    'boost_expired',
    'product_review_shop',
    'product_review_user',
    'seller_review_shop',
    'seller_review_user',
    'product_sold_shop',
    'product_sold_user',
    'shipment_update',
    'campaign',
    'product_question',
    'shop_invitation',
    'ad_expired',
    'ad_approved',
    'ad_rejected',
    'refund_request_approved',
    'refund_request_rejected',
    'default',
  ];
  
  // ============================================================================
  // PLACEHOLDER FIELDS
  // ============================================================================
  
  const PLACEHOLDER_FIELDS = [
    'productName',
    'itemType',
    'campaignName',
    'campaignDescription',
    'shopName',
    'role',
    'adTypeLabel',
    'rejectionReason',
    'receiptNo',
  ];
  
  // ============================================================================
  // FCM ERROR CODES FOR BAD TOKENS
  // ============================================================================
  
  const BAD_TOKEN_ERROR_CODES = [
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
  ];
  
  // ============================================================================
  // TEMPLATE FUNCTIONS
  // ============================================================================
  
 
  function getSupportedLocales() {
    return SUPPORTED_LOCALES;
  }
  

  function isValidLocale(locale) {
    return SUPPORTED_LOCALES.includes(locale);
  }
  

  function getLocaleSet(locale) {
    return TEMPLATES[locale] || TEMPLATES[DEFAULT_LOCALE];
  }

  function getTemplate(locale, type) {
    const localeSet = getLocaleSet(locale);
    return localeSet[type] || localeSet.default;
  }

  function getNotificationTypes() {
    return NOTIFICATION_TYPES;
  }
 
  function isValidNotificationType(type) {
    return NOTIFICATION_TYPES.includes(type);
  }
  
  // ============================================================================
  // TEMPLATE INTERPOLATION
  // ============================================================================
  

  function replacePlaceholder(text, placeholder, value) {
    if (!text || !value) return text;
    return text.replace(`{${placeholder}}`, value);
  }
  
 
  function interpolateTemplate(template, data) {
    let { title, body } = template;
  
    if (!data) {
      return { title, body };
    }
  
    // Replace all known placeholders
    PLACEHOLDER_FIELDS.forEach((field) => {
      if (data[field]) {
        title = replacePlaceholder(title, field, data[field]);
        body = replacePlaceholder(body, field, data[field]);
      }
    });
  
    return { title, body };
  }

  function getNotificationContent(locale, type, data) {
    const template = getTemplate(locale, type);
    return interpolateTemplate(template, data);
  }
  
  // ============================================================================
  // DEEP-LINK ROUTING
  // EXACT COPY from production code
  // ============================================================================
  
  /**
   * Default notification route
   */
  const DEFAULT_ROUTE = '/notifications';
  

  function getRouteForType(type, data = {}) {
    switch (type) {
      case 'product_out_of_stock':
        return '/myproducts';
  
      case 'product_out_of_stock_seller_panel':
        if (data.shopId) {
          return `/seller-panel?shopId=${data.shopId}&tab=2`;
        }
        return DEFAULT_ROUTE;
  
      case 'boost_expired':
        return DEFAULT_ROUTE;
  
      case 'product_review_shop':
        if (data.shopId) {
          return `/seller_panel_reviews/${data.shopId}`;
        }
        return DEFAULT_ROUTE;
  
      case 'product_review_user':
        if (data.productId) {
          return `/product/${data.productId}`;
        }
        return DEFAULT_ROUTE;
  
      case 'seller_review_shop':
        if (data.shopId) {
          return `/seller_panel_reviews/${data.shopId}`;
        }
        return DEFAULT_ROUTE;
  
      case 'seller_review_user':
        if (data.sellerId) {
          return `/seller_reviews/${data.sellerId}`;
        }
        return DEFAULT_ROUTE;
  
      case 'product_sold_shop':
        if (data.shopId) {
          return `/seller-panel?shopId=${data.shopId}&tab=3`;
        }
        return DEFAULT_ROUTE;
  
      case 'product_sold_user':
        return '/my_orders?tab=1';
  
      case 'shop_invitation':
        return DEFAULT_ROUTE;
  
      case 'campaign':
        return '/seller-panel?tab=0';
  
      case 'product_question':
        if (data.isShopProduct && data.shopId) {
          return `/seller_panel_product_questions/${data.shopId}`;
        }
        return '/user-product-questions';
  
      case 'ad_approved':
        return DEFAULT_ROUTE;
  
      case 'ad_rejected':
        return DEFAULT_ROUTE;
  
      case 'ad_expired':
        if (data.shopId) {
          return `/seller-panel?shopId=${data.shopId}&tab=5`;
        }
        return DEFAULT_ROUTE;
  
      case 'refund_request':
        return DEFAULT_ROUTE;
  
      case 'refund_request_approved':
        return DEFAULT_ROUTE;
  
      case 'refund_request_rejected':
        return DEFAULT_ROUTE;
  
      default:
        return DEFAULT_ROUTE;
    }
  }
  
  // ============================================================================
  // FCM TOKEN HANDLING
  // ============================================================================
  
 
  function extractFcmTokens(userData) {
    if (!userData) return [];
  
    const { fcmTokens } = userData;
    if (!fcmTokens || typeof fcmTokens !== 'object') {
      return [];
    }
  
    return Object.keys(fcmTokens);
  }
 
  function getUserLocale(userData) {
    return userData?.languageCode || DEFAULT_LOCALE;
  }
  
  // ============================================================================
  // DATA PAYLOAD BUILDING
  // ============================================================================
  

  function buildDataPayload(notificationId, route, notificationData) {
    const dataPayload = {
      notificationId: String(notificationId),
      route,
    };
  
    if (notificationData) {
      Object.entries(notificationData).forEach(([key, value]) => {
        dataPayload[key] = typeof value === 'string' ? value : JSON.stringify(value);
      });
    }
  
    return dataPayload;
  }

  function serializeForPayload(value) {
    return typeof value === 'string' ? value : JSON.stringify(value);
  }
  
  // ============================================================================
  // BAD TOKEN EXTRACTION
  // ============================================================================
 
  function isBadTokenError(errorCode) {
    return BAD_TOKEN_ERROR_CODES.includes(errorCode);
  }
 
  function extractBadTokens(responses, tokens) {
    const badTokens = [];
  
    responses.forEach((resp, i) => {
      if (resp.error) {
        const code = resp.error.code;
        if (isBadTokenError(code)) {
          badTokens.push(tokens[i]);
        }
      }
    });
  
    return badTokens;
  }

  function buildTokenDeletionUpdates(badTokens) {
    const updates = {};
    badTokens.forEach((token) => {
      updates[`fcmTokens.${token}`] = null; // Will use FieldValue.delete() in production
    });
    return updates;
  }
  
  // ============================================================================
  // FCM MESSAGE BUILDING
  // ============================================================================

  function buildFcmMessage(tokens, title, body, data) {
    return {
      tokens,
      notification: { title, body },
      data,
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default', badge: 1 } },
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel',
          sound: 'default',
          icon: 'ic_launcher',
        },
      },
    };
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Constants
    TEMPLATES,
    SUPPORTED_LOCALES,
    DEFAULT_LOCALE,
    NOTIFICATION_TYPES,
    PLACEHOLDER_FIELDS,
    BAD_TOKEN_ERROR_CODES,
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
  };
