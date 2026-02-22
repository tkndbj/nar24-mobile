import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

// ============================================================================
// SHARED SCORING UTILITY
// Export computeScores and related constants so expireSingleBoost can import
// from this file directly — single source of truth for all ranking logic.
//
// Usage in expireSingleBoost:
//   import { computeScores, DEFAULT_THRESHOLDS } from './computeRankingScores.js';
//   const scores = computeScores({ ...data, isBoosted: false }, DEFAULT_THRESHOLDS);
// ============================================================================

export const DEFAULT_THRESHOLDS = {
  purchaseP95: 100,
  cartP95: 50,
  favP95: 50,
};

export const BOOST_MULTIPLIER = 1.5;
export const BOOST_OFFSET = 1000;

const WEIGHTS = {
  purchase: 0.25,
  ctr: 0.15,
  conversion: 0.10,
  rating: 0.10,
  cart: 0.10,
  favorites: 0.10,
  recency: 0.20,
};

const BONUSES = {
  coldStart: 0.15, // product is <= 7 days old
  recentActivity: 0.10, // product was clicked in the last 48 hours
};


export function computeScores(d, thresholds) {
  // createdAt is required for recency — return null so callers can skip safely
  if (!d.createdAt?.toMillis) return null;

  const clicks      = Math.max(d.clickCount || 0, 0);
  const purchases   = Math.max(d.purchaseCount || 0, 0);
  const cart        = Math.max(d.cartCount || 0, 0);
  const favorites   = Math.max(d.favoritesCount || 0, 0);
  const rating      = Math.max(d.averageRating || 0, 0);
  const impressions = Math.max(d.impressionCount || 0, 0);

  // ── Normalized signals [0, 1] ────────────────────────────────────────────
  const purchaseNorm = Math.min(purchases / thresholds.purchaseP95, 1.0);
  const cartNorm     = Math.min(cart / thresholds.cartP95, 1.0);
  const favNorm      = Math.min(favorites / thresholds.favP95, 1.0);
  const ratingNorm   = rating / 5.0;

  // CTR requires enough impressions to be meaningful — skip if data is thin
  const ctr = impressions >= 10 ? Math.min(clicks / impressions, 1.0) : 0;

  // Conversion requires enough clicks to be meaningful — skip if data is thin
  const conversion = clicks >= 5 ? Math.min(purchases / clicks, 1.0) : 0;

  // ── Recency ──────────────────────────────────────────────────────────────
  // Exponential decay: score ~1.0 at day 0, ~0.37 at day 30, ~0.05 at day 90
  const ageDays     = (Date.now() - d.createdAt.toMillis()) / 86400000;
  const recency     = Math.exp(-ageDays / 30);
  const coldStart   = ageDays <= 7 ? BONUSES.coldStart : 0;
  const recentClick = _isRecentlyActive(d.lastClickDate) ? BONUSES.recentActivity : 0;

  // ── Organic score ────────────────────────────────────────────────────────
  const organicScore =
    WEIGHTS.purchase   * purchaseNorm +
    WEIGHTS.ctr        * ctr +
    WEIGHTS.conversion * conversion +
    WEIGHTS.rating     * ratingNorm +
    WEIGHTS.cart       * cartNorm +
    WEIGHTS.favorites  * favNorm +
    WEIGHTS.recency    * recency +
    coldStart +
    recentClick;

  // ── Promotion score ──────────────────────────────────────────────────────
  // Boosted: multiplier applied to organic so merit still matters within the
  // boosted tier, then offset added to guarantee boosted > non-boosted always.
  const promotionScore = d.isBoosted ? (organicScore * BOOST_MULTIPLIER) + BOOST_OFFSET : organicScore;

  return {
    organicScore: _round4(organicScore),
    promotionScore: _round4(promotionScore),
    lastRankingUpdate: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function _isRecentlyActive(lastClickDate) {
  if (!lastClickDate?.toMillis) return false;
  return lastClickDate.toMillis() >= Date.now() - 48 * 60 * 60 * 1000;
}

function _round4(n) {
  return Math.round(n * 10000) / 10000;
}

// ============================================================================
// THRESHOLD LOADER
// Reads from ranking_config/thresholds in Firestore so you can tune values
// without redeploying. Falls back to DEFAULT_THRESHOLDS if doc is missing.
//
// To update thresholds: write to ranking_config/thresholds in Firestore.
// Shape: { purchaseP95: number, cartP95: number, favP95: number }
// ============================================================================

async function loadThresholds(db) {
  try {
    const doc = await db.collection('ranking_config').doc('thresholds').get();
    if (!doc.exists) {
      console.log('[loadThresholds] No config doc found, using defaults');
      return DEFAULT_THRESHOLDS;
    }
    const thresholds = { ...DEFAULT_THRESHOLDS, ...doc.data() };
    console.log('[loadThresholds] Loaded:', thresholds);
    return thresholds;
  } catch (err) {
    console.error('[loadThresholds] Failed, using defaults:', err.message);
    return DEFAULT_THRESHOLDS;
  }
}

// ============================================================================
// SCHEDULED FUNCTION — runs every 12 hours
// Only processes products whose metrics changed since the last run
// (metricsUpdatedAt is set by your click/cart/fav sync pipelines).
// ============================================================================

export const computeRankingScores = onSchedule(
  {
    schedule: '0 */12 * * *',
    timeZone: 'UTC',
    region: 'europe-west3',
    memory: '1GiB',
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const startTime = Date.now();
    console.log('[computeRankingScores] start');

    const thresholds = await loadThresholds(db);

    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 12 * 60 * 60 * 1000,
    );

    const [productsResult, shopProductsResult] = await Promise.allSettled([
      processCollection(db, 'products', cutoff, thresholds),
      processCollection(db, 'shop_products', cutoff, thresholds),
    ]);

    const totalUpdated =
      (productsResult.status === 'fulfilled' ? productsResult.value : 0) +
      (shopProductsResult.status === 'fulfilled' ? shopProductsResult.value : 0);

    if (productsResult.status === 'rejected') {
      console.error('[computeRankingScores] products failed:', productsResult.reason);
    }
    if (shopProductsResult.status === 'rejected') {
      console.error('[computeRankingScores] shop_products failed:', shopProductsResult.reason);
    }

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'ranking_scores_computed',
      totalUpdated,
      durationMs: Date.now() - startTime,
    }));
  },
);

