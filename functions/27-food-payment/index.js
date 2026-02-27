// ============================================================================
// FOOD ORDER CLOUD FUNCTIONS
// ============================================================================
// Add these exports to your main functions/index.js
// Import: import { processFoodOrder, initializeFoodPayment, foodPaymentCallback } from './food-orders.js';
//
// This module handles:
//   1. processFoodOrder       – callable: creates order for pay_at_door
//   2. initializeFoodPayment  – callable: starts İşbank 3D flow for card payments
//   3. foodPaymentCallback    – HTTP: İşbank callback → creates order on success
// ============================================================================

import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import { transliterate } from 'transliteration';

// Re-use your existing getIsbankConfig & generateHashVer3 from index.js,
// or import them here. For self-containment, we duplicate the helpers below.
// In production you'd import: import { getIsbankConfig, generateHashVer3 } from './index.js';

const REGION = 'europe-west3';

// ============================================================================
// HELPER: Validate restaurant is currently open
// ============================================================================

function assertRestaurantOpen(restaurantData) {
  const { workingDays, workingHours, isActive } = restaurantData;

  if (!isActive) {
    throw new HttpsError(
      'failed-precondition',
      'This restaurant is currently not accepting orders.'
    );
  }

  // Current time in Turkey / North Cyprus (UTC+3, IANA: Europe/Istanbul)
  const now = new Date();
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Europe/Istanbul',
    weekday: 'long',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  const parts = formatter.formatToParts(now);
  const currentDay = parts.find((p) => p.type === 'weekday')?.value;  // "Monday"
  const currentHour = parseInt(parts.find((p) => p.type === 'hour')?.value || '0', 10);
  const currentMinute = parseInt(parts.find((p) => p.type === 'minute')?.value || '0', 10);
  const currentMinutes = currentHour * 60 + currentMinute; // minutes since midnight

  // 1. Check working day
  if (Array.isArray(workingDays) && !workingDays.includes(currentDay)) {
    throw new HttpsError(
      'failed-precondition',
      `Restaurant is closed today (${currentDay}). Open on: ${workingDays.join(', ')}.`
    );
  }

  // 2. Check working hours
  if (workingHours && workingHours.open && workingHours.close) {
    const [openH, openM] = workingHours.open.split(':').map(Number);
    const [closeH, closeM] = workingHours.close.split(':').map(Number);
    const openMinutes = openH * 60 + openM;
    const closeMinutes = closeH * 60 + closeM;

    let isOpen;

    if (closeMinutes > openMinutes) {
      // Normal hours (e.g., 08:00 – 22:00)
      isOpen = currentMinutes >= openMinutes && currentMinutes < closeMinutes;
    } else if (closeMinutes < openMinutes) {
      // Overnight hours (e.g., 18:00 – 02:00)
      isOpen = currentMinutes >= openMinutes || currentMinutes < closeMinutes;
    } else {
      // open === close → treat as 24-hour
      isOpen = true;
    }

    if (!isOpen) {
      throw new HttpsError(
        'failed-precondition',
        `Restaurant is closed right now. Working hours: ${workingHours.open} – ${workingHours.close}.`
      );
    }
  }
}

// ============================================================================
// HELPER: Validate & fetch food items from Firestore, compute server totals
// ============================================================================

