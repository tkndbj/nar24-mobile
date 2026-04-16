
/* eslint-disable valid-jsdoc */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

// ─── Constants ───────────────────────────────────────────────────────────────

const REGION           = 'europe-west3';
const TZ_OFFSET_MS = 3 * 60 * 60 * 1000; // Europe/Istanbul = UTC+3 (fixed, no DST)
const PAGE_SIZE        = 500;                 // Firestore pagination limit
const WRITE_BATCH_SIZE = 400;                 // Firestore batch write cap (< 500)
const TOP_ITEMS_LIMIT  = 10;                  // Top-N items stored per period

const ORDERS_COLL  = 'orders-market';
const DAILY_COLL   = 'market-accounting-daily';
const WEEKLY_COLL  = 'market-accounting-weekly';
const MONTHLY_COLL = 'market-accounting-monthly';

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


function initAggregate() {
  return {
    // Order counts
    totalOrders: 0,
    completedOrders: 0, // status === 'delivered'
    activeOrders: 0, // all non-rejected, non-delivered (in-flight)
    cancelledOrders: 0, // status === 'rejected'
    // Revenue — rejected orders are excluded from all revenue fields
    grossRevenue: 0, // active + completed
    deliveredRevenue: 0, // completed only (fully settled)
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
      unknown: { count: 0, amount: 0 }, // delivered orders where courier didn't record it
    },
    statusBreakdown: {}, // dynamic — { [status]: { count, amount } }
    // ── Category breakdown ────────────────────────────────────────────────
    categoryBreakdown: {}, // dynamic — { [category]: { count, amount } }
    // ── Transient ──────────────────────────────────────────────────────────
    _itemMap: new Map(), // name → { quantity, revenue }  (stripped on finalise)
  };
}

function accumulateOrder(agg, order) {
  const status  = order.status        || 'unknown';
  const total   = order.totalPrice    || 0;
  const sub     = order.subtotal      || 0;
  const fee     = order.deliveryFee   || 0;
  const payment = order.paymentMethod || 'pay_at_door';

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

  // ── Category breakdown ────────────────────────────────────────────────────
  if (Array.isArray(order.items)) {
    for (const item of order.items) {
      const cat = item.category || 'uncategorized';
      if (!agg.categoryBreakdown[cat]) {
        agg.categoryBreakdown[cat] = { count: 0, amount: 0 };
      }
      agg.categoryBreakdown[cat].count += (item.quantity || 1);
      agg.categoryBreakdown[cat].amount = round2(
        agg.categoryBreakdown[cat].amount + (item.itemTotal || 0)
      );
    }
  }

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

async function streamOrders(db, startTime, endTime) {
  const startTs = admin.firestore.Timestamp.fromDate(startTime);
  const endTs   = admin.firestore.Timestamp.fromDate(endTime);

  const agg       = initAggregate();
  let lastDoc     = null;
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
      accumulateOrder(agg, order);
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break; // Last page
  }

  console.info(
    `[MarketAccounting] Streamed ${totalDocs} orders across ${pagesFetched} page(s).`
  );

  return { agg, totalDocs };
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
      `[MarketAccounting] Committed batch ${Math.floor(i / WRITE_BATCH_SIZE) + 1} ` +
      `(${slice.length} docs) → ${collectionName}`
    );
  }
}

async function runJob(db, collectionName, periodKey, periodStart, periodEnd) {
  const { agg, totalDocs } = await streamOrders(db, periodStart, periodEnd);

  if (totalDocs === 0) {
    console.info(`[MarketAccounting] No orders found for period ${periodKey}.`);
    return {
      success: true,
      periodKey,
      totalOrders: 0,
      totalGrossRevenue: 0,
      message: 'No orders found for this period.',
    };
  }

  const doc = finaliseAggregate(agg, periodKey, periodStart, periodEnd);
  const entries = [{ docId: `MARKET_${periodKey}`, data: doc }];

  await writeBatched(db, collectionName, entries);

  console.info(
    `[MarketAccounting] ✓ Period ${periodKey}: ` +
    `${doc.totalOrders} orders, ${doc.grossRevenue} TL gross revenue. ` +
    `Wrote ${entries.length} doc(s) to ${collectionName}.`
  );

  return {
    success: true,
    periodKey,
    totalOrders: doc.totalOrders,
    totalGrossRevenue: doc.grossRevenue,
    docsWritten: entries.length,
  };
}

export const calculateDailyMarketAccounting = onCall(
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

    const { date } = request.data || {};

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

    const periodKey      = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const { start, end } = turkeyDayBounds(year, month, day);

    console.info(
      `[MarketAccounting] Daily job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), DAILY_COLL, periodKey, start, end);
  }
);

export const calculateWeeklyMarketAccounting = onCall(
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

    const { year: rawYear, week: rawWeek } = request.data || {};

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

    const weekStr        = String(week).padStart(2, '0');
    const periodKey      = `${year}-W${weekStr}`;
    const { start, end } = turkeyWeekBounds(year, week);

    console.info(
      `[MarketAccounting] Weekly job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), WEEKLY_COLL, periodKey, start, end);
  }
);

export const calculateMonthlyMarketAccounting = onCall(
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

    const { year: rawYear, month: rawMonth } = request.data || {};

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

    const periodKey      = `${year}-${String(month).padStart(2, '0')}`;
    const { start, end } = turkeyMonthBounds(year, month);

    console.info(
      `[MarketAccounting] Monthly job started: ${periodKey} ` +
      `| UTC [${start.toISOString()}, ${end.toISOString()})`
    );

    return runJob(admin.firestore(), MONTHLY_COLL, periodKey, start, end);
  }
);
