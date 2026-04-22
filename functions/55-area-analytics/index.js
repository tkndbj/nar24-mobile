// 55-area-analytics/index.js
//
// On-demand area analytics for operational fine-tuning. Admin calls
// getAreaAnalytics(from, to) from the ops dashboard; CF streams the orders in
// the window, aggregates by area in memory, returns the result. No triggers,
// no scheduled jobs, no persistent aggregate documents — all cost is pay-per-
// call and scoped to the requested window.
//
// Architecture intent
// ───────────────────
//   • Zero ambient cost — nothing runs unless an admin explicitly requests it.
//   • Freshness is "now" — there is no lag between an order being delivered
//     and it showing up in the next call.
//   • Read cost is capped by MAX_RANGE_DAYS so an accidental "last 5 years"
//     query can't detonate the Firestore bill.
//
// Source fields we rely on (all present today)
// ────────────────────────────────────────────
//   orders-food:
//     deliveryAddress.mainRegion, deliveryAddress.city   (buyer district +
//                                                         neighborhood)
//     restaurantCity, restaurantSubcity                  (pickup district +
//                                                         neighborhood — newly
//                                                         denormalized in CF-27
//                                                         and CF-30; pre-existing
//                                                         orders lack these and
//                                                         are bucketed as
//                                                         'Unknown')
//     createdAt, updatedAt, status, totalPrice, cargoUserId
//
//   Naming is a little confusing because the source docs aren't symmetric:
//     buyer.deliveryAddress uses   { mainRegion, city }
//     restaurant doc uses          { city, subcity }
//   But semantically both are { broader district, specific neighborhood }.
//   We normalise to { mainRegion, city } in the aggregation output so a
//   dashboard can display both sides with identical column headers.
//
//   orders-market:
//     deliveryAddress.city, deliveryAddress.mainRegion   (buyer area only —
//                                                         pickup is the fixed
//                                                         central warehouse, not
//                                                         tracked here by design)
//     createdAt, updatedAt, status, totalPrice, cargoUserId
//
// Delivery-time metric
//   For any order where status === 'delivered', we define:
//     deliveryMinutes = (order.updatedAt - order.createdAt) / 60000
//   i.e. wall-clock minutes from order placement to delivery. We filter out
//   absurd values (< 0 or > 6 h) — those are data anomalies.

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

// Europe/Istanbul is UTC+3 year-round (no DST); matches CF-36/CF-53 convention.
const TZ_OFFSET_MS = 3 * 60 * 60 * 1000;

// Pagination + cost guards.
const PAGE_SIZE       = 500;
const MAX_RANGE_DAYS  = 90;
const DEFAULT_TOP_N   = 20;
const MAX_TOP_N       = 100;

// Sanity-bound the delivery-minutes metric. Anything outside this range is
// treated as a data anomaly and excluded from time statistics (but still
// counted toward deliveredOrders so totals stay honest).
const MAX_SANE_DELIVERY_MS = 6 * 60 * 60 * 1000;   // 6 hours

const ORDER_STATUS_DELIVERED = 'delivered';
const ORDER_STATUS_REJECTED  = 'rejected';
const ORDER_STATUS_CANCELLED = 'cancelled';

const UNKNOWN_AREA = { mainRegion: 'Unknown', city: 'Unknown' };

// ─── Time helpers ──────────────────────────────────────────────────────────

function parseYmd(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const [y, m, d] = s.split('-').map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return { y, m, d };
}

function turkeyMidnightUtc(y, m, d) {
  // Midnight in Europe/Istanbul expressed as a UTC Date.
  return new Date(Date.UTC(y, m - 1, d) - TZ_OFFSET_MS);
}

function daysBetween(fromDate, toDate) {
  return Math.round((toDate.getTime() - fromDate.getTime()) / 86400000);
}

// ─── Aggregation primitives ────────────────────────────────────────────────

function round2(n) {
  return Math.round(n * 100) / 100;
}

function areaKey(mainRegion, city) {
  return `${mainRegion}||${city}`;
}

// Named histogram buckets for delivery-minute distribution. Ordering matters
// for readable output, so we return an array of {bucket, count} in the final
// payload rather than an object.
const BUCKET_DEFS = [
  { key: 'bucket_0_15',    label: '0-15 min',   max: 15 },
  { key: 'bucket_15_30',   label: '15-30 min',  max: 30 },
  { key: 'bucket_30_45',   label: '30-45 min',  max: 45 },
  { key: 'bucket_45_60',   label: '45-60 min',  max: 60 },
  { key: 'bucket_60plus',  label: '60+ min',    max: Infinity },
];

