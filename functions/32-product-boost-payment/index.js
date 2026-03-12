import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { transliterate } from 'transliteration';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import {CloudTasksClient} from '@google-cloud/tasks';
import { computeScores, DEFAULT_THRESHOLDS } from '../24-promotion-score/index.js';

const tasksClient = new CloudTasksClient();
const secretClient = new SecretManagerServiceClient();

// ── Helper to fetch a secret ──────────────────────────────────────────────────
async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({ name: secretName });
  return version.payload.data.toString('utf8');
}

// ── İş Bankası Configuration ──────────────────────────────────────────────────
let isbankConfig = null;

async function getIsbankConfig() {
  if (!isbankConfig) {
    const [clientId, apiUser, apiPassword, storeKey] = await Promise.all([
      getSecret('projects/emlak-mobile-app/secrets/ISBANK_CLIENT_ID/versions/latest'),
      getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_USER/versions/latest'),
      getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_PASSWORD/versions/latest'),
      getSecret('projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest'),
    ]);

    isbankConfig = {
      clientId,
      apiUser,
      apiPassword,
      storeKey,
      gatewayUrl: 'https://sanalpos.isbank.com.tr/fim/est3Dgate',
      currency: '949',
      storeType: '3d_pay_hosting',
    };
  }
  return isbankConfig;
}

// ── Hash ver3 generator (used for payment initialization) ─────────────────────
async function generateHashVer3(params) {
  const keys = Object.keys(params)
    .filter((key) => key !== 'hash' && key !== 'encoding')
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));

  const config = await getIsbankConfig();

  const values = keys.map((key) => {
    let value = String(params[key] || '');
    value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
    return value;
  });

  const plainText = values.join('|') + '|' + config.storeKey.trim();

  console.log('Hash keys order:', keys.join('|'));
  console.log('Hash plain text:', plainText);

  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

// ── Hash ver3 verifier (used for callback verification — sync, no async) ──────
// Computes the hash from raw request body fields without fetching secrets again.
function computeCallbackHashVer3(bodyFields, storeKey) {
  const keys = Object.keys(bodyFields)
    .filter((key) => {
      const lower = key.toLowerCase();
      return lower !== 'encoding' && lower !== 'hash' &&
             lower !== 'countdown' && lower !== 'nationalidno';
    })
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));

  const plainText =
    keys
      .map((key) => String(bodyFields[key] ?? '')
        .replace(/\\/g, '\\\\').replace(/\|/g, '\\|'))
      .join('|') +
    '|' +
    storeKey.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');

  return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
}

// ── Safe HTML redirect builder (prevents XSS from raw bank response values) ───
function buildRedirectHtml(deepLink, title, subtitle = '') {
  const esc = (s) => String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

  return `<!DOCTYPE html>
<html>
<head><title>${esc(title)}</title></head>
<body>
  <div style="text-align:center;padding:50px;">
    <h2>${esc(title)}</h2>
    ${subtitle ? `<p>${esc(subtitle)}</p>` : ''}
  </div>
  <script>window.location.href = '${esc(deepLink)}';</script>
</body>
</html>`;
}

