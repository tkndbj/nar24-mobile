import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

// ─────────────────────────────────────────────────────────────────────────────
// shared_favorites cleanup
//
// Each shared-favorites document is created with `expiresAt` set 30 days out
// (see lib/services/favorites_sharing_service.dart). The collection grows
// indefinitely if expired docs are never deleted.
//
// Architecture (industry standard):
//
//   PRIMARY: Firestore TTL policy — automatic deletion within 72h of expiresAt.
//     Enable via: Firebase Console → Firestore → TTL policies
//       Collection: shared_favorites      Field: expiresAt
//     This is essentially free (no CF invocations, no compute cost) and
//     scales to any volume without operator action.
//
//   SECONDARY (this file): Daily sweep that catches:
//     • The ~72h window between expiry and TTL deletion (so users don't see
//       a stale share resolve briefly before TTL gets to it).
//     • Legacy docs created before TTL was enabled / docs missing expiresAt.
//     • Any TTL gap during regional Firestore incidents.
//
// Cost at scale: trivial. Even with millions of users, expired share docs
// are bounded by daily share creation × 30 days, and each deletion is cheap.
// ─────────────────────────────────────────────────────────────────────────────

const COLLECTION = 'shared_favorites';

// Defensive cap on a single batch (Firestore limit is 500 ops).
const BATCH_SIZE = 400;

// Per-run delete cap. Prevents a runaway sweep from monopolizing the function
// instance; if there's a true backlog, subsequent days will drain it.
const MAX_DELETES_PER_RUN = 5000;

async function deleteInBatches(db, docs) {
  if (docs.length === 0) return 0;
  let deleted = 0;
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_SIZE).forEach((doc) => {
      batch.delete(doc.ref);
      deleted++;
    });
    await batch.commit();
  }
  return deleted;
}

export const cleanupSharedFavorites = onSchedule(
  {
    schedule: '15 3 * * *', // 03:15 daily — low-traffic window, offset from other cleanup jobs
    region: 'europe-west3',
    memory: '256MiB',
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const startTime = Date.now();
    const now = admin.firestore.Timestamp.now();

    console.log('[SharedFavoritesCleanup] Starting daily sweep');

    let totalDeleted = 0;
    const errors = [];

    try {
      // Pass 1: docs whose expiresAt has passed (TTL backstop).
      // Paginated so we never load more than BATCH_SIZE * a few hundred at once.
      let pageCursor = null;
      while (totalDeleted < MAX_DELETES_PER_RUN) {
        let query = db
          .collection(COLLECTION)
          .where('expiresAt', '<=', now)
          .orderBy('expiresAt')
          .limit(BATCH_SIZE);

        if (pageCursor) {
          query = query.startAfter(pageCursor);
        }

        const snap = await query.get();
        if (snap.empty) break;

        const deleted = await deleteInBatches(db, snap.docs);
        totalDeleted += deleted;

        if (snap.docs.length < BATCH_SIZE) break;
        pageCursor = snap.docs[snap.docs.length - 1];
      }

      // Pass 2: legacy / safety net — docs older than 30 days that have no
      // expiresAt at all (defensive, in case any future code path forgets to
      // set it). Bounded sweep — at most one batch per run.
      const legacyCutoff = admin.firestore.Timestamp.fromMillis(
        Date.now() - 31 * 24 * 60 * 60 * 1000,
      );
      const legacySnap = await db
        .collection(COLLECTION)
        .where('createdAt', '<=', legacyCutoff)
        .limit(BATCH_SIZE)
        .get();

      const legacyMissingExpiry = legacySnap.docs.filter(
        (doc) => !doc.data().expiresAt,
      );
      if (legacyMissingExpiry.length > 0) {
        const deleted = await deleteInBatches(db, legacyMissingExpiry);
        totalDeleted += deleted;
        console.log(
          `[SharedFavoritesCleanup] Deleted ${deleted} legacy docs missing expiresAt`,
        );
      }
    } catch (err) {
      console.error('[SharedFavoritesCleanup] Sweep failed:', err);
      errors.push({ message: err.message, stack: err.stack });
    }

    const duration = Date.now() - startTime;
    console.log(
      `[SharedFavoritesCleanup] Done in ${duration}ms — deleted ${totalDeleted} expired share doc(s)`,
    );

    // Persist run summary for ops visibility
    try {
      await db.collection('_cleanup_logs').add({
        type: 'shared_favorites_cleanup',
        totalDeleted,
        errors: errors.length > 0 ? errors : null,
        duration,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (logErr) {
      console.error(
        '[SharedFavoritesCleanup] Failed to write log (non-critical):',
        logErr.message,
      );
    }
  },
);
