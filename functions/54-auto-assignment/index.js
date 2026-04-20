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
//   3. Writes `courier_actions` doc with type:'assign', assignedBy:'auto'
//   4. CF-40 does the atomic state transition, bumps Redis load, pushes
//      in-app notification to the assigned courier (which fans out to FCM
//      via CF-46).
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
// CORE: pick best candidate from Redis
// ─────────────────────────────────────────────────────────────────────────────

async function selectCandidate({ pickupLat, pickupLng, collection, excludeUid = null }) {
  const redis = getRedisClient();
  const tiers = RADIUS_TIERS_BY_COLLECTION[collection] || RADIUS_TIERS_KM_FOOD;

  // Diagnostic: state of the geo index at dispatch time.
  try {
    const indexSize = await redis.zcard('couriers:geo');
    console.log(`[AutoAssign][dbg] couriers:geo size=${indexSize} collection=${collection} pickup=(${pickupLat},${pickupLng}) tiers=${tiers.join('/')}`);
  } catch (e) {
    console.warn('[AutoAssign][dbg] zcard failed:', e.message);
  }

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
      console.warn('[AutoAssign] GEOSEARCH failed:', err.message);
      return null;
    }

    console.log(`[AutoAssign][dbg] tier=${radius}km rows=${rows ? rows.length : 0}`);
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
      console.warn('[AutoAssign] pipeline exec failed:', err.message);
      return null;
    }

    let best = null;
    const rejects = [];
    for (let i = 0; i < ordered.length; i++) {
      const state = results[i * 2][1] || {};
      const recentAssigns = parseInt(results[i * 2 + 1][1] || '0', 10);

      const isOnShift = state.isOnShift === '1' || state.isOnShift === 'true';
      if (!isOnShift) {
        rejects.push(`${ordered[i].uid}:offshift(state.isOnShift=${state.isOnShift})`);
        continue;
      }

      const lastSeen = parseInt(state.lastSeen || '0', 10);
      if (lastSeen && now - lastSeen > COURIER_STALE_MS) {
        rejects.push(`${ordered[i].uid}:stale(${Math.round((now - lastSeen) / 1000)}s)`);
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
      console.log(`[AutoAssign][dbg] tier=${radius}km rejected: ${rejects.join(', ')}`);
    }

    if (best) return best;
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORE: attempt to assign one order
// ─────────────────────────────────────────────────────────────────────────────

async function autoAssignOrder(db, orderId, collection) {
  if (!VALID_COLLECTIONS.has(collection)) return { ok: false, reason: 'invalid_collection' };

  const orderRef = db.collection(collection).doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) return { ok: false, reason: 'not_found' };
  const order = orderSnap.data();

  // Guardrails
  if (order.cargoUserId) return { ok: false, reason: 'already_assigned' };
  if (order.assignedBy === 'master') return { ok: false, reason: 'master_assigned' };
  // Master explicitly pulled this order back — hands off until the master
  // re-assigns (which clears the stamp in CF-40 processAssign).
  if (order.unassignedBy === 'master') return { ok: false, reason: 'master_unassigned' };

  const expectedStatus = collection === 'orders-food' ? 'accepted' : 'pending';
  if (order.status !== expectedStatus) {
    return { ok: false, reason: `wrong_status:${order.status}` };
  }

  const pickup = pickupCoordsFor(order, collection);
  if (!pickup) return { ok: false, reason: 'missing_pickup_coords' };

  const best = await selectCandidate({
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    collection,
  });

  if (!best) {
    console.log(`[AutoAssign][dbg] ${collection}/${orderId} → no_candidate`);
    return { ok: false, reason: 'no_candidate' };
  }

  // Fetch courier display name (cheap single-doc read)
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
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `[AutoAssign] ${collection}/${orderId} → ${best.uid} ` +
      `(dist=${best.distKm.toFixed(2)}km, load=${best.load}, recent=${best.recentAssigns}, score=${best.score.toFixed(2)})`
  );

  return { ok: true, courierId: best.uid, score: best.score };
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
      await autoAssignOrder(admin.firestore(), orderId, 'orders-food');
    } catch (err) {
      console.error('[AutoAssign] food trigger failed:', orderId, err);
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
      await autoAssignOrder(admin.firestore(), orderId, 'orders-market');
    } catch (err) {
      console.error('[AutoAssign] market trigger failed:', orderId, err);
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
            console.warn('[AutoAssign] retry food query failed:', e.message);
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
            console.warn('[AutoAssign] retry market query failed:', e.message);
            return { empty: true, docs: [] };
          }),
      },
    ];

    let attempted = 0;
    for (const { coll, snap } of stale) {
      if (!snap || snap.empty) continue;
      for (const doc of snap.docs) {
        const data = doc.data();
        if (data.assignedBy === 'master') continue;
        if (data.unassignedBy === 'master') continue; // master pulled it back
        try {
          const result = await autoAssignOrder(db, doc.id, coll);
          if (result.ok) attempted++;
        } catch (err) {
          console.error(`[AutoAssign] retry ${coll}/${doc.id} failed:`, err);
        }
      }
    }

    if (attempted > 0) console.log(`[AutoAssign] retry assigned ${attempted} order(s)`);
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
          console.warn('[AutoAssign] rebalance food query failed:', e.message);
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
          console.warn('[AutoAssign] rebalance market query failed:', e.message);
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
    for (const { coll, doc } of jobs) {
      try {
        const order = doc.data();
        if (order.assignedBy === 'master') continue;
        if ((order.reassignHops || 0) >= REBALANCE_MAX_HOPS) {
          await doc.ref.update({ canReassign: false }).catch(() => {});
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
        });

        if (!best) continue;

        const improved =
          currentScore - best.score >= REBALANCE_MIN_DELTA &&
          best.score <= currentScore * REBALANCE_MIN_RATIO;
        if (!improved) continue;

        // Fetch new courier name
        const nameSnap = await db.collection('users').doc(best.uid).get();
        const newName = nameSnap.exists ?
          nameSnap.data().displayName || nameSnap.data().fullName || 'Courier' :
          'Courier';

        // Chain: unassign (silent), then assign (silent, suppresses notif)
        const unassignRef = db.collection('courier_actions').doc();
        await unassignRef.set({
          type: 'unassign',
          collection: coll,
          orderId: doc.id,
          courierId: currentCourierId,
          assignedBy: 'auto',
          reason: 'rebalance',
          status: 'pending',
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
        if (!unassigned) continue;

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
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        reassigned++;
      } catch (err) {
        console.error(`[AutoAssign] rebalance ${coll}/${doc.id} failed:`, err);
      }
    }

    if (reassigned > 0) console.log(`[AutoAssign] rebalanced ${reassigned} order(s)`);
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
        console.warn('[AutoAssign] mirror remove failed:', uid, err.message);
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
      console.warn('[AutoAssign] mirror write failed:', uid, err.message);
    }
  },
);
