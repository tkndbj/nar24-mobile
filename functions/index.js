// functions/index.js
import {setGlobalOptions} from 'firebase-functions/v2';
import {checkRateLimit, dedup} from './shared/redis.js';
import {onDocumentWritten, onDocumentUpdated} from 'firebase-functions/v2/firestore';
import {onRequest, onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {onObjectFinalized} from 'firebase-functions/v2/storage';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import {getDominantColor} from './getDominantColor.js';
import {CloudTasksClient} from '@google-cloud/tasks';
import {FieldValue} from 'firebase-admin/firestore';

setGlobalOptions({
  serviceAccount: 'emlak-mobile-app@appspot.gserviceaccount.com',
});

admin.initializeApp();

export const incrementImpressionCount = onCall(
  {
    region: 'europe-west3',    
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (request) => {
    const productIds = request.data.productIds;
    const userGender = request.data.userGender;
    const userAge = request.data.userAge;

    // Validation
    if (!Array.isArray(productIds) || productIds.length === 0) {
      throw new Error('The function must be called with a non-empty array of productIds.');
    }

    // Deduplicate and limit
    const productCounts = new Map();
productIds.forEach((id) => {
  productCounts.set(id, (productCounts.get(id) || 0) + 1);
});

const productsWithCounts = Array.from(productCounts.entries()).map(([productId, count]) => ({
  productId,
  count,
}));

if (productsWithCounts.length > 100) {
  console.warn(`Large batch of ${productsWithCounts.length} unique products, trimming to 100`);
  productsWithCounts.length = 100;
}

const CHUNK_SIZE = 25;
const chunks = [];

for (let i = 0; i < productsWithCounts.length; i += CHUNK_SIZE) {
  chunks.push(productsWithCounts.slice(i, i + CHUNK_SIZE));
}

    // Initialize Cloud Tasks client
    const client = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT;
    const location = 'europe-west3';
    const queue = 'impressionqueue';
    const queuePath = client.queuePath(project, location, queue);
    
    // Worker function URL
    const functionUrl = `https://${location}-${project}.cloudfunctions.net/impressionqueueWorker`;

    const buildTask = (chunk) => ({
      httpRequest: {
        httpMethod: 'POST',
        url: functionUrl,
        headers: { 'Content-Type': 'application/json' },
        body: Buffer.from(JSON.stringify({
          data: { products: chunk, userGender, userAge, timestamp: Date.now() },
        })).toString('base64'),
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
      dispatchDeadline: { seconds: 300 },
    });

    const results = await Promise.allSettled(
      chunks.map((chunk) => client.createTask({ parent: queuePath, task: buildTask(chunk) }))
    );

    const enqueuedTasks = results
      .filter((r) => r.status === 'fulfilled')
      .map((r) => r.value[0].name);

    results
      .filter((r) => r.status === 'rejected')
      .forEach((r) => console.error('Failed to enqueue task:', r.reason));

    // Quick response to user
    return {
      success: true,
      queued: enqueuedTasks.length,
      totalImpressions: productIds.length,
      message: 'Impressions are being recorded',
    };
  },
);

// ============================================================================
// HTTP WORKER FUNCTION - Processes impressions in background
// ============================================================================

const chunkArray = (arr, size) =>
  Array.from({ length: Math.ceil(arr.length / size) }, (_, i) =>
    arr.slice(i * size, i * size + size)
  );

export const impressionqueueWorker = onRequest(
  {
    region: 'europe-west3',
    timeoutSeconds: 300,
    memory: '512MiB',
    invoker: 'private', // Only Cloud Tasks (via service account) can invoke
  },
  async (req, res) => {
    try {
      // Extract data from request body
      const {products, userGender, userAge} = req.body.data || req.body;

if (!Array.isArray(products) || products.length === 0) {
  console.warn('Task received empty products, skipping');
  res.status(200).send('OK');
  return;
}

      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      // Helper: Calculate age group
      const getAgeGroup = (age) => {
        if (!age) return 'unknown';
        if (age < 18) return 'under18';
        if (age < 25) return '18-24';
        if (age < 35) return '25-34';
        if (age < 45) return '35-44';
        if (age < 55) return '45-54';
        return '55plus';
      };

      // Helper: normalize product ID
      const normalizeId = (id) => {
        if (id.startsWith('shop_products_')) {
          return {collection: 'shop_products', id: id.slice(14)};
        }
        if (id.startsWith('products_')) {
          return {collection: 'products', id: id.slice(9)};
        }
        return null;
      };

      // Group IDs by collection
      const productGroups = {
        products: [],
        shop_products: [],
        unknown: [],
      };

      products.forEach(({productId, count}) => {
        const norm = normalizeId(productId);
        if (norm) {
          productGroups[norm.collection].push({id: norm.id, count});
        } else {
          productGroups.unknown.push({id: productId, count});
        }
      });

      // Fetch documents in parallel with error handling
      const fetchWithRetry = async (collection, id, count) => {
        try {
          const snap = await db.collection(collection).doc(id).get();
          return snap.exists ? {
            ref: snap.ref,
            data: snap.data(),
            collection,
            count, // ✅ Added count
          } : null;
        } catch (error) {
          console.error(`Error fetching ${collection}/${id}:`, error);
          return null;
        }
      };

      const fetches = [];

      // Fetch known collections
      if (productGroups.products.length > 0) {
        fetches.push(
          ...productGroups.products.map(({id, count}) => fetchWithRetry('products', id, count)),
        );
      }

      if (productGroups.shop_products.length > 0) {
        fetches.push(
          ...productGroups.shop_products.map(({id, count}) => fetchWithRetry('shop_products', id, count)),
        );
      }

      // For unknown IDs, check both collections
      if (productGroups.unknown.length > 0) {
        fetches.push(
          ...productGroups.unknown.map(async ({id, count}) => {
            const [pSnap, sSnap] = await Promise.all([
              db.collection('products').doc(id).get().catch(() => null),
              db.collection('shop_products').doc(id).get().catch(() => null),
            ]);
            
            if (pSnap?.exists) {
              return {ref: pSnap.ref, data: pSnap.data(), collection: 'products', count};
            }
            if (sSnap?.exists) {
              return {ref: sSnap.ref, data: sSnap.data(), collection: 'shop_products', count};
            }
            return null;
          }),
        );
      }

      const resolved = (await Promise.all(fetches)).filter((x) => x);

      if (resolved.length === 0) {
        console.warn('No valid products found for impression tracking');
        res.status(200).send('OK');
        return;
      }

      // Separate pipelines: user products vs shop products
      const boostedUserProducts = {}; // userId -> products
      const boostedShopProducts = {}; // shopId -> products
      const regularProducts = [];

      resolved.forEach(({ref, data, collection, count}) => {
        if (data.isBoosted && data.boostStartTime) {
          if (collection === 'shop_products' && data.shopId) {
            if (!boostedShopProducts[data.shopId]) {
              boostedShopProducts[data.shopId] = [];
            }
            boostedShopProducts[data.shopId].push({
              ref,
              data,
              itemId: ref.id,
              boostStartTime: data.boostStartTime,
              count, // ✅ Added
            });
          } else if (collection === 'products' && data.userId) {
            if (!boostedUserProducts[data.userId]) {
              boostedUserProducts[data.userId] = [];
            }
            boostedUserProducts[data.userId].push({
              ref,
              data,
              itemId: ref.id,
              boostStartTime: data.boostStartTime,
              count, // ✅ Added
            });
          } else {
            regularProducts.push({ref, data, isBoosted: true, count});
          }
        } else {
          regularProducts.push({ref, data, isBoosted: false, count});
        }
      });

      // Process in smaller batches to respect Firestore 500 operation limit
      const MAX_BATCH_SIZE = 400; // Safe buffer under 500
      let batch = db.batch();
      let operationCount = 0;

      const commitBatch = async () => {
        if (operationCount > 0) {
          try {
            await batch.commit();
            console.log(`Committed batch with ${operationCount} operations`);
          } catch (error) {
            console.error('Batch commit failed:', error);
            throw error; // Retry via Cloud Tasks
          }
          batch = db.batch();
          operationCount = 0;
        }
      };

      // Update regular products
      for (const {ref, isBoosted, count} of regularProducts) {
        if (operationCount >= MAX_BATCH_SIZE) {
          await commitBatch();
        }
      
        const updates = {
          impressionCount: admin.firestore.FieldValue.increment(count), // ✅ Use count
          lastImpressionTime: now,
          metricsUpdatedAt: now,
        };
      
        if (isBoosted) {
          updates.boostedImpressionCount = admin.firestore.FieldValue.increment(count); // ✅ Use count
        }
      
        batch.update(ref, updates);
        operationCount++;
      }

      // Calculate demographics once
      const ageGroup = getAgeGroup(userAge);
      const gender = (userGender || 'unknown').toLowerCase();

      // Process user products boost history
      for (const [userId, userProducts] of Object.entries(boostedUserProducts)) {
        // Update product documents
        for (const {ref, count} of userProducts) {
          if (operationCount >= MAX_BATCH_SIZE) {
            await commitBatch();
          }
        
          batch.update(ref, {
            impressionCount: admin.firestore.FieldValue.increment(count), // ✅ Use count
            boostedImpressionCount: admin.firestore.FieldValue.increment(count), // ✅ Use count
            lastImpressionTime: now,
            metricsUpdatedAt: now,
          });
          operationCount++;
        }

        // Update boost history
        const itemIds = userProducts.map((p) => p.itemId);
        const boostStartTimes = [...new Set(userProducts.map((p) => p.boostStartTime))];
        // O(1) lookup map — built once, used per doc
        const userProductByItemId = new Map(userProducts.map((p) => [p.itemId, p]));

        try {
          const snapshots = await Promise.all(
            chunkArray(itemIds, 30).flatMap((idChunk) =>
              chunkArray(boostStartTimes, 30).map((timeChunk) =>
                db.collection('users').doc(userId).collection('boostHistory')
                  .where('itemId', 'in', idChunk)
                  .where('boostStartTime', 'in', timeChunk)
                  .get()
              )
            )
          );
          const allDocs = snapshots.flatMap((s) => s.docs);

          for (const doc of allDocs) {
            if (operationCount >= MAX_BATCH_SIZE) await commitBatch();

            const matchingProduct = userProductByItemId.get(doc.data().itemId);
            if (!matchingProduct) {
              console.warn(`No matching product for boost history doc ${doc.id}`);
              continue;
            }

            batch.update(doc.ref, {
              impressionsDuringBoost: admin.firestore.FieldValue.increment(matchingProduct.count),
              totalImpressionCount: admin.firestore.FieldValue.increment(matchingProduct.count),
              [`demographics.${gender}`]: admin.firestore.FieldValue.increment(matchingProduct.count),
              [`viewerAgeGroups.${ageGroup}`]: admin.firestore.FieldValue.increment(matchingProduct.count),
            });
            operationCount++;
          }
        } catch (error) {
          console.error(`Error updating user boost history for ${userId}:`, error);
        }
      }

      // Process shop products boost history
      for (const [shopId, shopProducts] of Object.entries(boostedShopProducts)) {
        // Update product documents
        for (const {ref, count} of shopProducts) {
          if (operationCount >= MAX_BATCH_SIZE) {
            await commitBatch();
          }
        
          batch.update(ref, {
            impressionCount: admin.firestore.FieldValue.increment(count), // ✅ Use count
            boostedImpressionCount: admin.firestore.FieldValue.increment(count), // ✅ Use count
            lastImpressionTime: now,
            metricsUpdatedAt: now,
          });
          operationCount++;
        }

        // Update boost history
        const itemIds = shopProducts.map((p) => p.itemId);
        const boostStartTimes = [...new Set(shopProducts.map((p) => p.boostStartTime))];
        // O(1) lookup map — built once, used per doc
        const shopProductByItemId = new Map(shopProducts.map((p) => [p.itemId, p]));

        try {
          const snapshots = await Promise.all(
            chunkArray(itemIds, 30).flatMap((idChunk) =>
              chunkArray(boostStartTimes, 30).map((timeChunk) =>
                db.collection('shops').doc(shopId).collection('boostHistory')
                  .where('itemId', 'in', idChunk)
                  .where('boostStartTime', 'in', timeChunk)
                  .get()
              )
            )
          );
          const allDocs = snapshots.flatMap((s) => s.docs);

          for (const doc of allDocs) {
            if (operationCount >= MAX_BATCH_SIZE) await commitBatch();

            const matchingProduct = shopProductByItemId.get(doc.data().itemId);
            if (!matchingProduct) {
              console.warn(`No matching product for boost history doc ${doc.id}`);
              continue;
            }

            batch.update(doc.ref, {
              impressionsDuringBoost: admin.firestore.FieldValue.increment(matchingProduct.count),
              totalImpressionCount: admin.firestore.FieldValue.increment(matchingProduct.count),
              [`demographics.${gender}`]: admin.firestore.FieldValue.increment(matchingProduct.count),
              [`viewerAgeGroups.${ageGroup}`]: admin.firestore.FieldValue.increment(matchingProduct.count),
            });
            operationCount++;
          }
        } catch (error) {
          console.error(`Error updating shop boost history for ${shopId}:`, error);
        }
      }

      // Commit final batch
      await commitBatch();

      console.log(`Successfully processed ${resolved.length} impressions`);
      
      // Return success to Cloud Tasks
      res.status(200).send('OK');
    } catch (error) {
      console.error('Worker error:', error);
      // Return 500 to trigger Cloud Tasks retry (up to 3 attempts as configured in queue)
      res.status(500).send('Error processing task');
    }
  },
);

// Increment totalProductsSold for seller when a new transaction is created
export const incrementTotalProductsSold = onDocumentWritten(
  {
    region: 'europe-west3',
    document: 'users/{buyerId}/transactions/{transactionId}',
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    // Check if the document was created (not updated or deleted)
    if (!before && after) {
      const sellerId = after.sellerId;

      if (!sellerId) {
        console.error('Transaction document missing sellerId');
        return null;
      }

      const sellerRef = admin.firestore().collection('users').doc(sellerId);

      try {
        await sellerRef.update({
          totalProductsSold: admin.firestore.FieldValue.increment(1),
        });
        console.log(`Incremented totalProductsSold for sellerId: ${sellerId}`);
      } catch (error) {
        console.error('Error incrementing totalProductsSold:', error);
        // Optionally, handle the error (e.g., retry logic, alerting)
      }
    }

    return null;
  },
);

export const onShopProductStockChange = onDocumentUpdated(
  {
    document: 'shop_products/{productId}',
    region: 'europe-west3',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const productId = event.params.productId;

    // Check stock change conditions FIRST (before deduplication to avoid unnecessary transactions)
    const mainWentOutOfStock = before.quantity > 0 && after.quantity === 0;

    let colorWentOutOfStock = false;
    const cb = before.colorQuantities ?? {};
    const ca = after.colorQuantities ?? {};

    const allColors = new Set([...Object.keys(cb), ...Object.keys(ca)]);
    for (const color of allColors) {
      const b = cb[color] ?? 0;
      const a = ca[color] ?? 0;
      if (b > 0 && a === 0) {
        colorWentOutOfStock = true;
        break;
      }
    }

    if (!(mainWentOutOfStock || colorWentOutOfStock)) return;

    const shopId = after.shopId;
    if (!shopId) return;

    // Atomic deduplication via Redis (30s window)
    const shouldProcess = await dedup(`dedupe:shop_stock:${productId}`, 30);
    if (!shouldProcess) {
      console.log(`Skipping duplicate shop stock notification for product ${productId}`);
      return;
    }

    // Load shop for name and members
    const shopSnap = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopSnap.exists) return;
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

    if (Object.keys(isReadMap).length === 0) {
      console.log('No members to notify');
      return;
    }

    const productName = after.productName || 'Your product';

    // ✅ Write to shop_notifications (triggers sendShopNotificationOnCreation)
    await admin.firestore().collection('shop_notifications').add({
      type: 'product_out_of_stock_seller_panel',
      shopId,
      shopName: shopData.name || '',
      productId,
      productName,
      isRead: isReadMap,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      message_en: `Product "${productName}" is out of stock!`,
      message_tr: `"${productName}" ürünü stokta kalmadı!`,
      message_ru: `Товар "${productName}" закончился!`,
    });

    console.log(`✅ Shop notification created for ${Object.keys(isReadMap).length} members (product ${productId})`);
  },
);

export const onGeneralProductStockChange = onDocumentUpdated(
  {
    document: 'products/{productId}',
    region: 'europe-west3',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const productId = event.params.productId;

    // Check stock change conditions FIRST (before deduplication to avoid unnecessary transactions)
    const mainWentOutOfStock = before.quantity > 0 && after.quantity === 0;

    let colorWentOutOfStock = false;
    const cb = before.colorQuantities ?? {};
    const ca = after.colorQuantities ?? {};

    const allColors = new Set([...Object.keys(cb), ...Object.keys(ca)]);
    for (const color of allColors) {
      const b = cb[color] ?? 0;
      const a = ca[color] ?? 0;
      if (b > 0 && a === 0) {
        colorWentOutOfStock = true;
        break;
      }
    }

    if (!(mainWentOutOfStock || colorWentOutOfStock)) return;

    // Who owns this product?
    const sellerId = after.userId;
    if (!sellerId) return;

    // Atomic deduplication via Redis (30s window)
    const shouldProcess = await dedup(`dedupe:general_stock:${productId}`, 30);
    if (!shouldProcess) {
      console.log(`Skipping duplicate general stock notification for product ${productId}`);
      return;
    }

    // Prepare messages
    const name = after.productName || 'Your product';
    const en = `Your product "${name}" is out of stock.`;
    const tr = `Ürününüz "${name}" stokta kalmadı.`;
    const ru = `Ваш продукт "${name}" распродан.`;

    // Write single notification
    await admin.firestore().collection('users').doc(sellerId).collection('notifications').add({
      type: 'product_out_of_stock',
      productId,
      productName: name,
      message_en: en,
      message_tr: tr,
      message_ru: ru,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false,
    });

    console.log(`General stock notification sent to user ${sellerId} for product ${productId}`);
  },
);

export const updateShipmentStatus = onCall(
  {region: 'europe-west3'}, // Specify the desired region
  async (request) => {
    try {
      // 1. Authentication Check
      const {auth} = request;
      if (!auth) {
        console.error('Unauthenticated request.');
        throw new HttpsError('unauthenticated', 'User must be authenticated to update shipment status.');
      }

      const sellerId = auth.uid;

      // 2. Input Validation
      const {transactionId, newStatus} = request.data;

      if (!transactionId || typeof transactionId !== 'string') {
        console.error('Invalid or missing transactionId.');
        throw new HttpsError('invalid-argument', 'The function must be called with a valid transactionId.');
      }

      const validStatuses = ['Pending', 'Shipped', 'Delivered', 'Canceled'];
      if (!newStatus || typeof newStatus !== 'string' || !validStatuses.includes(newStatus)) {
        console.error('Invalid newStatus.');
        throw new HttpsError('invalid-argument', `Invalid newStatus. Must be one of: ${validStatuses.join(', ')}.`);
      }

      const db = admin.firestore();

      // 3. Fetch the Seller's Transaction Document
      const sellerTransactionRef = db.collection('users').doc(sellerId).collection('transactions').doc(transactionId);

      const sellerTransactionDoc = await sellerTransactionRef.get();

      if (!sellerTransactionDoc.exists) {
        throw new HttpsError('not-found', 'The transaction does not exist.');
      }

      const sellerTransactionData = sellerTransactionDoc.data();

      // Verify that the authenticated user is indeed the seller
      if (sellerTransactionData.sellerId !== sellerId) {
        throw new HttpsError('permission-denied', 'You do not have permission to update this transaction.');
      }

      const buyerId = sellerTransactionData.buyerId;

      if (!buyerId) {
        console.error('Buyer ID is missing in the transaction document.');
        throw new HttpsError('internal', 'Buyer information is missing in the transaction.');
      }

      // 4. Firestore Transaction to Update Both Documents Atomically
      await db.runTransaction(async (transaction) => {
        // References to both seller's and buyer's transaction documents
        const buyerTransactionRef = db.collection('users').doc(buyerId).collection('transactions').doc(transactionId);

        const buyerTransactionDoc = await transaction.get(buyerTransactionRef);

        if (!buyerTransactionDoc.exists) {
          throw new HttpsError('not-found', 'The buyer\'s transaction does not exist.');
        }

        // Update shipmentStatus in seller's transaction
        transaction.update(sellerTransactionRef, {
          shipmentStatus: newStatus,
          shipmentUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update shipmentStatus in buyer's transaction
        transaction.update(buyerTransactionRef, {
          shipmentStatus: newStatus,
          shipmentUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Create a notification for the buyer
        const notificationRef = db.collection('users').doc(buyerId).collection('notifications').doc();

        const notificationData = {
          userId: buyerId,
          type: 'shipment_update',
          message_en: `Your ${sellerTransactionData.productName} order is ${newStatus}`,
          message_tr: `${sellerTransactionData.productName} ürün siparişiniz ${newStatus}`,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          productId: sellerTransactionData.productId,
          transactionId: transactionId,
        };

        transaction.set(notificationRef, notificationData);
      });

      return {success: true, message: 'Shipment status updated successfully.'};
    } catch (error) {
      console.error('Error updating shipment status:', error);

      if (error instanceof HttpsError) {
        throw error; // Re-throw known HttpsErrors
      } else {
        throw new HttpsError('internal', 'An unexpected error occurred while updating the shipment status.');
      }
    }
  },
);

// New Function: Delete User Account (with subcollections)
export const deleteUserAccount = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 540, // Max timeout for large deletions
    memory: '512MiB', // Increased memory for recursive operations
  },
  async (request) => {
    const {auth, data} = request;

    // === 1) Authentication check ===
    if (!auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const callerUid = auth.uid;

    // === 2) Determine target UID (admin or self-delete) ===
    let targetUid;
    let isAdminDelete = false;

    if (data.uid) {
      // — Admin path —
      isAdminDelete = true;

      if (typeof data.uid !== 'string' || !data.uid.trim()) {
        throw new HttpsError(
          'invalid-argument',
          'You must provide a valid target uid.',
        );
      }

      // Check admin status
      const adminDoc = await admin
        .firestore()
        .collection('users')
        .doc(callerUid)
        .get();

      if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
        throw new HttpsError(
          'permission-denied',
          'Only admins can delete other users.',
        );
      }

      targetUid = data.uid.trim();

      // Prevent admin from deleting themselves via admin path
      if (targetUid === callerUid) {
        throw new HttpsError(
          'invalid-argument',
          'Use self-delete to remove your own account.',
        );
      }
    } else {
      // — Self-delete path —
      if (typeof data.email !== 'string' || !data.email.trim()) {
        throw new HttpsError(
          'invalid-argument',
          'You must provide your email to confirm deletion.',
        );
      }

      // Verify email matches
      const userRecord = await admin.auth().getUser(callerUid);
      if (userRecord.email?.toLowerCase() !== data.email.trim().toLowerCase()) {
        throw new HttpsError(
          'permission-denied',
          'Provided email does not match your account.',
        );
      }

      targetUid = callerUid;
    }

    // === 3) Verify target user exists ===
    try {
      await admin.auth().getUser(targetUid);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        throw new HttpsError(
          'not-found',
          'Target user account does not exist.',
        );
      }
      throw new HttpsError('internal', 'Failed to verify user account.');
    }

    const userDocRef = admin.firestore().collection('users').doc(targetUid);

    // === 3.5) Remove user from all shops/restaurants they belong to ===
    try {
      const userSnap = await userDocRef.get();
      if (userSnap.exists) {
        const userData = userSnap.data();
        const roleToField = {
          'co-owner': 'coOwners',
          'editor': 'editors',
          'viewer': 'viewers',
        };

        const removalPromises = [];

        // Remove from shops
        const memberOfShops = userData.memberOfShops ?? {};
        for (const [shopId, role] of Object.entries(memberOfShops)) {
          const field = roleToField[role];
          if (field) {
            removalPromises.push(
              admin.firestore().collection('shops').doc(shopId).update({
                [field]: admin.firestore.FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from shop ${shopId}:`, err.message);
              }),
            );
          }
        }

        // Remove from restaurants
        const memberOfRestaurants = userData.memberOfRestaurants ?? {};
        for (const [restId, role] of Object.entries(memberOfRestaurants)) {
          const field = roleToField[role];
          if (field) {
            removalPromises.push(
              admin.firestore().collection('restaurants').doc(restId).update({
                [field]: admin.firestore.FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from restaurant ${restId}:`, err.message);
              }),
            );
          }
        }

        // Cancel pending invitations sent TO this user
        const invCollections = ['shopInvitations', 'restaurantInvitations'];
        const invQueryResults = await Promise.all(
          invCollections.map((coll) =>
            admin.firestore()
              .collection(coll)
              .where('userId', '==', targetUid)
              .where('status', '==', 'pending')
              .get(),
          ),
        );
        for (const snapshot of invQueryResults) {
          for (const doc of snapshot.docs) {
            removalPromises.push(
              doc.ref.update({ status: 'cancelled' }).catch((err) => {
                console.warn(`Could not cancel invitation ${doc.id}:`, err.message);
              }),
            );
          }
        }

        if (removalPromises.length > 0) {
          await Promise.all(removalPromises);
          console.log(`✓ Removed user ${targetUid} from ${removalPromises.length} shop/restaurant/invitation references`);
        }
      }
    } catch (err) {
      // Log but don't block deletion — the user doc cleanup is best-effort
      console.error('Warning: Failed to clean up shop/restaurant memberships:', err);
    }

    // === 4) Delete Firestore data with recursiveDelete ===
    // This automatically deletes all subcollections
    try {
      const docSnapshot = await userDocRef.get();

      if (docSnapshot.exists || await hasSubcollections(userDocRef)) {
        await admin.firestore().recursiveDelete(userDocRef);// ← Remove the options object
        console.log(
          `✓ Deleted Firestore data (including subcollections) for uid=${targetUid}`,
        );
      } else {
        console.log(`No Firestore data found for uid=${targetUid}`);
      }
    } catch (err) {
      console.error('Error deleting Firestore data:', err);
      throw new HttpsError(
        'internal',
        'Failed to delete user data from Firestore.',
      );
    }
    // === 5) Delete Auth account ===
    try {
      await admin.auth().deleteUser(targetUid);
      console.log(`✓ Deleted Auth record for uid=${targetUid}`);
    } catch (err) {
      // If auth deletion fails after Firestore deletion, log critical error
      console.error('CRITICAL: Auth deletion failed after Firestore deletion:', err);

      if (err.code === 'auth/user-not-found') {
        // User was already deleted - not critical
        console.log('Auth user was already deleted');
      } else {
        throw new HttpsError(
          'internal',
          'Failed to delete authentication record.',
        );
      }
    }

    // === 6) Return success ===
    return {
      success: true,
      message: isAdminDelete ? `User account ${targetUid} has been deleted.` : 'Your account has been deleted.',
      deletedUid: targetUid,
    };
  },
);

async function hasSubcollections(docRef) {
  const collections = await docRef.listCollections();
  return collections.length > 0;
}


export const hasUserBoughtProduct = onCall({region: 'europe-west3'}, async (request) => {
  // 1. Authentication Check
  const {auth, data} = request;
  if (!auth) {
    console.error('Unauthenticated request to hasUserBoughtProduct.');
    throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
  }

  // 2. Input Validation
  const {userId, productId} = data;
  if (!userId || typeof userId !== 'string' || !productId || typeof productId !== 'string') {
    console.error('Invalid or missing userId/productId in request data.');
    throw new HttpsError('invalid-argument', 'The function must be called with valid userId and productId.');
  }

  // 3. Query Firestore to check purchase
  try {
    const transactionsRef = admin.firestore().collection('transactions');
    const purchaseQuery = await transactionsRef
      .where('buyerId', '==', userId)
      .where('productId', '==', productId)
      .limit(1)
      .get();

    const hasPurchased = !purchaseQuery.empty;

    return {hasPurchased};
  } catch (error) {
    console.error('Error checking purchase status:', error);
    throw new HttpsError('internal', 'Unable to check purchase status.');
  }
});

// -----------------------------------------
// Create a new QR auth session (Web calls this)
// -----------------------------------------
export const createQrAuthSession = onCall(
  {
    region: 'europe-west3',
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
    cors: {
      origin: [
        'https://nar24.com', // Production origin(s)
        'https://www.nar24.com', // Production origin(s)
        'https://www.nar24.com/en',
      ],
      methods: ['POST'], // Callable functions are typically POST
      allowedHeaders: [
        'Content-Type',
        'Authorization',
        // add any custom headers you need
      ],
      // credentials: true, // If you need to send cookies/credentials
    },
  },
  async (request) => {
    try {
       // Rate limit: max 10 sessions per 10 minutes per IP
       const callerIp = request.rawRequest?.ip || 'unknown';
       const ipHash = callerIp.replace(/[^a-zA-Z0-9]/g, '_');
       const db = admin.firestore();

       const withinLimit = await checkRateLimit(`qr_session:${ipHash}`, 10, 600);
       if (!withinLimit) {
         throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
       }

      const sessionRef = db.collection('qrSessions').doc();
      const sessionId = sessionRef.id;

      await sessionRef.set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        used: false,
        customToken: null,
        userId: null,
        expiresAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 5 * 60 * 1000), // e.g., 5-minute expiry
        ),
      });

      return {sessionId};
    } catch (error) {
      console.error('Error creating QR auth session:', error);
      throw new HttpsError('internal', 'Unable to create QR auth session');
    }
  },
);

