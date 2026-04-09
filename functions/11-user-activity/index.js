// functions/11-user-activity/index.js
// Slimmed-down user activity tracking — aggregates only, no raw event storage

import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {checkRateLimit as redisRateLimit} from '../shared/redis.js';

// ============================================================================
// CONFIGURATION
// ============================================================================

const ACTIVITY_WEIGHTS = {
  click: 1,
  view: 2,
  addToCart: 5,
  removeFromCart: -2,
  favorite: 3,
  unfavorite: -1,
  purchase: 10,
  search: 1,
};

const CONFIG = {
  RATE_LIMIT_WINDOW_MS: 60000,
  RATE_LIMIT_MAX_REQUESTS: 20,
  MAX_EVENTS_PER_BATCH: 100,
  MAX_EVENT_AGE_MS: 24 * 60 * 60 * 1000,
  RETENTION_DAYS: 90,
  DLQ_MAX_RETRIES: 5,
  MAX_RECENT_PRODUCTS: 50,
};

// ============================================================================
// RATE LIMITING (Redis)
// ============================================================================

async function checkRateLimit(userId) {
  // 20 requests per 60 seconds per user (same as original)
  // Fail closed (return false) if Redis is down, matching original behavior
  try {
    return await redisRateLimit(`activity:${userId}`, CONFIG.RATE_LIMIT_MAX_REQUESTS, Math.ceil(CONFIG.RATE_LIMIT_WINDOW_MS / 1000));
  } catch (error) {
    console.error('Rate limit check failed:', error);
    return false;
  }
}

// ============================================================================
// RETRY HELPER
// ============================================================================

async function retryWithBackoff(operation, maxRetries = 3, baseDelay = 100) {
  let lastError;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;

      if (error.code === 'invalid-argument' ||
          error.code === 'permission-denied') {
        throw error;
      }

      if (attempt < maxRetries) {
        const delay = baseDelay * Math.pow(2, attempt - 1);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}

// ============================================================================
// DEAD LETTER QUEUE HELPER
// ============================================================================

async function saveToDeadLetterQueue(db, userId, events, error) {
  try {
    await db.collection('activity_dlq').add({
      userId,
      events,
      error: error.message || 'Unknown error',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      retryCount: 0,
      status: 'pending',
    });
    console.warn(`📥 DLQ: Saved ${events.length} events for user ${userId}`);
  } catch (dlqError) {
    console.error(JSON.stringify({
      level: 'CRITICAL',
      event: 'dlq_save_failed',
      userId,
      eventCount: events.length,
      originalError: error.message,
      dlqError: dlqError.message,
    }));
  }
}

// ============================================================================
// MAIN BATCH PROCESSING FUNCTION
// ============================================================================

export const batchUserActivity = onCall({
  timeoutSeconds: 30,
  memory: '256MiB',
  region: 'europe-west3',
  maxInstances: 50,
  concurrency: 80,
  vpcConnector: 'nar24-vpc',
  vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
}, async (request) => {
  const startTime = Date.now();

  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Must be logged in');
  }

  const userId = request.auth.uid;

  if (!(await checkRateLimit(userId))) {
    return {success: true, processed: 0, rateLimited: true};
  }

  const {events} = request.data;

  if (!Array.isArray(events) || events.length === 0) {
    return {success: true, processed: 0};
  }

  if (events.length > CONFIG.MAX_EVENTS_PER_BATCH) {
    throw new HttpsError(
      'invalid-argument',
      `Maximum ${CONFIG.MAX_EVENTS_PER_BATCH} events per batch`,
    );
  }

  const now = Date.now();
  const validEvents = events.filter((event) => {
    if (!event.eventId || !event.type || !event.timestamp) return false;
    if (!Object.hasOwn(ACTIVITY_WEIGHTS, event.type)) return false;
    if (now - event.timestamp > CONFIG.MAX_EVENT_AGE_MS) return false;
    return true;
  });

  if (validEvents.length === 0) {
    return {success: true, processed: 0};
  }

  const db = admin.firestore();

  try {
    await retryWithBackoff(async () => {
      await processEventBatch(db, userId, validEvents);
    }, 3, 100);

    const duration = Date.now() - startTime;

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'batch_processed',
      userId: userId.substring(0, 8),
      count: validEvents.length,
      duration,
    }));

    return {success: true, processed: validEvents.length, duration};
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'batch_failed',
      userId: userId.substring(0, 8),
      error: error.message,
    }));

    await saveToDeadLetterQueue(db, userId, validEvents, error);

    return {success: true, processed: 0, queued: validEvents.length};
  }
});


