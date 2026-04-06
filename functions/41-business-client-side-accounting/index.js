/**
 * 41 — Business Client-Side Accounting
 *
 * On-demand report generation for shop and restaurant owners.
 * No scheduled functions — reports are generated when the business
 * owner requests them and persisted in Firestore for future access.
 * Re-generating the same period always overwrites the previous report.
 *
 * ── How it works ──────────────────────────────────────────────
 *
 *   1. Business owner opens their seller panel
 *   2. Selects period (daily / weekly / monthly) and a date
 *   3. Calls generateBusinessReport → scans ONLY their orders/items
 *   4. Report is written to Firestore and returned immediately
 *   5. Future reads hit the stored doc (1 read, no re-scan)
 *
 * ── Storage ───────────────────────────────────────────────────
 *
 *   business-reports/{businessId}/reports/{periodKey}
 *
 *   periodKey examples:
 *     daily_2025-04-05
 *     weekly_2025-W14
 *     monthly_2025-04
 *
 * ── Scalability ───────────────────────────────────────────────
 *
 *   Each callable scans only ONE business's data. With proper
 *   composite indexes the query touches only matching docs:
 *
 *     Restaurants: orders-food  → (restaurantId ASC, createdAt ASC)
 *     Shops:       items (cG)  → (shopId ASC, timestamp ASC)
 *
 *   1 000 businesses generating reports = 1 000 small independent
 *   queries, NOT one giant platform-wide scan. Cloud Functions
 *   auto-scales horizontally to handle concurrent requests.
 *
 * ── Auth ──────────────────────────────────────────────────────
 *
 *   Custom claims (set by invitation CF):
 *     claims.shops       = { [shopId]: role }
 *     claims.restaurants  = { [restaurantId]: role }
 *   Admins (claims.isAdmin / claims.masterCourier) can access any business.
 *
 * ── Exported callables ────────────────────────────────────────
 *
 *   generateBusinessReport  — scan + aggregate + write + return
 *   getBusinessReport       — read a single stored report
 *   listBusinessReports     — paginated list of generated reports
 *   getMyBusinesses         — all businesses from caller's claims
 */
import admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

const REGION       = 'europe-west3';
const TZ_OFFSET_MS = 3 * 60 * 60 * 1000; // Europe/Istanbul = UTC+3 (no DST)
const PAGE_SIZE    = 500;                  // Firestore pagination limit
const TOP_ITEMS    = 10;                   // Top-N items in report

const REPORTS_ROOT = 'business-reports';   // top-level collection
const REPORTS_SUB  = 'reports';            // subcollection per business

const ORDERS_COLL  = 'orders-food';        // restaurant orders
const COMPLETED    = 'delivered';
const CANCELLED    = 'rejected';

// ═══════════════════════════════════════════════════════════════
// TURKEY TIME HELPERS
// ═══════════════════════════════════════════════════════════════

function turkeyDayBounds(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  return {
    start: new Date(Date.UTC(y, m - 1, d)     - TZ_OFFSET_MS),
    end: new Date(Date.UTC(y, m - 1, d + 1) - TZ_OFFSET_MS),
  };
}

function turkeyWeekBounds(year, isoWeek) {
  const jan4    = new Date(Date.UTC(year, 0, 4));
  const jan4Dow = (jan4.getUTCDay() + 6) % 7; // Mon = 0
  const monday  = new Date(
    jan4.getTime() - jan4Dow * 86400000 + (isoWeek - 1) * 7 * 86400000,
  );
  return {
    start: new Date(monday.getTime()                   - TZ_OFFSET_MS),
    end: new Date(monday.getTime() + 7 * 86400000    - TZ_OFFSET_MS),
  };
}