// ============================================================================
// COLLECTION PROCESSOR
// ============================================================================

async function processCollection(db, collectionName, cutoff, thresholds) {
  let totalUpdated = 0;
  let totalSkipped = 0;
  let totalErrors  = 0;
  const pendingUpdates = [];
  let lastDoc = null;
  const PAGE_SIZE      = 500;
  const BATCH_FLUSH_AT = 450;

  console.log(`[${collectionName}] Starting`);

  let hasMore = true;
while (hasMore) {
    let query = db
      .collection(collectionName)
      .where('metricsUpdatedAt', '>=', cutoff)
      .orderBy('metricsUpdatedAt')
      .limit(PAGE_SIZE);

    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    for (const doc of snapshot.docs) {
      try {
        const data = doc.data();

        const hasSignals =
          (data.clickCount     || 0) > 0 ||
          (data.purchaseCount  || 0) > 0 ||
          (data.cartCount      || 0) > 0 ||
          (data.favoritesCount || 0) > 0 ||
          (data.averageRating  || 0) > 0 ||
          (data.impressionCount|| 0) > 0;

        const ageDays = data.createdAt?.toMillis ? (Date.now() - data.createdAt.toMillis()) / 86400000 : Infinity;

        if (!hasSignals && ageDays > 30) {
          totalSkipped++;
          continue;
        }

        const scores = computeScores(data, thresholds);

        if (!scores) {
          console.warn(`[${collectionName}] ${doc.id}: missing createdAt, skipping`);
          totalSkipped++;
          continue;
        }

        pendingUpdates.push({ ref: doc.ref, data: scores });
      } catch (err) {
        totalErrors++;
        console.error(`[${collectionName}] ${doc.id}: ${err.message}`);
      }

      if (pendingUpdates.length >= BATCH_FLUSH_AT) {
        const toFlush = pendingUpdates.splice(0, BATCH_FLUSH_AT);
        await commitBatch(db, collectionName, toFlush);
        totalUpdated += toFlush.length;
      }
    }

    if (snapshot.docs.length < PAGE_SIZE) hasMore = false;
  }

  if (pendingUpdates.length > 0) {
    await commitBatch(db, collectionName, pendingUpdates);
    totalUpdated += pendingUpdates.length;
  }

  console.log(JSON.stringify({
    level: 'INFO',
    event: 'collection_processed',
    collection: collectionName,
    totalUpdated,
    totalSkipped,
    totalErrors,
  }));

  return totalUpdated;
}

// ============================================================================
// BATCH COMMIT
// ============================================================================

async function commitBatch(db, collectionName, updates) {
  const batch = db.batch();
  for (const { ref, data } of updates) {
    batch.update(ref, data);
  }
  await batch.commit();
  console.log(`[${collectionName}] Committed ${updates.length} updates`);
}
