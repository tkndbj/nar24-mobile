// functions/qr-functions.js

import admin from 'firebase-admin';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { CloudTasksClient } from '@google-cloud/tasks';
import crypto from 'crypto';
import QRCode from 'qrcode';

const tasksClient = new CloudTasksClient();

/**
 * Creates a Cloud Task to generate QR codes for an order
 * EXPORTED so it can be called from index.js
 * @param {string} orderId - The unique order identifier
 * @param {object} orderData - Order data for QR generation
 * @return {Promise<object>} Task creation result
 */
export async function createQRCodeTask(orderId, orderData) {
  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const queue = 'qr-code-generation';

  const db = admin.firestore();
  
  // ✅ IDEMPOTENCY: Check if QR already generated
  try {
    const orderSnap = await db.collection('orders').doc(orderId).get();
    if (orderSnap.exists) {
      const orderStatus = orderSnap.data();
      if (orderStatus.qrGenerationStatus === 'completed') {
        console.log(`⏭️ QR already generated for order ${orderId}, skipping task creation`);
        return { success: true, skipped: true, reason: 'already_completed' };
      }
      if (orderStatus.qrGenerationStatus === 'processing') {
        console.log(`⏭️ QR generation already in progress for order ${orderId}`);
        return { success: true, skipped: true, reason: 'already_processing' };
      }
    }
  } catch (checkError) {
    console.warn(`Could not check order status, proceeding with task: ${checkError.message}`);
  }

  const parent = tasksClient.queuePath(project, location, queue);

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url: `https://${location}-${project}.cloudfunctions.net/processQRCodeGeneration`,
      body: Buffer.from(JSON.stringify({
        orderId,
        buyerId: orderData.buyerId,
        buyerName: orderData.buyerName,
        items: orderData.items,
        totalPrice: orderData.totalPrice,
        deliveryOption: orderData.deliveryOption,
        createdAt: Date.now(),
      })).toString('base64'),
      headers: {
        'Content-Type': 'application/json',
      },
      oidcToken: {
        serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
      },
    },
    scheduleTime: {
      seconds: Math.floor(Date.now() / 1000) + 2,
    },
  };

  try {
    const [response] = await tasksClient.createTask({ parent, task });
    console.log(`✅ QR code task created for order ${orderId}: ${response.name}`);
    return { success: true, taskName: response.name };
  } catch (error) {
    console.error(`❌ Error creating QR code task for order ${orderId}:`, error);
    
    try {
      await db.collection('qr_generation_failures').add({
        orderId,
        error: error.message,
        stack: error.stack,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        retryable: true,
      });
    } catch (logError) {
      console.error('Failed to log QR task creation error:', logError);
    }
    
    return { success: false, error: error.message };
  }
}

/**
 * Generates verification hash for QR code security
 * @param {string} orderId - Order ID
 * @param {string} entityId - Buyer or Seller ID
 * @param {string} type - DELIVERY or GATHERING
 * @return {string} Hash string
 */
function generateVerificationHash(orderId, entityId, type) {
  const secret = process.env.QR_VERIFICATION_SECRET || 'your-secret-key-here';
  const data = `${orderId}:${entityId}:${type}:${secret}`;
  
  return crypto
    .createHash('sha256')
    .update(data)
    .digest('hex')
    .substring(0, 16);
}

/**
 * Generates QR code and uploads to Firebase Storage
 * @param {object} storage - Firebase Storage bucket
 * @param {object} data - Data to encode in QR
 * @param {string} filePath - Storage path for the file
 * @return {Promise<string>} Public URL of uploaded QR
 */
async function generateAndUploadQR(storage, data, filePath) {
  const qrContent = JSON.stringify(data);
  
  const qrBuffer = await QRCode.toBuffer(qrContent, {
    type: 'png',
    width: 400,
    margin: 2,
    errorCorrectionLevel: 'H',
    color: {
      dark: '#000000',
      light: '#FFFFFF',
    },
  });

  const file = storage.file(filePath);
  
  await file.save(qrBuffer, {
    metadata: {
      contentType: 'image/png',
      cacheControl: 'public, max-age=31536000',
      metadata: {
        orderId: data.orderId,
        type: data.type,
        generatedAt: new Date().toISOString(),
      },
    },
  });

  await file.makePublic();

  return `https://storage.googleapis.com/${storage.name}/${filePath}`;
}

/**
 * Cloud Task handler for QR code generation
 * Includes idempotency and duplication prevention
 */
