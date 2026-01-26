// functions/index.js
import crypto from 'crypto';
import * as functions from 'firebase-functions/v2';
import {onDocumentWritten, onDocumentCreated, onDocumentUpdated} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onRequest, onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import algoliasearch from 'algoliasearch';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
// import {PredictionServiceClient, UserEventServiceClient} from '@google-cloud/retail';
import {Storage} from '@google-cloud/storage';
import {transliterate} from 'transliteration';
const storage = new Storage();
// import {ProductServiceClient} from '@google-cloud/retail';
import mod from './i18n.cjs';
const {localize} = mod;
const SUPPORTED_LOCALES = ['en', 'tr', 'ru'];
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
import {trackPurchaseActivity} from './11-user-activity/index.js';
import {createQRCodeTask} from './16-qr-for-orders/index.js';
const tasksClient = new CloudTasksClient();
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const regularFontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
const boldFontPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
const OTP_SALT = defineSecret('OTP_SALT');
admin.initializeApp();
const visionClient = new vision.ImageAnnotatorClient();
// Initialize Secret Manager client!?!
const secretClient = new SecretManagerServiceClient();

// Helper to fetch a secret
async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({name: secretName});
  return version.payload.data.toString('utf8');
}

// Lazy-load Algolia at first use
let algoliaClient = null;
async function getAlgoliaIndex(indexName) {
  if (!algoliaClient) {
    const [appId, adminKey] = await Promise.all([
      getSecret('projects/emlak-mobile-app/secrets/ALGOLIA_APP_ID/versions/latest'),
      getSecret('projects/emlak-mobile-app/secrets/ALGOLIA_ADMIN_KEY/versions/latest'),
    ]);
    algoliaClient = algoliasearch(appId, adminKey);
  }
  return algoliaClient.initIndex(indexName);
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

async function validateAndMarkDiscounts(tx, db, userId, couponId, benefitId, orderId, cartTotal) {
  let couponDiscount = 0;
  let freeShippingApplied = false;
  let couponCode = null;

  // Validate and mark coupon
  if (couponId) {
    const couponRef = db.collection('users').doc(userId).collection('coupons').doc(couponId);
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

    // Mark as used (atomic within transaction)
    tx.update(couponRef, {
      isUsed: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      orderId: orderId,
    });

    console.log(`Coupon ${couponId} validated and marked as used for order ${orderId}`);
  }

  // Validate and mark free shipping benefit
  if (benefitId) {
    const benefitRef = db.collection('users').doc(userId).collection('benefits').doc(benefitId);
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

    // Mark as used (atomic within transaction)
    tx.update(benefitRef, {
      isUsed: true,
      usedAt: admin.firestore.FieldValue.serverTimestamp(),
      orderId: orderId,
    });

    console.log(`Benefit ${benefitId} validated and marked as used for order ${orderId}`);
  }

  return { couponDiscount, freeShippingApplied, couponCode };
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
    
    let discountResult = { couponDiscount: 0, freeShippingApplied: false, couponCode: null };
    
    if (couponId || freeShippingBenefitId) {
      discountResult = await validateAndMarkDiscounts(
        tx,
        db,
        buyerId,
        couponId,
        freeShippingBenefitId,
        finalOrderId,
        cartCalculatedTotal || 0
      );
    }

    // ✅ ADD: SERVER-SIDE PRICE CALCULATION
    const serverDeliveryPrice = discountResult.freeShippingApplied ? 0 : (clientDeliveryPrice || 0);
    const serverCouponDiscount = discountResult.couponDiscount;
    const serverFinalTotal = Math.max(0, (cartCalculatedTotal || 0) - serverCouponDiscount) + serverDeliveryPrice;

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

      // Call conversion tracking
      const functions = admin.functions();
      await functions.httpsCallable('trackAdConversion')({
        orderId: finalOrderId,
        productIds,
        shopIds,
      }, {
        auth: {uid: buyerId},
      });
    } catch (convError) {
      console.error('Error tracking ad conversion:', convError);
      // Don't fail the order
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
    }
  }).catch((err) => {
    console.error('Unexpected error in notification batch:', err);
  });

  Promise.resolve().then(async () => {
    try {
      const purchasedProductIds = items.map((item) => item.productId);
      await createCartClearTask(buyerId, purchasedProductIds, finalOrderId);
    } catch (cartClearError) {
      console.error('Error creating cart clear task:', cartClearError);
      // Don't fail the order
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
      // Don't fail the order
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
        amount,
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

        return sanitized || 'Customer'; // Fallback if sanitization results in empty string
      })();

      if (!amount || !orderNumber || !cartData) {
        throw new HttpsError('invalid-argument', 'Amount, orderNumber, and cartData are required');
      }

      console.log('🔍 Received amount from Flutter:', amount);
      console.log('🔍 Amount type:', typeof amount);

      const formattedAmount = Math.round(parseFloat(amount)).toString();
      const rnd = Date.now().toString();

      const baseUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
      const okUrl = `${baseUrl}/isbankPaymentCallback`;
      const failUrl = `${baseUrl}/isbankPaymentCallback`;
      const callbackUrl = `${baseUrl}/isbankPaymentCallback`;
      const isbankConfig = await getIsbankConfig();
      // For hash calculation - match exactly what will be sent
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
        taksit: '', // Keep empty string for installment
        tel: customerPhone || '',
      };

      const hash = await generateHashVer3(hashParams);

      // For form submission
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
        taksit: '', // Empty for single payment
        BillToName: sanitizedCustomerName || '',
        email: customerEmail || '',
        tel: customerPhone || '',
      };

      console.log('Hash params:', JSON.stringify(hashParams, null, 2));
      console.log('Payment params being sent:', JSON.stringify(paymentParams, null, 2));

      const db = admin.firestore();
      const timestamp = admin.firestore.FieldValue.serverTimestamp();

      await db.collection('pendingPayments').doc(orderNumber).set({
        userId: request.auth.uid,
        amount: amount,
        formattedAmount: formattedAmount,
        orderNumber: orderNumber,
        status: 'awaiting_3d',
        paymentParams: paymentParams,
        cartData: cartData,
        customerInfo: {
          name: sanitizedCustomerName,
          email: customerEmail,
          phone: customerPhone,
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

        // Verify hash if provided
        if (HASHPARAMSVAL && HASH) {
          const hashParams = HASHPARAMSVAL + isbankConfig.storeKey;
          const calculatedHash = crypto.createHash('sha512').update(hashParams, 'utf8').digest('base64');

          console.log('Received HASH:', HASH);
          console.log('Calculated HASH:', calculatedHash);

          if (calculatedHash !== HASH) {
            console.error('Hash verification failed!');
            transaction.update(pendingPaymentRef, {
              status: 'hash_verification_failed',
              errorMessage: 'Hash verification failed',
              receivedHash: HASH,
              calculatedHash: calculatedHash,
              hashParamsVal: HASHPARAMSVAL,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              callbackLogId: callbackLogRef.id,
            });

            return {
              error: 'hash_failed',
              message: 'Hash verification failed',
            };
          }
        } else {
          console.warn('HASHPARAMSVAL not provided - skipping hash verification');
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
              <script>window.location.href = 'payment-failed://${encodeURIComponent(transactionResult.message)}';</script>
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
              <script>window.location.href = 'payment-success://${transactionResult.orderId}';</script>
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
              <script>window.location.href = 'payment-status://${transactionResult.status}';</script>
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
                <script>window.location.href = 'payment-success://${checkData.orderId}';</script>
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

      // Create order with payment reference for idempotency
      try {
        console.log(`Creating order for payment ${oid}`);

        const orderResult = await createOrderTransaction(
          transactionResult.pendingPayment.userId,
          {
            ...transactionResult.pendingPayment.cartData,
            paymentOrderId: oid, // CRITICAL: Pass payment reference
            paymentMethod: 'isbank_3d',
          },
        );

        // Check if order was duplicate
        if (orderResult.duplicate) {
          console.log(`Order already existed for payment ${oid}: ${orderResult.orderId}`);
        }

        // Update payment status to completed
        await pendingPaymentRef.update({
          status: 'completed',
          orderId: orderResult.orderId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: Date.now() - startTime,
        });

        // Update callback log
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
            <script>window.location.href = 'payment-success://${orderResult.orderId}';</script>
          </body>
          </html>
        `);

        // Log successful response
        console.log(`Payment ${oid} successfully processed with order ${orderResult.orderId}`);
        return;
      } catch (orderError) {
        console.error('Order creation failed after payment:', orderError);

        await pendingPaymentRef.update({
          status: 'payment_succeeded_order_failed',
          orderError: orderError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await callbackLogRef.update({
          processingFailed: admin.firestore.FieldValue.serverTimestamp(),
          error: orderError.message,
          success: false,
        });

        response.send(`
          <!DOCTYPE html>
          <html>
          <head><title>Sipariş Hatası</title></head>
          <body>
            <div style="text-align:center; padding:50px;">
              <h2>Ödeme alındı ancak sipariş oluşturulamadı</h2>
              <p>Lütfen destek ile iletişime geçin.</p>
              <p>Referans: ${oid}</p>
            </div>
            <script>window.location.href = 'payment-failed://order-creation-error';</script>
          </body>
          </html>
        `);
        return;
      }
    } catch (error) {
      console.error('Payment callback critical error:', error);

      // Try to log the error
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
  },
);

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

// Calculate expiration date based on duration
// function calculateExpirationDate(duration) {
//   const now = new Date();
//   switch (duration) {
//     case 'oneWeek':
//       return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
//     case 'twoWeeks':
//       return new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
//     case 'oneMonth':
//       return new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
//     default:
//       return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
//   }
// }

export const extractColorOnly = onCall(
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

      const {imageUrl} = request.data;

      if (!imageUrl) {
        throw new HttpsError('invalid-argument', 'imageUrl is required');
      }

      console.log(`🎨 Extracting color from: ${imageUrl}`);

      // Extract color using your existing function
      const dominantColor = await extractDominantColorFromUrl(imageUrl);

      console.log(`✅ Color extracted: 0x${dominantColor.toString(16).toUpperCase()}`);

      return {
        success: true,
        dominantColor: dominantColor,
      };
    } catch (error) {
      console.error('❌ Error extracting color:', error);
      // Return default gray color if extraction fails
      return {
        success: false,
        dominantColor: 0xFF9E9E9E,
        error: error.message,
      };
    }
  },
);

async function extractDominantColorFromUrl(imageUrl) {
  let tmpFile = null;

  try {
    // Create unique temporary file
    tmpFile = path.join(os.tmpdir(), `ad_color_${Date.now()}_${Math.random().toString(36).substr(2, 9)}.jpg`);

    console.log(`Downloading image from: ${imageUrl}`);

    // Download image from Firebase Storage URL
    const response = await fetch(imageUrl);

    if (!response.ok) {
      throw new Error(`Failed to fetch image: ${response.statusText}`);
    }

    const buffer = await response.arrayBuffer();
    fs.writeFileSync(tmpFile, Buffer.from(buffer));

    console.log(`Image downloaded to: ${tmpFile}`);

    // Extract dominant color using your existing function
    const dominantColor = await getDominantColor(tmpFile);

    console.log(`✅ Dominant color extracted: ${dominantColor} (0x${dominantColor.toString(16).toUpperCase()})`);

    return dominantColor;
  } catch (error) {
    console.error('❌ Error extracting dominant color:', error);
    // Return a default pleasant gray color if extraction fails
    return 0xFF9E9E9E;
  } finally {
    // Cleanup: Always delete temp file
    if (tmpFile && fs.existsSync(tmpFile)) {
      try {
        fs.unlinkSync(tmpFile);
        console.log(`🗑️ Cleaned up temp file: ${tmpFile}`);
      } catch (cleanupError) {
        console.error('⚠️ Failed to cleanup temp file:', cleanupError);
      }
    }
  }
}

async function queueDominantColorExtraction(adId, imageUrl, adType) {
  // Only process topBanner ads
  if (adType !== 'topBanner') {
    console.log(`⏭️ Skipping color extraction for ${adType} (not a topBanner)`);
    return;
  }

  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const queue = 'ad-color-extraction';

  try {
    const parent = tasksClient.queuePath(project, location, queue);

    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `https://${location}-${project}.cloudfunctions.net/processAdColorExtraction`,
        body: Buffer.from(JSON.stringify({
          adId,
          imageUrl,
          adType,
        })).toString('base64'),
        headers: {
          'Content-Type': 'application/json',
        },
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
    };

    await tasksClient.createTask({parent, task});
    console.log(`✅ Color extraction task queued for ad ${adId}`);
  } catch (error) {
    console.error('❌ Error queuing color extraction task:', error);
    // Don't throw - color extraction is non-critical
    // The ad is already activated, color extraction is a bonus feature
  }
}

function calculateExpirationDate(duration) {
  const now = new Date();

  // 🧪 TEST MODE - Durations in MINUTES instead of days
  switch (duration) {
  case 'oneWeek':
    return new Date(now.getTime() + 1 * 60 * 1000); // ← 1 minute (was 7 days)
  case 'twoWeeks':
    return new Date(now.getTime() + 2 * 60 * 1000); // ← 2 minutes (was 14 days)
  case 'oneMonth':
    return new Date(now.getTime() + 3 * 60 * 1000); // ← 3 minutes (was 30 days)
  default:
    return new Date(now.getTime() + 1 * 60 * 1000); // ← Default 1 minute
  }
}

// Helper to schedule ad expiration task
async function scheduleAdExpiration(submissionId, expirationDate) {
  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const queue = 'ad-expirations';

  try {
    const parent = tasksClient.queuePath(project, location, queue);

    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `https://${location}-${project}.cloudfunctions.net/processAdExpiration`,
        body: Buffer.from(JSON.stringify({submissionId})).toString('base64'),
        headers: {'Content-Type': 'application/json'},
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
      scheduleTime: {
        seconds: Math.floor(expirationDate.getTime() / 1000),
      },
    };

    await tasksClient.createTask({parent, task});
    console.log(`✅ Scheduled expiration task for ad ${submissionId}`);
  } catch (error) {
    console.error('Error scheduling ad expiration:', error);
    // Don't throw - task scheduling is non-critical
  }
}

// Initialize Ad Payment
export const initializeIsbankAdPayment = onCall(
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

      const {submissionId, paymentLink} = request.data;

      if (!submissionId || !paymentLink) {
        throw new HttpsError(
          'invalid-argument',
          'submissionId and paymentLink are required',
        );
      }

      const db = admin.firestore();

      // Get submission details
      const submissionRef = db.collection('ad_submissions').doc(submissionId);
      const submissionSnap = await submissionRef.get();

      if (!submissionSnap.exists) {
        throw new HttpsError('not-found', 'Ad submission not found');
      }

      const submission = submissionSnap.data();

      // Verify ownership
      if (submission.userId !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Unauthorized');
      }

      // Verify status
      if (submission.status !== 'approved') {
        throw new HttpsError(
          'failed-precondition',
          'Ad submission must be approved',
        );
      }

      // Verify payment link matches
      if (submission.paymentLink !== paymentLink) {
        throw new HttpsError('invalid-argument', 'Invalid payment link');
      }

      const amount = submission.price;
      const orderNumber = `AD-${submissionId}-${Date.now()}`;
      const isbankConfig = await getIsbankConfig();
      // Get user info
      const userSnap = await db.collection('users').doc(request.auth.uid).get();
      const userData = userSnap.data() || {};
      const customerName = userData.displayName || userData.name || 'Customer';
      const customerEmail = userData.email || '';
      const customerPhone = userData.phoneNumber || '';

      const sanitizedCustomerName = transliterate(customerName)
        .replace(/[^a-zA-Z0-9\s]/g, '')
        .trim()
        .substring(0, 50) || 'Customer';

      const formattedAmount = Math.round(parseFloat(amount) * 1.2).toString(); // Include 20% tax
      const rnd = Date.now().toString();

      const baseUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
      const okUrl = `${baseUrl}/isbankAdPaymentCallback`;
      const failUrl = `${baseUrl}/isbankAdPaymentCallback`;
      const callbackUrl = `${baseUrl}/isbankAdPaymentCallback`;

      // Hash params
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

      // Payment params
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

      console.log('Ad Payment params:', JSON.stringify(paymentParams, null, 2));

      // Store pending ad payment
      await db
        .collection('pendingAdPayments')
        .doc(orderNumber)
        .set({
          userId: request.auth.uid,
          submissionId: submissionId,
          amount: amount,
          totalAmount: parseFloat(formattedAmount),
          formattedAmount: formattedAmount,
          orderNumber: orderNumber,
          status: 'awaiting_3d',
          paymentParams: paymentParams,
          adData: {
            adType: submission.adType,
            duration: submission.duration,
            shopId: submission.shopId,
            shopName: submission.shopName,
            imageUrl: submission.imageUrl,
            linkType: submission.linkType || null,
            linkedShopId: submission.linkedShopId || null,
            linkedProductId: submission.linkedProductId || null,
          },
          customerInfo: {
            name: sanitizedCustomerName,
            email: customerEmail,
            phone: customerPhone,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
        });

      return {
        success: true,
        gatewayUrl: isbankConfig.gatewayUrl,
        paymentParams: paymentParams,
        orderNumber: orderNumber,
      };
    } catch (error) {
      console.error('İşbank ad payment initialization error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

// Ad Payment Callback
export const isbankAdPaymentCallback = onRequest(
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
      console.log('Ad payment callback invoked - method:', request.method);
      console.log('All callback parameters:', JSON.stringify(request.body, null, 2));

      const {Response, mdStatus, oid, ProcReturnCode, ErrMsg, HASH, HASHPARAMSVAL} =
        request.body;

      if (!oid) {
        console.error('Missing oid in callback. Full body:', request.body);
        response.status(400).send('Order number missing');
        return;
      }

      // Log callback
      const callbackLogRef = db.collection('ad_payment_callback_logs').doc();
      await callbackLogRef.set({
        oid: oid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        requestBody: request.body,
        userAgent: request.headers['user-agent'] || null,
        ip: request.ip || request.headers['x-forwarded-for'] || null,
        processingStarted: new Date(startTime).toISOString(),
      });

      const pendingPaymentRef = db.collection('pendingAdPayments').doc(oid);

      // TRANSACTION: Atomic operations
      const transactionResult = await db.runTransaction(async (transaction) => {
        const pendingPaymentSnap = await transaction.get(pendingPaymentRef);

        if (!pendingPaymentSnap.exists) {
          return {error: 'not_found', message: 'Payment session not found'};
        }

        const pendingPayment = pendingPaymentSnap.data();

        // Idempotency checks
        if (pendingPayment.status === 'completed') {
          console.log(`Ad payment ${oid} already completed`);
          return {
            alreadyProcessed: true,
            status: 'completed',
            message: 'Payment already successfully processed',
          };
        }

        if (pendingPayment.status === 'payment_succeeded_activation_failed') {
          console.log(`Ad payment ${oid} succeeded but activation failed`);
          return {
            alreadyProcessed: true,
            status: 'payment_succeeded_activation_failed',
            message: 'Payment succeeded but ad activation failed',
          };
        }

        if (pendingPayment.status === 'payment_failed') {
          console.log(`Ad payment ${oid} already marked as failed`);
          return {
            alreadyProcessed: true,
            status: 'payment_failed',
            message: 'Payment already marked as failed',
          };
        }

        // Only proceed if awaiting_3d
        if (pendingPayment.status !== 'awaiting_3d') {
          console.warn(`Unexpected status for ${oid}: ${pendingPayment.status}`);

          if (
            pendingPayment.status === 'processing' ||
            pendingPayment.status === 'payment_verified_activating_ad'
          ) {
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

        // Verify hash
        if (HASHPARAMSVAL && HASH) {
          const hashParams = HASHPARAMSVAL + isbankConfig.storeKey;
          const calculatedHash = crypto
            .createHash('sha512')
            .update(hashParams, 'utf8')
            .digest('base64');

          console.log('Received HASH:', HASH);
          console.log('Calculated HASH:', calculatedHash);

          if (calculatedHash !== HASH) {
            console.error('Hash verification failed!');
            transaction.update(pendingPaymentRef, {
              status: 'hash_verification_failed',
              errorMessage: 'Hash verification failed',
              receivedHash: HASH,
              calculatedHash: calculatedHash,
              hashParamsVal: HASHPARAMSVAL,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              callbackLogId: callbackLogRef.id,
            });

            return {error: 'hash_failed', message: 'Hash verification failed'};
          }
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

          return {error: 'payment_failed', message: ErrMsg || 'Payment failed'};
        }

        // Mark as processing
        transaction.update(pendingPaymentRef, {
          status: 'processing',
          response: Response,
          mdStatus: mdStatus,
          procReturnCode: ProcReturnCode,
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
          rawResponse: request.body,
          callbackLogId: callbackLogRef.id,
        });

        return {success: true, pendingPayment: pendingPayment};
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
              <script>window.location.href = 'ad-payment-failed://hash-error';</script>
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
              <script>window.location.href = 'ad-payment-failed://${encodeURIComponent(
    transactionResult.message,
  )}';</script>
            </body>
            </html>
          `);
          return;
        }
      }

      // Handle already processed
      if (transactionResult.alreadyProcessed) {
        console.log(`Ad payment ${oid} already processed: ${transactionResult.status}`);

        if (transactionResult.status === 'completed') {
          response.send(`
            <!DOCTYPE html>
            <html>
            <head><title>Ödeme Başarılı</title></head>
            <body>
              <div style="text-align:center; padding:50px;">
                <h2>✓ Ödeme Başarılı</h2>
                <p>Reklamınız aktif edildi.</p>
              </div>
              <script>window.location.href = 'ad-payment-success://';</script>
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
              <script>window.location.href = 'ad-payment-status://${transactionResult.status}';</script>
            </body>
            </html>
          `);
          return;
        }
      }

      // Handle retry
      if (transactionResult.retry) {
        console.log(
          `Ad payment ${oid} is being processed by another callback, waiting...`,
        );

        let retryCount = 0;
        const maxRetries = 20;
        const retryDelay = 500;

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
                  <p>Reklamınız aktif edildi.</p>
                </div>
                <script>window.location.href = 'ad-payment-success://';</script>
              </body>
              </html>
            `);
            return;
          }

          if (
            checkData.status === 'payment_succeeded_activation_failed' ||
            checkData.status === 'payment_failed'
          ) {
            response.send(`
              <!DOCTYPE html>
              <html>
              <head><title>İşlem Hatası</title></head>
              <body>
                <div style="text-align:center; padding:50px;">
                  <h2>İşlem Hatası</h2>
                  <p>Lütfen destek ile iletişime geçin.</p>
                </div>
                <script>window.location.href = 'ad-payment-failed://processing-error';</script>
              </body>
              </html>
            `);
            return;
          }

          retryCount++;
        }

        console.error(`Timeout waiting for ad payment ${oid} processing`);
        response.status(500).send('Processing timeout');
        return;
      }

      // Activate ad
      try {
        console.log(`Activating ad for payment ${oid}`);

        const pendingPayment = transactionResult.pendingPayment;
        const submissionId = pendingPayment.submissionId;
        const adData = pendingPayment.adData;

        // Calculate expiration date
        const expirationDate = calculateExpirationDate(adData.duration);

        // Update submission to paid status
        await db
          .collection('ad_submissions')
          .doc(submissionId)
          .update({
            status: 'paid',
            paidAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromDate(expirationDate),
            paymentOrderId: oid,
          });

        // Activate ad based on type
        const adActivationRef = db.collection(getAdCollectionName(adData.adType)).doc();
        await adActivationRef.set({
          submissionId: submissionId,
          shopId: adData.shopId,
          shopName: adData.shopName,
          imageUrl: adData.imageUrl,
          adType: adData.adType,
          duration: adData.duration,
          activatedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(expirationDate),
          isActive: true,
          isManual: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          linkType: adData.linkType || null,
          linkedShopId: adData.linkedShopId || null,
          linkedProductId: adData.linkedProductId || null,
          // ✅ Add placeholder for dominantColor (will be updated by background task)
          dominantColor: null,
          colorExtractionQueued: adData.adType === 'topBanner',
        });

        // Update submission to active
        await db
          .collection('ad_submissions')
          .doc(submissionId)
          .update({
            status: 'active',
            activeAdId: adActivationRef.id,
          });

        // ✅ Queue dominant color extraction (non-blocking, async)
        await queueDominantColorExtraction(
          adActivationRef.id,
          adData.imageUrl,
          adData.adType,
        );

        // Schedule expiration task
        await scheduleAdExpiration(submissionId, expirationDate);

        // Update payment status
        await pendingPaymentRef.update({
          status: 'completed',
          activeAdId: adActivationRef.id,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: Date.now() - startTime,
        });

        // Update callback log
        await callbackLogRef.update({
          processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
          activeAdId: adActivationRef.id,
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
              <p>Reklamınız aktif edildi.</p>
            </div>
            <script>window.location.href = 'ad-payment-success://';</script>
          </body>
          </html>
        `);

        console.log(`✅ Ad payment ${oid} successfully processed`);
        return;
      } catch (activationError) {
        console.error('Ad activation failed after payment:', activationError);

        await pendingPaymentRef.update({
          status: 'payment_succeeded_activation_failed',
          activationError: activationError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await callbackLogRef.update({
          processingFailed: admin.firestore.FieldValue.serverTimestamp(),
          error: activationError.message,
          success: false,
        });

        response.send(`
          <!DOCTYPE html>
          <html>
          <head><title>Aktivasyon Hatası</title></head>
          <body>
            <div style="text-align:center; padding:50px;">
              <h2>Ödeme alındı ancak reklam aktif edilemedi</h2>
              <p>Lütfen destek ile iletişime geçin.</p>
              <p>Referans: ${oid}</p>
            </div>
            <script>window.location.href = 'ad-payment-failed://activation-error';</script>
          </body>
          </html>
        `);
        return;
      }
    } catch (error) {
      console.error('Ad payment callback critical error:', error);

      try {
        await db.collection('ad_payment_callback_errors').add({
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
  },
);

// Check Ad Payment Status
export const checkIsbankAdPaymentStatus = onCall(
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
      const pendingPaymentSnap = await db
        .collection('pendingAdPayments')
        .doc(orderNumber)
        .get();

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
        activeAdId: pendingPayment.activeAdId || null,
        errorMessage: pendingPayment.errorMessage || null,
      };
    } catch (error) {
      console.error('Check ad payment status error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

export const processAdColorExtraction = onRequest(
  {
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 120, // 2 minutes - plenty of time for download + processing
    invoker: 'private', // Only Cloud Tasks can invoke this
  },
  async (request, response) => {
    const startTime = Date.now();

    try {
      const {adId, imageUrl, adType} = request.body;

      // Validate input
      if (!adId || !imageUrl || !adType) {
        console.error('❌ Missing required parameters:', {adId, imageUrl, adType});
        response.status(400).send('adId, imageUrl, and adType are required');
        return;
      }

      console.log(`🎨 Processing color extraction for ad: ${adId}`);
      console.log(`   Type: ${adType}`);
      console.log(`   URL: ${imageUrl}`);

      // Only process topBanner ads
      if (adType !== 'topBanner') {
        console.log(`⏭️ Skipping: Not a topBanner ad`);
        response.status(200).send('Not a topBanner ad, skipping');
        return;
      }

      const db = admin.firestore();
      const adCollectionName = getAdCollectionName(adType);
      const adRef = db.collection(adCollectionName).doc(adId);

      // Check if ad still exists and is active
      const adSnap = await adRef.get();
if (!adSnap.exists) {
  console.warn(`⚠️ Ad ${adId} not found, may have been deleted`);
  response.status(404).send('Ad not found');
  return;
}

const adData = adSnap.data();

// ✅ CRITICAL FIX: Skip if color already extracted (prevents duplicate processing)
if (adData.dominantColor !== null && adData.dominantColor !== undefined) {
  console.log(`⏭️ Ad ${adId} already has dominant color (${adData.dominantColor}), skipping duplicate extraction`);
  response.status(200).send({
    success: true,
    message: 'Color already extracted',
    dominantColor: adData.dominantColor,
  });
  return;
}

// Skip if not active
if (!adData.isActive) {
  console.warn(`⚠️ Ad ${adId} is no longer active, skipping color extraction`);
  response.status(200).send('Ad is not active, skipping');
  return;
}

      // Extract dominant color
      console.log(`🔍 Extracting dominant color...`);
      const dominantColor = await extractDominantColorFromUrl(imageUrl);

      const processingTime = Date.now() - startTime;
      console.log(`⏱️ Color extraction completed in ${processingTime}ms`);

      // Update ad document with dominant color
      await adRef.update({
        dominantColor: dominantColor,
        colorExtractedAt: admin.firestore.FieldValue.serverTimestamp(),
        colorExtractionQueued: false,
        colorExtractionDuration: processingTime,
      });

      // Also update the submission document for consistency
      if (adData.submissionId) {
        await db
          .collection('ad_submissions')
          .doc(adData.submissionId)
          .update({
            dominantColor: dominantColor,
            colorExtractedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      }

      console.log(`✅ Dominant color saved successfully for ad ${adId}`);
      console.log(`   Color: 0x${dominantColor.toString(16).toUpperCase()}`);
      console.log(`   Total processing time: ${processingTime}ms`);

      response.status(200).send({
        success: true,
        adId: adId,
        dominantColor: dominantColor,
        processingTime: processingTime,
      });
    } catch (error) {
      console.error('❌ Critical error processing color extraction:', error);
      console.error('   Stack trace:', error.stack);

      // Log error to Firestore for debugging
      try {
        await admin.firestore().collection('ad_color_extraction_errors').add({
          adId: request.body?.adId || 'unknown',
          imageUrl: request.body?.imageUrl || 'unknown',
          error: error.message,
          stack: error.stack,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          processingTime: Date.now() - startTime,
        });
      } catch (logError) {
        console.error('❌ Failed to log error to Firestore:', logError);
      }

      response.status(500).send({
        success: false,
        error: error.message,
      });
    }
  },
);

// Process Ad Expiration (Cloud Task Handler)
export const processAdExpiration = onRequest(
  {
    region: 'europe-west3',
    memory: '256MB',
    timeoutSeconds: 30,
    invoker: 'private',
  },
  async (request, response) => {
    try {
      const {submissionId} = request.body;

      if (!submissionId) {
        response.status(400).send('submissionId is required');
        return;
      }

      const db = admin.firestore();
      const submissionRef = db.collection('ad_submissions').doc(submissionId);
      const submissionSnap = await submissionRef.get();

      if (!submissionSnap.exists) {
        console.log(`Submission ${submissionId} not found`);
        response.status(404).send('Submission not found');
        return;
      }

      // ✅ FIX: Get the data first
      const submissionData = submissionSnap.data();

      // Only expire if still active
      if (submissionData.status === 'active') {
        // Update submission status
        await submissionRef.update({
          status: 'expired',
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Deactivate the ad
        if (submissionData.activeAdId) {
          const adCollectionName = getAdCollectionName(submissionData.adType);
          await db
            .collection(adCollectionName)
            .doc(submissionData.activeAdId)
            .update({
              isActive: false,
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        // ✅ FIX: Create submission object with ID
        const submission = {
          ...submissionData,
          id: submissionId,
        };

        // ✅ SEND NOTIFICATIONS TO SHOP MEMBERS
        await sendAdExpirationNotifications(db, submission);

        console.log(`✅ Ad ${submissionId} expired successfully`);
      } else {
        console.log(`Ad ${submissionId} is not active, skipping expiration`);
      }

      response.status(200).send('Ad expiration processed');
    } catch (error) {
      console.error('Error processing ad expiration:', error);
      response.status(500).send('Error processing ad expiration');
    }
  },
);

async function sendAdExpirationNotifications(db, submission) {
  try {
    const shopId = submission.shopId;

    // Get shop data to find all members
    const shopSnap = await db.collection('shops').doc(shopId).get();

    if (!shopSnap.exists) {
      console.log(`Shop ${shopId} not found`);
      return;
    }

    const shopData = shopSnap.data();
    const shopMembers = getShopMemberIdsFromData(shopData);

    if (shopMembers.length === 0) {
      console.log(`No shop members found for ${shopId}`);
      return;
    }

    // Get ad type label for notification
    const adTypeLabel = getAdTypeLabel(submission.adType);

    // Create notifications for all shop members
    const batch = db.batch();
    let notificationCount = 0;

    for (const memberId of shopMembers) {
      const notificationRef = db
        .collection('users')
        .doc(memberId)
        .collection('notifications')
        .doc();

      batch.set(notificationRef, {
        type: 'ad_expired',
        adType: submission.adType,
        adTypeLabel: adTypeLabel,
        shopId: shopId,
        shopName: submission.shopName,
        submissionId: submission.id,
        imageUrl: submission.imageUrl || null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        // English
        message_en: `Your ${adTypeLabel} ad for ${submission.shopName} has expired.`,
        // Turkish
        message_tr: `${submission.shopName} için ${adTypeLabel} reklamınızın süresi doldu.`,
        // Russian
        message_ru: `Срок действия вашего объявления ${adTypeLabel} для ${submission.shopName} истек.`,
      });

      notificationCount++;
    }

    await batch.commit();
    console.log(`✅ Sent ${notificationCount} expiration notifications for ad ${submission.id}`);
  } catch (error) {
    console.error('Error sending ad expiration notifications:', error);
    // Don't throw - notifications are non-critical
  }
}

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

// Daily cleanup of expired ads (Scheduled Function)
export const cleanupExpiredAds = onSchedule(
  {
    schedule: 'every day 03:00',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
    memory: '256MB',
    timeoutSeconds: 540,
  },
  async (event) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    try {
      // Find all active ads that have expired
      const expiredAdsQuery = db
        .collection('ad_submissions')
        .where('status', '==', 'active')
        .where('expiresAt', '<=', now);

      const expiredAdsSnap = await expiredAdsQuery.get();

      console.log(`Found ${expiredAdsSnap.size} expired ads to clean up`);

      const batch = db.batch();
      let batchCount = 0;

      for (const doc of expiredAdsSnap.docs) {
        const submission = doc.data();

        // Update submission status
        batch.update(doc.ref, {
          status: 'expired',
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Deactivate the ad
        if (submission.activeAdId) {
          const adCollectionName = getAdCollectionName(submission.adType);
          const adRef = db.collection(adCollectionName).doc(submission.activeAdId);
          batch.update(adRef, {
            isActive: false,
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        batchCount++;

        // Firestore batch limit is 500
        if (batchCount >= 450) {
          await batch.commit();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      // ✅ SEND NOTIFICATIONS FOR ALL EXPIRED ADS
      for (const doc of expiredAdsSnap.docs) {
        const submission = {
          ...doc.data(),
          id: doc.id,
        };
        await sendAdExpirationNotifications(db, submission);
      }

      console.log(`✅ Cleaned up ${expiredAdsSnap.size} expired ads`);
    } catch (error) {
      console.error('Error cleaning up expired ads:', error);
    }
  },
);

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

// ================================
// AD ANALYTICS SYSTEM
// ================================

// Helper to calculate age from birthDate
function calculateAge(birthDate) {
  if (!birthDate || !birthDate.toDate) return null;

  const birth = birthDate.toDate();
  const today = new Date();
  let age = today.getFullYear() - birth.getFullYear();
  const monthDiff = today.getMonth() - birth.getMonth();

  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
    age--;
  }

  return age;
}

// Helper to get age group
function getAgeGroup(age) {
  if (!age || age < 0) return 'Unknown';
  if (age < 18) return 'Under 18';
  if (age < 25) return '18-24';
  if (age < 35) return '25-34';
  if (age < 45) return '35-44';
  if (age < 55) return '45-54';
  if (age < 65) return '55-64';
  return '65+';
}

// Helper to create analytics task (non-blocking)
async function createAnalyticsTask(analyticsData) {
  const project = 'emlak-mobile-app';
  const location = 'europe-west3';
  const queue = 'ad-analytics';

  try {
    const parent = tasksClient.queuePath(project, location, queue);

    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `https://${location}-${project}.cloudfunctions.net/processAdAnalytics`,
        body: Buffer.from(JSON.stringify(analyticsData)).toString('base64'),
        headers: {'Content-Type': 'application/json'},
        oidcToken: {
          serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
        },
      },
    };

    await tasksClient.createTask({parent, task});
    console.log(`✅ Analytics task queued for ad ${analyticsData.adId}`);
  } catch (error) {
    console.error('Error creating analytics task:', error);
    // Don't throw - analytics are non-critical
  }
}

// Track Ad Click (Called from Flutter)
export const trackAdClick = onCall(
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

      const {adId, adType, linkedType, linkedId} = request.data;

      if (!adId || !adType) {
        throw new HttpsError('invalid-argument', 'adId and adType are required');
      }

      const db = admin.firestore();
      const userId = request.auth.uid;

      // Get user data for demographics
      const userSnap = await db.collection('users').doc(userId).get();
      const userData = userSnap.data() || {};

      const age = calculateAge(userData.birthDate);
      const ageGroup = getAgeGroup(age);
      const gender = userData.gender || 'Not specified';

      // Queue analytics processing (non-blocking)
      await createAnalyticsTask({
        adId,
        adType,
        userId,
        gender,
        age,
        ageGroup,
        linkedType: linkedType || null,
        linkedId: linkedId || null,
        timestamp: Date.now(),
        eventType: 'click',
      });

      return {
        success: true,
        tracked: true,
      };
    } catch (error) {
      console.error('Error tracking ad click:', error);
      // Don't fail the user experience
      return {
        success: false,
        tracked: false,
        error: error.message,
      };
    }
  },
);

