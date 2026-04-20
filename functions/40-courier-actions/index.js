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
// Supported action types:
//   'assign'    — pool/accepted → assigned        (sets cargo* fields)
//   'pickup'    — assigned → out_for_delivery      ("Teslim Aldım" button)
//   'deliver'   — out_for_delivery → delivered     ("Teslim Edildi" button)
//   'unassign'  — assigned → (accepted|pending)    used by the auto-
//                 assignment rebalancer and by the master panel.
//                 Master-assigned orders can only be unassigned when the
//                 action carries `unassignedBy: 'master'`; any other
//                 caller is rejected with `master_locked`. When the
//                 master unassigns, `unassignedBy: 'master'` is mirrored
//                 onto the order so the auto-assigner leaves it alone
//                 until a new assign lands (which clears the stamp).
//
// Each action doc includes `collection` ∈ {'orders-food', 'orders-market'}.
// For backward compatibility, a missing collection defaults to 'orders-food'.

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import { getRedisClient } from '../shared/redis.js';

const REGION = 'europe-west3';

// ── Redis helpers (fire-and-forget — never fail the Firestore transaction) ──
// Load counter and rolling-assignment ZSET feed the auto-assignment fairness
// scoring. If Redis is unavailable we log and continue: the order has already
// been transitioned in Firestore, and the scheduled retry/rebalancer will
// eventually correct the index state on the next heartbeat.

async function redisIncrLoad(courierId, delta) {
  try {
    const pipeline = getRedisClient().pipeline();
    pipeline.hincrby(`courier:${courierId}`, 'load', delta);
    // Clamp to zero in case of races (HINCRBY can go negative under bugs).
    pipeline.eval(
      'local v=redis.call(\'HGET\', KEYS[1], \'load\') if v and tonumber(v) < 0 then redis.call(\'HSET\', KEYS[1], \'load\', 0) end return 1',
      1,
      `courier:${courierId}`,
    );
    await pipeline.exec();
  } catch (err) {
    console.warn('[CourierAction] Redis load update failed (non-fatal):', err.message);
  }
}

