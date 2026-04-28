// Load test for the courier dispatch + delivery pipeline.
//
// Simulates:
//   1. N test couriers going online (writes to RTDB couriers/{uid}).
//   2. Waiting one mirror tick (~70s) so CF-54 syncs them into Redis.
//   3. N orders created as `pending`, then transitioned to `accepted` —
//      this fires the autoAssignOnFoodAccepted trigger naturally.
//   4. Watching cargoUserId populate, measuring dispatch latency.
//   5. Simulating pickup + deliver actions for each assigned order.
//   6. Reporting latency stats + per-courier distribution.
//
// Run from the `functions/` directory:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json node loadtest/simulate.js
//
// Tweak COURIER_COUNT, ORDER_COUNT, and RESTAURANT_ID below for your test.

import admin from 'firebase-admin';
import { getDatabase } from 'firebase-admin/database';

// ─── CONFIG ──────────────────────────────────────────────────────────────────

const PROJECT_ID    = 'emlak-mobile-app';
const DATABASE_URL  = 'https://emlak-mobile-app-default-rtdb.europe-west1.firebasedatabase.app';

// Pick any restaurant doc ID from your `restaurants` collection. Use one
// whose `ourComission` and `ourShipmentFee` are set to non-zero, so the
// fees look realistic in courier_alltime_stats.
const RESTAURANT_ID = 'nyy2IrRGNQVZ4g2HhsjD';

const COURIER_COUNT = 50;
const ORDER_COUNT   = 50;

// Restaurant pickup coords (used for both the order's restaurantLat/Lng and
// as the centerpoint for buyer locations within delivery range).
const RESTAURANT_LAT = 35.137;
const RESTAURANT_LNG = 33.921;

// City-anchored random points. Each city has a weight (rough population
// share) and a ~3 km scatter radius around its center. Keeps the test
// realistic — couriers cluster around population centers like in production
// instead of getting sprinkled into the Mediterranean.
const KKTC_CITIES = [
  { name: 'Lefkoşa',    lat: 35.180, lng: 33.380, weight: 0.30 },
  { name: 'Gazimağusa', lat: 35.130, lng: 33.940, weight: 0.25 },
  { name: 'Girne',      lat: 35.340, lng: 33.320, weight: 0.20 },
  { name: 'Güzelyurt',  lat: 35.200, lng: 32.990, weight: 0.10 },
  { name: 'İskele',     lat: 35.288, lng: 33.890, weight: 0.10 },
  { name: 'Lefke',      lat: 35.118, lng: 32.847, weight: 0.05 },
];

const MIRROR_WAIT_MS    = 70000;    // mirror tick is every 60s
const DISPATCH_TIMEOUT  = 180000;   // 3 min cap for waiting on dispatches
const PICKUP_GAP_MS     = 500;      // delay between pickup and deliver actions

// ─── INIT ────────────────────────────────────────────────────────────────────

admin.initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL });
const db   = admin.firestore();
const rtdb = getDatabase();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function kktcRandomLatLng() {
  const r = Math.random();
  let acc = 0;
  for (const c of KKTC_CITIES) {
    acc += c.weight;
    if (r <= acc) {
      // Uniform scatter inside ~3 km box around the city center. dLat=0.05
      // ≈ 5.5 km north-south span, dLng=0.06 ≈ 5.5 km east-west at this
      // latitude — courier lands within a 3 km radius on average.
      const dLat = (Math.random() - 0.5) * 0.05;
      const dLng = (Math.random() - 0.5) * 0.06;
      return { lat: c.lat + dLat, lng: c.lng + dLng };
    }
  }
  // Fallback if weights don't sum to exactly 1 due to FP rounding.
  const last = KKTC_CITIES[KKTC_CITIES.length - 1];
  return { lat: last.lat, lng: last.lng };
}

// ─── STAGE 1: Couriers ───────────────────────────────────────────────────────

