/**
 * food_courier_notifications.js
 *
 * Scalable courier notification system.
 *
 * Architecture:
 * ─────────────────────────────────────────────────────────────────
 * • food_courier_notifications/{notifId}  — shared broadcast collection.
 *   ONE document per event, ALL couriers read it. Efficient at any scale.
 *   No per-courier fan-out write storms.
 *
 * • FCM Topic  "food_couriers"            — push to all couriers in one call.
 *   Firebase handles delivery to every subscribed device automatically.
 *
 * • Firestore trigger (onDocumentUpdated) — decoupled, reliable, catches
 *   every status change regardless of code path (callable, direct write, etc.)
 *
 * Notification lifecycle:
 *   order accepted  ──► restaurant can "Inform Courier" (heads_up, 5 min cooldown)
 *   order → ready   ──► automatic (order_ready) notification + FCM topic push
 *   order claimed   ──► notification deactivated (isActive = false)
 *   order rejected/cancelled ──► notification deactivated
 *   30 min TTL      ──► scheduled cleanup
 * ─────────────────────────────────────────────────────────────────
 */

import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule as onScheduleFn } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

// ─── FCM topic all active couriers subscribe to on login ─────────────────────
const FCM_TOPIC_ALL_COURIERS = 'food_couriers';

// ─── Notification TTLs ───────────────────────────────────────────────────────
const TTL_ORDER_READY_MS  = 30 * 60 * 1000; // 30 min
const TTL_HEADS_UP_MS     = 15 * 60 * 1000; // 15 min
const INFORM_COOLDOWN_MS  =  5 * 60 * 1000; //  5 min between Inform Courier presses
const CALL_COURIER_COOLDOWN_MS = 2 * 60 * 1000; // 2 min between calls
const CALL_COURIER_TTL_MS      = 30 * 60 * 1000; // call expires after 30 min

// ─── FCM Android channel (create in Flutter) ─────────────────────────────────
const FCM_CHANNEL_ID = 'food_orders_high';

export const callFoodCourier = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 20 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { restaurantId, callNote = '' } = request.data;
    if (!restaurantId || typeof restaurantId !== 'string') {
      throw new HttpsError('invalid-argument', 'restaurantId is required.');
    }

    const db   = admin.firestore();
    const claims = request.auth.token;

    // ── 1. Verify caller belongs to this restaurant ───────────────────
    const restaurantClaims = claims.restaurants || {};
    if (!(restaurantId in restaurantClaims)) {
      throw new HttpsError('permission-denied', 'Not authorised for this restaurant.');
    }

    // ── 2. Fetch restaurant doc ───────────────────────────────────────
    const restaurantSnap = await db.collection('restaurants').doc(restaurantId).get();
    if (!restaurantSnap.exists) {
      throw new HttpsError('not-found', 'Restaurant not found.');
    }
    const restaurant = restaurantSnap.data();

    // ── 3. Cooldown — prevent spam ────────────────────────────────────
    if (restaurant.lastCourierCallAt) {
      const lastCallMs = restaurant.lastCourierCallAt.toDate().getTime();
      if (Date.now() - lastCallMs < CALL_COURIER_COOLDOWN_MS) {
        const remaining = Math.ceil(
          (CALL_COURIER_COOLDOWN_MS - (Date.now() - lastCallMs)) / 1000
        );
        throw new HttpsError(
          'resource-exhausted',
          `Please wait ${remaining}s before calling again.`
        );
      }
    }

    // ── 4. Check no active call already exists for this restaurant ────
    const activeSnap = await db
      .collection('courier_calls')
      .where('restaurantId', '==', restaurantId)
      .where('isActive', '==', true)
      .limit(1)
      .get();

    if (!activeSnap.empty) {
      // Return the existing call rather than creating a duplicate
      return { success: true, callId: activeSnap.docs[0].id, existing: true };
    }

    // ── 5. Create the courier_calls document ─────────────────────────
    const batch = db.batch();

    const callRef = db.collection('courier_calls').doc();
    batch.set(callRef, {
      restaurantId,
      restaurantName: restaurant.name || '',
      restaurantProfileImage: restaurant.profileImageUrl || '',
      restaurantOwnerId: restaurant.ownerId || '',
      restaurantAddress: restaurant.address || '',
      callNote: typeof callNote === 'string' ? callNote.substring(0, 200) : '',
      status: 'waiting',          // waiting | accepted | completed
      acceptedBy: null,
      acceptedByName: null,
      acceptedAt: null,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + CALL_COURIER_TTL_MS
      ),
    });

    // Stamp cooldown on restaurant doc
    batch.update(db.collection('restaurants').doc(restaurantId), {
      lastCourierCallAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // ── 6. FCM push to all couriers ───────────────────────────────────
    try {
      await admin.messaging().send({
        topic: FCM_TOPIC_ALL_COURIERS,
        notification: {
          title: '🛵 Kurye Çağrısı',
          body: `${restaurant.name || 'Restoran'} kurye bekliyor!`,
        },
        data: {
          type: 'courier_call',
          callId: callRef.id,
          restaurantId,
          restaurantName: restaurant.name || '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          notification: { channelId: FCM_CHANNEL_ID, priority: 'max' },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'order_alert.caf', badge: 1 } },
        },
      });
    } catch (err) {
      console.error('[CourierCall] FCM send failed (non-fatal):', err.message);
    }

    console.log(`[CourierCall] Call created ${callRef.id} for restaurant ${restaurantId}`);
    return { success: true, callId: callRef.id };
  }
);

