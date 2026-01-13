// functions/src/utils/ad-payment-utils.js
//
// EXTRACTED PURE LOGIC from ad payment cloud functions
// These functions are EXACT COPIES of logic from the ad payment functions,
// extracted here for unit testing.
//
// ⚠️ IMPORTANT: Keep this file in sync with the source ad payment functions.
//
// Last synced with: ad payment functions (current version)

// ============================================================================
// EXPIRATION DATE CALCULATION
// Mirrors: calculateExpirationDate() in ad payment functions
// ============================================================================

/**
 * Production expiration durations in milliseconds
 */
const PRODUCTION_DURATIONS = {
    oneWeek: 7 * 24 * 60 * 60 * 1000,    // 7 days
    twoWeeks: 14 * 24 * 60 * 60 * 1000,  // 14 days
    oneMonth: 30 * 24 * 60 * 60 * 1000,  // 30 days
  };
  
  /**
   * Test mode durations in milliseconds (for testing)
   */
  const TEST_DURATIONS = {
    oneWeek: 1 * 60 * 1000,   // 1 minute
    twoWeeks: 2 * 60 * 1000,  // 2 minutes
    oneMonth: 3 * 60 * 1000,  // 3 minutes
  };

  function calculateExpirationDate(duration, options = {}) {
    const { now = new Date(), testMode = false } = options;
    const durations = testMode ? TEST_DURATIONS : PRODUCTION_DURATIONS;
  
    const durationMs = durations[duration] || durations.oneWeek; // Default to oneWeek
  
    return new Date(now.getTime() + durationMs);
  }

  function getDurationMs(duration, testMode = false) {
    const durations = testMode ? TEST_DURATIONS : PRODUCTION_DURATIONS;
    return durations[duration] || durations.oneWeek;
  }
  
  function getDurationDays(duration) {
    switch (duration) {
      case 'oneWeek':
        return 7;
      case 'twoWeeks':
        return 14;
      case 'oneMonth':
        return 30;
      default:
        return 7;
    }
  }

  function isValidDuration(duration) {
    return ['oneWeek', 'twoWeeks', 'oneMonth'].includes(duration);
  }
  
  // ============================================================================
  // AD COLLECTION NAME MAPPING
  // Mirrors: getAdCollectionName() in ad payment functions
  // ============================================================================
  
  /**
   * Ad type to Firestore collection name mapping
   */
  const AD_COLLECTION_MAP = {
    topBanner: 'market_top_ads_banners',
    thinBanner: 'market_thin_banners',
    marketBanner: 'market_banners',
  };

  function getAdCollectionName(adType) {
    return AD_COLLECTION_MAP[adType] || 'market_banners';
  }

  function isValidAdType(adType) {
    return Object.keys(AD_COLLECTION_MAP).includes(adType);
  }

  function getValidAdTypes() {
    return Object.keys(AD_COLLECTION_MAP);
  }
  
  // ============================================================================
  // AD TYPE LABELS
  // Mirrors: getAdTypeLabel() in ad payment functions
  // ============================================================================
  
  /**
   * Ad type to human-readable label mapping
   */
  const AD_TYPE_LABELS = {
    topBanner: 'Top Banner',
    thinBanner: 'Thin Banner',
    marketBanner: 'Market Banner',
  };

  function getAdTypeLabel(adType) {
    return AD_TYPE_LABELS[adType] || 'Banner';
  }
  
  // ============================================================================
  // AD PAYMENT AMOUNT CALCULATION
  // Mirrors: amount calculation in initializeIsbankAdPayment
  // ============================================================================
  
  /**
   * Tax rate for ad payments (20%)
   */
  const AD_TAX_RATE = 0.20;

  function calculateAdPaymentAmount(baseAmount) {
    return Math.round(parseFloat(baseAmount) * (1 + AD_TAX_RATE));
  }
 
  function formatAdPaymentAmount(baseAmount) {
    return calculateAdPaymentAmount(baseAmount).toString();
  }

  function calculateAdTaxAmount(baseAmount) {
    return Math.round(parseFloat(baseAmount) * AD_TAX_RATE);
  }
  
  // ============================================================================
  // AD ORDER NUMBER GENERATION
  // Mirrors: order number format in initializeIsbankAdPayment
  // ============================================================================
 
  function generateAdOrderNumber(submissionId, timestamp = Date.now()) {
    return `AD-${submissionId}-${timestamp}`;
  }

  function parseAdOrderNumber(orderNumber) {
    if (!orderNumber || typeof orderNumber !== 'string') {
      return null;
    }
  
    const match = orderNumber.match(/^AD-(.+)-(\d+)$/);
    if (!match) {
      return null;
    }
  
    return {
      submissionId: match[1],
      timestamp: parseInt(match[2], 10),
    };
  }
 
  function isValidAdOrderNumber(orderNumber) {
    return parseAdOrderNumber(orderNumber) !== null;
  }
  
  // ============================================================================
  // AD SUBMISSION VALIDATION
  // Mirrors: validation in initializeIsbankAdPayment
  // ============================================================================
  
  /**
   * Valid submission statuses that allow payment
   */
  const PAYABLE_STATUSES = ['approved'];

  function canInitiatePayment(status) {
    return PAYABLE_STATUSES.includes(status);
  }
 
  function validateAdPaymentRequest(requestData) {
    const { submissionId, paymentLink } = requestData || {};
  
    if (!submissionId) {
      return {
        isValid: false,
        reason: 'missing_submission_id',
        message: 'submissionId is required',
      };
    }
  
    if (!paymentLink) {
      return {
        isValid: false,
        reason: 'missing_payment_link',
        message: 'paymentLink is required',
      };
    }
  
    return {
      isValid: true,
    };
  }
 
  function validateSubmissionForPayment(submission, userId, paymentLink) {
    if (!submission) {
      return {
        isValid: false,
        reason: 'not_found',
        message: 'Ad submission not found',
      };
    }
  
    if (submission.userId !== userId) {
      return {
        isValid: false,
        reason: 'unauthorized',
        message: 'Unauthorized',
      };
    }
  
    if (submission.status !== 'approved') {
      return {
        isValid: false,
        reason: 'invalid_status',
        message: 'Ad submission must be approved',
      };
    }
  
    if (submission.paymentLink !== paymentLink) {
      return {
        isValid: false,
        reason: 'invalid_payment_link',
        message: 'Invalid payment link',
      };
    }
  
    return {
      isValid: true,
    };
  }
  
  // ============================================================================
  // AD PAYMENT STATUS VALIDATION
  // Mirrors: status checks in isbankAdPaymentCallback
  // ============================================================================
  
  /**
   * Terminal payment statuses (no further processing needed)
   */
  const TERMINAL_STATUSES = [
    'completed',
    'payment_succeeded_activation_failed',
    'payment_failed',
  ];
  
  /**
   * Processing statuses (another callback is handling)
   */
  const PROCESSING_STATUSES = [
    'processing',
    'payment_verified_activating_ad',
  ];
 
  function isTerminalStatus(status) {
    return TERMINAL_STATUSES.includes(status);
  }

  function isProcessingStatus(status) {
    return PROCESSING_STATUSES.includes(status);
  }

  function canProceedWithPayment(status) {
    return status === 'awaiting_3d';
  }

  function getPaymentStatusCategory(status) {
    if (isTerminalStatus(status)) return 'terminal';
    if (isProcessingStatus(status)) return 'processing';
    if (canProceedWithPayment(status)) return 'ready';
    return 'unknown';
  }
  
  // ============================================================================
  // COLOR EXTRACTION ELIGIBILITY
  // Mirrors: color extraction logic in isbankAdPaymentCallback
  // ============================================================================
  
  /**
   * Ad types that require dominant color extraction
   */
  const COLOR_EXTRACTION_AD_TYPES = ['topBanner'];

  function requiresColorExtraction(adType) {
    return COLOR_EXTRACTION_AD_TYPES.includes(adType);
  }

  function shouldSkipColorExtraction(adData) {
    if (!adData) {
      return { shouldSkip: true, reason: 'no_data' };
    }
  
    if (adData.dominantColor !== null && adData.dominantColor !== undefined) {
      return { shouldSkip: true, reason: 'already_extracted' };
    }
  
    if (!adData.isActive) {
      return { shouldSkip: true, reason: 'not_active' };
    }
  
    return { shouldSkip: false };
  }
  
  // ============================================================================
  // AD EXPIRATION VALIDATION
  // Mirrors: validation in processAdExpiration
  // ============================================================================
  
 
  function canExpireSubmission(submission) {
    return !!(submission && submission.status === 'active');
  }

  function validateExpirationRequest(requestBody) {
    const { submissionId } = requestBody || {};
  
    if (!submissionId) {
      return {
        isValid: false,
        message: 'submissionId is required',
      };
    }
  
    return {
      isValid: true,
      submissionId,
    };
  }
  
  // ============================================================================
  // EXPORTS
  // ============================================================================
  
  module.exports = {
    // Expiration date
    PRODUCTION_DURATIONS,
    TEST_DURATIONS,
    calculateExpirationDate,
    getDurationMs,
    getDurationDays,
    isValidDuration,
  
    // Ad collection
    AD_COLLECTION_MAP,
    getAdCollectionName,
    isValidAdType,
    getValidAdTypes,
  
    // Ad type labels
    AD_TYPE_LABELS,
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
    PAYABLE_STATUSES,
    canInitiatePayment,
    validateAdPaymentRequest,
    validateSubmissionForPayment,
  
    // Payment status
    TERMINAL_STATUSES,
    PROCESSING_STATUSES,
    isTerminalStatus,
    isProcessingStatus,
    canProceedWithPayment,
    getPaymentStatusCategory,
  
    // Color extraction
    COLOR_EXTRACTION_AD_TYPES,
    requiresColorExtraction,
    shouldSkipColorExtraction,
  
    // Expiration
    canExpireSubmission,
    validateExpirationRequest,
  };
