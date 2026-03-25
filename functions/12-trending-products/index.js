// functions/14-trending-products/index.js
// Production-grade trending products with streaming, parallelization, and self-healing

import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  TOP_PRODUCTS_COUNT: 200,
  LOOKBACK_DAYS: 7,
  STREAM_CHUNK_SIZE: 500,
  MIN_ENGAGEMENT_THRESHOLD: 1, // 5 was too aggressive — excludes real products on growing catalogs
  MAX_RETRIES: 3,
  INCREMENTAL_UPDATE_HOURS: 0.5, // 30 min — only skip recompute within a retry window, not between scheduled runs
};

// Scoring weights (must sum to 1.0)
const WEIGHTS = {
  CLICKS: 0.30,
  CART_ADDITIONS: 0.25,
  FAVORITES: 0.20,
  PURCHASES: 0.15,
  RECENCY: 0.10,
};

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

class ProductStreamLoader {
  constructor(db) {
    this.db = db;
  }

  async* streamProducts(collection, chunkSize = CONFIG.STREAM_CHUNK_SIZE) {
    let lastDoc = null;
    let hasMore = true;

    while (hasMore) {
      try {
        let query = this.db
          .collection(collection)          
          .orderBy('__name__')
          .limit(chunkSize);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
          hasMore = false;
          break;
        }

        yield snapshot.docs.map((doc) => {
          const data = doc.data();
          return {
            id: doc.id,
            clicks: data.clickCount || 0,
            cartCount: data.cartCount || 0,
            favoritesCount: data.favoritesCount || 0,
            purchaseCount: 0, // Will be filled later
            createdAt: data.createdAt?.toDate() || new Date(),
            price: data.price || 0,
            category: data.category || 'Other',
            collection, // Track which collection this came from
          };
        });

        lastDoc = snapshot.docs[snapshot.docs.length - 1];

        // Stop if we got fewer than requested (end of collection)
        if (snapshot.size < chunkSize) {
          hasMore = false;
        }
      } catch (error) {
        console.error(`Error streaming ${collection}:`, error);
        hasMore = false;
      }
    }
  }

  async* streamAllProducts() {
 // Stream shop products
    for await (const chunk of this.streamProducts('shop_products')) {
      yield chunk;
    }
  }
}

// ============================================================================
// PURCHASE AGGREGATOR
// ============================================================================

class PurchaseAggregator {
  constructor(db) {
    this.db = db;
  }

  async aggregatePurchases(daysBack = CONFIG.LOOKBACK_DAYS) {
    console.log(`📈 Aggregating purchases from last ${daysBack} days...`);

    // Generate date strings
    const dateStrs = [];
    for (let i = 0; i < daysBack; i++) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      dateStrs.push(date.toISOString().split('T')[0]);
    }

    // Query all days in parallel
    const dayPromises = dateStrs.map((dateStr) =>
      this.queryPurchasesForDay(dateStr),
    );

    const dayResults = await Promise.allSettled(dayPromises);

    // Merge all results
    const purchases = new Map();

    for (const result of dayResults) {
      if (result.status === 'fulfilled') {
        for (const [productId, count] of result.value.entries()) {
          purchases.set(productId, (purchases.get(productId) || 0) + count);
        }
      }
    }

    console.log(`✅ Found ${purchases.size} products with purchases`);
    return purchases;
  }

  async queryPurchasesForDay(dateStr) {
    const purchases = new Map();

    try {
      const eventsSnapshot = await this.db
        .collection('activity_events')
        .doc(dateStr)
        .collection('events')
        .where('type', '==', 'purchase')
        .select('productId') // Only fetch productId field
        .get();

      for (const doc of eventsSnapshot.docs) {
        const productId = doc.data().productId;
        if (productId) {
          purchases.set(productId, (purchases.get(productId) || 0) + 1);
        }
      }
    } catch (error) {
      // Day might not exist yet, that's okay
      console.log(`⏭️ No events for ${dateStr}`);
    }

    return purchases;
  }
}

// ============================================================================
// TRENDING CALCULATOR
// ============================================================================

class TrendingCalculator {
  constructor(db) {
    this.db = db;
    this.loader = new ProductStreamLoader(db);
    this.aggregator = new PurchaseAggregator(db);
  }

  calculateRecencyBoost(daysOld) {
    if (daysOld < 0) return 1.0;
    return 1.0 / (1 + daysOld / 30);
  }

  normalize(value, min, max) {
    if (max === min) return 0.5;
    return Math.max(0, Math.min(1, (value - min) / (max - min)));
  }

