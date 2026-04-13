/**
 * Sales Accounting Module (Daily / Weekly / Monthly)
 *
 * Processes order items via collectionGroup query, aggregates per-seller,
 * writes results to {period}_sales_accounting/{periodId}/shop_sales/{sellerId}.
 *
 * Idempotent: completed periods are never re-processed unless force=true.
 * Handles thousands of orders efficiently with cursor-based pagination.
 */
import admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

// ═══════════════════════════════════════════════════════════════
// DATE UTILITIES
// ═══════════════════════════════════════════════════════════════

// ── Daily ──────────────────────────────────────────────────────

export function getDayBounds(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const next = new Date(d);
  next.setDate(d.getDate() + 1);
  next.setHours(0, 0, 0, 0);
  return {periodStart: d, periodEnd: next};
}

export function getDayId(periodStart) {
  const y = periodStart.getFullYear();
  const m = String(periodStart.getMonth() + 1).padStart(2, '0');
  const d = String(periodStart.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// ── Weekly ─────────────────────────────────────────────────────

export function getWeekBounds(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const day = d.getDay(); // 0=Sun … 6=Sat
  const diffToMonday = day === 0 ? -6 : 1 - day;

  const monday = new Date(d);
  monday.setDate(d.getDate() + diffToMonday);
  monday.setHours(0, 0, 0, 0);

  const nextMonday = new Date(monday);
  nextMonday.setDate(monday.getDate() + 7);
  nextMonday.setHours(0, 0, 0, 0);

  return {periodStart: monday, periodEnd: nextMonday};
}

export function getWeekId(periodStart) {
  const y = periodStart.getFullYear();
  const m = String(periodStart.getMonth() + 1).padStart(2, '0');
  const d = String(periodStart.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// ── Monthly ───────────────────────────────────────────────────

export function getMonthBounds(date) {
  const d = new Date(date);
  const start = new Date(d.getFullYear(), d.getMonth(), 1);
  start.setHours(0, 0, 0, 0);
  const end = new Date(d.getFullYear(), d.getMonth() + 1, 1);
  end.setHours(0, 0, 0, 0);
  return {periodStart: start, periodEnd: end};
}

export function getMonthId(periodStart) {
  const y = periodStart.getFullYear();
  const m = String(periodStart.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

// ── Shared ─────────────────────────────────────────────────────

function formatRange(periodStart, periodEnd) {
  const lastDay = new Date(periodEnd);
  lastDay.setDate(lastDay.getDate() - 1);
  return {
    startStr: periodStart.toISOString().split('T')[0],
    endStr: lastDay.toISOString().split('T')[0],
  };
}

// ═══════════════════════════════════════════════════════════════
// AUTH HELPER
// ═══════════════════════════════════════════════════════════════

async function assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }
  const db = admin.firestore();
  const uid = request.auth.uid;
  const [adminDoc, userDoc] = await Promise.all([
    db.collection('admins').doc(uid).get(),
    db.collection('users').doc(uid).get(),
  ]);
  const isAdmin =
    adminDoc.exists ||
    userDoc.data()?.isAdmin === true ||
    request.auth.token?.admin === true;
  if (!isAdmin) {
    throw new HttpsError('permission-denied', 'Admin access required');
  }
}

// ═══════════════════════════════════════════════════════════════
// CORE PROCESSOR
// ═══════════════════════════════════════════════════════════════

const PAGE_SIZE = 500;
const BATCH_LIMIT = 500;
const STALE_THRESHOLD_MS = 30 * 60 * 1000; // 30 min

/**
 * @param {Date}   periodStart    – inclusive start
 * @param {Date}   periodEnd      – exclusive end
 * @param {string} periodId       – document ID (e.g. "2026-04-13", "2026-04-06", "2026-04")
 * @param {string} collectionName – top-level collection
 * @param {string} triggeredBy    – audit label
 * @param {boolean} force         – reprocess even if completed
 */
export async function processSalesAccounting(
  periodStart,
  periodEnd,
  periodId,
  collectionName,
  triggeredBy,
  force = false,
) {
  const db = admin.firestore();
  const reportRef = db.collection(collectionName).doc(periodId);

  // ── 1. Idempotency gate ──────────────────────────────────────
  const existingSnap = await reportRef.get();
  if (existingSnap.exists) {
    const existing = existingSnap.data();

    if (existing.status === 'completed' && !force) {
      console.log(`⏭️  ${collectionName}/${periodId} already completed — skipping`);
      return {periodId, status: 'skipped', reason: 'already_completed'};
    }

    if (existing.status === 'processing') {
      const startedAt = existing.processingStartedAt?.toDate?.();
      if (startedAt && Date.now() - startedAt.getTime() < STALE_THRESHOLD_MS) {
        console.log(`⏳ ${collectionName}/${periodId} is being processed by another invocation`);
        return {periodId, status: 'skipped', reason: 'currently_processing'};
      }
      console.log(`🔄 ${collectionName}/${periodId} has stale processing lock — retaking`);
    }
  }

  const {startStr, endStr} = formatRange(periodStart, periodEnd);

  // ── 2. Acquire processing lock ───────────────────────────────
  await reportRef.set(
    {
      periodId,
      periodStart: admin.firestore.Timestamp.fromDate(periodStart),
      periodEnd: admin.firestore.Timestamp.fromDate(periodEnd),
      periodStartStr: startStr,
      periodEndStr: endStr,
      status: 'processing',
      triggeredBy,
      processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: existingSnap.exists ? existingSnap.data().createdAt : admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      error: null,
    },
    {merge: true},
  );

  try {
    // ── 3. Aggregate via collectionGroup paginated scan ────────
    const sellerMap = new Map();
    const uniqueOrderIds = new Set();
    let totalItemsProcessed = 0;

    const tsStart = admin.firestore.Timestamp.fromDate(periodStart);
    const tsEnd = admin.firestore.Timestamp.fromDate(periodEnd);

    let cursor = null;
    let hasMore = true;

    while (hasMore) {
      let q = db
        .collectionGroup('items')
        .where('timestamp', '>=', tsStart)
        .where('timestamp', '<', tsEnd)
        .orderBy('timestamp')
        .limit(PAGE_SIZE);

      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();

      if (snap.empty || snap.docs.length === 0) {
        hasMore = false;
        break;
      }

      for (const doc of snap.docs) {
        const item = doc.data();

        if (!item.sellerId || !item.orderId) continue;

        const sid = item.sellerId;
        const qty = item.quantity || 1;
        const unitPrice = item.price || 0;
        const revenue = unitPrice * qty;
        const commission = item.ourComission || 0;

        if (!sellerMap.has(sid)) {
          sellerMap.set(sid, {
            sellerId: sid,
            shopId: item.shopId || null,
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
        seller.totalRevenue += revenue;
        seller.totalQuantity += qty;
        seller.totalCommission += commission;
        seller.totalItemCount += 1;
        seller.orderIds.add(item.orderId);

        const cat = item.category || 'Diger';
        if (!seller.categories[cat]) {
          seller.categories[cat] = {revenue: 0, quantity: 0, count: 0};
        }
        seller.categories[cat].revenue += revenue;
        seller.categories[cat].quantity += qty;
        seller.categories[cat].count += 1;

        uniqueOrderIds.add(item.orderId);
        totalItemsProcessed++;
      }

      cursor = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < PAGE_SIZE) hasMore = false;

      if (totalItemsProcessed % 2000 === 0) {
        console.log(
          `📦 ${collectionName}/${periodId}: ${totalItemsProcessed} items scanned, ${sellerMap.size} sellers found`,
        );
      }
    }

    console.log(
      `📊 ${collectionName}/${periodId}: scan complete — ${totalItemsProcessed} items, ${sellerMap.size} sellers, ${uniqueOrderIds.size} orders`,
    );

    // ── 4. Wipe old shop_sales if force-recalculating ─────────
    if (force && existingSnap.exists) {
      const oldDocs = await reportRef.collection('shop_sales').listDocuments();
      for (let i = 0; i < oldDocs.length; i += BATCH_LIMIT) {
        const batch = db.batch();
        oldDocs.slice(i, i + BATCH_LIMIT).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }
      console.log(`🗑️  Deleted ${oldDocs.length} old shop_sales docs for ${periodId}`);
    }

    // ── 5. Batch-write shop_sales subcollection ───────────────
    let totalRevenue = 0;
    let totalCommission = 0;
    let totalQuantity = 0;
    const entries = Array.from(sellerMap.entries());

    for (let i = 0; i < entries.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      const chunk = entries.slice(i, i + BATCH_LIMIT);

      for (const [sellerId, data] of chunk) {
        const ref = reportRef.collection('shop_sales').doc(sellerId);
        const orderCount = data.orderIds.size;
        const avgOrderValue = orderCount > 0 ? data.totalRevenue / orderCount : 0;

        batch.set(ref, {
          sellerId: data.sellerId,
          shopId: data.shopId,
          sellerName: data.sellerName,
          isShopProduct: data.isShopProduct,
          totalRevenue: round2(data.totalRevenue),
          totalQuantity: data.totalQuantity,
          totalCommission: round2(data.totalCommission),
          netRevenue: round2(data.totalRevenue - data.totalCommission),
          totalItemCount: data.totalItemCount,
          orderCount,
          averageOrderValue: round2(avgOrderValue),
          orderIds: Array.from(data.orderIds).slice(0, 200),
          totalOrderIds: orderCount,
          categories: data.categories,
          periodId,
        });

        totalRevenue += data.totalRevenue;
        totalCommission += data.totalCommission;
        totalQuantity += data.totalQuantity;
      }

      await batch.commit();
    }

    // ── 6. Finalize summary document ──────────────────────────
    const shopSellers = entries.filter(([, d]) => d.isShopProduct);
    const individualSellers = entries.filter(([, d]) => !d.isShopProduct);

    await reportRef.update({
      status: 'completed',
      totalRevenue: round2(totalRevenue),
      totalCommission: round2(totalCommission),
      netRevenue: round2(totalRevenue - totalCommission),
      totalQuantity,
      totalOrderCount: uniqueOrderIds.size,
      totalItemCount: totalItemsProcessed,
      sellerCount: sellerMap.size,
      shopCount: shopSellers.length,
      individualSellerCount: individualSellers.length,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      processingDurationMs: null,
      error: null,
    });

    console.log(
      `✅ ${collectionName}/${periodId} completed: ${sellerMap.size} sellers | ${uniqueOrderIds.size} orders | ₺${round2(totalRevenue)} revenue`,
    );

    return {
      periodId,
      status: 'completed',
      sellerCount: sellerMap.size,
      orderCount: uniqueOrderIds.size,
      totalRevenue: round2(totalRevenue),
      totalItemCount: totalItemsProcessed,
    };
  } catch (error) {
    console.error(`❌ ${collectionName}/${periodId} FAILED:`, error);

    await reportRef
      .update({
        status: 'failed',
        error: error.message || String(error),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      })
      .catch(() => {});

    return {periodId, status: 'failed', error: error.message};
  }
}

// ── Helpers ────────────────────────────────────────────────────
function round2(n) {
  return Math.round(n * 100) / 100;
}

// ═══════════════════════════════════════════════════════════════
// DAILY ACCOUNTING — onCall
// ═══════════════════════════════════════════════════════════════

export const triggerDailyAccounting = onCall(
  {
    region: 'europe-west3',
    memory: '1GiB',
    timeoutSeconds: 540,
  },
  async (request) => {
    await assertAdmin(request);

    const {
      mode = 'single',
      date: reqDate,
      startDate,
      endDate,
      force = false,
    } = request.data || {};

    if (mode === 'current') {
      const {periodStart, periodEnd} = getDayBounds(new Date());
      const pid = getDayId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'daily_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'yesterday') {
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const {periodStart, periodEnd} = getDayBounds(yesterday);
      const pid = getDayId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'daily_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'single') {
      if (!reqDate || !/^\d{4}-\d{2}-\d{2}$/.test(reqDate)) {
        throw new HttpsError('invalid-argument', 'date must be YYYY-MM-DD');
      }
      const [y, m, d] = reqDate.split('-').map(Number);
      const {periodStart, periodEnd} = getDayBounds(new Date(y, m - 1, d));
      const pid = getDayId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'daily_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'backfill') {
      if (!startDate || !endDate) {
        throw new HttpsError('invalid-argument', 'startDate and endDate required');
      }
      const rangeStart = new Date(startDate);
      const rangeEnd = new Date(endDate);
      if (isNaN(rangeStart.getTime()) || isNaN(rangeEnd.getTime())) {
        throw new HttpsError('invalid-argument', 'Invalid date format');
      }

      const results = [];
      let current = new Date(rangeStart);
      let dayCount = 0;
      const MAX_DAYS = 366;

      while (current < rangeEnd && dayCount < MAX_DAYS) {
        const {periodStart, periodEnd} = getDayBounds(current);
        const pid = getDayId(periodStart);
        if (periodEnd > rangeStart && periodStart < rangeEnd) {
          const result = await processSalesAccounting(
            periodStart, periodEnd, pid, 'daily_sales_accounting', 'manual_backfill', force,
          );
          results.push(result);
          dayCount++;
        }
        current = new Date(periodStart);
        current.setDate(current.getDate() + 1);
      }

      const completed = results.filter((r) => r.status === 'completed').length;
      const skipped = results.filter((r) => r.status === 'skipped').length;
      const failed = results.filter((r) => r.status === 'failed').length;

      return {
        success: true,
        results,
        summary: {completed, skipped, failed, totalProcessed: dayCount},
        hasMore: dayCount >= MAX_DAYS && current < rangeEnd,
      };
    }

    throw new HttpsError('invalid-argument', `Unknown mode: ${mode}`);
  },
);

// ═══════════════════════════════════════════════════════════════
// WEEKLY ACCOUNTING — onCall
// ═══════════════════════════════════════════════════════════════

export const triggerWeeklyAccounting = onCall(
  {
    region: 'europe-west3',
    memory: '2GiB',
    timeoutSeconds: 540,
  },
  async (request) => {
    await assertAdmin(request);

    const {
      mode = 'single',
      weekId: reqWeekId,
      startDate,
      endDate,
      force = false,
    } = request.data || {};

    if (mode === 'current') {
      const {periodStart, periodEnd} = getWeekBounds(new Date());
      const pid = getWeekId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'weekly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'lastWeek') {
      const lastWeek = new Date();
      lastWeek.setDate(lastWeek.getDate() - 7);
      const {periodStart, periodEnd} = getWeekBounds(lastWeek);
      const pid = getWeekId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'weekly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'single') {
      if (!reqWeekId || !/^\d{4}-\d{2}-\d{2}$/.test(reqWeekId)) {
        throw new HttpsError('invalid-argument', 'weekId must be YYYY-MM-DD');
      }
      const [y, m, d] = reqWeekId.split('-').map(Number);
      const {periodStart, periodEnd} = getWeekBounds(new Date(y, m - 1, d));
      const pid = getWeekId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'weekly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'backfill') {
      if (!startDate || !endDate) {
        throw new HttpsError('invalid-argument', 'startDate and endDate required');
      }
      const rangeStart = new Date(startDate);
      const rangeEnd = new Date(endDate);
      if (isNaN(rangeStart.getTime()) || isNaN(rangeEnd.getTime())) {
        throw new HttpsError('invalid-argument', 'Invalid date format');
      }

      const results = [];
      let current = new Date(rangeStart);
      let weekCount = 0;
      const MAX_WEEKS = 52;

      while (current < rangeEnd && weekCount < MAX_WEEKS) {
        const {periodStart, periodEnd} = getWeekBounds(current);
        const pid = getWeekId(periodStart);
        if (periodEnd > rangeStart && periodStart < rangeEnd) {
          const result = await processSalesAccounting(
            periodStart, periodEnd, pid, 'weekly_sales_accounting', 'manual_backfill', force,
          );
          results.push(result);
          weekCount++;
        }
        current = new Date(periodStart);
        current.setDate(current.getDate() + 7);
      }

      const completed = results.filter((r) => r.status === 'completed').length;
      const skipped = results.filter((r) => r.status === 'skipped').length;
      const failed = results.filter((r) => r.status === 'failed').length;

      return {
        success: true,
        results,
        summary: {completed, skipped, failed, totalProcessed: weekCount},
        hasMore: weekCount >= MAX_WEEKS && current < rangeEnd,
      };
    }

    throw new HttpsError('invalid-argument', `Unknown mode: ${mode}`);
  },
);

// ═══════════════════════════════════════════════════════════════
// MONTHLY ACCOUNTING — onCall
// ═══════════════════════════════════════════════════════════════

export const triggerMonthlyAccounting = onCall(
  {
    region: 'europe-west3',
    memory: '2GiB',
    timeoutSeconds: 540,
  },
  async (request) => {
    await assertAdmin(request);

    const {
      mode = 'single',
      month: reqMonth,
      startDate,
      endDate,
      force = false,
    } = request.data || {};

    if (mode === 'current') {
      const {periodStart, periodEnd} = getMonthBounds(new Date());
      const pid = getMonthId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'monthly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'lastMonth') {
      const now = new Date();
      const lastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const {periodStart, periodEnd} = getMonthBounds(lastMonth);
      const pid = getMonthId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'monthly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'single') {
      if (!reqMonth || !/^\d{4}-\d{2}$/.test(reqMonth)) {
        throw new HttpsError('invalid-argument', 'month must be YYYY-MM');
      }
      const [y, m] = reqMonth.split('-').map(Number);
      const {periodStart, periodEnd} = getMonthBounds(new Date(y, m - 1, 1));
      const pid = getMonthId(periodStart);
      const result = await processSalesAccounting(
        periodStart, periodEnd, pid, 'monthly_sales_accounting', 'manual', force,
      );
      return {success: true, results: [result]};
    }

    if (mode === 'backfill') {
      if (!startDate || !endDate) {
        throw new HttpsError('invalid-argument', 'startDate and endDate required');
      }
      const rangeStart = new Date(startDate);
      const rangeEnd = new Date(endDate);
      if (isNaN(rangeStart.getTime()) || isNaN(rangeEnd.getTime())) {
        throw new HttpsError('invalid-argument', 'Invalid date format');
      }

      const results = [];
      let current = new Date(rangeStart.getFullYear(), rangeStart.getMonth(), 1);
      let monthCount = 0;
      const MAX_MONTHS = 24;

      while (current < rangeEnd && monthCount < MAX_MONTHS) {
        const {periodStart, periodEnd} = getMonthBounds(current);
        const pid = getMonthId(periodStart);
        if (periodEnd > rangeStart && periodStart < rangeEnd) {
          const result = await processSalesAccounting(
            periodStart, periodEnd, pid, 'monthly_sales_accounting', 'manual_backfill', force,
          );
          results.push(result);
          monthCount++;
        }
        current = new Date(periodStart.getFullYear(), periodStart.getMonth() + 1, 1);
      }

      const completed = results.filter((r) => r.status === 'completed').length;
      const skipped = results.filter((r) => r.status === 'skipped').length;
      const failed = results.filter((r) => r.status === 'failed').length;

      return {
        success: true,
        results,
        summary: {completed, skipped, failed, totalProcessed: monthCount},
        hasMore: monthCount >= MAX_MONTHS && current < rangeEnd,
      };
    }

    throw new HttpsError('invalid-argument', `Unknown mode: ${mode}`);
  },
);
