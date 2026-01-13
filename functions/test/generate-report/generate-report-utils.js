// functions/test/generate-report/generate-report-utils.js
//
// EXTRACTED PURE LOGIC from PDF report generation cloud functions
// These functions are EXACT COPIES of logic from the report functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source report functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const SUPPORTED_LANGUAGES = ['en', 'tr', 'ru'];
const DEFAULT_LANGUAGE = 'en';
const MAX_ITEMS_PER_SECTION = 100;
const BATCH_SIZE = 500;
const PDF_URL_EXPIRY_DAYS = 7;

// ============================================================================
// REPORT TRANSLATIONS
// ============================================================================

const ReportTranslations = {
  en: {
    generated: 'Generated',
    dateRange: 'Date Range',
    products: 'Products',
    orders: 'Orders',
    boostHistory: 'Boost History',
    sortedBy: 'Sorted by',
    descending: 'Descending',
    ascending: 'Ascending',
    productName: 'Product Name',
    category: 'Category',
    price: 'Price',
    quantity: 'Quantity',
    views: 'Views',
    sales: 'Sales',
    favorites: 'Favorites',
    cartAdds: 'Cart Adds',
    product: 'Product',
    buyer: 'Buyer',
    status: 'Status',
    date: 'Date',
    item: 'Item',
    durationMinutes: 'Duration (min)',
    cost: 'Cost',
    impressions: 'Impressions',
    clicks: 'Clicks',
    notSpecified: 'Not specified',
    showingFirstItemsOfTotal: (shown, total) => `Showing first ${shown} items of ${total} total`,
    noDataAvailableForSection: 'No data available for this section',
    sortByDate: 'Date',
    sortByPurchaseCount: 'Purchase Count',
    sortByClickCount: 'Click Count',
    sortByFavoritesCount: 'Favorites Count',
    sortByCartCount: 'Cart Count',
    sortByPrice: 'Price',
    sortByDuration: 'Duration',
    sortByImpressionCount: 'Impression Count',
    statusPending: 'Pending',
    statusProcessing: 'Processing',
    statusShipped: 'Shipped',
    statusDelivered: 'Delivered',
    statusCancelled: 'Cancelled',
    statusReturned: 'Returned',
    unknownShop: 'Unknown Shop',
    reportGenerationFailed: 'Report generation failed',
    reportGeneratedSuccessfully: 'Report generated successfully',
  },
  tr: {
    generated: 'Oluşturuldu',
    dateRange: 'Tarih Aralığı',
    products: 'Ürünler',
    orders: 'Siparişler',
    boostHistory: 'Boost Geçmişi',
    sortedBy: 'Sıralama',
    descending: 'Azalan',
    ascending: 'Artan',
    productName: 'Ürün Adı',
    category: 'Kategori',
    price: 'Fiyat',
    quantity: 'Miktar',
    views: 'Görüntüleme',
    sales: 'Satış',
    favorites: 'Favoriler',
    cartAdds: 'Sepete Ekleme',
    product: 'Ürün',
    buyer: 'Alıcı',
    status: 'Durum',
    date: 'Tarih',
    item: 'Öğe',
    durationMinutes: 'Süre (dk)',
    cost: 'Maliyet',
    impressions: 'Gösterim',
    clicks: 'Tıklama',
    notSpecified: 'Belirtilmemiş',
    showingFirstItemsOfTotal: (shown, total) => `Toplam ${total} öğeden ilk ${shown} tanesi gösteriliyor`,
    noDataAvailableForSection: 'Bu bölüm için veri mevcut değil',
    sortByDate: 'Tarih',
    sortByPurchaseCount: 'Satın Alma Sayısı',
    sortByClickCount: 'Tıklama Sayısı',
    sortByFavoritesCount: 'Favori Sayısı',
    sortByCartCount: 'Sepet Sayısı',
    sortByPrice: 'Fiyat',
    sortByDuration: 'Süre',
    sortByImpressionCount: 'Gösterim Sayısı',
    statusPending: 'Beklemede',
    statusProcessing: 'İşleniyor',
    statusShipped: 'Kargoya Verildi',
    statusDelivered: 'Teslim Edildi',
    statusCancelled: 'İptal Edildi',
    statusReturned: 'İade Edildi',
    unknownShop: 'Bilinmeyen Mağaza',
    reportGenerationFailed: 'Rapor oluşturma başarısız',
    reportGeneratedSuccessfully: 'Rapor başarıyla oluşturuldu',
  },
  ru: {
    generated: 'Создано',
    dateRange: 'Диапазон дат',
    products: 'Товары',
    orders: 'Заказы',
    boostHistory: 'История продвижения',
    sortedBy: 'Сортировка',
    descending: 'По убыванию',
    ascending: 'По возрастанию',
    productName: 'Название товара',
    category: 'Категория',
    price: 'Цена',
    quantity: 'Количество',
    views: 'Просмотры',
    sales: 'Продажи',
    favorites: 'Избранное',
    cartAdds: 'Добавления в корзину',
    product: 'Товар',
    buyer: 'Покупатель',
    status: 'Статус',
    date: 'Дата',
    item: 'Элемент',
    durationMinutes: 'Длительность (мин)',
    cost: 'Стоимость',
    impressions: 'Показы',
    clicks: 'Клики',
    notSpecified: 'Не указано',
    showingFirstItemsOfTotal: (shown, total) => `Показаны первые ${shown} из ${total}`,
    noDataAvailableForSection: 'Нет данных для этого раздела',
    sortByDate: 'Дата',
    sortByPurchaseCount: 'Количество покупок',
    sortByClickCount: 'Количество кликов',
    sortByFavoritesCount: 'Количество избранного',
    sortByCartCount: 'Количество корзин',
    sortByPrice: 'Цена',
    sortByDuration: 'Длительность',
    sortByImpressionCount: 'Количество показов',
    statusPending: 'В ожидании',
    statusProcessing: 'Обработка',
    statusShipped: 'Отправлено',
    statusDelivered: 'Доставлено',
    statusCancelled: 'Отменено',
    statusReturned: 'Возвращено',
    unknownShop: 'Неизвестный магазин',
    reportGenerationFailed: 'Ошибка создания отчета',
    reportGeneratedSuccessfully: 'Отчет успешно создан',
  },
};

