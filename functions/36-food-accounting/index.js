
/* eslint-disable valid-jsdoc */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

// ─── Constants ───────────────────────────────────────────────────────────────

const REGION           = 'europe-west3';
const TZ_OFFSET_MS = 3 * 60 * 60 * 1000; // Europe/Istanbul = UTC+3 (fixed, no DST)
const PAGE_SIZE        = 500;                 // Firestore pagination limit
const WRITE_BATCH_SIZE = 400;                 // Firestore batch write cap (< 500)
const TOP_ITEMS_LIMIT  = 10;                  // Top-N items stored per restaurant

const ORDERS_COLL  = 'orders-food';
const DAILY_COLL   = 'food-accounting-daily';
const WEEKLY_COLL  = 'food-accounting-weekly';
const MONTHLY_COLL = 'food-accounting-monthly';

const COMPLETED_STATUS = 'delivered';
const CANCELLED_STATUS = 'rejected';

// ============================================================================
// SECTION 1 — TURKEY TIME HELPERS
// ============================================================================

function turkeyDayBounds(year, month, day) {
  const start = new Date(Date.UTC(year, month - 1, day)     - TZ_OFFSET_MS);
  const end = new Date(Date.UTC(year, month - 1, day + 1) - TZ_OFFSET_MS);
  return { start, end };
}

function turkeyWeekBounds(year, isoWeek) {
  const jan4      = new Date(Date.UTC(year, 0, 4));
  const jan4Dow   = (jan4.getUTCDay() + 6) % 7;                               // Mon = 0
  const mondayUtc = new Date(
    jan4.getTime() - jan4Dow * 86400000 + (isoWeek - 1) * 7 * 86400000
  );
  const start = new Date(mondayUtc.getTime()                   - TZ_OFFSET_MS);
  const end = new Date(mondayUtc.getTime() + 7 * 86400000 - TZ_OFFSET_MS);
  return { start, end };
}

function turkeyMonthBounds(year, month) {
  const start = new Date(Date.UTC(year, month - 1, 1) - TZ_OFFSET_MS);
  const end   = new Date(Date.UTC(year, month,     1) - TZ_OFFSET_MS);
  return { start, end };
}

function isoWeekAndYear(utcDate) {
  // Snap to midnight UTC for the same y/m/d
  const d   = new Date(Date.UTC(utcDate.getUTCFullYear(), utcDate.getUTCMonth(), utcDate.getUTCDate()));
  const dow = (d.getUTCDay() + 6) % 7;                 // Mon = 0
  d.setUTCDate(d.getUTCDate() - dow + 3);               // Thursday of this ISO week
  const y1  = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  const y1d = (y1.getUTCDay() + 6) % 7;
  y1.setUTCDate(y1.getUTCDate() - y1d + 3);             // Thursday of week 1
  const week = 1 + Math.round((d - y1) / (7 * 86400000));
  return { year: d.getUTCFullYear(), week };
}


function yesterdayTurkey() {
    const d = new Date(Date.now() + TZ_OFFSET_MS - 86400000);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}


function lastWeekTurkey() {
    return isoWeekAndYear(new Date(Date.now() + TZ_OFFSET_MS - 7 * 86400000));
}


function lastMonthTurkey() {
  const d = new Date(Date.now() + TZ_OFFSET_MS);
  let year  = d.getUTCFullYear();
  let month = d.getUTCMonth() + 1; // 1-12
  if (--month === 0) {month = 12; year--;}
  return { year, month };
}

// ============================================================================
// SECTION 2 — AGGREGATION ENGINE
// ============================================================================


function round2(n) {
  return Math.round(n * 100) / 100;
}


