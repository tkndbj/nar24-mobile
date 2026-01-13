// functions/test/campaign/campaign-utils.js
//
// EXTRACTED PURE LOGIC from campaign deletion cloud functions
// These functions are EXACT COPIES of logic from the campaign functions,
// extracted here for unit testing.
//
// IMPORTANT: Keep this file in sync with the source campaign functions.

// ============================================================================
// CONSTANTS
// ============================================================================

const BATCH_SIZE = 450; // Stay safely under Firestore's 500 limit
const PROGRESS_UPDATE_INTERVAL = 5; // Update progress every 5 batches
const DEFAULT_MAX_RETRIES = 3;
const CLEANUP_AGE_DAYS = 7;
const RATE_LIMIT_DELAY_MS = 100;
const INDIVIDUAL_UPDATE_DELAY_MS = 50;

const QUEUE_STATUS = {
  PENDING: 'pending',
  PROCESSING: 'processing',
  COMPLETED: 'completed',
  FAILED: 'failed',
  RETRYING: 'retrying',
};

const CAMPAIGN_STATUS = {
  ACTIVE: 'active',
  DELETING: 'deleting',
  DELETION_FAILED: 'deletion_failed',
};

// ============================================================================
// INPUT VALIDATION
// ============================================================================

function validateCampaignId(campaignId) {
  if (!campaignId) {
    return { isValid: false, reason: 'missing', message: 'Campaign ID is required' };
  }

  if (typeof campaignId !== 'string') {
    return { isValid: false, reason: 'not_string', message: 'Campaign ID must be a string' };
  }

  if (campaignId.trim() === '') {
    return { isValid: false, reason: 'empty', message: 'Campaign ID cannot be empty' };
  }

  return { isValid: true };
}

function validateQueueLookupInput(data) {
  if (!data.queueId && !data.campaignId) {
    return { isValid: false, message: 'Either queueId or campaignId is required' };
  }
  return { isValid: true };
}

// ============================================================================
// QUEUE DOCUMENT BUILDING
// ============================================================================

function buildQueueDocument(campaignId, campaignName, totalProducts, createdBy) {
  return {
    campaignId,
    campaignName: campaignName || 'Unnamed Campaign',
    totalProducts: totalProducts || 0,
    productsProcessed: 0,
    productsReverted: 0,
    productsFailed: 0,
    status: QUEUE_STATUS.PENDING,
    retryCount: 0,
    maxRetries: DEFAULT_MAX_RETRIES,
    createdBy: createdBy || 'system',
    lastProcessedDocId: null,
    errors: [],
  };
}

function buildRetryQueueDocument(originalQueueData, newRetryCount) {
  return {
    ...originalQueueData,
    retryCount: newRetryCount,
    status: QUEUE_STATUS.PENDING,
  };
}

// ============================================================================
// PRODUCT UPDATE DATA BUILDING
// ============================================================================

function buildProductUpdateData(productData) {
  const updateData = {
    // Fields to delete
    fieldsToDelete: [
      'campaign',
      'campaignName',
      'campaignDiscount',
      'campaignPrice',
      'discountPercentage',
      'originalPrice',
    ],
    // Price reversion
    priceRevert: null,
  };

  // CRITICAL: Revert to original price if it exists and is valid
  if (shouldRevertPrice(productData)) {
    updateData.priceRevert = {
      newPrice: productData.originalPrice,
      originalPrice: productData.originalPrice,
    };
  }

  return updateData;
}

function shouldRevertPrice(productData) {
  if (!productData) return false;
  if (productData.originalPrice == null) return false;
  if (typeof productData.originalPrice !== 'number') return false;
  if (isNaN(productData.originalPrice)) return false;
  if (productData.originalPrice < 0) return false;
  return true;
}

function getCampaignFieldsToDelete() {
  return [
    'campaign',
    'campaignName',
    'campaignDiscount',
    'campaignPrice',
    'discountPercentage',
    'originalPrice',
  ];
}

// ============================================================================
// PROGRESS CALCULATION
// ============================================================================

function calculateProgress(productsProcessed, totalProducts) {
  if (!totalProducts || totalProducts <= 0) return 0;
  if (!productsProcessed || productsProcessed < 0) return 0;
  
  const progress = Math.round((productsProcessed / totalProducts) * 100);
  return Math.min(progress, 100); // Cap at 100%
}

function shouldUpdateProgress(batchCount, interval = PROGRESS_UPDATE_INTERVAL) {
  return batchCount > 0 && batchCount % interval === 0;
}

function isLastBatch(docsInBatch, batchSize = BATCH_SIZE) {
  return docsInBatch < batchSize;
}

