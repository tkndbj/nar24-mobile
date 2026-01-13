// functions/test/isbank-adpayment/ad-payment-utils.test.js
//
// Unit tests for ad payment utility functions
// Tests the EXACT logic from ad payment cloud functions
//
// Run: npx jest test/isbank-adpayment/ad-payment-utils.test.js

const {
    // Expiration date

    calculateExpirationDate,
    getDurationMs,
    getDurationDays,
    isValidDuration,
  
    // Ad collection
  
    getAdCollectionName,
    isValidAdType,
    getValidAdTypes,
  
    // Ad type labels
 
    getAdTypeLabel,
  
    // Payment amount
    AD_TAX_RATE,
    calculateAdPaymentAmount,
    formatAdPaymentAmount,
    calculateAdTaxAmount,
  
    // Order number
    generateAdOrderNumber,
    parseAdOrderNumber,
    isValidAdOrderNumber,
  
    // Submission validation

    canInitiatePayment,
    validateAdPaymentRequest,
    validateSubmissionForPayment,
  
    // Payment status
  
    isTerminalStatus,
    isProcessingStatus,
    canProceedWithPayment,
    getPaymentStatusCategory,
  
    // Color extraction
 
    requiresColorExtraction,
    shouldSkipColorExtraction,
  
    // Expiration
    canExpireSubmission,
    validateExpirationRequest,
  } = require('./ad-payment-utils');
  
  // ============================================================================
  // EXPIRATION DATE CALCULATION TESTS
  // ============================================================================
  describe('calculateExpirationDate', () => {
    const fixedNow = new Date('2024-06-15T12:00:00Z');
  
    test('calculates oneWeek expiration in production mode', () => {
      const result = calculateExpirationDate('oneWeek', { now: fixedNow, testMode: false });
      const expectedMs = fixedNow.getTime() + (7 * 24 * 60 * 60 * 1000);
      expect(result.getTime()).toBe(expectedMs);
    });
  
    test('calculates twoWeeks expiration in production mode', () => {
      const result = calculateExpirationDate('twoWeeks', { now: fixedNow, testMode: false });
      const expectedMs = fixedNow.getTime() + (14 * 24 * 60 * 60 * 1000);
      expect(result.getTime()).toBe(expectedMs);
    });
  
    test('calculates oneMonth expiration in production mode', () => {
      const result = calculateExpirationDate('oneMonth', { now: fixedNow, testMode: false });
      const expectedMs = fixedNow.getTime() + (30 * 24 * 60 * 60 * 1000);
      expect(result.getTime()).toBe(expectedMs);
    });
  
    test('defaults to oneWeek for invalid duration', () => {
      const result = calculateExpirationDate('invalidDuration', { now: fixedNow, testMode: false });
      const expectedMs = fixedNow.getTime() + (7 * 24 * 60 * 60 * 1000);
      expect(result.getTime()).toBe(expectedMs);
    });
  
    test('uses test durations in test mode', () => {
      const result = calculateExpirationDate('oneWeek', { now: fixedNow, testMode: true });
      const expectedMs = fixedNow.getTime() + (1 * 60 * 1000); // 1 minute
      expect(result.getTime()).toBe(expectedMs);
    });
  
    test('uses current time when now not provided', () => {
      const before = Date.now();
      const result = calculateExpirationDate('oneWeek', { testMode: false });
      const after = Date.now();
  
      const expectedMin = before + (7 * 24 * 60 * 60 * 1000);
      const expectedMax = after + (7 * 24 * 60 * 60 * 1000);
  
      expect(result.getTime()).toBeGreaterThanOrEqual(expectedMin);
      expect(result.getTime()).toBeLessThanOrEqual(expectedMax);
    });
  });
  
  describe('getDurationMs', () => {
    test('returns correct ms for oneWeek production', () => {
      expect(getDurationMs('oneWeek', false)).toBe(7 * 24 * 60 * 60 * 1000);
    });
  
    test('returns correct ms for twoWeeks production', () => {
      expect(getDurationMs('twoWeeks', false)).toBe(14 * 24 * 60 * 60 * 1000);
    });
  
    test('returns correct ms for oneMonth production', () => {
      expect(getDurationMs('oneMonth', false)).toBe(30 * 24 * 60 * 60 * 1000);
    });
  
    test('returns correct ms for test mode', () => {
      expect(getDurationMs('oneWeek', true)).toBe(1 * 60 * 1000);
      expect(getDurationMs('twoWeeks', true)).toBe(2 * 60 * 1000);
      expect(getDurationMs('oneMonth', true)).toBe(3 * 60 * 1000);
    });
  });
  
  describe('getDurationDays', () => {
    test('returns 7 for oneWeek', () => {
      expect(getDurationDays('oneWeek')).toBe(7);
    });
  
    test('returns 14 for twoWeeks', () => {
      expect(getDurationDays('twoWeeks')).toBe(14);
    });
  
    test('returns 30 for oneMonth', () => {
      expect(getDurationDays('oneMonth')).toBe(30);
    });
  
    test('returns 7 for invalid duration', () => {
      expect(getDurationDays('invalid')).toBe(7);
    });
  });
  
  describe('isValidDuration', () => {
    test('returns true for oneWeek', () => {
      expect(isValidDuration('oneWeek')).toBe(true);
    });
  
    test('returns true for twoWeeks', () => {
      expect(isValidDuration('twoWeeks')).toBe(true);
    });
  
    test('returns true for oneMonth', () => {
      expect(isValidDuration('oneMonth')).toBe(true);
    });
  
    test('returns false for invalid duration', () => {
      expect(isValidDuration('threeDays')).toBe(false);
      expect(isValidDuration('')).toBe(false);
      expect(isValidDuration(null)).toBe(false);
    });
  });
  
  // ============================================================================
  // AD COLLECTION NAME TESTS
  // ============================================================================
  describe('getAdCollectionName', () => {
    test('returns correct collection for topBanner', () => {
      expect(getAdCollectionName('topBanner')).toBe('market_top_ads_banners');
    });
  
    test('returns correct collection for thinBanner', () => {
      expect(getAdCollectionName('thinBanner')).toBe('market_thin_banners');
    });
  
    test('returns correct collection for marketBanner', () => {
      expect(getAdCollectionName('marketBanner')).toBe('market_banners');
    });
  
    test('returns default collection for unknown type', () => {
      expect(getAdCollectionName('unknownType')).toBe('market_banners');
    });
  
    test('returns default collection for null', () => {
      expect(getAdCollectionName(null)).toBe('market_banners');
    });
  
    test('returns default collection for undefined', () => {
      expect(getAdCollectionName(undefined)).toBe('market_banners');
    });
  });
  
  describe('isValidAdType', () => {
    test('returns true for topBanner', () => {
      expect(isValidAdType('topBanner')).toBe(true);
    });
  
    test('returns true for thinBanner', () => {
      expect(isValidAdType('thinBanner')).toBe(true);
    });
  
    test('returns true for marketBanner', () => {
      expect(isValidAdType('marketBanner')).toBe(true);
    });
  
    test('returns false for invalid type', () => {
      expect(isValidAdType('invalid')).toBe(false);
      expect(isValidAdType('')).toBe(false);
      expect(isValidAdType(null)).toBe(false);
    });
  });
  
  describe('getValidAdTypes', () => {
    test('returns all valid ad types', () => {
      const types = getValidAdTypes();
      expect(types).toContain('topBanner');
      expect(types).toContain('thinBanner');
      expect(types).toContain('marketBanner');
      expect(types.length).toBe(3);
    });
  });
  
  // ============================================================================
  // AD TYPE LABELS TESTS
  // ============================================================================
  describe('getAdTypeLabel', () => {
    test('returns Top Banner for topBanner', () => {
      expect(getAdTypeLabel('topBanner')).toBe('Top Banner');
    });
  
    test('returns Thin Banner for thinBanner', () => {
      expect(getAdTypeLabel('thinBanner')).toBe('Thin Banner');
    });
  
    test('returns Market Banner for marketBanner', () => {
      expect(getAdTypeLabel('marketBanner')).toBe('Market Banner');
    });
  
    test('returns default Banner for unknown type', () => {
      expect(getAdTypeLabel('unknownType')).toBe('Banner');
      expect(getAdTypeLabel(null)).toBe('Banner');
      expect(getAdTypeLabel(undefined)).toBe('Banner');
    });
  });
  
  // ============================================================================
  // AD PAYMENT AMOUNT TESTS (CRITICAL - MONEY)
  // ============================================================================
  describe('calculateAdPaymentAmount', () => {
    test('adds 20% tax to base amount', () => {
      expect(calculateAdPaymentAmount(100)).toBe(120);
    });
  
    test('rounds result', () => {
      expect(calculateAdPaymentAmount(99.99)).toBe(120); // 99.99 * 1.2 = 119.988 → 120
    });
  
    test('handles string amount', () => {
      expect(calculateAdPaymentAmount('100')).toBe(120);
    });
  
    test('handles decimal base amount', () => {
      expect(calculateAdPaymentAmount(150.50)).toBe(181); // 150.50 * 1.2 = 180.6 → 181
    });
  
    test('handles large amounts', () => {
      expect(calculateAdPaymentAmount(10000)).toBe(12000);
    });
  });
  
  describe('formatAdPaymentAmount', () => {
    test('returns string with tax included', () => {
      expect(formatAdPaymentAmount(100)).toBe('120');
    });
  
    test('returns string for decimal amount', () => {
      expect(formatAdPaymentAmount(99.99)).toBe('120');
    });
  });
  
  describe('calculateAdTaxAmount', () => {
    test('calculates 20% tax', () => {
      expect(calculateAdTaxAmount(100)).toBe(20);
    });
  
    test('rounds tax amount', () => {
      expect(calculateAdTaxAmount(99)).toBe(20); // 99 * 0.2 = 19.8 → 20
    });
  
    test('handles string amount', () => {
      expect(calculateAdTaxAmount('500')).toBe(100);
    });
  });
  
  describe('AD_TAX_RATE', () => {
    test('is 20%', () => {
      expect(AD_TAX_RATE).toBe(0.20);
    });
  });
  
  // ============================================================================
  // AD ORDER NUMBER TESTS
  // ============================================================================
  describe('generateAdOrderNumber', () => {
    test('generates correct format', () => {
      const result = generateAdOrderNumber('sub123', 1234567890);
      expect(result).toBe('AD-sub123-1234567890');
    });
  
    test('uses current timestamp when not provided', () => {
      const before = Date.now();
      const result = generateAdOrderNumber('sub456');
      const after = Date.now();
  
      expect(result).toMatch(/^AD-sub456-\d+$/);
  
      const parsed = parseAdOrderNumber(result);
      expect(parsed.timestamp).toBeGreaterThanOrEqual(before);
      expect(parsed.timestamp).toBeLessThanOrEqual(after);
    });
  });
  
  describe('parseAdOrderNumber', () => {
    test('parses valid order number', () => {
      const result = parseAdOrderNumber('AD-submission123-1234567890');
      expect(result).toEqual({
        submissionId: 'submission123',
        timestamp: 1234567890,
      });
    });
  
    test('handles submission ID with hyphens', () => {
      const result = parseAdOrderNumber('AD-sub-with-hyphens-1234567890');
      expect(result).toEqual({
        submissionId: 'sub-with-hyphens',
        timestamp: 1234567890,
      });
    });
  
    test('returns null for invalid format', () => {
      expect(parseAdOrderNumber('INVALID')).toBe(null);
      expect(parseAdOrderNumber('AD-noTimestamp')).toBe(null);
      expect(parseAdOrderNumber('ORDER-123-456')).toBe(null);
    });
  
    test('returns null for null input', () => {
      expect(parseAdOrderNumber(null)).toBe(null);
    });
  
    test('returns null for non-string input', () => {
      expect(parseAdOrderNumber(12345)).toBe(null);
    });
  });
  
  describe('isValidAdOrderNumber', () => {
    test('returns true for valid order number', () => {
      expect(isValidAdOrderNumber('AD-sub123-1234567890')).toBe(true);
    });
  
    test('returns false for invalid format', () => {
      expect(isValidAdOrderNumber('INVALID')).toBe(false);
      expect(isValidAdOrderNumber('ORDER-123')).toBe(false);
      expect(isValidAdOrderNumber(null)).toBe(false);
    });
  });
  
  // ============================================================================
  // SUBMISSION VALIDATION TESTS
  // ============================================================================
  describe('canInitiatePayment', () => {
    test('returns true for approved status', () => {
      expect(canInitiatePayment('approved')).toBe(true);
    });
  
    test('returns false for other statuses', () => {
      expect(canInitiatePayment('pending')).toBe(false);
      expect(canInitiatePayment('rejected')).toBe(false);
      expect(canInitiatePayment('active')).toBe(false);
      expect(canInitiatePayment('paid')).toBe(false);
    });
  });
  
  describe('validateAdPaymentRequest', () => {
    test('returns invalid for missing submissionId', () => {
      const result = validateAdPaymentRequest({ paymentLink: 'link123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_submission_id');
    });
  
    test('returns invalid for missing paymentLink', () => {
      const result = validateAdPaymentRequest({ submissionId: 'sub123' });
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing_payment_link');
    });
  
    test('returns invalid for null request', () => {
      const result = validateAdPaymentRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid for complete request', () => {
      const result = validateAdPaymentRequest({
        submissionId: 'sub123',
        paymentLink: 'link456',
      });
      expect(result.isValid).toBe(true);
    });
  });
  
  describe('validateSubmissionForPayment', () => {
    const validSubmission = {
      userId: 'user123',
      status: 'approved',
      paymentLink: 'link456',
    };
  
    test('returns invalid for null submission', () => {
      const result = validateSubmissionForPayment(null, 'user123', 'link456');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_found');
    });
  
    test('returns invalid for wrong user', () => {
      const result = validateSubmissionForPayment(validSubmission, 'differentUser', 'link456');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('unauthorized');
    });
  
    test('returns invalid for non-approved status', () => {
      const submission = { ...validSubmission, status: 'pending' };
      const result = validateSubmissionForPayment(submission, 'user123', 'link456');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_status');
    });
  
    test('returns invalid for wrong payment link', () => {
      const result = validateSubmissionForPayment(validSubmission, 'user123', 'wrongLink');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('invalid_payment_link');
    });
  
    test('returns valid for correct submission', () => {
      const result = validateSubmissionForPayment(validSubmission, 'user123', 'link456');
      expect(result.isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // PAYMENT STATUS TESTS
  // ============================================================================
  describe('isTerminalStatus', () => {
    test('returns true for completed', () => {
      expect(isTerminalStatus('completed')).toBe(true);
    });
  
    test('returns true for payment_succeeded_activation_failed', () => {
      expect(isTerminalStatus('payment_succeeded_activation_failed')).toBe(true);
    });
  
    test('returns true for payment_failed', () => {
      expect(isTerminalStatus('payment_failed')).toBe(true);
    });
  
    test('returns false for non-terminal statuses', () => {
      expect(isTerminalStatus('awaiting_3d')).toBe(false);
      expect(isTerminalStatus('processing')).toBe(false);
    });
  });
  
  describe('isProcessingStatus', () => {
    test('returns true for processing', () => {
      expect(isProcessingStatus('processing')).toBe(true);
    });
  
    test('returns true for payment_verified_activating_ad', () => {
      expect(isProcessingStatus('payment_verified_activating_ad')).toBe(true);
    });
  
    test('returns false for other statuses', () => {
      expect(isProcessingStatus('awaiting_3d')).toBe(false);
      expect(isProcessingStatus('completed')).toBe(false);
    });
  });
  
  describe('canProceedWithPayment', () => {
    test('returns true for awaiting_3d', () => {
      expect(canProceedWithPayment('awaiting_3d')).toBe(true);
    });
  
    test('returns false for other statuses', () => {
      expect(canProceedWithPayment('processing')).toBe(false);
      expect(canProceedWithPayment('completed')).toBe(false);
      expect(canProceedWithPayment('payment_failed')).toBe(false);
    });
  });
  
  describe('getPaymentStatusCategory', () => {
    test('returns terminal for terminal statuses', () => {
      expect(getPaymentStatusCategory('completed')).toBe('terminal');
      expect(getPaymentStatusCategory('payment_failed')).toBe('terminal');
    });
  
    test('returns processing for processing statuses', () => {
      expect(getPaymentStatusCategory('processing')).toBe('processing');
    });
  
    test('returns ready for awaiting_3d', () => {
      expect(getPaymentStatusCategory('awaiting_3d')).toBe('ready');
    });
  
    test('returns unknown for unknown status', () => {
      expect(getPaymentStatusCategory('unknown_status')).toBe('unknown');
    });
  });
  
  // ============================================================================
  // COLOR EXTRACTION TESTS
  // ============================================================================
  describe('requiresColorExtraction', () => {
    test('returns true for topBanner', () => {
      expect(requiresColorExtraction('topBanner')).toBe(true);
    });
  
    test('returns false for thinBanner', () => {
      expect(requiresColorExtraction('thinBanner')).toBe(false);
    });
  
    test('returns false for marketBanner', () => {
      expect(requiresColorExtraction('marketBanner')).toBe(false);
    });
  });
  
  describe('shouldSkipColorExtraction', () => {
    test('returns shouldSkip true for null data', () => {
      const result = shouldSkipColorExtraction(null);
      expect(result.shouldSkip).toBe(true);
      expect(result.reason).toBe('no_data');
    });
  
    test('returns shouldSkip true if color already extracted', () => {
      const result = shouldSkipColorExtraction({ dominantColor: 0xFF5733, isActive: true });
      expect(result.shouldSkip).toBe(true);
      expect(result.reason).toBe('already_extracted');
    });
  
    test('returns shouldSkip true if not active', () => {
      const result = shouldSkipColorExtraction({ dominantColor: null, isActive: false });
      expect(result.shouldSkip).toBe(true);
      expect(result.reason).toBe('not_active');
    });
  
    test('returns shouldSkip false for active ad without color', () => {
      const result = shouldSkipColorExtraction({ dominantColor: null, isActive: true });
      expect(result.shouldSkip).toBe(false);
    });
  
    test('handles undefined dominantColor', () => {
      const result = shouldSkipColorExtraction({ isActive: true });
      expect(result.shouldSkip).toBe(false);
    });
  });
  
  // ============================================================================
  // EXPIRATION VALIDATION TESTS
  // ============================================================================
  describe('canExpireSubmission', () => {
    test('returns true for active submission', () => {
      expect(canExpireSubmission({ status: 'active' })).toBe(true);
    });
  
    test('returns false for non-active submission', () => {
      expect(canExpireSubmission({ status: 'expired' })).toBe(false);
      expect(canExpireSubmission({ status: 'pending' })).toBe(false);
    });
  
    test('returns false for null submission', () => {
      expect(canExpireSubmission(null)).toBe(false);
    });
  });
  
  describe('validateExpirationRequest', () => {
    test('returns invalid for missing submissionId', () => {
      const result = validateExpirationRequest({});
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for null body', () => {
      const result = validateExpirationRequest(null);
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid with submissionId', () => {
      const result = validateExpirationRequest({ submissionId: 'sub123' });
      expect(result.isValid).toBe(true);
      expect(result.submissionId).toBe('sub123');
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete ad payment flow validation', () => {
      // 1. Validate request
      const requestResult = validateAdPaymentRequest({
        submissionId: 'sub123',
        paymentLink: 'link456',
      });
      expect(requestResult.isValid).toBe(true);
  
      // 2. Validate submission
      const submission = {
        userId: 'user123',
        status: 'approved',
        paymentLink: 'link456',
        price: 100,
        adType: 'topBanner',
        duration: 'oneWeek',
      };
      const submissionResult = validateSubmissionForPayment(submission, 'user123', 'link456');
      expect(submissionResult.isValid).toBe(true);
  
      // 3. Calculate payment amount
      const amount = calculateAdPaymentAmount(submission.price);
      expect(amount).toBe(120); // 100 + 20% tax
  
      // 4. Generate order number
      const orderNumber = generateAdOrderNumber('sub123', 1234567890);
      expect(orderNumber).toBe('AD-sub123-1234567890');
      expect(isValidAdOrderNumber(orderNumber)).toBe(true);
  
      // 5. Get collection name
      const collection = getAdCollectionName(submission.adType);
      expect(collection).toBe('market_top_ads_banners');
  
      // 6. Check if requires color extraction
      expect(requiresColorExtraction(submission.adType)).toBe(true);
  
      // 7. Calculate expiration
      const fixedNow = new Date('2024-06-15T12:00:00Z');
      const expiration = calculateExpirationDate(submission.duration, { now: fixedNow });
      const expectedExpiration = new Date(fixedNow.getTime() + (7 * 24 * 60 * 60 * 1000));
      expect(expiration.getTime()).toBe(expectedExpiration.getTime());
    });
  
    test('ad payment callback status handling', () => {
      // Initial status - can proceed
      expect(getPaymentStatusCategory('awaiting_3d')).toBe('ready');
      expect(canProceedWithPayment('awaiting_3d')).toBe(true);
  
      // Processing - another callback is handling
      expect(getPaymentStatusCategory('processing')).toBe('processing');
      expect(isProcessingStatus('processing')).toBe(true);
  
      // Terminal - already done
      expect(getPaymentStatusCategory('completed')).toBe('terminal');
      expect(isTerminalStatus('completed')).toBe(true);
    });
  
    test('ad expiration flow', () => {
      // Active ad can be expired
      const activeSubmission = { status: 'active', adType: 'thinBanner' };
      expect(canExpireSubmission(activeSubmission)).toBe(true);
  
      // Get label for notification
      const label = getAdTypeLabel(activeSubmission.adType);
      expect(label).toBe('Thin Banner');
  
      // Get collection for deactivation
      const collection = getAdCollectionName(activeSubmission.adType);
      expect(collection).toBe('market_thin_banners');
    });
  
    test('tax calculation for different amounts', () => {
      // Budget ad: 50 TL
      expect(calculateAdPaymentAmount(50)).toBe(60);
      expect(calculateAdTaxAmount(50)).toBe(10);
  
      // Standard ad: 200 TL
      expect(calculateAdPaymentAmount(200)).toBe(240);
      expect(calculateAdTaxAmount(200)).toBe(40);
  
      // Premium ad: 1000 TL
      expect(calculateAdPaymentAmount(1000)).toBe(1200);
      expect(calculateAdTaxAmount(1000)).toBe(200);
    });
  });