function initAggregate(restaurantId, restaurantName) {
  return {
    restaurantId,
    restaurantName: restaurantName || '',
    // Order counts
    totalOrders: 0,
    completedOrders: 0,
    activeOrders: 0,
    cancelledOrders: 0,
    // Revenue
    grossRevenue: 0,
    deliveredRevenue: 0,
    subtotalRevenue: 0,
    deliveryFeeRevenue: 0,
    totalItemsSold: 0,
    paymentBreakdown: {
      card: { count: 0, amount: 0 },
      pay_at_door: { count: 0, amount: 0 },
    },
    paymentReceivedBreakdown: {
      card: { count: 0, amount: 0 },
      cash: { count: 0, amount: 0 },
      iban: { count: 0, amount: 0 },
      unknown: { count: 0, amount: 0 },
    },
    deliveryTypeBreakdown: {
      delivery: { count: 0, amount: 0 },
      pickup: { count: 0, amount: 0 },
    },
    statusBreakdown: {},
 
    // ── NEW: Platform economics (from immutable fees snapshot) ───────
    // All figures are derived from order.fees, which is frozen at accept
    // time by updateFoodOrderStatus. Rate changes never affect these.
    //
    // platformRevenue  = commission + shipment fee collected by Nar24
    // restaurantPayout = subtotal − commission − shipment fee
    platformRevenue: 0,
    commissionRevenue: 0,
    shipmentFeeRevenue: 0,
    restaurantPayout: 0,
    // Orders created before Step 3 have no fees snapshot — tracked
    // separately so the admin can see the blast radius.
    ordersWithoutFeesSnapshot: 0,
 
    // ── NEW: Courier-type breakdown ──────────────────────────────────
    // 'ours'   → Nar24 courier, shipment fee applied, auto-dispatched
    // 'theirs' → restaurant's own courier, no shipment fee
    // 'legacy' → pre-Step-3 orders with no courierType field
    courierTypeBreakdown: {
      ours: { count: 0, amount: 0, platformRevenue: 0 },
      theirs: { count: 0, amount: 0, platformRevenue: 0 },
      legacy: { count: 0, amount: 0, platformRevenue: 0 },
    },
 
    // ── Transient ────────────────────────────────────────────────────
    _itemMap: new Map(),
  };
}


