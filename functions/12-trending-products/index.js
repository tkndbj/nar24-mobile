import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

const CONFIG = {
  TOP_PRODUCTS_COUNT: 200,
  STREAM_CHUNK_SIZE: 500,
  MIN_ENGAGEMENT_THRESHOLD: 3,
  MAX_RETRIES: 3,
};

const WEIGHTS = {
  CLICKS: 0.30,
  CART_ADDITIONS: 0.25,
  FAVORITES: 0.20,
  PURCHASES: 0.15,
  RECENCY: 0.10,
};

async function retryWithBackoff(operation, maxRetries = 3, baseDelay = 100) {
  let lastError;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (error.code === 'invalid-argument' || error.code === 'permission-denied') {
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
// STREAMING PRODUCT LOADER
// ============================================================================

async function* streamProducts(db, collection, chunkSize = CONFIG.STREAM_CHUNK_SIZE) {
  let lastDoc = null;

  while (true) {
    let query = db
      .collection(collection)
      .orderBy('__name__')
      .limit(chunkSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    yield snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        clicks: data.clickCount || 0,
        cartCount: data.cartCount || 0,
        favoritesCount: data.favoritesCount || 0,
        purchaseCount: data.purchaseCount || 0,
        createdAt: data.createdAt?.toDate() || new Date(),
        price: data.price || 0,
        category: data.category || 'Other',
        subcategory: data.subcategory || null,
        brand: data.brandModel || null,
        gender: data.gender || null,
        collection,
      };
    });

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < chunkSize) break;
  }
}

// ============================================================================
// SCORING
// ============================================================================

function normalize(value, min, max) {
  if (max === min) return 0.5;
  return Math.max(0, Math.min(1, (value - min) / (max - min)));
}

function calculateStats(products) {
  const stats = {
    minClicks: Infinity, maxClicks: -Infinity,
    minCart: Infinity, maxCart: -Infinity,
    minFavorites: Infinity, maxFavorites: -Infinity,
    minPurchases: Infinity, maxPurchases: -Infinity,
  };

  for (const p of products) {
    if (p.clicks < stats.minClicks) stats.minClicks = p.clicks;
    if (p.clicks > stats.maxClicks) stats.maxClicks = p.clicks;
    if (p.cartCount < stats.minCart) stats.minCart = p.cartCount;
    if (p.cartCount > stats.maxCart) stats.maxCart = p.cartCount;
    if (p.favoritesCount < stats.minFavorites) stats.minFavorites = p.favoritesCount;
    if (p.favoritesCount > stats.maxFavorites) stats.maxFavorites = p.favoritesCount;
    if (p.purchaseCount < stats.minPurchases) stats.minPurchases = p.purchaseCount;
    if (p.purchaseCount > stats.maxPurchases) stats.maxPurchases = p.purchaseCount;
  }

  return stats;
}

function scoreTrendingProduct(product, stats) {
  const clickScore = normalize(product.clicks, stats.minClicks, stats.maxClicks);
  const cartScore = normalize(product.cartCount, stats.minCart, stats.maxCart);
  const favoriteScore = normalize(product.favoritesCount, stats.minFavorites, stats.maxFavorites);
  const purchaseScore = normalize(product.purchaseCount, stats.minPurchases, stats.maxPurchases);

  const daysOld = (Date.now() - product.createdAt.getTime()) / (1000 * 60 * 60 * 24);
  const recencyScore = 1.0 / (1 + daysOld / 30);

  const score =
    clickScore * WEIGHTS.CLICKS +
    cartScore * WEIGHTS.CART_ADDITIONS +
    favoriteScore * WEIGHTS.FAVORITES +
    purchaseScore * WEIGHTS.PURCHASES +
    recencyScore * WEIGHTS.RECENCY;

  return {
    score,
    breakdown: {
      clicks: clickScore.toFixed(3),
      cart: cartScore.toFixed(3),
      favorites: favoriteScore.toFixed(3),
      purchases: purchaseScore.toFixed(3),
      recency: recencyScore.toFixed(3),
    },
  };
}

// ============================================================================
// MAIN COMPUTATION
// ============================================================================

async function computeTrendingProducts(db) {
  const startTime = Date.now();

  // Stream all shop_products — purchaseCount is already on each doc
  console.log('📊 Streaming products...');
  let productCount = 0;
  const allProductsRaw = [];

  for await (const chunk of streamProducts(db, 'shop_products')) {
    allProductsRaw.push(...chunk);
    productCount += chunk.length;
    if (productCount % 1000 === 0) {
      console.log(`📦 Processed ${productCount} products...`);
    }
  }

  // Filter by engagement threshold
  let candidates = allProductsRaw.filter(
    (p) => p.clicks >= CONFIG.MIN_ENGAGEMENT_THRESHOLD,
  );

  if (candidates.length === 0 && allProductsRaw.length > 0) {
    console.warn(`⚠️ Threshold excluded all — using full catalog (${allProductsRaw.length})`);
    candidates = allProductsRaw;
  }

  if (candidates.length === 0) {
    throw new Error('No products found in catalog');
  }

  // Score
  const stats = calculateStats(candidates);

  const scoredProducts = candidates.map((product) => {
    const {score, breakdown} = scoreTrendingProduct(product, stats);
    return {
      id: product.id,
      score,
      breakdown,
      metrics: {
        clicks: product.clicks,
        cart: product.cartCount,
        favorites: product.favoritesCount,
        purchases: product.purchaseCount,
        category: product.category,
        subcategory: product.subcategory,
        brand: product.brand,
        price: product.price,
        gender: product.gender,
      },
    };
  });

  scoredProducts.sort((a, b) => b.score - a.score);
  const topProducts = scoredProducts.slice(0, CONFIG.TOP_PRODUCTS_COUNT);

  const duration = Date.now() - startTime;
  console.log(`✅ Computed trending in ${duration}ms (${candidates.length} candidates)`);

  return {
    products: topProducts,
    stats: {
      totalCandidates: candidates.length,
      totalProcessed: productCount,
      topCount: topProducts.length,
      computationTimeMs: duration,
      avgScore: topProducts.reduce((sum, p) => sum + p.score, 0) / topProducts.length,
    },
  };
}