// ============================================================================
// TRANSLATION HELPER
// ============================================================================

function t(lang, key, ...args) {
  const translation = ReportTranslations[lang] || ReportTranslations.en;
  const value = translation[key] || ReportTranslations.en[key] || key;
  return typeof value === 'function' ? value(...args) : value;
}

function getTranslation(lang, key) {
  return t(lang, key);
}

function getSupportedLanguages() {
  return SUPPORTED_LANGUAGES;
}

function isValidLanguage(lang) {
  return SUPPORTED_LANGUAGES.includes(lang);
}

function getEffectiveLanguage(lang) {
  return isValidLanguage(lang) ? lang : DEFAULT_LANGUAGE;
}

// ============================================================================
// DATE FORMATTING
// ============================================================================

function getLocaleCode(lang) {
  const localeMap = {
    en: 'en-US',
    tr: 'tr-TR',
    ru: 'ru-RU',
  };
  return localeMap[lang] || localeMap[DEFAULT_LANGUAGE];
}

function formatDate(date, lang = 'en') {
  if (!date) return t(lang, 'notSpecified');
  
  const dateObj = date instanceof Date ? date : (date.toDate ? date.toDate() : new Date(date));
  if (isNaN(dateObj.getTime())) return t(lang, 'notSpecified');

  const options = { year: 'numeric', month: 'short', day: 'numeric' };
  const locale = getLocaleCode(lang);
  return dateObj.toLocaleDateString(locale, options);
}

function formatDateTime(date, lang = 'en') {
  if (!date) return t(lang, 'notSpecified');
  
  const dateObj = date instanceof Date ? date : (date.toDate ? date.toDate() : new Date(date));
  if (isNaN(dateObj.getTime())) return t(lang, 'notSpecified');

  const options = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  };
  const locale = getLocaleCode(lang);
  return dateObj.toLocaleDateString(locale, options);
}