async function redisRecordAssign(courierId, orderId) {
  try {
    const now = Date.now();
    const pipeline = getRedisClient().pipeline();
    pipeline.zadd(`courier:${courierId}:assigns`, 'NX', now, orderId);
    // Trim window to 30 min so ZCOUNT stays bounded.
    pipeline.zremrangebyscore(
      `courier:${courierId}:assigns`,
      '-inf',
      now - 30 * 60 * 1000,
    );
    pipeline.expire(`courier:${courierId}:assigns`, 2 * 60 * 60);
    await pipeline.exec();
  } catch (err) {
    console.warn('[CourierAction] Redis assigns ZADD failed (non-fatal):', err.message);
  }
}

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
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
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
      } else if (type === 'unassign') {
        await processUnassign(db, actionRef, actionData, collection);
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
// ASSIGN — dispatch → assigned
//   food:   accepted → assigned   (auto) | ready → assigned (legacy self/master)
//   market: pending  → assigned
//
// Allowed source statuses depend on `assignedBy`:
//   'auto'              — food must be 'accepted' (auto-dispatch trigger)
//   'master' / 'self'   — food must be 'ready'    (master-courier / legacy)
// For market, source is always 'pending' regardless of assignedBy.
// ─────────────────────────────────────────────────────────────────────────────

function allowedSourceStatus(collection, assignedBy) {
  if (collection === 'orders-market') return ['pending'];
  // orders-food
  if (assignedBy === 'auto') return ['accepted'];
  return ['ready', 'accepted']; // master/self accept either ready or accepted
}

async function processAssign(db, actionRef, actionData, collection) {
  const {
    orderId,
    courierId,
    courierName,
    assignedBy,
    suppressNotification,
    reassignHop,
  } = actionData;

  const allowed = allowedSourceStatus(collection, assignedBy);
  let didAssign = false;

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

    if (order.status === 'assigned' && order.cargoUserId === courierId) {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already assigned to this courier',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    // Auto-assigner must never override a master-assigned order.
    if (assignedBy === 'auto' && order.assignedBy === 'master') {
      tx.update(actionRef, {
        status: 'failed',
        error: 'master_locked',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!allowed.includes(order.status)) {
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

    const orderUpdate = {
      status: 'assigned',
      cargoUserId: courierId,
      cargoName: courierName || 'Courier',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      assignedBy: assignedBy || 'self',
      // Any fresh assign cancels a prior master-unassign stamp — the
      // order is live again, auto-assigner & rebalancer can act as usual
      // (subject to the assignedBy:'master' lock for master assigns).
      unassignedBy: admin.firestore.FieldValue.delete(),
    };

    // Only auto-assigned orders are eligible for rebalance. Master-assigned
    // orders are immutable; self-assigned orders (legacy/manual path) commit
    // on first pickup.
    if (assignedBy === 'auto') {
      orderUpdate.canReassign = true;
      if (typeof reassignHop === 'number') {
        orderUpdate.reassignHops = reassignHop;
      }
    } else {
      orderUpdate.canReassign = false;
    }

    tx.update(orderRef, orderUpdate);

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify the courier on initial dispatch (both master- and auto-assigned),
    // skipping the silent-rebalance path that sets suppressNotification.
    const shouldNotify =
      (assignedBy === 'master' || assignedBy === 'auto') &&
      suppressNotification !== true;

    if (shouldNotify) {
      const courierNotifRef = db
        .collection('users')
        .doc(courierId)
        .collection('notifications')
        .doc();

      tx.set(courierNotifRef, {
        type: 'order_assigned',
        payload: {
          orderId,
          collection,
          restaurantName: order.restaurantName || order.marketName || 'Order',
          itemCount: order.itemCount || 0,
          totalPrice: order.totalPrice || 0,
          currency: order.currency || 'TL',
          isMarket: collection === 'orders-market',
          assignedBy,
        },
        isRead: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    didAssign = true;
  });

  if (didAssign) {
    // Fire-and-forget Redis index updates (outside transaction by design —
    // Firestore TX cannot include external IO).
    await Promise.all([
      redisIncrLoad(courierId, +1),
      redisRecordAssign(courierId, orderId),
    ]);
  }

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

    // ── Notify buyer that their order is on the way ────────────────────
if (order.buyerId) {
  const isMarket = collection === 'orders-market';
  const notifRef = db
    .collection('users')
    .doc(order.buyerId)
    .collection('notifications')
    .doc();

  tx.set(notifRef, {
    type: isMarket ? 'market_order_status_update' : 'food_order_status_update',
    payload: {
      orderId,
      orderStatus: 'out_for_delivery',
      previousStatus: 'assigned',
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

  console.log(`[CourierAction] Pickup completed: ${collection}/${orderId}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERY — out_for_delivery → delivered
// ─────────────────────────────────────────────────────────────────────────────

async function processDelivery(db, actionRef, actionData, collection) {
  const { orderId, courierId, paymentMethod } = actionData;
  const isMarket = collection === 'orders-market';
  let didDeliver = false;

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
      canReassign: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(paymentMethod ? { paymentReceivedMethod: paymentMethod } : {}),
    });
    didDeliver = true;

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

  if (didDeliver) {
    await redisIncrLoad(courierId, -1);
  }

  console.log(`[CourierAction] Delivery completed: ${collection}/${orderId}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// UNASSIGN — assigned → accepted (food) / pending (market)
//
// Two callers:
//   • auto-assignment rebalancer (silent, for fairness re-routing)
//   • master panel (explicit operator pull-back via unassignedBy:'master')
//
// A master-assigned order can only be unassigned when the action itself
// carries `unassignedBy: 'master'`; the rebalancer is blocked on those.
// When the master unassigns, `unassignedBy: 'master'` is mirrored onto the
// order so the auto-assigner skips it until the master re-assigns (or
// otherwise clears the stamp). Decrements the previous courier's load
// counter so the follow-up assign doesn't double-count them.
// ─────────────────────────────────────────────────────────────────────────────

async function processUnassign(db, actionRef, actionData, collection) {
  const { orderId, courierId, reason, unassignedBy } = actionData;
  const revertStatus = collection === 'orders-food' ? 'accepted' : 'pending';
  let didUnassign = false;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      console.log(`[CourierAction] Unassign ${orderId} already completed — skipping`);
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

    // Master-assigned orders are immutable to non-master callers. The
    // master panel overrides this by sending `unassignedBy: 'master'`.
    if (order.assignedBy === 'master' && unassignedBy !== 'master') {
      tx.update(actionRef, {
        status: 'failed',
        error: 'master_locked',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.status !== 'assigned') {
      tx.update(actionRef, {
        status: 'failed',
        error: `cannot_unassign_from_${order.status}`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'courier_mismatch',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    tx.update(orderRef, {
      status: revertStatus,
      cargoUserId: null,
      cargoName: null,
      assignedAt: null,
      assignedBy: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(reason ? { lastUnassignReason: reason } : {}),
      // Only the master path stamps this — rebalancer unassigns must
      // stay auto-assignable on the next tick.
      ...(unassignedBy === 'master' ? { unassignedBy: 'master' } : {}),
    });

    tx.update(actionRef, {
      status: 'completed',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    didUnassign = true;
  });

  if (didUnassign) {
    await redisIncrLoad(courierId, -1);
  }

  console.log(`[CourierAction] Unassign completed: ${collection}/${orderId}`);
}
