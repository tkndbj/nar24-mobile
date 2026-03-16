// functions/index.js
import crypto from 'crypto';
import * as functions from 'firebase-functions/v2';
import {onDocumentWritten, onDocumentCreated, onDocumentUpdated} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onRequest, onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {Storage} from '@google-cloud/storage';
const storage = new Storage();
import {onObjectFinalized} from 'firebase-functions/v2/storage';
import * as path from 'path';
import {localizeAttributeKey, localizeAttributeValue} from './attributeLocalization.js';
import * as os from 'os';
import * as fs from 'fs';
import PDFDocument from 'pdfkit';
import {getDominantColor} from './getDominantColor.js';
import {getMessaging} from 'firebase-admin/messaging';
import {CloudTasksClient} from '@google-cloud/tasks';
import {Timestamp, FieldValue} from 'firebase-admin/firestore';
import {fileURLToPath} from 'url';
import {dirname} from 'path';
import {authenticator} from 'otplib';
import {defineSecret} from 'firebase-functions/params';
import vision from '@google-cloud/vision';
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const regularFontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
const boldFontPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
const OTP_SALT = defineSecret('OTP_SALT');
admin.initializeApp();
const visionClient = new vision.ImageAnnotatorClient();


function getAdTypeLabel(adType) {
  switch (adType) {
  case 'topBanner':
    return 'Top Banner';
  case 'thinBanner':
    return 'Thin Banner';
  case 'marketBanner':
    return 'Market Banner';
  default:
    return 'Banner';
  }
}

  // Fire-and-forget alert for post-order task failures
  function logTaskFailureAlert(taskName, orderId, buyerId, buyerName, error) {
    try {
      admin.firestore().collection('_payment_alerts').doc(`${orderId}_${taskName}`).set({
        type: `task_${taskName}_failed`,
        severity: 'low',
        orderNumber: orderId,
        pendingPaymentId: null,
        orderId,
        userId: buyerId,
        buyerName: buyerName || '',
        amount: 0,
        errorMessage: `${taskName} failed: ${error?.message || String(error)}`,
        isRead: false,
        isResolved: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        detectedBy: 'task_catch',
      });
    } catch (_) {
      // Silent — alerting should never break anything
    }
  }


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

    const enqueuedTasks = [];

    // Queue each chunk as a separate task
    for (const chunk of chunks) {
      try {
        const payload = {
          data: {
            products: chunk,
            userGender,
            userAge,
            timestamp: Date.now(),
          },
        };

        const task = {
          httpRequest: {
            httpMethod: 'POST',
            url: functionUrl,
            headers: {
              'Content-Type': 'application/json',
            },
            body: Buffer.from(JSON.stringify(payload)).toString('base64'),
            oidcToken: {
              serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
            },
          },
          dispatchDeadline: {
            seconds: 300, // 5 minutes max execution (same as before)
          },
        };
        
        const [createdTask] = await client.createTask({
          parent: queuePath,
          task: task,
        });
        
        enqueuedTasks.push(createdTask.name);
      } catch (error) {
        console.error('Failed to enqueue task:', error);
        // Continue queuing other chunks even if one fails
      }
    }

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
        
        try {
          const snapshot = await db
            .collection('users')
            .doc(userId)
            .collection('boostHistory')
            .where('itemId', 'in', itemIds.slice(0, 10))
            .where('boostStartTime', 'in', boostStartTimes.slice(0, 10))
            .get();

            for (const doc of snapshot.docs) {
              if (operationCount >= MAX_BATCH_SIZE) {
                await commitBatch();
              }
            
              const docData = doc.data();
              const matchingProduct = userProducts.find((p) => p.itemId === docData.itemId);
              
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
          // Continue processing other users
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

        try {
          const snapshot = await db
            .collection('shops')
            .doc(shopId)
            .collection('boostHistory')
            .where('itemId', 'in', itemIds.slice(0, 10))
            .where('boostStartTime', 'in', boostStartTimes.slice(0, 10))
            .get();

            for (const doc of snapshot.docs) {
              if (operationCount >= MAX_BATCH_SIZE) {
                await commitBatch();
              }
            
              const docData = doc.data();
              const matchingProduct = shopProducts.find((p) => p.itemId === docData.itemId);
              
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
          // Continue processing other shops
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

export const TEMPLATES = {
  en: {
    // Notification types
    product_out_of_stock: {
      title: 'Out of Stock ⚠️',
      body: 'Your product is out of stock.',
    },
    product_out_of_stock_seller_panel: {
      title: 'Shop Item Out of Stock ⚠️',
      body: 'A product is out of stock in your shop.',
    },
    boost_expired: {
      title: 'Boost Expired ⚠️',
      body: 'Your boost has expired.',
    },
    product_archived_by_admin: {
      title: 'Product Paused ⚠️',
      body: '"{productName}" was paused by admin',
    },
    product_review_shop: {
      title: 'New Product Review ⭐',
      body: 'Your product "{productName}" received a new review',
    },
    product_review_user: {
      title: 'New Product Review ⭐',
      body: 'Your product "{productName}" received a new review',
    },
    seller_review_shop: {
      title: 'New Shop Review ⭐',
      body: 'Your shop received a new review',
    },
    seller_review_user: {
      title: 'New Seller Review ⭐',
      body: 'You received a new seller review',
    },
    product_sold: {
      title: 'Product Sold! 🎉',
      body: 'Your product "{productName}" has been sold!',
    },
    product_sold_user: {
      title: 'Продукт Продан! 🎉',
      body: 'Ваш продукт "{productName}" был продан!',
    },
    campaign_ended: {
      title: 'Campaign Ended 🏁',
      body: 'Campaign "{campaignName}" has ended',
    },
    shipment_update: {
      title: 'Shipment Status Updated! ✅',
      body: 'Your shipment status has been updated!',
    },
    campaign: {
      title: '🎉 New Campaign: {campaignName}',
      body: '{campaignDescription}',
    },
    product_question: {
      title: 'New Product Question 💬',
      body: 'Someone asked a question about your product: {productName}',
    },
    shop_invitation: {
      title: 'Shop Invitation 🏪',
      body: 'You have been invited to join {shopName} as {role}',
    },
    ad_expired: {
      title: 'Ad Expired ⚠️',
      body: 'Your ad for {shopName} has expired.',
    },
    ad_approved: {
      title: 'Ad Approved! 🎉',
      body: 'Your ad for {shopName} has been approved. Click to proceed with payment.',
    },
    ad_rejected: {
      title: 'Ad Rejected ❌',
      body: 'Your ad for {shopName} was rejected. Reason: {rejectionReason}',
    },
    refund_request_approved: {
      title: 'Refund Request Approved ✅',
      body: 'Your refund request for receipt #{receiptNo} has been approved.',
    },
    refund_request_rejected: {
      title: 'Refund Request Rejected ❌',
      body: 'Your refund request for receipt #{receiptNo} has been rejected.',
    },
    order_delivered: {
      title: 'Order Delivered! 📦✨',
      body: 'Your order has been delivered! Tap to share your experience.',
    },
    product_question_answered: {
      title: 'Question Answered! 💬',
      body: 'Your question about "{productName}" has been answered!',
    },
    new_food_order: {
      title: 'New Order! 🍽️',
      body: 'A new order has been placed.',
    },
    food_order_status_update_accepted: {
      title: 'Order Accepted! ✅',
      body: '{restaurantName} has accepted your order.',
    },
    food_order_status_update_rejected: {
      title: 'Order Rejected ❌',
      body: '{restaurantName} has rejected your order.',
    },
    food_order_status_update_preparing: {
      title: 'Being Prepared! 🍳',
      body: '{restaurantName} is now preparing your order.',
    },
    food_order_status_update_ready: {
      title: 'Order Ready! 📦',
      body: 'Your order from {restaurantName} is ready!',
    },
    food_order_status_update_delivered: {
      title: 'Order Delivered! 🎉',
      body: 'Your order from {restaurantName} has been delivered.',
    },
    food_order_delivered_review: {
      title: 'Order Delivered! 🎉',
      body: 'Your order from {restaurantName} has arrived. Tap to leave a review!',
    },
    restaurant_new_review: {
      title: 'New Review! ⭐',
      body: 'One of your customers left a {rating}-star review.',
    },
    default: {
      title: 'New Notification',
      body: 'You have a new notification!',
    },
  },

  tr: {
    product_out_of_stock: {
      title: 'Ürün Stoğu Tükendi ⚠️',
      body: 'Ürününüz stokta kalmadı.',
    },
    product_out_of_stock_seller_panel: {
      title: 'Mağaza Ürünü Stoğu Tükendi ⚠️',
      body: 'Mağanızdaki bir ürün stokta kalmadı.',
    },
    boost_expired: {
      title: 'Boost Süresi Doldu ⚠️',
      body: 'Öne çıkarılan ürünün süresi doldu.',
    },
    product_archived_by_admin: {
      title: 'Ürün Durduruldu ⚠️',
      body: '"{productName}" admin tarafından durduruldu',
    },
    product_review_shop: {
      title: 'Yeni Ürün Değerlendirmesi ⭐',
      body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
    },
    product_review_user: {
      title: 'Yeni Ürün Değerlendirmesi ⭐',
      body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
    },
    seller_review_shop: {
      title: 'Yeni Mağaza Değerlendirmesi ⭐',
      body: 'Mağazanız yeni bir değerlendirme aldı',
    },
    seller_review_user: {
      title: 'Yeni Satıcı Değerlendirmesi ⭐',
      body: 'Yeni bir satıcı değerlendirmesi aldınız',
    },
    product_sold: {
      title: 'Mağaza Ürünü Satıldı! 🎉',
      body: 'Ürününüz "{productName}" satıldı!',
    },
    product_sold_user: {
      title: 'Ürün Satıldı! 🎉',
      body: 'Ürününüz "{productName}" satıldı!',
    },
    campaign_ended: {
      title: 'Kampanya Bitti 🏁',
      body: '"{campaignName}" kampanyası sona erdi',
    },
    shipment_update: {
      title: 'Gönderi Durumu Güncellendi! ✅',
      body: 'Gönderi durumunuz güncellendi!',
    },
    campaign: {
      title: '🎉 Yeni Kampanya: {campaignName}',
      body: '{campaignDescription}',
    },
    product_question: {
      title: 'Yeni Ürün Sorusu 💬',
      body: 'Ürününüz hakkında soru soruldu: {productName}',
    },
    shop_invitation: {
      title: 'Mağaza Daveti 🏪',
      body: '{shopName} mağazasına {role} olarak katılmaya davet edildiniz',
    },
    ad_expired: {
      title: 'Reklam Süresi Doldu ⚠️',
      body: '{shopName} reklamınızın süresi doldu.',
    },
    ad_approved: {
      title: 'Reklam Onaylandı! 🎉',
      body: '{shopName} için reklamınız onaylandı. Ödeme yapmak için tıklayın.',
    },
    ad_rejected: {
      title: 'Reklam Reddedildi ❌',
      body: '{shopName} için reklamınız reddedildi. Neden: {rejectionReason}',
    },
    refund_request_approved: {
      title: 'İade Talebi Onaylandı ✅',
      body: 'Fiş no #{receiptNo} için iade talebiniz onaylandı.',
    },
    refund_request_rejected: {
      title: 'İade Talebi Reddedildi ❌',
      body: 'Fiş no #{receiptNo} için iade talebiniz reddedildi.',
    },
    order_delivered: {
      title: 'Sipariş Teslim Edildi! 📦✨',
      body: 'Siparişiniz teslim edildi! Deneyiminizi paylaşmak için dokunun.',
    },
    product_question_answered: {
      title: 'Soru Yanıtlandı! 💬',
      body: '"{productName}" hakkındaki sorunuz yanıtlandı!',
    },
    new_food_order: {
      title: 'Yeni Sipariş! 🍽️',
      body: 'Yeni sipariş verildi.',
    },
    food_order_status_update_accepted: {
      title: 'Sipariş Onaylandı! ✅',
      body: '{restaurantName} siparişinizi onayladı.',
    },
    food_order_status_update_rejected: {
      title: 'Sipariş Reddedildi ❌',
      body: '{restaurantName} siparişinizi reddetti.',
    },
    food_order_status_update_preparing: {
      title: 'Hazırlanıyor! 🍳',
      body: '{restaurantName} siparişinizi hazırlamaya başladı.',
    },
    food_order_status_update_ready: {
      title: 'Sipariş Hazır! 📦',
      body: '{restaurantName} siparişiniz teslimata hazır!',
    },
    food_order_status_update_delivered: {
      title: 'Sipariş Teslim Edildi! 🎉',
      body: '{restaurantName} siparişiniz teslim edildi.',
    },
    food_order_delivered_review: {
      title: 'Sipariş Teslim Edildi! 🎉',
      body: '{restaurantName} siparişiniz ulaştı. Değerlendirme yapmak için tıklayın!',
    },
    restaurant_new_review: {
      title: 'Yeni Değerlendirme! ⭐',
      body: 'Bir müşteriniz {rating} yıldız verdi.',
    },
    default: {
      title: 'Yeni Bildirim',
      body: 'Yeni bir bildiriminiz var!',
    },
  },

  ru: {
    product_out_of_stock: {
      title: 'Товар Распродан',
      body: 'Ваш продукт “{productName}” распродан.',
    },
    product_out_of_stock_seller_panel: {
      title: 'Запасы Магазина Исчерпаны',
      body: 'Товар “{productName}” отсутствует в вашем магазине.',
    },
    boost_expired: {
      title: 'Срок Буста Истек',
      body: 'Время действия буста “{itemType}” истекло.',
    },
    product_archived_by_admin: {
      title: 'Продукт приостановлен ⚠️',
      body: '"{productName}" приостановлен администратором',
    },
    product_review_shop: {
      title: 'Новый Отзыв о Продукте ⭐',
      body: 'Ваш продукт "{productName}" получил новый отзыв',
    },
    product_review_user: {
      title: 'Новый Отзыв о Продукте ⭐',
      body: 'Ваш продукт "{productName}" получил новый отзыв',
    },
    seller_review_shop: {
      title: 'Новый Отзыв о Магазине ⭐',
      body: 'Ваш магазин получил новый отзыв',
    },
    seller_review_user: {
      title: 'Новый Отзыв Продавца ⭐',
      body: 'Вы получили новый отзыв продавца',
    },
    product_sold: {
      title: 'Товар Магазина Продан! 🎉',
      body: 'Ваш товар "{productName}" был продан!',
    },
    product_sold_user: {
      title: 'Продукт Продан! 🎉',
      body: 'Ваш продукт "{productName}" был продан!',
    },
    campaign_ended: {
      title: 'Кампания завершена 🏁',
      body: 'Кампания "{campaignName}" завершена',
    },
    shipment_update: {
      title: 'Статус Доставки Обновлен!',
      body: 'Статус вашей доставки был обновлен!',
    },
    campaign: {
      title: '🎉 Новая Кампания: {campaignName}',
      body: '{campaignDescription}',
    },
    product_question: {
      title: 'Новый Вопрос о Продукте 💬',
      body: 'Кто-то задал вопрос о вашем продукте: {productName}',
    },
    shop_invitation: {
      title: 'Приглашение в Магазин 🏪',
      body: 'Вас пригласили присоединиться к {shopName} как {role}',
    },
    ad_expired: {
      title: 'Срок Рекламы Истек ⚠️',
      body: 'Срок действия вашего объявления для {shopName} истек.',
    },
    ad_approved: {
      title: 'Реклама Одобрена! 🎉',
      body: 'Ваше объявление для {shopName} было одобрено. Нажмите, чтобы перейти к оплате.',
    },
    ad_rejected: {
      title: 'Реклама Отклонена ❌',
      body: 'Ваше объявление для {shopName} было отклонено. Причина: {rejectionReason}',
    },
    refund_request_approved: {
      title: 'Запрос на Возврат Одобрен ✅',
      body: 'Ваш запрос на возврат для чека #{receiptNo} был одобрен.',
    },
    refund_request_rejected: {
      title: 'Запрос на Возврат Отклонен ❌',
      body: 'Ваш запрос на возврат для чека #{receiptNo} был отклонен.',
    },
    order_delivered: {
      title: 'Заказ доставлен! 📦✨',
      body: 'Ваш заказ доставлен! Нажмите, чтобы поделиться впечатлениями.',
    },
    product_question_answered: {
      title: 'Вопрос Отвечен! 💬',
      body: 'На ваш вопрос о "{productName}" ответили!',
    },
    new_food_order: {
      title: 'Новый заказ! 🍽️',
      body: 'Был размещен новый заказ.',
    },
    food_order_status_update_accepted: {
      title: 'Заказ принят! ✅',
      body: '{restaurantName} принял ваш заказ.',
    },
    food_order_status_update_rejected: {
      title: 'Заказ отклонён ❌',
      body: '{restaurantName} отклонил ваш заказ.',
    },
    food_order_status_update_preparing: {
      title: 'Готовится! 🍳',
      body: '{restaurantName} начал готовить ваш заказ.',
    },
    food_order_status_update_ready: {
      title: 'Заказ готов! 📦',
      body: 'Ваш заказ из {restaurantName} готов!',
    },
    food_order_status_update_delivered: {
      title: 'Заказ доставлен! 🎉',
      body: 'Ваш заказ из {restaurantName} доставлен.',
    }, 
    food_order_delivered_review: {
      title: 'Заказ доставлен! 🎉',
      body: 'Ваш заказ из {restaurantName} прибыл. Нажмите, чтобы оставить отзыв!',
    },
    restaurant_new_review: {
      title: 'Новый отзыв! ⭐',
      body: 'Один из ваших клиентов оставил оценку {rating} звезды.',
    },  
    default: {
      title: 'Новое Уведомление',
      body: 'У вас новое уведомление!',
    },
  },
};

export const sendNotificationOnCreation = onDocumentCreated({
  region: 'europe-west3',
  document: 'users/{userId}/notifications/{notificationId}',
}, async (event) => {
  const snap = event.data;
  const notificationData = snap.data();
  const {userId, notificationId} = event.params;

  if (!notificationData) {
    console.log('No notification data, exiting.');
    return;
  }

  // 1) Load the user's FCM tokens and locale
  const userDoc = await admin.firestore().doc(`users/${userId}`).get();
  const userData = userDoc.data() || {};
  const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];
  if (tokens.length === 0) {
    console.log(`No FCM tokens for user ${userId}.`);
    return;
  }
  const locale = userData.languageCode || 'en';

  // 2) Pick and interpolate the template
  const localeSet = TEMPLATES[locale] || TEMPLATES.en;
  const originalType = notificationData.type || 'default';
  let type = originalType;
  if (type === 'food_order_status_update' && notificationData.payload?.orderStatus) {
    type = `food_order_status_update_${notificationData.payload.orderStatus}`;
  }
  const tmpl = localeSet[type] || localeSet.default;

  let title = tmpl.title;
  let body = tmpl.body;
  if (notificationData.productName) {
    title = title.replace('{productName}', notificationData.productName);
    body = body .replace('{productName}', notificationData.productName);
  }
  if (notificationData.itemType) {
    title = title.replace('{itemType}', notificationData.itemType);
    body = body .replace('{itemType}', notificationData.itemType);
  }
  if (notificationData.campaignName) {
    title = title.replace('{campaignName}', notificationData.campaignName);
    body = body.replace('{campaignName}', notificationData.campaignName);
  }
  if (notificationData.campaignDescription) {
    title = title.replace('{campaignDescription}', notificationData.campaignDescription);
    body = body.replace('{campaignDescription}', notificationData.campaignDescription);
  }
  if (notificationData.shopName) {
    title = title.replace('{shopName}', notificationData.shopName);
    body = body.replace('{shopName}', notificationData.shopName);
  }
  if (notificationData.role) {
    title = title.replace('{role}', notificationData.role);
    body = body.replace('{role}', notificationData.role);
  }
  if (notificationData.adTypeLabel) {
    title = title.replace('{adTypeLabel}', notificationData.adTypeLabel);
    body = body.replace('{adTypeLabel}', notificationData.adTypeLabel);
  }
  if (notificationData.rejectionReason) {
    title = title.replace('{rejectionReason}', notificationData.rejectionReason);
    body = body.replace('{rejectionReason}', notificationData.rejectionReason);
  }
  if (notificationData.receiptNo) {
    title = title.replace('{receiptNo}', notificationData.receiptNo);
    body = body.replace('{receiptNo}', notificationData.receiptNo);
  }
  const payload = notificationData.payload || {};
if (payload.restaurantName) {
  title = title.replace('{restaurantName}', payload.restaurantName);
  body  = body .replace('{restaurantName}', payload.restaurantName);
}
if (payload.orderStatus) {
  title = title.replace('{orderStatus}', payload.orderStatus);
  body  = body .replace('{orderStatus}', payload.orderStatus);
}
if (payload.orderId) {
  title = title.replace('{orderId}', payload.orderId);
  body  = body .replace('{orderId}', payload.orderId);
}

  // 3) Compute the deep-link route for GoRouter
  //    (defaults to your in-app notifications list)
  let route = '/notifications';
  switch (originalType) {
  case 'product_out_of_stock':
    route = '/myproducts';
    break;
  case 'product_out_of_stock_seller_panel':
    if (notificationData.shopId) {
      route = `/seller-panel?shopId=${notificationData.shopId}&tab=2`;
    }
    break;
    case 'order_delivered':
      route = '/notifications';
      break;
    case 'boost_expired':
      route = '/notifications'; // User can tap the notification from the list
      break;
  case 'product_review_shop':
    if (notificationData.shopId) {
      route = `/seller_panel_reviews/${notificationData.shopId}`;
    }
    break;
    case 'food_order_delivered_review':
      route = payload.orderId ? `/food-order-detail/${payload.orderId}` : '/orders?tab=food';
      break;
      case 'food_order_status_update':
        route = '/my_food_orders';
        break;
  case 'product_review_user':
    if (notificationData.productId) {
      route = `/product/${notificationData.productId}`; 
    }
    break;
  case 'seller_review_shop':
    if (notificationData.shopId) {
      route = `/seller_panel_reviews/${notificationData.shopId}`;
    }
    break;
    case 'product_question_answered':
      route = '/user-product-questions';
      break;
  case 'ad_approved':
    route = '/notifications'; // User needs to see notification to click payment button
    break;
  case 'ad_rejected':
    route = '/notifications'; // User needs to see rejection reason
    break;
  case 'ad_expired':
    if (notificationData.shopId) {
      route = `/seller-panel?shopId=${notificationData.shopId}&tab=5`;
    }
    break;
  case 'seller_review_user':
    if (notificationData.sellerId) {
      route = `/seller_reviews/${notificationData.sellerId}`;
    }
    break;
  
  case 'product_sold_user':
    route = '/my_orders?tab=1';
    break;
  case 'shop_invitation':
    route = '/notifications';
    break;

  case 'campaign':
    route = '/seller-panel?tab=0';
    break;
  case 'product_question':
    if (notificationData.isShopProduct && notificationData.shopId) {
      route = `/seller_panel_product_questions/${notificationData.shopId}`;
    } else {
      route = '/user-product-questions';
    }
    break;
  case 'refund_request':
    route = '/notifications'; // User needs to see the notification details
    break;
    // default already '/notifications'
  }

  // 4) Build the data payload (including our new `route`)
  const dataPayload = {
    notificationId: String(notificationId),
    route,
  };
  Object.entries(notificationData).forEach(([key, value]) => {
    dataPayload[key] = typeof value === 'string' ?
      value :
      JSON.stringify(value);
  });

  // 5) Construct and send the multicast message
  const message = {
    tokens,
    notification: {title, body},
    data: dataPayload,
    android: {
      priority: 'high',
      notification: {
        channelId: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
          'food_orders_high' :
          'high_importance_channel',
        sound: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
          'order_alert' :
          'default',
        icon: 'ic_notification',
      },
    },
    apns: {
      headers: {'apns-priority': '10'},
      payload: { aps: {
        sound: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
          'order_alert.caf' :
          'default',
        badge: 1,
      }},
    },
  };

  console.log(
    `→ Sending localized notification (${locale}/${type}) to ${tokens.length} tokens`,
    {title, body, route},
  );

  let batchResponse;
  try {
    batchResponse = await getMessaging().sendEachForMulticast(message);
    console.log(
      `FCM: ${batchResponse.successCount}/${tokens.length} delivered, ${batchResponse.failureCount} failed`,
    );
  } catch (err) {
    console.error('FCM send error', err);
    throw err;
  }

  // 6) Clean up invalid tokens
  const badTokens = [];
  batchResponse.responses.forEach((resp, i) => {
    if (resp.error) {
      const code = resp.error.code;
      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        badTokens.push(tokens[i]);
      }
    }
  });
  if (badTokens.length) {
    console.log('Removing invalid tokens:', badTokens);
    const updates = {};
    badTokens.forEach((token) => {
      updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
    });
    await admin.firestore()
      .doc(`users/${userId}`)
      .update(updates);
  }
});

export const sendRestaurantNotificationOnCreation = onDocumentCreated({
  region: 'europe-west3',
  document: 'restaurant_notifications/{notificationId}',
  memory: '512MiB',
  timeoutSeconds: 60,
}, async (event) => {
  const snap = event.data;
  const notificationData = snap?.data();
  const { notificationId } = event.params;

  if (!notificationData) {
    console.log('No notification data, exiting.');
    return;
  }

  const ownerId = notificationData.restaurantOwnerId;
  if (!ownerId) {
    console.log('No restaurantOwnerId in notification, exiting.');
    return;
  }

  // Idempotency guard
  const notifRef = admin.firestore()
    .collection('restaurant_notifications')
    .doc(notificationId);

  try {
    const shouldProcess = await admin.firestore().runTransaction(async (tx) => {
      const doc = await tx.get(notifRef);
      if (doc.data()?.fcmSent === true) return false;
      tx.update(notifRef, { fcmSent: true });
      return true;
    });

    if (!shouldProcess) {
      console.log(`FCM already sent for restaurant notification ${notificationId}, skipping.`);
      return;
    }
  } catch (error) {
    console.error(`Idempotency check failed for ${notificationId}:`, error);
    return;
  }

  // Load owner's FCM tokens and locale
  const userDoc = await admin.firestore().doc(`users/${ownerId}`).get();
  const userData = userDoc.data() || {};
  const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];

  if (tokens.length === 0) {
    console.log(`No FCM tokens for restaurant owner ${ownerId}.`);
    return;
  }

  const locale = ['en', 'tr', 'ru'].includes(userData.languageCode) ? userData.languageCode : 'en';

  // Pick and interpolate template
  const type = notificationData.type || 'default';
  const localeSet = TEMPLATES[locale] || TEMPLATES.en;
  const tmpl = localeSet[type] || localeSet.default;

  let title = tmpl.title;
  let body  = tmpl.body;

  const replacements = {
    '{buyerName}': notificationData.buyerName,
    '{itemCount}': notificationData.itemCount,
    '{totalPrice}': notificationData.totalPrice,
    '{restaurantName}': notificationData.restaurantName,
    '{orderId}': notificationData.orderId,
    '{rating}': notificationData.rating,
  };

  Object.entries(replacements).forEach(([placeholder, value]) => {
    if (value !== undefined && value !== null) {
      title = title.replace(placeholder, String(value));
      body  = body .replace(placeholder, String(value));
    }
  });

  let route;
  const restaurantId = notificationData.restaurantId ?? '';
  
  if (type === 'new_food_order') {
    // Opens SellerPanel → restaurant mode → tab 1 (FoodOrdersTab)
    route = `/seller-panel?shopId=${restaurantId}&tab=1`;
  } else if (type === 'restaurant_new_review') {
    // Opens SellerPanel → restaurant mode → tab 2 (RestaurantReviewsTab)
    route = `/seller-panel?shopId=${restaurantId}&tab=2`;
  } else {
    // Fallback for any future restaurant notification types
    route = restaurantId ? `/seller-panel?shopId=${restaurantId}&tab=0` : '/seller-panel';
  }

  // Data payload
  const dataPayload = {
    notificationId: String(notificationId),
    route,
    type,
  };
  Object.entries(notificationData).forEach(([key, value]) => {
    if (key === 'isRead' || key === 'timestamp' || key === 'route') return;
    dataPayload[key] = typeof value === 'string' ? value : JSON.stringify(value);
  });

  // Send — batch if somehow >500 tokens (defensive)
  const FCM_BATCH_SIZE = 500;
  let successCount = 0;
  let failureCount = 0;
  const badTokens = [];

  for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
    const batch = tokens.slice(i, i + FCM_BATCH_SIZE);
    const message = {
      tokens: batch,
      notification: { title, body },
      data: dataPayload,
      android: {
        priority: 'high',
        notification: {
          channelId: type === 'new_food_order' || type === 'restaurant_new_review' ?
            'food_orders_high' :
            'high_importance_channel',
          sound: type === 'new_food_order' || type === 'restaurant_new_review' ?
            'order_alert' :
            'default',
          icon: 'ic_notification',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: {
          sound: type === 'new_food_order' || type === 'restaurant_new_review' ?
            'order_alert.caf' :
            'default',
          badge: 1,
        }},
      },
    };

    try {
      const batchResponse = await getMessaging().sendEachForMulticast(message);
      successCount += batchResponse.successCount;
      failureCount += batchResponse.failureCount;

      batchResponse.responses.forEach((resp, idx) => {
        if (resp.error) {
          const code = resp.error.code;
          if (
            code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered'
          ) {
            badTokens.push(batch[idx]);
          }
        }
      });
    } catch (err) {
      console.error('FCM send error for restaurant notification:', err);
      failureCount += batch.length;
    }
  }

  // Update stats
  await notifRef.update({
    fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
    fcmStats: { successCount, failureCount, totalTokens: tokens.length },
  });

  // Clean up bad tokens
  if (badTokens.length > 0) {
    const updates = {};
    badTokens.forEach((token) => {
      updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
    });
    await admin.firestore().doc(`users/${ownerId}`).update(updates).catch((err) => {
      console.error('Failed to clean bad tokens:', err);
    });
  }

  console.log(
    `Restaurant notification ${notificationId} (${type}) → ${successCount} sent, ${failureCount} failed`
  );
});

