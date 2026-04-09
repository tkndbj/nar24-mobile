import {onCall} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {bufferClicks, drainClicks, deleteDrainKeys, dedup, getRedisClient} from '../shared/redis.js';

// ============================================================================
// CLIENT-FACING: Buffer clicks in Redis (no Firestore writes)
// Accepts a single click OR an array of clicks for batch support.
// ============================================================================

export const trackProductClick = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 10,
    memory: '256MiB',
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const raw = request.data;

    // Support both single click and batch: { clicks: [...] }
    const clicks = Array.isArray(raw.clicks) ? raw.clicks : [raw];

    const valid = [];
    for (const click of clicks) {
      const {productId, collection, shopId} = click;
      if (!productId || typeof productId !== 'string') continue;
    
      const isShopClick = collection === 'shops';
    
      valid.push({
        productId,
        collection: isShopClick ? 'shops' : ['products', 'shop_products'].includes(collection) ? collection : 'unknown',
        shopId: shopId || null,
        isShopClick,
      });
    }

    if (valid.length === 0) {
      throw new Error('At least one valid click is required.');
    }

    await bufferClicks(valid);
    return {success: true, buffered: valid.length};
  },
);

// ============================================================================
// SCHEDULED FLUSH: Drain Redis → Firestore (every minute)
// ============================================================================

export const flushClicks = onSchedule(
  {
    schedule: '* * * * *',
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 120,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    const locked = await dedup('flush_clicks_lock', 55);
    if (!locked) {
      console.log('[FlushClicks] Another instance running, skipping');
      return;
    }

    const client = getRedisClient();
    await recoverOrphanedKeys(client, 'click:counts');
    await recoverOrphanedKeys(client, 'click:shops');

    const {counts, shops, tempKeys} = await drainClicks();

    const countEntries = Object.entries(counts);
    if (countEntries.length === 0 && Object.keys(shops).length === 0) {
      await deleteDrainKeys(tempKeys);
      return;
    }

    console.log(`[FlushClicks] Processing ${countEntries.length} products, ${Object.keys(shops).length} shops`);

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // ── Parse entries and separate known from unknown ─────────────────────────
    const unknownIds = [];
    const knownProducts = [];

    for (const [field, val] of countEntries) {
      const sepIndex = field.indexOf(':');
      const collection = field.substring(0, sepIndex);
      const productId = field.substring(sepIndex + 1);
      const count = parseInt(val, 10);
      if (count <= 0) continue;

      if (collection === 'unknown') {
        unknownIds.push({productId, count});
      } else {
        knownProducts.push({collection, productId, count});
      }
    }

    // ── Resolve unknown collections ──────────────────────────────────────────
    if (unknownIds.length > 0) {
      const resolved = await Promise.all(
        unknownIds.map(async ({productId, count}) => {
          const [pSnap, sSnap] = await Promise.all([
            db.collection('products').doc(productId).get().catch(() => null),
            db.collection('shop_products').doc(productId).get().catch(() => null),
          ]);
          if (sSnap?.exists) return {collection: 'shop_products', productId, count};
          if (pSnap?.exists) return {collection: 'products', productId, count};
          console.warn(`[FlushClicks] Dropping clicks for unresolvable product: ${productId}`);
          return null;
        }),
      );
      knownProducts.push(...resolved.filter(Boolean));
    }

    if (knownProducts.length === 0 && Object.keys(shops).length === 0) {
      await deleteDrainKeys(tempKeys);
      return;
    }

    // ── Fetch all product docs once (needed to verify existence + boost data) ─
    const allSnaps = await Promise.all(
      knownProducts.map((p) =>
        db.collection(p.collection).doc(p.productId).get().catch(() => null),
      ),
    );

    // Only keep products whose docs actually exist
    const liveProducts = [];
    const boostedProducts = [];

    for (let i = 0; i < knownProducts.length; i++) {
      const snap = allSnaps[i];
      if (!snap?.exists) continue;

      const p = knownProducts[i];
      liveProducts.push(p);

      const data = snap.data();
      if (data.isBoosted && data.boostStartTime) {
        boostedProducts.push({...p, data});
      }
    }

    // ── Batch writer ─────────────────────────────────────────────────────────
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

    // ── Pass 1: Product click counts (only verified-existing docs) ───────────
    for (const {collection, productId, count} of liveProducts) {
      if (ops >= BATCH_LIMIT) await flushBatch();
      batch.update(db.collection(collection).doc(productId), {
        clickCount: admin.firestore.FieldValue.increment(count),
        clickCountUpdatedAt: now,
        metricsUpdatedAt: now,
      });
      ops++;
    }
    await flushBatch();

    // ── Pass 2: Boost history (pre-fetch all history docs in parallel) ───────
    if (boostedProducts.length > 0) {
      const historyQueries = boostedProducts.map(({productId, data, collection}) => {
        const historyCol =
          collection === 'shop_products' && data.shopId ? db.collection('shops').doc(data.shopId).collection('boostHistory') : data.userId ? db.collection('users').doc(data.userId).collection('boostHistory') : null;

        if (!historyCol) return Promise.resolve(null);

        return historyCol
          .where('itemId', '==', productId)
          .where('boostStartTime', '==', data.boostStartTime)
          .limit(1)
          .get()
          .catch((e) => {
            console.error(`[FlushClicks] Boost history query failed for ${productId}:`, e.message);
            return null;
          });
      });

      const historySnaps = await Promise.all(historyQueries);

      for (let i = 0; i < boostedProducts.length; i++) {
        const snap = historySnaps[i];
        if (!snap || snap.empty) continue;

        if (ops >= BATCH_LIMIT) await flushBatch();
        batch.update(snap.docs[0].ref, {
          clicksDuringBoost: admin.firestore.FieldValue.increment(boostedProducts[i].count),
          totalClickCount: admin.firestore.FieldValue.increment(boostedProducts[i].count),
        });
        ops++;
      }
      await flushBatch();
    }

    // ── Pass 3: Shop-level click counts ──────────────────────────────────────
    const shopEntries = Object.entries(shops);
    for (const [shopId, val] of shopEntries) {
      const count = parseInt(val, 10);
      if (count <= 0) continue;

      if (ops >= BATCH_LIMIT) await flushBatch();
      batch.update(db.collection('shops').doc(shopId), {
        clickCount: admin.firestore.FieldValue.increment(count),
        clickCountUpdatedAt: now,
      });
      ops++;
    }
    await flushBatch();

    // ── Cleanup only after all writes succeed ────────────────────────────────
    await deleteDrainKeys(tempKeys);

    if (liveProducts.length > 0) {
      await db.collection('_system').doc('metrics_version').set({
        lastMetricsUpdate: now,
        version: admin.firestore.FieldValue.increment(1),
      }, {merge: true});
    }

    console.log(JSON.stringify({
      event: 'flush_clicks_done',
      products: liveProducts.length,
      boosted: boostedProducts.length,
      shops: shopEntries.length,
      dropped: knownProducts.length - liveProducts.length,
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

  console.warn(`[FlushClicks] Recovering ${orphanedKeys.length} orphaned keys matching ${pattern}`);

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