  calculateTrendingScore(product, stats) {
    const clickScore = this.normalize(product.clicks, stats.minClicks, stats.maxClicks);
    const cartScore = this.normalize(product.cartCount, stats.minCart, stats.maxCart);
    const favoriteScore = this.normalize(
      product.favoritesCount,
      stats.minFavorites,
      stats.maxFavorites,
    );
    const purchaseScore = this.normalize(
      product.purchaseCount,
      stats.minPurchases,
      stats.maxPurchases,
    );

    const daysOld =
      (Date.now() - product.createdAt.getTime()) / (1000 * 60 * 60 * 24);
    const recencyScore = this.calculateRecencyBoost(daysOld);

    const trendingScore =
      clickScore * WEIGHTS.CLICKS +
      cartScore * WEIGHTS.CART_ADDITIONS +
      favoriteScore * WEIGHTS.FAVORITES +
      purchaseScore * WEIGHTS.PURCHASES +
      recencyScore * WEIGHTS.RECENCY;

    return {
      score: trendingScore,
      breakdown: {
        clicks: clickScore.toFixed(3),
        cart: cartScore.toFixed(3),
        favorites: favoriteScore.toFixed(3),
        purchases: purchaseScore.toFixed(3),
        recency: recencyScore.toFixed(3),
      },
    };
  }

  /**
   * Incremental computation: Only recompute products that changed
   */
  async shouldUseIncrementalUpdate() {
    try {
      const existingDoc = await this.db
        .collection('trending_products')
        .doc('global')
        .get();

      if (!existingDoc.exists) return {useIncremental: false};

      const lastComputed = existingDoc.data().lastComputed?.toMillis() || 0;
      const hoursSinceUpdate = (Date.now() - lastComputed) / (1000 * 60 * 60);

      // Only do full recomputation every 24 hours
      if (hoursSinceUpdate < CONFIG.INCREMENTAL_UPDATE_HOURS) {
        return {
          useIncremental: true,
          lastComputed: new Date(lastComputed),
          existingData: existingDoc.data(),
        };
      }

      return {useIncremental: false};
    } catch (error) {
      return {useIncremental: false};
    }
  }

  async computeTrendingProducts() {
    const startTime = Date.now();

    try {
      // 1. Get purchase counts (parallel aggregation)
      const purchases = await this.aggregator.aggregatePurchases();

      // 2. Check if we can do incremental update
      const {useIncremental, existingData} = await this.shouldUseIncrementalUpdate();

      if (useIncremental && existingData) {
        console.log('⚡ Using cached trending data (< 6 hours old)');
        return {
          products: existingData.products.map((id, idx) => ({
            id,
            score: existingData.scores[idx],
          })),
          stats: {
            ...existingData.stats,
            avgScore: existingData.stats.avgTrendScore,
            cached: true,
            computationTimeMs: Date.now() - startTime,
          },
        };
      }

      // 3. Stream products in chunks and build candidate list
      console.log('📊 Streaming products...');     
      let productCount = 0;

      const allProductsRaw = [];

      for await (const chunk of this.loader.streamAllProducts()) {
        for (const product of chunk) {
          product.purchaseCount = purchases.get(product.id) || 0;
          allProductsRaw.push(product);
        }
        productCount += chunk.length;
        if (productCount % 1000 === 0) {
          console.log(`📦 Processed ${productCount} products...`);
        }
      }
      
      // Apply engagement threshold, but fall back to full catalog if it excludes everything
      let allProducts = allProductsRaw.filter((p) => p.clicks >= CONFIG.MIN_ENGAGEMENT_THRESHOLD);
      
      if (allProducts.length === 0 && allProductsRaw.length > 0) {
        console.warn(`⚠️ Threshold ${CONFIG.MIN_ENGAGEMENT_THRESHOLD} excluded all products — using full catalog of ${allProductsRaw.length}`);
        allProducts = allProductsRaw;
      }
      
      console.log(`✅ Found ${allProducts.length} eligible products from ${productCount} total`);
      
      if (allProducts.length === 0) {
        throw new Error('No products found in catalog');
      }

      // 4. Calculate stats for normalization
      const stats = this.calculateStats(allProducts);

      // 5. Score all products
      const scoredProducts = allProducts.map((product) => {
        const {score, breakdown} = this.calculateTrendingScore(product, stats);
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
          },
        };
      });

      // 6. Sort and take top N
      scoredProducts.sort((a, b) => b.score - a.score);
      const topProducts = scoredProducts.slice(0, CONFIG.TOP_PRODUCTS_COUNT);

      const duration = Date.now() - startTime;

      console.log(`✅ Computed trending in ${duration}ms`);
      console.log(
        `📊 Top 5 scores: ${topProducts
          .slice(0, 5)
          .map((p) => p.score.toFixed(3))
          .join(', ')}`,
      );

      return {
        products: topProducts,
        stats: {
          totalCandidates: allProducts.length,
          totalProcessed: productCount,
          topCount: topProducts.length,
          computationTimeMs: duration,
          avgScore:
            topProducts.reduce((sum, p) => sum + p.score, 0) / topProducts.length,
          cached: false,
        },
      };
    } catch (error) {
      console.error('❌ Error computing trending:', error.message);
      throw error;
    }
  }

  calculateStats(products) {
    if (products.length === 0) {
      return {
        minClicks: 0, maxClicks: 0,
        minCart: 0, maxCart: 0,
        minFavorites: 0, maxFavorites: 0,
        minPurchases: 0, maxPurchases: 0,
      };
    }
  
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
}

