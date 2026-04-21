// functions/shared/redis.js
// Shared Redis client and helpers for rate limiting, caching, and deduplication.

import Redis from 'ioredis';

// Connect to Memorystore Redis instance via VPC
const REDIS_HOST = process.env.REDIS_HOST || '10.250.147.43';
const REDIS_PORT = parseInt(process.env.REDIS_PORT || '6379', 10);

let redis = null;

function getRedisClient() {
  if (!redis) {
    redis = new Redis({
      host: REDIS_HOST,
      port: REDIS_PORT,
      maxRetriesPerRequest: 2,
      connectTimeout: 3000,
      commandTimeout: 2000,
      enableOfflineQueue: true,
      retryStrategy(times) {
        if (times > 3) return null;
        return Math.min(times * 200, 1000);
      },
    });

    redis.on('error', (err) => {
      console.error('Redis connection error:', err.message);
    });
  }

  return redis;
}

// ============================================================================
// RATE LIMITING
// ============================================================================

const RATE_LIMIT_SCRIPT = `
  local current = redis.call('INCR', KEYS[1])
  if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  return current
`;

const localRateLimits = new Map();
const LOCAL_CLEANUP_INTERVAL = 60000;
let lastCleanup = Date.now();

function localRateLimit(key, maxAttempts, windowSeconds) {
  const now = Date.now();

  if (now - lastCleanup > LOCAL_CLEANUP_INTERVAL) {
    for (const [k, v] of localRateLimits) {
      if (now > v.expiresAt) localRateLimits.delete(k);
    }
    lastCleanup = now;
  }

  const entry = localRateLimits.get(key);
  if (!entry || now > entry.expiresAt) {
    localRateLimits.set(key, {count: 1, expiresAt: now + windowSeconds * 1000});
    return true;
  }

  entry.count += 1;
  return entry.count <= maxAttempts;
}

export async function checkRateLimit(key, maxAttempts, windowSeconds, {failOpen = true} = {}) {
  try {
    const client = getRedisClient();
    const current = await client.eval(RATE_LIMIT_SCRIPT, 1, key, windowSeconds);
    return current <= maxAttempts;
  } catch (error) {
    console.warn('Redis rate limit failed, using in-memory fallback:', error.message);
    try {
      return localRateLimit(key, maxAttempts, windowSeconds);
    } catch (localError) {
      console.error('Local rate limit also failed:', localError.message);
      return failOpen;
    }
  }
}

// ============================================================================
// CACHING
// ============================================================================

export async function cacheGet(key) {
  try {
    const client = getRedisClient();
    const value = await client.get(key);
    return value ? JSON.parse(value) : null;
  } catch (error) {
    console.warn('Redis cache get failed:', error.message);
    return null;
  }
}

export async function cacheSet(key, value, ttlSeconds) {
  try {
    const client = getRedisClient();
    await client.setex(key, ttlSeconds, JSON.stringify(value));
  } catch (error) {
    console.warn('Redis cache set failed:', error.message);
  }
}

export async function cacheDel(key) {
  try {
    const client = getRedisClient();
    await client.del(key);
  } catch (error) {
    console.warn('Redis cache del failed:', error.message);
  }
}

// ============================================================================
// DEDUPLICATION
// ============================================================================

export async function dedup(key, windowSeconds) {
  try {
    const client = getRedisClient();
    const result = await client.set(key, '1', 'EX', windowSeconds, 'NX');
    return result === 'OK';
  } catch (error) {
    console.warn('Redis dedup check failed, allowing processing:', error.message);
    return true;
  }
}

// ============================================================================
// IMPRESSION BUFFERING
// ============================================================================

const IMP_COUNTS_KEY = 'imp:counts';
const IMP_DEMO_KEY = 'imp:demo';

export async function bufferImpressions(products, gender, ageGroup) {
  const client = getRedisClient();
  const pipeline = client.pipeline();

  for (const {productId, collection, count} of products) {
    const field = `${collection}:${productId}`;
    pipeline.hincrby(IMP_COUNTS_KEY, field, count);
  }

  if (gender || ageGroup) {
    const g = (gender || 'unknown').toLowerCase();
    const a = ageGroup || 'unknown';
    for (const {productId, count} of products) {
      pipeline.hincrby(IMP_DEMO_KEY, `${productId}:${g}:${a}`, count);
    }
  }

  await pipeline.exec();
}

export async function drainImpressions() {
  const client = getRedisClient();
  const ts = Date.now();
  const tempCounts = `${IMP_COUNTS_KEY}:drain:${ts}`;
  const tempDemo = `${IMP_DEMO_KEY}:drain:${ts}`;

  let counts = {};
  let demo = {};

  try {
    await client.rename(IMP_COUNTS_KEY, tempCounts);
    counts = await client.hgetall(tempCounts);
  } catch (e) {
    if (!e.message.includes('no such key')) throw e;
  }

  try {
    await client.rename(IMP_DEMO_KEY, tempDemo);
    demo = await client.hgetall(tempDemo);
  } catch (e) {
    if (!e.message.includes('no such key')) throw e;
  }

  return {counts, demo, tempKeys: [tempCounts, tempDemo]};
}

