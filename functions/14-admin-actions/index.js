import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';

// Constants for validation
const MAX_ARCHIVE_REASON_LENGTH = 1000;
const BATCH_SIZE = 400; // Keep under 500 for safety margin

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

    // Use transaction for atomicity on main document
    const result = await db.runTransaction(async (transaction) => {
      const productDoc = await transaction.get(sourceRef);

      if (!productDoc.exists) {
        throw new HttpsError('not-found', `Product not found in ${sourceCollection}`);
      }

      // Idempotency check - already in destination?
      const destDoc = await transaction.get(destRef);
      if (destDoc.exists) {
        console.log(`Product ${productId} already exists in ${destCollection}, skipping`);
        return { alreadyProcessed: true, productData: destDoc.data() };
      }

      const productData = productDoc.data();

      // Prepare update data
      const updateData = {
        ...productData,
        paused: archiveStatus,
        lastModified: FieldValue.serverTimestamp(),
        modifiedBy: userId,
      };

      if (archiveStatus) {
        updateData.archivedByAdmin = true;
        updateData.archivedByAdminAt = FieldValue.serverTimestamp();
        updateData.archivedByAdminId = userId;
        updateData.needsUpdate = needsUpdate === true;
        updateData.archiveReason = (needsUpdate && sanitizedArchiveReason) ? sanitizedArchiveReason : null;
        updateData.adminArchiveReason = updateData.archiveReason || 'Archived by admin';
      } else {
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

      return { alreadyProcessed: false, productData };
    });

    // If already processed, return early
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

    // Handle subcollections outside transaction
    const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences'];
    let totalSubcollectionDocsMoved = 0;

    for (const subcollectionName of subcollectionsToMove) {
      try {
        const movedCount = await moveSubcollection(
          db,
          sourceRef.collection(subcollectionName),
          destRef.collection(subcollectionName)
        );
        totalSubcollectionDocsMoved += movedCount;
      } catch (subcollectionError) {
        console.error(`Error moving ${subcollectionName}:`, subcollectionError);
      }
    }

    // Audit logging
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
      metadata: {
        previousState: {
          archivedByAdmin: result.productData?.archivedByAdmin || false,
          paused: result.productData?.paused || false,
          needsUpdate: result.productData?.needsUpdate || false,
        },
        newState: {
          archivedByAdmin: archiveStatus,
          paused: archiveStatus,
          needsUpdate: archiveStatus ? (needsUpdate === true) : false,
        },
        archiveReason: archiveStatus ? sanitizedArchiveReason : null,
        subcollectionDocsMoved: totalSubcollectionDocsMoved,
      },
    });

    if (archiveStatus && shopId) {
      try {
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
            const productName = result.productData?.productName || 'Your product';
    
            await db.collection('shop_notifications').add({
              type: 'product_archived_by_admin',
              shopId,
              shopName: shopData.name || '',
              productId,
              productName,
              needsUpdate: needsUpdate === true,
              archiveReason: sanitizedArchiveReason || null,
              isRead: isReadMap,
              timestamp: FieldValue.serverTimestamp(),
              message_en: needsUpdate ? `"${productName}" was paused by admin and needs updates: ${sanitizedArchiveReason || 'Please review'}` : `"${productName}" was paused by admin`,
              message_tr: needsUpdate ? `"${productName}" admin tarafından durduruldu ve güncelleme gerekiyor: ${sanitizedArchiveReason || 'Lütfen inceleyin'}` : `"${productName}" admin tarafından durduruldu`,
              message_ru: needsUpdate ? `"${productName}" приостановлен администратором и требует обновления: ${sanitizedArchiveReason || 'Пожалуйста, проверьте'}` : `"${productName}" приостановлен администратором`,
            });
    
            console.log(`✅ Admin archive notification created for shop ${shopId}`);
          }
        }
      } catch (notificationError) {
        console.error('Failed to create admin archive notification:', notificationError);
        // Don't fail the main operation
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
  const { applicationId } = request.data;

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
      const updatedProductData = { ...applicationData };
      
      // Remove application-specific fields
      const fieldsToRemove = [
        'originalProductId', 'editType', 'originalProductData', 'submittedAt',
        'status', 'editedFields', 'changes', 'sourceCollection', 'deletedColors',
        'phone', 'region', 'address', 'ibanOwnerName', 'ibanOwnerSurname', 'iban',
        'approvedAt', 'approvedBy', 'rejectedAt', 'rejectedBy', 'rejectionReason',
        'applicationId'
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
      updatedProductData.isBoosted = applicationData.isBoosted ?? originalProductData.isBoosted ?? false;
      
      // Ranking - PRESERVE FROM ORIGINAL
      updatedProductData.rankingScore = applicationData.rankingScore ?? originalProductData.rankingScore ?? 0;
      updatedProductData.promotionScore = applicationData.promotionScore ?? originalProductData.promotionScore ?? 0;
      
      // Boost tracking - PRESERVE FROM ORIGINAL
      updatedProductData.boostedImpressionCount = applicationData.boostedImpressionCount ?? originalProductData.boostedImpressionCount ?? 0;
      updatedProductData.boostImpressionCountAtStart = applicationData.boostImpressionCountAtStart ?? originalProductData.boostImpressionCountAtStart ?? 0;
      updatedProductData.boostClickCountAtStart = applicationData.boostClickCountAtStart ?? originalProductData.boostClickCountAtStart ?? 0;
      updatedProductData.boostStartTime = applicationData.boostStartTime ?? originalProductData.boostStartTime ?? null;
      updatedProductData.boostEndTime = applicationData.boostEndTime ?? originalProductData.boostEndTime ?? null;
      
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
          destRef.collection(subcollectionName)
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