function getWebRoute(type, shopId, orderId) {
  switch (type) {
    case 'product_sold':
      return '/orders';
    case 'product_out_of_stock_seller_panel':
      return '/stock';
    case 'product_review_shop':
    case 'seller_review_shop':
      return `/reviews/${shopId}`;
    case 'product_question':
      return `/productquestions/${shopId}`;
    case 'product_archived_by_admin':
      return `/archived/${shopId}`;
    case 'boost_expired':
      return '/boostanalysis';
    case 'ad_approved':
    case 'ad_rejected':
    case 'ad_expired':
      return `/homescreen-ads`;
    default:
      return '/dashboard';
  }
}

export const sendShopNotificationOnCreation = onDocumentCreated({
  region: 'europe-west3',
  document: 'shop_notifications/{notificationId}',
  memory: '256MiB',
  timeoutSeconds: 60,
}, async (event) => {
  const snap = event.data;
  const notificationData = snap?.data();
  const { notificationId } = event.params;

  if (!notificationData) {
    console.log('No notification data, exiting.');
    return;
  }

  const shopId = notificationData.shopId;
  if (!shopId) {
    console.log('No shopId in notification, exiting.');
    return;
  }

  // Atomic idempotency check - prevent duplicate sends on retry
  const notificationRef = admin.firestore().collection('shop_notifications').doc(notificationId);
  
  try {
    const shouldProcess = await admin.firestore().runTransaction(async (transaction) => {
      const currentDoc = await transaction.get(notificationRef);
      
      if (currentDoc.data()?.fcmSent === true) {
        // Already sent, skip
        return false;
      }
      
      // Mark as sent atomically BEFORE processing to prevent duplicates
      transaction.update(notificationRef, { fcmSent: true });
      return true;
    });

    if (!shouldProcess) {
      console.log(`FCM already sent for ${notificationId}, skipping.`);
      return;
    }
  } catch (error) {
    // If transaction fails (e.g., doc doesn't exist), log and exit
    console.error(`Idempotency transaction failed for ${notificationId}:`, error);
    return;
  }

  // 1) Get shop to find all members
  const shopDoc = await admin.firestore().doc(`shops/${shopId}`).get();
  const shopData = shopDoc.data();
  if (!shopData) {
    console.log(`Shop ${shopId} not found.`);
    return;
  }

  // 2) Collect all member IDs
  const memberIds = new Set();
  if (shopData.ownerId) memberIds.add(shopData.ownerId);
  if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach((id) => memberIds.add(id));
  if (Array.isArray(shopData.editors)) shopData.editors.forEach((id) => memberIds.add(id));
  if (Array.isArray(shopData.viewers)) shopData.viewers.forEach((id) => memberIds.add(id));

  if (memberIds.size === 0) {
    console.log(`No members found for shop ${shopId}.`);
    return;
  }

  console.log(`Found ${memberIds.size} members for shop ${shopId}`);

  // 3) Fetch all members' user documents in parallel
  const memberDocs = await Promise.all(
    Array.from(memberIds).map((id) => admin.firestore().doc(`users/${id}`).get())
  );

  // 4) Group tokens by locale for efficient batch sending
  const tokensByLocale = {
    en: [],
    tr: [],
    ru: [],
  };

  const tokenToUserMap = new Map(); // For cleanup later

  for (const doc of memberDocs) {
    if (!doc.exists) continue;
    const userData = doc.data();
    const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];
    
    if (tokens.length === 0) continue;

    const locale = userData.languageCode || 'en';
    const validLocale = ['en', 'tr', 'ru'].includes(locale) ? locale : 'en';

    tokens.forEach((token) => {
      tokensByLocale[validLocale].push(token);
      tokenToUserMap.set(token, doc.id);
    });
  }

  const totalTokens = Object.values(tokensByLocale).flat().length;
  if (totalTokens === 0) {
    console.log('No FCM tokens found for any shop members.');
    await notificationRef.update({ 
      fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
      fcmStats: { successCount: 0, failureCount: 0, totalTokens: 0 },
    });
    return;
  }

  console.log(`Sending to ${totalTokens} tokens across ${memberIds.size} members`);

  // 5) Determine route for deep linking
  const type = notificationData.type || 'default';
  let route = `/seller-panel?shopId=${shopId}`;
  
  switch (type) {
    case 'product_sold':
      route = `/seller-panel?shopId=${shopId}&tab=3`;
      break;
    case 'product_review_shop':
    case 'seller_review_shop':
      route = `/seller_panel_reviews/${shopId}`;
      break;
    case 'product_question':
      route = `/seller_panel_product_questions/${shopId}`;
      break;
    case 'product_out_of_stock_seller_panel':
      route = `/seller-panel?shopId=${shopId}&tab=2`;
      break;
    case 'boost_expired':
      route = `/seller-panel?shopId=${shopId}&tab=5`;
      break;
      case 'product_archived_by_admin':
  route = `/seller_panel_archived_screen`;
  break;
    case 'campaign_ended':
      route = `/seller-panel?shopId=${shopId}&tab=0`;
      break;
    case 'ad_approved':
    case 'ad_rejected':
    case 'ad_expired':
      route = `/seller-panel?shopId=${shopId}&tab=5`; 
      break;
  }

  // Web URL for click action (computed once)
  const webBaseUrl = 'https://nar24panel.com';
  const webRoute = getWebRoute(type, shopId, notificationData.orderId);
  const webClickAction = `${webBaseUrl}${webRoute}`;

  // 6) Build data payload
  const dataPayload = {
    notificationId: String(notificationId),
    route,
    shopId,
    type,
    webRoute,
  };
  
  Object.entries(notificationData).forEach(([key, value]) => {
    if (key === 'isRead' || key === 'timestamp') return;
    dataPayload[key] = typeof value === 'string' ? value : JSON.stringify(value);
  });

  // 7) Send notifications grouped by locale
  const badTokens = [];
  let successCount = 0;
  let failureCount = 0;

  for (const [locale, tokens] of Object.entries(tokensByLocale)) {
    if (tokens.length === 0) continue;

    // Get localized template
    const localeSet = TEMPLATES[locale] || TEMPLATES.en;
    const tmpl = localeSet[type] || localeSet.default;

    // Interpolate template
    let title = tmpl.title;
    let body = tmpl.body;

    const replacements = {
      '{productName}': notificationData.productName,
      '{shopName}': notificationData.shopName,
      '{buyerName}': notificationData.buyerName,
      '{campaignName}': notificationData.campaignName,
      '{quantity}': notificationData.quantity,
      '{rating}': notificationData.rating,
      '{rejectionReason}': notificationData.rejectionReason,
    };

    Object.entries(replacements).forEach(([placeholder, value]) => {
      if (value !== undefined && value !== null) {
        title = title.replace(placeholder, String(value));
        body = body.replace(placeholder, String(value));
      }
    });

    // FCM has a 500 token limit per multicast call
    const FCM_BATCH_SIZE = 500;
    const tokenBatches = [];
    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
      tokenBatches.push(tokens.slice(i, i + FCM_BATCH_SIZE));
    }

    for (const tokenBatch of tokenBatches) {
      const message = {
        tokens: tokenBatch,
        notification: { title, body },
        data: dataPayload,
        
        // iOS Configuration
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: {
              sound: 'order_alert.caf',
              badge: 1,
              mutableContent: 1,
            }
          },
        },
        
        // Android Configuration
        android: {
          priority: 'high',
          notification: {
            channelId: 'food_orders_high',
            sound: 'order_alert',
            icon: 'ic_notification',
          },
        },
        
        // Web Push Configuration
        webpush: {
          headers: {
            Urgency: 'high',
          },
          notification: {
            title,
            body,
            icon: `${webBaseUrl}/icons/notification-icon-192.png`,
            badge: `${webBaseUrl}/icons/notification-badge-72.png`,
            tag: `shop-${shopId}-${type}`,
            renotify: true,
            requireInteraction: type === 'product_sold',
            actions: [
              {
                action: 'open',
                title: locale === 'tr' ? 'Görüntüle' : locale === 'ru' ? 'Открыть' : 'View',
              },
              {
                action: 'dismiss',
                title: locale === 'tr' ? 'Kapat' : locale === 'ru' ? 'Закрыть' : 'Dismiss',
              },
            ],
          },
          fcmOptions: {
            link: webClickAction,
          },
        },
      };

      console.log(
        `→ Sending shop notification (${locale}/${type}) to ${tokenBatch.length} tokens`,
        { title, body, route, webClickAction }
      );

      try {
        const batchResponse = await getMessaging().sendEachForMulticast(message);
        successCount += batchResponse.successCount;
        failureCount += batchResponse.failureCount;

        console.log(
          `FCM [${locale}]: ${batchResponse.successCount}/${tokenBatch.length} delivered`
        );

        // Collect bad tokens
        batchResponse.responses.forEach((resp, i) => {
          if (resp.error) {
            const code = resp.error.code;
            if (
              code === 'messaging/invalid-registration-token' ||
              code === 'messaging/registration-token-not-registered'
            ) {
              badTokens.push(tokenBatch[i]);
            }
          }
        });
      } catch (err) {
        console.error(`FCM send error for locale ${locale}:`, err);
        failureCount += tokenBatch.length;
      }
    }
  }

  // 8) Update notification with stats (fcmSent already set by transaction)
  await notificationRef.update({ 
    fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
    fcmStats: { successCount, failureCount, totalTokens },
  });

  // 9) Clean up invalid tokens
  if (badTokens.length > 0) {
    console.log(`Removing ${badTokens.length} invalid tokens`);
    
    const tokensByUser = new Map();
    badTokens.forEach((token) => {
      const userId = tokenToUserMap.get(token);
      if (userId) {
        if (!tokensByUser.has(userId)) {
          tokensByUser.set(userId, []);
        }
        tokensByUser.get(userId).push(token);
      }
    });

    const cleanupPromises = [];
    for (const [userId, userTokens] of tokensByUser) {
      const updates = {};
      userTokens.forEach((token) => {
        updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
      });
      cleanupPromises.push(
        admin.firestore().doc(`users/${userId}`).update(updates).catch((err) => {
          console.error(`Failed to clean tokens for user ${userId}:`, err);
        })
      );
    }
    
    await Promise.all(cleanupPromises);
  }

  console.log(`Shop notification ${notificationId} complete: ${successCount} sent, ${failureCount} failed`);
});