// ------------------------------------------------------------
// Complete a QR auth session (Phone calls this, must be logged in)
// ------------------------------------------------------------
export const confirmQrAuthSession = onCall(
  {
    region: 'europe-west3',
    cors: {
      origin: ['https://nar24.com', 'https://www.nar24.com', 'https://www.nar24.com/en'],
      methods: ['POST'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    },
  },
  async (request) => {
    const {auth, data} = request;
    if (!auth) {
      console.error('Unauthenticated request to confirmQrAuthSession.');
      throw new HttpsError('unauthenticated', 'Must be logged in to confirm a QR session.');
    }

    const {sessionId} = data;
    if (!sessionId || typeof sessionId !== 'string') {
      console.error('Invalid or missing sessionId in request data.');
      throw new HttpsError('invalid-argument', 'Must provide a valid sessionId.');
    }

    try {
      const db = admin.firestore();
      const sessionRef = db.collection('qrSessions').doc(sessionId);
      const sessionSnap = await sessionRef.get();

      if (!sessionSnap.exists) {
        console.error(`No qrSession found for ID: ${sessionId}`);
        throw new HttpsError('not-found', 'Session does not exist');
      }

      const sessionData = sessionSnap.data();
      if (sessionData.used === true) {
        console.error(`Session ${sessionId} is already used.`);
        throw new HttpsError('failed-precondition', 'Session already used');
      }
      if (sessionData.expiresAt && sessionData.expiresAt.toMillis() < Date.now()) {
        console.error(`Session ${sessionId} is expired.`);
        throw new HttpsError('deadline-exceeded', 'Session expired');
      }

      // Generate a custom token for the phone user's UID
      const phoneUid = auth.uid;
      console.log(`Creating custom token for phone user: ${phoneUid}`);
      const customToken = await admin.auth().createCustomToken(phoneUid);

      // Mark the session as used, store the customToken & userId
      await sessionRef.update({
        used: true,
        customToken,
        userId: phoneUid,
      });

      return {success: true};
    } catch (error) {
      console.error('Error confirming QR auth session:', error);
      if (error instanceof HttpsError) {
        throw error;
      } else {
        throw new HttpsError('internal', 'An unexpected error occurred while confirming QR session.');
      }
    }
  },
);

export const createQrAuthSessionWebToPhone = onCall(
  {
    region: 'europe-west3',
    cors: {
      origin: ['https://nar24.com', 'https://www.nar24.com', 'https://www.nar24.com/en'],
      methods: ['POST'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    },
  },
  async (request) => {
    const {auth} = request;
    if (!auth) {
      console.error('Unauthenticated request createQrAuthSessionWebToPhone.');
      throw new HttpsError('unauthenticated', 'Must be logged in on the web to create this QR session.');
    }

    try {
      const db = admin.firestore();
      const sessionRef = db.collection('qrSessions').doc();
      const sessionId = sessionRef.id;

      // 1) Generate a custom token for the WEB user's UID
      const webUserUid = auth.uid;
      console.log(`Creating custom token for web user: ${webUserUid}`);
      const customToken = await admin.auth().createCustomToken(webUserUid);

      // 2) Write doc with the custom token
      await sessionRef.set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        used: false,
        customToken,
        userId: webUserUid, // optional: store the userId
        expiresAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 5 * 60 * 1000), // 5 min expiry
        ),
      });

      return {sessionId};
    } catch (error) {
      console.error('Error creating web->phone QR session:', error);
      throw new HttpsError('internal', 'Unable to create QR session for web->phone');
    }
  },
);

