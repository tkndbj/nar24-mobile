import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import { checkRateLimit } from '../shared/redis.js';
import { transliterate } from 'transliteration';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import PDFDocument from 'pdfkit';
import path from 'path';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';
import { trackPurchaseActivity } from '../11-user-activity/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const secretClient = new SecretManagerServiceClient();

// ── Static pickup location for the physical market ──────────────────────────
// Denormalized onto every orders-market doc so couriers can route to it the
// same way they route to a restaurant. Update these values here whenever the
// market moves.
const MARKET_PICKUP_NAME = 'Nar24 Market';
const MARKET_PICKUP_LAT = 35.1856;  // Nicosia city center
const MARKET_PICKUP_LNG = 33.3823;

async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({ name: secretName });
  return version.payload.data.toString('utf8');
}

// ── İşbank config (shared singleton) ─────────────────────────────────────────

let _isbankConfigPromise = null;

function getIsbankConfig() {
  if (!_isbankConfigPromise) {
    _isbankConfigPromise = (async () => {
      const [clientId, apiUser, apiPassword, storeKey] = await Promise.all([
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_CLIENT_ID/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_USER/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_PASSWORD/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest'),
      ]);
      return {
        clientId, apiUser, apiPassword, storeKey,
        gatewayUrl: 'https://sanalpos.isbank.com.tr/fim/est3Dgate',
        currency: '949',
        storeType: '3d_pay_hosting',
      };
    })();
  }
  return _isbankConfigPromise;
}

async function generateHashVer3(params) {
  const keys = Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));
  const config = await getIsbankConfig();
  const values = keys.map((key) => {
    let value = String(params[key] || '');
    value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
    return value;
  });
  const plainText = values.join('|') + '|' + config.storeKey.trim();
  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

const REGION = 'europe-west3';

// ============================================================================
// HELPER: Validate & price market items, compute server totals
// ============================================================================

async function validateAndPriceMarketItems(tx, db, items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new HttpsError('invalid-argument', 'Order must contain at least one item.');
  }
  if (items.length > 50) {
    throw new HttpsError('invalid-argument', 'Order cannot exceed 50 items.');
  }

  // Parallel fetch all items
  const refs = items.map((item) => db.collection('market-items').doc(item.itemId));
  const snaps = await Promise.all(refs.map((ref) => tx.get(ref)));

  const validatedItems = [];
  let subtotal = 0;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const { itemId, quantity = 1 } = item;

    if (!itemId || typeof itemId !== 'string') {
      throw new HttpsError('invalid-argument', 'Each item must have a valid itemId.');
    }
    if (quantity < 1 || quantity > 99) {
      throw new HttpsError('invalid-argument', `Invalid quantity (${quantity}) for item ${itemId}.`);
    }

    const snap = snaps[i];
    if (!snap.exists) {
      throw new HttpsError('not-found', `Market item "${itemId}" not found.`);
    }

    const data = snap.data();

    if (data.isAvailable === false) {
      throw new HttpsError('failed-precondition', `"${data.name}" is currently unavailable.`);
    }

    // Stock check
    if (typeof data.stock === 'number' && data.stock < quantity) {
      throw new HttpsError(
        'failed-precondition',
        `Insufficient stock for "${data.name}". Available: ${data.stock}, requested: ${quantity}.`
      );
    }

    const itemTotal = data.price * quantity;
    subtotal += itemTotal;

    validatedItems.push({
      itemId,
      name: data.name || '',
      brand: data.brand || '',
      type: data.type || '',
      category: data.category || '',
      price: data.price,
      imageUrl: data.imageUrl || '',
      quantity,
      itemTotal: Math.round(itemTotal * 100) / 100,
    });
  }

  return {
    validatedItems,
    subtotal: Math.round(subtotal * 100) / 100,
  };
}

// ============================================================================
// HELPER: Create market order document atomically
// ============================================================================