async function createCouriers(n) {
  const uids = [];
  for (let i = 0; i < n; i++) {
    const email = `loadtest-courier-${i}@example.com`;
    let uid;
    try {
      const u = await admin.auth().createUser({
        email,
        password: 'Test1234!',
        displayName: `LT Courier ${i}`,
      });
      uid = u.uid;
    } catch (e) {
      // Already exists (re-running the script) — fetch existing UID.
      const existing = await admin.auth().getUserByEmail(email);
      uid = existing.uid;
    }
    uids.push(uid);
  }
  console.log(`[stage 1] Created/found ${uids.length} test couriers`);
  return uids;
}

async function setOnline(uids) {
  for (const uid of uids) {
    const { lat, lng } = kktcRandomLatLng();
    await rtdb.ref(`courier_locations/${uid}`).set({
      lat, lng,
      isOnline: true,
      isOnShift: true,
      updatedAt: Date.now(),
    });
  }
  console.log(`[stage 1] Wrote ${uids.length} couriers to RTDB`);
  console.log(`[stage 1] Waiting ${MIRROR_WAIT_MS / 1000}s for mirror tick...`);
  await sleep(MIRROR_WAIT_MS);
  console.log(`[stage 1] Couriers should now be in Redis`);
}

// ─── STAGE 2: Orders ─────────────────────────────────────────────────────────