// ── Fire-and-forget payment alert (never throws) ──────────────────────────────
function logBoostPaymentAlert(type, severity, oid, userId, errorMessage) {
  try {
    admin.firestore().collection('_payment_alerts').doc(`boost_${oid}`).set({
      type,
      severity,
      paymentOrderId: oid,
      userId: userId || 'unknown',
      errorMessage,
      isRead: false,
      isResolved: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      detectedBy: 'boost_callback',
    });
  } catch (_) {
    // Silent — alerting must never break anything
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helper
//
// Claim + expire a single boostedProducts document.
// Returns { success } | { skipped, reason } — never throws.
// ─────────────────────────────────────────────────────────────────────────────
async function processExpiredBoostDoc(db, doc, processedBy) {
    const boostIndexRef = doc.ref;
    const productId     = doc.id;
   
    let claimedData;
    try {
      claimedData = await claimExpiredBoost(db, boostIndexRef, processedBy);
    } catch (err) {
      console.error(`[Scheduler] Failed to claim ${productId}:`, err.message);
      throw err; // propagate so Promise.allSettled records the failure
    }
   
    if (!claimedData) {
      return { skipped: true, reason: 'claim_lost' };
    }
   
    return expireBoostItemCore(db, { ...claimedData, productId }, processedBy);
  }
   
  // ─────────────────────────────────────────────────────────────────────────────
  // LAYER 1 — processExpiredBoosts
  //
  // Runs every minute. Cheap when there is nothing to do (~1 Firestore read
  // that returns empty, function exits in < 100ms). When there are expired
  // items it processes up to 400 in parallel batches of 10.
  //
  // If a run finds exactly 400 results there may be more — the NEXT run
  // (60s later) will pick them up. For pathological cases (tens of thousands
  // expiring at the same moment) this is still bounded at ≤ 400 expirations
  // per minute per function instance. Cloud Scheduler can be tightened to
  // `every 30 seconds` if needed without any code changes.
  // ─────────────────────────────────────────────────────────────────────────────
  export const processExpiredBoosts = onSchedule(
    {
      schedule: '* * * * *', // every minute
      region: 'europe-west3',
      memory: '1GiB',
      timeoutSeconds: 300,
    },
    async () => {
      const db  = admin.firestore();
      const now = admin.firestore.Timestamp.now();
   
      // ── Query the index — O(active boosts) not O(all products) ───────────────
      // Requires composite index: processedAt ASC, boostEndTime ASC
      const expiredSnap = await db.collection('boostedProducts')
        .where('processedAt', '==', null)
        .where('boostEndTime', '<=', now)
        .orderBy('boostEndTime', 'asc') // oldest-first so the longest-overdue clear first
        .limit(400)
        .get();
   
      if (expiredSnap.empty) {
        // Fast path — nothing to do (the common case between boosts)
        return;
      }
   
      console.log(`[Scheduler] Processing ${expiredSnap.docs.length} expired boosts`);
   
      // ── Process with bounded concurrency ──────────────────────────────────────
      // 10 concurrent Firestore transactions + batch writes keeps throughput high
      // without saturating the Firestore write quota (max 1 write/sec per doc).
      const CONCURRENCY = 10;
      const results = { success: 0, skipped: 0, failed: 0 };
      const failures = [];
   
      for (let i = 0; i < expiredSnap.docs.length; i += CONCURRENCY) {
        const chunk = expiredSnap.docs.slice(i, i + CONCURRENCY);
   
        const settled = await Promise.allSettled(
          chunk.map((doc) => processExpiredBoostDoc(db, doc, 'scheduler')),
        );
   
        settled.forEach((result, idx) => {
          if (result.status === 'fulfilled') {
            result.value?.skipped ? results.skipped++ : results.success++;
          } else {
            results.failed++;
            failures.push({
              productId: chunk[idx].id,
              error: result.reason?.message || String(result.reason),
            });
            console.error(`[Scheduler] Failed: ${chunk[idx].id}`, result.reason?.message);
          }
        });
      }
   
      console.log(
        `[Scheduler] Done — ` +
        `${results.success} expired, ${results.skipped} skipped, ${results.failed} failed` +
        (expiredSnap.docs.length === 400 ? ' (limit hit — more may remain)' : ''),
      );
   
      // ── Persist failure summary for alerting ──────────────────────────────────
      if (failures.length > 0) {
        try {
          await db.collection('_payment_alerts').add({
            type: 'boost_scheduler_partial_failure',
            severity: failures.length > 10 ? 'high' : 'medium',
            failCount: failures.length,
            failures: failures.slice(0, 50), // cap payload size
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
      }
    },
  );
   
  // ─────────────────────────────────────────────────────────────────────────────
  // LAYER 3 — expiredBoostCleanup
  //
  // Daily emergency sweep. Finds any boost that:
  //   • has processedAt == null   (not yet expired)
  //   • has boostEndTime ≤ 2 hours ago  (scheduler + backup task both missed it)
  //
  // If anything is found it means both Layer 1 and Layer 2 failed for that item,
  // which should be extremely rare. The function expires them and raises a high-
  // severity alert for investigation.
  //
  // Also prunes boostedProducts records older than 30 days to keep the collection
  // lean (the composite index stays fast when the collection is small).
  // ─────────────────────────────────────────────────────────────────────────────
  export const expiredBoostCleanup = onSchedule(
    {
      schedule: '0 2 * * *', // 02:00 daily
      region: 'europe-west3',
      memory: '512MiB',
      timeoutSeconds: 540,
    },
    async () => {
      const db = admin.firestore();
   
      // ── 1. Find boosts missed by both Layer 1 and Layer 2 ────────────────────
      const twoHoursAgo = admin.firestore.Timestamp.fromMillis(
        Date.now() - 2 * 60 * 60 * 1000,
      );
   
      const missedSnap = await db.collection('boostedProducts')
        .where('processedAt', '==', null)
        .where('boostEndTime', '<=', twoHoursAgo)
        .get(); // intentionally no limit — must catch everything
   
      if (!missedSnap.empty) {
        const count = missedSnap.docs.length;
        console.warn(`[Cleanup] ⚠️  Found ${count} boost(s) missed by scheduler + backup task`);
   
        // Raise alert immediately before processing (so it's recorded even if
        // the cleanup itself fails partway through)
        try {
          await db.collection('_payment_alerts').add({
            type: 'boost_missed_expirations_cleanup',
            severity: count > 5 ? 'high' : 'medium',
            count,
            productIds: missedSnap.docs.map((d) => d.id),
            message: `Cleanup job found ${count} boost(s) that both the scheduler and backup task missed`,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
   
        // Process with lower concurrency — cleanup should be gentle
        const CONCURRENCY = 5;
        let processed = 0;
   
        for (let i = 0; i < missedSnap.docs.length; i += CONCURRENCY) {
          const chunk = missedSnap.docs.slice(i, i + CONCURRENCY);
          const settled = await Promise.allSettled(
            chunk.map((doc) => processExpiredBoostDoc(db, doc, 'cleanup')),
          );
   
          settled.forEach((result, idx) => {
            if (result.status === 'rejected') {
              console.error(`[Cleanup] Failed to expire ${chunk[idx].id}:`, result.reason?.message);
            } else {
              processed++;
            }
          });
        }
   
        console.log(`[Cleanup] Processed ${processed}/${count} missed expirations`);
      } else {
        console.log('[Cleanup] ✅ No missed expirations — all layers working correctly');
      }
   
      // ── 2. Prune old processed records (> 30 days) ───────────────────────────
      // Keeps the boostedProducts collection lean so the composite index stays fast.
      // processedAt is a Timestamp, so the single-field index handles this query.
      const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
        Date.now() - 30 * 24 * 60 * 60 * 1000,
      );
   
      const oldRecordsSnap = await db.collection('boostedProducts')
        .where('processedAt', '<=', thirtyDaysAgo)
        .limit(500) // batch-delete safely
        .get();
   
      if (!oldRecordsSnap.empty) {
        const deleteBatch = db.batch();
        oldRecordsSnap.docs.forEach((doc) => deleteBatch.delete(doc.ref));
        await deleteBatch.commit();
        console.log(`[Cleanup] Pruned ${oldRecordsSnap.docs.length} old boost index records`);
      }
    },
  );

  // ─────────────────────────────────────────────────────────────────────────────
// claimExpiredBoost
//
// Atomically marks a boostedProducts index doc as processed.
// Returns the boost data if we won the claim, null otherwise.
//
// Reasons for returning null (all safe to ignore):
//   • already claimed by scheduler / another task / cleanup job
//   • stale task — product was re-boosted after this task was scheduled
//   • boostEndTime is still in the future (race between boost activation
//     and an early-firing task)
//   • index doc was deleted (cleanup already ran)
// ─────────────────────────────────────────────────────────────────────────────
async function claimExpiredBoost(db, boostIndexRef, processedBy, expectedTaskName = null) {
    let claimedData = null;
   
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(boostIndexRef);
   
      if (!snap.exists) {
        console.log(`[Claim] Index doc missing for ${boostIndexRef.id} — already cleaned up`);
        return;
      }
   
      const data = snap.data();
   
      // Already processed by someone else
      if (data.processedAt !== null) {
        console.log(`[Claim] ${boostIndexRef.id} already claimed by '${data.processedBy}', skipping`);
        return;
      }
   
      // Stale task guard — if a product was re-boosted after this task was
      // scheduled, taskName in the index will be different.
      if (expectedTaskName && data.taskName !== expectedTaskName) {
        console.log(`[Claim] Stale task for ${boostIndexRef.id}: expected ${expectedTaskName}, found ${data.taskName}`);
        return;
      }
   
      // Not yet expired (e.g. backup task fired early somehow)
      const now = new Date();
      if (data.boostEndTime.toDate() > now) {
        console.log(`[Claim] ${boostIndexRef.id} boostEndTime still in the future, skipping`);
        return;
      }
   
      // We win the claim — mark atomically
      tx.update(boostIndexRef, {
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processedBy,
      });
   
      claimedData = data;
    });
   
    return claimedData; // null = skip, object = proceed with expiration
  }
   
  // ─────────────────────────────────────────────────────────────────────────────
  // expireBoostItemCore
  //
  // Performs all expiration side-effects for a single product:
  //   1. Clears boost fields on the product document
  //   2. Recomputes organic promotion score immediately (no wait for ranking job)
  //   3. Updates boostHistory with final impression / click metrics
  //   4. Writes a notification (user or shop)
  //
  // All writes go through Firestore batch writes (≤500 ops/batch).
  // The function is idempotent: if isBoosted is already false, it exits cleanly.
  // ─────────────────────────────────────────────────────────────────────────────
 async function expireBoostItemCore(db, boostData, processedBy) {
    const {
      productId,
      collection,
      shopId,
      userId,         // initiating user (or product owner for personal products)
      boostStartTime, // from index doc — avoids extra product read just for this field
    } = boostData;
   
    // ── Fetch current product state ───────────────────────────────────────────
    const productRef = db.collection(collection).doc(productId);
    const productSnap = await productRef.get();
   
    if (!productSnap.exists) {
      // Product deleted between boost activation and expiration — nothing to do
      console.warn(`[ExpireCore] Product ${productId} not found in ${collection}, skipping`);
      return { skipped: true, reason: 'product_not_found' };
    }
   
    const data = productSnap.data();
   
    if (!data.isBoosted) {
      // Already expired (e.g. admin manually cleared it, or double-run)
      console.log(`[ExpireCore] ${productId} already not boosted, skipping`);
      return { skipped: true, reason: 'already_expired' };
    }
   
    const productName  = data.productName || 'Product';
    const actualUserId = data.userId  || userId;
    const actualShopId = collection === 'shop_products' ? (data.shopId || shopId) : null;
   
    const ops = []; // Collect all writes; commit in a single batch at the end
   
    // ── 1. Update boostHistory with final metrics ─────────────────────────────
    const histStartTime = boostStartTime || data.boostStartTime;
   
    if (histStartTime) {
      const historyCol = collection === 'products' ?
        db.collection('users').doc(actualUserId).collection('boostHistory') :
        db.collection('shops').doc(actualShopId).collection('boostHistory');
   
      // This query requires a composite index:
      //   Collection: boostHistory  Fields: itemId ASC, boostStartTime ASC
      const historySnap = await historyCol
        .where('itemId', '==', productId)
        .where('boostStartTime', '==', histStartTime)
        .limit(1)
        .get();
   
      if (!historySnap.empty) {
        const impressionsDuringBoost =
          (data.boostedImpressionCount || 0) - (data.boostImpressionCountAtStart || 0);
        const clicksDuringBoost =
          (data.clickCount || 0) - (data.boostClickCountAtStart || 0);
   
        ops.push({
          type: 'update',
          ref: historySnap.docs[0].ref,
          data: {
            impressionsDuringBoost,
            clicksDuringBoost,
            totalImpressionCount: data.boostedImpressionCount || 0,
            totalClickCount: data.clickCount || 0,
            finalImpressions: data.boostImpressionCountAtStart || 0,
            finalClicks: data.boostClickCountAtStart || 0,
            itemName: data.productName || 'Unnamed Product',
            productImage: data.imageUrls?.[0] || null,
            averageRating: data.averageRating || 0,
            price: data.price    || 0,
            currency: data.currency || 'TL',
            actualExpirationTime: admin.firestore.FieldValue.serverTimestamp(),
            expiredBy: processedBy,
          },
        });
      }
    }
   
    // ── 2. Notification ───────────────────────────────────────────────────────
    if (collection === 'shop_products' && actualShopId) {
      ops.push({
        type: 'set',
        ref: db.collection('shop_notifications').doc(),
        data: {
          shopId: actualShopId,
          type: 'boost_expired',
          productId,
          productName,
          productImage: data.imageUrls?.[0] || null,
          isRead: {},
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    } else if (collection === 'products' && actualUserId) {
      ops.push({
        type: 'set',
        ref: db.collection('users').doc(actualUserId).collection('notifications').doc(),
        data: {
          userId: actualUserId,
          type: 'boost_expired',
          productName,
          message_en: `${productName} boost has expired.`,
          message_tr: `${productName} boost süresi doldu.`,
          message_ru: `У объявления ${productName} закончился буст.`,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          productId,
          itemType: 'product',
        },
      });
    }
   
    // ── 3. Expire the product and recompute organic score immediately ─────────
    // This drops the product from the boosted tier without waiting for the next
    // ranking job run (which could be up to 12 hours later).
    const scores = computeScores({ ...data, isBoosted: false }, DEFAULT_THRESHOLDS);
   
    ops.push({
      type: 'update',
      ref: productRef,
      data: {
        isBoosted: false,
        boostStartTime: admin.firestore.FieldValue.delete(),
        boostEndTime: admin.firestore.FieldValue.delete(),
        boostExpirationTaskName: admin.firestore.FieldValue.delete(),
        lastBoostExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
        expiredBy: processedBy,
        ...(scores && {
          organicScore: scores.organicScore,
          lastRankingUpdate: scores.lastRankingUpdate,
        }),
        promotionScore: scores ? scores.promotionScore : 0,
      },
    });
   
    // ── 4. Commit all writes in Firestore batch(es) ───────────────────────────
    const BATCH_SIZE = 500;
    for (let i = 0; i < ops.length; i += BATCH_SIZE) {
      const batch = db.batch();
      ops.slice(i, i + BATCH_SIZE).forEach((op) => {
        if (op.type === 'update') batch.update(op.ref, op.data);
        else                      batch.set(op.ref, op.data);
      });
      await batch.commit();
    }
   
    console.log(`[ExpireCore] ✅ Expired ${productId} (by: ${processedBy})`);
    return { success: true };
  }

// ─────────────────────────────────────────────────────────────────────────────
// processBatchBoost
//
// CHANGED: PHASE 2 now also writes a `boostedProducts` index document.
// This is the entry-point for the scheduler-based expiration system.
// The index doc has processedAt = null (meaning "active / not yet expired").
// ─────────────────────────────────────────────────────────────────────────────
async function processBatchBoost(db, batchItems, userId, boostDuration, isAdmin) {
    const validatedItems = [];
    const failedItems    = [];
   
    await db.runTransaction(async (transaction) => {
      const now              = new Date();
      const boostEndDate     = new Date(now.getTime() + boostDuration * 60 * 1000);
      const boostStartTimestamp = admin.firestore.Timestamp.fromDate(now);
      const boostEndTimestamp   = admin.firestore.Timestamp.fromDate(boostEndDate);
   
      const shopMembershipCache    = new Map();
      const userVerificationCache  = new Map();
      const basePricePerProduct    = 1.0;
      const itemsData              = [];
   
      // ── PHASE 1: ALL READS ───────────────────────────────────────────────────
      for (const item of batchItems) {
        try {
          const { itemId, collection, shopId: itemShopId } = item;
   
          const productRef  = db.collection(collection).doc(itemId);
          const productSnap = await transaction.get(productRef);
   
          if (!productSnap.exists) {
            console.warn(`Product ${itemId} not found in ${collection}`);
            failedItems.push({ ...item, error: 'Product not found' });
            continue;
          }
   
          const productData = productSnap.data();
          let hasPermission = false;
   
          if (collection === 'products') {
            hasPermission = productData.userId === userId || isAdmin;
          } else if (collection === 'shop_products') {
            const targetShopId = itemShopId || productData.shopId;
            if (!targetShopId) {
              failedItems.push({ ...item, error: 'Missing shopId' });
              continue;
            }
            if (isAdmin) {
              hasPermission = true;
            } else if (shopMembershipCache.has(targetShopId)) {
              hasPermission = shopMembershipCache.get(targetShopId);
            } else {
              const shopSnap = await transaction.get(db.collection('shops').doc(targetShopId));
              if (shopSnap.exists) {
                const sd = shopSnap.data();
                hasPermission =
                  sd.ownerId === userId ||
                  (sd.editors   && sd.editors.includes(userId))   ||
                  (sd.coOwners  && sd.coOwners.includes(userId))  ||
                  (sd.viewers   && sd.viewers.includes(userId));
                shopMembershipCache.set(targetShopId, hasPermission);
              }
            }
          }
   
          if (!hasPermission) {
            failedItems.push({ ...item, error: 'Insufficient permissions' });
            continue;
          }
   
          if (productData.isBoosted && productData.boostEndTime?.toDate() > now) {
            failedItems.push({ ...item, error: 'Already boosted' });
            continue;
          }
   
          const ownerUserId = productData.userId || userId;
          let isVerified = false;
          if (userVerificationCache.has(ownerUserId)) {
            isVerified = userVerificationCache.get(ownerUserId);
          } else {
            try {
              const ownerSnap = await transaction.get(db.collection('users').doc(ownerUserId));
              isVerified = ownerSnap.exists ? (ownerSnap.data().verified || false) : false;
              userVerificationCache.set(ownerUserId, isVerified);
            } catch (e) {
              userVerificationCache.set(ownerUserId, false);
            }
          }
   
          itemsData.push({
            item, productRef, productData, isVerified,
            targetShopId: itemShopId || productData.shopId,
          });
        } catch (itemError) {
          console.error(`Error processing item ${item.itemId}:`, itemError);
          failedItems.push({ ...item, error: itemError.message });
        }
      }
   
      // ── PHASE 2: ALL WRITES ──────────────────────────────────────────────────
      for (const { item, productRef, productData, isVerified, targetShopId } of itemsData) {
        const { itemId, collection } = item;
   
        const currentImpressions = productData.boostedImpressionCount || 0;
        const currentClicks      = productData.clickCount || 0;
        const boostScreen        = isVerified ? 'shop_product' : 'product';
        const screenType         = isVerified ? 'shop_product' : 'product';
   
        const taskName =
          `expire-boost-${collection}-${itemId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
   
        // Update the product itself
        transaction.update(productRef, {
          boostStartTime: boostStartTimestamp,
          boostEndTime: boostEndTimestamp,
          boostDuration,
          isBoosted: true,
          boostImpressionCountAtStart: currentImpressions,
          boostClickCountAtStart: currentClicks,
          boostScreen,
          screenType,
          boostExpirationTaskName: taskName,
          promotionScore: (productData.rankingScore || 0) + 1000,
          lastRankingUpdate: admin.firestore.FieldValue.serverTimestamp(),
        });
   
        // Boost history
        const historyData = {
          userId, itemId,
          itemType: collection === 'shop_products' ? 'shop_product' : 'product',
          itemName: productData.productName || 'Unnamed Product',
          boostStartTime: boostStartTimestamp,
          boostEndTime: boostEndTimestamp,
          boostDuration,
          pricePerMinutePerItem: basePricePerProduct,
          boostPrice: boostDuration * basePricePerProduct,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          boostImpressionCountAtStart: currentImpressions,
          boostClickCountAtStart: currentClicks,
          finalImpressions: 0, finalClicks: 0,
          totalImpressionCount: 0, totalClickCount: 0,
          demographics: {}, viewerAgeGroups: {},
        };
   
        if (collection === 'shop_products' && targetShopId) {
          transaction.set(
            db.collection('shops').doc(targetShopId).collection('boostHistory').doc(),
            historyData,
          );
        } else {
          transaction.set(
            db.collection('users').doc(userId).collection('boostHistory').doc(),
            historyData,
          );
        }
   
        // ── NEW: Write boostedProducts index doc ─────────────────────────────
        // This is the entry-point for the scheduler-based expiration engine.
        // processedAt = null means "active, not yet expired."
        // The scheduler queries: WHERE processedAt == null AND boostEndTime <= now
        // Requires composite index: processedAt ASC, boostEndTime ASC
        transaction.set(db.collection('boostedProducts').doc(itemId), {
          productId: itemId,
          collection,
          shopId: targetShopId || null,
          userId,                          // initiating user
          productUserId: productData.userId || null, // actual product owner
          boostStartTime: boostStartTimestamp,
          boostEndTime: boostEndTimestamp,
          boostDuration,
          taskName,                        // used by backup task for stale-task detection
          processedAt: null,           // null = active, Timestamp = expired
          processedBy: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
   
        validatedItems.push({
          itemId, collection,
          shopId: targetShopId,
          productData,
          currentImpressions, currentClicks,
          boostScreen, boostEndDate, taskName,
        });
      }
    });
   
    return { validatedItems, failedItems };
  }
   
  // ─────────────────────────────────────────────────────────────────────────────
  // scheduleExpirationTasks
  //
  // CHANGED: tasks now schedule 2 minutes AFTER boostEndTime (backup role).
  // The primary expiration (scheduler) runs every minute and will expire the
  // boost before this task fires. The task is purely a safety net.
  // ─────────────────────────────────────────────────────────────────────────────
  async function scheduleExpirationTasks(validatedItems, userId) {
    const projectId = process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'emlak-mobile-app';
    const location  = 'europe-west3';
    const queue     = 'boost-expiration-queue';
   
    console.log(`Scheduling backup tasks: project=${projectId}, queue=${queue}`);
   
    const scheduledTasks  = [];
    const failedSchedules = [];
    const PARALLEL_LIMIT  = 5;
   
    for (let i = 0; i < validatedItems.length; i += PARALLEL_LIMIT) {
      const batch = validatedItems.slice(i, i + PARALLEL_LIMIT);
   
      await Promise.all(batch.map(async (item) => {
        try {
          const { taskName, itemId, collection, shopId, boostEndDate } = item;
          const parent          = tasksClient.queuePath(projectId, location, queue);
          const boostEndTimeUTC = new Date(boostEndDate.getTime());
   
          // ── 2-minute backup delay ─────────────────────────────────────────────
          // Scheduler fires every minute so it will have expired this boost by now.
          // This task is only here in case the scheduler had an outage.
          const BACKUP_DELAY_MS     = 2 * 60 * 1000;
          const effectiveScheduleTime = new Date(boostEndTimeUTC.getTime() + BACKUP_DELAY_MS);
   
          const payload = {
            itemId, collection, shopId, userId,
            boostEndTime: boostEndTimeUTC.toISOString(),
            taskName,
            scheduledAt: new Date().toISOString(),
          };
   
          const task = {
            name: tasksClient.taskPath(projectId, location, queue, taskName),
            httpRequest: {
              httpMethod: 'POST',
              url: `https://${location}-${projectId}.cloudfunctions.net/expireSingleBoost`,
              headers: { 'Content-Type': 'application/json' },
              body: Buffer.from(JSON.stringify(payload)),
              oidcToken: { serviceAccountEmail: `${projectId}@appspot.gserviceaccount.com` },
            },
            scheduleTime: { seconds: Math.floor(effectiveScheduleTime.getTime() / 1000) },
          };
   
          const [response] = await tasksClient.createTask({ parent, task });
          console.log(`✅ Backup task scheduled: ${response.name}`);
   
          scheduledTasks.push({
            taskName: response.name,
            itemId,
            scheduledFor: effectiveScheduleTime.toISOString(),
            boostExpiresAt: boostEndTimeUTC.toISOString(),
          });
        } catch (taskError) {
          console.error(`❌ Failed to schedule backup task for ${item.itemId}:`, taskError);
          failedSchedules.push({ itemId: item.itemId, error: taskError.message });
        }
      }));
    }
   
    if (failedSchedules.length > 0) {
      console.warn(`Failed to schedule ${failedSchedules.length} backup tasks:`, failedSchedules);
      // Non-critical: the scheduler (Layer 1) will still expire these items.
      // Log so ops can investigate Cloud Tasks quota issues.
    }
   
    return scheduledTasks;
  }
   
  // ─────────────────────────────────────────────────────────────────────────────
  // expireSingleBoost — LAYER 2 BACKUP TASK
  //
  // CHANGED: This function no longer does full expiration work itself.
  // It delegates entirely to claimExpiredBoost + expireBoostItemCore.
  //
  // Normal flow: scheduler already set processedAt → claim returns null → exits
  //              in < 50ms with a 200. Zero wasted work.
  // Fallback:    scheduler missed this item → claim succeeds → expires it now →
  //              writes a monitoring alert so the team can investigate.
  // ─────────────────────────────────────────────────────────────────────────────
  export const expireSingleBoost = onRequest(
    {
      region: 'europe-west3',
      memory: '256MiB',
      timeoutSeconds: 60,
      invoker: 'private',
    },
    async (req, res) => {
      try {
        const { itemId, collection, taskName } = req.body;
   
        if (!itemId || !collection) {
          res.status(400).json({ error: 'Missing required parameters' });
          return;
        }
   
        const db             = admin.firestore();
        const boostIndexRef  = db.collection('boostedProducts').doc(itemId);
   
        console.log(`[BackupTask] Checking ${itemId} (taskName: ${taskName})`);
   
        // Pass expectedTaskName so stale tasks (product re-boosted) are safely skipped
        const claimedData = await claimExpiredBoost(db, boostIndexRef, 'backup_task', taskName);
   
        if (!claimedData) {
          // Scheduler already handled this — the common case
          console.log(`[BackupTask] ${itemId} already processed or not eligible, skipping`);
          res.status(200).json({ message: 'Already processed by scheduler', itemId });
          return;
        }
   
        // Scheduler missed this item — handle it now and alert ops
        console.warn(`[BackupTask] ⚠️ Scheduler missed ${itemId} — expiring via backup task`);
   
        await expireBoostItemCore(db, { ...claimedData, productId: itemId }, 'backup_task');
   
        // Monitoring alert — this fires only when the scheduler genuinely missed something
        try {
          await db.collection('_payment_alerts').add({
            type: 'boost_scheduler_miss',
            severity: 'low',
            productId: itemId,
            collection,
            taskName,
            message: `Backup task had to expire boost for ${itemId} — scheduler missed it`,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
   
        res.status(200).json({ success: true, message: `Backup expiration completed for ${itemId}` });
      } catch (error) {
        console.error('[BackupTask] Error:', error);
        res.status(500).json({ error: 'Failed to expire boost', details: error.message });
      }
    },
  );
   
  // ─────────────────────────────────────────────────────────────────────────────
  // executeBoostLogic — unchanged, used by boostPaymentCallback
  // ─────────────────────────────────────────────────────────────────────────────
  async function executeBoostLogic(db, userId, items, boostDuration, isAdmin) {
    const BATCH_SIZE       = 10;
    const allValidatedItems = [];
    const failedItems       = [];
   
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const batchItems = items.slice(i, i + BATCH_SIZE);
      try {
        const batchResult = await processBatchBoost(db, batchItems, userId, boostDuration, isAdmin);
        allValidatedItems.push(...batchResult.validatedItems);
        failedItems.push(...batchResult.failedItems);
      } catch (batchError) {
        console.error(`Batch ${i / BATCH_SIZE + 1} failed:`, batchError);
        failedItems.push(...batchItems.map((item) => ({ ...item, error: batchError.message })));
      }
    }
   
    if (allValidatedItems.length === 0) {
      throw new Error('No valid items found to boost. Check permissions and item validity.');
    }
   
    const scheduledTasks = await scheduleExpirationTasks(allValidatedItems, userId);
    const totalPrice     = allValidatedItems.length * boostDuration * 1.0;
   
    return {
      boostedItemsCount: allValidatedItems.length,
      totalRequestedItems: items.length,
      failedItemsCount: failedItems.length,
      boostDuration,
      boostStartTime: admin.firestore.Timestamp.fromDate(new Date()),
      boostEndTime: admin.firestore.Timestamp.fromDate(new Date(Date.now() + boostDuration * 60 * 1000)),
      totalPrice,
      pricePerItem: boostDuration * 1.0,
      boostedItems: allValidatedItems.map((item) => ({
        itemId: item.itemId,
        collection: item.collection,
        shopId: item.shopId,
      })),
      failedItems: failedItems.length > 0 ? failedItems : undefined,
      scheduledTasks,
    };
  }
   
  // ─────────────────────────────────────────────────────────────────────────────
  // initializeBoostPayment — unchanged
  // ─────────────────────────────────────────────────────────────────────────────
  export const initializeBoostPayment = onCall(
    { region: 'europe-west3', memory: '256MiB', timeoutSeconds: 30 },
    async (request) => {
      try {
        if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
   
        const { items, boostDuration, isShopContext, shopId, customerName, customerEmail, customerPhone } =
          request.data;
   
        const sanitizedCustomerName = (() => {
          if (!customerName) return 'Customer';
          const s = transliterate(customerName).replace(/[^a-zA-Z0-9\s]/g, '').trim().substring(0, 50);
          return s || 'Customer';
        })();
   
        if (!items || !Array.isArray(items) || items.length === 0)
          {throw new HttpsError('invalid-argument', 'Items array is required and must not be empty.');}
        if (!boostDuration || typeof boostDuration !== 'number' || boostDuration <= 0 || boostDuration > 10080)
          {throw new HttpsError('invalid-argument', 'Boost duration must be a positive number (max 10080 minutes).');}
        if (items.length > 50)
          {throw new HttpsError('invalid-argument', 'Cannot boost more than 50 items at once.');}
   
        for (const item of items) {
          if (!item.itemId || typeof item.itemId !== 'string')
            {throw new HttpsError('invalid-argument', 'Each item must have a valid itemId.');}
          if (!item.collection || !['products', 'shop_products'].includes(item.collection))
            {throw new HttpsError('invalid-argument', 'Each item must specify a valid collection.');}
          if (item.collection === 'shop_products' && (!item.shopId || typeof item.shopId !== 'string'))
            {throw new HttpsError('invalid-argument', 'Shop products must include a valid shopId.');}
        }
   
        const db                 = admin.firestore();
        const basePricePerProduct = 1.0;
        const totalPrice         = items.length * boostDuration * basePricePerProduct;
        const formattedAmount    = Math.round(totalPrice).toString();
        const orderNumber        = `BOOST-${Date.now()}-${request.auth.uid.substring(0, 8)}`;
        const rnd                = Date.now().toString();
        const config             = await getIsbankConfig();
        const baseUrl            = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
        const okUrl              = `${baseUrl}/boostPaymentCallback`;
        const failUrl            = okUrl;
        const callbackUrl        = okUrl;
   
        const hashParams = {
          BillToName: sanitizedCustomerName, amount: formattedAmount,
          callbackurl: callbackUrl, clientid: config.clientId, currency: config.currency,
          email: customerEmail || '', failurl: failUrl, hashAlgorithm: 'ver3',
          islemtipi: 'Auth', lang: 'tr', oid: orderNumber, okurl: okUrl, rnd,
          storetype: config.storeType, taksit: '', tel: customerPhone || '',
        };
   
        const hash = await generateHashVer3(hashParams);
        const paymentParams = {
          clientid: config.clientId, storetype: config.storeType, hash, hashAlgorithm: 'ver3',
          islemtipi: 'Auth', amount: formattedAmount, currency: config.currency, oid: orderNumber,
          okurl: okUrl, failurl: failUrl, callbackurl: callbackUrl, lang: 'tr', rnd, taksit: '',
          BillToName: sanitizedCustomerName, email: customerEmail || '', tel: customerPhone || '',
        };
   
        await db.collection('pendingBoostPayments').doc(orderNumber).set({
          userId: request.auth.uid,
          amount: totalPrice,
          formattedAmount, orderNumber,
          status: 'awaiting_3d',
          paymentParams,
          boostData: { items, boostDuration, isShopContext: isShopContext || false, shopId: shopId || null, basePricePerProduct },
          customerInfo: { name: sanitizedCustomerName, email: customerEmail, phone: customerPhone },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
        });
   
        return { success: true, gatewayUrl: config.gatewayUrl, paymentParams, orderNumber, totalPrice, itemCount: items.length };
      } catch (error) {
        console.error('Boost payment initialization error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );
   
  // ─────────────────────────────────────────────────────────────────────────────
  // boostPaymentCallback — production-hardened (from previous review)
  // No changes to payment logic; only added processingDuration tracking.
  // ─────────────────────────────────────────────────────────────────────────────
  export const boostPaymentCallback = onRequest(
    { region: 'europe-west3', memory: '512MiB', timeoutSeconds: 90, cors: true, invoker: 'public' },
    async (request, response) => {
      const startTime = Date.now();
      const db = admin.firestore();
   
      try {
        console.log('[BoostPayment] Callback invoked:', request.method);
        console.log('[BoostPayment] Body:', JSON.stringify(request.body, null, 2));
   
        const { Response: bankResponse, mdStatus, oid, ProcReturnCode, ErrMsg, HASH } = request.body;
   
        // İşbank probe guard
        if (!request.body.oid && request.body.HASH && request.body.rnd) {
          response.status(200).send('<html><body></body></html>');
          return;
        }
        if (!oid) {response.status(400).send('Order number missing'); return;}
   
        const storeKey    = (await getSecret('projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest')).trim();
        const computedHash = computeCallbackHashVer3(request.body, storeKey);
        const hashValid    = HASH && computedHash === HASH;
   
        const callbackLogRef = db.collection('boost_payment_callback_logs').doc();
        await callbackLogRef.set({
          oid, hashValid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          requestBody: request.body,
          ip: request.ip || request.headers['x-forwarded-for'] || null,
          userAgent: request.headers['user-agent'] || null,
          processingStarted: new Date(startTime).toISOString(),
        });
   
        const pendingPaymentRef = db.collection('pendingBoostPayments').doc(oid);
   
        const txResult = await db.runTransaction(async (tx) => {
          const snap = await tx.get(pendingPaymentRef);
          if (!snap.exists) return { error: 'not_found' };
   
          const p = snap.data();
          if (p.status === 'completed')                          return { alreadyProcessed: true, status: 'completed', pendingPayment: p };
          if (p.status === 'payment_succeeded_boost_failed')     return { alreadyProcessed: true, status: p.status };
          if (p.status === 'payment_failed')                     return { alreadyProcessed: true, status: p.status };
          if (p.status === 'hash_verification_failed')           return { alreadyProcessed: true, status: p.status };
          if (p.status === 'processing' || p.status === 'payment_verified_processing_boost')
            {return { retry: true, pendingPayment: p };}
          if (p.status !== 'awaiting_3d')                        return { alreadyProcessed: true, status: p.status };
   
          if (!hashValid) {
            tx.update(pendingPaymentRef, { status: 'hash_verification_failed', receivedHash: HASH || null, computedHash, callbackLogId: callbackLogRef.id, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
            return { error: 'hash_failed' };
          }
   
          const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
          const isTxnSuccess  = bankResponse === 'Approved' && ProcReturnCode === '00';
   
          if (!isAuthSuccess || !isTxnSuccess) {
            tx.update(pendingPaymentRef, { status: 'payment_failed', mdStatus, procReturnCode: ProcReturnCode, errorMessage: ErrMsg || 'Payment failed', rawResponse: request.body, callbackLogId: callbackLogRef.id, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
            return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
          }
   
          tx.update(pendingPaymentRef, { status: 'processing', mdStatus, procReturnCode: ProcReturnCode, rawResponse: request.body, callbackLogId: callbackLogRef.id, processingStartedAt: admin.firestore.FieldValue.serverTimestamp() });
          return { success: true, pendingPayment: p };
        });
   
        if (txResult.error === 'not_found') {response.status(404).send('Payment session not found'); return;}
        if (txResult.error === 'hash_failed')    {response.send(buildRedirectHtml('boost-payment-failed://hash-error', 'Ödeme Doğrulama Hatası', 'Lütfen tekrar deneyin.')); return;}
        if (txResult.error === 'payment_failed') {response.send(buildRedirectHtml(`boost-payment-failed://${encodeURIComponent(txResult.message)}`, 'Boost Ödemesi Başarısız', txResult.message)); return;}
   
        if (txResult.alreadyProcessed) {
          if (txResult.status === 'completed') response.send(buildRedirectHtml(`boost-payment-success://${oid}`, '✓ Boost Ödemesi Başarılı', 'Boost işleminiz tamamlandı.'));
          else response.send(buildRedirectHtml(`boost-payment-status://${txResult.status}`, 'İşlem Zaten İşlendi'));
          return;
        }
   
        if (txResult.retry) {
          let retries = 0;
          while (retries < 20) {
            await new Promise((r) => setTimeout(r, 500));
            const check = (await pendingPaymentRef.get()).data();
            if (check.status === 'completed') {response.send(buildRedirectHtml(`boost-payment-success://${oid}`, '✓ Boost Ödemesi Başarılı', 'Boost işleminiz tamamlandı.')); return;}
            if (check.status === 'payment_succeeded_boost_failed' || check.status === 'payment_failed') {response.send(buildRedirectHtml('boost-payment-failed://processing-error', 'İşlem Hatası', 'Lütfen destek ile iletişime geçin.')); return;}
            retries++;
          }
          console.error(`[BoostPayment] Timeout polling for ${oid}`);
          response.status(500).send('Processing timeout');
          return;
        }
   
        // ── Execute boost ───────────────────────────────────────────────────────
        try {
          const { pendingPayment } = txResult;
          const boostData = pendingPayment.boostData;
   
          let isAdmin = false;
          try {
            const userRecord = await admin.auth().getUser(pendingPayment.userId);
            isAdmin = userRecord.customClaims?.admin === true;
            if (!isAdmin) {
              const adminDoc = await db.collection('users').doc(pendingPayment.userId).get();
              isAdmin = adminDoc.exists && adminDoc.data()?.isAdmin === true;
            }
          } catch (e) {console.warn('Could not check admin status:', e.message);}
   
          const boostResult = await executeBoostLogic(db, pendingPayment.userId, boostData.items, boostData.boostDuration, isAdmin);
   
          // Shop metrics (non-critical)
          try {
            const shopBoostCounts = {};
            for (const item of boostResult.boostedItems) {
              if (item.shopId) shopBoostCounts[item.shopId] = (shopBoostCounts[item.shopId] || 0) + 1;
            }
            if (Object.keys(shopBoostCounts).length > 0) {
              const b = db.batch();
              for (const [sid, count] of Object.entries(shopBoostCounts)) {
                b.update(db.collection('shops').doc(sid), {
                  'metrics.boostCount': admin.firestore.FieldValue.increment(count),
                  'metrics.lastUpdated': admin.firestore.FieldValue.serverTimestamp(),
                });
              }
              await b.commit();
            }
          } catch (metricsError) {console.error('Failed to update shop metrics:', metricsError);}
   
          const cleanBoostResult = {
            boostedItemsCount: boostResult.boostedItemsCount,
            totalRequestedItems: boostResult.totalRequestedItems,
            failedItemsCount: boostResult.failedItemsCount || 0,
            boostDuration: boostResult.boostDuration,
            boostStartTime: boostResult.boostStartTime,
            boostEndTime: boostResult.boostEndTime,
            totalPrice: boostResult.totalPrice,
            pricePerItem: boostResult.pricePerItem,
            boostedItems: boostResult.boostedItems.map((i) => ({
              itemId: i.itemId, collection: i.collection, ...(i.shopId && { shopId: i.shopId }),
            })),
            ...(boostResult.failedItems?.length > 0   && { failedItems: boostResult.failedItems }),
            ...(boostResult.scheduledTasks            && { scheduledTasks: boostResult.scheduledTasks }),
          };
   
          await pendingPaymentRef.update({
            status: 'completed', boostResult: cleanBoostResult,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            processingDuration: Date.now() - startTime,
          });
          await callbackLogRef.update({
            processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
            success: true, processingDuration: Date.now() - startTime,
          });
   
          // Receipt generation (non-critical)
          try {
            const productNames = {};
            await Promise.all(boostResult.boostedItems.map((item) => {
              const ref = item.collection === 'shop_products' ?
                db.collection('shop_products').doc(item.itemId) :
                db.collection('products').doc(item.itemId);
              return ref.get().then((snap) => {
                productNames[item.itemId] = snap.exists ? (snap.data().name || snap.data().productName || 'Boost Item') : 'Boost Item';
              }).catch(() => {productNames[item.itemId] = 'Boost Item';});
            }));
   
            let buyerInfo = { name: pendingPayment.customerInfo.name || 'Customer', email: pendingPayment.customerInfo.email || '', phone: pendingPayment.customerInfo.phone || '' };
            if (boostData.isShopContext && boostData.shopId) {
              try {
                const sd = (await db.collection('shops').doc(boostData.shopId).get()).data();
                if (sd) buyerInfo = { name: sd.name || 'Shop', email: sd.email || sd.contactEmail || '', phone: sd.contactNo || sd.phoneNumber || '' };
            } catch (_) {/* alerting must never throw */}
            } else {
              try {
                const ud = (await db.collection('users').doc(pendingPayment.userId).get()).data();
                if (ud) buyerInfo = { name: ud.displayName || buyerInfo.name, email: ud.email || buyerInfo.email, phone: ud.phoneNumber || buyerInfo.phone };
            } catch (_) {/* alerting must never throw */}
            }
   
            const receiptGroups = {};
            for (const item of boostResult.boostedItems) {
              const ownerId   = (item.shopId && item.shopId.trim()) ? item.shopId : pendingPayment.userId;
              const ownerType = (item.shopId && item.shopId.trim()) ? 'shop' : 'user';
              if (!receiptGroups[ownerId]) receiptGroups[ownerId] = { ownerId, ownerType, items: [] };
              receiptGroups[ownerId].items.push({ ...item, productName: productNames[item.itemId] });
            }
   
            for (const [, group] of Object.entries(receiptGroups)) {
              const itemsSubtotal = group.items.length * boostData.boostDuration * boostData.basePricePerProduct;
              await db.collection('receiptTasks').add({
                receiptType: 'boost', orderId: oid,
                ownerId: group.ownerId, ownerType: group.ownerType,
                buyerId: pendingPayment.userId, buyerName: buyerInfo.name,
                buyerEmail: buyerInfo.email, buyerPhone: buyerInfo.phone,
                totalPrice: itemsSubtotal, itemsSubtotal,
                deliveryPrice: 0, currency: 'TRY', paymentMethod: 'isbank_3d',
                orderDate: admin.firestore.FieldValue.serverTimestamp(), language: 'tr',
                boostData: {
                  boostDuration: boostData.boostDuration, itemCount: group.items.length,
                  items: group.items.map((i) => ({
                    itemId: i.itemId, collection: i.collection, productName: i.productName,
                    boostDuration: boostData.boostDuration, unitPrice: boostData.basePricePerProduct,
                    totalPrice: boostData.boostDuration * boostData.basePricePerProduct, shopId: i.shopId || null,
                  })),
                },
                status: 'pending', createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });
            }
            console.log(`[BoostPayment] Receipt tasks created for ${oid}`);
          } catch (receiptError) {console.error('Receipt task creation failed (non-critical):', receiptError);}
   
          console.log(`[BoostPayment] ${oid} → boost completed, ${boostResult.boostedItemsCount} items`);
          response.send(buildRedirectHtml(
            `boost-payment-success://${oid}`, '✓ Boost Ödemesi Başarılı',
            `${boostResult.boostedItemsCount} ürün ${boostResult.boostDuration} dakika boyunca boost edildi.`,
          ));
        } catch (boostError) {
          console.error('[BoostPayment] Boost processing failed after payment:', boostError);
   
          await pendingPaymentRef.update({ status: 'payment_succeeded_boost_failed', boostError: boostError.message, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
          await callbackLogRef.update({ processingFailed: admin.firestore.FieldValue.serverTimestamp(), error: boostError.message, success: false });
   
          logBoostPaymentAlert('boost_execution_failed_after_payment', 'high', oid, txResult.pendingPayment?.userId, boostError.message);
   
          response.send(buildRedirectHtml('boost-payment-failed://boost-processing-error', 'Boost İşlem Hatası', `Ödeme alındı ancak boost işlemi başarısız. Lütfen destek ile iletişime geçin. Sipariş No: ${oid}`));
        }
      } catch (error) {
        console.error('[BoostPayment] Critical callback error:', error);
        try {
          await db.collection('boost_payment_callback_errors').add({
            oid: request.body?.oid || 'unknown', error: error.message, stack: error.stack,
            requestBody: request.body, timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
        response.status(500).send('Internal server error');
      }
    },
  );
   
  // ─────────────────────────────────────────────────────────────────────────────
  // checkBoostPaymentStatus — unchanged
  // ─────────────────────────────────────────────────────────────────────────────
  export const checkBoostPaymentStatus = onCall(
    { region: 'europe-west3', memory: '256MiB', timeoutSeconds: 10 },
    async (request) => {
      try {
        if (!request.auth) throw new HttpsError('unauthenticated', 'User must be authenticated');
        const { orderNumber } = request.data;
        if (!orderNumber) throw new HttpsError('invalid-argument', 'Order number is required');
   
        const snap = await admin.firestore().collection('pendingBoostPayments').doc(orderNumber).get();
        if (!snap.exists) throw new HttpsError('not-found', 'Payment not found');
   
        const p = snap.data();
        if (p.userId !== request.auth.uid) throw new HttpsError('permission-denied', 'Unauthorized');
   
        return { orderNumber, status: p.status, boostResult: p.boostResult || null, errorMessage: p.errorMessage || null, boostError: p.boostError || null };
      } catch (error) {
        console.error('Check boost payment status error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );
