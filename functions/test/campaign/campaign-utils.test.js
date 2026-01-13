// functions/test/campaign/campaign-utils.test.js
//
// Unit tests for campaign deletion utility functions
// Tests the EXACT logic from campaign deletion cloud functions
//
// Run: npx jest test/campaign/campaign-utils.test.js

const {
    BATCH_SIZE,
    PROGRESS_UPDATE_INTERVAL,
    DEFAULT_MAX_RETRIES,
    CLEANUP_AGE_DAYS,
    QUEUE_STATUS,
    CAMPAIGN_STATUS,
  
    validateCampaignId,
    validateQueueLookupInput,
  
    buildQueueDocument,
    buildRetryQueueDocument,
  
    buildProductUpdateData,
    shouldRevertPrice,
    getCampaignFieldsToDelete,
  
    calculateProgress,
    shouldUpdateProgress,
    isLastBatch,
  
    shouldRetry,
    getNextRetryCount,
    hasExhaustedRetries,
    buildErrorEntry,
  
    estimateTimeRemaining,
    calculateProcessingDuration,
  
    buildStatusResponse,
    buildNotFoundResponse,
    buildInitiateResponse,
  
    buildProcessingResult,
    buildBatchResult,
    aggregateBatchResults,
  
    buildDeletingStatusUpdate,
    buildDeletionFailedStatusUpdate,

    buildProgressUpdate,
  
    isQueueItemStale,
    shouldCleanupQueueItem,
    getCleanupCutoffDate,
  
    isDeletionInProgress,
    getActiveQueueStatuses,
  } = require('./campaign-utils');
  
  // ============================================================================
  // CONSTANTS TESTS
  // ============================================================================
  describe('Constants', () => {
    test('BATCH_SIZE is 450', () => {
      expect(BATCH_SIZE).toBe(450);
    });
  
    test('PROGRESS_UPDATE_INTERVAL is 5', () => {
      expect(PROGRESS_UPDATE_INTERVAL).toBe(5);
    });
  
    test('DEFAULT_MAX_RETRIES is 3', () => {
      expect(DEFAULT_MAX_RETRIES).toBe(3);
    });
  
    test('CLEANUP_AGE_DAYS is 7', () => {
      expect(CLEANUP_AGE_DAYS).toBe(7);
    });
  
    test('QUEUE_STATUS has all statuses', () => {
      expect(QUEUE_STATUS.PENDING).toBe('pending');
      expect(QUEUE_STATUS.PROCESSING).toBe('processing');
      expect(QUEUE_STATUS.COMPLETED).toBe('completed');
      expect(QUEUE_STATUS.FAILED).toBe('failed');
      expect(QUEUE_STATUS.RETRYING).toBe('retrying');
    });
  
    test('CAMPAIGN_STATUS has all statuses', () => {
      expect(CAMPAIGN_STATUS.ACTIVE).toBe('active');
      expect(CAMPAIGN_STATUS.DELETING).toBe('deleting');
      expect(CAMPAIGN_STATUS.DELETION_FAILED).toBe('deletion_failed');
    });
  });
  
  // ============================================================================
  // INPUT VALIDATION TESTS
  // ============================================================================
  describe('validateCampaignId', () => {
    test('returns invalid for null', () => {
      const result = validateCampaignId(null);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('missing');
    });
  
    test('returns invalid for undefined', () => {
      const result = validateCampaignId(undefined);
      expect(result.isValid).toBe(false);
    });
  
    test('returns invalid for non-string', () => {
      const result = validateCampaignId(12345);
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('not_string');
    });
  
    test('returns invalid for empty string', () => {
      const result = validateCampaignId('   ');
      expect(result.isValid).toBe(false);
      expect(result.reason).toBe('empty');
    });
  
    test('returns valid for valid ID', () => {
      expect(validateCampaignId('campaign123').isValid).toBe(true);
    });
  });
  
  describe('validateQueueLookupInput', () => {
    test('returns invalid when neither provided', () => {
      const result = validateQueueLookupInput({});
      expect(result.isValid).toBe(false);
    });
  
    test('returns valid with queueId', () => {
      expect(validateQueueLookupInput({ queueId: 'q1' }).isValid).toBe(true);
    });
  
    test('returns valid with campaignId', () => {
      expect(validateQueueLookupInput({ campaignId: 'c1' }).isValid).toBe(true);
    });
  });
  
  // ============================================================================
  // QUEUE DOCUMENT TESTS
  // ============================================================================
  describe('buildQueueDocument', () => {
    test('builds complete document', () => {
      const doc = buildQueueDocument('campaign1', 'Summer Sale', 100, 'user1');
      
      expect(doc.campaignId).toBe('campaign1');
      expect(doc.campaignName).toBe('Summer Sale');
      expect(doc.totalProducts).toBe(100);
      expect(doc.createdBy).toBe('user1');
      expect(doc.status).toBe('pending');
      expect(doc.retryCount).toBe(0);
      expect(doc.maxRetries).toBe(3);
      expect(doc.productsProcessed).toBe(0);
    });
  
    test('handles missing campaign name', () => {
      const doc = buildQueueDocument('c1', null, 50, 'user1');
      expect(doc.campaignName).toBe('Unnamed Campaign');
    });
  
    test('handles missing createdBy', () => {
      const doc = buildQueueDocument('c1', 'Test', 50, null);
      expect(doc.createdBy).toBe('system');
    });
  });
  
  describe('buildRetryQueueDocument', () => {
    test('builds retry document with new count', () => {
      const original = { campaignId: 'c1', retryCount: 1 };
      const retry = buildRetryQueueDocument(original, 2);
      
      expect(retry.campaignId).toBe('c1');
      expect(retry.retryCount).toBe(2);
      expect(retry.status).toBe('pending');
    });
  });
  
  // ============================================================================
  // PRODUCT UPDATE TESTS
  // ============================================================================
  describe('shouldRevertPrice', () => {
    test('returns true for valid originalPrice', () => {
      expect(shouldRevertPrice({ originalPrice: 100 })).toBe(true);
    });
  
    test('returns true for zero price', () => {
      expect(shouldRevertPrice({ originalPrice: 0 })).toBe(true);
    });
  
    test('returns false for null originalPrice', () => {
      expect(shouldRevertPrice({ originalPrice: null })).toBe(false);
    });
  
    test('returns false for undefined originalPrice', () => {
      expect(shouldRevertPrice({})).toBe(false);
    });
  
    test('returns false for non-number originalPrice', () => {
      expect(shouldRevertPrice({ originalPrice: '100' })).toBe(false);
    });
  
    test('returns false for NaN', () => {
      expect(shouldRevertPrice({ originalPrice: NaN })).toBe(false);
    });
  
    test('returns false for negative price', () => {
      expect(shouldRevertPrice({ originalPrice: -10 })).toBe(false);
    });
  
    test('returns false for null productData', () => {
      expect(shouldRevertPrice(null)).toBe(false);
    });
  });
  
  describe('buildProductUpdateData', () => {
    test('includes price revert when originalPrice exists', () => {
      const productData = { originalPrice: 150 };
      const update = buildProductUpdateData(productData);
      
      expect(update.priceRevert).not.toBeNull();
      expect(update.priceRevert.newPrice).toBe(150);
    });
  
    test('has null priceRevert when no originalPrice', () => {
      const productData = { price: 100 };
      const update = buildProductUpdateData(productData);
      
      expect(update.priceRevert).toBeNull();
    });
  
    test('includes all campaign fields to delete', () => {
      const update = buildProductUpdateData({});
      
      expect(update.fieldsToDelete).toContain('campaign');
      expect(update.fieldsToDelete).toContain('campaignName');
      expect(update.fieldsToDelete).toContain('campaignDiscount');
      expect(update.fieldsToDelete).toContain('campaignPrice');
      expect(update.fieldsToDelete).toContain('discountPercentage');
    });
  });
  
  describe('getCampaignFieldsToDelete', () => {
    test('returns all campaign fields', () => {
      const fields = getCampaignFieldsToDelete();
      expect(fields).toContain('campaign');
      expect(fields).toContain('originalPrice');
      expect(fields.length).toBe(6);
    });
  });
  
  // ============================================================================
  // PROGRESS TESTS
  // ============================================================================
  describe('calculateProgress', () => {
    test('calculates correct percentage', () => {
      expect(calculateProgress(50, 100)).toBe(50);
      expect(calculateProgress(25, 100)).toBe(25);
      expect(calculateProgress(100, 100)).toBe(100);
    });
  
    test('rounds to integer', () => {
      expect(calculateProgress(33, 100)).toBe(33);
      expect(calculateProgress(1, 3)).toBe(33);
    });
  
    test('returns 0 for zero total', () => {
      expect(calculateProgress(50, 0)).toBe(0);
    });
  
    test('returns 0 for null processed', () => {
      expect(calculateProgress(null, 100)).toBe(0);
    });
  
    test('caps at 100%', () => {
      expect(calculateProgress(150, 100)).toBe(100);
    });
  });
  
  describe('shouldUpdateProgress', () => {
    test('returns true at interval', () => {
      expect(shouldUpdateProgress(5, 5)).toBe(true);
      expect(shouldUpdateProgress(10, 5)).toBe(true);
    });
  
    test('returns false between intervals', () => {
      expect(shouldUpdateProgress(3, 5)).toBe(false);
      expect(shouldUpdateProgress(7, 5)).toBe(false);
    });
  
    test('returns false for zero', () => {
      expect(shouldUpdateProgress(0, 5)).toBe(false);
    });
  });
  
  describe('isLastBatch', () => {
    test('returns true when under batch size', () => {
      expect(isLastBatch(200, 450)).toBe(true);
    });
  
    test('returns false when at batch size', () => {
      expect(isLastBatch(450, 450)).toBe(false);
    });
  });
  
  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  describe('shouldRetry', () => {
    test('returns true when under max', () => {
      expect(shouldRetry(0, 3)).toBe(true);
      expect(shouldRetry(2, 3)).toBe(true);
    });
  
    test('returns false when at max', () => {
      expect(shouldRetry(3, 3)).toBe(false);
    });
  
    test('returns false when over max', () => {
      expect(shouldRetry(5, 3)).toBe(false);
    });
  
    test('handles null as 0', () => {
      expect(shouldRetry(null, 3)).toBe(true);
    });
  });
  
  describe('getNextRetryCount', () => {
    test('increments count', () => {
      expect(getNextRetryCount(0)).toBe(1);
      expect(getNextRetryCount(2)).toBe(3);
    });
  
    test('handles null as 0', () => {
      expect(getNextRetryCount(null)).toBe(1);
    });
  });
  
  describe('hasExhaustedRetries', () => {
    test('returns true at max', () => {
      expect(hasExhaustedRetries(3, 3)).toBe(true);
    });
  
    test('returns false under max', () => {
      expect(hasExhaustedRetries(2, 3)).toBe(false);
    });
  });
  
  describe('buildErrorEntry', () => {
    test('builds error entry', () => {
      const entry = buildErrorEntry('Test error', 2, false);
      expect(entry.message).toBe('Test error');
      expect(entry.retryAttempt).toBe(2);
      expect(entry.final).toBe(false);
    });
  
    test('marks final error', () => {
      const entry = buildErrorEntry('Final error', 3, true);
      expect(entry.final).toBe(true);
    });
  });
  
  // ============================================================================
  // TIME ESTIMATION TESTS
  // ============================================================================
  describe('estimateTimeRemaining', () => {
    const now = Date.now();
    const oneMinuteAgo = now - 60000;
  
    test('returns null for non-processing status', () => {
      const queueData = { status: 'pending' };
      expect(estimateTimeRemaining(queueData)).toBeNull();
    });
  
    test('returns null without start time', () => {
      const queueData = { status: 'processing', productsProcessed: 50 };
      expect(estimateTimeRemaining(queueData)).toBeNull();
    });
  
    test('returns null without progress', () => {
      const queueData = { 
        status: 'processing', 
        processingStartedAt: { toMillis: () => oneMinuteAgo },
        productsProcessed: 0,
      };
      expect(estimateTimeRemaining(queueData)).toBeNull();
    });
  
    test('calculates estimate correctly', () => {
      const queueData = {
        status: 'processing',
        processingStartedAt: { toMillis: () => oneMinuteAgo },
        productsProcessed: 50,
        totalProducts: 100,
      };
      const estimate = estimateTimeRemaining(queueData, now);
      
      expect(estimate).not.toBeNull();
      expect(estimate.milliseconds).toBeGreaterThan(0);
      expect(estimate.seconds).toBeGreaterThan(0);
    });
  
    test('returns null when complete', () => {
      const queueData = {
        status: 'processing',
        processingStartedAt: { toMillis: () => oneMinuteAgo },
        productsProcessed: 100,
        totalProducts: 100,
      };
      expect(estimateTimeRemaining(queueData, now)).toBeNull();
    });
  });
  
  describe('calculateProcessingDuration', () => {
    test('calculates duration', () => {
      const start = Date.now() - 60000;
      const end = Date.now();
      const duration = calculateProcessingDuration(start, end);
      expect(duration).toBeGreaterThanOrEqual(59000);
      expect(duration).toBeLessThanOrEqual(61000);
    });
  });
  
  // ============================================================================
  // STATUS RESPONSE TESTS
  // ============================================================================
  describe('buildStatusResponse', () => {
    test('builds complete response', () => {
      const queueData = {
        status: 'processing',
        campaignId: 'c1',
        campaignName: 'Test Campaign',
        totalProducts: 100,
        productsProcessed: 50,
        productsReverted: 45,
        productsFailed: 5,
        retryCount: 1,
        maxRetries: 3,
        errors: [{ message: 'error' }],
      };
      const response = buildStatusResponse(queueData, 'q1');
  
      expect(response.found).toBe(true);
      expect(response.queueId).toBe('q1');
      expect(response.progress).toBe(50);
      expect(response.productsReverted).toBe(45);
    });
  });
  
  describe('buildNotFoundResponse', () => {
    test('builds not found response', () => {
      const response = buildNotFoundResponse();
      expect(response.found).toBe(false);
      expect(response.message).toBe('Queue document not found');
    });
  
    test('accepts custom message', () => {
      const response = buildNotFoundResponse('Custom message');
      expect(response.message).toBe('Custom message');
    });
  });
  
  describe('buildInitiateResponse', () => {
    test('builds initiate response', () => {
      const response = buildInitiateResponse('q1', 100);
      expect(response.success).toBe(true);
      expect(response.queueId).toBe('q1');
      expect(response.totalProducts).toBe(100);
      expect(response.message).toContain('100');
    });
  });
  
  // ============================================================================
  // PROCESSING RESULT TESTS
  // ============================================================================
  describe('buildProcessingResult', () => {
    test('builds processing result', () => {
      const result = buildProcessingResult(100, 95, 5, 60000, 10);
      
      expect(result.totalProcessed).toBe(100);
      expect(result.totalReverted).toBe(95);
      expect(result.totalFailed).toBe(5);
      expect(result.duration).toBe(60000);
      expect(result.batchesProcessed).toBe(10);
    });
  });
  
  describe('buildBatchResult', () => {
    test('builds batch result', () => {
      const result = buildBatchResult(10, 8, 2);
      
      expect(result.processed).toBe(10);
      expect(result.reverted).toBe(8);
      expect(result.failed).toBe(2);
    });
  });
  
  describe('aggregateBatchResults', () => {
    test('aggregates results', () => {
      const current = { totalProcessed: 50, totalReverted: 45, totalFailed: 5 };
      const batch = { processed: 10, reverted: 9, failed: 1 };
      const result = aggregateBatchResults(current, batch);
  
      expect(result.totalProcessed).toBe(60);
      expect(result.totalReverted).toBe(54);
      expect(result.totalFailed).toBe(6);
    });
  });
  
  // ============================================================================
  // CAMPAIGN STATUS TESTS
  // ============================================================================
  describe('buildDeletingStatusUpdate', () => {
    test('builds deleting status', () => {
      const update = buildDeletingStatusUpdate('user1');
      expect(update.status).toBe('deleting');
      expect(update.deletionStartedBy).toBe('user1');
    });
  
    test('defaults to system', () => {
      const update = buildDeletingStatusUpdate(null);
      expect(update.deletionStartedBy).toBe('system');
    });
  });
  
  describe('buildDeletionFailedStatusUpdate', () => {
    test('builds failed status', () => {
      const update = buildDeletionFailedStatusUpdate('Error message');
      expect(update.status).toBe('deletion_failed');
      expect(update.deletionError).toBe('Error message');
    });
  });
  
  // ============================================================================
  // QUEUE STATUS TESTS
  // ============================================================================
  describe('buildProgressUpdate', () => {
    test('builds progress update', () => {
      const update = buildProgressUpdate(50, 45, 5, 'doc123', 100);
      
      expect(update.productsProcessed).toBe(50);
      expect(update.productsReverted).toBe(45);
      expect(update.productsFailed).toBe(5);
      expect(update.lastProcessedDocId).toBe('doc123');
      expect(update.progress).toBe(50);
    });
  });
  
  // ============================================================================
  // CLEANUP TESTS
  // ============================================================================
  describe('isQueueItemStale', () => {
    const now = Date.now();
    const eightDaysAgo = now - (8 * 24 * 60 * 60 * 1000);
    const sixDaysAgo = now - (6 * 24 * 60 * 60 * 1000);
  
    test('returns true for old items', () => {
      const createdAt = { toMillis: () => eightDaysAgo };
      expect(isQueueItemStale(createdAt, 7, now)).toBe(true);
    });
  
    test('returns false for recent items', () => {
      const createdAt = { toMillis: () => sixDaysAgo };
      expect(isQueueItemStale(createdAt, 7, now)).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isQueueItemStale(null, 7, now)).toBe(false);
    });
  });
  
  describe('shouldCleanupQueueItem', () => {
    const now = Date.now();
    const eightDaysAgo = now - (8 * 24 * 60 * 60 * 1000);
  
    test('returns true for old completed items', () => {
      const queueData = {
        status: 'completed',
        createdAt: { toMillis: () => eightDaysAgo },
      };
      expect(shouldCleanupQueueItem(queueData, 7)).toBe(true);
    });
  
    test('returns true for old failed items', () => {
      const queueData = {
        status: 'failed',
        createdAt: { toMillis: () => eightDaysAgo },
      };
      expect(shouldCleanupQueueItem(queueData, 7)).toBe(true);
    });
  
    test('returns false for processing items', () => {
      const queueData = {
        status: 'processing',
        createdAt: { toMillis: () => eightDaysAgo },
      };
      expect(shouldCleanupQueueItem(queueData, 7)).toBe(false);
    });
  });
  
  describe('getCleanupCutoffDate', () => {
    test('returns date 7 days ago', () => {
      const now = new Date('2024-06-15');
      const cutoff = getCleanupCutoffDate(7, now);
      expect(cutoff.getDate()).toBe(8); // June 8
    });
  });
  
  // ============================================================================
  // DUPLICATE DETECTION TESTS
  // ============================================================================
  describe('isDeletionInProgress', () => {
    test('returns true for pending items', () => {
      const items = [{ status: 'pending' }];
      expect(isDeletionInProgress(items)).toBe(true);
    });
  
    test('returns true for processing items', () => {
      const items = [{ status: 'processing' }];
      expect(isDeletionInProgress(items)).toBe(true);
    });
  
    test('returns false for completed items', () => {
      const items = [{ status: 'completed' }];
      expect(isDeletionInProgress(items)).toBe(false);
    });
  
    test('returns false for empty array', () => {
      expect(isDeletionInProgress([])).toBe(false);
    });
  
    test('returns false for null', () => {
      expect(isDeletionInProgress(null)).toBe(false);
    });
  });
  
  describe('getActiveQueueStatuses', () => {
    test('returns pending and processing', () => {
      const statuses = getActiveQueueStatuses();
      expect(statuses).toContain('pending');
      expect(statuses).toContain('processing');
      expect(statuses.length).toBe(2);
    });
  });
  
  // ============================================================================
  // REAL-WORLD SCENARIO TESTS
  // ============================================================================
  describe('Real-World Scenarios', () => {
    test('complete campaign deletion flow', () => {
      // 1. Validate input
      const campaignId = 'campaign123';
      expect(validateCampaignId(campaignId).isValid).toBe(true);
  
      // 2. Build queue document
      const queueDoc = buildQueueDocument(campaignId, 'Summer Sale', 1000, 'admin1');
      expect(queueDoc.status).toBe('pending');
      expect(queueDoc.totalProducts).toBe(1000);
  
      // 3. Process products with price reversion
      const productWithOriginalPrice = { price: 80, originalPrice: 100 };
      expect(shouldRevertPrice(productWithOriginalPrice)).toBe(true);
  
      const updateData = buildProductUpdateData(productWithOriginalPrice);
      expect(updateData.priceRevert.newPrice).toBe(100);
  
      // 4. Track progress
      expect(calculateProgress(500, 1000)).toBe(50);
  
      // 5. Build completion result
      const result = buildProcessingResult(1000, 950, 50, 120000, 3);
      expect(result.totalProcessed).toBe(1000);
    });
  
    test('retry flow on failure', () => {
      // First failure
      expect(shouldRetry(0, 3)).toBe(true);
      const nextRetry = getNextRetryCount(0);
      expect(nextRetry).toBe(1);
  
      // Second failure
      expect(shouldRetry(1, 3)).toBe(true);
  
      // Third failure (last retry)
      expect(shouldRetry(2, 3)).toBe(true);
  
      // After third failure - exhausted
      expect(hasExhaustedRetries(3, 3)).toBe(true);
      expect(shouldRetry(3, 3)).toBe(false);
    });
  
    test('price reversion scenarios', () => {
      // Product with campaign discount
      const discountedProduct = {
        price: 80,
        originalPrice: 100,
        campaign: 'summer',
        campaignDiscount: 20,
      };
      expect(shouldRevertPrice(discountedProduct)).toBe(true);
      const update = buildProductUpdateData(discountedProduct);
      expect(update.priceRevert.newPrice).toBe(100);
  
      // Product without original price (no reversion needed)
      const regularProduct = { price: 100 };
      expect(shouldRevertPrice(regularProduct)).toBe(false);
  
      // Product with invalid original price
      const invalidProduct = { price: 100, originalPrice: 'invalid' };
      expect(shouldRevertPrice(invalidProduct)).toBe(false);
    });
  });