function formatDateRange(startDate, endDate, lang = 'en') {
  const start = formatDate(startDate, lang);
  const end = formatDate(endDate, lang);
  return `${start} - ${end}`;
}

// ============================================================================
// SORTING FUNCTIONS
// ============================================================================

function extractDate(item, field) {
  const value = item[field];
  if (!value) return new Date(1970, 0, 1);
  return value.toDate ? value.toDate() : new Date(value);
}

function sortProducts(products, sortBy, descending = true) {
  if (!Array.isArray(products)) return [];
  
  return [...products].sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
      case 'date': {
        const dateA = extractDate(a, 'createdAt');
        const dateB = extractDate(b, 'createdAt');
        comparison = dateA - dateB;
        break;
      }
      case 'purchaseCount': {
        comparison = (a.purchaseCount || 0) - (b.purchaseCount || 0);
        break;
      }
      case 'clickCount': {
        comparison = (a.clickCount || 0) - (b.clickCount || 0);
        break;
      }
      case 'favoritesCount': {
        comparison = (a.favoritesCount || 0) - (b.favoritesCount || 0);
        break;
      }
      case 'cartCount': {
        comparison = (a.cartCount || 0) - (b.cartCount || 0);
        break;
      }
      case 'price': {
        comparison = (a.price || 0) - (b.price || 0);
        break;
      }
      default:
        comparison = 0;
    }
    return descending ? -comparison : comparison;
  });
}

function sortOrders(orders, sortBy, descending = true) {
  if (!Array.isArray(orders)) return [];
  
  return [...orders].sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
      case 'date': {
        const dateA = extractDate(a, 'timestamp');
        const dateB = extractDate(b, 'timestamp');
        comparison = dateA - dateB;
        break;
      }
      case 'price': {
        comparison = (a.price || 0) - (b.price || 0);
        break;
      }
      default:
        comparison = 0;
    }
    return descending ? -comparison : comparison;
  });
}

function sortBoosts(boosts, sortBy, descending = true) {
  if (!Array.isArray(boosts)) return [];
  
  return [...boosts].sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
      case 'date': {
        const dateA = extractDate(a, 'createdAt');
        const dateB = extractDate(b, 'createdAt');
        comparison = dateA - dateB;
        break;
      }
      case 'duration': {
        comparison = (a.boostDuration || 0) - (b.boostDuration || 0);
        break;
      }
      case 'price': {
        comparison = (a.boostPrice || 0) - (b.boostPrice || 0);
        break;
      }
      case 'impressionCount': {
        comparison = (a.impressionsDuringBoost || 0) - (b.impressionsDuringBoost || 0);
        break;
      }
      case 'clickCount': {
        comparison = (a.clicksDuringBoost || 0) - (b.clicksDuringBoost || 0);
        break;
      }
      default:
        comparison = 0;
    }
    return descending ? -comparison : comparison;
  });
}

// ============================================================================
// STATUS LOCALIZATION
// ============================================================================

const STATUS_KEYS = {
  pending: 'statusPending',
  processing: 'statusProcessing',
  shipped: 'statusShipped',
  delivered: 'statusDelivered',
  cancelled: 'statusCancelled',
  returned: 'statusReturned',
};

function localizeShipmentStatus(status, lang = 'en') {
  if (!status) return t(lang, 'notSpecified');

  const normalizedStatus = status.toLowerCase();
  const statusKey = STATUS_KEYS[normalizedStatus];
  
  if (statusKey) {
    return t(lang, statusKey);
  }
  
  // Fallback: capitalize first letter
  return status.charAt(0).toUpperCase() + status.slice(1).toLowerCase();
}

function getStatusKey(status) {
  if (!status) return null;
  return STATUS_KEYS[status.toLowerCase()] || null;
}

// ============================================================================
// EMAIL LOCALIZED CONTENT
// ============================================================================

