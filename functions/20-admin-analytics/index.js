/**
 * Admin Analytics Module
 *
 * Computes weekly analytics by scanning activity_events (clicks, views, carts, favorites, searches)
 * and reading pre-computed weekly_sales_accounting data (revenue, orders, quantities).
 *
 * Writes results to admin_analytics/{weekId}.
 * No redundant order queries — relies entirely on already-denormalized data.
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
  const day = d.getDay();
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

function getDateStrings(weekStart, weekEnd) {
  const dates = [];
  const current = new Date(weekStart);
  while (current < weekEnd) {
    const y = current.getFullYear();
    const m = String(current.getMonth() + 1).padStart(2, '0');
    const d = String(current.getDate()).padStart(2, '0');
    dates.push(`${y}-${m}-${d}`);
    current.setDate(current.getDate() + 1);
  }
  return dates;
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
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

const PAGE_SIZE = 500;
const STALE_THRESHOLD_MS = 30 * 60 * 1000;
const TOP_N = 50;

// ═══════════════════════════════════════════════════════════════
// CORE PROCESSOR
// ═══════════════════════════════════════════════════════════════

export async function computeWeeklyAnalytics(
  weekStartDate,
  weekEndDate,
  weekId,
  triggeredBy,
  force = false,
) {
  const db = admin.firestore();
  const reportRef = db.collection('admin_analytics').doc(weekId);

  // ── 1. Idempotency gate ──────────────────────────────────────
  const existingSnap = await reportRef.get();
  if (existingSnap.exists) {
    const existing = existingSnap.data();
    if (existing.status === 'completed' && !force) {
      console.log(`⏭️  Analytics ${weekId} already completed — skipping`);
      return {weekId, status: 'skipped', reason: 'already_completed'};
    }
    if (existing.status === 'processing') {
      const startedAt = existing.processingStartedAt?.toDate?.();
      if (startedAt && Date.now() - startedAt.getTime() < STALE_THRESHOLD_MS) {
        console.log(`⏳ Analytics ${weekId} is being processed`);
        return {weekId, status: 'skipped', reason: 'currently_processing'};
      }
      console.log(`🔄 Analytics ${weekId} stale lock — retaking`);
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
    // ── 3. Scan activity events for the week ───────────────────
    const engagement = await scanActivityEvents(db, weekStartDate, weekEndDate, weekId);

    // ── 4. Read pre-computed sales data ────────────────────────
    const sales = await readSalesData(db, weekId);

    // ── 5. Build analytics ─────────────────────────────────────
    const analytics = await buildAnalytics(db, engagement, sales);

    // ── 6. Write results ───────────────────────────────────────
    await reportRef.update({
      status: 'completed',
      ...analytics,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      error: null,
    });

    console.log(
      `✅ Analytics ${weekId} completed: ${engagement.totals.totalEvents} events scanned`,
    );

    return {
      weekId,
      status: 'completed',
      totalEvents: engagement.totals.totalEvents,
    };
  } catch (error) {
    console.error(`❌ Analytics ${weekId} FAILED:`, error);
    await reportRef
      .update({
        status: 'failed',
        error: error.message || String(error),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      })
      .catch(() => {});
    return {weekId, status: 'failed', error: error.message};
  }
}

// ═══════════════════════════════════════════════════════════════
// SCAN ACTIVITY EVENTS (7 day shards)
// ═══════════════════════════════════════════════════════════════

async function scanActivityEvents(db, weekStart, weekEnd, weekId) {
  const dates = getDateStrings(weekStart, weekEnd);

  // Aggregation maps
  const categoryEngagement = new Map(); // key: "cat|subcat|subsubcat"
  const sellerClicks = new Map(); // key: shopId
  const brandEngagement = new Map(); // key: brand name
  const genderEngagement = new Map(); // key: gender value
  const searchTerms = new Map();
  const uniqueProducts = new Set();
  const uniqueUsers = new Set();
  let totalClicks = 0;
  let totalViews = 0;
  let totalCartAdds = 0;
  let totalFavorites = 0;
  let totalSearches = 0;
  let totalPurchaseEvents = 0;
  let totalEvents = 0;

  for (const dateStr of dates) {
    let cursor = null;
    let hasMore = true;

    while (hasMore) {
      let q = db
        .collection('activity_events')
        .doc(dateStr)
        .collection('events')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(PAGE_SIZE);

      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();
      if (snap.empty) {
        hasMore = false;
        break;
      }

      for (const doc of snap.docs) {
        const e = doc.data();
        totalEvents++;

        if (e.userId) uniqueUsers.add(e.userId);
        if (e.productId) uniqueProducts.add(e.productId);

        const type = e.type;

        // ── Category engagement (including purchases for funnel) ──
        if (e.category && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
          const catKey = [
            e.category,
            e.subcategory || '',
            e.subsubcategory || '',
          ].join('|');

          if (!categoryEngagement.has(catKey)) {
            categoryEngagement.set(catKey, {
              category: e.category,
              subcategory: e.subcategory || null,
              subsubcategory: e.subsubcategory || null,
              clicks: 0,
              views: 0,
              cartAdds: 0,
              favorites: 0,
              purchases: 0,
            });
          }
          const cat = categoryEngagement.get(catKey);

          if (type === 'click') {
            cat.clicks++;
            totalClicks++;
          } else if (type === 'view') {
            cat.views++;
            totalViews++;
          } else if (type === 'addToCart') {
            cat.cartAdds++;
            totalCartAdds++;
          } else if (type === 'favorite') {
            cat.favorites++;
            totalFavorites++;
          } else if (type === 'purchase') {
            cat.purchases++;
            totalPurchaseEvents++;
          }
        } else {
          // Count totals even without category
          if (type === 'click') totalClicks++;
          else if (type === 'view') totalViews++;
          else if (type === 'addToCart') totalCartAdds++;
          else if (type === 'favorite') totalFavorites++;
          else if (type === 'purchase') totalPurchaseEvents++;
        }

        // ── Brand engagement ─────────────────────────────────────
        if (e.brand && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
          const brandKey = e.brand;
          if (!brandEngagement.has(brandKey)) {
            brandEngagement.set(brandKey, {
              brand: brandKey,
              clicks: 0,
              views: 0,
              cartAdds: 0,
              favorites: 0,
              purchases: 0,
            });
          }
          const b = brandEngagement.get(brandKey);
          if (type === 'click') b.clicks++;
          else if (type === 'view') b.views++;
          else if (type === 'addToCart') b.cartAdds++;
          else if (type === 'favorite') b.favorites++;
          else if (type === 'purchase') b.purchases++;
        }

        // ── Gender engagement ────────────────────────────────────
        if (e.gender && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
          const gKey = e.gender;
          if (!genderEngagement.has(gKey)) {
            genderEngagement.set(gKey, {
              gender: gKey,
              clicks: 0,
              views: 0,
              cartAdds: 0,
              favorites: 0,
              purchases: 0,
              uniqueUsers: new Set(),
            });
          }
          const g = genderEngagement.get(gKey);
          if (type === 'click') g.clicks++;
          else if (type === 'view') g.views++;
          else if (type === 'addToCart') g.cartAdds++;
          else if (type === 'favorite') g.favorites++;
          else if (type === 'purchase') g.purchases++;
          if (e.userId) g.uniqueUsers.add(e.userId);
        }

        // ── Seller clicks ──────────────────────────────────────
        if (e.shopId && (type === 'click' || type === 'view')) {
          if (!sellerClicks.has(e.shopId)) {
            sellerClicks.set(e.shopId, {
              shopId: e.shopId,
              clicks: 0,
              views: 0,
              products: new Set(),
            });
          }
          const seller = sellerClicks.get(e.shopId);
          if (type === 'click') seller.clicks++;
          else seller.views++;
          if (e.productId) seller.products.add(e.productId);
        }

        // ── Search terms ───────────────────────────────────────
        if (type === 'search' && e.searchQuery) {
          totalSearches++;
          const term = e.searchQuery.toLowerCase().trim().substring(0, 80);
          if (term.length > 0) {
            searchTerms.set(term, (searchTerms.get(term) || 0) + 1);
          }
        }
      }

      cursor = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < PAGE_SIZE) hasMore = false;
    }

    if (totalEvents > 0 && totalEvents % 5000 === 0) {
      console.log(`📦 Analytics ${weekId}: ${totalEvents} events scanned so far`);
    }
  }

  console.log(
    `📊 Analytics ${weekId}: scan complete — ${totalEvents} events, ` +
      `${categoryEngagement.size} categories, ${brandEngagement.size} brands, ` +
      `${genderEngagement.size} genders, ${sellerClicks.size} sellers`,
  );

  return {
    categoryEngagement,
    sellerClicks,
    brandEngagement,
    genderEngagement,
    searchTerms,
    uniqueProducts: uniqueProducts.size,
    uniqueUsers: uniqueUsers.size,
    totals: {
      totalClicks,
      totalViews,
      totalCartAdds,
      totalFavorites,
      totalSearches,
      totalPurchaseEvents,
      totalEvents,
    },
  };
}

// ═══════════════════════════════════════════════════════════════
// READ SALES DATA (from weekly_sales_accounting)
// ═══════════════════════════════════════════════════════════════

async function readSalesData(db, weekId) {
  const salesRef = db.collection('weekly_sales_accounting').doc(weekId);
  const salesSnap = await salesRef.get();

  if (!salesSnap.exists || salesSnap.data().status !== 'completed') {
    console.log(`⚠️ No completed sales data for week ${weekId}`);
    return null;
  }

  const shopSalesSnap = await salesRef.collection('shop_sales').get();
  const shopSales = shopSalesSnap.docs.map((d) => d.data());

  console.log(
    `📈 Sales data loaded: ${shopSales.length} sellers for week ${weekId}`,
  );

  return {summary: salesSnap.data(), shopSales};
}

// ═══════════════════════════════════════════════════════════════
// BUILD ANALYTICS
// ═══════════════════════════════════════════════════════════════

async function buildAnalytics(db, engagement, sales) {
  // ── 1. Top clicked categories ────────────────────────────────
  const topClickedCategories = Array.from(engagement.categoryEngagement.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N)
    .map((c) => ({
      category: c.category,
      subcategory: c.subcategory,
      subsubcategory: c.subsubcategory,
      clicks: c.clicks,
      views: c.views,
      cartAdds: c.cartAdds,
      favorites: c.favorites,
      purchases: c.purchases,
    }));

  // ── 2. Top clicked sellers ───────────────────────────────────
  const topClickedSellers = Array.from(engagement.sellerClicks.values())
    .map((s) => ({
      shopId: s.shopId,
      sellerName: null, // enriched below
      clicks: s.clicks,
      views: s.views,
      uniqueProducts: s.products.size,
    }))
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N);

  // Enrich seller names from shops collection (max 20 reads)
  if (topClickedSellers.length > 0) {
    const shopRefs = topClickedSellers.map((s) =>
      db.collection('shops').doc(s.shopId),
    );
    const shopDocs = await db.getAll(...shopRefs);
    for (let i = 0; i < topClickedSellers.length; i++) {
      const shopData = shopDocs[i]?.data?.();
      if (shopData) {
        topClickedSellers[i].sellerName =
          shopData.shopName || shopData.name || shopData.sellerName || null;
      }
    }
  }

  // ── 3. Sales-based rankings ──────────────────────────────────
  let topSellersByRevenue = [];
  let topCategoriesBySales = [];
  const salesByMainCategory = new Map();

  if (sales) {
    // Enrich remaining null seller names from sales data
    const sellerNames = new Map();
    for (const s of sales.shopSales) {
      if (s.shopId) sellerNames.set(s.shopId, s.sellerName);
      sellerNames.set(s.sellerId, s.sellerName);
    }
    for (const seller of topClickedSellers) {
      if (!seller.sellerName) {
        seller.sellerName = sellerNames.get(seller.shopId) || 'Bilinmeyen';
      }
    }

    // Top sellers by revenue
    topSellersByRevenue = sales.shopSales
      .sort((a, b) => b.totalRevenue - a.totalRevenue)
      .slice(0, TOP_N)
      .map((s) => ({
        sellerId: s.sellerId,
        sellerName: s.sellerName,
        shopId: s.shopId,
        isShopProduct: s.isShopProduct,
        totalRevenue: round2(s.totalRevenue),
        orderCount: s.orderCount,
        totalQuantity: s.totalQuantity,
      }));

    // Aggregate categories from all sellers' breakdowns
    for (const seller of sales.shopSales) {
      for (const [cat, data] of Object.entries(seller.categories || {})) {
        if (!salesByMainCategory.has(cat)) {
          salesByMainCategory.set(cat, {
            category: cat,
            revenue: 0,
            quantity: 0,
            orderCount: 0,
          });
        }
        const agg = salesByMainCategory.get(cat);
        agg.revenue += data.revenue || 0;
        agg.quantity += data.quantity || 0;
        agg.orderCount += data.count || 0;
      }
    }

    topCategoriesBySales = Array.from(salesByMainCategory.values())
      .map((c) => ({...c, revenue: round2(c.revenue)}))
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, TOP_N);
  }

  // Final fallback: any seller still without a name
  for (const seller of topClickedSellers) {
    if (!seller.sellerName) seller.sellerName = 'Bilinmeyen';
  }

  // ── 4. Click vs Sale insights ────────────────────────────────
  // Aggregate clicks by main category name (flatten sub-levels)
  const clicksByMainCat = new Map();
  for (const cat of engagement.categoryEngagement.values()) {
    const name = cat.category;
    clicksByMainCat.set(name, (clicksByMainCat.get(name) || 0) + cat.clicks);
  }

  const allCategories = new Set([
    ...clicksByMainCat.keys(),
    ...salesByMainCategory.keys(),
  ]);

  const categoryComparison = [];
  for (const cat of allCategories) {
    const clicks = clicksByMainCat.get(cat) || 0;
    const salesQty = salesByMainCategory.get(cat)?.quantity || 0;
    if (clicks > 0 || salesQty > 0) {
      const ratio =
        salesQty > 0 ? round2(clicks / salesQty) : clicks > 0 ? 999 : 0;
      categoryComparison.push({
        category: cat,
        clicks,
        salesQuantity: salesQty,
        clickToSaleRatio: ratio,
      });
    }
  }

  // High click, low sale: many clicks per sale (or zero sales)
  const highClickLowSale = categoryComparison
    .filter((c) => c.clicks >= 5)
    .sort((a, b) => b.clickToSaleRatio - a.clickToSaleRatio)
    .slice(0, 10);

  // Low click, high sale: few clicks but decent sales
  const lowClickHighSale = categoryComparison
    .filter((c) => c.salesQuantity >= 3)
    .sort((a, b) => a.clickToSaleRatio - b.clickToSaleRatio)
    .slice(0, 10);

  // ── 5. Top search terms ──────────────────────────────────────
  const topSearchTerms = Array.from(engagement.searchTerms.entries())
    .map(([term, count]) => ({term, count}))
    .sort((a, b) => b.count - a.count)
    .slice(0, TOP_N);

  // ── 6. Conversion funnel per category ─────────────────────────
  // Aggregate to main category level for cleaner funnel
  const funnelByMainCat = new Map();
  for (const cat of engagement.categoryEngagement.values()) {
    const name = cat.category;
    if (!funnelByMainCat.has(name)) {
      funnelByMainCat.set(name, {
        category: name,
        clicks: 0,
        cartAdds: 0,
        purchases: 0,
      });
    }
    const f = funnelByMainCat.get(name);
    f.clicks += cat.clicks;
    f.cartAdds += cat.cartAdds;
    f.purchases += cat.purchases;
  }

  const conversionFunnels = Array.from(funnelByMainCat.values())
    .filter((f) => f.clicks > 0)
    .map((f) => ({
      category: f.category,
      clicks: f.clicks,
      cartAdds: f.cartAdds,
      purchases: f.purchases,
      clickToCartRate: f.clicks > 0 ? round2((f.cartAdds / f.clicks) * 100) : 0,
      cartToPurchaseRate: f.cartAdds > 0 ? round2((f.purchases / f.cartAdds) * 100) : 0,
      overallConversion: f.clicks > 0 ? round2((f.purchases / f.clicks) * 100) : 0,
    }))
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N);

  // ── 7. Brand analytics ────────────────────────────────────────
  const topClickedBrands = Array.from(engagement.brandEngagement.values())
    .sort((a, b) => b.clicks - a.clicks)
    .slice(0, TOP_N)
    .map((b) => ({
      brand: b.brand,
      clicks: b.clicks,
      views: b.views,
      cartAdds: b.cartAdds,
      favorites: b.favorites,
      purchases: b.purchases,
    }));

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

  // Brand insight: high click low sale
  const brandHighClickLowSale = Array.from(engagement.brandEngagement.values())
    .filter((b) => b.clicks >= 5)
    .map((b) => {
      const ratio = b.purchases > 0 ? round2(b.clicks / b.purchases) : b.clicks > 0 ? 999 : 0;
      return {
        brand: b.brand,
        clicks: b.clicks,
        purchases: b.purchases,
        clickToPurchaseRatio: ratio,
      };
    })
    .sort((a, b) => b.clickToPurchaseRatio - a.clickToPurchaseRatio)
    .slice(0, 10);

  // ── 8. Gender breakdown ───────────────────────────────────────
  const genderBreakdown = Array.from(engagement.genderEngagement.values())
    .map((g) => ({
      gender: g.gender,
      clicks: g.clicks,
      views: g.views,
      cartAdds: g.cartAdds,
      favorites: g.favorites,
      purchases: g.purchases,
      uniqueUsers: g.uniqueUsers.size,
      totalEngagement: g.clicks + g.views + g.cartAdds + g.favorites + g.purchases,
    }))
    .sort((a, b) => b.totalEngagement - a.totalEngagement);

  return {
    // Totals
    ...engagement.totals,
    uniqueProducts: engagement.uniqueProducts,
    uniqueUsers: engagement.uniqueUsers,

    // Rankings
    topClickedCategories,
    topClickedSellers,
    topSellersByRevenue,
    topCategoriesBySales,

    // Insights
    highClickLowSale,
    lowClickHighSale,

    // Search
    topSearchTerms,

    // Conversion funnel
    conversionFunnels,

    // Brand analytics
    topClickedBrands,
    topSellingBrands,
    brandHighClickLowSale,

    // Gender breakdown
    genderBreakdown,
  };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

// ═══════════════════════════════════════════════════════════════
// SCHEDULED — Every Monday 05:00 Istanbul (after accounting at 04:00)
// ═══════════════════════════════════════════════════════════════

export const weeklyAnalyticsScheduled = onSchedule(
  {
    schedule: 'every monday 05:00',
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
    console.log(`📅 Scheduled weekly analytics: ${weekId}`);
    await computeWeeklyAnalytics(weekStart, weekEnd, weekId, 'scheduled', false);
  },
);

// ═══════════════════════════════════════════════════════════════
// MANUAL TRIGGER — Admin panel
// ═══════════════════════════════════════════════════════════════

export const triggerWeeklyAnalytics = onCall(
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
    const isAdmin =
      adminDoc.exists ||
      userDoc.data()?.isAdmin === true ||
      request.auth.token?.admin === true;
    if (!isAdmin) {
      throw new HttpsError('permission-denied', 'Admin access required');
    }

    const {weekId: reqWeekId, force = false} = request.data || {};

    if (!reqWeekId || !/^\d{4}-\d{2}-\d{2}$/.test(reqWeekId)) {
      throw new HttpsError('invalid-argument', 'weekId must be YYYY-MM-DD');
    }

    const [y, m, d] = reqWeekId.split('-').map(Number);
    const targetDate = new Date(y, m - 1, d);
    const {weekStart, weekEnd} = getWeekBounds(targetDate);
    const wid = getWeekId(weekStart);

    const result = await computeWeeklyAnalytics(
      weekStart,
      weekEnd,
      wid,
      'manual',
      force,
    );
    return {success: true, result};
  },
);
