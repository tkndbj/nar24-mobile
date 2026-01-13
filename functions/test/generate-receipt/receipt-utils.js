// functions/test/generate-receipt/receipt-utils.js
//
// EXTRACTED PURE LOGIC from receipt generation cloud functions
// These functions are EXACT COPIES of logic from the receipt functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source receipt functions.

// ============================================================================
// SUPPORTED LANGUAGES
// ============================================================================

const SUPPORTED_LANGUAGES = ['en', 'tr', 'ru'];
const DEFAULT_LANGUAGE = 'en';

// ============================================================================
// RECEIPT TYPES
// ============================================================================

const RECEIPT_TYPES = {
  ORDER: 'order',
  BOOST: 'boost',
};

// ============================================================================
// OWNER TYPES
// ============================================================================

const OWNER_TYPES = {
  SHOP: 'shop',
  USER: 'user',
};

// ============================================================================
// DELIVERY OPTIONS
// ============================================================================

const DELIVERY_OPTIONS = {
  NORMAL: 'normal',
  EXPRESS: 'express',
  PICKUP: 'pickup',
};

// ============================================================================
// LOCALIZED LABELS
// EXACT COPY from production code
// ============================================================================

const RECEIPT_LABELS = {
  en: {
    title: 'Nar24 Receipt',
    orderInfo: 'Order Information',
    buyerInfo: 'Buyer Information',
    pickupInfo: 'Pickup Point Information',
    purchasedItems: 'Purchased Items',
    orderId: 'Order ID',
    date: 'Date',
    paymentMethod: 'Payment Method',
    deliveryOption: 'Delivery Option',
    name: 'Name',
    phone: 'Phone',
    address: 'Address',
    city: 'City',
    deliveryPrice: 'Delivery',
    subtotal: 'Subtotal',
    free: 'Free',
    pickupName: 'Pickup Point',
    pickupAddress: 'Address',
    pickupPhone: 'Contact Phone',
    pickupHours: 'Operating Hours',
    pickupContact: 'Contact Person',
    pickupNotes: 'Notes',
    seller: 'Seller',
    product: 'Product',
    attributes: 'Attributes',
    qty: 'Qty',
    unitPrice: 'Unit Price',
    total: 'Total',
    footer: 'This is a computer-generated receipt and does not require a signature.',
    boostDuration: 'Boost Duration',
    boostedItems: 'Boosted Items',
    duration: 'Duration',
    shopName: 'Shop Name',
  },
  tr: {
    title: 'Nar24 Fatura',
    orderInfo: 'Sipariş Bilgileri',
    buyerInfo: 'Alıcı Bilgileri',
    pickupInfo: 'Gel-Al Noktası Bilgileri',
    purchasedItems: 'Satın Alınan Ürünler',
    orderId: 'Sipariş No',
    date: 'Tarih',
    paymentMethod: 'Ödeme Yöntemi',
    deliveryOption: 'Teslimat Seçeneği',
    name: 'Ad-Soyad',
    phone: 'Telefon',
    address: 'Adres',
    city: 'Şehir',
    deliveryPrice: 'Kargo',
    subtotal: 'Ara Toplam',
    free: 'Ücretsiz',
    pickupName: 'Gel-Al Noktası',
    pickupAddress: 'Adres',
    pickupPhone: 'İletişim Telefonu',
    pickupHours: 'Çalışma Saatleri',
    pickupContact: 'İletişim Kişisi',
    pickupNotes: 'Notlar',
    seller: 'Satıcı',
    product: 'Ürün',
    attributes: 'Özellikler',
    qty: 'Adet',
    unitPrice: 'Birim Fiyat',
    total: 'Toplam',
    footer: 'Bu bilgisayar tarafından oluşturulan bir makbuzdur ve imza gerektirmez.',
    boostDuration: 'Boost Süresi',
    boostedItems: 'Boost Edilen',
    duration: 'Süre',
    shopName: 'Dükkan İsmi',
  },
  ru: {
    title: 'Nar24 Счет',
    orderInfo: 'Информация о заказе',
    buyerInfo: 'Информация о покупателе',
    pickupInfo: 'Информация о пункте выдачи',
    purchasedItems: 'Купленные товары',
    orderId: 'Номер заказа',
    date: 'Дата',
    paymentMethod: 'Способ оплаты',
    deliveryOption: 'Вариант доставки',
    name: 'Имя',
    phone: 'Телефон',
    address: 'Адрес',
    city: 'Город',
    pickupName: 'Пункт выдачи',
    pickupAddress: 'Адрес',
    pickupPhone: 'Контактный телефон',
    pickupHours: 'Часы работы',
    deliveryPrice: 'Доставка',
    subtotal: 'Промежуточный итог',
    free: 'Бесплатно',
    pickupContact: 'Контактное лицо',
    pickupNotes: 'Примечания',
    seller: 'Продавец',
    product: 'Товар',
    attributes: 'Характеристики',
    qty: 'Кол-во',
    unitPrice: 'Цена за единицу',
    total: 'Итого',
    footer: 'Это компьютерный чек и не требует подписи.',
    boostDuration: 'Длительность буста',
    boostedItems: 'Усиленные товары',
    duration: 'Длительность',
    shopName: 'Название магазина',
  },
};

