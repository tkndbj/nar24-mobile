import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
 
// ─────────────────────────────────────────────────────────────────────────────
// RETENTION POLICY
//
// These constants define how long each status is kept before deletion.
// Adjust to match your legal/audit requirements.
//
// TTL (primary):  Firestore deletes automatically within 72h of expiresAt.
//                 Enable via: Firebase Console → Firestore → TTL policies
//                   Collection: pendingPayments       Field: expiresAt
//                   Collection: pendingBoostPayments  Field: expiresAt
//                   Collection: pendingPaymentsBackup Field: expiresAt
//                   Collection: boostPaymentBackup    Field: expiresAt
//
// Daily sweep (secondary): Catches anything TTL missed; also handles docs
//                           that were created before TTL was enabled.
// ─────────────────────────────────────────────────────────────────────────────
const RETENTION = {
  // User abandoned the 3DS page — short retention, nothing useful here
  awaiting_3d: { days: 1 },
 
  // Terminal states — keep for audit / dispute window
  completed: { days: 90 },
  payment_failed: { days: 30 },
  hash_verification_failed: { days: 30 },
 
  // Payment charged but order/boost creation failed — keep longest for
  // manual recovery and potential refund evidence
  payment_succeeded_order_failed: { days: 180 },
  payment_succeeded_boost_failed: { days: 180 },
 
  // Intermediate states left behind by a crashed function instance.
  // The recovery scheduler re-processes these, but if it gives up
  // (max attempts exceeded) they should eventually be pruned.
  processing: { days: 7 },
  payment_verified_processing_order: { days: 7 },
  payment_verified_processing_boost: { days: 7 },
};
 
// Boost-specific terminal state aliases (same policy as order equivalents)
const BOOST_RETENTION = {
  ...RETENTION,
  payment_succeeded_boost_failed: { days: 180 },
};
 
// ─────────────────────────────────────────────────────────────────────────────
// setPaymentExpiresAt
//
// Call this whenever a pendingPayments / pendingBoostPayments document
// transitions to a new status. It stamps the correct expiresAt so Firestore
// TTL knows when to delete it.
//
// Usage (drop this into your existing callback handlers):
//
//   await pendingPaymentRef.update({
//     status: 'completed',
//     orderId: orderResult.orderId,
//     completedAt: admin.firestore.FieldValue.serverTimestamp(),
//     ...setPaymentExpiresAt('completed'),          // ← add this
//   });
// ─────────────────────────────────────────────────────────────────────────────
export function setPaymentExpiresAt(status, retentionMap = RETENTION) {
  const policy = retentionMap[status];
 
  if (!policy) {
    // Unknown status — keep for 30 days as a safe default
    console.warn(`[Cleanup] No retention policy for status '${status}', defaulting to 30 days`);
    return {
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000,
      ),
    };
  }
 
  return {
    expiresAt: admin.firestore.Timestamp.fromMillis(
      Date.now() + policy.days * 24 * 60 * 60 * 1000,
    ),
  };
}
 
export function setBoostPaymentExpiresAt(status) {
  return setPaymentExpiresAt(status, BOOST_RETENTION);
}
 
// ─────────────────────────────────────────────────────────────────────────────
// deleteInBatches
//
// Deletes a query snapshot in Firestore batches (max 500 ops each).
// Returns the total number of documents deleted.
// ─────────────────────────────────────────────────────────────────────────────
async function deleteInBatches(db, snap) {
  if (snap.empty) return 0;
 
  let deleted = 0;
  const BATCH_SIZE = 400; // stay well under the 500-op limit
 
  for (let i = 0; i < snap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snap.docs.slice(i, i + BATCH_SIZE).forEach((doc) => {
      batch.delete(doc.ref);
      deleted++;
    });
    await batch.commit();
  }
 
  return deleted;
}
 