function accumulateOrder(agg, order) {
  const status  = order.status        || 'unknown';
  const total   = order.totalPrice    || 0;
  const sub     = order.subtotal      || 0;
  const fee     = order.deliveryFee   || 0;
  const payment = order.paymentMethod || 'pay_at_door';
  const delType = order.deliveryType  || 'delivery';

  agg.totalOrders++;

  // ── Status breakdown (all orders, incl. cancelled) ──────────────────────
  if (!agg.statusBreakdown[status]) {
    agg.statusBreakdown[status] = { count: 0, amount: 0 };
  }
  agg.statusBreakdown[status].count++;
  agg.statusBreakdown[status].amount = round2(agg.statusBreakdown[status].amount + total);

  // ── Rejected orders do not contribute to revenue ─────────────────────────
  if (status === CANCELLED_STATUS) {
    agg.cancelledOrders++;
    return;
  }

  // ── Revenue ───────────────────────────────────────────────────────────────
  agg.grossRevenue      = round2(agg.grossRevenue      + total);
  agg.subtotalRevenue   = round2(agg.subtotalRevenue   + sub);
  agg.deliveryFeeRevenue= round2(agg.deliveryFeeRevenue+ fee);

  if (status === COMPLETED_STATUS) {
    agg.completedOrders++;
    agg.deliveredRevenue = round2(agg.deliveredRevenue + total);
  } else {
    agg.activeOrders++;
  }

  // ── Payment breakdown ─────────────────────────────────────────────────────
  const pKey = payment === 'card' ? 'card' : 'pay_at_door';
  agg.paymentBreakdown[pKey].count++;
  agg.paymentBreakdown[pKey].amount = round2(agg.paymentBreakdown[pKey].amount + total);

  // ── Payment received breakdown (delivered orders only) ────────────────────
if (status === COMPLETED_STATUS) {
  const received = order.paymentReceivedMethod;
  const rKey = (received === 'card' || received === 'cash' || received === 'iban') ?
    received :
    'unknown';
  agg.paymentReceivedBreakdown[rKey].count++;
  agg.paymentReceivedBreakdown[rKey].amount = round2(
    agg.paymentReceivedBreakdown[rKey].amount + total
  );
}

  // ── Delivery type breakdown ───────────────────────────────────────────────
  const dKey = delType === 'pickup' ? 'pickup' : 'delivery';
  agg.deliveryTypeBreakdown[dKey].count++;
  agg.deliveryTypeBreakdown[dKey].amount = round2(agg.deliveryTypeBreakdown[dKey].amount + total);

    // ── Platform economics (from frozen fees snapshot) ─────────────────
  // Reads the fees snapshot written by updateFoodOrderStatus. Orders
  // created before Step 3 won't have it — counted separately.
  const fees = order.fees;
  if (fees && typeof fees === 'object') {
    const commAmt = Number(fees.commissionAmount)   || 0;
    const shipAmt = Number(fees.shipmentFeeApplied) || 0;
    const platRev = Number(fees.platformRevenue)    || 0;
    const restPay = Number(fees.restaurantPayout)   || 0;
 
    agg.commissionRevenue  = round2(agg.commissionRevenue  + commAmt);
    agg.shipmentFeeRevenue = round2(agg.shipmentFeeRevenue + shipAmt);
    agg.platformRevenue    = round2(agg.platformRevenue    + platRev);
    agg.restaurantPayout   = round2(agg.restaurantPayout   + restPay);
  } else {
    agg.ordersWithoutFeesSnapshot++;
  }
 
  // Courier-type breakdown. 'legacy' catches pre-Step-3 orders where
  // courierType was never set — useful for spotting tail orders after
  // the migration.
  const ctKey = order.courierType === 'ours'   ? 'ours' : order.courierType === 'theirs' ? 'theirs' : 'legacy';
  agg.courierTypeBreakdown[ctKey].count++;
  agg.courierTypeBreakdown[ctKey].amount = round2(
    agg.courierTypeBreakdown[ctKey].amount + total,
  );
  agg.courierTypeBreakdown[ctKey].platformRevenue = round2(
    agg.courierTypeBreakdown[ctKey].platformRevenue +
      (fees?.platformRevenue || 0),
  );

  // ── Item-level aggregation ────────────────────────────────────────────────
  agg.totalItemsSold += (order.itemCount || 0);

  if (Array.isArray(order.items)) {
    for (const item of order.items) {
      if (!item?.name) continue;
      const prev = agg._itemMap.get(item.name) || { quantity: 0, revenue: 0 };
      agg._itemMap.set(item.name, {
        quantity: prev.quantity + (item.quantity || 1),
        revenue: round2(prev.revenue + (item.itemTotal || 0)),
      });
    }
  }
}