export const onBannerUpload = onObjectFinalized(
  {region: 'europe-west2'},
  async (event) => {
    const object = event.data;
    if (!object) return;

    const filePath = object.name;
    if (!filePath || !filePath.startsWith('market_top_ads_banners/')) {
      return;
    }

    const bucketName = object.bucket;
    const docId = path.basename(filePath); // e.g. "1623456789012_my.jpg"

    // 1) Build the public URL
    const imageUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
      `${encodeURIComponent(filePath)}?alt=media`;

    // 2) Download to a temp file
    const tmpFile = path.join(os.tmpdir(), docId);
    await admin
      .storage()
      .bucket(bucketName)
      .file(filePath)
      .download({destination: tmpFile});

    // 3) Compute dominant edge color
    let dominantColor;
    try {
      dominantColor = await getDominantColor(tmpFile);
    } finally {
      fs.unlinkSync(tmpFile);
    }

    // 4) Write (or overwrite) the Firestore doc in one go
    await admin
      .firestore()
      .collection('market_top_ads_banners')
      .doc(docId)
      .set({
        imageUrl,
        storagePath: filePath,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        dominantColor,
        isActive: true,
      });
  },
);

export const getSharedFavorites = onRequest({region: 'europe-west3'}, async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  if (req.method !== 'GET') {
    res.status(405).json({error: 'Method not allowed'});
    return;
  }

  try {
    const shareId = req.path.split('/').pop(); // Get shareId from path

    if (!shareId) {
      res.status(400).json({error: 'Share ID is required'});
      return;
    }

    // Get shared favorites document
    const doc = await admin.firestore().collection('shared_favorites').doc(shareId).get();

    if (!doc.exists) {
      res.status(404).json({error: 'Shared favorites not found'});
      return;
    }

    const data = doc.data();

    // Check if expired
    if (data.expiresAt && data.expiresAt.toDate() < new Date()) {
      res.status(410).json({error: 'Shared favorites have expired'});
      return;
    }

    // Return public data (don't expose sensitive information)
    res.json({
      shareTitle: data.shareTitle,
      shareDescription: data.shareDescription,
      senderName: data.senderName,
      basketName: data.basketName,
      itemCount: data.itemCount,
      languageCode: data.languageCode,
      appName: data.appName || 'Nar24',
      appIcon: data.appIcon || 'https://nar24.app/assets/images/naricon.png',
      createdAt: data.createdAt,
    });
  } catch (error) {
    console.error('Error getting shared favorites:', error);
    res.status(500).json({error: 'Internal server error'});
  }
});

