/**
 * Daily Engagement Pre-Aggregation
 *
 * Scans activity_events/{dateStr}/events for a single day and writes
 * a compact summary to daily_engagement_summary/{dateStr}.
 *
 * This is the scalability layer: instead of the weekly CF scanning
 * millions of raw events, it reads 7 pre-computed daily summaries.
 *
 * Cost at scale:
 *   300K events/day × $0.06/100K = $0.18/day
 *   But spread across 1 short nightly run instead of 1 massive weekly run.
 *   Each run processes fewer docs → stays well within CF timeout.
 *
 * Doc size budget (at 50K MAU):
 *   Categories: ~500 entries × 120B = 60KB
 *   Brands: ~200 entries × 80B = 16KB
 *   Gender: ~6 entries × 80B = 0.5KB
 *   Sellers: ~500 entries × 60B = 30KB
 *   Search terms: 500 entries × 50B = 25KB
 *   Total: ~130KB (well under Firestore's 1MB limit)
 */
import admin from 'firebase-admin';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

const PAGE_SIZE = 500;
const STALE_THRESHOLD_MS = 15 * 60 * 1000; // 15 min
const MAX_SEARCH_TERMS = 500; // Cap per day to control doc size

// ═══════════════════════════════════════════════════════════════
// CORE PROCESSOR
// ═══════════════════════════════════════════════════════════════

export async function computeDailyEngagement(dateStr, triggeredBy, force = false) {
  const db = admin.firestore();
  const summaryRef = db.collection('daily_engagement_summary').doc(dateStr);

  // ── 1. Idempotency ────────────────────────────────────────
  const existing = await summaryRef.get();
  if (existing.exists) {
    const data = existing.data();
    if (data.status === 'completed' && !force) {
      console.log(`⏭️ Daily ${dateStr} already completed — skipping`);
      return {dateStr, status: 'skipped', reason: 'already_completed'};
    }
    if (data.status === 'processing') {
      const startedAt = data.processingStartedAt?.toDate?.();
      if (startedAt && Date.now() - startedAt.getTime() < STALE_THRESHOLD_MS) {
        console.log(`⏳ Daily ${dateStr} currently processing — skipping`);
        return {dateStr, status: 'skipped', reason: 'currently_processing'};
      }
      console.log(`🔄 Daily ${dateStr} stale lock — retaking`);
    }
  }

  // ── 2. Lock ───────────────────────────────────────────────
  await summaryRef.set({
    dateStr,
    status: 'processing',
    triggeredBy,
    processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  try {
    // ── 3. Scan events ──────────────────────────────────────
    const result = await scanDayEvents(db, dateStr);

    // ── 4. Serialize and write ──────────────────────────────
    const serialized = serializeForFirestore(result);

    await summaryRef.update({
      status: 'completed',
      ...serialized,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      error: null,
    });

    console.log(
      `✅ Daily ${dateStr} completed: ${result.totals.totalEvents} events, ` +
        `${result.categoryEngagement.size} categories, ${result.brandEngagement.size} brands`,
    );

    return {
      dateStr,
      status: 'completed',
      totalEvents: result.totals.totalEvents,
    };
  } catch (error) {
    console.error(`❌ Daily ${dateStr} FAILED:`, error);
    await summaryRef.update({
      status: 'failed',
      error: error.message || String(error),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});
    return {dateStr, status: 'failed', error: error.message};
  }
}

// ═══════════════════════════════════════════════════════════════
// SCAN ONE DAY'S EVENTS
// ═══════════════════════════════════════════════════════════════

async function scanDayEvents(db, dateStr) {
  const categoryEngagement = new Map();
  const brandEngagement = new Map();
  const genderEngagement = new Map();
  const sellerClicks = new Map();
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

      // ── Category engagement ────────────────────────────────
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
            clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
          });
        }
        const cat = categoryEngagement.get(catKey);
        if (type === 'click') {
            cat.clicks++; totalClicks++;
        } else if (type === 'view') {
            cat.views++; totalViews++;
        } else if (type === 'addToCart') {
            cat.cartAdds++; totalCartAdds++;
        } else if (type === 'favorite') {
            cat.favorites++; totalFavorites++;
        } else if (type === 'purchase') {
            cat.purchases++; totalPurchaseEvents++;
        }
      } else {
        if (type === 'click') totalClicks++;
        else if (type === 'view') totalViews++;
        else if (type === 'addToCart') totalCartAdds++;
        else if (type === 'favorite') totalFavorites++;
        else if (type === 'purchase') totalPurchaseEvents++;
      }

      // ── Brand engagement ───────────────────────────────────
      if (e.brand && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
        if (!brandEngagement.has(e.brand)) {
          brandEngagement.set(e.brand, {
            brand: e.brand,
            clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
          });
        }
        const b = brandEngagement.get(e.brand);
        if (type === 'click') b.clicks++;
        else if (type === 'view') b.views++;
        else if (type === 'addToCart') b.cartAdds++;
        else if (type === 'favorite') b.favorites++;
        else if (type === 'purchase') b.purchases++;
      }

      // ── Gender engagement ──────────────────────────────────
      if (e.gender && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
        if (!genderEngagement.has(e.gender)) {
          genderEngagement.set(e.gender, {
            gender: e.gender,
            clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
            uniqueUsers: new Set(),
          });
        }
        const g = genderEngagement.get(e.gender);
        if (type === 'click') g.clicks++;
        else if (type === 'view') g.views++;
        else if (type === 'addToCart') g.cartAdds++;
        else if (type === 'favorite') g.favorites++;
        else if (type === 'purchase') g.purchases++;
        if (e.userId) g.uniqueUsers.add(e.userId);
      }

      // ── Seller clicks ─────────────────────────────────────
      if (e.shopId && (type === 'click' || type === 'view')) {
        if (!sellerClicks.has(e.shopId)) {
          sellerClicks.set(e.shopId, {
            shopId: e.shopId,
            clicks: 0, views: 0, products: new Set(),
          });
        }
        const seller = sellerClicks.get(e.shopId);
        if (type === 'click') seller.clicks++;
        else seller.views++;
        if (e.productId) seller.products.add(e.productId);
      }

      // ── Search terms ──────────────────────────────────────
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

    // Progress log every 50K events
    if (totalEvents > 0 && totalEvents % 50000 === 0) {
      console.log(`📦 Daily ${dateStr}: ${totalEvents} events scanned so far`);
    }
  }

  return {
    categoryEngagement,
    brandEngagement,
    genderEngagement,
    sellerClicks,
    searchTerms,
    uniqueProducts,
    uniqueUsers,
    totals: {
      totalClicks, totalViews, totalCartAdds,
      totalFavorites, totalSearches, totalPurchaseEvents, totalEvents,
    },
  };
}

