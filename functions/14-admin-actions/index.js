import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {CloudTasksClient} from '@google-cloud/tasks';

// Constants
const MAX_ARCHIVE_REASON_LENGTH = 1000;
const BATCH_SIZE = 400; // Keep under 500 for safety margin
const PROJECT_ID = process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'emlak-mobile-app';
const CLOUD_TASKS_LOCATION = 'europe-west3';
const BOOST_EXPIRATION_QUEUE = 'boost-expiration-queue';

// Lazy-init Cloud Tasks client (only created when needed)
let _tasksClient = null;
function getTasksClient() {
  if (!_tasksClient) {
    _tasksClient = new CloudTasksClient();
  }
  return _tasksClient;
}

// Helper function for moving subcollections safely
async function moveSubcollection(db, sourceCollection, destCollection) {
  const snapshot = await sourceCollection.get();

  if (snapshot.empty) {
    return 0;
  }

  const deleteRefs = [];

  // Copy in batches
  for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
    const copyBatch = db.batch();
    const chunk = snapshot.docs.slice(i, i + BATCH_SIZE);

    for (const doc of chunk) {
      copyBatch.set(destCollection.doc(doc.id), doc.data());
      deleteRefs.push(doc.ref);
    }

    await copyBatch.commit();
  }

  console.log(`Copied ${snapshot.docs.length} docs to destination`);

  // Delete from source only after ALL copies succeed
  for (let i = 0; i < deleteRefs.length; i += BATCH_SIZE) {
    const deleteBatch = db.batch();
    const chunk = deleteRefs.slice(i, i + BATCH_SIZE);

    for (const ref of chunk) {
      deleteBatch.delete(ref);
    }

    await deleteBatch.commit();
  }

  console.log(`Deleted ${deleteRefs.length} source docs`);

  return snapshot.docs.length;
}

/**
 * Gracefully expires a product's boost and cleans up related resources.
 * Called AFTER the main archive transaction completes.
 * All operations are best-effort — failures are logged but do not block the archive.
 *
 * @param {FirebaseFirestore.Firestore} db - Firestore instance
 * @param {string} productId - The product document ID
 * @param {string} sourceCollection - Original collection ('products' or 'shop_products')
 * @param {Object} boostCleanupData - Captured boost state from the transaction
 */
async function handleBoostCleanup(db, productId, sourceCollection, boostCleanupData) {
  const bcd = boostCleanupData;
  console.log(`Performing boost cleanup for ${productId} (source: ${sourceCollection})`);

  // 1. Update boost history with final stats
  if (bcd.boostStartTime) {
    try {
      const isShopProduct = sourceCollection === 'shop_products';
      const historyOwnerId = isShopProduct ? bcd.productShopId : bcd.productUserId;

      if (!historyOwnerId) {
        console.warn(`No owner ID for boost history lookup on ${productId}`);
      } else {
        const historyCol = isShopProduct ? db.collection('shops').doc(historyOwnerId).collection('boostHistory') : db.collection('users').doc(historyOwnerId).collection('boostHistory');

        const historySnap = await historyCol
          .where('itemId', '==', productId)
          .where('boostStartTime', '==', bcd.boostStartTime)
          .limit(1)
          .get();

        const impressionsDuringBoost = Math.max(
          (bcd.boostedImpressionCount) - (bcd.boostImpressionCountAtStart), 0,
        );
        const clicksDuringBoost = Math.max(
          (bcd.clickCount) - (bcd.boostClickCountAtStart), 0,
        );

        const historyData = {
          impressionsDuringBoost,
          clicksDuringBoost,
          totalImpressionCount: bcd.boostedImpressionCount,
          totalClickCount: bcd.clickCount,
          finalImpressions: bcd.boostImpressionCountAtStart,
          finalClicks: bcd.boostClickCountAtStart,
          itemName: bcd.productName,
          productImage: bcd.productImage,
          averageRating: bcd.averageRating,
          price: bcd.price,
          currency: bcd.currency,
          actualExpirationTime: FieldValue.serverTimestamp(),
          expiredReason: 'admin_archived',
          terminatedEarly: true,
        };

        if (!historySnap.empty) {
          await historySnap.docs[0].ref.update(historyData);
          console.log(`✅ Boost history updated for ${productId}`);
        } else {
          await historyCol.add({
            ...historyData,
            itemId: productId,
            itemType: isShopProduct ? 'shop_product' : 'product',
            boostStartTime: bcd.boostStartTime,
            createdAt: FieldValue.serverTimestamp(),
          });
          console.log(`✅ Boost history created for ${productId} (none existed)`);
        }
      }
    } catch (historyError) {
      console.error(`Failed to update boost history for ${productId}:`, historyError);
    }
  }

  // 2. Cancel scheduled Cloud Task (best-effort)
  if (bcd.boostExpirationTaskName) {
    try {
      const client = getTasksClient();
      const taskPath = client.taskPath(
        PROJECT_ID,
        CLOUD_TASKS_LOCATION,
        BOOST_EXPIRATION_QUEUE,
        bcd.boostExpirationTaskName,
      );
      await client.deleteTask({name: taskPath});
      console.log(`✅ Cancelled boost expiration task: ${bcd.boostExpirationTaskName}`);
    } catch (taskError) {
      // Task may have already executed, been deleted, or not exist — safe to ignore
      if (taskError.code === 5) {
        // NOT_FOUND — task already gone
        console.log(`Boost task already completed/deleted: ${bcd.boostExpirationTaskName}`);
      } else {
        console.warn(`Could not cancel boost task: ${taskError.message}`);
      }
    }
  }

  // 3. Individual product boost notification — SKIPPED
  // For individual products, the main archive notification handles this
  // with boostExpired: true flag. Only shop products need a separate
  // boost notification since they don't get the archive notification.

 // 4. Shop product boost notification — SKIPPED
  // For admin-archived shop products, the main archive notification
  // handles this with boostExpired: true flag (same pattern as individual products).
}

