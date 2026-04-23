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
import { logInfo, logWarn, logError, startTimer } from '../shared/logger.js';

const REGION = 'europe-west3';
const COMPONENT = 'courier_action';

// ── Redis helpers (fire-and-forget — never fail the Firestore transaction) ──
// Load counter and rolling-assignment ZSET feed the auto-assignment fairness
// scoring. If Redis is unavailable we log and continue: the order has already
// been transitioned in Firestore, and the scheduled retry/rebalancer will
// eventually correct the index state on the next heartbeat.

async function redisIncrLoad(courierId, delta, dispatchId) {
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
    logWarn({
      component: COMPONENT,
      event: 'redis.load_update_failed',
      courierId,
      dispatchId,
      delta,
      reason: 'redis_error',
      message: err.message,
    });
  }
}

async function redisRecordAssign(courierId, orderId, dispatchId) {
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
    logWarn({
      component: COMPONENT,
      event: 'redis.zadd_failed',
      courierId,
      orderId,
      dispatchId,
      reason: 'redis_error',
      message: err.message,
    });
  }
}

const VALID_COLLECTIONS = new Set(['orders-food', 'orders-market']);

function resolveCollection(actionData) {
  const col = actionData.collection || 'orders-food';
  if (!VALID_COLLECTIONS.has(col)) return null;
  return col;
}

// ── Rate limit ────────────────────────────────────────────────────────────
// Per-courier sliding window to cap damage from a buggy / hostile client.
// Only applies to courier-initiated actions; system-generated assigns
// (auto-dispatcher, master panel, rebalancer) are already bounded by their
// producer and can legitimately burst (e.g. a shift starting + 3 rapid
// auto-dispatches to the same courier).
//
// Window: 60 s. Limit: 30 actions. A legitimate courier doing 3 orders in
// rapid succession uses ~6 actions (assign ack + pickup + deliver × 3) — far
// below the ceiling. A retry-storm client trips at 30 and all further
// writes fast-fail in ~5 ms with no transaction / notification cost.

const RATE_LIMIT_WINDOW_SEC = 60;
const RATE_LIMIT_MAX_ACTIONS = 30;

function shouldRateLimit(actionData) {
  if (actionData.assignedBy === 'auto') return false;
  if (actionData.assignedBy === 'master') return false;
  if (actionData.unassignedBy === 'master') return false;
  return true;
}

