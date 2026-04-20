// 54-auto-assignment/index.js
//
// Auto-assigns food and market orders to the best available courier, removing
// the pool-based self-assignment model. Candidates are scored on proximity,
// current load, and recent-assignment rotation so the work is distributed
// fairly across the fleet.
//
// Data plane
// ─────────
//   Redis (Memorystore):
//     couriers:geo                GEO set   — online+on-shift couriers (uid, lng, lat)
//     courier:{uid}               HASH      — { load, isOnShift, vehicleType, lastSeen }
//     courier:{uid}:assigns       ZSET      — timestamp-scored order ids (30-min window)
//
//   Firestore:
//     orders-food / orders-market   status transitions and cargoUserId
//     courier_actions               atomic transitions via CF-40
//
// Event flow
// ─────────
//   1. Order trigger (food accepted / market created) → autoAssignOrder()
//   2. Redis GEOSEARCH + HGETALL + ZCOUNT → picks best candidate
//   3. Pre-reserves the winner's load (+1) atomically in Redis. Concurrent
//      dispatches (lunch rush) then see the updated counter and fan out
//      across couriers instead of piling onto whoever scored best at t=0.
//   4. Writes `courier_actions` doc with type:'assign', assignedBy:'auto'.
//      If any step between reservation and this write fails, the caller
//      releases the reservation (-1) so the counter doesn't drift.
//   5. CF-40 does the atomic state transition and pushes the in-app notif
//      (which fans out to FCM via CF-46). On auto-path success CF-40 does
//      NOT re-bump load (already reserved); on auto-path failure branches
//      (master_locked / already_taken / idempotent double-dispatch) it
//      releases the reservation itself.
//
//   Scheduled rebalancer (every 60 s):
//     scans `assigned + assignedBy:'auto' + canReassign:true` orders and
//     flips to a significantly-better candidate if one appeared. Never
//     touches `assignedBy:'master'`.
//
//   Scheduled retry (every 30 s):
//     picks up orders stuck without cargoUserId (Redis outage at dispatch
//     time, or no candidate in range earlier).
//
//   RTDB mirror:
//     `courier_locations/{uid}` (RTDB) → Redis GEO + HASH.

import { onDocumentUpdated, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onValueWritten } from 'firebase-functions/v2/database';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { getRedisClient } from '../shared/redis.js';
import { logInfo, logWarn, logError, newDispatchId, startTimer } from '../shared/logger.js';

const COMPONENT = 'auto_assign';

const REGION = 'europe-west3';
const RTDB_REGION = 'europe-west1'; // Firebase RTDB location for this project

// ── Tuning constants ────────────────────────────────────────────────────────
// Food dispatches go out from many restaurants (spread across the delivery
// zone), so a tight 25 km ceiling keeps the pool relevant. Market dispatches
// all originate from a single central warehouse, so the furthest ring must
// cover the whole service area — otherwise couriers working the far side of
// the island are permanently unreachable. Scoring still penalises distance,
// so far-away couriers only win when no one closer is free.
const RADIUS_TIERS_KM_FOOD   = [5, 10, 25];
const RADIUS_TIERS_KM_MARKET = [10, 25, 75];
const RADIUS_TIERS_BY_COLLECTION = {
  'orders-food': RADIUS_TIERS_KM_FOOD,
  'orders-market': RADIUS_TIERS_KM_MARKET,
};
const CANDIDATE_LIMIT    = 20;            // top-N per GEOSEARCH
const SOFT_LOAD_REF      = 3;             // load beyond this costs more
const W_DISTANCE         = 1.0;           // km → score
const W_LOAD             = 1.5;           // each active order
const W_ROTATION         = 0.8;           // each recent assign in last 30m
const ROTATION_WINDOW_MS = 30 * 60 * 1000;
const REBALANCE_MIN_DELTA        = 1.5;   // absolute score improvement required
const REBALANCE_MIN_RATIO        = 0.75;  // new must also be ≤ old × 0.75
const REBALANCE_COMMIT_RADIUS_KM = 0.5;   // courier already near pickup → lock
const REBALANCE_MAX_HOPS         = 2;
const STALE_UNASSIGNED_MS = 30 * 1000;    // retry threshold
const COURIER_STALE_MS    = 2 * 60 * 1000; // drop from index if no heartbeat