// ============================================================================
// CLICK BUFFERING
// ============================================================================

const CLICK_COUNTS_KEY = 'click:counts';
const CLICK_SHOPS_KEY = 'click:shops';

export async function bufferClicks(clicks) {
  const client = getRedisClient();
  const pipeline = client.pipeline();

  for (const {productId, collection, shopId, isShopClick} of clicks) {
    // Product-level counts (skip for pure shop clicks)
    if (!isShopClick) {
      pipeline.hincrby(CLICK_COUNTS_KEY, `${collection}:${productId}`, 1);
    }

    // Shop-level counts
    if (shopId) {
      pipeline.hincrby(CLICK_SHOPS_KEY, shopId, 1);
    }
  }

  await pipeline.exec();
}

/**
 * Atomically grab all buffered clicks and clear the buffer.
 * Same RENAME pattern as drainImpressions.
 */
export async function drainClicks() {
  const client = getRedisClient();
  const ts = Date.now();
  const tempCounts = `${CLICK_COUNTS_KEY}:drain:${ts}`;
  const tempShops = `${CLICK_SHOPS_KEY}:drain:${ts}`;

  let counts = {};
  let shops = {};

  try {
    await client.rename(CLICK_COUNTS_KEY, tempCounts);
    counts = await client.hgetall(tempCounts);
  } catch (e) {
    if (!e.message.includes('no such key')) throw e;
  }

  try {
    await client.rename(CLICK_SHOPS_KEY, tempShops);
    shops = await client.hgetall(tempShops);
  } catch (e) {
    if (!e.message.includes('no such key')) throw e;
  }

  return {counts, shops, tempKeys: [tempCounts, tempShops]};
}

// ============================================================================
// CART & FAVORITE EVENT BUFFERING
// ============================================================================

const CART_COUNTS_KEY = 'cart:counts';         // hash: "collection:productId" → net delta
const FAV_COUNTS_KEY = 'fav:counts';           // hash: "collection:productId" → net delta
const SHOP_CART_ADDS_KEY = 'shop:cart_adds';   // hash: shopId → count (adds only)
const SHOP_FAV_ADDS_KEY = 'shop:fav_adds';     // hash: shopId → count (adds only)

export async function bufferCartFavEvents(events) {
  const client = getRedisClient();
  const pipeline = client.pipeline();

  for (const {productId, collection, shopId, type, delta} of events) {
    const field = `${collection}:${productId}`;

    if (type === 'cart') {
      pipeline.hincrby(CART_COUNTS_KEY, field, delta);
      // Shop-level tracks ADDS ONLY (mirrors current Firestore behavior)
      if (shopId && delta > 0) {
        pipeline.hincrby(SHOP_CART_ADDS_KEY, shopId, delta);
      }
    } else if (type === 'favorite') {
      pipeline.hincrby(FAV_COUNTS_KEY, field, delta);
      if (shopId && delta > 0) {
        pipeline.hincrby(SHOP_FAV_ADDS_KEY, shopId, delta);
      }
    }
  }

  await pipeline.exec();
}

/**
 * Atomically grab all buffered cart/fav events and clear the buffers.
 */
export async function drainCartFavEvents() {
  const client = getRedisClient();
  const ts = Date.now();
  const tempCart = `${CART_COUNTS_KEY}:drain:${ts}`;
  const tempFav = `${FAV_COUNTS_KEY}:drain:${ts}`;
  const tempShopCart = `${SHOP_CART_ADDS_KEY}:drain:${ts}`;
  const tempShopFav = `${SHOP_FAV_ADDS_KEY}:drain:${ts}`;

  let cart = {};
  let fav = {};
  let shopCart = {};
  let shopFav = {};

  const renameAndRead = async (src, dst) => {
    try {
      await client.rename(src, dst);
      return await client.hgetall(dst);
    } catch (e) {
      if (!e.message.includes('no such key')) throw e;
      return {};
    }
  };

  cart = await renameAndRead(CART_COUNTS_KEY, tempCart);
  fav = await renameAndRead(FAV_COUNTS_KEY, tempFav);
  shopCart = await renameAndRead(SHOP_CART_ADDS_KEY, tempShopCart);
  shopFav = await renameAndRead(SHOP_FAV_ADDS_KEY, tempShopFav);

  return {
    cart,
    fav,
    shopCart,
    shopFav,
    tempKeys: [tempCart, tempFav, tempShopCart, tempShopFav],
  };
}

// ============================================================================
// SHARED: Delete drain temp keys after successful Firestore flush
// ============================================================================

export async function deleteDrainKeys(keys) {
  const client = getRedisClient();
  const existing = keys.filter(Boolean);
  if (existing.length > 0) await client.del(...existing);
}

export {getRedisClient};