// Main redirect handler for shared favorites URLs
export const sharedFavoritesRedirect = onRequest({region: 'europe-west3'}, async (req, res) => {
  try {
    const shareId = req.path.split('/').pop();

    if (!shareId) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com');
      return;
    }

    // Get share data for meta tags
    const doc = await admin.firestore().collection('shared_favorites').doc(shareId).get();

    if (!doc.exists) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com');
      return;
    }

    const data = doc.data();

    // Check if expired
    if (data.expiresAt && data.expiresAt.toDate() < new Date()) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com');
      return;
    }

    // Create rich link preview exactly like Trendyol
    const shareTitle = data.shareTitle || 'Nar24 - Shared Favorites';
    const shareDescription = data.shareDescription || 'Check out these amazing products!';
    const shareUrl = `https://app.nar24.com/shared-favorites/${shareId}`;
    const appIcon = data.appIcon || 'https://app.nar24.com/assets/images/naricon.png?v=2';

    // Generate dynamic HTML with rich Open Graph meta tags
    const html = `
<!DOCTYPE html>
<html lang="${data.languageCode || 'en'}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${shareTitle}</title>
    
    <!-- ✅ RICH LINK PREVIEW - Open Graph meta tags (WhatsApp optimized) -->
    <meta property="og:title" content="${shareTitle}">
    <meta property="og:description" content="${shareDescription}">
    <meta property="og:image" content="${appIcon}">
    <meta property="og:image:url" content="${appIcon}">
    <meta property="og:image:secure_url" content="${appIcon}">
    <meta property="og:image:width" content="120">
    <meta property="og:image:height" content="120">
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:alt" content="Nar24 App Icon">
    <meta property="og:url" content="${shareUrl}">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Nar24">
    <meta property="og:locale" content="${data.languageCode || 'en'}_${(data.languageCode || 'en').toUpperCase()}">
    
    <!-- ✅ Additional meta tags for better compatibility -->
    <meta name="image" content="${appIcon}">
    <meta name="thumbnail" content="${appIcon}">
    
    <!-- ✅ Twitter Card meta tags for Twitter sharing -->
    <meta name="twitter:card" content="summary">
    <meta name="twitter:title" content="${shareTitle}">
    <meta name="twitter:description" content="${shareDescription}">
    <meta name="twitter:image" content="${appIcon}">
    <meta name="twitter:image:src" content="${appIcon}">
    <meta name="twitter:site" content="@nar24app">
    
    <!-- ✅ WhatsApp specific meta tags -->
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:alt" content="Nar24 App Icon">
    
    <!-- ✅ Additional compatibility meta tags -->
    <meta name="image" content="${appIcon}">
    <meta name="thumbnail" content="${appIcon}">
    <meta property="article:author" content="Nar24">
    
    <!-- ✅ Telegram specific meta tags -->
    <meta name="telegram:channel" content="@nar24app">
    
    <!-- App store meta tags -->
    <meta name="apple-itunes-app" content="app-id=YOUR_IOS_APP_ID">
    <meta name="google-play-app" content="app-id=com.cts.emlak">
    
    <!-- ✅ Favicon -->
    <link rel="icon" type="image/png" href="${appIcon}">
    <link rel="apple-touch-icon" href="${appIcon}">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #00A86B 0%, #00C851 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        
        .container {
            text-align: center;
            max-width: 400px;
            padding: 40px 20px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.2);
        }
        
        .app-icon {
            width: 80px;
            height: 80px;
            border-radius: 18px;
            margin: 0 auto 20px;
            display: block;
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.3);
        }
        
        .app-name {
            font-size: 28px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .share-title {
            font-size: 18px;
            margin-bottom: 8px;
            opacity: 0.9;
        }
        
        .share-description {
            font-size: 14px;
            margin-bottom: 30px;
            opacity: 0.8;
        }
        
        .share-url {
            font-size: 12px;
            margin-bottom: 20px;
            opacity: 0.7;
            word-break: break-all;
            background: rgba(255, 255, 255, 0.1);
            padding: 8px 12px;
            border-radius: 8px;
        }
        
        .download-buttons {
            display: flex;
            flex-direction: column;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .download-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 12px 24px;
            background: rgba(255, 255, 255, 0.9);
            color: #333;
            text-decoration: none;
            border-radius: 12px;
            font-weight: 600;
            transition: all 0.3s ease;
            gap: 10px;
        }
        
        .download-btn:hover {
            background: white;
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.2);
        }
        
        .open-app-btn {
            background: #FF6B35;
            color: white;
            font-size: 16px;
            padding: 15px 30px;
        }
        
        .open-app-btn:hover {
            background: #E55A2B;
        }
        
        .footer {
            margin-top: 20px;
            font-size: 12px;
            opacity: 0.7;
        }
        
        @media (max-width: 480px) {
            .container {
                margin: 20px;
                padding: 30px 15px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="${appIcon}" alt="Nar24" class="app-icon" 
             onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22
              width=%2280%22 height=%2280%22 viewBox=%220 0 80 80%22%3E%3Crect width=%2280%22
               height=%2280%22 rx=%2218%22 fill=%22%2300A86B%22/%3E%3Ctext x=%2240%22 y=%2250%22
                text-anchor=%22middle%22 dy=%22.3em%22 font-family=%22Arial%22 font-size=%2240%22
                 fill=%22white%22%3EN%3C/text%3E%3C/svg%3E'">
        
        <h1 class="app-name">Nar24</h1>
        <h2 class="share-title">${shareTitle}</h2>
        <p class="share-description">${shareDescription}</p>
        
        <!-- ✅ Show the share URL like in Trendyol example -->
        <div class="share-url">🔗 ${shareUrl}</div>
        
        <div class="download-buttons">
            <a href="#" class="download-btn open-app-btn" onclick="openApp()">
                📱 Open in Nar24 App
            </a>
            <a href="https://play.google.com/store/apps/details?id=com.cts.emlak" class="download-btn" target="_blank">
                📲 Download for Android
            </a>
            <a href="https://apps.apple.com/app/id6752034508" class="download-btn" target="_blank">
                🍎 Download for iOS
            </a>
        </div>
        
        <div class="footer">
            <p>Powered by Nar24</p>
        </div>
    </div>

    <script>
        function openApp() {
            const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
            const isAndroid = /Android/.test(navigator.userAgent);
            
            if (isIOS) {
                // Try to open iOS app
                window.location.href = 'nar24app://shared-favorites/${shareId}';
                
                // Fallback to App Store after a delay
                setTimeout(() => {
                    window.location.href = 'https://apps.apple.com/app/id6752034508';
                }, 2000);
            } else if (isAndroid) {
                // Try to open Android app
                window.location.href = 'nar24app://shared-favorites/${shareId}';
                
                // Fallback to Play Store after a delay
                setTimeout(() => {
                    window.location.href = 'https://play.google.com/store/apps/details?id=com.cts.emlak';
                }, 2000);
            } else {
                // Desktop - show message
                alert('Please download the Nar24 app on your mobile device to view shared favorites.');
            }
        }
        
        // Auto-redirect attempt for mobile devices
        if (/Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)) {
            setTimeout(() => {
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = 'nar24app://shared-favorites/${shareId}';
                document.body.appendChild(iframe);
                
                setTimeout(() => {
                    if (iframe.parentNode) {
                        document.body.removeChild(iframe);
                    }
                }, 1000);
            }, 1000);
        }
    </script>
</body>
</html>`;

    res.set('Content-Type', 'text/html');
    res.send(html);
  } catch (error) {
    console.error('Error in shared favorites redirect:', error);
    res.redirect('https://app.nar24.com');
  }
});