// Process Ad Analytics (Cloud Task Handler)
export const processAdAnalytics = onRequest(
  {
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 60,
    invoker: 'private',
  },
  async (request, response) => {
    try {
      const {
        adId,
        adType,
        userId,
        gender,
        age,
        ageGroup,
        linkedType,
        linkedId,
        timestamp,
      } = request.body;

      if (!adId || !userId) {
        response.status(400).send('adId and userId are required');
        return;
      }

      const db = admin.firestore();
      const clickTimestamp = admin.firestore.Timestamp.fromMillis(timestamp);

      // Get the ad collection name
      const adCollectionName = getAdCollectionName(adType);
      const adRef = db.collection(adCollectionName).doc(adId);

      // Use batched write for efficiency
      const batch = db.batch();

      // 1. Update ad document with aggregated metrics
      batch.update(adRef, {
        totalClicks: admin.firestore.FieldValue.increment(1),
        [`demographics.gender.${gender}`]: admin.firestore.FieldValue.increment(1),
        [`demographics.ageGroups.${ageGroup}`]: admin.firestore.FieldValue.increment(1),
        lastClickedAt: admin.firestore.FieldValue.serverTimestamp(),
        metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. Store individual click record for detailed analytics
      const clickRecordRef = db
        .collection(adCollectionName)
        .doc(adId)
        .collection('clicks')
        .doc();

      batch.set(clickRecordRef, {
        userId,
        gender,
        age: age || null,
        ageGroup,
        linkedType,
        linkedId,
        clickedAt: clickTimestamp,
        converted: false, // Will be updated if user makes purchase
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 3. Create user click record (for conversion tracking)
      const userClickRef = db
        .collection('users')
        .doc(userId)
        .collection('ad_clicks')
        .doc();

      batch.set(userClickRef, {
        adId,
        adType,
        linkedType,
        linkedId,
        clickedAt: clickTimestamp,
        converted: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();

      console.log(`✅ Analytics processed for ad ${adId}, user ${userId}`);
      response.status(200).send('Analytics processed');
    } catch (error) {
      console.error('Error processing ad analytics:', error);
      response.status(500).send('Error processing analytics');
    }
  },
);

// Track Ad Conversion (Called when order is created)
export const trackAdConversion = onCall(
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

      const {orderId, productIds, shopIds} = request.data;

      if (!orderId || !productIds || !Array.isArray(productIds)) {
        throw new HttpsError('invalid-argument', 'orderId and productIds array are required');
      }

      const db = admin.firestore();
      const userId = request.auth.uid;

      // Get user's recent ad clicks (last 30 days)
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
        return {success: true, conversions: 0};
      }

      const batch = db.batch();
      let conversionsCount = 0;

      // Check each click to see if it led to a conversion
      for (const clickDoc of userClicksSnap.docs) {
        const clickData = clickDoc.data();

        // Check if the linked product/shop matches the purchase
        let isConversion = false;

        if (clickData.linkedType === 'product' && productIds.includes(clickData.linkedId)) {
          isConversion = true;
        } else if (clickData.linkedType === 'shop' && shopIds && shopIds.includes(clickData.linkedId)) {
          isConversion = true;
        }

        if (isConversion) {
          conversionsCount++;

          // Update user's click record
          batch.update(clickDoc.ref, {
            converted: true,
            convertedAt: admin.firestore.FieldValue.serverTimestamp(),
            orderId: orderId,
          });

          // Update the ad's aggregated metrics
          const adCollectionName = getAdCollectionName(clickData.adType);
          const adRef = db.collection(adCollectionName).doc(clickData.adId);

          batch.update(adRef, {
            totalConversions: admin.firestore.FieldValue.increment(1),
            lastConvertedAt: admin.firestore.FieldValue.serverTimestamp(),
            metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Update the specific click record
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

      await batch.commit();

      console.log(`✅ Tracked ${conversionsCount} conversions for order ${orderId}`);
      return {success: true, conversions: conversionsCount};
    } catch (error) {
      console.error('Error tracking ad conversion:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

// Batch Analytics Snapshot (Daily scheduled function)
export const createDailyAdAnalyticsSnapshot = onSchedule(
  {
    schedule: 'every day 02:00',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 540,
  },
  async (event) => {
    const db = admin.firestore();
    const today = new Date();
    const snapshotDate = new Date(today.getFullYear(), today.getMonth(), today.getDate());

    try {
      console.log('Creating daily analytics snapshots...');

      const adCollections = ['market_top_ads_banners', 'market_thin_banners', 'market_banners'];
      let totalSnapshots = 0;

      for (const collectionName of adCollections) {
        // Get all active ads
        const adsSnap = await db
          .collection(collectionName)
          .where('isActive', '==', true)
          .get();

        const batch = db.batch();
        let batchCount = 0;

        for (const adDoc of adsSnap.docs) {
          const adData = adDoc.data();

          // Create daily snapshot
          const snapshotRef = db
            .collection(collectionName)
            .doc(adDoc.id)
            .collection('daily_snapshots')
            .doc(snapshotDate.toISOString().split('T')[0]);

          batch.set(snapshotRef, {
            date: admin.firestore.Timestamp.fromDate(snapshotDate),
            totalClicks: adData.totalClicks || 0,
            totalConversions: adData.totalConversions || 0,
            conversionRate: adData.totalClicks > 0 ? ((adData.totalConversions || 0) / adData.totalClicks) * 100 : 0,
            demographics: adData.demographics || {gender: {}, ageGroups: {}},
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          batchCount++;
          totalSnapshots++;

          // Firestore batch limit is 500
          if (batchCount >= 450) {
            await batch.commit();
            batchCount = 0;
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }
      }

      console.log(`✅ Created ${totalSnapshots} daily analytics snapshots`);
    } catch (error) {
      console.error('Error creating daily analytics snapshots:', error);
    }
  },
);


// // Ensure clients are instantiated only once.
// if (!global.retailClient) {
//   global.retailClient = new PredictionServiceClient({
//     projectId: process.env.GCP_PROJECT || 'emlak-mobile-app',
//   });
// }
// if (!global.userEventClient) {
//   global.userEventClient = new UserEventServiceClient({
//     projectId: process.env.GCP_PROJECT || 'emlak-mobile-app',
//   });
// }

// // --- Get Recommendations ---
// export const getRecommendations = onCall(
//   {
//     region: 'europe-west3',
//     minInstances: 1,
//   },
//   async (req) => {
//     // unpack
//     const {data, auth, rawRequest} = req;

//     // HTTP header lives on rawRequest.headers.authorization
//     const authHeader =
//       rawRequest?.headers?.authorization ||
//       '<<none>>';
//     console.log('  • authorization header:', authHeader);

//     // now enforce authentication
//     if (!auth) {
//       console.log('👎 Rejecting: unauthenticated');
//       throw new HttpsError('unauthenticated', 'User must be authenticated.');
//     }
//     console.log('✅ Authenticated user:', auth.uid);

//     // grab your retail client
//     const retailClient = global.retailClient;
//     if (!retailClient) {
//       throw new HttpsError('internal', 'Retail client not initialized.');
//     }

//     // ——— Unpack request data ———
//     const {
//       visitorId,
//       placement,
//       params,
//       experimentId,
//       currentProductId,
//     } = data;

//     if (!visitorId || typeof visitorId !== 'string') {
//       throw new HttpsError('invalid-argument', 'A valid visitorId is required.');
//     }

//     // ——— Determine placement ———
//     const recPlacement = placement || 'recently_viewed_default';
//     const projectId = process.env.GCP_PROJECT || 'emlak-mobile-app';
//     const fullyQualifiedPlacement =
//       `projects/${projectId}/locations/global/catalogs/default_catalog/placements/${recPlacement}`;

//     // ——— Build userEvent ———
//     const userEvent = {
//       eventType: currentProductId ? 'detail-page-view' : 'home-page-view',
//       visitorId,
//       eventTime: {
//         seconds: Math.floor(Date.now() / 1000),
//         nanos: (Date.now() % 1000) * 1e6,
//       },
//     };
//     if (currentProductId) {
//       userEvent.productDetails = [{product: {id: currentProductId}}];
//     }

//     // ——— Handle filter + pagination ———
//     // Based on the error message, we need to use simple space-separated filters
//     let filter = 'tag="shop_product" filterOutOfStockItems'; // Fixed filter syntax
//     let pageSize = 20;
//     let pageToken;
//     const MAX_PAGE_SIZE = 100;

//     if (params && typeof params === 'object') {
//       if (typeof params.filter === 'string') {
//         // Parse user filters
//         const parts = params.filter.split(' ').filter(Boolean);
//         const additionalFilters = [];

//         for (const p of parts) {
//           // Skip filterOutOfStockItems as we already have it
//           if (p === 'filterOutOfStockItems') continue;

//           if (p.startsWith('tag=')) {
//             // Add additional tag filters
//             additionalFilters.push(`tag="${p.slice(4).replace(/"/g, '')}"`);
//           } else {
//             // Add other filters as-is
//             additionalFilters.push(p);
//           }
//         }

//         // Append additional filters
//         if (additionalFilters.length > 0) {
//           filter = `tag="shop_product" filterOutOfStockItems ${additionalFilters.join(' ')}`;
//         }
//       }

//       if (params.pageSize) {
//         const ps = parseInt(params.pageSize, 10);
//         if (!isNaN(ps) && ps >= 1 && ps <= MAX_PAGE_SIZE) {
//           pageSize = ps;
//         } else {
//           throw new HttpsError(
//             'invalid-argument',
//             `pageSize must be between 1 and ${MAX_PAGE_SIZE}.`,
//           );
//         }
//       }
//       if (typeof params.pageToken === 'string') {
//         if (params.pageToken.length > 1000) {
//           throw new HttpsError('invalid-argument', 'pageToken is too long.');
//         }
//         pageToken = params.pageToken;
//       }
//     }

//     // ——— Build params map ———
//     const paramsMap = {};
//     if (experimentId && typeof experimentId === 'string') {
//       paramsMap.experimentId = {stringValue: experimentId};
//     }

//     // ——— Assemble PredictRequest ———
//     const predictionRequest = {
//       placement: fullyQualifiedPlacement,
//       userEvent,
//       ...(filter && {filter}),
//       pageSize,
//       ...(pageToken && {pageToken}),
//       ...(Object.keys(paramsMap).length && {params: paramsMap}),
//     };

//     console.log('PredictionRequest:', JSON.stringify(predictionRequest, null, 2));

//     // ——— Call the Retail API ———
//     try {
//       const [response] = await retailClient.predict(predictionRequest);
//       console.log('Retail API response count:', response.results?.length);

//       const recommendedProducts = (response.results || []).map((r) => r.id);
//       return {recommendedProducts, nextPageToken: response.nextPageToken};
//     } catch (err) {
//       console.error('Error fetching recommendations:', err);
//       throw new HttpsError('internal', 'Unable to fetch recommendations.');
//     }
//   },
// );

// // --- Ingest Transaction Event ---
// export const ingestTransactionEvent = onDocumentCreated(
//   {
//     region: 'europe-west3',
//     document: 'orders/{orderId}/items/{itemId}',
//   },
//   async (event) => {
//     const data = event.data.data();
//     if (!data) {
//       throw new HttpsError('invalid-argument', 'No order item data found.');
//     }

//     // Validate required fields
//     if (!data.buyerId || !data.productId) {
//       throw new HttpsError('invalid-argument', 'Order item must include buyerId and productId.');
//     }

//     // Determine product type based on shopId presence
//     // If shopId exists, it's a shop_product, otherwise it's a regular product
//     const productType = data.shopId ? 'shop_product' : 'regular_product';

//     // Extract category and subcategory from the product
//     // Since these aren't stored in the order item, we'll need to fetch from the product
//     let category = '';
//     let subcategory = '';

//     try {
//       // Try to get product details for category info
//       const productRef = data.shopId ?
//         admin.firestore().collection('shop_products').doc(data.productId) :
//         admin.firestore().collection('products').doc(data.productId);

//       const productSnap = await productRef.get();
//       if (productSnap.exists) {
//         const productData = productSnap.data();
//         category = productData.category || '';
//         subcategory = productData.subcategory || '';
//       }
//     } catch (error) {
//       console.log('Could not fetch product details for categories:', error);
//       // Continue without categories - they're optional
//     }

//     const userEvent = {
//       visitorId: data.buyerId,
//       eventType: 'purchase',
//       productDetails: [
//         {
//           product: {
//             id: data.productId,
//             ...(data.price && {
//               priceInfo: {
//                 price: {
//                   value: Number(data.price),
//                   currencyCode: data.currency || 'TRY',
//                 },
//               },
//             }),
//           },
//           ...(data.quantity && {quantity: Number(data.quantity)}),
//         },
//       ],
//       eventTime: {
//         seconds: Math.floor(Date.now() / 1000),
//         nanos: (Date.now() % 1000) * 1e6,
//       },
//       // ✅ FIXED: Changed from stringValue to text array format
//       attributes: {
//         ...(category && {category: {text: [category]}}),
//         ...(subcategory && {subcategory: {text: [subcategory]}}),
//         ...(data.sellerId && {sellerId: {text: [data.sellerId]}}),
//         productType: {text: [productType]},
//         // Optional: include selected attributes if relevant for recommendations
//         ...(data.selectedColor && {selectedColor: {text: [data.selectedColor]}}),
//         ...(data.selectedSize && {selectedSize: {text: [data.selectedSize]}}),
//       },
//     };

//     // If timestamp is available from the order item, use it
//     if (data.timestamp && data.timestamp._seconds) {
//       userEvent.eventTime = {
//         seconds: data.timestamp._seconds,
//         nanos: data.timestamp._nanoseconds || 0,
//       };
//     }

//     const projectId = process.env.GCLOUD_PROJECT || 'emlak-mobile-app';
//     const parent = `projects/${projectId}/locations/global/catalogs/default_catalog`;
//     const requestPayload = {parent, userEvent};

//     try {
//       const [response] = await global.userEventClient.writeUserEvent(requestPayload);
//       console.log(`Purchase event for product ${data.productId} ingested successfully:`, response);
//     } catch (error) {
//       console.error('Error ingesting purchase event:', error);
//       throw new HttpsError('internal', 'Failed to ingest purchase event.');
//     }
//   },
// );

// export const ingestDetailViewEvent = onDocumentCreated(
//   {
//     region: 'europe-west3',
//     document: 'products/{productId}/detailViews/{viewId}',
//   },
//   async (event) => {
//     const productId = event.params.productId;
//     const snap = event.data;
//     if (!snap) {
//       throw new HttpsError('invalid-argument', 'No detailView document snapshot found.');
//     }

//     const viewData = snap.data();
//     console.log('Ingesting detail-view, data:', viewData);

//     if (!viewData || !viewData.userId) {
//       throw new HttpsError('invalid-argument', 'Detail view must include userId.');
//     }

//     let eventTime;
//     if (viewData.viewStart && viewData.viewStart._seconds) {
//       eventTime = {
//         seconds: viewData.viewStart._seconds,
//         nanos: viewData.viewStart._nanoseconds || 0,
//       };
//     } else {
//       eventTime = {
//         seconds: Math.floor(Date.now() / 1000),
//         nanos: (Date.now() % 1000) * 1e6,
//       };
//     }

//     const userEvent = {
//       visitorId: viewData.userId,
//       eventType: 'detail-page-view',
//       eventTime: eventTime,
//       productDetails: [
//         {
//           product: {
//             id: productId,
//             ...(viewData.category && {
//               categories: [`${viewData.category}${viewData.subcategory ? `>${viewData.subcategory}` : ''}`],
//             }),
//             ...(viewData.brand && {brand: viewData.brand}),
//             ...(viewData.price && {
//               priceInfo: {
//                 price: {
//                   currencyCode: 'TRY',
//                   value: Number(viewData.price), // Fixed: was 'amount'
//                 },
//               },
//             }),
//           },
//           ...(viewData.quantity && {quantity: viewData.quantity}),
//         },
//       ],
//       attributes: { // Fixed: use text array instead of stringValue
//         productType: {text: ['regular_product']},
//       },
//     };

//     console.log('Sending userEvent:', JSON.stringify(userEvent, null, 2));

//     const projectId = process.env.GCLOUD_PROJECT || 'emlak-mobile-app';
//     const parent = `projects/${projectId}/locations/global/catalogs/default_catalog`;

//     try {
//       const [response] = await global.userEventClient.writeUserEvent({
//         parent,
//         userEvent,
//       });
//       console.log(`detail-page-view for product ${productId} ingested:`, response);
//     } catch (error) {
//       console.error('Error ingesting detail-page-view:', error);
//       throw new HttpsError('internal', 'Failed to ingest detail-page-view.');
//     }
//   },
// );

// export const ingestShopProductDetailViewEvent = onDocumentCreated(
//   {
//     region: 'europe-west3',
//     document: 'shop_products/{productId}/detailViews/{viewId}',
//   },
//   async (event) => {
//     const productId = event.params.productId;
//     const snap = event.data;
//     if (!snap) {
//       throw new HttpsError('invalid-argument', 'No detailView document snapshot found.');
//     }

//     const viewData = snap.data();
//     console.log('Ingesting shop product detail-view, data:', viewData);

//     if (!viewData || !viewData.userId) {
//       throw new HttpsError('invalid-argument', 'Detail view must include userId.');
//     }

//     let eventTime;
//     if (viewData.viewStart && viewData.viewStart._seconds) {
//       eventTime = {
//         seconds: viewData.viewStart._seconds,
//         nanos: viewData.viewStart._nanoseconds || 0,
//       };
//     } else {
//       eventTime = {
//         seconds: Math.floor(Date.now() / 1000),
//         nanos: (Date.now() % 1000) * 1e6,
//       };
//     }

//     const userEvent = {
//       visitorId: viewData.userId,
//       eventType: 'detail-page-view',
//       eventTime: eventTime,
//       productDetails: [
//         {
//           product: {
//             id: productId,
//             ...(viewData.category && {
//               categories: [`${viewData.category}${viewData.subcategory ? `>${viewData.subcategory}` : ''}`],
//             }),
//             ...(viewData.brand && {brand: viewData.brand}),
//             ...(viewData.price && {
//               priceInfo: {
//                 price: {
//                   currencyCode: 'TRY',
//                   value: Number(viewData.price), // Fixed: was 'amount'
//                 },
//               },
//             }),
//           },
//           ...(viewData.quantity && {quantity: viewData.quantity}),
//         },
//       ],
//       attributes: { // Fixed: use text array instead of stringValue
//         productType: {text: ['shop_product']},
//       },
//     };

//     console.log('Sending userEvent for shop product:', JSON.stringify(userEvent, null, 2));

//     const projectId = process.env.GCLOUD_PROJECT || 'emlak-mobile-app';
//     const parent = `projects/${projectId}/locations/global/catalogs/default_catalog`;

//     try {
//       const [response] = await global.userEventClient.writeUserEvent({
//         parent,
//         userEvent,
//       });
//       console.log(`detail-page-view for shop product ${productId} ingested:`, response);
//     } catch (error) {
//       console.error('Error ingesting shop product detail-page-view:', error);
//       throw new HttpsError('internal', 'Failed to ingest shop product detail-page-view.');
//     }
//   },
// );

// // Core function to export products from Firestore to GCS.
// async function exportProductsCore() {
//   const productsSnapshot = await admin.firestore().collection('products').where('needsSync', '==', true).get();
//   const shopProductsSnapshot = await admin.firestore().collection('shop_products').where('needsSync', '==', true).get();

//   const retailProducts = [];

//   // Process 'products' collection with a tag
//   productsSnapshot.forEach((doc) => {
//     const data = doc.data();
//     const retailProduct = {
//       id: data.productId,
//       title: data.productName,
//       description: data.description || '',
//       categories: [`${data.category} > ${data.subcategory}`].filter(Boolean),
//       brands: [data.brandModel].filter(Boolean),
//       availability: data.quantity && data.quantity > 0 ? 'IN_STOCK' : 'OUT_OF_STOCK',
//       images: (data.imageUrls || []).map((url) => ({uri: url})),
//       // Add tag to identify regular products
//       tags: ['regular_product'],
//     };
//     retailProducts.push(retailProduct);
//   });

//   // Process 'shop_products' collection with a different tag
//   shopProductsSnapshot.forEach((doc) => {
//     const data = doc.data();
//     const retailProduct = {
//       id: data.productId,
//       title: data.productName,
//       description: data.description || '',
//       categories: [`${data.category} > ${data.subcategory}`].filter(Boolean),
//       brands: [data.brandModel].filter(Boolean),
//       availability: data.quantity && data.quantity > 0 ? 'IN_STOCK' : 'OUT_OF_STOCK',
//       images: (data.imageUrls || []).map((url) => ({uri: url})),
//       // Add tag to identify shop products
//       tags: ['shop_product'],
//     };
//     retailProducts.push(retailProduct);
//   });

//   if (retailProducts.length === 0) {
//     console.log('No products need syncing.');
//     return {message: 'No products need syncing.', count: 0};
//   }

//   const bucketName = 'emlak-mobile-app.appspot.com';
//   const fileName = 'products.jsonl';
//   const bucket = storage.bucket(bucketName);
//   const file = bucket.file(fileName);
//   // Save each product as a JSON line
//   await file.save(retailProducts.map((p) => JSON.stringify(p)).join('\n'));

//   // Mark documents as synced in a batch update for both collections.
//   const batch = admin.firestore().batch();
//   productsSnapshot.forEach((doc) => {
//     batch.update(doc.ref, {needsSync: false});
//   });
//   shopProductsSnapshot.forEach((doc) => {
//     batch.update(doc.ref, {needsSync: false});
//   });
//   await batch.commit();

//   console.log('Products exported successfully:', retailProducts.length);
//   return {message: 'Products exported successfully.', count: retailProducts.length};
// }

// // Core function to import products from GCS to the Retail API.
// async function importProductsCore() {
//   const projectId = process.env.GCP_PROJECT || 'emlak-mobile-app';
//   const parent = `projects/${projectId}/locations/global/catalogs/default_catalog/branches/0`;

//   const importRequest = {
//     parent,
//     inputConfig: {
//       gcsSource: {
//         inputUris: [`gs://emlak-mobile-app.appspot.com/products.jsonl`],
//       },
//     },
//     errorsConfig: {
//       gcsPrefix: `gs://emlak-mobile-app.appspot.com/import_errors/`,
//     },
//   };

//   const retailClient = new ProductServiceClient();
//   console.log('Sending import request:', JSON.stringify(importRequest, null, 2)); // Debug log
//   try {
//     const [operation] = await retailClient.importProducts(importRequest);
//     console.log('Import initiated:', operation.name);
//     const [response] = await operation.promise();
//     console.log('Import response:', response);
//     if (response.error) {
//       throw new Error(`Import failed: ${response.error.message}`);
//     }
//     return {message: 'Import completed successfully.', response};
//   } catch (error) {
//     console.error('Import error details:', error);
//     throw error; // Re-throw for upstream handling
//   }
// }

// // ----- HTTP Functions (onRequest) -----

// export const syncExportProducts = onRequest({region: 'europe-west3'}, async (req, res) => {
//   try {
//     const result = await exportProductsCore();
//     res.json(result);
//   } catch (error) {
//     console.error('Error in syncExportProducts:', error);
//     res.status(500).json({error: 'Failed to export products.'});
//   }
// });

// export const syncImportProducts = onRequest({region: 'europe-west3'}, async (req, res) => {
//   try {
//     const result = await importProductsCore();
//     res.json(result);
//   } catch (error) {
//     console.error('Error in syncImportProducts:', error);
//     res.status(500).json({error: 'Failed to import products.'});
//   }
// });

// // ----- Scheduled Function (onSchedule) -----

// export const syncProductsDaily = onSchedule(
//   {
//     schedule: '0 0 * * *', // '0 0 * * *' Daily at midnight
//     timeZone: 'Europe/Istanbul',
//     region: 'europe-west3',
//   },
//   async () => {
//     try {
//       const exportResult = await exportProductsCore();
//       console.log(exportResult.message, exportResult.count);
//       const importResult = await importProductsCore();
//       console.log(importResult.message);
//       console.log('Daily product sync completed.');
//     } catch (error) {
//       console.error('Daily product sync failed:', error);
//     }
//   },
// );

// New Function: Sync Products with Algolia
// Helper function that syncs a document (product/shop_product) with Algolia.
const syncDocumentToAlgolia = async (collectionName, productId, beforeData, afterData, algoliaIndex) => {
  try {
    // Create an objectID that combines the collection name and productId to avoid collisions.
    const objectID = `${collectionName}_${productId}`;

    if (!beforeData && afterData) {
      // Document Created
      const product = {
        objectID,
        ...afterData,
        collection: collectionName,
      };
      await algoliaIndex.saveObject(product);
      console.log(`Document ${collectionName}/${productId} added to Algolia.`);
    } else if (beforeData && afterData) {
      // Document Updated
      const product = {
        objectID,
        ...afterData,
        collection: collectionName,
      };
      await algoliaIndex.saveObject(product);
      console.log(`Document ${collectionName}/${productId} updated in Algolia.`);
    } else if (beforeData && !afterData) {
      // Document Deleted
      await algoliaIndex.deleteObject(objectID);
      console.log(`Document ${collectionName}/${productId} deleted from Algolia.`);
    }
  } catch (error) {
    console.error(`Error syncing document ${collectionName}/${productId} with Algolia:`, error);
    throw error;
  }
};

// Firestore trigger for the "products" collection.
export const syncProductsWithAlgolia = onDocumentWritten(
  {region: 'europe-west3', document: 'products/{productId}'},
  async (event) => {
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();

    // Add the filter here - but only for updates (not creates/deletes)
    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory',
        'price', 'description', 'brandModel', 'subsubcategory', 'averageRating'];
      const hasRelevantChanges = searchFields.some((field) =>
        beforeData[field] !== afterData[field],
      );
      if (!hasRelevantChanges) return;
    }

    const index = await getAlgoliaIndex('products');

    if (!afterData) {
      // delete or clear
      return syncDocumentToAlgolia('products', event.params.productId, event.data.before?.data(), null, index);
    }

    // Build exactly the same extra fields you need:
    const localizedFields = {};
    for (const locale of SUPPORTED_LOCALES) {
      // existing category/subcategory
      try {
        localizedFields[`category_${locale}`] = localize('category', afterData.category, locale);
      } catch (error) {
        console.error(`Error localizing category: ${error.message}`);
        localizedFields[`category_${locale}`] = afterData.category;
      }

      try {
        localizedFields[`subcategory_${locale}`] = localize('subcategory', afterData.subcategory, locale);
      } catch (error) {
        console.error(`Error localizing subcategory: ${error.message}`);
        localizedFields[`subcategory_${locale}`] = afterData.subcategory;
      }

      try {
        localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', afterData.subsubcategory, locale);
      } catch (error) {
        console.error(`Error localizing subsubcategory: ${error.message}`);
        localizedFields[`subsubcategory_${locale}`] = afterData.subsubcategory;
      }

      // new: jewelry type (single)
      if (afterData.jewelryType) {
        try {
          localizedFields[`jewelryType_${locale}`] = localize('jewelryType', afterData.jewelryType, locale);
        } catch (error) {
          console.error(`Error localizing jewelryType: ${error.message}`);
          localizedFields[`jewelryType_${locale}`] = afterData.jewelryType;
        }
      }

      // new: jewelry materials (array → array of localized strings)
      if (Array.isArray(afterData.jewelryMaterials)) {
        try {
          localizedFields[`jewelryMaterials_${locale}`] =
            afterData.jewelryMaterials.map((mat) => {
              try {
                return localize('jewelryMaterial', mat, locale);
              } catch (error) {
                console.error(`Error localizing jewelry material "${mat}": ${error.message}`);
                return mat;
              }
            });
        } catch (error) {
          console.error(`Error localizing jewelryMaterials: ${error.message}`);
          localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials;
        }
      }
    }

    const augmented = {...afterData, ...localizedFields};
    await syncDocumentToAlgolia('products', event.params.productId, event.data.before?.data(), augmented, index);
  },
);

export const syncShopProductsWithAlgolia = onDocumentWritten(
  {region: 'europe-west3', document: 'shop_products/{productId}'},
  async (event) => {
    const productId = event.params.productId;
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;

    // Add the filter here - but only for updates (not creates/deletes)
    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory',
        'price', 'description', 'brandModel', 'subsubcategory',
        'averageRating', 'discountPercentage', 'campaignName', 'isBoosted'];
      const hasRelevantChanges = searchFields.some((field) =>
        beforeData[field] !== afterData[field],
      );
      if (!hasRelevantChanges) return;
    }

    const index = await getAlgoliaIndex('shop_products');

    // handle deletes
    if (!afterData) {
      return syncDocumentToAlgolia(
        'shop_products', productId, beforeData, null, index,
      );
    }

    // build one localized field per locale
    const localizedFields = {};
    for (const locale of SUPPORTED_LOCALES) {
      // existing category/subcategory
      try {
        localizedFields[`category_${locale}`] = localize('category', afterData.category, locale);
      } catch (error) {
        console.error(`Error localizing category: ${error.message}`);
        localizedFields[`category_${locale}`] = afterData.category;
      }

      try {
        localizedFields[`subcategory_${locale}`] = localize('subcategory', afterData.subcategory, locale);
      } catch (error) {
        console.error(`Error localizing subcategory: ${error.message}`);
        localizedFields[`subcategory_${locale}`] = afterData.subcategory;
      }

      try {
        localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', afterData.subsubcategory, locale);
      } catch (error) {
        console.error(`Error localizing subsubcategory: ${error.message}`);
        localizedFields[`subsubcategory_${locale}`] = afterData.subsubcategory;
      }

      // new: jewelry type (single)
      if (afterData.jewelryType) {
        try {
          localizedFields[`jewelryType_${locale}`] = localize('jewelryType', afterData.jewelryType, locale);
        } catch (error) {
          console.error(`Error localizing jewelryType: ${error.message}`);
          localizedFields[`jewelryType_${locale}`] = afterData.jewelryType;
        }
      }

      // new: jewelry materials (array → array of localized strings)
      if (Array.isArray(afterData.jewelryMaterials)) {
        try {
          localizedFields[`jewelryMaterials_${locale}`] =
            afterData.jewelryMaterials.map((mat) => {
              try {
                return localize('jewelryMaterial', mat, locale);
              } catch (error) {
                console.error(`Error localizing jewelry material "${mat}": ${error.message}`);
                return mat;
              }
            });
        } catch (error) {
          console.error(`Error localizing jewelryMaterials: ${error.message}`);
          localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials;
        }
      }
    }

    const augmented = {...afterData, ...localizedFields};

    await syncDocumentToAlgolia(
      'shop_products', productId, beforeData, augmented, index,
    );
  },
);

export const syncShopsWithAlgolia = onDocumentWritten(
  {region: 'europe-west3', document: 'shops/{shopId}'},
  async (event) => {
    const shopId = event.params.shopId;
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;

    // Filter to only sync when name, profileImageUrl, or isActive changes
    // Skip if this is not an update (for creates and deletes, we always sync)
    if (beforeData && afterData) {
      const relevantFields = ['name', 'profileImageUrl', 'isActive']; // Add isActive here
      const hasRelevantChanges = relevantFields.some((field) =>
        beforeData[field] !== afterData[field],
      );

      // If no relevant changes in an update, exit early
      if (!hasRelevantChanges) {
        console.log(`No relevant changes for shop ${shopId}, skipping sync`);
        return;
      }
    }

    const index = await getAlgoliaIndex('shops');

    // Handle deletes - sync with null to remove from Algolia
    if (!afterData) {
      // Even for deletes, we only need minimal data
      const minimalBeforeData = beforeData ? {
        name: beforeData.name,
        profileImageUrl: beforeData.profileImageUrl,
        categories: beforeData.categories,
        isActive: beforeData.isActive ?? true, // Add isActive here
      } : null;

      return syncDocumentToAlgolia(
        'shops', shopId, minimalBeforeData, null, index,
      );
    }

    // Build localized fields for categories
    const localizedFields = {};

    // Only process categories if they exist
    if (Array.isArray(afterData.categories)) {
      for (const locale of SUPPORTED_LOCALES) {
        try {
          localizedFields[`categories_${locale}`] = afterData.categories.map((category) => {
            try {
              return localize('category', category, locale);
            } catch (error) {
              console.error(`Error localizing category "${category}": ${error.message}`);
              return category;
            }
          });
        } catch (error) {
          console.error(`Error localizing categories for locale ${locale}: ${error.message}`);
          localizedFields[`categories_${locale}`] = afterData.categories;
        }
      }
    }

    // Create minimal document with only required fields
    const minimalData = {
      name: afterData.name,
      profileImageUrl: afterData.profileImageUrl || null,
      categories: afterData.categories || [],
      isActive: afterData.isActive ?? true, // Add isActive field, default to true
      ...localizedFields,
      // Add a searchable text field for better search experience
      searchableText: [
        afterData.name,
        ...(afterData.categories || []),
      ].filter(Boolean).join(' '),
    };

    // For beforeData in updates, also use minimal data
    const minimalBeforeData = beforeData ? {
      name: beforeData.name,
      profileImageUrl: beforeData.profileImageUrl,
      categories: beforeData.categories,
      isActive: beforeData.isActive ?? true, // Add isActive here
    } : null;

    await syncDocumentToAlgolia(
      'shops', shopId, minimalBeforeData, minimalData, index,
    );

    console.log(`Successfully synced shop ${shopId} to Algolia with minimal data`);
  },
);

export const syncOrdersWithAlgolia = onDocumentWritten(
  {region: 'europe-west3', document: 'orders/{orderId}/items/{itemId}'},
  async (event) => {
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();
    const orderId = event.params.orderId;
    const itemId = event.params.itemId;

    // Add the filter here - but only for updates (not creates/deletes)
    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory', 'subsubcategory',
        'price', 'brandModel', 'condition', 'shipmentStatus', 'buyerName', 'sellerName',
        'needsAnyReview', 'needsProductReview', 'needsSellerReview'];
      const hasRelevantChanges = searchFields.some((field) =>
        beforeData[field] !== afterData[field],
      );
      if (!hasRelevantChanges) return;
    }

    const index = await getAlgoliaIndex('orders');

    if (!afterData) {
      // Delete case
      return syncDocumentToAlgolia('orders', itemId, beforeData, null, index);
    }

    // Fetch the parent order document for additional context
    const db = admin.firestore();
    let orderData = {};
    try {
      const orderDoc = await db.collection('orders').doc(orderId).get();
      if (orderDoc.exists) {
        orderData = orderDoc.data();
      }
    } catch (error) {
      console.error(`Error fetching order ${orderId}:`, error.message);
    }

    // Build localized fields for categories
    const localizedFields = {};
    for (const locale of SUPPORTED_LOCALES) {
      // Localize category
      if (afterData.category) {
        try {
          localizedFields[`category_${locale}`] = localize('category', afterData.category, locale);
        } catch (error) {
          console.error(`Error localizing category: ${error.message}`);
          localizedFields[`category_${locale}`] = afterData.category;
        }
      }

      // Localize subcategory
      if (afterData.subcategory) {
        try {
          localizedFields[`subcategory_${locale}`] = localize('subcategory', afterData.subcategory, locale);
        } catch (error) {
          console.error(`Error localizing subcategory: ${error.message}`);
          localizedFields[`subcategory_${locale}`] = afterData.subcategory;
        }
      }

      // Localize subsubcategory
      if (afterData.subsubcategory) {
        try {
          localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', afterData.subsubcategory, locale);
        } catch (error) {
          console.error(`Error localizing subsubcategory: ${error.message}`);
          localizedFields[`subsubcategory_${locale}`] = afterData.subsubcategory;
        }
      }

      // Localize condition if available
      if (afterData.condition) {
        try {
          localizedFields[`condition_${locale}`] = localize('condition', afterData.condition, locale);
        } catch (error) {
          console.error(`Error localizing condition: ${error.message}`);
          localizedFields[`condition_${locale}`] = afterData.condition;
        }
      }

      // Localize shipment status
      if (afterData.shipmentStatus) {
        try {
          localizedFields[`shipmentStatus_${locale}`] = localize('shipmentStatus', afterData.shipmentStatus, locale);
        } catch (error) {
          console.error(`Error localizing shipmentStatus: ${error.message}`);
          localizedFields[`shipmentStatus_${locale}`] = afterData.shipmentStatus;
        }
      }
    }

    // Create the augmented document with order context and localized fields
    const augmented = {
      ...afterData,
      ...localizedFields,
      // Add order-level data for better search context
      orderTotalPrice: orderData.totalPrice || 0,
      orderTotalQuantity: orderData.totalQuantity || 0,
      orderPaymentMethod: orderData.paymentMethod || '',
      orderTimestamp: orderData.timestamp || afterData.timestamp,
      orderAddress: orderData.address || null,
      // Calculate item total (price * quantity)
      itemTotal: (afterData.price || 0) * (afterData.quantity || 1),
      // Add searchable text fields
      searchableText: [
        afterData.productName,
        afterData.buyerName,
        afterData.sellerName,
        afterData.brandModel,
        afterData.category,
        afterData.subcategory,
        afterData.subsubcategory,
        afterData.condition,
        afterData.shipmentStatus,
      ].filter(Boolean).join(' '),
      // Add timestamp for sorting (convert Firestore timestamp to Unix timestamp)
      timestampForSorting: afterData.timestamp?.seconds || Math.floor(Date.now() / 1000),
    };

    await syncDocumentToAlgolia('orders', itemId, beforeData, augmented, index);
  },
);

export const dailyComputeRankingScores = onSchedule(
  {
    schedule: '0 */12 * * *', // Every 12 hours - less frequent
    timeZone: 'UTC',
    region: 'europe-west3',
    memory: '1GiB', // Increase for parallel processing
    timeoutSeconds: 540, // 9 minutes max
  },
  async () => {
    const db = admin.firestore();
    console.log('[dailyComputeRankingScores] start');

    // 1) Use static thresholds (update manually quarterly)
    const thresholds = STATIC_THRESHOLDS;

    // 2) Only process products with actual metric changes
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 12 * 60 * 60 * 1000,
    );

    // 3) Process collections in parallel
    const results = await Promise.allSettled([
      processCollection(db, 'products', cutoff, thresholds),
      processCollection(db, 'shop_products', cutoff, thresholds),
    ]);

    const totalUpdated = results
      .filter((r) => r.status === 'fulfilled')
      .reduce((sum, r) => sum + r.value, 0);

    console.log(`[dailyComputeRankingScores] done. Updated ${totalUpdated} products`);
  },
);

// Static thresholds - update these quarterly based on analytics
const STATIC_THRESHOLDS = {
  purchaseP95: 100,
  cartP95: 50,
  favP95: 50,
};

async function processCollection(db, collectionName, cutoff, thresholds) {
  let totalProcessed = 0;
  const updates = [];
  let lastDoc = null;
  let hasMore = true;
  const QUERY_LIMIT = 500;

  while (hasMore) {
    let query = db.collection(collectionName)
      .where('metricsUpdatedAt', '>=', cutoff)
      .orderBy('metricsUpdatedAt')
      .limit(QUERY_LIMIT);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();

    if (snapshot.empty) {
      hasMore = false;
      break;
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    hasMore = snapshot.docs.length === QUERY_LIMIT;

    snapshot.forEach((doc) => {
      const data = computeRankingScore(doc.data(), thresholds);
      if (data) {
        updates.push({ref: doc.ref, data});
      }
    });

    if (updates.length >= 450) {
      const batch = updates.splice(0, 450); // Extract exactly 450
      await commitBatch(db, batch);
      totalProcessed += batch.length; // Count what you actually committed
    }
  }

  if (updates.length > 0) {
    await commitBatch(db, updates);
    totalProcessed += updates.length;
  }

  console.log(`[${collectionName}] Processed ${totalProcessed} products`);
  return totalProcessed;
}

function computeRankingScore(d, thresholds) {
  // Skip if no meaningful metrics changed
  if (!d.clickCount && !d.purchaseCount && !d.dailyClickCount) {
    return null;
  }

  const impressions = Math.max(d.impressionCount || 0, 1);
  const clicks = Math.max(d.clickCount || 0, 0);
  const purchases = Math.max(d.purchaseCount || 0, 0);
  const dailyClicks = Math.max(d.dailyClickCount || 0, 0);

  const purchaseNorm = Math.min(purchases / thresholds.purchaseP95, 1.0);
  const ctr = impressions > 10 ? Math.min(clicks / impressions, 1.0) : 0;
  const conv = clicks > 5 ? Math.min(purchases / clicks, 1.0) : 0;
  const ratingNorm = (d.averageRating || 0) / 5;
  const cartNorm = Math.min((d.cartCount || 0) / thresholds.cartP95, 1.0);
  const favNorm = Math.min((d.favoritesCount || 0) / thresholds.favP95, 1.0);

  const ageDays = (Date.now() - d.createdAt.toMillis()) / (1000 * 60 * 60 * 24);
  const recencyBoost = Math.exp(-ageDays / 30);
  const coldStartBonus = ageDays <= 7 ? 0.2 : 0;
  const trendingBonus = dailyClicks >= 10 ? 0.15 : 0;

  const baseScore =
    0.20 * purchaseNorm +
    0.15 * ctr +
    0.10 * conv +
    0.10 * ratingNorm +
    0.10 * cartNorm +
    0.10 * favNorm +
    0.25 * recencyBoost;

  const enhancedScore = baseScore + coldStartBonus + trendingBonus;
  const boostMultiplier = d.isBoosted ? 1.5 : 1.0;
  const rankingScore = Math.min(enhancedScore * boostMultiplier, 2.0);
  const promotionScore = d.isBoosted ? rankingScore + 1000 : rankingScore;

  return {
    rankingScore,
    promotionScore,
    lastRankingUpdate: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function commitBatch(db, updates) {
  const batch = db.batch();
  updates.forEach(({ref, data}) => {
    batch.update(ref, data);
  });
  await batch.commit();
  console.log(`Committed batch of ${updates.length} updates`);
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
  const type = notificationData.type || 'default';
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

  // 3) Compute the deep-link route for GoRouter
  //    (defaults to your in-app notifications list)
  let route = '/notifications';
  switch (type) {
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
    apns: {
      headers: {'apns-priority': '10'},
      payload: {aps: {sound: 'default', badge: 1}},
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'high_importance_channel',
        sound: 'default',
        icon: 'ic_notification',
      },
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
        route = `/seller-panel?shopId=${shopId}&tab=1`;  // Products tab
        break;
    case 'campaign_ended':
      route = `/seller-panel?shopId=${shopId}&tab=0`;
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
              sound: 'default', 
              badge: 1,
              mutableContent: 1,
            }
          },
        },
        
        // Android Configuration
        android: {
          priority: 'high',
          notification: {
            channelId: 'high_importance_channel',
            sound: 'default',
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
        filePath,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Add boost-specific fields if it's a boost receipt
      if (taskData.receiptType === 'boost' && taskData.boostData) {
        receiptDocument.boostDuration = taskData.boostData.boostDuration;
        receiptDocument.itemCount = taskData.boostData.itemCount;
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

// Boost-specific information
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
if (data.receiptType !== 'boost') {
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
const nameLabel = (data.receiptType === 'boost' && data.ownerType === 'shop') ? t.shopName : t.name;
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
  if (data.receiptType !== 'boost' && data.buyerAddress) {
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

    if (data.receiptType === 'boost' && data.boostData) {
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
          .text(`${data.boostData.boostDuration} min`, 260, yPosition, {width: 100})
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
    const deliveryPrice = data.deliveryPrice || 0;
    const subtotal = data.itemsSubtotal || (data.totalPrice - deliveryPrice);
    const grandTotal = subtotal + deliveryPrice;

    // Subtotal row
    doc.font(titleFont)
      .fontSize(11)
      .fillColor('#666')
      .text(`${t.subtotal}:`, 390, yPosition)
      .fillColor('#333')
      .text(`${subtotal.toFixed(0)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});

    yPosition += 20;

   // Delivery price row - Only show for regular orders, not boost receipts
if (data.receiptType !== 'boost') {
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

    // Divider line
    doc.moveTo(380, yPosition - 5)
      .lineTo(550, yPosition - 5)
      .strokeColor('#333')
      .lineWidth(1.5)
      .stroke();

    yPosition += 10;

    // Total with background - USE grandTotal here
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

export const updateBestSellerRanks = onSchedule(
  {
    schedule: 'every 6 hours',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
  },
  async () => {
    const db = admin.firestore();
    const shopProductsRef = db.collection('shop_products');

    try {
      // 1) grab all unique subsubcategories
      const subSnap = await shopProductsRef
        .orderBy('subsubcategory')
        .select('subsubcategory')
        .get();

      const subsubs = [
        ...new Set(
          subSnap.docs
            .map((d) => d.data().subsubcategory)
            .filter((s) => typeof s === 'string' && s.trim()),
        ),
      ];

      // 2) for each subsubcategory, do its ranking in parallel
      await Promise.all(
        subsubs.map(async (sub) => {
          // kick off both queries in parallel
          const [topSnap, restSnap] = await Promise.all([
            shopProductsRef
              .where('subsubcategory', '==', sub)
              .orderBy('purchaseCount', 'desc')
              .limit(10)
              .get(),
            shopProductsRef
              .where('subsubcategory', '==', sub)
              .where(
                'purchaseCount',
                '<',
                // cutoff will be adjusted below if fewer than 10
                topSnap.docs[9]?.data().purchaseCount ?? 0,
              )
              .get(),
          ]);

          if (topSnap.empty) return;

          const batch = db.batch();
          // assign 1–10
          let rank = 1;
          topSnap.docs.forEach((doc) => {
            batch.update(doc.ref, {bestSellerRank: rank++});
          });

          // clear everyone else (below cutoff)
          restSnap.docs.forEach((doc) => {
            batch.update(doc.ref, {
              bestSellerRank: admin.firestore.FieldValue.delete(),
            });
          });

          await batch.commit();
          console.log(`Updated bestSellerRank for "${sub}"`);
        }),
      );

      console.log('Finished updating bestSellerRank for all subsubcategories');
    } catch (error) {
      console.error('Error updating bestSellerRank by subsubcategory:', error);
      throw new HttpsError('internal', 'Failed to update bestSellerRank');
    }

    return null;
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
  // Email subjects by language
  const subjects = {
    en: 'Nar24 - Email Verification Code',
    tr: 'Nar24 - Email Doğrulama Kodu',
    ru: 'Nar24 - Код подтверждения электронной почты',
  };

  // Split code into individual digits for better rendering
  const codeDigits = code.split('');

  // Email HTML templates by language
  const getEmailHtml = (lang, codeDigits, name) => {
    const templates = {
      en: {
        title: 'Verify Your Email',
        greeting: `Hello ${name},`,
        message: 'Thank you for signing up with Nar24. To complete your registration, please enter the verification code below:',
        codeLabel: 'Your Verification Code',
        expiry: 'This code expires in 5 minutes',
        warning: 'If you did not create an account with Nar24, please ignore this email or contact our support team.',
        footer: 'This is an automated message from Nar24. Please do not reply to this email.',
        copyright: '© 2024 Nar24. All rights reserved.',
      },
      tr: {
        title: 'E-postanızı Doğrulayın',
        greeting: `Merhaba ${name},`,
        message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Kaydınızı tamamlamak için lütfen aşağıdaki doğrulama kodunu girin:',
        codeLabel: 'Doğrulama Kodunuz',
        expiry: 'Bu kod 5 dakika içinde sona erer',
        warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin veya destek ekibimizle iletişime geçin.',
        footer: 'Bu, Nar24 tarafından gönderilen otomatik bir mesajdır. Lütfen bu e-postayı yanıtlamayın.',
        copyright: '© 2024 Nar24. Tüm hakları saklıdır.',
      },
      ru: {
        title: 'Подтвердите вашу почту',
        greeting: `Здравствуйте, ${name}!`,
        message: 'Благодарим вас за регистрацию в Nar24. Чтобы завершить регистрацию, введите код подтверждения ниже:',
        codeLabel: 'Ваш код подтверждения',
        expiry: 'Срок действия кода истекает через 5 минут',
        warning: 'Если вы не создавали учетную запись в Nar24, проигнорируйте это письмо или свяжитесь с нашей службой поддержки.',
        footer: 'Это автоматическое сообщение от Nar24. Пожалуйста, не отвечайте на это письмо.',
        copyright: '© 2024 Nar24. Все права защищены.',
      },
    };

    const t = templates[lang] || templates.en;

    // Generate individual digit boxes for maximum compatibility
    const digitBoxes = codeDigits.map((digit) => `
              <td style="padding:0 4px;">
                <table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                  <tr>
                    <td style="width:44px;height:56px;background-color:#ffffff;border:2px solid #ff6b35;border-radius:8px;text-align:center;vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-size:28px;font-weight:bold;color:#333333;">
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
  <title>${t.title}</title>
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
<body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;-webkit-font-smoothing:antialiased;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%;">
  
  <!-- Wrapper Table -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f4f4f4;">
    <tr>
      <td align="center" style="padding:40px 20px;">
        
        <!-- Main Content Table -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;background-color:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
          
          <!-- Header -->
          <tr>
            <td style="background-color:#ff6b35;padding:30px 40px;text-align:center;">
              <h1 style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:32px;font-weight:bold;color:#ffffff;">Nar24</h1>
            </td>
          </tr>
          
          <!-- Body -->
          <tr>
            <td style="padding:40px;">
              
              <!-- Title -->
              <h2 style="margin:0 0 24px 0;font-family:Arial,Helvetica,sans-serif;font-size:24px;font-weight:bold;color:#333333;text-align:center;">
                ${t.title}
              </h2>
              
              <!-- Greeting -->
              <p style="margin:0 0 16px 0;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:24px;color:#555555;">
                ${t.greeting}
              </p>
              
              <!-- Message -->
              <p style="margin:0 0 32px 0;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:24px;color:#555555;">
                ${t.message}
              </p>
              
              <!-- Code Label -->
              <p style="margin:0 0 16px 0;font-family:Arial,Helvetica,sans-serif;font-size:14px;font-weight:bold;color:#888888;text-align:center;text-transform:uppercase;letter-spacing:1px;">
                ${t.codeLabel}
              </p>
              
              <!-- Verification Code Box -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:16px;">
                <tr>
                  <td align="center">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="background-color:#f8f9fa;border-radius:12px;padding:24px;">
                      <tr>
                        ${digitBoxes}
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              
              <!-- Fallback Plain Text Code (ensures code is always accessible) -->
              <p style="margin:0 0 32px 0;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#888888;text-align:center;">
                Code: <strong style="color:#333333;font-size:18px;letter-spacing:2px;">${codeDigits.join('')}</strong>
              </p>
              
              <!-- Expiry Notice -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:24px;">
                <tr>
                  <td style="background-color:#fff8e1;border-left:4px solid #ffc107;padding:16px;border-radius:0 8px 8px 0;">
                    <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#856404;">
                      <strong>&#9200;</strong> ${t.expiry}
                    </p>
                  </td>
                </tr>
              </table>
              
              <!-- Warning -->
              <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#888888;">
                ${t.warning}
              </p>
              
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background-color:#f8f9fa;padding:24px 40px;border-top:1px solid #eeeeee;">
              <p style="margin:0 0 8px 0;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#999999;text-align:center;">
                ${t.footer}
              </p>
              <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#999999;text-align:center;">
                ${t.copyright}
              </p>
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

  // Create mail document for SendGrid extension
  const mailDoc = {
    to: [email],
    message: {
      subject: subjects[languageCode] || subjects.en,
      html: getEmailHtml(languageCode, codeDigits, displayName),
      // Add plain text version for clients that don't support HTML
      text: getPlainTextEmail(languageCode, code, displayName),
    },
  };

  // Add to mail collection - SendGrid extension will process it
  await admin.firestore().collection('mail').add(mailDoc);
}

// Helper function to generate plain text email (fallback for non-HTML clients)
function getPlainTextEmail(lang, code, name) {
  const templates = {
    en: {
      title: 'Email Verification - Nar24',
      greeting: `Hello ${name},`,
      message: 'Thank you for signing up with Nar24. To complete your registration, please enter the verification code below:',
      codeLabel: 'Your Verification Code',
      expiry: 'This code expires in 5 minutes.',
      warning: 'If you did not create an account with Nar24, please ignore this email.',
      footer: 'This is an automated message from Nar24.',
    },
    tr: {
      title: 'E-posta Doğrulama - Nar24',
      greeting: `Merhaba ${name},`,
      message: 'Nar24\'e kaydolduğunuz için teşekkür ederiz. Kaydınızı tamamlamak için lütfen aşağıdaki doğrulama kodunu girin:',
      codeLabel: 'Doğrulama Kodunuz',
      expiry: 'Bu kod 5 dakika içinde sona erer.',
      warning: 'Nar24\'te bir hesap oluşturmadıysanız, lütfen bu e-postayı görmezden gelin.',
      footer: 'Bu, Nar24 tarafından gönderilen otomatik bir mesajdır.',
    },
    ru: {
      title: 'Подтверждение почты - Nar24',
      greeting: `Здравствуйте, ${name}!`,
      message: 'Благодарим вас за регистрацию в Nar24. Чтобы завершить регистрацию, введите код подтверждения ниже:',
      codeLabel: 'Ваш код подтверждения',
      expiry: 'Срок действия кода истекает через 5 минут.',
      warning: 'Если вы не создавали учетную запись в Nar24, проигнорируйте это письмо.',
      footer: 'Это автоматическое сообщение от Nar24.',
    },
  };

  const t = templates[lang] || templates.en;

  return `
${t.title}
========================================

${t.greeting}

${t.message}

${t.codeLabel}: ${code}

${t.expiry}

${t.warning}

---
${t.footer}
© 2024 Nar24
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
        // Get receipt from shop's collection
        receiptDoc = await admin.firestore()
          .collection('shops')
          .doc(shopId)
          .collection('receipts')
          .doc(receiptId)
          .get();

        if (!receiptDoc.exists) {
          throw new HttpsError('not-found', 'Receipt not found');
        }

        // Get shop details for language
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
        // Get user's receipt (existing logic)
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
        
        // Verify ownership for user receipts only
        if (receiptData.buyerId !== uid) {
          throw new HttpsError('permission-denied', 'Access denied');
        }
      }

      const receiptData = receiptDoc.data();

      // Rest of the function stays the same...
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

      // Get localized content
      const content = getLocalizedContent(languageCode);
      const orderIdShort = orderId.substring(0, 8).toUpperCase();
      const receiptIdShort = receiptId.substring(0, 8).toUpperCase();

      // Format date
      const orderDate = receiptData.createdAt ?
        new Date(receiptData.createdAt.toDate()).toLocaleDateString(languageCode === 'tr' ? 'tr-TR' : languageCode === 'ru' ? 'ru-RU' : 'en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        }) : new Date().toLocaleDateString();

      // Enhanced HTML email template
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
        <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f7f8fa;">
          
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f7f8fa;padding:20px 0;">
            <tr>
              <td align="center">
                
                <!-- Main Container -->
                <table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;background-color:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.07);">
                  
                  <!-- Header Section -->
                  <tr>
                    <td style="background:linear-gradient(135deg,#ff6b35 0%,#ff8555 100%);padding:40px 30px;text-align:center;">
                      <h1 style="margin:0;color:#ffffff;font-size:36px;font-weight:700;letter-spacing:-0.5px;">Nar24</h1>
                      <p style="margin:10px 0 0 0;color:#ffe5dd;font-size:14px;font-weight:500;">${content.tagline}</p>
                    </td>
                  </tr>
                  
                  <!-- Success Icon & Message -->
                  <tr>
                    <td style="padding:40px 30px 20px 30px;text-align:center;">
                      <div style="display:inline-block;width:80px;height:80px;background:linear-gradient(135deg,#4ade80 0%,#22c55e 100%);border-radius:50%;margin-bottom:20px;">
                        <div style="color:#ffffff;font-size:40px;line-height:80px;">✓</div>
                      </div>
                      <h2 style="margin:0 0 10px 0;color:#1a1a1a;font-size:24px;font-weight:600;">${content.successTitle}</h2>
                      <p style="margin:0;color:#6b7280;font-size:16px;line-height:24px;">${content.greeting} ${displayName}, ${content.message}</p>
                    </td>
                  </tr>
                  
                  <!-- Order Details Card -->
                  <tr>
                    <td style="padding:0 30px 30px 30px;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:linear-gradient(135deg,#fef3f2 0%,#fff7f5 100%);border-radius:12px;border:1px solid #fed7d2;">
                        <tr>
                          <td style="padding:24px;">
                            
                            <!-- Order Header -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%">
                              <tr>
                                <td style="padding-bottom:20px;border-bottom:1px solid #fed7d2;">
                                  <h3 style="margin:0 0 8px 0;color:#ff6b35;font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">${content.orderDetailsTitle}</h3>
                                </td>
                              </tr>
                            </table>
                            
                            <!-- Order Info Grid -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:20px;">
                              <tr>
                                <td width="50%" style="padding-right:10px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.orderLabel}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">#${orderIdShort}</p>
                                </td>
                                <td width="50%" style="padding-left:10px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.receiptLabel}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">#${receiptIdShort}</p>
                                </td>
                              </tr>
                              <tr>
                                <td colspan="2" style="padding-top:16px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.dateLabel}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">${orderDate}</p>
                                </td>
                              </tr>
                            </table>
                            
                            <!-- Total Amount -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:20px;padding-top:20px;border-top:1px solid #fed7d2;">
                              <tr>
                                <td>
                                  <p style="margin:0;color:#6b7280;font-size:14px;font-weight:500;">${content.totalLabel}</p>
                                </td>
                                <td align="right">
                                  <p style="margin:0;color:#ff6b35;font-size:28px;font-weight:700;">${receiptData.totalPrice.toFixed(0)} ${receiptData.currency || 'TL'}</p>
                                </td>
                              </tr>
                            </table>
                            
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Download Button -->
${pdfUrl ? `
<tr>
  <td style="padding:0 30px 40px 30px;text-align:center;">
    <a href="${pdfUrl}" style="display:inline-block;padding:16px 40px;background:linear-gradient(135deg,#ff6b35 0%,#ff8555 100%);color:#ffffff;text-decoration:none;border-radius:10px;font-size:16px;font-weight:600;box-shadow:0 4px 14px 0 rgba(255,107,53,0.35);">
      📄 ${content.downloadButton}
    </a>
    <p style="margin:12px 0 0 0;color:#9ca3af;font-size:12px;">${content.downloadHint}</p>
  </td>
</tr>
` : ''}
                  
                  <!-- Help Section -->
                  <tr>
                    <td style="background-color:#fafbfc;padding:30px;text-align:center;border-top:1px solid #e5e7eb;">
                      <p style="margin:0 0 8px 0;color:#6b7280;font-size:14px;">${content.needHelp}</p>
                      <a href="mailto:support@nar24.com" style="color:#ff6b35;text-decoration:none;font-weight:600;font-size:14px;">${content.contactSupport}</a>
                    </td>
                  </tr>
                  
                  <!-- Footer -->
                  <tr>
                    <td style="background-color:#1a1a1a;padding:30px;text-align:center;">
                      <p style="margin:0 0 8px 0;color:#ffffff;font-size:14px;font-weight:500;">${content.footer}</p>
                      <p style="margin:0 0 16px 0;color:#9ca3af;font-size:12px;">© 2024 Nar24. ${content.rights}</p>
                      
                      <!-- Social Media Icons -->
                      <table cellpadding="0" cellspacing="0" border="0" align="center">
                        <tr>
                          <td style="padding:0 8px;">
                            <a href="https://facebook.com/nar24" style="display:inline-block;width:32px;height:32px;background-color:#2d2d2d;border-radius:50%;text-align:center;line-height:32px;text-decoration:none;">
                              <span style="color:#ffffff;font-size:16px;">f</span>
                            </a>
                          </td>
                          <td style="padding:0 8px;">
                            <a href="https://instagram.com/nar24" style="display:inline-block;width:32px;height:32px;background-color:#2d2d2d;border-radius:50%;text-align:center;line-height:32px;text-decoration:none;">
                              <span style="color:#ffffff;font-size:16px;">📷</span>
                            </a>
                          </td>
                          <td style="padding:0 8px;">
                            <a href="https://twitter.com/nar24" style="display:inline-block;width:32px;height:32px;background-color:#2d2d2d;border-radius:50%;text-align:center;line-height:32px;text-decoration:none;">
                              <span style="color:#ffffff;font-size:16px;">X</span>
                            </a>
                          </td>
                        </tr>
                      </table>
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
          subject: `✅ ${content.subject} #${orderIdShort} - Nar24`,
          html: emailHtml,
        },
        template: {
          name: 'receipt',
          data: {
            receiptId,
            orderId,
            type: 'order_receipt',
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

function getLocalizedContent(languageCode) {
  const content = {
    en: {
      greeting: 'Hello',
      message: 'thank you for your order!',
      orderLabel: 'Order ID',
      receiptLabel: 'Receipt ID',
      dateLabel: 'Date',
      totalLabel: 'Total Amount',
      subject: 'Your Receipt',
      downloadButton: 'Download Receipt PDF',
      downloadHint: 'Save this receipt for your records',
      footer: 'Thank you for shopping with Nar24!',
      rights: 'All rights reserved.',
      tagline: 'Your Premium Shopping Destination',
      successTitle: 'Payment Successful!',
      orderDetailsTitle: 'Order Information',
      needHelp: 'Need help with your order?',
      contactSupport: 'Contact Support',
    },
    tr: {
      greeting: 'Merhaba',
      message: 'siparişiniz için teşekkür ederiz!',
      orderLabel: 'Sipariş No',
      receiptLabel: 'Fatura No',
      dateLabel: 'Tarih',
      totalLabel: 'Toplam Tutar',
      subject: 'Faturanız',
      downloadButton: 'Faturayı PDF Olarak İndir',
      downloadHint: 'Bu faturayı kayıtlarınız için saklayın',
      footer: 'Nar24\'ten alışveriş yaptığınız için teşekkür ederiz!',
      rights: 'Tüm hakları saklıdır.',
      tagline: 'Premium Alışveriş Deneyiminiz',
      successTitle: 'Ödeme Başarılı!',
      orderDetailsTitle: 'Sipariş Bilgileri',
      needHelp: 'Siparişinizle ilgili yardıma mı ihtiyacınız var?',
      contactSupport: 'Destek ile İletişime Geç',
    },
    ru: {
      greeting: 'Здравствуйте',
      message: 'спасибо за ваш заказ!',
      orderLabel: 'Номер заказа',
      receiptLabel: 'Номер чека',
      dateLabel: 'Дата',
      totalLabel: 'Итого',
      subject: 'Ваш чек',
      downloadButton: 'Скачать чек в PDF',
      downloadHint: 'Сохраните этот чек для ваших записей',
      footer: 'Спасибо за покупки в Nar24!',
      rights: 'Все права защищены.',
      tagline: 'Ваш премиум шоппинг',
      successTitle: 'Оплата прошла успешно!',
      orderDetailsTitle: 'Информация о заказе',
      needHelp: 'Нужна помощь с заказом?',
      contactSupport: 'Связаться с поддержкой',
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

      // Generate report URL (you'll need to implement this endpoint)
      let pdfUrl = null;
      try {
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);

        // Try to get file path from report data first (for newer reports)
        if (reportData.filePath) {
          const file = bucket.file(reportData.filePath);
          const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
          });
          pdfUrl = url;
        } else {
          // Fallback for older reports - try different naming patterns
          const possiblePaths = [
            `reports/${shopId}/${reportId}.pdf`,
            // Could add more patterns here if needed
          ];

          for (const path of possiblePaths) {
            try {
              const file = bucket.file(path);
              const [exists] = await file.exists();
              if (exists) {
                const [url] = await file.getSignedUrl({
                  action: 'read',
                  expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
                });
                pdfUrl = url;
                break;
              }
            } catch (error) {
              // Continue to next path
              continue;
            }
          }

          // Final fallback - search for files with timestamp
          if (!pdfUrl) {
            try {
              const [files] = await bucket.getFiles({
                prefix: `reports/${shopId}/${reportId}`,
              });

              if (files.length > 0) {
                // Use the most recent file (sort by name which includes timestamp)
                const sortedFiles = files.sort((a, b) => b.name.localeCompare(a.name));
                const [url] = await sortedFiles[0].getSignedUrl({
                  action: 'read',
                  expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
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
      // You might want to handle this more gracefully in production
      }

      // Enhanced HTML email template
      const emailHtml = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f7f8fa;">
          
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f7f8fa;padding:20px 0;">
            <tr>
              <td align="center">
                
                <!-- Main Container -->
                <table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;background-color:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.07);">
                  
                  <!-- Header Section -->
                  <tr>
                    <td style="background:linear-gradient(135deg,#6366F1 0%,#8B5CF6 100%);padding:40px 30px;text-align:center;">
                      <h1 style="margin:0;color:#ffffff;font-size:36px;font-weight:700;letter-spacing:-0.5px;">Nar24</h1>
                      <p style="margin:10px 0 0 0;color:#E9D5FF;font-size:14px;font-weight:500;">${content.businessReports}</p>
                    </td>
                  </tr>
                  
                  <!-- Icon & Message -->
                  <tr>
                    <td style="padding:40px 30px 20px 30px;text-align:center;">
                      <div style="display:inline-block;width:80px;height:80px;background:linear-gradient(135deg,#6366F1 0%,#8B5CF6 100%);border-radius:50%;margin-bottom:20px;">
                        <div style="color:#ffffff;font-size:40px;line-height:80px;">📊</div>
                      </div>
                      <h2 style="margin:0 0 10px 0;color:#1a1a1a;font-size:24px;font-weight:600;">${content.reportReady}</h2>
                      <p style="margin:0;color:#6b7280;font-size:16px;line-height:24px;">${content.greeting} ${displayName}, ${content.message}</p>
                    </td>
                  </tr>
                  
                  <!-- Report Details Card -->
                  <tr>
                    <td style="padding:0 30px 30px 30px;">
                      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:linear-gradient(135deg,#F3F4F6 0%,#F9FAFB 100%);border-radius:12px;border:1px solid #E5E7EB;">
                        <tr>
                          <td style="padding:24px;">
                            
                            <!-- Report Header -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%">
                              <tr>
                                <td style="padding-bottom:20px;border-bottom:1px solid #E5E7EB;">
                                  <h3 style="margin:0 0 8px 0;color:#6366F1;font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">${content.reportDetails}</h3>
                                </td>
                              </tr>
                            </table>
                            
                            <!-- Report Info Grid -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:20px;">
                              <tr>
                                <td width="50%" style="padding-right:10px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.reportName}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">${reportData.reportName || 'Report'}</p>
                                </td>
                                <td width="50%" style="padding-left:10px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.reportId}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">#${reportIdShort}</p>
                                </td>
                              </tr>
                              <tr>
                                <td colspan="2" style="padding-top:16px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.shopName}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">${shopName}</p>
                                </td>
                              </tr>
                              ${dateRangeText ? `
                              <tr>
                                <td colspan="2" style="padding-top:16px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.dateRange}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">${dateRangeText}</p>
                                </td>
                              </tr>
                              ` : ''}
                              <tr>
                                <td colspan="2" style="padding-top:16px;">
                                  <p style="margin:0 0 4px 0;color:#9ca3af;font-size:12px;font-weight:500;text-transform:uppercase;">${content.generatedOn}</p>
                                  <p style="margin:0;color:#1a1a1a;font-size:16px;font-weight:600;">${formattedDate}</p>
                                </td>
                              </tr>
                            </table>
                            
                            <!-- Data Types Included -->
                            <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:20px;padding-top:20px;border-top:1px solid #E5E7EB;">
                              <tr>
                                <td>
                                  <p style="margin:0 0 12px 0;color:#6b7280;font-size:14px;font-weight:500;">${content.includedData}:</p>
                                  <div>
                                    ${reportData.includeProducts ? `
                                      <span style="display:inline-block;margin:4px;padding:6px 12px;background-color:#10B981;color:#ffffff;border-radius:6px;font-size:12px;font-weight:600;">
                                        ${content.products}
                                      </span>
                                    ` : ''}
                                    ${reportData.includeOrders ? `
                                      <span style="display:inline-block;margin:4px;padding:6px 12px;background-color:#F59E0B;color:#ffffff;border-radius:6px;font-size:12px;font-weight:600;">
                                        ${content.orders}
                                      </span>
                                    ` : ''}
                                    ${reportData.includeBoostHistory ? `
                                      <span style="display:inline-block;margin:4px;padding:6px 12px;background-color:#6366F1;color:#ffffff;border-radius:6px;font-size:12px;font-weight:600;">
                                        ${content.boostHistory}
                                      </span>
                                    ` : ''}
                                  </div>
                                </td>
                              </tr>
                            </table>
                            
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Download Button -->
                  <tr>
                    <td style="padding:0 30px 40px 30px;text-align:center;">
                      <a href="${pdfUrl}" style="display:inline-block;padding:16px 40px;background:linear-gradient(135deg,#6366F1 0%,#8B5CF6 100%);color:#ffffff;text-decoration:none;border-radius:10px;font-size:16px;font-weight:600;box-shadow:0 4px 14px 0 rgba(99,102,241,0.35);">
                        📥 ${content.downloadButton}
                      </a>
                      <p style="margin:12px 0 0 0;color:#9ca3af;font-size:12px;">${content.downloadHint}</p>
                    </td>
                  </tr>
                  
                  <!-- Help Section -->
                  <tr>
                    <td style="background-color:#fafbfc;padding:30px;text-align:center;border-top:1px solid #e5e7eb;">
                      <p style="margin:0 0 8px 0;color:#6b7280;font-size:14px;">${content.needHelp}</p>
                      <a href="mailto:support@nar24.com" style="color:#6366F1;text-decoration:none;font-weight:600;font-size:14px;">${content.contactSupport}</a>
                    </td>
                  </tr>
                  
                  <!-- Footer -->
                  <tr>
                    <td style="background-color:#1a1a1a;padding:30px;text-align:center;">
                      <p style="margin:0 0 8px 0;color:#ffffff;font-size:14px;font-weight:500;">${content.footer}</p>
                      <p style="margin:0 0 16px 0;color:#9ca3af;font-size:12px;">© 2024 Nar24. ${content.rights}</p>
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
          subject: `📊 ${content.subject}: ${reportData.reportName || 'Report'} - Nar24`,
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

export const shopWelcomeEmail = onCall(
  {region: 'europe-west3'},
  async (request) => {
    const {shopId, email} = request.data;
    const context = request.auth;

    // Check if user is authenticated (admin calling this)
    if (!context || !context.uid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    // Validate input
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
      const shopName = shopData.name || 'Mağazanız';
      const ownerName = shopData.ownerName || 'Değerli Satıcı';

      // Get signed URLs for email images
      const bucket = admin.storage().bucket();
      const imageUrls = {};
      
      const images = [
        'shopwelcome.png',
        'shopproducts.png',
        'shopboost.png',
      ];

      try {
        for (const image of images) {
          const file = bucket.file(`functions/shop-email-icons/${image}`);
          const [exists] = await file.exists();
          
          if (exists) {
            const [url] = await file.getSignedUrl({
              action: 'read',
              expires: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
            });
            imageUrls[image.replace('.png', '')] = url;
          }
        }
      } catch (error) {
        console.error('Error loading email images:', error);
        // Continue without images if they fail to load
      }

      // Enhanced HTML email template for shop welcome
      const emailHtml = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background-color:#f7f8fa;">
          
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f7f8fa;padding:20px 0;">
            <tr>
              <td align="center">
                
                <!-- Main Container -->
                <table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;background-color:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.07);">
                  
                  <!-- Header Section with Gradient -->
                  <tr>
                    <td style="background:linear-gradient(135deg,#6366F1 0%,#8B5CF6 100%);padding:40px 30px;text-align:center;">
                      <h1 style="margin:0;color:#ffffff;font-size:36px;font-weight:700;letter-spacing:-0.5px;">Nar24</h1>
                      <p style="margin:10px 0 0 0;color:#E9D5FF;font-size:14px;font-weight:500;">Premium Alışveriş Platformu</p>
                    </td>
                  </tr>
                  
                  <!-- Celebration Icon & Main Title -->
                  <tr>
                    <td style="padding:40px 30px 30px 30px;text-align:center;">
                      ${imageUrls.shopwelcome ? `
                        <img src="${imageUrls.shopwelcome}" alt="Hoş Geldiniz" style="width:120px;height:120px;margin-bottom:24px;display:block;margin-left:auto;margin-right:auto;" />
                      ` : `
                        <div style="display:inline-block;width:100px;height:100px;background:linear-gradient(135deg,#10B981 0%,#059669 100%);border-radius:50%;margin-bottom:24px;">
                          <div style="color:#ffffff;font-size:50px;line-height:100px;">🎉</div>
                        </div>
                      `}
                      <h2 style="margin:0 0 16px 0;color:#1a1a1a;font-size:28px;font-weight:700;line-height:1.3;">
                        Tebrikler, Nar24'te Yetkili Satıcı Oldunuz! 🎉
                      </h2>
                      <p style="margin:0;color:#6b7280;font-size:16px;line-height:24px;">
                        Merhaba <strong style="color:#6366F1;">${ownerName}</strong>,<br/>
                        <strong style="color:#1a1a1a;">${shopName}</strong> mağazanız başarıyla onaylandı ve artık satışa hazırsınız!
                      </p>
                    </td>
                  </tr>
                  
                  <!-- Features Section -->
                  <tr>
                    <td style="padding:0 30px 40px 30px;">
                      
                      <!-- Feature 1: Upload Products -->
                      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:linear-gradient(135deg,#F0F9FF 0%,#E0F2FE 100%);border-radius:12px;margin-bottom:16px;border:1px solid #BAE6FD;">
                        <tr>
                          <td style="padding:24px;">
                            <table cellpadding="0" cellspacing="0" border="0" width="100%">
                              <tr>
                                <td width="80" valign="top">
                                  ${imageUrls.shopproducts ? `
                                    <img src="${imageUrls.shopproducts}" alt="Ürün Yükleme" style="width:64px;height:64px;border-radius:12px;" />
                                  ` : `
                                    <div style="width:64px;height:64px;background:linear-gradient(135deg,#0EA5E9 0%,#0284C7 100%);border-radius:12px;text-align:center;line-height:64px;font-size:32px;">
                                      📦
                                    </div>
                                  `}
                                </td>
                                <td style="padding-left:16px;">
                                  <h3 style="margin:0 0 8px 0;color:#0369A1;font-size:18px;font-weight:600;">
                                    Ürünlerinizi Kolaylıkla Yükleyin
                                  </h3>
                                  <p style="margin:0;color:#475569;font-size:14px;line-height:20px;">
                                    Ürünlerinizi kolaylıkla yükleyip hemen satışa sunabilirsiniz! Gelişmiş panelimiz ile dakikalar içinde ürünlerinizi yükleyin.
                                  </p>
                                </td>
                              </tr>
                            </table>
                          </td>
                        </tr>
                      </table>
                      
                      <!-- Feature 2: Boost Products -->
                      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:linear-gradient(135deg,#FEF3C7 0%,#FDE68A 100%);border-radius:12px;border:1px solid #FCD34D;">
                        <tr>
                          <td style="padding:24px;">
                            <table cellpadding="0" cellspacing="0" border="0" width="100%">
                              <tr>
                                <td width="80" valign="top">
                                  ${imageUrls.shopboost ? `
                                    <img src="${imageUrls.shopboost}" alt="Ürün Boost" style="width:64px;height:64px;border-radius:12px;" />
                                  ` : `
                                    <div style="width:64px;height:64px;background:linear-gradient(135deg,#F59E0B 0%,#D97706 100%);border-radius:12px;text-align:center;line-height:64px;font-size:32px;">
                                      🚀
                                    </div>
                                  `}
                                </td>
                                <td style="padding-left:16px;">
                                  <h3 style="margin:0 0 8px 0;color:#B45309;font-size:18px;font-weight:600;">
                                    Ürünlerinizi Öne Çıkarın
                                  </h3>
                                  <p style="margin:0;color:#78350F;font-size:14px;line-height:20px;">
                                    Dilediğiniz ürünlerinizi öne çıkarıp daha geniş kitlelere ulaşabilirsiniz. Boost özelliği ile satışlarınızı artırın!
                                  </p>
                                </td>
                              </tr>
                            </table>
                          </td>
                        </tr>
                      </table>
                      
                    </td>
                  </tr>
                  
                  <!-- Call to Action Button -->
                  <tr>
                    <td style="padding:0 30px 40px 30px;text-align:center;">
                      <a href="https://www.nar24panel.com/" style="display:inline-block;padding:18px 48px;background:linear-gradient(135deg,#6366F1 0%,#8B5CF6 100%);color:#ffffff;text-decoration:none;border-radius:12px;font-size:18px;font-weight:600;box-shadow:0 4px 14px 0 rgba(99,102,241,0.4);transition:all 0.3s ease;">
                        🏪 Mağaza Paneline Git
                      </a>
                      <p style="margin:16px 0 0 0;color:#9ca3af;font-size:13px;line-height:20px;">
                        Hemen başlayın ve binlerce müşteriye ulaşın!
                      </p>
                    </td>
                  </tr>
                  
                  <!-- Quick Start Tips -->
                  <tr>
                    <td style="background-color:#fafbfc;padding:30px;border-top:1px solid #e5e7eb;">
                      <h3 style="margin:0 0 16px 0;color:#1a1a1a;font-size:16px;font-weight:600;text-align:center;">
                        💡 Hızlı Başlangıç İpuçları
                      </h3>
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td style="padding:8px 0;">
                            <span style="display:inline-block;width:24px;height:24px;background-color:#10B981;color:#ffffff;border-radius:50%;text-align:center;line-height:24px;font-size:12px;font-weight:600;margin-right:8px;">1</span>
                            <span style="color:#4b5563;font-size:14px;">İlk ürünlerinizi ekleyin ve detaylı açıklamalar yazın</span>
                          </td>
                        </tr>
                        <tr>
                          <td style="padding:8px 0;">
                            <span style="display:inline-block;width:24px;height:24px;background-color:#F59E0B;color:#ffffff;border-radius:50%;text-align:center;line-height:24px;font-size:12px;font-weight:600;margin-right:8px;">2</span>
                            <span style="color:#4b5563;font-size:14px;">Kaliteli fotoğraflar kullanarak ürünlerinizi sergileyin</span>
                          </td>
                        </tr>
                        <tr>
                          <td style="padding:8px 0;">
                            <span style="display:inline-block;width:24px;height:24px;background-color:#6366F1;color:#ffffff;border-radius:50%;text-align:center;line-height:24px;font-size:12px;font-weight:600;margin-right:8px;">3</span>
                            <span style="color:#4b5563;font-size:14px;">Popüler ürünlerinizi boost ederek öne çıkarın</span>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  
                  <!-- Help Section -->
                  <tr>
                    <td style="background-color:#fafbfc;padding:20px 30px;text-align:center;border-top:1px solid #e5e7eb;">
                      <p style="margin:0 0 8px 0;color:#6b7280;font-size:14px;">Yardıma mı ihtiyacınız var?</p>
                      <a href="mailto:support@nar24.com" style="color:#6366F1;text-decoration:none;font-weight:600;font-size:14px;">Destek Ekibimizle İletişime Geçin</a>
                    </td>
                  </tr>
                  
                  <!-- Footer -->
                  <tr>
                    <td style="background-color:#1a1a1a;padding:30px;text-align:center;">
                      <p style="margin:0 0 8px 0;color:#ffffff;font-size:14px;font-weight:500;">Nar24'te satıcı olduğunuz için teşekkür ederiz! 🙏</p>
                      <p style="margin:0 0 16px 0;color:#9ca3af;font-size:12px;">Başarılı satışlar dileriz!</p>
                      <p style="margin:0;color:#6b7280;font-size:11px;">© 2024 Nar24. Tüm hakları saklıdır.</p>
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
          subject: '🎉 Tebrikler! Nar24\'te Yetkili Satıcı Oldunuz - Mağazanız Onaylandı',
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

      // Send email via SendGrid extension
      await admin.firestore().collection('mail').add(mailDoc);

      // Update shop document to mark welcome email as sent
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

function getReportLocalizedContent(languageCode) {
  const content = {
    en: {
      greeting: 'Hello',
      message: 'your shop report is ready for download!',
      reportName: 'Report Name',
      reportId: 'Report ID',
      shopName: 'Shop',
      dateRange: 'Date Range',
      generatedOn: 'Generated On',
      includedData: 'Included Data',
      products: 'Products',
      orders: 'Orders',
      boostHistory: 'Boost History',
      subject: 'Your Shop Report',
      downloadButton: 'Download Report PDF',
      downloadHint: 'Click to download your detailed shop report',
      footer: 'Thank you for using Nar24 Business Tools!',
      rights: 'All rights reserved.',
      businessReports: 'Business Intelligence Reports',
      reportReady: 'Your Report is Ready!',
      reportDetails: 'Report Information',
      needHelp: 'Need help understanding your report?',
      contactSupport: 'Contact Support',
    },
    tr: {
      greeting: 'Merhaba',
      message: 'mağaza raporunuz indirilmeye hazır!',
      reportName: 'Rapor Adı',
      reportId: 'Rapor No',
      shopName: 'Mağaza',
      dateRange: 'Tarih Aralığı',
      generatedOn: 'Oluşturulma Tarihi',
      includedData: 'İçerilen Veriler',
      products: 'Ürünler',
      orders: 'Siparişler',
      boostHistory: 'Boost Geçmişi',
      subject: 'Mağaza Raporunuz',
      downloadButton: 'Raporu PDF Olarak İndir',
      downloadHint: 'Detaylı mağaza raporunuzu indirmek için tıklayın',
      footer: 'Nar24 İşletme Araçlarını kullandığınız için teşekkür ederiz!',
      rights: 'Tüm hakları saklıdır.',
      businessReports: 'İş Zekası Raporları',
      reportReady: 'Raporunuz Hazır!',
      reportDetails: 'Rapor Bilgileri',
      needHelp: 'Raporunuzu anlamak için yardıma mı ihtiyacınız var?',
      contactSupport: 'Destek ile İletişime Geç',
    },
    ru: {
      greeting: 'Здравствуйте',
      message: 'ваш отчет магазина готов к загрузке!',
      reportName: 'Название отчета',
      reportId: 'Номер отчета',
      shopName: 'Магазин',
      dateRange: 'Период',
      generatedOn: 'Дата создания',
      includedData: 'Включенные данные',
      products: 'Товары',
      orders: 'Заказы',
      boostHistory: 'История продвижения',
      subject: 'Ваш отчет магазина',
      downloadButton: 'Скачать отчет в PDF',
      downloadHint: 'Нажмите, чтобы скачать подробный отчет магазина',
      footer: 'Спасибо за использование бизнес-инструментов Nar24!',
      rights: 'Все права защищены.',
      businessReports: 'Бизнес-аналитика',
      reportReady: 'Ваш отчет готов!',
      reportDetails: 'Информация об отчете',
      needHelp: 'Нужна помощь в понимании отчета?',
      contactSupport: 'Связаться с поддержкой',
    },
  };

  return content[languageCode] || content.en;
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

// Helper function to process a batch of items
async function processBatchBoost(db, batchItems, userId, boostDuration, isAdmin) {
  const validatedItems = [];
  const failedItems = [];

  await db.runTransaction(async (transaction) => {
    const now = new Date();
    const boostEndDate = new Date(now.getTime() + (boostDuration * 60 * 1000));
    const boostStartTimestamp = admin.firestore.Timestamp.fromDate(now);
    const boostEndTimestamp = admin.firestore.Timestamp.fromDate(boostEndDate);

    const shopMembershipCache = new Map();
    const basePricePerProduct = 1.0;

    // PHASE 1: ALL READS - Fetch and validate all products and related data
    const itemsData = [];
    const userVerificationCache = new Map();

    for (const item of batchItems) {
      try {
        const {itemId, collection, shopId: itemShopId} = item;

        // Get product document
        const productRef = db.collection(collection).doc(itemId);
        const productSnap = await transaction.get(productRef);

        if (!productSnap.exists) {
          console.warn(`Product ${itemId} not found in ${collection}`);
          failedItems.push({...item, error: 'Product not found'});
          continue;
        }

        const productData = productSnap.data();

        // Permission validation
        let hasPermission = false;

        if (collection === 'products') {
          hasPermission = productData.userId === userId || isAdmin;
        } else if (collection === 'shop_products') {
          const targetShopId = itemShopId || productData.shopId;

          if (!targetShopId) {
            console.warn(`Shop product ${itemId} missing shopId`);
            failedItems.push({...item, error: 'Missing shopId'});
            continue;
          }

          if (isAdmin) {
            hasPermission = true;
          } else {
            if (shopMembershipCache.has(targetShopId)) {
              hasPermission = shopMembershipCache.get(targetShopId);
            } else {
              const shopRef = db.collection('shops').doc(targetShopId);
              const shopSnap = await transaction.get(shopRef);

              if (shopSnap.exists) {
                const shopData = shopSnap.data();
                hasPermission = shopData.ownerId === userId ||
                    (shopData.editors && shopData.editors.includes(userId)) ||
                    (shopData.coOwners && shopData.coOwners.includes(userId)) ||
                    (shopData.viewers && shopData.viewers.includes(userId));

                shopMembershipCache.set(targetShopId, hasPermission);
              }
            }
          }
        }

        if (!hasPermission) {
          console.warn(`User ${userId} lacks permission for ${collection}/${itemId}`);
          failedItems.push({...item, error: 'Insufficient permissions'});
          continue;
        }

        // Check if product is already boosted
        if (productData.isBoosted && productData.boostEndTime && productData.boostEndTime.toDate() > now) {
          console.warn(`Product ${itemId} is already boosted until ${productData.boostEndTime.toDate()}`);
          failedItems.push({...item, error: 'Already boosted'});
          continue;
        }

        // Get user verification status (do this in the read phase)
        const ownerUserId = productData.userId || userId;
        let isVerified = false;

        if (userVerificationCache.has(ownerUserId)) {
          isVerified = userVerificationCache.get(ownerUserId);
        } else {
          try {
            const ownerRef = db.collection('users').doc(ownerUserId);
            const ownerSnap = await transaction.get(ownerRef);
            if (ownerSnap.exists) {
              isVerified = ownerSnap.data().verified || false;
            }
            userVerificationCache.set(ownerUserId, isVerified);
          } catch (error) {
            console.warn(`Could not fetch user verification status: ${error.message}`);
            isVerified = false;
            userVerificationCache.set(ownerUserId, false);
          }
        }

        // Store all data needed for the write phase
        itemsData.push({
          item,
          productRef,
          productData,
          isVerified,
          targetShopId: itemShopId || productData.shopId,
        });
      } catch (itemError) {
        console.error(`Error processing item ${item.itemId}:`, itemError);
        failedItems.push({...item, error: itemError.message});
      }
    }

    // PHASE 2: ALL WRITES - Now perform all the updates
    for (const itemData of itemsData) {
      const {item, productRef, productData, isVerified, targetShopId} = itemData;
      const {itemId, collection} = item;

      const currentImpressions = productData.boostedImpressionCount || 0;
      const currentClicks = productData.clickCount || 0;
      const boostScreen = isVerified ? 'shop_product' : 'product';
      const screenType = isVerified ? 'shop_product' : 'product';

      // Generate unique task name
      const taskName = `expire-boost-${collection}-${itemId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

      // Update product
      const updateData = {
        boostStartTime: boostStartTimestamp,
        boostEndTime: boostEndTimestamp,
        boostDuration: boostDuration,
        isBoosted: true,
        boostImpressionCountAtStart: currentImpressions,
        boostClickCountAtStart: currentClicks,
        boostScreen: boostScreen,
        screenType: screenType,
        boostExpirationTaskName: taskName,
        promotionScore: (productData.rankingScore || 0) + 1000,
        lastRankingUpdate: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.update(productRef, updateData);

      // Create boost history
      const itemName = productData.productName || 'Unnamed Product';
      const historyData = {
        userId: userId,
        itemId: itemId,
        itemType: collection === 'shop_products' ? 'shop_product' : 'product',
        itemName: itemName,
        boostStartTime: boostStartTimestamp,
        boostEndTime: boostEndTimestamp,
        boostDuration: boostDuration,
        pricePerMinutePerItem: basePricePerProduct,
        boostPrice: boostDuration * basePricePerProduct,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        boostImpressionCountAtStart: currentImpressions,
        boostClickCountAtStart: currentClicks,
        finalImpressions: 0,
        finalClicks: 0,
        totalImpressionCount: 0,
        totalClickCount: 0,
        demographics: {},
        viewerAgeGroups: {},
      };

      if (collection === 'shop_products' && targetShopId) {
        const historyRef = db.collection('shops')
          .doc(targetShopId)
          .collection('boostHistory')
          .doc();
        transaction.set(historyRef, historyData);
      } else {
        const historyRef = db.collection('users')
          .doc(userId)
          .collection('boostHistory')
          .doc();
        transaction.set(historyRef, historyData);
      }

      validatedItems.push({
        itemId,
        collection,
        shopId: targetShopId,
        productData: productData,
        currentImpressions,
        currentClicks,
        boostScreen,
        boostEndDate,
        taskName,
      });
    }
  });

  return {validatedItems, failedItems};
}

// Helper function to schedule expiration tasks with retry logic
async function scheduleExpirationTasks(validatedItems, userId) {
  const projectId = process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'emlak-mobile-app';
  const location = 'europe-west3';
  const queue = 'boost-expiration-queue';

  console.log(`Scheduling tasks with projectId: ${projectId}, location: ${location}, queue: ${queue}`);

  const scheduledTasks = [];
  const failedSchedules = [];

  // Process task scheduling in parallel batches
  const PARALLEL_LIMIT = 5;

  for (let i = 0; i < validatedItems.length; i += PARALLEL_LIMIT) {
    const batch = validatedItems.slice(i, i + PARALLEL_LIMIT);

    const batchPromises = batch.map(async (item) => {
      try {
        const taskName = item.taskName;

        if (!projectId || !location || !queue) {
          throw new Error(`Missing required parameters: projectId=${projectId}, location=${location}, queue=${queue}`);
        }

        const parent = tasksClient.queuePath(projectId, location, queue);

        const boostEndTimeUTC = new Date(item.boostEndDate.getTime());
        console.log(`Scheduling task for ${item.itemId} to expire at: ${boostEndTimeUTC.toISOString()}`);

        const payload = {
          itemId: item.itemId,
          collection: item.collection,
          shopId: item.shopId,
          userId: userId,
          boostEndTime: boostEndTimeUTC.toISOString(),
          taskName: taskName,
          scheduledAt: new Date().toISOString(),
        };

        // Schedule 10 seconds before actual expiry
        const scheduleTimeBuffer = 10 * 1000;
        const effectiveScheduleTime = new Date(boostEndTimeUTC.getTime() - scheduleTimeBuffer);

        const task = {
          name: tasksClient.taskPath(projectId, location, queue, taskName),
          httpRequest: {
            httpMethod: 'POST',
            url: `https://${location}-${projectId}.cloudfunctions.net/expireSingleBoost`,
            headers: {
              'Content-Type': 'application/json',
            },
            body: Buffer.from(JSON.stringify(payload)),
            // ✅ Add OIDC authentication
            oidcToken: {
              serviceAccountEmail: `${projectId}@appspot.gserviceaccount.com`,
            },
          },
          scheduleTime: {
            seconds: Math.floor(effectiveScheduleTime.getTime() / 1000),
          },
        };

        const [response] = await tasksClient.createTask({parent, task});
        console.log(`✅ Scheduled boost expiration task: ${response.name}`);

        scheduledTasks.push({
          taskName: response.name,
          itemId: item.itemId,
          scheduledFor: effectiveScheduleTime.toISOString(),
          boostExpiresAt: boostEndTimeUTC.toISOString(),
        });
      } catch (taskError) {
        console.error(`❌ Failed to schedule expiration for ${item.itemId}:`, taskError);
        failedSchedules.push({
          itemId: item.itemId,
          error: taskError.message,
        });
      }
    });

    await Promise.all(batchPromises);
  }

  if (failedSchedules.length > 0) {
    console.warn(`Failed to schedule ${failedSchedules.length} tasks:`, failedSchedules);
  }

  return scheduledTasks;
}

// expireSingleBoost function remains unchanged
export const expireSingleBoost = onRequest(
  {
    region: 'europe-west3',
    invoker: 'private',
  },
  async (req, res) => {
    try {
      const {itemId, collection, shopId, userId, boostEndTime, taskName} = req.body;

      if (!itemId || !collection) {
        res.status(400).json({error: 'Missing required parameters'});
        return;
      }

      const db = admin.firestore();
      const now = new Date();
      const scheduledEndTime = new Date(boostEndTime);

      // ROBUST TIME COMPARISON WITH TOLERANCE
      const EXECUTION_TOLERANCE_MS = 30 * 1000; // 30 seconds
      const tolerantEndTime = new Date(scheduledEndTime.getTime() - EXECUTION_TOLERANCE_MS);

      console.log(`Expiration check for ${itemId}:`);
      console.log(`  Current time: ${now.toISOString()}`);
      console.log(`  Scheduled end time: ${scheduledEndTime.toISOString()}`);
      console.log(`  Tolerant end time: ${tolerantEndTime.toISOString()}`);
      console.log(`  Time difference: ${now.getTime() - scheduledEndTime.getTime()}ms`);

      if (now < tolerantEndTime) {
        const timeDiff = tolerantEndTime.getTime() - now.getTime();
        console.log(`Boost for ${itemId} too early to expire by ${timeDiff}ms, skipping`);
        res.status(200).json({
          message: 'Boost not yet expired',
          timeDifference: timeDiff,
          scheduledTime: scheduledEndTime.toISOString(),
          currentTime: now.toISOString(),
        });
        return;
      }

      const productRef = db.collection(collection).doc(itemId);
      const productSnap = await productRef.get();

      if (!productSnap.exists) {
        console.warn(`Product ${itemId} not found during expiration`);
        res.status(404).json({error: 'Product not found'});
        return;
      }

      const data = productSnap.data();

      if (data.boostExpirationTaskName && data.boostExpirationTaskName !== taskName) {
        console.warn(`Stale task for ${itemId}, skipping`);
        res.status(200).json({message: 'Stale task', skipped: true});
        return;
      }

      if (!data.isBoosted) {
        console.log(`Boost for ${itemId} already marked as not boosted`);
        res.status(200).json({message: 'Boost already expired or not active'});
        return;
      }

      if (data.boostEndTime) {
        const dbBoostEndTime = data.boostEndTime.toDate();
        console.log(`Database boost end time: ${dbBoostEndTime.toISOString()}`);

        if (dbBoostEndTime.getTime() - now.getTime() > 60000) {
          console.log(`Database boost end time is too far in future, skipping`);
          res.status(200).json({
            message: 'Boost end time too far in future',
            dbEndTime: dbBoostEndTime.toISOString(),
            currentTime: now.toISOString(),
          });
          return;
        }
      }

      console.log(`Proceeding with boost expiration for ${itemId}`);

      const ops = [];
      const productName = data.productName || 'Product';
      const actualUserId = data.userId || userId;
      const actualShopId = collection === 'shop_products' ? (data.shopId || shopId) : null;

      // Update boost history
      if (data.boostStartTime) {
        const historyCol = collection === 'products' ?
          db.collection('users').doc(actualUserId).collection('boostHistory') :
          db.collection('shops').doc(actualShopId).collection('boostHistory');

        const historySnap = await historyCol
          .where('itemId', '==', itemId)
          .where('boostStartTime', '==', data.boostStartTime)
          .limit(1)
          .get();

        if (!historySnap.empty) {
          const bhRef = historySnap.docs[0].ref;
          const impressionsDuringBoost = (data.boostedImpressionCount || 0) - (data.boostImpressionCountAtStart || 0);
          const clicksDuringBoost = (data.clickCount || 0) - (data.boostClickCountAtStart || 0);

          ops.push({
            type: 'update',
            ref: bhRef,
            data: {
              impressionsDuringBoost,
              clicksDuringBoost,
              totalImpressionCount: data.boostedImpressionCount || 0,
              totalClickCount: data.clickCount || 0,
              finalImpressions: data.boostImpressionCountAtStart || 0,
              finalClicks: data.boostClickCountAtStart || 0,
              itemName: data.productName || 'Unnamed Product',
              productImage: (data.imageUrls && data.imageUrls.length > 0) ? data.imageUrls[0] : null,
              averageRating: data.averageRating || 0,
              price: data.price || 0,
              currency: data.currency || 'TL',
              actualExpirationTime: admin.firestore.FieldValue.serverTimestamp(),
            },
          });
        }
      }

      // Create notifications
      if (collection === 'shop_products' && actualShopId) {
        const shopSnap = await db.collection('shops').doc(actualShopId).get();
        if (shopSnap.exists) {
          const shop = shopSnap.data();
          const members = new Set([shop.ownerId, ...(shop.coOwners||[]), ...(shop.editors||[]), ...(shop.viewers||[])]);
          for (const memberId of members) {
            ops.push({
              type: 'set',
              ref: db.collection('users')
                .doc(memberId)
                .collection('notifications')
                .doc(),
              data: {
                userId: memberId,
                type: 'boost_expired',
                message_en: `${productName} boost has expired.`,
                message_tr: `${productName} boost süresi doldu.`,
                message_ru: `У объявления ${productName} закончился буст.`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
                productId: itemId,
                itemType: 'shop_product',
                shopId: actualShopId,
              },
            });
          }
        }
      } else if (collection === 'products' && actualUserId) {
        ops.push({
          type: 'set',
          ref: db.collection('users')
            .doc(actualUserId)
            .collection('notifications')
            .doc(),
          data: {
            userId: actualUserId,
            type: 'boost_expired',
            message_en: `${productName} boost has expired.`,
            message_tr: `${productName} boost süresi doldu.`,
            message_ru: `У объявления ${productName} закончился буст.`,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
            productId: itemId,
            itemType: 'product',
          },
        });
      }

      // Expire the boost
      ops.push({
        type: 'update',
        ref: productRef,
        data: {
          isBoosted: false,
          boostStartTime: admin.firestore.FieldValue.delete(),
          boostEndTime: admin.firestore.FieldValue.delete(),
          boostExpirationTaskName: admin.firestore.FieldValue.delete(),
          lastBoostExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
          promotionScore: Math.max((data.promotionScore || 0) - 1000, 0),
        },
      });

      // Commit in batches
      const BATCH_SIZE = 500;
      for (let i = 0; i < ops.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = ops.slice(i, i + BATCH_SIZE);
        chunk.forEach((op) => {
          if (op.type === 'update') batch.update(op.ref, op.data);
          else batch.set(op.ref, op.data);
        });
        await batch.commit();
      }

      console.log(`Successfully expired boost for ${itemId} in ${Math.ceil(ops.length / BATCH_SIZE)} batch(es).`);

      res.status(200).json({
        success: true,
        message: `Boost expired for ${itemId}`,
        operationsCount: ops.length,
        executionTime: now.toISOString(),
        scheduledTime: scheduledEndTime.toISOString(),
      });
    } catch (error) {
      console.error('Error expiring single boost:', error);
      res.status(500).json({
        error: 'Failed to expire boost',
        details: error.message,
        timestamp: new Date().toISOString(),
      });
    }
  },
);

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

export const handleShopInvitation = functions.https.onCall({
  region: 'europe-west3',
  maxInstances: 10,
}, async (request) => {
  // Validate authentication
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated',
    );
  }

  const {notificationId, accepted, shopId, role} = request.data;
  const userId = request.auth.uid;

  // Validate required parameters
  if (!notificationId || accepted === undefined || !shopId || !role) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing required parameters',
    );
  }

  // Validate role
  const validRoles = ['co-owner', 'editor', 'viewer'];
  if (!validRoles.includes(role)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid role specified',
    );
  }

  const batch = admin.firestore().batch();

  try {
    // 1. Update notification status
    const notificationRef = admin.firestore()
      .collection('users')
      .doc(userId)
      .collection('notifications')
      .doc(notificationId);

    batch.update(notificationRef, {
      status: accepted ? 'accepted' : 'rejected',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (accepted) {
      // 2. Check if shop exists
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
      if (!shopDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Shop not found',
        );
      }

      // 3. Add user to shop
      const shopRef = admin.firestore().collection('shops').doc(shopId);
      const roleField = `${role.replace('-', '')}s`; // co-owners -> coOwners, editors, viewers

      batch.update(shopRef, {
        [roleField]: admin.firestore.FieldValue.arrayUnion(userId),
      });

      // 4. Add shop to user's memberOfShops
      const userRef = admin.firestore().collection('users').doc(userId);
      batch.set(userRef, {
        memberOfShops: {
          [shopId]: role,
        },
      }, {merge: true});

      // 5. Update invitation document if exists
      const invitationQuery = await admin.firestore()
        .collection('shopInvitations')
        .where('shopId', '==', shopId)
        .where('userId', '==', userId)
        .where('status', '==', 'pending')
        .limit(1)
        .get();

      if (!invitationQuery.empty) {
        batch.update(invitationQuery.docs[0].ref, {
          status: 'accepted',
          acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else {
      // If rejected, just update invitation document
      const invitationQuery = await admin.firestore()
        .collection('shopInvitations')
        .where('shopId', '==', shopId)
        .where('userId', '==', userId)
        .where('status', '==', 'pending')
        .limit(1)
        .get();

      if (!invitationQuery.empty) {
        batch.update(invitationQuery.docs[0].ref, {
          status: 'rejected',
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    // Commit all changes
    await batch.commit();

    return {
      success: true,
      accepted,
      shopId,
      message: accepted ? 'Invitation accepted successfully' : 'Invitation rejected',
    };
  } catch (error) {
    console.error('Error handling shop invitation:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to process invitation',
      error.message,
    );
  }
});

export const revokeShopAccess = functions.https.onCall({
  region: 'europe-west3',
  maxInstances: 10,
}, async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const {targetUserId, shopId, role} = request.data;
  const requesterId = request.auth.uid;

  // Validate parameters
  if (!targetUserId || !shopId || !role) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters');
  }

  const batch = admin.firestore().batch();

  try {
    // Verify requester has permission (owner or co-owner)
    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Shop not found');
    }

    const shopData = shopDoc.data();
    const isOwner = shopData.ownerId === requesterId;
    const isCoOwner = (shopData.coOwners || []).includes(requesterId);

    if (!isOwner && !isCoOwner) {
      throw new functions.https.HttpsError('permission-denied', 'No permission to revoke access');
    }

    // Cannot remove the owner
    if (role === 'owner' && targetUserId === shopData.ownerId) {
      throw new functions.https.HttpsError('invalid-argument', 'Cannot remove shop owner');
    }

    // Remove from shop arrays
    const shopRef = admin.firestore().collection('shops').doc(shopId);
    const roleField = role === 'co-owner' ? 'coOwners' : `${role}s`;
    batch.update(shopRef, {
      [roleField]: admin.firestore.FieldValue.arrayRemove(targetUserId),
    });

    // Remove from user's memberOfShops
    const userDoc = await admin.firestore().collection('users').doc(targetUserId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      const memberOfShops = userData.memberOfShops || {};

      if (memberOfShops[shopId]) {
        delete memberOfShops[shopId];

        const userRef = admin.firestore().collection('users').doc(targetUserId);
        if (Object.keys(memberOfShops).length === 0) {
          batch.update(userRef, {
            memberOfShops: admin.firestore.FieldValue.delete(),
          });
        } else {
          batch.update(userRef, {
            memberOfShops: memberOfShops,
          });
        }
      }
    }

    await batch.commit();

    return {
      success: true,
      message: 'Access revoked successfully',
    };
  } catch (error) {
    console.error('Error revoking access:', error);
    throw new functions.https.HttpsError('internal', 'Failed to revoke access', error.message);
  }
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

        // ========== ADD THIS CHECK HERE ==========
    // Prevent users from unarchiving products archived by admin
    if (!pauseStatus && productData.archivedByAdmin === true) {
      throw new HttpsError(
        'permission-denied',
        'Bu ürün bir yönetici tarafından arşivlenmiştir. Daha fazla bilgi için destek ile iletişime geçin.',
      );
    }
    // =========================================


    // Verify product belongs to the specified shop
    if (productData.shopId !== shopId) {
      throw new HttpsError(
        'permission-denied',
        'Product does not belong to the specified shop',
      );
    }

    // Use a batch to ensure atomicity for the main document
    const batch = admin.firestore().batch();

    // Add product to destination collection with updated metadata
    batch.set(destRef, {
      ...productData,
      paused: pauseStatus,
      lastModified: FieldValue.serverTimestamp(),
      modifiedBy: userId,
    });

    // Delete product from source collection
    batch.delete(sourceRef);

    // Commit the batch for the main document
    await batch.commit();

    // Handle subcollections if they exist
    // Define which subcollections your products might have
    const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences']; // Add your actual subcollection names

    for (const subcollectionName of subcollectionsToMove) {
      try {
        const sourceSubcollection = sourceRef.collection(subcollectionName);
        const destSubcollection = destRef.collection(subcollectionName);

        const snapshot = await sourceSubcollection.get();

        if (!snapshot.empty) {
          // Process in batches of 500 (Firestore limit)
          const batchSize = 500;
          let currentBatch = admin.firestore().batch();
          let operationCount = 0;

          for (const doc of snapshot.docs) {
            // Copy to destination
            currentBatch.set(destSubcollection.doc(doc.id), doc.data());
            // Delete from source
            currentBatch.delete(doc.ref);
            operationCount += 2;

            if (operationCount >= batchSize) {
              await currentBatch.commit();
              currentBatch = admin.firestore().batch();
              operationCount = 0;
            }
          }

          // Commit any remaining operations
          if (operationCount > 0) {
            await currentBatch.commit();
          }
        }
      } catch (subcollectionError) {
        console.log(`No ${subcollectionName} subcollection or error moving it:`, subcollectionError);
        // Continue with other subcollections even if one fails
      }
    }

    return {
      success: true,
      productId: productId,
      paused: pauseStatus,
    };
  } catch (error) {
    console.error('Error toggling product pause status:', error);

    // Re-throw HttpsErrors as-is
    if (error instanceof HttpsError) {
      throw error;
    }

    // Convert other errors to HttpsError
    throw new HttpsError(
      'internal',
      'Failed to update product status. Please try again.',
    );
  }
});

async function executeBoostLogic(db, userId, items, boostDuration, isAdmin) {
  const BATCH_SIZE = 10;
  const allValidatedItems = [];
  const failedItems = [];

  for (let i = 0; i < items.length; i += BATCH_SIZE) {
    const batchItems = items.slice(i, i + BATCH_SIZE);

    try {
      const batchResult = await processBatchBoost(db, batchItems, userId, boostDuration, isAdmin);
      allValidatedItems.push(...batchResult.validatedItems);
      failedItems.push(...batchResult.failedItems);
    } catch (batchError) {
      console.error(`Batch ${i/BATCH_SIZE + 1} failed:`, batchError);
      failedItems.push(...batchItems.map((item) => ({
        ...item,
        error: batchError.message,
      })));
    }
  }

  if (allValidatedItems.length === 0) {
    throw new Error('No valid items found to boost. Check permissions and item validity.');
  }

  const scheduledTasks = await scheduleExpirationTasks(allValidatedItems, userId);
  const totalPrice = allValidatedItems.length * boostDuration * 1.0;

  return {
    boostedItemsCount: allValidatedItems.length,
    totalRequestedItems: items.length,
    failedItemsCount: failedItems.length,
    boostDuration: boostDuration,
    boostStartTime: admin.firestore.Timestamp.fromDate(new Date()),
    boostEndTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + (boostDuration * 60 * 1000))),
    totalPrice: totalPrice,
    pricePerItem: boostDuration * 1.0,
    boostedItems: allValidatedItems.map((item) => ({
      itemId: item.itemId,
      collection: item.collection,
      shopId: item.shopId,
    })),
    failedItems: failedItems.length > 0 ? failedItems : undefined,
    scheduledTasks: scheduledTasks,
  };
}

// 2. INITIALIZE PAYMENT (your existing code - no changes needed)
export const initializeBoostPayment = onCall(
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

      const {items, boostDuration, isShopContext, shopId, customerName, customerEmail, customerPhone} = request.data;

      const sanitizedCustomerName = (() => {
        if (!customerName) return 'Customer';

        const sanitized = transliterate(customerName)
          .replace(/[^a-zA-Z0-9\s]/g, '')
          .trim()
          .substring(0, 50);

        return sanitized || 'Customer';
      })();

      // Validation
      if (!items || !Array.isArray(items) || items.length === 0) {
        throw new HttpsError('invalid-argument', 'Items array is required and must not be empty.');
      }

      if (!boostDuration || typeof boostDuration !== 'number' || boostDuration <= 0 || boostDuration > 10080) {
        throw new HttpsError('invalid-argument', 'Boost duration must be a positive number (max 10080 minutes).');
      }

      if (items.length > 50) {
        throw new HttpsError('invalid-argument', 'Cannot boost more than 50 items at once.');
      }

      for (const item of items) {
        if (!item.itemId || typeof item.itemId !== 'string') {
          throw new HttpsError('invalid-argument', 'Each item must have a valid itemId.');
        }
        if (!item.collection || !['products', 'shop_products'].includes(item.collection)) {
          throw new HttpsError('invalid-argument', 'Each item must specify a valid collection.');
        }
        if (item.collection === 'shop_products' && (!item.shopId || typeof item.shopId !== 'string')) {
          throw new HttpsError('invalid-argument', 'Shop products must include a valid shopId.');
        }
      }

      const db = admin.firestore();
      const basePricePerProduct = 1.0;
      const totalPrice = items.length * boostDuration * basePricePerProduct;
      const formattedAmount = Math.round(totalPrice).toString();
      const orderNumber = `BOOST-${Date.now()}-${request.auth.uid.substring(0, 8)}`;
      const rnd = Date.now().toString();
      const isbankConfig = await getIsbankConfig();
      const baseUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
      const okUrl = `${baseUrl}/boostPaymentCallback`;
      const failUrl = `${baseUrl}/boostPaymentCallback`;
      const callbackUrl = `${baseUrl}/boostPaymentCallback`;

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

      await db.collection('pendingBoostPayments').doc(orderNumber).set({
        userId: request.auth.uid,
        amount: totalPrice,
        formattedAmount: formattedAmount,
        orderNumber: orderNumber,
        status: 'awaiting_3d',
        paymentParams: paymentParams,
        boostData: {
          items: items,
          boostDuration: boostDuration,
          isShopContext: isShopContext || false,
          shopId: shopId || null,
          basePricePerProduct: basePricePerProduct,
        },
        customerInfo: {name: sanitizedCustomerName, email: customerEmail, phone: customerPhone},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      });

      return {
        success: true,
        gatewayUrl: isbankConfig.gatewayUrl,
        paymentParams: paymentParams,
        orderNumber: orderNumber,
        totalPrice: totalPrice,
        itemCount: items.length,
      };
    } catch (error) {
      console.error('Boost payment initialization error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

// 3. PAYMENT CALLBACK - Uses executeBoostLogic after payment success
export const boostPaymentCallback = onRequest(
  {
    region: 'europe-west3',
    memory: '512MB',
    timeoutSeconds: 90,
    cors: true,
    invoker: 'public',
  },
  async (request, response) => {
    try {
      const {Response, mdStatus, oid, ProcReturnCode, ErrMsg, HASH, HASHPARAMSVAL} = request.body;

      if (!oid) {
        response.status(400).send('Order number missing');
        return;
      }

      const db = admin.firestore();
      const isbankConfig = await getIsbankConfig();
      const pendingPaymentRef = db.collection('pendingBoostPayments').doc(oid);
      const pendingPaymentSnap = await pendingPaymentRef.get();

      if (!pendingPaymentSnap.exists) {
        response.status(404).send('Payment session not found');
        return;
      }

      const pendingPayment = pendingPaymentSnap.data();

      // Verify hash
      if (HASHPARAMSVAL && HASH) {
        const hashParams = HASHPARAMSVAL + isbankConfig.storeKey;
        const calculatedHash = crypto.createHash('sha512').update(hashParams, 'utf8').digest('base64');

        if (calculatedHash !== HASH) {
          await pendingPaymentRef.update({
            status: 'hash_verification_failed',
            errorMessage: 'Hash verification failed',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          response.send(`
            <!DOCTYPE html>
            <html>
            <head><title>Ödeme Hatası</title></head>
            <body>
              <div style="text-align:center; padding:50px;">
                <h2>Ödeme Doğrulama Hatası</h2>
                <p>Lütfen tekrar deneyin.</p>
              </div>
              <script>window.location.href = 'boost-payment-failed://hash-error';</script>
            </body>
            </html>
          `);
          return;
        }
      }

      const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
      const isTransactionSuccess = Response === 'Approved' && ProcReturnCode === '00';

      if (!isAuthSuccess || !isTransactionSuccess) {
        await pendingPaymentRef.update({
          status: 'payment_failed',
          errorMessage: ErrMsg || 'Payment failed',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        response.send(`
          <!DOCTYPE html>
          <html>
          <head><title>Ödeme Başarısız</title></head>
          <body>
            <div style="text-align:center; padding:50px;">
              <h2>Boost Ödemesi Başarısız</h2>
              <p>${ErrMsg || 'Ödeme işlemi başarısız oldu.'}</p>
            </div>
            <script>window.location.href = 'boost-payment-failed://${encodeURIComponent(ErrMsg || 'payment-failed')}';</script>
          </body>
          </html>
        `);
        return;
      }

      // Payment successful - NOW BOOST
      await pendingPaymentRef.update({
        status: 'payment_verified_processing_boost',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      try {
        const boostData = pendingPayment.boostData;

        // Check admin status
        let isAdmin = false;
        try {
          const userRecord = await admin.auth().getUser(pendingPayment.userId);
          isAdmin = userRecord.customClaims?.admin === true;

          if (!isAdmin) {
            const adminDoc = await db.collection('users').doc(pendingPayment.userId).get();
            isAdmin = adminDoc.exists && adminDoc.data()?.isAdmin === true;
          }
        } catch (error) {
          console.warn('Could not check admin status:', error.message);
          isAdmin = false;
        }

        // Execute boost using shared logic
        const boostResult = await executeBoostLogic(
          db,
          pendingPayment.userId,
          boostData.items,
          boostData.boostDuration,
          isAdmin,
        );

        try {
          const shopBoostCounts = {};
          for (const item of boostResult.boostedItems) {
            if (item.shopId) {
              shopBoostCounts[item.shopId] = (shopBoostCounts[item.shopId] || 0) + 1;
            }
          }

          if (Object.keys(shopBoostCounts).length > 0) {
            const shopUpdateBatch = db.batch();
            for (const [shopId, count] of Object.entries(shopBoostCounts)) {
              const shopRef = db.collection('shops').doc(shopId);
              shopUpdateBatch.update(shopRef, {
                'metrics.boostCount': admin.firestore.FieldValue.increment(count),
                'metrics.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            await shopUpdateBatch.commit();
          }
        } catch (metricsError) {
          console.error('Failed to update shop metrics, but boost was successful:', metricsError);
          // Continue - don't fail the entire boost because metrics update failed
        }

        // Clean the boost result to remove undefined values
        const cleanBoostResult = {
          boostedItemsCount: boostResult.boostedItemsCount,
          totalRequestedItems: boostResult.totalRequestedItems,
          failedItemsCount: boostResult.failedItemsCount || 0,
          boostDuration: boostResult.boostDuration,
          boostStartTime: boostResult.boostStartTime,
          boostEndTime: boostResult.boostEndTime,
          totalPrice: boostResult.totalPrice,
          pricePerItem: boostResult.pricePerItem,
          boostedItems: boostResult.boostedItems.map((item) => ({
            itemId: item.itemId,
            collection: item.collection,
            ...(item.shopId && {shopId: item.shopId}), // Only include if not null
          })),
          // Only include failedItems if it exists and has content
          ...(boostResult.failedItems && boostResult.failedItems.length > 0 && {
            failedItems: boostResult.failedItems,
          }),
          // Only include scheduledTasks if it exists
          ...(boostResult.scheduledTasks && {
            scheduledTasks: boostResult.scheduledTasks,
          }),
        };

        await pendingPaymentRef.update({
          status: 'completed',
          boostResult: cleanBoostResult,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        try {
          // Group items by owner (shop or user)
          const receiptGroups = {};
          
          // First, fetch all product names in a batch
          const productNames = {};
          const productFetchPromises = [];
          
          for (const item of boostResult.boostedItems) {
            const productRef = item.collection === 'shop_products' ? 
              db.collection('shop_products').doc(item.itemId) :
              db.collection('products').doc(item.itemId);
            
            productFetchPromises.push(
              productRef.get().then((snap) => {
                if (snap.exists) {
                  productNames[item.itemId] = snap.data().name || snap.data().productName || 'Boost Item';
                } else {
                  productNames[item.itemId] = 'Boost Item';
                }
              }).catch((err) => {
                console.error(`Failed to fetch product ${item.itemId}:`, err);
                productNames[item.itemId] = 'Boost Item';
              }),
            );
          }
          
          // Wait for all product names to be fetched
          await Promise.all(productFetchPromises);
          
          // ✅ NEW: Fetch buyer information (could be user or shop)
          let buyerInfo = {
            name: pendingPayment.customerInfo.name || 'Customer',
            email: pendingPayment.customerInfo.email || '',
            phone: pendingPayment.customerInfo.phone || '',
          };
          
          // Check if this is a shop context payment
          if (boostData.isShopContext && boostData.shopId) {
            try {
              const shopDoc = await db.collection('shops').doc(boostData.shopId).get();
              if (shopDoc.exists) {
                const shopData = shopDoc.data();
                buyerInfo = {
                  name: shopData.name || 'Shop',
                  email: shopData.email || shopData.contactEmail || '',
                  phone: shopData.contactNo || shopData.phoneNumber || '',
                };
              }
            } catch (shopError) {
              console.error('Failed to fetch shop info, using customerInfo:', shopError);
            }
          } else {
            // It's a user context payment - fetch user data
            try {
              const userDoc = await db.collection('users').doc(pendingPayment.userId).get();
              if (userDoc.exists) {
                const userData = userDoc.data();
                buyerInfo = {
                  name: userData.displayName || pendingPayment.customerInfo.name || 'Customer',
                  email: userData.email || pendingPayment.customerInfo.email || '',
                  phone: userData.phoneNumber || pendingPayment.customerInfo.phone || '',
                };
              }
            } catch (userError) {
              console.error('Failed to fetch user info, using customerInfo:', userError);
            }
          }
          
          // Now group items by owner
          for (const item of boostResult.boostedItems) {
            const ownerId = (item.shopId && typeof item.shopId === 'string' && item.shopId.trim() !== '') ? 
  item.shopId : 
  pendingPayment.userId;
  const ownerType = (item.shopId && typeof item.shopId === 'string' && item.shopId.trim() !== '') ? 'shop' : 'user';
            
            if (!receiptGroups[ownerId]) {
              receiptGroups[ownerId] = {
                ownerId: ownerId,
                ownerType: ownerType,
                items: [],
              };
            }
            
            receiptGroups[ownerId].items.push({
              ...item,
              productName: productNames[item.itemId],
            });
          }
          
          // Create receipt task for each owner
          for (const [ownerId, group] of Object.entries(receiptGroups)) {
            const itemsSubtotal = group.items.length * boostData.boostDuration * boostData.basePricePerProduct;

            console.log(`Creating receipt task for owner ${ownerId} (${group.ownerType}) with ${group.items.length} items`);
            
            await db.collection('receiptTasks').add({
              receiptType: 'boost',
              orderId: oid,
              ownerId: ownerId,
              ownerType: group.ownerType,
              buyerId: pendingPayment.userId,
              buyerName: buyerInfo.name, // ✅ Use fetched buyer info
              buyerEmail: buyerInfo.email, // ✅ NEW
              buyerPhone: buyerInfo.phone, // ✅ NEW
              totalPrice: itemsSubtotal,
              itemsSubtotal: itemsSubtotal,
              deliveryPrice: 0,
              currency: 'TRY',
              paymentMethod: 'isbank_3d',
              orderDate: admin.firestore.FieldValue.serverTimestamp(),
              language: 'tr',
              boostData: {
                boostDuration: boostData.boostDuration,
                itemCount: group.items.length,
                items: group.items.map((item) => ({
                  itemId: item.itemId,
                  collection: item.collection,
                  productName: item.productName,
                  boostDuration: boostData.boostDuration,
                  unitPrice: boostData.basePricePerProduct,
                  totalPrice: boostData.boostDuration * boostData.basePricePerProduct,
                  shopId: item.shopId || null,
                })),
              },
              status: 'pending',
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          
          console.log(`Receipt tasks created for boost payment ${oid}`);
        } catch (receiptError) {
          console.error('Failed to create receipt task for boost payment:', receiptError);
          // Don't throw - receipt generation is non-critical
        }

        response.send(`
          <!DOCTYPE html>
          <html>
          <head><title>Ödeme Başarılı</title></head>
          <body>
            <div style="text-align:center; padding:50px;">
              <h2>✓ Boost Ödemesi Başarılı</h2>
              <p>${boostResult.boostedItemsCount} ürün ${boostResult.boostDuration} dakika boyunca boost edildi.</p>
            </div>
            <script>window.location.href = 'boost-payment-success://${oid}';</script>
          </body>
          </html>
        `);
      } catch (boostError) {
        console.error('Boost processing failed after payment:', boostError);

        await pendingPaymentRef.update({
          status: 'payment_succeeded_boost_failed',
          boostError: boostError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        response.send(`
          <!DOCTYPE html>
          <html>
          <head><title>Boost Hatası</title></head>
          <body>
            <div style="text-align:center; padding:50px;">
              <h2>Ödeme alındı ancak boost işlemi başarısız</h2>
              <p>Lütfen destek ile iletişime geçin. Sipariş No: ${oid}</p>
            </div>
            <script>window.location.href = 'boost-payment-failed://boost-processing-error';</script>
          </body>
          </html>
        `);
      }
    } catch (error) {
      console.error('Boost payment callback error:', error);
      response.status(500).send('Internal server error');
    }
  },
);

// 4. CHECK PAYMENT STATUS (your existing code - no changes)
export const checkBoostPaymentStatus = onCall(
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
      const pendingPaymentSnap = await db.collection('pendingBoostPayments').doc(orderNumber).get();

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
        boostResult: pendingPayment.boostResult || null,
        errorMessage: pendingPayment.errorMessage || null,
        boostError: pendingPayment.boostError || null,
      };
    } catch (error) {
      console.error('Check boost payment status error:', error);
      throw new HttpsError('internal', error.message);
    }
  },
);

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
export {updatePersonalizedFeeds, cleanupOldFeeds} from './13-personalized-feed/index.js';
export {adminToggleProductArchiveStatus, approveArchivedProductEdit} from './14-admin-actions/index.js';
export {translateText, translateBatch} from './15-openai-translation/index.js';
export {processQRCodeGeneration, verifyQRCode, markQRScanned, retryQRGeneration} from './16-qr-for-orders/index.js';
export {
  grantUserCoupon,
  grantFreeShipping,
  getUserCouponsAndBenefits,
  revokeCoupon,
  revokeBenefit,
} from './17-coupons/index.js';