// ═══════════════════════════════════════════════════════════════
// SERIALIZE FOR FIRESTORE
// Maps/Sets → plain objects/numbers for storage
// ═══════════════════════════════════════════════════════════════

function serializeForFirestore(result) {
  // Category engagement: Map → plain object
  const categoryEngagement = {};
  for (const [key, val] of result.categoryEngagement) {
    categoryEngagement[key] = {
      category: val.category,
      subcategory: val.subcategory,
      subsubcategory: val.subsubcategory,
      clicks: val.clicks,
      views: val.views,
      cartAdds: val.cartAdds,
      favorites: val.favorites,
      purchases: val.purchases,
    };
  }

  // Brand engagement
  const brandEngagement = {};
  for (const [key, val] of result.brandEngagement) {
    brandEngagement[key] = {
      brand: val.brand,
      clicks: val.clicks,
      views: val.views,
      cartAdds: val.cartAdds,
      favorites: val.favorites,
      purchases: val.purchases,
    };
  }

  // Gender engagement (Set → count)
  const genderEngagement = {};
  for (const [key, val] of result.genderEngagement) {
    genderEngagement[key] = {
      gender: val.gender,
      clicks: val.clicks,
      views: val.views,
      cartAdds: val.cartAdds,
      favorites: val.favorites,
      purchases: val.purchases,
      uniqueUserCount: val.uniqueUsers.size,
    };
  }

  // Seller clicks (Set → count)
  const sellerClicks = {};
  for (const [key, val] of result.sellerClicks) {
    sellerClicks[key] = {
      shopId: val.shopId,
      clicks: val.clicks,
      views: val.views,
      uniqueProductCount: val.products.size,
    };
  }

  // Search terms: cap at MAX_SEARCH_TERMS, sorted by count desc
  const sortedTerms = Array.from(result.searchTerms.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, MAX_SEARCH_TERMS);
  const searchTerms = {};
  for (const [term, count] of sortedTerms) {
    searchTerms[term] = count;
  }

  return {
    categoryEngagement,
    brandEngagement,
    genderEngagement,
    sellerClicks,
    searchTerms,
    totals: result.totals,
    uniqueProductCount: result.uniqueProducts.size,
    uniqueUserCount: result.uniqueUsers.size,
    eventCount: result.totals.totalEvents,
  };
}

// ═══════════════════════════════════════════════════════════════
// SCHEDULED — Every day at 01:00 Istanbul
// ═══════════════════════════════════════════════════════════════

export const dailyEngagementScheduled = onSchedule(
  {
    schedule: '0 1 * * *',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west3',
    memory: '1GiB',
    timeoutSeconds: 540,
    retryCount: 2,
  },
  async () => {
    // Process yesterday
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    const dateStr = [
      yesterday.getFullYear(),
      String(yesterday.getMonth() + 1).padStart(2, '0'),
      String(yesterday.getDate()).padStart(2, '0'),
    ].join('-');

    console.log(`📅 Scheduled daily engagement: ${dateStr}`);
    await computeDailyEngagement(dateStr, 'scheduled', false);
  },
);

// ═══════════════════════════════════════════════════════════════
// MANUAL TRIGGER
// ═══════════════════════════════════════════════════════════════

export const triggerDailyEngagement = onCall(
  {
    region: 'europe-west3',
    memory: '1GiB',
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

    const {dateStr, force = false} = request.data || {};
    if (!dateStr || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
      throw new HttpsError('invalid-argument', 'dateStr required (YYYY-MM-DD)');
    }

    const result = await computeDailyEngagement(dateStr, 'manual', force);
    return {success: true, result};
  },
);