const VALID_COLLECTIONS = new Set(['orders-food', 'orders-market']);

function pickupCoordsFor(order, collection) {
  if (collection === 'orders-food') {
    const lat = order.restaurantLat;
    const lng = order.restaurantLng;
    if (typeof lat === 'number' && typeof lng === 'number') return { lat, lng };
    return null;
  }
  // orders-market
  const lat = order.marketLat;
  const lng = order.marketLng;
  if (typeof lat === 'number' && typeof lng === 'number') return { lat, lng };
  return null;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// ─────────────────────────────────────────────────────────────────────────────
// Optimistic load reservation
//
// selectCandidate bumps the winning courier's `load` BEFORE returning, so
// concurrent dispatches observe the updated state and score a different
// courier best. Without this, N parallel triggers reading load=0 for the
// same courier all assign to them (the classic dispatch race).
//
// The CALLER owns the reservation until committed:
//   • autoAssignOrder + autoAssignRebalance must call releaseReservation
//     if any step between selectCandidate and the courier_actions write
//     fails.
//   • CF-40 processAssign skips the usual +1 on success for auto-path
//     (already reserved) and releases -1 on its own failure branches.
// ─────────────────────────────────────────────────────────────────────────────

async function reserveCourier(courierId, dispatchId) {
  try {
    await getRedisClient().hincrby(`courier:${courierId}`, 'load', 1);
    logInfo({ component: COMPONENT, event: 'reservation.reserved', courierId, dispatchId });
  } catch (err) {
    // Degraded mode: race still possible but dispatch itself continues.
    logWarn({
      component: COMPONENT,
      event: 'reservation.reserve_failed',
      courierId,
      dispatchId,
      reason: 'redis_error',
      message: err.message,
    });
  }
}

async function releaseReservation(courierId, dispatchId) {
  try {
    const pipeline = getRedisClient().pipeline();
    pipeline.hincrby(`courier:${courierId}`, 'load', -1);
    // Clamp to zero — if a race left load negative, reset.
    pipeline.eval(
      'local v=redis.call(\'HGET\', KEYS[1], \'load\') if v and tonumber(v) < 0 then redis.call(\'HSET\', KEYS[1], \'load\', 0) end return 1',
      1,
      `courier:${courierId}`,
    );
    await pipeline.exec();
    logInfo({ component: COMPONENT, event: 'reservation.released', courierId, dispatchId });
  } catch (err) {
    logWarn({
      component: COMPONENT,
      event: 'reservation.release_failed',
      courierId,
      dispatchId,
      reason: 'redis_error',
      message: err.message,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORE: pick best candidate from Redis
// ─────────────────────────────────────────────────────────────────────────────

async function selectCandidate({ pickupLat, pickupLng, collection, excludeUid = null, dispatchId }) {
  const redis = getRedisClient();
  const tiers = RADIUS_TIERS_BY_COLLECTION[collection] || RADIUS_TIERS_KM_FOOD;

  // Diagnostic: state of the geo index at dispatch time.
  let indexSize = null;
  try {
    indexSize = await redis.zcard('couriers:geo');
  } catch (err) {
    logWarn({
      component: COMPONENT,
      event: 'redis.zcard_failed',
      dispatchId,
      reason: 'redis_error',
      message: err.message,
    });
  }
  logInfo({
    component: COMPONENT,
    event: 'select.started',
    dispatchId,
    collection,
    pickupLat,
    pickupLng,
    indexSize,
    tiers,
  });

  // Progressive radius widening — small first so most dispatches stay cheap.
  for (const radius of tiers) {
    let rows;
    try {
      rows = await redis.geosearch(
        'couriers:geo',
        'FROMLONLAT', pickupLng, pickupLat,
        'BYRADIUS', radius, 'km',
        'ASC',
        'COUNT', CANDIDATE_LIMIT,
        'WITHCOORD',
        'WITHDIST',
      );
    } catch (err) {
      logError({
        component: COMPONENT,
        event: 'redis.geosearch_failed',
        dispatchId,
        collection,
        radius,
        reason: 'redis_error',
        message: err.message,
      });
      return null;
    }

    logInfo({
      component: COMPONENT,
      event: 'select.tier_scanned',
      dispatchId,
      collection,
      radius,
      rowCount: rows ? rows.length : 0,
    });
    if (!rows || rows.length === 0) continue;

    // rows: [[uid, distKmStr, [lngStr, latStr]], ...]
    const now = Date.now();
    const pipeline = redis.pipeline();
    const ordered = [];
    for (const row of rows) {
      const uid = row[0];
      if (excludeUid && uid === excludeUid) continue;
      const distKm = parseFloat(row[1]);
      const lng = parseFloat(row[2][0]);
      const lat = parseFloat(row[2][1]);
      ordered.push({ uid, distKm, lat, lng });
      pipeline.hgetall(`courier:${uid}`);
      pipeline.zcount(
        `courier:${uid}:assigns`,
        now - ROTATION_WINDOW_MS,
        '+inf',
      );
    }

    if (ordered.length === 0) continue;

    let results;
    try {
      results = await pipeline.exec();
    } catch (err) {
      logError({
        component: COMPONENT,
        event: 'redis.pipeline_failed',
        dispatchId,
        reason: 'redis_error',
        message: err.message,
      });
      return null;
    }

    let best = null;
    const rejects = [];
    for (let i = 0; i < ordered.length; i++) {
      const state = results[i * 2][1] || {};
      const recentAssigns = parseInt(results[i * 2 + 1][1] || '0', 10);

      const isOnShift = state.isOnShift === '1' || state.isOnShift === 'true';
      if (!isOnShift) {
        rejects.push({ courierId: ordered[i].uid, reason: 'off_shift' });
        continue;
      }

      const lastSeen = parseInt(state.lastSeen || '0', 10);
      if (lastSeen && now - lastSeen > COURIER_STALE_MS) {
        rejects.push({
          courierId: ordered[i].uid,
          reason: 'stale_heartbeat',
          staleSeconds: Math.round((now - lastSeen) / 1000),
        });
        continue;
      }

      const load = Math.max(0, parseInt(state.load || '0', 10));

      // Soft cap: beyond SOFT_LOAD_REF, each extra order costs more (not
      // forbidden — someone still has to take the order).
      const loadPenalty =
        load <= SOFT_LOAD_REF ?
          load * W_LOAD :
          SOFT_LOAD_REF * W_LOAD + (load - SOFT_LOAD_REF) * W_LOAD * 2;

      const c = ordered[i];
      const score =
        c.distKm * W_DISTANCE +
        loadPenalty +
        recentAssigns * W_ROTATION;

      if (!best || score < best.score) {
        best = { ...c, load, recentAssigns, score };
      }
    }

    if (rejects.length) {
      logInfo({
        component: COMPONENT,
        event: 'select.rejected_candidates',
        dispatchId,
        collection,
        radius,
        rejectCount: rejects.length,
        rejects,
      });
    }

    if (best) {
      // Pre-reserve load on the winner so concurrent dispatches route elsewhere.
      // Caller MUST releaseReservation on any failure between here and the
      // courier_actions doc being written.
      await reserveCourier(best.uid, dispatchId);
      return best;
    }
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORE: attempt to assign one order
// ─────────────────────────────────────────────────────────────────────────────

async function autoAssignOrder(db, orderId, collection, { source = 'trigger' } = {}) {
  const dispatchId = newDispatchId();
  const stop = startTimer();

  const emitSkip = (reason, extra = {}) => {
    logInfo({
      component: COMPONENT,
      event: 'dispatch.skipped',
      dispatchId,
      orderId,
      collection,
      source,
      reason,
      latencyMs: stop(),
      ...extra,
    });
  };

  if (!VALID_COLLECTIONS.has(collection)) {
    emitSkip('invalid_collection');
    return { ok: false, reason: 'invalid_collection', dispatchId };
  }

  const orderRef = db.collection(collection).doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    emitSkip('order_not_found');
    return { ok: false, reason: 'not_found', dispatchId };
  }
  const order = orderSnap.data();

  // Guardrails
  if (order.cargoUserId) {
    emitSkip('already_assigned');
    return { ok: false, reason: 'already_assigned', dispatchId };
  }
  if (order.assignedBy === 'master') {
    emitSkip('master_assigned');
    return { ok: false, reason: 'master_assigned', dispatchId };
  }
  // Master explicitly pulled this order back — hands off until the master
  // re-assigns (which clears the stamp in CF-40 processAssign).
  if (order.unassignedBy === 'master') {
    emitSkip('master_unassigned');
    return { ok: false, reason: 'master_unassigned', dispatchId };
  }

  const expectedStatus = collection === 'orders-food' ? 'accepted' : 'pending';
  if (order.status !== expectedStatus) {
    emitSkip('wrong_status', { orderStatus: order.status });
    return { ok: false, reason: `wrong_status:${order.status}`, dispatchId };
  }

  const pickup = pickupCoordsFor(order, collection);
  if (!pickup) {
    emitSkip('missing_pickup_coords');
    return { ok: false, reason: 'missing_pickup_coords', dispatchId };
  }

  const best = await selectCandidate({
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    collection,
    dispatchId,
  });

  if (!best) {
    logInfo({
      component: COMPONENT,
      event: 'dispatch.no_candidate',
      dispatchId,
      orderId,
      collection,
      source,
      latencyMs: stop(),
    });
    return { ok: false, reason: 'no_candidate', dispatchId };
  }

  // best.uid's load is reserved (+1) inside selectCandidate. Everything from
  // here until the courier_actions doc lands must either succeed (CF-40 owns
  // the reservation) or release on failure so the counter doesn't drift.
  let committed = false;
  try {
    const courierSnap = await db.collection('users').doc(best.uid).get();
    const courierName = courierSnap.exists ?
      courierSnap.data().displayName || courierSnap.data().fullName || 'Courier' :
      'Courier';

    const actionRef = db.collection('courier_actions').doc();
    await actionRef.set({
      type: 'assign',
      collection,
      orderId,
      courierId: best.uid,
      courierName,
      assignedBy: 'auto',
      status: 'pending',
      autoAssignScore: best.score,
      autoAssignDistanceKm: best.distKm,
      dispatchId, // threaded into CF-40 logs
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    committed = true;

    logInfo({
      component: COMPONENT,
      event: 'dispatch.dispatched',
      dispatchId,
      orderId,
      collection,
      source,
      courierId: best.uid,
      distKm: Number(best.distKm.toFixed(2)),
      load: best.load,
      recentAssigns: best.recentAssigns,
      score: Number(best.score.toFixed(2)),
      latencyMs: stop(),
    });

    return { ok: true, courierId: best.uid, score: best.score, dispatchId };
  } finally {
    if (!committed) await releaseReservation(best.uid, dispatchId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 1: food order transitions pending → accepted
// ─────────────────────────────────────────────────────────────────────────────

export const autoAssignOnFoodAccepted = onDocumentUpdated(
  {
    document: 'orders-food/{orderId}',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (after.status !== 'accepted') return;
    if (after.cargoUserId) return; // already taken (e.g. master override)
    if (after.unassignedBy === 'master') return; // master pulled it back

    const orderId = event.params.orderId;
    try {
      await autoAssignOrder(admin.firestore(), orderId, 'orders-food', { source: 'food_trigger' });
    } catch (err) {
      logError({
        component: COMPONENT,
        event: 'dispatch.trigger_failed',
        orderId,
        collection: 'orders-food',
        source: 'food_trigger',
        reason: 'exception',
        message: err.message,
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// TRIGGER 2: market order created
// ─────────────────────────────────────────────────────────────────────────────

export const autoAssignOnMarketCreated = onDocumentCreated(
  {
    document: 'orders-market/{orderId}',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (event) => {
    const order = event.data?.data();
    if (!order) return;
    if (order.status !== 'pending') return;
    if (order.cargoUserId) return;

    const orderId = event.params.orderId;
    try {
      await autoAssignOrder(admin.firestore(), orderId, 'orders-market', { source: 'market_trigger' });
    } catch (err) {
      logError({
        component: COMPONENT,
        event: 'dispatch.trigger_failed',
        orderId,
        collection: 'orders-market',
        source: 'market_trigger',
        reason: 'exception',
        message: err.message,
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// SCHEDULED: retry unassigned orders (Redis blip, no candidate earlier)
// ─────────────────────────────────────────────────────────────────────────────

export const autoAssignRetryUnassigned = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 120,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    const db = admin.firestore();
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - STALE_UNASSIGNED_MS,
    );

    const stale = [
      {
        coll: 'orders-food',
        status: 'accepted',
        snap: await db
          .collection('orders-food')
          .where('status', '==', 'accepted')
          .where('cargoUserId', '==', null)
          .where('updatedAt', '<', cutoff)
          .limit(50)
          .get()
          .catch((e) => {
            logWarn({
              component: COMPONENT,
              event: 'retry.query_failed',
              collection: 'orders-food',
              reason: 'firestore_error',
              message: e.message,
            });
            return { empty: true, docs: [] };
          }),
      },
      {
        coll: 'orders-market',
        status: 'pending',
        snap: await db
          .collection('orders-market')
          .where('status', '==', 'pending')
          .where('cargoUserId', '==', null)
          .where('createdAt', '<', cutoff)
          .limit(50)
          .get()
          .catch((e) => {
            logWarn({
              component: COMPONENT,
              event: 'retry.query_failed',
              collection: 'orders-market',
              reason: 'firestore_error',
              message: e.message,
            });
            return { empty: true, docs: [] };
          }),
      },
    ];

    let attempted = 0;
    let scanned = 0;
    for (const { coll, snap } of stale) {
      if (!snap || snap.empty) continue;
      for (const doc of snap.docs) {
        scanned++;
        const data = doc.data();
        if (data.assignedBy === 'master') continue;
        if (data.unassignedBy === 'master') continue; // master pulled it back
        try {
          const result = await autoAssignOrder(db, doc.id, coll, { source: 'retry' });
          if (result.ok) attempted++;
        } catch (err) {
          logError({
            component: COMPONENT,
            event: 'retry.order_failed',
            orderId: doc.id,
            collection: coll,
            reason: 'exception',
            message: err.message,
          });
        }
      }
    }

    logInfo({
      component: COMPONENT,
      event: 'retry.swept',
      scanned,
      dispatched: attempted,
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// SCHEDULED: rebalance hot orders if a better candidate emerged
// ─────────────────────────────────────────────────────────────────────────────

export const autoAssignRebalance = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 120,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    const db = admin.firestore();

    const [foodSnap, marketSnap] = await Promise.all([
      db
        .collection('orders-food')
        .where('status', '==', 'assigned')
        .where('assignedBy', '==', 'auto')
        .where('canReassign', '==', true)
        .limit(50)
        .get()
        .catch((e) => {
          logWarn({
            component: COMPONENT,
            event: 'rebalance.query_failed',
            collection: 'orders-food',
            reason: 'firestore_error',
            message: e.message,
          });
          return { empty: true, docs: [] };
        }),
      db
        .collection('orders-market')
        .where('status', '==', 'assigned')
        .where('assignedBy', '==', 'auto')
        .where('canReassign', '==', true)
        .limit(50)
        .get()
        .catch((e) => {
          logWarn({
            component: COMPONENT,
            event: 'rebalance.query_failed',
            collection: 'orders-market',
            reason: 'firestore_error',
            message: e.message,
          });
          return { empty: true, docs: [] };
        }),
    ]);

    const jobs = [];
    if (foodSnap && !foodSnap.empty) {
      foodSnap.docs.forEach((d) => jobs.push({ coll: 'orders-food', doc: d }));
    }
    if (marketSnap && !marketSnap.empty) {
      marketSnap.docs.forEach((d) => jobs.push({ coll: 'orders-market', doc: d }));
    }
    if (jobs.length === 0) return;

    let reassigned = 0;
    let scanned = 0;
    for (const { coll, doc } of jobs) {
      scanned++;
      const rebalanceId = newDispatchId();
      try {
        const order = doc.data();
        if (order.assignedBy === 'master') continue;
        if ((order.reassignHops || 0) >= REBALANCE_MAX_HOPS) {
          await doc.ref.update({ canReassign: false }).catch(() => {});
          logInfo({
            component: COMPONENT,
            event: 'rebalance.skipped',
            dispatchId: rebalanceId,
            orderId: doc.id,
            collection: coll,
            reason: 'max_hops',
          });
          continue;
        }

        const pickup = pickupCoordsFor(order, coll);
        if (!pickup) continue;

        const currentCourierId = order.cargoUserId;
        if (!currentCourierId) continue;

        // Commit the assignment if the current courier is already near the
        // pickup — no point reshuffling a nearly-arrived driver.
        const redis = getRedisClient();
        let currentPos = null;
        try {
          const pos = await redis.geopos('couriers:geo', currentCourierId);
          if (pos && pos[0]) {
            currentPos = {
              lng: parseFloat(pos[0][0]),
              lat: parseFloat(pos[0][1]),
            };
          }
        } catch (e) {
          // ignore, we'll treat as unknown → allow rebalance
        }

        if (currentPos) {
          const distToPickup = haversineKm(
            currentPos.lat, currentPos.lng,
            pickup.lat, pickup.lng,
          );
          if (distToPickup <= REBALANCE_COMMIT_RADIUS_KM) {
            await doc.ref.update({ canReassign: false }).catch(() => {});
            logInfo({
              component: COMPONENT,
              event: 'rebalance.skipped',
              dispatchId: rebalanceId,
              orderId: doc.id,
              collection: coll,
              reason: 'near_pickup',
              distToPickupKm: Number(distToPickup.toFixed(2)),
            });
            continue;
          }
        }

        // Score of current courier (using live Redis state)
        const currentState = await redis.hgetall(`courier:${currentCourierId}`).catch(() => ({}));
        const currentLoad = Math.max(0, parseInt(currentState.load || '0', 10));
        const currentRecent = await redis
          .zcount(
            `courier:${currentCourierId}:assigns`,
            Date.now() - ROTATION_WINDOW_MS,
            '+inf',
          )
          .catch(() => 0);
        const currentDist = currentPos ?
          haversineKm(currentPos.lat, currentPos.lng, pickup.lat, pickup.lng) :
          null;
        const currentLoadPenalty =
          currentLoad <= SOFT_LOAD_REF ?
            currentLoad * W_LOAD :
            SOFT_LOAD_REF * W_LOAD + (currentLoad - SOFT_LOAD_REF) * W_LOAD * 2;
        const currentScore =
          (currentDist ?? Infinity) * W_DISTANCE +
          currentLoadPenalty +
          currentRecent * W_ROTATION;

        const best = await selectCandidate({
          pickupLat: pickup.lat,
          pickupLng: pickup.lng,
          collection: coll,
          excludeUid: currentCourierId,
          dispatchId: rebalanceId,
        });

        if (!best) {
          logInfo({
            component: COMPONENT,
            event: 'rebalance.skipped',
            dispatchId: rebalanceId,
            orderId: doc.id,
            collection: coll,
            reason: 'no_candidate',
          });
          continue;
        }

        // best.uid is reserved (+1). Must release if we decide not to commit,
        // or if the unassign/assign chain fails before CF-40 takes ownership.
        let committed = false;
        try {
          const improved =
            currentScore - best.score >= REBALANCE_MIN_DELTA &&
            best.score <= currentScore * REBALANCE_MIN_RATIO;
          if (!improved) {
            logInfo({
              component: COMPONENT,
              event: 'rebalance.skipped',
              dispatchId: rebalanceId,
              orderId: doc.id,
              collection: coll,
              reason: 'not_improved',
              currentScore: Number(currentScore.toFixed(2)),
              candidateScore: Number(best.score.toFixed(2)),
            });
            continue;
          }

          const nameSnap = await db.collection('users').doc(best.uid).get();
          const newName = nameSnap.exists ?
            nameSnap.data().displayName || nameSnap.data().fullName || 'Courier' :
            'Courier';

          const unassignRef = db.collection('courier_actions').doc();
          await unassignRef.set({
            type: 'unassign',
            collection: coll,
            orderId: doc.id,
            courierId: currentCourierId,
            assignedBy: 'auto',
            reason: 'rebalance',
            status: 'pending',
            dispatchId: rebalanceId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Wait briefly for the unassign action to complete. We poll up to 3s.
          let unassigned = false;
          for (let i = 0; i < 15; i++) {
            await new Promise((r) => setTimeout(r, 200));
            const u = await unassignRef.get();
            const s = u.data()?.status;
            if (s === 'completed') {unassigned = true; break;}
            if (s === 'failed')    break;
          }
          if (!unassigned) {
            logWarn({
              component: COMPONENT,
              event: 'rebalance.unassign_timeout',
              dispatchId: rebalanceId,
              orderId: doc.id,
              collection: coll,
              previousCourierId: currentCourierId,
            });
            continue;
          }

          const assignRef = db.collection('courier_actions').doc();
          await assignRef.set({
            type: 'assign',
            collection: coll,
            orderId: doc.id,
            courierId: best.uid,
            courierName: newName,
            assignedBy: 'auto',
            suppressNotification: true, // silent on rebalance (user preference)
            status: 'pending',
            autoAssignScore: best.score,
            autoAssignDistanceKm: best.distKm,
            reassignHop: (order.reassignHops || 0) + 1,
            dispatchId: rebalanceId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          committed = true;

          logInfo({
            component: COMPONENT,
            event: 'rebalance.reassigned',
            dispatchId: rebalanceId,
            orderId: doc.id,
            collection: coll,
            previousCourierId: currentCourierId,
            courierId: best.uid,
            currentScore: Number(currentScore.toFixed(2)),
            newScore: Number(best.score.toFixed(2)),
            hop: (order.reassignHops || 0) + 1,
          });

          reassigned++;
        } finally {
          if (!committed) await releaseReservation(best.uid, rebalanceId);
        }
      } catch (err) {
        logError({
          component: COMPONENT,
          event: 'rebalance.order_failed',
          dispatchId: rebalanceId,
          orderId: doc.id,
          collection: coll,
          reason: 'exception',
          message: err.message,
        });
      }
    }

    logInfo({
      component: COMPONENT,
      event: 'rebalance.swept',
      scanned,
      reassigned,
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// RTDB → Redis mirror of courier location
// ─────────────────────────────────────────────────────────────────────────────

export const mirrorCourierLocation = onValueWritten(
  {
    ref: '/courier_locations/{uid}',
    region: RTDB_REGION,
    memory: '256MiB',
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (event) => {
    const uid = event.params.uid;
    const redis = getRedisClient();
    const after = event.data.after.val();

    // Courier gone → remove from indexes so they stop being picked.
    if (!after) {
      try {
        await redis
          .multi()
          .zrem('couriers:geo', uid)
          .del(`courier:${uid}`)
          .exec();
      } catch (err) {
        logWarn({
          component: 'mirror',
          event: 'mirror.remove_failed',
          courierId: uid,
          reason: 'redis_error',
          message: err.message,
        });
      }
      return;
    }

    const lat = typeof after.lat === 'number' ? after.lat : null;
    const lng = typeof after.lng === 'number' ? after.lng : null;
    const isOnline  = after.isOnline  === true;
    const isOnShift = after.isOnShift === true;

    try {
      const pipeline = redis.pipeline();

      if (!isOnline || !isOnShift || lat === null || lng === null) {
        pipeline.zrem('couriers:geo', uid);
      } else {
        pipeline.geoadd('couriers:geo', lng, lat, uid);
      }

      pipeline.hset(`courier:${uid}`, {
        isOnShift: isOnShift ? '1' : '0',
        isOnline: isOnline  ? '1' : '0',
        lastSeen: String(Date.now()),
        ...(typeof after.speed === 'number' ? { speed: String(after.speed) } : {}),
      });

      // Ensure a load key exists (does NOT overwrite live counter).
      pipeline.hsetnx(`courier:${uid}`, 'load', '0');

      await pipeline.exec();
    } catch (err) {
      logWarn({
        component: 'mirror',
        event: 'mirror.write_failed',
        courierId: uid,
        reason: 'redis_error',
        message: err.message,
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// SCHEDULED: fleet gauge — snapshots the dispatch pool size once a minute.
//
// Powers the ops dashboard's "couriers on-shift" chart and the alert
// "on_shift == 0 during operating hours". Intentionally tiny — one Redis
// call, one structured log line.
// ─────────────────────────────────────────────────────────────────────────────

export const logFleetMetrics = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    try {
      const redis = getRedisClient();
      const onShift = await redis.zcard('couriers:geo');
      logInfo({
        component: 'fleet',
        event: 'fleet.gauge',
        onShift,
      });
    } catch (err) {
      logError({
        component: 'fleet',
        event: 'fleet.gauge_failed',
        reason: 'redis_error',
        message: err.message,
      });
    }
  },
);