async function processEventBatch(db, userId, validEvents, fromDLQ = false) {
  const userProfileRef = db.collection('user_profiles').doc(userId);

  // ── Aggregate in memory ───────────────────────────────────────
  const categoryScores = new Map();
  const subcategoryScores = new Map();
  const brandScores = new Map();
  const genderScores = new Map();
  const recentProducts = [];
  const searchQueries = [];
  let purchaseCount = 0;
  let totalPurchaseValue = 0;

  // ── Daily summary counters (single pass) ──────────────────────
  let dayClicks = 0; let dayViews = 0; let dayCartAdds = 0;
  let dayFavorites = 0; let dayPurchases = 0; let daySearches = 0;

  const dayCategoryBreakdown = new Map();
  const dayBrandBreakdown = new Map();
  const dayGenderBreakdown = new Map();
  const recentActivityEntries = [];

  for (const event of validEvents) {
    const weight = ACTIVITY_WEIGHTS[event.type] || 0;
    const type = event.type;

    // ── Per-type counters ─────────────────────────────────────
    switch (type) {
      case 'click': dayClicks++; break;
      case 'view': dayViews++; break;
      case 'addToCart': dayCartAdds++; break;
      case 'favorite': dayFavorites++; break;
      case 'purchase': dayPurchases++; break;
      case 'search': daySearches++; break;
    }

    // ── Category (user profile) ──────────────────────────────
    if (event.category && weight > 0) {
      categoryScores.set(
        event.category,
        (categoryScores.get(event.category) || 0) + weight,
      );
    }

    if (event.subcategory && weight > 0) {
      subcategoryScores.set(
        event.subcategory,
        (subcategoryScores.get(event.subcategory) || 0) + weight,
      );
    }

    // ── Category (daily summary) ─────────────────────────────
    if (event.category && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
      if (!dayCategoryBreakdown.has(event.category)) {
        dayCategoryBreakdown.set(event.category, {
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const cat = dayCategoryBreakdown.get(event.category);
      if (type === 'click') cat.clicks++;
      else if (type === 'view') cat.views++;
      else if (type === 'addToCart') cat.cartAdds++;
      else if (type === 'favorite') cat.favorites++;
      else if (type === 'purchase') cat.purchases++;
    }

    // ── Brand (user profile) ─────────────────────────────────
    if (event.brand && weight > 0) {
      brandScores.set(
        event.brand,
        (brandScores.get(event.brand) || 0) + weight,
      );
    }

    // ── Brand (daily summary) ────────────────────────────────
    if (event.brand && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
      if (!dayBrandBreakdown.has(event.brand)) {
        dayBrandBreakdown.set(event.brand, {
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const b = dayBrandBreakdown.get(event.brand);
      if (type === 'click') b.clicks++;
      else if (type === 'view') b.views++;
      else if (type === 'addToCart') b.cartAdds++;
      else if (type === 'favorite') b.favorites++;
      else if (type === 'purchase') b.purchases++;
    }

    // ── Gender (user profile) ────────────────────────────────
    if (event.gender && weight > 0) {
      genderScores.set(
        event.gender,
        (genderScores.get(event.gender) || 0) + weight,
      );
    }

    // ── Gender (daily summary) ───────────────────────────────
    if (event.gender && ['click', 'view', 'addToCart', 'favorite', 'purchase'].includes(type)) {
      if (!dayGenderBreakdown.has(event.gender)) {
        dayGenderBreakdown.set(event.gender, {
          clicks: 0, views: 0, cartAdds: 0, favorites: 0, purchases: 0,
        });
      }
      const g = dayGenderBreakdown.get(event.gender);
      if (type === 'click') g.clicks++;
      else if (type === 'view') g.views++;
      else if (type === 'addToCart') g.cartAdds++;
      else if (type === 'favorite') g.favorites++;
      else if (type === 'purchase') g.purchases++;
    }

    // ── Recently viewed ──────────────────────────────────────
    if (event.productId && ['click', 'view', 'addToCart', 'favorite'].includes(type)) {
      recentProducts.push({
        productId: event.productId,
        timestamp: event.timestamp,
      });
    }

    // ── Purchases ────────────────────────────────────────────
    if (type === 'purchase') {
      purchaseCount++;
      totalPurchaseValue += event.totalValue || 0;
    }

    // ── Searches ─────────────────────────────────────────────
    if (type === 'search' && event.searchQuery) {
      searchQueries.push(event.searchQuery);
    }

     // ── Recent activity log ──────────────────────────────────
     recentActivityEntries.push({
      t: type,
      pid: event.productId || null,
      pn: event.productName || null,
      cat: event.category || null,
      br: event.brand || null,
      pr: event.price || null,
      q: event.searchQuery || null,
      ts: event.timestamp,
    });
  }

  // ── Single transaction: user profile + recentlyViewed ─────────
  await db.runTransaction(async (tx) => {
    const profileSnap = await tx.get(userProfileRef);
    const existing = profileSnap.exists ? profileSnap.data() : {};

    const profileUpdate = {
      'lastActivityAt': admin.firestore.FieldValue.serverTimestamp(),
      'stats.totalEvents': admin.firestore.FieldValue.increment(validEvents.length),
    };

    if (purchaseCount > 0) {
      profileUpdate['stats.totalPurchases'] =
        admin.firestore.FieldValue.increment(purchaseCount);
      profileUpdate['stats.totalSpent'] =
        admin.firestore.FieldValue.increment(totalPurchaseValue);
    }

    for (const [category, score] of categoryScores.entries()) {
      const safeKey = category.replace(/[./]/g, '_');
      profileUpdate[`categoryScores.${safeKey}`] =
        admin.firestore.FieldValue.increment(score);
    }

    for (const [subcategory, score] of subcategoryScores.entries()) {
      const safeKey = subcategory.replace(/[./]/g, '_');
      profileUpdate[`subcategoryScores.${safeKey}`] =
        admin.firestore.FieldValue.increment(score);
    }

    for (const [brand, score] of brandScores.entries()) {
      const safeKey = brand.replace(/[./]/g, '_');
      profileUpdate[`brandScores.${safeKey}`] =
        admin.firestore.FieldValue.increment(score);
    }

    for (const [gender, score] of genderScores.entries()) {
      const safeKey = gender.replace(/[./]/g, '_');
      profileUpdate[`genderScores.${safeKey}`] =
        admin.firestore.FieldValue.increment(score);
    }

    if (recentProducts.length > 0) {
      const existingRecent = existing.recentlyViewed || [];
      const mergedMap = new Map(
        existingRecent.map((item) => [item.productId, item]),
      );

      for (const item of recentProducts) {
        mergedMap.set(item.productId, {
          productId: item.productId,
          timestamp: admin.firestore.Timestamp.fromMillis(item.timestamp),
        });
      }

      profileUpdate.recentlyViewed = Array.from(mergedMap.values())
        .sort((a, b) => b.timestamp.toMillis() - a.timestamp.toMillis())
        .slice(0, CONFIG.MAX_RECENT_PRODUCTS);
    }

     // ── Recent activity feed (capped at 50) ─────────────────
     if (recentActivityEntries.length > 0) {
      const existingActivity = existing.recentActivity || [];
      profileUpdate.recentActivity = [
        ...recentActivityEntries,
        ...existingActivity,
      ].slice(0, 50);
    }

    if (profileSnap.exists) {
      tx.update(userProfileRef, profileUpdate);
    } else {
      tx.set(userProfileRef, profileUpdate, {merge: true});
    }
  });

  // ── Search analytics (fire-and-forget) ────────────────────────
  if (searchQueries.length > 0) {
    const today = new Date().toISOString().split('T')[0];
    const searchRef = db.collection('search_analytics').doc(today);
    const searchUpdate = {
      date: today,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    for (const q of searchQueries) {
      const safeQuery = q.toLowerCase().trim().substring(0, 50).replace(/[./]/g, '_');
      if (safeQuery.length > 0) {
        searchUpdate[`terms.${safeQuery}`] =
          admin.firestore.FieldValue.increment(1);
      }
    }

    searchRef.set(searchUpdate, {merge: true}).catch((err) => {
      console.warn('⚠️ Search analytics write failed:', err.message);
    });
  }

  // ── Daily engagement summary (fire-and-forget, 1 write) ───────
  const today = new Date().toISOString().split('T')[0];
  const summaryRef = db.collection('daily_engagement_summary').doc(today);

  const summaryUpdate = {
    'dateStr': today,
    'status': 'live',
    'updatedAt': admin.firestore.FieldValue.serverTimestamp(),
    'totals.totalEvents': admin.firestore.FieldValue.increment(validEvents.length),
  };

  if (dayClicks > 0) summaryUpdate['totals.totalClicks'] = admin.firestore.FieldValue.increment(dayClicks);
  if (dayViews > 0) summaryUpdate['totals.totalViews'] = admin.firestore.FieldValue.increment(dayViews);
  if (dayCartAdds > 0) summaryUpdate['totals.totalCartAdds'] = admin.firestore.FieldValue.increment(dayCartAdds);
  if (dayFavorites > 0) summaryUpdate['totals.totalFavorites'] = admin.firestore.FieldValue.increment(dayFavorites);
  if (dayPurchases > 0) summaryUpdate['totals.totalPurchaseEvents'] = admin.firestore.FieldValue.increment(dayPurchases);
  if (daySearches > 0) summaryUpdate['totals.totalSearches'] = admin.firestore.FieldValue.increment(daySearches);

  for (const [category, counts] of dayCategoryBreakdown.entries()) {
    const safeKey = category.replace(/[./|]/g, '_');
    summaryUpdate[`categoryEngagement.${safeKey}.category`] = category;
    if (counts.clicks > 0) summaryUpdate[`categoryEngagement.${safeKey}.clicks`] = admin.firestore.FieldValue.increment(counts.clicks);
    if (counts.views > 0) summaryUpdate[`categoryEngagement.${safeKey}.views`] = admin.firestore.FieldValue.increment(counts.views);
    if (counts.cartAdds > 0) summaryUpdate[`categoryEngagement.${safeKey}.cartAdds`] = admin.firestore.FieldValue.increment(counts.cartAdds);
    if (counts.favorites > 0) summaryUpdate[`categoryEngagement.${safeKey}.favorites`] = admin.firestore.FieldValue.increment(counts.favorites);
    if (counts.purchases > 0) summaryUpdate[`categoryEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(counts.purchases);
  }

  for (const [brand, counts] of dayBrandBreakdown.entries()) {
    const safeKey = brand.replace(/[./|]/g, '_');
    summaryUpdate[`brandEngagement.${safeKey}.brand`] = brand;
    if (counts.clicks > 0) summaryUpdate[`brandEngagement.${safeKey}.clicks`] = admin.firestore.FieldValue.increment(counts.clicks);
    if (counts.views > 0) summaryUpdate[`brandEngagement.${safeKey}.views`] = admin.firestore.FieldValue.increment(counts.views);
    if (counts.cartAdds > 0) summaryUpdate[`brandEngagement.${safeKey}.cartAdds`] = admin.firestore.FieldValue.increment(counts.cartAdds);
    if (counts.favorites > 0) summaryUpdate[`brandEngagement.${safeKey}.favorites`] = admin.firestore.FieldValue.increment(counts.favorites);
    if (counts.purchases > 0) summaryUpdate[`brandEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(counts.purchases);
  }

  for (const [gender, counts] of dayGenderBreakdown.entries()) {
    const safeKey = gender.replace(/[./|]/g, '_');
    summaryUpdate[`genderEngagement.${safeKey}.gender`] = gender;
    if (counts.clicks > 0) summaryUpdate[`genderEngagement.${safeKey}.clicks`] = admin.firestore.FieldValue.increment(counts.clicks);
    if (counts.views > 0) summaryUpdate[`genderEngagement.${safeKey}.views`] = admin.firestore.FieldValue.increment(counts.views);
    if (counts.cartAdds > 0) summaryUpdate[`genderEngagement.${safeKey}.cartAdds`] = admin.firestore.FieldValue.increment(counts.cartAdds);
    if (counts.favorites > 0) summaryUpdate[`genderEngagement.${safeKey}.favorites`] = admin.firestore.FieldValue.increment(counts.favorites);
    if (counts.purchases > 0) summaryUpdate[`genderEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(counts.purchases);
  }

  for (const q of searchQueries) {
    const safeQuery = q.toLowerCase().trim().substring(0, 50).replace(/[./|]/g, '_');
    if (safeQuery.length > 0) {
      summaryUpdate[`searchTerms.${safeQuery}`] = admin.firestore.FieldValue.increment(1);
    }
  }

  summaryRef.update(summaryUpdate).catch(async (err) => {
    if (err.code === 5 || err.code === 'not-found') {
      await summaryRef.set({}).catch(() => {});
      await summaryRef.update(summaryUpdate).catch((e) => {
        console.warn('⚠️ Daily summary increment failed:', e.message);
      });
    } else {
      console.warn('⚠️ Daily summary increment failed:', err.message);
    }
  });
}

// ============================================================================
// DEAD LETTER QUEUE PROCESSOR (Every 6 hours)
// ============================================================================

export const processActivityDLQ = onSchedule({
  schedule: 'every 6 hours',
  timeZone: 'UTC',
  timeoutSeconds: 300,
  memory: '256MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();

  try {
    const dlqSnapshot = await db
      .collection('activity_dlq')
      .where('status', '==', 'pending')
      .where('retryCount', '<', CONFIG.DLQ_MAX_RETRIES)
      .orderBy('retryCount')
      .orderBy('createdAt')
      .limit(50)
      .get();

    if (dlqSnapshot.empty) {
      console.log('✅ DLQ empty');
      return;
    }

    let processed = 0;
    let failed = 0;

    for (const dlqDoc of dlqSnapshot.docs) {
      const dlqData = dlqDoc.data();

      try {
        await processEventBatch(db, dlqData.userId, dlqData.events, true);

        await dlqDoc.ref.update({
          status: 'processed',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        processed++;
      } catch (error) {
        const newRetryCount = (dlqData.retryCount || 0) + 1;

        await dlqDoc.ref.update({
          retryCount: newRetryCount,
          lastError: error.message,
          lastRetryAt: admin.firestore.FieldValue.serverTimestamp(),
          status:
            newRetryCount >= CONFIG.DLQ_MAX_RETRIES ? 'failed' : 'pending',
        });

        failed++;
      }
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'dlq_processed',
      processed,
      failed,
      total: dlqSnapshot.size,
    }));
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'dlq_processing_failed',
      error: error.message,
    }));
  }
});

// ============================================================================
// CLEANUP (Daily at 03:00 UTC)
// ============================================================================

export const cleanupOldActivityEvents = onSchedule({
  schedule: 'every day 03:00',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '256MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - CONFIG.RETENTION_DAYS);
  const cutoffDateStr = cutoffDate.toISOString().split('T')[0];

  try {
    // Delete old search analytics
    const searchSnapshot = await db
      .collection('search_analytics')
      .where(admin.firestore.FieldPath.documentId(), '<', cutoffDateStr)
      .limit(90)
      .get();

    if (!searchSnapshot.empty) {
      const batch = db.batch();
      searchSnapshot.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }

    // Delete processed/failed DLQ items older than 7 days
    const dlqCutoff = new Date();
    dlqCutoff.setDate(dlqCutoff.getDate() - 7);

    const dlqSnapshot = await db
      .collection('activity_dlq')
      .where('status', 'in', ['processed', 'failed'])
      .where('createdAt', '<', dlqCutoff)
      .limit(500)
      .get();

    if (!dlqSnapshot.empty) {
      const batch = db.batch();
      dlqSnapshot.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }

     // Delete old daily engagement summaries
     const oldSummaries = await db
     .collection('daily_engagement_summary')
     .where(admin.firestore.FieldPath.documentId(), '<', cutoffDateStr)
     .limit(90)
     .get();

  // Rate limit cleanup no longer needed — Redis keys auto-expire

   if (!oldSummaries.empty) {
     const batch = db.batch();
     oldSummaries.docs.forEach((d) => batch.delete(d.ref));
     await batch.commit();
   }

   console.log(JSON.stringify({
    level: 'INFO',
    event: 'cleanup_completed',
    searchDocsDeleted: searchSnapshot.size,
    dlqDeleted: dlqSnapshot.size,
    summariesDeleted: oldSummaries.size,
  }));
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'cleanup_failed',
      error: error.message,
    }));
  }
});

// ============================================================================
// COMPUTE USER PREFERENCES (Daily at 06:00 UTC)
// ============================================================================

export const computeUserPreferences = onSchedule({
  schedule: 'every day 06:00',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '1GiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const startTime = Date.now();

  try {
    let processed = 0;
    let totalFetched = 0;
    let lastDoc = null;
    const PAGE_SIZE = 500;

    const hasMore = true;
while (hasMore) {
      let q = db
        .collection('user_profiles')
        .where('lastActivityAt', '>=', oneDayAgo)
        .orderBy('lastActivityAt')
        .limit(PAGE_SIZE);

      if (lastDoc) {
        q = q.startAfter(lastDoc);
      }

      const profilesSnapshot = await q.get();

      if (profilesSnapshot.empty) break;

      totalFetched += profilesSnapshot.size;
      lastDoc = profilesSnapshot.docs[profilesSnapshot.docs.length - 1];

      // Process in batches of 50
      for (let i = 0; i < profilesSnapshot.docs.length; i += 50) {
        const batch = db.batch();
        const chunk = profilesSnapshot.docs.slice(i, i + 50);

        for (const profileDoc of chunk) {
          try {
            const profile = profileDoc.data();

            // Prune + compute top categories
            const categoryScores = profile.categoryScores || {};
            const prunedCategoryScores = {};
            const topCategories = [];

            Object.entries(categoryScores)
              .sort((a, b) => b[1] - a[1])
              .forEach(([category, score], idx) => {
                if (score >= 5 && idx < 100) {
                  prunedCategoryScores[category] = score;
                }
                if (idx < 10) {
                  topCategories.push({category, score});
                }
              });

            // Prune + compute top subcategories
            const subcategoryScores = profile.subcategoryScores || {};
            const prunedSubcategoryScores = {};

            Object.entries(subcategoryScores)
              .sort((a, b) => b[1] - a[1])
              .forEach(([subcategory, score], idx) => {
                if (score >= 5 && idx < 100) {
                  prunedSubcategoryScores[subcategory] = score;
                }
              });

            // Prune + compute top brands
            const brandScores = profile.brandScores || {};
            const prunedBrandScores = {};
            const topBrands = [];

            Object.entries(brandScores)
              .sort((a, b) => b[1] - a[1])
              .forEach(([brand, score], idx) => {
                if (score >= 5 && idx < 50) {
                  prunedBrandScores[brand] = score;
                }
                if (idx < 10) {
                  topBrands.push({brand, score});
                }
              });

            // Gender preference
            const genderScores = profile.genderScores || {};
            const sortedGenders = Object.entries(genderScores)
              .sort((a, b) => b[1] - a[1])
              .map(([gender, score]) => ({gender, score}));

            // Average purchase price
            const stats = profile.stats || {};
            const avgPurchasePrice =
              stats.totalPurchases > 0 ?
                stats.totalSpent / stats.totalPurchases :
                null;

            // Prune recentlyViewed to cap
            const recentlyViewed = (profile.recentlyViewed || []).slice(
              0,
              CONFIG.MAX_RECENT_PRODUCTS,
            );

            batch.update(profileDoc.ref, {
              'categoryScores': prunedCategoryScores,
              'subcategoryScores': prunedSubcategoryScores,
              'brandScores': prunedBrandScores,
              'genderScores': genderScores,
              'recentlyViewed': recentlyViewed,
              'preferences.topCategories': topCategories,
              'preferences.topBrands': topBrands,
              'preferences.preferredGender':
                sortedGenders[0]?.gender || null,
              'preferences.genderScores': sortedGenders,
              'preferences.avgPurchasePrice': avgPurchasePrice,
              'preferences.computedAt':
                admin.firestore.FieldValue.serverTimestamp(),
              'trendingInput.needsRecompute': true,
            });

            processed++;
          } catch (err) {
            console.error(
              `Error processing ${profileDoc.id}: ${err.message}`,
            );
          }
        }

        await batch.commit();
      }

      // Timeout guard (60s buffer)
      if (Date.now() - startTime > 480000) {
        console.warn(
          `⏰ Approaching timeout after ${totalFetched} users, stopping`,
        );
        break;
      }

      if (profilesSnapshot.size < PAGE_SIZE) break;
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'preferences_computed',
      processed,
      totalFetched,
    }));
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'preferences_failed',
      error: error.message,
    }));
  }
});

// ============================================================================
// TRACK PURCHASE (Called from order creation CF)
// ============================================================================

export async function trackPurchaseActivity(userId, items, orderId) {
  if (!userId || !items || items.length === 0) return;

  const db = admin.firestore();

  try {
    let totalValue = 0;
    const categoryScores = new Map();
    const brandScores = new Map();
    const genderScores = new Map();

    for (const item of items) {
      const itemTotal = (item.price || 0) * (item.quantity || 1);
      totalValue += itemTotal;

      if (item.category) {
        categoryScores.set(
          item.category,
          (categoryScores.get(item.category) || 0) + ACTIVITY_WEIGHTS.purchase,
        );
      }

      if (item.brandModel) {
        brandScores.set(
          item.brandModel,
          (brandScores.get(item.brandModel) || 0) + ACTIVITY_WEIGHTS.purchase,
        );
      }

      if (item.gender) {
        genderScores.set(
          item.gender,
          (genderScores.get(item.gender) || 0) + ACTIVITY_WEIGHTS.purchase,
        );
      }
    }

    await retryWithBackoff(async () => {
      const userProfileRef = db.collection('user_profiles').doc(userId);

      const profileUpdate = {
        'lastActivityAt': admin.firestore.FieldValue.serverTimestamp(),
        'stats.totalEvents': admin.firestore.FieldValue.increment(
          items.length,
        ),
        'stats.totalPurchases': admin.firestore.FieldValue.increment(
          items.length,
        ),
        'stats.totalSpent': admin.firestore.FieldValue.increment(totalValue),
      };

      for (const [category, score] of categoryScores.entries()) {
        const safeKey = category.replace(/[./]/g, '_');
        profileUpdate[`categoryScores.${safeKey}`] =
          admin.firestore.FieldValue.increment(score);
      }

      for (const [brand, score] of brandScores.entries()) {
        const safeKey = brand.replace(/[./]/g, '_');
        profileUpdate[`brandScores.${safeKey}`] =
          admin.firestore.FieldValue.increment(score);
      }

      for (const [gender, score] of genderScores.entries()) {
        const safeKey = gender.replace(/[./]/g, '_');
        profileUpdate[`genderScores.${safeKey}`] =
          admin.firestore.FieldValue.increment(score);
      }

      // Build recent activity entries for purchases
const purchaseActivities = items.map((item) => ({
  t: 'purchase',
  pid: item.productId || null,
  pn: null, // product name not available in items payload
  cat: item.category || null,
  br: item.brandModel || null,
  pr: item.price || null,
  q: null,
  ts: Date.now(),
}));

// Merge with existing recentActivity
const existingDoc = await userProfileRef.get();
const existingActivity = existingDoc.exists ? (existingDoc.data().recentActivity || []) : [];
profileUpdate.recentActivity = [...purchaseActivities, ...existingActivity].slice(0, 50);

await userProfileRef.set(profileUpdate, {merge: true});
    }, 3, 100);

    // ── Daily engagement summary for purchases (outside retry) ──
    const today = new Date().toISOString().split('T')[0];
      const summaryRef = db.collection('daily_engagement_summary').doc(today);

      const summaryUpdate = {
        'dateStr': today,
        'status': 'live',
        'updatedAt': admin.firestore.FieldValue.serverTimestamp(),
        'totals.totalEvents': admin.firestore.FieldValue.increment(items.length),
        'totals.totalPurchaseEvents': admin.firestore.FieldValue.increment(items.length),
      };

      for (const [category] of categoryScores.entries()) {
        const safeKey = category.replace(/[./|]/g, '_');
        summaryUpdate[`categoryEngagement.${safeKey}.category`] = category;
        summaryUpdate[`categoryEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(
          items.filter((i) => i.category === category).length,
        );
      }

      for (const [brand] of brandScores.entries()) {
        const safeKey = brand.replace(/[./|]/g, '_');
        summaryUpdate[`brandEngagement.${safeKey}.brand`] = brand;
        summaryUpdate[`brandEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(
          items.filter((i) => i.brandModel === brand).length,
        );
      }

      for (const [gender] of genderScores.entries()) {
        const safeKey = gender.replace(/[./|]/g, '_');
        summaryUpdate[`genderEngagement.${safeKey}.gender`] = gender;
        summaryUpdate[`genderEngagement.${safeKey}.purchases`] = admin.firestore.FieldValue.increment(
          items.filter((i) => i.gender === gender).length,
        );
      }

      summaryRef.update(summaryUpdate).catch(async (err) => {
        if (err.code === 5 || err.code === 'not-found') {
          await summaryRef.set({}).catch(() => {});
          await summaryRef.update(summaryUpdate).catch((e) => {
            console.warn('⚠️ Daily summary increment failed:', e.message);
          });
        } else {
          console.warn('⚠️ Daily summary increment failed:', err.message);
        }
      });

    console.log(`✅ Tracked ${items.length} purchases for order ${orderId}`);
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'purchase_tracking_failed',
      userId: userId.substring(0, 8),
      orderId,
      error: error.message,
    }));
  }
}
