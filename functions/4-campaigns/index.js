import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

// ============================================================================
// PHASE 1: Initiate Campaign Deletion (Called by Admin)
// ============================================================================
export const deleteCampaign = onCall(
    {
      region: 'europe-west3',
      timeoutSeconds: 60,
      memory: '512MiB',
    },
    async (request) => {
      const {campaignId} = request.data;

      if (!campaignId) {
        throw new HttpsError('invalid-argument', 'Campaign ID is required');
      }

      const db = admin.firestore();
  
      try {
        // 1. Verify campaign exists
        const campaignDoc = await db.collection('campaigns').doc(campaignId).get();
        if (!campaignDoc.exists) {
          throw new HttpsError('not-found', 'Campaign not found');
        }
  
        // 2. Check if already being deleted
        const existingQueue = await db
          .collection('campaign_deletion_queue')
          .where('campaignId', '==', campaignId)
          .where('status', 'in', ['pending', 'processing'])
          .limit(1)
          .get();
  
        if (!existingQueue.empty) {
          throw new HttpsError(
            'already-exists',
            'Campaign deletion already in progress',
          );
        }
  
        // 3. Get total product count for monitoring
        const productsCountSnapshot = await db
          .collection('shop_products')
          .where('campaign', '==', campaignId)
          .count()
          .get();
  
        const totalProducts = productsCountSnapshot.data().count;
  
        // 4. Mark campaign as deleting (prevents further modifications)
        await db.collection('campaigns').doc(campaignId).update({
          status: 'deleting',
          deletionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletionStartedBy: request.auth?.uid || 'system',
        });
  
        // 5. Create deletion queue item
        const queueRef = await db.collection('campaign_deletion_queue').add({
          campaignId,
          campaignName: campaignDoc.data().name || campaignDoc.data().title,
          totalProducts,
          productsProcessed: 0,
          productsReverted: 0,
          productsFailed: 0,
          status: 'pending',
          retryCount: 0,
          maxRetries: 3,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: request.auth?.uid || 'system',
          lastProcessedDocId: null,
          errors: [],
        });
  
        console.log(`Campaign deletion queued: ${campaignId}, Queue ID: ${queueRef.id}`);
  
        return {
          success: true,
          queueId: queueRef.id,
          totalProducts,
          message: `Campaign deletion started. ${totalProducts} products will be processed in background.`,
        };
      } catch (error) {
        console.error('Failed to queue campaign deletion:', error);
        
        // Revert campaign status if we failed to queue
        try {
          await db.collection('campaigns').doc(campaignId).update({
            status: admin.firestore.FieldValue.delete(),
            deletionStartedAt: admin.firestore.FieldValue.delete(),
            deletionStartedBy: admin.firestore.FieldValue.delete(),
          });
        } catch (revertError) {
          console.error('Failed to revert campaign status:', revertError);
        }
  
        throw new HttpsError(
          'internal',
          `Failed to start campaign deletion: ${error.message}`,
        );
      }
    },
  );
  
  // ============================================================================
  // PHASE 2: Background Processing (Triggered automatically)
  // ============================================================================
  export const processCampaignDeletion = onDocumentCreated(
    {
      document: 'campaign_deletion_queue/{queueId}',
      region: 'europe-west3',
      timeoutSeconds: 540,
      memory: '2GiB',
      maxInstances: 10, // Limit concurrent deletions
    },
    async (event) => {
      const db = admin.firestore();
      const queueDocRef = event.data.ref;
      const queueData = event.data.data();
      const {campaignId, maxRetries} = queueData;
  
      console.log(`Starting campaign deletion processing: ${campaignId}`);
  
      try {
        // Update status to processing
        await queueDocRef.update({
          status: 'processing',
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        const result = await processCampaignProducts(db, campaignId, queueDocRef, queueData);
  
        // Mark as completed
        await queueDocRef.update({
          status: 'completed',
          productsProcessed: result.totalProcessed,
          productsReverted: result.totalReverted,
          productsFailed: result.totalFailed,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: result.duration,
        });

        const campaignDoc = await db.collection('campaigns').doc(campaignId).get();
        if (campaignDoc.exists) {
          const campaignData = campaignDoc.data();
          const shopId = campaignData.shopId;
  
          if (shopId) {
            // Get shop data for isRead map
            const shopSnap = await db.collection('shops').doc(shopId).get();
            
            if (shopSnap.exists) {
              const shopData = shopSnap.data();
  
              // Build isRead map for all members
              const isReadMap = {};
              const addMember = (id) => {
                if (id && typeof id === 'string') {
                  isReadMap[id] = false;
                }
              };
  
              addMember(shopData.ownerId);
              if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach(addMember);
              if (Array.isArray(shopData.editors)) shopData.editors.forEach(addMember);
              if (Array.isArray(shopData.viewers)) shopData.viewers.forEach(addMember);
  
              if (Object.keys(isReadMap).length > 0) {
                const campaignName = campaignData.name || campaignData.title || 'Your campaign';
  
                await db.collection('shop_notifications').add({
                  type: 'campaign_ended',
                  shopId,
                  shopName: shopData.name || '',
                  campaignId,
                  campaignName,
                  isRead: isReadMap,
                  timestamp: admin.firestore.FieldValue.serverTimestamp(),
                  message_en: `Campaign "${campaignName}" has ended`,
                  message_tr: `"${campaignName}" kampanyası sona erdi`,
                  message_ru: `Кампания "${campaignName}" завершена`,
                });
  
                console.log(`✅ Campaign ended notification created for shop ${shopId}`);
              }
            }
          }
        }
  
        // Delete the campaign document
        await db.collection('campaigns').doc(campaignId).delete();
  
        console.log(`Campaign deletion completed: ${campaignId}`, result);
  
        return {success: true, ...result};
      } catch (error) {
        console.error(`Campaign deletion failed: ${campaignId}`, error);
  
        const retryCount = queueData.retryCount || 0;
        const shouldRetry = retryCount < maxRetries;
  
        if (shouldRetry) {
          // Schedule retry
          console.log(`Scheduling retry ${retryCount + 1}/${maxRetries} for campaign: ${campaignId}`);
          
          await queueDocRef.update({
            status: 'retrying',
            retryCount: retryCount + 1,
            lastError: error.message,
            lastErrorAt: admin.firestore.FieldValue.serverTimestamp(),
            errors: admin.firestore.FieldValue.arrayUnion({
              message: error.message,
              timestamp: admin.firestore.Timestamp.now(),
              retryAttempt: retryCount + 1,
            }),
          });
  
          // Create a new queue item for retry (triggers the function again)
          await db.collection('campaign_deletion_queue').add({
            ...queueData,
            retryCount: retryCount + 1,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            originalQueueId: queueDocRef.id,
          });
        } else {
          // Max retries reached - mark as failed
          await queueDocRef.update({
            status: 'failed',
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            finalError: error.message,
            errors: admin.firestore.FieldValue.arrayUnion({
              message: error.message,
              timestamp: admin.firestore.Timestamp.now(),
              retryAttempt: retryCount + 1,
              final: true,
            }),
          });
  
          // Revert campaign status so admin can try again manually
          try {
            await db.collection('campaigns').doc(campaignId).update({
              status: 'deletion_failed',
              deletionFailedAt: admin.firestore.FieldValue.serverTimestamp(),
              deletionError: error.message,
            });
          } catch (revertError) {
            console.error('Failed to update campaign status:', revertError);
          }
  
          console.error(`Campaign deletion permanently failed after ${maxRetries} retries: ${campaignId}`);
        }
  
        throw error;
      }
    },
  );
  
  // ============================================================================
  // CORE PROCESSING LOGIC
  // ============================================================================
  async function processCampaignProducts(db, campaignId, queueDocRef, queueData) {
    const startTime = Date.now();
    const batchSize = 450; // Stay safely under Firestore's 500 limit
    const progressUpdateInterval = 5; // Update progress every 5 batches
  
    let totalProcessed = 0;
    let totalReverted = 0;
    let totalFailed = 0;
    let batchCount = 0;
    let lastDoc = queueData.lastProcessedDocId ? await db.collection('shop_products').doc(queueData.lastProcessedDocId).get() : null;
  
    let hasMore = true; // ✅ ADD THIS
    
    while (hasMore) { // ✅ CHANGE THIS
      // Build query with cursor-based pagination
      let productsQuery = db
        .collection('shop_products')
        .where('campaign', '==', campaignId)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(batchSize);
  
      if (lastDoc && lastDoc.exists) {
        productsQuery = productsQuery.startAfter(lastDoc);
      }
  
      const snapshot = await productsQuery.get();
  
      // No more products to process
      if (snapshot.empty) {
        console.log(`No more products to process for campaign: ${campaignId}`);
        hasMore = false; // ✅ CHANGE THIS
        break;
      }
  
      // Process batch with error handling per product
      const batchResults = await processBatch(db, snapshot.docs);
      
      totalProcessed += batchResults.processed;
      totalReverted += batchResults.reverted;
      totalFailed += batchResults.failed;
      batchCount++;
  
      // Update last processed document for resumability
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
  
      // Update progress periodically (not every batch to reduce writes)
      if (batchCount % progressUpdateInterval === 0) {
        await queueDocRef.update({
          productsProcessed: totalProcessed,
          productsReverted: totalReverted,
          productsFailed: totalFailed,
          lastProcessedDocId: lastDoc.id,
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          progress: Math.round((totalProcessed / queueData.totalProducts) * 100),
        });
        
        console.log(`Progress: ${totalProcessed}/${queueData.totalProducts} products processed`);
      }
  
      // If we got less than batchSize, we're done
      if (snapshot.docs.length < batchSize) {
        console.log(`Processed final batch for campaign: ${campaignId}`);
        hasMore = false; // ✅ CHANGE THIS
        break;
      }
  
      // Small delay to avoid rate limiting
      await sleep(100);
    }
  
    const duration = Date.now() - startTime;
  
    return {
      totalProcessed,
      totalReverted,
      totalFailed,
      duration,
      batchesProcessed: batchCount,
    };
  }
  
  // ============================================================================
  // BATCH PROCESSING WITH ERROR HANDLING
  // ============================================================================
  async function processBatch(db, docs) {
    const batch = db.batch();
    const productUpdates = [];
  
    let processed = 0;
    let reverted = 0;
    let failed = 0;
  
    for (const doc of docs) {
      try {
        const productData = doc.data();
        
        // Build update object - only touch campaign-related fields
        const updateData = {
          campaign: '',
campaignName: '',
          campaignDiscount: admin.firestore.FieldValue.delete(),
          campaignPrice: admin.firestore.FieldValue.delete(),
          discountPercentage: admin.firestore.FieldValue.delete(),
        };
  
        // CRITICAL: Revert to original price if it exists
        if (productData.originalPrice != null && typeof productData.originalPrice === 'number') {
          updateData.price = productData.originalPrice;
          updateData.originalPrice = admin.firestore.FieldValue.delete();
          reverted++;
        } else {
          // Just remove originalPrice field if present but invalid
          updateData.originalPrice = admin.firestore.FieldValue.delete();
        }
  
        batch.update(doc.ref, updateData);
        processed++;
  
        productUpdates.push({
          productId: doc.id,
          priceReverted: productData.originalPrice != null,
          originalPrice: productData.originalPrice || null,
        });
      } catch (error) {
        console.error(`Error preparing update for product ${doc.id}:`, error);
        failed++;
      }
    }
  
    // Commit the batch
    try {
      await batch.commit();
      console.log(`Batch committed: ${processed} products updated, ${reverted} prices reverted, ${failed} failed`);
    } catch (error) {
      console.error('Batch commit failed:', error);
      
      // If batch fails, try individual updates for this batch
      const individualResults = await processIndividually(db, docs);
      return individualResults;
    }
  
    return {processed, reverted, failed, productUpdates};
  }
  
  // ============================================================================
  // FALLBACK: Individual Processing (if batch fails)
  // ============================================================================
  async function processIndividually(db, docs) {
    let processed = 0;
    let reverted = 0;
    let failed = 0;
  
    console.log(`Attempting individual updates for ${docs.length} products`);
  
    for (const doc of docs) {
      try {
        const productData = doc.data();
        
        const updateData = {
          campaign: '',
campaignName: '',
          campaignDiscount: admin.firestore.FieldValue.delete(),
          campaignPrice: admin.firestore.FieldValue.delete(),
          discountPercentage: admin.firestore.FieldValue.delete(),
        };
  
        if (productData.originalPrice != null && typeof productData.originalPrice === 'number') {
          updateData.price = productData.originalPrice;
          updateData.originalPrice = admin.firestore.FieldValue.delete();
          reverted++;
        } else {
          updateData.originalPrice = admin.firestore.FieldValue.delete();
        }
  
        await doc.ref.update(updateData);
        processed++;
      } catch (error) {
        console.error(`Individual update failed for product ${doc.id}:`, error);
        failed++;
      }
  
      // Small delay between individual updates
      await sleep(50);
    }
  
    console.log(`Individual processing completed: ${processed} succeeded, ${failed} failed`);
    return {processed, reverted, failed};
  }
  
  // ============================================================================
  // MONITORING: Check Queue Status (for admin dashboard)
  // ============================================================================
  export const getCampaignDeletionStatus = onCall(
    {
      region: 'europe-west3',
      timeoutSeconds: 30,
    },
    async (request) => {
      const {queueId, campaignId} = request.data;
  
      if (!queueId && !campaignId) {
        throw new HttpsError(
          'invalid-argument',
          'Either queueId or campaignId is required',
        );
      }
  
      const db = admin.firestore();
  
      try {
        let queueDoc;
  
        if (queueId) {
          queueDoc = await db.collection('campaign_deletion_queue').doc(queueId).get();
        } else {
          // Find by campaignId
          const snapshot = await db
            .collection('campaign_deletion_queue')
            .where('campaignId', '==', campaignId)
            .orderBy('createdAt', 'desc')
            .limit(1)
            .get();
  
          if (snapshot.empty) {
            return {
              found: false,
              message: 'No deletion queue found for this campaign',
            };
          }
  
          queueDoc = snapshot.docs[0];
        }
  
        if (!queueDoc.exists) {
          return {
            found: false,
            message: 'Queue document not found',
          };
        }
  
        const data = queueDoc.data();
        const progress = data.totalProducts > 0 ? Math.round((data.productsProcessed / data.totalProducts) * 100) : 0;
  
        return {
          found: true,
          queueId: queueDoc.id,
          status: data.status,
          campaignId: data.campaignId,
          campaignName: data.campaignName,
          totalProducts: data.totalProducts,
          productsProcessed: data.productsProcessed || 0,
          productsReverted: data.productsReverted || 0,
          productsFailed: data.productsFailed || 0,
          progress,
          retryCount: data.retryCount || 0,
          maxRetries: data.maxRetries || 3,
          createdAt: data.createdAt,
          completedAt: data.completedAt || null,
          errors: data.errors || [],
          lastError: data.lastError || null,
          estimatedTimeRemaining: estimateTimeRemaining(data),
        };
      } catch (error) {
        console.error('Failed to get deletion status:', error);
        throw new HttpsError(
          'internal',
          `Failed to get deletion status: ${error.message}`,
        );
      }
    },
  );
  
  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================
  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
  
  function estimateTimeRemaining(queueData) {
    if (queueData.status !== 'processing') return null;
    if (!queueData.processingStartedAt || !queueData.productsProcessed) return null;
  
    const elapsed = Date.now() - queueData.processingStartedAt.toMillis();
    const processed = queueData.productsProcessed;
    const remaining = queueData.totalProducts - processed;
  
    if (processed === 0) return null;
  
    const avgTimePerProduct = elapsed / processed;
    const estimatedMs = avgTimePerProduct * remaining;
  
    return {
      milliseconds: Math.round(estimatedMs),
      seconds: Math.round(estimatedMs / 1000),
      minutes: Math.round(estimatedMs / 60000),
    };
  }
  
  // ============================================================================
  // CLEANUP: Remove old completed/failed queue items (run periodically)
  // ============================================================================
  export const cleanupCampaignDeletionQueue = onSchedule(
    {
      schedule: 'every 24 hours',
      region: 'europe-west3',
      timeoutSeconds: 300,
    },
    async (event) => {
      const db = admin.firestore();
      
      // Delete queue items older than 7 days that are completed or failed
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - 7);
  
      const snapshot = await db
        .collection('campaign_deletion_queue')
        .where('status', 'in', ['completed', 'failed'])
        .where('createdAt', '<', admin.firestore.Timestamp.fromDate(cutoffDate))
        .limit(500)
        .get();
  
      if (snapshot.empty) {
        console.log('No old queue items to clean up');
        return;
      }
  
      const batch = db.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.ref));
      
      await batch.commit();
      console.log(`Cleaned up ${snapshot.docs.length} old queue items`);
    },
  );