// ✅ FIXED: Updated getShareImage function with consistent domain
export const getShareImage = onRequest({region: 'europe-west3'}, async (req, res) => {
  try {
    const shareId = req.query.shareId;

    if (!shareId) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com/assets/images/naricon.png');
      return;
    }

    // Get share data
    const doc = await admin.firestore().collection('shared_favorites').doc(shareId).get();

    if (!doc.exists) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com/assets/images/naricon.png');
      return;
    }

    const data = doc.data();
    // ✅ FIXED: Use app.nar24.com consistently
    const appIcon = data.appIcon || 'https://app.nar24.com/assets/images/naricon.png';

    // Redirect to the app icon (or you could generate a custom image here)
    res.redirect(appIcon);
  } catch (error) {
    console.error('Error serving share image:', error);
    // ✅ FIXED: Use app.nar24.com consistently
    res.redirect('https://app.nar24.com/assets/images/naricon.png');
  }
});

export const productShareRedirect = onRequest({region: 'europe-west3'}, async (req, res) => {
  try {
    // ✅ DEBUG: Log the incoming request
    console.log('🔍 Product share request path:', req.path);
    console.log('🔍 Product share request query:', req.query);
    console.log('🔍 Product share request method:', req.method);
    console.log('🔍 Product share request headers:', req.headers);

    // ✅ IMPROVED: Extract product ID from path more reliably
    const pathSegments = req.path.split('/').filter((segment) => segment.length > 0);
    console.log('🔍 Path segments:', pathSegments);

    // Expected format: /products/PRODUCT_ID
    let productId = null;

    if (pathSegments.length >= 2 && pathSegments[0] === 'products') {
      productId = pathSegments[1];
    } else if (pathSegments.length >= 1) {
      // Fallback: maybe just the product ID
      productId = pathSegments[0];
    }

    console.log('🔍 Extracted product ID:', productId);

    if (!productId) {
      console.log('❌ No product ID found, redirecting to app');
      res.redirect('https://app.nar24.com');
      return;
    }

    const collection = req.query.collection || 'products';
    console.log('🔍 Using collection:', collection);

    // Get product data from Firestore
    const doc = await admin.firestore().collection(collection).doc(productId).get();

    if (!doc.exists) {
      console.log('❌ Product not found in Firestore, redirecting to app');
      res.redirect('https://app.nar24.com');
      return;
    }

    const product = doc.data();
    console.log('✅ Product found:', product.productName);

    // ✅ Build product information
    const productName = product.productName || 'Product';
    const brandModel = product.brandModel || '';
    const fullProductName = brandModel ? `${brandModel} ${productName}` : productName;

    // ✅ Use the first product image
    const productImage = product.imageUrls?.[0] || 'https://app.nar24.com/assets/images/naricon.png';
    const shareUrl = `https://app.nar24.com/products/${productId}?collection=${collection}`;

    console.log('✅ Generated share URL:', shareUrl);
    console.log('✅ Product image:', productImage);

    const html = `
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${fullProductName}</title>
    
    <!-- ✅ Open Graph meta tags for rich link previews -->
    <meta property="og:title" content="${fullProductName}">
    <meta property="og:description" content="Nar24">
    <meta property="og:image" content="${productImage}">
    <meta property="og:image:url" content="${productImage}">
    <meta property="og:image:secure_url" content="${productImage}">
    <meta property="og:image:width" content="120">
    <meta property="og:image:height" content="120">
    <meta property="og:image:type" content="image/jpeg">
    <meta property="og:image:alt" content="${fullProductName}">
    <meta property="og:url" content="${shareUrl}">
    <meta property="og:type" content="product">
    <meta property="og:site_name" content="Nar24">
    <meta property="og:locale" content="tr_TR">
    
    <!-- ✅ Twitter Card meta tags -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${fullProductName}">
    <meta name="twitter:description" content="Nar24">
    <meta name="twitter:image" content="${productImage}">
    <meta name="twitter:image:src" content="${productImage}">
    <meta name="twitter:site" content="@nar24app">
    
    <!-- ✅ WhatsApp specific meta tags -->
    <meta property="og:image:type" content="image/jpeg">
    <meta property="og:image:alt" content="${fullProductName}">
    
    <!-- ✅ Additional compatibility meta tags -->
    <meta name="image" content="${productImage}">
    <meta name="thumbnail" content="${productImage}">
    
    <!-- ✅ Favicon -->
    <link rel="icon" type="image/png" href="https://app.nar24.com/assets/images/naricon.png">
    <link rel="apple-touch-icon" href="https://app.nar24.com/assets/images/naricon.png">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #00A86B 0%, #00C851 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            margin: 0;
            padding: 20px;
        }
        
        .container {
            text-align: center;
            max-width: 400px;
            padding: 40px 20px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.2);
        }
        
        .product-image {
            width: 120px;
            height: 120px;
            border-radius: 12px;
            margin: 0 auto 20px;
            display: block;
            object-fit: cover;
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.3);
        }
        
        .product-name {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 10px;
            line-height: 1.3;
        }
        
        .app-name {
            font-size: 16px;
            margin-bottom: 20px;
            opacity: 0.9;
        }
        
        .share-url {
            font-size: 12px;
            margin-bottom: 20px;
            opacity: 0.7;
            word-break: break-all;
            background: rgba(255, 255, 255, 0.1);
            padding: 8px 12px;
            border-radius: 8px;
        }
        
        .download-buttons {
            display: flex;
            flex-direction: column;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .download-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 12px 24px;
            background: rgba(255, 255, 255, 0.9);
            color: #333;
            text-decoration: none;
            border-radius: 12px;
            font-weight: 600;
            transition: all 0.3s ease;
            gap: 10px;
        }
        
        .download-btn:hover {
            background: white;
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.2);
        }
        
        .open-app-btn {
            background: #FF6B35;
            color: white;
            font-size: 16px;
            padding: 15px 30px;
        }
        
        .open-app-btn:hover {
            background: #E55A2B;
        }
        
        .footer {
            margin-top: 20px;
            font-size: 12px;
            opacity: 0.7;
        }
        
        @media (max-width: 480px) {
            .container {
                margin: 20px;
                padding: 30px 15px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="${productImage}" alt="${fullProductName}" class="product-image" 
             onerror="this.src='https://app.nar24.com/assets/images/naricon.png'">
        
        <h1 class="product-name">${fullProductName}</h1>
        <p class="app-name">Nar24'te keşfet</p>
        
        <div class="share-url">🔗 ${shareUrl}</div>
        
        <div class="download-buttons">
            <a href="#" class="download-btn open-app-btn" onclick="openApp()">
                📱 Nar24 Uygulamasında Aç
            </a>
            <a href="https://play.google.com/store/apps/details?id=com.cts.emlak" class="download-btn" target="_blank">
                📲 Android İçin İndir
            </a>
            <a href="https://apps.apple.com/app/id6752034508" class="download-btn" target="_blank">
                🍎 iOS İçin İndir
            </a>
        </div>
        
        <div class="footer">
            <p>Nar24 ile güçlendirilmiştir</p>
        </div>
    </div>

    <script>
        function openApp() {
            const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
            const isAndroid = /Android/.test(navigator.userAgent);
            
            if (isIOS) {
                window.location.href = 'nar24app://product/${productId}?collection=${collection}';
                setTimeout(() => {
                    window.location.href = 'https://apps.apple.com/app/id6752034508';
                }, 2000);
            } else if (isAndroid) {
                window.location.href = 'nar24app://product/${productId}?collection=${collection}';
                setTimeout(() => {
                    window.location.href = 'https://play.google.com/store/apps/details?id=com.cts.emlak';
                }, 2000);
            } else {
                alert('Bu ürünü görüntülemek için lütfen mobil cihazınızda Nar24 uygulamasını indirin.');
            }
        }
        
        // Auto-redirect attempt for mobile devices
        if (/Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)) {
            setTimeout(() => {
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = 'nar24app://product/${productId}?collection=${collection}';
                document.body.appendChild(iframe);
                
                setTimeout(() => {
                    if (iframe.parentNode) {
                        document.body.removeChild(iframe);
                    }
                }, 1000);
            }, 1000);
        }
    </script>
</body>
</html>`;

    res.set('Content-Type', 'text/html');
    res.set('Cache-Control', 'public, max-age=300'); // Cache for 5 minutes
    res.send(html);
  } catch (error) {
    console.error('❌ Error in product share redirect:', error);
    res.redirect('https://app.nar24.com');
  }
});