function bucketKeyForMinutes(mins) {
  for (const b of BUCKET_DEFS) {
    if (mins < b.max) return b.key;
  }
  return 'bucket_60plus';
}

function initAreaAgg(mainRegion, city) {
  const agg = {
    mainRegion,
    city,
    totalOrders: 0,
    foodOrders: 0,
    marketOrders: 0,
    deliveredOrders: 0,
    cancelledOrders: 0,
    rejectedOrders: 0,
    inFlightOrders: 0,   // created in range, not yet terminal at query time
    totalRevenue: 0,
    deliveredRevenue: 0,
    sumDeliveryMs: 0,
    deliveryCount: 0,    // sample size for avg (may be < deliveredOrders if anomalies filtered)
    minDeliveryMs: null,
    maxDeliveryMs: null,
  };
  for (const b of BUCKET_DEFS) agg[b.key] = 0;
  return agg;
}

function normalizeArea(mainRegion, city) {
  const mr = (typeof mainRegion === 'string' && mainRegion.trim()) ? mainRegion.trim() : UNKNOWN_AREA.mainRegion;
  const ct = (typeof city === 'string' && city.trim()) ? city.trim() : UNKNOWN_AREA.city;
  return { mainRegion: mr, city: ct };
}

function buyerAreaOf(order) {
  const addr = order && order.deliveryAddress;
  if (!addr || typeof addr !== 'object') return UNKNOWN_AREA;
  return normalizeArea(addr.mainRegion, addr.city);
}

function restaurantAreaOf(order) {
  // Restaurant doc stores `city` (broader district, e.g. "Gazimağusa") and
  // `subcity` (specific neighborhood, e.g. "Karakol"). We denormalized them
  // as restaurantCity + restaurantSubcity on the order. Map them to the
  // same { mainRegion, city } shape as buyer areas so the dashboard can
  // render both sides with the same columns.
  //
  // Pre-denormalization orders (created before the CF-27/CF-30 change) won't
  // have these fields and bucket as 'Unknown'. That bucket should shrink to
  // zero as old orders age out of query windows.
  return normalizeArea(order && order.restaurantCity, order && order.restaurantSubcity);
}

function deliveryMs(order) {
  if (order.status !== ORDER_STATUS_DELIVERED) return null;
  const createdAt = order.createdAt && order.createdAt.toMillis && order.createdAt.toMillis();
  const updatedAt = order.updatedAt && order.updatedAt.toMillis && order.updatedAt.toMillis();
  if (!createdAt || !updatedAt) return null;
  const ms = updatedAt - createdAt;
  if (ms <= 0 || ms > MAX_SANE_DELIVERY_MS) return null;
  return ms;
}

function accumulate(agg, order, { isMarket }) {
  const revenue = typeof order.totalPrice === 'number' ? order.totalPrice : 0;
  const status = order.status || '';

  agg.totalOrders += 1;
  if (isMarket) agg.marketOrders += 1;
  else agg.foodOrders += 1;
  agg.totalRevenue = round2(agg.totalRevenue + revenue);

  if (status === ORDER_STATUS_DELIVERED) {
    agg.deliveredOrders += 1;
    agg.deliveredRevenue = round2(agg.deliveredRevenue + revenue);

    const ms = deliveryMs(order);
    if (ms !== null) {
      agg.sumDeliveryMs += ms;
      agg.deliveryCount += 1;
      if (agg.minDeliveryMs === null || ms < agg.minDeliveryMs) agg.minDeliveryMs = ms;
      if (agg.maxDeliveryMs === null || ms > agg.maxDeliveryMs) agg.maxDeliveryMs = ms;
      agg[bucketKeyForMinutes(ms / 60000)] += 1;
    }
  } else if (status === ORDER_STATUS_CANCELLED) {
    agg.cancelledOrders += 1;
  } else if (status === ORDER_STATUS_REJECTED) {
    agg.rejectedOrders += 1;
  } else {
    agg.inFlightOrders += 1;
  }
}