// Background function to generate receipts
export const generateReceiptBackground = onDocumentCreated(
  {
    document: 'receiptTasks/{taskId}',
    region: 'europe-west3',
    memory: '1GB', // More memory for PDF generation
    timeoutSeconds: 120,
  },
  async (event) => {
    const taskData = event.data.data();
    const taskId = event.params.taskId;
    const db = admin.firestore();

    try {
      // Convert Firestore timestamp to Date
      const orderDate = taskData.orderDate.toDate ? taskData.orderDate.toDate() : new Date();

      // Generate PDF with converted date
      const receiptData = {
        ...taskData,
        orderDate,
      };

      const receiptPdf = await generateReceipt(receiptData);

      // Save to storage
      const bucket = admin.storage().bucket();
      const receiptFileName = `receipts/${taskData.orderId}.pdf`;
      const file = bucket.file(receiptFileName);

      await file.save(receiptPdf, {
        metadata: {
          contentType: 'application/pdf',
        },
      });

      const filePath = receiptFileName;

      let receiptRef;
      
      if (taskData.ownerType === 'shop') {
        // Create receipt in shop's receipts collection
        receiptRef = db.collection('shops')
          .doc(taskData.ownerId)
          .collection('receipts')
          .doc();
      } else {
        // Create receipt in user's receipts collection
        receiptRef = db.collection('users')
          .doc(taskData.ownerId)
          .collection('receipts')
          .doc();
      }

      const receiptDocument = {
        receiptId: receiptRef.id,
        receiptType: taskData.receiptType || 'order', // 'order' or 'boost'
        orderId: taskData.orderId,
        buyerId: taskData.buyerId,
        totalPrice: taskData.totalPrice,
        itemsSubtotal: taskData.itemsSubtotal,
        deliveryPrice: taskData.deliveryPrice || 0,
        currency: taskData.currency,
        paymentMethod: taskData.paymentMethod,
        deliveryOption: taskData.deliveryOption || 'normal',
        couponCode: taskData.couponCode || null,
        couponDiscount: taskData.couponDiscount || 0,
        freeShippingApplied: taskData.freeShippingApplied || false,
        originalDeliveryPrice: taskData.originalDeliveryPrice || 0,
        totalSavings: (taskData.couponDiscount || 0) + 
          (taskData.freeShippingApplied ? (taskData.originalDeliveryPrice || 0) : 0),
        filePath,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Add boost-specific fields if it's a boost receipt
      if (taskData.receiptType === 'boost' && taskData.boostData) {
        receiptDocument.boostDuration = taskData.boostData.boostDuration;
        receiptDocument.itemCount = taskData.boostData.itemCount;
      }

      // Add ad-specific fields if it's an ad receipt
if (taskData.receiptType === 'ad' && taskData.adData) {
  receiptDocument.adType = taskData.adData.adType;
  receiptDocument.adDuration = taskData.adData.duration;
}

      // Add delivery info for regular orders
      if (taskData.deliveryOption === 'pickup' && taskData.pickupPoint) {
        receiptDocument.pickupPointName = taskData.pickupPoint.name;
        receiptDocument.pickupPointAddress = taskData.pickupPoint.address;
      } else if (taskData.buyerAddress) {
        receiptDocument.deliveryAddress = `${taskData.buyerAddress.addressLine1}, ${taskData.buyerAddress.city}`;
      }

      await receiptRef.set(receiptDocument);

      // Mark task as complete
      await db.collection('receiptTasks').doc(taskId).update({
        status: 'completed',
        filePath,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Receipt generated successfully for ${taskData.receiptType || 'order'} ${taskData.orderId}`);
    } catch (error) {
      console.error('Error generating receipt:', error);

      // Mark task as failed with retry count
      const taskRef = db.collection('receiptTasks').doc(taskId);
      const taskDoc = await taskRef.get();
      const retryCount = (taskDoc.data()?.retryCount || 0) + 1;

      await taskRef.update({
        status: retryCount >= 3 ? 'failed' : 'pending',
        retryCount,
        lastError: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // If permanently failed, log to payment alerts
      if (retryCount >= 3) {
        logTaskFailureAlert('receipt_generation', taskData.orderId, taskData.buyerId, taskData.buyerName, error);
      }

      // If under retry limit, throw error to trigger function retry
      if (retryCount < 3) {
        throw error;
      }
    }
  },
);

async function generateReceipt(data) {
  const lang = data.language || 'en';

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: 'A4',
      margin: 50,
      bufferPages: true,
      compress: true,
    });

    const chunks = [];

    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => {
      const result = Buffer.concat(chunks);
      chunks.length = 0;
      resolve(result);
    });
    doc.on('error', reject);

    // Register Inter fonts that support Turkish characters
    const fontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
    const fontBoldPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');

    doc.registerFont('Inter', fontPath);
    doc.registerFont('Inter-Bold', fontBoldPath);

    const titleFont = 'Inter-Bold';
    const normalFont = 'Inter';

    // Localized text labels
    const labels = {
      en: {
        title: 'Nar24 Receipt',
        orderInfo: 'Order Information',
        buyerInfo: 'Buyer Information',
        pickupInfo: 'Pickup Point Information',
        purchasedItems: 'Purchased Items',
        orderId: 'Order ID',
        date: 'Date',
        paymentMethod: 'Payment Method',
        deliveryOption: 'Delivery Option',
        name: 'Name',
        phone: 'Phone',
        address: 'Address',
        city: 'City',
        deliveryPrice: 'Delivery',
        subtotal: 'Subtotal',
        free: 'Free',
        pickupName: 'Pickup Point',
        couponDiscount: 'Coupon Discount',
    freeShippingBenefit: 'Free Shipping Benefit',    
        pickupAddress: 'Address',
        pickupPhone: 'Contact Phone',
        pickupHours: 'Operating Hours',
        pickupContact: 'Contact Person',
        pickupNotes: 'Notes',
        seller: 'Seller',
        product: 'Product',
        attributes: 'Attributes',
        qty: 'Qty',
        unitPrice: 'Unit Price',
        total: 'Total',
        footer: 'This is a computer-generated receipt and does not require a signature.',
        boostDuration: 'Boost Duration',
    boostedItems: 'Boosted Items',
    duration: 'Duration',
    shopName: 'Shop Name',
    adType: 'Ad Type',
tax: 'Tax (20%)',
      },
      tr: {
        title: 'Nar24 Fatura',
        orderInfo: 'Sipariş Bilgileri',
        buyerInfo: 'Alıcı Bilgileri',
        pickupInfo: 'Gel-Al Noktası Bilgileri',
        purchasedItems: 'Satın Alınan Ürünler',
        orderId: 'Sipariş No',
        date: 'Tarih',
        paymentMethod: 'Ödeme Yöntemi',
        deliveryOption: 'Teslimat Seçeneği',
        name: 'Ad-Soyad',
        phone: 'Telefon',
        address: 'Adres',
        city: 'Şehir',
        deliveryPrice: 'Kargo',
        subtotal: 'Ara Toplam',
        free: 'Ücretsiz',
        pickupName: 'Gel-Al Noktası',
        pickupAddress: 'Adres',
        couponDiscount: 'Kupon İndirimi',
        freeShippingBenefit: 'Ücretsiz Kargo Avantajı',
        pickupPhone: 'İletişim Telefonu',
        pickupHours: 'Çalışma Saatleri',
        pickupContact: 'İletişim Kişisi',
        pickupNotes: 'Notlar',
        seller: 'Satıcı',
        product: 'Ürün',
        attributes: 'Özellikler',
        qty: 'Adet',
        unitPrice: 'Birim Fiyat',
        total: 'Toplam',
        footer: 'Bu bilgisayar tarafından oluşturulan bir makbuzdur ve imza gerektirmez.',
        boostDuration: 'Boost Süresi',
        boostedItems: 'Boost Edilen',
        duration: 'Süre',
        shopName: 'Dükkan İsmi',
        adType: 'Reklam Türü',
tax: 'KDV (%20)',
      },
      ru: {
        title: 'Nar24 Счет',
        orderInfo: 'Информация о заказе',
        buyerInfo: 'Информация о покупателе',
        pickupInfo: 'Информация о пункте выдачи',
        purchasedItems: 'Купленные товары',
        orderId: 'Номер заказа',
        date: 'Дата',
        paymentMethod: 'Способ оплаты',
        deliveryOption: 'Вариант доставки',
        name: 'Имя',
        phone: 'Телефон',
        address: 'Адрес',
        city: 'Город',
        couponDiscount: 'Скидка по купону',
        freeShippingBenefit: 'Бесплатная доставка',
        pickupName: 'Пункт выдачи',
        pickupAddress: 'Адрес',
        pickupPhone: 'Контактный телефон',
        pickupHours: 'Часы работы',
        deliveryPrice: 'Доставка',
        subtotal: 'Промежуточный итог',
        free: 'Бесплатно',
        pickupContact: 'Контактное лицо',
        pickupNotes: 'Примечания',
        seller: 'Продавец',
        product: 'Товар',
        attributes: 'Характеристики',
        qty: 'Кол-во',
        unitPrice: 'Цена за единицу',
        total: 'Итого',
        footer: 'Это компьютерный чек и не требует подписи.',
        boostDuration: 'Длительность буста',
        boostedItems: 'Усиленные товары',
        duration: 'Длительность',
        shopName: 'Название магазина',
        adType: 'Тип рекламы',
tax: 'Налог (20%)',
      },
    };

    const t = labels[lang] || labels.en;

    // Header with logo and title
    doc.fontSize(24)
      .font(titleFont)
      .text(t.title, 50, 50);

    // Add logo on the right side
    try {
      const logoPath = path.join(__dirname, 'siyahlogo.png');
      doc.image(logoPath, 460, 0, {width: 70});
    } catch (err) {
      console.log('Logo not found:', err);
    }

    // Divider line
    doc.moveTo(50, 100)
      .lineTo(550, 100)
      .strokeColor('#e0e0e0')
      .lineWidth(1)
      .stroke();

    // Order Information Section - LEFT COLUMN
    doc.fontSize(14)
      .fillColor('#333')
      .font(titleFont)
      .text(t.orderInfo, 50, 115);

    // Format date based on language
    const dateOptions = {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    };
    const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
    const formattedDate = data.orderDate.toLocaleDateString(locale, dateOptions);

    // LEFT COLUMN - Order details
    const leftColumnX = 50;
    const rightColumnX = 320;
    const labelWidth = 110;
    const valueX = leftColumnX + labelWidth;

    doc.fontSize(10)
      .font(normalFont)
      .fillColor('#666');

    // Order ID row
    doc.text(`${t.orderId}:`, leftColumnX, 140, {width: labelWidth, align: 'left'})
      .fillColor('#000')
      .font(titleFont)
      .text(data.orderId.substring(0, 8).toUpperCase(), valueX, 140);

    // Date row
    doc.font(normalFont)
      .fillColor('#666')
      .text(`${t.date}:`, leftColumnX, 160, {width: labelWidth, align: 'left'})
      .fillColor('#000')
      .text(formattedDate, valueX, 160);

    // Payment method row
    let currentY = 180; // DEFINE IT HERE FIRST!
doc.fillColor('#666')
  .text(`${t.paymentMethod}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
  .fillColor('#000')
  .text(data.paymentMethod, valueX, currentY);
currentY += 20;

if (data.receiptType === 'boost' && data.boostData) {
  doc.fillColor('#666')
    .text(`${t.boostDuration}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
    .fillColor('#000')
    .text(`${data.boostData.boostDuration} ${lang === 'tr' ? 'dakika' : lang === 'ru' ? 'минут' : 'minutes'}`, valueX, currentY);
  currentY += 20;
  
  doc.fillColor('#666')
    .text(`${t.boostedItems}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
    .fillColor('#000')
    .text(`${data.boostData.itemCount} ${lang === 'tr' ? 'ürün' : lang === 'ru' ? 'товаров' : 'items'}`, valueX, currentY);
  currentY += 20;
}

// Delivery option (skip for boost receipts)
if (data.receiptType !== 'boost' && data.receiptType !== 'ad') {
  doc.fillColor('#666')
    .text(`${t.deliveryOption}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
    .fillColor('#000')
    .text(formatDeliveryOption(data.deliveryOption, lang), valueX, currentY);
}

// RIGHT COLUMN - Conditional buyer/pickup information
let rightCurrentY = 115;
const buyerLabelWidth = 90;
const buyerValueX = rightColumnX + buyerLabelWidth;

if (data.pickupPoint) {
  // PICKUP POINT INFORMATION
  doc.font(titleFont)
    .fillColor('#333')
    .fontSize(14)
    .text(t.pickupInfo, rightColumnX, rightCurrentY);

  doc.font(normalFont)
    .fontSize(10);
  rightCurrentY += 25;

  // Pickup point details...
  doc.fillColor('#666')
    .text(`${t.pickupName}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
    .fillColor('#000')
    .text(data.pickupPoint.name, buyerValueX, rightCurrentY, {width: 160});
  rightCurrentY += 20;

  doc.fillColor('#666')
    .text(`${t.pickupAddress}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
    .fillColor('#000')
    .text(data.pickupPoint.address, buyerValueX, rightCurrentY, {width: 160});
  rightCurrentY += 20;

  if (data.pickupPoint.phone) {
    doc.fillColor('#666')
      .text(`${t.pickupPhone}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.pickupPoint.phone, buyerValueX, rightCurrentY);
    rightCurrentY += 20;
  }

  doc.fillColor('#666')
    .text(`${t.name}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
    .fillColor('#000')
    .text(data.buyerName, buyerValueX, rightCurrentY);
  rightCurrentY += 20;
} else {
  // BUYER INFORMATION (works for both regular orders and boost receipts)
  doc.font(titleFont)
    .fillColor('#333')
    .fontSize(14)
    .text(t.buyerInfo, rightColumnX, rightCurrentY);

  doc.font(normalFont)
    .fontSize(10);
  rightCurrentY += 25;

 // Buyer name - Use shopName label for boost receipts where owner is a shop
 const nameLabel = ((data.receiptType === 'boost' && data.ownerType === 'shop') || data.receiptType === 'ad') ? t.shopName : t.name;
doc.fillColor('#666')
  .text(`${nameLabel}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
  .fillColor('#000')
  .text(data.buyerName || 'N/A', buyerValueX, rightCurrentY, {width: 160});
  rightCurrentY += 20;

  // Email (for boost receipts)
  if (data.buyerEmail) {
    doc.fillColor('#666')
      .text('Email:', rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.buyerEmail, buyerValueX, rightCurrentY, {width: 160});
    rightCurrentY += 20;
  }

  // Phone - handle both boost and regular order formats
  const phoneNumber = data.buyerPhone || data.buyerAddress?.phoneNumber || 'N/A';
  doc.fillColor('#666')
    .text(`${t.phone}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
    .fillColor('#000')
    .text(phoneNumber, buyerValueX, rightCurrentY);
  rightCurrentY += 20;

  // Only show full address for regular orders (not boost)
  if (data.receiptType !== 'boost' && data.receiptType !== 'ad' && data.buyerAddress) {
    doc.fillColor('#666')
      .text(`${t.address}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.buyerAddress.addressLine1, buyerValueX, rightCurrentY, {width: 160});
    rightCurrentY += 20;

    if (data.buyerAddress.addressLine2) {
      doc.fillColor('#000')
        .text(data.buyerAddress.addressLine2, buyerValueX, rightCurrentY, {width: 160});
      rightCurrentY += 20;
    }

    doc.fillColor('#666')
      .text(`${t.city}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.buyerAddress.city, buyerValueX, rightCurrentY);
    rightCurrentY += 20;
  }
}

    // Items section
    let yPosition = Math.max(rightCurrentY + 20, 240);

    doc.moveTo(50, yPosition)
      .lineTo(550, yPosition)
      .strokeColor('#e0e0e0')
      .lineWidth(1)
      .stroke();

    yPosition += 15;

    doc.fontSize(14)
      .font(titleFont)
      .fillColor('#333')
      .text(t.purchasedItems, 50, yPosition);

    yPosition += 25;

    if (data.receiptType === 'ad' && data.adData) {
      // AD RECEIPT: Simple single-row table
      doc.fontSize(9)
        .font(titleFont)
        .fillColor('#666')
        .text(t.product, 55, yPosition, {width: 200})
        .text(t.duration, 260, yPosition, {width: 100})
        .text(t.unitPrice, 365, yPosition, {width: 70, align: 'right'})
        .text(t.total, 480, yPosition, {width: 65, align: 'right'});
    
      yPosition += 18;
    
      doc.moveTo(55, yPosition - 3)
        .lineTo(545, yPosition - 3)
        .strokeColor('#e0e0e0')
        .lineWidth(0.5)
        .stroke();
    
      doc.font(normalFont)
        .fillColor('#000');
    
      const adTypeLabel = getAdTypeLabel(data.adData.adType);
      const durationLabel = formatAdDuration(data.adData.duration, lang);
    
      doc.fontSize(9)
        .text(adTypeLabel, 55, yPosition, {width: 200})
        .text(durationLabel, 260, yPosition, {width: 100})
        .text(`${data.itemsSubtotal.toFixed(0)} ${data.currency}`, 365, yPosition, {width: 70, align: 'right'})
        .text(`${data.itemsSubtotal.toFixed(0)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
    
      yPosition += 30;
    } else if (data.receiptType === 'boost' && data.boostData) {
      // BOOST RECEIPT: Simple table header
      doc.fontSize(9)
        .font(titleFont)
        .fillColor('#666')
        .text(t.product, 55, yPosition, {width: 200})
        .text(t.duration, 260, yPosition, {width: 100})
        .text(t.unitPrice, 365, yPosition, {width: 70, align: 'right'})
        .text(t.total, 480, yPosition, {width: 65, align: 'right'});
    
      yPosition += 18;
    
      // Draw line under header
      doc.moveTo(55, yPosition - 3)
        .lineTo(545, yPosition - 3)
        .strokeColor('#e0e0e0')
        .lineWidth(0.5)
        .stroke();
    
      // Render boost items
      doc.font(normalFont)
        .fillColor('#000');
    
      for (const item of data.boostData.items) {
        if (yPosition > 700) {
          doc.addPage();
          yPosition = 50;
        }
        
        doc.fontSize(9)
          .text(item.productName || 'Boost Item', 55, yPosition, {width: 200})
          .text(`${data.boostData.boostDuration} ${lang === 'tr' ? 'dakika' : lang === 'ru' ? 'минут' : 'minutes'}`, 260, yPosition, {width: 100})
          .text(`${item.unitPrice.toFixed(0)} ${data.currency}`, 365, yPosition, {width: 70, align: 'right'})
          .text(`${item.totalPrice.toFixed(0)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
        
        yPosition += 20;
      }
    
      yPosition += 10;
    } else {
      // REGULAR ORDER RECEIPT: Original sellerGroups rendering
      for (const sellerGroup of data.sellerGroups) {
        // Seller header with background
        doc.rect(50, yPosition - 5, 500, 22)
          .fillColor('#f5f5f5')
          .fill();
    
        doc.fontSize(11)
          .font(titleFont)
          .fillColor('#333')
          .text(`${t.seller}: ${sellerGroup.sellerName}`, 55, yPosition);
    
        yPosition += 25;
    
        // Table header
        doc.fontSize(9)
          .font(titleFont)
          .fillColor('#666')
          .text(t.product, 55, yPosition, {width: 140})
          .text(t.attributes, 200, yPosition, {width: 160})
          .text(t.qty, 365, yPosition, {width: 35, align: 'center'})
          .text(t.unitPrice, 405, yPosition, {width: 70, align: 'right'})
          .text(t.total, 480, yPosition, {width: 65, align: 'right'});
    
        yPosition += 18;
    
        // Draw line under header
        doc.moveTo(55, yPosition - 3)
          .lineTo(545, yPosition - 3)
          .strokeColor('#e0e0e0')
          .lineWidth(0.5)
          .stroke();
    
        // Items for this seller
        doc.font(normalFont)
          .fillColor('#000');
    
        for (const item of sellerGroup.items) {
          // Check if we need a new page
          if (yPosition > 700) {
            doc.addPage();
            yPosition = 50;
          }
    
          doc.fontSize(9);
    
          // Product name
          const productName = item.productName || 'Unknown Product';
          doc.text(productName, 55, yPosition, {width: 140});
    
          // Display localized attributes
          const attrs = item.selectedAttributes || {};
          const attrTexts = [];
    
          Object.entries(attrs).forEach(([key, value]) => {
            const systemFields = [
              'productId', 'quantity', 'addedAt', 'updatedAt',
              'sellerId', 'sellerName', 'isShop', 'finalPrice',
              'selectedColorImage', 'productImage',
              'ourComission', 'calculatedTotal', 'calculatedUnitPrice',
              'isBundleItem', 'unitPrice', 'totalPrice', 'currency', 'sellerContactNo',
            ];
    
            if (value && value !== '' && value !== null && !systemFields.includes(key)) {
              const localizedKey = localizeAttributeKey(key, lang);
              const localizedValue = localizeAttributeValue(key, value, lang);
              attrTexts.push(`${localizedKey}: ${localizedValue}`);
            }
          });
    
          const attrText = attrTexts.join(', ');
    
          if (attrText) {
            doc.fontSize(8)
              .fillColor('#666')
              .text(attrText, 200, yPosition, {width: 160});
          } else {
            doc.text('-', 200, yPosition, {width: 160});
          }
    
          // Quantity, unit price, and total
          doc.fontSize(9)
            .fillColor('#000')
            .text(item.quantity.toString(), 365, yPosition, {width: 35, align: 'center'})
            .text(`${item.unitPrice.toFixed(0)} ${data.currency}`, 405, yPosition, {width: 70, align: 'right'})
            .text(`${item.totalPrice.toFixed(0)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
    
          yPosition += 20;
        }
    
        yPosition += 10;
      }
    }

    // Total section
    if (yPosition > 650) {
      doc.addPage();
      yPosition = 50;
    }

    doc.moveTo(50, yPosition)
      .lineTo(550, yPosition)
      .strokeColor('#e0e0e0')
      .lineWidth(1)
      .stroke();

    yPosition += 15;

    // Calculate values FIRST
    const originalDeliveryPrice = data.originalDeliveryPrice || data.deliveryPrice || 0;
const deliveryPrice = data.deliveryPrice || 0;
const couponDiscount = data.couponDiscount || 0;
const freeShippingApplied = data.freeShippingApplied || false;
const subtotal = data.itemsSubtotal || (data.totalPrice - deliveryPrice + couponDiscount);
const grandTotal = data.totalPrice;

    // Subtotal row
    doc.font(titleFont)
      .fontSize(11)
      .fillColor('#666')
      .text(`${t.subtotal}:`, 390, yPosition)
      .fillColor('#333')
      .text(`${subtotal.toFixed(0)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});

    yPosition += 20;

    if (couponDiscount > 0) {
      doc.font(titleFont)
        .fontSize(11)
        .fillColor('#666')
        .text(`${t.couponDiscount}:`, 390, yPosition)
        .fillColor('#00A86B')
        .text(`-${couponDiscount.toFixed(0)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});
    
      yPosition += 20;
    }

    if (data.receiptType !== 'boost' && data.receiptType !== 'ad') {
      // ✅ UPDATED: Show free shipping benefit
      if (freeShippingApplied && originalDeliveryPrice > 0) {
        // Show original price struck through and "Free" 
        doc.font(titleFont)
          .fontSize(11)
          .fillColor('#666')
          .text(`${t.deliveryPrice}:`, 390, yPosition);
        
        // Show original price with strikethrough effect (gray)
        doc.fillColor('#999')
          .text(`${originalDeliveryPrice.toFixed(0)}`, 460, yPosition, {width: 40, align: 'right'});
        
        // Draw strikethrough line
        const textWidth = doc.widthOfString(`${originalDeliveryPrice.toFixed(0)}`);
        doc.moveTo(500 - textWidth, yPosition + 5)
          .lineTo(502, yPosition + 5)
          .strokeColor('#999')
          .lineWidth(1)
          .stroke();
        
        // Show "Free" in green
        doc.fillColor('#00A86B')
          .text(t.free, 505, yPosition, {width: 35, align: 'right'});
        
        yPosition += 18;
        
        // Show benefit label
        doc.fontSize(9)
          .fillColor('#00A86B')
          .text(`✓ ${t.freeShippingBenefit}`, 390, yPosition);
        
        yPosition += 20;
      } else {
        // Normal delivery display (no free shipping benefit)
        const deliveryText = deliveryPrice === 0 ? t.free : `${deliveryPrice.toFixed(0)} ${data.currency}`;
        const deliveryColor = deliveryPrice === 0 ? '#00A86B' : '#333';
    
        doc.font(titleFont)
          .fontSize(11)
          .fillColor('#666')
          .text(`${t.deliveryPrice}:`, 390, yPosition)
          .fillColor(deliveryColor)
          .text(deliveryText, 460, yPosition, {width: 80, align: 'right'});
    
        yPosition += 25;
      }
    }

    // Tax row (for ad receipts)
if (data.receiptType === 'ad' && data.taxAmount) {
  doc.font(titleFont)
    .fontSize(11)
    .fillColor('#666')
    .text(`${t.tax}:`, 390, yPosition)
    .fillColor('#333')
    .text(`${data.taxAmount.toFixed(0)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});

  yPosition += 20;
}
    
    yPosition += 5;
    
    // Divider line
    doc.moveTo(380, yPosition - 5)
      .lineTo(550, yPosition - 5)
      .strokeColor('#333')
      .lineWidth(1.5)
      .stroke();
    
    yPosition += 10;
    
    // Total with background
    doc.rect(380, yPosition - 10, 170, 35)
      .fillColor('#f0f8f0')
      .fill();
    
    doc.font(titleFont)
      .fontSize(14)
      .fillColor('#333')
      .text(`${t.total}:`, 390, yPosition)
      .fillColor('#00A86B')
      .fontSize(16)
      .text(`${grandTotal.toFixed(0)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});

    // Footer
    doc.fontSize(8)
      .font(normalFont)
      .fillColor('#999')
      .text(t.footer, 50, 750, {
        align: 'center',
        width: 500,
      });

    doc.end();
  });
}

function formatAdDuration(duration, lang = 'en') {
  const durations = {
    en: {
      oneWeek: '1 Week',
      twoWeeks: '2 Weeks',
      oneMonth: '1 Month',
    },
    tr: {
      oneWeek: '1 Hafta',
      twoWeeks: '2 Hafta',
      oneMonth: '1 Ay',
    },
    ru: {
      oneWeek: '1 Неделя',
      twoWeeks: '2 Недели',
      oneMonth: '1 Месяц',
    },
  };
  return durations[lang]?.[duration] || durations['en'][duration] || duration;
}


// Helper functions for formatting
function formatDeliveryOption(option, lang = 'en') {
  const options = {
    en: {
      'normal': 'Normal Delivery',
      'express': 'Express Delivery',
    },
    tr: {
      'normal': 'Normal Teslimat',
      'express': 'Express Teslimat',
    },
    ru: {
      'normal': 'Обычная доставка',
      'express': 'Экспресс-доставка',
    },
  };
  return options[lang]?.[option] || options['en'][option] || option;
}

export const moderateImage = onCall(
  {region: 'europe-west3'},
  async (req) => {
    const auth = req.auth;
    if (!auth) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const {imageUrl} = req.data || {};
    
    if (!imageUrl || typeof imageUrl !== 'string') {
      throw new HttpsError('invalid-argument', 'Invalid image URL provided.');
    }

    try {
      const [result] = await visionClient.safeSearchDetection(imageUrl);
      const safeSearch = result.safeSearchAnnotation;

      if (!safeSearch) {
        return {approved: true};
      }

      // ✅ E-commerce appropriate: Only block EXPLICIT content
      // Bikinis, lingerie, fashion = OK
      // Explicit nudity/pornography = NOT OK
      const isInappropriate = 
        safeSearch.adult === 'VERY_LIKELY' || // Only explicit pornography
        safeSearch.violence === 'VERY_LIKELY'; // Only extreme violence
        // Note: We're NOT blocking "racy" at all - swimwear/fashion is fine!

      let rejectionReason = null;
      if (safeSearch.adult === 'VERY_LIKELY') {
        rejectionReason = 'adult_content';
      } else if (safeSearch.violence === 'VERY_LIKELY') {
        rejectionReason = 'violent_content';
      }

      // 🔍 Add logging to see what Vision API returns (helpful for debugging)
      console.log('Vision API results:', {
        adult: safeSearch.adult,
        violence: safeSearch.violence,
        racy: safeSearch.racy,
        approved: !isInappropriate,
      });

      return {
        approved: !isInappropriate,
        rejectionReason,
        details: {
          adult: safeSearch.adult,
          violence: safeSearch.violence,
          racy: safeSearch.racy,
        },
      };
    } catch (error) {
      console.error('Vision API error:', error);
      return {approved: true, error: 'processing_error'};
    }
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

    // Atomic deduplication using transaction
    const deduplicationWindow = 30000; // 30 seconds
    const now = Date.now();
    const dedupeKey = `shop_stock_${productId}`;
    const dedupeRef = admin.firestore().collection('_stock_dedupe').doc(dedupeKey);

    try {
      const shouldProcess = await admin.firestore().runTransaction(async (transaction) => {
        const dedupeDoc = await transaction.get(dedupeRef);

        if (dedupeDoc.exists) {
          const lastProcessed = dedupeDoc.data()?.timestamp || 0;
          if (now - lastProcessed < deduplicationWindow) {
            // Recent duplicate, skip processing
            return false;
          }
        }

        // Either doesn't exist or is old enough - mark as processed atomically
        transaction.set(dedupeRef, {
          timestamp: now,
          productId,
          type: 'shop_product',
        });

        return true;
      });

      if (!shouldProcess) {
        console.log(`Skipping duplicate shop stock notification for product ${productId}`);
        return;
      }
    } catch (error) {
      console.warn('Deduplication transaction failed, proceeding with caution:', error);
      // On transaction failure, we proceed but log the issue
      // This prevents the function from being completely blocked by dedupe failures
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

    // Atomic deduplication using transaction
    const deduplicationWindow = 30000; // 30 seconds
    const now = Date.now();
    const dedupeKey = `general_stock_${productId}`;
    const dedupeRef = admin.firestore().collection('_stock_dedupe').doc(dedupeKey);

    try {
      const shouldProcess = await admin.firestore().runTransaction(async (transaction) => {
        const dedupeDoc = await transaction.get(dedupeRef);

        if (dedupeDoc.exists) {
          const lastProcessed = dedupeDoc.data()?.timestamp || 0;
          if (now - lastProcessed < deduplicationWindow) {
            // Recent duplicate, skip processing
            return false;
          }
        }

        // Either doesn't exist or is old enough - mark as processed atomically
        transaction.set(dedupeRef, {
          timestamp: now,
          productId,
          sellerId,
          type: 'general_product',
        });

        return true;
      });

      if (!shouldProcess) {
        console.log(`Skipping duplicate general stock notification for product ${productId}`);
        return;
      }
    } catch (error) {
      console.warn('Deduplication transaction failed, proceeding with caution:', error);
      // On transaction failure, we proceed but log the issue
      // This prevents the function from being completely blocked by dedupe failures
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

// === getCustomToken Function ===
export const getCustomToken = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 60,
    memory: '128MB',
  },
  async (request) => {
    const {biometricToken} = request.data;

    // 1. Input Validation
    if (!biometricToken || typeof biometricToken !== 'string') {
      console.error('Invalid or missing biometricToken.');
      throw new HttpsError('invalid-argument', 'The function must be called with a valid biometricToken.');
    }

    try {
      // 2. Query Firestore for user with this biometricToken
      const userQuery = await admin
        .firestore()
        .collection('users')
        .where('biometricToken', '==', biometricToken)
        .limit(1)
        .get();

      if (userQuery.empty) {
        console.error('No user with the provided biometricToken.');
        throw new HttpsError('not-found', 'No user found with the provided biometricToken.');
      }

      const userDoc = userQuery.docs[0];
      const userId = userDoc.id;

      // 3. Generate a Firebase Custom Token
      const customToken = await admin.auth().createCustomToken(userId);

      return {customToken};
    } catch (error) {
      console.error('Error generating custom token:', error);
      if (error instanceof HttpsError) {
        throw error; // Re-throw known HttpsErrors
      } else {
        throw new HttpsError('internal', 'Unable to generate token for biometric authentication.');
      }
    }
  },
);

export const setCustomToken = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 60,
    memory: '128MB',
  },
  async (request) => {
    console.log('setCustomToken function invoked.');

    const {userId, biometricToken} = request.data;

    // 1. Input Validation
    if (!userId || typeof userId !== 'string') {
      console.error('Invalid or missing userId.');
      throw new HttpsError('invalid-argument', 'The function must be called with a valid userId.');
    }

    if (!biometricToken || typeof biometricToken !== 'string') {
      console.error('Invalid or missing biometricToken.');
      throw new HttpsError('invalid-argument', 'The function must be called with a valid biometricToken.');
    }

    try {
      console.log(`Attempting to set biometricToken for userId: ${userId}`);

      // 2. Reference to the user document
      const userRef = admin.firestore().collection('users').doc(userId);

      // 3. Check if user exists
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        console.error(`User with ID ${userId} does not exist.`);
        throw new HttpsError('not-found', 'No user found with the provided userId.');
      }

      await userRef.update({
        biometricToken: biometricToken,
        useBiometric: true, // Ensure useBiometric is set to true
      });

      console.log(`Biometric token set successfully for user ${userId}.`);

      return {success: true};
    } catch (error) {
      console.error('Error setting biometricToken:', error);
      throw new HttpsError('internal', 'Unable to set biometric token.');
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

// Near the bottom of index.js:

export const registerUserWithReferral = onCall(
  {region: 'europe-west3'}, // or your region
  async (request) => {
    console.log('registerUserWithReferral called with data:', request.data);

    // 1) Parse input
    const {email, password, name, surname, referralCode, gender, birthYear} = request.data;

    // 2) Basic validation
    if (!email || typeof email !== 'string') {
      throw new HttpsError('invalid-argument', 'invalid email');
    }
    if (!password || typeof password !== 'string' || password.length < 6) {
      throw new HttpsError('invalid-argument', 'invalid password min 6 chars');
    }
    if (!name || typeof name !== 'string') {
      throw new HttpsError('invalid-argument', 'invalid name');
    }
    if (!surname || typeof surname !== 'string') {
      throw new HttpsError('invalid-argument', 'invalid surname');
    }

    // 3) Create user in Firebase Auth (admin SDK)
    let userRecord;
    try {
      userRecord = await admin.auth().createUser({
        email,
        password,
        displayName: `${name.trim()} ${surname.trim()}`,
      });
    } catch (error) {
      console.error('Error creating user in Auth:', error);
      // Convert error to an HttpsError if you like
      throw new HttpsError('internal', 'Failed to create user');
    }

    // 4) Build user doc data
    const userData = {
      displayName: `${name.trim()} ${surname.trim()}`,
      email: userRecord.email ?? '',
      isNew: true,
      gender: gender || '',
      birthYear: birthYear || 0,
      referralCode: userRecord.uid,
      verified: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // If referral code was provided, store it
    if (referralCode && typeof referralCode === 'string' && referralCode.trim() !== '') {
      userData.referrerId = referralCode.trim();
    }

    // 5) Create user doc in Firestore
    const userDocRef = admin.firestore().collection('users').doc(userRecord.uid);
    try {
      await userDocRef.set(userData);
    } catch (error) {
      console.error('Error creating user document:', error);
      // Attempt to clean up the auth user if needed
      await admin.auth().deleteUser(userRecord.uid);
      throw new HttpsError('internal', 'Failed to create user doc');
    }

    // If referral code was provided, update the inviter's subcollection
    if (referralCode && typeof referralCode === 'string' && referralCode.trim() !== '') {
      const inviterDocRef = admin.firestore().collection('users').doc(referralCode.trim());
      const referralDocRef = inviterDocRef.collection('referral').doc(userRecord.uid);

      // Add extra fields if you like
      const referralData = {
        email: userRecord.email,
        registeredAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      try {
        await referralDocRef.set(referralData);
      } catch (error) {
        console.warn('Failed to update inviter:', error);
        // Not a fatal error, you can handle or ignore
      }
    }

    // 7) (Optional) Send email verification link

    try {
      const actionCodeSettings = {
        url: 'https://emlak-mobile-app.web.app/emailVerified',
        // This is the deep link your user will open after verifying
        handleCodeInApp: true,
      };
      const link = await admin.auth().generateEmailVerificationLink(userRecord.email, actionCodeSettings);
      console.log('Email verification link generated:', link);
      // Send the link to the user's email yourself or via sendGrid
    } catch (error) {
      console.error('Error sending email verification link:', error);
      // Not necessarily fatal
    }

    // 8) Generate a custom token so the client can sign in
    let customToken;
    try {
      customToken = await admin.auth().createCustomToken(userRecord.uid);
      console.log('Custom token generated for user:', userRecord.uid);
    } catch (error) {
      console.error('Error generating custom token:', error);
      // Clean up or handle as needed
      await admin.auth().deleteUser(userRecord.uid);
      throw new HttpsError('internal', 'Failed to generate custom token');
    }

    // Return the token to the client
    return {customToken};
  },
);


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
    cors: {
      origin: [
        'http://localhost:3000', // Dev origin
        'https://adaexpress.co', // Production origin(s)
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
      const db = admin.firestore();
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
      origin: ['http://localhost:3000', 'https://adaexpress.co'],
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
      origin: ['http://localhost:3000', 'https://adaexpress.co'],
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


export const registerWithEmailPassword = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {
      email,
      password,
      name,
      surname,
      gender,
      birthDate,
      referralCode,
      languageCode = 'en', // Default to English if not provided
    } = request.data;

    // 1) Basic validation
    if (
      !email || typeof email !== 'string' ||
      !password || typeof password !== 'string' ||
      !name || typeof name !== 'string' ||
      !surname || typeof surname !== 'string'
    ) {
      throw new HttpsError(
        'invalid-argument',
        'email (string), password (min 6 chars), name & surname are required',
      );
    }

    if (password.length < 8) {
      throw new HttpsError(
        'invalid-argument',
        'Password must be at least 8 characters long',
      );
    }

    if (!/[A-Z]/.test(password)) {
      throw new HttpsError(
        'invalid-argument',
        'Password must contain at least one uppercase letter',
      );
    }

    if (!/[a-z]/.test(password)) {
      throw new HttpsError(
        'invalid-argument',
        'Password must contain at least one lowercase letter',
      );
    }

    if (!/[0-9]/.test(password)) {
      throw new HttpsError(
        'invalid-argument',
        'Password must contain at least one number',
      );
    }

    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
      throw new HttpsError(
        'invalid-argument',
        'Password must contain at least one special character',
      );
    }

    let userRecord;
    try {
      // 2) Create the Auth user
      userRecord = await admin.auth().createUser({
        email,
        password,
        displayName: `${name.trim()} ${surname.trim()}`,
        emailVerified: false, // Explicitly set to false initially
      });
    } catch (err) {
      throw new HttpsError('internal', 'Auth.createUser failed: ' + err.message);
    }

    const uid = userRecord.uid;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // 3) Build the Firestore profile
    const profileData = {
      displayName: `${name.trim()} ${surname.trim()}`,
      email,
      isNew: true,
      isVerified: false,
      referralCode: uid,
      createdAt: now,
      languageCode, // Store the language preference
    };
    if (gender) profileData.gender = gender;
    if (birthDate) {
      const d = new Date(birthDate);
      if (!isNaN(d.getTime())) {
        profileData.birthDate = admin.firestore.Timestamp.fromDate(d);
      } else {
        throw new HttpsError(
          'invalid-argument',
          `birthDate must be a valid ISO string, got "${birthDate}"`,
        );
      }
    }

    try {
      await admin.firestore()
        .collection('users')
        .doc(uid)
        .set(profileData, {merge: true});

      // 4) If a referralCode was provided, record it
      if (referralCode) {
        await admin.firestore()
          .collection('users')
          .doc(referralCode.trim())
          .collection('referral')
          .doc(uid)
          .set({
            email,
            registeredAt: now,
          });
      }
    } catch (err) {
      await admin.auth().deleteUser(uid).catch(() => {});
      throw new HttpsError('internal', 'Firestore write failed: ' + err.message);
    }

    // 5) Generate verification code and send email via SendGrid
    let emailSent = false;
    let verificationCode = '';

    try {
      // Generate 6-digit verification code
      verificationCode = Math.floor(100000 + Math.random() * 900000).toString();

      // Store verification code in Firestore with expiration
      await admin.firestore()
        .collection('emailVerificationCodes')
        .doc(uid)
        .set({
          code: verificationCode,
          email,
          createdAt: now,
          expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)), // 5 minutes
          used: false,
        });

      // Send verification email via SendGrid using mail collection
      await sendVerificationEmail(email, verificationCode, languageCode, `${name.trim()} ${surname.trim()}`);
      emailSent = true;

      console.log(`Email verification sent to ${email} (user ${uid}) in ${languageCode}`);
    } catch (err) {
      console.warn('Could not send email verification:', err);
      // Don't throw error - continue with registration
    }

    // 6) Mint a Custom Token
    let customToken;
    try {
      customToken = await admin.auth().createCustomToken(uid);
    } catch (err) {
      throw new HttpsError('internal', 'Custom token creation failed: ' + err.message);
    }

    return {
      uid,
      customToken,
      emailSent,
      verificationCodeSent: emailSent, // Indicate if verification code was sent
    };
  },
);

// Helper function to send verification email via SendGrid mail collection
async function sendVerificationEmail(email, code, languageCode, displayName) {
  const subjects = {
    en: 'Nar24 - Email Verification Code',
    tr: 'Nar24 - Email Doğrulama Kodu',
    ru: 'Nar24 - Код подтверждения электронной почты',
  };

  const codeDigits = code.split('');

  // Get logo URL from Storage
  let logoUrl = '';
  try {
    const bucket = admin.storage().bucket();
    const logoFile = bucket.file('assets/naricon.png');
    const [exists] = await logoFile.exists();
    if (exists) {
      const [url] = await logoFile.getSignedUrl({
        action: 'read',
        expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
      });
      logoUrl = url;
    }
  } catch (err) {
    console.warn('Could not get logo URL:', err.message);
  }

  const getEmailHtml = (lang, codeDigits, name) => {
    const templates = {
      en: {
        greeting: `Hello ${name},`,
        message: 'Thank you for signing up with Nar24. Please enter the verification code below to complete your registration.',
        codeLabel: 'VERIFICATION CODE',
        expiry: 'This code expires in 5 minutes.',
        warning: 'If you did not create an account with Nar24, please ignore this email.',
        rights: 'All rights reserved.',
      },
      tr: {
        greeting: `Merhaba ${name},`,
        message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Kaydınızı tamamlamak için aşağıdaki doğrulama kodunu girin.',
        codeLabel: 'DOĞRULAMA KODU',
        expiry: 'Bu kod 5 dakika içinde sona erer.',
        warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin.',
        rights: 'Tüm hakları saklıdır.',
      },
      ru: {
        greeting: `Здравствуйте, ${name}!`,
        message: 'Благодарим за регистрацию в Nar24. Введите код подтверждения ниже, чтобы завершить регистрацию.',
        codeLabel: 'КОД ПОДТВЕРЖДЕНИЯ',
        expiry: 'Срок действия кода — 5 минут.',
        warning: 'Если вы не создавали учётную запись в Nar24, проигнорируйте это письмо.',
        rights: 'Все права защищены.',
      },
    };

    const t = templates[lang] || templates.en;

    const digitBoxes = codeDigits.map((digit) => `
              <td style="padding:0 4px;">
                <table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                  <tr>
                    <td style="width:44px;height:56px;background-color:#f9fafb;border:2px solid #e5e7eb;border-radius:8px;text-align:center;vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-size:28px;font-weight:bold;color:#1a1a1a;">
                      ${digit}
                    </td>
                  </tr>
                </table>
              </td>
    `).join('');

    return `
<!DOCTYPE html>
<html lang="${lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
  
  <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
          
          <!-- Logo -->
          <tr>
            <td style="padding:32px 40px 24px 40px;text-align:center;">
              ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
            </td>
          </tr>
          
          <!-- Top Gradient Line -->
          <tr>
            <td style="padding:0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Greeting -->
          <tr>
            <td style="padding:32px 40px 0 40px;">
              <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${t.greeting}</p>
              <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${t.message}</p>
            </td>
          </tr>
          
          <!-- Code Label -->
          <tr>
            <td style="padding:28px 40px 12px 40px;text-align:center;">
              <p style="margin:0;font-size:11px;font-weight:600;color:#9ca3af;letter-spacing:1.5px;">${t.codeLabel}</p>
            </td>
          </tr>
          
          <!-- Verification Code Digits -->
          <tr>
            <td style="padding:0 40px;text-align:center;">
              <table cellpadding="0" cellspacing="0" border="0" align="center">
                <tr>
                  ${digitBoxes}
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Fallback Plain Text Code -->
          <tr>
            <td style="padding:12px 40px 0 40px;text-align:center;">
              <p style="margin:0;font-size:13px;color:#c0c0c0;">Code: <strong style="color:#9ca3af;letter-spacing:2px;">${codeDigits.join('')}</strong></p>
            </td>
          </tr>
          
          <!-- Expiry Notice -->
          <tr>
            <td style="padding:24px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="background-color:#f9fafb;border-radius:8px;padding:14px 16px;text-align:center;">
                    <p style="margin:0;font-size:13px;color:#6b7280;">${t.expiry}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Warning -->
          <tr>
            <td style="padding:20px 40px 0 40px;">
              <p style="margin:0;font-size:13px;color:#c0c0c0;line-height:20px;">${t.warning}</p>
            </td>
          </tr>
          
          <!-- Bottom Gradient Line -->
          <tr>
            <td style="padding:36px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px 40px;text-align:center;">
              <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${t.rights}</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
  
</body>
</html>
    `;
  };

  const mailDoc = {
    to: [email],
    message: {
      subject: subjects[languageCode] || subjects.en,
      html: getEmailHtml(languageCode, codeDigits, displayName),
      text: getPlainTextEmail(languageCode, code, displayName),
    },
  };

  await admin.firestore().collection('mail').add(mailDoc);
}

function getPlainTextEmail(lang, code, name) {
  const templates = {
    en: {
      greeting: `Hello ${name},`,
      message: 'Thank you for signing up with Nar24. Your verification code:',
      expiry: 'This code expires in 5 minutes.',
      warning: 'If you did not create an account with Nar24, please ignore this email.',
    },
    tr: {
      greeting: `Merhaba ${name},`,
      message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Doğrulama kodunuz:',
      expiry: 'Bu kod 5 dakika içinde sona erer.',
      warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin.',
    },
    ru: {
      greeting: `Здравствуйте, ${name}!`,
      message: 'Благодарим за регистрацию в Nar24. Ваш код подтверждения:',
      expiry: 'Срок действия кода — 5 минут.',
      warning: 'Если вы не создавали учётную запись в Nar24, проигнорируйте это письмо.',
    },
  };

  const t = templates[lang] || templates.en;

  return `
${t.greeting}

${t.message}

${code}

${t.expiry}

${t.warning}

---
© 2026 Nar24
  `.trim();
}


export const verifyEmailCode = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {code} = request.data;
    const context = request.auth;

    // Check if user is authenticated
    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const uid = context.uid;

    if (!code || typeof code !== 'string' || code.length !== 6) {
      throw new HttpsError('invalid-argument', 'Valid 6-digit code is required');
    }

    try {
      // Get the verification code document
      const codeDoc = await admin.firestore()
        .collection('emailVerificationCodes')
        .doc(uid)
        .get();

      if (!codeDoc.exists) {
        throw new HttpsError('not-found', 'No verification code found for this user');
      }

      const codeData = codeDoc.data();
      const now = new Date();

      // Check if code has expired
      if (codeData.expiresAt.toDate() < now) {
        throw new HttpsError('deadline-exceeded', 'Verification code has expired');
      }

      // Check if code has already been used
      if (codeData.used) {
        throw new HttpsError('failed-precondition', 'Verification code has already been used');
      }

      // Check if code matches
      if (codeData.code !== code) {
        throw new HttpsError('invalid-argument', 'Invalid verification code');
      }

      // Mark code as used
      await admin.firestore()
        .collection('emailVerificationCodes')
        .doc(uid)
        .update({
          used: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      // Update the user's email verification status in Firebase Auth
      await admin.auth().updateUser(uid, {
        emailVerified: true,
      });

      // Update user document in Firestore
      await admin.firestore()
        .collection('users')
        .doc(uid)
        .update({
          isVerified: true,
          emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      console.log(`Email verified successfully for user ${uid}`);

      return {
        success: true,
        message: 'Email verified successfully',
      };
    } catch (error) {
      console.error('Error verifying email code:', error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError('internal', 'Error verifying email code');
    }
  },
);

// Function to resend verification code
export const resendEmailVerificationCode = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const context = request.auth;

    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const uid = context.uid;

    try {
      // Get user data
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(uid)
        .get();

      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'User document not found');
      }

      const userData = userDoc.data();

      // Check if email is already verified
      if (userData.isVerified) {
        throw new HttpsError('failed-precondition', 'Email is already verified');
      }

      // Check rate limiting - allow resend only after 30 seconds
      const existingCodeDoc = await admin.firestore()
        .collection('emailVerificationCodes')
        .doc(uid)
        .get();

      if (existingCodeDoc.exists) {
        const existingData = existingCodeDoc.data();
        const timeSinceLastCode = Date.now() - existingData.createdAt.toMillis();

        if (timeSinceLastCode < 30000) { // 30 seconds
          const waitTime = Math.ceil((30000 - timeSinceLastCode) / 1000);
          throw new HttpsError('resource-exhausted', `Please wait ${waitTime} seconds before requesting a new code`);
        }
      }

      // Generate new verification code
      const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
      const now = admin.firestore.FieldValue.serverTimestamp();

      // Store new verification code
      await admin.firestore()
        .collection('emailVerificationCodes')
        .doc(uid)
        .set({
          code: verificationCode,
          email: userData.email,
          createdAt: now,
          expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000)), // 5 minutes
          used: false,
        });

      // Send verification email
      await sendVerificationEmail(
        userData.email,
        verificationCode,
        userData.languageCode || 'en',
        userData.displayName || 'User',
      );

      return {
        success: true,
        message: 'Verification code sent successfully',
      };
    } catch (error) {
      console.error('Error resending verification code:', error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError('internal', 'Error resending verification code');
    }
  },
);

export const sendPasswordResetEmail = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {email} = request.data;

    if (!email) {
      throw new HttpsError('invalid-argument', 'Email is required');
    }

    try {
      // Get user's language preference (don't reveal if user exists)
      let languageCode = 'en';
      let displayName = '';

      try {
        const userRecord = await admin.auth().getUserByEmail(email.trim().toLowerCase());
        const userDoc = await admin.firestore()
          .collection('users')
          .doc(userRecord.uid)
          .get();

        if (userDoc.exists) {
          const userData = userDoc.data();
          languageCode = userData.languageCode || 'en';
          displayName = userData.displayName || '';
        }
      } catch (err) {
        // User not found — return success anyway to not reveal if email exists
        return {success: true};
      }

      // Generate password reset link via Admin SDK
      const resetLink = await admin.auth().generatePasswordResetLink(
        email.trim().toLowerCase(),
      );

      // Get logo URL from Storage
      let logoUrl = '';
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
        const logoFile = bucket.file('assets/naricon.png');
        const [exists] = await logoFile.exists();
        if (exists) {
          const [url] = await logoFile.getSignedUrl({
            action: 'read',
            expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
          });
          logoUrl = url;
        }
      } catch (err) {
        console.warn('Could not get logo URL:', err.message);
      }

      const content = getPasswordResetContent(languageCode);
      const greeting = displayName ? `${content.greeting} ${displayName},` : `${content.greeting},`;

      const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
  
  <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
          
          <!-- Logo -->
          <tr>
            <td style="padding:32px 40px 24px 40px;text-align:center;">
              ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
            </td>
          </tr>
          
          <!-- Top Gradient Line -->
          <tr>
            <td style="padding:0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Greeting -->
          <tr>
            <td style="padding:32px 40px 0 40px;">
              <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${greeting}</p>
              <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${content.message}</p>
            </td>
          </tr>
          
          <!-- Reset Button -->
          <tr>
            <td style="padding:28px 40px 0 40px;text-align:center;">
              <a href="${resetLink}" style="display:inline-block;padding:14px 36px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.resetButton}</a>
            </td>
          </tr>
          
          <!-- Or copy link -->
          <tr>
            <td style="padding:20px 40px 0 40px;text-align:center;">
              <p style="margin:0 0 8px 0;color:#c0c0c0;font-size:12px;">${content.orCopyLink}</p>
              <p style="margin:0;color:#9ca3af;font-size:11px;line-height:18px;word-break:break-all;">${resetLink}</p>
            </td>
          </tr>
          
          <!-- Expiry Notice -->
          <tr>
            <td style="padding:24px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="background-color:#f9fafb;border-radius:8px;padding:14px 16px;text-align:center;">
                    <p style="margin:0;font-size:13px;color:#6b7280;">${content.expiry}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Warning -->
          <tr>
            <td style="padding:20px 40px 0 40px;">
              <p style="margin:0;font-size:13px;color:#c0c0c0;line-height:20px;">${content.warning}</p>
            </td>
          </tr>
          
          <!-- Bottom Gradient Line -->
          <tr>
            <td style="padding:36px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px 40px;text-align:center;">
              <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
  
</body>
</html>
      `;

      const mailDoc = {
        to: [email.trim().toLowerCase()],
        message: {
          subject: `${content.subject} — Nar24`,
          html: emailHtml,
        },
      };

      await admin.firestore().collection('mail').add(mailDoc);

      return {success: true};
    } catch (error) {
      console.error('Password reset email error:', error);

      // Don't reveal specific errors for security
      if (error.code === 'auth/user-not-found') {
        return {success: true};
      }

      throw new HttpsError('internal', 'Failed to send password reset email');
    }
  },
);

function getPasswordResetContent(languageCode) {
  const content = {
    en: {
      greeting: 'Hello',
      message: 'We received a request to reset your password. Click the button below to create a new password.',
      resetButton: 'Reset Password',
      orCopyLink: 'Or copy and paste this link in your browser:',
      expiry: 'This link expires in 1 hour.',
      warning: 'If you did not request a password reset, you can safely ignore this email. Your password will not be changed.',
      subject: 'Password Reset',
      rights: 'All rights reserved.',
    },
    tr: {
      greeting: 'Merhaba',
      message: 'Şifrenizi sıfırlamak için bir istek aldık. Yeni bir şifre oluşturmak için aşağıdaki butona tıklayın.',
      resetButton: 'Şifreyi Sıfırla',
      orCopyLink: 'Veya bu bağlantıyı tarayıcınıza yapıştırın:',
      expiry: 'Bu bağlantı 1 saat içinde sona erer.',
      warning: 'Şifre sıfırlama talebinde bulunmadıysanız bu e-postayı görmezden gelebilirsiniz. Şifreniz değiştirilmeyecektir.',
      subject: 'Şifre Sıfırlama',
      rights: 'Tüm hakları saklıdır.',
    },
    ru: {
      greeting: 'Здравствуйте',
      message: 'Мы получили запрос на сброс вашего пароля. Нажмите кнопку ниже, чтобы создать новый пароль.',
      resetButton: 'Сбросить пароль',
      orCopyLink: 'Или скопируйте и вставьте эту ссылку в браузер:',
      expiry: 'Срок действия ссылки — 1 час.',
      warning: 'Если вы не запрашивали сброс пароля, проигнорируйте это письмо. Ваш пароль не будет изменён.',
      subject: 'Сброс пароля',
      rights: 'Все права защищены.',
    },
  };

  return content[languageCode] || content.en;
}

export const sendReceiptEmail = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {receiptId, orderId, email, isShopReceipt, shopId} = request.data;
    const context = request.auth;

    // Check if user is authenticated
    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const uid = context.uid;

    // Validate input
    if (!receiptId || !orderId || !email) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }

    try {
      let receiptDoc;
      let ownerDoc;
      let displayName = 'Customer';
      let languageCode = 'en';

      // ✅ Support for shop receipts
      if (isShopReceipt && shopId) {
        receiptDoc = await admin.firestore()
          .collection('shops')
          .doc(shopId)
          .collection('receipts')
          .doc(receiptId)
          .get();

        if (!receiptDoc.exists) {
          throw new HttpsError('not-found', 'Receipt not found');
        }

        ownerDoc = await admin.firestore()
          .collection('shops')
          .doc(shopId)
          .get();

        if (ownerDoc.exists) {
          const shopData = ownerDoc.data();
          displayName = shopData.name || 'Shop';
          languageCode = shopData.languageCode || 'tr';
        }
      } else {
        ownerDoc = await admin.firestore()
          .collection('users')
          .doc(uid)
          .get();

        const userData = ownerDoc.data() || {};
        languageCode = userData.languageCode || 'en';
        displayName = userData.displayName || 'Customer';

        receiptDoc = await admin.firestore()
          .collection('users')
          .doc(uid)
          .collection('receipts')
          .doc(receiptId)
          .get();

        if (!receiptDoc.exists) {
          throw new HttpsError('not-found', 'Receipt not found');
        }

        const receiptData = receiptDoc.data();

        if (receiptData.buyerId !== uid) {
          throw new HttpsError('permission-denied', 'Access denied');
        }
      }

      const receiptData = receiptDoc.data();

      // Get logo URL from Storage
      let logoUrl = '';
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
        const logoFile = bucket.file('assets/naricon.png');
        const [exists] = await logoFile.exists();
        if (exists) {
          const [url] = await logoFile.getSignedUrl({
            action: 'read',
            expires: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
          });
          logoUrl = url;
        }
      } catch (err) {
        console.warn('Could not get logo URL:', err.message);
      }

      // Get PDF download URL
      let pdfUrl = null;
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);

        if (receiptData.filePath) {
          const file = bucket.file(receiptData.filePath);
          const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
          });
          pdfUrl = url;
        } else {
          const fallbackPath = `receipts/${orderId}.pdf`;
          const file = bucket.file(fallbackPath);
          const [exists] = await file.exists();
          if (exists) {
            const [url] = await file.getSignedUrl({
              action: 'read',
              expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
            });
            pdfUrl = url;
          }
        }
      } catch (error) {
        console.error('Error generating download URL:', error);
      }

      const content = getLocalizedContent(languageCode);
      const orderIdShort = orderId.substring(0, 8).toUpperCase();
      const receiptIdShort = receiptId.substring(0, 8).toUpperCase();

      const orderDate = receiptData.createdAt ?
        new Date(receiptData.createdAt.toDate()).toLocaleDateString(
          languageCode === 'tr' ? 'tr-TR' : languageCode === 'ru' ? 'ru-RU' : 'en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
          }) : new Date().toLocaleDateString();

      const isBoost = receiptData.receiptType === 'boost';

      const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
  
  <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
          
          <!-- Logo -->
          <tr>
            <td style="padding:32px 40px 24px 40px;text-align:center;">
              ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:44px;height:44px;border-radius:10px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
            </td>
          </tr>
          
          <!-- Top Gradient Line -->
          <tr>
            <td style="padding:0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Greeting -->
          <tr>
            <td style="padding:32px 40px 0 40px;">
              <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${content.greeting} ${displayName},</p>
              <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${isBoost ? content.boostMessage : content.message}</p>
            </td>
          </tr>
          
          <!-- Details -->
          <tr>
            <td style="padding:28px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                
                <!-- Order/Boost ID -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${isBoost ? content.boostLabel : content.orderLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${orderIdShort}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Receipt ID -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.receiptLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${receiptIdShort}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Date -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.dateLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${orderDate}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Payment Method -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.paymentLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.paymentMethod || 'Card'}</td>
                      </tr>
                    </table>
                  </td>
                </tr>

${isBoost && receiptData.boostDuration ? `
                <!-- Boost Duration -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.durationLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.boostDuration} ${content.minutesUnit}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Boosted Items -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.itemsLabel}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${receiptData.itemCount || 1}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
` : ''}
                
                <!-- Total -->
                <tr>
                  <td style="padding:16px 0 0 0;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#1a1a1a;font-size:14px;font-weight:600;">${content.totalLabel}</td>
                        <td align="right" style="color:#ff6b35;font-size:22px;font-weight:700;letter-spacing:-0.3px;">${receiptData.totalPrice.toFixed(0)} ${receiptData.currency || 'TL'}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
              </table>
            </td>
          </tr>

${pdfUrl ? `
          <!-- Download Button -->
          <tr>
            <td style="padding:32px 40px 0 40px;text-align:center;">
              <a href="${pdfUrl}" style="display:inline-block;padding:12px 32px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.downloadButton}</a>
            </td>
          </tr>
` : ''}
          
          <!-- Bottom Gradient Line -->
          <tr>
            <td style="padding:36px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px 40px;text-align:center;">
              <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
  
</body>
</html>
      `;

      const mailDoc = {
        to: [email],
        message: {
          subject: `${content.subject} #${orderIdShort} — Nar24`,
          html: emailHtml,
        },
        template: {
          name: 'receipt',
          data: {
            receiptId,
            orderId,
            type: isBoost ? 'boost_receipt' : 'order_receipt',
          },
        },
      };

      await admin.firestore().collection('mail').add(mailDoc);

      return {
        success: true,
        message: 'Email sent successfully',
      };
    } catch (error) {
      console.error('Error:', error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError('internal', 'Failed to send email');
    }
  },
);

function getLocalizedContent(languageCode) {
  const content = {
    en: {
      greeting: 'Hello',
      message: 'Thank you for your purchase. Here are your receipt details.',
      boostMessage: 'Your boost payment was successful. Here are the details.',
      orderLabel: 'Order',
      boostLabel: 'Boost',
      receiptLabel: 'Receipt',
      dateLabel: 'Date',
      paymentLabel: 'Payment',
      durationLabel: 'Duration',
      itemsLabel: 'Items Boosted',
      minutesUnit: 'min',
      totalLabel: 'Total',
      subject: 'Receipt',
      downloadButton: 'Download PDF',
      rights: 'All rights reserved.',
    },
    tr: {
      greeting: 'Merhaba',
      message: 'Satın alımınız için teşekkür ederiz. Fatura detaylarınız aşağıdadır.',
      boostMessage: 'Boost ödemeniz başarılı. Detaylar aşağıdadır.',
      orderLabel: 'Sipariş',
      boostLabel: 'Boost',
      receiptLabel: 'Fatura',
      dateLabel: 'Tarih',
      paymentLabel: 'Ödeme',
      durationLabel: 'Süre',
      itemsLabel: 'Boost Edilen',
      minutesUnit: 'dk',
      totalLabel: 'Toplam',
      subject: 'Fatura',
      downloadButton: 'PDF İndir',
      rights: 'Tüm hakları saklıdır.',
    },
    ru: {
      greeting: 'Здравствуйте',
      message: 'Спасибо за покупку. Детали вашего чека ниже.',
      boostMessage: 'Оплата буста прошла успешно. Детали ниже.',
      orderLabel: 'Заказ',
      boostLabel: 'Буст',
      receiptLabel: 'Чек',
      dateLabel: 'Дата',
      paymentLabel: 'Оплата',
      durationLabel: 'Длительность',
      itemsLabel: 'Товаров',
      minutesUnit: 'мин',
      totalLabel: 'Итого',
      subject: 'Чек',
      downloadButton: 'Скачать PDF',
      rights: 'Все права защищены.',
    },
  };

  return content[languageCode] || content.en;
}

export const sendReportEmail = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {reportId, shopId, email} = request.data;
    const context = request.auth;

    // Check if user is authenticated
    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const uid = context.uid;

    // Validate input
    if (!reportId || !shopId || !email) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }

    try {
      // Get user's language preference
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(uid)
        .get();

      const userData = userDoc.data() || {};
      const languageCode = userData.languageCode || 'en';
      const displayName = userData.displayName || 'Shop Owner';

      // Get report data
      const reportDoc = await admin.firestore()
        .collection('shops')
        .doc(shopId)
        .collection('reports')
        .doc(reportId)
        .get();

      if (!reportDoc.exists) {
        throw new HttpsError('not-found', 'Report not found');
      }

      const reportData = reportDoc.data();

      // Get shop data
      const shopDoc = await admin.firestore()
        .collection('shops')
        .doc(shopId)
        .get();

      const shopData = shopDoc.data() || {};
      const shopName = shopData.name || 'Unknown Shop';

      // Verify ownership or access
      if (shopData.ownerId !== uid && !shopData.managers?.includes(uid)) {
        throw new HttpsError('permission-denied', 'Access denied');
      }

      // Get logo URL from Storage
      let logoUrl = '';
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
        const logoFile = bucket.file('assets/naricon.png');
        const [exists] = await logoFile.exists();
        if (exists) {
          const [url] = await logoFile.getSignedUrl({
            action: 'read',
            expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
          });
          logoUrl = url;
        }
      } catch (err) {
        console.warn('Could not get logo URL:', err.message);
      }

      // Get localized content
      const content = getReportLocalizedContent(languageCode);
      const reportIdShort = reportId.substring(0, 8).toUpperCase();

      // Format dates
      const createdAt = reportData.createdAt?.toDate() || new Date();
      const formattedDate = createdAt.toLocaleDateString(
        languageCode === 'tr' ? 'tr-TR' : languageCode === 'ru' ? 'ru-RU' : 'en-US',
        {year: 'numeric', month: 'long', day: 'numeric'},
      );

      // Format date range if exists
      let dateRangeText = '';
      if (reportData.dateRange) {
        const startDate = reportData.dateRange.start.toDate();
        const endDate = reportData.dateRange.end.toDate();
        dateRangeText = `${startDate.toLocaleDateString()} - ${endDate.toLocaleDateString()}`;
      }

      // Build included data tags
      const includedTags = [];
      if (reportData.includeProducts) includedTags.push(content.products);
      if (reportData.includeOrders) includedTags.push(content.orders);
      if (reportData.includeBoostHistory) includedTags.push(content.boostHistory);
      const includedText = includedTags.join(', ');

      // Generate report URL
      let pdfUrl = null;
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);

        if (reportData.filePath) {
          const file = bucket.file(reportData.filePath);
          const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
          });
          pdfUrl = url;
        } else {
          const possiblePaths = [
            `reports/${shopId}/${reportId}.pdf`,
          ];

          for (const filePath of possiblePaths) {
            try {
              const file = bucket.file(filePath);
              const [exists] = await file.exists();
              if (exists) {
                const [url] = await file.getSignedUrl({
                  action: 'read',
                  expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
                });
                pdfUrl = url;
                break;
              }
            } catch (error) {
              continue;
            }
          }

          if (!pdfUrl) {
            try {
              const [files] = await bucket.getFiles({
                prefix: `reports/${shopId}/${reportId}`,
              });

              if (files.length > 0) {
                const sortedFiles = files.sort((a, b) => b.name.localeCompare(a.name));
                const [url] = await sortedFiles[0].getSignedUrl({
                  action: 'read',
                  expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
                });
                pdfUrl = url;
              }
            } catch (error) {
              console.error('Error searching for report file:', error);
            }
          }
        }
      } catch (error) {
        console.error('Error generating download URL:', error);
      }

      const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
  
  <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
          
          <!-- Logo -->
          <tr>
            <td style="padding:32px 40px 24px 40px;text-align:center;">
              ${logoUrl ? `<img src="${logoUrl}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
            </td>
          </tr>
          
          <!-- Top Gradient Line -->
          <tr>
            <td style="padding:0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Greeting -->
          <tr>
            <td style="padding:32px 40px 0 40px;">
              <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;line-height:24px;">${content.greeting} ${displayName},</p>
              <p style="margin:8px 0 0 0;color:#6b7280;font-size:14px;line-height:22px;">${content.message}</p>
            </td>
          </tr>
          
          <!-- Details -->
          <tr>
            <td style="padding:28px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                
                <!-- Report Name -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.reportName}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${reportData.reportName || 'Report'}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Report ID -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.reportId}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">#${reportIdShort}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Shop Name -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.shopName}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${shopName}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
                <!-- Date -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.generatedOn}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${formattedDate}</td>
                      </tr>
                    </table>
                  </td>
                </tr>

${dateRangeText ? `
                <!-- Date Range -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.dateRange}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${dateRangeText}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