// ============================================================================
// DELIVERY OPTION LABELS
// EXACT COPY from production code
// ============================================================================

const DELIVERY_OPTION_LABELS = {
  en: {
    normal: 'Normal Delivery',
    express: 'Express Delivery',
    pickup: 'Pickup',
  },
  tr: {
    normal: 'Normal Teslimat',
    express: 'Express Teslimat',
    pickup: 'Gel-Al',
  },
  ru: {
    normal: 'Обычная доставка',
    express: 'Экспресс-доставка',
    pickup: 'Самовывоз',
  },
};

// ============================================================================
// DURATION LABELS (for boost receipts)
// ============================================================================

const DURATION_LABELS = {
  en: { minutes: 'minutes', items: 'items' },
  tr: { minutes: 'dakika', items: 'ürün' },
  ru: { minutes: 'минут', items: 'товаров' },
};

// ============================================================================
// LANGUAGE UTILITIES
// ============================================================================


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
// LABEL FUNCTIONS
// ============================================================================


function getReceiptLabels(lang) {
  return RECEIPT_LABELS[lang] || RECEIPT_LABELS[DEFAULT_LANGUAGE];
}


function getLabel(lang, key) {
  const labels = getReceiptLabels(lang);
  return labels[key] || key;
}

// ============================================================================
// DELIVERY OPTION FORMATTING
// EXACT COPY from production code
// ============================================================================


function formatDeliveryOption(option, lang = 'en') {
  const options = DELIVERY_OPTION_LABELS[lang] || DELIVERY_OPTION_LABELS[DEFAULT_LANGUAGE];
  return options[option] || options['normal'] || option;
}

// ============================================================================
// DURATION FORMATTING (for boost receipts)
// ============================================================================


function formatDuration(duration, lang = 'en') {
  const labels = DURATION_LABELS[lang] || DURATION_LABELS[DEFAULT_LANGUAGE];
  return `${duration} ${labels.minutes}`;
}


function formatItemCount(count, lang = 'en') {
  const labels = DURATION_LABELS[lang] || DURATION_LABELS[DEFAULT_LANGUAGE];
  return `${count} ${labels.items}`;
}

// ============================================================================
// PRICE AND TOTAL CALCULATIONS
// ============================================================================


function calculateTotals(data) {
  const deliveryPrice = data.deliveryPrice || 0;
  const subtotal = data.itemsSubtotal || (data.totalPrice - deliveryPrice);
  const grandTotal = subtotal + deliveryPrice;

  return {
    deliveryPrice,
    subtotal,
    grandTotal,
  };
}


function formatPrice(amount, currency) {
  return `${(amount || 0).toFixed(0)} ${currency}`;
}


function isDeliveryFree(deliveryPrice) {
  return !deliveryPrice || deliveryPrice === 0;
}