export const checkOrderCompletion = onDocumentUpdated({
  document: 'orders/{orderId}/items/{itemId}',
  region: 'europe-west3',
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Only run if arrivedAt was just set (not on other updates)
  if (!before.arrivedAt && after.arrivedAt) {
    const orderId = event.params.orderId;
    const db = admin.firestore();

    try {
      // First, get the order to check its current status
      const orderDoc = await db
        .collection('orders')
        .doc(orderId)
        .get();

      const orderData = orderDoc.data();

      // IMPORTANT: Don't update if order is already delivered (partial or complete)
      if (orderData && orderData.distributionStatus === 'delivered') {
        console.log(`Order ${orderId} is already delivered (partial delivery), skipping status update`);

        // Just update that all items are gathered without changing distribution status
        const itemsSnapshot = await db
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .where('gatheringStatus', '!=', 'at_warehouse')
          .limit(1)
          .get();

        if (itemsSnapshot.empty) {
          await db
            .collection('orders')
            .doc(orderId)
            .update({
              allItemsGathered: true,
              // DO NOT update distributionStatus for delivered orders
              readyForDistributionAt: FieldValue.serverTimestamp(),
            });
          console.log(`Order ${orderId} has all items gathered but keeping delivered status (partial delivery)`);
        }
        return;
      }

      // For non-delivered orders, check if all items are at warehouse
      const itemsSnapshot = await db
        .collection('orders')
        .doc(orderId)
        .collection('items')
        .where('gatheringStatus', '!=', 'at_warehouse')
        .limit(1)
        .get();

      // If query returns empty, ALL items are at warehouse
      if (itemsSnapshot.empty) {
        await db
          .collection('orders')
          .doc(orderId)
          .update({
            allItemsGathered: true,
            distributionStatus: 'ready',
            readyForDistributionAt: FieldValue.serverTimestamp(),
          });

        console.log(`Order ${orderId} marked as ready for distribution`);
      }
    } catch (error) {
      console.error(`Error checking order ${orderId} completion:`, error);
      throw error;
    }
  }
});