` : ''}
                
                <!-- Included Data -->
                <tr>
                  <td style="padding:12px 0;border-bottom:1px solid #f3f4f6;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="color:#9ca3af;font-size:13px;font-weight:500;">${content.includedData}</td>
                        <td align="right" style="color:#1a1a1a;font-size:13px;font-weight:600;">${includedText || '—'}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                
              </table>
            </td>
          </tr>

${pdfUrl ? `
          <!-- Download Button -->
          <tr>
            <td style="padding:32px 40px 0 40px;text-align:center;">
              <a href="${pdfUrl}" style="display:inline-block;padding:12px 32px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.downloadButton}</a>
            </td>
          </tr>
` : ''}
          
          <!-- Bottom Gradient Line -->
          <tr>
            <td style="padding:36px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px 40px;text-align:center;">
              <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
  
</body>
</html>
      `;

      // Create mail document for SendGrid
      const mailDoc = {
        to: [email],
        message: {
          subject: `${content.subject}: ${reportData.reportName || 'Report'} — Nar24`,
          html: emailHtml,
        },
        template: {
          name: 'report',
          data: {
            reportId,
            shopId,
            type: 'shop_report',
          },
        },
      };

      // Send email via SendGrid extension
      await admin.firestore().collection('mail').add(mailDoc);

      return {
        success: true,
        message: 'Email sent successfully',
      };
    } catch (error) {
      console.error('Error:', error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError('internal', 'Failed to send email');
    }
  },
);