const ReportEmailContent = {
  en: {
    greeting: 'Hello',
    message: 'your shop report is ready for download!',
    reportName: 'Report Name',
    reportId: 'Report ID',
    shopName: 'Shop',
    dateRange: 'Date Range',
    generatedOn: 'Generated On',
    includedData: 'Included Data',
    products: 'Products',
    orders: 'Orders',
    boostHistory: 'Boost History',
    subject: 'Your Shop Report',
    downloadButton: 'Download Report PDF',
    downloadHint: 'Click to download your detailed shop report',
    footer: 'Thank you for using Nar24 Business Tools!',
    rights: 'All rights reserved.',
    businessReports: 'Business Intelligence Reports',
    reportReady: 'Your Report is Ready!',
    reportDetails: 'Report Information',
    needHelp: 'Need help understanding your report?',
    contactSupport: 'Contact Support',
  },
  tr: {
    greeting: 'Merhaba',
    message: 'mağaza raporunuz indirilmeye hazır!',
    reportName: 'Rapor Adı',
    reportId: 'Rapor No',
    shopName: 'Mağaza',
    dateRange: 'Tarih Aralığı',
    generatedOn: 'Oluşturulma Tarihi',
    includedData: 'İçerilen Veriler',
    products: 'Ürünler',
    orders: 'Siparişler',
    boostHistory: 'Boost Geçmişi',
    subject: 'Mağaza Raporunuz',
    downloadButton: 'Raporu PDF Olarak İndir',
    downloadHint: 'Detaylı mağaza raporunuzu indirmek için tıklayın',
    footer: 'Nar24 İşletme Araçlarını kullandığınız için teşekkür ederiz!',
    rights: 'Tüm hakları saklıdır.',
    businessReports: 'İş Zekası Raporları',
    reportReady: 'Raporunuz Hazır!',
    reportDetails: 'Rapor Bilgileri',
    needHelp: 'Raporunuzu anlamak için yardıma mı ihtiyacınız var?',
    contactSupport: 'Destek ile İletişime Geç',
  },
  ru: {
    greeting: 'Здравствуйте',
    message: 'ваш отчет магазина готов к загрузке!',
    reportName: 'Название отчета',
    reportId: 'Номер отчета',
    shopName: 'Магазин',
    dateRange: 'Период',
    generatedOn: 'Дата создания',
    includedData: 'Включенные данные',
    products: 'Товары',
    orders: 'Заказы',
    boostHistory: 'История продвижения',
    subject: 'Ваш отчет магазина',
    downloadButton: 'Скачать отчет в PDF',
    downloadHint: 'Нажмите, чтобы скачать подробный отчет магазина',
    footer: 'Спасибо за использование бизнес-инструментов Nar24!',
    rights: 'Все права защищены.',
    businessReports: 'Бизнес-аналитика',
    reportReady: 'Ваш отчет готов!',
    reportDetails: 'Информация об отчете',
    needHelp: 'Нужна помощь в понимании отчета?',
    contactSupport: 'Связаться с поддержкой',
  },
};