function finalizeArea(agg) {
  const avgMs = agg.deliveryCount > 0 ? agg.sumDeliveryMs / agg.deliveryCount : null;
  const msToMin = (ms) => (ms === null ? null : Math.round((ms / 60000) * 10) / 10);

  return {
    mainRegion: agg.mainRegion,
    city: agg.city,
    totalOrders: agg.totalOrders,
    foodOrders: agg.foodOrders,
    marketOrders: agg.marketOrders,
    deliveredOrders: agg.deliveredOrders,
    cancelledOrders: agg.cancelledOrders,
    rejectedOrders: agg.rejectedOrders,
    inFlightOrders: agg.inFlightOrders,
    totalRevenue: agg.totalRevenue,
    deliveredRevenue: agg.deliveredRevenue,
    avgDeliveryMinutes: msToMin(avgMs),
    minDeliveryMinutes: msToMin(agg.minDeliveryMs),
    maxDeliveryMinutes: msToMin(agg.maxDeliveryMs),
    deliverySampleSize: agg.deliveryCount,
    deliveryBuckets: BUCKET_DEFS.map((b) => ({
      label: b.label,
      count: agg[b.key],
    })),
  };
}

// ─── Order streaming ───────────────────────────────────────────────────────
//
// Paginated scan of a single collection over a timestamp range. We orderBy
// createdAt so pagination is deterministic, and fan out into two parallel
// streams (food + market). Memory is bounded by the aggregation Maps, not the
// raw order list — we never hold all docs at once.

async function streamCollection(db, collection, startTs, endTs, handler) {
  let lastDoc = null;
  let totalDocs = 0;

  for (;;) {
    let query = db
      .collection(collection)
      .where('createdAt', '>=', startTs)
      .where('createdAt', '<', endTs)
      .orderBy('createdAt')
      .limit(PAGE_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) return totalDocs;

    for (const doc of snap.docs) {
      handler(doc.data());
    }
    totalDocs += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) return totalDocs;
  }
}

// ─── Ranking helpers ───────────────────────────────────────────────────────

function rankBy(areas, metric, direction, topN, { minSample = 0 } = {}) {
  const filtered = minSample > 0 ?
    areas.filter((a) => (a.deliverySampleSize || 0) >= minSample) :
    areas.slice();

  filtered.sort((a, b) => {
    const va = a[metric];
    const vb = b[metric];
    // Nulls sort last regardless of direction.
    if (va === null || va === undefined) return 1;
    if (vb === null || vb === undefined) return -1;
    return direction === 'desc' ? vb - va : va - vb;
  });

  return filtered.slice(0, topN).map((a) => ({
    mainRegion: a.mainRegion,
    city: a.city,
    value: a[metric],
    orders: a.totalOrders,
    deliveredOrders: a.deliveredOrders,
    sampleSize: a.deliverySampleSize || 0,
  }));
}

// ─── Callable ──────────────────────────────────────────────────────────────

