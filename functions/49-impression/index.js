import {onCall} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import {bufferImpressions, drainImpressions, deleteDrainKeys, dedup, getRedisClient} from '../shared/redis.js';

// ============================================================================
// CLIENT-FACING: Buffer impressions in Redis (no Firestore writes)
// ============================================================================

export const incrementImpressionCount = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 10,
    memory: '256MiB',
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async (request) => {
    const {productIds, userGender, userAge} = request.data;

    if (!Array.isArray(productIds) || productIds.length === 0) {
      throw new Error('productIds must be a non-empty array.');
    }

    // Deduplicate and count
    const productCounts = new Map();
    productIds.forEach((id) => {
      productCounts.set(id, (productCounts.get(id) || 0) + 1);
    });

    // Normalize IDs
    const products = [];
    for (const [rawId, count] of productCounts) {
      if (products.length >= 100) break;

      let collection;
      let id;
      if (rawId.startsWith('shop_products_')) {
        collection = 'shop_products';
        id = rawId.slice(14);
      } else if (rawId.startsWith('products_')) {
        collection = 'products';
        id = rawId.slice(9);
      } else {
        collection = 'unknown';
        id = rawId;
      }
      products.push({productId: id, collection, count});
    }

    const getAgeGroup = (age) => {
      if (!age) return 'unknown';
      if (age < 18) return 'under18';
      if (age < 25) return '18-24';
      if (age < 35) return '25-34';
      if (age < 45) return '35-44';
      if (age < 55) return '45-54';
      return '55plus';
    };

    await bufferImpressions(products, userGender, getAgeGroup(userAge));

    return {success: true, buffered: products.length};
  },
);

// ============================================================================
// SCHEDULED FLUSH: Drain Redis → Firestore (every minute)
// ============================================================================