function getReportLocalizedContent(languageCode) {
  return ReportEmailContent[languageCode] || ReportEmailContent[DEFAULT_LANGUAGE];
}

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateReportInput(data) {
  const errors = [];

  if (!data.reportId) {
    errors.push({ field: 'reportId', message: 'Report ID is required' });
  }

  if (!data.shopId) {
    errors.push({ field: 'shopId', message: 'Shop ID is required' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, message: 'Missing required parameters' };
  }

  return { isValid: true };
}

// ============================================================================
// FILE PATH GENERATION
// ============================================================================

function generateReportFilePath(shopId, reportId, timestamp = Date.now()) {
  return `reports/${shopId}/${reportId}_${timestamp}.pdf`;
}

function calculatePdfUrlExpiry(nowMs = Date.now()) {
  return nowMs + PDF_URL_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
}

// ============================================================================
// SUMMARY BUILDING
// ============================================================================

function buildReportSummary(reportData) {
  return {
    productsCount: reportData.products?.length || 0,
    ordersCount: reportData.orders?.length || 0,
    boostsCount: reportData.boostHistory?.length || 0,
  };
}

// ============================================================================
// ROW BUILDERS FOR PDF
// ============================================================================

function buildProductRow(item, lang) {
  return [
    item.productName || t(lang, 'notSpecified'),
    `${item.price || 0} ${item.currency || 'TL'}`,
    String(item.quantity || 0),
    String(item.clickCount || 0),
    String(item.purchaseCount || 0),
    String(item.favoritesCount || 0),
    String(item.cartCount || 0),
  ];
}

function buildOrderRow(item, lang) {
  return [
    item.productName || t(lang, 'notSpecified'),
    item.buyerName || t(lang, 'notSpecified'),
    String(item.quantity || 0),
    `${item.price || 0} ${item.currency || 'TL'}`,
    localizeShipmentStatus(item.shipmentStatus, lang),
    item.timestamp ? formatDate(item.timestamp, lang) : t(lang, 'notSpecified'),
  ];
}

function buildBoostRow(item, lang) {
  return [
    item.itemName || t(lang, 'notSpecified'),
    String(item.boostDuration || 0),
    `${item.boostPrice || 0} ${item.currency || 'TL'}`,
    String(item.impressionsDuringBoost || 0),
    String(item.clicksDuringBoost || 0),
    item.createdAt ? formatDate(item.createdAt, lang) : t(lang, 'notSpecified'),
  ];
}

// ============================================================================
// HEADERS FOR PDF
// ============================================================================

function getProductHeaders(lang) {
  return [
    t(lang, 'productName'),
    t(lang, 'price'),
    t(lang, 'quantity'),
    t(lang, 'views'),
    t(lang, 'sales'),
    t(lang, 'favorites'),
    t(lang, 'cartAdds'),
  ];
}

function getOrderHeaders(lang) {
  return [
    t(lang, 'product'),
    t(lang, 'buyer'),
    t(lang, 'quantity'),
    t(lang, 'price'),
    t(lang, 'status'),
    t(lang, 'date'),
  ];
}

function getBoostHeaders(lang) {
  return [
    t(lang, 'item'),
    t(lang, 'durationMinutes'),
    t(lang, 'cost'),
    t(lang, 'impressions'),
    t(lang, 'clicks'),
    t(lang, 'date'),
  ];
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildSuccessResponse(pdfUrl, lang) {
  return {
    success: true,
    pdfUrl,
    message: t(lang, 'reportGeneratedSuccessfully'),
  };
}

function buildErrorResponse(lang) {
  return {
    success: false,
    message: t(lang, 'reportGenerationFailed'),
  };
}

// ============================================================================
// PAGINATION
// ============================================================================

function limitItems(items, maxItems = MAX_ITEMS_PER_SECTION) {
  if (!Array.isArray(items)) return [];
  return items.slice(0, maxItems);
}

function shouldShowTruncationMessage(items, maxItems = MAX_ITEMS_PER_SECTION) {
  return Array.isArray(items) && items.length > maxItems;
}

function getTruncationMessage(shown, total, lang) {
  return t(lang, 'showingFirstItemsOfTotal', shown, total);
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  SUPPORTED_LANGUAGES,
  DEFAULT_LANGUAGE,
  MAX_ITEMS_PER_SECTION,
  BATCH_SIZE,
  PDF_URL_EXPIRY_DAYS,
  ReportTranslations,
  ReportEmailContent,
  STATUS_KEYS,

  // Translation
  t,
  getTranslation,
  getSupportedLanguages,
  isValidLanguage,
  getEffectiveLanguage,

  // Date formatting
  getLocaleCode,
  formatDate,
  formatDateTime,
  formatDateRange,

  // Sorting
  extractDate,
  sortProducts,
  sortOrders,
  sortBoosts,

  // Status
  localizeShipmentStatus,
  getStatusKey,

  // Email content
  getReportLocalizedContent,

  // Validation
  validateReportInput,

  // File paths
  generateReportFilePath,
  calculatePdfUrlExpiry,

  // Summary
  buildReportSummary,

  // Row builders
  buildProductRow,
  buildOrderRow,
  buildBoostRow,

  // Headers
  getProductHeaders,
  getOrderHeaders,
  getBoostHeaders,

  // Response
  buildSuccessResponse,
  buildErrorResponse,

  // Pagination
  limitItems,
  shouldShowTruncationMessage,
  getTruncationMessage,
};
