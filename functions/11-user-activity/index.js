// functions/11-user-activity/index.js
// Production-ready user activity tracking with self-healing and efficient batching

import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

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
};

// ============================================================================
// RATE LIMITING (In-memory, per-instance)
// ============================================================================

const rateLimitMap = new Map();

function checkRateLimit(userId) {
  const now = Date.now();
  const key = `activity_${userId}`;

  if (!rateLimitMap.has(key)) {
    rateLimitMap.set(key, {count: 1, windowStart: now});
    return true;
  }

  const limit = rateLimitMap.get(key);

  if (now - limit.windowStart > CONFIG.RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(key, {count: 1, windowStart: now});
    return true;
  }

  if (limit.count >= CONFIG.RATE_LIMIT_MAX_REQUESTS) {
    return false;
  }

  limit.count++;
  return true;
}

// Periodic cleanup of rate limit map (prevents memory leak)
setInterval(() => {
  const now = Date.now();
  for (const [key, value] of rateLimitMap.entries()) {
    if (now - value.windowStart > CONFIG.RATE_LIMIT_WINDOW_MS * 2) {
      rateLimitMap.delete(key);
    }
  }
}, 60000);

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

      // Don't retry validation errors
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
    // Critical failure - log for manual recovery
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
}, async (request) => {
  const startTime = Date.now();

  // Auth check
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Must be logged in');
  }

  const userId = request.auth.uid;

  // Rate limiting
  if (!checkRateLimit(userId)) {
    return {success: true, processed: 0, rateLimited: true};
  }

  const {events} = request.data;

  // Validate input
  if (!Array.isArray(events) || events.length === 0) {
    return {success: true, processed: 0};
  }

  if (events.length > CONFIG.MAX_EVENTS_PER_BATCH) {
    throw new HttpsError('invalid-argument', `Maximum ${CONFIG.MAX_EVENTS_PER_BATCH} events per batch`);
  }

  // Filter valid events
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

    // Save to DLQ for later processing
    await saveToDeadLetterQueue(db, userId, validEvents, error);

    // Return success to client - events are safely queued
    return {success: true, processed: 0, queued: validEvents.length};
  }
});

// ============================================================================
// CORE PROCESSING LOGIC (Separated for reuse in DLQ)
// ============================================================================