function getReportLocalizedContent(languageCode) {
  const content = {
    en: {
      greeting: 'Hello',
      message: 'Your shop report is ready. Here are the details.',
      reportName: 'Report',
      reportId: 'Report ID',
      shopName: 'Shop',
      generatedOn: 'Date',
      dateRange: 'Period',
      includedData: 'Includes',
      products: 'Products',
      orders: 'Orders',
      boostHistory: 'Boost History',
      subject: 'Report',
      downloadButton: 'Download PDF',
      rights: 'All rights reserved.',
    },
    tr: {
      greeting: 'Merhaba',
      message: 'Mağaza raporunuz hazır. Detaylar aşağıdadır.',
      reportName: 'Rapor',
      reportId: 'Rapor No',
      shopName: 'Mağaza',
      generatedOn: 'Tarih',
      dateRange: 'Dönem',
      includedData: 'İçerik',
      products: 'Ürünler',
      orders: 'Siparişler',
      boostHistory: 'Boost Geçmişi',
      subject: 'Rapor',
      downloadButton: 'PDF İndir',
      rights: 'Tüm hakları saklıdır.',
    },
    ru: {
      greeting: 'Здравствуйте',
      message: 'Отчёт вашего магазина готов. Детали ниже.',
      reportName: 'Отчёт',
      reportId: 'Номер отчёта',
      shopName: 'Магазин',
      generatedOn: 'Дата',
      dateRange: 'Период',
      includedData: 'Содержание',
      products: 'Товары',
      orders: 'Заказы',
      boostHistory: 'История бустов',
      subject: 'Отчёт',
      downloadButton: 'Скачать PDF',
      rights: 'Все права защищены.',
    },
  };

  return content[languageCode] || content.en;
}

