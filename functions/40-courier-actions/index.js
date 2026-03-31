// 40-courier-actions/index.js
//
// Instead of couriers calling httpsCallable('updateFoodOrderStatus'),
// they write a document to `courier_actions`. This CF trigger picks it up
// and performs the state transition atomically.
//
// Benefits:
//  - Firestore offline persistence queues the write if the courier is offline
//  - When connectivity returns, the write syncs and this trigger fires
//  - No partial states — everything happens atomically server-side
//  - Idempotent — reprocessing a completed action is a no-op

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

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

      if (type === 'deliver') {
        await processDelivery(db, actionRef, actionData);
      } else if (type === 'pickup') {
        await processPickup(db, actionRef, actionData);
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
// DELIVERY
// ─────────────────────────────────────────────────────────────────────────────

async function processDelivery(db, actionRef, actionData) {
  const { orderId, courierId, paymentMethod } = actionData;

  await db.runTransaction(async (tx) => {
    // ── 1. Re-read the action to check idempotency ──────────────
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Delivery ${orderId} already completed — skipping`);
      return;
    }

    // ── 2. Validate order state ─────────────────────────────────
    const orderRef = db.collection('orders-food').doc(orderId);
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

    // ── 3. Atomically update order ──────────────────────────────
    tx.update(orderRef, {
      status: 'delivered',
      needsReview: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(paymentMethod ? { paymentReceivedMethod: paymentMethod } : {}),
    });

    // ── 4. Notify buyer (if exists) ─────────────────────────────
    if (order.buyerId) {
      const notifRef = db
        .collection('users')
        .doc(order.buyerId)
        .collection('notifications')
        .doc();

      tx.set(notifRef, {
        type: 'food_order_delivered_review',
        payload: {
          orderId,
          orderStatus: 'delivered',
          previousStatus: 'out_for_delivery',
          restaurantId: order.restaurantId,
          restaurantName: order.restaurantName,
        },
        isRead: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // ── 5. Mark action as completed ─────────────────────────────
    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(`[CourierAction] Delivery completed: ${orderId}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKUP
// ─────────────────────────────────────────────────────────────────────────────

async function processPickup(db, actionRef, actionData) {
  const { orderId, courierId } = actionData;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Pickup ${orderId} already completed — skipping`);
      return;
    }

    const orderRef = db.collection('orders-food').doc(orderId);
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

    // Already picked up — idempotent
    if (order.pickedUpFromRestaurant === true) {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already picked up',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.status !== 'out_for_delivery') {
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
      pickedUpFromRestaurant: true,
      pickedUpAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(`[CourierAction] Pickup completed: ${orderId}`);
}