// ============================================================================
// RETRY LOGIC
// ============================================================================

function shouldRetry(retryCount, maxRetries = DEFAULT_MAX_RETRIES) {
  return (retryCount || 0) < maxRetries;
}

function getNextRetryCount(currentRetryCount) {
  return (currentRetryCount || 0) + 1;
}

function hasExhaustedRetries(retryCount, maxRetries = DEFAULT_MAX_RETRIES) {
  return (retryCount || 0) >= maxRetries;
}

function buildErrorEntry(message, retryAttempt, isFinal = false) {
  return {
    message,
    retryAttempt,
    final: isFinal,
  };
}

// ============================================================================
// TIME ESTIMATION
// ============================================================================

function estimateTimeRemaining(queueData, nowMs = Date.now()) {
  // Only estimate for processing status
  if (queueData.status !== QUEUE_STATUS.PROCESSING) return null;
  
  // Need start time and some progress
  if (!queueData.processingStartedAt) return null;
  if (!queueData.productsProcessed || queueData.productsProcessed <= 0) return null;
  if (!queueData.totalProducts || queueData.totalProducts <= 0) return null;

  const startMs = queueData.processingStartedAt.toMillis ? queueData.processingStartedAt.toMillis() : (queueData.processingStartedAt instanceof Date ? queueData.processingStartedAt.getTime() : queueData.processingStartedAt);

  const elapsed = nowMs - startMs;
  const processed = queueData.productsProcessed;
  const remaining = queueData.totalProducts - processed;

  if (remaining <= 0) return null;

  const avgTimePerProduct = elapsed / processed;
  const estimatedMs = avgTimePerProduct * remaining;

  return {
    milliseconds: Math.round(estimatedMs),
    seconds: Math.round(estimatedMs / 1000),
    minutes: Math.round(estimatedMs / 60000),
  };
}

function calculateProcessingDuration(startTime, endTime = Date.now()) {
  const startMs = startTime instanceof Date ? startTime.getTime() : startTime;
  const endMs = endTime instanceof Date ? endTime.getTime() : endTime;
  return endMs - startMs;
}

// ============================================================================
// STATUS RESPONSE BUILDING
// ============================================================================

function buildStatusResponse(queueData, queueId) {
  const progress = calculateProgress(queueData.productsProcessed, queueData.totalProducts);

  return {
    found: true,
    queueId,
    status: queueData.status,
    campaignId: queueData.campaignId,
    campaignName: queueData.campaignName,
    totalProducts: queueData.totalProducts,
    productsProcessed: queueData.productsProcessed || 0,
    productsReverted: queueData.productsReverted || 0,
    productsFailed: queueData.productsFailed || 0,
    progress,
    retryCount: queueData.retryCount || 0,
    maxRetries: queueData.maxRetries || DEFAULT_MAX_RETRIES,
    createdAt: queueData.createdAt,
    completedAt: queueData.completedAt || null,
    errors: queueData.errors || [],
    lastError: queueData.lastError || null,
    estimatedTimeRemaining: estimateTimeRemaining(queueData),
  };
}

function buildNotFoundResponse(message = 'Queue document not found') {
  return {
    found: false,
    message,
  };
}

function buildInitiateResponse(queueId, totalProducts) {
  return {
    success: true,
    queueId,
    totalProducts,
    message: `Campaign deletion started. ${totalProducts} products will be processed in background.`,
  };
}

// ============================================================================
// PROCESSING RESULT BUILDING
// ============================================================================

function buildProcessingResult(totalProcessed, totalReverted, totalFailed, duration, batchesProcessed) {
  return {
    totalProcessed,
    totalReverted,
    totalFailed,
    duration,
    batchesProcessed,
  };
}

function buildBatchResult(processed, reverted, failed, productUpdates = []) {
  return {
    processed,
    reverted,
    failed,
    productUpdates,
  };
}

function aggregateBatchResults(currentTotals, batchResult) {
  return {
    totalProcessed: currentTotals.totalProcessed + batchResult.processed,
    totalReverted: currentTotals.totalReverted + batchResult.reverted,
    totalFailed: currentTotals.totalFailed + batchResult.failed,
  };
}

// ============================================================================
// CAMPAIGN STATUS UPDATES
// ============================================================================

function buildDeletingStatusUpdate(userId) {
  return {
    status: CAMPAIGN_STATUS.DELETING,
    deletionStartedBy: userId || 'system',
  };
}

function buildDeletionFailedStatusUpdate(errorMessage) {
  return {
    status: CAMPAIGN_STATUS.DELETION_FAILED,
    deletionError: errorMessage,
  };
}

function getDeletionStatusFieldsToRevert() {
  return ['status', 'deletionStartedAt', 'deletionStartedBy'];
}