export const shopWelcomeEmail = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {shopId, email} = request.data;
    const context = request.auth;

    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    if (!shopId || !email) {
      throw new HttpsError('invalid-argument', 'Missing required fields: shopId and email');
    }

    try {
      // Get shop data
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();

      if (!shopDoc.exists) {
        throw new HttpsError('not-found', 'Shop not found');
      }

      const shopData = shopDoc.data();
      const shopName = shopData.name || 'Shop';
      const ownerName = shopData.ownerName || 'Seller';

      // Get user's language preference
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(context.uid)
        .get();
      const userData = userDoc.data() || {};
      const languageCode = userData.languageCode || 'tr';

      const content = getWelcomeLocalizedContent(languageCode);

      // Get signed URLs for email images
      const bucket = admin.storage().bucket();
      const imageUrls = {};

      const images = [
        {key: 'logo', path: 'assets/naricon.png'},
        {key: 'welcome', path: 'assets/shopwelcome.png'},
        {key: 'products', path: 'assets/shopproducts.png'},
        {key: 'boost', path: 'assets/shopboost.png'},
      ];

      try {
        for (const img of images) {
          const file = bucket.file(img.path);
          const [exists] = await file.exists();
          if (exists) {
            const [url] = await file.getSignedUrl({
              action: 'read',
              expires: Date.now() + 30 * 24 * 60 * 60 * 1000,
            });
            imageUrls[img.key] = url;
          }
        }
      } catch (error) {
        console.error('Error loading email images:', error);
      }

      const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f9fafb;-webkit-font-smoothing:antialiased;">
  
  <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f9fafb;padding:40px 0;">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;background-color:#ffffff;">
          
          <!-- Logo -->
          <tr>
            <td style="padding:32px 40px 24px 40px;text-align:center;">
              ${imageUrls.logo ? `<img src="${imageUrls.logo}" alt="Nar24" width="64" height="64" style="display:inline-block;width:64px;height:64px;border-radius:12px;" />` : `<span style="font-size:22px;font-weight:700;color:#1a1a1a;letter-spacing:-0.3px;">Nar24</span>`}
            </td>
          </tr>
          
          <!-- Top Gradient Line -->
          <tr>
            <td style="padding:0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Welcome Image -->
          ${imageUrls.welcome ? `
          <tr>
            <td style="padding:32px 40px 0 40px;text-align:center;">
              <img src="${imageUrls.welcome}" alt="Welcome" width="100" height="100" style="display:inline-block;width:100px;height:100px;" />
            </td>
          </tr>
          ` : ''}
          
          <!-- Greeting -->
          <tr>
            <td style="padding:24px 40px 0 40px;text-align:center;">
              <h2 style="margin:0 0 12px 0;color:#1a1a1a;font-size:22px;font-weight:700;line-height:1.3;">${content.title}</h2>
              <p style="margin:0;color:#6b7280;font-size:14px;line-height:22px;">
                ${content.greeting} <span style="color:#1a1a1a;font-weight:600;">${ownerName}</span>, 
                <span style="color:#ff6b35;font-weight:600;">${shopName}</span> ${content.approved}
              </p>
            </td>
          </tr>
          
          <!-- Feature Cards -->
          <tr>
            <td style="padding:32px 40px 0 40px;">
              
              <!-- Feature 1: Products -->
              <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:16px;">
                <tr>
                  <td style="padding:20px;background-color:#f9fafb;border-radius:12px;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        ${imageUrls.products ? `
                        <td width="56" valign="top">
                          <img src="${imageUrls.products}" alt="" width="48" height="48" style="display:block;width:48px;height:48px;border-radius:10px;" />
                        </td>
                        ` : `
                        <td width="56" valign="top">
                          <div style="width:48px;height:48px;background-color:#e0f2fe;border-radius:10px;text-align:center;line-height:48px;font-size:22px;">📦</div>
                        </td>
                        `}
                        <td style="padding-left:14px;">
                          <p style="margin:0 0 4px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.productsTitle}</p>
                          <p style="margin:0;color:#9ca3af;font-size:13px;line-height:19px;">${content.productsDesc}</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              
              <!-- Feature 2: Boost -->
              <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:16px;">
                <tr>
                  <td style="padding:20px;background-color:#f9fafb;border-radius:12px;">
                    <table cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        ${imageUrls.boost ? `
                        <td width="56" valign="top">
                          <img src="${imageUrls.boost}" alt="" width="48" height="48" style="display:block;width:48px;height:48px;border-radius:10px;" />
                        </td>
                        ` : `
                        <td width="56" valign="top">
                          <div style="width:48px;height:48px;background-color:#fef3c7;border-radius:10px;text-align:center;line-height:48px;font-size:22px;">🚀</div>
                        </td>
                        `}
                        <td style="padding-left:14px;">
                          <p style="margin:0 0 4px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.boostTitle}</p>
                          <p style="margin:0;color:#9ca3af;font-size:13px;line-height:19px;">${content.boostDesc}</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              
            </td>
          </tr>
          
          <!-- Quick Start Steps -->
          <tr>
            <td style="padding:8px 40px 0 40px;">
              <p style="margin:0 0 14px 0;color:#1a1a1a;font-size:14px;font-weight:600;">${content.quickStart}</p>
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="padding:8px 0;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td width="28" valign="top">
                          <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">1</div>
                        </td>
                        <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step1}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding:8px 0;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td width="28" valign="top">
                          <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">2</div>
                        </td>
                        <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step2}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding:8px 0;">
                    <table cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td width="28" valign="top">
                          <div style="width:22px;height:22px;background-color:#ff6b35;color:#ffffff;border-radius:50%;text-align:center;line-height:22px;font-size:11px;font-weight:700;">3</div>
                        </td>
                        <td style="color:#6b7280;font-size:13px;line-height:20px;">${content.step3}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- CTA Button -->
          <tr>
            <td style="padding:28px 40px 0 40px;text-align:center;">
              <a href="https://www.nar24panel.com/" style="display:inline-block;padding:14px 36px;background-color:#1a1a1a;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600;">${content.ctaButton}</a>
            </td>
          </tr>
          
          <!-- Bottom Gradient Line -->
          <tr>
            <td style="padding:36px 40px 0 40px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td width="50%" style="height:2px;background-color:#ff6b35;">&nbsp;</td>
                  <td width="50%" style="height:2px;background-color:#ec4899;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px 40px;text-align:center;">
              <p style="margin:0 0 6px 0;color:#9ca3af;font-size:12px;">${content.supportText} <a href="mailto:support@nar24.com" style="color:#ff6b35;text-decoration:none;font-weight:500;">support@nar24.com</a></p>
              <p style="margin:0;color:#c0c0c0;font-size:12px;font-weight:400;">© 2026 Nar24. ${content.rights}</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
  
</body>
</html>
      `;

      const mailDoc = {
        to: [email],
        message: {
          subject: `${content.subject} — Nar24`,
          html: emailHtml,
        },
        template: {
          name: 'shop_welcome',
          data: {
            shopId,
            shopName,
            type: 'shop_approval',
          },
        },
      };

      await admin.firestore().collection('mail').add(mailDoc);

      await admin.firestore().collection('shops').doc(shopId).update({
        welcomeEmailSent: true,
        welcomeEmailSentAt: new Date(),
      });

      return {
        success: true,
        message: 'Welcome email sent successfully',
        shopName,
      };
    } catch (error) {
      console.error('Error sending shop welcome email:', error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError('internal', 'Failed to send welcome email');
    }
  },
);

function getWelcomeLocalizedContent(languageCode) {
  const content = {
    en: {
      title: 'You Are Now an Authorized Seller!',
      greeting: 'Hello',
      approved: 'has been approved and is ready for sales!',
      productsTitle: 'List Your Products Easily',
      productsDesc: 'Upload your products in minutes and start selling right away with our advanced panel.',
      boostTitle: 'Boost Your Products',
      boostDesc: 'Highlight your products to reach wider audiences and increase your sales.',
      quickStart: 'Quick Start',
      step1: 'Add your first products with detailed descriptions',
      step2: 'Use quality photos to showcase your products',
      step3: 'Boost popular products to get more visibility',
      ctaButton: 'Go to Shop Panel',
      supportText: 'Need help?',
      rights: 'All rights reserved.',
      subject: 'Your Shop Has Been Approved',
    },
    tr: {
      title: 'Yetkili Satıcı Oldunuz!',
      greeting: 'Merhaba',
      approved: 'mağazanız onaylandı ve satışa hazır!',
      productsTitle: 'Ürünlerinizi Kolayca Listeleyin',
      productsDesc: 'Gelişmiş panelimiz ile ürünlerinizi dakikalar içinde yükleyip hemen satışa sunun.',
      boostTitle: 'Ürünlerinizi Öne Çıkarın',
      boostDesc: 'Ürünlerinizi boost ederek daha geniş kitlelere ulaşın ve satışlarınızı artırın.',
      quickStart: 'Hızlı Başlangıç',
      step1: 'İlk ürünlerinizi detaylı açıklamalarla ekleyin',
      step2: 'Kaliteli fotoğraflar ile ürünlerinizi sergileyin',
      step3: 'Popüler ürünlerinizi boost ederek öne çıkarın',
      ctaButton: 'Mağaza Paneline Git',
      supportText: 'Yardıma mı ihtiyacınız var?',
      rights: 'Tüm hakları saklıdır.',
      subject: 'Mağazanız Onaylandı',
    },
    ru: {
      title: 'Вы стали авторизованным продавцом!',
      greeting: 'Здравствуйте',
      approved: 'ваш магазин одобрен и готов к продажам!',
      productsTitle: 'Легко размещайте товары',
      productsDesc: 'Загружайте товары за считанные минуты и сразу начинайте продавать через нашу панель.',
      boostTitle: 'Продвигайте свои товары',
      boostDesc: 'Выделяйте товары с помощью буста, чтобы охватить больше покупателей и увеличить продажи.',
      quickStart: 'Быстрый старт',
      step1: 'Добавьте первые товары с подробными описаниями',
      step2: 'Используйте качественные фотографии для демонстрации',
      step3: 'Продвигайте популярные товары для большей видимости',
      ctaButton: 'Перейти в панель магазина',
      supportText: 'Нужна помощь?',
      rights: 'Все права защищены.',
      subject: 'Ваш магазин одобрен',
    },
  };

  return content[languageCode] || content.tr;
}


const ReportTranslations = {
  en: {
    generated: 'Generated',
    dateRange: 'Date Range',
    products: 'Products',
    orders: 'Orders',
    boostHistory: 'Boost History',
    sortedBy: 'Sorted by',
    descending: 'Descending',
    ascending: 'Ascending',
    productName: 'Product Name',
    category: 'Category',
    price: 'Price',
    quantity: 'Quantity',
    views: 'Views',
    sales: 'Sales',
    favorites: 'Favorites',
    cartAdds: 'Cart Adds',
    product: 'Product',
    buyer: 'Buyer',
    status: 'Status',
    date: 'Date',
    item: 'Item',
    durationMinutes: 'Duration (min)',
    cost: 'Cost',
    impressions: 'Impressions',
    clicks: 'Clicks',
    notSpecified: 'Not specified',
    showingFirstItemsOfTotal: (shown, total) => `Showing first ${shown} items of ${total} total`,
    noDataAvailableForSection: 'No data available for this section',
    sortByDate: 'Date',
    sortByPurchaseCount: 'Purchase Count',
    sortByClickCount: 'Click Count',
    sortByFavoritesCount: 'Favorites Count',
    sortByCartCount: 'Cart Count',
    sortByPrice: 'Price',
    sortByDuration: 'Duration',
    sortByImpressionCount: 'Impression Count',
    statusPending: 'Pending',
    statusProcessing: 'Processing',
    statusShipped: 'Shipped',
    statusDelivered: 'Delivered',
    statusCancelled: 'Cancelled',
    statusReturned: 'Returned',
    unknownShop: 'Unknown Shop',
    reportGenerationFailed: 'Report generation failed',
    reportGeneratedSuccessfully: 'Report generated successfully',
  },
  tr: {
    generated: 'Oluşturuldu',
    dateRange: 'Tarih Aralığı',
    products: 'Ürünler',
    orders: 'Siparişler',
    boostHistory: 'Boost Geçmişi',
    sortedBy: 'Sıralama',
    descending: 'Azalan',
    ascending: 'Artan',
    productName: 'Ürün Adı',
    category: 'Kategori',
    price: 'Fiyat',
    quantity: 'Miktar',
    views: 'Görüntüleme',
    sales: 'Satış',
    favorites: 'Favoriler',
    cartAdds: 'Sepete Ekleme',
    product: 'Ürün',
    buyer: 'Alıcı',
    status: 'Durum',
    date: 'Tarih',
    item: 'Öğe',
    durationMinutes: 'Süre (dk)',
    cost: 'Maliyet',
    impressions: 'Gösterim',
    clicks: 'Tıklama',
    notSpecified: 'Belirtilmemiş',
    showingFirstItemsOfTotal: (shown, total) => `Toplam ${total} öğeden ilk ${shown} tanesi gösteriliyor`,
    noDataAvailableForSection: 'Bu bölüm için veri mevcut değil',
    sortByDate: 'Tarih',
    sortByPurchaseCount: 'Satın Alma Sayısı',
    sortByClickCount: 'Tıklama Sayısı',
    sortByFavoritesCount: 'Favori Sayısı',
    sortByCartCount: 'Sepet Sayısı',
    sortByPrice: 'Fiyat',
    sortByDuration: 'Süre',
    sortByImpressionCount: 'Gösterim Sayısı',
    statusPending: 'Beklemede',
    statusProcessing: 'İşleniyor',
    statusShipped: 'Kargoya Verildi',
    statusDelivered: 'Teslim Edildi',
    statusCancelled: 'İptal Edildi',
    statusReturned: 'İade Edildi',
    unknownShop: 'Bilinmeyen Mağaza',
    reportGenerationFailed: 'Rapor oluşturma başarısız',
    reportGeneratedSuccessfully: 'Rapor başarıyla oluşturuldu',
  },
  ru: {
    generated: 'Создано',
    dateRange: 'Диапазон дат',
    products: 'Товары',
    orders: 'Заказы',
    boostHistory: 'История продвижения',
    sortedBy: 'Сортировка',
    descending: 'По убыванию',
    ascending: 'По возрастанию',
    productName: 'Название товара',
    category: 'Категория',
    price: 'Цена',
    quantity: 'Количество',
    views: 'Просмотры',
    sales: 'Продажи',
    favorites: 'Избранное',
    cartAdds: 'Добавления в корзину',
    product: 'Товар',
    buyer: 'Покупатель',
    status: 'Статус',
    date: 'Дата',
    item: 'Элемент',
    durationMinutes: 'Длительность (мин)',
    cost: 'Стоимость',
    impressions: 'Показы',
    clicks: 'Клики',
    notSpecified: 'Не указано',
    showingFirstItemsOfTotal: (shown, total) => `Показаны первые ${shown} из ${total}`,
    noDataAvailableForSection: 'Нет данных для этого раздела',
    sortByDate: 'Дата',
    sortByPurchaseCount: 'Количество покупок',
    sortByClickCount: 'Количество кликов',
    sortByFavoritesCount: 'Количество избранного',
    sortByCartCount: 'Количество корзин',
    sortByPrice: 'Цена',
    sortByDuration: 'Длительность',
    sortByImpressionCount: 'Количество показов',
    statusPending: 'В ожидании',
    statusProcessing: 'Обработка',
    statusShipped: 'Отправлено',
    statusDelivered: 'Доставлено',
    statusCancelled: 'Отменено',
    statusReturned: 'Возвращено',
    unknownShop: 'Неизвестный магазин',
    reportGenerationFailed: 'Ошибка создания отчета',
    reportGeneratedSuccessfully: 'Отчет успешно создан',
  },
};

// Helper function to get translation
function t(lang, key, ...args) {
  const translation = ReportTranslations[lang] || ReportTranslations.en;
  const value = translation[key] || ReportTranslations.en[key] || key;
  return typeof value === 'function' ? value(...args) : value;
}

// Helper function to format dates
function formatDate(date, lang = 'en') {
  const options = {year: 'numeric', month: 'short', day: 'numeric'};
  const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
  return date.toLocaleDateString(locale, options);
}

function formatDateTime(date, lang = 'en') {
  const options = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  };
  const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
  return date.toLocaleDateString(locale, options);
}

// Sort functions
function sortProducts(products, sortBy, descending) {
  return products.sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
    case 'date': {
      const dateA = a.createdAt?.toDate() || new Date(1970, 0, 1);
      const dateB = b.createdAt?.toDate() || new Date(1970, 0, 1);
      comparison = dateA - dateB;
      break;
    }
    case 'purchaseCount': {
      comparison = (a.purchaseCount || 0) - (b.purchaseCount || 0);
      break;
    }
    case 'clickCount': {
      comparison = (a.clickCount || 0) - (b.clickCount || 0);
      break;
    }
    case 'favoritesCount': {
      comparison = (a.favoritesCount || 0) - (b.favoritesCount || 0);
      break;
    }
    case 'cartCount': {
      comparison = (a.cartCount || 0) - (b.cartCount || 0);
      break;
    }
    case 'price': {
      comparison = (a.price || 0) - (b.price || 0);
      break;
    }
    }
    return descending ? -comparison : comparison;
  });
}

function sortOrders(orders, sortBy, descending) {
  return orders.sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
    case 'date': {
      const dateA = a.timestamp?.toDate() || new Date(1970, 0, 1);
      const dateB = b.timestamp?.toDate() || new Date(1970, 0, 1);
      comparison = dateA - dateB;
      break;
    }
    case 'price': {
      comparison = (a.price || 0) - (b.price || 0);
      break;
    }
    }
    return descending ? -comparison : comparison;
  });
}

function sortBoosts(boosts, sortBy, descending) {
  return boosts.sort((a, b) => {
    let comparison = 0;
    switch (sortBy) {
    case 'date': {
      const dateA = a.createdAt?.toDate() || new Date(1970, 0, 1);
      const dateB = b.createdAt?.toDate() || new Date(1970, 0, 1);
      comparison = dateA - dateB;
      break;
    }
    case 'duration': {
      comparison = (a.boostDuration || 0) - (b.boostDuration || 0);
      break;
    }
    case 'price': {
      comparison = (a.boostPrice || 0) - (b.boostPrice || 0);
      break;
    }
    case 'impressionCount': {
      comparison = (a.impressionsDuringBoost || 0) - (b.impressionsDuringBoost || 0);
      break;
    }
    case 'clickCount': {
      comparison = (a.clicksDuringBoost || 0) - (b.clicksDuringBoost || 0);
      break;
    }
    }
    return descending ? -comparison : comparison;
  });
}

// Batch processing for large datasets
async function* batchQuery(query, batchSize = 500) {
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    let batch = query.limit(batchSize);

    if (lastDoc) {
      batch = batch.startAfter(lastDoc);
    }

    const snapshot = await batch.get();

    if (snapshot.empty) {
      hasMore = false;
    } else {
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
      yield snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));

      // If we got less than batchSize, we've reached the end
      if (snapshot.docs.length < batchSize) {
        hasMore = false;
      }
    }
  }
}

// Main Cloud Function
export const generatePDFReport = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 540, // 9 minutes timeout
    memory: '2GiB', // Note: v2 uses 'GiB' instead of 'GB'
  },
  async (request) => {
    try {
      // Validate authentication
      if (!request.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          'User must be authenticated',
        );
      }

      const {reportId, shopId} = request.data;

      if (!reportId || !shopId) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'Missing required parameters',
        );
      }

      // Get report configuration
      const reportDoc = await admin.firestore()
        .collection('shops')
        .doc(shopId)
        .collection('reports')
        .doc(reportId)
        .get();

      if (!reportDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Report not found',
        );
      }

      const config = reportDoc.data();

      // Get user language preference
      const userDoc = await admin.firestore().collection('users').doc(request.auth.uid).get();
      const userLang = userDoc.exists ? (userDoc.data().languageCode || 'en') : 'en';

      // Get shop information
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
      const shopName = shopDoc.exists ? (shopDoc.data().name || t(userLang, 'unknownShop')) : t(userLang, 'unknownShop');

      // Update report status to processing
      await reportDoc.ref.update({
        status: 'processing',
        processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Collect data with pagination
      const reportData = {};

      // Collect products
      if (config.includeProducts) {
        let productsQuery = admin.firestore().collection('shop_products').where('shopId', '==', shopId);

        if (config.productCategory) {
          productsQuery = productsQuery.where('category', '==', config.productCategory);
        }
        if (config.productSubcategory) {
          productsQuery = productsQuery.where('subcategory', '==', config.productSubcategory);
        }
        if (config.productSubsubcategory) {
          productsQuery = productsQuery.where('subsubcategory', '==', config.productSubsubcategory);
        }

        if (config.dateRange) {
          productsQuery = productsQuery
            .where('createdAt', '>=', config.dateRange.start)
            .where('createdAt', '<=', config.dateRange.end);
        }

        const products = [];
        for await (const batch of batchQuery(productsQuery)) {
          products.push(...batch);
        }

        reportData.products = sortProducts(
          products,
          config.productSortBy || 'date',
          config.productSortDescending !== false,
        );
      }

      // Collect orders
      if (config.includeOrders) {
        let ordersQuery = admin.firestore().collectionGroup('items').where('shopId', '==', shopId);

        if (config.dateRange) {
          ordersQuery = ordersQuery
            .where('timestamp', '>=', config.dateRange.start)
            .where('timestamp', '<=', config.dateRange.end);
        }

        const orders = [];
        for await (const batch of batchQuery(ordersQuery)) {
          orders.push(...batch);
        }

        reportData.orders = sortOrders(
          orders,
          config.orderSortBy || 'date',
          config.orderSortDescending !== false,
        );
      }

      // Collect boost history
      if (config.includeBoostHistory) {
        let boostQuery = admin.firestore().collection('shops').doc(shopId).collection('boostHistory');

        if (config.dateRange) {
          boostQuery = boostQuery
            .where('createdAt', '>=', config.dateRange.start)
            .where('createdAt', '<=', config.dateRange.end);
        }

        const boosts = [];
        for await (const batch of batchQuery(boostQuery)) {
          boosts.push(...batch);
        }

        reportData.boostHistory = sortBoosts(
          boosts,
          config.boostSortBy || 'date',
          config.boostSortDescending !== false,
        );
      }

      // Generate PDF
      const pdfBuffer = await generatePDF(config, reportData, shopName, userLang);

      // Upload to Storage
      const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
      const timestamp = Date.now();
      const fileName = `reports/${shopId}/${reportId}_${timestamp}.pdf`;
      const file = bucket.file(fileName);

      await file.save(pdfBuffer, {
        metadata: {
          contentType: 'application/pdf',
          metadata: {
            reportId,
            shopId,
            generatedAt: new Date().toISOString(),
            userId: request.auth.uid,
          },
        },
      });

      // Get download URL
      const [url] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
      });

      // Update report with success status
      await reportDoc.ref.update({
        status: 'completed',
        pdfUrl: url,
        pdfSize: pdfBuffer.length,
        filePath: fileName,
        generationCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Store summary data for quick access
        summary: {
          productsCount: reportData.products?.length || 0,
          ordersCount: reportData.orders?.length || 0,
          boostsCount: reportData.boostHistory?.length || 0,
        },
      });

      return {
        success: true,
        pdfUrl: url,
        message: t(userLang, 'reportGeneratedSuccessfully'),
      };
    } catch (error) {
      console.error('Error generating PDF report:', error);

      // Update report with error status
      if (request.data.reportId && request.data.shopId) {
        await admin.firestore()
          .collection('shops')
          .doc(request.data.shopId)
          .collection('reports')
          .doc(request.data.reportId)
          .update({
            status: 'failed',
            error: error.message,
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
          })
          .catch(console.error);
      }

      throw new functions.https.HttpsError(
        'internal',
        error.message || 'Failed to generate report',
      );
    }
  });

