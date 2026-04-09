import {onCall, HttpsError} from 'firebase-functions/v2/https';                                                                                                                                                                                           
  import admin from 'firebase-admin';                                                                                                                                                                                                                       
  import {FieldValue} from 'firebase-admin/firestore'; 
  import {CloudTasksClient} from '@google-cloud/tasks';  

export const removeShopProduct = onCall(
    {
      region: 'europe-west3',
      maxInstances: 10,
      timeoutSeconds: 540, // Max timeout for recursive deletion
      memory: '512MiB',
    },
    async (request) => {
      // === 1) Authentication ===
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }
  
      const userId = request.auth.uid;
      const {productId, shopId} = request.data;
  
      // === 2) Input validation ===
      if (typeof productId !== 'string' || !productId.trim()) {
        throw new HttpsError('invalid-argument', 'Valid Product ID is required');
      }
  
      if (typeof shopId !== 'string' || !shopId.trim()) {
        throw new HttpsError('invalid-argument', 'Valid Shop ID is required');
      }
  
      const trimmedProductId = productId.trim();
      const trimmedShopId = shopId.trim();
  
      const db = admin.firestore();
  
      try {
        // === 3) Verify shop exists and user has permission ===
        const shopDoc = await db.collection('shops').doc(trimmedShopId).get();
  
        if (!shopDoc.exists) {
          throw new HttpsError('not-found', 'Shop not found');
        }
  
        const shopData = shopDoc.data();
  
        // Check permissions (owner, co-owner, or editor)
        const isOwner = shopData?.ownerId === userId;
        const isCoOwner = Array.isArray(shopData?.coOwners) &&
          shopData.coOwners.includes(userId);
        const isEditor = Array.isArray(shopData?.editors) &&
          shopData.editors.includes(userId);
  
        if (!isOwner && !isCoOwner && !isEditor) {
          throw new HttpsError(
            'permission-denied',
            'You don\'t have permission to delete products from this shop',
          );
        }
  
        // === 4) Verify product exists and belongs to this shop ===
        const productRef = db.collection('shop_products').doc(trimmedProductId);
        const productDoc = await productRef.get();
  
        if (!productDoc.exists) {
          throw new HttpsError('not-found', 'Product not found');
        }
  
        const productData = productDoc.data();
  
        // CRITICAL: Verify product belongs to the specified shop
        if (productData?.shopId !== trimmedShopId) {
          throw new HttpsError(
            'permission-denied',
            'Product does not belong to the specified shop',
          );
        }
  
        // === 5) Check for subcollections before deletion ===
        const hasSubcollections = await checkProductSubcollections(productRef);
  
        // === 6) Delete product and all subcollections ===
        if (hasSubcollections) {
          // Use recursiveDelete for products with subcollections
          await db.recursiveDelete(productRef);// ← Remove the options object
          console.log(
            `✓ Recursively deleted product ${trimmedProductId} with subcollections`,
          );
        } else {
          // Simple delete for products without subcollections (faster)
          await productRef.delete();
          console.log(`✓ Deleted product ${trimmedProductId} (no subcollections)`);
        }
  
        // === 7) Clean up related data (batch operations for atomicity) ===
        const batch = db.batch();
        let batchCount = 0;
  
        const campaignsQuery = await db
          .collection('campaigns')
          .where('shopId', '==', trimmedShopId)
          .where('productIds', 'array-contains', trimmedProductId)
          .limit(500) // Safety limit
          .get();
  
        campaignsQuery.forEach((doc) => {
          if (batchCount >= 500) return; // Firestore batch limit
          batch.update(doc.ref, {
            productIds: FieldValue.arrayRemove(trimmedProductId),
          });
          batchCount++;
        });
  
        // Remove from collections (if applicable)
        const collectionsQuery = await db
          .collection('product_collections')
          .where('shopId', '==', trimmedShopId)
          .where('productIds', 'array-contains', trimmedProductId)
          .limit(500)
          .get();
  
        collectionsQuery.forEach((doc) => {
          if (batchCount >= 500) return;
          batch.update(doc.ref, {
            productIds: FieldValue.arrayRemove(trimmedProductId),
          });
          batchCount++;
        });
  
        // Commit cleanup batch if there are operations
        if (batchCount > 0) {
          await batch.commit();
          console.log(`✓ Cleaned up ${batchCount} related references`);
        }
  
        // === 8) Audit log (non-blocking) ===
        // Use .catch() to prevent audit log failures from affecting the operation
        db.collection('audit_logs')
          .add({
            action: 'product_deleted',
            productId: trimmedProductId,
            shopId: trimmedShopId,
            deletedBy: userId,
            deletedByRole: isOwner ? 'owner' : isCoOwner ? 'co-owner' : 'editor',
            productName: productData?.productName || 'Unknown',
            productSku: productData?.sku || null,
            hadSubcollections: hasSubcollections,
            timestamp: FieldValue.serverTimestamp(),
          })
          .catch((err) => {
            console.error('Non-critical: Audit log failed:', err);
          });
  
        // === 9) Success response ===
        return {
          success: true,
          message: 'Product successfully removed',
          productId: trimmedProductId,
          shopId: trimmedShopId,
          subcollectionsDeleted: hasSubcollections,
        };
      } catch (error) {
        console.error('Error removing product:', error);
  
        // Re-throw HttpsErrors as-is
        if (error instanceof HttpsError) {
          throw error;
        }
  
        // Convert other errors to HttpsError
        throw new HttpsError(
          'internal',
          'Failed to remove product. Please try again.',
        );
      }
    },
  );
  
  async function checkProductSubcollections(
    productRef) {
    try {
      const collections = await productRef.listCollections();
      return collections.length > 0;
    } catch (err) {
      console.error('Error checking subcollections:', err);
      return false; // Fail safe: assume no subcollections
    }
  }
  
  export const deleteProduct = onCall(
    {
      region: 'europe-west3',
      maxInstances: 100,
      timeoutSeconds: 60,
      memory: '256MiB',
    },
    async (request) => {
      const {auth, data} = request;
  
      // Authentication check
      if (!auth) {
        throw new HttpsError(
          'unauthenticated',
          'User must be authenticated to delete products.',
        );
      }
  
      const userId = auth.uid;
      const {productId} = data;
  
      // Input validation
      if (!productId || typeof productId !== 'string' || productId.trim() === '') {
        throw new HttpsError(
          'invalid-argument',
          'Product ID is required and must be a valid string.',
        );
      }
  
      try {
        // Use a transaction for consistency
        await admin.firestore().runTransaction(async (transaction) => {
          const productRef = admin.firestore().collection('products').doc(productId);
          const productDoc = await transaction.get(productRef);
  
          // Check if product exists
          if (!productDoc.exists) {
            throw new HttpsError('not-found', 'Product not found.');
          }
  
          const productData = productDoc.data();
  
          // Authorization check - verify ownership
          if (productData.userId !== userId) {
            throw new HttpsError(
              'permission-denied',
              'You do not have permission to delete this product.',
            );
          }
  
          // Delete the product document
          transaction.delete(productRef);
        });
  
        // Delete subcollections after transaction completes
        // This is done outside the transaction to avoid timeout issues
        await deleteSubcollections(productId);
  
        return {
          success: true,
          message: 'Product deleted successfully.',
          productId: productId,
        };
      } catch (error) {
        // Re-throw HttpsErrors as-is
        if (error instanceof HttpsError) {
          throw error;
        }
  
        // Log unexpected errors
        console.error('Error deleting product:', error);
  
        throw new HttpsError(
          'internal',
          'An error occurred while deleting the product. Please try again.',
        );
      }
    },
  );
  
  async function deleteSubcollections(productId) {
    const productRef = admin.firestore().collection('products').doc(productId);
  
    // List of known subcollections (add more if needed)
    const subcollections = ['detailViews', 'reviews', 'ratings', 'product_questions', 'sale_preferences'];
  
    const deletionPromises = subcollections.map((subcollection) =>
      deleteCollection(productRef.collection(subcollection), 100),
    );
  
    await Promise.all(deletionPromises);
  }
  
  async function deleteCollection(collectionRef, batchSize) {
    const query = collectionRef.limit(batchSize);
  
    return new Promise((resolve, reject) => {
      deleteQueryBatch(query, resolve, reject);
    });
  }
  
  async function deleteQueryBatch(query, resolve, reject) {
    try {
      const snapshot = await query.get();
  
      // No more documents to delete
      if (snapshot.size === 0) {
        resolve();
        return;
      }
  
      // Delete documents in a batch
      const batch = admin.firestore().batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });
  
      await batch.commit();
  
      // Recurse on the next batch
      process.nextTick(() => {
        deleteQueryBatch(query, resolve, reject);
      });
    } catch (error) {
      reject(error);
    }
  }
  
  export const toggleProductPauseStatus = onCall({
    region: 'europe-west3',
    maxInstances: 10,
    timeoutSeconds: 120,
    memory: '256MiB',
  }, async (request) => {
    // Verify authentication
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }
  
    const userId = request.auth.uid;
    const {productId, shopId, pauseStatus} = request.data;
  
    // Validate required parameters
    if (!productId || !shopId || pauseStatus === undefined) {
      throw new HttpsError('invalid-argument', 'Product ID, Shop ID, and pause status are required');
    }
  
    try {
      // Verify user has permission to modify this shop
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
  
      if (!shopDoc.exists) {
        throw new HttpsError('not-found', 'Shop not found');
      }
  
      const shopData = shopDoc.data();
  
      // Check if user is owner, co-owner, or editor
      const isOwner = shopData.ownerId === userId;
      const isCoOwner = (shopData.coOwners || []).includes(userId);
      const isEditor = (shopData.editors || []).includes(userId);
  
      if (!isOwner && !isCoOwner && !isEditor) {
        throw new HttpsError(
          'permission-denied',
          'You don\'t have permission to modify products in this shop',
        );
      }
  
      // Determine source and destination collections based on pause status
      const sourceCollection = pauseStatus ? 'shop_products' : 'paused_shop_products';
      const destCollection = pauseStatus ? 'paused_shop_products' : 'shop_products';
  
      const sourceRef = admin.firestore().collection(sourceCollection).doc(productId);
      const destRef = admin.firestore().collection(destCollection).doc(productId);
  
      // Get the product from source collection
      const productDoc = await sourceRef.get();
  
      if (!productDoc.exists) {
        throw new HttpsError('not-found', `Product not found in ${sourceCollection}`);
      }
  
      const productData = productDoc.data();
  
      // Prevent users from unarchiving products archived by admin
      if (!pauseStatus && productData.archivedByAdmin === true) {
        throw new HttpsError(
          'permission-denied',
          'Bu ürün bir yönetici tarafından arşivlenmiştir. Daha fazla bilgi için destek ile iletişime geçin.',
        );
      }
  
      // Verify product belongs to the specified shop
      if (productData.shopId !== shopId) {
        throw new HttpsError(
          'permission-denied',
          'Product does not belong to the specified shop',
        );
      }
  
      // ================================================================
      // Capture boost state BEFORE modifying anything
      // ================================================================
      let boostCleanupData = null;
  
      if (pauseStatus && productData.isBoosted === true) {
        console.log(`Product ${productId} is boosted — will clean boost before archiving`);
  
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
        };
      }
  
      // ================================================================
      // Prepare the data to write to the destination collection
      // ================================================================
      const destData = {
        ...productData,
        paused: pauseStatus,
        lastModified: FieldValue.serverTimestamp(),
        modifiedBy: userId,
      };
  
      // If archiving a boosted product, clean boost fields from dest data
      if (boostCleanupData) {
        destData.isBoosted = false;
        destData.lastBoostExpiredAt = FieldValue.serverTimestamp();
        destData.promotionScore = Math.max((productData.promotionScore || 0) - 1000, 0);
  
        delete destData.boostStartTime;
        delete destData.boostEndTime;
        delete destData.boostExpirationTaskName;
        delete destData.boostDuration;
        delete destData.boostScreen;
        delete destData.screenType;
        delete destData.boostImpressionCountAtStart;
        delete destData.boostClickCountAtStart;
      }
  
      // ================================================================
      // Atomic move: write to dest + delete from source
      // ================================================================
      const batch = admin.firestore().batch();
      batch.set(destRef, destData);
      batch.delete(sourceRef);
      await batch.commit();
  
      // ================================================================
      // Move subcollections (outside batch — best effort)
      // ================================================================
      const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences'];
  
      for (const subcollectionName of subcollectionsToMove) {
        try {
          const sourceSubcollection = sourceRef.collection(subcollectionName);
          const destSubcollection = destRef.collection(subcollectionName);
  
          const snapshot = await sourceSubcollection.get();
  
          if (!snapshot.empty) {
            const batchSize = 500;
            let currentBatch = admin.firestore().batch();
            let operationCount = 0;
  
            for (const doc of snapshot.docs) {
              currentBatch.set(destSubcollection.doc(doc.id), doc.data());
              currentBatch.delete(doc.ref);
              operationCount += 2;
  
              if (operationCount >= batchSize) {
                await currentBatch.commit();
                currentBatch = admin.firestore().batch();
                operationCount = 0;
              }
            }
  
            if (operationCount > 0) {
              await currentBatch.commit();
            }
          }
        } catch (subcollectionError) {
          console.log(`No ${subcollectionName} subcollection or error moving it:`, subcollectionError);
        }
      }
  
      // ================================================================
      // Boost cleanup (best-effort, non-blocking)
      // ================================================================
      if (boostCleanupData) {
        const bcd = boostCleanupData;
        console.log(`Performing boost cleanup for ${productId}`);
  
        // 1. Update boost history with final stats
        if (bcd.boostStartTime) {
          try {
            const historyCol = admin.firestore()
              .collection('shops')
              .doc(shopId)
              .collection('boostHistory');
  
            const historySnap = await historyCol
              .where('itemId', '==', productId)
              .where('boostStartTime', '==', bcd.boostStartTime)
              .limit(1)
              .get();
  
              const impressionsDuringBoost = Math.max(
                bcd.boostedImpressionCount - bcd.boostImpressionCountAtStart, 0,
              );
              const clicksDuringBoost = Math.max(
                bcd.clickCount - bcd.boostClickCountAtStart, 0,
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
                expiredReason: 'seller_archived',
                terminatedEarly: true,
              };
    
              if (!historySnap.empty) {
                await historySnap.docs[0].ref.update(historyData);
                console.log(`✅ Boost history updated for ${productId}`);
              } else {
                await historyCol.add({
                  ...historyData,
                  itemId: productId,
                  itemType: 'shop_product',
                  boostStartTime: bcd.boostStartTime,
                  createdAt: FieldValue.serverTimestamp(),
                });
                console.log(`✅ Boost history created for ${productId} (none existed)`);
              }
          } catch (historyError) {
            console.error(`Failed to update boost history for ${productId}:`, historyError);
          }
        }
  
        // 2. Cancel scheduled Cloud Task
        if (bcd.boostExpirationTaskName) {
          try {
            const projectId = process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'emlak-mobile-app';
            const tasksClient = new CloudTasksClient();
            const taskPath = tasksClient.taskPath(
              projectId,
              'europe-west3',
              'boost-expiration-queue',
              bcd.boostExpirationTaskName,
            );
            await tasksClient.deleteTask({name: taskPath});
            console.log(`✅ Cancelled boost expiration task: ${bcd.boostExpirationTaskName}`);
          } catch (taskError) {
            if (taskError.code === 5) {
              console.log(`Boost task already completed/deleted: ${bcd.boostExpirationTaskName}`);
            } else {
              console.warn(`Could not cancel boost task: ${taskError.message}`);
            }
          }
        }
  
        // 3. Single shop notification
        try {
          await admin.firestore().collection('shop_notifications').add({
            shopId: shopId,
            type: 'boost_expired',
            productId: productId,
            productName: bcd.productName,
            productImage: bcd.productImage,
            reason: 'seller_archived',
            isRead: {},
            timestamp: FieldValue.serverTimestamp(),
          });
          console.log(`✅ Boost-expired shop notification created for shop ${shopId}`);
        } catch (notifError) {
          console.error(`Failed to create boost-expired shop notification:`, notifError);
        }
      }
  
      return {
        success: true,
        productId: productId,
        paused: pauseStatus,
        boostExpired: boostCleanupData !== null,
      };
    } catch (error) {
      console.error('Error toggling product pause status:', error);
  
      if (error instanceof HttpsError) {
        throw error;
      }
  
      throw new HttpsError(
        'internal',
        'Failed to update product status. Please try again.',
      );
    }
  });