export const flushImpressions = onSchedule(
  {
    schedule: '* * * * *',
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 120,
    vpcConnector: 'nar24-vpc',
    vpcConnectorEgressSettings: 'PRIVATE_RANGES_ONLY',
  },
  async () => {
    // ── FIX 2: Distributed lock — prevent overlapping flushes ────────────────
    const locked = await dedup('flush_impressions_lock', 55);
    if (!locked) {
      console.log('[Flush] Another instance running, skipping');
      return;
    }

    // ── FIX 1: Recover orphaned drain keys from crashed flushes ──────────────
    const client = getRedisClient();
    await recoverOrphanedKeys(client, 'imp:counts');
    await recoverOrphanedKeys(client, 'imp:demo');

    // ── Drain current buffer ─────────────────────────────────────────────────
    const {counts, demo, tempKeys} = await drainImpressions();

    const countEntries = Object.entries(counts);
    if (countEntries.length === 0) {
      // Nothing buffered — clean up empty temp keys and exit
      await deleteDrainKeys(tempKeys);
      return;
    }

    console.log(`[Flush] Processing ${countEntries.length} products`);

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // ── Parse demographics into map: productId → [{gender, ageGroup, count}] ─
    const demoMap = new Map();
    for (const [key, val] of Object.entries(demo)) {
      const parts = key.split(':');
      const productId = parts.slice(0, -2).join(':');
      const gender = parts[parts.length - 2];
      const ageGroup = parts[parts.length - 1];
      if (!demoMap.has(productId)) demoMap.set(productId, []);
      demoMap.get(productId).push({gender, ageGroup, count: parseInt(val, 10)});
    }

    // ── Parse count entries and resolve unknown collections ───────────────────
    const unknownIds = [];
    const knownProducts = [];

    for (const [field, val] of countEntries) {
      const [collection, ...idParts] = field.split(':');
      const productId = idParts.join(':');
      const count = parseInt(val, 10);

      if (collection === 'unknown') {
        unknownIds.push({productId, count});
      } else {
        knownProducts.push({collection, productId, count});
      }
    }

    if (unknownIds.length > 0) {
      const resolved = await Promise.all(
        unknownIds.map(async ({productId, count}) => {
          const [pSnap, sSnap] = await Promise.all([
            db.collection('products').doc(productId).get().catch(() => null),
            db.collection('shop_products').doc(productId).get().catch(() => null),
          ]);
          if (sSnap?.exists) return {collection: 'shop_products', productId, count};
          if (pSnap?.exists) return {collection: 'products', productId, count};
          return null;
        }),
      );
      knownProducts.push(...resolved.filter(Boolean));
    }

    // ── FIX 3: Fetch ALL product docs ONCE for both passes ───────────────────
    const allSnaps = await Promise.all(
      knownProducts.map((p) =>
        db.collection(p.collection).doc(p.productId).get().catch(() => null),
      ),
    );

    const snapMap = new Map();
    knownProducts.forEach((p, i) => {
      if (allSnaps[i]?.exists) {
        snapMap.set(p.productId, {snap: allSnaps[i], data: allSnaps[i].data(), ...p});
      }
    });

    // ── Batch write helpers ──────────────────────────────────────────────────
    const BATCH_LIMIT = 450;
    let batch = db.batch();
    let ops = 0;

    const commitBatch = async () => {
      if (ops > 0) {
        await batch.commit();
        console.log(`[Flush] Committed ${ops} ops`);
        batch = db.batch();
        ops = 0;
      }
    };

    // ── Pass 1: Impression counts + boostedImpressionCount (single pass) ─────
    for (const {collection, productId, count} of knownProducts) {
      if (ops >= BATCH_LIMIT) await commitBatch();

      const ref = db.collection(collection).doc(productId);
      const entry = snapMap.get(productId);
      const isBoosted = entry?.data?.isBoosted || false;

      const updates = {
        impressionCount: admin.firestore.FieldValue.increment(count),
        lastImpressionTime: now,
        metricsUpdatedAt: now,
      };

      if (isBoosted) {
        updates.boostedImpressionCount = admin.firestore.FieldValue.increment(count);
      }

      batch.update(ref, updates);
      ops++;
    }

    await commitBatch();

    // ── Pass 2: Boost history demographics (only boosted products, no re-fetch)
    if (demoMap.size > 0) {
      for (const [productId, entry] of snapMap) {
        const {data, collection, count} = entry;
        if (!data.isBoosted || !demoMap.has(productId)) continue;

        const demos = demoMap.get(productId);
        const historyCol = collection === 'shop_products' && data.shopId ? db.collection('shops').doc(data.shopId).collection('boostHistory') : data.userId ? db.collection('users').doc(data.userId).collection('boostHistory') : null;

        if (!historyCol || !data.boostStartTime) continue;

        try {
          const histSnap = await historyCol
            .where('itemId', '==', productId)
            .where('boostStartTime', '==', data.boostStartTime)
            .limit(1)
            .get();

          if (!histSnap.empty) {
            if (ops >= BATCH_LIMIT) await commitBatch();

            const demoUpdates = {
              impressionsDuringBoost: admin.firestore.FieldValue.increment(count),
              totalImpressionCount: admin.firestore.FieldValue.increment(count),
            };
            for (const {gender, ageGroup, count: dCount} of demos) {
              demoUpdates[`demographics.${gender}`] = admin.firestore.FieldValue.increment(dCount);
              demoUpdates[`viewerAgeGroups.${ageGroup}`] = admin.firestore.FieldValue.increment(dCount);
            }

            batch.update(histSnap.docs[0].ref, demoUpdates);
            ops++;
          }
        } catch (e) {
          console.error(`[Flush] Boost history update failed for ${productId}:`, e.message);
        }
      }

      await commitBatch();
    }

    // ── FIX 1: Only delete temp keys AFTER all Firestore writes succeed ──────
    await deleteDrainKeys(tempKeys);

    console.log(`[Flush] Done — ${knownProducts.length} products flushed`);
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

  console.warn(`[Flush] Recovering ${orphanedKeys.length} orphaned keys matching ${pattern}`);

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