function rollupToPlatform(platform, restaurant) {
  platform.totalOrders        += restaurant.totalOrders;
  platform.completedOrders    += restaurant.completedOrders;
  platform.activeOrders       += restaurant.activeOrders;
  platform.cancelledOrders    += restaurant.cancelledOrders;
  platform.grossRevenue        = round2(platform.grossRevenue        + restaurant.grossRevenue);
  platform.deliveredRevenue    = round2(platform.deliveredRevenue    + restaurant.deliveredRevenue);
  platform.subtotalRevenue     = round2(platform.subtotalRevenue     + restaurant.subtotalRevenue);
  platform.deliveryFeeRevenue  = round2(platform.deliveryFeeRevenue  + restaurant.deliveryFeeRevenue);
  platform.totalItemsSold     += restaurant.totalItemsSold;

  for (const [pKey, v] of Object.entries(restaurant.paymentBreakdown)) {
    if (!platform.paymentBreakdown[pKey]) {
      platform.paymentBreakdown[pKey] = { count: 0, amount: 0 };
    }
    platform.paymentBreakdown[pKey].count += v.count;
    platform.paymentBreakdown[pKey].amount = round2(
      platform.paymentBreakdown[pKey].amount + v.amount
    );
  }

  for (const [dKey, v] of Object.entries(restaurant.deliveryTypeBreakdown)) {
    if (!platform.deliveryTypeBreakdown[dKey]) {
      platform.deliveryTypeBreakdown[dKey] = { count: 0, amount: 0 };
    }
    platform.deliveryTypeBreakdown[dKey].count  += v.count;
    platform.deliveryTypeBreakdown[dKey].amount  = round2(
      platform.deliveryTypeBreakdown[dKey].amount + v.amount
    );
  }

  for (const [sKey, v] of Object.entries(restaurant.statusBreakdown)) {
    if (!platform.statusBreakdown[sKey]) {
      platform.statusBreakdown[sKey] = { count: 0, amount: 0 };
    }
    platform.statusBreakdown[sKey].count  += v.count;
    platform.statusBreakdown[sKey].amount  = round2(
      platform.statusBreakdown[sKey].amount + v.amount
    );
  }

  for (const [rKey, v] of Object.entries(restaurant.paymentReceivedBreakdown)) {
    if (!platform.paymentReceivedBreakdown[rKey]) {
      platform.paymentReceivedBreakdown[rKey] = { count: 0, amount: 0 };
    }
    platform.paymentReceivedBreakdown[rKey].count  += v.count;
    platform.paymentReceivedBreakdown[rKey].amount  = round2(
      platform.paymentReceivedBreakdown[rKey].amount + v.amount
    );
  }

  // Merge full item map (not just top-10) for accurate platform top-items
  for (const [name, v] of restaurant._itemMap.entries()) {
    const prev = platform._itemMap.get(name) || { quantity: 0, revenue: 0 };
    platform._itemMap.set(name, {
      quantity: prev.quantity + v.quantity,
      revenue: round2(prev.revenue + v.revenue),
    });
  }
    // ── NEW: Platform economics rollup ─────────────────────────────────
    platform.platformRevenue    = round2(platform.platformRevenue    + restaurant.platformRevenue);
    platform.commissionRevenue  = round2(platform.commissionRevenue  + restaurant.commissionRevenue);
    platform.shipmentFeeRevenue = round2(platform.shipmentFeeRevenue + restaurant.shipmentFeeRevenue);
    platform.restaurantPayout   = round2(platform.restaurantPayout   + restaurant.restaurantPayout);
    platform.ordersWithoutFeesSnapshot += restaurant.ordersWithoutFeesSnapshot;
   
    // Courier-type breakdown rollup
    for (const [ctKey, v] of Object.entries(restaurant.courierTypeBreakdown)) {
      if (!platform.courierTypeBreakdown[ctKey]) {
        platform.courierTypeBreakdown[ctKey] = { count: 0, amount: 0, platformRevenue: 0 };
      }
      platform.courierTypeBreakdown[ctKey].count          += v.count;
      platform.courierTypeBreakdown[ctKey].amount          = round2(
        platform.courierTypeBreakdown[ctKey].amount + v.amount,
      );
      platform.courierTypeBreakdown[ctKey].platformRevenue = round2(
        platform.courierTypeBreakdown[ctKey].platformRevenue + v.platformRevenue,
      );
    }
}

function finaliseAggregate(agg, periodKey, periodStart, periodEnd) {
  const { _itemMap, ...doc } = agg;

  // Top-N items by quantity sold
  doc.topItems = Array.from(_itemMap.entries())
    .map(([name, v]) => ({ name, ...v }))
    .sort((a, b) => b.quantity - a.quantity)
    .slice(0, TOP_ITEMS_LIMIT);

  const revenueOrderCount = doc.completedOrders + doc.activeOrders;
  doc.averageOrderValue   = revenueOrderCount > 0 ?
    round2(doc.grossRevenue / revenueOrderCount) :
    0;

  doc.periodKey    = periodKey;
  doc.periodStart  = admin.firestore.Timestamp.fromDate(periodStart);
  doc.periodEnd    = admin.firestore.Timestamp.fromDate(periodEnd);
  doc.calculatedAt = admin.firestore.FieldValue.serverTimestamp();

  return doc;
}

// ============================================================================
// SECTION 3 — I/O HELPERS
// ============================================================================

async function assertAdmin(uid) {
    const record = await admin.auth().getUser(uid);
    const claims = record.customClaims || {};
    if (claims.isAdmin !== true && claims.masterCourier !== true) {
      throw new HttpsError('permission-denied', 'Only admins or master couriers can invoke accounting functions.');
    }
  }

