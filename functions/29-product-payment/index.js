import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { checkRateLimit } from '../shared/redis.js';
import { transliterate } from 'transliteration';
import {trackPurchaseActivity} from '../11-user-activity/index.js';
import {createQRCodeTask} from '../16-qr-for-orders/index.js';
import { CloudTasksClient } from '@google-cloud/tasks';
import { setPaymentExpiresAt } from '../33-payment-cleanup/index.js';
import { reversePayment } from '../shared/isbank-void.js';

const tasksClient = new CloudTasksClient();

function getIsbankConfig() {
  return {
    clientId: process.env.ISBANK_CLIENT_ID,
    apiUser: process.env.ISBANK_API_USER,
    apiPassword: process.env.ISBANK_API_PASSWORD,
    storeKey: process.env.ISBANK_STORE_KEY,
    gatewayUrl: 'https://sanalpos.isbank.com.tr/fim/est3Dgate',
    currency: '949',
    storeType: '3d_pay_hosting',
  };
}

function getAdCollectionName(adType) {
  switch (adType) {
    case 'topBanner':  return 'market_top_ads_banners';
    case 'thinBanner': return 'market_thin_banners';
    case 'marketBanner': return 'market_banners';
    default: return 'market_banners';
  }
}

// Rate limit: 5 payment attempts per 10 minutes per user
async function checkPaymentRateLimit(userId) {
  const withinLimit = await checkRateLimit(`payment_init:${userId}`, 5, 600, { failOpen: false });
  if (!withinLimit) {
    throw new HttpsError('resource-exhausted', 'Too many payment attempts. Please try again later.');
  }
}

async function validateDiscounts(tx, db, userId, couponId, benefitId, cartTotal) {
  let couponDiscount = 0;
  let freeShippingApplied = false;
  let couponCode = null;
  let couponRef = null;
  let benefitRef = null;

  if (couponId) {
    couponRef = db.collection('users').doc(userId).collection('coupons').doc(couponId);
    const couponDoc = await tx.get(couponRef);

    if (!couponDoc.exists) throw new HttpsError('not-found', 'Coupon not found');
    const coupon = couponDoc.data();
    if (coupon.isUsed) throw new HttpsError('failed-precondition', 'Coupon has already been used');
    if (coupon.expiresAt && coupon.expiresAt.toDate() < new Date()) throw new HttpsError('failed-precondition', 'Coupon has expired');

    couponDiscount = Math.min(coupon.amount || 0, cartTotal);
    couponCode = coupon.code || null;
  }

  if (benefitId) {
    benefitRef = db.collection('users').doc(userId).collection('benefits').doc(benefitId);
    const benefitDoc = await tx.get(benefitRef);

    if (!benefitDoc.exists) throw new HttpsError('not-found', 'Free shipping benefit not found');
    const benefit = benefitDoc.data();
    if (benefit.isUsed) throw new HttpsError('failed-precondition', 'Free shipping has already been used');
    if (benefit.expiresAt && benefit.expiresAt.toDate() < new Date()) throw new HttpsError('failed-precondition', 'Free shipping benefit has expired');

    freeShippingApplied = true;
  }

  return { couponDiscount, freeShippingApplied, couponCode, couponRef, benefitRef };
}

function markDiscountsAsUsed(tx, discountResult, orderId) {
  const { couponRef, benefitRef } = discountResult;

  if (couponRef) {
    tx.update(couponRef, {
      isUsed: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      orderId,
    });
    console.log(`Coupon marked as used for order ${orderId}`);
  }

  if (benefitRef) {
    tx.update(benefitRef, {
      isUsed: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      orderId,
    });
    console.log(`Benefit marked as used for order ${orderId}`);
  }
}

async function createCartClearTask(buyerId, purchasedProductIds, orderId) {
  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const parent = tasksClient.queuePath(project, location, 'cart-operations');

  try {
    await tasksClient.createTask({
      parent,
      task: {
        httpRequest: {
          httpMethod: 'POST',
          url: `https://${location}-${project}.cloudfunctions.net/clearPurchasedCartItems`,
          body: Buffer.from(JSON.stringify({ buyerId, purchasedProductIds, orderId })).toString('base64'),
          headers: { 'Content-Type': 'application/json' },
          oidcToken: { serviceAccountEmail: `${project}@appspot.gserviceaccount.com` },
        },
      },
    });
    console.log(`Cart clear task created for buyer ${buyerId}, order ${orderId}`);
  } catch (error) {
    console.error('Error creating cart clear task:', error);
  }
}

export const clearPurchasedCartItems = onRequest(
  { region: 'europe-west3', memory: '256MiB', timeoutSeconds: 60, invoker: 'private' },
  async (request, response) => {
    try {
      const {buyerId, purchasedProductIds, orderId} = request.body;

      if (!buyerId || !Array.isArray(purchasedProductIds) || purchasedProductIds.length === 0) {
        console.error('Invalid cart clear request:', {buyerId, purchasedProductIds});
        response.status(400).send('Invalid request parameters');
        return;
      }

      const db = admin.firestore();
      const cartRef = db.collection('users').doc(buyerId).collection('cart');
      let deletedCount = 0;

      for (let i = 0; i < purchasedProductIds.length; i += 500) {
        const batch = db.batch();
        purchasedProductIds.slice(i, i + 500).forEach((productId) => {
          batch.delete(cartRef.doc(productId));
          deletedCount++;
        });
        await batch.commit();
      }

      await db.collection('users').doc(buyerId).update({
        cartItemIds: admin.firestore.FieldValue.arrayRemove(...purchasedProductIds),
      });

      await db.collection('cart_clear_logs').add({
        buyerId, orderId, purchasedProductIds, deletedCount,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });

      response.status(200).send({ success: true, deletedCount });
    } catch (error) {
      console.error('Error clearing cart items:', error);
      try {
        const {buyerId, orderId} = request.body;
        await admin.firestore().collection('cart_clear_logs').add({
          buyerId: buyerId || 'unknown', orderId: orderId || 'unknown',
          error: error.message, stack: error.stack,
          timestamp: admin.firestore.FieldValue.serverTimestamp(), success: false,
        });
      } catch (logError) {
        console.error('Failed to log cart clear error:', logError);
      }
      response.status(500).send({ success: false, error: error.message });
    }
  },
);

