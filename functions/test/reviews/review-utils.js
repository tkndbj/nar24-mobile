// functions/test/reviews/review-utils.js
//
// EXTRACTED PURE LOGIC from review system cloud functions
// These functions are EXACT COPIES of logic from the review functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source review functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const MIN_RATING = 1;
const MAX_RATING = 5;
const VALID_COLLECTIONS = ['products', 'shop_products', 'shops', 'users'];

const NOTIFICATION_TYPES = {
  PRODUCT_REVIEW_SHOP: 'product_review_shop',
  PRODUCT_REVIEW_USER: 'product_review_user',
  SELLER_REVIEW_SHOP: 'seller_review_shop',
  SELLER_REVIEW_USER: 'seller_review_user',
};

// ============================================================================
// RATING VALIDATION
// ============================================================================

function validateRating(rating) {
  if (rating === null || rating === undefined) {
    return { isValid: false, reason: 'missing', message: 'Rating must be a number between 1 and 5.' };
  }

  if (typeof rating !== 'number') {
    return { isValid: false, reason: 'not_number', message: 'Rating must be a number between 1 and 5.' };
  }

  if (isNaN(rating)) {
    return { isValid: false, reason: 'nan', message: 'Rating must be a number between 1 and 5.' };
  }

  if (rating < MIN_RATING || rating > MAX_RATING) {
    return { isValid: false, reason: 'out_of_range', message: 'Rating must be a number between 1 and 5.' };
  }

  // Check for integer (no decimals)
  if (!Number.isInteger(rating)) {
    return { isValid: false, reason: 'not_integer', message: 'Rating must be a whole number between 1 and 5.' };
  }

  return { isValid: true, rating };
}

function isValidRating(rating) {
  return validateRating(rating).isValid;
}

// ============================================================================
// REVIEW TEXT VALIDATION
// ============================================================================

function validateReviewText(review) {
  if (review === null || review === undefined) {
    return { isValid: false, reason: 'missing', message: 'Review text must be a non-empty string.' };
  }

  if (typeof review !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Review text must be a non-empty string.' };
  }

  if (!review.trim()) {
    return { isValid: false, reason: 'empty', message: 'Review text must be a non-empty string.' };
  }

  return { isValid: true, sanitizedReview: review.trim() };
}

function isValidReviewText(review) {
  return validateReviewText(review).isValid;
}

// ============================================================================
// COMPLETE INPUT VALIDATION
// ============================================================================

function validateReviewInput(data) {
  const errors = [];

  // Rating validation
  const ratingResult = validateRating(data.rating);
  if (!ratingResult.isValid) {
    errors.push({ field: 'rating', ...ratingResult });
  }

  // Review text validation
  const reviewResult = validateReviewText(data.review);
  if (!reviewResult.isValid) {
    errors.push({ field: 'review', ...reviewResult });
  }

  // Transaction/Order ID validation
  if (!data.transactionId) {
    errors.push({ field: 'transactionId', message: 'Missing transactionId or orderId.' });
  }
  if (!data.orderId) {
    errors.push({ field: 'orderId', message: 'Missing transactionId or orderId.' });
  }

  // Product review specific validation
  if (data.isProduct && !data.productId) {
    errors.push({ field: 'productId', message: 'Missing productId for a product review.' });
  }

  // Seller review specific validation
  if (!data.isProduct && !data.sellerId && !data.shopId) {
    errors.push({ field: 'sellerId', message: 'Missing sellerId or shopId for a seller review.' });
  }

  if (errors.length > 0) {
    return { isValid: false, errors, firstError: errors[0] };
  }

  return { isValid: true };
}

// ============================================================================
// AVERAGE RATING CALCULATION
// ============================================================================

function calculateNewAverage(currentAverage, currentCount, newRating) {
  // Handle invalid inputs
  const curAvg = typeof currentAverage === 'number' && !isNaN(currentAverage) ? currentAverage : 0;
  const curCount = typeof currentCount === 'number' && !isNaN(currentCount) && currentCount >= 0 ? currentCount : 0;

  const newCount = curCount + 1;
  const newAvg = (curAvg * curCount + newRating) / newCount;

  return {
    averageRating: newAvg,
    reviewCount: newCount,
  };
}