async function streamAndGroupOrders(db, startTime, endTime, restaurantIdFilter) {
  const startTs = admin.firestore.Timestamp.fromDate(startTime);
  const endTs   = admin.firestore.Timestamp.fromDate(endTime);
  const filter  = (restaurantIdFilter && restaurantIdFilter.length > 0) ?
    new Set(restaurantIdFilter) :
    null;

  /** @type {Map<string, ReturnType<initAggregate>>} */
  const groups  = new Map();
  let lastDoc   = null;
  let pagesFetched  = 0;
  let totalDocs     = 0;

  for (;;) {
    let query = db
      .collection(ORDERS_COLL)
      .where('createdAt', '>=', startTs)
      .where('createdAt', '<',  endTs)
      .orderBy('createdAt')
      .limit(PAGE_SIZE);

    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) break;

    pagesFetched++;
    totalDocs += snap.size;

    for (const doc of snap.docs) {
      const order = doc.data();
      const rId   = order.restaurantId;

      // Skip orders with no restaurant reference
      if (!rId || typeof rId !== 'string') continue;
      // Skip if caller scoped to specific restaurants
      if (filter && !filter.has(rId)) continue;

      if (!groups.has(rId)) {
        groups.set(rId, initAggregate(rId, order.restaurantName || ''));
      } else if (!groups.get(rId).restaurantName && order.restaurantName) {
        // Backfill name if the first order for this restaurant lacked it
        groups.get(rId).restaurantName = order.restaurantName;
      }

      accumulateOrder(groups.get(rId), order);
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break; // Last page
  }

  console.info(
    `[FoodAccounting] Streamed ${totalDocs} orders across ${pagesFetched} page(s); ` +
    `${groups.size} restaurant(s) found.`
  );

  return groups;
}

async function writeBatched(db, collectionName, entries) {
  for (let i = 0; i < entries.length; i += WRITE_BATCH_SIZE) {
    const slice = entries.slice(i, i + WRITE_BATCH_SIZE);
    const batch = db.batch();
    for (const { docId, data } of slice) {
      batch.set(db.collection(collectionName).doc(docId), data);
    }
    await batch.commit();
    console.info(
      `[FoodAccounting] Committed batch ${Math.floor(i / WRITE_BATCH_SIZE) + 1} ` +
      `(${slice.length} docs) → ${collectionName}`
    );
  }
}

async function runJob(db, collectionName, periodKey, periodStart, periodEnd, restaurantIdFilter) {
  const groups = await streamAndGroupOrders(db, periodStart, periodEnd, restaurantIdFilter);

  if (groups.size === 0) {
    console.info(`[FoodAccounting] No orders found for period ${periodKey}.`);
    return {
      success: true,
      periodKey,
      restaurantCount: 0,
      totalOrders: 0,
      totalGrossRevenue: 0,
      message: 'No orders found for this period.',
    };
  }

  const entries       = [];
  const includeGlobal = !restaurantIdFilter || restaurantIdFilter.length === 0;
  const platformAgg   = includeGlobal ? initAggregate('_PLATFORM', 'Platform Summary') : null;

  let grandTotalOrders  = 0;
  let grandGrossRevenue = 0;

  for (const [rId, agg] of groups.entries()) {
    grandTotalOrders  += agg.totalOrders;
    grandGrossRevenue  = round2(grandGrossRevenue + agg.grossRevenue);

    // Roll up into platform BEFORE finalise strips _itemMap
    if (platformAgg) rollupToPlatform(platformAgg, agg);

    const doc = finaliseAggregate(agg, periodKey, periodStart, periodEnd);
    entries.push({ docId: `${rId}_${periodKey}`, data: doc });
  }

  // Platform summary document
  if (platformAgg) {
    const platformDoc = finaliseAggregate(platformAgg, periodKey, periodStart, periodEnd);
    platformDoc.restaurantCount = groups.size;
    entries.push({ docId: `PLATFORM_${periodKey}`, data: platformDoc });
  }

  await writeBatched(db, collectionName, entries);

  console.info(
    `[FoodAccounting] ✓ Period ${periodKey}: ${groups.size} restaurant(s), ` +
    `${grandTotalOrders} orders, ${grandGrossRevenue} TL gross revenue. ` +
    `Wrote ${entries.length} doc(s) to ${collectionName}.`
  );

  return {
    success: true,
    periodKey,
    restaurantCount: groups.size,
    totalOrders: grandTotalOrders,
    totalGrossRevenue: grandGrossRevenue,
    docsWritten: entries.length,
  };
}