async function processEventBatch(db, userId, validEvents, fromDLQ = false) {
  const batch = db.batch();
  const today = new Date().toISOString().split('T')[0];

  // Aggregation maps
  const categoryScores = new Map();
  const brandScores = new Map();
  const genderScores = new Map(); // ✅ NEW: Gender tracking
  const recentProducts = [];
  const searchQueries = [];
  let purchaseCount = 0;
  let totalPurchaseValue = 0;

  // Process each event
  for (const event of validEvents) {
    const weight = ACTIVITY_WEIGHTS[event.type] || 0;

    // Store raw event
    const eventRef = db
        .collection('activity_events')
        .doc(today)
        .collection('events')
        .doc();

    const eventData = {
      userId,
      ...event,
      weight,
      serverTimestamp: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (fromDLQ) {
      eventData.reprocessedFromDLQ = true;
    }

    batch.set(eventRef, eventData);

    // Aggregate category scores (only positive weights)
    if (event.category && weight > 0) {
      const current = categoryScores.get(event.category) || 0;
      categoryScores.set(event.category, current + weight);
    }
    
    // Aggregate subcategory scores (only positive weights)
    if (event.subcategory && weight > 0) {
      const current = categoryScores.get(event.subcategory) || 0;
      categoryScores.set(event.subcategory, current + weight);
    }

    // Aggregate brand scores (only positive weights)
    if (event.brand && weight > 0) {
      const current = brandScores.get(event.brand) || 0;
      brandScores.set(event.brand, current + weight);
    }

    // ✅ NEW: Aggregate gender scores (only positive weights)
    if (event.gender && weight > 0) {
      const current = genderScores.get(event.gender) || 0;
      genderScores.set(event.gender, current + weight);
    }

    // Track recently viewed products
    if (event.productId &&
        ['click', 'view', 'addToCart', 'favorite'].includes(event.type)) {
      recentProducts.push({
        productId: event.productId,
        timestamp: event.timestamp,
      });
    }

    // Track purchases
    if (event.type === 'purchase') {
      purchaseCount++;
      totalPurchaseValue += event.totalValue || 0;
    }

    // Track searches
    if (event.type === 'search' && event.searchQuery) {
      searchQueries.push(event.searchQuery);
    }
  }

  // Build user profile update
  const userProfileRef = db.collection('user_profiles').doc(userId);
  const profileUpdate = {
    lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
    stats: {
      totalEvents: admin.firestore.FieldValue.increment(validEvents.length),
    },
  };
  
  // Add purchase stats to nested stats object
  if (purchaseCount > 0) {
    profileUpdate.stats.totalPurchases =
      admin.firestore.FieldValue.increment(purchaseCount);
    profileUpdate.stats.totalSpent =
      admin.firestore.FieldValue.increment(totalPurchaseValue);
  }
  
  // ✅ FIXED: Build nested categoryScores object
  if (categoryScores.size > 0) {
    profileUpdate.categoryScores = {};
    for (const [category, score] of categoryScores.entries()) {
      const safeKey = category.replace(/[./]/g, '_');
      profileUpdate.categoryScores[safeKey] =
        admin.firestore.FieldValue.increment(score);
    }
  }
  
  // ✅ FIXED: Build nested brandScores object
  if (brandScores.size > 0) {
    profileUpdate.brandScores = {};
    for (const [brand, score] of brandScores.entries()) {
      const safeKey = brand.replace(/[./]/g, '_');
      profileUpdate.brandScores[safeKey] =
        admin.firestore.FieldValue.increment(score);
    }
  }

  // ✅ NEW: Build nested genderScores object
  if (genderScores.size > 0) {
    profileUpdate.genderScores = {};
    for (const [gender, score] of genderScores.entries()) {
      const safeKey = gender.replace(/[./]/g, '_');
      profileUpdate.genderScores[safeKey] =
        admin.firestore.FieldValue.increment(score);
    }
  }
  
  batch.set(userProfileRef, profileUpdate, {merge: true});

  // Update recently viewed (limit to 20, sorted by timestamp)
  if (recentProducts.length > 0) {
    const sortedRecent = recentProducts
        .sort((a, b) => b.timestamp - a.timestamp)
        .slice(0, 20)
        .map((p) => ({
          productId: p.productId,
          timestamp: admin.firestore.Timestamp.fromMillis(p.timestamp),
        }));

    batch.set(userProfileRef, {recentlyViewed: sortedRecent}, {merge: true});
  }

  // Update search analytics
  if (searchQueries.length > 0) {
    const searchRef = db.collection('search_analytics').doc(today);
    const searchUpdate = {
      date: today,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    for (const query of searchQueries) {
      const safeQuery = query
          .toLowerCase()
          .trim()
          .substring(0, 50)
          .replace(/[./]/g, '_');

      if (safeQuery.length > 0) {
        searchUpdate[`terms.${safeQuery}`] =
          admin.firestore.FieldValue.increment(1);
      }
    }

    batch.set(searchRef, searchUpdate, {merge: true});
  }

  // Commit all writes atomically
  await batch.commit();
}

// ============================================================================
// DEAD LETTER QUEUE PROCESSOR (Every 15 minutes)
// ============================================================================

export const processActivityDLQ = onSchedule({
  schedule: 'every 15 minutes',
  timeZone: 'UTC',
  timeoutSeconds: 300,
  memory: '512MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();

  console.log('🔄 Processing activity DLQ...');

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
          status: newRetryCount >= CONFIG.DLQ_MAX_RETRIES ? 'failed' : 'pending',
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
// CLEANUP OLD EVENTS (Daily at 03:00 UTC)
// ============================================================================

export const cleanupOldActivityEvents = onSchedule({
  schedule: 'every day 03:00',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '512MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - CONFIG.RETENTION_DAYS);
  const cutoffDateStr = cutoffDate.toISOString().split('T')[0];

  console.log(`🧹 Cleaning up before ${cutoffDateStr}`);

  try {
    let totalDeleted = 0;

    // Delete old activity events
    const shardsSnapshot = await db
        .collection('activity_events')
        .where(admin.firestore.FieldPath.documentId(), '<', cutoffDateStr)
        .limit(30)
        .get();

    for (const shardDoc of shardsSnapshot.docs) {
      let hasMore = true;

      while (hasMore) {
        const eventsSnapshot = await shardDoc.ref
            .collection('events')
            .limit(500)
            .get();

        if (eventsSnapshot.empty) {
          hasMore = false;
          break;
        }

        const batch = db.batch();
        eventsSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        totalDeleted += eventsSnapshot.size;
      }

      await shardDoc.ref.delete();
    }

    // Delete old search analytics
    const searchSnapshot = await db
        .collection('search_analytics')
        .where(admin.firestore.FieldPath.documentId(), '<', cutoffDateStr)
        .limit(30)
        .get();

    if (!searchSnapshot.empty) {
      const batch = db.batch();
      searchSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }

    // Delete processed DLQ items older than 7 days
    const dlqCutoff = new Date();
    dlqCutoff.setDate(dlqCutoff.getDate() - 7);

    const dlqSnapshot = await db
        .collection('activity_dlq')
        .where('status', 'in', ['processed', 'failed'])
        .where('createdAt', '<', dlqCutoff)
        .limit(100)
        .get();

    if (!dlqSnapshot.empty) {
      const batch = db.batch();
      dlqSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'cleanup_completed',
      eventsDeleted: totalDeleted,
      shardsDeleted: shardsSnapshot.size,
      searchDocsDeleted: searchSnapshot.size,
      dlqDeleted: dlqSnapshot.size,
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
// COMPUTE USER PREFERENCES (Every 6 hours)
// ============================================================================

export const computeUserPreferences = onSchedule({
  schedule: 'every 6 hours',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '1GiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();
  const sixHoursAgo = new Date(Date.now() - 6 * 60 * 60 * 1000);
  const startTime = Date.now();
  console.log('🧮 Computing user preferences...');

  try {
    let processed = 0;
let totalFetched = 0;
let lastDoc = null;
const PAGE_SIZE = 500;
const MAX_USERS = 10000; // Safety cap

while (totalFetched < MAX_USERS) {
  let query = db
      .collection('user_profiles')
      .where('lastActivityAt', '>=', sixHoursAgo)
      .orderBy('lastActivityAt')
      .limit(PAGE_SIZE);

  if (lastDoc) {
    query = query.startAfter(lastDoc);
  }

  const profilesSnapshot = await query.get();

  if (profilesSnapshot.empty) {
    if (totalFetched === 0) {
      console.log('✅ No active users');
    }
    break;
  }

  totalFetched += profilesSnapshot.size;
  lastDoc = profilesSnapshot.docs[profilesSnapshot.docs.length - 1];

  const profileDocs = profilesSnapshot.docs;

  for (let i = 0; i < profileDocs.length; i += 50) {
      const batch = db.batch();
      const chunk = profileDocs.slice(i, i + 50);

      for (const profileDoc of chunk) {
        try {
          const profile = profileDoc.data();
      
          // ✅ PRUNING: Get top categories and prune the rest
          const categoryScores = profile.categoryScores || {};
          const topCategories = Object.entries(categoryScores)
              .map(([category, score]) => ({category, score}))
              .sort((a, b) => b.score - a.score)
              .slice(0, 10);
      
          // Keep only top 100 categories (prune the rest)
          const prunedCategoryScores = {};
          Object.entries(categoryScores)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 100)
              .forEach(([category, score]) => {
                if (score >= 5) { // Only keep meaningful scores
                  prunedCategoryScores[category] = score;
                }
              });
      
          // ✅ PRUNING: Get top brands and prune the rest
          const brandScores = profile.brandScores || {};
          const topBrands = Object.entries(brandScores)
              .map(([brand, score]) => ({brand, score}))
              .sort((a, b) => b.score - a.score)
              .slice(0, 10);
      
          // Keep only top 50 brands (prune the rest)
          const prunedBrandScores = {};
          Object.entries(brandScores)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 50)
              .forEach(([brand, score]) => {
                if (score >= 5) { // Only keep meaningful scores
                  prunedBrandScores[brand] = score;
                }
              });

          // ✅ NEW: Compute gender preference
          const genderScores = profile.genderScores || {};
          const sortedGenders = Object.entries(genderScores)
              .map(([gender, score]) => ({gender, score}))
              .sort((a, b) => b.score - a.score);
          const preferredGender = sortedGenders.length > 0 ?
            sortedGenders[0].gender :
            null;
      
          // Compute average purchase price
          const stats = profile.stats || {};
          const avgPurchasePrice = stats.totalPurchases > 0 ?
            stats.totalSpent / stats.totalPurchases :
            null;
      
          // ✅ Replace entire categoryScores and brandScores with pruned versions
          batch.update(profileDoc.ref, {
            'categoryScores': prunedCategoryScores,
            'brandScores': prunedBrandScores,
            'genderScores': genderScores, // ✅ NEW: Keep as-is (very few entries)
            'preferences.topCategories': topCategories,
            'preferences.topBrands': topBrands,
            'preferences.preferredGender': preferredGender, // ✅ NEW
            'preferences.genderScores': sortedGenders, // ✅ NEW
            'preferences.avgPurchasePrice': avgPurchasePrice,
            'preferences.computedAt': admin.firestore.FieldValue.serverTimestamp(),
            'trendingInput.needsRecompute': true,
          });

          processed++;
        } catch (err) {
          console.error(`Error processing ${profileDoc.id}: ${err.message}`);
        }
      }

      await batch.commit();
    }

    // Check timeout (leave 60s buffer)
    const elapsed = Date.now() - startTime;
    if (elapsed > 480000) {
      console.warn(`⏰ Approaching timeout after ${totalFetched} users, stopping`);
      break;
    }

    // If we got fewer than PAGE_SIZE, we've reached the end
    if (profilesSnapshot.size < PAGE_SIZE) {
      break;
    }
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
// TRACK PURCHASE (Called from order creation)
// ============================================================================

export async function trackPurchaseActivity(userId, items, orderId) {
  if (!userId || !items || items.length === 0) {
    console.warn('trackPurchaseActivity: Missing required params');
    return;
  }

  const db = admin.firestore();

  try {
    await retryWithBackoff(async () => {
      const batch = db.batch();
      const today = new Date().toISOString().split('T')[0];

      let totalValue = 0;
      const categoryScores = new Map();
      const brandScores = new Map();
      const genderScores = new Map(); // ✅ NEW

      for (const item of items) {
        const eventRef = db
            .collection('activity_events')
            .doc(today)
            .collection('events')
            .doc();

        const itemTotal = (item.price || 0) * (item.quantity || 1);
        totalValue += itemTotal;

        batch.set(eventRef, {
          userId,
          eventId: `purchase_${orderId}_${item.productId}`,
          type: 'purchase',
          timestamp: Date.now(),
          weight: ACTIVITY_WEIGHTS.purchase,
          productId: item.productId,
          shopId: item.shopId || null,
          category: item.category || null,
          subcategory: item.subcategory || null,
          subsubcategory: item.subsubcategory || null,
          brand: item.brandModel || null,
          gender: item.gender || null, // ✅ NEW: Store gender in raw event
          price: item.price || 0,
          quantity: item.quantity || 1,
          totalValue: itemTotal,
          orderId,
          serverTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (item.category) {
          const current = categoryScores.get(item.category) || 0;
          categoryScores.set(item.category, current + ACTIVITY_WEIGHTS.purchase);
        }

        if (item.brandModel) {
          const current = brandScores.get(item.brandModel) || 0;
          brandScores.set(item.brandModel, current + ACTIVITY_WEIGHTS.purchase);
        }

        // ✅ NEW: Track gender from purchased items
        if (item.gender) {
          const current = genderScores.get(item.gender) || 0;
          genderScores.set(item.gender, current + ACTIVITY_WEIGHTS.purchase);
        }
      }

      // Update user profile
      const profileUpdate = {
        lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
        stats: {
          totalEvents: admin.firestore.FieldValue.increment(items.length),
          totalPurchases: admin.firestore.FieldValue.increment(items.length),
          totalSpent: admin.firestore.FieldValue.increment(totalValue),
        },
      };

      if (categoryScores.size > 0) {
        profileUpdate.categoryScores = {};
        for (const [category, score] of categoryScores.entries()) {
          const safeKey = category.replace(/[./]/g, '_');
          profileUpdate.categoryScores[safeKey] =
            admin.firestore.FieldValue.increment(score);
        }
      }
      
      // ✅ FIXED: Build nested brandScores object
      if (brandScores.size > 0) {
        profileUpdate.brandScores = {};
        for (const [brand, score] of brandScores.entries()) {
          const safeKey = brand.replace(/[./]/g, '_');
          profileUpdate.brandScores[safeKey] =
            admin.firestore.FieldValue.increment(score);
        }
      }

      // ✅ NEW: Build nested genderScores object
      if (genderScores.size > 0) {
        profileUpdate.genderScores = {};
        for (const [gender, score] of genderScores.entries()) {
          const safeKey = gender.replace(/[./]/g, '_');
          profileUpdate.genderScores[safeKey] =
            admin.firestore.FieldValue.increment(score);
        }
      }

      const userProfileRef = db.collection('user_profiles').doc(userId);
      batch.set(userProfileRef, profileUpdate, {merge: true});

      await batch.commit();
    }, 3, 100);

    console.log(`✅ Tracked ${items.length} purchases for order ${orderId}`);
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'purchase_tracking_failed',
      userId: userId.substring(0, 8),
      orderId,
      error: error.message,
    }));
    // Don't throw - purchase tracking failure shouldn't fail the order
  }
}
