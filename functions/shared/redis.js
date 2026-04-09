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
        if (times > 3) return null; // Stop retrying after 3 attempts
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

// Lua script: atomic INCR + EXPIRE in a single Redis call.
// Eliminates the race condition where a crash between INCR and EXPIRE
// could leave a key without a TTL, permanently rate-limiting a user.
const RATE_LIMIT_SCRIPT = `
  local current = redis.call('INCR', KEYS[1])
  if current == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  return current
`;

/**
 * Check rate limit using an atomic Lua script (INCR + EXPIRE).
 * Falls back to allowing the request if Redis is unavailable.
 *
 * @param {string} key - Unique rate limit key (e.g. "validation_rate:{userId}")
 * @param {number} maxAttempts - Max allowed requests in the window
 * @param {number} windowSeconds - Time window in seconds
 * @return {Promise<boolean>} true if within limit, false if exceeded
 */
// In-memory fallback when Redis is unavailable.
// Not shared across instances, but still prevents a single instance
// from processing unlimited requests during a Redis outage.
const localRateLimits = new Map();
const LOCAL_CLEANUP_INTERVAL = 60000;
let lastCleanup = Date.now();

function localRateLimit(key, maxAttempts, windowSeconds) {
  const now = Date.now();

  // Periodic cleanup of expired entries to prevent memory leak
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

export async function checkRateLimit(key, maxAttempts, windowSeconds, { failOpen = true } = {}) {
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

/**
 * Get a value from Redis cache.
 * @param {string} key
 * @return {Promise<any|null>} Parsed JSON value or null
 */
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

/**
 * Set a value in Redis cache with TTL.
 * @param {string} key
 * @param {any} value - Will be JSON.stringify'd
 * @param {number} ttlSeconds - Time to live in seconds
 */
export async function cacheSet(key, value, ttlSeconds) {
  try {
    const client = getRedisClient();
    await client.setex(key, ttlSeconds, JSON.stringify(value));
  } catch (error) {
    console.warn('Redis cache set failed:', error.message);
  }
}

/**
 * Delete a cache key (for invalidation).
 * @param {string} key
 */
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

/**
 * Atomic deduplication check using Redis SET NX (set if not exists).
 * @param {string} key - Dedup key
 * @param {number} windowSeconds - Dedup window in seconds
 * @return {Promise<boolean>} true if this is the first call (should process), false if duplicate
 */
export async function dedup(key, windowSeconds) {
  try {
    const client = getRedisClient();
    // SET key "1" EX windowSeconds NX — only sets if key doesn't exist
    const result = await client.set(key, '1', 'EX', windowSeconds, 'NX');
    return result === 'OK'; // "OK" = first call, null = duplicate
  } catch (error) {
    // Redis down — allow processing (fail open)
    console.warn('Redis dedup check failed, allowing processing:', error.message);
    return true;
  }
}

export { getRedisClient };