export const calculateDailyFoodAccounting = onCall(
  {
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 540,
    concurrency: 1, // Serialised — prevents duplicate concurrent jobs
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    await assertAdmin(request.auth.uid);

    const { date, restaurantIds = [] } = request.data || {};

    let year; let month; let day;

    if (date) {
      const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
      if (!m) {
        throw new HttpsError('invalid-argument', 'date must be in YYYY-MM-DD format.');
      }
      [, year, month, day] = m.map(Number);
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        throw new HttpsError('invalid-argument', 'date contains an invalid month or day.');
      }
    } else {
      ({ year, month, day } = yesterdayTurkey());
    }

    if (!Array.isArray(restaurantIds)) {
      throw new HttpsError('invalid-argument', 'restaurantIds must be an array.');
    }

    const periodKey      = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const { start, end } = turkeyDayBounds(year, month, day);

    console.info(
      `[FoodAccounting] Daily job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), DAILY_COLL, periodKey, start, end, restaurantIds);
  }
);

export const calculateWeeklyFoodAccounting = onCall(
  {
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 540,
    concurrency: 1,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    await assertAdmin(request.auth.uid);

    const { year: rawYear, week: rawWeek, restaurantIds = [] } = request.data || {};

    let year; let week;

    if (rawYear != null && rawWeek != null) {
      year = Number(rawYear);
      week = Number(rawWeek);
      if (!Number.isInteger(year) || year < 2020 || year > 2100) {
        throw new HttpsError('invalid-argument', 'year must be a valid integer (e.g. 2024).');
      }
      if (!Number.isInteger(week) || week < 1 || week > 53) {
        throw new HttpsError('invalid-argument', 'week must be an integer between 1 and 53.');
      }
    } else if (rawYear == null && rawWeek == null) {
      ({ year, week } = lastWeekTurkey());
    } else {
      throw new HttpsError(
        'invalid-argument',
        'Provide both year and week, or neither (to use last week).'
      );
    }

    if (!Array.isArray(restaurantIds)) {
      throw new HttpsError('invalid-argument', 'restaurantIds must be an array.');
    }

    const weekStr        = String(week).padStart(2, '0');
    const periodKey      = `${year}-W${weekStr}`;
    const { start, end } = turkeyWeekBounds(year, week);

    console.info(
      `[FoodAccounting] Weekly job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), WEEKLY_COLL, periodKey, start, end, restaurantIds);
  }
);

export const calculateMonthlyFoodAccounting = onCall(
  {
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 540,
    concurrency: 1,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    await assertAdmin(request.auth.uid);

    const { year: rawYear, month: rawMonth, restaurantIds = [] } = request.data || {};

    let year; let month;

    if (rawYear != null && rawMonth != null) {
      year  = Number(rawYear);
      month = Number(rawMonth);
      if (!Number.isInteger(year) || year < 2020 || year > 2100) {
        throw new HttpsError('invalid-argument', 'year must be a valid integer (e.g. 2024).');
      }
      if (!Number.isInteger(month) || month < 1 || month > 12) {
        throw new HttpsError('invalid-argument', 'month must be an integer between 1 and 12.');
      }
    } else if (rawYear == null && rawMonth == null) {
      ({ year, month } = lastMonthTurkey());
    } else {
      throw new HttpsError(
        'invalid-argument',
        'Provide both year and month, or neither (to use last month).'
      );
    }

    if (!Array.isArray(restaurantIds)) {
      throw new HttpsError('invalid-argument', 'restaurantIds must be an array.');
    }

    const periodKey      = `${year}-${String(month).padStart(2, '0')}`;
    const { start, end } = turkeyMonthBounds(year, month);

    console.info(
      `[FoodAccounting] Monthly job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), MONTHLY_COLL, periodKey, start, end, restaurantIds);
  }
);