// ─────────────────────────────────────────────────────────────────────────────
// cleanupCollection
//
// Sweeps a single collection, deleting docs where:
//   • expiresAt field exists and is in the past  (TTL missed these)
//   • OR status matches a retention policy and the doc is old enough
//     (docs created before TTL was enabled, or missing expiresAt entirely)
//
// Runs each status group as a separate query so it stays within Firestore's
// single-query result limits and avoids full collection scans.
// ─────────────────────────────────────────────────────────────────────────────
async function cleanupCollection(db, collectionName, retentionMap) {
  const now = admin.firestore.Timestamp.now();
  const results = {};
  let totalDeleted = 0;
 
  // ── Pass 1: delete anything TTL should have caught (expiresAt in the past) ──
  // Handles docs that were created before TTL policy was enabled, and catches
  // the ~72h window between expiration and actual Firestore TTL deletion.
  const ttlMissedSnap = await db.collection(collectionName)
    .where('expiresAt', '<=', now)
    .limit(500)
    .get();
 
  const ttlDeleted = await deleteInBatches(db, ttlMissedSnap);
  if (ttlDeleted > 0) {
    results['ttl_missed'] = ttlDeleted;
    totalDeleted += ttlDeleted;
    console.log(`[Cleanup] ${collectionName}: deleted ${ttlDeleted} TTL-missed docs`);
  }
 
  // ── Pass 2: status-based sweep for docs without expiresAt field ──────────
  // Targets legacy documents created before this cleanup system was deployed.
  for (const [status, policy] of Object.entries(retentionMap)) {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - policy.days * 24 * 60 * 60 * 1000,
    );
 
    // Query: correct status + no expiresAt field (legacy) + old enough
    // Firestore doesn't support "field doesn't exist" queries directly,
    // so we query by status + timestamp and filter client-side for missing expiresAt.
    const snap = await db.collection(collectionName)
      .where('status', '==', status)
      .where('createdAt', '<=', cutoff)
      .limit(500)
      .get();
 
    if (snap.empty) continue;
 
    // Only delete docs that don't already have expiresAt (TTL will handle the rest)
    const legacyDocs = { docs: snap.docs.filter((doc) => !doc.data().expiresAt), empty: false };
    if (legacyDocs.docs.length === 0) continue;
    legacyDocs.empty = legacyDocs.docs.length === 0;
 
    const count = await deleteInBatches(db, legacyDocs);
    if (count > 0) {
      results[status] = count;
      totalDeleted += count;
      console.log(`[Cleanup] ${collectionName}[${status}]: deleted ${count} legacy docs`);
    }
  }
 
  return { totalDeleted, breakdown: results };
}
 
// ─────────────────────────────────────────────────────────────────────────────
// cleanupPaymentCollections  —  runs daily at 03:00
//
// Why daily and not weekly?
//   At 20-30K concurrent users even at modest conversion, ~1000+ pending docs
//   are created daily. The recovery scheduler (*/5 min) queries pendingPayments
//   on every run — a bloated collection makes those queries progressively slower.
//   Weekly would let 7,000-10,000 stale docs accumulate, visibly degrading the
//   scheduler's query latency within 2-3 weeks at scale.
//
// Why not just TTL?
//   Firestore TTL is the primary mechanism (enable it — see notes above) but
//   it only guarantees deletion within 72 hours of the timestamp, not exactly
//   on time. This sweep catches the gap and handles legacy docs created before
//   TTL was enabled.
// ─────────────────────────────────────────────────────────────────────────────
export const cleanupPaymentCollections = onSchedule(
  {
    schedule: '0 3 * * *', // 03:00 daily — low-traffic window
    region: 'europe-west3',
    memory: '512MiB',
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const startTime = Date.now();
 
    console.log('[Cleanup] Starting daily payment collection cleanup');
 
    const collectionsToClean = [
      { name: 'pendingPayments',        retentionMap: RETENTION,       label: 'orders' },
      { name: 'pendingBoostPayments',   retentionMap: BOOST_RETENTION, label: 'boosts' },
      { name: 'pendingPaymentsBackup',  retentionMap: RETENTION,       label: 'orders-backup' },
      { name: 'boostPaymentBackup',     retentionMap: BOOST_RETENTION, label: 'boosts-backup' },
    ];
 
    const summary = {};
    let grandTotal = 0;
    const errors = [];
 
    // Clean each collection independently — one failure doesn't block others
    await Promise.allSettled(
      collectionsToClean.map(async ({ name, retentionMap, label }) => {
        try {
          const result = await cleanupCollection(db, name, retentionMap);
          summary[label] = result;
          grandTotal += result.totalDeleted;
        } catch (err) {
          console.error(`[Cleanup] Failed to clean ${name}:`, err.message);
          errors.push({ collection: name, error: err.message });
        }
      }),
    );
 
    const duration = Date.now() - startTime;
    console.log(`[Cleanup] Done in ${duration}ms — deleted ${grandTotal} total docs`, summary);
 
    // ── Persist run summary for ops visibility ────────────────────────────────
    try {
      await db.collection('_cleanup_logs').add({
        type: 'payment_collections_cleanup',
        grandTotal,
        summary,
        errors: errors.length > 0 ? errors : null,
        duration,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (logErr) {
      console.error('[Cleanup] Failed to write cleanup log (non-critical):', logErr.message);
    }
 
    // ── Alert if errors occurred ──────────────────────────────────────────────
    if (errors.length > 0) {
      try {
        await db.collection('_payment_alerts').add({
          type: 'payment_cleanup_partial_failure',
          severity: 'medium',
          errors,
          grandTotal,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {/* alerting must never throw */}
    }
  },
);
