import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {CloudTasksClient} from '@google-cloud/tasks';
import {FieldValue} from 'firebase-admin/firestore';
 
// ═══════════════════════════════════════════════════════════════════════════
// Shared Storage cleanup helpers
// ═══════════════════════════════════════════════════════════════════════════

function extractStoragePathFromUrl(url, expectedBucket) {
  if (typeof url !== 'string' || !url.trim()) return null;
 
  try {
    if (url.startsWith('gs://')) {
      const withoutScheme = url.slice(5);
      const slashIdx = withoutScheme.indexOf('/');
      if (slashIdx === -1) return null;
      const bucket = withoutScheme.slice(0, slashIdx);
      const path = withoutScheme.slice(slashIdx + 1);
      if (bucket !== expectedBucket) return null;
      return path || null;
    }
 
    const parsed = new URL(url);
    if (!parsed.hostname.includes('firebasestorage.googleapis.com') &&
        !parsed.hostname.includes('firebasestorage.app')) {
      return null;
    }
 
    const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!match) return null;
 
    const bucket = match[1];
    const encodedPath = match[2];
    if (bucket !== expectedBucket) return null;
 
    return decodeURIComponent(encodedPath);
  } catch {
    return null;
  }
}

function isPathSafeForItem(path, collectionPrefix, ownerId, restaurantId) {
  if (typeof path !== 'string' || !path.trim()) return false;
 
  // Reject traversal and absolute paths
  if (path.includes('..') || path.startsWith('/')) return false;
 
  // Require the correct collection prefix
  if (!path.startsWith(`${collectionPrefix}/`)) return false;
 
  // If we know the owner AND restaurant, enforce full scoping
  if (ownerId && typeof ownerId === 'string' && ownerId.trim() &&
      restaurantId && typeof restaurantId === 'string' && restaurantId.trim()) {
    if (!path.startsWith(`${collectionPrefix}/${ownerId}/${restaurantId}/`)) {
      return false;
    }
  } else if (ownerId && typeof ownerId === 'string' && ownerId.trim()) {
    // Fallback: at least require owner scope
    if (!path.startsWith(`${collectionPrefix}/${ownerId}/`)) return false;
  }
 
  return true;
}

function collectItemStoragePaths(itemData, collectionPrefix, expectedBucket) {
  const paths = new Set();
  const ownerId = itemData?.ownerId || null;
  const restaurantId = itemData?.restaurantId || null;
 
  const addPath = (path) => {
    if (isPathSafeForItem(path, collectionPrefix, ownerId, restaurantId)) {
      paths.add(path);
    } else if (path) {
      console.warn(
        `Rejected unsafe storage path: "${path}" (owner: ${ownerId}, restaurant: ${restaurantId})`,
      );
    }
  };
 
  const addFromUrl = (url) => {
    const path = extractStoragePathFromUrl(url, expectedBucket);
    if (path) addPath(path);
  };
 
  // ─── Primary: explicit storage path field ─────────────────────────────
  if (typeof itemData?.imageStoragePath === 'string') {
    addPath(itemData.imageStoragePath);
  }
 
  // ─── Fallback: parse URL for legacy docs ──────────────────────────────
  if (!itemData?.imageStoragePath && typeof itemData?.imageUrl === 'string') {
    addFromUrl(itemData.imageUrl);
  }
 
  return Array.from(paths);
}

function isPathSafeForProduct(path, ownerId) {
  if (typeof path !== 'string' || !path.trim()) return false;
 
  // Reject traversal and absolute paths
  if (path.includes('..') || path.startsWith('/')) return false;
 
  if (!path.startsWith('products/')) return false;
 
  if (ownerId && typeof ownerId === 'string' && ownerId.trim()) {
    if (!path.startsWith(`products/${ownerId}/`)) return false;
  }
 
  return true;
}

