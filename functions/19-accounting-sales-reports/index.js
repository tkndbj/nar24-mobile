/**
 * Weekly Sales Accounting Module
 * 
 * Processes order items via collectionGroup query, aggregates per-seller,
 * writes results to weekly_sales_accounting/{weekId}/shop_sales/{sellerId}.
 * 
 * Idempotent: completed weeks are never re-processed unless force=true.
 * Handles thousands of orders efficiently with cursor-based pagination.
 */
import admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

// ═══════════════════════════════════════════════════════════════
// DATE UTILITIES
// ═══════════════════════════════════════════════════════════════

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

  return {weekStart: monday, weekEnd: nextMonday};
}


export function getWeekId(weekStart) {
  const y = weekStart.getFullYear();
  const m = String(weekStart.getMonth() + 1).padStart(2, '0');
  const d = String(weekStart.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}


function formatRange(weekStart, weekEnd) {
  const sunday = new Date(weekEnd);
  sunday.setDate(sunday.getDate() - 1);
  return {
    startStr: weekStart.toISOString().split('T')[0],
    endStr: sunday.toISOString().split('T')[0],
  };
}

// ═══════════════════════════════════════════════════════════════
// CORE PROCESSOR
// ═══════════════════════════════════════════════════════════════

const PAGE_SIZE = 500; // Firestore page size for reads
const BATCH_LIMIT = 500; // Firestore batch write limit
const STALE_THRESHOLD_MS = 30 * 60 * 1000; // 30 min

export async function processWeekSales(
  weekStartDate,
  weekEndDate,
  weekId,
  triggeredBy,
  force = false,
) {
  const db = admin.firestore();
  const reportRef = db.collection('weekly_sales_accounting').doc(weekId);

  // ── 1. Idempotency gate ──────────────────────────────────────
  const existingSnap = await reportRef.get();
  if (existingSnap.exists) {
    const existing = existingSnap.data();

    if (existing.status === 'completed' && !force) {
      console.log(`⏭️  Week ${weekId} already completed — skipping`);
      return {weekId, status: 'skipped', reason: 'already_completed'};
    }

    if (existing.status === 'processing') {
      const startedAt = existing.processingStartedAt?.toDate?.();
      if (startedAt && Date.now() - startedAt.getTime() < STALE_THRESHOLD_MS) {
        console.log(`⏳ Week ${weekId} is being processed by another invocation`);
        return {weekId, status: 'skipped', reason: 'currently_processing'};
      }
      console.log(`🔄 Week ${weekId} has stale processing lock — retaking`);
    }
  }

  const {startStr, endStr} = formatRange(weekStartDate, weekEndDate);

  // ── 2. Acquire processing lock ───────────────────────────────
  await reportRef.set(
    {
      weekId,
      weekStart: admin.firestore.Timestamp.fromDate(weekStartDate),
      weekEnd: admin.firestore.Timestamp.fromDate(weekEndDate),
      weekStartStr: startStr,
      weekEndStr: endStr,
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

    const tsStart = admin.firestore.Timestamp.fromDate(weekStartDate);
    const tsEnd = admin.firestore.Timestamp.fromDate(weekEndDate);

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

        // Safety: skip docs that aren't real order items
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

        // Category breakdown
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
        console.log(`📦 Week ${weekId}: ${totalItemsProcessed} items scanned, ${sellerMap.size} sellers found`);
      }
    }

    console.log(`📊 Week ${weekId}: scan complete — ${totalItemsProcessed} items, ${sellerMap.size} sellers, ${uniqueOrderIds.size} orders`);

    // ── 4. Wipe old shop_sales if force-recalculating ─────────
    if (force && existingSnap.exists) {
      const oldDocs = await reportRef.collection('shop_sales').listDocuments();
      for (let i = 0; i < oldDocs.length; i += BATCH_LIMIT) {
        const batch = db.batch();
        oldDocs.slice(i, i + BATCH_LIMIT).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }
      console.log(`🗑️  Deleted ${oldDocs.length} old shop_sales docs for ${weekId}`);
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
          // Store first 200 order IDs for audit; full count in totalOrderIds
          orderIds: Array.from(data.orderIds).slice(0, 200),
          totalOrderIds: orderCount,
          categories: data.categories,
          weekId,
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
      processingDurationMs: null, // will be overwritten below
      error: null,
    });

    console.log(
      `✅ Week ${weekId} completed: ${sellerMap.size} sellers | ${uniqueOrderIds.size} orders | ₺${round2(totalRevenue)} revenue`,
    );

    return {
      weekId,
      status: 'completed',
      sellerCount: sellerMap.size,
      orderCount: uniqueOrderIds.size,
      totalRevenue: round2(totalRevenue),
      totalItemCount: totalItemsProcessed,
    };
  } catch (error) {
    console.error(`❌ Week ${weekId} FAILED:`, error);

    await reportRef.update({
      status: 'failed',
      error: error.message || String(error),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {}); // never let logging crash the handler

    return {weekId, status: 'failed', error: error.message};
  }
}

