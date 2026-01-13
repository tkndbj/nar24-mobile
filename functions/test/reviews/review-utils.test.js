// functions/test/reviews/review-utils.test.js
//
// Unit tests for review system utility functions
// Tests the EXACT logic from review cloud functions
//
// Run: npx jest test/reviews/review-utils.test.js

const {
    MIN_RATING,
    MAX_RATING,
    VALID_COLLECTIONS,
    NOTIFICATION_TYPES,
  
    validateRating,
    isValidRating,
  
    validateReviewText,
    isValidReviewText,
  
    validateReviewInput,
  
    calculateNewAverage,
    calculateAverageFromRatings,
  
    buildReviewDocument,
    getProductImage,
  
    buildReviewFlagsUpdate,
    canSubmitProductReview,
    canSubmitSellerReview,
  
    shouldProcessMetrics,
    buildMetricsUpdate,
    buildMetricsProcessedUpdate,
  
    getNotificationType,
    getShopMemberIds,
    getRecipientIds,

    getNotificationMessage,
  
    isValidCollection,
    getTargetCollection,
  
    buildSuccessResponse,
    buildErrorResponse,
  } = require('./review-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('MIN_RATING is 1', () => {
      expect(MIN_RATING).toBe(1);
    });
  
    test('MAX_RATING is 5', () => {
      expect(MAX_RATING).toBe(5);
    });
  
    test('VALID_COLLECTIONS contains all valid collections', () => {
      expect(VALID_COLLECTIONS).toContain('products');
      expect(VALID_COLLECTIONS).toContain('shop_products');
      expect(VALID_COLLECTIONS).toContain('shops');
      expect(VALID_COLLECTIONS).toContain('users');
    });
  
    test('NOTIFICATION_TYPES has all types', () => {
      expect(NOTIFICATION_TYPES.PRODUCT_REVIEW_SHOP).toBe('product_review_shop');
      expect(NOTIFICATION_TYPES.PRODUCT_REVIEW_USER).toBe('product_review_user');
      expect(NOTIFICATION_TYPES.SELLER_REVIEW_SHOP).toBe('seller_review_shop');
      expect(NOTIFICATION_TYPES.SELLER_REVIEW_USER).toBe('seller_review_user');
    });
  });
  
  // ============================================================================
  // RATING VALIDATION TESTS
  // ============================================================================
  describe('validateRating', () => {
    test('returns invalid for null', () => {
      const result = validateRating(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for undefined', () => {
      const result = validateRating(undefined);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-number', () => {
      const result = validateRating('5');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_number');
    });
  
    test('returns invalid for NaN', () => {
      const result = validateRating(NaN);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('nan');
    });
  
    test('returns invalid for rating < 1', () => {
      const result = validateRating(0);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });
  
    test('returns invalid for rating > 5', () => {
      const result = validateRating(6);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('out_of_range');
    });
  
    test('returns invalid for decimal rating', () => {
      const result = validateRating(4.5);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_integer');
    });
  
    test('returns valid for rating 1', () => {
      expect(validateRating(1).isValid).toBe(true);
    });
  
    test('returns valid for rating 5', () => {
      expect(validateRating(5).isValid).toBe(true);
    });
  
    test('returns valid for rating 3', () => {
      expect(validateRating(3).isValid).toBe(true);
    });
  });
  
  describe('isValidRating', () => {
    test('returns true for valid ratings', () => {
      expect(isValidRating(1)).toBe(true);
      expect(isValidRating(3)).toBe(true);
      expect(isValidRating(5)).toBe(true);
    });
  
    test('returns false for invalid ratings', () => {
      expect(isValidRating(0)).toBe(false);
      expect(isValidRating(6)).toBe(false);
    });
  });
  
  // ============================================================================
  // REVIEW TEXT VALIDATION TESTS
  // ============================================================================
  describe('validateReviewText', () => {
    test('returns invalid for null', () => {
      const result = validateReviewText(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for non-string', () => {
      const result = validateReviewText(123);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns invalid for empty string', () => {
      const result = validateReviewText('');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty');
    });
  
    test('returns invalid for whitespace only', () => {
      const result = validateReviewText('   ');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty');
    });
  
    test('returns valid for non-empty string', () => {
      const result = validateReviewText('Great product!');
      expect(result.isValid).toBe(true);
      expect(result.sanitizedReview).toBe('Great product!');
    });
  
    test('trims whitespace', () => {
      const result = validateReviewText('  Good service  ');
      expect(result.sanitizedReview).toBe('Good service');
    });
  });
  
  describe('isValidReviewText', () => {
    test('returns true for valid text', () => {
      expect(isValidReviewText('Nice!')).toBe(true);
    });
  
    test('returns false for invalid text', () => {
      expect(isValidReviewText('')).toBe(false);
    });
  });
  
  // ============================================================================
  // COMPLETE INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateReviewInput', () => {
    const validProductReview = {
      rating: 5,
      review: 'Great product!',
      transactionId: 'tx123',
      orderId: 'order123',
      isProduct: true,
      productId: 'prod123',
    };
  
    const validSellerReview = {
      rating: 4,
      review: 'Good seller!',
      transactionId: 'tx123',
      orderId: 'order123',
      isProduct: false,
      sellerId: 'seller123',
    };
  
    test('returns valid for complete product review', () => {
      expect(validateReviewInput(validProductReview).isValid).toBe(true);
    });
  
    test('returns valid for complete seller review', () => {
      expect(validateReviewInput(validSellerReview).isValid).toBe(true);
    });
  
    test('returns invalid for missing rating', () => {
      const data = { ...validProductReview, rating: null };
      const result = validateReviewInput(data);
      expect(result.isValid).toBe(false);
      expect(result.errors.some((e) => e.field === 'rating')).toBe(true);
    });
  
    test('returns invalid for missing review text', () => {
      const data = { ...validProductReview, review: '' };
      const result = validateReviewInput(data);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for missing transactionId', () => {
      const data = { ...validProductReview, transactionId: null };
      const result = validateReviewInput(data);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for product review without productId', () => {
      const data = { ...validProductReview, productId: null };
      const result = validateReviewInput(data);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for seller review without sellerId or shopId', () => {
      const data = { ...validSellerReview, sellerId: null, shopId: null };
      const result = validateReviewInput(data);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for seller review with shopId', () => {
      const data = { ...validSellerReview, sellerId: null, shopId: 'shop123' };
      expect(validateReviewInput(data).isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // AVERAGE CALCULATION TESTS
  // ============================================================================
  describe('calculateNewAverage', () => {
    test('calculates correctly for first review', () => {
      const result = calculateNewAverage(0, 0, 5);
      expect(result.averageRating).toBe(5);
      expect(result.reviewCount).toBe(1);
    });
  
    test('calculates correctly for additional review', () => {
      const result = calculateNewAverage(4, 4, 5);
      expect(result.averageRating).toBe(4.2);
      expect(result.reviewCount).toBe(5);
    });
  
    test('handles null current average', () => {
      const result = calculateNewAverage(null, 0, 4);
      expect(result.averageRating).toBe(4);
      expect(result.reviewCount).toBe(1);
    });
  
    test('handles NaN current average', () => {
      const result = calculateNewAverage(NaN, 0, 3);
      expect(result.averageRating).toBe(3);
    });
  
    test('calculates running average correctly', () => {
      // Simulate: 4, 4, 4, 4 = avg 4, then add 5
      const result = calculateNewAverage(4, 4, 5);
      // (4*4 + 5) / 5 = 21/5 = 4.2
      expect(result.averageRating).toBe(4.2);
    });
  });
  
  describe('calculateAverageFromRatings', () => {
    test('calculates average from array', () => {
      const result = calculateAverageFromRatings([4, 5, 3, 5, 3]);
      expect(result.averageRating).toBe(4);
      expect(result.reviewCount).toBe(5);
    });
  
    test('handles empty array', () => {
      const result = calculateAverageFromRatings([]);
      expect(result.averageRating).toBe(0);
      expect(result.reviewCount).toBe(0);
    });
  
    test('filters invalid ratings', () => {
      const result = calculateAverageFromRatings([5, 'invalid', null, 5]);
      expect(result.averageRating).toBe(5);
      expect(result.reviewCount).toBe(2);
    });
  });
  
  // ============================================================================
  // REVIEW DOCUMENT TESTS
  // ============================================================================
  describe('buildReviewDocument', () => {
    const baseData = {
      rating: 5,
      review: '  Great product!  ',
      transactionId: 'tx123',
      orderId: 'order123',
      productId: 'prod123',
      isProduct: true,
      isShopProduct: false,
      imageUrls: ['img1.jpg'],
    };
  
    const reviewerInfo = { userId: 'user123', userName: 'John Doe' };
    const sellerInfo = { sellerId: 'seller123', sellerName: 'Acme Shop', shopId: null };
    const itemData = {
      productName: 'Widget',
      productImage: 'widget.jpg',
      price: 100,
      currency: 'TL',
      quantity: 2,
    };
  
    test('builds complete document', () => {
      const doc = buildReviewDocument(baseData, reviewerInfo, sellerInfo, itemData);
  
      expect(doc.rating).toBe(5);
      expect(doc.review).toBe('Great product!');
      expect(doc.userId).toBe('user123');
      expect(doc.userName).toBe('John Doe');
      expect(doc.productName).toBe('Widget');
      expect(doc.metricsProcessed).toBe(false);
    });
  
    test('sets null fields for seller review', () => {
      const sellerReviewData = { ...baseData, isProduct: false };
      const doc = buildReviewDocument(sellerReviewData, reviewerInfo, sellerInfo, itemData);
  
      expect(doc.productId).toBeNull();
      expect(doc.productName).toBeNull();
      expect(doc.isProductReview).toBe(false);
    });
  
    test('handles missing reviewer name', () => {
      const doc = buildReviewDocument(baseData, { userId: 'u1' }, sellerInfo, itemData);
      expect(doc.userName).toBe('Anonymous');
    });
  
    test('includes image URLs', () => {
      const doc = buildReviewDocument(baseData, reviewerInfo, sellerInfo, itemData);
      expect(doc.imageUrls).toEqual(['img1.jpg']);
    });
  });
  
  describe('getProductImage', () => {
    test('prefers selectedColorImage', () => {
      const itemData = { selectedColorImage: 'color.jpg', productImage: 'product.jpg' };
      expect(getProductImage(itemData)).toBe('color.jpg');
    });
  
    test('falls back to productImage', () => {
      const itemData = { productImage: 'product.jpg' };
      expect(getProductImage(itemData)).toBe('product.jpg');
    });
  
    test('returns null if no images', () => {
      expect(getProductImage({})).toBeNull();
    });
  });
  
  // ============================================================================
  // REVIEW FLAGS TESTS
  // ============================================================================
  describe('buildReviewFlagsUpdate', () => {
    test('clears product review flag', () => {
      const update = buildReviewFlagsUpdate(true, { needsSellerReview: true });
      expect(update.needsProductReview).toBe(false);
      expect(update.needsAnyReview).toBeUndefined();
    });
  
    test('clears needsAnyReview when both done', () => {
      const update = buildReviewFlagsUpdate(true, { needsSellerReview: false });
      expect(update.needsAnyReview).toBe(false);
    });
  
    test('clears seller review flag', () => {
      const update = buildReviewFlagsUpdate(false, { needsProductReview: true });
      expect(update.needsSellerReview).toBe(false);
    });
  });
  
  describe('canSubmitProductReview', () => {
    test('returns true when needed', () => {
      expect(canSubmitProductReview({ needsProductReview: true })).toBe(true);
    });
  
    test('returns false when not needed', () => {
      expect(canSubmitProductReview({ needsProductReview: false })).toBe(false);
    });
  });
  
  describe('canSubmitSellerReview', () => {
    test('returns true when needed', () => {
      expect(canSubmitSellerReview({ needsSellerReview: true })).toBe(true);
    });
  
    test('returns false when not needed', () => {
      expect(canSubmitSellerReview({ needsSellerReview: false })).toBe(false);
    });
  });
  
  // ============================================================================
  // METRICS PROCESSING TESTS
  // ============================================================================
  describe('shouldProcessMetrics', () => {
    test('returns true for unprocessed review', () => {
      expect(shouldProcessMetrics({ metricsProcessed: false })).toBe(true);
    });
  
    test('returns false for processed review', () => {
      expect(shouldProcessMetrics({ metricsProcessed: true })).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(shouldProcessMetrics(null)).toBe(false);
    });
  
    test('returns true when flag missing', () => {
      expect(shouldProcessMetrics({})).toBe(true);
    });
  });
  
  describe('buildMetricsUpdate', () => {
    test('builds metrics update', () => {
      const update = buildMetricsUpdate(4.5, 10);
      expect(update.averageRating).toBe(4.5);
      expect(update.reviewCount).toBe(10);
    });
  });
  
  describe('buildMetricsProcessedUpdate', () => {
    test('builds processed flag update', () => {
      const update = buildMetricsProcessedUpdate();
      expect(update.metricsProcessed).toBe(true);
    });
  });
  
  // ============================================================================
  // NOTIFICATION TESTS
  // ============================================================================
  describe('getNotificationType', () => {
    test('returns product_review_shop for shop product', () => {
      const reviewData = { isProductReview: true, isShopProduct: true, shopId: 'shop1' };
      expect(getNotificationType(reviewData)).toBe('product_review_shop');
    });
  
    test('returns product_review_user for user product', () => {
      const reviewData = { isProductReview: true, isShopProduct: false };
      expect(getNotificationType(reviewData)).toBe('product_review_user');
    });
  
    test('returns seller_review_shop for shop seller review', () => {
      const reviewData = { isProductReview: false, shopId: 'shop1' };
      expect(getNotificationType(reviewData)).toBe('seller_review_shop');
    });
  
    test('returns seller_review_user for user seller review', () => {
      const reviewData = { isProductReview: false, shopId: null };
      expect(getNotificationType(reviewData)).toBe('seller_review_user');
    });
  });
  
  describe('getShopMemberIds', () => {
    test('collects all members', () => {
      const shopData = {
        ownerId: 'owner1',
        coOwners: ['co1', 'co2'],
        editors: ['ed1'],
        viewers: ['v1'],
      };
      const members = getShopMemberIds(shopData);
      expect(members).toContain('owner1');
      expect(members).toContain('co1');
      expect(members).toContain('ed1');
      expect(members.length).toBe(5);
    });
  
    test('handles missing arrays', () => {
      const shopData = { ownerId: 'owner1' };
      const members = getShopMemberIds(shopData);
      expect(members).toEqual(['owner1']);
    });
  });
  
  describe('getRecipientIds', () => {
    const shopData = { ownerId: 'owner1', coOwners: ['co1'] };
  
    test('excludes reviewer', () => {
      const reviewData = { isProductReview: true, isShopProduct: true, shopId: 'shop1', userId: 'owner1' };
      const recipients = getRecipientIds(reviewData, shopData);
      expect(recipients).not.toContain('owner1');
      expect(recipients).toContain('co1');
    });
  
    test('returns seller for user product', () => {
      const reviewData = { isProductReview: true, isShopProduct: false, sellerId: 'seller1', userId: 'user1' };
      const recipients = getRecipientIds(reviewData);
      expect(recipients).toEqual(['seller1']);
    });
  
    test('returns empty if reviewer is only recipient', () => {
      const reviewData = { isProductReview: false, sellerId: 'user1', userId: 'user1' };
      const recipients = getRecipientIds(reviewData);
      expect(recipients).toEqual([]);
    });
  });
  
  describe('getNotificationMessage', () => {
    test('returns English product message', () => {
      const reviewData = { isProductReview: true, productName: 'Widget' };
      const message = getNotificationMessage(reviewData, 'en');
      expect(message).toContain('Widget');
      expect(message).toContain('new review');
    });
  
    test('returns Turkish seller message', () => {
      const reviewData = { isProductReview: false };
      const message = getNotificationMessage(reviewData, 'tr');
      expect(message).toContain('satıcı değerlendirmesi');
    });
  
    test('returns Russian product message', () => {
      const reviewData = { isProductReview: true, productName: 'Товар' };
      const message = getNotificationMessage(reviewData, 'ru');
      expect(message).toContain('Товар');
    });
  
    test('defaults to English for unknown language', () => {
      const reviewData = { isProductReview: true, productName: 'Test' };
      const message = getNotificationMessage(reviewData, 'de');
      expect(message).toContain('new review');
    });
  });
  
  // ============================================================================
  // COLLECTION VALIDATION TESTS
  // ============================================================================
  describe('isValidCollection', () => {
    test('returns true for valid collections', () => {
      expect(isValidCollection('products')).toBe(true);
      expect(isValidCollection('shop_products')).toBe(true);
      expect(isValidCollection('shops')).toBe(true);
      expect(isValidCollection('users')).toBe(true);
    });
  
    test('returns false for invalid collections', () => {
      expect(isValidCollection('orders')).toBe(false);
      expect(isValidCollection('invalid')).toBe(false);
    });
  });
  
  describe('getTargetCollection', () => {
    test('returns shop_products for shop product', () => {
      expect(getTargetCollection(true, true)).toBe('shop_products');
    });
  
    test('returns products for user product', () => {
      expect(getTargetCollection(true, false)).toBe('products');
    });
  
    test('returns null for seller review', () => {
      expect(getTargetCollection(false, false)).toBeNull();
    });
  });
  
  // ============================================================================
  // RESPONSE TESTS
  // ============================================================================
  describe('buildSuccessResponse', () => {
    test('builds success response', () => {
      const response = buildSuccessResponse();
      expect(response.success).toBe(true);
    });
  });
  
  describe('buildErrorResponse', () => {
    test('builds error response', () => {
      const response = buildErrorResponse('Test error');
      expect(response.success).toBe(false);
      expect(response.message).toBe('Test error');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete product review flow', () => {
      // 1. Validate input
      const input = {
        rating: 5,
        review: 'Excellent quality!',
        transactionId: 'tx123',
        orderId: 'order456',
        isProduct: true,
        productId: 'prod789',
      };
      expect(validateReviewInput(input).isValid).toBe(true);
  
      // 2. Check if can submit
      const itemData = { needsProductReview: true, needsSellerReview: true };
      expect(canSubmitProductReview(itemData)).toBe(true);
  
      // 3. Build review document
      const reviewerInfo = { userId: 'buyer1', userName: 'Jane' };
      const sellerInfo = { sellerId: 'seller1', sellerName: 'Acme' };
      const doc = buildReviewDocument(input, reviewerInfo, sellerInfo, { productName: 'Widget' });
      expect(doc.metricsProcessed).toBe(false);
  
      // 4. Calculate new metrics
      const oldAvg = 4.0;
      const oldCount = 10;
      const metrics = calculateNewAverage(oldAvg, oldCount, 5);
      expect(metrics.reviewCount).toBe(11);
      expect(metrics.averageRating).toBeCloseTo(4.09, 1);
  
      // 5. Update flags
      const flagUpdate = buildReviewFlagsUpdate(true, itemData);
      expect(flagUpdate.needsProductReview).toBe(false);
    });
  
    test('shop seller review with notifications', () => {
      const reviewData = {
        isProductReview: false,
        shopId: 'shop123',
        userId: 'buyer1',
        userName: 'John',
        rating: 4,
        review: 'Good service',
      };
  
      const shopData = {
        ownerId: 'owner1',
        coOwners: ['co1'],
        editors: ['buyer1'], // Buyer is also an editor
      };
  
      // Get notification type
      const type = getNotificationType(reviewData);
      expect(type).toBe('seller_review_shop');
  
      // Get recipients (should exclude buyer)
      const recipients = getRecipientIds(reviewData, shopData);
      expect(recipients).not.toContain('buyer1');
      expect(recipients).toContain('owner1');
      expect(recipients).toContain('co1');
  
      // Get message
      const message = getNotificationMessage(reviewData, 'en');
      expect(message).toContain('seller review');
    });
  });