function calculateAverageFromRatings(ratings) {
  if (!Array.isArray(ratings) || ratings.length === 0) {
    return { averageRating: 0, reviewCount: 0 };
  }

  const validRatings = ratings.filter((r) => typeof r === 'number' && !isNaN(r) && r >= MIN_RATING && r <= MAX_RATING);
  
  if (validRatings.length === 0) {
    return { averageRating: 0, reviewCount: 0 };
  }

  const sum = validRatings.reduce((acc, r) => acc + r, 0);
  return {
    averageRating: sum / validRatings.length,
    reviewCount: validRatings.length,
  };
}

// ============================================================================
// REVIEW DOCUMENT BUILDING
// ============================================================================

function buildReviewDocument(data, reviewerInfo, sellerInfo, itemData) {
  const {
    rating,
    review,
    transactionId,
    orderId,
    productId,
    isProduct,
    isShopProduct,
    imageUrls = [],
  } = data;

  return {
    // Core fields
    rating,
    review: review.trim(),
    userId: reviewerInfo.userId,
    userName: reviewerInfo.userName || 'Anonymous',
    transactionId,
    orderId,

    // Product-specific fields
    productId: isProduct ? productId : null,
    productName: isProduct ? (itemData.productName || 'Unknown Product') : null,
    productImage: isProduct ? getProductImage(itemData) : null,

    // Product metadata
    brand: isProduct ? (itemData.brand || null) : null,
    brandModel: isProduct ? (itemData.brandModel || null) : null,
    category: isProduct ? (itemData.category || null) : null,
    subcategory: isProduct ? (itemData.subcategory || null) : null,
    condition: isProduct ? (itemData.condition || null) : null,

    // Pricing info
    price: isProduct ? (itemData.price || 0) : null,
    currency: isProduct ? (itemData.currency || 'TL') : null,

    // Product rating at time of purchase
    productAverageRatingAtPurchase: isProduct ? (itemData.productAverageRating || 0) : null,
    productReviewCountAtPurchase: isProduct ? (itemData.productReviewCount || 0) : null,

    // Seller-specific fields
    sellerId: sellerInfo.sellerId,
    sellerName: sellerInfo.sellerName || 'Unknown',
    shopId: sellerInfo.shopId || null,
    isShopProduct: !!isShopProduct,
    isProductReview: !!isProduct,

    // Images
    imageUrls: Array.isArray(imageUrls) ? imageUrls : [],

    // Selected attributes
    selectedColor: itemData.selectedColor || null,
    selectedSize: itemData.selectedSize || null,
    selectedAttributes: itemData.selectedAttributes || null,

    // Purchase context
    quantity: itemData.quantity || 1,
    purchaseTimestamp: itemData.timestamp || null,

    // Processing flag for idempotency
    metricsProcessed: false,
  };
}

function getProductImage(itemData) {
  return itemData.selectedColorImage || itemData.productImage || null;
}

// ============================================================================
// REVIEW FLAGS UPDATE
// ============================================================================

function buildReviewFlagsUpdate(isProduct, itemData) {
  const updates = {};

  if (isProduct) {
    updates.needsProductReview = false;
    if (!itemData.needsSellerReview) {
      updates.needsAnyReview = false;
    }
  } else {
    updates.needsSellerReview = false;
    if (!itemData.needsProductReview) {
      updates.needsAnyReview = false;
    }
  }

  return updates;
}

function canSubmitProductReview(itemData) {
  return itemData.needsProductReview === true;
}

function canSubmitSellerReview(itemData) {
  return itemData.needsSellerReview === true;
}

// ============================================================================
// METRICS PROCESSING
// ============================================================================

function shouldProcessMetrics(reviewData) {
  if (!reviewData) return false;
  if (reviewData.metricsProcessed === true) return false;
  return true;
}

function buildMetricsUpdate(newAverage, newCount) {
  return {
    averageRating: newAverage,
    reviewCount: newCount,
  };
}

function buildMetricsProcessedUpdate() {
  return {
    metricsProcessed: true,
  };
}

// ============================================================================
// NOTIFICATION HELPERS
// ============================================================================

function getNotificationType(reviewData) {
  if (reviewData.isProductReview) {
    if (reviewData.isShopProduct && reviewData.shopId) {
      return NOTIFICATION_TYPES.PRODUCT_REVIEW_SHOP;
    }
    return NOTIFICATION_TYPES.PRODUCT_REVIEW_USER;
  } else {
    if (reviewData.shopId) {
      return NOTIFICATION_TYPES.SELLER_REVIEW_SHOP;
    }
    return NOTIFICATION_TYPES.SELLER_REVIEW_USER;
  }
}

