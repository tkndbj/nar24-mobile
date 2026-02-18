/**
 * Monthly Analytics Summary
 *
 * Reads pre-computed admin_analytics/{weekId} docs for a given month,
 * aggregates totals, computes week-over-week trends, and writes a
 * single summary doc to admin_analytics_summary/{monthId}.
 *
 * Max reads per run: ~5 weekly docs + 1 previous month check = ~6 reads.
 */
import admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import { getWeekId} from '../20-admin-analytics/index.js';

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

function getMonthId(year, month) {
  return `${year}-${String(month + 1).padStart(2, '0')}`;
}

function getWeeksOfMonth(year, month) {
  const weeks = [];
  const firstOfMonth = new Date(year, month, 1);
  const lastOfMonth = new Date(year, month + 1, 0);

  // Find first Monday that overlaps this month
  const d = new Date(firstOfMonth);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const firstMonday = new Date(d);
  firstMonday.setDate(d.getDate() + diff);
  firstMonday.setHours(0, 0, 0, 0);

  const current = new Date(firstMonday);
  while (current <= lastOfMonth) {
    const monday = new Date(current);
    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    weeks.push({
      weekId: getWeekId(monday),
      monday: new Date(monday),
      sunday: new Date(sunday),
    });
    current.setDate(current.getDate() + 7);
  }
  return weeks;
}

