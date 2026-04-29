// functions/test/send-emails/send-email-utils.js
//
// EXTRACTED PURE LOGIC from email sending cloud functions
// These functions are EXACT COPIES of logic from the email functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source email functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const SUPPORTED_LANGUAGES = ['en', 'tr', 'ru'];
const DEFAULT_LANGUAGE = 'en';
const PDF_URL_EXPIRY_DAYS = 7;
const WELCOME_IMAGE_EXPIRY_DAYS = 30;

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateReceiptEmailInput(data) {
  const errors = [];

  if (!data.receiptId) {
    errors.push({ field: 'receiptId', message: 'Receipt ID is required' });
  }

  if (!data.orderId) {
    errors.push({ field: 'orderId', message: 'Order ID is required' });
  }

  if (!data.email) {
    errors.push({ field: 'email', message: 'Email is required' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, message: 'Missing required fields' };
  }

  return { isValid: true };
}

function validateReportEmailInput(data) {
  const errors = [];

  if (!data.reportId) {
    errors.push({ field: 'reportId', message: 'Report ID is required' });
  }

  if (!data.shopId) {
    errors.push({ field: 'shopId', message: 'Shop ID is required' });
  }

  if (!data.email) {
    errors.push({ field: 'email', message: 'Email is required' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, message: 'Missing required fields' };
  }

  return { isValid: true };
}

function validateShopWelcomeInput(data) {
  const errors = [];

  if (!data.shopId) {
    errors.push({ field: 'shopId', message: 'Shop ID is required' });
  }

  if (!data.email) {
    errors.push({ field: 'email', message: 'Email is required' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, message: 'Missing required fields: shopId and email' };
  }

  return { isValid: true };
}

// ============================================================================
// ID FORMATTING
// ============================================================================

function formatIdShort(id, length = 8) {
  if (!id || typeof id !== 'string') return '';
  return id.substring(0, length).toUpperCase();
}

function formatOrderIdShort(orderId) {
  return formatIdShort(orderId, 8);
}

function formatReceiptIdShort(receiptId) {
  return formatIdShort(receiptId, 8);
}

function formatReportIdShort(reportId) {
  return formatIdShort(reportId, 8);
}

// ============================================================================
// DATE FORMATTING
// ============================================================================

function getLocaleCode(languageCode) {
  const localeMap = {
    en: 'en-US',
    tr: 'tr-TR',
    ru: 'ru-RU',
  };
  return localeMap[languageCode] || localeMap[DEFAULT_LANGUAGE];
}

function formatDateForLocale(date, languageCode) {
  if (!date) return new Date().toLocaleDateString();

  const dateObj = date instanceof Date ? date : (date.toDate ? date.toDate() : new Date(date));
  const locale = getLocaleCode(languageCode);

  return dateObj.toLocaleDateString(locale, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

function formatDateRange(startDate, endDate) {
  if (!startDate || !endDate) return '';

  const start = startDate instanceof Date ? startDate : (startDate.toDate ? startDate.toDate() : new Date(startDate));
  const end = endDate instanceof Date ? endDate : (endDate.toDate ? endDate.toDate() : new Date(endDate));

  return `${start.toLocaleDateString()} - ${end.toLocaleDateString()}`;
}

// ============================================================================
// LOCALIZED CONTENT - RECEIPT EMAIL
// ============================================================================

const RECEIPT_EMAIL_CONTENT = {
  en: {
    greeting: 'Hello',
    message: 'thank you for your order!',
    orderLabel: 'Order ID',
    receiptLabel: 'Receipt ID',
    dateLabel: 'Date',
    totalLabel: 'Total Amount',
    subject: 'Your Receipt',
    downloadButton: 'Download Receipt PDF',
    downloadHint: 'Save this receipt for your records',
    footer: 'Thank you for shopping with Nar24!',
    rights: 'All rights reserved.',
    tagline: 'Your Premium Shopping Destination',
    successTitle: 'Payment Successful!',
    orderDetailsTitle: 'Order Information',
    needHelp: 'Need help with your order?',
    contactSupport: 'Contact Support',
  },
  tr: {
    greeting: 'Merhaba',
    message: 'siparişiniz için teşekkür ederiz!',
    orderLabel: 'Sipariş No',
    receiptLabel: 'Fatura No',
    dateLabel: 'Tarih',
    totalLabel: 'Toplam Tutar',
    subject: 'Faturanız',
    downloadButton: 'Faturayı PDF Olarak İndir',
    downloadHint: 'Bu faturayı kayıtlarınız için saklayın',
    footer: 'Nar24\'ten alışveriş yaptığınız için teşekkür ederiz!',
    rights: 'Tüm hakları saklıdır.',
    tagline: 'Premium Alışveriş Deneyiminiz',
    successTitle: 'Ödeme Başarılı!',
    orderDetailsTitle: 'Sipariş Bilgileri',
    needHelp: 'Siparişinizle ilgili yardıma mı ihtiyacınız var?',
    contactSupport: 'Destek ile İletişime Geç',
  },
  ru: {
    greeting: 'Здравствуйте',
    message: 'спасибо за ваш заказ!',
    orderLabel: 'Номер заказа',
    receiptLabel: 'Номер чека',
    dateLabel: 'Дата',
    totalLabel: 'Итого',
    subject: 'Ваш чек',
    downloadButton: 'Скачать чек в PDF',
    downloadHint: 'Сохраните этот чек для ваших записей',
    footer: 'Спасибо за покупки в Nar24!',
    rights: 'Все права защищены.',
    tagline: 'Ваш премиум шоппинг',
    successTitle: 'Оплата прошла успешно!',
    orderDetailsTitle: 'Информация о заказе',
    needHelp: 'Нужна помощь с заказом?',
    contactSupport: 'Связаться с поддержкой',
  },
};

function getLocalizedContent(languageCode) {
  return RECEIPT_EMAIL_CONTENT[languageCode] || RECEIPT_EMAIL_CONTENT[DEFAULT_LANGUAGE];
}

// ============================================================================
// LOCALIZED CONTENT - REPORT EMAIL
// ============================================================================

const REPORT_EMAIL_CONTENT = {
  en: {
    greeting: 'Hello',
    message: 'your report is ready for download.',
    reportReady: 'Report Ready!',
    businessReports: 'Business Reports',
    reportDetails: 'Report Details',
    reportName: 'Report Name',
    reportId: 'Report ID',
    shopName: 'Shop Name',
    dateRange: 'Date Range',
    generatedOn: 'Generated On',
    includedData: 'Included Data',
    products: 'Products',
    orders: 'Orders',
    boostHistory: 'Boost History',
    subject: 'Your Business Report',
    downloadButton: 'Download Report',
    downloadHint: 'Report available for 7 days',
    needHelp: 'Need help with your report?',
    contactSupport: 'Contact Support',
    footer: 'Thank you for using Nar24 Business!',
    rights: 'All rights reserved.',
  },
  tr: {
    greeting: 'Merhaba',
    message: 'raporunuz indirilmeye hazır.',
    reportReady: 'Rapor Hazır!',
    businessReports: 'İş Raporları',
    reportDetails: 'Rapor Detayları',
    reportName: 'Rapor Adı',
    reportId: 'Rapor No',
    shopName: 'Mağaza Adı',
    dateRange: 'Tarih Aralığı',
    generatedOn: 'Oluşturulma Tarihi',
    includedData: 'Dahil Edilen Veriler',
    products: 'Ürünler',
    orders: 'Siparişler',
    boostHistory: 'Boost Geçmişi',
    subject: 'İş Raporunuz',
    downloadButton: 'Raporu İndir',
    downloadHint: 'Rapor 7 gün boyunca geçerli',
    needHelp: 'Raporunuzla ilgili yardıma mı ihtiyacınız var?',
    contactSupport: 'Destek ile İletişime Geç',
    footer: 'Nar24 İş\'i kullandığınız için teşekkür ederiz!',
    rights: 'Tüm hakları saklıdır.',
  },
  ru: {
    greeting: 'Здравствуйте',
    message: 'ваш отчет готов к загрузке.',
    reportReady: 'Отчет готов!',
    businessReports: 'Бизнес-отчеты',
    reportDetails: 'Детали отчета',
    reportName: 'Название отчета',
    reportId: 'Номер отчета',
    shopName: 'Название магазина',
    dateRange: 'Период',
    generatedOn: 'Дата создания',
    includedData: 'Включенные данные',
    products: 'Товары',
    orders: 'Заказы',
    boostHistory: 'История продвижения',
    subject: 'Ваш бизнес-отчет',
    downloadButton: 'Скачать отчет',
    downloadHint: 'Отчет доступен 7 дней',
    needHelp: 'Нужна помощь с отчетом?',
    contactSupport: 'Связаться с поддержкой',
    footer: 'Спасибо за использование Nar24 Business!',
    rights: 'Все права защищены.',
  },
};

function getReportLocalizedContent(languageCode) {
  return REPORT_EMAIL_CONTENT[languageCode] || REPORT_EMAIL_CONTENT[DEFAULT_LANGUAGE];
}

// ============================================================================
// FILE PATHS
// ============================================================================

function getReceiptFilePath(orderId, existingFilePath = null) {
  if (existingFilePath) return existingFilePath;
  return `receipts/${orderId}.pdf`;
}

function getReportFilePath(shopId, reportId) {
  return `reports/${shopId}/${reportId}.pdf`;
}

function getReportSearchPrefix(shopId, reportId) {
  return `reports/${shopId}/${reportId}`;
}

// ============================================================================
// URL EXPIRY CALCULATION
// ============================================================================

function calculatePdfUrlExpiry(nowMs = Date.now()) {
  return nowMs + PDF_URL_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
}

function calculateWelcomeImageExpiry(nowMs = Date.now()) {
  return nowMs + WELCOME_IMAGE_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
}

function getExpiryDays(type) {
  if (type === 'welcome_image') return WELCOME_IMAGE_EXPIRY_DAYS;
  return PDF_URL_EXPIRY_DAYS;
}

// ============================================================================
// MAIL DOCUMENT BUILDING
// ============================================================================

function buildReceiptMailDocument(email, orderIdShort, content, pdfUrl = null) {
  return {
    to: [email],
    message: {
      subject: `✅ ${content.subject} #${orderIdShort} - Nar24`,
    },
    template: {
      name: 'receipt',
      data: {
        type: 'order_receipt',
      },
    },
  };
}

function buildReportMailDocument(email, reportName, content) {
  return {
    to: [email],
    message: {
      subject: `📊 ${content.subject}: ${reportName || 'Report'} - Nar24`,
    },
    template: {
      name: 'report',
      data: {
        type: 'shop_report',
      },
    },
  };
}

function buildShopWelcomeMailDocument(email, shopId, shopName) {
  return {
    to: [email],
    message: {
      subject: '🎉 Tebrikler! Nar24\'te Yetkili Satıcı Oldunuz - Mağazanız Onaylandı',
    },
    template: {
      name: 'shop_welcome',
      data: {
        shopId,
        shopName,
        type: 'shop_approval',
      },
    },
  };
}

// ============================================================================
// PRICE FORMATTING
// ============================================================================

function formatPrice(amount, currency = 'TL') {
  if (amount === null || amount === undefined) return `0 ${currency}`;
  return `${amount.toFixed(2)} ${currency}`;
}

// ============================================================================
// OWNERSHIP VERIFICATION
// ============================================================================

function canAccessReceipt(receiptData, uid, isShopReceipt, shopId) {
  if (isShopReceipt && shopId) {
    return true;
  }
  return receiptData.buyerId === uid;
}

function canAccessReport(shopData, uid) {
  if (!shopData) return false;
  if (shopData.ownerId === uid) return true;
  if (shopData.managers && shopData.managers.includes(uid)) return true;
  return false;
}

// ============================================================================
// COLLECTION PATHS
// ============================================================================

function getReceiptCollectionPath(isShopReceipt, shopId, uid) {
  if (isShopReceipt && shopId) {
    return `shops/${shopId}/receipts`;
  }
  return `users/${uid}/receipts`;
}

function getReportCollectionPath(shopId) {
  return `shops/${shopId}/reports`;
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildSuccessResponse(message = 'Email sent successfully') {
  return {
    success: true,
    message,
  };
}

function buildWelcomeSuccessResponse(shopName) {
  return {
    success: true,
    message: 'Welcome email sent successfully',
    shopName,
  };
}

// ============================================================================
// WELCOME EMAIL IMAGES
// ============================================================================

const WELCOME_EMAIL_IMAGES = [
  'shopwelcome.png',
  'shopproducts.png',
  'shopboost.png',
];

function getWelcomeEmailImages() {
  return WELCOME_EMAIL_IMAGES;
}

function getImagePath(imageName) {
  return `functions/shop-email-icons/${imageName}`;
}

function getImageKey(imageName) {
  return imageName.replace('.png', '');
}

// ============================================================================
// DATA EXTRACTION
// ============================================================================

function extractDisplayName(userData, defaultName = 'Customer') {
  return userData?.displayName || defaultName;
}

function extractLanguageCode(userData) {
  return userData?.languageCode || DEFAULT_LANGUAGE;
}

function extractShopName(shopData, defaultName = 'Unknown Shop') {
  return shopData?.name || defaultName;
}

function extractOwnerName(shopData, defaultName = 'Değerli Satıcı') {
  return shopData?.ownerName || defaultName;
}

// ============================================================================
// DATA BADGES (for report email)
// ============================================================================

function getIncludedDataBadges(reportData, content) {
  const badges = [];

  if (reportData.includeProducts) {
    badges.push({ label: content.products, color: '#10B981' });
  }
  if (reportData.includeOrders) {
    badges.push({ label: content.orders, color: '#F59E0B' });
  }
  if (reportData.includeBoostHistory) {
    badges.push({ label: content.boostHistory, color: '#6366F1' });
  }

  return badges;
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  SUPPORTED_LANGUAGES,
  DEFAULT_LANGUAGE,
  PDF_URL_EXPIRY_DAYS,
  WELCOME_IMAGE_EXPIRY_DAYS,
  RECEIPT_EMAIL_CONTENT,
  REPORT_EMAIL_CONTENT,
  WELCOME_EMAIL_IMAGES,

  // Input validation
  validateReceiptEmailInput,
  validateReportEmailInput,
  validateShopWelcomeInput,

  // ID formatting
  formatIdShort,
  formatOrderIdShort,
  formatReceiptIdShort,
  formatReportIdShort,

  // Date formatting
  getLocaleCode,
  formatDateForLocale,
  formatDateRange,

  // Localized content
  getLocalizedContent,
  getReportLocalizedContent,

  // File paths
  getReceiptFilePath,
  getReportFilePath,
  getReportSearchPrefix,

  // URL expiry
  calculatePdfUrlExpiry,
  calculateWelcomeImageExpiry,
  getExpiryDays,

  // Mail document building
  buildReceiptMailDocument,
  buildReportMailDocument,
  buildShopWelcomeMailDocument,

  // Price formatting
  formatPrice,

  // Ownership verification
  canAccessReceipt,
  canAccessReport,

  // Collection paths
  getReceiptCollectionPath,
  getReportCollectionPath,

  // Response building
  buildSuccessResponse,
  buildWelcomeSuccessResponse,

  // Welcome email images
  getWelcomeEmailImages,
  getImagePath,
  getImageKey,

  // Data extraction
  extractDisplayName,
  extractLanguageCode,
  extractShopName,
  extractOwnerName,

  // Data badges
  getIncludedDataBadges,
};