// ============================================================================
// QUEUE STATUS UPDATES
// ============================================================================

function buildProcessingStatusUpdate() {
  return {
    status: QUEUE_STATUS.PROCESSING,
  };
}

function buildCompletedStatusUpdate(result) {
  return {
    status: QUEUE_STATUS.COMPLETED,
    productsProcessed: result.totalProcessed,
    productsReverted: result.totalReverted,
    productsFailed: result.totalFailed,
    processingDuration: result.duration,
  };
}

function buildFailedStatusUpdate(errorMessage, retryCount) {
  return {
    status: QUEUE_STATUS.FAILED,
    finalError: errorMessage,
  };
}

function buildRetryingStatusUpdate(retryCount, errorMessage) {
  return {
    status: QUEUE_STATUS.RETRYING,
    retryCount,
    lastError: errorMessage,
  };
}

function buildProgressUpdate(totalProcessed, totalReverted, totalFailed, lastDocId, totalProducts) {
  return {
    productsProcessed: totalProcessed,
    productsReverted: totalReverted,
    productsFailed: totalFailed,
    lastProcessedDocId: lastDocId,
    progress: calculateProgress(totalProcessed, totalProducts),
  };
}

// ============================================================================
// CLEANUP LOGIC
// ============================================================================

function isQueueItemStale(createdAt, cleanupAgeDays = CLEANUP_AGE_DAYS, nowMs = Date.now()) {
  if (!createdAt) return false;

  const createdMs = createdAt.toMillis ? createdAt.toMillis() : (createdAt instanceof Date ? createdAt.getTime() : createdAt);

  const cutoffMs = nowMs - (cleanupAgeDays * 24 * 60 * 60 * 1000);
  return createdMs < cutoffMs;
}

function shouldCleanupQueueItem(queueData, cleanupAgeDays = CLEANUP_AGE_DAYS) {
  // Only cleanup completed or failed items
  if (queueData.status !== QUEUE_STATUS.COMPLETED && queueData.status !== QUEUE_STATUS.FAILED) {
    return false;
  }
  return isQueueItemStale(queueData.createdAt, cleanupAgeDays);
}

function getCleanupCutoffDate(ageDays = CLEANUP_AGE_DAYS, now = new Date()) {
  const cutoff = new Date(now);
  cutoff.setDate(cutoff.getDate() - ageDays);
  return cutoff;
}

// ============================================================================
// DUPLICATE DETECTION
// ============================================================================

function isDeletionInProgress(existingQueueItems) {
  if (!existingQueueItems || !Array.isArray(existingQueueItems)) return false;
  
  return existingQueueItems.some((item) => 
    item.status === QUEUE_STATUS.PENDING || item.status === QUEUE_STATUS.PROCESSING
  );
}

function getActiveQueueStatuses() {
  return [QUEUE_STATUS.PENDING, QUEUE_STATUS.PROCESSING];
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  // Constants
  BATCH_SIZE,
  PROGRESS_UPDATE_INTERVAL,
  DEFAULT_MAX_RETRIES,
  CLEANUP_AGE_DAYS,
  RATE_LIMIT_DELAY_MS,
  INDIVIDUAL_UPDATE_DELAY_MS,
  QUEUE_STATUS,
  CAMPAIGN_STATUS,

  // Input validation
  validateCampaignId,
  validateQueueLookupInput,

  // Queue document
  buildQueueDocument,
  buildRetryQueueDocument,

  // Product update
  buildProductUpdateData,
  shouldRevertPrice,
  getCampaignFieldsToDelete,

  // Progress
  calculateProgress,
  shouldUpdateProgress,
  isLastBatch,

  // Retry logic
  shouldRetry,
  getNextRetryCount,
  hasExhaustedRetries,
  buildErrorEntry,

  // Time estimation
  estimateTimeRemaining,
  calculateProcessingDuration,

  // Status response
  buildStatusResponse,
  buildNotFoundResponse,
  buildInitiateResponse,

  // Processing result
  buildProcessingResult,
  buildBatchResult,
  aggregateBatchResults,

  // Campaign status
  buildDeletingStatusUpdate,
  buildDeletionFailedStatusUpdate,
  getDeletionStatusFieldsToRevert,

  // Queue status
  buildProcessingStatusUpdate,
  buildCompletedStatusUpdate,
  buildFailedStatusUpdate,
  buildRetryingStatusUpdate,
  buildProgressUpdate,

  // Cleanup
  isQueueItemStale,
  shouldCleanupQueueItem,
  getCleanupCutoffDate,

  // Duplicate detection
  isDeletionInProgress,
  getActiveQueueStatuses,
};