function pctChange(current, previous) {
  if (previous === 0) return current > 0 ? 100 : 0;
  return Math.round(((current - previous) / previous) * 1000) / 10;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

// ═══════════════════════════════════════════════════════════════
// CORE PROCESSOR
// ═══════════════════════════════════════════════════════════════

async function computeMonthlySummary(year, month, triggeredBy, force = false) {
  const db = admin.firestore();
  const monthId = getMonthId(year, month);
  const summaryRef = db.collection('admin_analytics_summary').doc(monthId);

  // ── 1. Idempotency ────────────────────────────────────────
  const existing = await summaryRef.get();
  if (existing.exists && existing.data().status === 'completed' && !force) {
    console.log(`⏭️ Summary ${monthId} already completed — skipping`);
    return {monthId, status: 'skipped', reason: 'already_completed'};
  }

  // ── 2. Lock ───────────────────────────────────────────────
  await summaryRef.set({
    monthId,
    year,
    month: month + 1,
    status: 'processing',
    triggeredBy,
    processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  try {
    // ── 3. Read weekly analytics for this month ────────────
    const weeks = getWeeksOfMonth(year, month);
    const weekIds = weeks.map((w) => w.weekId);

    const weekDocs = await Promise.all(
      weekIds.map((wid) => db.collection('admin_analytics').doc(wid).get()),
    );

    const completedWeeks = [];
    for (let i = 0; i < weekDocs.length; i++) {
      const doc = weekDocs[i];
      if (doc.exists && doc.data().status === 'completed') {
        completedWeeks.push({
          weekId: weekIds[i],
          monday: weeks[i].monday,
          sunday: weeks[i].sunday,
          ...doc.data(),
        });
      }
    }

    if (completedWeeks.length === 0) {
      await summaryRef.update({
        status: 'completed',
        weekCount: 0,
        message: 'No completed weekly reports found',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {monthId, status: 'completed', weekCount: 0};
    }

    // Sort chronologically
    completedWeeks.sort((a, b) => a.monday - b.monday);

    // ── 4. Aggregate ────────────────────────────────────────
    const summary = buildMonthlySummary(completedWeeks);

    // ── 5. Write ────────────────────────────────────────────
    await summaryRef.update({
      status: 'completed',
      weekCount: completedWeeks.length,
      ...summary,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      error: null,
    });

    console.log(`✅ Summary ${monthId} completed: ${completedWeeks.length} weeks`);
    return {monthId, status: 'completed', weekCount: completedWeeks.length};
  } catch (error) {
    console.error(`❌ Summary ${monthId} FAILED:`, error);
    await summaryRef.update({
      status: 'failed',
      error: error.message || String(error),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});
    return {monthId, status: 'failed', error: error.message};
  }
}

// ═══════════════════════════════════════════════════════════════
// BUILD MONTHLY SUMMARY
// ═══════════════════════════════════════════════════════════════

function buildMonthlySummary(weeks) {
  // ── Monthly totals ────────────────────────────────────────
  const monthlyTotals = {
    totalClicks: 0,
    totalViews: 0,
    totalCartAdds: 0,
    totalFavorites: 0,
    totalSearches: 0,
    totalPurchaseEvents: 0,
    totalEvents: 0,
    uniqueProducts: 0,
    uniqueUsers: 0,
  };

  for (const w of weeks) {
    monthlyTotals.totalClicks += w.totalClicks || 0;
    monthlyTotals.totalViews += w.totalViews || 0;
    monthlyTotals.totalCartAdds += w.totalCartAdds || 0;
    monthlyTotals.totalFavorites += w.totalFavorites || 0;
    monthlyTotals.totalSearches += w.totalSearches || 0;
    monthlyTotals.totalPurchaseEvents += w.totalPurchaseEvents || 0;
    monthlyTotals.totalEvents += w.totalEvents || 0;
    monthlyTotals.uniqueProducts += w.uniqueProducts || 0;
    monthlyTotals.uniqueUsers += w.uniqueUsers || 0;
  }

  // ── Weekly trend data (for charts) ────────────────────────
  const weeklyTrend = weeks.map((w) => ({
    weekId: w.weekId,
    weekStartStr: w.weekStartStr || w.weekId,
    weekEndStr: w.weekEndStr || '',
    totalClicks: w.totalClicks || 0,
    totalCartAdds: w.totalCartAdds || 0,
    totalFavorites: w.totalFavorites || 0,
    totalSearches: w.totalSearches || 0,
    totalPurchaseEvents: w.totalPurchaseEvents || 0,
    totalEvents: w.totalEvents || 0,
    uniqueProducts: w.uniqueProducts || 0,
    uniqueUsers: w.uniqueUsers || 0,
  }));

  // ── Week-over-week changes ────────────────────────────────
  const weekOverWeek = [];
  for (let i = 1; i < weeks.length; i++) {
    const curr = weeks[i];
    const prev = weeks[i - 1];
    weekOverWeek.push({
      weekId: curr.weekId,
      prevWeekId: prev.weekId,
      changes: {
        totalClicks: pctChange(curr.totalClicks || 0, prev.totalClicks || 0),
        totalCartAdds: pctChange(curr.totalCartAdds || 0, prev.totalCartAdds || 0),
        totalPurchaseEvents: pctChange(curr.totalPurchaseEvents || 0, prev.totalPurchaseEvents || 0),
        totalEvents: pctChange(curr.totalEvents || 0, prev.totalEvents || 0),
        uniqueUsers: pctChange(curr.uniqueUsers || 0, prev.uniqueUsers || 0),
      },
    });
  }

  // ── Aggregate categories across all weeks ─────────────────
  const catMap = new Map();
  for (const w of weeks) {
    for (const c of (w.topClickedCategories || [])) {
      const key = c.category;
      if (!catMap.has(key)) {
        catMap.set(key, {category: key, clicks: 0, cartAdds: 0, purchases: 0, favorites: 0});
      }
      const agg = catMap.get(key);
      agg.clicks += c.clicks || 0;
      agg.cartAdds += c.cartAdds || 0;
      agg.purchases += c.purchases || 0;
      agg.favorites += c.favorites || 0;
    }
  }
  const topCategoriesMonthly = Array.from(catMap.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, 20);

  // ── Aggregate brands across all weeks ─────────────────────
  const brandMap = new Map();
  for (const w of weeks) {
    for (const b of (w.topClickedBrands || [])) {
      const key = b.brand;
      if (!brandMap.has(key)) {
        brandMap.set(key, {brand: key, clicks: 0, cartAdds: 0, purchases: 0, favorites: 0});
      }
      const agg = brandMap.get(key);
      agg.clicks += b.clicks || 0;
      agg.cartAdds += b.cartAdds || 0;
      agg.purchases += b.purchases || 0;
      agg.favorites += b.favorites || 0;
    }
  }
  const topBrandsMonthly = Array.from(brandMap.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, 20);

  // ── Aggregate gender across all weeks ─────────────────────
  const genderMap = new Map();
  for (const w of weeks) {
    for (const g of (w.genderBreakdown || [])) {
      const key = g.gender;
      if (!genderMap.has(key)) {
        genderMap.set(key, {
          gender: key,
          clicks: 0, views: 0, cartAdds: 0, favorites: 0,
          purchases: 0, uniqueUsers: 0, totalEngagement: 0,
        });
      }
      const agg = genderMap.get(key);
      agg.clicks += g.clicks || 0;
      agg.views += g.views || 0;
      agg.cartAdds += g.cartAdds || 0;
      agg.favorites += g.favorites || 0;
      agg.purchases += g.purchases || 0;
      agg.uniqueUsers += g.uniqueUsers || 0;
      agg.totalEngagement += g.totalEngagement || 0;
    }
  }
  const genderMonthly = Array.from(genderMap.values())
    .sort((a, b) => b.totalEngagement - a.totalEngagement);

  // ── Aggregate search terms across all weeks ───────────────
  const searchMap = new Map();
  for (const w of weeks) {
    for (const s of (w.topSearchTerms || [])) {
      searchMap.set(s.term, (searchMap.get(s.term) || 0) + s.count);
    }
  }
  const topSearchMonthly = Array.from(searchMap.entries())
    .map(([term, count]) => ({term, count}))
    .sort((a, b) => b.count - a.count)
    .slice(0, 30);

  // ── Aggregate conversion funnels across all weeks ─────────
  const funnelMap = new Map();
  for (const w of weeks) {
    for (const f of (w.conversionFunnels || [])) {
      const key = f.category;
      if (!funnelMap.has(key)) {
        funnelMap.set(key, {category: key, clicks: 0, cartAdds: 0, purchases: 0});
      }
      const agg = funnelMap.get(key);
      agg.clicks += f.clicks || 0;
      agg.cartAdds += f.cartAdds || 0;
      agg.purchases += f.purchases || 0;
    }
  }
  const conversionMonthly = Array.from(funnelMap.values())
    .map((f) => ({
      ...f,
      clickToCartRate: f.clicks > 0 ? round2((f.cartAdds / f.clicks) * 100) : 0,
      cartToPurchaseRate: f.cartAdds > 0 ? round2((f.purchases / f.cartAdds) * 100) : 0,
      overallConversion: f.clicks > 0 ? round2((f.purchases / f.clicks) * 100) : 0,
    }))
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, 20);

  // ── Aggregate sellers (from topSellersByRevenue) ──────────
  const sellerRevenueMap = new Map();
  for (const w of weeks) {
    for (const s of (w.topSellersByRevenue || [])) {
      const key = s.sellerId;
      if (!sellerRevenueMap.has(key)) {
        sellerRevenueMap.set(key, {
          sellerId: s.sellerId,
          sellerName: s.sellerName,
          shopId: s.shopId,
          totalRevenue: 0,
          orderCount: 0,
          totalQuantity: 0,
        });
      }
      const agg = sellerRevenueMap.get(key);
      agg.totalRevenue += s.totalRevenue || 0;
      agg.orderCount += s.orderCount || 0;
      agg.totalQuantity += s.totalQuantity || 0;
      // Keep latest name
      if (s.sellerName) agg.sellerName = s.sellerName;
    }
  }
  const topSellersMonthly = Array.from(sellerRevenueMap.values())
    .map((s) => ({...s, totalRevenue: round2(s.totalRevenue)}))
    .sort((a, b) => b.totalRevenue - a.totalRevenue)
    .slice(0, 20);

  return {
    monthlyTotals,
    weeklyTrend,
    weekOverWeek,
    topCategoriesMonthly,
    topBrandsMonthly,
    genderMonthly,
    topSearchMonthly,
    conversionMonthly,
    topSellersMonthly,
  };
}

// ═══════════════════════════════════════════════════════════════
// SCHEDULED — 1st of each month at 06:00 Istanbul
// ═══════════════════════════════════════════════════════════════

export const monthlyAnalyticsSummaryScheduled = onSchedule(
  {
    schedule: '0 6 1 * *',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 120,
    retryCount: 2,
  },
  async () => {
    // Summarize previous month
    const now = new Date();
    let year = now.getFullYear();
    let month = now.getMonth() - 1;
    if (month < 0) {
      month = 11;
      year--;
    }
    console.log(`📅 Scheduled monthly summary: ${getMonthId(year, month)}`);
    await computeMonthlySummary(year, month, 'scheduled', false);
  },
);

// ═══════════════════════════════════════════════════════════════
// MANUAL TRIGGER
// ═══════════════════════════════════════════════════════════════

export const triggerMonthlySummary = onCall(
  {
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 120,
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
    const isAdmin =
      adminDoc.exists ||
      userDoc.data()?.isAdmin === true ||
      request.auth.token?.admin === true;
    if (!isAdmin) {
      throw new HttpsError('permission-denied', 'Admin access required');
    }

    const {year, month, force = false} = request.data || {};
    if (!year || month === undefined || month === null) {
      throw new HttpsError('invalid-argument', 'year and month required');
    }
    if (month < 1 || month > 12) {
      throw new HttpsError('invalid-argument', 'month must be 1-12');
    }

    const result = await computeMonthlySummary(year, month - 1, 'manual', force);
    return {success: true, result};
  },
);
