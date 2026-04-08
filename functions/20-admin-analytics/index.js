// functions/20-admin-analytics/index.js
// Manual-only admin analytics — no scheduled functions

import admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

const TOP_N = 50;

function round2(n) {
  return Math.round(n * 100) / 100;
}

// ============================================================================
// AUTH HELPER
// ============================================================================

async function verifyAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication required');
  }

  const db = admin.firestore();
  const uid = request.auth.uid;

  if (request.auth.token?.admin === true || request.auth.token?.isAdmin === true) {
    return uid;
  }

  const adminDoc = await db.collection('admins').doc(uid).get();
  if (adminDoc.exists) return uid;

  throw new HttpsError('permission-denied', 'Admin access required');
}

// ============================================================================
// DATE HELPERS
// ============================================================================

function getDateStrings(startDate, endDate) {
  const dates = [];
  const current = new Date(startDate);
  while (current < endDate) {
    const y = current.getFullYear();
    const m = String(current.getMonth() + 1).padStart(2, '0');
    const d = String(current.getDate()).padStart(2, '0');
    dates.push(`${y}-${m}-${d}`);
    current.setDate(current.getDate() + 1);
  }
  return dates;
}

function getWeekBounds(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const monday = new Date(d);
  monday.setDate(d.getDate() + diff);
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 7);
  return {weekStart: monday, weekEnd: sunday};
}