async function createMarketOrderCore(buyerId, requestData, paymentOrderId = null) {
  const {
    items,
    paymentMethod,
    buyerPhone = '',
    orderNotes = '',
    clientSubtotal = 0,
  } = requestData;

  if (!['pay_at_door', 'card'].includes(paymentMethod)) {
    throw new HttpsError('invalid-argument', 'paymentMethod must be "pay_at_door" or "card".');
  }

  const db = admin.firestore();
  let orderResult;
  let orderDoc = null;

  await db.runTransaction(async (tx) => {
    // ── 1. Fetch buyer ───────────────────────────────────────────────
    const buyerRef = db.collection('users').doc(buyerId);
    const buyerSnap = await tx.get(buyerRef);
    if (!buyerSnap.exists) {
      throw new HttpsError('not-found', 'User not found.');
    }
    const buyerData = buyerSnap.data() || {};
    const buyerName = buyerData.displayName || buyerData.name || 'Customer';

    // Always use server-side address
    const serverFoodAddress = buyerData.foodAddress || null;
    if (!serverFoodAddress?.addressLine1) {
      throw new HttpsError('failed-precondition', 'No delivery address found on your profile.');
    }

    // ── 2. Idempotency: prevent duplicate orders for same payment ────
    if (paymentOrderId) {
      const dupQuery = db
        .collection('orders-market')
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

    // ── 3. Validate items & compute server-side totals ───────────────
    const { validatedItems, subtotal } =
      await validateAndPriceMarketItems(tx, db, items);

    const deliveryFee = 0;
    const totalPrice = Math.round((subtotal + deliveryFee) * 100) / 100;

    if (clientSubtotal && Math.abs(clientSubtotal - subtotal) > 0.01) {
      console.warn(
        `⚠️ Market order price discrepancy: client=${clientSubtotal}, server=${subtotal}`
      );
    }

    // ── 4. Create order document ─────────────────────────────────────
    const orderRef = db.collection('orders-market').doc();
    const orderId = orderRef.id;

    orderDoc = {
      buyerId,
      buyerName,
      buyerPhone: buyerPhone || buyerData.phoneNumber || '',

      items: validatedItems,
      itemCount: validatedItems.reduce((sum, i) => sum + i.quantity, 0),

      subtotal,
      deliveryFee,
      totalPrice,
      currency: 'TL',

      paymentMethod,
      paymentOrderId: paymentOrderId || null,
      isPaid: paymentMethod === 'card',

      // Denormalized pickup location (static — couriers route here first)
      marketName: MARKET_PICKUP_NAME,
      marketLat: MARKET_PICKUP_LAT,
      marketLng: MARKET_PICKUP_LNG,

      deliveryType: 'delivery',
      deliveryAddress: serverFoodAddress ? {
        addressLine1: serverFoodAddress.addressLine1,
        addressLine2: serverFoodAddress.addressLine2 || '',
        city: serverFoodAddress.city || '',
        mainRegion: serverFoodAddress.mainRegion || '',
        phoneNumber: serverFoodAddress.phoneNumber || '',
        location: serverFoodAddress.location ? new admin.firestore.GeoPoint(
              serverFoodAddress.location.latitude,
              serverFoodAddress.location.longitude
            ) : null,
      } : null,

      orderNotes: typeof orderNotes === 'string' ? orderNotes.substring(0, 1000) : '',
      needsReview: false,
      status: 'pending', // pending → confirmed → preparing → out_for_delivery → delivered
      // Explicit null so the auto-assigner retry sweep's
      // `where('cargoUserId', '==', null)` query matches this doc.
      // Firestore `== null` does NOT match missing fields.
      cargoUserId: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(orderRef, orderDoc);

    // ── 5. Decrement stock atomically ────────────────────────────
for (const item of validatedItems) {
    const ref = db.collection('market-items').doc(item.itemId);
    tx.update(ref, {
      stock: admin.firestore.FieldValue.increment(-item.quantity),
    });
  }

    orderResult = {
      orderId,
      success: true,
      totalPrice,
    };
  });

  // ── Post-transaction side effects (fire-and-forget) ────────────────
  if (orderResult && !orderResult.duplicate) {
    // Clear market cart
    clearMarketCartAsync(buyerId).catch((err) =>
      console.error('[MarketOrder] Cart clear failed:', err)
    );

    // Schedule receipt
    scheduleMarketReceiptTask(orderDoc, orderResult.orderId).catch((err) =>
      console.error('[MarketOrder] Receipt task failed:', err)
    );

    // Track purchase activity
    const activityItems = orderDoc.items.map((item) => ({
      productId: item.itemId,
      category: item.category || 'Market',
      brandModel: item.brand || null,
      price: item.price,
      quantity: item.quantity,
    }));
    trackPurchaseActivity(buyerId, activityItems, orderResult.orderId).catch((err) =>
      console.error('[MarketOrder] Activity tracking failed:', err)
    );
  }

  return orderResult;
}

// ============================================================================
// HELPER: Clear user's market cart after successful order
// ============================================================================

async function clearMarketCartAsync(userId) {
  const db = admin.firestore();
  const cartRef = db.collection('users').doc(userId).collection('marketCart');

  const snapshot = await cartRef.get();
  if (snapshot.empty) return;

  const BATCH_SIZE = 500;
  for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snapshot.docs.slice(i, i + BATCH_SIZE).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  console.log(`[MarketOrder] Cleared ${snapshot.docs.length} market cart items for user ${userId}`);
}

// ============================================================================
// CALLABLE: processMarketOrder (pay_at_door)
// ============================================================================

export const processMarketOrder = onCall(
  {
    region: REGION,
    memory: '512MiB',
    concurrency: 80,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'You must be signed in to place an order.');
    }

    const data = request.data || {};

    if (data.paymentMethod !== 'pay_at_door') {
      throw new HttpsError('invalid-argument', 'Use initializeMarketPayment for card payments.');
    }

    return createMarketOrderCore(request.auth.uid, data);
  }
);

