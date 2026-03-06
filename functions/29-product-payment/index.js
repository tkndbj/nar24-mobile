import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import { transliterate } from 'transliteration';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

import {trackPurchaseActivity} from '../11-user-activity/index.js';
import {createQRCodeTask} from '../16-qr-for-orders/index.js';
import {CloudTasksClient} from '@google-cloud/tasks';

const tasksClient = new CloudTasksClient();

const secretClient = new SecretManagerServiceClient();

// Helper to fetch a secret
async function getSecret(secretName) {
    const [version] = await secretClient.accessSecretVersion({name: secretName});
    return version.payload.data.toString('utf8');
  } 
  
  // İş Bankası Configuration
  let isbankConfig = null;
  
  async function getIsbankConfig() {
    if (!isbankConfig) {
      const [clientId, apiUser, apiPassword, storeKey] = await Promise.all([
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_CLIENT_ID/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_USER/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_PASSWORD/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest'),
      ]);
  
      isbankConfig = {
        clientId,
        apiUser,
        apiPassword,
        storeKey,
        gatewayUrl: 'https://sanalpos.isbank.com.tr/fim/est3Dgate',
        currency: '949',
        storeType: '3d_pay_hosting',
      };
    }
    return isbankConfig;
  }

// Helper function to get collection name based on ad type
function getAdCollectionName(adType) {
    switch (adType) {
    case 'topBanner':
      return 'market_top_ads_banners';
    case 'thinBanner':
      return 'market_thin_banners';
    case 'marketBanner':
      return 'market_banners';
    default:
      return 'market_banners';
    }
  }