export const getAreaAnalytics = onCall(
  { region: REGION, memory: '512MiB', timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const record = await admin.auth().getUser(request.auth.uid);
    const claims = record.customClaims || {};
    if (claims.isAdmin !== true && claims.masterCourier !== true) {
      throw new HttpsError(
        'permission-denied',
        'Only admins or master couriers can call this.',
      );
    }

    // ── Input parsing ────────────────────────────────────────────────────
    const data = request.data || {};
    const fromYmd = parseYmd(data.from);
    const toYmd   = parseYmd(data.to);
    if (!fromYmd || !toYmd) {
      throw new HttpsError(
        'invalid-argument',
        'from and to must be YYYY-MM-DD strings.',
      );
    }
    const topN = Math.min(
      Math.max(parseInt(data.topN, 10) || DEFAULT_TOP_N, 1),
      MAX_TOP_N,
    );

    const startUtc = turkeyMidnightUtc(fromYmd.y, fromYmd.m, fromYmd.d);
    // `to` is inclusive of the named day → end = midnight of the NEXT day.
    const endUtc   = turkeyMidnightUtc(toYmd.y, toYmd.m, toYmd.d + 1);
    if (endUtc <= startUtc) {
      throw new HttpsError('invalid-argument', 'to must be >= from.');
    }

    const days = daysBetween(startUtc, endUtc);
    if (days > MAX_RANGE_DAYS) {
      throw new HttpsError(
        'invalid-argument',
        `Range too large: ${days} days (max ${MAX_RANGE_DAYS}).`,
      );
    }

    const startTs = admin.firestore.Timestamp.fromDate(startUtc);
    const endTs   = admin.firestore.Timestamp.fromDate(endUtc);

    // ── Aggregation ──────────────────────────────────────────────────────
    const db = admin.firestore();
    const byBuyer      = new Map(); // buyer delivery address (food + market)
    const byRestaurant = new Map(); // restaurant pickup area (food only)
    const totals = initAreaAgg('__ALL__', '__ALL__');

    const handleFood = (order) => {
      accumulate(totals, order, { isMarket: false });

      const buyer = buyerAreaOf(order);
      const bk = areaKey(buyer.mainRegion, buyer.city);
      if (!byBuyer.has(bk)) byBuyer.set(bk, initAreaAgg(buyer.mainRegion, buyer.city));
      accumulate(byBuyer.get(bk), order, { isMarket: false });

      const rest = restaurantAreaOf(order);
      const rk = areaKey(rest.mainRegion, rest.city);
      if (!byRestaurant.has(rk)) byRestaurant.set(rk, initAreaAgg(rest.mainRegion, rest.city));
      accumulate(byRestaurant.get(rk), order, { isMarket: false });
    };

    const handleMarket = (order) => {
      accumulate(totals, order, { isMarket: true });

      const buyer = buyerAreaOf(order);
      const bk = areaKey(buyer.mainRegion, buyer.city);
      if (!byBuyer.has(bk)) byBuyer.set(bk, initAreaAgg(buyer.mainRegion, buyer.city));
      accumulate(byBuyer.get(bk), order, { isMarket: true });
      // By design, market orders don't contribute to `byRestaurant` —
      // the pickup is always the central warehouse.
    };

    const t0 = Date.now();
    const [foodCount, marketCount] = await Promise.all([
      streamCollection(db, 'orders-food',   startTs, endTs, handleFood),
      streamCollection(db, 'orders-market', startTs, endTs, handleMarket),
    ]);
    const elapsedMs = Date.now() - t0;

    const buyerAreas      = Array.from(byBuyer.values()).map(finalizeArea);
    const restaurantAreas = Array.from(byRestaurant.values()).map(finalizeArea);
    const totalsFinal     = finalizeArea(totals);

    // For delivery-time rankings, require at least 5 delivered samples per
    // area so a single fluke order doesn't top the "slowest" list.
    const MIN_SAMPLE_FOR_TIME_RANKING = 5;

    const rankings = {
      topDemandByBuyerArea: rankBy(buyerAreas, 'totalOrders', 'desc', topN),
      topDemandByRestaurantArea: rankBy(restaurantAreas, 'totalOrders', 'desc', topN),
      slowestDeliveryByBuyerArea: rankBy(
        buyerAreas, 'avgDeliveryMinutes', 'desc', topN,
        { minSample: MIN_SAMPLE_FOR_TIME_RANKING },
      ),
      fastestDeliveryByBuyerArea: rankBy(
        buyerAreas, 'avgDeliveryMinutes', 'asc', topN,
        { minSample: MIN_SAMPLE_FOR_TIME_RANKING },
      ),
      slowestDeliveryByRestaurantArea: rankBy(
        restaurantAreas, 'avgDeliveryMinutes', 'desc', topN,
        { minSample: MIN_SAMPLE_FOR_TIME_RANKING },
      ),
      fastestDeliveryByRestaurantArea: rankBy(
        restaurantAreas, 'avgDeliveryMinutes', 'asc', topN,
        { minSample: MIN_SAMPLE_FOR_TIME_RANKING },
      ),
      topRevenueByBuyerArea: rankBy(buyerAreas, 'totalRevenue', 'desc', topN),
    };

    console.info(
      `[AreaAnalytics] ${fromYmd.y}-${fromYmd.m}-${fromYmd.d} → ` +
      `${toYmd.y}-${toYmd.m}-${toYmd.d}: food=${foodCount} market=${marketCount} ` +
      `areas=${buyerAreas.length}/${restaurantAreas.length} in ${elapsedMs}ms`,
    );

    return {
      range: {
        from: data.from,
        to: data.to,
        days,
      },
      scanned: {
        foodOrders: foodCount,
        marketOrders: marketCount,
        totalOrders: foodCount + marketCount,
        elapsedMs,
      },
      totals: totalsFinal,
      byBuyerArea: buyerAreas,
      byRestaurantArea: restaurantAreas,
      rankings,
    };
  },
);