function getDeliveryPriceText(deliveryPrice, currency, lang = 'en') {
  if (isDeliveryFree(deliveryPrice)) {
    return getLabel(lang, 'free');
  }
  return formatPrice(deliveryPrice, currency);
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


function formatReceiptDate(date, lang = 'en') {
  if (!date || !(date instanceof Date)) {
    return 'N/A';
  }

  const locale = getLocaleCode(lang);
  const options = {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  };

  return date.toLocaleDateString(locale, options);
}

// ============================================================================
// FILE PATH GENERATION
// ============================================================================


function getReceiptFilePath(orderId) {
  return `receipts/${orderId}.pdf`;
}


function getReceiptCollectionPath(ownerType, ownerId) {
  if (ownerType === OWNER_TYPES.SHOP) {
    return `shops/${ownerId}/receipts`;
  }
  return `users/${ownerId}/receipts`;
}

// ============================================================================
// RECEIPT DOCUMENT BUILDING
// ============================================================================


function buildReceiptDocument(receiptId, taskData, filePath) {
  const receiptDocument = {
    receiptId,
    receiptType: taskData.receiptType || RECEIPT_TYPES.ORDER,
    orderId: taskData.orderId,
    buyerId: taskData.buyerId,
    totalPrice: taskData.totalPrice,
    itemsSubtotal: taskData.itemsSubtotal,
    deliveryPrice: taskData.deliveryPrice || 0,
    currency: taskData.currency,
    paymentMethod: taskData.paymentMethod,
    filePath,
  };

  // Add boost-specific fields if it's a boost receipt
  if (taskData.receiptType === RECEIPT_TYPES.BOOST && taskData.boostData) {
    receiptDocument.boostDuration = taskData.boostData.boostDuration;
    receiptDocument.itemCount = taskData.boostData.itemCount;
  }

  // Add delivery info for regular orders
  if (taskData.deliveryOption === DELIVERY_OPTIONS.PICKUP && taskData.pickupPoint) {
    receiptDocument.pickupPointName = taskData.pickupPoint.name;
    receiptDocument.pickupPointAddress = taskData.pickupPoint.address;
  } else if (taskData.buyerAddress) {
    receiptDocument.deliveryAddress = `${taskData.buyerAddress.addressLine1}, ${taskData.buyerAddress.city}`;
  }

  return receiptDocument;
}

// ============================================================================
// BUYER INFO EXTRACTION
// ============================================================================


function getBuyerPhone(data) {
  return data.buyerPhone || data.buyerAddress?.phoneNumber || 'N/A';
}


function getBuyerNameLabel(data, lang = 'en') {
  if (data.receiptType === RECEIPT_TYPES.BOOST && data.ownerType === OWNER_TYPES.SHOP) {
    return getLabel(lang, 'shopName');
  }
  return getLabel(lang, 'name');
}

// ============================================================================
// ATTRIBUTE SYSTEM FIELDS
// ============================================================================

/**
 * Fields to exclude from attribute display
 */
const SYSTEM_FIELDS = [
  'productId', 'quantity', 'addedAt', 'updatedAt',
  'sellerId', 'sellerName', 'isShop', 'finalPrice',
  'selectedColorImage', 'productImage',
  'ourComission', 'calculatedTotal', 'calculatedUnitPrice',
  'isBundleItem', 'unitPrice', 'totalPrice', 'currency', 'sellerContactNo',
];


function isSystemField(key) {
  return SYSTEM_FIELDS.includes(key);
}


function filterDisplayableAttributes(attributes) {
  if (!attributes) return {};

  const filtered = {};
  Object.entries(attributes).forEach(([key, value]) => {
    if (value && value !== '' && value !== null && !isSystemField(key)) {
      filtered[key] = value;
    }
  });
  return filtered;
}

// ============================================================================
// ATTRIBUTE LOCALIZATION
// ============================================================================

/**
 * Common attribute key translations
 */
const ATTRIBUTE_KEY_TRANSLATIONS = {
  en: {
    color: 'Color',
    size: 'Size',
    material: 'Material',
    brand: 'Brand',
    model: 'Model',
  },
  tr: {
    color: 'Renk',
    size: 'Beden',
    material: 'Malzeme',
    brand: 'Marka',
    model: 'Model',
  },
  ru: {
    color: 'Цвет',
    size: 'Размер',
    material: 'Материал',
    brand: 'Бренд',
    model: 'Модель',
  },
};


function localizeAttributeKey(key, lang = 'en') {
  const translations = ATTRIBUTE_KEY_TRANSLATIONS[lang] || ATTRIBUTE_KEY_TRANSLATIONS[DEFAULT_LANGUAGE];
  const lowerKey = key.toLowerCase();
  return translations[lowerKey] || key;
}


function localizeAttributeValue(key, value, lang = 'en') {
  // Currently returns value as-is
  // Could be extended for specific value translations
  return value;
}


function formatAttributes(attributes, lang = 'en') {
  const filtered = filterDisplayableAttributes(attributes);
  const parts = [];

  Object.entries(filtered).forEach(([key, value]) => {
    const localizedKey = localizeAttributeKey(key, lang);
    const localizedValue = localizeAttributeValue(key, value, lang);
    parts.push(`${localizedKey}: ${localizedValue}`);
  });

  return parts.join(', ') || '-';
}

// ============================================================================
// RETRY LOGIC
// ============================================================================

/**
 * Maximum retry attempts
 */
const MAX_RETRY_COUNT = 3;


function getTaskStatusAfterError(retryCount) {
  return retryCount >= MAX_RETRY_COUNT ? 'failed' : 'pending';
}


function shouldRetryTask(retryCount) {
  return retryCount < MAX_RETRY_COUNT;
}

// ============================================================================
// RECEIPT TYPE CHECKS
// ============================================================================


function isBoostReceipt(data) {
  return data?.receiptType === RECEIPT_TYPES.BOOST;
}

function isOrderReceipt(data) {
  return !data?.receiptType || data.receiptType === RECEIPT_TYPES.ORDER;
}


function shouldShowDelivery(data) {
  return !isBoostReceipt(data);
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  SUPPORTED_LANGUAGES,
  DEFAULT_LANGUAGE,
  RECEIPT_TYPES,
  OWNER_TYPES,
  DELIVERY_OPTIONS,
  RECEIPT_LABELS,
  DELIVERY_OPTION_LABELS,
  DURATION_LABELS,
  SYSTEM_FIELDS,
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
  localizeAttributeValue,
  formatAttributes,

  // Retry logic
  getTaskStatusAfterError,
  shouldRetryTask,

  // Receipt type checks
  isBoostReceipt,
  isOrderReceipt,
  shouldShowDelivery,
};