// PDF Generation function
async function generatePDF(config, reportData, shopName, lang) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: 'A4',
        layout: 'landscape',
        margin: 50,
        bufferPages: true,
      });

      // Register custom fonts
      doc.registerFont('Inter-Regular', regularFontPath);
      doc.registerFont('Inter-Bold', boldFontPath);

      const chunks = [];
      doc.on('data', (chunk) => chunks.push(chunk));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      // Cover page with logo
      const pageWidth = doc.page.width;


      const logoPath = path.join(__dirname, 'siyahlogo.png');
      const logoWidth = 350;
      const logoX = (pageWidth - logoWidth) / 2;
      const logoY = -100;

      // Check if logo exists before trying to add it
      const textStartY = 370; // Fixed position for text - same as before (80 + 250 + 40)
      try {
        doc.image(logoPath, logoX, logoY, {
          width: logoWidth,
        });
      } catch (logoError) {
        console.error('Error loading logo:', logoError);
      }

      // Shop name - stays at same position
      doc.fontSize(36)
        .font('Inter-Bold')
        .fillColor('#000000')
        .text(shopName, 50, textStartY, {
          align: 'center',
          width: pageWidth - 100,
        });

      // Report name - position below shop name
      const reportNameY = textStartY + 60; // 60px below shop name
      doc.fontSize(24)
        .font('Inter-Regular')
        .text(config.reportName || 'Report', 50, reportNameY, {
          align: 'center',
          width: pageWidth - 100,
        });

      // Date information - position below report name
      const dateY = reportNameY + 80; // 80px below report name
      doc.fontSize(12)
        .fillColor('#666666')
        .text(`${t(lang, 'generated')}: ${formatDateTime(new Date(), lang)}`, 50, dateY, {
          align: 'center',
          width: pageWidth - 100,
        });

      if (config.dateRange) {
        const startDate = config.dateRange.start.toDate ? config.dateRange.start.toDate() : new Date(config.dateRange.start);
        const endDate = config.dateRange.end.toDate ? config.dateRange.end.toDate() : new Date(config.dateRange.end);
        const dateRangeY = dateY + 20; // 20px below generation date
        doc.text(`${t(lang, 'dateRange')}: ${formatDate(startDate, lang)} - ${formatDate(endDate, lang)}`, 50, dateRangeY, {
          align: 'center',
          width: pageWidth - 100,
        });
      }

      // Products section
      if (config.includeProducts && reportData.products) {
        doc.addPage();
        addSection(
          doc,
          t(lang, 'products'),
          reportData.products,
          [
            t(lang, 'productName'),
            t(lang, 'price'),
            t(lang, 'quantity'),
            t(lang, 'views'),
            t(lang, 'sales'),
            t(lang, 'favorites'),
            t(lang, 'cartAdds'),
          ],
          (item) => [
            item.productName || t(lang, 'notSpecified'),
            `${item.price || 0} ${item.currency || 'TL'}`,
            String(item.quantity || 0),
            String(item.clickCount || 0),
            String(item.purchaseCount || 0),
            String(item.favoritesCount || 0),
            String(item.cartCount || 0),
          ],
          lang,
        );
      }

      // Orders section
      if (config.includeOrders && reportData.orders) {
        doc.addPage();
        addSection(
          doc,
          t(lang, 'orders'),
          reportData.orders,
          [
            t(lang, 'product'),
            t(lang, 'buyer'),
            t(lang, 'quantity'),
            t(lang, 'price'),
            t(lang, 'status'),
            t(lang, 'date'),
          ],
          (item) => [
            item.productName || t(lang, 'notSpecified'),
            item.buyerName || t(lang, 'notSpecified'),
            String(item.quantity || 0),
            `${item.price || 0} ${item.currency || 'TL'}`,
            localizeShipmentStatus(item.shipmentStatus, lang),
            item.timestamp ? formatDate(item.timestamp.toDate(), lang) : t(lang, 'notSpecified'),
          ],
          lang,
        );
      }

      // Boost history section
      if (config.includeBoostHistory && reportData.boostHistory) {
        doc.addPage();
        addSection(
          doc,
          t(lang, 'boostHistory'),
          reportData.boostHistory,
          [
            t(lang, 'item'),
            t(lang, 'durationMinutes'),
            t(lang, 'cost'),
            t(lang, 'impressions'),
            t(lang, 'clicks'),
            t(lang, 'date'),
          ],
          (item) => [
            item.itemName || t(lang, 'notSpecified'),
            String(item.boostDuration || 0),
            `${item.boostPrice || 0} ${item.currency || 'TL'}`,
            String(item.impressionsDuringBoost || 0),
            String(item.clicksDuringBoost || 0),
            item.createdAt ? formatDate(item.createdAt.toDate(), lang) : t(lang, 'notSpecified'),
          ],
          lang,
        );
      }

      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}

// Helper function to add sections to PDF with light background for headers
function addSection(doc, title, data, headers, rowBuilder, lang) {
  doc.fontSize(18)
    .font('Inter-Bold')
    .fillColor('#000000')
    .text(title, {underline: true});

  doc.moveDown();

  if (!data || data.length === 0) {
    doc.fontSize(12)
      .font('Inter-Regular')
      .fillColor('#666666')
      .text(t(lang, 'noDataAvailableForSection'));
    return;
  }

  // Create table
  const itemsToShow = Math.min(data.length, 100); // Limit to 100 items per section for PDF size
  const columnWidth = (doc.page.width - 100) / headers.length;
  let y = doc.y;

  // Draw light background for header row
  doc.rect(50, y - 5, doc.page.width - 100, 25)
    .fillColor('#f0f0f0')
    .fill();

  // Draw headers
  doc.fontSize(10)
    .font('Inter-Bold')
    .fillColor('#000000');

  headers.forEach((header, i) => {
    doc.text(header, 50 + (i * columnWidth), y, {
      width: columnWidth - 5,
      ellipsis: true,
    });
  });

  y += 20;
  doc.moveTo(50, y)
    .lineTo(doc.page.width - 50, y)
    .strokeColor('#cccccc')
    .stroke();
  y += 10;

  // Draw rows
  doc.fontSize(9)
    .font('Inter-Regular')
    .fillColor('#333333');

  for (let i = 0; i < itemsToShow; i++) {
    const row = rowBuilder(data[i]);

    // Check if we need a new page
    if (y > doc.page.height - 100) {
      doc.addPage();
      y = 50;

      // Draw light background for header row on new page
      doc.rect(50, y - 5, doc.page.width - 100, 25)
        .fillColor('#f0f0f0')
        .fill();

      // Redraw headers on new page
      doc.fontSize(10)
        .font('Inter-Bold')
        .fillColor('#000000');

      headers.forEach((header, j) => {
        doc.text(header, 50 + (j * columnWidth), y, {
          width: columnWidth - 5,
          ellipsis: true,
        });
      });

      y += 20;
      doc.moveTo(50, y)
        .lineTo(doc.page.width - 50, y)
        .strokeColor('#cccccc')
        .stroke();
      y += 10;

      doc.fontSize(9)
        .font('Inter-Regular')
        .fillColor('#333333');
    }

    let maxRowHeight = 15; // minimum height
    const rowTexts = [];

    // First pass: measure text heights
    row.forEach((cell) => {
      const textHeight = doc.heightOfString(cell, {
        width: columnWidth - 5,
      });
      rowTexts.push({text: cell, height: textHeight});
      maxRowHeight = Math.max(maxRowHeight, textHeight + 5); // +5 for padding
    });

    // Second pass: draw the text
    rowTexts.forEach((cellData, j) => {
      doc.text(cellData.text, 50 + (j * columnWidth), y, {
        width: columnWidth - 5,
        ellipsis: false, // Remove ellipsis since we're giving proper space
      });
    });

    y += maxRowHeight;
  }

  if (data.length > itemsToShow) {
    doc.moveDown()
      .fontSize(10)
      .fillColor('#666666')
      .text(t(lang, 'showingFirstItemsOfTotal', itemsToShow, data.length));
  }
}

// Helper function to localize shipment status
function localizeShipmentStatus(status, lang) {
  if (!status) return t(lang, 'notSpecified');

  const statusKey = `status${status.charAt(0).toUpperCase() + status.slice(1).toLowerCase()}`;
  return t(lang, statusKey) || status;
}

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

export const registerFcmToken = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 10,
    memory: '256MiB',
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError('unauthenticated', 'Authentication required');
    }

    const {token, deviceId, platform} = req.data;

    // Validate inputs
    if (!token || typeof token !== 'string' || token.length < 50) {
      throw new HttpsError('invalid-argument', 'Invalid FCM token');
    }

    if (!deviceId || typeof deviceId !== 'string') {
      throw new HttpsError('invalid-argument', 'Device ID required');
    }

    const validPlatforms = ['ios', 'android', 'web'];
    if (!platform || !validPlatforms.includes(platform)) {
      throw new HttpsError('invalid-argument', 'Invalid platform');
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(auth.uid);

    try {
      await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError('not-found', 'User document not found');
        }

        const userData = userDoc.data() || {};
        let fcmTokens = userData.fcmTokens || {};

        // Step 1: Remove any existing tokens for this device
        Object.keys(fcmTokens).forEach((existingToken) => {
          if (fcmTokens[existingToken]?.deviceId === deviceId) {
            delete fcmTokens[existingToken];
          }
        });

        // Step 2: Also remove if this exact token exists under different device
        if (fcmTokens[token]) {
          delete fcmTokens[token];
        }

        // Step 3: Clean up old tokens BEFORE adding new one
        // (serverTimestamp is a sentinel that doesn't have toDate() yet)
        const existingEntries = Object.entries(fcmTokens)
          .sort((a, b) => {
            const aTime = a[1].lastSeen?.toDate?.()?.getTime() ||
                         a[1].registeredAt?.toDate?.()?.getTime() || 0;
            const bTime = b[1].lastSeen?.toDate?.()?.getTime() ||
                         b[1].registeredAt?.toDate?.()?.getTime() || 0;
            return bTime - aTime; // Most recent first
          });

        // Keep only 4 most recent (leaving room for the new token)
        if (existingEntries.length >= 5) {
          fcmTokens = Object.fromEntries(existingEntries.slice(0, 4));
        }

        // Step 4: NOW add the new token (guaranteed to be kept)
        fcmTokens[token] = {
          deviceId,
          platform,
          registeredAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        };

        transaction.update(userRef, {
          fcmTokens,
          lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      return {success: true, deviceId};
    } catch (error) {
      console.error('FCM registration error:', error);
      
      if (error instanceof HttpsError) {
        throw error;
      }
      
      throw new HttpsError('internal', 'Failed to register token');
    }
  },
);


export const cleanupInvalidToken = onCall(
  {region: 'europe-west3'},
  async (req) => {
    const {userId, invalidToken} = req.data;

    if (!userId || !invalidToken) {
      throw new HttpsError('invalid-argument', 'Missing required parameters');
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(userId);

    await userRef.update({
      [`fcmTokens.${invalidToken}`]: admin.firestore.FieldValue.delete(),
    });

    return {success: true};
  },
);

export const removeFcmToken = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 5,
    memory: '256MB',
  },
  async (req) => {
    const auth = req.auth;
    if (!auth?.uid) {
      throw new HttpsError('unauthenticated', 'Authentication required');
    }

    const {token, deviceId} = req.data;

    console.log(`🔍 Removing token for user ${auth.uid}`);
    console.log(`🔍 Token received: ${token?.substring(0, 50)}...`);
    console.log(`🔍 DeviceId received: ${deviceId}`);

    if (!token && !deviceId) {
      throw new HttpsError('invalid-argument', 'Token or device ID required');
    }

    const db = admin.firestore();
    const userRef = db.collection('users').doc(auth.uid);

    try {
      await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          console.log('⚠️ User document does not exist');
          return;
        }

        const userData = userDoc.data() || {};
        const fcmTokens = userData.fcmTokens || {};

        console.log(`📱 Current tokens count: ${Object.keys(fcmTokens).length}`);

        let removedCount = 0;

        if (token) {
          // Log if token exists in the map
          if (fcmTokens[token]) {
            console.log('✅ Found exact token match, removing...');
            delete fcmTokens[token];
            removedCount++;
          } else {
            console.log('⚠️ Token not found in user\'s token list');
            console.log('Available tokens:', Object.keys(fcmTokens).map((t) => t.substring(0, 50)));
          }
        }

        if (deviceId) {
          // Remove all tokens for this device
          Object.keys(fcmTokens).forEach((existingToken) => {
            if (fcmTokens[existingToken]?.deviceId === deviceId) {
              console.log(`✅ Removing token for deviceId: ${deviceId}`);
              delete fcmTokens[existingToken];
              removedCount++;
            }
          });

          if (removedCount === 0) {
            console.log(`⚠️ No tokens found for deviceId: ${deviceId}`);
            console.log('Available device IDs:', Object.values(fcmTokens).map((t) => t.deviceId));
          }
        }

        console.log(`🗑️ Removed ${removedCount} tokens`);
        console.log(`📱 Remaining tokens: ${Object.keys(fcmTokens).length}`);

        transaction.update(userRef, {
          fcmTokens,
          lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      return {success: true, removed: true};
    } catch (error) {
      console.error('FCM removal error:', error);
      throw new HttpsError('internal', 'Failed to remove token');
    }
  },
);


// export const boostProducts = onCall(
//   {
//     region: 'europe-west3',
//     cors: {
//       origin: ['http://localhost:3000', 'https://nar24panel.com', 'https://nar24admin.com', 'https://nar24.com'],
//       methods: ['POST'],
//       allowedHeaders: ['Content-Type', 'Authorization'],
//     },
//   },
//   async (request) => {
//     const {auth, data} = request;

//     // 1. Authentication Check
//     if (!auth) {
//       console.error('Unauthenticated request to boostProducts.');
//       throw new HttpsError('unauthenticated', 'User must be authenticated to boost products.');
//     }

//     const userId = auth.uid;

//     // 2. Input Validation
//     const {items, boostDuration} = data;

//     if (!items || !Array.isArray(items) || items.length === 0) {
//       throw new HttpsError('invalid-argument', 'Items array is required and must not be empty.');
//     }

//     if (!boostDuration || typeof boostDuration !== 'number' || boostDuration <= 0 || boostDuration > 10080) {
//       throw new HttpsError('invalid-argument', 'Boost duration must be a positive number (max 10080 minutes).');
//     }

//     if (items.length > 50) {
//       throw new HttpsError('invalid-argument', 'Cannot boost more than 50 items at once.');
//     }

//     // Validate item structure
//     for (const item of items) {
//       if (!item.itemId || typeof item.itemId !== 'string') {
//         throw new HttpsError('invalid-argument', 'Each item must have a valid itemId.');
//       }

//       if (!item.collection || !['products', 'shop_products'].includes(item.collection)) {
//         throw new HttpsError('invalid-argument', 'Each item must specify a valid collection (products or shop_products).');
//       }

//       if (item.collection === 'shop_products' && (!item.shopId || typeof item.shopId !== 'string')) {
//         throw new HttpsError('invalid-argument', 'Shop products must include a valid shopId.');
//       }
//     }

//     const db = admin.firestore();

//     // Check admin status
//     let isAdmin = false;
//     try {
//       const userRecord = await admin.auth().getUser(userId);
//       isAdmin = userRecord.customClaims?.admin === true;

//       if (!isAdmin) {
//         const adminDoc = await db.collection('users').doc(userId).get();
//         isAdmin = adminDoc.exists && adminDoc.data()?.isAdmin === true;
//       }

//       console.log(`User ${userId} admin status: ${isAdmin}`);
//     } catch (error) {
//       console.warn('Could not check admin status:', error.message);
//       isAdmin = false;
//     }

//     try {
//       // Process items in smaller batches to avoid transaction limits
//       const BATCH_SIZE = 10; // Process 10 items at a time
//       const allValidatedItems = [];
//       const failedItems = [];

//       for (let i = 0; i < items.length; i += BATCH_SIZE) {
//         const batchItems = items.slice(i, i + BATCH_SIZE);

//         try {
//           const batchResult = await processBatchBoost(db, batchItems, userId, boostDuration, isAdmin);
//           allValidatedItems.push(...batchResult.validatedItems);
//           failedItems.push(...batchResult.failedItems);
//         } catch (batchError) {
//           console.error(`Batch ${i/BATCH_SIZE + 1} failed:`, batchError);
//           // Add all items from failed batch to failedItems
//           failedItems.push(...batchItems.map((item) => ({
//             ...item,
//             error: batchError.message,
//           })));
//         }
//       }

//       if (allValidatedItems.length === 0) {
//         throw new HttpsError('failed-precondition', 'No valid items found to boost. Check permissions and item validity.');
//       }

//       // Schedule expiration tasks for all validated items
//       const scheduledTasks = await scheduleExpirationTasks(allValidatedItems, userId);

//       // Return success response
//       const totalPrice = allValidatedItems.length * boostDuration * 150.0;

//       return {
//         success: true,
//         message: `Successfully boosted ${allValidatedItems.length} item(s) for ${boostDuration} minutes.`,
//         data: {
//           boostedItemsCount: allValidatedItems.length,
//           totalRequestedItems: items.length,
//           failedItemsCount: failedItems.length,
//           boostDuration: boostDuration,
//           boostStartTime: admin.firestore.Timestamp.fromDate(new Date()),
//           boostEndTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + (boostDuration * 60 * 1000))),
//           totalPrice: totalPrice,
//           pricePerItem: boostDuration * 150.0,
//           boostedItems: allValidatedItems.map((item) => ({
//             itemId: item.itemId,
//             collection: item.collection,
//             shopId: item.shopId,
//           })),
//           failedItems: failedItems.length > 0 ? failedItems : undefined,
//           scheduledTasks: scheduledTasks,
//         },
//       };
//     } catch (error) {
//       console.error('Error in boostProducts function:', error);

//       if (error instanceof HttpsError) {
//         throw error;
//       }

//       throw new HttpsError('internal', 'An unexpected error occurred while boosting products.');
//     }
//   },
// );