function collectProductStoragePaths(productData, expectedBucket) {
  const paths = new Set();
  const ownerId = productData?.ownerId || productData?.userId || null;
 
  const addPath = (path) => {
    if (isPathSafeForProduct(path, ownerId)) {
      paths.add(path);
    } else if (path) {
      console.warn(`Rejected unsafe storage path: "${path}" (ownerId: ${ownerId})`);
    }
  };
 
  const addFromUrl = (url) => {
    const path = extractStoragePathFromUrl(url, expectedBucket);
    if (path) addPath(path);
  };
 
  // ─── Primary: explicit storage path fields ────────────────────────────
 
  // imageStoragePaths: array of path strings
  if (Array.isArray(productData?.imageStoragePaths)) {
    for (const p of productData.imageStoragePaths) addPath(p);
  }
 
  // colorImageStoragePaths: map where values are either strings OR arrays
  if (productData?.colorImageStoragePaths &&
      typeof productData.colorImageStoragePaths === 'object') {
    for (const value of Object.values(productData.colorImageStoragePaths)) {
      if (Array.isArray(value)) {
        for (const p of value) addPath(p);
      } else if (typeof value === 'string') {
        addPath(value);
      }
    }
  }
 
  // videoStoragePath: single string
  if (typeof productData?.videoStoragePath === 'string') {
    addPath(productData.videoStoragePath);
  }
 
  // ─── Fallback: parse URLs for legacy docs ──────────────────────────────
 
  if ((!Array.isArray(productData?.imageStoragePaths) ||
       productData.imageStoragePaths.length === 0) &&
      Array.isArray(productData?.imageUrls)) {
    for (const url of productData.imageUrls) addFromUrl(url);
  }
 
  if ((!productData?.colorImageStoragePaths ||
       Object.keys(productData.colorImageStoragePaths).length === 0) &&
      productData?.colorImages &&
      typeof productData.colorImages === 'object') {
    for (const value of Object.values(productData.colorImages)) {
      if (Array.isArray(value)) {
        for (const url of value) addFromUrl(url);
      } else if (typeof value === 'string') {
        addFromUrl(value);
      }
    }
  }
 
  if (!productData?.videoStoragePath && typeof productData?.videoUrl === 'string') {
    addFromUrl(productData.videoUrl);
  }
 
  return Array.from(paths);
}

async function deleteStorageFiles(paths, contextLabel) {
  if (paths.length === 0) {
    return {deleted: 0, failed: 0, missing: 0};
  }
 
  const bucket = admin.storage().bucket();
  let deleted = 0;
  let failed = 0;
  let missing = 0;
 
  const results = await Promise.allSettled(
    paths.map((path) => bucket.file(path).delete()),
  );
 
  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const path = paths[i];
 
    if (result.status === 'fulfilled') {
      deleted++;
    } else {
      const err = result.reason;
      if (err?.code === 404) {
        missing++;
      } else {
        failed++;
        console.warn(
          `[${contextLabel}] Failed to delete "${path}":`,
          err?.message || err,
        );
      }
    }
  }
 
  console.log(
    `[${contextLabel}] Storage: ${deleted} deleted, ${missing} already gone, ${failed} failed (total ${paths.length})`,
  );
 
  return {deleted, failed, missing};
}

function isRestaurantMember(authToken, restaurantId) {
  if (!authToken || !restaurantId) return false;
  const restaurants = authToken.restaurants;
  if (!restaurants || typeof restaurants !== 'object') return false;
  return restaurantId in restaurants;
}

