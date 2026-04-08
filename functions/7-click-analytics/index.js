import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

/**
 * Hourly rollup: reads distributed click shards, increments the parent
 * document's clickCount by the shard total, resets shards to zero,
 * then removes the dirty flag.
 *
 * Only processes products/shops that received clicks since last rollup
 * (via _dirty_clicks collection), so cost scales with activity, not catalog size.
 */
export const rollupClickCounts = onSchedule({
  schedule: 'every 60 minutes',
  timeZone: 'UTC',
  timeoutSeconds: 300,
  memory: '256MiB',
  region: 'europe-west3',
  maxInstances: 1,
},
async () => {
  const db = admin.firestore();
  const startTime = Date.now();
  let totalRolledUp = 0;
  let totalSkipped = 0;
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    let query = db
      .collection('_dirty_clicks')
      .orderBy('updatedAt', 'asc')
      .limit(200);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();

    if (snapshot.empty) {
      hasMore = false;
      break;
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    // Read all shards in parallel
    const results = await Promise.all(
      snapshot.docs.map(async (dirtyDoc) => {
        const {collection} = dirtyDoc.data();
        const docId = dirtyDoc.id;

        if (!collection) return {dirtyRef: dirtyDoc.ref, docRef: null, total: 0, shardDocs: []};

        const docRef = db.collection(collection).doc(docId);

        // Verify target document still exists before reading shards
        const targetDoc = await docRef.get();
        if (!targetDoc.exists) {
          return {dirtyRef: dirtyDoc.ref, docRef: null, total: 0, skipped: true, shardDocs: []};
        }

        const shardsSnap = await docRef.collection('click_shards').get();

        if (shardsSnap.empty) {
          return {dirtyRef: dirtyDoc.ref, docRef: null, total: 0, shardDocs: []};
        }

        let total = 0;
        for (const shard of shardsSnap.docs) {
          total += shard.data().count || 0;
        }

        return {dirtyRef: dirtyDoc.ref, docRef, total, shardDocs: shardsSnap.docs};
      }),
    );

    // Batch: increment clickCount + delete dirty entry
    // Each item = up to 2 ops (update + delete), so chunk at 225
    const chunks = [];
    for (let i = 0; i < results.length; i += 225) {
      chunks.push(results.slice(i, i + 225));
    }

    for (const chunk of chunks) {
      const batch = db.batch();

      for (const {dirtyRef, docRef, total, skipped} of chunk) {
        if (skipped) {
          totalSkipped++;
        }

        if (docRef && total > 0) {
          batch.update(docRef, {
            clickCount: admin.firestore.FieldValue.increment(total),
            clickCountUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          totalRolledUp++;
        }
        batch.delete(dirtyRef);
      }

      await batch.commit();

      // Reset shards to zero so they don't get double-counted next rollup
      for (const {docRef, total, shardDocs} of chunk) {
        if (docRef && total > 0 && shardDocs.length > 0) {
          const resetBatch = db.batch();
          for (const shard of shardDocs) {
            resetBatch.update(shard.ref, {count: 0});
          }
          await resetBatch.commit();
        }
      }
    }

    if (snapshot.docs.length < 200) {
      hasMore = false;
    }
  }

  // Signal downstream consumers (trending products, promotion scores)
  if (totalRolledUp > 0) {
    await db.collection('_system').doc('metrics_version').set({
      lastMetricsUpdate: admin.firestore.FieldValue.serverTimestamp(),
      version: admin.firestore.FieldValue.increment(1),
    }, {merge: true});
  }

  const duration = Date.now() - startTime;

  console.log(JSON.stringify({
    level: 'INFO',
    event: 'rollup_completed',
    totalRolledUp,
    totalSkipped,
    duration,
  }));

  return {success: true, totalRolledUp, totalSkipped, duration};
});