async function checkCourierRateLimit(courierId) {
  try {
    const redis = getRedisClient();
    const key = `rate:courier:${courierId}`;
    const count = await redis.incr(key);
    if (count === 1) {
      // First action in window — stamp TTL so the counter self-expires.
      await redis.expire(key, RATE_LIMIT_WINDOW_SEC);
    }
    return { ok: count <= RATE_LIMIT_MAX_ACTIONS, count };
  } catch (err) {
    // Redis outage: fail open. A short blip allowing through real traffic
    // is strictly safer than blocking every courier action.
    logWarn({
      component: COMPONENT,
      event: 'rate_limit.check_failed',
      courierId,
      reason: 'redis_error',
      message: err.message,
    });
    return { ok: true, count: 0 };
  }
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
    const dispatchId = actionData.dispatchId || null;
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
        logError({
          component: COMPONENT,
          event: 'action.invalid',
          actionId,
          dispatchId,
          reason: 'missing_fields',
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
        logError({
          component: COMPONENT,
          event: 'action.invalid',
          actionId,
          dispatchId,
          orderId,
          reason: 'invalid_collection',
          collectionInput: actionData.collection,
        });
        return;
      }

      if (shouldRateLimit(actionData)) {
        const rate = await checkCourierRateLimit(courierId);
        if (!rate.ok) {
          await actionRef.update({
            status: 'failed',
            error: 'rate_limited',
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          logWarn({
            component: COMPONENT,
            event: 'action.rate_limited',
            actionId,
            dispatchId,
            type,
            orderId,
            collection,
            courierId,
            count: rate.count,
            limit: RATE_LIMIT_MAX_ACTIONS,
            windowSec: RATE_LIMIT_WINDOW_SEC,
          });
          return;
        }
      }

      logInfo({
        component: COMPONENT,
        event: 'action.received',
        actionId,
        dispatchId,
        type,
        orderId,
        collection,
        courierId,
        assignedBy: actionData.assignedBy || null,
      });

      if (type === 'assign') {
        await processAssign(db, actionRef, actionData, collection, actionId);
      } else if (type === 'pickup') {
        await processPickup(db, actionRef, actionData, collection, actionId);
      } else if (type === 'deliver') {
        await processDelivery(db, actionRef, actionData, collection, actionId);
      } else if (type === 'unassign') {
        await processUnassign(db, actionRef, actionData, collection, actionId);
      } else {
        await actionRef.update({
          status: 'failed',
          error: `Unknown action type: ${type}`,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logError({
          component: COMPONENT,
          event: 'action.invalid',
          actionId,
          dispatchId,
          orderId,
          type,
          reason: 'unknown_type',
        });
      }
    } catch (error) {
      logError({
        component: COMPONENT,
        event: 'action.exception',
        actionId,
        dispatchId,
        reason: 'exception',
        message: error.message,
        stack: error.stack,
      });
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

async function processAssign(db, actionRef, actionData, collection, actionId) {
  const {
    orderId,
    courierId,
    courierName,
    assignedBy,
    suppressNotification,
    reassignHop,
  } = actionData;
  const dispatchId = actionData.dispatchId || null;
  const stop = startTimer();

  const allowed = allowedSourceStatus(collection, assignedBy);
  let didAssign = false;
  // For the auto path, the dispatcher (CF-54 selectCandidate) has already
  // pre-reserved +1 on this courier's load. This function owns that
  // reservation: on success we let it stand (skip the usual +1 bump), on
  // any failure branch we release it (-1). A null outcome means no Redis
  // change is needed — either this is the master/self path, or a prior
  // CF-40 invocation already settled the reservation.
  const isAutoPath = assignedBy === 'auto';
  let reservationOutcome = null; // 'commit' | 'release' | null (noop)
  let terminalEvent = null; // {event, severity, reason?}

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      reservationOutcome = null; // noop — prior invocation already handled it
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_completed' };
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
      reservationOutcome = isAutoPath ? 'release' : null;
      terminalEvent = { event: 'action.failed', severity: 'warn', reason: 'order_not_found' };
      return;
    }

    const order = orderSnap.data();

    if (order.status === 'assigned' && order.cargoUserId === courierId) {
      tx.update(actionRef, {
        status: 'completed',
        note: 'Order was already assigned to this courier',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      // Rare: duplicate auto dispatch that lost the race but picked the
      // same courier. Load was counted by the winning dispatch — release
      // this one.
      reservationOutcome = isAutoPath ? 'release' : null;
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_assigned_to_same_courier' };
      return;
    }

   // Master cannot assign a courier to an order where the restaurant chose
// their own courier. Defense-in-depth: the admin UI blocks this before
// writing the action doc, but we refuse at the CF layer too.
if (
  assignedBy === 'master' &&
  collection === 'orders-food' &&
  order.courierType === 'theirs'
) {
  tx.update(actionRef, {
    status: 'failed',
    error: 'restaurant_uses_own_courier',
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  // Master path doesn't pre-reserve, so nothing to release.
  reservationOutcome = null;
  terminalEvent = {
    event: 'action.failed',
    severity: 'warn',
    reason: 'restaurant_uses_own_courier',
  };
  return;
}

    if (!allowed.includes(order.status)) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'already_taken',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      reservationOutcome = isAutoPath ? 'release' : null;
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'wrong_status',
        observedStatus: order.status,
      };
      return;
    }

    if (order.cargoUserId && order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'already_taken',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      reservationOutcome = isAutoPath ? 'release' : null;
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'already_taken_by_other',
        observedCourierId: order.cargoUserId,
      };
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
    reservationOutcome = 'commit';
    terminalEvent = { event: 'action.completed', severity: 'info' };
  });

  if (didAssign) {
    // Fire-and-forget Redis index updates (outside transaction by design —
    // Firestore TX cannot include external IO).
    //
    // Auto path: the dispatcher already reserved +1, so only record the
    // rotation ZSET entry. Master/self path: bump +1 as before.
    const updates = [redisRecordAssign(courierId, orderId, dispatchId)];
    if (!isAutoPath) {
      updates.push(redisIncrLoad(courierId, +1, dispatchId));
    }
    await Promise.all(updates);
  } else if (reservationOutcome === 'release') {
    // Auto-path failure: release the pre-reservation made by selectCandidate
    // so the load counter doesn't drift upward.
    await redisIncrLoad(courierId, -1, dispatchId);
  }

  const latencyMs = stop();
  const base = {
    component: COMPONENT,
    actionId,
    dispatchId,
    type: 'assign',
    orderId,
    collection,
    courierId,
    assignedBy: assignedBy || null,
    reservationOutcome,
    latencyMs,
  };
  if (terminalEvent) {
    const payload = { ...base, event: terminalEvent.event };
    if (terminalEvent.reason) payload.reason = terminalEvent.reason;
    if (terminalEvent.observedStatus) payload.observedStatus = terminalEvent.observedStatus;
    if (terminalEvent.observedCourierId) payload.observedCourierId = terminalEvent.observedCourierId;
    if (terminalEvent.severity === 'warn') logWarn(payload);
    else logInfo(payload);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKUP — assigned → out_for_delivery
// ─────────────────────────────────────────────────────────────────────────────

async function processPickup(db, actionRef, actionData, collection, actionId) {
  const { orderId, courierId } = actionData;
  const dispatchId = actionData.dispatchId || null;
  const stop = startTimer();
  let terminalEvent = null;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_completed' };
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
      terminalEvent = { event: 'action.failed', severity: 'warn', reason: 'order_not_found' };
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
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_picked_up' };
      return;
    }

    if (order.status !== 'assigned') {
      tx.update(actionRef, {
        status: 'failed',
        error: `Cannot pick up: order status is "${order.status}"`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'wrong_status',
        observedStatus: order.status,
      };
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Courier not assigned to this order',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'courier_mismatch',
        observedCourierId: order.cargoUserId || null,
      };
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
    terminalEvent = { event: 'action.completed', severity: 'info' };
  });

  const latencyMs = stop();
  const base = {
    component: COMPONENT,
    actionId,
    dispatchId,
    type: 'pickup',
    orderId,
    collection,
    courierId,
    latencyMs,
  };
  if (terminalEvent) {
    const payload = { ...base, event: terminalEvent.event };
    if (terminalEvent.reason) payload.reason = terminalEvent.reason;
    if (terminalEvent.observedStatus) payload.observedStatus = terminalEvent.observedStatus;
    if (terminalEvent.observedCourierId) payload.observedCourierId = terminalEvent.observedCourierId;
    if (terminalEvent.severity === 'warn') logWarn(payload);
    else logInfo(payload);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERY — out_for_delivery → delivered
// ─────────────────────────────────────────────────────────────────────────────

async function processDelivery(db, actionRef, actionData, collection, actionId) {
  const { orderId, courierId, paymentMethod } = actionData;
  const dispatchId = actionData.dispatchId || null;
  const isMarket = collection === 'orders-market';
  const stop = startTimer();
  let didDeliver = false;
  let terminalEvent = null;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_completed' };
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
      terminalEvent = { event: 'action.failed', severity: 'warn', reason: 'order_not_found' };
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
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_delivered' };
      return;
    }

    if (order.status !== 'out_for_delivery') {
      tx.update(actionRef, {
        status: 'failed',
        error: `Cannot deliver: order status is "${order.status}"`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'wrong_status',
        observedStatus: order.status,
      };
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'Courier not assigned to this order',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'courier_mismatch',
        observedCourierId: order.cargoUserId || null,
      };
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
    terminalEvent = { event: 'action.completed', severity: 'info' };
  });

  if (didDeliver) {
    await redisIncrLoad(courierId, -1, dispatchId);
  }

  const latencyMs = stop();
  const base = {
    component: COMPONENT,
    actionId,
    dispatchId,
    type: 'deliver',
    orderId,
    collection,
    courierId,
    latencyMs,
  };
  if (terminalEvent) {
    const payload = { ...base, event: terminalEvent.event };
    if (terminalEvent.reason) payload.reason = terminalEvent.reason;
    if (terminalEvent.observedStatus) payload.observedStatus = terminalEvent.observedStatus;
    if (terminalEvent.observedCourierId) payload.observedCourierId = terminalEvent.observedCourierId;
    if (terminalEvent.severity === 'warn') logWarn(payload);
    else logInfo(payload);
  }
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

async function processUnassign(db, actionRef, actionData, collection, actionId) {
  const { orderId, courierId, reason, unassignedBy } = actionData;
  const dispatchId = actionData.dispatchId || null;
  const revertStatus = collection === 'orders-food' ? 'accepted' : 'pending';
  const stop = startTimer();
  let didUnassign = false;
  let terminalEvent = null;

  await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.data().status === 'completed') {
      terminalEvent = { event: 'action.idempotent', severity: 'info', reason: 'already_completed' };
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
      terminalEvent = { event: 'action.failed', severity: 'warn', reason: 'order_not_found' };
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
      terminalEvent = { event: 'action.failed', severity: 'warn', reason: 'master_locked' };
      return;
    }

    if (order.status !== 'assigned') {
      tx.update(actionRef, {
        status: 'failed',
        error: `cannot_unassign_from_${order.status}`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: `cannot_unassign_from_${order.status}`,
        observedStatus: order.status,
      };
      return;
    }

    if (order.cargoUserId !== courierId) {
      tx.update(actionRef, {
        status: 'failed',
        error: 'courier_mismatch',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      terminalEvent = {
        event: 'action.failed',
        severity: 'warn',
        reason: 'courier_mismatch',
        observedCourierId: order.cargoUserId || null,
      };
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
    terminalEvent = { event: 'action.completed', severity: 'info' };
  });

  if (didUnassign) {
    await redisIncrLoad(courierId, -1, dispatchId);
  }

  const latencyMs = stop();
  const base = {
    component: COMPONENT,
    actionId,
    dispatchId,
    type: 'unassign',
    orderId,
    collection,
    courierId,
    unassignedBy: unassignedBy || null,
    unassignReason: reason || null,
    latencyMs,
  };
  if (terminalEvent) {
    const payload = { ...base, event: terminalEvent.event };
    if (terminalEvent.reason) payload.reason = terminalEvent.reason;
    if (terminalEvent.observedStatus) payload.observedStatus = terminalEvent.observedStatus;
    if (terminalEvent.observedCourierId) payload.observedCourierId = terminalEvent.observedCourierId;
    if (terminalEvent.severity === 'warn') logWarn(payload);
    else logInfo(payload);
  }
}
