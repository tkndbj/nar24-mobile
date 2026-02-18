// functions/15-personalized-feed/index.js
// Production-grade personalized feed with trending-based candidates and batch operations
// ✅ UPDATED: Progressive personalization + subcategory support

import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  FEED_SIZE: 200,
  BATCH_SIZE: 50,
  MAX_CANDIDATES: 1000,
  REFRESH_INTERVAL_DAYS: 2,
  MIN_ACTIVITY_THRESHOLD: 3,
  MAX_RETRIES: 3,
  CATEGORY_TRENDING_LIMIT: 50,
};

// ✅ UPDATED: Base weights (will be dynamically adjusted)
const BASE_WEIGHTS = {
  CATEGORY_MATCH: 0.25, // Base: 25% (will scale up to 40% with engagement)
  BRAND_MATCH: 0.20, // Base: 20% (will scale up to 30% with engagement)
  TRENDING_SCORE: 0.25, // Base: 25% (will scale down to 10% with engagement)
  PRICE_RANGE_MATCH: 0.05, // Fixed: 15%
  RECENCY_PENALTY: 0.15, // Fixed: 15%
  GENDER_MATCH: 0.10,
};

// ✅ NEW: Progressive personalization config
const PERSONALIZATION_CONFIG = {
  // Activity thresholds for scaling
  MIN_EVENTS_FOR_PERSONALIZATION: 3, // Minimum to start personalizing
  FULL_PERSONALIZATION_EVENTS: 50, // Full personalization strength at 50 events
  
  // Weight scaling ranges (from base to max)
  CATEGORY_WEIGHT_MAX: 0.40, // Category can go up to 40%
  BRAND_WEIGHT_MAX: 0.30, // Brand can go up to 30%
  TRENDING_WEIGHT_MIN: 0.10, // Trending drops to minimum 10%
  
  // Subcategory bonus (portion of category score)
  SUBCATEGORY_BONUS_RATIO: 0.3, // Subcategory match adds 30% bonus to category score
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
// CANDIDATE SELECTOR
// ============================================================================

class CandidateSelector {
  constructor(db) {
    this.db = db;
    this.trendingCache = null;
    this.trendingScores = null;
  }

  async loadTrendingProducts() {
    if (this.trendingCache) {
      return this.trendingCache;
    }

    try {
      const trendingDoc = await this.db
        .collection('trending_products')
        .doc('global')
        .get();

      if (!trendingDoc.exists) {
        console.warn('⚠️ No global trending found, will use query-based approach');
        return {productIds: [], scores: new Map()};
      }

      const data = trendingDoc.data();
      const productIds = data.products || [];
      const scores = new Map();

      productIds.forEach((id, idx) => {
        scores.set(id, data.scores?.[idx] || 0);
      });

      this.trendingCache = {productIds, scores};
      this.trendingScores = scores;

      console.log(`✅ Loaded ${productIds.length} trending products`);
      return this.trendingCache;
    } catch (error) {
      console.error('⚠️ Failed to load trending:', error.message);
      return {productIds: [], scores: new Map()};
    }
  }

  async getCandidatesForUser(userProfile) {
    const topCategories =
      userProfile.preferences?.topCategories?.slice(0, 3).map((c) => c.category) || [];

    if (topCategories.length === 0) {
      const {productIds} = await this.loadTrendingProducts();
      return productIds.slice(0, CONFIG.MAX_CANDIDATES);
    }

    const categoryProducts = await this.loadCategoryTrending(topCategories);

    if (categoryProducts.length > 0) {
      return categoryProducts.slice(0, CONFIG.MAX_CANDIDATES);
    }

    return await this.queryProductsByCategories(topCategories, userProfile);
  }

  async loadCategoryTrending(categories) {
    try {
      const productSet = new Set();

      const promises = categories.map((category) =>
        this.db
          .collection('trending_by_category')
          .doc(category.replace(/[./]/g, '_'))
          .get(),
      );

      const docs = await Promise.all(promises);

      for (const doc of docs) {
        if (doc.exists) {
          const products = doc.data().products || [];
          products.forEach((id) => productSet.add(id));
        }
      }

      return Array.from(productSet);
    } catch (error) {
      console.error('⚠️ Failed to load category trending:', error.message);
      return [];
    }
  }

  async queryProductsByCategories(categories, userProfile) {
    try {
      const avgPrice = userProfile.preferences?.avgPurchasePrice;
      const priceMin = avgPrice ? avgPrice * 0.5 : 0;
      const priceMax = avgPrice ? avgPrice * 2.0 : Number.MAX_SAFE_INTEGER;

      let query = this.db
        .collection('shop_products')
        .where('category', 'in', categories.slice(0, 10));

      if (avgPrice) {
        query = query.where('price', '>=', priceMin).where('price', '<=', priceMax);
      }

      const snapshot = await query
        .orderBy('clickCount', 'desc')
        .limit(CONFIG.MAX_CANDIDATES)
        .get();

      return snapshot.docs.map((doc) => doc.id);
    } catch (error) {
      console.error('⚠️ Query failed, using trending fallback:', error.message);

      const {productIds} = await this.loadTrendingProducts();
      return productIds.slice(0, CONFIG.MAX_CANDIDATES);
    }
  }

  async loadProductDetails(productIds) {
    if (productIds.length === 0) return new Map();

    const productMap = new Map();
    const chunks = this.chunkArray(productIds, 100);

    for (const chunk of chunks) {
      try {
        const shopRefs = chunk.map((id) => this.db.collection('shop_products').doc(id));
        const shopDocs = await this.db.getAll(...shopRefs);

        shopDocs.forEach((doc) => {
          if (doc.exists) {
            const data = doc.data();
            productMap.set(doc.id, {
              id: doc.id,
              category: data.category || null,
              subcategory: data.subcategory || null,
              brand: data.brandModel || null,
              price: data.price || 0,
              clicks: data.clickCount || 0,
              cartCount: data.cartCount || 0,
              favoritesCount: data.favoritesCount || 0,
              gender: data.gender || null,
            });
          }
        });
      } catch (error) {
        console.error('⚠️ Error loading product chunk:', error.message);
      }
    }

    return productMap;
  }

  chunkArray(array, size) {
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
}

// ============================================================================
// FEED SCORER - ✅ UPDATED WITH PROGRESSIVE PERSONALIZATION
// ============================================================================

class FeedScorer {
  constructor(trendingScores, userActivityCount = 0) {
    this.trendingScores = trendingScores || new Map();
    this.userActivityCount = userActivityCount;
    
    // ✅ Calculate dynamic weights based on user engagement
    this.weights = this.calculateDynamicWeights(userActivityCount);
  }

  calculateDynamicWeights(activityCount) {
    const {
      MIN_EVENTS_FOR_PERSONALIZATION,
      FULL_PERSONALIZATION_EVENTS,
      CATEGORY_WEIGHT_MAX,
      BRAND_WEIGHT_MAX,
      TRENDING_WEIGHT_MIN,
    } = PERSONALIZATION_CONFIG;

    // Calculate personalization strength (0 to 1)
    // 0 = new user, 1 = fully engaged user
    const personalizationStrength = Math.min(
      1.0,
      Math.max(
        0,
        (activityCount - MIN_EVENTS_FOR_PERSONALIZATION) /
          (FULL_PERSONALIZATION_EVENTS - MIN_EVENTS_FOR_PERSONALIZATION),
      ),
    );

    // Scale weights based on personalization strength
    const categoryWeight =
      BASE_WEIGHTS.CATEGORY_MATCH +
      (CATEGORY_WEIGHT_MAX - BASE_WEIGHTS.CATEGORY_MATCH) * personalizationStrength;

    const brandWeight =
      BASE_WEIGHTS.BRAND_MATCH +
      (BRAND_WEIGHT_MAX - BASE_WEIGHTS.BRAND_MATCH) * personalizationStrength;

    const trendingWeight =
      BASE_WEIGHTS.TRENDING_SCORE -
      (BASE_WEIGHTS.TRENDING_SCORE - TRENDING_WEIGHT_MIN) * personalizationStrength;

    // Fixed weights
    const priceWeight = BASE_WEIGHTS.PRICE_RANGE_MATCH;
    const recencyWeight = BASE_WEIGHTS.RECENCY_PENALTY;
    const genderWeight = BASE_WEIGHTS.GENDER_MATCH;

    // Normalize to ensure sum = 1.0
    const total = categoryWeight + brandWeight + trendingWeight + priceWeight + recencyWeight + genderWeight;

    return {
      CATEGORY_MATCH: categoryWeight / total,
      BRAND_MATCH: brandWeight / total,
      TRENDING_SCORE: trendingWeight / total,
      PRICE_RANGE_MATCH: priceWeight / total,
      RECENCY_PENALTY: recencyWeight / total,
      GENDER_MATCH: genderWeight / total,
      // Store metadata for debugging
      _personalizationStrength: personalizationStrength,
      _activityCount: activityCount,
    };
  }

  calculateGenderMatch(product, userProfile) {
    const genderScores = userProfile.genderScores || {};
    const productGender = product.gender;
  
    if (!productGender || Object.keys(genderScores).length === 0) {
      return 0.5; // Neutral — don't penalize unknown
    }
  
    // Unisex products always get a good score
    if (productGender === 'Unisex') {
      return 0.8;
    }
  
    const maxScore = Math.max(...Object.values(genderScores), 1);
    return (genderScores[productGender] || 0) / maxScore;
  }

  normalize(value, min, max) {
    if (max === min) return 0.5;
    return Math.max(0, Math.min(1, (value - min) / (max - min)));
  }

  calculateCategoryMatch(product, userProfile) {
    const categoryScores = userProfile.categoryScores || {};
    const productCategory = product.category;
    const productSubcategory = product.subcategory;

    // No category preference data
    if (Object.keys(categoryScores).length === 0) {
      return 0.0;
    }

    const maxScore = Math.max(...Object.values(categoryScores), 1);
    
    // Base category match (0 to 1)
    let categoryMatch = 0.0;
    if (productCategory && categoryScores[productCategory]) {
      categoryMatch = categoryScores[productCategory] / maxScore;
    }

    // Subcategory bonus (adds up to 30% more to the category score)
    let subcategoryBonus = 0.0;
    if (productSubcategory && categoryScores[productSubcategory]) {
      const subcategoryMatch = categoryScores[productSubcategory] / maxScore;
      subcategoryBonus = subcategoryMatch * PERSONALIZATION_CONFIG.SUBCATEGORY_BONUS_RATIO;
    }

    // Combined score (capped at 1.0)
    return Math.min(1.0, categoryMatch + subcategoryBonus);
  }

  calculateBrandMatch(product, userProfile) {
    const brandScores = userProfile.brandScores || {};
    const productBrand = product.brand;

    if (!productBrand || !brandScores[productBrand]) {
      return 0.0;
    }

    const maxScore = Math.max(...Object.values(brandScores), 1);
    return brandScores[productBrand] / maxScore;
  }

  calculatePriceMatch(product, userProfile) {
    const avgPrice = userProfile.preferences?.avgPurchasePrice;

    if (!avgPrice || avgPrice === 0) {
      return 0.5;
    }

    const priceDiff = Math.abs(product.price - avgPrice);
    const priceRatio = priceDiff / avgPrice;

    return Math.max(0, 1 - priceRatio);
  }

  calculateRecencyPenalty(product, userProfile) {
    const recentlyViewed = userProfile.recentlyViewed || [];

    const wasRecentlyViewed = recentlyViewed
      .slice(-50)
      .some((item) => item.productId === product.id);

    return wasRecentlyViewed ? 0.5 : 1.0;
  }

  scoreProduct(product, userProfile) {
    const categoryMatch = this.calculateCategoryMatch(product, userProfile);
    const genderMatch = this.calculateGenderMatch(product, userProfile);
    const brandMatch = this.calculateBrandMatch(product, userProfile);
    const priceMatch = this.calculatePriceMatch(product, userProfile);
    const recencyPenalty = this.calculateRecencyPenalty(product, userProfile);

    const trendingScore = this.trendingScores.get(product.id) || 0;

    // ✅ Use dynamic weights instead of static WEIGHTS
    const score =
      categoryMatch * this.weights.CATEGORY_MATCH +
      genderMatch * this.weights.GENDER_MATCH +
      brandMatch * this.weights.BRAND_MATCH +
      trendingScore * this.weights.TRENDING_SCORE +
      priceMatch * this.weights.PRICE_RANGE_MATCH +
      recencyPenalty * this.weights.RECENCY_PENALTY;

    return {
      score,
      breakdown: {
        category: categoryMatch.toFixed(3),
        gender: genderMatch.toFixed(3),
        brand: brandMatch.toFixed(3),
        trending: trendingScore.toFixed(3),
        price: priceMatch.toFixed(3),
        recency: recencyPenalty.toFixed(3),
      },
    };
  }

  getWeightsInfo() {
    return {
      category: this.weights.CATEGORY_MATCH.toFixed(3),
      gender: this.weights.GENDER_MATCH.toFixed(3),
      brand: this.weights.BRAND_MATCH.toFixed(3),
      trending: this.weights.TRENDING_SCORE.toFixed(3),
      price: this.weights.PRICE_RANGE_MATCH.toFixed(3),
      recency: this.weights.RECENCY_PENALTY.toFixed(3),
      personalizationStrength: this.weights._personalizationStrength.toFixed(3),
    };
  }
}

// ============================================================================
// FEED GENERATOR
// ============================================================================

class PersonalizedFeedGenerator {
  constructor(db) {
    this.db = db;
    this.selector = new CandidateSelector(db);
  }

  shouldUpdateFeed(userProfile, existingFeed) {
    if (!existingFeed) {
      return {shouldUpdate: true, reason: 'no_existing_feed'};
    }

    const feedAge = Date.now() - (existingFeed.lastComputed?.toMillis() || 0);
    const daysSinceFeed = feedAge / (1000 * 60 * 60 * 24);

    if (daysSinceFeed > CONFIG.REFRESH_INTERVAL_DAYS) {
      return {shouldUpdate: true, reason: 'stale_feed'};
    }

    const userActivityCount = userProfile.stats?.totalEvents || 0;
    const feedActivityCount = existingFeed.stats?.userActivityCount || 0;

    if (userActivityCount > feedActivityCount + 5) {
      return {shouldUpdate: true, reason: 'new_activity'};
    }

    return {shouldUpdate: false, reason: 'feed_fresh'};
  }

  async generateFeed(userId, userProfile) {
    const startTime = Date.now();

    try {
      const activityCount = userProfile.stats?.totalEvents || 0;

      if (activityCount < CONFIG.MIN_ACTIVITY_THRESHOLD) {
        return {success: false, reason: 'insufficient_activity'};
      }

      // 1. Load trending scores (shared)
      const {scores} = await this.selector.loadTrendingProducts();

      // 2. Get candidate product IDs (efficient)
      const candidateIds = await this.selector.getCandidatesForUser(userProfile);

      if (candidateIds.length === 0) {
        return {success: false, reason: 'no_candidates'};
      }

      // 3. Load product details in batches
      const products = await this.selector.loadProductDetails(candidateIds);

      if (products.size === 0) {
        return {success: false, reason: 'no_product_data'};
      }

      // 4. Score products - ✅ UPDATED: Pass activityCount for progressive weights
      const scorer = new FeedScorer(scores, activityCount);
      const scoredProducts = [];

      for (const [productId, product] of products.entries()) {
        const {score, breakdown} = scorer.scoreProduct(product, userProfile);
        scoredProducts.push({id: productId, score, breakdown});
      }

      // 5. Sort and take top N
      scoredProducts.sort((a, b) => b.score - a.score);
      const topProducts = scoredProducts.slice(0, CONFIG.FEED_SIZE);

      // 6. Prepare feed data - ✅ UPDATED: Include weights info for debugging
      const weightsInfo = scorer.getWeightsInfo();
      
      const feedData = {
        productIds: topProducts.map((p) => p.id),
        scores: topProducts.map((p) => p.score),
        lastComputed: admin.firestore.FieldValue.serverTimestamp(),
        nextRefreshDue: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + CONFIG.REFRESH_INTERVAL_DAYS * 24 * 60 * 60 * 1000),
        ),
        version: new Date().toISOString().split('T')[0],
        stats: {
          productsScored: products.size,
          computationTimeMs: Date.now() - startTime,
          userActivityCount: activityCount,
          topCategories:
            userProfile.preferences?.topCategories
              ?.slice(0, 3)
              .map((c) => c.category) || [],
          avgScore: parseFloat(
            (
              topProducts.reduce((sum, p) => sum + p.score, 0) / topProducts.length
            ).toFixed(3),
          ),
          // ✅ NEW: Include personalization info
          personalizationStrength: weightsInfo.personalizationStrength,
          appliedWeights: weightsInfo,
        },
        topProductsDebug: topProducts.slice(0, 5).map((p) => ({
          id: p.id,
          score: parseFloat(p.score.toFixed(3)),
          breakdown: p.breakdown,
        })),
      };

      // 7. Write to Firestore with retry
      await retryWithBackoff(
        async () => {
          await this.db
            .collection('user_profiles')
            .doc(userId)
            .collection('personalized_feed')
            .doc('current')
            .set(feedData);
        },
        CONFIG.MAX_RETRIES,
        100,
      );

      return {
        success: true,
        duration: Date.now() - startTime,
        productsCount: topProducts.length,
        avgScore: feedData.stats.avgScore,
        personalizationStrength: weightsInfo.personalizationStrength,
      };
    } catch (error) {
      console.error(`❌ Feed error for ${userId.substring(0, 8)}:`, error.message);
      return {success: false, error: error.message};
    }
  }

  async loadExistingFeeds(userIds) {
    const feedMap = new Map();
    const chunks = this.chunkArray(userIds, 100);

    for (const chunk of chunks) {
      try {
        const refs = chunk.map((userId) =>
          this.db
            .collection('user_profiles')
            .doc(userId)
            .collection('personalized_feed')
            .doc('current'),
        );

        const docs = await this.db.getAll(...refs);

        docs.forEach((doc, idx) => {
          if (doc.exists) {
            feedMap.set(chunk[idx], doc.data());
          }
        });
      } catch (error) {
        console.error('⚠️ Error loading feed batch:', error.message);
      }
    }

    return feedMap;
  }

  async processBatch(users) {
    const results = {
      updated: 0,
      skipped: 0,
      failed: 0,
      reasons: {},
    };

    const userIds = users.map((doc) => doc.id);
    const existingFeeds = await this.loadExistingFeeds(userIds);

    await Promise.all(
      users.map(async (userDoc) => {
        try {
          const userId = userDoc.id;
          const userProfile = userDoc.data();
          const existingFeed = existingFeeds.get(userId) || null;

          const {shouldUpdate, reason} = this.shouldUpdateFeed(
            userProfile,
            existingFeed,
          );

          if (!shouldUpdate) {
            results.skipped++;
            results.reasons[reason] = (results.reasons[reason] || 0) + 1;
            return;
          }

          const result = await this.generateFeed(userId, userProfile);

          if (result.success) {
            results.updated++;
            results.reasons[reason] = (results.reasons[reason] || 0) + 1;
          } else {
            results.skipped++;
            results.reasons[result.reason] = (results.reasons[result.reason] || 0) + 1;
          }
        } catch (error) {
          results.failed++;
          console.error(`❌ Error processing ${userDoc.id}:`, error.message);
        }
      }),
    );

    return results;
  }

  chunkArray(array, size) {
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
}

// ============================================================================
// CLOUD SCHEDULER
// ============================================================================

export const updatePersonalizedFeeds = onSchedule(
  {
    schedule: 'every 48 hours',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '2GiB',
    region: 'europe-west3',
    maxInstances: 5,
  },
  async () => {
    const startTime = Date.now();
    const db = admin.firestore();
    const generator = new PersonalizedFeedGenerator(db);

    try {
      console.log('🚀 Starting personalized feed update...');

      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const totalResults = {
        updated: 0,
        skipped: 0,
        failed: 0,
        reasons: {},
      };

      let lastDoc = null;
      let totalFetched = 0;
      const PAGE_SIZE = 2000;
      const MAX_USERS = 30000;

      while (totalFetched < MAX_USERS) {
        let query = db
          .collection('user_profiles')
          .where('lastActivityAt', '>', thirtyDaysAgo)
          .orderBy('lastActivityAt')
          .limit(PAGE_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const usersSnapshot = await query.get();

        if (usersSnapshot.empty) {
          if (totalFetched === 0) {
            console.log('✅ No active users');
          }
          break;
        }

        totalFetched += usersSnapshot.size;
        lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];

        console.log(`📊 Page loaded: ${usersSnapshot.size} users (${totalFetched} total)`);

        const batches = generator.chunkArray(usersSnapshot.docs, CONFIG.BATCH_SIZE);

        for (const [index, batch] of batches.entries()) {
          if (index % 10 === 0) {
            console.log(`🔄 Batch ${index + 1}/${batches.length}...`);
          }

          const batchResults = await generator.processBatch(batch);

          totalResults.updated += batchResults.updated;
          totalResults.skipped += batchResults.skipped;
          totalResults.failed += batchResults.failed;

          for (const [reason, count] of Object.entries(batchResults.reasons)) {
            totalResults.reasons[reason] = (totalResults.reasons[reason] || 0) + count;
          }

          const elapsed = Date.now() - startTime;
          if (elapsed > 480000) {
            console.warn(`⏰ Approaching timeout after ${totalFetched} users, stopping`);
            break;
          }
        }

        // Timeout check at page level too
        const elapsed = Date.now() - startTime;
        if (elapsed > 480000) break;

        // End of collection
        if (usersSnapshot.size < PAGE_SIZE) break;
      }

      const duration = Date.now() - startTime;

      console.log(
        JSON.stringify({
          level: 'INFO',
          event: 'feeds_updated',
          totalUsers: totalFetched,
          updated: totalResults.updated,
          skipped: totalResults.skipped,
          failed: totalResults.failed,
          reasons: totalResults.reasons,
          duration,
        }),
      );

      if (totalFetched > 0 && totalResults.failed > totalFetched * 0.1) {
        console.error(
          JSON.stringify({
            level: 'ERROR',
            event: 'high_failure_rate',
            failureRate: ((totalResults.failed / totalFetched) * 100).toFixed(2) + '%',
            alert: true,
          }),
        );
      }

      return {
        success: true,
        totalUsers: totalFetched,
        updated: totalResults.updated,
        skipped: totalResults.skipped,
        failed: totalResults.failed,
        reasons: totalResults.reasons,
        duration,
      };
    } catch (error) {
      const duration = Date.now() - startTime;

      console.error(
        JSON.stringify({
          level: 'ERROR',
          event: 'feed_update_failed',
          error: error.message,
          stack: error.stack,
          duration,
          alert: true,
        }),
      );

      return {
        success: false,
        error: error.message,
        duration,
      };
    }
  },
);

export const cleanupOldFeeds = onSchedule(
  {
    schedule: 'every day 05:00',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    memory: '512MiB',
    region: 'europe-west3',
  },
  async () => {
    const db = admin.firestore();

    try {
      console.log('🧹 Cleaning up old feeds...');

      let totalDeleted = 0;
      const profilesSnapshot = await db.collection('user_profiles').limit(1000).get();

      const batchSize = 10;
      const chunks = [];

      for (let i = 0; i < profilesSnapshot.docs.length; i += batchSize) {
        chunks.push(profilesSnapshot.docs.slice(i, i + batchSize));
      }

      for (const chunk of chunks) {
        await Promise.all(
          chunk.map(async (profileDoc) => {
            try {
              const feedsSnapshot = await profileDoc.ref
                .collection('personalized_feed')
                .where(admin.firestore.FieldPath.documentId(), '!=', 'current')
                .limit(100)
                .get();

              if (!feedsSnapshot.empty) {
                const batch = db.batch();
                feedsSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
                totalDeleted += feedsSnapshot.size;
              }
            } catch (error) {
              console.error(`⚠️ Error cleaning ${profileDoc.id}:`, error.message);
            }
          }),
        );
      }

      console.log(`✅ Cleaned up ${totalDeleted} old feeds`);
      return {success: true, deleted: totalDeleted};
    } catch (error) {
      console.error('❌ Cleanup failed:', error.message);
      return {success: false, error: error.message};
    }
  },
);