// ============================================================================
// CALLABLE: initializeMarketPayment (card — İşbank 3D)
// ============================================================================

export const initializeMarketPayment = onCall(
  {
    region: REGION,
    memory: '512MiB',
    concurrency: 80,
    timeoutSeconds: 30,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const userId = request.auth.uid;
    const db = admin.firestore();

    const withinLimit = await checkRateLimit(`market_payment_init:${userId}`, 5, 600, { failOpen: false });
    if (!withinLimit) {
      throw new HttpsError('resource-exhausted', 'Too many payment attempts. Try again later.');
    }

    const {
      items,
      buyerPhone,
      orderNotes,
      clientSubtotal,
      customerName,
      customerEmail,
      customerPhone,
      orderNumber,
    } = request.data;

    if (!orderNumber || !items) {
      throw new HttpsError('invalid-argument', 'orderNumber and items are required.');
    }

    // Fetch server-side address
    const userSnap = await db.collection('users').doc(userId).get();
    const serverFoodAddress = userSnap.data()?.foodAddress || null;

    if (!serverFoodAddress?.addressLine1) {
      throw new HttpsError('failed-precondition', 'No delivery address found on your profile.');
    }

    // Validate items and compute server total
    let serverSubtotal = 0;
    let validatedItems = [];

    await db.runTransaction(async (tx) => {
      const result = await validateAndPriceMarketItems(tx, db, items);
      serverSubtotal = result.subtotal;
      validatedItems = result.validatedItems;
    });

    const deliveryFee = 0;
    const serverFinalTotal = Math.round((serverSubtotal + deliveryFee) * 100) / 100;

    if (clientSubtotal && Math.abs(clientSubtotal - serverSubtotal) > 0.01) {
      console.warn(
        `⚠️ Market payment price discrepancy: client=${clientSubtotal}, server=${serverSubtotal}`
      );
    }

    // ── Generate İşbank payment parameters ────────────────────────────
    const isbankConfig = await getIsbankConfig();

    const sanitizedName = (() => {
      if (!customerName) return 'Customer';
      return transliterate(customerName)
        .replace(/[^a-zA-Z0-9\s]/g, '')
        .trim()
        .substring(0, 50) || 'Customer';
    })();

    const formattedAmount = serverFinalTotal.toFixed(2);
    const rnd = Date.now().toString();

    const baseUrl = `https://${REGION}-emlak-mobile-app.cloudfunctions.net`;
    const callbackUrl = `${baseUrl}/marketPaymentCallback`;

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

    // ── Store pending payment ─────────────────────────────────────────
    await db.collection('pendingMarketPayments').doc(orderNumber).set({
      userId,
      amount: serverFinalTotal,
      formattedAmount,
      clientAmount: clientSubtotal || 0,
      orderNumber,
      status: 'awaiting_3d',
      paymentParams,
      orderData: {
        items: validatedItems.map((i) => ({
          itemId: i.itemId,
          quantity: i.quantity,
        })),
        deliveryAddress: serverFoodAddress || null,
        buyerPhone: serverFoodAddress?.phoneNumber || buyerPhone || customerPhone || '',
        orderNotes: orderNotes || '',
        paymentMethod: 'card',
        clientSubtotal: clientSubtotal || 0,
      },
      serverCalculation: {
        subtotal: serverSubtotal,
        deliveryFee,
        finalTotal: serverFinalTotal,
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
// HTTP: marketPaymentCallback (İşbank 3D callback)
// ============================================================================

export const marketPaymentCallback = onRequest(
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
      } = request.body;

      // İşbank probe request
      if (!request.body.oid && request.body.HASH && request.body.rnd) {
        response.status(200).send('<html><body></body></html>');
        return;
      }

      if (!oid) {
        response.status(400).send('Missing order number');
        return;
      }

      const storeKey = (await getIsbankConfig()).storeKey.trim();

      const computedHash = (() => {
        const bodyParams = request.body;
        const keys = Object.keys(bodyParams)
          .filter((key) => {
            const lower = key.toLowerCase();
            return lower !== 'encoding' && lower !== 'hash' && lower !== 'countdown' && lower !== 'nationalidno';
          })
          .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));

        const plainText =
          keys
            .map((key) => {
              const val = String(bodyParams[key] ?? '');
              return val.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
            })
            .join('|') +
          '|' +
          storeKey.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');

        return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
      })();

      const hashValid = HASH && computedHash === HASH;

      if (hashValid) {
        await db.collection('market_payment_callback_logs').doc().set({
          oid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          requestBody: request.body,
          ip: request.ip || request.headers['x-forwarded-for'] || null,
        });
      }

      const pendingRef = db.collection('pendingMarketPayments').doc(oid);

      const txResult = await db.runTransaction(async (tx) => {
        const pendingSnap = await tx.get(pendingRef);

        if (!pendingSnap.exists) return { error: 'not_found' };

        const pending = pendingSnap.data();

        if (pending.status === 'completed') {
          return { alreadyProcessed: true, orderId: pending.orderId };
        }
        if (pending.status === 'payment_failed') {
          return { alreadyProcessed: true, status: 'payment_failed' };
        }
        if (pending.status !== 'awaiting_3d') {
          return { alreadyProcessed: true, status: pending.status };
        }

        if (!hashValid) {
          console.error('[MarketPayment] Hash mismatch for oid:', oid);
          tx.update(pendingRef, {
            status: 'hash_verification_failed',
            receivedHash: HASH || null,
            computedHash,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return { error: 'hash_failed' };
        }

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

        tx.update(pendingRef, {
          status: 'processing',
          rawResponse: request.body,
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { success: true, pending };
      });

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
          response.send(buildRedirectHtml(`payment-success://${txResult.orderId}`, '✓ Ödeme Başarılı'));
        } else {
          response.send(buildRedirectHtml(`payment-status://${txResult.status}`, 'İşlem Tamamlandı'));
        }
        return;
      }

      // ── Create the market order ─────────────────────────────────────
      try {
        const pending = txResult.pending;
        const orderResult = await createMarketOrderCore(
          pending.userId,
          { ...pending.orderData, paymentMethod: 'card' },
          oid
        );

        await pendingRef.update({
          status: 'completed',
          orderId: orderResult.orderId,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          processingDuration: Date.now() - startTime,
        });

        response.send(buildRedirectHtml(`payment-success://${orderResult.orderId}`, '✓ Ödeme Başarılı'));
      } catch (orderError) {
        console.error('[MarketPayment] Order creation failed:', orderError);

        await pendingRef.update({
          status: 'payment_succeeded_order_failed',
          orderError: orderError.message,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await db.collection('_payment_alerts').doc(`market_${oid}`).set({
          type: 'market_order_creation_failed',
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
      console.error('[MarketPayment] Critical callback error:', error);

      try {
        await db.collection('market_payment_callback_errors').add({
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
// CALLABLE: checkMarketPaymentStatus
// ============================================================================

export const checkMarketPaymentStatus = onCall(
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
    const snap = await db.collection('pendingMarketPayments').doc(orderNumber).get();

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
// CALLABLE: updateMarketOrderStatus (admin only)
// ============================================================================

export const updateMarketOrderStatus = onCall(
  { region: REGION, memory: '512MiB', concurrency: 80, timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    // Only admins can update market order status (we are the seller)
    const userRecord = await admin.auth().getUser(request.auth.uid);
    const isAdmin = userRecord.customClaims?.isAdmin === true;
    const isSemiAdmin = userRecord.customClaims?.isSemiAdmin === true;

    if (!isAdmin && !isSemiAdmin) {
      throw new HttpsError('permission-denied', 'Only admins can update market order status.');
    }

    const { orderId, newStatus } = request.data;
    // Admin-settable statuses only. Courier-owned states
    // ('accepted', 'out_for_delivery', 'delivered') are driven exclusively
    // by the courier_actions trigger and are intentionally excluded here.
    const ALLOWED_STATUSES = ['confirmed', 'rejected', 'preparing'];

    if (!orderId || !ALLOWED_STATUSES.includes(newStatus)) {
      throw new HttpsError('invalid-argument', 'Invalid orderId or status.');
    }

    const db = admin.firestore();

    await db.runTransaction(async (tx) => {
      const orderRef = db.collection('orders-market').doc(orderId);
      const orderSnap = await tx.get(orderRef);

      if (!orderSnap.exists) {
        throw new HttpsError('not-found', 'Order not found.');
      }

      const order = orderSnap.data();

      const VALID_TRANSITIONS = {
        pending: ['confirmed', 'rejected'],
        confirmed: ['preparing', 'pending'],
      };

      const allowed = VALID_TRANSITIONS[order.status] || [];
      if (!allowed.includes(newStatus)) {
        throw new HttpsError(
          'failed-precondition',
          `Cannot transition from "${order.status}" to "${newStatus}".`
        );
      }

      tx.update(orderRef, {
        status: newStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify buyer
      if (order.buyerId) {
        const notifRef = db
          .collection('users')
          .doc(order.buyerId)
          .collection('notifications')
          .doc();

        tx.set(notifRef, {
          type: 'market_order_status_update',
          payload: {
            orderId,
            orderStatus: newStatus,
            previousStatus: order.status,
          },
          isRead: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    return { success: true };
  }
);

// ============================================================================
// CALLABLE: submitMarketReview
// ============================================================================

export const submitMarketReview = onCall(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { orderId, rating, comment } = request.data;

    if (!orderId) {
      throw new HttpsError('invalid-argument', 'orderId is required.');
    }
    if (!rating || rating < 1 || rating > 5) {
      throw new HttpsError('invalid-argument', 'Rating must be between 1 and 5.');
    }

    const db = admin.firestore();
    const buyerId = request.auth.uid;

    await db.runTransaction(async (tx) => {
      // 1. Validate order
      const orderRef = db.collection('orders-market').doc(orderId);
      const orderSnap = await tx.get(orderRef);

      if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found.');

      const order = orderSnap.data();

      if (order.buyerId !== buyerId) {
        throw new HttpsError('permission-denied', 'You can only review your own orders.');
      }
      if (order.status !== 'delivered') {
        throw new HttpsError('failed-precondition', 'Order has not been delivered yet.');
      }
      if (!order.needsReview) {
        throw new HttpsError('already-exists', 'You have already reviewed this order.');
      }

      // 2. Fetch buyer info
      const buyerSnap = await tx.get(db.collection('users').doc(buyerId));
      const buyerData = buyerSnap.data() || {};
      const buyerName = buyerData.displayName || buyerData.name || 'Customer';

      // 3. Fetch denormalized market stats
      const marketRef = db.collection('nar24market').doc('stats');
      const marketSnap = await tx.get(marketRef);

      const marketData = marketSnap.exists ? marketSnap.data() : {};
      const currentCount = marketData.reviewCount || 0;
      const currentAvg = marketData.averageRating || 0;

      const newCount = currentCount + 1;
      const newAvg = Math.round(((currentAvg * currentCount + rating) / newCount) * 10) / 10;

      // 4. Create review document
      const reviewRef = db.collection('nar24market').doc('stats').collection('reviews').doc();
      tx.set(reviewRef, {
        orderId,
        buyerId,
        buyerName,
        rating,
        comment: typeof comment === 'string' ? comment.substring(0, 1000) : '',
        imageUrls: Array.isArray(request.data.imageUrls) ? request.data.imageUrls.slice(0, 3).filter((u) => typeof u === 'string') : [],
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 5. Update denormalized stats
      tx.set(marketRef, {
        averageRating: newAvg,
        reviewCount: newCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // 6. Mark order as reviewed
      tx.update(orderRef, {
        needsReview: false,
        reviewId: reviewRef.id,
      });
    });

    return { success: true };
  }
);

// ============================================================================
// HELPER: Build redirect HTML for İşbank callback
// ============================================================================

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function buildRedirectHtml(deepLink, title, subtitle = '') {
  return `
    <!DOCTYPE html>
    <html>
    <head><title>${escapeHtml(title)}</title></head>
    <body>
      <div style="text-align:center; padding:50px;">
        <h2>${escapeHtml(title)}</h2>
        ${subtitle ? `<p>${escapeHtml(subtitle)}</p>` : ''}
      </div>
      <script>window.location.href = ${JSON.stringify(deepLink)};</script>
    </body>
    </html>
  `;
}

// ============================================================================
// RECEIPT: Task scheduler
// ============================================================================

export async function scheduleMarketReceiptTask(orderDoc, orderId) {
  const db = admin.firestore();
  await db.collection('marketReceiptTasks').doc(orderId).set({
    orderId,
    buyerId: orderDoc.buyerId,
    buyerName: orderDoc.buyerName,
    buyerPhone: orderDoc.buyerPhone || '',
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
    orderDate: admin.firestore.FieldValue.serverTimestamp(),
    language: 'tr',
    status: 'pending',
    retryCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    deleteAt: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
  });
}

// ============================================================================
// RECEIPT: Background generator (triggered by task creation)
// ============================================================================

export const generateMarketReceiptBackground = onDocumentCreated(
  {
    document: 'marketReceiptTasks/{taskId}',
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 120,
  },
  async (event) => {
    const taskData = event.data.data();
    const taskId = event.params.taskId;
    const db = admin.firestore();

    try {
      const orderDate =
        taskData.orderDate?.toDate ? taskData.orderDate.toDate() : new Date();

      const receiptPdf = await generateMarketReceipt({ ...taskData, orderDate });

      const bucket = admin.storage().bucket();
      const receiptFileName = `market-receipts/${taskData.buyerId}/${taskData.orderId}.pdf`;
      const file = bucket.file(receiptFileName);

      const downloadToken = uuidv4();

      await file.save(receiptPdf, {
        metadata: {
          contentType: 'application/pdf',
          metadata: { firebaseStorageDownloadTokens: downloadToken },
        },
      });

      const bucketName = bucket.name;
      const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(receiptFileName)}?alt=media&token=${downloadToken}`;

      const receiptRef = db
        .collection('users')
        .doc(taskData.buyerId)
        .collection('marketReceipts')
        .doc();

      await receiptRef.set({
        receiptId: receiptRef.id,
        receiptType: 'market_order',
        orderId: taskData.orderId,
        buyerId: taskData.buyerId,
        buyerName: taskData.buyerName || '',
        subtotal: taskData.subtotal,
        deliveryFee: taskData.deliveryFee || 0,
        totalPrice: taskData.totalPrice,
        currency: taskData.currency || 'TL',
        paymentMethod: taskData.paymentMethod,
        isPaid: taskData.isPaid || false,
        deliveryType: taskData.deliveryType,
        deliveryAddress: taskData.deliveryAddress || null,
        filePath: receiptFileName,
        downloadUrl,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection('marketReceiptTasks').doc(taskId).update({
        status: 'completed',
        filePath: receiptFileName,
        downloadUrl,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[MarketReceipt] Generated successfully for order ${taskData.orderId}`);
    } catch (error) {
      console.error('[MarketReceipt] Error generating receipt:', error);

      const taskRef = db.collection('marketReceiptTasks').doc(taskId);
      const taskDoc = await taskRef.get();
      const retryCount = (taskDoc.data()?.retryCount || 0) + 1;

      await taskRef.update({
        status: retryCount >= 3 ? 'failed' : 'pending',
        retryCount,
        lastError: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (retryCount >= 3) {
        await db.collection('_payment_alerts').add({
          type: 'market_receipt_generation_failed',
          severity: 'medium',
          orderId: taskData.orderId,
          buyerId: taskData.buyerId,
          errorMessage: error.message,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (retryCount < 3) throw error;
    }
  },
);

// ============================================================================
// PDF GENERATOR
// ============================================================================

async function generateMarketReceipt(data) {
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

    const fontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
    const fontBoldPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
    doc.registerFont('Inter', fontPath);
    doc.registerFont('Inter-Bold', fontBoldPath);

    const titleFont = 'Inter-Bold';
    const normalFont = 'Inter';

    const t = lang === 'en' ? {
      title: 'Nar24 Market Receipt',
      orderInfo: 'Order Information',
      buyerInfo: 'Customer Information',
      deliveryInfo: 'Delivery Address',
      orderedItems: 'Ordered Items',
      orderId: 'Order ID',
      date: 'Date',
      paymentMethod: 'Payment Method',
      name: 'Name',
      phone: 'Phone',
      address: 'Address',
      city: 'City',
      brand: 'Brand',
      qty: 'Qty',
      unitPrice: 'Unit Price',
      total: 'Total',
      subtotal: 'Subtotal',
      deliveryFee: 'Delivery Fee',
      free: 'Free',
      grandTotal: 'Total',
      orderNotes: 'Order Notes',
      payAtDoor: 'Pay at Door',
      card: 'Credit/Debit Card',
      paid: 'PAID',
      pending: 'TO BE PAID',
      footer: 'This is a computer-generated receipt and does not require a signature.',
    } : {
      title: 'Nar24 Market Faturası',
      orderInfo: 'Sipariş Bilgileri',
      buyerInfo: 'Müşteri Bilgileri',
      deliveryInfo: 'Teslimat Adresi',
      orderedItems: 'Sipariş Edilen Ürünler',
      orderId: 'Sipariş No',
      date: 'Tarih',
      paymentMethod: 'Ödeme Yöntemi',
      name: 'Ad-Soyad',
      phone: 'Telefon',
      address: 'Adres',
      city: 'Şehir',
      brand: 'Marka',
      qty: 'Adet',
      unitPrice: 'Birim Fiyat',
      total: 'Toplam',
      subtotal: 'Ara Toplam',
      deliveryFee: 'Teslimat Ücreti',
      free: 'Ücretsiz',
      grandTotal: 'Genel Toplam',
      orderNotes: 'Sipariş Notu',
      payAtDoor: 'Kapıda Ödeme',
      card: 'Kredi / Banka Kartı',
      paid: 'ÖDENDİ',
      pending: 'KAPIDA ÖDENECEK',
      footer: 'Bu bilgisayar tarafından oluşturulan bir makbuzdur ve imza gerektirmez.',
    };

    const locale = lang === 'tr' ? 'tr-TR' : 'en-US';
    const formattedDate = data.orderDate.toLocaleDateString(locale, {
      year: 'numeric', month: 'long', day: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });

    const PAGE_LEFT = 50;
    const PAGE_RIGHT = 550;
    const PAGE_WIDTH = PAGE_RIGHT - PAGE_LEFT;

    const hRule = (y, color = '#e0e0e0', weight = 1) => {
      doc.moveTo(PAGE_LEFT, y).lineTo(PAGE_RIGHT, y)
        .strokeColor(color).lineWidth(weight).stroke();
    };

    // ── Header ─────────────────────────────────────────────────────────
    doc.fontSize(24).font(titleFont).fillColor('#333').text(t.title, PAGE_LEFT, 50);

    try {
      const logoPath = path.join(__dirname, 'siyahlogo.png');
      doc.image(logoPath, 460, 0, { width: 70 });
    } catch (_) {
        // logo optional — not all deployments include it
      }

    const isPaid = data.isPaid || data.paymentMethod === 'card';
    const badgeLabel = isPaid ? t.paid : t.pending;
    const badgeColor = isPaid ? '#00A86B' : '#E67E22';
    const badgeBgColor = isPaid ? '#e8f8f0' : '#fdf3e7';

    doc.rect(320, 52, PAGE_RIGHT - 320, 22).fillColor(badgeBgColor).fill();
    doc.fontSize(9).font(titleFont).fillColor(badgeColor)
      .text(badgeLabel, 320, 59, { width: PAGE_RIGHT - 320, align: 'center' });

    hRule(100);

    // ── Order info + Customer info ─────────────────────────────────────
    let leftY = 115;
    const labelW = 110;

    doc.fontSize(14).font(titleFont).fillColor('#333').text(t.orderInfo, PAGE_LEFT, leftY);
    leftY += 25;

    doc.font(normalFont).fontSize(10).fillColor('#666')
      .text(`${t.orderId}:`, PAGE_LEFT, leftY, { width: labelW })
      .fillColor('#000').font(titleFont)
      .text(data.orderId.substring(0, 8).toUpperCase(), PAGE_LEFT + labelW, leftY);
    leftY += 20;

    doc.font(normalFont).fillColor('#666')
      .text(`${t.date}:`, PAGE_LEFT, leftY, { width: labelW })
      .fillColor('#000').text(formattedDate, PAGE_LEFT + labelW, leftY);
    leftY += 20;

    const paymentLabel = data.paymentMethod === 'pay_at_door' ? t.payAtDoor : t.card;
    doc.fillColor('#666').text(`${t.paymentMethod}:`, PAGE_LEFT, leftY, { width: labelW })
      .fillColor('#000').text(paymentLabel, PAGE_LEFT + labelW, leftY);
    leftY += 30;

    // Customer
    let rightY = 115;
    doc.fontSize(14).font(titleFont).fillColor('#333').text(t.buyerInfo, 320, rightY);
    rightY += 25;

    doc.font(normalFont).fontSize(10).fillColor('#666')
      .text(`${t.name}:`, 320, rightY, { width: 90 })
      .fillColor('#000').text(data.buyerName || 'N/A', 410, rightY, { width: 140 });
    rightY += 18;

    if (data.buyerPhone) {
      doc.fillColor('#666').text(`${t.phone}:`, 320, rightY, { width: 90 })
        .fillColor('#000').text(data.buyerPhone, 410, rightY, { width: 140 });
      rightY += 18;
    }

    if (data.deliveryAddress) {
      doc.fontSize(12).font(titleFont).fillColor('#333').text(t.deliveryInfo, 320, rightY);
      rightY += 18;
      const addr = data.deliveryAddress;
      doc.font(normalFont).fontSize(10).fillColor('#666')
        .text(`${t.address}:`, 320, rightY, { width: 90 })
        .fillColor('#000').text(addr.addressLine1, 410, rightY, { width: 140 });
      rightY += 18;
      if (addr.city) {
        doc.fillColor('#666').text(`${t.city}:`, 320, rightY, { width: 90 })
          .fillColor('#000').text(addr.city, 410, rightY, { width: 140 });
        rightY += 18;
      }
    }

    // ── Items table ────────────────────────────────────────────────────
    let yPos = Math.max(leftY, rightY) + 10;
    hRule(yPos);
    yPos += 15;

    doc.fontSize(14).font(titleFont).fillColor('#333').text(t.orderedItems, PAGE_LEFT, yPos);
    yPos += 25;

    const COL = { item: 55, brand: 230, qty: 340, unitPrice: 390, total: 480 };

    doc.fontSize(9).font(titleFont).fillColor('#666')
      .text(t.name, COL.item, yPos, { width: 170 })
      .text(t.brand, COL.brand, yPos, { width: 100 })
      .text(t.qty, COL.qty, yPos, { width: 40, align: 'center' })
      .text(t.unitPrice, COL.unitPrice, yPos, { width: 80, align: 'right' })
      .text(t.total, COL.total, yPos, { width: 65, align: 'right' });
    yPos += 16;

    doc.moveTo(COL.item, yPos - 2).lineTo(PAGE_RIGHT - 5, yPos - 2)
      .strokeColor('#e0e0e0').lineWidth(0.5).stroke();

    for (const item of data.items) {
      if (yPos > 680) {doc.addPage(); yPos = 50;}

      doc.font(titleFont).fontSize(9).fillColor('#000')
        .text(item.name || 'Item', COL.item, yPos, { width: 170 });

      doc.font(normalFont).fontSize(8).fillColor('#555')
        .text(item.brand || '', COL.brand, yPos, { width: 100 });

      doc.font(normalFont).fontSize(9).fillColor('#000')
        .text(String(item.quantity), COL.qty, yPos, { width: 40, align: 'center' })
        .text(`${item.price.toFixed(2)} ${data.currency}`, COL.unitPrice, yPos, { width: 80, align: 'right' })
        .text(`${(item.itemTotal || item.price * item.quantity).toFixed(2)} ${data.currency}`, COL.total, yPos, { width: 65, align: 'right' });

      yPos += 20;

      doc.moveTo(COL.item, yPos - 4).lineTo(PAGE_RIGHT - 5, yPos - 4)
        .strokeColor('#f0f0f0').lineWidth(0.3).stroke();
    }

    // Order notes
    if (data.orderNotes) {
      yPos += 6;
      doc.fontSize(9).font(titleFont).fillColor('#666')
        .text(`${t.orderNotes}:`, PAGE_LEFT, yPos)
        .font(normalFont).fillColor('#444')
        .text(data.orderNotes, PAGE_LEFT + 90, yPos, { width: PAGE_WIDTH - 90 });
      yPos += doc.heightOfString(data.orderNotes, { width: PAGE_WIDTH - 90 }) + 10;
    }

    // ── Totals ─────────────────────────────────────────────────────────
    if (yPos > 670) {doc.addPage(); yPos = 50;}
    hRule(yPos + 5);
    yPos += 20;

    const tLX = 380;
    const tVX = 460;

    doc.font(titleFont).fontSize(11).fillColor('#666')
      .text(`${t.subtotal}:`, tLX, yPos)
      .fillColor('#333')
      .text(`${(data.subtotal || 0).toFixed(2)} ${data.currency}`, tVX, yPos, { width: 80, align: 'right' });
    yPos += 20;

    const deliveryFee = data.deliveryFee || 0;
    doc.font(titleFont).fontSize(11).fillColor('#666')
      .text(`${t.deliveryFee}:`, tLX, yPos)
      .fillColor(deliveryFee === 0 ? '#00A86B' : '#333')
      .text(deliveryFee === 0 ? t.free : `${deliveryFee.toFixed(2)} ${data.currency}`, tVX, yPos, { width: 80, align: 'right' });
    yPos += 20;

    doc.moveTo(tLX, yPos).lineTo(PAGE_RIGHT, yPos).strokeColor('#333').lineWidth(1.5).stroke();
    yPos += 10;

    doc.rect(tLX, yPos - 8, PAGE_RIGHT - tLX, 34).fillColor('#f0f8f0').fill();

    doc.font(titleFont).fontSize(14).fillColor('#333')
      .text(`${t.grandTotal}:`, tLX + 10, yPos)
      .fillColor('#00A86B').fontSize(16)
      .text(`${(data.totalPrice || 0).toFixed(2)} ${data.currency}`, tVX, yPos, { width: 80, align: 'right' });

    yPos += 36;
    doc.fontSize(9).font(normalFont)
      .fillColor(isPaid ? '#00A86B' : '#E67E22')
      .text(
        isPaid ? (lang === 'tr' ? '✓ Online ödeme alındı' : '✓ Paid online') : (lang === 'tr' ? '⚠ Teslimat sırasında ödenecek' : '⚠ Payment due at delivery'),
        tLX, yPos, { width: PAGE_RIGHT - tLX, align: 'right' },
      );

    // Footer
    doc.fontSize(8).font(normalFont).fillColor('#999')
      .text(t.footer, PAGE_LEFT, 750, { align: 'center', width: PAGE_WIDTH });

    doc.end();
  });
}