export function getWeekId(weekStart) {
  const y = weekStart.getFullYear();
  const m = String(weekStart.getMonth() + 1).padStart(2, '0');
  const d = String(weekStart.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// ============================================================================
// MERGE DAILY SUMMARIES
// ============================================================================

function mergeDailySummaries(summaries) {
  const categoryEngagement = new Map();
  const brandEngagement = new Map();
  const genderEngagement = new Map();
  const searchTerms = new Map();

  let totalClicks = 0; let totalViews = 0; let totalCartAdds = 0;
  let totalFavorites = 0; let totalSearches = 0; let totalPurchaseEvents = 0;
  let totalEvents = 0;

  for (const s of summaries) {
    const t = s.totals || {};
    totalClicks += t.totalClicks || 0;
    totalViews += t.totalViews || 0;
    totalCartAdds += t.totalCartAdds || 0;
    totalFavorites += t.totalFavorites || 0;
    totalSearches += t.totalSearches || 0;
    totalPurchaseEvents += t.totalPurchaseEvents || 0;
    totalEvents += t.totalEvents || 0;

    for (const [key, val] of Object.entries(s.categoryEngagement || {})) {
      if (!categoryEngagement.has(key)) {
        categoryEngagement.set(key, {
          category: val.category || key,
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const cat = categoryEngagement.get(key);
      cat.clicks += val.clicks || 0;
      cat.views += val.views || 0;
      cat.cartAdds += val.cartAdds || 0;
      cat.favorites += val.favorites || 0;
      cat.purchases += val.purchases || 0;
    }

    for (const [key, val] of Object.entries(s.brandEngagement || {})) {
      if (!brandEngagement.has(key)) {
        brandEngagement.set(key, {
          brand: val.brand || key,
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const b = brandEngagement.get(key);
      b.clicks += val.clicks || 0;
      b.views += val.views || 0;
      b.cartAdds += val.cartAdds || 0;
      b.favorites += val.favorites || 0;
      b.purchases += val.purchases || 0;
    }

    for (const [key, val] of Object.entries(s.genderEngagement || {})) {
      if (!genderEngagement.has(key)) {
        genderEngagement.set(key, {
          gender: val.gender || key,
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const g = genderEngagement.get(key);
      g.clicks += val.clicks || 0;
      g.views += val.views || 0;
      g.cartAdds += val.cartAdds || 0;
      g.favorites += val.favorites || 0;
      g.purchases += val.purchases || 0;
    }

    for (const [term, count] of Object.entries(s.searchTerms || {})) {
      searchTerms.set(term, (searchTerms.get(term) || 0) + count);
    }
  }

  return {
    categoryEngagement,
    brandEngagement,
    genderEngagement,
    searchTerms,
    totals: {
      totalClicks, totalViews, totalCartAdds,
      totalFavorites, totalSearches, totalPurchaseEvents, totalEvents,
    },
  };
}

// ============================================================================
// BUILD ANALYTICS FROM MERGED DATA
// ============================================================================

function buildAnalytics(engagement, sales) {
  // Top categories
  const topClickedCategories = Array.from(engagement.categoryEngagement.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N)
    .map((c) => ({...c}));

  // Conversion funnels
  const conversionFunnels = Array.from(engagement.categoryEngagement.values())
    .filter((f) => f.clicks > 0)
    .map((f) => ({
      category: f.category,
      clicks: f.clicks,
      cartAdds: f.cartAdds,
      purchases: f.purchases,
      clickToCartRate: round2((f.cartAdds / f.clicks) * 100),
      cartToPurchaseRate: f.cartAdds > 0 ? round2((f.purchases / f.cartAdds) * 100) : 0,
      overallConversion: round2((f.purchases / f.clicks) * 100),
    }))
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N);

  // Top brands
  const topClickedBrands = Array.from(engagement.brandEngagement.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N)
    .map((b) => ({...b}));

  const topSellingBrands = Array.from(engagement.brandEngagement.values())
    .filter((b) => b.purchases > 0)
    .sort((a, b) => b.purchases - a.purchases)
    .slice(0, TOP_N)
    .map((b) => ({
      brand: b.brand,
      purchases: b.purchases,
      clicks: b.clicks,
      conversionRate: b.clicks > 0 ? round2((b.purchases / b.clicks) * 100) : 0,
    }));

  // Gender breakdown
  const genderBreakdown = Array.from(engagement.genderEngagement.values())
    .map((g) => ({
      ...g,
      totalEngagement: g.clicks + g.views + g.cartAdds + g.favorites + g.purchases,
    }))
    .sort((a, b) => b.totalEngagement - a.totalEngagement);

  // Search terms
  const topSearchTerms = Array.from(engagement.searchTerms.entries())
    .map(([term, count]) => ({term, count}))
    .sort((a, b) => b.count - a.count)
    .slice(0, TOP_N);

  // Sales rankings
  let topSellersByRevenue = [];
  let topCategoriesBySales = [];

  if (sales) {
    topSellersByRevenue = sales.shopSales
      .sort((a, b) => b.totalRevenue - a.totalRevenue)
      .slice(0, TOP_N)
      .map((s) => ({
        sellerId: s.sellerId,
        sellerName: s.sellerName,
        shopId: s.shopId,
        totalRevenue: round2(s.totalRevenue),
        orderCount: s.orderCount,
        totalQuantity: s.totalQuantity,
      }));

    const salesByCat = new Map();
    for (const seller of sales.shopSales) {
      for (const [cat, data] of Object.entries(seller.categories || {})) {
        if (!salesByCat.has(cat)) {
          salesByCat.set(cat, {category: cat, revenue: 0, quantity: 0, orderCount: 0});
        }
        const agg = salesByCat.get(cat);
        agg.revenue += data.revenue || 0;
        agg.quantity += data.quantity || 0;
        agg.orderCount += data.count || 0;
      }
    }
    topCategoriesBySales = Array.from(salesByCat.values())
      .map((c) => ({...c, revenue: round2(c.revenue)}))
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, TOP_N);
  }

  return {
    ...engagement.totals,
    topClickedCategories,
    conversionFunnels,
    topClickedBrands,
    topSellingBrands,
    genderBreakdown,
    topSearchTerms,
    topSellersByRevenue,
    topCategoriesBySales,
  };
}

// ============================================================================
// READ SALES DATA
// ============================================================================

async function readSalesData(db, weekId) {
  const salesRef = db.collection('weekly_sales_accounting').doc(weekId);
  const salesSnap = await salesRef.get();

  if (!salesSnap.exists || salesSnap.data().status !== 'completed') return null;

  const shopSalesSnap = await salesRef.collection('shop_sales').get();
  return {
    summary: salesSnap.data(),
    shopSales: shopSalesSnap.docs.map((d) => d.data()),
  };
}

// ============================================================================
// MANUAL: COMPUTE WEEKLY ANALYTICS
// ============================================================================

export const computeWeeklyAnalytics = onCall({
  region: 'europe-west3',
  memory: '512MiB',
  timeoutSeconds: 120,
}, async (request) => {
  await verifyAdmin(request);

  const {weekId: reqWeekId, force = false} = request.data || {};

  if (!reqWeekId || !/^\d{4}-\d{2}-\d{2}$/.test(reqWeekId)) {
    throw new HttpsError('invalid-argument', 'weekId must be YYYY-MM-DD (Monday)');
  }

  const db = admin.firestore();
  const reportRef = db.collection('admin_analytics').doc(reqWeekId);

  // Idempotency
  if (!force) {
    const existing = await reportRef.get();
    if (existing.exists && existing.data().status === 'completed') {
      return {success: true, status: 'cached', data: existing.data()};
    }
  }

  // Get date range
  const [y, m, d] = reqWeekId.split('-').map(Number);
  const targetDate = new Date(y, m - 1, d);
  const {weekStart, weekEnd} = getWeekBounds(targetDate);
  const dates = getDateStrings(weekStart, weekEnd);
  const wid = getWeekId(weekStart);

  // Read daily summaries
  const summaryDocs = await Promise.all(
    dates.map((date) => db.collection('daily_engagement_summary').doc(date).get()),
  );

  const summaries = summaryDocs
    .filter((doc) => doc.exists)
    .map((doc) => doc.data());

  if (summaries.length === 0) {
    return {success: true, status: 'no_data', message: 'No daily summaries found for this week'};
  }

  // Merge + build
  const engagement = mergeDailySummaries(summaries);
  const sales = await readSalesData(db, wid);
  const analytics = buildAnalytics(engagement, sales);

  const result = {
    weekId: wid,
    weekStartStr: dates[0],
    weekEndStr: dates[dates.length - 1],
    status: 'completed',
    daysWithData: summaries.length,
    ...analytics,
    computedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Cache for future calls
  await reportRef.set(result, {merge: true});

  return {success: true, status: 'computed', data: result};
});

// ============================================================================
// MANUAL: COMPUTE MONTHLY SUMMARY
// ============================================================================

export const computeMonthlySummary = onCall({
  region: 'europe-west3',
  memory: '512MiB',
  timeoutSeconds: 120,
}, async (request) => {
  await verifyAdmin(request);

  const {year, month, force = false} = request.data || {};

  if (!year || !month || month < 1 || month > 12) {
    throw new HttpsError('invalid-argument', 'year and month (1-12) required');
  }

  const db = admin.firestore();
  const monthId = `${year}-${String(month).padStart(2, '0')}`;
  const summaryRef = db.collection('admin_analytics_summary').doc(monthId);

  // Idempotency
  if (!force) {
    const existing = await summaryRef.get();
    if (existing.exists && existing.data().status === 'completed') {
      return {success: true, status: 'cached', data: existing.data()};
    }
  }

  // Get all days in the month
  const startDate = new Date(year, month - 1, 1);
  const endDate = new Date(year, month, 1);
  const dates = getDateStrings(startDate, endDate);

  // Read all daily summaries for the month
  const summaryDocs = await Promise.all(
    dates.map((date) => db.collection('daily_engagement_summary').doc(date).get()),
  );

  const summaries = summaryDocs
    .filter((doc) => doc.exists)
    .map((doc) => doc.data());

  if (summaries.length === 0) {
    return {success: true, status: 'no_data', message: 'No daily summaries found for this month'};
  }

  // Merge all days
  const engagement = mergeDailySummaries(summaries);

  // Read all weekly sales for this month
  const weekSalesIds = new Set();
  const current = new Date(startDate);
  while (current < endDate) {
    const {weekStart} = getWeekBounds(current);
    weekSalesIds.add(getWeekId(weekStart));
    current.setDate(current.getDate() + 7);
  }

  // Merge sales from all weeks
  let allShopSales = [];
  for (const wid of weekSalesIds) {
    const sales = await readSalesData(db, wid);
    if (sales) {
      allShopSales = allShopSales.concat(sales.shopSales);
    }
  }

  const mergedSales = allShopSales.length > 0 ? {shopSales: allShopSales} : null;
  const analytics = buildAnalytics(engagement, mergedSales);

  const result = {
    monthId,
    year,
    month,
    status: 'completed',
    daysWithData: summaries.length,
    totalDaysInMonth: dates.length,
    ...analytics,
    computedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Cache
  await summaryRef.set(result, {merge: true});

  return {success: true, status: 'computed', data: result};
});

// ============================================================================
// MANUAL: COMPUTE CUSTOM DATE RANGE
// ============================================================================

export const computeDateRangeAnalytics = onCall({
  region: 'europe-west3',
  memory: '512MiB',
  timeoutSeconds: 120,
}, async (request) => {
  await verifyAdmin(request);

  const {startDate, endDate} = request.data || {};

  if (!startDate || !endDate) {
    throw new HttpsError('invalid-argument', 'startDate and endDate required (YYYY-MM-DD)');
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate)) {
    throw new HttpsError('invalid-argument', 'Dates must be YYYY-MM-DD format');
  }

  const start = new Date(startDate);
  const end = new Date(endDate);
  end.setDate(end.getDate() + 1); // Include end date

  const daysDiff = Math.ceil((end - start) / (1000 * 60 * 60 * 24));
  if (daysDiff > 90) {
    throw new HttpsError('invalid-argument', 'Maximum 90 days per query');
  }
  if (daysDiff < 1) {
    throw new HttpsError('invalid-argument', 'endDate must be after startDate');
  }

  const db = admin.firestore();
  const dates = getDateStrings(start, end);

  // Read daily summaries
  const summaryDocs = await Promise.all(
    dates.map((date) => db.collection('daily_engagement_summary').doc(date).get()),
  );

  const summaries = summaryDocs
    .filter((doc) => doc.exists)
    .map((doc) => doc.data());

  if (summaries.length === 0) {
    return {success: true, status: 'no_data', message: 'No data for this date range'};
  }

  const engagement = mergeDailySummaries(summaries);
  const analytics = buildAnalytics(engagement, null);

  return {
    success: true,
    status: 'computed',
    data: {
      startDate,
      endDate,
      daysWithData: summaries.length,
      totalDays: dates.length,
      ...analytics,
    },
  };
});