async function validateAndPriceFoodItems(tx, db, items, restaurantId) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Order must contain at least one item.');
  }

  if (items.length > 50) {
    throw new HttpsError('invalid-argument', 'Order cannot exceed 50 items.');
  }

  const validatedItems = [];
  let subtotal = 0;
  let maxPrepTime = 0;

  for (const item of items) {
    const { foodId, quantity = 1, extras = [], specialNotes = '' } = item;

    if (!foodId || typeof foodId !== 'string') {
      throw new HttpsError('invalid-argument', 'Each item must have a valid foodId.');
    }
    if (quantity < 1 || quantity > 99) {
      throw new HttpsError('invalid-argument', `Invalid quantity (${quantity}) for item ${foodId}.`);
    }

    // Fetch the canonical food document
    const foodRef = db.collection('foods').doc(foodId);
    const foodSnap = await tx.get(foodRef);

    if (!foodSnap.exists) {
      throw new HttpsError('not-found', `Food item "${foodId}" not found.`);
    }

    const foodData = foodSnap.data();

    // Ensure food belongs to the correct restaurant
    if (foodData.restaurantId !== restaurantId) {
      throw new HttpsError(
        'invalid-argument',
        `Food "${foodData.name}" does not belong to this restaurant.`
      );
    }

    // Ensure food is available
    if (foodData.isAvailable === false) {
      throw new HttpsError(
        'failed-precondition',
        `"${foodData.name}" is currently unavailable.`
      );
    }

    // Validate extras — only allow extras defined on the food document
    const allowedExtras = new Set(Array.isArray(foodData.extras) ? foodData.extras : []);
    const validatedExtras = [];

    for (const ext of extras) {
      if (!ext.name || typeof ext.name !== 'string') continue;
      if (!allowedExtras.has(ext.name)) {
        throw new HttpsError(
          'invalid-argument',
          `Extra "${ext.name}" is not available for "${foodData.name}".`
        );
      }
      validatedExtras.push({
        name: ext.name,
        quantity: Math.max(1, ext.quantity || 1),
        price: typeof ext.price === 'number' ? ext.price : 0,
      });
    }

    // Server-authoritative price calculation
    const extrasTotal = validatedExtras.reduce(
      (sum, e) => sum + e.price * e.quantity,
      0
    );
    const itemTotal = (foodData.price + extrasTotal) * quantity;

    subtotal += itemTotal;

    if (foodData.preparationTime && foodData.preparationTime > maxPrepTime) {
      maxPrepTime = foodData.preparationTime;
    }

    validatedItems.push({
      foodId,
      name: foodData.name || '',
      description: foodData.description || '',
      price: foodData.price,
      imageUrl: foodData.imageUrl || '',
      foodCategory: foodData.foodCategory || '',
      foodType: foodData.foodType || '',
      preparationTime: foodData.preparationTime || null,
      quantity,
      extras: validatedExtras,
      specialNotes: typeof specialNotes === 'string' ? specialNotes.substring(0, 500) : '',
      itemTotal: Math.round(itemTotal * 100) / 100,
    });
  }

  return {
    validatedItems,
    subtotal: Math.round(subtotal * 100) / 100,
    estimatedPrepTime: maxPrepTime,
  };
}

// ============================================================================
// HELPER: Create the order document + notification atomically
// ============================================================================

