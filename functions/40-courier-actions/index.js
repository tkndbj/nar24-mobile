// 40-courier-actions/index.js
//
// Couriers write a document to `courier_actions` instead of calling
// httpsCallables. This Firestore trigger picks the doc up and performs
// the order state transition atomically.
//
// Benefits:
//  - Firestore offline persistence queues the write if the courier is offline
//  - When connectivity returns, the write syncs and this trigger fires
//  - No partial states — everything happens atomically server-side
//  - Idempotent — reprocessing a completed action is a no-op
//
// Supported action types (3-step courier flow):
//   'assign'  — pool → assigned         (ready/pending → assigned; sets cargo* fields)
//   'pickup'  — assigned → out_for_delivery   ("Teslim Aldım" button)
//   'deliver' — out_for_delivery → delivered  ("Teslim Edildi" button)
//
// Each action doc includes `collection` ∈ {'orders-food', 'orders-market'}.
// For backward compatibility, a missing collection defaults to 'orders-food'.

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

const VALID_COLLECTIONS = new Set(['orders-food', 'orders-market']);

function resolveCollection(actionData) {
  const col = actionData.collection || 'orders-food';
  if (!VALID_COLLECTIONS.has(col)) return null;
  return col;
}

export const processCourierAction = onDocumentCreated(
  {
    document: 'courier_actions/{actionId}',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (event) => {
    const actionData = event.data.data();
    const actionId = event.params.actionId;
    const db = admin.firestore();
    const actionRef = db.collection('courier_actions').doc(actionId);

    try {
      const { type, orderId, courierId } = actionData;

      if (!type || !orderId || !courierId) {
        await actionRef.update({
          status: 'failed',
          error: 'Missing required fields',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const collection = resolveCollection(actionData);
      if (!collection) {
        await actionRef.update({
          status: 'failed',
          error: `Invalid collection: ${actionData.collection}`,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      if (type === 'assign') {
        await processAssign(db, actionRef, actionData, collection);
      } else if (type === 'pickup') {
        await processPickup(db, actionRef, actionData, collection);
      } else if (type === 'deliver') {
        await processDelivery(db, actionRef, actionData, collection);
      } else {
        await actionRef.update({
          status: 'failed',
          error: `Unknown action type: ${type}`,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (error) {
      console.error(`[CourierAction] Error processing ${actionId}:`, error);
      await actionRef.update({
        status: 'failed',
        error: error.message || 'Unknown error',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {});
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// ASSIGN — pool → assigned
//   food:   ready   → assigned
//   market: pending → assigned
// ─────────────────────────────────────────────────────────────────────────────

async function processAssign(db, actionRef, actionData, collection) {
  const { orderId, courierId, courierName } = actionData;
  const poolStatus = collection === 'orders-food' ? 'ready' : 'pending';

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Assign ${orderId} already completed — skipping`);
      return;
    }

    const orderRef = db.collection(collection).doc(orderId);
    const orderSnap = await tx.get(orderRef);

    if (!orderSnap.exists) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Order not found',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const order = orderSnap.data();

    // Idempotent: if this same courier already assigned to it, treat as success
    if (order.status === 'assigned' && order.cargoUserId === courierId) {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already assigned to this courier',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.status !== poolStatus) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'already_taken',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.cargoUserId && order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'already_taken',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    tx.update(orderRef, {
      status: 'assigned',
      cargoUserId: courierId,
      cargoName: courierName || 'Courier',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(`[CourierAction] Assign completed: ${collection}/${orderId}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKUP — assigned → out_for_delivery
// ─────────────────────────────────────────────────────────────────────────────

async function processPickup(db, actionRef, actionData, collection) {
  const { orderId, courierId } = actionData;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Pickup ${orderId} already completed — skipping`);
      return;
    }

    const orderRef = db.collection(collection).doc(orderId);
    const orderSnap = await tx.get(orderRef);

    if (!orderSnap.exists) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Order not found',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const order = orderSnap.data();

    // Idempotent — already picked up
    if (order.status === 'out_for_delivery') {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already picked up',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.status !== 'assigned') {
      tx.update(actionRef, {
        status: 'failed',
        error: `Cannot pick up: order status is "${order.status}"`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Courier not assigned to this order',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    tx.update(orderRef, {
      status: 'out_for_delivery',
      pickedUpAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(`[CourierAction] Pickup completed: ${collection}/${orderId}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERY — out_for_delivery → delivered
// ─────────────────────────────────────────────────────────────────────────────

async function processDelivery(db, actionRef, actionData, collection) {
  const { orderId, courierId, paymentMethod } = actionData;
  const isMarket = collection === 'orders-market';

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Delivery ${orderId} already completed — skipping`);
      return;
    }

    const orderRef = db.collection(collection).doc(orderId);
    const orderSnap = await tx.get(orderRef);

    if (!orderSnap.exists) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Order not found',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const order = orderSnap.data();

    // Already delivered — idempotent
    if (order.status === 'delivered') {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already delivered',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.status !== 'out_for_delivery') {
      tx.update(actionRef, {
        status: 'failed',
        error: `Cannot deliver: order status is "${order.status}"`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Courier not assigned to this order',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    tx.update(orderRef, {
      status: 'delivered',
      needsReview: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(paymentMethod ? { paymentReceivedMethod: paymentMethod } : {}),
    });

    // Notify buyer (if exists)
    if (order.buyerId) {
      const notifRef = db
        .collection('users')
        .doc(order.buyerId)
        .collection('notifications')
        .doc();

      tx.set(notifRef, {
        type: isMarket ? 'market_order_delivered_review' : 'food_order_delivered_review',
        payload: {
          orderId,
          orderStatus: 'delivered',
          previousStatus: 'out_for_delivery',
          ...(isMarket ? {} : {
                restaurantId: order.restaurantId,
                restaurantName: order.restaurantName,
              }),
        },
        isRead: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(`[CourierAction] Delivery completed: ${collection}/${orderId}`);
}
