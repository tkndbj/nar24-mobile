import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import { transliterate } from 'transliteration';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import PDFDocument from 'pdfkit';
import path from 'path';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const secretClient = new SecretManagerServiceClient();

async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({ name: secretName });
  return version.payload.data.toString('utf8');
}

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

async function generateHashVer3(params) {
  const keys = Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  const config = await getIsbankConfig();
  const values = keys.map((key) => {
    let value = String(params[key] || '');
    value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
    return value;
  });
  const plainText = values.join('|') + '|' + config.storeKey;
  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

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
  let orderDoc = null;

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

    orderDoc = {
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
    scheduleFoodReceiptTask(orderDoc, orderResult.orderId).catch((err) =>  // ✅ moved here
      console.error('[FoodOrder] Receipt task scheduling failed:', err)
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
          const config = await getIsbankConfig();          
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

export const generateFoodReceiptBackground = onDocumentCreated(
  {
    document: 'foodReceiptTasks/{taskId}',
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 120,
  },
  async (event) => {
    const taskData = event.data.data();
    const taskId = event.params.taskId;
    const db = admin.firestore();

    try {
      // Convert Firestore Timestamp → Date
      const orderDate =
        taskData.orderDate?.toDate ? taskData.orderDate.toDate() : new Date();

      const receiptPdf = await generateFoodReceipt({ ...taskData, orderDate });

      // ── Save PDF to Cloud Storage ───────────────────────────────
      const bucket = admin.storage().bucket();
      const receiptFileName = `food-receipts/${taskData.buyerId}/${taskData.orderId}.pdf`;
      const file = bucket.file(receiptFileName);

      const downloadToken = uuidv4();

await file.save(receiptPdf, {
  metadata: {
    contentType: 'application/pdf',
    metadata: {
      firebaseStorageDownloadTokens: downloadToken,  // ← this makes it permanent
    },
  },
});

const bucketName = bucket.name;
const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(receiptFileName)}?alt=media&token=${downloadToken}`;

      // ── Create receipt document in user's subcollection ─────────
      const receiptRef = db
        .collection('users')
        .doc(taskData.buyerId)
        .collection('foodReceipts')
        .doc();

      await receiptRef.set({
        receiptId: receiptRef.id,
        receiptType: 'food_order',
        orderId: taskData.orderId,
        buyerId: taskData.buyerId,
        buyerName: taskData.buyerName || '',
        restaurantId: taskData.restaurantId,
        restaurantName: taskData.restaurantName || '',
        // Pricing
        subtotal: taskData.subtotal,
        deliveryFee: taskData.deliveryFee || 0,
        totalPrice: taskData.totalPrice,
        currency: taskData.currency || 'TL',
        // Payment
        paymentMethod: taskData.paymentMethod,
        isPaid: taskData.isPaid || false,
        // Delivery
        deliveryType: taskData.deliveryType,
        deliveryAddress: taskData.deliveryAddress || null,
        // PDF path
        filePath: receiptFileName,
        downloadUrl,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // ── Mark task as complete ────────────────────────────────────
      await db.collection('foodReceiptTasks').doc(taskId).update({
        status: 'completed',
        filePath: receiptFileName,
        downloadUrl,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[FoodReceipt] Generated successfully for order ${taskData.orderId}`);
    } catch (error) {
      console.error('[FoodReceipt] Error generating receipt:', error);

      const taskRef = db.collection('foodReceiptTasks').doc(taskId);
      const taskDoc = await taskRef.get();
      const retryCount = (taskDoc.data()?.retryCount || 0) + 1;

      await taskRef.update({
        status: retryCount >= 3 ? 'failed' : 'pending',
        retryCount,
        lastError: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (retryCount >= 3) {
        // Log to payment alerts for manual resolution
        await db.collection('_payment_alerts').add({
          type: 'food_receipt_generation_failed',
          severity: 'medium',
          orderId: taskData.orderId,
          buyerId: taskData.buyerId,
          errorMessage: error.message,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Throw to trigger automatic Cloud Functions retry (only if under limit)
      if (retryCount < 3) {
        throw error;
      }
    }
  },
);

// ============================================================================
// HELPER: Schedule receipt task creation after order is placed
// Call this from createFoodOrderCore after the transaction commits.
// ============================================================================

export async function scheduleFoodReceiptTask(orderDoc, orderId) {
  const db = admin.firestore();
  await db.collection('foodReceiptTasks').doc(orderId).set({
    orderId,
    buyerId: orderDoc.buyerId,
    buyerName: orderDoc.buyerName,
    buyerPhone: orderDoc.buyerPhone || '',
    restaurantId: orderDoc.restaurantId,
    restaurantName: orderDoc.restaurantName || '',
    restaurantPhone: orderDoc.restaurantPhone || '',
    items: orderDoc.items,
    subtotal: orderDoc.subtotal,
    deliveryFee: orderDoc.deliveryFee || 0,
    totalPrice: orderDoc.totalPrice,
    currency: orderDoc.currency || 'TL',
    paymentMethod: orderDoc.paymentMethod,
    isPaid: orderDoc.isPaid || false,
    deliveryType: orderDoc.deliveryType,
    deliveryAddress: orderDoc.deliveryAddress || null,
    orderNotes: orderDoc.orderNotes || '',
    estimatedPrepTime: orderDoc.estimatedPrepTime || 0,
    orderDate: admin.firestore.FieldValue.serverTimestamp(),
    language: 'tr', // default; pass from user profile if available
    status: 'pending',
    retryCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ============================================================================
// PDF GENERATOR
// ============================================================================

async function generateFoodReceipt(data) {
  const lang = data.language || 'tr';

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

    // ── Fonts ──────────────────────────────────────────────────────
    const fontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
    const fontBoldPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
    doc.registerFont('Inter', fontPath);
    doc.registerFont('Inter-Bold', fontBoldPath);

    const titleFont = 'Inter-Bold';
    const normalFont = 'Inter';

    // ── Localised labels ───────────────────────────────────────────
    const labels = {
      en: {
        title: 'Nar24 Food Receipt',
        orderInfo: 'Order Information',
        restaurantInfo: 'Restaurant',
        buyerInfo: 'Customer Information',
        deliveryInfo: 'Delivery Address',
        pickupInfo: 'Pickup Order',
        orderedItems: 'Ordered Items',
        orderId: 'Order ID',
        date: 'Date',
        paymentMethod: 'Payment Method',
        deliveryType: 'Delivery Type',
        name: 'Name',
        phone: 'Phone',
        address: 'Address',
        city: 'City',
        restaurant: 'Restaurant',
        restaurantPhone: 'Rest. Phone',
        extras: 'Extras',
        specialNotes: 'Note',
        qty: 'Qty',
        unitPrice: 'Unit Price',
        total: 'Total',
        subtotal: 'Subtotal',
        deliveryFee: 'Delivery Fee',
        free: 'Free',
        grandTotal: 'Total',
        prepTime: 'Est. Prep Time',
        minutes: 'min',
        orderNotes: 'Order Notes',
        payAtDoor: 'Pay at Door',
        card: 'Credit/Debit Card',
        paid: 'PAID',
        pending: 'TO BE PAID',
        deliveryLabel: 'Delivery',
        pickupLabel: 'Pickup',
        footer: 'This is a computer-generated receipt and does not require a signature.',
      },
      tr: {
        title: 'Nar24 Yemek Faturası',
        orderInfo: 'Sipariş Bilgileri',
        restaurantInfo: 'Restoran',
        buyerInfo: 'Müşteri Bilgileri',
        deliveryInfo: 'Teslimat Adresi',
        pickupInfo: 'Gel-Al Siparişi',
        orderedItems: 'Sipariş Edilen Ürünler',
        orderId: 'Sipariş No',
        date: 'Tarih',
        paymentMethod: 'Ödeme Yöntemi',
        deliveryType: 'Teslimat',
        name: 'Ad-Soyad',
        phone: 'Telefon',
        address: 'Adres',
        city: 'Şehir',
        restaurant: 'Restoran',
        restaurantPhone: 'Rest. Tel',
        extras: 'Ekstralar',
        specialNotes: 'Not',
        qty: 'Adet',
        unitPrice: 'Birim Fiyat',
        total: 'Toplam',
        subtotal: 'Ara Toplam',
        deliveryFee: 'Kargo Ücreti',
        free: 'Ücretsiz',
        grandTotal: 'Genel Toplam',
        prepTime: 'Tahmini Hazırlık',
        minutes: 'dk',
        orderNotes: 'Sipariş Notu',
        payAtDoor: 'Kapıda Ödeme',
        card: 'Kredi / Banka Kartı',
        paid: 'ÖDENDİ',
        pending: 'KAPIDA ÖDENECEK',
        deliveryLabel: 'Teslimat',
        pickupLabel: 'Gel-Al',
        footer: 'Bu bilgisayar tarafından oluşturulan bir makbuzdur ve imza gerektirmez.',
      },
      ru: {
        title: 'Nar24 Счет за еду',
        orderInfo: 'Информация о заказе',
        restaurantInfo: 'Ресторан',
        buyerInfo: 'Информация о клиенте',
        deliveryInfo: 'Адрес доставки',
        pickupInfo: 'Самовывоз',
        orderedItems: 'Заказанные блюда',
        orderId: 'Номер заказа',
        date: 'Дата',
        paymentMethod: 'Способ оплаты',
        deliveryType: 'Доставка',
        name: 'Имя',
        phone: 'Телефон',
        address: 'Адрес',
        city: 'Город',
        restaurant: 'Ресторан',
        restaurantPhone: 'Тел. рест.',
        extras: 'Дополнения',
        specialNotes: 'Примечание',
        qty: 'Кол-во',
        unitPrice: 'Цена за ед.',
        total: 'Итого',
        subtotal: 'Промежуточный итог',
        deliveryFee: 'Стоимость доставки',
        free: 'Бесплатно',
        grandTotal: 'Итого',
        prepTime: 'Время приготовления',
        minutes: 'мин',
        orderNotes: 'Примечания к заказу',
        payAtDoor: 'Оплата при получении',
        card: 'Банковская карта',
        paid: 'ОПЛАЧЕНО',
        pending: 'ОПЛАТА ПРИ ПОЛУЧЕНИИ',
        deliveryLabel: 'Доставка',
        pickupLabel: 'Самовывоз',
        footer: 'Это компьютерный чек и не требует подписи.',
      },
    };

    const t = labels[lang] || labels.tr;

    const locale =
      lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';

    const formattedDate = data.orderDate.toLocaleDateString(locale, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });

    // ── Layout constants ───────────────────────────────────────────
    const PAGE_LEFT = 50;
    const PAGE_RIGHT = 550;
    const PAGE_WIDTH = PAGE_RIGHT - PAGE_LEFT; // 500
    const COL_RIGHT = 320;

    // ── Helper: horizontal rule ────────────────────────────────────
    const hRule = (y, color = '#e0e0e0', weight = 1) => {
      doc
        .moveTo(PAGE_LEFT, y)
        .lineTo(PAGE_RIGHT, y)
        .strokeColor(color)
        .lineWidth(weight)
        .stroke();
    };

    // ── Helper: two-column label/value row ─────────────────────────
    const labelValue = (labelText, valueText, x, y, labelW = 120, valueW = 130, valueColor = '#000') => {
      doc
        .font(normalFont)
        .fontSize(10)
        .fillColor('#666')
        .text(`${labelText}:`, x, y, { width: labelW, align: 'left' })
        .fillColor(valueColor)
        .font(normalFont)
        .text(valueText, x + labelW, y, { width: valueW });
    };

    // ──────────────────────────────────────────────────────────────
    // HEADER
    // ──────────────────────────────────────────────────────────────
    doc.fontSize(24).font(titleFont).fillColor('#333').text(t.title, PAGE_LEFT, 50);

    // Logo (top-right, same as product receipt)
    try {
      const logoPath = path.join(__dirname, 'siyahlogo.png');
      doc.image(logoPath, 460, 0, { width: 70 });
    } catch (_) {
      // logo optional
    }

    // Payment status badge (top-right under logo)
    const isPaid = data.isPaid || data.paymentMethod === 'card';
    const badgeLabel = isPaid ? t.paid : t.pending;
    const badgeColor = isPaid ? '#00A86B' : '#E67E22';
    const badgeBgColor = isPaid ? '#e8f8f0' : '#fdf3e7';

    doc
      .rect(COL_RIGHT, 52, PAGE_RIGHT - COL_RIGHT, 22)
      .fillColor(badgeBgColor)
      .fill();
    doc
      .fontSize(9)
      .font(titleFont)
      .fillColor(badgeColor)
      .text(badgeLabel, COL_RIGHT, 59, { width: PAGE_RIGHT - COL_RIGHT, align: 'center' });

    hRule(100);

    // ──────────────────────────────────────────────────────────────
    // TWO-COLUMN INFO BLOCK
    // LEFT: Order details | RIGHT: Customer / delivery info
    // ──────────────────────────────────────────────────────────────

    // ── LEFT COLUMN: Order info ────────────────────────────────────
    doc
      .fontSize(14)
      .font(titleFont)
      .fillColor('#333')
      .text(t.orderInfo, PAGE_LEFT, 115);

    let leftY = 140;
    const labelW = 110;

    // Order ID
    doc.font(titleFont).fontSize(10).fillColor('#666')
      .text(`${t.orderId}:`, PAGE_LEFT, leftY, { width: labelW })
      .fillColor('#000')
      .text(data.orderId.substring(0, 8).toUpperCase(), PAGE_LEFT + labelW, leftY);
    leftY += 20;

    // Date
    labelValue(t.date, formattedDate, PAGE_LEFT, leftY, labelW, 155);
    leftY += 20;

    // Payment method
    const paymentLabel =
      data.paymentMethod === 'pay_at_door' ? t.payAtDoor : t.card;
    labelValue(t.paymentMethod, paymentLabel, PAGE_LEFT, leftY, labelW, 155);
    leftY += 20;

    // Delivery type
    const deliveryLabel =
      data.deliveryType === 'pickup' ? t.pickupLabel : t.deliveryLabel;
    labelValue(t.deliveryType, deliveryLabel, PAGE_LEFT, leftY, labelW, 155);
    leftY += 20;

    // Estimated prep time
    if (data.estimatedPrepTime > 0) {
      labelValue(
        t.prepTime,
        `${data.estimatedPrepTime} ${t.minutes}`,
        PAGE_LEFT,
        leftY,
        labelW,
        155,
      );
      leftY += 20;
    }

    // Restaurant block (below order meta)
    leftY += 5;
    doc.fontSize(11).font(titleFont).fillColor('#333').text(t.restaurantInfo, PAGE_LEFT, leftY);
    leftY += 18;
    labelValue(t.restaurant, data.restaurantName || '-', PAGE_LEFT, leftY, labelW, 155);
    leftY += 18;
    if (data.restaurantPhone) {
      labelValue(t.restaurantPhone, data.restaurantPhone, PAGE_LEFT, leftY, labelW, 155);
      leftY += 18;
    }

    // ── RIGHT COLUMN: Customer / delivery ─────────────────────────
    const rightLabelW = 90;
    const rightValueX = COL_RIGHT + rightLabelW;
    let rightY = 115;

    const isPickup = data.deliveryType === 'pickup';

    doc
      .fontSize(14)
      .font(titleFont)
      .fillColor('#333')
      .text(isPickup ? t.pickupInfo : t.buyerInfo, COL_RIGHT, rightY);
    rightY += 25;

    // Customer name
    doc.font(normalFont).fontSize(10).fillColor('#666')
      .text(`${t.name}:`, COL_RIGHT, rightY, { width: rightLabelW })
      .fillColor('#000')
      .text(data.buyerName || 'N/A', rightValueX, rightY, { width: 160 });
    rightY += 18;

    // Phone
    if (data.buyerPhone) {
      doc.fillColor('#666')
        .text(`${t.phone}:`, COL_RIGHT, rightY, { width: rightLabelW })
        .fillColor('#000')
        .text(data.buyerPhone, rightValueX, rightY, { width: 160 });
      rightY += 18;
    }

    // Delivery address (only for delivery orders)
    if (!isPickup && data.deliveryAddress) {
      doc.fontSize(12).font(titleFont).fillColor('#333')
        .text(t.deliveryInfo, COL_RIGHT, rightY);
      rightY += 18;

      const addr = data.deliveryAddress;

      doc.font(normalFont).fontSize(10).fillColor('#666')
        .text(`${t.address}:`, COL_RIGHT, rightY, { width: rightLabelW })
        .fillColor('#000')
        .text(addr.addressLine1, rightValueX, rightY, { width: 160 });
      rightY += 18;

      if (addr.addressLine2) {
        doc.fillColor('#000')
          .text(addr.addressLine2, rightValueX, rightY, { width: 160 });
        rightY += 18;
      }

      if (addr.city) {
        doc.fillColor('#666')
          .text(`${t.city}:`, COL_RIGHT, rightY, { width: rightLabelW })
          .fillColor('#000')
          .text(addr.city, rightValueX, rightY, { width: 160 });
        rightY += 18;
      }

      if (addr.phoneNumber && addr.phoneNumber !== data.buyerPhone) {
        doc.fillColor('#666')
          .text(`${t.phone}:`, COL_RIGHT, rightY, { width: rightLabelW })
          .fillColor('#000')
          .text(addr.phoneNumber, rightValueX, rightY, { width: 160 });
        rightY += 18;
      }
    }

    // ──────────────────────────────────────────────────────────────
    // ITEMS TABLE
    // ──────────────────────────────────────────────────────────────
    let yPos = Math.max(leftY, rightY) + 20;

    hRule(yPos);
    yPos += 15;

    doc.fontSize(14).font(titleFont).fillColor('#333').text(t.orderedItems, PAGE_LEFT, yPos);
    yPos += 25;

    // Table header row
    const COL = {
      item: 55,
      extras: 230,
      qty: 360,
      unitPrice: 395,
      total: 480,
    };

    doc.fontSize(9).font(titleFont).fillColor('#666')
      .text(t.name,      COL.item,      yPos, { width: 170 })
      .text(t.extras,    COL.extras,    yPos, { width: 125 })
      .text(t.qty,       COL.qty,       yPos, { width: 30, align: 'center' })
      .text(t.unitPrice, COL.unitPrice, yPos, { width: 80, align: 'right' })
      .text(t.total,     COL.total,     yPos, { width: 65, align: 'right' });

    yPos += 16;

    doc.moveTo(COL.item, yPos - 2)
      .lineTo(PAGE_RIGHT - 5, yPos - 2)
      .strokeColor('#e0e0e0')
      .lineWidth(0.5)
      .stroke();

    // ── Item rows ──────────────────────────────────────────────────
    for (const item of data.items) {
      // Page overflow guard
      if (yPos > 680) {
        doc.addPage();
        yPos = 50;
      }

      const rowStart = yPos;

      // Item name
      doc.font(titleFont).fontSize(9).fillColor('#000')
        .text(item.name || 'Item', COL.item, yPos, { width: 170 });

      // Extras + special note in middle column
      doc.font(normalFont).fontSize(8);

      if (item.extras && item.extras.length > 0) {
        const extrasText = item.extras
          .map((e) => (e.quantity > 1 ? `${e.name} x${e.quantity}` : e.name))
          .join(', ');
        doc.fillColor('#555').text(extrasText, COL.extras, yPos, { width: 125 });
        yPos += doc.heightOfString(extrasText, { width: 125, fontSize: 8 });
      }

      if (item.specialNotes) {
        doc.fillColor('#888').fontSize(7)
          .text(`${t.specialNotes}: ${item.specialNotes}`, COL.extras, yPos, { width: 125 });
        yPos += doc.heightOfString(item.specialNotes, { width: 125, fontSize: 7 });
      }

      // Measure actual row height — at least one line
      const rowHeight = Math.max(yPos - rowStart, 16);
      const midRowY = rowStart + (rowHeight / 2) - 5;

      // Qty, unit price, total (vertically centred)
      const extrasTotal = (item.extras || []).reduce(
        (sum, e) => sum + (e.price || 0) * (e.quantity || 1),
        0,
      );
      const effectiveUnitPrice = item.price + extrasTotal;

      doc.font(normalFont).fontSize(9).fillColor('#000')
        .text(String(item.quantity), COL.qty, midRowY, { width: 30, align: 'center' })
        .text(
          `${effectiveUnitPrice.toFixed(0)} ${data.currency}`,
          COL.unitPrice,
          midRowY,
          { width: 80, align: 'right' },
        )
        .text(
          `${(item.itemTotal || effectiveUnitPrice * item.quantity).toFixed(0)} ${data.currency}`,
          COL.total,
          midRowY,
          { width: 65, align: 'right' },
        );

      yPos = Math.max(yPos, rowStart + rowHeight) + 8;

      // Light separator between items
      doc.moveTo(COL.item, yPos - 4)
        .lineTo(PAGE_RIGHT - 5, yPos - 4)
        .strokeColor('#f0f0f0')
        .lineWidth(0.3)
        .stroke();
    }

    // ── Order notes ────────────────────────────────────────────────
    if (data.orderNotes) {
      yPos += 6;
      doc.fontSize(9).font(titleFont).fillColor('#666')
        .text(`${t.orderNotes}:`, PAGE_LEFT, yPos)
        .font(normalFont)
        .fillColor('#444')
        .text(data.orderNotes, PAGE_LEFT + 90, yPos, { width: PAGE_WIDTH - 90 });
      yPos += doc.heightOfString(data.orderNotes, { width: PAGE_WIDTH - 90 }) + 10;
    }

    // ──────────────────────────────────────────────────────────────
    // TOTALS BLOCK
    // ──────────────────────────────────────────────────────────────
    if (yPos > 670) {
      doc.addPage();
      yPos = 50;
    }

    hRule(yPos + 5);
    yPos += 20;

    const totalLabelX = 380;
    const totalValueX = 460;
    const totalValueWidth = 80;

    // Subtotal
    doc.font(titleFont).fontSize(11).fillColor('#666')
      .text(`${t.subtotal}:`, totalLabelX, yPos)
      .fillColor('#333')
      .text(
        `${(data.subtotal || 0).toFixed(0)} ${data.currency}`,
        totalValueX,
        yPos,
        { width: totalValueWidth, align: 'right' },
      );
    yPos += 20;

    // Delivery fee
    const deliveryFee = data.deliveryFee || 0;
    const deliveryText =
      deliveryFee === 0 ? t.free : `${deliveryFee.toFixed(0)} ${data.currency}`;
    const deliveryColor = deliveryFee === 0 ? '#00A86B' : '#333';

    if (data.deliveryType === 'delivery') {
      doc.font(titleFont).fontSize(11).fillColor('#666')
        .text(`${t.deliveryFee}:`, totalLabelX, yPos)
        .fillColor(deliveryColor)
        .text(deliveryText, totalValueX, yPos, { width: totalValueWidth, align: 'right' });
      yPos += 20;
    }

    // Grand total divider
    doc.moveTo(totalLabelX, yPos)
      .lineTo(PAGE_RIGHT, yPos)
      .strokeColor('#333')
      .lineWidth(1.5)
      .stroke();
    yPos += 10;

    // Grand total with green background
    doc.rect(totalLabelX, yPos - 8, PAGE_RIGHT - totalLabelX, 34)
      .fillColor('#f0f8f0')
      .fill();

    doc.font(titleFont).fontSize(14).fillColor('#333')
      .text(`${t.grandTotal}:`, totalLabelX + 10, yPos)
      .fillColor('#00A86B')
      .fontSize(16)
      .text(
        `${(data.totalPrice || 0).toFixed(0)} ${data.currency}`,
        totalValueX,
        yPos,
        { width: totalValueWidth, align: 'right' },
      );

    // Payment status note below total
    yPos += 36;
    doc.fontSize(9).font(normalFont)
      .fillColor(isPaid ? '#00A86B' : '#E67E22')
      .text(
        isPaid ? (lang === 'tr' ? '✓ Online ödeme alındı' : lang === 'ru' ? '✓ Оплата получена онлайн' : '✓ Paid online') : (lang === 'tr' ? '⚠ Teslimat sırasında ödenecek' : lang === 'ru' ? '⚠ Оплата при получении' : '⚠ Payment due at delivery'),
        totalLabelX,
        yPos,
        { width: PAGE_RIGHT - totalLabelX, align: 'right' },
      );

    // ── Footer ─────────────────────────────────────────────────────
    doc.fontSize(8).font(normalFont).fillColor('#999')
      .text(t.footer, PAGE_LEFT, 750, { align: 'center', width: PAGE_WIDTH });

    doc.end();
  });
}