function buildRemoveItemHandler({
  collectionName,
  idParamName,
  storagePrefix,
  actionName,
}) {
  return async (request) => {
    // ─── 1. Auth ──────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }
 
    const userId = request.auth.uid;
    const itemId = request.data?.[idParamName];
    const restaurantId = request.data?.restaurantId;
 
    // ─── 2. Input validation ──────────────────────────────────────────────
    if (typeof itemId !== 'string' || !itemId.trim()) {
      throw new HttpsError(
        'invalid-argument',
        `Valid ${idParamName} is required`,
      );
    }
    if (typeof restaurantId !== 'string' || !restaurantId.trim()) {
      throw new HttpsError('invalid-argument', 'Valid Restaurant ID is required');
    }
 
    const trimmedItemId = itemId.trim();
    const trimmedRestaurantId = restaurantId.trim();
    const db = admin.firestore();
    const expectedBucket = admin.storage().bucket().name;
    const contextLabel = `${actionName}:${trimmedItemId}`;
 
    try {
      // ─── 3. Permission check via custom claims (zero reads) ───────────
      if (!isRestaurantMember(request.auth.token, trimmedRestaurantId)) {
        throw new HttpsError(
          'permission-denied',
          'You don\'t have permission to modify items for this restaurant',
        );
      }
 
      // ─── 4. Item exists + belongs to this restaurant ──────────────────
      const itemRef = db.collection(collectionName).doc(trimmedItemId);
      const itemDoc = await itemRef.get();
 
      if (!itemDoc.exists) {
        throw new HttpsError('not-found', `${collectionName} item not found`);
      }
 
      const itemData = itemDoc.data();
 
      if (itemData?.restaurantId !== trimmedRestaurantId) {
        throw new HttpsError(
          'permission-denied',
          'Item does not belong to the specified restaurant',
        );
      }
 
      // ─── 5. Collect storage paths BEFORE deletion ─────────────────────
      const storagePaths = collectItemStoragePaths(
        itemData,
        storagePrefix,
        expectedBucket,
      );
      console.log(
        `[${contextLabel}] Found ${storagePaths.length} storage files to delete`,
      );
 
      // ─── 6. Delete Firestore doc + any subcollections ─────────────────
      // recursiveDelete is future-proof: if you ever add subcollections
      // (reviews, ratings, questions), they're handled automatically.
      await db.recursiveDelete(itemRef);
      console.log(`✓ Deleted Firestore doc: ${trimmedItemId}`);
 
      // ─── 7. Storage cleanup (best effort) ─────────────────────────────
      const storageResult = await deleteStorageFiles(storagePaths, contextLabel);
 
      // ─── 8. Audit log (non-blocking) ──────────────────────────────────
      db.collection('audit_logs')
        .add({
          action: actionName,
          itemId: trimmedItemId,
          itemCollection: collectionName,
          restaurantId: trimmedRestaurantId,
          deletedBy: userId,
          itemName: itemData?.name || 'Unknown',
          itemOwnerId: itemData?.ownerId || null,
          storageFilesTotal: storagePaths.length,
          storageFilesDeleted: storageResult.deleted,
          storageFilesMissing: storageResult.missing,
          storageFilesFailed: storageResult.failed,
          timestamp: FieldValue.serverTimestamp(),
        })
        .catch((err) => console.error('Non-critical: audit log failed:', err));
 
      // ─── 9. Response ──────────────────────────────────────────────────
      return {
        success: true,
        message: 'Item successfully removed',
        [idParamName]: trimmedItemId,
        restaurantId: trimmedRestaurantId,
        storageFilesDeleted: storageResult.deleted,
        storageFilesFailed: storageResult.failed,
      };
    } catch (error) {
      console.error(`[${contextLabel}] Error:`, error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        'internal',
        'Failed to remove item. Please try again.',
      );
    }
  };
}
 
// ═══════════════════════════════════════════════════════════════════════════
// Exported Cloud Functions
// ═══════════════════════════════════════════════════════════════════════════
 
