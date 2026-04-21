import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {
  bufferCartFavEvents,
  drainCartFavEvents,
  deleteDrainKeys,
  dedup,
  getRedisClient,
  checkRateLimit,
} from '../shared/redis.js';

// ============================================================================
// CLIENT-FACING: Buffer cart/favorite events in Redis (no Firestore writes)
// ============================================================================

const VALID_TYPES = new Set(['cart', 'favorite']);
const VALID_COLLECTIONS = new Set(['products', 'shop_products']);

export const trackCartFavEvent = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 10,
    memory: '256MiB',
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Authentication required.');

    const allowed = await checkRateLimit(`rl:cartfav:${uid}`, 60, 60);
    if (!allowed) {
      throw new HttpsError('resource-exhausted', 'Rate limit exceeded. Try again shortly.');
    }

    const raw = request.data;
    const events = Array.isArray(raw?.events) ? raw.events : [raw];

    const valid = [];
    for (const ev of events) {
      const {productId, collection, shopId, type, delta} = ev || {};

      if (!productId || typeof productId !== 'string') continue;
      if (!VALID_TYPES.has(type)) continue;
      if (!VALID_COLLECTIONS.has(collection)) continue;
      if (delta !== 1 && delta !== -1) continue;

      valid.push({
        productId,
        collection,
        shopId: shopId || null,
        type,
        delta,
      });
    }

    if (valid.length === 0) {
      throw new HttpsError('invalid-argument', 'At least one valid event is required.');
    }

    await bufferCartFavEvents(valid);
    return {success: true, buffered: valid.length};
  },
);

// ============================================================================
// SCHEDULED FLUSH: Drain Redis → Firestore (every minute)
// ============================================================================

