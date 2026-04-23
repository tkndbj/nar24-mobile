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
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { getRedisClient } from '../shared/redis.js';
import { logInfo, logWarn, logError, newDispatchId, startTimer } from '../shared/logger.js';

const COMPONENT = 'auto_assign';

const REGION = 'europe-west3';

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
// Heading-awareness (Level 1 on-path bonus).
//
// For couriers already carrying at least one order, we have an idea of where
// they're heading (their immediate next stop — pickup if not-yet-picked-up,
// else delivery address). If the *new* pickup bearing from the courier's
// current position aligns with that existing heading, inserting this order
// into their route is cheap. If it's opposite, it's a backtrack.
//
// Bonuses/penalties are absolute score deltas, sized to be meaningful without
// overwhelming raw distance (a <30° on-path match is worth ~3 km of proximity).
const W_HEADING_ONPATH   = -3.0;          // <30°  from heading (big bonus)
const W_HEADING_MOSTLY   = -1.5;          // <60°  from heading (partial)
const W_HEADING_AGAINST  = +2.0;          // >120° from heading (backtrack)
const HEADING_ONPATH_DEG  = 30;
const HEADING_MOSTLY_DEG  = 60;
const HEADING_AGAINST_DEG = 120;
// Courier must be ≥100 m from their next stop for the bearing to be
// informative. Sub-100 m bearings are GPS noise.
const HEADING_MIN_LEG_KM = 0.1;
const REBALANCE_MIN_DELTA        = 1.5;   // absolute score improvement required
const REBALANCE_MIN_RATIO        = 0.75;  // new must also be ≤ old × 0.75
const REBALANCE_COMMIT_RADIUS_KM = 0.5;   // courier already near pickup → lock
const REBALANCE_MAX_HOPS         = 2;
const STALE_UNASSIGNED_MS = 30 * 1000;    // retry threshold
// With a 60 s mirror tick, we need a margin >2× the tick to avoid scoring
// against couriers whose off-shift event hasn't propagated yet. 3 min gives
// us one full missed tick of headroom before dispatch sees a ghost.
const COURIER_STALE_MS    = 3 * 60 * 1000;

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