export const removeFood = onCall(
  {
    region: 'europe-west3',
    maxInstances: 10,
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  buildRemoveItemHandler({
    collectionName: 'foods',
    idParamName: 'foodId',
    storagePrefix: 'foods',
    actionName: 'food_deleted',
  }),
);
 
export const removeDrink = onCall(
  {
    region: 'europe-west3',
    maxInstances: 10,
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  buildRemoveItemHandler({
    collectionName: 'drinks',
    idParamName: 'drinkId',
    storagePrefix: 'drinks',
    actionName: 'drink_deleted',
  }),
);
 
// ═══════════════════════════════════════════════════════════════════════════
// removeShopProduct — Delete a product belonging to a shop
// ═══════════════════════════════════════════════════════════════════════════
 
export const removeShopProduct = onCall(
  {
    region: 'europe-west3',
    maxInstances: 10,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (request) => {
    // ─── 1. Auth ──────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }
 
    const userId = request.auth.uid;
    const {productId, shopId} = request.data || {};
 
    // ─── 2. Input validation ──────────────────────────────────────────────
    if (typeof productId !== 'string' || !productId.trim()) {
      throw new HttpsError('invalid-argument', 'Valid Product ID is required');
    }
    if (typeof shopId !== 'string' || !shopId.trim()) {
      throw new HttpsError('invalid-argument', 'Valid Shop ID is required');
    }
 
    const trimmedProductId = productId.trim();
    const trimmedShopId = shopId.trim();
    const db = admin.firestore();
    const expectedBucket = admin.storage().bucket().name;
 
    try {
      // ─── 3. Shop exists + user is a member ────────────────────────────
      const shopDoc = await db.collection('shops').doc(trimmedShopId).get();
      if (!shopDoc.exists) {
        throw new HttpsError('not-found', 'Shop not found');
      }
 
      const shopData = shopDoc.data();
      const isOwner = shopData?.ownerId === userId;
      const isCoOwner = Array.isArray(shopData?.coOwners) && shopData.coOwners.includes(userId);
      const isEditor = Array.isArray(shopData?.editors) && shopData.editors.includes(userId);
 
      if (!isOwner && !isCoOwner && !isEditor) {
        throw new HttpsError(
          'permission-denied',
          'You don\'t have permission to delete products from this shop',
        );
      }
 
      // ─── 4. Product exists + belongs to this shop ─────────────────────
      const productRef = db.collection('shop_products').doc(trimmedProductId);
      const productDoc = await productRef.get();
 
      if (!productDoc.exists) {
        throw new HttpsError('not-found', 'Product not found');
      }
 
      const productData = productDoc.data();
 
      if (productData?.shopId !== trimmedShopId) {
        throw new HttpsError(
          'permission-denied',
          'Product does not belong to the specified shop',
        );
      }
 
      // ─── 5. Collect storage paths BEFORE deletion ─────────────────────
      const storagePaths = collectProductStoragePaths(productData, expectedBucket);
      console.log(
        `[removeShopProduct:${trimmedProductId}] Found ${storagePaths.length} storage files to delete`,
      );
 
      // ─── 6. Delete Firestore (source of truth) ────────────────────────
      // recursiveDelete handles both cases: with or without subcollections.
      // If this fails, we haven't touched Storage yet.
      await db.recursiveDelete(productRef);
      console.log(`✓ Deleted Firestore doc: ${trimmedProductId}`);
 
      // ─── 7. Clean up array references (best effort) ───────────────────
      let cleanupCount = 0;
      try {
        cleanupCount = await cleanupProductReferences(db, trimmedShopId, trimmedProductId);
      } catch (cleanupErr) {
        console.error(
          `Non-critical: reference cleanup failed for ${trimmedProductId}:`,
          cleanupErr,
        );
      }
 
      // ─── 8. Storage cleanup (best effort) ─────────────────────────────
      const storageResult = await deleteStorageFiles(
        storagePaths,
        `removeShopProduct:${trimmedProductId}`,
      );
 
      // ─── 9. Audit log (non-blocking) ──────────────────────────────────
      db.collection('audit_logs')
        .add({
          action: 'shop_product_deleted',
          productId: trimmedProductId,
          shopId: trimmedShopId,
          deletedBy: userId,
          deletedByRole: isOwner ? 'owner' : isCoOwner ? 'co-owner' : 'editor',
          productName: productData?.productName || 'Unknown',
          productOwnerId: productData?.ownerId || null,
          referencesCleanedUp: cleanupCount,
          storageFilesTotal: storagePaths.length,
          storageFilesDeleted: storageResult.deleted,
          storageFilesMissing: storageResult.missing,
          storageFilesFailed: storageResult.failed,
          timestamp: FieldValue.serverTimestamp(),
        })
        .catch((err) => console.error('Non-critical: audit log failed:', err));
 
      // ─── 10. Response ─────────────────────────────────────────────────
      return {
        success: true,
        message: 'Product successfully removed',
        productId: trimmedProductId,
        shopId: trimmedShopId,
        storageFilesDeleted: storageResult.deleted,
        storageFilesFailed: storageResult.failed,
      };
    } catch (error) {
      console.error('Error removing shop product:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        'internal',
        'Failed to remove product. Please try again.',
      );
    }
  },
);

async function cleanupProductReferences(db, shopId, productId) {
  const batch = db.batch();
  let batchCount = 0;
 
  const campaignsSnap = await db
    .collection('campaigns')
    .where('shopId', '==', shopId)
    .where('productIds', 'array-contains', productId)
    .limit(500)
    .get();
 
  campaignsSnap.forEach((doc) => {
    if (batchCount >= 500) return;
    batch.update(doc.ref, {
      productIds: FieldValue.arrayRemove(productId),
    });
    batchCount++;
  });
 
  const remaining = 500 - batchCount;
  if (remaining > 0) {
    const collectionsSnap = await db
      .collection('product_collections')
      .where('shopId', '==', shopId)
      .where('productIds', 'array-contains', productId)
      .limit(remaining)
      .get();
 
    collectionsSnap.forEach((doc) => {
      if (batchCount >= 500) return;
      batch.update(doc.ref, {
        productIds: FieldValue.arrayRemove(productId),
      });
      batchCount++;
    });
  }
 
  if (batchCount > 0) {
    await batch.commit();
    console.log(`✓ Cleaned up ${batchCount} product references`);
  }
 
  return batchCount;
}
 
// ═══════════════════════════════════════════════════════════════════════════
// deleteProduct — Delete a user-owned product
// ═══════════════════════════════════════════════════════════════════════════
 
export const deleteProduct = onCall(
  {
    region: 'europe-west3',
    maxInstances: 100,
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  async (request) => {
    // ─── 1. Auth ──────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated to delete products.',
      );
    }
 
    const userId = request.auth.uid;
    const {productId} = request.data || {};
 
    // ─── 2. Input validation ──────────────────────────────────────────────
    if (typeof productId !== 'string' || !productId.trim()) {
      throw new HttpsError(
        'invalid-argument',
        'Product ID is required and must be a valid string.',
      );
    }
 
    const trimmedProductId = productId.trim();
    const db = admin.firestore();
    const expectedBucket = admin.storage().bucket().name;
    const productRef = db.collection('products').doc(trimmedProductId);
 
    try {
      // ─── 3. Read + verify ownership ───────────────────────────────────
      const productDoc = await productRef.get();
 
      if (!productDoc.exists) {
        throw new HttpsError('not-found', 'Product not found.');
      }
 
      const productData = productDoc.data();
 
      if (productData?.userId !== userId) {
        throw new HttpsError(
          'permission-denied',
          'You do not have permission to delete this product.',
        );
      }
 
      // ─── 4. Collect storage paths BEFORE deletion ─────────────────────
      const storagePaths = collectProductStoragePaths(productData, expectedBucket);
      console.log(
        `[deleteProduct:${trimmedProductId}] Found ${storagePaths.length} storage files to delete`,
      );
 
      // ─── 5. Delete Firestore + all subcollections ─────────────────────
      await db.recursiveDelete(productRef);
      console.log(`✓ Deleted Firestore doc: ${trimmedProductId}`);
 
      // ─── 6. Storage cleanup (best effort) ─────────────────────────────
      const storageResult = await deleteStorageFiles(
        storagePaths,
        `deleteProduct:${trimmedProductId}`,
      );
 
      // ─── 7. Audit log (non-blocking) ──────────────────────────────────
      db.collection('audit_logs')
        .add({
          action: 'user_product_deleted',
          productId: trimmedProductId,
          deletedBy: userId,
          productName: productData?.productName || 'Unknown',
          storageFilesTotal: storagePaths.length,
          storageFilesDeleted: storageResult.deleted,
          storageFilesMissing: storageResult.missing,
          storageFilesFailed: storageResult.failed,
          timestamp: FieldValue.serverTimestamp(),
        })
        .catch((err) => console.error('Non-critical: audit log failed:', err));
 
      // ─── 8. Response ──────────────────────────────────────────────────
      return {
        success: true,
        message: 'Product deleted successfully.',
        productId: trimmedProductId,
        storageFilesDeleted: storageResult.deleted,
        storageFilesFailed: storageResult.failed,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('Error deleting product:', error);
      throw new HttpsError(
        'internal',
        'An error occurred while deleting the product. Please try again.',
      );
    }
  },
);
  
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