function getShopMemberIds(shopData) {
  const memberSet = new Set();

  if (shopData.ownerId) memberSet.add(shopData.ownerId);
  if (Array.isArray(shopData.coOwners)) {
    shopData.coOwners.forEach((id) => memberSet.add(id));
  }
  if (Array.isArray(shopData.editors)) {
    shopData.editors.forEach((id) => memberSet.add(id));
  }
  if (Array.isArray(shopData.viewers)) {
    shopData.viewers.forEach((id) => memberSet.add(id));
  }

  return Array.from(memberSet);
}

function getRecipientIds(reviewData, shopData = null) {
  let recipientIds = [];

  if (reviewData.isProductReview) {
    if (reviewData.isShopProduct && reviewData.shopId && shopData) {
      recipientIds = getShopMemberIds(shopData);
    } else if (reviewData.sellerId) {
      recipientIds = [reviewData.sellerId];
    }
  } else {
    // Seller review
    if (reviewData.shopId && shopData) {
      recipientIds = getShopMemberIds(shopData);
    } else if (reviewData.sellerId) {
      recipientIds = [reviewData.sellerId];
    }
  }

  // Exclude the reviewer
  return recipientIds.filter((id) => id !== reviewData.userId);
}

function buildNotificationDocument(reviewData, recipientId) {
  const notificationType = getNotificationType(reviewData);

  return {
    type: notificationType,
    productId: reviewData.productId,
    productName: reviewData.productName,
    sellerId: reviewData.sellerId,
    shopId: reviewData.shopId,
    reviewerId: reviewData.userId,
    reviewerName: reviewData.userName,
    rating: reviewData.rating,
    reviewText: reviewData.review,
    transactionId: reviewData.transactionId,
    orderId: reviewData.orderId,
    isShopProduct: reviewData.isShopProduct,
    isProductReview: reviewData.isProductReview,
    isRead: false,
    message: getNotificationMessage(reviewData, 'en'),
    message_en: getNotificationMessage(reviewData, 'en'),
    message_tr: getNotificationMessage(reviewData, 'tr'),
    message_ru: getNotificationMessage(reviewData, 'ru'),
  };
}

function getNotificationMessage(reviewData, lang) {
  const productName = reviewData.productName || 'your product';

  const messages = {
    en: {
      product: `You received a new review for your product: ${productName}`,
      seller: 'You received a new seller review',
    },
    tr: {
      product: `Ürününüz için yeni bir değerlendirme aldınız: ${productName}`,
      seller: 'Yeni bir satıcı değerlendirmesi aldınız',
    },
    ru: {
      product: `Вы получили новый отзыв о вашем продукте: ${productName}`,
      seller: 'Вы получили новый отзыв продавца',
    },
  };

  const langMessages = messages[lang] || messages.en;
  return reviewData.isProductReview ? langMessages.product : langMessages.seller;
}

// ============================================================================
// COLLECTION VALIDATION
// ============================================================================

function isValidCollection(collection) {
  return VALID_COLLECTIONS.includes(collection);
}

function getTargetCollection(isProduct, isShopProduct) {
  if (!isProduct) return null; // Seller reviews go to shops or users
  return isShopProduct ? 'shop_products' : 'products';
}

// ============================================================================
// RESPONSE BUILDING
// ============================================================================

function buildSuccessResponse() {
  return { success: true };
}

function buildErrorResponse(message) {
  return { success: false, message };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  MIN_RATING,
  MAX_RATING,
  VALID_COLLECTIONS,
  NOTIFICATION_TYPES,

  // Rating validation
  validateRating,
  isValidRating,

  // Review text validation
  validateReviewText,
  isValidReviewText,

  // Complete validation
  validateReviewInput,

  // Average calculation
  calculateNewAverage,
  calculateAverageFromRatings,

  // Review document
  buildReviewDocument,
  getProductImage,

  // Review flags
  buildReviewFlagsUpdate,
  canSubmitProductReview,
  canSubmitSellerReview,

  // Metrics processing
  shouldProcessMetrics,
  buildMetricsUpdate,
  buildMetricsProcessedUpdate,

  // Notifications
  getNotificationType,
  getShopMemberIds,
  getRecipientIds,
  buildNotificationDocument,
  getNotificationMessage,

  // Collection validation
  isValidCollection,
  getTargetCollection,

  // Response building
  buildSuccessResponse,
  buildErrorResponse,
};