export const updateBoostedProductSlots = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
    memory: '256MiB', // Lightweight function
  },
  async (event) => {
    const db = admin.firestore();

    try {
      const now = admin.firestore.Timestamp.now();

      // OPTIMIZED: Simple query that works with Firestore's rules
      // We'll do the sorting in memory (it's only ~1000 items max)
      const boostedQuery = db.collection('shop_products')
        .where('isBoosted', '==', true)
        .where('boostEndTime', '>', now)
        .select('boostStartTime', 'promotionScore') // Minimal fields
        .limit(1000); // Safety limit

      const snapshot = await boostedQuery.get();

      if (snapshot.empty) {
        // No boosted products, clear the slots
        await db.collection('boosted_rotation').doc('boosted_slots').set({
          slots: [],
          totalBoosted: 0,
          lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
          rotationIndex: 0,
        });
        console.log('✅ No boosted products found, slots cleared');
        return;
      }

      // Extract and sort for fairness
      const allBoosted = snapshot.docs.map((doc) => ({
        itemId: doc.id,
        boostStartTime: doc.data().boostStartTime?.toMillis() || 0,
        promotionScore: doc.data().promotionScore || 0,
      }));

      // Sort: oldest boosts first (fairness), then by promotion score
      allBoosted.sort((a, b) => {
        const timeDiff = a.boostStartTime - b.boostStartTime;
        if (timeDiff !== 0) return timeDiff;
        return b.promotionScore - a.promotionScore;
      });

      // Get current rotation index
      const slotsDoc = await db.collection('boosted_rotation').doc('boosted_slots').get();
      let rotationIndex = 0;

      if (slotsDoc.exists) {
        const currentIndex = slotsDoc.data()?.rotationIndex || 0;
        rotationIndex = currentIndex + 10;

        // Wrap around if we've gone through all products
        if (rotationIndex >= allBoosted.length) {
          rotationIndex = 0;
        }
      }

      // Select next 10 products in rotation
      const selectedSlots = [];
      const numSlots = Math.min(10, allBoosted.length);

      for (let i = 0; i < numSlots; i++) {
        const index = (rotationIndex + i) % allBoosted.length;
        selectedSlots.push(allBoosted[index].itemId);
      }

      // Update the slots document
      await db.collection('boosted_rotation').doc('boosted_slots').set({
        slots: selectedSlots,
        totalBoosted: allBoosted.length,
        lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
        rotationIndex: rotationIndex,
        nextRotation: admin.firestore.Timestamp.fromMillis(
          Date.now() + (5 * 60 * 1000),
        ),
      });

      console.log(`✅ Boosted slots updated successfully`);
      console.log(`   Selected: ${selectedSlots.length} products`);
      console.log(`   Total boosted: ${allBoosted.length}`);
      console.log(`   Rotation index: ${rotationIndex} → ${rotationIndex + 10}`);
      console.log(`   Next rotation: ${new Date(Date.now() + 5 * 60 * 1000).toISOString()}`);
    } catch (error) {
      console.error('❌ Error updating boosted product slots:', error);

      // Don't throw - let the function succeed to avoid Cloud Scheduler retries
      // The previous slots will remain valid until next successful run
      console.error('   Previous slots remain active until next successful update');
    }
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
            <a href="https://apps.apple.com/app/YOUR_APP_ID" class="download-btn" target="_blank">
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
                    window.location.href = 'https://apps.apple.com/app/YOUR_APP_ID';
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
            <a href="https://apps.apple.com/app/YOUR_APP_ID" class="download-btn" target="_blank">
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
                    window.location.href = 'https://apps.apple.com/app/YOUR_APP_ID';
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

const emailTemplates = {
  en: {
    brandName: 'Nar24',
    copyright: '© 2024 Nar24. All rights reserved.',
    automatedMessage:
      'This is an automated message from Nar24. Please do not reply to this email.',
    setup: {
      subject: 'Nar24 - Two-Factor Authentication Setup',
      title: 'Two-Factor Authentication Setup',
      description:
        'You are setting up two-factor authentication for your Nar24 account. Please enter the verification code below in your app:',
      expiresIn: 'This code expires in 10 minutes',
      securityNote:
        'If you did not request this setup, please contact our support team immediately.',
    },
    login: {
      subject: 'Nar24 - Login Verification Code',
      title: 'Login Verification Required',
      description:
        'Someone is trying to sign in to your Nar24 account. Enter the verification code below to complete your login:',
      expiresIn: 'This code expires in 5 minutes',
      securityNote:
        '🚨 If you did not try to sign in, please secure your account immediately by changing your password.',
    },
    disable: {
      subject: 'Nar24 - Disable Two-Factor Authentication',
      title: 'Disable Two-Factor Authentication',
      description:
        'You are about to disable two-factor authentication for your Nar24 account. Enter the verification code below to confirm:',
      expiresIn: 'This code expires in 10 minutes',
      securityNote:
        'If you did not request this change, please contact our support team immediately.',
      warning: '⚠️ Warning: Disabling 2FA will make your account less secure.',
    },
    default: {
      subject: 'Nar24 - Verification Code',
      title: 'Verification Code',
      description: 'Your Nar24 verification code is:',
      expiresIn: 'This code expires in 10 minutes',
    },
  },
  tr: {
    brandName: 'Nar24',
    copyright: '© 2024 Nar24. Tüm hakları saklıdır.',
    automatedMessage:
      'Bu Nar24 tarafından otomatik bir mesajdır. Lütfen bu e-postayı yanıtlamayın.',
    setup: {
      subject: 'Nar24 - İki Faktörlü Doğrulama Kurulumu',
      title: 'İki Faktörlü Doğrulama Kurulumu',
      description:
        'Nar24 hesabınız için iki faktörlü doğrulama kuruluyor. Lütfen aşağıdaki doğrulama kodunu uygulamanızda girin:',
      expiresIn: 'Bu kod 10 dakika içinde sona erer',
      securityNote:
        'Bu kurulumu talep etmediyseniz, lütfen destek ekibimizle hemen iletişime geçin.',
    },
    login: {
      subject: 'Nar24 - Giriş Doğrulama Kodu',
      title: 'Giriş Doğrulaması Gerekli',
      description:
        'Birisi Nar24 hesabınızda oturum açmaya çalışıyor. Girişinizi tamamlamak için aşağıdaki doğrulama kodunu girin:',
      expiresIn: 'Bu kod 5 dakika içinde sona erer',
      securityNote:
        '🚨 Giriş yapmaya çalışmadıysanız, lütfen şifrenizi değiştirerek hesabınızı hemen güvence altına alın.',
    },
    disable: {
      subject: 'Nar24 - İki Faktörlü Doğrulamayı Devre Dışı Bırak',
      title: 'İki Faktörlü Doğrulamayı Devre Dışı Bırak',
      description:
        'Nar24 hesabınızda iki faktörlü doğrulamayı devre dışı bırakmak üzeresiniz. Onaylamak için aşağıdaki doğrulama kodunu girin:',
      expiresIn: 'Bu kod 10 dakika içinde sona erer',
      securityNote:
        'Bu değişikliği talep etmediyseniz, lütfen destek ekibimizle hemen iletişime geçin.',
      warning:
        '⚠️ Uyarı: 2FAyı devre dışı bırakmak hesabınızı daha az güvenli hale getirir.',
    },
    default: {
      subject: 'Nar24 - Doğrulama Kodu',
      title: 'Doğrulama Kodu',
      description: 'Nar24 doğrulama kodunuz:',
      expiresIn: 'Bu kod 10 dakika içinde sona erer',
    },
  },
  ru: {
    brandName: 'Nar24',
    copyright: '© 2024 Nar24. Все права защищены.',
    automatedMessage:
      'Это автоматическое сообщение от Nar24. Пожалуйста, не отвечайте на это письмо.',
    setup: {
      subject: 'Nar24 - Настройка двухфакторной аутентификации',
      title: 'Настройка двухфакторной аутентификации',
      description:
        'Вы настраиваете двухфакторную аутентификацию для своей учетной записи Nar24. Пожалуйста, введите код подтверждения ниже в вашем приложении:',
      expiresIn: 'Этот код истекает через 10 минут',
      securityNote:
        'Если вы не запрашивали эту настройку, немедленно обратитесь в нашу службу поддержки.',
    },
    login: {
      subject: 'Nar24 - Код подтверждения входа',
      title: 'Требуется подтверждение входа',
      description:
        'Кто-то пытается войти в вашу учетную запись Nar24. Введите код подтверждения ниже, чтобы завершить вход:',
      expiresIn: 'Этот код истекает через 5 минут',
      securityNote:
        '🚨 Если вы не пытались войти в систему, немедленно защитите свою учетную запись, изменив пароль.',
    },
    disable: {
      subject: 'Nar24 - Отключить двухфакторную аутентификацию',
      title: 'Отключить двухфакторную аутентификацию',
      description:
        'Вы собираетесь отключить двухфакторную аутентификацию для своей учетной записи Nar24. Введите код подтверждения ниже для подтверждения:',
      expiresIn: 'Этот код истекает через 10 минут',
      securityNote:
        'Если вы не запрашивали это изменение, немедленно обратитесь в нашу службу поддержки.',
      warning:
        '⚠️ Предупреждение: Отключение 2FA сделает вашу учетную запись менее безопасной.',
    },
    default: {
      subject: 'Nar24 - Код подтверждения',
      title: 'Код подтверждения',
      description: 'Ваш код подтверждения Nar24:',
      expiresIn: 'Этот код истекает через 10 минут',
    },
  },
};

function getLocalizedTemplate(language, type) {
  const lang = emailTemplates[language] || emailTemplates['en'];
  const template = lang[type] || lang['default'];
  return {...lang, ...template};
}

function generateEmailHTML(template, code) {
  const gradientColors = {
    setup: 'linear-gradient(135deg, #ff6b35, #e91e63)',
    login: 'linear-gradient(135deg, #4caf50, #2196f3)',
    disable: 'linear-gradient(135deg, #ff9800, #f44336)',
    default: 'linear-gradient(135deg, #ff6b35, #e91e63)',
  };
  const gradient = gradientColors[template.type] || gradientColors.default;

  const warningSection = template.warning ? `
      <div style="background:#ffebee;border-left:4px solid #f44336;padding:15px;margin:20px 0;">
        <p style="margin:0;color:#c62828;font-weight:bold;">${template.warning}</p>
      </div>` : '';

  return `
    <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;padding:20px;">
      <div style="text-align:center;margin-bottom:30px;">
        <h1 style="color:#ff6b35;margin:0;">${template.brandName}</h1>
      </div>
      <h2 style="color:#333;text-align:center;">${template.title}</h2>
      <p style="color:#555;font-size:16px;line-height:1.6;">${template.description}</p>
      <div style="background:${gradient};padding:25px;text-align:center;margin:30px 0;border-radius:12px;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
        <h3 style="margin:0;font-size:36px;letter-spacing:8px;color:white;font-weight:bold;">${code}</h3>
      </div>
      <div style="background:#fff3e0;border-left:4px solid #ff9800;padding:15px;margin:20px 0;">
        <p style="margin:0;color:#e65100;font-weight:bold;">⏰ ${template.expiresIn}</p>
      </div>
      ${warningSection}
      <p style="color:#555;font-size:14px;">${template.securityNote || ''}</p>
      <hr style="margin:30px 0;border:none;border-top:1px solid #eee;">
      <p style="color:#999;font-size:12px;text-align:center;">${template.automatedMessage}<br>${template.copyright}</p>
    </div>
  `;
}

/**
 * ──────────────────────────────────────────────────────────────────────────────
 * TOTP helpers
 * ──────────────────────────────────────────────────────────────────────────────
 */
const ISSUER = 'Nar24';

// Otplib defaults: 6 digits, 30s step, SHA-1 — matches authenticator apps.
authenticator.options = {digits: 6, step: 30};

function hmac(code) {
  const salt = OTP_SALT.value();
  return crypto.createHmac('sha256', salt).update(code).digest('hex');
}

function secureRandom6() {
  const max = 999999;
  const min = 0;
  const range = max - min + 1;
  const bytesNeeded = Math.ceil(Math.log2(range) / 8);
  const maxValid = Math.pow(256, bytesNeeded) - (Math.pow(256, bytesNeeded) % range);

  let result;
  do {
    const bytes = crypto.randomBytes(bytesNeeded);
    result = 0;
    for (let i = 0; i < bytesNeeded; i++) {
      result = (result * 256) + bytes[i];
    }
  } while (result >= maxValid);

  return String(result % range).padStart(6, '0');
}

// user_secrets/{uid}/totp/config altında güvenli saklama
async function readUserTotp(uid) {
  const ref = admin.firestore().collection('user_secrets').doc(uid).collection('totp').doc('config');
  const snap = await ref.get();
  if (snap.exists) return snap.data();

  // legacy: users/{uid}.totp
  const legacy = (await admin.firestore().collection('users').doc(uid).get()).data()?.totp;
  return legacy ?? null;
}

async function writeUserTotp(uid, payload) {
  const ref = admin.firestore().collection('user_secrets').doc(uid).collection('totp').doc('config');
  await ref.set({...payload, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
}

async function deleteUserTotpEverywhere(uid) {
  await admin.firestore()
    .collection('user_secrets')
    .doc(uid)
    .collection('totp')
    .doc('config')
    .delete()
    .catch(() => {});
  await admin.firestore()
    .collection('users')
    .doc(uid)
    .set({totp: admin.firestore.FieldValue.delete()}, {merge: true})
    .catch(() => {});
}

export const startEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  const kind = ['login', 'setup', 'disable'].includes(req.data?.type) ? req.data.type : 'login';
  return await startEmail2FAImpl(uid, kind);
});

export const verifyEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  let {code, action} = req.data || {}; // action: 'login' | 'setup' | 'disable'
  code = String(code || '').replace(/\D/g, '');
  if (code.length !== 6) throw new HttpsError('invalid-argument', '6-digit code required.');

  const codeRef = admin.firestore().collection('verification_codes').doc(uid);
  const now = Timestamp.now();

  let remaining = 0;

  const res = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(codeRef);
    if (!snap.exists) return {ok: false, err: 'codeNotFound'};

    const data = snap.data();
    if (!data) return {ok: false, err: 'codeNotFound'};

    if (now.toMillis() > data.expiresAt.toMillis()) {
      tx.delete(codeRef);
      return {ok: false, err: 'codeExpired'};
    }

    if ((data.attempts || 0) >= (data.maxAttempts || 5)) {
      tx.delete(codeRef);
      return {ok: false, err: 'tooManyAttempts'};
    }

    const valid = hmac(code) === data.codeHash;
    if (!valid) {
      const attempts = (data.attempts || 0) + 1;
      remaining = Math.max((data.maxAttempts || 5) - attempts, 0);
      tx.update(codeRef, {attempts});
      return {ok: false, err: 'invalidCodeWithRemaining', remaining};
    }

    // success → consume
    tx.delete(codeRef);
    return {ok: true};
  });

  if (!res.ok) {
    if (res.err === 'invalidCodeWithRemaining') {
      return {success: false, message: 'invalidCodeWithRemaining', remaining};
    }
    return {success: false, message: res.err};
  }

  // On success: stamp
  const usersRef = admin.firestore().collection('users').doc(uid);

  if (action === 'setup') {
    await usersRef.set(
      {
        twoFactorEnabled: true,
        twoFactorEnabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  } else if (action === 'disable') {
    await usersRef.set(
      {
        twoFactorEnabled: false,
        twoFactorDisabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  } else {
    // login default
    await usersRef.set({lastTwoFactorVerification: FieldValue.serverTimestamp()}, {merge: true});
  }

  return {success: true, message: 'verificationSuccess'};
});

export const resendEmail2FA = onCall({region: 'europe-west2', cors: true, secrets: [OTP_SALT]}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  const kind = ['login', 'setup', 'disable'].includes(req.data?.type) ? req.data.type : 'login';
  return await startEmail2FAImpl(uid, kind); // <— .run yerine helper
});

async function startEmail2FAImpl(uid, kind) {
  // startEmail2FA içindeki mevcut gövdeni buraya aynen taşı
  const userRec = await admin.auth().getUser(uid);
  const email = userRec.email;
  if (!email) throw new HttpsError('failed-precondition', 'No email for user.');

  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const language = userDoc.data()?.languageCode || 'en';

  // throttle: 30s
  const codeRef = admin.firestore().collection('verification_codes').doc(uid);
  const last = await codeRef.get();
  if (last.exists) {
    const lastCreated = last.data()?.createdAt?.toDate?.();
    if (lastCreated && Date.now() - lastCreated.getTime() < 30 * 1000) {
      return {success: false, message: 'pleasewait30seconds'};
    }
  }

  const rawCode = secureRandom6();
  const codeHash = hmac(rawCode);
  const nowMs = Date.now();
  const ttlMin = kind === 'login' ? 5 : 10;
  const expiresAt = Timestamp.fromDate(new Date(nowMs + ttlMin * 60 * 1000));

  await admin.firestore().runTransaction(async (tx) => {
    tx.set(
      codeRef,
      {
        codeHash,
        type: kind,
        attempts: 0,
        maxAttempts: 5,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt,
      },
      {merge: true},
    );
  });

  // mail (Firestore Send Email extension veya kendi mail pipeline'ınız)
  const template = getLocalizedTemplate(language, kind);
  template.type = kind;
  const html = generateEmailHTML(template, rawCode);

  await admin.firestore().collection('mail').add({
    to: [email],
    message: {subject: template.subject, html},
    template: {name: 'verification-code', data: {code: rawCode, type: kind, language}},
  });

  return {success: true, sentViaEmail: true, message: 'emailCodeSent'};
}


/**
 * Create secret & otpauth:// URI for setup
 */
export const createTotpSecret = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  
  const existing = await readUserTotp(uid);
  if (existing?.enabled) {
    throw new HttpsError('failed-precondition', 'TOTP already enabled. Disable it first.');
  }

  const userRecord = await admin.auth().getUser(uid);
  const accountName = userRecord.email || uid;

  const secretBase32 = authenticator.generateSecret();
  const otpauth = authenticator.keyuri(accountName, ISSUER, secretBase32);

  await writeUserTotp(uid, {
    enabled: false,
    secretBase32,
    createdAt: FieldValue.serverTimestamp(),
  });

  // legacy alanı temizlemeye bir şans ver (sessiz)
  await admin.firestore().collection('users').doc(uid).set(
    {totp: admin.firestore.FieldValue.delete()},
    {merge: true},
  ).catch(() => {});

  return {success: true, otpauth, secretBase32};
});


export const verifyTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;
  let {code} = req.data || {};
  code = String(code || '').replace(/\D/g, '');
  if (code.length !== 6) throw new HttpsError('invalid-argument', '6-digit code is required.');

  // rate limit: 5 deneme / 15 dk
  const attemptsRef = admin.firestore().collection('totp_attempts').doc(uid);
  const attemptsSnap = await attemptsRef.get();
  const attempts = attemptsSnap.data()?.attempts || 0;
  const lastAttempt = attemptsSnap.data()?.lastAttempt?.toDate?.();
  if (lastAttempt && Date.now() - lastAttempt.getTime() > 15 * 60 * 1000) {
    await attemptsRef.delete().catch(() => {});
  } else if (attempts >= 5) {
    throw new HttpsError('permission-denied', 'Too many attempts. Try again later.');
  }

  const totp = await readUserTotp(uid);
  if (!totp?.secretBase32) throw new HttpsError('failed-precondition', 'TOTP is not initialized.');

  const isValid = authenticator.check(code, totp.secretBase32, {window: 1});
  if (!isValid) {
    await attemptsRef.set(
      {attempts: attempts + 1, lastAttempt: FieldValue.serverTimestamp()},
      {merge: true},
    );
    throw new HttpsError('permission-denied', 'Invalid TOTP code.');
  }

  await attemptsRef.delete().catch(() => {});

  // Setup ise enable, değilse sadece lastTwoFactorVerification damgası
  const usersRef = admin.firestore().collection('users').doc(uid);
  if (!totp.enabled) {
    await usersRef.set(
      {
        twoFactorEnabled: true,
        twoFactorEnabledAt: FieldValue.serverTimestamp(),
        lastTwoFactorVerification: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await writeUserTotp(uid, {
      enabled: true,
      secretBase32: totp.secretBase32,
      verifiedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await usersRef.set({lastTwoFactorVerification: FieldValue.serverTimestamp()}, {merge: true});
  }

  return {success: true};
});

export const disableTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const uid = req.auth.uid;

  // recent-2FA zorunluluğu (5 dk)
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const last2faTs = userDoc.data()?.lastTwoFactorVerification?.toDate?.();
  if (!last2faTs || Date.now() - last2faTs.getTime() > 5 * 60 * 1000) {
    throw new HttpsError('permission-denied', 'recent-2fa-required');
  }

  await admin.firestore().collection('users').doc(uid).set(
    {
      twoFactorEnabled: false,
      twoFactorDisabledAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await deleteUserTotpEverywhere(uid);

  return {success: true};
});


/**
 * ──────────────────────────────────────────────────────────────────────────────
 * Housekeeping: clean expired verification codes/sessions
 * ──────────────────────────────────────────────────────────────────────────────
 */
export const cleanupExpiredVerificationData = onSchedule(
  {schedule: '0 2 * * *', timeZone: 'Europe/Istanbul', region: 'europe-west3'},
  async () => {
    try {
      const now = Timestamp.now();
      
      const deleteInBatches = async (docs) => {
        const chunks = [];
        for (let i = 0; i < docs.length; i += 450) {
          chunks.push(docs.slice(i, i + 450));
        }
        for (const chunk of chunks) {
          const batch = admin.firestore().batch();
          chunk.forEach((d) => batch.delete(d.ref));
          await batch.commit();
        }
      };

      // Get and delete expired codes
      const expiredCodes = await admin.firestore()
        .collection('verification_codes')
        .where('expiresAt', '<', now)
        .get();
      await deleteInBatches(expiredCodes.docs);

      // Get and delete old attempts
      const oldAttempts = await admin.firestore()
        .collection('totp_attempts')
        .where('lastAttempt', '<', Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)))
        .get();
      await deleteInBatches(oldAttempts.docs);

      return {success: true, totalCleaned: expiredCodes.size + oldAttempts.size};
    } catch (err) {
      console.error('Cleanup error:', err);
      return {success: false};
    }
  },
);

export const hasTotp = onCall({region: 'europe-west3', cors: true}, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
  const totp = await readUserTotp(req.auth.uid);
  return {enabled: !!totp?.enabled};
});


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

export const createProductQuestionNotification = onCall(
  {
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 60,
  },
  async (request) => {
    const startTime = Date.now();

    try {
      // ============================================
      // STEP 1: AUTHENTICATION & VALIDATION
      // ============================================
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
      }

      const {
        productId,
        productName,
        questionText,
        askerName,
        isShopProduct,
        shopId,
        sellerId,
      } = request.data;

      if (!productId || !productName || !questionText) {
        throw new HttpsError(
          'invalid-argument',
          'productId, productName, and questionText are required',
        );
      }

      if (isShopProduct && !shopId) {
        throw new HttpsError(
          'invalid-argument',
          'shopId is required for shop products',
        );
      }

      if (!isShopProduct && !sellerId) {
        throw new HttpsError(
          'invalid-argument',
          'sellerId is required for user products',
        );
      }

      const db = admin.firestore();
      const askerId = request.auth.uid;

      console.log(`📧 Creating notifications for product ${productId}`);
      console.log(`   Type: ${isShopProduct ? 'Shop Product' : 'User Product'}`);

      // ============================================
      // STEP 2: SHOP PRODUCT → shop_notifications
      // ============================================
      if (isShopProduct) {
        // Get shop to build isRead map
        const shopSnap = await db.collection('shops').doc(shopId).get();

        if (!shopSnap.exists) {
          throw new HttpsError('not-found', 'Shop not found');
        }

        const shopData = shopSnap.data();

        // Build isRead map for all members (excluding asker)
        const isReadMap = {};
        const addMember = (id) => {
          if (id && typeof id === 'string' && id !== askerId) {
            isReadMap[id] = false;
          }
        };

        addMember(shopData.ownerId);
        if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach(addMember);
        if (Array.isArray(shopData.editors)) shopData.editors.forEach(addMember);
        if (Array.isArray(shopData.viewers)) shopData.viewers.forEach(addMember);

        if (Object.keys(isReadMap).length === 0) {
          console.log('No recipients to notify');
          return { success: true, notificationsSent: 0 };
        }

        // ✅ Write to shop_notifications (triggers sendShopNotificationOnCreation)
        await db.collection('shop_notifications').add({
          type: 'product_question',
          shopId,
          shopName: shopData.name || '',
          productId,
          productName,
          questionText: questionText.substring(0, 500),
          askerName: askerName || 'Anonymous',
          askerId,
          isRead: isReadMap,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          message_en: `New question about "${productName}"`,
          message_tr: `"${productName}" hakkında yeni soru`,
          message_ru: `Новый вопрос о "${productName}"`,
        });

        console.log(`✅ Shop notification created for ${Object.keys(isReadMap).length} members`);

        return {
          success: true,
          notificationsSent: 1,
          recipients: Object.keys(isReadMap).length,
          processingTime: Date.now() - startTime,
        };
      }

      // ============================================
      // STEP 3: USER PRODUCT → users/{uid}/notifications
      // ============================================
      if (sellerId === askerId) {
        console.log('Asker is the product owner, no notification needed');
        return { success: true, notificationsSent: 0 };
      }

      await db.collection('users').doc(sellerId).collection('notifications').add({
        type: 'product_question',
        productId,
        productName,
        questionText: questionText.substring(0, 500),
        askerName: askerName || 'Anonymous',
        askerId,
        sellerId,
        isShopProduct: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        message_en: `New question about "${productName}"`,
        message_tr: `"${productName}" hakkında yeni soru`,
        message_ru: `Новый вопрос о "${productName}"`,
      });

      console.log(`✅ User notification created for seller ${sellerId}`);

      return {
        success: true,
        notificationsSent: 1,
        recipients: 1,
        processingTime: Date.now() - startTime,
      };
    } catch (error) {
      console.error('❌ Error:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'Failed to create notifications');
    }
  },
);

export {deleteCampaign, processCampaignDeletion, getCampaignDeletionStatus, cleanupCampaignDeletionQueue} from './4-campaigns/index.js';
export {submitReview, updateProductMetrics, updateShopProductMetrics, updateShopMetrics, updateUserSellerMetrics, sendReviewNotifications} from './5-reviews/index.js';
export {rebuildRelatedProducts} from './6-related_products/index.js';
export {batchUpdateClicks, syncClickAnalytics} from './7-click-analytics/index.js';
export {validateCartCheckout, updateCartCache} from './8-cart-validation/index.js';
export {calculateCartTotals} from './9-cart-total-price/index.js';
export {batchCartFavoriteEvents, syncCartFavoriteMetrics} from './10-cart&favorite-metrics/index.js';
export {
  batchUserActivity,
  cleanupOldActivityEvents,
  computeUserPreferences,
  processActivityDLQ,
} from './11-user-activity/index.js';
export {computeTrendingProducts, cleanupTrendingHistory} from './12-trending-products/index.js';
export {updatePersonalizedFeeds, cleanupOldFeeds, processPersonalizedFeedBatch} from './13-personalized-feed/index.js';
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
export { weeklyAnalyticsScheduled, triggerWeeklyAnalytics } from './20-admin-analytics/index.js';
export { monthlyAnalyticsSummaryScheduled, triggerMonthlySummary } from './21-admin-analytics-summary/index.js';
export { dailyEngagementScheduled, triggerDailyEngagement } from './22-daily-aggregated-analytics-summary/index.js';
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
export { onFoodOrderStatusChange, informFoodCourier, cleanupExpiredCourierNotifications } from './30-food-courier-notifications/index.js';
export { extractColorOnly, initializeIsbankAdPayment, isbankAdPaymentCallback, checkIsbankAdPaymentStatus, processAdColorExtraction, processAdExpiration, processAdAnalytics, trackAdClick, trackAdConversion, createDailyAdAnalyticsSnapshot, cleanupExpiredAds, recoverStuckAdPayments } from './31-homescreen-ads-payment/index.js';
export { expireSingleBoost, initializeBoostPayment, boostPaymentCallback, checkBoostPaymentStatus, recoverStuckBoostPayments } from './32-product-boost-payment/index.js';
export { cleanupPaymentCollections } from './33-payment-cleanup/index.js';