// ============================================================================
// CATEGORY TRENDING
// ============================================================================

async function createCategoryTrending(db, scoredProducts) {
  try {
    const categoryCounts = new Map();

    for (const product of scoredProducts) {
      const category = product.metrics?.category || 'Other';
      if (!categoryCounts.has(category)) categoryCounts.set(category, []);
      if (categoryCounts.get(category).length < 50) {
        categoryCounts.get(category).push({
          id: product.id,
          trendingScore: product.score,
          category: product.metrics.category,
          subcategory: product.metrics.subcategory || null,
          brand: product.metrics.brand || null,
          price: product.metrics.price || 0,
          gender: product.metrics.gender || null,
        });
      }
    }

    let batch = db.batch();
    let batchCount = 0;

    for (const [category, productFeatures] of categoryCounts.entries()) {
      const safeCategory = category.replace(/[./]/g, '_');
      batch.set(
        db.collection('trending_by_category').doc(safeCategory),
        {
          category,
          products: productFeatures.map((p) => p.id),
          features: productFeatures,
          lastComputed: admin.firestore.FieldValue.serverTimestamp(),
          count: productFeatures.length,
        },
        {merge: true},
      );

      batchCount++;
      if (batchCount >= 500) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    console.log(`✅ Created trending for ${categoryCounts.size} categories`);
  } catch (error) {
    console.error('⚠️ Failed to create category trending:', error.message);
  }
}

// ============================================================================
// SCHEDULED FUNCTIONS
// ============================================================================

export const computeTrendingProductsScheduled = onSchedule({
  schedule: '30 */6 * * *',
  timeZone: 'UTC',
  timeoutSeconds: 540,
  memory: '1GiB',
  region: 'europe-west3',
  maxInstances: 1,
}, async () => {
  const startTime = Date.now();
  const db = admin.firestore();

  try {
    console.log('🚀 Starting trending computation...');

    const result = await retryWithBackoff(
      () => computeTrendingProducts(db),
      CONFIG.MAX_RETRIES,
      1000,
    );

    if (!result.products || result.products.length === 0) {
      throw new Error('No trending products computed');
    }

    // Write global trending
    await retryWithBackoff(() =>
      db.collection('trending_products').doc('global').set({
        products: result.products.map((p) => p.id),
        scores: result.products.map((p) => p.score),
        lastComputed: admin.firestore.FieldValue.serverTimestamp(),
        version: new Date().toISOString().split('T')[0],
        stats: {
          totalProducts: result.stats.topCount,
          totalProcessed: result.stats.totalProcessed,
          totalCandidates: result.stats.totalCandidates,
          computationTimeMs: result.stats.computationTimeMs,
          avgTrendScore: parseFloat(result.stats.avgScore.toFixed(3)),
        },
        topProductsDebug: result.products.slice(0, 10).map((p) => ({
          id: p.id,
          score: parseFloat(p.score.toFixed(3)),
          breakdown: p.breakdown,
          metrics: p.metrics,
        })),
      }),
    );

    await createCategoryTrending(db, result.products);

    const totalDuration = Date.now() - startTime;

    console.log(JSON.stringify({
      level: 'INFO',
      event: 'trending_computed',
      productsCount: result.stats.topCount,
      totalDuration,
    }));

    return {success: true, productsCount: result.stats.topCount, duration: totalDuration};
  } catch (error) {
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'trending_computation_failed',
      error: error.message,
      duration: Date.now() - startTime,
    }));

    return {success: false, error: error.message};
  }
});

export const cleanupTrendingHistory = onSchedule({
  schedule: 'every day 04:00',
  timeZone: 'UTC',
  timeoutSeconds: 60,
  memory: '256MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();

  try {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const oldDocs = await db
      .collection('trending_products')
      .where('lastComputed', '<', sevenDaysAgo)
      .limit(100)
      .get();

    if (!oldDocs.empty) {
      const batch = db.batch();
      oldDocs.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }

    const oldCategoryDocs = await db
      .collection('trending_by_category')
      .where('lastComputed', '<', sevenDaysAgo)
      .limit(100)
      .get();

    if (!oldCategoryDocs.empty) {
      const batch = db.batch();
      oldCategoryDocs.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }

    console.log(`✅ Cleaned up ${oldDocs.size + oldCategoryDocs.size} old trending docs`);
    return {success: true};
  } catch (error) {
    console.error('❌ Cleanup failed:', error.message);
    return {success: false};
  }
});