// ============================================================================
// CALLABLE: createScannedFoodOrder — courier scans receipt, creates the order
// ============================================================================

export const createScannedRestaurantOrder = onCall(
  { region: REGION, memory: '512MiB', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');

    const {
      restaurantId,
      scannedRawText = '',
      detectedAddress = null,
      detectedTotal = null,
      detectedPhone = null,
      detectedLat = null,
      detectedLng = null,
      detectedItems = [],
    } = request.data;

    if (!restaurantId) throw new HttpsError('invalid-argument', 'restaurantId is required.');

    const db = admin.firestore();
    const uid = request.auth.uid;

    // Verify caller belongs to this restaurant
    const userRecord = await admin.auth().getUser(uid);
    const restaurantClaims = userRecord.customClaims?.restaurants || {};
    if (!(restaurantId in restaurantClaims)) {
      throw new HttpsError('permission-denied', 'Not authorised for this restaurant.');
    }

    const restaurantSnap = await db.collection('restaurants').doc(restaurantId).get();
    if (!restaurantSnap.exists) throw new HttpsError('not-found', 'Restaurant not found.');
    const restaurant = restaurantSnap.data();

    const locationGeoPoint = (
      typeof detectedLat === 'number' && typeof detectedLng === 'number'
    ) ? new admin.firestore.GeoPoint(detectedLat, detectedLng) : null;

    const orderRef = db.collection('orders-food').doc();
    const orderId = orderRef.id;

    await orderRef.set({
      sourceType: 'scanned_receipt',
      restaurantId,
      restaurantName: restaurant.name || '',
      restaurantProfileImage: restaurant.profileImageUrl || '',
      restaurantOwnerId: restaurant.ownerId || '',
      restaurantPhone: restaurant.contactNo || '',
      restaurantLat: restaurant.latitude || null,
      restaurantLng: restaurant.longitude || null,
      // Denormalized for area analytics (CF-55). Restaurant doc uses
      // `city` for the broader district and `subcity` for the neighborhood,
      // matching buyer's deliveryAddress.mainRegion + .city respectively.
      restaurantCity: restaurant.city || '',
      restaurantSubcity: restaurant.subcity || '',

      // No courier yet — assigned when courier takes from pool
      cargoUserId: null,
      cargoName: null,

      buyerId: null,
      buyerName: 'External Customer',
      buyerPhone: detectedPhone || '',

      // Items from OCR
      items: Array.isArray(detectedItems) ? detectedItems.slice(0, 50).map((item, i) => ({
        foodId: `scanned_${i}`,
        name: typeof item.name === 'string' ? item.name.substring(0, 200) : 'Unknown item',
        quantity: typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1,
        price: typeof item.price === 'number' ? item.price : 0,
        extras: [],
        specialNotes: '',
        itemTotal: (typeof item.price === 'number' ? item.price : 0) * (typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1),
      })) : [],
      itemCount: Array.isArray(detectedItems) ? detectedItems.reduce((sum, item) => sum + (typeof item.quantity === 'number' && item.quantity > 0 ? Math.floor(item.quantity) : 1), 0) : 0,

      subtotal: typeof detectedTotal === 'number' ? detectedTotal : 0,
      deliveryFee: 0,
      totalPrice: typeof detectedTotal === 'number' ? detectedTotal : 0,
      currency: 'TL',

      paymentMethod: 'unknown',
      isPaid: false,

      deliveryType: 'delivery',
      deliveryAddress: detectedAddress ? {
        addressLine1: detectedAddress,
        city: '',
        phoneNumber: detectedPhone || '',
        location: locationGeoPoint,
      } : null,

      scannedReceipt: {
        rawText: scannedRawText.substring(0, 2000),
        detectedAddress: detectedAddress || null,
        detectedTotal: typeof detectedTotal === 'number' ? detectedTotal : null,
        scannedAt: new Date().toISOString(),
      },

      // Starts as accepted — restaurant will mark ready, then courier takes it
      status: 'accepted',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      needsReview: false,
      orderNotes: '',
      estimatedPrepTime: 0,
    });

    console.log(`[ScannedOrder] Restaurant ${restaurantId} created scanned order ${orderId}`);
    return { success: true, orderId };
  }
);

