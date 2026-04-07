// functions/13-personalized-feed/index.js
// Production-grade personalized feed with trending-based candidates and batch operations
// ✅ UPDATED: Progressive personalization + subcategory support + Cloud Tasks batching

import {onSchedule} from 'firebase-functions/v2/scheduler';
import {onRequest} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {CloudTasksClient} from '@google-cloud/tasks';

const PROJECT = 'emlak-mobile-app';
const LOCATION = 'europe-west3';
const QUEUE = 'personalized-feeds';
const tasksClient = new CloudTasksClient();

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  FEED_SIZE: 150,
  BATCH_SIZE: 50,
  MAX_CANDIDATES: 300,
  REFRESH_INTERVAL_DAYS: 2,
  MIN_ACTIVITY_THRESHOLD: 20,
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
      return {
        candidateIds: productIds.slice(0, CONFIG.MAX_CANDIDATES),
        featuresMap: new Map(), // no features for trending fallback
      };
    }
  
    const {productIds, featuresMap} = await this.loadCategoryTrending(topCategories);
  
    if (productIds.length > 0) {
      return {
        candidateIds: productIds.slice(0, CONFIG.MAX_CANDIDATES),
        featuresMap,
      };
    }
  
    // Fallback: no features available from query
    const fallbackIds = await this.queryProductsByCategories(topCategories);
    return {
      candidateIds: fallbackIds,
      featuresMap: new Map(),
    };
  }

  async loadCategoryTrending(categories) {
    try {
      const productSet = new Set();
      const featuresMap = new Map(); // ✅ NEW
  
      const promises = categories.map((category) =>
        this.db.collection('trending_by_category')
          .doc(category.replace(/[./]/g, '_'))
          .get(),
      );
      const docs = await Promise.all(promises);
  
      for (const doc of docs) {
        if (doc.exists) {
          const data = doc.data();
          const products = data.products || [];
          products.forEach((id) => productSet.add(id));
  
          // ✅ NEW: extract features if available
          const features = data.features || [];
          for (const feature of features) {
            if (!featuresMap.has(feature.id)) {
              featuresMap.set(feature.id, feature);
            }
          }
        }
      }
  
      return {
        productIds: Array.from(productSet),
        featuresMap,
      };
    } catch (error) {
      console.error('⚠️ Failed to load category trending:', error.message);
      return {productIds: [], featuresMap: new Map()};
    }
  }

  async queryProductsByCategories(categories) {
    // Fallback query — keep it simple, no orderBy, no price filter
    // Price scoring happens in memory via FeedScorer anyway
    try {
      const snapshot = await this.db
        .collection('shop_products')
        .where('category', 'in', categories.slice(0, 10))
        .limit(CONFIG.MAX_CANDIDATES)
        .get();
  
      return snapshot.docs.map((doc) => doc.id);
    } catch (error) {
      console.error('⚠️ Category query failed, using trending fallback:', error);
      const {productIds} = await this.loadTrendingProducts();
      return productIds.slice(0, CONFIG.MAX_CANDIDATES);
    }
  }

  async loadProductDetails(productIds) {
    if (productIds.length === 0) return new Map();
  
    const productMap = new Map();
    const chunks = this.chunkArray(productIds, 100);
  
    // Parallel fetching — 10x faster for 1000 candidates
    await Promise.all(chunks.map(async (chunk) => {
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
        console.error('⚠️ Error loading product chunk:', error);
      }
    }));
  
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

    if (userActivityCount > feedActivityCount + 30) {
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

      const {candidateIds, featuresMap} = await this.selector.getCandidatesForUser(userProfile);

if (candidateIds.length === 0) {
  return {success: false, reason: 'no_candidates'};
}

// ✅ Use embedded features when available, fall back to Firestore reads
let products;
if (featuresMap.size > 0) {
  // Build product map directly from features — zero extra reads
  products = new Map();
  for (const id of candidateIds) {
    const feature = featuresMap.get(id);
    if (feature) {
      products.set(id, {
        id,
        category: feature.category,
        subcategory: feature.subcategory,
        brand: feature.brand,
        price: feature.price,
        gender: feature.gender,
        clicks: 0,        // not needed for scoring
        cartCount: 0,     // not needed for scoring
        favoritesCount: 0, // not needed for scoring
      });
    }
  }
  console.log(`⚡ Using embedded features for ${products.size} products (0 extra reads)`);
} else {
  // Fallback for users with no category preferences (trending-based candidates)
  products = await this.selector.loadProductDetails(candidateIds);
}

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
            .update({ feed: feedData });
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

  async loadExistingFeeds(users) {
    const feedMap = new Map();
  
    for (const userDoc of users) {
      const feed = userDoc.data().feed;
      if (feed) {
        feedMap.set(userDoc.id, feed);
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

    const existingFeeds = await this.loadExistingFeeds(users);

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
// CLOUD SCHEDULER (DISPATCHER) — Creates Cloud Tasks for batches of users
// ============================================================================

export const updatePersonalizedFeeds = onSchedule(
  {
    schedule: 'every 48 hours',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    memory: '512MiB',
    region: LOCATION,
    maxInstances: 1,
  },
  async () => {
    const startTime = Date.now();
    const db = admin.firestore();

    try {
      console.log('Starting personalized feed dispatch...');

      const fiveDaysAgo = new Date();
      fiveDaysAgo.setDate(fiveDaysAgo.getDate() - 5);

      const parent = tasksClient.queuePath(PROJECT, LOCATION, QUEUE);
      let lastDoc = null;
      let totalFetched = 0;
      let tasksCreated = 0;
      const PAGE_SIZE = 2000;
      const BATCH_SIZE = 50;
      const MAX_USERS = 50000;

      while (totalFetched < MAX_USERS) {
        let query = db
          .collection('user_profiles')
          .where('lastActivityAt', '>', fiveDaysAgo)
          .orderBy('lastActivityAt')
          .limit(PAGE_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const usersSnapshot = await query.get();

        if (usersSnapshot.empty) {
          if (totalFetched === 0) {
            console.log('No active users found');
          }
          break;
        }

        totalFetched += usersSnapshot.size;
        lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];

        // Collect user IDs and chunk into batches
        const userIds = usersSnapshot.docs.map((doc) => doc.id);
        const chunks = [];
        for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
          chunks.push(userIds.slice(i, i + BATCH_SIZE));
        }

        // Create Cloud Tasks for each batch
        const taskPromises = chunks.map(async (chunk) => {
          const task = {
            httpRequest: {
              httpMethod: 'POST',
              url: `https://${LOCATION}-${PROJECT}.cloudfunctions.net/processPersonalizedFeedBatch`,
              body: Buffer.from(JSON.stringify({userIds: chunk})).toString('base64'),
              headers: {'Content-Type': 'application/json'},
              oidcToken: {
                serviceAccountEmail: `${PROJECT}@appspot.gserviceaccount.com`,
              },
            },
          };

          try {
            await tasksClient.createTask({parent, task});
            return true;
          } catch (error) {
            console.error('Failed to create task:', error.message);
            return false;
          }
        });

        const results = await Promise.all(taskPromises);
        tasksCreated += results.filter(Boolean).length;

        console.log(`Page: ${usersSnapshot.size} users, ${results.filter(Boolean).length} tasks created (${totalFetched} total users)`);

        if (usersSnapshot.size < PAGE_SIZE) break;
      }

      const duration = Date.now() - startTime;

      console.log(
        JSON.stringify({
          level: 'INFO',
          event: 'feed_dispatch_complete',
          totalUsers: totalFetched,
          tasksCreated,
          duration,
        }),
      );

      return {success: true, totalUsers: totalFetched, tasksCreated, duration};
    } catch (error) {
      const duration = Date.now() - startTime;

      console.error(
        JSON.stringify({
          level: 'ERROR',
          event: 'feed_dispatch_failed',
          error: error.message,
          stack: error.stack,
          duration,
          alert: true,
        }),
      );

      return {success: false, error: error.message, duration};
    }
  },
);

// ============================================================================
// CLOUD TASK HANDLER — Processes a batch of user IDs
// ============================================================================

export const processPersonalizedFeedBatch = onRequest(
  {
    region: LOCATION,
    memory: '1GiB',
    timeoutSeconds: 540,
    maxInstances: 20,
  },
  async (req, res) => {
    const startTime = Date.now();
    const db = admin.firestore();
    const generator = new PersonalizedFeedGenerator(db);

    try {
      const {userIds} = req.body;

      if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
        res.status(400).json({error: 'Missing or invalid userIds'});
        return;
      }

      // Load user profiles for this batch
      const refs = userIds.map((id) => db.collection('user_profiles').doc(id));
      const docs = await db.getAll(...refs);

      const users = docs.filter((doc) => doc.exists);

      if (users.length === 0) {
        res.status(200).json({success: true, updated: 0, skipped: 0, failed: 0});
        return;
      }

      const results = await generator.processBatch(users);
      const duration = Date.now() - startTime;

      console.log(
        JSON.stringify({
          level: 'INFO',
          event: 'feed_batch_complete',
          batchSize: userIds.length,
          updated: results.updated,
          skipped: results.skipped,
          failed: results.failed,
          reasons: results.reasons,
          duration,
        }),
      );

      if (results.failed > users.length * 0.5) {
        console.error(
          JSON.stringify({
            level: 'ERROR',
            event: 'batch_high_failure_rate',
            failureRate: ((results.failed / users.length) * 100).toFixed(2) + '%',
            alert: true,
          }),
        );
      }

      res.status(200).json({success: true, ...results, duration});
    } catch (error) {
      console.error('Batch processing failed:', error.message);
      res.status(500).json({error: error.message});
    }
  },
);