export const flushCartFavEvents = onSchedule(
  {
    schedule: '* * * * *',
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 120,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    const locked = await dedup('flush_cartfav_lock', 55);
    if (!locked) {
      console.log('[FlushCartFav] Another instance running, skipping');
      return;
    }

    const client = getRedisClient();
    await recoverOrphanedKeys(client, 'cart:counts');
    await recoverOrphanedKeys(client, 'fav:counts');
    await recoverOrphanedKeys(client, 'shop:cart_adds');
    await recoverOrphanedKeys(client, 'shop:fav_adds');

    const {cart, fav, shopCart, shopFav, tempKeys} = await drainCartFavEvents();

    const cartEntries = Object.entries(cart);
    const favEntries = Object.entries(fav);
    const shopCartEntries = Object.entries(shopCart);
    const shopFavEntries = Object.entries(shopFav);

    const totalEvents =
      cartEntries.length + favEntries.length + shopCartEntries.length + shopFavEntries.length;

    if (totalEvents === 0) {
      await deleteDrainKeys(tempKeys);
      return;
    }

    console.log(
      `[FlushCartFav] Processing cart:${cartEntries.length} fav:${favEntries.length} shopCart:${shopCartEntries.length} shopFav:${shopFavEntries.length}`,
    );

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // ── Merge cart + fav deltas per product (one write per product) ─────────
    // Map: "collection:productId" → { cart: int, fav: int }
    const productDeltas = new Map();

    for (const [field, val] of cartEntries) {
      const delta = parseInt(val, 10);
      if (delta === 0) continue;
      const entry = productDeltas.get(field) || {cart: 0, fav: 0};
      entry.cart += delta;
      productDeltas.set(field, entry);
    }

    for (const [field, val] of favEntries) {
      const delta = parseInt(val, 10);
      if (delta === 0) continue;
      const entry = productDeltas.get(field) || {cart: 0, fav: 0};
      entry.fav += delta;
      productDeltas.set(field, entry);
    }

    // ── Verify products exist before writing (avoid zombie docs) ────────────
    const productRefs = [];
    for (const field of productDeltas.keys()) {
      const sepIndex = field.indexOf(':');
      const collection = field.substring(0, sepIndex);
      const productId = field.substring(sepIndex + 1);
      productRefs.push({field, collection, productId});
    }

    const existenceChecks = await Promise.all(
      productRefs.map((p) =>
        db.collection(p.collection).doc(p.productId).get().catch(() => null),
      ),
    );

    const liveProducts = [];
    let dropped = 0;
    existenceChecks.forEach((snap, i) => {
      if (snap?.exists) {
        liveProducts.push(productRefs[i]);
      } else {
        dropped++;
      }
    });

    // ── Batch writer ────────────────────────────────────────────────────────
    const BATCH_LIMIT = 450;
    let batch = db.batch();
    let ops = 0;

    const flushBatch = async () => {
      if (ops > 0) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    };

    // ── Pass 1: Product-level cart + fav counts ─────────────────────────────
    for (const {field, collection, productId} of liveProducts) {
      const deltas = productDeltas.get(field);
      const update = {metricsUpdatedAt: now};

      if (deltas.cart !== 0) {
        update.cartCount = admin.firestore.FieldValue.increment(deltas.cart);
      }
      if (deltas.fav !== 0) {
        update.favoritesCount = admin.firestore.FieldValue.increment(deltas.fav);
      }

      // Skip if both deltas netted to zero
      if (Object.keys(update).length === 1) continue;

      if (ops >= BATCH_LIMIT) await flushBatch();
      batch.update(db.collection(collection).doc(productId), update);
      ops++;
    }
    await flushBatch();

    // ── Pass 2: Shop-level aggregates (adds only) ───────────────────────────
    // Merge cart + fav adds per shop
    const shopDeltas = new Map();

    for (const [shopId, val] of shopCartEntries) {
      const delta = parseInt(val, 10);
      if (delta <= 0) continue;
      const entry = shopDeltas.get(shopId) || {cart: 0, fav: 0};
      entry.cart += delta;
      shopDeltas.set(shopId, entry);
    }

    for (const [shopId, val] of shopFavEntries) {
      const delta = parseInt(val, 10);
      if (delta <= 0) continue;
      const entry = shopDeltas.get(shopId) || {cart: 0, fav: 0};
      entry.fav += delta;
      shopDeltas.set(shopId, entry);
    }

    for (const [shopId, deltas] of shopDeltas) {
      const update = {'metrics.lastUpdated': now};

      if (deltas.cart > 0) {
        update['metrics.totalCartAdditions'] =
          admin.firestore.FieldValue.increment(deltas.cart);
      }
      if (deltas.fav > 0) {
        update['metrics.totalFavoriteAdditions'] =
          admin.firestore.FieldValue.increment(deltas.fav);
      }

      if (Object.keys(update).length === 1) continue;

      if (ops >= BATCH_LIMIT) await flushBatch();
      batch.update(db.collection('shops').doc(shopId), update);
      ops++;
    }
    await flushBatch();

    // ── Cleanup only after all writes succeed ───────────────────────────────
    await deleteDrainKeys(tempKeys);

    console.log(JSON.stringify({
      event: 'flush_cartfav_done',
      products: liveProducts.length,
      shops: shopDeltas.size,
      dropped,
    }));
  },
);

// ============================================================================
// HELPER: Recover orphaned drain keys from previous crashed flushes
// ============================================================================

async function recoverOrphanedKeys(client, prefix) {
  const pattern = `${prefix}:drain:*`;
  const orphanedKeys = [];
  let cursor = '0';
  do {
    const [nextCursor, keys] = await client.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
    cursor = nextCursor;
    orphanedKeys.push(...keys);
  } while (cursor !== '0');

  if (orphanedKeys.length === 0) return;

  console.warn(`[FlushCartFav] Recovering ${orphanedKeys.length} orphaned keys matching ${pattern}`);

  for (const key of orphanedKeys) {
    const data = await client.hgetall(key);
    if (Object.keys(data).length > 0) {
      const pipeline = client.pipeline();
      for (const [field, val] of Object.entries(data)) {
        pipeline.hincrby(prefix, field, parseInt(val, 10));
      }
      await pipeline.exec();
    }
    await client.del(key);
  }
}