export const cleanupExpiredCourierCalls = onScheduleFn(
  { schedule: 'every 30 minutes', region: REGION, memory: '256MiB' },
  async () => {
    const db  = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const snap = await db
      .collection('courier_calls')
      .where('expiresAt', '<', now)
      .where('isActive', '==', true)
      .limit(200)
      .get();

    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((d) =>
      batch.update(d.ref, { isActive: false, status: 'expired' })
    );
    await batch.commit();
    console.log(`[CourierCall] Expired ${snap.size} calls.`);
  }
);

// ============================================================================
// FIRESTORE TRIGGER — react to every status change on orders-food
// ============================================================================

export const onFoodOrderStatusChange = onDocumentUpdated(
  {
    document: 'orders-food/{orderId}',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Nothing to do if status hasn't changed
    if (before.status === after.status) return;

    const orderId  = event.params.orderId;
    const newStatus = after.status;

    const db = admin.firestore();

    // NOTE: the "order_ready" broadcast to the food_couriers FCM topic has
    // been removed. Auto-assignment (CF-54) handles dispatch directly and
    // writes a targeted in-app notification (via CF-40 → users/{uid}/
    // notifications → CF-46 FCM fan-out) for the assigned courier.
    // The only broadcast-style notification that remains in this module is
    // the restaurant-initiated courier call and the "heads up" button.

    // ── Order ended → deactivate any lingering heads-up notifications ───
    const terminalStatuses = [
      'assigned',
      'out_for_delivery',
      'delivered',
      'cancelled',
      'rejected',
    ];
    if (terminalStatuses.includes(newStatus)) {
      try {
        await deactivateCourierNotification(db, orderId);
      } catch (err) {
        console.error('[CourierNotif] Failed to deactivate notification:', err);
      }
    }
  },
);

// ============================================================================
// CALLABLE — Restaurant triggers "Inform Courier" (heads-up)
// ============================================================================

export const informFoodCourier = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 20,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { orderId } = request.data;
    if (!orderId || typeof orderId !== 'string') {
      throw new HttpsError('invalid-argument', 'orderId is required.');
    }

    const db     = admin.firestore();
    const uid    = request.auth.uid;
    const claims = request.auth.token;

    // ── 1. Fetch the order ──────────────────────────────────────────────
    const orderRef  = db.collection('orders-food').doc(orderId);
    const orderSnap = await orderRef.get();

    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'Order not found.');
    }

    const order = orderSnap.data();

    // ── 2. Authorisation — caller must belong to this restaurant ────────
    const restaurantClaims = claims.restaurants || {};
    if (!(order.restaurantId in restaurantClaims)) {
      throw new HttpsError('permission-denied', 'Not authorised for this restaurant.');
    }

    // ── 3. Order must be in accepted or preparing state ─────────────────
    if (!['accepted', 'preparing'].includes(order.status)) {
      throw new HttpsError(
        'failed-precondition',
        `Cannot inform courier when order is "${order.status}".`
      );
    }

    // ── 4. Cooldown check — prevent spam (5 min between calls) ──────────
    if (order.lastInformedAt) {
      const lastInformedMs = order.lastInformedAt.toDate().getTime();
      const msSinceLastInform = Date.now() - lastInformedMs;
      if (msSinceLastInform < INFORM_COOLDOWN_MS) {
        const remainingSec = Math.ceil((INFORM_COOLDOWN_MS - msSinceLastInform) / 1000);
        throw new HttpsError(
          'resource-exhausted',
          `Please wait ${remainingSec} seconds before informing again.`
        );
      }
    }

    // ── 5. Create in-app notification + stamp cooldown ───────────────────
    const batch = db.batch();

    const notifRef = db.collection('food_courier_notifications').doc();
    batch.set(notifRef, buildNotifDoc(orderId, order, 'heads_up'));

    batch.update(orderRef, {
      lastInformedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // ── 6. FCM topic push ────────────────────────────────────────────────
    await sendFcmToTopic(order, orderId, 'heads_up');

    console.log(`[CourierNotif] heads_up sent for order ${orderId} by ${uid}`);
    return { success: true };
  },
);

// ============================================================================
// SCHEDULED — Clean up expired notifications (runs every 30 min)
// ============================================================================