// ── Helpers ────────────────────────────────────────────────────
function round2(n) {
  return Math.round(n * 100) / 100;
}

// ═══════════════════════════════════════════════════════════════
// SCHEDULED — Every Monday 04:00 Istanbul
// ═══════════════════════════════════════════════════════════════
export const weeklyAccountingScheduled = onSchedule(
    {
      schedule: 'every monday 04:00',
      timeZone: 'Europe/Istanbul',
      region: 'europe-west3',
      memory: '1GiB',
      timeoutSeconds: 540,
      retryCount: 2,
    },
    async () => {
      const now = new Date();
      const lastWeekDate = new Date(now);
      lastWeekDate.setDate(now.getDate() - 7);
      const {weekStart, weekEnd} = getWeekBounds(lastWeekDate);
      const weekId = getWeekId(weekStart);
      console.log(`📅 Scheduled weekly accounting: ${weekId}`);
      await processWeekSales(weekStart, weekEnd, weekId, 'scheduled', false);
    },
  );
  
  // ═══════════════════════════════════════════════════════════════
  // MANUAL TRIGGER — Admin panel
  // ═══════════════════════════════════════════════════════════════
  export const triggerWeeklyAccounting = onCall(
    {
      region: 'europe-west3',
      memory: '2GiB',
      timeoutSeconds: 540,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Authentication required');
      }
  
      const db = admin.firestore();
      const uid = request.auth.uid;
  
      const [adminDoc, userDoc] = await Promise.all([
        db.collection('admins').doc(uid).get(),
        db.collection('users').doc(uid).get(),
      ]);
      const isAdmin = adminDoc.exists || userDoc.data()?.isAdmin === true || request.auth.token?.admin === true;
      if (!isAdmin) {
        throw new HttpsError('permission-denied', 'Admin access required');
      }
  
      const {
        mode = 'single',
        weekId: reqWeekId,
        startDate,
        endDate,
        force = false,
      } = request.data || {};
  
      if (mode === 'current') {
        const {weekStart, weekEnd} = getWeekBounds(new Date());
        const wid = getWeekId(weekStart);
        const result = await processWeekSales(weekStart, weekEnd, wid, 'manual', force);
        return {success: true, results: [result]};
      }
  
      if (mode === 'single') {
        if (!reqWeekId || !/^\d{4}-\d{2}-\d{2}$/.test(reqWeekId)) {
          throw new HttpsError('invalid-argument', 'weekId must be YYYY-MM-DD');
        }
        const [y, m, d] = reqWeekId.split('-').map(Number);
        const targetDate = new Date(y, m - 1, d);
        const {weekStart, weekEnd} = getWeekBounds(targetDate);
        const wid = getWeekId(weekStart);
        const result = await processWeekSales(weekStart, weekEnd, wid, 'manual', force);
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
          const {weekStart, weekEnd} = getWeekBounds(current);
          const wid = getWeekId(weekStart);
          if (weekEnd > rangeStart && weekStart < rangeEnd) {
            const result = await processWeekSales(weekStart, weekEnd, wid, 'manual_backfill', force);
            results.push(result);
            weekCount++;
          }
          current = new Date(weekStart);
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