export const adminToggleProductArchiveStatus = onCall({
  region: 'europe-west3',
  maxInstances: 10,
  timeoutSeconds: 300,
  memory: '512MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = request.auth.uid;
  const {
    productId,
    shopId,
    archiveStatus,
    collection: sourceCollectionType,
    needsUpdate,
    archiveReason,
  } = request.data;

  // Enhanced input validation
  if (!productId || typeof productId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid Product ID is required');
  }

  if (archiveStatus === undefined || typeof archiveStatus !== 'boolean') {
    throw new HttpsError('invalid-argument', 'Archive status must be a boolean');
  }

  // Sanitize archiveReason
  const sanitizedArchiveReason = archiveReason ? String(archiveReason).trim().slice(0, MAX_ARCHIVE_REASON_LENGTH) : null;
  const db = getFirestore();

  try {
    // Verify user is a full admin
    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      throw new HttpsError('not-found', 'User not found');
    }

    const userData = userDoc.data();
    const isFullAdmin = userData?.isAdmin === true && !userData?.isSemiAdmin;

    if (!isFullAdmin) {
      throw new HttpsError('permission-denied', 'Only full admins can perform this action');
    }

    // Determine collections
    let sourceCollection;
    let destCollection;

    if (archiveStatus) {
      if (sourceCollectionType === 'shop_products' || shopId) {
        sourceCollection = 'shop_products';
        destCollection = 'paused_shop_products';
      } else {
        sourceCollection = 'products';
        destCollection = 'paused_products';
      }
    } else {
      if (sourceCollectionType === 'paused_shop_products' || shopId) {
        sourceCollection = 'paused_shop_products';
        destCollection = 'shop_products';
      } else {
        sourceCollection = 'paused_products';
        destCollection = 'products';
      }
    }

    const sourceRef = db.collection(sourceCollection).doc(productId);
    const destRef = db.collection(destCollection).doc(productId);

    // ================================================================
    // TRANSACTION: Atomic read → prepare → write
    // ================================================================
    const result = await db.runTransaction(async (transaction) => {
      const productDoc = await transaction.get(sourceRef);

      if (!productDoc.exists) {
        throw new HttpsError('not-found', `Product not found in ${sourceCollection}`);
      }

      // Idempotency check — already in destination?
      const destDoc = await transaction.get(destRef);
      if (destDoc.exists) {
        console.log(`Product ${productId} already exists in ${destCollection}, skipping`);
        return {alreadyProcessed: true, productData: destDoc.data(), boostCleanupData: null};
      }

      const productData = productDoc.data();

      // Prepare update data
      const updateData = {
        ...productData,
        paused: archiveStatus,
        lastModified: FieldValue.serverTimestamp(),
        modifiedBy: userId,
      };

      // Track boost cleanup data (populated only when archiving a boosted product)
      let boostCleanupData = null;

      if (archiveStatus) {
        // ── Archive: set admin flags ──
        updateData.archivedByAdmin = true;
        updateData.archivedByAdminAt = FieldValue.serverTimestamp();
        updateData.archivedByAdminId = userId;
        updateData.needsUpdate = needsUpdate === true;
        updateData.archiveReason = (needsUpdate && sanitizedArchiveReason) ? sanitizedArchiveReason : null;
        updateData.adminArchiveReason = updateData.archiveReason || 'Archived by admin';

        // ── If product is currently boosted, clean boost state ──
        if (productData.isBoosted === true) {
          console.log(`Product ${productId} is boosted — cleaning boost fields before archive`);

          // Capture everything needed for post-transaction cleanup.
          // We snapshot these values NOW because after the transaction
          // the source document will be deleted.
          boostCleanupData = {
            boostStartTime: productData.boostStartTime || null,
            boostExpirationTaskName: productData.boostExpirationTaskName || null,
            boostedImpressionCount: productData.boostedImpressionCount || 0,
            boostImpressionCountAtStart: productData.boostImpressionCountAtStart || 0,
            clickCount: productData.clickCount || 0,
            boostClickCountAtStart: productData.boostClickCountAtStart || 0,
            productName: productData.productName || 'Product',
            productImage: (productData.imageUrls && productData.imageUrls.length > 0) ? productData.imageUrls[0] : null,
            averageRating: productData.averageRating || 0,
            price: productData.price || 0,
            currency: productData.currency || 'TL',
            productUserId: productData.userId || null,
            productShopId: productData.shopId || shopId || null,
          };

          // Overwrite boost fields in the document that will be written
          // to the paused collection so it arrives in a clean state.
          updateData.isBoosted = false;
          updateData.lastBoostExpiredAt = FieldValue.serverTimestamp();
          updateData.promotionScore = Math.max((productData.promotionScore || 0) - 1000, 0);

          // Remove transient boost fields entirely — they are meaningless
          // once the boost is expired and would be stale if the product
          // is ever unarchived.
          delete updateData.boostStartTime;
          delete updateData.boostEndTime;
          delete updateData.boostExpirationTaskName;
          delete updateData.boostDuration;
          delete updateData.boostScreen;
          delete updateData.screenType;
          delete updateData.boostImpressionCountAtStart;
          delete updateData.boostClickCountAtStart;
        }
      } else {
        // ── Unarchive: clear admin flags ──
        updateData.archivedByAdmin = false;
        updateData.archivedByAdminAt = null;
        updateData.archivedByAdminId = null;
        updateData.adminArchiveReason = null;
        updateData.needsUpdate = false;
        updateData.archiveReason = null;
        updateData.unarchivedByAdminAt = FieldValue.serverTimestamp();
        updateData.unarchivedByAdminId = userId;
      }

      // Atomic move within transaction
      transaction.set(destRef, updateData);
      transaction.delete(sourceRef);

      return {alreadyProcessed: false, productData, boostCleanupData};
    });

    // ================================================================
    // EARLY RETURN: idempotent case
    // ================================================================
    if (result.alreadyProcessed) {
      return {
        success: true,
        productId: productId,
        archived: archiveStatus,
        archivedByAdmin: archiveStatus,
        needsUpdate: archiveStatus ? (needsUpdate === true) : false,
        sourceCollection: sourceCollection,
        destCollection: destCollection,
        subcollectionDocsMoved: 0,
        note: 'Product was already in destination (idempotent)',
      };
    }

    // ================================================================
    // POST-TRANSACTION: Subcollection migration
    // ================================================================
    const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences'];
    let totalSubcollectionDocsMoved = 0;

    for (const subcollectionName of subcollectionsToMove) {
      try {
        const movedCount = await moveSubcollection(
          db,
          sourceRef.collection(subcollectionName),
          destRef.collection(subcollectionName),
        );
        totalSubcollectionDocsMoved += movedCount;
      } catch (subcollectionError) {
        console.error(`Error moving ${subcollectionName}:`, subcollectionError);
      }
    }

    // ================================================================
    // POST-TRANSACTION: Boost cleanup (best-effort, non-blocking)
    // ================================================================
    if (result.boostCleanupData) {
      await handleBoostCleanup(db, productId, sourceCollection, result.boostCleanupData);
    }

    // ================================================================
    // POST-TRANSACTION: Audit logging
    // ================================================================
    const auditMetadata = {
      previousState: {
        archivedByAdmin: result.productData?.archivedByAdmin || false,
        paused: result.productData?.paused || false,
        needsUpdate: result.productData?.needsUpdate || false,
        isBoosted: result.productData?.isBoosted || false,
      },
      newState: {
        archivedByAdmin: archiveStatus,
        paused: archiveStatus,
        needsUpdate: archiveStatus ? (needsUpdate === true) : false,
        isBoosted: false,
      },
      archiveReason: archiveStatus ? sanitizedArchiveReason : null,
      subcollectionDocsMoved: totalSubcollectionDocsMoved,
      boostWasActive: result.boostCleanupData !== null,
    };

    await db.collection('admin_audit_logs').add({
      action: archiveStatus ? 'PRODUCT_ARCHIVED_BY_ADMIN' : 'PRODUCT_UNARCHIVED_BY_ADMIN',
      adminId: userId,
      adminEmail: userData?.email || 'unknown',
      productId: productId,
      shopId: shopId || null,
      sourceCollection: sourceCollection,
      destCollection: destCollection,
      timestamp: FieldValue.serverTimestamp(),
      productName: result.productData?.productName || 'Unknown',
      metadata: auditMetadata,
    });

    // ================================================================
    // POST-TRANSACTION: Archive notification for individual (non-shop) products
    // ================================================================
    if (archiveStatus && !shopId && result.productData?.userId) {
      try {
        const productOwnerId = result.productData.userId;
        const productName = result.productData?.productName || 'Your product';

        await db.collection('users').doc(productOwnerId).collection('notifications').add({
          type: 'product_archived_by_admin',
          productId: productId,
          productName: productName,
          needsUpdate: needsUpdate === true,
          archiveReason: sanitizedArchiveReason || null,
          boostExpired: result.boostCleanupData !== null,
          isRead: false,
          timestamp: FieldValue.serverTimestamp(),
        });

        console.log(`✅ Admin archive notification created for user ${productOwnerId}`);
      } catch (notificationError) {
        console.error('Failed to create user archive notification:', notificationError);
      }
    }

    // ================================================================
    // POST-TRANSACTION: Archive notification for shop products
    // ================================================================
    if (archiveStatus && shopId) {
      try {
        const productName = result.productData?.productName || 'Product';

        await db.collection('shop_notifications').add({
          shopId: shopId,
          type: 'product_archived_by_admin',
          productId: productId,
          productName: productName,
          needsUpdate: needsUpdate === true,
          archiveReason: sanitizedArchiveReason || null,
          boostExpired: result.boostCleanupData !== null,
          isRead: {},    // ← map, not boolean
          timestamp: FieldValue.serverTimestamp(),
        });

        console.log(`✅ Admin archive shop notification created for shop ${shopId}`);
      } catch (notificationError) {
        console.error('Failed to create shop archive notification:', notificationError);
      }
    }

    return {
      success: true,
      productId: productId,
      archived: archiveStatus,
      archivedByAdmin: archiveStatus,
      needsUpdate: archiveStatus ? (needsUpdate === true) : false,
      sourceCollection: sourceCollection,
      destCollection: destCollection,
      subcollectionDocsMoved: totalSubcollectionDocsMoved,
      boostExpired: result.boostCleanupData !== null,
    };
  } catch (error) {
    console.error('Error toggling product archive status:', error);

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError('internal', 'Failed to update product status. Please try again.');
  }
});