// ============================================================================
// CLOUD SCHEDULER
// ============================================================================

export const computeTrendingProducts = onSchedule(
  {
    schedule: '30 */6 * * *',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '1GiB', // Reduced from 2GiB (streaming uses less memory)
    region: 'europe-west3',
    maxInstances: 1,
  },
  async () => {
    const startTime = Date.now();
    const db = admin.firestore();
    const calculator = new TrendingCalculator(db);

    try {
      console.log('🚀 Starting trending computation...');

      const result = await retryWithBackoff(
        async () => await calculator.computeTrendingProducts(),
        CONFIG.MAX_RETRIES,
        1000,
      );

      if (!result.products || result.products.length === 0) {
        throw new Error('No trending products computed');
      }

      // Prepare data for Firestore
      const trendingData = {
        products: result.products.map((p) => p.id),
        scores: result.products.map((p) => p.score),
        lastComputed: admin.firestore.FieldValue.serverTimestamp(),
        version: new Date().toISOString().split('T')[0],
        stats: {
          totalProducts: result.stats.topCount,
          totalProcessed: result.stats.totalProcessed || 0,
          totalCandidates: result.stats.totalCandidates,
          computationTimeMs: result.stats.computationTimeMs,
          avgTrendScore: parseFloat(result.stats.avgScore.toFixed(3)),
          cached: result.stats.cached || false,
        },
        topProductsDebug: result.products.slice(0, 10).map((p) => ({
          id: p.id,
          score: parseFloat(p.score.toFixed(3)),
          breakdown: p.breakdown,
          metrics: p.metrics,
        })),
      };

      // Write to Firestore with retry
      await retryWithBackoff(
        async () => {
          await db.collection('trending_products').doc('global').set(trendingData);
        },
        CONFIG.MAX_RETRIES,
        500,
      );

      // Also create category-specific trending for faster personalization
      await createCategoryTrending(db, result.products);

      const totalDuration = Date.now() - startTime;

      console.log(
        JSON.stringify({
          level: 'INFO',
          event: 'trending_computed',
          productsCount: result.stats.topCount,
          totalDuration,
          avgScore: result.stats.avgScore.toFixed(3),
          cached: result.stats.cached,
        }),
      );

      return {
        success: true,
        productsCount: result.stats.topCount,
        duration: totalDuration,
        avgScore: result.stats.avgScore,
        cached: result.stats.cached,
      };
    } catch (error) {
      const duration = Date.now() - startTime;

      console.error(
        JSON.stringify({
          level: 'ERROR',
          event: 'trending_computation_failed',
          error: error.message,
          stack: error.stack,
          duration,
          alert: true,
        }),
      );

      // Don't throw - allow graceful degradation
      return {
        success: false,
        error: error.message,
        duration,
      };
    }
  },
);

async function createCategoryTrending(db, scoredProducts) {
  try {
    console.log('📂 Creating category-specific trending...');

    const categoryCounts = new Map();

    // Group products by category (top 50 per category)
    for (const product of scoredProducts) {
      const category = product.metrics?.category || 'Other';

      if (!categoryCounts.has(category)) {
        categoryCounts.set(category, []);
      }

      if (categoryCounts.get(category).length < 50) {
        categoryCounts.get(category).push(product.id);
      }
    }

    // Write category trending in batches
    let batch = db.batch();
    let batchCount = 0;

    for (const [category, productIds] of categoryCounts.entries()) {
      const safeCategory = category.replace(/[./]/g, '_');

      batch.set(
        db.collection('trending_by_category').doc(safeCategory),
        {
          category,
          products: productIds,
          lastComputed: admin.firestore.FieldValue.serverTimestamp(),
          count: productIds.length,
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
    // Non-critical, don't throw
  }
}

/**
 * Cleanup old trending data
 */
export const cleanupTrendingHistory = onSchedule(
  {
    schedule: 'every day 04:00',
    timeZone: 'UTC',
    timeoutSeconds: 60,
    memory: '256MiB',
    region: 'europe-west3',
  },
  async () => {
    const db = admin.firestore();

    try {
      console.log('🧹 Cleaning up old trending data...');

      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

      const oldDocs = await db
        .collection('trending_products')
        .where('lastComputed', '<', sevenDaysAgo)
        .limit(100)
        .get();

      if (!oldDocs.empty) {
        const batch = db.batch();
        oldDocs.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        console.log(`✅ Cleaned up ${oldDocs.size} old trending documents`);
      }

      // Cleanup old category trending
      const oldCategoryDocs = await db
        .collection('trending_by_category')
        .where('lastComputed', '<', sevenDaysAgo)
        .limit(100)
        .get();

      if (!oldCategoryDocs.empty) {
        const batch = db.batch();
        oldCategoryDocs.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        console.log(`✅ Cleaned up ${oldCategoryDocs.size} old category trending`);
      }

      return {success: true, deleted: oldDocs.size + oldCategoryDocs.size};
    } catch (error) {
      console.error('❌ Cleanup failed:', error.message);
      return {success: false, error: error.message};
    }
  },
);