async function createOrdersAsPending(n) {
  const orderIds = [];
  for (let i = 0; i < n; i++) {
    const ref = db.collection('orders-food').doc();
    const buyerLoc = kktcRandomLatLng();
    await ref.set({
      sourceType: 'loadtest',
      restaurantId: RESTAURANT_ID,
      restaurantName: 'Load Test Restaurant',
      restaurantLat: RESTAURANT_LAT,
      restaurantLng: RESTAURANT_LNG,
      restaurantCity: 'Gazimağusa',
      restaurantSubcity: 'Salamis Yolu',
      buyerId: null,
      buyerName: `Load Test Buyer ${i}`,
      buyerPhone: '+905330000000',
      items: [{
        foodId: 'lt',
        name: 'Test Item',
        quantity: 1,
        price: 100,
        itemTotal: 100,
        extras: [],
        specialNotes: '',
      }],
      itemCount: 1,
      subtotal: 100, deliveryFee: 0, totalPrice: 100, currency: 'TL',
      paymentMethod: 'pay_at_door', isPaid: false,
      deliveryType: 'delivery',
      deliveryAddress: {
        addressLine1: 'Load Test Address',
        city: 'Gazimağusa',
        phoneNumber: '+905330000000',
        location: new admin.firestore.GeoPoint(buyerLoc.lat, buyerLoc.lng),
      },
      status: 'pending',
      cargoUserId: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    orderIds.push(ref.id);
  }
  console.log(`[stage 2] Created ${orderIds.length} pending orders`);
  return orderIds;
}

async function acceptAll(orderIds) {
  const t0 = Date.now();
  await Promise.all(orderIds.map((id) =>
    db.collection('orders-food').doc(id).update({
      status: 'accepted',
      courierType: 'ours',
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      fees: {
        subtotal: 100,
        commissionRate: 10,
        shipmentFeeRate: 180,
        courierType: 'ours',
        commissionAmount: 10,
        shipmentFeeApplied: 180,
        platformRevenue: 190,
        restaurantPayout: -90,
        status: 'finalized',
        calculatedAt: admin.firestore.Timestamp.now(),
        ratesVersion: 1,
      },
    })
  ));
  console.log(`[stage 2] Accepted ${orderIds.length} orders in ${Date.now() - t0}ms`);
  return Date.now();   // return the moment dispatch became possible
}

async function watchDispatch(orderIds, dispatchStartedAt, timeoutMs) {
  const assignments = new Map();   // orderId → { courierId, latencyMs }

  return new Promise((resolve) => {
    const unsubs = [];
    // Firestore `in` query is capped at 30, so chunk.
    const chunks = [];
    for (let i = 0; i < orderIds.length; i += 30) {
      chunks.push(orderIds.slice(i, i + 30));
    }
    for (const chunk of chunks) {
      const u = db.collection('orders-food')
        .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
        .onSnapshot((snap) => {
          for (const doc of snap.docs) {
            const data = doc.data();
            if (data.cargoUserId && !assignments.has(doc.id)) {
              assignments.set(doc.id, {
                courierId: data.cargoUserId,
                latencyMs: Date.now() - dispatchStartedAt,
              });
            }
          }
          if (assignments.size === orderIds.length) {
            unsubs.forEach((fn) => fn());
            resolve(assignments);
          }
        });
      unsubs.push(u);
    }
    setTimeout(() => {
      unsubs.forEach((fn) => fn());
      resolve(assignments);
    }, timeoutMs);
  });
}

// ─── STAGE 3: Deliveries ─────────────────────────────────────────────────────

async function simulateDeliveries(assignments) {
  let i = 0;
  for (const [orderId, info] of assignments) {
    const courierId = info.courierId;
    await db.collection('courier_actions').add({
      type: 'pickup',
      collection: 'orders-food',
      orderId,
      courierId,
      courierName: 'LT',
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await sleep(PICKUP_GAP_MS);
    await db.collection('courier_actions').add({
      type: 'deliver',
      collection: 'orders-food',
      orderId,
      courierId,
      courierName: 'LT',
      paymentMethod: 'cash',
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (++i % 10 === 0) console.log(`[stage 3]   ${i}/${assignments.size} pickup+deliver written`);
  }
  console.log(`[stage 3] All ${assignments.size} delivery actions queued`);
}

// ─── REPORT ──────────────────────────────────────────────────────────────────

function reportLatency(assignments, expectedCount) {
  const latencies = [...assignments.values()].map((a) => a.latencyMs).sort((a, b) => a - b);
  if (latencies.length === 0) {
    console.log('\n[report] No dispatches captured. Check Cloud Logging.');
    return;
  }
  const pct = (p) => latencies[Math.min(latencies.length - 1, Math.floor(latencies.length * p))];
  console.log(`\n[report] Dispatched ${assignments.size}/${expectedCount}`);
  console.log(`[report] Latency  p50=${pct(0.5)}ms  p95=${pct(0.95)}ms  p99=${pct(0.99)}ms  max=${latencies[latencies.length - 1]}ms`);

  const perCourier = new Map();
  for (const { courierId } of assignments.values()) {
    perCourier.set(courierId, (perCourier.get(courierId) || 0) + 1);
  }
  const counts = [...perCourier.values()];
  console.log(`[report] Couriers used: ${perCourier.size}`);
  console.log(`[report] Orders/courier: min=${Math.min(...counts)}  max=${Math.max(...counts)}  mean=${(counts.reduce((s, c) => s + c, 0) / counts.length).toFixed(2)}`);
}

// ─── MAIN ────────────────────────────────────────────────────────────────────

(async () => {
  console.log(`Load test starting. Project: ${PROJECT_ID}`);
  console.log(`  ${COURIER_COUNT} couriers, ${ORDER_COUNT} orders`);
  console.log(`  Restaurant: ${RESTAURANT_ID}`);
  console.log('');

  const couriers = await createCouriers(COURIER_COUNT);
  await setOnline(couriers);

  const orderIds         = await createOrdersAsPending(ORDER_COUNT);
  const dispatchStartedAt = await acceptAll(orderIds);

  console.log(`[stage 2] Watching dispatch (timeout ${DISPATCH_TIMEOUT / 1000}s)...`);
  const assignments = await watchDispatch(orderIds, dispatchStartedAt, DISPATCH_TIMEOUT);

  reportLatency(assignments, orderIds.length);

  if (assignments.size > 0) {
    console.log('');
    await simulateDeliveries(assignments);
  } else {
    console.log('\n[stage 3] Skipped — nothing was dispatched.');
  }

  console.log('\nSimulation complete.');
  console.log('Run `node loadtest/cleanup.js` to remove test data when finished.');
  process.exit(0);
})().catch((err) => {
  console.error('Simulation failed:', err);
  process.exit(1);
});