async function createFoodOrderCore(buyerId, requestData, paymentOrderId = null) {
  const {
    restaurantId,
    items,
    paymentMethod,          // 'pay_at_door' | 'card'
    deliveryType = 'delivery', // 'delivery' | 'pickup'
    deliveryAddress = null,
    buyerPhone = '',
    orderNotes = '',
    clientSubtotal = 0,     // for logging / comparison only
  } = requestData;

  if (!restaurantId || typeof restaurantId !== 'string') {
    throw new HttpsError('invalid-argument', 'restaurantId is required.');
  }
  if (!['pay_at_door', 'card'].includes(paymentMethod)) {
    throw new HttpsError('invalid-argument', 'paymentMethod must be "pay_at_door" or "card".');
  }
  if (!['delivery', 'pickup'].includes(deliveryType)) {
    throw new HttpsError('invalid-argument', 'deliveryType must be "delivery" or "pickup".');
  }
  if (deliveryType === 'delivery') {
    if (!deliveryAddress || !deliveryAddress.addressLine1 || !deliveryAddress.phoneNumber) {
      throw new HttpsError('invalid-argument', 'Delivery address with phone is required for delivery orders.');
    }
  }

  const db = admin.firestore();
  let orderResult;

  await db.runTransaction(async (tx) => {
    // ── 1. Fetch & validate restaurant ───────────────────────────────
    const restaurantRef = db.collection('restaurants').doc(restaurantId);
    const restaurantSnap = await tx.get(restaurantRef);

    if (!restaurantSnap.exists) {
      throw new HttpsError('not-found', 'Restaurant not found.');
    }

    const restaurantData = restaurantSnap.data();
    assertRestaurantOpen(restaurantData);

    // ── 2. Fetch buyer ───────────────────────────────────────────────
    const buyerRef = db.collection('users').doc(buyerId);
    const buyerSnap = await tx.get(buyerRef);
    if (!buyerSnap.exists) {
      throw new HttpsError('not-found', 'User not found.');
    }
    const buyerData = buyerSnap.data() || {};
    const buyerName = buyerData.displayName || buyerData.name || 'Customer';

    // ── 3. Idempotency: prevent duplicate orders for same payment ────
    if (paymentOrderId) {
      const dupQuery = db
        .collection('orders-food')
        .where('paymentOrderId', '==', paymentOrderId)
        .limit(1);
      const dupSnap = await tx.get(dupQuery);
      if (!dupSnap.empty) {
        orderResult = {
          orderId: dupSnap.docs[0].id,
          success: true,
          duplicate: true,
        };
        return;
      }
    }

    // ── 4. Validate items & compute server-side totals ───────────────
    const { validatedItems, subtotal, estimatedPrepTime } =
      await validateAndPriceFoodItems(tx, db, items, restaurantId);

    // Server-authoritative total
    const deliveryFee = 0; // adjust if you add delivery pricing later
    const totalPrice = Math.round((subtotal + deliveryFee) * 100) / 100;

    // Log price discrepancy for monitoring
    if (clientSubtotal && Math.abs(clientSubtotal - subtotal) > 0.01) {
      console.warn(
        `⚠️ Food order price discrepancy: client=${clientSubtotal}, server=${subtotal}`
      );
    }

    // ── 5. Create order document ─────────────────────────────────────
    const orderRef = db.collection('orders-food').doc();
    const orderId = orderRef.id;

    const orderDoc = {
      // Buyer
      buyerId,
      buyerName,
      buyerPhone: buyerPhone || buyerData.phoneNumber || '',

      // Restaurant
      restaurantId,
      restaurantName: restaurantData.name || '',
      restaurantOwnerId: restaurantData.ownerId || '',
      restaurantPhone: restaurantData.contactNo || '',
      restaurantProfileImage: restaurantData.profileImageUrl || '',

      // Items (embedded array — food orders are typically small)
      items: validatedItems,
      itemCount: validatedItems.reduce((sum, i) => sum + i.quantity, 0),

      // Pricing
      subtotal,
      deliveryFee,
      totalPrice,
      currency: 'TL',

      // Payment
      paymentMethod,
      paymentOrderId: paymentOrderId || null,
      isPaid: paymentMethod === 'card', // card orders are pre-paid

      // Delivery
      deliveryType,
      deliveryAddress:
        deliveryType === 'delivery' && deliveryAddress ?
          {
              addressLine1: deliveryAddress.addressLine1,
              addressLine2: deliveryAddress.addressLine2 || '',
              city: deliveryAddress.city || '',
              phoneNumber: deliveryAddress.phoneNumber || '',
              location:
                deliveryAddress.location &&
                deliveryAddress.location.latitude &&
                deliveryAddress.location.longitude ?
                  new admin.firestore.GeoPoint(
                      deliveryAddress.location.latitude,
                      deliveryAddress.location.longitude
                    ) :
                  null,
            } :
          null,

      // Meta
      orderNotes: typeof orderNotes === 'string' ? orderNotes.substring(0, 1000) : '',
      estimatedPrepTime,
      status: 'pending', // pending → confirmed → preparing → ready → delivered / completed
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(orderRef, orderDoc);

    // ── 6. Create restaurant notification ────────────────────────────
    const notifRef = db.collection('restaurant_notifications').doc();

    // Build concise items summary for notification
    const itemsSummary = validatedItems.map((i) => ({
      name: i.name,
      quantity: i.quantity,
      foodType: i.foodType,
      extras: i.extras.map((e) => e.name),
      specialNotes: i.specialNotes || '',
      itemTotal: i.itemTotal,
    }));

    tx.set(notifRef, {
      type: 'new_food_order',
      restaurantId,
      restaurantOwnerId: restaurantData.ownerId || '',
      orderId,
      buyerName,
      buyerPhone: orderDoc.buyerPhone,
      itemCount: orderDoc.itemCount,
      totalPrice,
      currency: 'TL',
      paymentMethod,
      isPaid: orderDoc.isPaid,
      deliveryType,
      items: itemsSummary,
      orderNotes: orderDoc.orderNotes,
      estimatedPrepTime,
      isRead: {}, // map — supports multi-user read tracking
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      // Localized preview messages
      message_en: `New order from ${buyerName} — ${orderDoc.itemCount} item(s), ${totalPrice} TL`,
      message_tr: `${buyerName} adından yeni sipariş — ${orderDoc.itemCount} ürün, ${totalPrice} TL`,
    });

    orderResult = {
      orderId,
      success: true,
      totalPrice,
      estimatedPrepTime,
    };
  });

  // ── 7. Clear user's food cart (fire-and-forget) ──────────────────
  if (orderResult && !orderResult.duplicate) {
    clearFoodCartAsync(buyerId).catch((err) =>
      console.error('[FoodOrder] Cart clear failed:', err)
    );
  }

  return orderResult;
}

// ============================================================================
// HELPER: Clear user's food cart after successful order
// ============================================================================

async function clearFoodCartAsync(userId) {
  const db = admin.firestore();
  const cartRef = db.collection('users').doc(userId).collection('foodCart');
  const metaRef = db.collection('users').doc(userId).collection('foodCartMeta').doc('info');

  const snapshot = await cartRef.get();
  if (snapshot.empty) return;

  const BATCH_SIZE = 500;
  for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snapshot.docs.slice(i, i + BATCH_SIZE).forEach((d) => batch.delete(d.ref));
    if (i === 0) batch.delete(metaRef); // delete meta in first batch
    await batch.commit();
  }

  console.log(`[FoodOrder] Cleared ${snapshot.docs.length} food cart items for user ${userId}`);
}

// ============================================================================
// CALLABLE: processFoodOrder (pay_at_door)
// ============================================================================

export const processFoodOrder = onCall(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'You must be signed in to place an order.');
    }

    const data = request.data || {};

    // For pay_at_door, no paymentOrderId
    if (data.paymentMethod !== 'pay_at_door') {
      throw new HttpsError(
        'invalid-argument',
        'Use initializeFoodPayment for card payments.'
      );
    }

    return createFoodOrderCore(request.auth.uid, data);
  }
);

// ============================================================================
// CALLABLE: initializeFoodPayment (card — İşbank 3D)
// ============================================================================

export const initializeFoodPayment = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const {
      restaurantId,
      items,
      deliveryType,
      deliveryAddress,
      buyerPhone,
      orderNotes,
      clientSubtotal,
      customerName,
      customerEmail,
      customerPhone,
      orderNumber,
    } = request.data;

    if (!orderNumber || !restaurantId || !items) {
      throw new HttpsError('invalid-argument', 'orderNumber, restaurantId, and items are required.');
    }

    const db = admin.firestore();
    const userId = request.auth.uid;

    // ── 1. Pre-validate restaurant open & items available ────────────
    // We do a non-transactional read here (payment init is not the final commit)
    const restaurantSnap = await db.collection('restaurants').doc(restaurantId).get();
    if (!restaurantSnap.exists) {
      throw new HttpsError('not-found', 'Restaurant not found.');
    }
    assertRestaurantOpen(restaurantSnap.data());

    // Validate items and compute server total
    // Use a transaction for consistent reads
    let serverSubtotal = 0;
    let validatedItems = [];
    let estimatedPrepTime = 0;

    await db.runTransaction(async (tx) => {
      const result = await validateAndPriceFoodItems(tx, db, items, restaurantId);
      serverSubtotal = result.subtotal;
      validatedItems = result.validatedItems;
      estimatedPrepTime = result.estimatedPrepTime;
    });

    const deliveryFee = 0;
    const serverFinalTotal = Math.round((serverSubtotal + deliveryFee) * 100) / 100;

    // Log discrepancy
    if (clientSubtotal && Math.abs(clientSubtotal - serverSubtotal) > 0.01) {
      console.warn(
        `⚠️ Food payment price discrepancy: client=${clientSubtotal}, server=${serverSubtotal}`
      );
    }

    // ── 2. Generate İşbank payment parameters ────────────────────────
    // NOTE: Import getIsbankConfig & generateHashVer3 from your index.js
    // For this module, we assume they're available. Replace with your actual import.
    const { getIsbankConfig, generateHashVer3 } = await import('./index.js');
    const isbankConfig = await getIsbankConfig();

    const sanitizedName = (() => {
      if (!customerName) return 'Customer';
      return transliterate(customerName)
        .replace(/[^a-zA-Z0-9\s]/g, '')
        .trim()
        .substring(0, 50) || 'Customer';
    })();

    const formattedAmount = Math.round(serverFinalTotal).toString();
    const rnd = Date.now().toString();

    const baseUrl = `https://${REGION}-emlak-mobile-app.cloudfunctions.net`;
    const callbackUrl = `${baseUrl}/foodPaymentCallback`;

    const hashParams = {
      BillToName: sanitizedName,
      amount: formattedAmount,
      callbackurl: callbackUrl,
      clientid: isbankConfig.clientId,
      currency: isbankConfig.currency,
      email: customerEmail || '',
      failurl: callbackUrl,
      hashAlgorithm: 'ver3',
      islemtipi: 'Auth',
      lang: 'tr',
      oid: orderNumber,
      okurl: callbackUrl,
      rnd,
      storetype: isbankConfig.storeType,
      taksit: '',
      tel: customerPhone || '',
    };

    const hash = await generateHashVer3(hashParams);

    const paymentParams = {
      clientid: isbankConfig.clientId,
      storetype: isbankConfig.storeType,
      hash,
      hashAlgorithm: 'ver3',
      islemtipi: 'Auth',
      amount: formattedAmount,
      currency: isbankConfig.currency,
      oid: orderNumber,
      okurl: callbackUrl,
      failurl: callbackUrl,
      callbackurl: callbackUrl,
      lang: 'tr',
      rnd,
      taksit: '',
      BillToName: sanitizedName,
      email: customerEmail || '',
      tel: customerPhone || '',
    };

    // ── 3. Store pending payment ─────────────────────────────────────
    await db.collection('pendingFoodPayments').doc(orderNumber).set({
      userId,
      amount: serverFinalTotal,
      formattedAmount,
      clientAmount: clientSubtotal || 0,
      orderNumber,
      status: 'awaiting_3d',
      paymentParams,
      // Store all order data so callback can create the order
      orderData: {
        restaurantId,
        items: validatedItems.map((i) => ({
          foodId: i.foodId,
          quantity: i.quantity,
          extras: i.extras,
          specialNotes: i.specialNotes,
        })),
        deliveryType: deliveryType || 'delivery',
        deliveryAddress: deliveryAddress || null,
        buyerPhone: buyerPhone || customerPhone || '',
        orderNotes: orderNotes || '',
        paymentMethod: 'card',
        clientSubtotal: clientSubtotal || 0,
      },
      serverCalculation: {
        subtotal: serverSubtotal,
        deliveryFee,
        finalTotal: serverFinalTotal,
        estimatedPrepTime,
        calculatedAt: new Date().toISOString(),
      },
      customerInfo: {
        name: sanitizedName,
        email: customerEmail || '',
        phone: customerPhone || '',
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
    });

    return {
      success: true,
      gatewayUrl: isbankConfig.gatewayUrl,
      paymentParams,
      orderNumber,
      serverTotal: serverFinalTotal,
    };
  }
);

// ============================================================================
// HTTP: foodPaymentCallback (İşbank 3D callback)
// ============================================================================

export const foodPaymentCallback = onRequest(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 90,
    cors: true,
    invoker: 'public',
  },
  async (request, response) => {
    const startTime = Date.now();
    const db = admin.firestore();

    try {
      const {
        Response: bankResponse,
        mdStatus,
        oid,
        ProcReturnCode,
        ErrMsg,
        HASH,
        HASHPARAMSVAL,
      } = request.body;

      if (!oid) {
        response.status(400).send('Missing order number');
        return;
      }

      // Log callback
      const logRef = db.collection('food_payment_callback_logs').doc();
      await logRef.set({
        oid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        requestBody: request.body,
        ip: request.ip || request.headers['x-forwarded-for'] || null,
      });

      const pendingRef = db.collection('pendingFoodPayments').doc(oid);

      // Atomic status check + update
      const txResult = await db.runTransaction(async (tx) => {
        const pendingSnap = await tx.get(pendingRef);

        if (!pendingSnap.exists) {
          return { error: 'not_found' };
        }

        const pending = pendingSnap.data();

        // Idempotency
        if (pending.status === 'completed') {
          return { alreadyProcessed: true, orderId: pending.orderId };
        }
        if (pending.status === 'payment_failed') {
          return { alreadyProcessed: true, status: 'payment_failed' };
        }
        if (pending.status !== 'awaiting_3d') {
          return { alreadyProcessed: true, status: pending.status };
        }

        // Verify hash
        if (HASHPARAMSVAL && HASH) {
          const { getIsbankConfig: getConfig } = await import('./index.js');
          const config = await getConfig();
          const hashInput = HASHPARAMSVAL + config.storeKey;
          const calculated = crypto.createHash('sha512').update(hashInput, 'utf8').digest('base64');

          if (calculated !== HASH) {
            tx.update(pendingRef, {
              status: 'hash_verification_failed',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return { error: 'hash_failed' };
          }
        }

        // Check payment result
        const isAuthOk = ['1', '2', '3', '4'].includes(mdStatus);
        const isTxnOk = bankResponse === 'Approved' && ProcReturnCode === '00';

        if (!isAuthOk || !isTxnOk) {
          tx.update(pendingRef, {
            status: 'payment_failed',
            errorMessage: ErrMsg || 'Payment failed',
            rawResponse: request.body,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
        }

        // Mark as processing
        tx.update(pendingRef, {
          status: 'processing',
          rawResponse: request.body,
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { success: true, pending };
      });

      // ── Handle transaction results ─────────────────────────────────

      if (txResult.error === 'not_found') {
        response.status(404).send('Payment session not found');
        return;
      }

      if (txResult.error === 'hash_failed') {
        response.send(buildRedirectHtml('payment-failed://hash-error', 'Ödeme Doğrulama Hatası'));
        return;
      }

      if (txResult.error === 'payment_failed') {
        response.send(
          buildRedirectHtml(
            `payment-failed://${encodeURIComponent(txResult.message)}`,
            'Ödeme Başarısız',
            txResult.message
          )
        );
        return;
      }

      if (txResult.alreadyProcessed) {
        if (txResult.orderId) {
          response.send(
            buildRedirectHtml(`payment-success://${txResult.orderId}`, '✓ Ödeme Başarılı')
          );
        } else {
          response.send(
            buildRedirectHtml(`payment-status://${txResult.status}`, 'İşlem Tamamlandı')
          );
        }
        return;
      }

      // ── Create the food order ──────────────────────────────────────
      try {
        const pending = txResult.pending;
        const orderResult = await createFoodOrderCore(
          pending.userId,
          {
            ...pending.orderData,
            paymentMethod: 'card',
          },
          oid // paymentOrderId
        );

        await pendingRef.update({
          status: 'completed',
          orderId: orderResult.orderId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: Date.now() - startTime,
        });

        response.send(
          buildRedirectHtml(`payment-success://${orderResult.orderId}`, '✓ Ödeme Başarılı')
        );
      } catch (orderError) {
        console.error('[FoodPayment] Order creation failed:', orderError);

        await pendingRef.update({
          status: 'payment_succeeded_order_failed',
          orderError: orderError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Alert for manual resolution
        await db.collection('_payment_alerts').doc(`food_${oid}`).set({
          type: 'food_order_creation_failed',
          severity: 'high',
          paymentOrderId: oid,
          userId: txResult.pending?.userId,
          errorMessage: orderError.message,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        response.send(
          buildRedirectHtml(
            'payment-failed://order-creation-error',
            'Sipariş Hatası',
            'Ödeme alındı ancak sipariş oluşturulamadı. Lütfen destek ile iletişime geçin.'
          )
        );
      }
    } catch (error) {
      console.error('[FoodPayment] Critical callback error:', error);

      try {
        await db.collection('food_payment_callback_errors').add({
          oid: request.body?.oid || 'unknown',
          error: error.message,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {/* silent */}

      response.status(500).send('Internal server error');
    }
  }
);

// ============================================================================
// CALLABLE: checkFoodPaymentStatus
// ============================================================================

export const checkFoodPaymentStatus = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const { orderNumber } = request.data;
    if (!orderNumber) {
      throw new HttpsError('invalid-argument', 'orderNumber is required.');
    }

    const db = admin.firestore();
    const snap = await db.collection('pendingFoodPayments').doc(orderNumber).get();

    if (!snap.exists) {
      throw new HttpsError('not-found', 'Payment not found.');
    }

    const data = snap.data();
    if (data.userId !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'Unauthorized.');
    }

    return {
      orderNumber,
      status: data.status,
      orderId: data.orderId || null,
      errorMessage: data.errorMessage || null,
    };
  }
);

// ============================================================================
// HELPER: Build redirect HTML for İşbank callback
// ============================================================================

function buildRedirectHtml(deepLink, title, subtitle = '') {
  return `
    <!DOCTYPE html>
    <html>
    <head><title>${title}</title></head>
    <body>
      <div style="text-align:center; padding:50px;">
        <h2>${title}</h2>
        ${subtitle ? `<p>${subtitle}</p>` : ''}
      </div>
      <script>window.location.href = '${deepLink}';</script>
    </body>
    </html>
  `;
}