function turkeyMonthBounds(year, month) {
  return {
    start: new Date(Date.UTC(year, month - 1, 1) - TZ_OFFSET_MS),
    end: new Date(Date.UTC(year, month,     1) - TZ_OFFSET_MS),
  };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

// ═══════════════════════════════════════════════════════════════
// AUTH — Custom claims
// ═══════════════════════════════════════════════════════════════

async function getClaims(uid) {
  const record = await admin.auth().getUser(uid);
  return record.customClaims || {};
}

function assertAccess(claims, businessType, businessId) {
  const isAdmin = claims.isAdmin === true || claims.masterCourier === true;
  if (isAdmin) return;

  const map = businessType === 'restaurant' ?
    (claims.restaurants || {}) :
    (claims.shops || {});

  if (!map[businessId]) {
    throw new HttpsError(
      'permission-denied',
      `You do not have access to this ${businessType}. ` +
      'If you were recently invited, refresh your session.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PERIOD RESOLUTION
// ═══════════════════════════════════════════════════════════════

function resolvePeriod(period, data) {
  switch (period) {
    case 'daily': {
      const { date } = data;
      if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        throw new HttpsError('invalid-argument', 'date must be YYYY-MM-DD.');
      }
      const bounds = turkeyDayBounds(date);
      return { periodKey: `daily_${date}`, periodLabel: date, ...bounds };
    }

    case 'weekly': {
      const year = Number(data.year);
      const week = Number(data.week);
      if (!Number.isInteger(year) || year < 2020 || year > 2100) {
        throw new HttpsError('invalid-argument', 'year must be a valid integer.');
      }
      if (!Number.isInteger(week) || week < 1 || week > 53) {
        throw new HttpsError('invalid-argument', 'week must be 1–53.');
      }
      const bounds = turkeyWeekBounds(year, week);
      const label  = `${year}-W${String(week).padStart(2, '0')}`;
      return { periodKey: `weekly_${label}`, periodLabel: label, ...bounds };
    }

    case 'monthly': {
      const year  = Number(data.year);
      const month = Number(data.month);
      if (!Number.isInteger(year) || year < 2020 || year > 2100) {
        throw new HttpsError('invalid-argument', 'year must be a valid integer.');
      }
      if (!Number.isInteger(month) || month < 1 || month > 12) {
        throw new HttpsError('invalid-argument', 'month must be 1–12.');
      }
      const bounds = turkeyMonthBounds(year, month);
      const label  = `${year}-${String(month).padStart(2, '0')}`;
      return { periodKey: `monthly_${label}`, periodLabel: label, ...bounds };
    }

    default:
      throw new HttpsError('invalid-argument', 'period must be daily, weekly, or monthly.');
  }
}

// ═══════════════════════════════════════════════════════════════
// RESTAURANT AGGREGATION
//
// Scans orders-food filtered by restaurantId + createdAt range.
// Composite index required: restaurantId ASC, createdAt ASC
//
// Output matches the admin food-accounting format so the frontend
// can reuse the same rendering components.
// ═══════════════════════════════════════════════════════════════

async function aggregateRestaurantOrders(db, restaurantId, start, end) {
  const tsStart = admin.firestore.Timestamp.fromDate(start);
  const tsEnd   = admin.firestore.Timestamp.fromDate(end);

  // Counters
  let totalOrders = 0; let completedOrders = 0; let activeOrders = 0; let cancelledOrders = 0;
  let grossRevenue = 0; let deliveredRevenue = 0; let subtotalRevenue = 0; let deliveryFeeRevenue = 0;
  let totalItemsSold = 0;

  const paymentBreakdown = {
    card: { count: 0, amount: 0 },
    pay_at_door: { count: 0, amount: 0 },
  };
  const paymentReceivedBreakdown = {
    card: { count: 0, amount: 0 }, cash: { count: 0, amount: 0 },
    iban: { count: 0, amount: 0 }, unknown: { count: 0, amount: 0 },
  };
  const deliveryTypeBreakdown = {
    delivery: { count: 0, amount: 0 },
    pickup: { count: 0, amount: 0 },
  };
  const statusBreakdown = {};
  const itemMap = new Map(); // name → { quantity, revenue }

  let cursor = null;

  for (;;) {
    let q = db
      .collection(ORDERS_COLL)
      .where('restaurantId', '==', restaurantId)
      .where('createdAt', '>=', tsStart)
      .where('createdAt', '<',  tsEnd)
      .orderBy('createdAt')
      .limit(PAGE_SIZE);

    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const order = doc.data();
      const status  = order.status        || 'unknown';
      const total   = order.totalPrice    || 0;
      const sub     = order.subtotal      || 0;
      const fee     = order.deliveryFee   || 0;
      const payment = order.paymentMethod || 'pay_at_door';
      const delType = order.deliveryType  || 'delivery';

      totalOrders++;

      // Status breakdown (all orders)
      if (!statusBreakdown[status]) statusBreakdown[status] = { count: 0, amount: 0 };
      statusBreakdown[status].count++;
      statusBreakdown[status].amount = round2(statusBreakdown[status].amount + total);

      // Cancelled orders excluded from revenue
      if (status === CANCELLED) {cancelledOrders++; continue;}

      grossRevenue      = round2(grossRevenue      + total);
      subtotalRevenue   = round2(subtotalRevenue   + sub);
      deliveryFeeRevenue = round2(deliveryFeeRevenue + fee);

      if (status === COMPLETED) {
        completedOrders++;
        deliveredRevenue = round2(deliveredRevenue + total);
      } else {
        activeOrders++;
      }

      // Payment method
      const pKey = payment === 'card' ? 'card' : 'pay_at_door';
      paymentBreakdown[pKey].count++;
      paymentBreakdown[pKey].amount = round2(paymentBreakdown[pKey].amount + total);

      // Payment received (delivered only)
      if (status === COMPLETED) {
        const received = order.paymentReceivedMethod;
        const rKey = (received === 'card' || received === 'cash' || received === 'iban') ?
          received : 'unknown';
        paymentReceivedBreakdown[rKey].count++;
        paymentReceivedBreakdown[rKey].amount = round2(
          paymentReceivedBreakdown[rKey].amount + total,
        );
      }

      // Delivery type
      const dKey = delType === 'pickup' ? 'pickup' : 'delivery';
      deliveryTypeBreakdown[dKey].count++;
      deliveryTypeBreakdown[dKey].amount = round2(deliveryTypeBreakdown[dKey].amount + total);

      // Items
      totalItemsSold += (order.itemCount || 0);
      if (Array.isArray(order.items)) {
        for (const item of order.items) {
          if (!item?.name) continue;
          const prev = itemMap.get(item.name) || { quantity: 0, revenue: 0 };
          itemMap.set(item.name, {
            quantity: prev.quantity + (item.quantity || 1),
            revenue: round2(prev.revenue + (item.itemTotal || 0)),
          });
        }
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  // Top items
  const topItems = Array.from(itemMap.entries())
    .map(([name, v]) => ({ name, ...v }))
    .sort((a, b) => b.quantity - a.quantity)
    .slice(0, TOP_ITEMS);

  const revenueOrderCount = completedOrders + activeOrders;

  return {
    totalOrders,
    completedOrders,
    activeOrders,
    cancelledOrders,
    grossRevenue,
    deliveredRevenue,
    subtotalRevenue,
    deliveryFeeRevenue,
    averageOrderValue: revenueOrderCount > 0 ? round2(grossRevenue / revenueOrderCount) : 0,
    totalItemsSold,
    paymentBreakdown,
    paymentReceivedBreakdown,
    deliveryTypeBreakdown,
    statusBreakdown,
    topItems,
  };
}

// ═══════════════════════════════════════════════════════════════
// SHOP AGGREGATION
//
// Scans collectionGroup('items') filtered by shopId + timestamp.
// Composite index required: shopId ASC, timestamp ASC (collectionGroup)
//
// Aggregates per-seller within the shop, plus shop-wide totals.
// ═══════════════════════════════════════════════════════════════

async function aggregateShopSales(db, shopId, start, end) {
  const tsStart = admin.firestore.Timestamp.fromDate(start);
  const tsEnd   = admin.firestore.Timestamp.fromDate(end);

  const sellerMap    = new Map();
  const orderIdSet   = new Set();
  let totalItemCount = 0;

  let cursor = null;

  for (;;) {
    let q = db
      .collectionGroup('items')
      .where('shopId', '==', shopId)
      .where('timestamp', '>=', tsStart)
      .where('timestamp', '<',  tsEnd)
      .orderBy('timestamp')
      .limit(PAGE_SIZE);

    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const item = doc.data();
      if (!item.sellerId || !item.orderId) continue;

      const sid        = item.sellerId;
      const qty        = item.quantity || 1;
      const price      = item.price || 0;
      const revenue    = price * qty;
      const commission = item.ourComission || 0;

      if (!sellerMap.has(sid)) {
        sellerMap.set(sid, {
          sellerId: sid,
          sellerName: item.sellerName || 'Unknown',
          isShopProduct: !!item.isShopProduct,
          totalRevenue: 0,
          totalQuantity: 0,
          totalCommission: 0,
          totalItemCount: 0,
          orderIds: new Set(),
          categories: {},
        });
      }

      const seller = sellerMap.get(sid);
      seller.totalRevenue    += revenue;
      seller.totalQuantity   += qty;
      seller.totalCommission += commission;
      seller.totalItemCount  += 1;
      seller.orderIds.add(item.orderId);

      const cat = item.category || 'Diğer';
      if (!seller.categories[cat]) {
        seller.categories[cat] = { revenue: 0, quantity: 0, count: 0 };
      }
      seller.categories[cat].revenue  += revenue;
      seller.categories[cat].quantity  += qty;
      seller.categories[cat].count    += 1;

      orderIdSet.add(item.orderId);
      totalItemCount++;
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  // Build shop-wide totals + per-seller breakdown
  let totalRevenue = 0; let totalQuantity = 0; let totalCommission = 0;
  const categories = {};
  const sellers    = [];

  for (const [, d] of sellerMap) {
    totalRevenue    += d.totalRevenue;
    totalQuantity   += d.totalQuantity;
    totalCommission += d.totalCommission;

    // Merge categories
    for (const [cat, cd] of Object.entries(d.categories)) {
      if (!categories[cat]) categories[cat] = { revenue: 0, quantity: 0, count: 0 };
      categories[cat].revenue  += cd.revenue;
      categories[cat].quantity += cd.quantity;
      categories[cat].count   += cd.count;
    }

    const orderCount = d.orderIds.size;
    sellers.push({
      sellerId: d.sellerId,
      sellerName: d.sellerName,
      isShopProduct: d.isShopProduct,
      totalRevenue: round2(d.totalRevenue),
      totalQuantity: d.totalQuantity,
      totalCommission: round2(d.totalCommission),
      netRevenue: round2(d.totalRevenue - d.totalCommission),
      totalItemCount: d.totalItemCount,
      orderCount,
      averageOrderValue: orderCount > 0 ? round2(d.totalRevenue / orderCount) : 0,
    });
  }

  // Round category revenues
  for (const cat of Object.keys(categories)) {
    categories[cat].revenue = round2(categories[cat].revenue);
  }

  const orderCount = orderIdSet.size;

  return {
    totalRevenue: round2(totalRevenue),
    totalQuantity,
    totalCommission: round2(totalCommission),
    netRevenue: round2(totalRevenue - totalCommission),
    totalItemCount,
    orderCount,
    averageOrderValue: orderCount > 0 ? round2(totalRevenue / orderCount) : 0,
    sellerCount: sellerMap.size,
    categories,
    sellers: sellers.length > 1 ? sellers : (sellers[0] || null),
  };
}

// ═══════════════════════════════════════════════════════════════
// generateBusinessReport
//
// Scans orders/items for the requested period, aggregates,
// writes the report to Firestore, and returns the data.
//
// Request:
//   {
//     businessId:   string,
//     businessType: 'restaurant' | 'shop',
//     period:       'daily' | 'weekly' | 'monthly',
//     date?:   'YYYY-MM-DD',   // daily
//     year?:   number,          // weekly (+ week) or monthly (+ month)
//     week?:   number,          // weekly
//     month?:  number,          // monthly (1–12)
//   }
// ═══════════════════════════════════════════════════════════════

export const generateBusinessReport = onCall(
  {
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 300,
    concurrency: 80,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const uid = request.auth.uid;
    const { businessId, businessType, period, date, year, week, month } =
      request.data || {};

    // ── Validate ──────────────────────────────────────────────
    if (!businessId || typeof businessId !== 'string') {
      throw new HttpsError('invalid-argument', 'businessId is required.');
    }
    if (!businessType || !['restaurant', 'shop'].includes(businessType)) {
      throw new HttpsError('invalid-argument', 'businessType must be restaurant or shop.');
    }

    // ── Auth ──────────────────────────────────────────────────
    const claims = await getClaims(uid);
    assertAccess(claims, businessType, businessId);

    // ── Resolve period ────────────────────────────────────────
    const { periodKey, periodLabel, start, end } =
      resolvePeriod(period, { date, year, week, month });

    // ── Aggregate ─────────────────────────────────────────────
    const db = admin.firestore();

    let reportData;
    if (businessType === 'restaurant') {
      reportData = await aggregateRestaurantOrders(db, businessId, start, end);
    } else {
      reportData = await aggregateShopSales(db, businessId, start, end);
    }

    // ── Build document ────────────────────────────────────────
    const doc = {
      businessId,
      businessType,
      period,
      periodKey,
      periodLabel,
      periodStart: admin.firestore.Timestamp.fromDate(start),
      periodEnd: admin.firestore.Timestamp.fromDate(end),
      generatedBy: uid,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...reportData,
    };

    // ── Write (overwrite if exists) ───────────────────────────
    const reportRef = db
      .collection(REPORTS_ROOT)
      .doc(businessId)
      .collection(REPORTS_SUB)
      .doc(periodKey);

    await reportRef.set(doc);

    console.info(
      `[BusinessAccounting] ✓ ${businessType} ${businessId} | ${periodKey} | ` +
      `generated by ${uid}`,
    );

    // ── Return (convert Timestamps for client) ────────────────
    return {
      success: true,
      periodKey,
      periodLabel,
      periodStart: start.toISOString(),
      periodEnd: end.toISOString(),
      businessType,
      ...reportData,
    };
  },
);

// ═══════════════════════════════════════════════════════════════
// getBusinessReport
//
// Reads a single previously generated report.
//
// Request:
//   { businessId, businessType, periodKey }
//
// periodKey examples: daily_2025-04-05, weekly_2025-W14, monthly_2025-04
// ═══════════════════════════════════════════════════════════════

export const getBusinessReport = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 15,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { businessId, businessType, periodKey } = request.data || {};

    if (!businessId || !businessType || !periodKey) {
      throw new HttpsError('invalid-argument', 'businessId, businessType, and periodKey are required.');
    }

    const claims = await getClaims(request.auth.uid);
    assertAccess(claims, businessType, businessId);

    const snap = await admin.firestore()
      .collection(REPORTS_ROOT)
      .doc(businessId)
      .collection(REPORTS_SUB)
      .doc(periodKey)
      .get();

    if (!snap.exists) {
      return { exists: false, message: 'Report not found. Generate it first.' };
    }

    const data = snap.data();

    return {
      exists: true,
      periodKey: data.periodKey,
      periodLabel: data.periodLabel,
      periodStart: data.periodStart?.toDate?.()?.toISOString() || null,
      periodEnd: data.periodEnd?.toDate?.()?.toISOString()   || null,
      generatedAt: data.generatedAt?.toDate?.()?.toISOString() || null,
      businessType: data.businessType,
      period: data.period,
      // Spread all report metrics (varies by business type)
      ...(data.businessType === 'restaurant' ?
        pickRestaurantFields(data) :
        pickShopFields(data)),
    };
  },
);

// ── Field pickers (avoid sending internal fields to client) ───

function pickRestaurantFields(d) {
  return {
    totalOrders: d.totalOrders        || 0,
    completedOrders: d.completedOrders    || 0,
    activeOrders: d.activeOrders       || 0,
    cancelledOrders: d.cancelledOrders    || 0,
    grossRevenue: d.grossRevenue       || 0,
    deliveredRevenue: d.deliveredRevenue   || 0,
    subtotalRevenue: d.subtotalRevenue    || 0,
    deliveryFeeRevenue: d.deliveryFeeRevenue || 0,
    averageOrderValue: d.averageOrderValue  || 0,
    totalItemsSold: d.totalItemsSold     || 0,
    paymentBreakdown: d.paymentBreakdown         || {},
    paymentReceivedBreakdown: d.paymentReceivedBreakdown || {},
    deliveryTypeBreakdown: d.deliveryTypeBreakdown    || {},
    statusBreakdown: d.statusBreakdown          || {},
    topItems: d.topItems                 || [],
  };
}

function pickShopFields(d) {
  return {
    totalRevenue: d.totalRevenue      || 0,
    totalQuantity: d.totalQuantity     || 0,
    totalCommission: d.totalCommission   || 0,
    netRevenue: d.netRevenue        || 0,
    totalItemCount: d.totalItemCount    || 0,
    orderCount: d.orderCount        || 0,
    averageOrderValue: d.averageOrderValue || 0,
    sellerCount: d.sellerCount       || 0,
    categories: d.categories        || {},
    sellers: d.sellers           || null,
  };
}

// ═══════════════════════════════════════════════════════════════
// listBusinessReports
//
// Returns a paginated list of generated reports for a business,
// ordered newest-first.
//
// Request:
//   {
//     businessId,
//     businessType,
//     period?:  'daily' | 'weekly' | 'monthly',  // optional filter
//     limit?:   number,                            // default 30, max 100
//     startAfter?: string,                         // periodKey cursor
//   }
// ═══════════════════════════════════════════════════════════════

export const listBusinessReports = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 15,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const { businessId, businessType, period, limit: rawLimit, startAfter } =
      request.data || {};

    if (!businessId || !businessType) {
      throw new HttpsError('invalid-argument', 'businessId and businessType are required.');
    }

    const claims = await getClaims(request.auth.uid);
    assertAccess(claims, businessType, businessId);

    const maxResults = Math.min(Math.max(rawLimit || 30, 1), 100);
    const db = admin.firestore();

    let q = db
      .collection(REPORTS_ROOT)
      .doc(businessId)
      .collection(REPORTS_SUB)
      .orderBy('periodStart', 'desc')
      .limit(maxResults);

    // Filter by period type if specified
    if (period && ['daily', 'weekly', 'monthly'].includes(period)) {
      q = q.where('period', '==', period);
    }

    // Cursor-based pagination
    if (startAfter) {
      const cursorSnap = await db
        .collection(REPORTS_ROOT)
        .doc(businessId)
        .collection(REPORTS_SUB)
        .doc(startAfter)
        .get();

      if (cursorSnap.exists) {
        q = q.startAfter(cursorSnap);
      }
    }

    const snap = await q.get();

    const reports = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        periodKey: d.periodKey,
        periodLabel: d.periodLabel,
        period: d.period,
        periodStart: d.periodStart?.toDate?.()?.toISOString() || null,
        periodEnd: d.periodEnd?.toDate?.()?.toISOString()   || null,
        generatedAt: d.generatedAt?.toDate?.()?.toISOString() || null,
        // Summary metrics for the list view
        ...(d.businessType === 'restaurant' ?
          {
              totalOrders: d.totalOrders    || 0,
              grossRevenue: d.grossRevenue   || 0,
              completedOrders: d.completedOrders || 0,
            } :
          {
              totalRevenue: d.totalRevenue || 0,
              orderCount: d.orderCount   || 0,
              netRevenue: d.netRevenue   || 0,
            }),
      };
    });

    return {
      reports,
      hasMore: snap.size === maxResults,
      lastKey: reports.length > 0 ? reports[reports.length - 1].periodKey : null,
    };
  },
);