async function validateDiscounts(tx, db, userId, couponId, benefitId, cartTotal) {
    let couponDiscount = 0;
    let freeShippingApplied = false;
    let couponCode = null;
    let couponRef = null;
    let benefitRef = null;
  
    // Validate coupon (READ ONLY)
    if (couponId) {
      couponRef = db.collection('users').doc(userId).collection('coupons').doc(couponId);
      const couponDoc = await tx.get(couponRef);
  
      if (!couponDoc.exists) {
        throw new HttpsError('not-found', 'Coupon not found');
      }
  
      const coupon = couponDoc.data();
  
      if (coupon.isUsed) {
        throw new HttpsError('failed-precondition', 'Coupon has already been used');
      }
  
      if (coupon.expiresAt && coupon.expiresAt.toDate() < new Date()) {
        throw new HttpsError('failed-precondition', 'Coupon has expired');
      }
  
      // Cap discount at cart total
      couponDiscount = Math.min(coupon.amount || 0, cartTotal);
      couponCode = coupon.code || null;
    }
  
    // Validate free shipping benefit (READ ONLY)
    if (benefitId) {
      benefitRef = db.collection('users').doc(userId).collection('benefits').doc(benefitId);
      const benefitDoc = await tx.get(benefitRef);
  
      if (!benefitDoc.exists) {
        throw new HttpsError('not-found', 'Free shipping benefit not found');
      }
  
      const benefit = benefitDoc.data();
  
      if (benefit.isUsed) {
        throw new HttpsError('failed-precondition', 'Free shipping has already been used');
      }
  
      if (benefit.expiresAt && benefit.expiresAt.toDate() < new Date()) {
        throw new HttpsError('failed-precondition', 'Free shipping benefit has expired');
      }
  
      freeShippingApplied = true;
    }
  
    return { 
      couponDiscount, 
      freeShippingApplied, 
      couponCode,
      couponRef,  // Pass ref for later write
      benefitRef, // Pass ref for later write
    };
  }
  
  // STEP 2: Mark discounts as used (WRITES ONLY - call after all reads)
  function markDiscountsAsUsed(tx, discountResult, orderId) {
    const { couponRef, benefitRef } = discountResult;
  
    if (couponRef) {
      tx.update(couponRef, {
        isUsed: true,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        orderId: orderId,
      });
      console.log(`Coupon marked as used for order ${orderId}`);
    }
  
    if (benefitRef) {
      tx.update(benefitRef, {
        isUsed: true,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        orderId: orderId,
      });
      console.log(`Benefit marked as used for order ${orderId}`);
    }
  }
  
  // Add this function to create the cart clearing task
  async function createCartClearTask(buyerId, purchasedProductIds, orderId) {
    const project = 'emlak-mobile-app';
    const location = 'europe-west3';
    const queue = 'cart-operations';
  
    const parent = tasksClient.queuePath(project, location, queue);
  
    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `https://${location}-${project}.cloudfunctions.net/clearPurchasedCartItems`,
        body: Buffer.from(JSON.stringify({
          buyerId,
          purchasedProductIds,
          orderId,
        })).toString('base64'),
        headers: {
          'Content-Type': 'application/json',
        },
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
    };
  
    try {
      await tasksClient.createTask({parent, task});
      console.log(`Cart clear task created for buyer ${buyerId}, order ${orderId}`);
    } catch (error) {
      console.error('Error creating cart clear task:', error);
      // Don't throw - cart clearing is non-critical
    }
  }
  
  // Cloud Task handler for cart clearing
  export const clearPurchasedCartItems = onRequest(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 60,
      invoker: 'private',
    },
    async (request, response) => {
      try {
        const {buyerId, purchasedProductIds, orderId} = request.body;
  
        // Validate inputs
        if (!buyerId || !Array.isArray(purchasedProductIds) || purchasedProductIds.length === 0) {
          console.error('Invalid cart clear request:', {buyerId, purchasedProductIds});
          response.status(400).send('Invalid request parameters');
          return;
        }
  
        const db = admin.firestore();
        const cartRef = db.collection('users').doc(buyerId).collection('cart');
  
        // Log the operation
        console.log(`Clearing ${purchasedProductIds.length} items from cart for user ${buyerId}, order ${orderId}`);
        console.log(`Product IDs to remove:`, purchasedProductIds);
  
        // CRITICAL: Cart uses document IDs as product IDs (not a field)
        // Firestore batch writes limited to 500 operations
        const WRITE_BATCH_SIZE = 500;
        let deletedCount = 0;
  
        // The cart document ID IS the productId, so we can delete directly
        console.log(`Target product IDs to remove:`, purchasedProductIds);
  
        for (let i = 0; i < purchasedProductIds.length; i += WRITE_BATCH_SIZE) {
          const batchProductIds = purchasedProductIds.slice(i, i + WRITE_BATCH_SIZE);
          const batch = db.batch();
  
          // Delete each cart document directly by its ID (which is the productId)
          batchProductIds.forEach((productId) => {
            const cartItemRef = cartRef.doc(productId);
            batch.delete(cartItemRef);
            deletedCount++;
            console.log(`✓ Marked for deletion: ${productId}`);
          });
  
          // Commit the batch
          await batch.commit();
          console.log(`Write batch ${Math.floor(i / WRITE_BATCH_SIZE) + 1} committed: ${batchProductIds.length} items`);
        }
  
        // Log the operation result
        await db.collection('cart_clear_logs').add({
          buyerId,
          orderId,
          purchasedProductIds,
          deletedCount,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          success: true,
        });
  
        console.log(`Cart clearing completed: ${deletedCount} items deleted`);
        response.status(200).send({
          success: true,
          deletedCount,
        });
      } catch (error) {
        console.error('Error clearing cart items:', error);
  
        // Log the error
        try {
          const {buyerId, orderId} = request.body;
          await admin.firestore().collection('cart_clear_logs').add({
            buyerId: buyerId || 'unknown',
            orderId: orderId || 'unknown',
            error: error.message,
            stack: error.stack,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            success: false,
          });
        } catch (logError) {
          console.error('Failed to log cart clear error:', logError);
        }
  
        response.status(500).send({
          success: false,
          error: error.message,
        });
      }
    },
  );
  
  // Helper function to create notification tasks
  async function createNotificationTask(orderId, productData, recipientId, buyerName, buyerId) {
    const project = 'emlak-mobile-app';
    const location = 'europe-west3';
    const queue = 'order-notifications';
  
    const parent = tasksClient.queuePath(project, location, queue);
  
    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `https://${location}-${project}.cloudfunctions.net/processOrderNotification`,
        body: Buffer.from(JSON.stringify({
          orderId,
          productId: productData.productId,
          productName: productData.productName,
          recipientId,
          buyerName,
          buyerId,
          quantity: productData.quantity,
          shopId: productData.shopId,
          shopName: productData.shopName,
          sellerId: productData.sellerId,
          isShopProduct: productData.isShopProduct,
        })).toString('base64'),
        headers: {
          'Content-Type': 'application/json',
        },
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
    };
  
    try {
      await tasksClient.createTask({parent, task});
    } catch (error) {
      console.error('Error creating notification task:', error);
      // Don't throw - notifications are non-critical
    }
  }
  
  // Batch fetch products to reduce transaction reads
  async function batchFetchProducts(tx, db, items) {
    const productRefs = [];
    const productSnapPromises = [];
  
    for (const item of items) {
      const {productId} = item;
      if (!productId || typeof productId !== 'string') {
        throw new HttpsError('invalid-argument', 'Each cart item needs a valid productId.');
      }
  
      // Try products collection first
      const pRef = db.collection('products').doc(productId);
      productRefs.push({ref: pRef, item, collection: 'products'});
      productSnapPromises.push(tx.get(pRef));
    }
  
    const productSnaps = await Promise.all(productSnapPromises);
    const productsMeta = [];
  
    for (let i = 0; i < productSnaps.length; i++) {
      let pSnap = productSnaps[i];
      let pRef = productRefs[i].ref;
      const item = productRefs[i].item;
  
      if (!pSnap.exists) {
        // Try shop_products collection
        pRef = db.collection('shop_products').doc(item.productId);
        pSnap = await tx.get(pRef);
        if (!pSnap.exists) {
          throw new HttpsError('not-found', `Product ${item.productId} not found.`);
        }
      }
  
      productsMeta.push({ref: pRef, data: pSnap.data(), item});
    }
  
    return productsMeta;
  }
  
  // Batch fetch seller information
  async function batchFetchSellers(tx, db, productsMeta) {
    const shopIds = new Set();
    const userIds = new Set();
  
    for (const meta of productsMeta) {
      if (meta.data.shopId) {
        shopIds.add(meta.data.shopId);
      } else {
        userIds.add(meta.data.userId);
      }
    }
  
    const shopPromises = Array.from(shopIds).map((id) => tx.get(db.collection('shops').doc(id)));
    const userPromises = Array.from(userIds).map((id) => tx.get(db.collection('users').doc(id)));
  
    const [shopSnaps, userSnaps] = await Promise.all([
      Promise.all(shopPromises),
      Promise.all(userPromises),
    ]);
  
    const shopData = new Map();
    const userData = new Map();
  
    shopSnaps.forEach((snap, idx) => {
      const id = Array.from(shopIds)[idx];
      shopData.set(id, snap.data());
    });
  
    userSnaps.forEach((snap, idx) => {
      const id = Array.from(userIds)[idx];
      userData.set(id, snap.data());
    });
  
    // Attach seller names to metadata
    for (const meta of productsMeta) {
      if (meta.data.shopId) {
        const shop = shopData.get(meta.data.shopId);
        meta.sellerName = shop?.name || 'Unknown Shop';
        meta.sellerType = 'shop';
        meta.shopMembers = getShopMemberIdsFromData(shop);
        meta.sellerContactNo = shop?.contactNo || null;
        // NEW: Add location
        meta.sellerAddress = {
          addressLine1: shop?.address || 'N/A',
          location: (shop?.latitude && shop?.longitude) ? {
            lat: shop.latitude,
            lng: shop.longitude,
          } : null,
        };
      } else {
        const user = userData.get(meta.data.userId);
        meta.sellerName = user?.displayName || 'Unknown Seller';
        meta.sellerType = 'user';
        meta.sellerContactNo = user?.sellerInfo?.phone || null;
        // NEW: Add location
        meta.sellerAddress = user?.sellerInfo ? {
          addressLine1: user.sellerInfo.address || 'N/A',
          location: (user.sellerInfo.latitude && user.sellerInfo.longitude) ? {
            lat: user.sellerInfo.latitude,
            lng: user.sellerInfo.longitude,
          } : null,
        } : null;
      }
    }
  
    return productsMeta;
  }
  
  // Extract shop member IDs from shop data (no external read)
  function getShopMemberIdsFromData(shopData) {
    if (!shopData) return [];
  
    const memberIds = [];
    if (shopData.ownerId) memberIds.push(shopData.ownerId);
    if (Array.isArray(shopData.coOwners)) memberIds.push(...shopData.coOwners);
    if (Array.isArray(shopData.editors)) memberIds.push(...shopData.editors);
    if (Array.isArray(shopData.viewers)) memberIds.push(...shopData.viewers);
  
    return [...new Set(memberIds)];
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
  
  async function createOrderTransaction(buyerId, requestData) {
    const {
      items,
      address,
      pickupPoint,
      paymentMethod,
      cartCalculatedTotal,
      deliveryOption = 'normal',
      saveAddress = false,
      paymentOrderId,
      couponId = null,
      freeShippingBenefitId = null,
      clientDeliveryPrice = 0,
    } = requestData;
  
    // Validate required fields
    if (!Array.isArray(items) || items.length === 0) {
      throw new HttpsError('invalid-argument', 'Cart must contain at least one item.');
    }
  
    if (deliveryOption === 'pickup') {
      if (!pickupPoint || typeof pickupPoint !== 'object') {
        throw new HttpsError('invalid-argument', 'Pickup point is required for pickup delivery.');
      }
      ['pickupPointId', 'pickupPointName', 'pickupPointAddress'].forEach((f) => {
        if (!(f in pickupPoint)) {
          throw new HttpsError('invalid-argument', `Missing pickup point field: ${f}`);
        }
      });
    } else {
      if (!address || typeof address !== 'object') {
        throw new HttpsError('invalid-argument', 'A valid address object is required.');
      }
      ['addressLine1', 'city', 'phoneNumber', 'location'].forEach((f) => {
        if (!(f in address)) {
          throw new HttpsError('invalid-argument', `Missing address field: ${f}`);
        }
      });
    }
  
    const validDeliveryOptions = ['normal', 'express'];
    if (!validDeliveryOptions.includes(deliveryOption)) {
      throw new HttpsError('invalid-argument', 'Invalid delivery option.');
    }
  
    const db = admin.firestore();
    let orderResult;
    const notificationData = [];
  
    let productsMeta = [];
    let finalOrderId = null;
  
    // TRANSACTION: Critical operations only
    await db.runTransaction(async (tx) => {
      // CRITICAL: Prevent duplicate orders for same payment
      if (paymentOrderId) {
        const existingOrdersQuery = db.collection('orders')
          .where('paymentOrderId', '==', paymentOrderId)
          .limit(1);
  
        const existingOrdersSnap = await tx.get(existingOrdersQuery);
  
        if (!existingOrdersSnap.empty) {
          console.log(`Order already exists for payment ${paymentOrderId}`);
          orderResult = {
            orderId: existingOrdersSnap.docs[0].id,
            success: true,
            duplicate: true,
            message: 'Order already processed for this payment.',
          };
          return;
        }
      }
      // FETCH BUYER
      const buyerRef = db.collection('users').doc(buyerId);
      const buyerSnap = await tx.get(buyerRef);
      if (!buyerSnap.exists) {
        throw new HttpsError('not-found', `Buyer ${buyerId} not found.`);
      }
      const buyerData = buyerSnap.data() || {};
      const buyerName = buyerData.displayName || buyerData.name || 'Unknown Buyer';
      const userLanguage = buyerData.languageCode || 'en';
  
      const orderRef = db.collection('orders').doc(); // Create ref early for orderId
      finalOrderId = orderRef.id;
      
      let discountResult = { 
        couponDiscount: 0, 
        freeShippingApplied: false, 
        couponCode: null,
        couponRef: null,
        benefitRef: null,
      };
      
      if (couponId || freeShippingBenefitId) {
        discountResult = await validateDiscounts(
          tx,
          db,
          buyerId,
          couponId,
          freeShippingBenefitId,
          cartCalculatedTotal || 0
        );
      }
  
      const preCalc = requestData.serverCalculation || null;
  
  let serverFinalTotal;
  let serverDeliveryPrice;
  let serverCouponDiscount;
  
  if (preCalc) {
    serverFinalTotal = preCalc.finalTotal;
    serverDeliveryPrice = preCalc.deliveryPrice;
    serverCouponDiscount = preCalc.couponDiscount;
    console.log(`💰 Using pre-calculated totals: final=${serverFinalTotal}, delivery=${serverDeliveryPrice}, coupon=-${serverCouponDiscount}`);
  } else {
    serverDeliveryPrice = discountResult.freeShippingApplied ? 0 : (clientDeliveryPrice || 0);
    serverCouponDiscount = discountResult.couponDiscount;
    serverFinalTotal = Math.max(0, (cartCalculatedTotal || 0) - serverCouponDiscount) + serverDeliveryPrice;
    console.log(`💰 Fallback calculation: final=${serverFinalTotal}, delivery=${serverDeliveryPrice}, coupon=-${serverCouponDiscount}`);
  }
  
      console.log(`Price calculation - Subtotal: ${cartCalculatedTotal}, Coupon: -${serverCouponDiscount}, Delivery: ${serverDeliveryPrice}, Final: ${serverFinalTotal}`);
  
      // BATCH FETCH PRODUCTS
      productsMeta = await batchFetchProducts(tx, db, items);
  
      // BATCH FETCH SELLERS
      await batchFetchSellers(tx, db, productsMeta);
  
      // STOCK VALIDATION
      const totalPrice = cartCalculatedTotal || 0;
      let totalQuantity = 0;
      const shopTotals = new Map();
      const userTotals = new Map();
      const sellerGroups = new Map();
  
      for (const {data, item} of productsMeta) {
        const qty = Math.max(1, item.quantity || 1);
        const colorKey = item.selectedColor;
      
        // ✅ FIX: Check if color EXISTS first (don't check stock yet)
        const hasColorVariant = colorKey && 
                                data.colorQuantities && 
                                Object.prototype.hasOwnProperty.call(data.colorQuantities, colorKey);
      
        // ✅ FIX: Get available stock (0 if color doesn't exist)
        const available = hasColorVariant ? (data.colorQuantities[colorKey] || 0) : (data.quantity || 0);
      
        // ✅ FIX: Detailed error message with actual values
        if (available < qty) {
          const stockInfo = hasColorVariant ? `color '${colorKey}' stock: ${available}` : `general stock: ${available}`;
          
          throw new HttpsError(
            'failed-precondition',
            `Not enough stock for ${data.productName}. ` +
            `Requested: ${qty}, Available: ${available} (${stockInfo})`,
          );
        }
      
        totalQuantity += qty;
      
        if (data.shopId) {
          shopTotals.set(data.shopId, (shopTotals.get(data.shopId) || 0) + qty);
        } else {
          userTotals.set(data.userId, (userTotals.get(data.userId) || 0) + qty);
        }
      }
  
      // BUILD SELLER GROUPS FOR RECEIPT
      for (const meta of productsMeta) {
        const {data, item} = meta;
        const sellerId = data.shopId || data.userId;
  
        if (!sellerGroups.has(sellerId)) {
          sellerGroups.set(sellerId, {
            sellerName: meta.sellerName,
            items: [],
          });
        }
  
        const dynamicAttributes = {};
        const systemFields = new Set([
          'productId', 'quantity', 'addedAt', 'updatedAt',
          'sellerId', 'sellerName', 'isShop',
          'salePreferences', 'calculatedUnitPrice', 'calculatedTotal', 'isBundleItem',
          'price', 'finalPrice', 'unitPrice', 'totalPrice', 'currency',
          'bundleInfo', 'isBundle', 'bundleId', 'mainProductPrice', 'bundlePrice',
          'selectedColorImage', 'productImage',
          'productName', 'brandModel', 'brand', 'category', 'subcategory',
          'subsubcategory', 'condition', 'averageRating', 'productAverageRating',
          'reviewCount', 'productReviewCount', 'clothingType',
          'clothingFit', 'gender',
          'shipmentStatus', 'deliveryOption', 'needsProductReview',
          'needsSellerReview', 'needsAnyReview', 'timestamp',
          'availableStock', 'maxQuantityAllowed', 'ourComission', 'sellerContactNo', 'showSellerHeader',       
        ]);
  
        Object.keys(item).forEach((key) => {
          if (!systemFields.has(key) && item[key] !== undefined && item[key] !== null && item[key] !== '') {
            dynamicAttributes[key] = item[key];
          }
        });
  
        sellerGroups.get(sellerId).items.push({
          productName: data.productName || 'Unknown Product',
          quantity: item.quantity || 1,
          unitPrice: item.calculatedUnitPrice || data.price,
          totalPrice: item.calculatedTotal || ((data.price || 0) * (item.quantity || 1)),
          selectedAttributes: dynamicAttributes,
          sellerName: meta.sellerName,
          sellerId: data.shopId || data.userId,
        });
      }
  
      
      const timestamp = admin.firestore.FieldValue.serverTimestamp();
  
      const orderDocument = {
        buyerId,
        buyerName,
        totalPrice: serverFinalTotal,
        totalQuantity,
        deliveryPrice: serverDeliveryPrice,
        paymentMethod,
        paymentOrderId: paymentOrderId || null,
        deliveryOption,
        timestamp,
        itemCount: items.length,
        couponId: couponId || null,
        couponCode: discountResult.couponCode || null,
        couponDiscount: serverCouponDiscount,
        freeShippingApplied: discountResult.freeShippingApplied,
        freeShippingBenefitId: freeShippingBenefitId || null,
        itemsSubtotal: cartCalculatedTotal || 0, 
      };
  
      if (deliveryOption === 'pickup') {
        orderDocument.pickupPoint = {
          pickupPointId: pickupPoint.pickupPointId,
          pickupPointName: pickupPoint.pickupPointName,
          pickupPointAddress: pickupPoint.pickupPointAddress,
          pickupPointPhone: pickupPoint.pickupPointPhone || null,
          pickupPointHours: pickupPoint.pickupPointHours || null,
          pickupPointContactPerson: pickupPoint.pickupPointContactPerson || null,
          pickupPointNotes: pickupPoint.pickupPointNotes || null,
          pickupPointLocation: pickupPoint.pickupPointLocation ?
            new admin.firestore.GeoPoint(
              pickupPoint.pickupPointLocation.latitude,
              pickupPoint.pickupPointLocation.longitude,
            ) : null,
        };
      } else {
        orderDocument.address = {
          addressLine1: address.addressLine1,
          addressLine2: address.addressLine2 || '',
          city: address.city,
          phoneNumber: address.phoneNumber,
          location: new admin.firestore.GeoPoint(
            address.location.latitude,
            address.location.longitude,
          ),
        };
      }
  
      if (couponId || freeShippingBenefitId) {
        markDiscountsAsUsed(tx, discountResult, finalOrderId);
      }
  
      tx.set(orderRef, orderDocument);
  
      // WRITE ITEMS & UPDATE INVENTORY ATOMICALLY
      const now = admin.firestore.FieldValue.serverTimestamp();
      const receiptItems = [];
  
      for (const meta of productsMeta) {
        const {ref, data, item, sellerName} = meta;
        const qty = Math.max(1, item.quantity || 1);
        const colorKey = item.selectedColor;
  
        const hasColorVariant = colorKey && 
                            data.colorQuantities && 
                            Object.prototype.hasOwnProperty.call(data.colorQuantities, colorKey);
  
        let productImage = '';
        let selectedColorImage = '';
  
        if (colorKey && data.colorImages && data.colorImages[colorKey] &&
            Array.isArray(data.colorImages[colorKey]) && data.colorImages[colorKey].length > 0) {
          productImage = data.colorImages[colorKey][0];
          selectedColorImage = data.colorImages[colorKey][0];
        } else if (Array.isArray(data.imageUrls) && data.imageUrls.length > 0) {
          productImage = data.imageUrls[0];
        }
  
        const orderItemData = {
          orderId: orderRef.id,
          buyerId: buyerId,
          productId: ref.id,
          productName: data.productName || 'Unknown Product',
          price: data.price || 0,
          currency: data.currency || 'TL',
          quantity: qty,
          sellerName,
          sellerContactNo: meta.sellerContactNo,
          gatheringStatus: 'pending',
          sellerAddress: meta.sellerAddress,
          buyerName,
          productImage,
          selectedColorImage: selectedColorImage || null,        
          brandModel: data.brandModel || null,
          category: data.category || null,
          subcategory: data.subcategory || null,
          subsubcategory: data.subsubcategory || null,
          condition: data.condition || null,
          sellerId: data.shopId || data.userId,
          shopId: data.shopId || null,
          isShopProduct: !!data.shopId,
          ourComission: item.ourComission || 0,
          bundleInfo: item.isBundleItem && item.calculatedUnitPrice && item.calculatedUnitPrice < data.price ? {
            wasInBundle: true,
            originalPrice: data.price,
            bundlePrice: item.calculatedUnitPrice,
            bundleDiscount: Math.round(((data.price - item.calculatedUnitPrice) / data.price) * 100),
            bundleDiscountAmount: data.price - item.calculatedUnitPrice,
            originalBundleDiscountPercentage: data.bundleDiscount || null,
          } : null,
          salePreferenceInfo: (() => {
            const salePrefs = item.salePreferences;
            if (salePrefs && salePrefs.discountThreshold && salePrefs.discountPercentage) {
              const quantity = Math.max(1, item.quantity || 1);
              const meetsThreshold = quantity >= salePrefs.discountThreshold;
              return {
                discountThreshold: salePrefs.discountThreshold,
                discountPercentage: salePrefs.discountPercentage,
                discountApplied: meetsThreshold,
                wasSalePrefUsed: item.calculatedUnitPrice &&
                                  item.calculatedUnitPrice < (data.price * (1 - (salePrefs.discountPercentage / 100))) + 0.01,
              };
            }
            return null;
          })(),
          deliveryOption,
          needsProductReview: true,
          needsSellerReview: true,
          needsAnyReview: true,
        };
  
        const dynamicAttributes = {};
        const systemFields = new Set([
          'productId', 'quantity', 'addedAt', 'updatedAt',
          'sellerId', 'sellerName', 'isShop', 'salePreferences',         
        ]);
  
        Object.keys(item).forEach((key) => {
          if (!systemFields.has(key) && item[key] !== undefined && item[key] !== null && item[key] !== '') {
            dynamicAttributes[key] = item[key];
          }
        });
  
        if (Object.keys(dynamicAttributes).length > 0) {
          orderItemData.selectedAttributes = dynamicAttributes;
        }
  
        const oiRef = orderRef.collection('items').doc();
        tx.set(oiRef, {
          ...orderItemData,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        receiptItems.push({
          productName: data.productName || 'Unknown Product',
          quantity: qty,
          unitPrice: item.calculatedUnitPrice || data.price,
          totalPrice: item.calculatedTotal || (data.price * qty),
          selectedAttributes: dynamicAttributes,
          sellerName,
          sellerId: data.shopId || data.userId,
        });
  
        // ATOMIC INVENTORY UPDATE
        const updates = {
          purchaseCount: admin.firestore.FieldValue.increment(qty),
          metricsUpdatedAt: now,
        };
        
        const isCurtain = data.subsubcategory === 'Curtains';
        
        if (!isCurtain) {
          // ✅ Use the same hasColorVariant variable
          if (hasColorVariant) {
            updates[`colorQuantities.${colorKey}`] = admin.firestore.FieldValue.increment(-qty);
          } else {
            updates.quantity = admin.firestore.FieldValue.increment(-qty);
          }
        }
        
        tx.update(ref, updates);
  
        // Collect notification data for post-transaction processing
        if (data.shopId) {
          // Shop product: Add ONE entry for shop_notifications (not per member)
          notificationData.push({
            productId: ref.id,
            productName: data.productName || 'Unknown Product',
            recipientId: null,  // No individual recipient
            quantity: qty,
            shopId: data.shopId,
            shopName: meta.sellerName,
            sellerId: data.shopId,
            isShopProduct: true,
          });
        } else if (data.userId && data.userId !== buyerId) {
          notificationData.push({
            productId: ref.id,
            productName: data.productName || 'Unknown Product',
            recipientId: data.userId,
            quantity: qty,
            shopId: null,
            sellerId: data.userId,
            isShopProduct: false,
          });
        }
      }
  
      // UPDATE SELLER METRICS
      userTotals.forEach((qty, uid) => {
        let userTotalPrice = 0;
        for (const {data, item} of productsMeta) {
          if (data.userId === uid && !data.shopId) {
            const itemPrice = item.calculatedTotal || ((data.price || 0) * (item.quantity || 1));
            userTotalPrice += itemPrice;
          }
        }
  
        tx.update(db.collection('users').doc(uid), {
          totalProductsSold: admin.firestore.FieldValue.increment(qty),
          totalSoldPrice: admin.firestore.FieldValue.increment(userTotalPrice),
        });
      });
  
      shopTotals.forEach((qty, sid) => {
        let shopTotalPrice = 0;
        for (const {data, item} of productsMeta) {
          if (data.shopId === sid) {
            const itemPrice = item.calculatedTotal || ((data.price || 0) * (item.quantity || 1));
            shopTotalPrice += itemPrice;
          }
        }
  
        tx.update(db.collection('shops').doc(sid), {
          totalProductsSold: admin.firestore.FieldValue.increment(qty),
          totalSoldPrice: admin.firestore.FieldValue.increment(shopTotalPrice),
        });
      });
  
      if (saveAddress && deliveryOption !== 'pickup' && address) {
        const savedAddress = {
          addressLine1: address.addressLine1,
          addressLine2: address.addressLine2 || '',
          city: address.city,
          phoneNumber: address.phoneNumber,
          location: new admin.firestore.GeoPoint(
            address.location.latitude,
            address.location.longitude,
          ),
          addedAt: now,
        };
        tx.set(buyerRef.collection('addresses').doc(), savedAddress);
      }
  
      // CREATE RECEIPT GENERATION TASK
      const receiptTaskRef = db.collection('receiptTasks').doc();
      tx.set(receiptTaskRef, {
        ...removeUndefined({
          orderId: orderRef.id,
          ownerId: buyerId, // ✅ ADD THIS LINE
          ownerType: 'user',  
          buyerId,
          buyerName,
          items: receiptItems,
          sellerGroups: Array.from(sellerGroups.values()),
          totalPrice: serverFinalTotal,
          itemsSubtotal: totalPrice,
          currency: 'TL',
          paymentMethod,
          deliveryOption,
          deliveryPrice: serverDeliveryPrice,
          couponDiscount: serverCouponDiscount,
          couponCode: discountResult.couponCode,
          freeShippingApplied: discountResult.freeShippingApplied,
          originalDeliveryPrice: preCalc ? preCalc.deliveryPriceBeforeFreeShipping : (clientDeliveryPrice || 0),
          language: userLanguage,
          status: 'pending',
          pickupPoint: deliveryOption === 'pickup' ? {
            name: pickupPoint.pickupPointName,
            address: pickupPoint.pickupPointAddress,
            phone: pickupPoint.pickupPointPhone || null,
            hours: pickupPoint.pickupPointHours || null,
            contactPerson: pickupPoint.pickupPointContactPerson || null,
            notes: pickupPoint.pickupPointNotes || null,
          } : null,
          buyerAddress: deliveryOption !== 'pickup' ? address : null,
        }),
        orderDate: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  
      orderResult = {
        orderId: orderRef.id,
        buyerName,
      };
    });
  
    if (orderResult && orderResult.duplicate) {
      return orderResult;// Return early if duplicate was found
    }
  
    Promise.resolve().then(async () => {
      try {
        const productIds = items.map((item) => item.productId);
        const shopIds = [...new Set(productsMeta
          .filter((meta) => meta.data.shopId)
          .map((meta) => meta.data.shopId))];
  
        await trackAdConversionInternal(buyerId, finalOrderId, productIds, shopIds);
      } catch (convError) {
        console.error('Error tracking ad conversion:', convError);
        logTaskFailureAlert('ad_conversion', finalOrderId, buyerId, orderResult?.buyerName, convError);
      }
    });
  
    Promise.allSettled(
      notificationData.map((notif) =>
        createNotificationTask(
          orderResult.orderId,
          notif,
          notif.recipientId,
          orderResult.buyerName,
          buyerId,
        ),
      ),
    ).then((results) => {
      const failed = results.filter((r) => r.status === 'rejected').length;
      const succeeded = results.length - failed;
      if (results.length > 0) {
        console.log(`Notifications: ${succeeded} succeeded, ${failed} failed out of ${results.length}`);
      }
      if (failed > 0) {
        results.forEach((result, idx) => {
          if (result.status === 'rejected') {
            console.error(`Notification ${idx} failed:`, result.reason?.message || result.reason);
          }
        });
        logTaskFailureAlert('notification_partial', finalOrderId, buyerId, orderResult?.buyerName, {message: `${failed}/${results.length} notifications failed`});
      }
    }).catch((err) => {
      console.error('Unexpected error in notification batch:', err);
      logTaskFailureAlert('notifications', finalOrderId, buyerId, orderResult?.buyerName, err);
    });
  
    Promise.resolve().then(async () => {
      try {
        const purchasedProductIds = items.map((item) => item.productId);
        await createCartClearTask(buyerId, purchasedProductIds, finalOrderId);
      } catch (cartClearError) {
        console.error('Error creating cart clear task:', cartClearError);
        logTaskFailureAlert('cart_clear', finalOrderId, buyerId, orderResult?.buyerName, cartClearError);
      }
    });
  
    Promise.resolve().then(async () => {
      try {
        const trackingItems = productsMeta.map(({data, item}) => ({
          productId: data.id || item.productId,
          shopId: data.shopId || null,
          category: data.category,
          subcategory: data.subcategory,
          subsubcategory: data.subsubcategory,
          brandModel: data.brandModel,
          price: item.calculatedUnitPrice || data.price,
          quantity: item.quantity || 1,
        }));
        
        await trackPurchaseActivity(buyerId, trackingItems, finalOrderId);
      } catch (trackingError) {
        console.error('User activity tracking failed:', trackingError);
        logTaskFailureAlert('activity_tracking', finalOrderId, buyerId, orderResult?.buyerName, trackingError);
      }
    });
  
    Promise.resolve().then(async () => {
      try {
        await createQRCodeTask(finalOrderId, {
          buyerId,
          buyerName: orderResult.buyerName,
          items: items,
          totalPrice: cartCalculatedTotal,
          deliveryOption,
        });
      } catch (qrError) {
        console.error('Error creating QR code task:', qrError);
        logTaskFailureAlert('qr_code', finalOrderId, buyerId, orderResult?.buyerName, qrError);
      }
    });
  
    return {
      orderId: orderResult.orderId,
      success: true,
      receiptPending: true,    
    };
  }
  
  // Helper to remove undefined values - PRESERVES FIELDVALUE
  function removeUndefined(obj) {
    if (Array.isArray(obj)) {
      return obj.map((item) => removeUndefined(item));
    }
  
    if (!obj || typeof obj !== 'object') {
      return obj;
    }
  
    if (obj instanceof admin.firestore.Timestamp || obj instanceof admin.firestore.GeoPoint) {
      return obj;
    }
  
    if (obj.constructor && obj.constructor.name === 'FieldValue') {
      return obj;
    }
  
    const cleaned = {};
    for (const [key, value] of Object.entries(obj)) {
      if (value !== undefined) {
        if (value && typeof value === 'object' &&
            value.constructor && value.constructor.name === 'FieldValue') {
          cleaned[key] = value;
        } else if (value && typeof value === 'object') {
          cleaned[key] = removeUndefined(value);
        } else {
          cleaned[key] = value;
        }
      }
    }
    return cleaned;
  }
  
  // Cloud Task handler for notifications
  export const processOrderNotification = onRequest(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 30,
      invoker: 'private',
    },
    async (request, response) => {
      try {
        const {
          orderId,
          productId,
          productName,
          recipientId,
          buyerName,
          buyerId,
          quantity,
          shopId,
          shopName,
          sellerId,
          isShopProduct,
        } = request.body;
  
        const db = admin.firestore();
  
        if (isShopProduct && shopId) {
          // ✅ Shop product: Write to shop_notifications only
          const shopNotificationId = `${orderId}_${productId}`;
          await db.collection('shop_notifications').doc(shopNotificationId).set({
            type: 'product_sold',
            shopId,
            shopName: shopName || 'Your Shop',
            productId,
            productName,
            buyerName,
            buyerId,
            orderId,
            quantity,
            sellerId,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isRead: {},
            message_en: `Product "${productName}" has been sold!`,
            message_tr: `"${productName}" ürünü satıldı!`,
            message_ru: `Продукт "${productName}" был продан!`,
          });
        } else if (recipientId) {
          // ✅ Individual seller: Write to user's notifications
          await db.collection('users').doc(recipientId).collection('notifications').doc().set({
            type: 'product_sold_user',
            productId,
            productName,
            buyerName,
            buyerId,
            orderId,
            quantity,
            shopId: null,
            sellerId,
            isShopProduct: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
            message: `Your product "${productName}" has been sold!`,
            message_en: `Your product "${productName}" has been sold!`,
            message_tr: `Ürününüz "${productName}" satıldı!`,
            message_ru: `Ваш продукт "${productName}" был продан!`,
          });
        }
  
        response.status(200).send('Notification created');
      } catch (error) {
        console.error('Error creating notification:', error);
        response.status(500).send('Error creating notification');
      }
    },
  );
  
  export const processPurchase = onCall(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 60,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'You must be signed in to checkout.');
      }
  
      return createOrderTransaction(request.auth.uid, request.data || {});
    },
  );
  
  export const initializeIsbankPayment = onCall(
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
  
        const {
          amount,            // Client-calculated (kept for logging/comparison only)
          orderNumber,
          customerName,
          customerEmail,
          customerPhone,
          cartData,
        } = request.data;
  
        const sanitizedCustomerName = (() => {
          if (!customerName) return 'Customer';
          const sanitized = transliterate(customerName)
            .replace(/[^a-zA-Z0-9\s]/g, '')
            .trim()
            .substring(0, 50);
          return sanitized || 'Customer';
        })();
  
        if (!orderNumber || !cartData) {
          throw new HttpsError('invalid-argument', 'orderNumber and cartData are required');
        }
  
        // ═══════════════════════════════════════════════════════════════
        // SERVER-SIDE TOTAL CALCULATION — Single Source of Truth
        // ═══════════════════════════════════════════════════════════════
        const db = admin.firestore();
        const userId = request.auth.uid;
  
        const cartCalculatedTotal = parseFloat(cartData.cartCalculatedTotal) || 0;
        const deliveryOption = cartData.deliveryOption || 'normal';
        const couponId = cartData.couponId || null;
        const freeShippingBenefitId = cartData.freeShippingBenefitId || null;
  
        // --- 1. Fetch delivery settings from Firestore ---
        let deliverySettings = null;
        try {
          const deliveryDoc = await db.collection('settings').doc('delivery').get();
          if (deliveryDoc.exists) {
            deliverySettings = deliveryDoc.data();
          }
        } catch (e) {
          console.error('Failed to fetch delivery settings:', e);
        }
  
        // --- 2. Calculate server-side delivery price ---
        const serverDeliveryPriceRaw = calculateDeliveryPrice(
          deliveryOption,
          cartCalculatedTotal,
          deliverySettings,
        );
  
        // --- 3. Validate coupon & free shipping (read-only, no marking as used) ---
        let serverCouponDiscount = 0;
        let serverFreeShippingApplied = false;
        let couponCode = null;
  
        if (couponId) {
          try {
            const couponRef = db.collection('users').doc(userId).collection('coupons').doc(couponId);
            const couponDoc = await couponRef.get();
  
            if (couponDoc.exists) {
              const coupon = couponDoc.data();
              if (!coupon.isUsed && (!coupon.expiresAt || coupon.expiresAt.toDate() >= new Date())) {
                serverCouponDiscount = Math.min(coupon.amount || 0, cartCalculatedTotal);
                couponCode = coupon.code || null;
              } else {
                console.warn(`Coupon ${couponId} is invalid (used or expired)`);
                // Don't throw — let createOrderTransaction handle the final validation
                // This is just pre-calculation
              }
            }
          } catch (e) {
            console.error('Coupon validation failed:', e);
            // Continue without coupon — createOrderTransaction will validate again
          }
        }
  
        if (freeShippingBenefitId) {
          try {
            const benefitRef = db.collection('users').doc(userId).collection('benefits').doc(freeShippingBenefitId);
            const benefitDoc = await benefitRef.get();
  
            if (benefitDoc.exists) {
              const benefit = benefitDoc.data();
              if (!benefit.isUsed && (!benefit.expiresAt || benefit.expiresAt.toDate() >= new Date())) {
                serverFreeShippingApplied = true;
              } else {
                console.warn(`Benefit ${freeShippingBenefitId} is invalid (used or expired)`);
              }
            }
          } catch (e) {
            console.error('Benefit validation failed:', e);
          }
        }
  
        // --- 4. Compute final delivery price (apply free shipping) ---
        const serverDeliveryPrice = serverFreeShippingApplied ? 0 : serverDeliveryPriceRaw;
  
        // --- 5. Calculate the REAL final total ---
        const serverFinalTotal = Math.max(0, cartCalculatedTotal - serverCouponDiscount) + serverDeliveryPrice;
  
        // --- 6. Log comparison for monitoring ---
        const clientAmount = parseFloat(amount) || 0;
        const discrepancy = Math.abs(serverFinalTotal - clientAmount);
        if (discrepancy > 0.01) {
          console.warn(`⚠️ PRICE DISCREPANCY: client=${clientAmount}, server=${serverFinalTotal}, diff=${discrepancy.toFixed(2)}`);
          console.warn(`  Breakdown: subtotal=${cartCalculatedTotal}, coupon=-${serverCouponDiscount}, delivery=+${serverDeliveryPrice}`);
        }
  
        console.log(`💰 Server total: ${serverFinalTotal} (subtotal: ${cartCalculatedTotal}, coupon: -${serverCouponDiscount}, delivery: +${serverDeliveryPrice})`);
  
        // ═══════════════════════════════════════════════════════════════
        // USE SERVER-CALCULATED TOTAL FOR BANK
        // ═══════════════════════════════════════════════════════════════
        const formattedAmount = Math.round(serverFinalTotal).toString();
        const rnd = Date.now().toString();
  
        const baseUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
        const okUrl = `${baseUrl}/isbankPaymentCallback`;
        const failUrl = `${baseUrl}/isbankPaymentCallback`;
        const callbackUrl = `${baseUrl}/isbankPaymentCallback`;
        const isbankConfig = await getIsbankConfig();
  
        const hashParams = {
          BillToName: sanitizedCustomerName || '',
          amount: formattedAmount,
          callbackurl: callbackUrl,
          clientid: isbankConfig.clientId,
          currency: isbankConfig.currency,
          email: customerEmail || '',
          failurl: failUrl,
          hashAlgorithm: 'ver3',
          islemtipi: 'Auth',
          lang: 'tr',
          oid: orderNumber,
          okurl: okUrl,
          rnd: rnd,
          storetype: isbankConfig.storeType,
          taksit: '',
          tel: customerPhone || '',
        };
  
        const hash = await generateHashVer3(hashParams);
  
        const paymentParams = {
          clientid: isbankConfig.clientId,
          storetype: isbankConfig.storeType,
          hash: hash,
          hashAlgorithm: 'ver3',
          islemtipi: 'Auth',
          amount: formattedAmount,
          currency: isbankConfig.currency,
          oid: orderNumber,
          okurl: okUrl,
          failurl: failUrl,
          callbackurl: callbackUrl,
          lang: 'tr',
          rnd: rnd,
          taksit: '',
          BillToName: sanitizedCustomerName || '',
          email: customerEmail || '',
          tel: customerPhone || '',
        };
  
        console.log('Hash params:', JSON.stringify(hashParams, null, 2));
        console.log('Payment params being sent:', JSON.stringify(paymentParams, null, 2));
  
        const timestamp = admin.firestore.FieldValue.serverTimestamp();
  
        await db.collection('pendingPayments').doc(orderNumber).set({
          userId: request.auth.uid,
          amount: serverFinalTotal,              // ✅ Server-calculated
          formattedAmount: formattedAmount,
          clientAmount: clientAmount,            // ✅ Keep client value for comparison/debugging
          orderNumber: orderNumber,
          status: 'awaiting_3d',
          paymentParams: paymentParams,
          cartData: cartData,
          customerInfo: {
            name: sanitizedCustomerName,
            email: customerEmail,
            phone: customerPhone,
          },
          // ✅ NEW: Pre-calculated values for createOrderTransaction
          serverCalculation: {
            itemsSubtotal: cartCalculatedTotal,
            couponDiscount: serverCouponDiscount,
            couponCode: couponCode,
            deliveryPrice: serverDeliveryPrice,
            deliveryPriceBeforeFreeShipping: serverDeliveryPriceRaw,
            freeShippingApplied: serverFreeShippingApplied,
            finalTotal: serverFinalTotal,
            deliveryOption: deliveryOption,
            calculatedAt: new Date().toISOString(),
          },
          createdAt: timestamp,
          expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
        });
  
        return {
          success: true,
          gatewayUrl: isbankConfig.gatewayUrl,
          paymentParams: paymentParams,
          orderNumber: orderNumber,
        };
      } catch (error) {
        console.error('İşbank payment initialization error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );
  
  function escapeHtml(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#x27;');
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // NEW HELPER: Calculate delivery price (mirrors Flutter logic exactly)
  // ═══════════════════════════════════════════════════════════════════════
  function calculateDeliveryPrice(deliveryOption, cartTotal, deliverySettings) {
    if (!deliverySettings) {
      // Fallback defaults (same as Flutter defaults)
      const defaults = {
        normal: { price: 150, freeThreshold: 2000 },
        express: { price: 350, freeThreshold: 10000 },
      };
      const opt = defaults[deliveryOption] || defaults.normal;
      return cartTotal >= opt.freeThreshold ? 0 : opt.price;
    }
  
    const optionSettings = deliverySettings[deliveryOption] || deliverySettings['normal'];
    if (!optionSettings) {
      return 0;
    }
  
    const price = parseFloat(optionSettings.price) || 0;
    const freeThreshold = parseFloat(optionSettings.freeThreshold) || Infinity;
  
    return cartTotal >= freeThreshold ? 0 : price;
  }
  
  async function generateHashVer3(params) {
    // Get all parameter keys except 'hash' and 'encoding'!!!
    const keys = Object.keys(params)
      .filter((key) => key !== 'hash' && key !== 'encoding')
      .sort((a, b) => {
        // Case-insensitive sort - convert both to lowercase for comparison
        return a.toLowerCase().localeCompare(b.toLowerCase());
      });
      const isbankConfig = await getIsbankConfig();
    // Build the plain text with pipe separators
    const values = keys.map((key) => {
      let value = String(params[key] || '');
      // Escape special characters as per documentation
      value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
      return value;
    });
  
    const plainText = values.join('|') + '|' + isbankConfig.storeKey;
  
    console.log('Hash keys order:', keys.join('|'));
    console.log('Hash plain text:', plainText);
  
    return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
  }
  
  async function issueIsbankRefund(paymentOrderId, currency = '949') {
    const config = await getIsbankConfig();
    const API_URL = 'https://sanalpos.isbank.com.tr/fim/api';
    const attemptTypes = ['Void', 'Credit'];
  
    for (const type of attemptTypes) {
      const xmlBody = `<?xml version="1.0" encoding="UTF-8"?>
  <CC5Request>
    <Name>${config.apiUser}</Name>
    <Password>${config.apiPassword}</Password>
    <ClientId>${config.clientId}</ClientId>
    <Type>${type}</Type>
    <OrderId>${paymentOrderId}</OrderId>
  </CC5Request>`;
  
      let rawText = '';
      try {
        const res = await fetch(API_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'text/xml; charset=UTF-8' },
          body: xmlBody,
          signal: AbortSignal.timeout(15000),
        });
        rawText = await res.text();
      } catch (fetchErr) {
        console.error(`[Refund] Network error on ${type}:`, fetchErr.message);
        continue;
      }
  
      const get = (tag) => {
        const m = rawText.match(new RegExp(`<${tag}>([^<]*)</${tag}>`));
        return m ? m[1].trim() : '';
      };
  
      const procCode = get('ProcReturnCode');
      const bankResp = get('Response');
      const errMsg = get('ErrMsg');
  
      console.log(`[Refund] ${type} → ProcReturnCode=${procCode} Response=${bankResp}`);
  
      if (procCode === '00' && bankResp === 'Approved') {
        return { success: true, type, procCode };
      }
  
      const alreadySettled =
        errMsg.toLowerCase().includes('settled') ||
        errMsg.toLowerCase().includes('not found') ||
        procCode === '99';
  
      if (type === 'Void' && alreadySettled) {
        console.log('[Refund] Void failed (already settled), trying Credit...');
        continue;
      }
  
      throw new Error(`İşbank ${type} rejected: ${errMsg || procCode}`);
    }
  
    throw new Error('[Refund] Both Void and Credit failed.');
  }
  
  async function attemptAutoRefundProduct(db, oid, pendingPayment) {
    const alertRef = db.collection('_payment_alerts').doc(`product_${oid}`);
  
    // Safety check: never refund if an order already exists
    const existingOrder = await db.collection('orders')
      .where('paymentOrderId', '==', oid)
      .limit(1)
      .get();
  
    if (!existingOrder.empty) {
      console.warn(`[Refund] BLOCKED — order ${existingOrder.docs[0].id} already exists for ${oid}. Not refunding.`);
      await db.collection('pendingPayments').doc(oid).update({
        status: 'completed',
        orderId: existingOrder.docs[0].id,
        note: 'Order found during refund safety check',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return false;
    }
  
    try {
      const result = await issueIsbankRefund(oid);
  
      await alertRef.set({
        type: 'product_order_creation_failed',
        severity: 'low',
        paymentOrderId: oid,
        userId: pendingPayment.userId,
        amount: pendingPayment.amount,
        refundType: result.type,
        requiresRefund: false,
        isResolved: true,
        isRead: false,
        resolvedNote: `Auto-refunded via ${result.type}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
  
      await db.collection('pendingPayments').doc(oid).update({
        status: 'refunded',
        refundType: result.type,
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  
      console.log(`[Refund] Product auto-refund (${result.type}) succeeded for ${oid}`);
      return true;
    } catch (refundErr) {
      console.error('[Refund] Product auto-refund failed:', refundErr.message);
  
      await alertRef.set({
        type: 'product_order_creation_failed',
        severity: 'critical',
        paymentOrderId: oid,
        userId: pendingPayment.userId,
        amount: pendingPayment.amount,
        requiresRefund: true,
        autoRefundError: refundErr.message,
        isResolved: false,
        isRead: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
  
      return false;
    }
  }
  
  export const isbankPaymentCallback = onRequest(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 90,
      cors: true,
      invoker: 'public',
    },
    async (request, response) => {
      const startTime = Date.now();
      const db = admin.firestore();
      const isbankConfig = await getIsbankConfig();
      try {
        console.log('Callback invoked - method:', request.method);
        console.log('All callback parameters:', JSON.stringify(request.body, null, 2));
  
        const {
          Response,
          mdStatus,
          oid,
          ProcReturnCode,
          ErrMsg,
          HASH,
          HASHPARAMSVAL,
        } = request.body;
  
        // Validate required fields
        if (!oid) {
          console.error('Missing oid in callback. Full body:', request.body);
          response.status(400).send('Order number missing');
          return;
        }
  
        // Log every callback attempt for forensics
        const callbackLogRef = db.collection('payment_callback_logs').doc();
        await callbackLogRef.set({
          oid: oid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          requestBody: request.body,
          userAgent: request.headers['user-agent'] || null,
          ip: request.ip || request.headers['x-forwarded-for'] || null,
          processingStarted: new Date(startTime).toISOString(),
        });
  
        const pendingPaymentRef = db.collection('pendingPayments').doc(oid);
  
        // CRITICAL: Use transaction for atomic operations
        const transactionResult = await db.runTransaction(async (transaction) => {
          const pendingPaymentSnap = await transaction.get(pendingPaymentRef);
  
          if (!pendingPaymentSnap.exists) {
            return {
              error: 'not_found',
              message: 'Payment session not found',
            };
          }
  
          const pendingPayment = pendingPaymentSnap.data();
  
          // Check if already processed (idempotency check)
          if (pendingPayment.status === 'completed') {
            console.log(`Payment ${oid} already completed with order ${pendingPayment.orderId}`);
            return {
              alreadyProcessed: true,
              orderId: pendingPayment.orderId,
              status: 'completed',
              message: 'Payment already successfully processed',
            };
          }
  
          if (pendingPayment.status === 'payment_succeeded_order_failed') {
            console.log(`Payment ${oid} succeeded but order creation failed previously`);
            return {
              alreadyProcessed: true,
              status: 'payment_succeeded_order_failed',
              message: 'Payment succeeded but order creation failed',
            };
          }
  
          if (pendingPayment.status === 'payment_failed') {
            console.log(`Payment ${oid} already marked as failed`);
            return {
              alreadyProcessed: true,
              status: 'payment_failed',
              message: 'Payment already marked as failed',
            };
          }
  
          // Only proceed if status is awaiting_3d
          if (pendingPayment.status !== 'awaiting_3d') {
            console.warn(`Unexpected status for ${oid}: ${pendingPayment.status}`);
  
            // If it's processing, another callback is handling it
            if (pendingPayment.status === 'processing' ||
                pendingPayment.status === 'payment_verified_processing_order') {
              // Wait a bit and check if it completes
              return {
                retry: true,
                currentStatus: pendingPayment.status,
                pendingPayment: pendingPayment,
              };
            }
  
            return {
              alreadyProcessed: true,
              status: pendingPayment.status,
              message: 'Payment in unexpected state',
            };
          }
  
           // Verify hash — reject if missing or wrong
           if (!HASHPARAMSVAL || !HASH) {
            console.error('[Payment] Callback missing hash fields — rejecting.');
            transaction.update(pendingPaymentRef, {
              status: 'hash_verification_failed',
              errorMessage: 'Missing hash fields',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              callbackLogId: callbackLogRef.id,
            });
            return { error: 'hash_failed', message: 'Missing hash fields' };
          }
  
          const hashParams = HASHPARAMSVAL + isbankConfig.storeKey;
          const calculatedHash = crypto.createHash('sha512').update(hashParams, 'utf8').digest('base64');
  
          if (calculatedHash !== HASH) {
            console.error('Hash verification failed!');
            transaction.update(pendingPaymentRef, {
              status: 'hash_verification_failed',
              errorMessage: 'Hash verification failed',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              callbackLogId: callbackLogRef.id,
            });
            return { error: 'hash_failed', message: 'Hash verification failed' };
          }
  
          // Check payment status
          const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
          const isTransactionSuccess = Response === 'Approved' && ProcReturnCode === '00';
  
          if (!isAuthSuccess || !isTransactionSuccess) {
            transaction.update(pendingPaymentRef, {
              status: 'payment_failed',
              response: Response,
              mdStatus: mdStatus,
              procReturnCode: ProcReturnCode,
              errorMessage: ErrMsg || 'Payment failed',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              rawResponse: request.body,
              callbackLogId: callbackLogRef.id,
            });
  
            return {
              error: 'payment_failed',
              message: ErrMsg || 'Payment failed',
            };
          }
  
          // Payment successful - mark as processing to prevent race condition
          transaction.update(pendingPaymentRef, {
            status: 'processing',
            response: Response,
            mdStatus: mdStatus,
            procReturnCode: ProcReturnCode,
            processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
            rawResponse: request.body,
            callbackLogId: callbackLogRef.id,
          });
  
          return {
            success: true,
            pendingPayment: pendingPayment,
          };
        });
  
        // Handle transaction results
        if (transactionResult.error) {
          if (transactionResult.error === 'not_found') {
            response.status(404).send('Payment session not found');
            return;
          }
  
          if (transactionResult.error === 'hash_failed') {
            response.send(`
              <!DOCTYPE html>
              <html>
              <head><title>Ödeme Hatası</title></head>
              <body>
                <div style="text-align:center; padding:50px;">
                  <h2>Ödeme Doğrulama Hatası</h2>
                  <p>Lütfen tekrar deneyin.</p>
                </div>
                <script>window.location.href = 'payment-failed://hash-error';</script>
              </body>
              </html>
            `);
            return;
          }
  
          if (transactionResult.error === 'payment_failed') {
            response.send(`
              <!DOCTYPE html>
              <html>
              <head><title>Ödeme Başarısız</title></head>
              <body>
                <div style="text-align:center; padding:50px;">
                  <h2>Ödeme Başarısız</h2>
                  <p>${transactionResult.message}</p>
                </div>
                <script>window.location.href = 'payment-failed://${escapeHtml(encodeURIComponent(transactionResult.message))}';</script>
              </body>
              </html>
            `);
            return;
          }
        }
  
        // Handle already processed payments
        if (transactionResult.alreadyProcessed) {
          console.log(`Payment ${oid} already processed: ${transactionResult.status}`);
  
          if (transactionResult.status === 'completed') {
            response.send(`
              <!DOCTYPE html>
              <html>
              <head><title>Ödeme Başarılı</title></head>
              <body>
                <div style="text-align:center; padding:50px;">
                  <h2>✓ Ödeme Başarılı</h2>
                  <p>Siparişiniz oluşturuldu.</p>
                </div>
                <script>window.location.href = 'payment-success://${escapeHtml(transactionResult.orderId)}';</script>
              </body>
              </html>
            `);
            return;
          } else {
            response.send(`
              <!DOCTYPE html>
              <html>
              <head><title>İşlem Tamamlandı</title></head>
              <body>
                <div style="text-align:center; padding:50px;">
                  <h2>İşlem Zaten İşlendi</h2>
                  <p>${transactionResult.message}</p>
                </div>
                <script>window.location.href = 'payment-status://${escapeHtml(transactionResult.status)}';</script>
              </body>
              </html>
            `);
            return;
          }
        }
  
        // Handle retry case (concurrent processing)
        if (transactionResult.retry) {
          console.log(`Payment ${oid} is being processed by another callback, waiting...`);
  
          // Wait up to 10 seconds for the other process to complete
          let retryCount = 0;
          const maxRetries = 20;
          const retryDelay = 500; // 500ms between checks
  
          while (retryCount < maxRetries) {
            await new Promise((resolve) => setTimeout(resolve, retryDelay));
  
            const checkSnap = await pendingPaymentRef.get();
            const checkData = checkSnap.data();
  
            if (checkData.status === 'completed') {
              response.send(`
                <!DOCTYPE html>
                <html>
                <head><title>Ödeme Başarılı</title></head>
                <body>
                  <div style="text-align:center; padding:50px;">
                    <h2>✓ Ödeme Başarılı</h2>
                    <p>Siparişiniz oluşturuldu.</p>
                  </div>
                  <script>window.location.href = 'payment-success://${escapeHtml(checkData.orderId)}';</script>
                </body>
                </html>
              `);
              return;
            }
  
            if (checkData.status === 'payment_succeeded_order_failed' ||
                checkData.status === 'payment_failed') {
              response.send(`
                <!DOCTYPE html>
                <html>
                <head><title>İşlem Hatası</title></head>
                <body>
                  <div style="text-align:center; padding:50px;">
                    <h2>İşlem Hatası</h2>
                    <p>Lütfen destek ile iletişime geçin.</p>
                  </div>
                  <script>window.location.href = 'payment-failed://processing-error';</script>
                </body>
                </html>
              `);
              return;
            }
  
            retryCount++;
          }
  
          // Timeout waiting for other process
          console.error(`Timeout waiting for payment ${oid} processing`);
          response.status(500).send('Processing timeout');
          return;
        }
  
       // ── Create order (3 attempts with backoff) ─────────────────────
       const MAX_RETRIES = 3;
       let orderResult = null;
       let lastOrderError = null;
  
       for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
         try {
           console.log(`[Payment] Order creation attempt ${attempt} for ${oid}`);
           orderResult = await createOrderTransaction(
             transactionResult.pendingPayment.userId,
             {
               ...transactionResult.pendingPayment.cartData,
               paymentOrderId: oid,
               paymentMethod: 'isbank_3d',
               serverCalculation: transactionResult.pendingPayment.serverCalculation || null,
             },
           );
           lastOrderError = null;
           break;
         } catch (err) {
           lastOrderError = err;
           console.warn(`[Payment] Order creation attempt ${attempt} failed:`, err.message);
           if (attempt < MAX_RETRIES) {
             await new Promise((r) => setTimeout(r, 500 * attempt));
           }
         }
       }
  
       if (orderResult) {
         // ── Happy path ────────────────────────────────────────────────
         await pendingPaymentRef.update({
           status: 'completed',
           orderId: orderResult.orderId,
           completedAt: admin.firestore.FieldValue.serverTimestamp(),
           processingDuration: Date.now() - startTime,
         });
  
         await callbackLogRef.update({
           processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
           orderId: orderResult.orderId,
           success: true,
           processingDuration: Date.now() - startTime,
         });
  
         response.send(`
           <!DOCTYPE html>
           <html>
           <head><title>Ödeme Başarılı</title></head>
           <body>
             <div style="text-align:center; padding:50px;">
               <h2>✓ Ödeme Başarılı</h2>
               <p>Siparişiniz oluşturuldu.</p>
             </div>
             <script>window.location.href = 'payment-success://${escapeHtml(orderResult.orderId)}';</script>
           </body>
           </html>
         `);
         console.log(`[Payment] ${oid} successfully processed → order ${orderResult.orderId}`);
       } else {
         // ── All retries exhausted — attempt auto-refund ───────────────
         console.error('[Payment] All order creation attempts failed:', lastOrderError?.message);
  
         await pendingPaymentRef.update({
           status: 'payment_succeeded_order_failed',
           orderError: lastOrderError?.message,
           retryExhausted: true,
           updatedAt: admin.firestore.FieldValue.serverTimestamp(),
         });
  
         await callbackLogRef.update({
           processingFailed: admin.firestore.FieldValue.serverTimestamp(),
           error: lastOrderError?.message,
           success: false,
         });
  
         await attemptAutoRefundProduct(db, oid, transactionResult.pendingPayment);
  
         response.send(`
           <!DOCTYPE html>
           <html>
           <head><title>Sipariş Hatası</title></head>
           <body>
             <div style="text-align:center; padding:50px;">
               <h2>Ödeme alındı ancak sipariş oluşturulamadı</h2>
               <p>Lütfen destek ile iletişime geçin.</p>
               <p>Referans: ${escapeHtml(oid)}</p>
             </div>
             <script>window.location.href = 'payment-failed://order-creation-error';</script>
           </body>
           </html>
         `);
       }
      } catch (error) {
        console.error('Payment callback critical error:', error);
        try {
          await db.collection('payment_callback_errors').add({
            oid: request.body?.oid || 'unknown',
            error: error.message,
            stack: error.stack,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            requestBody: request.body,
          });
        } catch (logError) {
          console.error('Failed to log error:', logError);
        }
        response.status(500).send('Internal server error');
      }
  });
  
  export const checkIsbankPaymentStatus = onCall(
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
  
        const {orderNumber} = request.data;
  
        if (!orderNumber) {
          throw new HttpsError('invalid-argument', 'Order number is required');
        }
  
        const db = admin.firestore();
        const pendingPaymentSnap = await db.collection('pendingPayments').doc(orderNumber).get();
  
        if (!pendingPaymentSnap.exists) {
          throw new HttpsError('not-found', 'Payment not found');
        }
  
        const pendingPayment = pendingPaymentSnap.data();
  
        if (pendingPayment.userId !== request.auth.uid) {
          throw new HttpsError('permission-denied', 'Unauthorized');
        }
  
        return {
          orderNumber: orderNumber,
          status: pendingPayment.status,
          orderId: pendingPayment.orderId || null,
          errorMessage: pendingPayment.errorMessage || null,
        };
      } catch (error) {
        console.error('Check payment status error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );

  async function trackAdConversionInternal(userId, orderId, productIds, shopIds) {
    const db = admin.firestore();
  
    const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
      Date.now() - 30 * 24 * 60 * 60 * 1000,
    );
  
    const userClicksSnap = await db
      .collection('users')
      .doc(userId)
      .collection('ad_clicks')
      .where('clickedAt', '>=', thirtyDaysAgo)
      .where('converted', '==', false)
      .get();
  
    if (userClicksSnap.empty) {
      return;
    }
  
    const batch = db.batch();
    let conversionsCount = 0;
  
    for (const clickDoc of userClicksSnap.docs) {
      const clickData = clickDoc.data();
  
      let isConversion = false;
  
      if (clickData.linkedType === 'product' && productIds.includes(clickData.linkedId)) {
        isConversion = true;
      } else if (clickData.linkedType === 'shop' && shopIds && shopIds.includes(clickData.linkedId)) {
        isConversion = true;
      }
  
      if (isConversion) {
        conversionsCount++;
  
        batch.update(clickDoc.ref, {
          converted: true,
          convertedAt: admin.firestore.FieldValue.serverTimestamp(),
          orderId: orderId,
        });
  
        const adCollectionName = getAdCollectionName(clickData.adType);
        const adRef = db.collection(adCollectionName).doc(clickData.adId);
  
        batch.update(adRef, {
          totalConversions: admin.firestore.FieldValue.increment(1),
          lastConvertedAt: admin.firestore.FieldValue.serverTimestamp(),
          metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        const clickRecordsSnap = await db
          .collection(adCollectionName)
          .doc(clickData.adId)
          .collection('clicks')
          .where('userId', '==', userId)
          .where('clickedAt', '==', clickData.clickedAt)
          .limit(1)
          .get();
  
        if (!clickRecordsSnap.empty) {
          batch.update(clickRecordsSnap.docs[0].ref, {
            converted: true,
            convertedAt: admin.firestore.FieldValue.serverTimestamp(),
            orderId: orderId,
          });
        }
      }
    }
  
    if (conversionsCount > 0) {
      await batch.commit();
      console.log(`✅ Tracked ${conversionsCount} ad conversions for order ${orderId}`);
    }
  }