// Initial bearing from point 1 to point 2, in degrees [0, 360).
// Standard great-circle formula. Accurate enough for <300 km hops; we only
// use this to compare directions, never to navigate.
function bearingDeg(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const toDeg = (r) => (r * 180) / Math.PI;
  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δλ = toRad(lng2 - lng1);
  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x =
    Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

// Absolute angular difference in [0, 180] — handles the 359° ↔ 1° wrap.
function angularDiff(a, b) {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

// Returns the scoring delta for how aligned `newPickup` is with the
// courier's existing heading (courier → nextStop). Returns 0 when the
// heuristic can't be applied (no stop, too close to stop, bad input).
function headingDelta({ courierLat, courierLng, nextStop, newPickupLat, newPickupLng }) {
  if (!nextStop) return 0;
  const legKm = haversineKm(courierLat, courierLng, nextStop.lat, nextStop.lng);
  if (legKm < HEADING_MIN_LEG_KM) return 0; // sub-100m = GPS noise

  const existingBearing = bearingDeg(
    courierLat, courierLng,
    nextStop.lat, nextStop.lng,
  );
  const newBearing = bearingDeg(
    courierLat, courierLng,
    newPickupLat, newPickupLng,
  );
  const diff = angularDiff(existingBearing, newBearing);

  if (diff <= HEADING_ONPATH_DEG) return W_HEADING_ONPATH;
  if (diff <= HEADING_MOSTLY_DEG) return W_HEADING_MOSTLY;
  if (diff >= HEADING_AGAINST_DEG) return W_HEADING_AGAINST;
  return 0;
}

// Batch-fetches the "next immediate stop" for each loaded candidate courier.
// For an order in status:
//   'assigned'          → the courier hasn't picked up yet; next stop = pickup
//                         (restaurant for food, warehouse for market)
//   'out_for_delivery'  → picked up; next stop = delivery address
//
// If a courier has multiple active orders, we pick the NEAREST stop as the
// proxy for their immediate direction of travel. That's the stop they're
// most plausibly heading to next.
//
// Issues one pair of Firestore queries per candidate in parallel. Bounded by
// CANDIDATE_LIMIT (20), so worst case ~40 reads per dispatch. Runs only for
// candidates with load>0, typically 3-8 of them.
async function fetchNextStops(db, courierIds, courierPositions) {
  if (!courierIds.length) return new Map();
  const statuses = ['assigned', 'out_for_delivery'];
  const perCourier = await Promise.all(
    courierIds.map(async (uid) => {
      try {
        const [foodSnap, marketSnap] = await Promise.all([
          db.collection('orders-food')
            .where('cargoUserId', '==', uid)
            .where('status', 'in', statuses)
            .get(),
          db.collection('orders-market')
            .where('cargoUserId', '==', uid)
            .where('status', 'in', statuses)
            .get(),
        ]);
        const stops = [];
        const ingest = (doc, isMarket) => {
          const o = doc.data();
          if (o.status === 'assigned') {
            // Next stop is the pickup location.
            const lat = isMarket ? o.marketLat : o.restaurantLat;
            const lng = isMarket ? o.marketLng : o.restaurantLng;
            if (typeof lat === 'number' && typeof lng === 'number') {
              stops.push({ lat, lng });
            }
          } else if (o.status === 'out_for_delivery') {
            const loc = o.deliveryAddress && o.deliveryAddress.location;
            if (loc && typeof loc.latitude === 'number' && typeof loc.longitude === 'number') {
              stops.push({ lat: loc.latitude, lng: loc.longitude });
            }
          }
        };
        foodSnap.docs.forEach((d) => ingest(d, false));
        marketSnap.docs.forEach((d) => ingest(d, true));
        if (!stops.length) return [uid, null];

        // Pick the stop nearest to the courier's current position — that's
        // their imminent destination.
        const pos = courierPositions.get(uid);
        if (!pos) return [uid, stops[0]]; // fall back to first stop
        let best = stops[0];
        let bestKm = haversineKm(pos.lat, pos.lng, best.lat, best.lng);
        for (let i = 1; i < stops.length; i++) {
          const km = haversineKm(pos.lat, pos.lng, stops[i].lat, stops[i].lng);
          if (km < bestKm) {
            bestKm = km;
            best = stops[i];
          }
        }
        return [uid, best];
      } catch (err) {
        // Per-courier failure is isolated — we just treat that courier as
        // "no heading info" and fall back to raw-distance scoring for them.
        logWarn({
          component: COMPONENT,
          event: 'heading.fetch_failed',
          courierId: uid,
          reason: 'firestore_error',
          message: err.message,
        });
        return [uid, null];
      }
    }),
  );
  return new Map(perCourier);
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

async function selectCandidate({ db, pickupLat, pickupLng, collection, excludeUid = null, dispatchId }) {
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

    // ── Two-pass scoring ─────────────────────────────────────────────
    // Pass 1: filter to candidates that are on-shift + fresh heartbeat,
    //          resolve their base state (load, recentAssigns).
    // Between passes: for loaded candidates, batch-fetch "next stop" from
    //          Firestore to enable the heading-aware bonus.
    // Pass 2: compute final score (base + heading delta) and pick best.
    const rejects = [];
    const active = [];                       // candidates that passed filters
    const courierPositions = new Map();      // uid → {lat, lng}
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
      active.push({ ...ordered[i], load, recentAssigns });
      courierPositions.set(ordered[i].uid, { lat: ordered[i].lat, lng: ordered[i].lng });
    }

    if (active.length === 0) {
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
      continue;
    }

    // Fetch next-stop destinations for loaded candidates so scoring can
    // apply the on-path bonus. Idle couriers (load == 0) skip this lookup
    // entirely — they have no existing heading to align against.
    //
    // Firestore failure is isolated per-courier inside fetchNextStops, so
    // a partial outage only degrades heading-awareness for affected
    // couriers; base scoring still runs.
    const loadedUids = active.filter((c) => c.load > 0).map((c) => c.uid);
    let nextStopByUid = new Map();
    if (db && loadedUids.length > 0) {
      nextStopByUid = await fetchNextStops(db, loadedUids, courierPositions);
    }

    let best = null;
    for (const c of active) {
      // Soft cap: beyond SOFT_LOAD_REF, each extra order costs more (not
      // forbidden — someone still has to take the order).
      const loadPenalty =
        c.load <= SOFT_LOAD_REF ?
          c.load * W_LOAD :
          SOFT_LOAD_REF * W_LOAD + (c.load - SOFT_LOAD_REF) * W_LOAD * 2;

      const nextStop = nextStopByUid.get(c.uid) || null;
      const hDelta = headingDelta({
        courierLat: c.lat,
        courierLng: c.lng,
        nextStop,
        newPickupLat: pickupLat,
        newPickupLng: pickupLng,
      });

      const score =
        c.distKm * W_DISTANCE +
        loadPenalty +
        c.recentAssigns * W_ROTATION +
        hDelta;

      if (!best || score < best.score) {
        best = { ...c, score, headingDelta: hDelta, hasHeading: !!nextStop };
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
    db,
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
      headingDelta: Number((best.headingDelta || 0).toFixed(2)),
      hasHeading: !!best.hasHeading,
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
    if (after.courierType !== 'ours') return; // restaurant using own courier — skip

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
          .where('courierType', '==', 'ours')
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
        if (coll === 'orders-food' && data.courierType !== 'ours') continue;
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

        // Apply the same heading-delta the candidate will receive so the
        // two scores are directly comparable. Without this, candidates get
        // an implicit free bonus and the rebalancer fires spuriously. Only
        // possible when we know the current courier's position.
        let currentHeadingDelta = 0;
        if (currentPos) {
          const currentStops = await fetchNextStops(
            db,
            [currentCourierId],
            new Map([[currentCourierId, currentPos]]),
          );
          const currentStop = currentStops.get(currentCourierId);
          currentHeadingDelta = headingDelta({
            courierLat: currentPos.lat,
            courierLng: currentPos.lng,
            nextStop: currentStop,
            newPickupLat: pickup.lat,
            newPickupLng: pickup.lng,
          });
        }

        const currentScore =
          (currentDist ?? Infinity) * W_DISTANCE +
          currentLoadPenalty +
          currentRecent * W_ROTATION +
          currentHeadingDelta;

        const best = await selectCandidate({
          db,
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
// RTDB → Redis mirror of courier locations (scheduled sweep)
//
// Replaces the per-write onValueWritten trigger. A single scheduled invocation
// reads the /courier_locations tree once per tick and pipelines one Redis
// batch for the whole fleet, so CF cost scales with fleet size — not with
// GPS write frequency. At 100 couriers this is ~1,440 invocations/day
// instead of ~150K.
//
// Freshness trade-off: shift-on / shift-off propagates into the dispatch
// index within 60 s (the tick interval). Well under COURIER_STALE_MS (3 min)
// so `selectCandidate` never sees a racing mismatch, even if one tick runs
// late.
//
// Deletion behaviour: when a courier account is removed, their
// `/courier_locations/{uid}` node disappears. The cron skips them; their
// Redis entries age out naturally — `selectCandidate`'s stale_heartbeat
// filter (`now - lastSeen > COURIER_STALE_MS`) rejects them at dispatch
// time. Negligibly larger ZSET, no correctness impact.
// ─────────────────────────────────────────────────────────────────────────────

export const mirrorCourierLocations = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: REGION,
    memory: '256MiB',
    // Headroom for slow RTDB reads + slow Redis pipelines on the same tick.
    // Early-return cost is zero; a timeout mid-pipeline leaves Redis partly
    // updated until the next tick heals it.
    timeoutSeconds: 180,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    const redis = getRedisClient();
    const tickStart = Date.now();

    // Skip records older than this — apps uninstalled, dormant accounts.
    // Still processed (so we can DEL them from Redis) but never indexed.
    const DORMANT_THRESHOLD_MS = 24 * 60 * 60 * 1000; // 24h

    // ── Step 1: read RTDB ────────────────────────────────────────────
    let rtdbSnap;
    const rtdbStart = Date.now();
    try {
      rtdbSnap = await admin.database().ref('/courier_locations').get();
    } catch (err) {
      logError({
        component: 'mirror',
        event: 'mirror.rtdb_read_failed',
        reason: 'rtdb_error',
        message: err.message,
      });
      return;
    }
    const rtdbMs = Date.now() - rtdbStart;

    const couriers = rtdbSnap.exists() ? (rtdbSnap.val() || {}) : {};
    const rtdbUids = new Set(Object.keys(couriers));

    // ── Step 2: reconcile against previous Redis index ───────────────
    // Any uid that was in `couriers:geo` last tick but isn't in RTDB now
    // (courier deleted, record expired) must be purged from Redis —
    // otherwise the ZSET leaks forever.
    let priorIndexUids;
    try {
      priorIndexUids = await redis.zrange('couriers:geo', 0, -1);
    } catch (err) {
      logWarn({
        component: 'mirror',
        event: 'mirror.zrange_failed',
        reason: 'redis_error',
        message: err.message,
      });
      priorIndexUids = [];
    }

  // Chunk the pipeline so no single exec() issues more than this many
    // commands. Protects against unbounded pipeline growth on first-run
    // reconciliation (thousands of accumulated leaked keys) and on fleet
    // growth. 500 ops = ~4 per courier × 125 couriers per flush; well
    // within Memorystore / ioredis comfort zones.
    const PIPELINE_CHUNK_SIZE = 500;

    let indexed = 0;
    let unindexed = 0;
    let dormant = 0;
    let purged = 0;
    let pipeline = redis.pipeline();
    let opsInPipeline = 0;
    let totalRedisMs = 0;
    let flushCount = 0;
    let pipelineFailed = false;

    // Flushes the current pipeline and starts a fresh one. Accumulates
    // timing and failure state across chunks so the final log line reflects
    // the whole tick, not just the last flush.
    const flushPipeline = async () => {
      if (opsInPipeline === 0) return;
      const flushStart = Date.now();
      try {
        await pipeline.exec();
      } catch (err) {
        pipelineFailed = true;
        logError({
          component: 'mirror',
          event: 'mirror.pipeline_failed',
          reason: 'redis_error',
          flushIndex: flushCount,
          message: err.message,
        });
      }
      totalRedisMs += Date.now() - flushStart;
      flushCount++;
      pipeline = redis.pipeline();
      opsInPipeline = 0;
    };

    const maybeFlush = async () => {
      if (opsInPipeline >= PIPELINE_CHUNK_SIZE) {
        await flushPipeline();
      }
    };

    // Purge couriers that vanished from RTDB entirely.
    for (const uid of priorIndexUids) {
      if (!rtdbUids.has(uid)) {
        pipeline.zrem('couriers:geo', uid);
        pipeline.del(`courier:${uid}`);
        // Note: we leave `courier:{uid}:assigns` alone — the rotation
        // window is 30 min so it ages out naturally and may still be
        // needed if the courier returns shortly.
        opsInPipeline += 2;
        purged++;
        await maybeFlush();
      }
    }

    // ── Step 3: process RTDB records ─────────────────────────────────
    for (const uid of rtdbUids) {
      const c = couriers[uid] || {};
      const lat = typeof c.lat === 'number' ? c.lat : null;
      const lng = typeof c.lng === 'number' ? c.lng : null;
      const isOnline  = c.isOnline  === true;
      const isOnShift = c.isOnShift === true;
      // Use the courier's own write timestamp as `lastSeen` — more accurate
      // than the CF invocation time. Falls back to now() if RTDB hasn't
      // stamped it (shouldn't happen, but defensive).
      const updatedAt = typeof c.updatedAt === 'number' ? c.updatedAt : Date.now();
      const age = tickStart - updatedAt;

      // Dormant: hasn't written in >24h. Skip indexing, purge any stale
      // Redis entries, move on. Keeps the index lean even if RTDB
      // accumulates orphaned records.
      if (age > DORMANT_THRESHOLD_MS) {
        pipeline.zrem('couriers:geo', uid);
        pipeline.del(`courier:${uid}`);
        opsInPipeline += 2;
        dormant++;
        await maybeFlush();
        continue;
      }

      if (!isOnline || !isOnShift || lat === null || lng === null) {
        pipeline.zrem('couriers:geo', uid);
        unindexed++;
      } else {
        pipeline.geoadd('couriers:geo', lng, lat, uid);
        indexed++;
      }

      pipeline.hset(`courier:${uid}`, {
        isOnShift: isOnShift ? '1' : '0',
        isOnline: isOnline  ? '1' : '0',
        lastSeen: String(updatedAt),
        ...(typeof c.speed === 'number' ? { speed: String(c.speed) } : {}),
      });
      // Initialise load only if not already set — we must not stomp the live
      // counter maintained by CF-40 and selectCandidate reservations.
      pipeline.hsetnx(`courier:${uid}`, 'load', '0');
      opsInPipeline += 3;
      await maybeFlush();
    }

    // ── Step 4: final flush ──────────────────────────────────────────
    await flushPipeline();

    if (!pipelineFailed) {
      logInfo({
        component: 'mirror',
        event: 'mirror.swept',
        count: rtdbUids.size,
        indexed,
        unindexed,
        dormant,
        purged,
        rtdbReadMs: rtdbMs,
        redisPipelineMs: totalRedisMs,
        flushCount,
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