export {deleteCampaign, processCampaignDeletion, getCampaignDeletionStatus, cleanupCampaignDeletionQueue} from './4-campaigns/index.js';
export {submitReview, updateProductMetrics, updateShopProductMetrics, updateShopMetrics, updateUserSellerMetrics, sendReviewNotifications} from './5-reviews/index.js';
export {rebuildRelatedProducts} from './6-related_products/index.js';
export {rollupClickCounts} from './7-click-analytics/index.js';
export {validateCartCheckout, updateCartCache} from './8-cart-validation/index.js';
export {calculateCartTotals} from './9-cart-total-price/index.js';
export {clampNegativeMetrics} from './10-cart&favorite-metrics/index.js';
export {
  batchUserActivity,
  cleanupOldActivityEvents,
  computeUserPreferences,
  processActivityDLQ,
} from './11-user-activity/index.js';
export {computeTrendingProductsScheduled, cleanupTrendingHistory} from './12-trending-products/index.js';
export {updatePersonalizedFeeds, processPersonalizedFeedBatch} from './13-personalized-feed/index.js';
export {adminToggleProductArchiveStatus, approveArchivedProductEdit, approveProductApplication, rejectProductApplication, setCargoGuyClaim} from './14-admin-actions/index.js';
export {translateText, translateBatch} from './15-openai-translation/index.js';
export {processQRCodeGeneration, verifyQRCode, markQRScanned, retryQRGeneration} from './16-qr-for-orders/index.js';
export {
  grantUserCoupon,
  grantFreeShipping,
  getUserCouponsAndBenefits,
  revokeCoupon,
  revokeBenefit,
} from './17-coupons/index.js';
export {alertOnPaymentIssue, detectPaymentAnomalies} from './18-payment-alerts/index.js';
export {weeklyAccountingScheduled, triggerWeeklyAccounting} from './19-accounting-sales-reports/index.js';
export { computeWeeklyAnalytics, computeMonthlySummary, computeDateRangeAnalytics } from './20-admin-analytics/index.js';
export {
  createTypesenseCollections,
  syncProductsWithTypesense,
  syncShopProductsWithTypesense,
  syncShopsWithTypesense,
  syncOrdersWithTypesense,
  syncFoodsWithTypesense,
  syncRestaurantsWithTypesense
} from './23-typesense/index.js';
export { computeRankingScores } from './24-promotion-score/index.js';
export { addProductsToCampaign, removeProductFromCampaign, updateCampaignProductDiscount } from './25-shop-campaign/index.js';
export { submitProduct, submitProductEdit } from './26-list-product/index.js';
export { processFoodOrder, initializeFoodPayment, foodPaymentCallback, checkFoodPaymentStatus, generateFoodReceiptBackground, updateFoodOrderStatus, submitRestaurantReview } from './27-food-payment/index.js';
export { sendShopInvitation, handleShopInvitation, revokeShopAccess, leaveShop, cancelShopInvitation, backfillShopClaims, setAdminClaim } from './28-shop-invitation/index.js';
export { initializeIsbankPayment, isbankPaymentCallback, checkIsbankPaymentStatus, clearPurchasedCartItems, processOrderNotification, recoverStuckPayments, processPostOrderWork } from './29-product-payment/index.js';
export { onFoodOrderStatusChange, informFoodCourier, cleanupExpiredCourierNotifications, callFoodCourier, createScannedFoodOrder, cleanupExpiredCourierCalls } from './30-food-courier-notifications/index.js';
export { extractColorOnly, initializeIsbankAdPayment, isbankAdPaymentCallback, checkIsbankAdPaymentStatus, processAdColorExtraction, processAdExpiration, processAdAnalytics, trackAdClick, trackAdConversion, createDailyAdAnalyticsSnapshot, cleanupExpiredAds, recoverStuckAdPayments } from './31-homescreen-ads-payment/index.js';
export { expireSingleBoost, initializeBoostPayment, boostPaymentCallback, checkBoostPaymentStatus, recoverStuckBoostPayments } from './32-product-boost-payment/index.js';
export { cleanupPaymentCollections } from './33-payment-cleanup/index.js';
export { setMasterCourierClaim } from './34-master-courier/index.js';
export { onDeliveryCompleted, recalcCourierStats, getCourierStatsSummary } from './35-courier-stats/index.js';
export { calculateDailyFoodAccounting, calculateWeeklyFoodAccounting, calculateMonthlyFoodAccounting } from './36-food-accounting/index.js';
export { generateRestaurantReceiptBackground } from './37-restaurant-receipt/index.js';
export { scheduleDiscountExpiry, restoreDiscountPrice } from './38-food-discount/index.js';
export { createTestCouriers, deleteTestCouriers, listTestCouriers } from './39-fake-accounts/index.js';
export { processCourierAction } from './40-courier-actions/index.js';
export { generateBusinessReport } from './41-business-client-side-accounting/index.js';
export { moderateImage } from './42-moderate-image-vision-api/index.js';
export { generateReceiptBackground } from './43-receipt-product-payment/index.js';
export { generatePDFReport } from './44-business-report-creation/index.js';
export { startEmail2FA, verifyEmail2FA, resendEmail2FA, createTotpSecret, verifyTotp, disableTotp, hasTotp, cleanupExpiredVerificationData } from './45-2FA/index.js'; 
export { sendNotificationOnCreation, sendRestaurantNotificationOnCreation, sendShopNotificationOnCreation, registerFcmToken, cleanupInvalidToken, removeFcmToken, createProductQuestionNotification } from './46-FCM-notifications/index.js';
export { registerWithEmailPassword, verifyEmailCode, resendEmailVerificationCode, sendPasswordResetEmail, sendReceiptEmail, sendReportEmail, shopWelcomeEmail } from './47-emails/index.js';
export { removeShopProduct, deleteProduct, toggleProductPauseStatus } from './48-product-management/index.js';