// ═══════════════════════════════════════════════════════════════
// getMyBusinesses
//
// Returns all businesses the caller has access to from custom
// claims, enriched with names and images via a single batch read.
//
// Response:
//   {
//     shops:       [{ id, role, name, profileImageUrl }],
//     restaurants: [{ id, role, name, profileImageUrl }],
//   }
// ═══════════════════════════════════════════════════════════════

export const getMyBusinesses = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const claims = await getClaims(request.auth.uid);
    const shopEntries      = Object.entries(claims.shops || {});
    const restaurantEntries = Object.entries(claims.restaurants || {});

    const db = admin.firestore();

    // Single batch read for all business docs
    const allRefs = [
      ...shopEntries.map(([id]) => db.collection('shops').doc(id)),
      ...restaurantEntries.map(([id]) => db.collection('restaurants').doc(id)),
    ];

    const allDocs = allRefs.length > 0 ? await db.getAll(...allRefs) : [];
    let idx = 0;

    const shops = shopEntries.map(([id, role]) => {
      const data = allDocs[idx++]?.data?.();
      return {
        id,
        role,
        name: data?.name || data?.shopName || null,
        profileImageUrl: data?.profileImageUrl || null,
      };
    });

    const restaurants = restaurantEntries.map(([id, role]) => {
      const data = allDocs[idx++]?.data?.();
      return {
        id,
        role,
        name: data?.name || null,
        profileImageUrl: data?.profileImageUrl || null,
      };
    });

    return { shops, restaurants };
  },
);