export const cleanupExpiredCourierNotifications = onScheduleFn(
  {
    schedule: 'every 30 minutes',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async () => {
    const db  = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    const expiredSnap = await db
      .collection('food_courier_notifications')
      .where('expiresAt', '<', now)
      .where('isActive', '==', true)
      .limit(200)
      .get();

    if (expiredSnap.empty) {
      console.log('[CourierNotif] No expired notifications to clean up.');
      return;
    }

    // Batch delete in chunks of 500
    const CHUNK = 500;
    for (let i = 0; i < expiredSnap.docs.length; i += CHUNK) {
      const batch = db.batch();
      expiredSnap.docs.slice(i, i + CHUNK).forEach((doc) =>
        batch.update(doc.ref, { isActive: false })
      );
      await batch.commit();
    }

    console.log(`[CourierNotif] Deactivated ${expiredSnap.size} expired notifications.`);
  },
);

// ============================================================================
// HELPERS
// ============================================================================

function buildNotifDoc(orderId, order, type) {
  const ttlMs = type === 'order_ready' ? TTL_ORDER_READY_MS : TTL_HEADS_UP_MS;

  const deliveryCity   = order.deliveryAddress?.city || '';
  const deliveryRegion = order.deliveryAddress?.mainRegion || '';

  const restaurantName = order.restaurantName || '';
  const itemCount      = order.itemCount || 0;
  const totalPrice     = order.totalPrice || 0;
  const currency       = order.currency || 'TL';

  const messages = buildMessages(type, restaurantName, itemCount, totalPrice, currency);

  return {
    type,                        // 'order_ready' | 'heads_up'
    orderId,
    restaurantId: order.restaurantId,
    restaurantName,
    restaurantProfileImage: order.restaurantProfileImage || '',
    itemCount,
    totalPrice,
    currency,
    deliveryCity,
    deliveryRegion,
    message_en: messages.en,
    message_tr: messages.tr,
    isActive: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + ttlMs),
  };
}

async function deactivateCourierNotification(db, orderId) {
  // Query by orderId field (index needed: orderId ASC + isActive ASC)
  const snap = await db
    .collection('food_courier_notifications')
    .where('orderId', '==', orderId)
    .where('isActive', '==', true)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.update(doc.ref, { isActive: false }));
  await batch.commit();
}

async function sendFcmToTopic(order, orderId, type) {
  const restaurantName = order.restaurantName || '';
  const itemCount      = order.itemCount || 0;
  const totalPrice     = order.totalPrice || 0;
  const currency       = order.currency || 'TL';

  const messages = buildMessages(type, restaurantName, itemCount, totalPrice, currency);

  const message = {
    topic: FCM_TOPIC_ALL_COURIERS,

    // Notification payload (system tray — shown when app is in background/killed)
    notification: {
      title: messages.fcmTitle,
      body: messages.tr,       // default to Turkish; Flutter can localise
    },

    // Data payload (available in both foreground and background handlers)
    data: {
      type,
      orderId,
      restaurantId: order.restaurantId  || '',
      restaurantName: order.restaurantName || '',
      itemCount: String(itemCount),
      totalPrice: String(totalPrice),
      currency,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },

    // Android — high priority to wake screen
    android: {
      priority: 'high',
      notification: {
        channelId: FCM_CHANNEL_ID,
        sound: 'order_alert',   // put order_alert.mp3 in res/raw/
        priority: 'max',
        visibility: 'public',
      },
    },

    // iOS
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          'sound': 'order_alert.caf',
          'badge': 1,
          'content-available': 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().send(message);
    console.log(`[CourierNotif] FCM ${type} sent, messageId: ${response}`);
  } catch (err) {
    // FCM failure must NOT fail the Cloud Function — notification is already in Firestore
    console.error('[CourierNotif] FCM send failed (non-fatal):', err.message);
  }
}

function buildMessages(type, restaurantName, itemCount, totalPrice, currency) {
  if (type === 'order_ready') {
    return {
      fcmTitle: '📦 Yeni Sipariş Hazır',
      en: `${restaurantName} — ${itemCount} item(s), ${totalPrice} ${currency}. Ready for pickup!`,
      tr: `${restaurantName} — ${itemCount} ürün, ${totalPrice} ${currency}. Teslimata hazır!`,
    };
  }
  // heads_up
  return {
    fcmTitle: '⏳ Sipariş Neredeyse Hazır',
    en: `${restaurantName} — ${itemCount} item(s) almost ready. Heading to restaurant soon?`,
    tr: `${restaurantName} — ${itemCount} ürün neredeyse hazır. Restorana gidebilirsiniz!`,
  };
}

// Auto-assignment (CF-54) now handles market-order dispatch directly. The
// previous onMarketOrderCreated / onMarketOrderStatusChangeDeactivate triggers
// broadcast to the food_couriers FCM topic for the pool UI, which has been
// removed — targeted in-app notifications are written via CF-40 on assignment.