async function createNotificationTask(orderId, productData, recipientId, buyerName, buyerId) {
  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const parent = tasksClient.queuePath(project, location, 'order-notifications');

  try {
    await tasksClient.createTask({
      parent,
      task: {
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
          headers: { 'Content-Type': 'application/json' },
          oidcToken: { serviceAccountEmail: `${project}@appspot.gserviceaccount.com` },
        },
      },
    });
  } catch (error) {
    console.error('Error creating notification task:', error);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX 2: batchFetchProducts — two-phase fully parallel fetch
//
// Before: Phase 2 (shop_products fallback) was sequential — one await per miss.
// After:  Phase 1 fetches ALL items from `products` in parallel.
//         Phase 2 collects ALL misses and fetches them from `shop_products`
//         in a single parallel round-trip. Total: 2 round-trips max, regardless
//         of cart size or how many items are shop products.
// ─────────────────────────────────────────────────────────────────────────────
async function batchFetchProducts(tx, db, items) {
  // Validate all items up front
  for (const item of items) {
    if (!item.productId || typeof item.productId !== 'string') {
      throw new HttpsError('invalid-argument', 'Each cart item needs a valid productId.');
    }
  }

  // Phase 1: fetch everything from `products` in parallel
  const primaryRefs = items.map((item) => db.collection('products').doc(item.productId));
  const primarySnaps = await Promise.all(primaryRefs.map((ref) => tx.get(ref)));

  // Collect indices of misses
  const missIndices = [];
  primarySnaps.forEach((snap, i) => {
    if (!snap.exists) missIndices.push(i);
  });

  // Phase 2: fetch ALL misses from `shop_products` in parallel (single round-trip)
  let shopRefs = [];
  let shopSnaps = [];
  if (missIndices.length > 0) {
    shopRefs = missIndices.map((i) => db.collection('shop_products').doc(items[i].productId));
    shopSnaps = await Promise.all(shopRefs.map((ref) => tx.get(ref)));
  }

  // Map miss index → shop result
  const shopResultByOriginalIndex = new Map();
  missIndices.forEach((origIdx, shopIdx) => {
    shopResultByOriginalIndex.set(origIdx, { ref: shopRefs[shopIdx], snap: shopSnaps[shopIdx] });
  });

  // Assemble final ordered result
  return items.map((item, i) => {
    if (primarySnaps[i].exists) {
      return { ref: primaryRefs[i], data: primarySnaps[i].data(), item };
    }
    const shopEntry = shopResultByOriginalIndex.get(i);
    if (!shopEntry.snap.exists) {
      throw new HttpsError('not-found', `Product ${item.productId} not found.`);
    }
    return { ref: shopEntry.ref, data: shopEntry.snap.data(), item };
  });
}

async function batchFetchSellers(db, productsMeta) {
  const shopIds = new Set();
  const userIds = new Set();

  for (const meta of productsMeta) {
    if (meta.data.shopId) shopIds.add(meta.data.shopId);
    else userIds.add(meta.data.userId);
  }

  const [shopSnaps, userSnaps] = await Promise.all([
    Promise.all(Array.from(shopIds).map((id) => db.collection('shops').doc(id).get())),  // db.get, not tx.get
    Promise.all(Array.from(userIds).map((id) => db.collection('users').doc(id).get())),  // db.get, not tx.get
  ]);

  const shopData = new Map();
  const userData = new Map();
  shopSnaps.forEach((snap, idx) => shopData.set(Array.from(shopIds)[idx], snap.data()));
  userSnaps.forEach((snap, idx) => userData.set(Array.from(userIds)[idx], snap.data()));

  for (const meta of productsMeta) {
    if (meta.data.shopId) {
      const shop = shopData.get(meta.data.shopId);
      meta.sellerName = shop?.name || 'Unknown Shop';
      meta.sellerType = 'shop';
      meta.shopMembers = getShopMemberIdsFromData(shop);
      meta.sellerContactNo = shop?.contactNo || null;
      meta.sellerAddress = {
        addressLine1: shop?.address || 'N/A',
        location: (shop?.latitude && shop?.longitude) ? { lat: shop.latitude, lng: shop.longitude } : null,
      };
    } else {
      const user = userData.get(meta.data.userId);
      meta.sellerName = user?.displayName || 'Unknown Seller';
      meta.sellerType = 'user';
      meta.sellerContactNo = user?.sellerInfo?.phone || null;
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

function getShopMemberIdsFromData(shopData) {
  if (!shopData) return [];
  const memberIds = [];
  if (shopData.ownerId) memberIds.push(shopData.ownerId);
  if (Array.isArray(shopData.coOwners)) memberIds.push(...shopData.coOwners);
  if (Array.isArray(shopData.editors)) memberIds.push(...shopData.editors);
  if (Array.isArray(shopData.viewers)) memberIds.push(...shopData.viewers);
  return [...new Set(memberIds)];
}

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
  } catch (_) {/* alerting must never throw */}
}

// ─────────────────────────────────────────────────────────────────────────────
// createOrderTransaction
//
// FIX 1: notificationData.length = 0 at top of tx body — prevents duplicate
//         notifications on Firestore transaction retries.
//
// FIX 3: Transaction contains ONLY atomically-critical writes:
//   • Duplicate order check
//   • Buyer read
//   • Discount validation + marking
//   • Product + seller reads (now fully parallel via batchFetchProducts fix)
//   • Stock validation
//   • Order document
//   • Order items subcollection
//   • Inventory decrements
//
// Moved OUT of transaction (post-tx, individually fault-tolerant):
//   • Seller metrics (totalProductsSold, totalSoldPrice) — eventual consistency OK
//   • Address save — user preference, non-critical
//   • receiptTasks write — queued work, non-critical
//   • Notifications, cart clear, activity tracking, QR, ad conversion
//
// This keeps the transaction lean, predictable, and well within Firestore's
// limits even for large multi-seller carts.
// ─────────────────────────────────────────────────────────────────────────────
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

  if (!Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Cart must contain at least one item.');
  }

  if (deliveryOption === 'pickup') {
    if (!pickupPoint || typeof pickupPoint !== 'object') {
      throw new HttpsError('invalid-argument', 'Pickup point is required for pickup delivery.');
    }
    ['pickupPointId', 'pickupPointName', 'pickupPointAddress'].forEach((f) => {
      if (!(f in pickupPoint)) throw new HttpsError('invalid-argument', `Missing pickup point field: ${f}`);
    });
  } else {
    if (!address || typeof address !== 'object') {
      throw new HttpsError('invalid-argument', 'A valid address object is required.');
    }
    ['addressLine1', 'city', 'phoneNumber', 'location'].forEach((f) => {
      if (!(f in address)) throw new HttpsError('invalid-argument', `Missing address field: ${f}`);
    });
  }

  if (!['normal', 'express'].includes(deliveryOption)) {
    throw new HttpsError('invalid-argument', 'Invalid delivery option.');
  }

  const db = admin.firestore();
  let orderResult;
  const notificationData = []; // reset on each tx retry — see FIX 1
  let productsMeta = [];
  let finalOrderId = null;

  // Data collected inside tx, used for post-tx writes
  let postTxData = null;

  await db.runTransaction(async (tx) => {
    // ── FIX 1: Reset on every retry — prevents duplicate notifications ───────
    notificationData.length = 0;

    // ── Duplicate order guard ────────────────────────────────────────────────
    if (paymentOrderId) {
      const existingOrdersSnap = await tx.get(
        db.collection('orders').where('paymentOrderId', '==', paymentOrderId).limit(1),
      );
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

    // ── Buyer read ───────────────────────────────────────────────────────────
    const buyerRef = db.collection('users').doc(buyerId);
    const buyerSnap = await tx.get(buyerRef);
    if (!buyerSnap.exists) throw new HttpsError('not-found', `Buyer ${buyerId} not found.`);
    const buyerData = buyerSnap.data() || {};
    const buyerName = buyerData.displayName || buyerData.name || 'Unknown Buyer';
    const userLanguage = buyerData.languageCode || 'en';

    const orderRef = db.collection('orders').doc();
    finalOrderId = orderRef.id;

    // ── Discount reads ───────────────────────────────────────────────────────
    let discountResult = {
      couponDiscount: 0, freeShippingApplied: false,
      couponCode: null, couponRef: null, benefitRef: null,
    };
    if (couponId || freeShippingBenefitId) {
      discountResult = await validateDiscounts(tx, db, buyerId, couponId, freeShippingBenefitId, cartCalculatedTotal || 0);
    }

    // ── Price resolution ─────────────────────────────────────────────────────
    const preCalc = requestData.serverCalculation || null;
    let serverFinalTotal; let serverDeliveryPrice; let serverCouponDiscount;

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

    // ── FIX 2: Product + seller reads — fully parallel ───────────────────────
    productsMeta = await batchFetchProducts(tx, db, items);
    await batchFetchSellers(db, productsMeta);

    // ── Stock validation + seller group accumulation ─────────────────────────
    let totalQuantity = 0;
    const sellerGroups = new Map();

    const systemFieldsForGroups = new Set([
      'productId', 'quantity', 'addedAt', 'updatedAt', 'sellerId', 'sellerName', 'isShop',
      'salePreferences', 'calculatedUnitPrice', 'calculatedTotal', 'isBundleItem',
      'price', 'finalPrice', 'unitPrice', 'totalPrice', 'currency',
      'bundleInfo', 'isBundle', 'bundleId', 'mainProductPrice', 'bundlePrice',
      'selectedColorImage', 'productImage', 'productName', 'brandModel', 'brand',
      'category', 'subcategory', 'subsubcategory', 'condition', 'averageRating',
      'productAverageRating', 'reviewCount', 'productReviewCount', 'clothingType',
      'clothingFit', 'gender', 'shipmentStatus', 'deliveryOption', 'needsProductReview',
      'needsSellerReview', 'needsAnyReview', 'timestamp', 'availableStock',
      'maxQuantityAllowed', 'ourComission', 'sellerContactNo', 'showSellerHeader',
    ]);

    for (const meta of productsMeta) {
      const {data, item} = meta;
      const qty = Math.max(1, item.quantity || 1);
      const colorKey = (item.selectedColor && item.selectedColor !== 'default') ? item.selectedColor : null;
      const hasColorVariant = colorKey && data.colorQuantities &&
        Object.prototype.hasOwnProperty.call(data.colorQuantities, colorKey);
      const available = hasColorVariant ? (data.colorQuantities[colorKey] || 0) : (data.quantity || 0);

      if (available < qty) {
        const stockInfo = hasColorVariant ? `color '${colorKey}' stock: ${available}` : `general stock: ${available}`;
        throw new HttpsError('failed-precondition',
          `Not enough stock for ${data.productName}. Requested: ${qty}, Available: ${available} (${stockInfo})`);
      }

      totalQuantity += qty;

      // Build seller groups (for receipt)
      const sellerId = data.shopId || data.userId;
      if (!sellerGroups.has(sellerId)) {
        sellerGroups.set(sellerId, { sellerName: meta.sellerName, items: [] });
      }
      const dynAttrs = {};
      Object.keys(item).forEach((key) => {
        if (!systemFieldsForGroups.has(key) && item[key] !== undefined && item[key] !== null && item[key] !== '') {
          dynAttrs[key] = item[key];
        }
      });
      sellerGroups.get(sellerId).items.push({
        productName: data.productName || 'Unknown Product',
        quantity: item.quantity || 1,
        unitPrice: item.calculatedUnitPrice || data.price,
        totalPrice: item.calculatedTotal || ((data.price || 0) * (item.quantity || 1)),
        selectedAttributes: dynAttrs,
        sellerName: meta.sellerName,
        sellerId: data.shopId || data.userId,
      });
    }

    // ── Order document ───────────────────────────────────────────────────────
    const orderDocument = {
      buyerId,
      buyerName,
      totalPrice: serverFinalTotal,
      totalQuantity,
      deliveryPrice: serverDeliveryPrice,
      paymentMethod,
      paymentOrderId: paymentOrderId || null,
      deliveryOption,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
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
        location: new admin.firestore.GeoPoint(address.location.latitude, address.location.longitude),
      };
    }

    if (couponId || freeShippingBenefitId) {
      markDiscountsAsUsed(tx, discountResult, finalOrderId);
    }

    tx.set(orderRef, orderDocument);

    // ── Order items + inventory decrements ───────────────────────────────────
    const receiptItems = [];
    const systemFieldsForItems = new Set([
      'productId', 'quantity', 'addedAt', 'updatedAt',
      'sellerId', 'sellerName', 'isShop', 'salePreferences',
    ]);

    for (const meta of productsMeta) {
      const {ref, data, item, sellerName} = meta;
      const qty = Math.max(1, item.quantity || 1);
      const colorKey = (item.selectedColor && item.selectedColor !== 'default') ? item.selectedColor : null;
      const hasColorVariant = colorKey && data.colorQuantities &&
        Object.prototype.hasOwnProperty.call(data.colorQuantities, colorKey);

      let productImage = '';
      let selectedColorImage = '';
      if (colorKey && data.colorImages?.[colorKey]?.length > 0) {
        productImage = data.colorImages[colorKey][0];
        selectedColorImage = data.colorImages[colorKey][0];
      } else if (Array.isArray(data.imageUrls) && data.imageUrls.length > 0) {
        productImage = data.imageUrls[0];
      }

      const orderItemData = {
        orderId: orderRef.id,
        buyerId,
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
          if (salePrefs?.discountThreshold && salePrefs?.discountPercentage) {
            const quantity = Math.max(1, item.quantity || 1);
            return {
              discountThreshold: salePrefs.discountThreshold,
              discountPercentage: salePrefs.discountPercentage,
              discountApplied: quantity >= salePrefs.discountThreshold,
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

      const dynAttrs = {};
      Object.keys(item).forEach((key) => {
        if (!systemFieldsForItems.has(key) && item[key] !== undefined && item[key] !== null && item[key] !== '') {
          dynAttrs[key] = item[key];
        }
      });
      if (Object.keys(dynAttrs).length > 0) orderItemData.selectedAttributes = dynAttrs;

      tx.set(orderRef.collection('items').doc(), {
        ...orderItemData,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      receiptItems.push({
        productName: data.productName || 'Unknown Product',
        quantity: qty,
        unitPrice: item.calculatedUnitPrice || data.price,
        totalPrice: item.calculatedTotal || (data.price * qty),
        selectedAttributes: dynAttrs,
        sellerName,
        sellerId: data.shopId || data.userId,
      });

      // Inventory decrement (atomic — must stay in transaction)
      const updates = {
        purchaseCount: admin.firestore.FieldValue.increment(qty),
        metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (data.subsubcategory !== 'Curtains') {
        if (hasColorVariant) {
          updates[`colorQuantities.${colorKey}`] = admin.firestore.FieldValue.increment(-qty);
        } else {
          updates.quantity = admin.firestore.FieldValue.increment(-qty);
        }
      }
      tx.update(ref, updates);

      // Collect for post-tx notifications
      if (data.shopId) {
        notificationData.push({
          productId: ref.id,
          productName: data.productName || 'Unknown Product',
          recipientId: null,
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

    // ── FIX 3: Capture data for post-tx writes (no writes here) ─────────────
    postTxData = {
      buyerName,
      userLanguage,
      hasAdClicks: buyerData.hasAdClicks || false,
      receiptItems: [...receiptItems],
      sellerGroups,
      serverFinalTotal,
      serverDeliveryPrice,
      serverCouponDiscount,
      couponCode: discountResult.couponCode,
      freeShippingApplied: discountResult.freeShippingApplied,
      preCalc,
      saveAddress: saveAddress && deliveryOption !== 'pickup' && !!address,
      addressToSave: saveAddress && deliveryOption !== 'pickup' && address ? {
        addressLine1: address.addressLine1,
        addressLine2: address.addressLine2 || '',
        city: address.city,
        phoneNumber: address.phoneNumber,
        location: new admin.firestore.GeoPoint(address.location.latitude, address.location.longitude),
      } : null,
    };

    orderResult = { orderId: orderRef.id, buyerName };
  });

  if (orderResult?.duplicate) return orderResult;

   // ── POST-TRANSACTION WRITES ───────────────────────────────────────────────

  // Build serializable seller metrics — computed here so productsMeta
  // doesn't need to be passed through the task payload.
  const sellerMetrics = [];
  {
    const userTotals = new Map();
    const shopTotals = new Map();
    for (const { data, item } of productsMeta) {
      const qty   = Math.max(1, item.quantity || 1);
      const price = item.calculatedTotal || ((data.price || 0) * qty);
      if (data.shopId) {
        const e = shopTotals.get(data.shopId) || { qty: 0, price: 0 };
        e.qty += qty; e.price += price;
        shopTotals.set(data.shopId, e);
      } else if (data.userId) {
        const e = userTotals.get(data.userId) || { qty: 0, price: 0 };
        e.qty += qty; e.price += price;
        userTotals.set(data.userId, e);
      }
    }
    userTotals.forEach(({ qty, price }, id) => sellerMetrics.push({ type: 'user', id, qty, price }));
    shopTotals.forEach(({ qty, price }, id) => sellerMetrics.push({ type: 'shop', id, qty, price }));
  }

  // 1. Consolidated post-order Cloud Task
  //    Replaces fire-and-forget blocks for: seller metrics, address save,
  //    receipt task, activity tracking, ad conversion.
  await createPostOrderTask({
    orderId: finalOrderId,
    buyerId,
    buyerName: postTxData.buyerName,
    userLanguage: postTxData.userLanguage,
    hasAdClicks: postTxData.hasAdClicks,
    saveAddress: postTxData.saveAddress,
    // Serialize GeoPoint → plain object so JSON serialization is safe
    addressToSave: postTxData.addressToSave ? {
      ...postTxData.addressToSave,
      location: postTxData.addressToSave.location ? {
        latitude: postTxData.addressToSave.location.latitude,
        longitude: postTxData.addressToSave.location.longitude,
      } : null,
    } : null,
    sellerMetrics,
    receipt: {
      receiptItems: postTxData.receiptItems,
      sellerGroups: Array.from(postTxData.sellerGroups.values()), // Map → Array
      serverFinalTotal: postTxData.serverFinalTotal,
      serverDeliveryPrice: postTxData.serverDeliveryPrice,
      serverCouponDiscount: postTxData.serverCouponDiscount,
      couponCode: postTxData.couponCode,
      freeShippingApplied: postTxData.freeShippingApplied,
      preCalc: postTxData.preCalc,
      cartCalculatedTotal: cartCalculatedTotal || 0,
      paymentMethod,
      deliveryOption,
      clientDeliveryPrice: clientDeliveryPrice || 0,
      pickupPoint: deliveryOption === 'pickup' ? pickupPoint : null,
      address: deliveryOption !== 'pickup' ? address    : null,
    },
    activityItems: productsMeta.map(({ data, item }) => ({
      productId: data.id || item.productId,
      shopId: data.shopId || null,
      category: data.category,
      subcategory: data.subcategory,
      subsubcategory: data.subsubcategory,
      brandModel: data.brandModel,
      price: item.calculatedUnitPrice || data.price,
      quantity: item.quantity || 1,
    })),
    adConversion: {
      productIds: items.map((i) => i.productId),
      shopIds: [...new Set(productsMeta.filter((m) => m.data.shopId).map((m) => m.data.shopId))],
    },
  });

  // 2. Notifications — already Cloud Tasks, unchanged
  Promise.allSettled(
    notificationData.map((notif) =>
      createNotificationTask(orderResult.orderId, notif, notif.recipientId, orderResult.buyerName, buyerId),
    ),
  ).then((results) => {
    const failed = results.filter((r) => r.status === 'rejected').length;
    if (failed > 0) {
      logTaskFailureAlert('notification_partial', finalOrderId, buyerId, orderResult?.buyerName,
        { message: `${failed}/${results.length} notifications failed` });
    }
  });

  // 3. Cart clear — already Cloud Tasks, unchanged
  try {
    await createCartClearTask(buyerId, items.map((i) => i.productId), finalOrderId);
  } catch (err) {
    logTaskFailureAlert('cart_clear', finalOrderId, buyerId, orderResult?.buyerName, err);
  }

  // 4. QR code — already Cloud Tasks, unchanged
  try {
    await createQRCodeTask(finalOrderId, {
      buyerId,
      buyerName: orderResult.buyerName,
      items,
      totalPrice: cartCalculatedTotal,
      deliveryOption,
    });
  } catch (err) {
    logTaskFailureAlert('qr_code', finalOrderId, buyerId, orderResult?.buyerName, err);
  }

  return { orderId: orderResult.orderId, success: true, receiptPending: true };
}


async function createPostOrderTask(payload) {
  const project  = 'emlak-mobile-app';
  const location = 'europe-west3';
  const parent   = tasksClient.queuePath(project, location, 'post-order-tasks');

  try {
    await tasksClient.createTask({
      parent,
      task: {
        httpRequest: {
          httpMethod: 'POST',
          url: `https://${location}-${project}.cloudfunctions.net/processPostOrderWork`,
          body: Buffer.from(JSON.stringify(payload)).toString('base64'),
          headers: { 'Content-Type': 'application/json' },
          oidcToken: { serviceAccountEmail: `${project}@appspot.gserviceaccount.com` },
        },
      },
    });
    console.log(`Post-order task created for order ${payload.orderId}`);
  } catch (error) {
    // Log but don't throw — order is already committed, task failure is non-fatal
    // on first attempt. Cloud Tasks will not retry since we caught here, so
    // alert ops so they can manually trigger if needed.
    console.error('Failed to create post-order task:', error);
    logTaskFailureAlert('post_order_task_create', payload.orderId, payload.buyerId, payload.buyerName, error);
  }
}

export const processPostOrderWork = onRequest(
  { region: 'europe-west3', memory: '512MiB', timeoutSeconds: 120, invoker: 'private' },
  async (request, response) => {
    const {
      orderId,
      buyerId,
      buyerName,
      userLanguage,
      hasAdClicks,
      saveAddress,
      addressToSave,      // location serialized as {latitude, longitude}
      sellerMetrics,      // [{type: 'user'|'shop', id, qty, price}]
      receipt,
      activityItems,
      adConversion,       // {productIds, shopIds}
    } = request.body;

    if (!orderId || !buyerId) {
      response.status(400).send('Missing orderId or buyerId');
      return;
    }

    const db = admin.firestore();

   // ── 1. Seller metrics ─────────────────────────────────────────────────────
    // Guard doc prevents double-incrementing if Cloud Tasks retries this handler.
    // The batch atomically writes the guard + all metric increments together,
    // so a crash mid-batch won't leave the guard written without the increments.
    try {
      if (sellerMetrics && sellerMetrics.length > 0) {
        const metricsGuardRef = db.collection('_order_metrics_applied').doc(orderId);

        await db.runTransaction(async (tx) => {
          const guardSnap = await tx.get(metricsGuardRef);
          if (guardSnap.exists) {
            console.log(`[PostOrder] Seller metrics already applied for order ${orderId}, skipping`);
            return;
          }

          // Mark as applied + write all increments atomically
          tx.set(metricsGuardRef, {
            appliedAt: admin.firestore.FieldValue.serverTimestamp(),
            orderId,
            expiresAt: admin.firestore.Timestamp.fromMillis(
              Date.now() + 7 * 24 * 60 * 60 * 1000,
            ),
          });

          for (const { type, id, qty, price } of sellerMetrics) {
            const ref = type === 'shop' ?
              db.collection('shops').doc(id) :
              db.collection('users').doc(id);
            tx.update(ref, {
              totalProductsSold: admin.firestore.FieldValue.increment(qty),
              totalSoldPrice: admin.firestore.FieldValue.increment(price),
            });
          }
        });

        console.log(`[PostOrder] Seller metrics updated for order ${orderId}`);
      }
    } catch (err) {
      console.error(`[PostOrder] Seller metrics failed for ${orderId}:`, err.message);
      logTaskFailureAlert('seller_metrics', orderId, buyerId, buyerName, err);
    }

    // ── 2. Address save ───────────────────────────────────────────────────────
    try {
      if (saveAddress && addressToSave) {
        await db.collection('users').doc(buyerId).collection('addresses').add({
          addressLine1: addressToSave.addressLine1,
          addressLine2: addressToSave.addressLine2 || '',
          city: addressToSave.city,
          phoneNumber: addressToSave.phoneNumber,
          // Reconstruct GeoPoint from serialized plain object
          location: new admin.firestore.GeoPoint(
            addressToSave.location.latitude,
            addressToSave.location.longitude,
          ),
          addedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[PostOrder] Address saved for user ${buyerId}`);
      }
    } catch (err) {
      console.error(`[PostOrder] Address save failed for ${orderId}:`, err.message);
      // Non-critical, no alert needed
    }

    // ── 3. Receipt task ───────────────────────────────────────────────────────
    try {
      if (receipt) {
        const {
          receiptItems, sellerGroups, serverFinalTotal, serverDeliveryPrice,
          serverCouponDiscount, couponCode, freeShippingApplied, preCalc,
          cartCalculatedTotal, paymentMethod, deliveryOption, clientDeliveryPrice,
          pickupPoint, address,
        } = receipt;

        // Use orderId as document ID — idempotent on Cloud Tasks retry
        await db.collection('receiptTasks').doc(orderId).set({
          orderId,
          ownerId: buyerId,
          ownerType: 'user',
          buyerId,
          buyerName,
          items: receiptItems,
          sellerGroups: sellerGroups,
          totalPrice: serverFinalTotal,
          itemsSubtotal: cartCalculatedTotal || 0,
          currency: 'TL',
          paymentMethod,
          deliveryOption,
          deliveryPrice: serverDeliveryPrice,
          couponDiscount: serverCouponDiscount,
          couponCode,
          freeShippingApplied,
          originalDeliveryPrice: preCalc ?
            preCalc.deliveryPriceBeforeFreeShipping :
            (clientDeliveryPrice || 0),
          language: userLanguage,
          status: 'pending',
          pickupPoint: deliveryOption === 'pickup' && pickupPoint ? {
            name: pickupPoint.pickupPointName,
            address: pickupPoint.pickupPointAddress,
            phone: pickupPoint.pickupPointPhone || null,
            hours: pickupPoint.pickupPointHours || null,
            contactPerson: pickupPoint.pickupPointContactPerson || null,
            notes: pickupPoint.pickupPointNotes || null,
          } : null,
          buyerAddress: deliveryOption !== 'pickup' ? address : null,
          orderDate: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: false });
        console.log(`[PostOrder] Receipt task created for order ${orderId}`);
      }
    } catch (err) {
      console.error(`[PostOrder] Receipt task failed for ${orderId}:`, err.message);
      logTaskFailureAlert('receipt_task', orderId, buyerId, buyerName, err);
    }

    // ── 4. Activity tracking ──────────────────────────────────────────────────
    try {
      if (activityItems && activityItems.length > 0) {
        await trackPurchaseActivity(buyerId, activityItems, orderId);
        console.log(`[PostOrder] Activity tracked for order ${orderId}`);
      }
    } catch (err) {
      console.error(`[PostOrder] Activity tracking failed for ${orderId}:`, err.message);
      logTaskFailureAlert('activity_tracking', orderId, buyerId, buyerName, err);
    }

    // ── 5. Ad conversion ──────────────────────────────────────────────────────
    try {
      if (hasAdClicks && adConversion) {
        await trackAdConversionInternal(
          buyerId, orderId,
          adConversion.productIds,
          adConversion.shopIds,
        );
        console.log(`[PostOrder] Ad conversion tracked for order ${orderId}`);
      }
    } catch (err) {
      console.error(`[PostOrder] Ad conversion failed for ${orderId}:`, err.message);
      logTaskFailureAlert('ad_conversion', orderId, buyerId, buyerName, err);
    }

    response.status(200).send({ success: true, orderId });
  },
);

export const processOrderNotification = onRequest(
  { region: 'europe-west3', memory: '256MiB', timeoutSeconds: 30, invoker: 'private' },
  async (request, response) => {
    try {
      const {
        orderId, productId, productName, recipientId, buyerName,
        buyerId, quantity, shopId, shopName, sellerId, isShopProduct,
      } = request.body;

      const db = admin.firestore();

      if (isShopProduct && shopId) {
        await db.collection('shop_notifications').doc(`${orderId}_${productId}`).set({
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

export const initializeIsbankPayment = onCall(
  {
    region: 'europe-west3',
    memory: '256MiB',
    timeoutSeconds: 30,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
    secrets: [
      'ISBANK_CLIENT_ID',
      'ISBANK_API_USER',
      'ISBANK_API_PASSWORD',
      'ISBANK_STORE_KEY',
    ],
  },
  async (request) => {
    try {
      if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
      
      const db = admin.firestore();
      const userId = request.auth.uid;

      await checkPaymentRateLimit(userId);

      const { amount, orderNumber, customerName, customerEmail, customerPhone, cartData } = request.data;

      const sanitizedCustomerName = (() => {
        if (!customerName) return 'Customer';
        const s = transliterate(customerName).replace(/[^a-zA-Z0-9\s]/g, '').trim().substring(0, 50);
        return s || 'Customer';
      })();

      if (!orderNumber || !cartData) {
        throw new HttpsError('invalid-argument', 'orderNumber and cartData are required');
      }

      const cartCalculatedTotal = parseFloat(cartData.cartCalculatedTotal) || 0;
      const deliveryOption = cartData.deliveryOption || 'normal';
      const couponId = cartData.couponId || null;
      const freeShippingBenefitId = cartData.freeShippingBenefitId || null;

      let deliverySettings = null;
      try {
        const deliveryDoc = await db.collection('settings').doc('delivery').get();
        if (deliveryDoc.exists) deliverySettings = deliveryDoc.data();
      } catch (e) {
        console.error('Failed to fetch delivery settings:', e);
      }

      const serverDeliveryPriceRaw = calculateDeliveryPrice(deliveryOption, cartCalculatedTotal, deliverySettings);

      let serverCouponDiscount = 0;
      let serverFreeShippingApplied = false;
      let couponCode = null;

      if (couponId) {
        const couponDoc = await db.collection('users').doc(userId).collection('coupons').doc(couponId).get();
        if (couponDoc.exists) {
          const coupon = couponDoc.data();
          if (!coupon.isUsed && (!coupon.expiresAt || coupon.expiresAt.toDate() >= new Date())) {
            serverCouponDiscount = Math.min(coupon.amount || 0, cartCalculatedTotal);
            couponCode = coupon.code || null;
          }
        }
      }

      if (freeShippingBenefitId) {
        const benefitDoc = await db.collection('users').doc(userId).collection('benefits').doc(freeShippingBenefitId).get();
        if (benefitDoc.exists) {
          const benefit = benefitDoc.data();
          if (!benefit.isUsed && (!benefit.expiresAt || benefit.expiresAt.toDate() >= new Date())) {
            serverFreeShippingApplied = true;
          }
        }
      }

      const serverDeliveryPrice = serverFreeShippingApplied ? 0 : serverDeliveryPriceRaw;
      const serverFinalTotal = Math.max(0, cartCalculatedTotal - serverCouponDiscount) + serverDeliveryPrice;

      const clientAmount = parseFloat(amount) || 0;
      const discrepancy = Math.abs(serverFinalTotal - clientAmount);
      if (discrepancy > 0.01) {
        console.warn(`⚠️ PRICE DISCREPANCY: client=${clientAmount}, server=${serverFinalTotal}, diff=${discrepancy.toFixed(2)}`);
      }

      const formattedAmount = Math.round(serverFinalTotal).toString();
      const rnd = Date.now().toString();
      const callbackUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net/isbankPaymentCallback`;
      const config = getIsbankConfig();

      const hashParams = {
        BillToName: sanitizedCustomerName,
        amount: formattedAmount,
        callbackurl: callbackUrl,
        clientid: config.clientId,
        currency: config.currency,
        email: customerEmail || '',
        failurl: callbackUrl,
        hashAlgorithm: 'ver3',
        islemtipi: 'Auth',
        lang: 'tr',
        oid: orderNumber,
        okurl: callbackUrl,
        rnd,
        storetype: config.storeType,
        taksit: '',
        tel: customerPhone || '',
      };

      const hash = generateHashVer3(hashParams);

      const paymentParams = {
        clientid: config.clientId,
        storetype: config.storeType,
        hash,
        hashAlgorithm: 'ver3',
        islemtipi: 'Auth',
        amount: formattedAmount,
        currency: config.currency,
        oid: orderNumber,
        okurl: callbackUrl,
        failurl: callbackUrl,
        callbackurl: callbackUrl,
        lang: 'tr',
        rnd,
        taksit: '',
        BillToName: sanitizedCustomerName,
        email: customerEmail || '',
        tel: customerPhone || '',
      };

      const docData = {
        userId,
        amount: serverFinalTotal,
        formattedAmount,
        clientAmount,
        orderNumber,
        status: 'awaiting_3d',
        paymentParams,
        cartData,
        customerInfo: { name: sanitizedCustomerName, email: customerEmail, phone: customerPhone },
        serverCalculation: {
          itemsSubtotal: cartCalculatedTotal,
          couponDiscount: serverCouponDiscount,
          couponCode,
          deliveryPrice: serverDeliveryPrice,
          deliveryPriceBeforeFreeShipping: serverDeliveryPriceRaw,
          freeShippingApplied: serverFreeShippingApplied,
          finalTotal: serverFinalTotal,
          deliveryOption,
          calculatedAt: new Date().toISOString(),
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      };

      let docWritten = false;
      let lastWriteError = null;

      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const batch = db.batch();
          batch.set(db.collection('pendingPayments').doc(orderNumber), docData);
          batch.set(db.collection('pendingPaymentsBackup').doc(orderNumber), { ...docData, _isBackup: true });
          await batch.commit();
          docWritten = true;
          break;
        } catch (writeErr) {
          lastWriteError = writeErr;
          console.error(`[initializeIsbankPayment] Write attempt ${attempt}/3 failed:`, writeErr.message);
          if (attempt < 3) await new Promise((r) => setTimeout(r, 300 * attempt));
        }
      }

      if (!docWritten) {
        console.error(`[initializeIsbankPayment] All 3 write attempts failed for ${orderNumber}`);
        try {
          await db.collection('_payment_alerts').add({
            type: 'payment_doc_write_failed',
            severity: 'high',
            orderNumber,
            userId,
            errorMessage: lastWriteError?.message || 'Unknown write error',
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
        throw new HttpsError('internal', 'Payment session could not be created. Please try again.');
      }

      return { success: true, gatewayUrl: config.gatewayUrl, paymentParams, orderNumber };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error('İşbank payment initialization error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

function calculateDeliveryPrice(deliveryOption, cartTotal, deliverySettings) {
  if (!deliverySettings) {
    const defaults = {
      normal: { price: 150, freeThreshold: 2000 },
      express: { price: 350, freeThreshold: 10000 },
    };
    const opt = defaults[deliveryOption] || defaults.normal;
    return cartTotal >= opt.freeThreshold ? 0 : opt.price;
  }
  const optionSettings = deliverySettings[deliveryOption] || deliverySettings['normal'];
  if (!optionSettings) return 0;
  const price = parseFloat(optionSettings.price) || 0;
  const freeThreshold = parseFloat(optionSettings.freeThreshold) || Infinity;
  return cartTotal >= freeThreshold ? 0 : price;
}

function generateHashVer3(params) {
  const config = getIsbankConfig();

  const keys = Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));

  const plainText = keys
    .map((key) => String(params[key] || '').replace(/\\/g, '\\\\').replace(/\|/g, '\\|'))
    .join('|') + '|' + config.storeKey.trim();

  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

function buildRedirectHtml(deepLink, title, subtitle = '') {
  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  return `<!DOCTYPE html>
<html>
<head><title>${esc(title)}</title></head>
<body>
  <div style="text-align:center;padding:50px;">
    <h2>${esc(title)}</h2>
    ${subtitle ? `<p>${esc(subtitle)}</p>` : ''}
  </div>
  <script>window.location.href = ${JSON.stringify(deepLink)};</script>
</body>
</html>`;
}

export const isbankPaymentCallback = onRequest(
  {
    region: 'europe-west3',
    memory: '512MiB',
    minInstances: 1,
    timeoutSeconds: 90,
    cors: true,
    invoker: 'public',
    secrets: [
      'ISBANK_CLIENT_ID',
      'ISBANK_API_USER',
      'ISBANK_API_PASSWORD',
      'ISBANK_STORE_KEY',
    ],
  },
  async (request, response) => {
    const startTime = Date.now();
    const db = admin.firestore();

    try {
      console.log('[Payment] Callback invoked:', request.method);
      console.log('[Payment] Body:', JSON.stringify(request.body, null, 2));

      const { Response: bankResponse, mdStatus, oid, ProcReturnCode, ErrMsg, HASH } = request.body;

      if (!request.body.oid && request.body.HASH && request.body.rnd) {
        response.status(200).send('<html><body></body></html>');
        return;
      }

      if (!oid) {response.status(400).send('Order number missing'); return;}

      const storeKey = process.env.ISBANK_STORE_KEY.trim();

      const computedHash = (() => {
        const keys = Object.keys(request.body)
          .filter((key) => {
            const lower = key.toLowerCase();
            return lower !== 'encoding' && lower !== 'hash' &&
                   lower !== 'countdown' && lower !== 'nationalidno';
          })
          .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));

        return crypto.createHash('sha512')
          .update(
            keys.map((key) => String(request.body[key] ?? '').replace(/\\/g, '\\\\').replace(/\|/g, '\\|'))
              .join('|') + '|' + storeKey.replace(/\\/g, '\\\\').replace(/\|/g, '\\|'),
            'utf8',
          )
          .digest('base64');
      })();

      const hashValid = HASH && computedHash === HASH;

      const callbackLogRef = db.collection('payment_callback_logs').doc();
      await callbackLogRef.set({
        oid,
        hashValid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        requestBody: request.body,
        ip: request.ip || request.headers['x-forwarded-for'] || null,
        userAgent: request.headers['user-agent'] || null,
        processingStarted: new Date(startTime).toISOString(),
      });

      const pendingPaymentRef = db.collection('pendingPayments').doc(oid);

      const txResult = await db.runTransaction(async (tx) => {
        const snap = await tx.get(pendingPaymentRef);

        if (!snap.exists) {
          const backupSnap = await tx.get(db.collection('pendingPaymentsBackup').doc(oid));

          if (backupSnap.exists) {
            console.warn(`[Payment] Primary doc missing for ${oid} — restoring from backup`);
            const backupData = backupSnap.data();

            tx.set(pendingPaymentRef, {
              ...backupData,
              _restoredFromBackup: true,
              _restoredAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (!hashValid) {
              tx.update(pendingPaymentRef, {
                status: 'hash_verification_failed',
                receivedHash: HASH || null,
                computedHash,
                callbackLogId: callbackLogRef.id,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                ...setPaymentExpiresAt('hash_verification_failed'),
              });
              return { error: 'hash_failed' };
            }

            const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
            const isTxnSuccess = bankResponse === 'Approved' && ProcReturnCode === '00';

            if (!isAuthSuccess || !isTxnSuccess) {
              tx.update(pendingPaymentRef, {
                status: 'payment_failed', mdStatus, procReturnCode: ProcReturnCode,
                errorMessage: ErrMsg || 'Payment failed', rawResponse: request.body,
                callbackLogId: callbackLogRef.id, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                ...setPaymentExpiresAt('payment_failed'),
              });
              return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
            }

            tx.update(pendingPaymentRef, {
              status: 'processing', mdStatus, procReturnCode: ProcReturnCode,
              rawResponse: request.body, callbackLogId: callbackLogRef.id,
              processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
              ...setPaymentExpiresAt('processing'),
            });
            return { success: true, pendingPayment: backupData, restoredFromBackup: true };
          }

          console.error(`[Payment] CRITICAL: No doc found for ${oid} in primary or backup`);
          return { error: 'not_found' };
        }

        const p = snap.data();

        if (p.status === 'completed')                         return { alreadyProcessed: true, status: 'completed', orderId: p.orderId };
        if (p.status === 'payment_succeeded_order_failed')    return { alreadyProcessed: true, status: p.status };
        if (p.status === 'payment_failed')                    return { alreadyProcessed: true, status: p.status };
        if (p.status === 'hash_verification_failed')          return { alreadyProcessed: true, status: p.status };
        if (p.status === 'processing' ||
            p.status === 'payment_verified_processing_order') return { retry: true, pendingPayment: p };
        if (p.status !== 'awaiting_3d')                       return { alreadyProcessed: true, status: p.status };

        if (!hashValid) {
          tx.update(pendingPaymentRef, {
            status: 'hash_verification_failed',
            receivedHash: HASH || null,
            computedHash,
            callbackLogId: callbackLogRef.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...setPaymentExpiresAt('hash_verification_failed'),
          });
          return { error: 'hash_failed' };
        }

        const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
        const isTxnSuccess = bankResponse === 'Approved' && ProcReturnCode === '00';

        if (!isAuthSuccess || !isTxnSuccess) {
          tx.update(pendingPaymentRef, {
            status: 'payment_failed', mdStatus, procReturnCode: ProcReturnCode,
            errorMessage: ErrMsg || 'Payment failed', rawResponse: request.body,
            callbackLogId: callbackLogRef.id, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...setPaymentExpiresAt('payment_failed'),
          });
          return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
        }

        tx.update(pendingPaymentRef, {
          status: 'processing', mdStatus, procReturnCode: ProcReturnCode,
          rawResponse: request.body, callbackLogId: callbackLogRef.id,
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...setPaymentExpiresAt('processing'),
        });

        return { success: true, pendingPayment: p };
      });

      if (txResult.error === 'not_found') {
        try {
          await db.collection('_payment_alerts').add({
            type: 'payment_callback_no_doc',
            severity: 'critical',
            orderNumber: oid,
            bankCallbackBody: request.body,
            mdStatus, bankResponse, ProcReturnCode,
            ip: request.ip || request.headers['x-forwarded-for'] || null,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            message: 'Payment may have been charged but no session doc exists. Manual recovery required.',
          });
        } catch (_) {/* alerting must never throw */}

        response.send(buildRedirectHtml(
          'payment-failed://session-not-found',
          'Ödeme Oturumu Bulunamadı',
          `Ödemeniz alınmış olabilir. Lütfen destek ile iletişime geçin. Referans: ${oid}`,
        ));
        return;
      }

      if (txResult.error === 'hash_failed') {
        response.send(buildRedirectHtml('payment-failed://hash-error', 'Ödeme Doğrulama Hatası', 'Lütfen tekrar deneyin.'));
        return;
      }

      if (txResult.error === 'payment_failed') {
        response.send(buildRedirectHtml(
          `payment-failed://${encodeURIComponent(txResult.message)}`, 'Ödeme Başarısız', txResult.message,
        ));
        return;
      }

      if (txResult.alreadyProcessed) {
        if (txResult.status === 'completed') {
          response.send(buildRedirectHtml(`payment-success://${txResult.orderId}`, '✓ Ödeme Başarılı', 'Siparişiniz oluşturuldu.'));
        } else {
          response.send(buildRedirectHtml(`payment-status://${txResult.status}`, 'İşlem Zaten İşlendi'));
        }
        return;
      }

      if (txResult.retry) {
        console.log(`[Payment] ${oid} already processing — client listener will handle completion`);
        response.send(buildRedirectHtml(
          `payment-status://processing`,
          'İşleminiz Devam Ediyor',
          'Ödemeniz işleniyor, lütfen bekleyin.',
        ));
        return;
      }

      const pendingPayment = txResult.pendingPayment;
      let orderResult;

      try {
        orderResult = await createOrderTransaction(pendingPayment.userId, {
          ...pendingPayment.cartData,
          paymentOrderId: oid,
          paymentMethod: 'isbank_3d',
          serverCalculation: pendingPayment.serverCalculation || null,
        });
      } catch (orderError) {
        console.error('[Payment] Order creation failed after successful payment:', orderError);
      
        // ── AUTO-REVERSAL: Safe here — order was NOT created ──────────
        let reversalResult = null;
        try {
          const paymentAmount = pendingPayment?.amount || pendingPayment?.serverCalculation?.finalTotal;
          reversalResult = await reversePayment(oid, paymentAmount, '949');
        } catch (reversalError) {
          console.error('[Payment] Reversal attempt threw:', reversalError.message);
        }
      
        const reversalSucceeded = reversalResult?.success === true;
      
        await pendingPaymentRef.update({
          status: reversalSucceeded ? 'payment_reversed' : 'payment_succeeded_order_failed',
          orderError: orderError.message,
          reversalAttempted: true,
          reversalSuccess: reversalSucceeded,
          reversalMethod: reversalResult?.method || null,
          reversalResponse: reversalResult?.response || null,
          reversalError: reversalResult?.error || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...setPaymentExpiresAt(reversalSucceeded ? 'payment_reversed' : 'payment_succeeded_order_failed'),
        });
      
        await callbackLogRef.update({
          processingFailed: admin.firestore.FieldValue.serverTimestamp(),
          error: orderError.message,
          reversalSuccess: reversalSucceeded,
          success: false,
        });
      
        try {
          await db.collection('_payment_alerts').doc(`product_${oid}`).set({
            type: reversalSucceeded ?
              'order_failed_payment_reversed' :
              'order_creation_failed_after_payment',
            severity: reversalSucceeded ? 'medium' : 'critical',
            paymentOrderId: oid,
            userId: pendingPayment.userId,
            amount: pendingPayment.amount,
            errorMessage: orderError.message,
            reversalSuccess: reversalSucceeded,
            reversalMethod: reversalResult?.method || null,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
      
        if (reversalSucceeded) {
          response.send(buildRedirectHtml(
            'payment-failed://order-reversed',
            'Sipariş Oluşturulamadı',
            'Ödemeniz iptal edildi ve iade edilecektir. Lütfen tekrar deneyiniz.',
          ));
        } else {
          response.send(buildRedirectHtml(
            'payment-failed://order-creation-error',
            'Sipariş Hatası',
            `Ödeme alındı ancak sipariş oluşturulamadı. Lütfen destek ile iletişime geçin. Referans: ${oid}`,
          ));
        }
        return;
      }

      // ── ORDER SUCCEEDED — post-order updates below are non-critical ──
      if (orderResult.duplicate) {
        console.log(`[Payment] Duplicate order for payment ${oid}: ${orderResult.orderId}`);
      }

      try {
        await pendingPaymentRef.update({
          status: 'completed',
          orderId: orderResult.orderId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: Date.now() - startTime,
          ...setPaymentExpiresAt('completed'),
        });
      } catch (updateErr) {
        console.error(`[Payment] Status update failed for ${oid} (order ${orderResult.orderId} exists):`, updateErr.message);
        // Order exists — recovery scheduler will find it in 'processing' and
        // the duplicate guard in createOrderTransaction will handle it safely
      }

      try {
        await callbackLogRef.update({
          processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
          orderId: orderResult.orderId,
          success: true,
          processingDuration: Date.now() - startTime,
        });
      } catch (_) {/* logging failure is non-critical */}

      console.log(`[Payment] ${oid} → order ${orderResult.orderId} created`);
      response.send(buildRedirectHtml(`payment-success://${orderResult.orderId}`, '✓ Ödeme Başarılı', 'Siparişiniz oluşturuldu.'));
    } catch (error) {
      console.error('[Payment] Critical callback error:', error);
      try {
        await db.collection('payment_callback_errors').add({
          oid: request.body?.oid || 'unknown',
          error: error.message,
          stack: error.stack,
          requestBody: request.body,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {/* alerting must never throw */}
      response.status(500).send('Internal server error');
    }
  },
);

export const checkIsbankPaymentStatus = onCall(
  { region: 'europe-west3', memory: '256MiB', timeoutSeconds: 10 },
  async (request) => {
    try {
      if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
      const {orderNumber} = request.data;
      if (!orderNumber) throw new HttpsError('invalid-argument', 'Order number is required');

      const snap = await admin.firestore().collection('pendingPayments').doc(orderNumber).get();
      if (!snap.exists) throw new HttpsError('not-found', 'Payment not found');

      const p = snap.data();
      if (p.userId !== request.auth.uid) throw new HttpsError('permission-denied', 'Unauthorized');

      return { orderNumber, status: p.status, orderId: p.orderId || null, errorMessage: p.errorMessage || null };
    } catch (error) {
      console.error('Check payment status error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

export const recoverStuckPayments = onSchedule(
  { schedule: '*/5 * * * *', region: 'europe-west3', memory: '512MiB', timeoutSeconds: 300 },
  async () => {
    const db = admin.firestore();
    const fiveMinutesAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);

    const stuckSnap = await db.collection('pendingPayments')
      .where('status', 'in', ['processing', 'payment_verified_processing_order'])
      .where('processingStartedAt', '<=', fiveMinutesAgo)
      .limit(100)
      .get();

    if (stuckSnap.empty) return;

    console.warn(`[Recovery] Found ${stuckSnap.docs.length} stuck payment(s)`);

    const CONCURRENCY = 5;
    const results = { recovered: 0, skipped: 0, failed: 0 };

    for (let i = 0; i < stuckSnap.docs.length; i += CONCURRENCY) {
      const chunk = stuckSnap.docs.slice(i, i + CONCURRENCY);

      const settled = await Promise.allSettled(chunk.map(async (doc) => {
        const oid = doc.id;
        const p   = doc.data();

        if ((p.recoveryAttemptCount || 0) >= 5) {
          console.error(`[Recovery] ${oid} exceeded max attempts, giving up`);
          await doc.ref.update({
            status: 'payment_succeeded_order_failed',
            orderError: 'Max recovery attempts exceeded',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...setPaymentExpiresAt('payment_succeeded_order_failed'),
          });
          try {
            const paymentAmount = p.amount || p.serverCalculation?.finalTotal;
            const reversalResult = await reversePayment(oid, paymentAmount, '949');
            if (reversalResult.success) {
              await doc.ref.update({
                status: 'payment_reversed',
                reversalSuccess: true,
                reversalMethod: reversalResult.method,
                ...setPaymentExpiresAt('payment_reversed'),
              });
            }
          } catch (_) {/* reversal is best-effort here */}
          // Alert only on the give-up — not on every attempt
          try {
            await db.collection('_payment_alerts').add({
              type: 'payment_recovery_max_attempts', severity: 'high',
              orderNumber: oid, userId: p.userId,
              message: `Payment ${oid} exceeded max recovery attempts`,
              isRead: false, isResolved: false,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
          } catch (_) {/* alerting must never throw */}
          return 'skipped';
        }

        // Atomic claim — prevents double-execution if two scheduler runs overlap
        const claimed = await db.runTransaction(async (tx) => {
          const fresh = (await tx.get(doc.ref)).data();
          if (!['processing', 'payment_verified_processing_order'].includes(fresh.status)) return false;
          tx.update(doc.ref, {
            status: 'payment_verified_processing_order',
            recoveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
            recoveryAttemptCount: admin.firestore.FieldValue.increment(1),
          });
          return true;
        });

        if (!claimed) {
          console.log(`[Recovery] ${oid} already resolved by concurrent run, skipping`);
          return 'skipped';
        }

        const orderResult = await createOrderTransaction(p.userId, {
          ...p.cartData,
          paymentOrderId: oid,
          paymentMethod: 'isbank_3d',
          serverCalculation: p.serverCalculation || null,
        });

        await doc.ref.update({
          status: 'completed',
          orderId: orderResult.orderId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          recoveredBy: 'recovery_scheduler',
          ...setPaymentExpiresAt('completed'),
        });

        try {
          await db.collection('_payment_alerts').add({
            type: 'payment_recovered', severity: 'medium',
            orderNumber: oid, userId: p.userId, orderId: orderResult.orderId,
            message: `Recovery scheduler fixed stuck payment: ${oid}`,
            isRead: false, isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}

        console.log(`[Recovery] ✅ Recovered ${oid} → order ${orderResult.orderId}`);
        return 'recovered';
      }));

      settled.forEach((result, idx) => {
        if (result.status === 'fulfilled') {
          result.value === 'recovered' ? results.recovered++ : results.skipped++;
        } else {
          results.failed++;
          const oid = chunk[idx].id;
          const p   = chunk[idx].data();
          console.error(`[Recovery] Failed to recover ${oid}:`, result.reason?.message);

          // Fire-and-forget — don't let alert failure propagate
          db.runTransaction(async (tx) => {
            const fresh = (await tx.get(chunk[idx].ref)).data();
            // Only mark as failed if we actually claimed it (status was flipped)
            if (fresh.status === 'payment_verified_processing_order') {
              tx.update(chunk[idx].ref, {
                status: 'payment_succeeded_order_failed',
                orderError: result.reason?.message || 'Recovery failed',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                ...setPaymentExpiresAt('payment_succeeded_order_failed'),
              });
            }
          }).catch(console.error);

          db.collection('_payment_alerts').add({
            type: 'payment_recovery_failed', severity: 'high',
            orderNumber: oid, userId: p.userId,
            errorMessage: result.reason?.message || 'Unknown error',
            isRead: false, isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          }).catch(() => {});
        }
      });
    }

    console.log(`[Recovery] Done — ${results.recovered} recovered, ${results.skipped} skipped, ${results.failed} failed`);
  },
);

async function trackAdConversionInternal(userId, orderId, productIds, shopIds) {
  const db = admin.firestore();
  const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);

  const userClicksSnap = await db.collection('users').doc(userId).collection('ad_clicks')
    .where('clickedAt', '>=', thirtyDaysAgo)
    .where('converted', '==', false)
    .get();

  if (userClicksSnap.empty) return;

  // Filter to actual conversions first — no point querying click records for non-conversions
  const matchingClicks = userClicksSnap.docs.filter((clickDoc) => {
    const d = clickDoc.data();
    return (
      (d.linkedType === 'product' && productIds.includes(d.linkedId)) ||
      (d.linkedType === 'shop' && shopIds && shopIds.includes(d.linkedId))
    );
  });

  if (matchingClicks.length === 0) return;

  // Fire all nested click-record lookups in parallel — one round-trip total
  const clickRecordQueries = await Promise.all(
    matchingClicks.map((clickDoc) => {
      const d = clickDoc.data();
      const adCollectionName = getAdCollectionName(d.adType);
      return db.collection(adCollectionName).doc(d.adId)
        .collection('clicks')
        .where('userId', '==', userId)
        .where('clickedAt', '==', d.clickedAt)
        .limit(1)
        .get();
    }),
  );

  const batch = db.batch();
  let conversionsCount = 0;

  matchingClicks.forEach((clickDoc, i) => {
    const d = clickDoc.data();
    const adCollectionName = getAdCollectionName(d.adType);
    conversionsCount++;

    batch.update(clickDoc.ref, {
      converted: true,
      convertedAt: admin.firestore.FieldValue.serverTimestamp(),
      orderId,
    });

    batch.update(db.collection(adCollectionName).doc(d.adId), {
      totalConversions: admin.firestore.FieldValue.increment(1),
      lastConvertedAt: admin.firestore.FieldValue.serverTimestamp(),
      metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (!clickRecordQueries[i].empty) {
      batch.update(clickRecordQueries[i].docs[0].ref, {
        converted: true,
        convertedAt: admin.firestore.FieldValue.serverTimestamp(),
        orderId,
      });
    }
  });

  await batch.commit();
  console.log(`✅ Tracked ${conversionsCount} ad conversions for order ${orderId}`);
}