export const processQRCodeGeneration = onRequest(
  {
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 120,
    invoker: 'private',
  },
  async (request, response) => {
    const startTime = Date.now();
    const db = admin.firestore();
    const storage = admin.storage().bucket();
    
    let orderId = null;
    
    try {
      const {
        orderId: reqOrderId,
        buyerId,
        buyerName,        
        totalPrice,
        deliveryOption,
        createdAt,
      } = request.body;
      
      orderId = reqOrderId;

      // ✅ VALIDATION
      if (!orderId || !buyerId) {
        console.error('Invalid QR generation request:', { orderId, buyerId });
        response.status(400).send({ success: false, error: 'Invalid request parameters' });
        return;
      }

      console.log(`🔄 Starting QR generation for order ${orderId}`);

      const orderRef = db.collection('orders').doc(orderId);
      
      // ✅ IDEMPOTENCY CHECK WITH TRANSACTION
      const idempotencyResult = await db.runTransaction(async (tx) => {
        const orderSnap = await tx.get(orderRef);
        
        if (!orderSnap.exists) {
          return { error: 'not_found', message: 'Order not found' };
        }

        const orderData = orderSnap.data();

        // ✅ DUPLICATION PREVENTION: Check if already completed
        if (orderData.qrGenerationStatus === 'completed' && orderData.deliveryQR?.url) {
          console.log(`⏭️ QR codes already exist for order ${orderId}`);
          return { 
            alreadyCompleted: true, 
            deliveryQR: orderData.deliveryQR,
            gatheringQRs: orderData.gatheringQRs,
          };
        }

        // ✅ PREVENT CONCURRENT PROCESSING
        if (orderData.qrGenerationStatus === 'processing') {
          const processingStarted = orderData.qrProcessingStartedAt?.toDate?.();
          const processingAge = processingStarted ? Date.now() - processingStarted.getTime() : 0;
          
          // If processing for less than 2 minutes, assume another instance is handling it
          if (processingAge < 120000) {
            console.log(`⏭️ QR generation already in progress for order ${orderId} (${processingAge}ms ago)`);
            return { alreadyProcessing: true };
          }
          
          // If older than 2 minutes, assume it failed and retry
          console.log(`🔄 Previous QR processing stale for order ${orderId}, retrying...`);
        }

        // ✅ MARK AS PROCESSING (atomic)
        tx.update(orderRef, {
          qrGenerationStatus: 'processing',
          qrProcessingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { proceed: true, orderData };
      });

      // Handle idempotency results
      if (idempotencyResult.error === 'not_found') {
        console.error(`Order ${orderId} not found`);
        response.status(404).send({ success: false, error: 'Order not found' });
        return;
      }

      if (idempotencyResult.alreadyCompleted) {
        console.log(`✅ Returning existing QR codes for order ${orderId}`);
        response.status(200).send({
          success: true,
          orderId,
          alreadyCompleted: true,
          deliveryQR: idempotencyResult.deliveryQR,
          gatheringQRs: idempotencyResult.gatheringQRs,
        });
        return;
      }

      if (idempotencyResult.alreadyProcessing) {
        response.status(200).send({
          success: true,
          orderId,
          alreadyProcessing: true,
          message: 'QR generation already in progress',
        });
        return;
      }

      const orderData = idempotencyResult.orderData;

      // Fetch order items
      const itemsSnap = await orderRef.collection('items').get();
      const orderItems = itemsSnap.docs.map((doc) => ({
        itemId: doc.id,
        ...doc.data(),
      }));

      if (orderItems.length === 0) {
        console.error(`No items found for order ${orderId}`);
        await orderRef.update({
          qrGenerationStatus: 'failed',
          qrGenerationError: 'No order items found',
          qrGenerationFailedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        response.status(400).send({ success: false, error: 'No order items found' });
        return;
      }

      // Group items by seller
      const sellerGroups = new Map();
      
      for (const item of orderItems) {
        const sellerId = item.sellerId || item.shopId || item.userId;
        
        if (!sellerGroups.has(sellerId)) {
          sellerGroups.set(sellerId, {
            sellerId,
            sellerName: item.sellerName || 'Unknown Seller',
            sellerType: item.isShopProduct ? 'shop' : 'user',
            shopId: item.shopId || null,
            items: [],
          });
        }
        
        sellerGroups.get(sellerId).items.push({
          itemId: item.itemId,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          price: item.price,
        });
      }

      const qrResults = {
        deliveryQR: null,
        gatheringQRs: [],
      };

      // 1. Generate DELIVERY QR
      const deliveryQRData = {
        type: 'DELIVERY',
        orderId,
        buyerId,
        buyerName,
        totalItems: orderItems.length,
        totalPrice: orderData.totalPrice || totalPrice,
        deliveryOption,
        createdAt: orderData.timestamp?.toDate?.()?.toISOString() || new Date(createdAt).toISOString(),
        verificationHash: generateVerificationHash(orderId, buyerId, 'DELIVERY'),
      };

      const deliveryQRUrl = await generateAndUploadQR(
        storage,
        deliveryQRData,
        `orders/${orderId}/qr_delivery.png`,
      );

      qrResults.deliveryQR = {
        url: deliveryQRUrl,
        type: 'delivery',
        generatedAt: new Date().toISOString(),
      };

      // 2. Generate GATHERING QRs
      for (const [sellerId, sellerData] of sellerGroups) {
        const gatheringQRData = {
          type: 'GATHERING',
          orderId,
          sellerId,
          sellerName: sellerData.sellerName,
          sellerType: sellerData.sellerType,
          shopId: sellerData.shopId,
          buyerName,
          items: sellerData.items.map((item) => ({
            productName: item.productName,
            quantity: item.quantity,
            itemId: item.itemId,
          })),
          itemCount: sellerData.items.length,
          createdAt: orderData.timestamp?.toDate?.()?.toISOString() || new Date(createdAt).toISOString(),
          verificationHash: generateVerificationHash(orderId, sellerId, 'GATHERING'),
        };

        const gatheringQRUrl = await generateAndUploadQR(
          storage,
          gatheringQRData,
          `orders/${orderId}/qr_gathering_${sellerId}.png`,
        );

        qrResults.gatheringQRs.push({
          sellerId,
          sellerName: sellerData.sellerName,
          url: gatheringQRUrl,
          type: 'gathering',
          itemCount: sellerData.items.length,
          generatedAt: new Date().toISOString(),
        });

        // Update items with gathering QR
        const batch = db.batch();
        for (const item of sellerData.items) {
          const itemRef = orderRef.collection('items').doc(item.itemId);
          batch.update(itemRef, {
            gatheringQRUrl: gatheringQRUrl,
            gatheringQRGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      // 3. Update order document - COMPLETED
      await orderRef.update({
        deliveryQR: qrResults.deliveryQR,
        gatheringQRs: qrResults.gatheringQRs,
        qrCodesGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        qrGenerationStatus: 'completed',
        qrProcessingStartedAt: admin.firestore.FieldValue.delete(), // Clean up
      });

      // 4. Log success
      const processingTime = Date.now() - startTime;
      await db.collection('qr_generation_logs').add({
        orderId,
        buyerId,
        deliveryQRUrl: qrResults.deliveryQR.url,
        gatheringQRCount: qrResults.gatheringQRs.length,
        processingTimeMs: processingTime,
        success: true,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`✅ QR generation completed for order ${orderId} in ${processingTime}ms`);

      response.status(200).send({
        success: true,
        orderId,
        deliveryQR: qrResults.deliveryQR,
        gatheringQRs: qrResults.gatheringQRs,
        processingTimeMs: processingTime,
      });
    } catch (error) {
      console.error(`❌ QR generation failed for order ${orderId}:`, error);

      try {
        await db.collection('qr_generation_logs').add({
          orderId: orderId || 'unknown',
          error: error.message,
          stack: error.stack,
          success: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (orderId) {
          await db.collection('orders').doc(orderId).update({
            qrGenerationStatus: 'failed',
            qrGenerationError: error.message,
            qrGenerationFailedAt: admin.firestore.FieldValue.serverTimestamp(),
            qrProcessingStartedAt: admin.firestore.FieldValue.delete(),
          });
        }
      } catch (logError) {
        console.error('Failed to log QR generation error:', logError);
      }

      response.status(500).send({
        success: false,
        error: error.message,
        orderId,
      });
    }
  },
);

/**
 * Verify QR code (used by courier app)
 * @description Validates QR authenticity and returns order details
 */
export const verifyQRCode = onCall(
  {
    region: 'europe-west3',
    memory: '128MB',
    timeoutSeconds: 10,
  },
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }

      const { qrData } = request.data;

      if (!qrData) {
        throw new HttpsError('invalid-argument', 'QR data is required');
      }

      let parsedData;
      try {
        parsedData = typeof qrData === 'string' ? JSON.parse(qrData) : qrData;
      } catch (parseError) {
        throw new HttpsError('invalid-argument', 'Invalid QR code format');
      }

      const { type, orderId, verificationHash } = parsedData;

      if (!type || !orderId || !verificationHash) {
        throw new HttpsError('invalid-argument', 'Missing required QR fields');
      }

      const entityId = type === 'DELIVERY' ? parsedData.buyerId : parsedData.sellerId;
      const expectedHash = generateVerificationHash(orderId, entityId, type);
      
      if (verificationHash !== expectedHash) {
        console.warn(`QR verification failed for order ${orderId}`);
        return { valid: false, error: 'Invalid QR code' };
      }

      const db = admin.firestore();
      const orderSnap = await db.collection('orders').doc(orderId).get();

      if (!orderSnap.exists) {
        return { valid: false, error: 'Order not found' };
      }

      const orderData = orderSnap.data();

      return {
        valid: true,
        type,
        orderId,
        orderData: {
          buyerName: orderData.buyerName,
          totalPrice: orderData.totalPrice,
          itemCount: orderData.itemCount,
          deliveryOption: orderData.deliveryOption,
          timestamp: orderData.timestamp?.toDate?.()?.toISOString(),
        },
        qrDetails: parsedData,
      };
    } catch (error) {
      console.error('QR verification error:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message);
    }
  },
);

/**
 * Mark QR as scanned (updates order status)
 * @description Called by courier when scanning QR at pickup/delivery
 */
export const markQRScanned = onCall(
  {
    region: 'europe-west3',
    memory: '256MB',
    timeoutSeconds: 30,
  },
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }

      // ✅ COURIER ROLE CHECK
      const db = admin.firestore();
      const courierSnap = await db.collection('users').doc(request.auth.uid).get();
      const courierData = courierSnap.data();
      
      if (!courierData?.cargoGuy && !courierData?.roles?.includes('cargoGuy')) {
        throw new HttpsError('permission-denied', 'Only couriers can scan QR codes');
      }

      const { qrData, scannedLocation, notes } = request.data;

      if (!qrData) {
        throw new HttpsError('invalid-argument', 'QR data is required');
      }

      let parsedData;
      try {
        parsedData = typeof qrData === 'string' ? JSON.parse(qrData) : qrData;
      } catch (parseError) {
        throw new HttpsError('invalid-argument', 'Invalid QR code format');
      }

      const { type, orderId, verificationHash } = parsedData;
      const entityId = type === 'DELIVERY' ? parsedData.buyerId : parsedData.sellerId;
      
      const expectedHash = generateVerificationHash(orderId, entityId, type);
      if (verificationHash !== expectedHash) {
        throw new HttpsError('invalid-argument', 'Invalid QR code');
      }

      const orderRef = db.collection('orders').doc(orderId);
      const courierId = request.auth.uid;
      const timestamp = admin.firestore.FieldValue.serverTimestamp();

      if (type === 'GATHERING') {
        const sellerId = parsedData.sellerId;
        
        const result = await db.runTransaction(async (tx) => {
          const itemsSnap = await tx.get(
            orderRef.collection('items').where('sellerId', '==', sellerId)
          );

          const alreadyGathered = itemsSnap.docs.every(
            (doc) => doc.data().gatheringStatus === 'gathered'
          );

          if (alreadyGathered) {
            return { alreadyGathered: true, itemsCount: itemsSnap.docs.length };
          }

          itemsSnap.docs.forEach((doc) => {
            tx.update(doc.ref, {
              gatheringStatus: 'gathered',
              gatheredAt: timestamp,
              gatheredBy: courierId,
              gatheredLocation: scannedLocation ? 
                new admin.firestore.GeoPoint(scannedLocation.latitude, scannedLocation.longitude) : null,
              gatheringNotes: notes || null,
            });
          });

          return { updated: true, itemsCount: itemsSnap.docs.length };
        });

        if (result.alreadyGathered) {
          return {
            success: true,
            type: 'GATHERING',
            orderId,
            sellerId,
            alreadyGathered: true,
            itemsGathered: result.itemsCount,
          };
        }

        await db.collection('qr_scan_logs').add({
          type: 'GATHERING',
          orderId,
          sellerId,
          courierId,
          itemsCount: result.itemsCount,
          location: scannedLocation || null,
          notes: notes || null,
          timestamp,
        });

        const allItemsSnap = await orderRef.collection('items').get();
        const allGathered = allItemsSnap.docs.every(
          (doc) => doc.data().gatheringStatus === 'gathered'
        );

        if (allGathered) {
          await orderRef.update({
            gatheringStatus: 'all_gathered',
            allGatheredAt: timestamp,
          });
        }

        return {
          success: true,
          type: 'GATHERING',
          orderId,
          sellerId,
          itemsGathered: result.itemsCount,
          allItemsGathered: allGathered,
        };
      } else if (type === 'DELIVERY') {
        const buyerId = parsedData.buyerId;
        
        const result = await db.runTransaction(async (tx) => {
          const orderSnap = await tx.get(orderRef);
          const orderData = orderSnap.data();

          if (orderData.deliveryStatus === 'delivered' || orderData.distributionStatus === 'delivered') {
            return { alreadyDelivered: true };
          }

          tx.update(orderRef, {
            deliveryStatus: 'delivered',
            deliveredAt: timestamp,
            deliveredBy: courierId,
            deliveredLocation: scannedLocation ?
              new admin.firestore.GeoPoint(scannedLocation.latitude, scannedLocation.longitude) : null,
            deliveryNotes: notes || null,
            distributionStatus: 'delivered',
          });

          return { updated: true, orderData };
        });

        if (result.alreadyDelivered) {
          return {
            success: true,
            type: 'DELIVERY',
            orderId,
            alreadyDelivered: true,
          };
        }

        // Update all items
        const itemsSnap = await orderRef.collection('items').get();
        const batch = db.batch();
        
        itemsSnap.docs.forEach((doc) => {
          batch.update(doc.ref, {
            deliveryStatus: 'delivered',
            deliveredAt: timestamp,
            gatheringStatus: 'delivered',
          });
        });

        await batch.commit();

        // Log scan
        await db.collection('qr_scan_logs').add({
          type: 'DELIVERY',
          orderId,
          buyerId,
          courierId,
          location: scannedLocation || null,
          notes: notes || null,
          timestamp,
        });

        // ✅ CREATE NOTIFICATION FOR BUYER
        const notificationRef = db.collection('users').doc(buyerId).collection('notifications').doc();
        await notificationRef.set({
          type: 'order_delivered',
          orderId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          message: '📦✨ Your order has been delivered! Tap to share your experience and leave a review.',
          message_en: '📦✨ Your order has been delivered! Tap to share your experience and leave a review.',
          message_tr: '📦✨ Siparişiniz teslim edildi! Deneyiminizi paylaşmak ve değerlendirme bırakmak için dokunun.',
          message_ru: '📦✨ Ваш заказ доставлен! Нажмите, чтобы поделиться впечатлениями и оставить отзыв.',
        });

        return {
          success: true,
          type: 'DELIVERY',
          orderId,
          delivered: true,
          notificationSent: true,
        };
      }

      throw new HttpsError('invalid-argument', 'Invalid QR type');
    } catch (error) {
      console.error('Mark QR scanned error:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message);
    }
  },
);

/**
 * Retry failed QR generation
 * @description Manual retry for failed QR generations
 */
export const retryQRGeneration = onCall(
  {
    region: 'europe-west3',
    memory: '256MB',
    timeoutSeconds: 30,
  },
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }

      const { orderId } = request.data;

      if (!orderId) {
        throw new HttpsError('invalid-argument', 'Order ID is required');
      }

      const db = admin.firestore();
      const orderRef = db.collection('orders').doc(orderId);
      const orderSnap = await orderRef.get();

      if (!orderSnap.exists) {
        throw new HttpsError('not-found', 'Order not found');
      }

      const orderData = orderSnap.data();

      // ✅ PERMISSION CHECK: Buyer or admin can retry
      if (orderData.buyerId !== request.auth.uid) {
        // TODO: Add admin role check if needed
        throw new HttpsError('permission-denied', 'Not authorized');
      }

      // ✅ CHECK IF ALREADY COMPLETED
      if (orderData.qrGenerationStatus === 'completed' && orderData.deliveryQR?.url) {
        return {
          success: true,
          alreadyCompleted: true,
          message: 'QR codes already exist',
          deliveryQR: orderData.deliveryQR,
        };
      }

      // ✅ RESET STATUS BEFORE RETRY
      await orderRef.update({
        qrGenerationStatus: 'pending_retry',
        qrRetryRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        qrRetryRequestedBy: request.auth.uid,
      });

      const result = await createQRCodeTask(orderId, {
        buyerId: orderData.buyerId,
        buyerName: orderData.buyerName,
        items: [],
        totalPrice: orderData.totalPrice,
        deliveryOption: orderData.deliveryOption,
      });

      if (result.skipped) {
        return {
          success: true,
          skipped: true,
          reason: result.reason,
          message: 'QR generation already completed or in progress',
        };
      }

      return {
        success: result.success,
        message: result.success ? 'QR generation retry initiated' : 'Failed to create retry task',
        error: result.error || null,
      };
    } catch (error) {
      console.error('Retry QR generation error:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message);
    }
  },
);