export const approveArchivedProductEdit = onCall({
  region: 'europe-west3',
  maxInstances: 10,
  timeoutSeconds: 300,
  memory: '512MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = request.auth.uid;
  const db = getFirestore();

  // Verify admin status
  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists || !userDoc.data()?.isAdmin) {
    throw new HttpsError('permission-denied', 'Only admins can approve edits');
  }

  const userData = userDoc.data();
  const {applicationId} = request.data;

  // Enhanced validation
  if (!applicationId || typeof applicationId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid Application ID is required');
  }

  try {
    const applicationRef = db.collection('product_edit_applications').doc(applicationId);

    // Use transaction for atomicity
    const result = await db.runTransaction(async (transaction) => {
      const applicationDoc = await transaction.get(applicationRef);

      if (!applicationDoc.exists) {
        throw new HttpsError('not-found', 'Application not found');
      }

      const applicationData = applicationDoc.data() || {};

      // Idempotency check - already approved?
      if (applicationData.status === 'approved') {
        console.log(`Application ${applicationId} already approved, skipping`);
        return {
          alreadyProcessed: true,
          productId: applicationData.originalProductId,
          sourceCollection: applicationData.sourceCollection || 'paused_shop_products',
        };
      }

      // Check it's not rejected
      if (applicationData.status === 'rejected') {
        throw new HttpsError('failed-precondition', 'Cannot approve a rejected application');
      }

      if (applicationData.editType !== 'archived_product_update') {
        throw new HttpsError('invalid-argument', 'This function only handles archived product updates');
      }

      const productId = applicationData.originalProductId;
      const sourceCollection = applicationData.sourceCollection || 'paused_shop_products';
      const destCollection = sourceCollection === 'paused_shop_products' ? 'shop_products' : 'products';

      const sourceRef = db.collection(sourceCollection).doc(productId);
      const destRef = db.collection(destCollection).doc(productId);

      const sourceDoc = await transaction.get(sourceRef);
      if (!sourceDoc.exists) {
        throw new HttpsError('not-found', `Product not found in ${sourceCollection}`);
      }

      const originalProductData = sourceDoc.data() || {};

      // Prepare updated product data
      const updatedProductData = {...applicationData};

      // Remove application-specific fields
      const fieldsToRemove = [
        'originalProductId', 'editType', 'originalProductData', 'submittedAt',
        'status', 'editedFields', 'changes', 'sourceCollection', 'deletedColors',
        'phone', 'region', 'address', 'ibanOwnerName', 'ibanOwnerSurname', 'iban',
        'approvedAt', 'approvedBy', 'rejectedAt', 'rejectedBy', 'rejectionReason',
        'applicationId',
      ];
      fieldsToRemove.forEach((field) => delete updatedProductData[field]);

      // =====================================================================
      // DEFENSIVE FIELD PRESERVATION
      // =====================================================================

      // Identity - CRITICAL
      updatedProductData.id = productId;
      updatedProductData.ilan_no = applicationData.ilan_no ?? originalProductData.ilan_no ?? productId;
      updatedProductData.currency = applicationData.currency ?? originalProductData.currency ?? 'TL';

      // Ownership - CRITICAL
      updatedProductData.userId = applicationData.userId ?? originalProductData.userId;
      updatedProductData.ownerId = applicationData.ownerId ?? originalProductData.ownerId ?? applicationData.userId ?? originalProductData.userId;
      updatedProductData.shopId = applicationData.shopId ?? originalProductData.shopId;
      updatedProductData.sellerName = applicationData.sellerName ?? originalProductData.sellerName ?? 'Unknown Seller';

      // Timestamps - CRITICAL
      updatedProductData.createdAt = originalProductData.createdAt ?? FieldValue.serverTimestamp();
      updatedProductData.updatedAt = FieldValue.serverTimestamp();

      // Stats - PRESERVE FROM ORIGINAL
      updatedProductData.averageRating = applicationData.averageRating ?? originalProductData.averageRating ?? 0;
      updatedProductData.reviewCount = applicationData.reviewCount ?? originalProductData.reviewCount ?? 0;
      updatedProductData.clickCount = applicationData.clickCount ?? originalProductData.clickCount ?? 0;
      updatedProductData.favoritesCount = applicationData.favoritesCount ?? originalProductData.favoritesCount ?? 0;
      updatedProductData.cartCount = applicationData.cartCount ?? originalProductData.cartCount ?? 0;
      updatedProductData.purchaseCount = applicationData.purchaseCount ?? originalProductData.purchaseCount ?? 0;

      // Flags - PRESERVE FROM ORIGINAL
      updatedProductData.isFeatured = applicationData.isFeatured ?? originalProductData.isFeatured ?? false;
      updatedProductData.isTrending = applicationData.isTrending ?? originalProductData.isTrending ?? false;

      // Boost should always be false for a product coming out of archive.
      // The admin archive function already cleaned boost state when archiving.
      // If somehow stale boost data persists, force it clean here.
      updatedProductData.isBoosted = false;
      updatedProductData.promotionScore = applicationData.promotionScore ?? originalProductData.promotionScore ?? 0;

      // Ranking - PRESERVE FROM ORIGINAL
      updatedProductData.rankingScore = applicationData.rankingScore ?? originalProductData.rankingScore ?? 0;

      // Boost tracking - explicitly clear (boost was expired on archive)
      updatedProductData.boostedImpressionCount = originalProductData.boostedImpressionCount ?? 0;
      updatedProductData.boostImpressionCountAtStart = 0;
      updatedProductData.boostClickCountAtStart = 0;
      updatedProductData.boostStartTime = null;
      updatedProductData.boostEndTime = null;

      // Click tracking - PRESERVE FROM ORIGINAL
      updatedProductData.dailyClickCount = applicationData.dailyClickCount ?? originalProductData.dailyClickCount ?? 0;
      updatedProductData.lastClickDate = applicationData.lastClickDate ?? originalProductData.lastClickDate ?? null;
      updatedProductData.clickCountAtStart = applicationData.clickCountAtStart ?? originalProductData.clickCountAtStart ?? 0;

      // Related products - PRESERVE FROM ORIGINAL
      updatedProductData.relatedProductIds = applicationData.relatedProductIds ?? originalProductData.relatedProductIds ?? [];
      updatedProductData.relatedLastUpdated = applicationData.relatedLastUpdated ?? originalProductData.relatedLastUpdated ?? null;
      updatedProductData.relatedCount = applicationData.relatedCount ?? originalProductData.relatedCount ?? 0;

      // Clear archive flags
      updatedProductData.paused = false;
      updatedProductData.needsUpdate = false;
      updatedProductData.archiveReason = null;
      updatedProductData.archivedByAdmin = false;
      updatedProductData.archivedByAdminAt = null;
      updatedProductData.archivedByAdminId = null;
      updatedProductData.adminArchiveReason = null;

      // Set approval metadata
      updatedProductData.lastModified = FieldValue.serverTimestamp();
      updatedProductData.approvedAt = FieldValue.serverTimestamp();
      updatedProductData.approvedBy = userId;
      updatedProductData.status = 'approved';

      // Atomic operations within transaction
      transaction.set(destRef, updatedProductData);
      transaction.delete(sourceRef);
      transaction.update(applicationRef, {
        status: 'approved',
        approvedAt: FieldValue.serverTimestamp(),
        approvedBy: userId,
      });

      return {
        alreadyProcessed: false,
        productId,
        sourceCollection,
        destCollection,
        productName: updatedProductData.productName || 'Unknown',
        shopId: updatedProductData.shopId,
      };
    });

    // If already processed, return early
    if (result.alreadyProcessed) {
      return {
        success: true,
        productId: result.productId,
        applicationId: applicationId,
        sourceCollection: result.sourceCollection,
        destCollection: result.sourceCollection === 'paused_shop_products' ? 'shop_products' : 'products',
        subcollectionDocsMoved: 0,
        message: 'Application was already approved (idempotent)',
      };
    }

    const sourceRef = db.collection(result.sourceCollection).doc(result.productId);
    const destRef = db.collection(result.destCollection).doc(result.productId);

    // Handle subcollections outside transaction
    const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences'];
    let totalSubcollectionDocsMoved = 0;

    for (const subcollectionName of subcollectionsToMove) {
      try {
        const movedCount = await moveSubcollection(
          db,
          sourceRef.collection(subcollectionName),
          destRef.collection(subcollectionName),
        );
        totalSubcollectionDocsMoved += movedCount;
      } catch (subcollectionError) {
        console.error(`Error moving ${subcollectionName}:`, subcollectionError);
      }
    }

    // Audit logging
    await db.collection('admin_audit_logs').add({
      action: 'ARCHIVED_PRODUCT_EDIT_APPROVED',
      adminId: userId,
      adminEmail: userData?.email || 'unknown',
      productId: result.productId,
      applicationId: applicationId,
      shopId: result.shopId || null,
      sourceCollection: result.sourceCollection,
      destCollection: result.destCollection,
      timestamp: FieldValue.serverTimestamp(),
      productName: result.productName,
      metadata: {
        subcollectionDocsMoved: totalSubcollectionDocsMoved,
      },
    });

    return {
      success: true,
      productId: result.productId,
      applicationId: applicationId,
      sourceCollection: result.sourceCollection,
      destCollection: result.destCollection,
      subcollectionDocsMoved: totalSubcollectionDocsMoved,
      message: 'Archived product update approved and product is now active',
    };
  } catch (error) {
    console.error('Error approving archived product edit:', error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('internal', 'Failed to approve edit');
  }
});
