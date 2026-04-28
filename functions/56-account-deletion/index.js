// functions/56-account-deletion/index.js
//
// Account-deletion lifecycle:
//   • precheckAccountDeletion                  — surfaces ownership state + localized warnings
//   • transferOwnership                        — atomic shop/restaurant ownership swap
//   • deleteUserAccount                        — moved from main index; gated on ownership
//   • processAccountDeletionShopArchive        — Cloud Tasks worker for shop products
//   • processAccountDeletionUserProductArchive — Cloud Tasks worker for individual seller products
//   • processAccountDataPurge                  — Cloud Tasks worker for recursive user-data delete
//
// Flow on self-delete when the user owns shops/restaurants:
//   1) Client → precheckAccountDeletion
//      → 'clear'              → safe to delete
//      → 'transfer_required'  → show member bottom sheet, call transferOwnership, re-precheck
//      → 'solo_owner_warning' → show "will be disabled" warning, call delete with confirmDisableOwned
//   2) Client → deleteUserAccount({ email, confirmDisableOwned: true })
//      → server re-checks ownership (never trust the client)
//      → solo-owned shops/restaurants get isActive=false
//      → per shop, a Cloud Task is enqueued to archive products in pages (with retry)
//      → memberships, sent + received invitations cleaned up
//      → audit row written to account_deletions/{uid}
//      → Auth deleted
//      → Cloud Task enqueued for recursive Firestore purge (with retry; inline fallback)

import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import { CloudTasksClient } from '@google-cloud/tasks';
import { FieldValue, FieldPath } from 'firebase-admin/firestore';

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = 'europe-west3';
const PROJECT_ID =
  process.env.GCP_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  'emlak-mobile-app';

const ARCHIVE_QUEUE = 'account-deletion-archive-queue';
const PURGE_QUEUE = 'account-deletion-purge-queue';
const ARCHIVE_PAGE_SIZE = 25;
const AUDIT_COLLECTION = 'account_deletions';

const ROLE_TO_FIELD = {
  'co-owner': 'coOwners',
  'editor': 'editors',
  'viewer': 'viewers',
};
const MEMBER_ROLE_FIELDS = ['coOwners', 'editors', 'viewers'];

const ENTITY_CONFIG = {
  shop: {
    collection: 'shops',
    memberField: 'memberOfShops',
    label: 'shop',
  },
  restaurant: {
    collection: 'restaurants',
    memberField: 'memberOfRestaurants',
    label: 'restaurant',
  },
};

// ─── Lazy singletons ──────────────────────────────────────────────────────────

let _db;
const db = () => _db ?? (_db = admin.firestore());

let _tasks;
const tasks = () => _tasks ?? (_tasks = new CloudTasksClient());

// ─── Generic helpers ──────────────────────────────────────────────────────────

async function isAdmin(uid) {
  // Accept either a custom claim (set by setAdminClaim) or a users-doc flag.
  try {
    const record = await admin.auth().getUser(uid);
    if (record.customClaims?.isAdmin === true) return true;
  } catch (_) {/* fall through */}
  try {
    const snap = await db().collection('users').doc(uid).get();
    return snap.exists && snap.data()?.isAdmin === true;
  } catch (_) {
    return false;
  }
}

async function syncUserClaims(uid) {
  const [userSnap, userRecord] = await Promise.all([
    db().doc(`users/${uid}`).get(),
    admin.auth().getUser(uid),
  ]);

  const data = userSnap.data() ?? {};
  const existingClaims = userRecord.customClaims ?? {};

  const newClaims = {
    ...existingClaims,
    shops: data.memberOfShops ?? {},
    restaurants: data.memberOfRestaurants ?? {},
  };

  await admin.auth().setCustomUserClaims(uid, newClaims);
}

async function syncUserClaimsSafe(uid) {
  try {
    await syncUserClaims(uid);
  } catch (err) {
    console.error(`[syncUserClaims] Failed for uid=${uid}:`, err);
    // Queue for backfillShopClaims to pick up (same fallback as 28-shop-invitation)
    try {
      await db().collection('claimsSyncQueue').add({
        uid,
        failedAt: FieldValue.serverTimestamp(),
        error: err?.message ?? 'unknown',
        retryCount: 0,
      });
    } catch (queueErr) {
      console.error(`[syncUserClaims] Could not enqueue retry for uid=${uid}:`, queueErr);
    }
  }
}

async function hasSubcollections(docRef) {
  const collections = await docRef.listCollections();
  return collections.length > 0;
}

// ─── Ownership inspection ─────────────────────────────────────────────────────

async function getOwnedEntities(uid) {
  const [shopsSnap, restaurantsSnap] = await Promise.all([
    db().collection('shops').where('ownerId', '==', uid).get(),
    db().collection('restaurants').where('ownerId', '==', uid).get(),
  ]);

  const owned = [];
  for (const doc of shopsSnap.docs) {
    owned.push({ ref: doc.ref, id: doc.id, type: 'shop', data: doc.data() });
  }
  for (const doc of restaurantsSnap.docs) {
    owned.push({ ref: doc.ref, id: doc.id, type: 'restaurant', data: doc.data() });
  }
  return owned;
}

function getEntityMembers(entityData) {
  const members = [];
  const seen = new Set();
  for (const field of MEMBER_ROLE_FIELDS) {
    const ids = Array.isArray(entityData[field]) ? entityData[field] : [];
    const role =
      field === 'coOwners' ? 'co-owner' :
      field === 'editors'  ? 'editor'  : 'viewer';
    for (const uid of ids) {
      if (!uid || seen.has(uid)) continue;
      seen.add(uid);
      members.push({ uid, role });
    }
  }
  return members;
}

async function fetchUserDisplayNames(uids) {
  const result = new Map();
  if (uids.length === 0) return result;

  // getAll accepts up to 1000 refs per call; chunk defensively.
  const CHUNK = 200;
  for (let i = 0; i < uids.length; i += CHUNK) {
    const slice = uids.slice(i, i + CHUNK);
    const refs = slice.map((id) => db().collection('users').doc(id));
    const docs = await db().getAll(...refs);
    for (const doc of docs) {
      const data = doc.data() ?? {};
      const display =
        data.displayName ||
        data.name ||
        data.fullName ||
        data.email ||
        doc.id;
      result.set(doc.id, display);
    }
  }
  return result;
}

// ─── Localization for precheck ────────────────────────────────────────────────

function buildPrecheckMessages(soloOwned, transferRequired) {
  const messages = { en: '', tr: '', ru: '' };

  if (transferRequired.length > 0) {
    const names = transferRequired.map((e) => e.name || e.id).join(', ');
    const isPlural = transferRequired.length > 1;
    messages.en =
      `You own ${transferRequired.length} ${isPlural ? 'businesses' : 'business'} (${names}) ` +
      `with active members. If ${isPlural ? 'they are' : 'it is'} actively maintained, ` +
      `please transfer ownership to another member first.`;
    messages.tr =
      `Aktif üyeleri olan ${transferRequired.length} işletmeye sahipsiniz (${names}). ` +
      `Aktif olarak yürütülüyorsa, lütfen önce sahipliği başka bir üyeye devredin.`;
    messages.ru =
      `Вы являетесь владельцем ${transferRequired.length} бизнес${isPlural ? 'ов' : 'а'} (${names}) ` +
      `с активными участниками. Если ${isPlural ? 'они активны' : 'он активен'}, ` +
      `сначала передайте право владения другому участнику.`;
  }

  if (soloOwned.length > 0) {
    const names = soloOwned.map((e) => e.name || e.id).join(', ');
    const isPlural = soloOwned.length > 1;
    const en =
      `You own ${soloOwned.length} ${isPlural ? 'businesses' : 'business'} (${names}) ` +
      `with no other members. Deleting your account will disable ${isPlural ? 'them' : 'it'} ` +
      `and all sales will be paused. Do you want to continue?`;
    const tr =
      `Başka üyesi olmayan ${soloOwned.length} işletmeye sahipsiniz (${names}). ` +
      `Hesabınızı silmek ${isPlural ? 'bu işletmeleri' : 'bu işletmeyi'} devre dışı bırakacak ` +
      `ve tüm satışlar durdurulacaktır. Devam etmek istiyor musunuz?`;
    const ru =
      `Вы являетесь владельцем ${soloOwned.length} бизнес${isPlural ? 'ов' : 'а'} (${names}) ` +
      `без других участников. Удаление аккаунта отключит ${isPlural ? 'их' : 'его'}, ` +
      `и все продажи будут приостановлены. Продолжить?`;

    messages.en = messages.en ? `${messages.en}\n\n${en}` : en;
    messages.tr = messages.tr ? `${messages.tr}\n\n${tr}` : tr;
    messages.ru = messages.ru ? `${messages.ru}\n\n${ru}` : ru;
  }

  return messages;
}

// ─── Bulk delete by query (chunked into 500-op batches) ──────────────────────
// Used for inline cleanup of bundles, ad submissions, applications. Returns
// the number of docs actually deleted. Best-effort: per-batch failures are
// logged but don't abort the overall sweep.

async function deleteByQuery(query, label) {
  const PER_BATCH = 500;
  let deleted = 0;
  let cursor = null;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let pageQuery = query
      .orderBy(FieldPath.documentId())
      .limit(PER_BATCH);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);

    const snap = await pageQuery.get();
    if (snap.empty) break;

    const batch = db().batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    try {
      await batch.commit();
      deleted += snap.docs.length;
    } catch (err) {
      console.warn(`[deleteByQuery:${label}] batch commit failed: ${err.message}`);
      break;
    }

    cursor = snap.docs[snap.docs.length - 1].id;
    if (snap.docs.length < PER_BATCH) break;
  }

  return deleted;
}

// ─── Generic retry wrapper for transient infrastructure failures ──────────────
// Used for Cloud Tasks enqueue calls — retries with exponential backoff (~3s
// total worst case) before giving up. Idempotent operations only.

async function withRetry(fn, { attempts = 3, baseMs = 250, label = 'op' } = {}) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (i < attempts - 1) {
        const delay = baseMs * Math.pow(3, i); // 250ms, 750ms, 2250ms
        console.warn(
          `[retry] ${label} attempt ${i + 1}/${attempts} failed: ${err.message} — retrying in ${delay}ms`,
        );
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastErr;
}

// ─── Cloud Tasks: enqueue archive workers ─────────────────────────────────────

async function enqueueShopArchiveTask({ shopId, deletedUserId, startedAt, cursor }) {
  const parent = tasks().queuePath(PROJECT_ID, REGION, ARCHIVE_QUEUE);
  const url = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/processAccountDeletionShopArchive`;

  const payload = { shopId, deletedUserId, startedAt, cursor: cursor ?? null };

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url,
      headers: { 'Content-Type': 'application/json' },
      body: Buffer.from(JSON.stringify(payload)),
      oidcToken: { serviceAccountEmail: `${PROJECT_ID}@appspot.gserviceaccount.com` },
    },
  };

  const [response] = await tasks().createTask({ parent, task });
  return response.name;
}

async function enqueueUserProductArchiveTask({ deletedUserId, startedAt, cursor }) {
  const parent = tasks().queuePath(PROJECT_ID, REGION, ARCHIVE_QUEUE);
  const url = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/processAccountDeletionUserProductArchive`;

  const payload = { deletedUserId, startedAt, cursor: cursor ?? null };

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url,
      headers: { 'Content-Type': 'application/json' },
      body: Buffer.from(JSON.stringify(payload)),
      oidcToken: { serviceAccountEmail: `${PROJECT_ID}@appspot.gserviceaccount.com` },
    },
  };

  const [response] = await tasks().createTask({ parent, task });
  return response.name;
}

// ─── Cloud Tasks: enqueue Firestore purge worker ──────────────────────────────

async function enqueueAccountPurgeTask({ targetUid, isAdminDelete, deletedBy }) {
  const parent = tasks().queuePath(PROJECT_ID, REGION, PURGE_QUEUE);
  const url = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/processAccountDataPurge`;

  const payload = { targetUid, isAdminDelete, deletedBy };

  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url,
      headers: { 'Content-Type': 'application/json' },
      body: Buffer.from(JSON.stringify(payload)),
      oidcToken: { serviceAccountEmail: `${PROJECT_ID}@appspot.gserviceaccount.com` },
    },
  };

  const [response] = await tasks().createTask({ parent, task });
  return response.name;
}

// ─── Internal: archive a single product (shop or individual seller) ───────────
// Mirrors the archive path in toggleProductPauseStatus (48-product-management)
// without the permission check (caller has already proven authority) and
// without the boost-expired notification fan-out (the owner is being deleted).
//
// Parameterized over collection + ownership field so the same logic serves
// both shop_products → paused_shop_products and products → paused_products.

async function archiveProductInternal({
  productId,
  modifiedBy,
  sourceCollection,
  destCollection,
  ownerField,    // 'shopId' or 'userId'
  ownerValue,    // expected value of ownerField
}) {
  const sourceRef = db().collection(sourceCollection).doc(productId);
  const destRef = db().collection(destCollection).doc(productId);

  const productSnap = await sourceRef.get();
  if (!productSnap.exists) {
    return { skipped: 'not-found' }; // already moved or never existed — idempotent
  }

  const productData = productSnap.data();
  if (productData[ownerField] !== ownerValue) {
    console.warn(
      `[archive] product ${productId} ${ownerField} mismatch ` +
      `(got ${productData[ownerField]}, expected ${ownerValue})`,
    );
    return { skipped: 'owner-mismatch' };
  }

  const wasBoosted = productData.isBoosted === true;
  const boostTaskName = productData.boostExpirationTaskName || null;

  const destData = {
    ...productData,
    paused: true,
    archivedReason: 'owner_account_deleted',
    archivedAt: FieldValue.serverTimestamp(),
    lastModified: FieldValue.serverTimestamp(),
    modifiedBy,
  };

  if (wasBoosted) {
    destData.isBoosted = false;
    destData.lastBoostExpiredAt = FieldValue.serverTimestamp();
    destData.promotionScore = Math.max((productData.promotionScore || 0) - 1000, 0);
    delete destData.boostStartTime;
    delete destData.boostEndTime;
    delete destData.boostExpirationTaskName;
    delete destData.boostDuration;
    delete destData.boostScreen;
    delete destData.screenType;
    delete destData.boostImpressionCountAtStart;
    delete destData.boostClickCountAtStart;
  }

  // Atomic doc move
  const moveBatch = db().batch();
  moveBatch.set(destRef, destData);
  moveBatch.delete(sourceRef);
  await moveBatch.commit();

  // Subcollection migration (best-effort; failure here doesn't undo the move)
  const subcollectionsToMove = ['reviews', 'product_questions', 'sale_preferences'];
  for (const subName of subcollectionsToMove) {
    try {
      const sourceSub = sourceRef.collection(subName);
      const destSub = destRef.collection(subName);
      const snap = await sourceSub.get();
      if (snap.empty) continue;

      const PER_BATCH = 250; // 250 sets + 250 deletes = 500 ops, the batch cap
      let cur = db().batch();
      let ops = 0;

      for (const doc of snap.docs) {
        cur.set(destSub.doc(doc.id), doc.data());
        cur.delete(doc.ref);
        ops += 2;
        if (ops >= PER_BATCH * 2) {
          await cur.commit();
          cur = db().batch();
          ops = 0;
        }
      }
      if (ops > 0) await cur.commit();
    } catch (err) {
      console.warn(`[archive] subcollection ${subName} for ${productId} failed: ${err.message}`);
    }
  }

  // Cancel scheduled boost expiration task (silent if already fired/deleted)
  if (boostTaskName) {
    try {
      const taskPath = tasks().taskPath(
        PROJECT_ID, REGION, 'boost-expiration-queue', boostTaskName,
      );
      await tasks().deleteTask({ name: taskPath });
    } catch (err) {
      if (err.code !== 5) { // 5 = NOT_FOUND
        console.warn(`[archive] could not cancel boost task ${boostTaskName}: ${err.message}`);
      }
    }
  }

  return { archived: true };
}

// ─── precheckAccountDeletion ──────────────────────────────────────────────────
// Returns the ownership state the client needs to decide which UI to show.
// Safe to call repeatedly (read-only, no side effects).

export const precheckAccountDeletion = onCall(
  { region: REGION, memory: '256MiB', maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    let targetUid = request.auth.uid;
    if (request.data?.uid && typeof request.data.uid === 'string' && request.data.uid.trim()) {
      const requested = request.data.uid.trim();
      if (requested !== request.auth.uid) {
        if (!await isAdmin(request.auth.uid)) {
          throw new HttpsError('permission-denied', 'Only admins can precheck other users.');
        }
        targetUid = requested;
      }
    }

    const owned = await getOwnedEntities(targetUid);

    const soloOwned = [];
    const transferRequired = [];
    const allMemberUids = new Set();

    for (const entity of owned) {
      const members = getEntityMembers(entity.data);
      const summary = {
        id: entity.id,
        type: entity.type,
        name: entity.data.name ?? '',
      };
      if (members.length === 0) {
        soloOwned.push(summary);
      } else {
        members.forEach((m) => allMemberUids.add(m.uid));
        transferRequired.push({ ...summary, members });
      }
    }

    const nameMap = await fetchUserDisplayNames([...allMemberUids]);

    for (const entity of transferRequired) {
      entity.members = entity.members.map((m) => ({
        uid: m.uid,
        role: m.role,
        displayName: nameMap.get(m.uid) ?? m.uid,
      }));
    }

    let status;
    if (transferRequired.length > 0) {
      status = 'transfer_required';
    } else if (soloOwned.length > 0) {
      status = 'solo_owner_warning';
    } else {
      status = 'clear';
    }

    return {
      status,
      soloOwned,
      transferRequired,
      messages: buildPrecheckMessages(soloOwned, transferRequired),
    };
  },
);

// ─── transferOwnership ────────────────────────────────────────────────────────
// Caller must be the current owner (or admin). The new owner must already be a
// co-owner / editor / viewer of the entity. After transfer the previous owner
// becomes a co-owner — the deletion flow then strips them via the normal
// membership cleanup, which keeps this function reusable outside deletion.

export const transferOwnership = onCall(
  { region: REGION, memory: '256MiB', maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const { entityId, entityType, newOwnerId } = request.data || {};

    if (!entityId || typeof entityId !== 'string') {
      throw new HttpsError('invalid-argument', 'entityId is required.');
    }
    if (!newOwnerId || typeof newOwnerId !== 'string') {
      throw new HttpsError('invalid-argument', 'newOwnerId is required.');
    }
    if (entityType !== 'shop' && entityType !== 'restaurant') {
      throw new HttpsError('invalid-argument', 'entityType must be "shop" or "restaurant".');
    }

    const config = ENTITY_CONFIG[entityType];
    const entityRef = db().collection(config.collection).doc(entityId);
    const entitySnap = await entityRef.get();

    if (!entitySnap.exists) {
      throw new HttpsError('not-found', `${config.label} not found.`);
    }

    const entity = entitySnap.data();
    const callerUid = request.auth.uid;
    const callerIsAdmin = await isAdmin(callerUid);

    if (!callerIsAdmin && entity.ownerId !== callerUid) {
      throw new HttpsError('permission-denied', 'Only the current owner can transfer ownership.');
    }

    const oldOwnerId = entity.ownerId;
    if (newOwnerId === oldOwnerId) {
      throw new HttpsError('invalid-argument', 'New owner is already the owner.');
    }

    // Locate new owner's current role on the entity
    let newOwnerCurrentField = null;
    for (const field of MEMBER_ROLE_FIELDS) {
      if ((entity[field] ?? []).includes(newOwnerId)) {
        newOwnerCurrentField = field;
        break;
      }
    }
    if (!newOwnerCurrentField) {
      throw new HttpsError(
        'failed-precondition',
        'New owner must already be a member (co-owner, editor, or viewer) of the entity.',
      );
    }

    // Verify the new owner's auth account still exists
    try {
      await admin.auth().getUser(newOwnerId);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        throw new HttpsError('not-found', 'New owner account no longer exists.');
      }
      throw new HttpsError('internal', 'Failed to verify new owner account.');
    }

    const batch = db().batch();

    batch.update(entityRef, {
      ownerId: newOwnerId,
      [newOwnerCurrentField]: FieldValue.arrayRemove(newOwnerId),
      coOwners: FieldValue.arrayUnion(oldOwnerId),
      ownershipTransferredAt: FieldValue.serverTimestamp(),
      ownershipTransferredFrom: oldOwnerId,
    });

    // Old owner is now a co-owner
    batch.set(
      db().collection('users').doc(oldOwnerId),
      { [config.memberField]: { [entityId]: 'co-owner' } },
      { merge: true },
    );

    // New owner no longer carries the previous member-map entry
    batch.update(
      db().collection('users').doc(newOwnerId),
      { [`${config.memberField}.${entityId}`]: FieldValue.delete() },
    );

    await batch.commit();

    await Promise.all([
      syncUserClaimsSafe(oldOwnerId),
      syncUserClaimsSafe(newOwnerId),
    ]);

    return {
      success: true,
      entityId,
      entityType,
      previousOwnerId: oldOwnerId,
      newOwnerId,
    };
  },
);

// ─── deleteUserAccount ────────────────────────────────────────────────────────
// Moved from functions/index.js. Adds:
//   • server-side ownership recheck (rejects if owns-with-members)
//   • confirmDisableOwned gate for solo-owned shops/restaurants
//   • disable + enqueue product-archive Cloud Tasks for solo-owned shops
//   • cancellation of invitations SENT by the user (in addition to received)

export const deleteUserAccount = onCall(
  { region: REGION, timeoutSeconds: 540, memory: '512MiB', maxInstances: 5 },
  async (request) => {
    const { auth, data } = request;

    // === 1) Authentication ===
    if (!auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const callerUid = auth.uid;

    // === 2) Resolve target uid (admin or self) ===
    let targetUid;
    let isAdminDelete = false;
    const confirmDisableOwned = data?.confirmDisableOwned === true;

    if (data?.uid) {
      isAdminDelete = true;
      if (typeof data.uid !== 'string' || !data.uid.trim()) {
        throw new HttpsError('invalid-argument', 'You must provide a valid target uid.');
      }
      if (!await isAdmin(callerUid)) {
        throw new HttpsError('permission-denied', 'Only admins can delete other users.');
      }
      targetUid = data.uid.trim();
      if (targetUid === callerUid) {
        throw new HttpsError('invalid-argument', 'Use self-delete to remove your own account.');
      }
    } else {
      if (typeof data?.email !== 'string' || !data.email.trim()) {
        throw new HttpsError('invalid-argument', 'You must provide your email to confirm deletion.');
      }
      const userRecord = await admin.auth().getUser(callerUid);
      if (userRecord.email?.toLowerCase() !== data.email.trim().toLowerCase()) {
        throw new HttpsError('permission-denied', 'Provided email does not match your account.');
      }
      targetUid = callerUid;
    }

    // === 3) Verify target exists + capture identity for audit ===
    let targetEmail = null;
    let targetDisplayName = null;
    try {
      const targetRecord = await admin.auth().getUser(targetUid);
      targetEmail = targetRecord.email ?? null;
      targetDisplayName = targetRecord.displayName ?? null;
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        throw new HttpsError('not-found', 'Target user account does not exist.');
      }
      throw new HttpsError('internal', 'Failed to verify user account.');
    }

    const userDocRef = db().collection('users').doc(targetUid);
    // Read the user doc once for memberships + audit metadata. Captured up
    // front so the audit row reflects the user's profile even if cleanup
    // partially fails downstream.
    let userData = null;
    try {
      const snap = await userDocRef.get();
      if (snap.exists) userData = snap.data();
    } catch (err) {
      console.warn(`Could not read users/${targetUid}: ${err.message}`);
    }
    if (userData) {
      targetDisplayName = targetDisplayName ||
        userData.displayName || userData.name || userData.fullName || null;
      targetEmail = targetEmail || userData.email || null;
    }

    // === 4) Server-side ownership recheck ===
    const owned = await getOwnedEntities(targetUid);
    const soloOwned = [];
    const ownedWithMembers = [];
    for (const entity of owned) {
      const members = getEntityMembers(entity.data);
      if (members.length === 0) soloOwned.push(entity);
      else ownedWithMembers.push(entity);
    }

    if (ownedWithMembers.length > 0) {
      throw new HttpsError(
        'failed-precondition',
        `Account owns ${ownedWithMembers.length} business(es) with active members. Transfer ownership before deleting.`,
        {
          reason: 'transfer_required',
          ownedWithMembers: ownedWithMembers.map((e) => ({
            id: e.id, type: e.type, name: e.data.name ?? '',
          })),
        },
      );
    }

    if (soloOwned.length > 0 && !confirmDisableOwned) {
      throw new HttpsError(
        'failed-precondition',
        `Account owns ${soloOwned.length} business(es) that will be disabled. Confirmation required.`,
        {
          reason: 'confirmation_required',
          soloOwned: soloOwned.map((e) => ({
            id: e.id, type: e.type, name: e.data.name ?? '',
          })),
        },
      );
    }

    // === 5) Disable solo-owned entities + enqueue product archiving ===
    const archiveTaskNames = []; // captured for the audit row
    let userProductArchiveTaskName = null;
    const cleanupCounts = { bundles: 0, adSubmissions: 0, applications: 0 };
    if (soloOwned.length > 0) {
      // 5a) Disable in one batch — instant for discovery (isActive=false hides them)
      const disableBatch = db().batch();
      for (const entity of soloOwned) {
        disableBatch.update(entity.ref, {
          isActive: false,
          disabledAt: FieldValue.serverTimestamp(),
          disabledReason: 'owner_account_deleted',
          disabledByUid: targetUid,
        });
      }
      try {
        await disableBatch.commit();
        console.log(`✓ Disabled ${soloOwned.length} owned ${soloOwned.length === 1 ? 'entity' : 'entities'} for uid=${targetUid}`);
      } catch (err) {
        // Disable failed — abort before any irreversible step.
        console.error('Failed to disable owned entities:', err);
        throw new HttpsError('internal', 'Failed to disable owned businesses. Please retry.');
      }

      // 5b) Enqueue archive tasks for each solo-owned shop (with retry).
      // Restaurants don't need food archiving — their dishes are not discoverable
      // when the parent restaurant is isActive=false (they load via the restaurant).
      const startedAt = new Date().toISOString();

      for (const entity of soloOwned) {
        if (entity.type !== 'shop') continue;
        try {
          const taskName = await withRetry(
            () => enqueueShopArchiveTask({
              shopId: entity.id,
              deletedUserId: targetUid,
              startedAt,
              cursor: null,
            }),
            { label: `enqueue archive shop=${entity.id}` },
          );
          archiveTaskNames.push({ shopId: entity.id, taskName });
          console.log(`✓ Enqueued archive task for shop ${entity.id}: ${taskName}`);
        } catch (err) {
          console.error(`Could not enqueue archive task for shop ${entity.id} after retries:`, err);

          // Alert ops so the products can be archived manually.
          // The shop is already disabled, so it's hidden from listings — but
          // direct product queries may still surface its products until cleaned.
          try {
            await db().collection('_payment_alerts').add({
              type: 'account_deletion_archive_enqueue_failed',
              severity: 'high',
              shopId: entity.id,
              userId: targetUid,
              isAdminDelete,
              deletedBy: callerUid,
              errorMessage: err.message,
              message: `Could not enqueue product archive for shop ${entity.id} after 3 attempts. Manual archive required.`,
              isRead: false,
              isResolved: false,
              timestamp: FieldValue.serverTimestamp(),
            });
          } catch (_) {/* alerting must never throw */}
        }
      }

      // 5c) Per-shop inline cleanup: delete bundles + ad submissions.
      // Both are scoped by shopId. Counts are low (typically <100 each), so
      // inline batched deletes are safe inside the 540s budget.
      for (const entity of soloOwned) {
        if (entity.type !== 'shop') continue;
        try {
          const bundleCount = await deleteByQuery(
            db().collection('bundles').where('shopId', '==', entity.id),
            `bundles shop=${entity.id}`,
          );
          cleanupCounts.bundles += bundleCount;
          if (bundleCount > 0) console.log(`✓ Deleted ${bundleCount} bundle(s) for shop ${entity.id}`);
        } catch (err) {
          console.warn(`Bundle cleanup failed for shop ${entity.id}: ${err.message}`);
        }

        try {
          const adCount = await deleteByQuery(
            db().collection('ad_submissions').where('shopId', '==', entity.id),
            `ad_submissions shop=${entity.id}`,
          );
          cleanupCounts.adSubmissions += adCount;
          if (adCount > 0) console.log(`✓ Deleted ${adCount} ad submission(s) for shop ${entity.id}`);
        } catch (err) {
          console.warn(`Ad submission cleanup failed for shop ${entity.id}: ${err.message}`);
        }
      }
    }

    // === 5d) Enqueue user-product archive (individual seller listings) ===
    // Runs for every deletion, not just shop owners — any user can have
    // personal listings in `products` (where userId == targetUid). Skipped
    // entirely if no such products exist (one cheap probe read).
    try {
      const probe = await db().collection('products')
        .where('userId', '==', targetUid)
        .limit(1)
        .get();

      if (!probe.empty) {
        const startedAt = new Date().toISOString();
        try {
          userProductArchiveTaskName = await withRetry(
            () => enqueueUserProductArchiveTask({
              deletedUserId: targetUid,
              startedAt,
              cursor: null,
            }),
            { label: `enqueue user-product archive uid=${targetUid}` },
          );
          console.log(`✓ Enqueued user-product archive task for uid=${targetUid}: ${userProductArchiveTaskName}`);
        } catch (err) {
          console.error(`Could not enqueue user-product archive for uid=${targetUid} after retries:`, err);
          try {
            await db().collection('_payment_alerts').add({
              type: 'account_deletion_user_product_archive_enqueue_failed',
              severity: 'high',
              userId: targetUid,
              isAdminDelete,
              deletedBy: callerUid,
              errorMessage: err.message,
              message: `Could not enqueue personal product archive for uid=${targetUid} after 3 attempts. Manual archive required.`,
              isRead: false,
              isResolved: false,
              timestamp: FieldValue.serverTimestamp(),
            });
          } catch (_) {/* alerting must never throw */}
        }
      }
    } catch (err) {
      console.warn(`Probe for user products failed: ${err.message}`);
    }

    // === 6) Membership + invitation cleanup (best-effort) ===
    try {
      if (userData) {
        const cleanupPromises = [];

        // 6a) Strip user from member arrays on shops they belong to (non-owner roles)
        const memberOfShops = userData.memberOfShops ?? {};
        for (const [shopId, role] of Object.entries(memberOfShops)) {
          const field = ROLE_TO_FIELD[role];
          if (field) {
            cleanupPromises.push(
              db().collection('shops').doc(shopId).update({
                [field]: FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from shop ${shopId}: ${err.message}`);
              }),
            );
          }
        }

        const memberOfRestaurants = userData.memberOfRestaurants ?? {};
        for (const [restId, role] of Object.entries(memberOfRestaurants)) {
          const field = ROLE_TO_FIELD[role];
          if (field) {
            cleanupPromises.push(
              db().collection('restaurants').doc(restId).update({
                [field]: FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from restaurant ${restId}: ${err.message}`);
              }),
            );
          }
        }

        // 6b) Cancel pending invitations RECEIVED by the user
        const invCollections = ['shopInvitations', 'restaurantInvitations'];
        const receivedSnaps = await Promise.all(
          invCollections.map((coll) =>
            db().collection(coll)
              .where('userId', '==', targetUid)
              .where('status', '==', 'pending')
              .get(),
          ),
        );
        for (const snapshot of receivedSnaps) {
          for (const doc of snapshot.docs) {
            cleanupPromises.push(
              doc.ref.update({
                status: 'cancelled',
                cancelledAt: FieldValue.serverTimestamp(),
                cancelledReason: 'recipient_account_deleted',
              }).catch((err) => {
                console.warn(`Could not cancel received invitation ${doc.id}: ${err.message}`);
              }),
            );
          }
        }

        // 6c) Cancel pending invitations SENT by the user; flip recipient notifications too.
        const sentSnaps = await Promise.all(
          invCollections.map((coll) =>
            db().collection(coll)
              .where('senderId', '==', targetUid)
              .where('status', '==', 'pending')
              .get(),
          ),
        );
        for (const snapshot of sentSnaps) {
          for (const doc of snapshot.docs) {
            const inv = doc.data();
            cleanupPromises.push((async () => {
              const subBatch = db().batch();
              subBatch.update(doc.ref, {
                status: 'cancelled',
                cancelledAt: FieldValue.serverTimestamp(),
                cancelledReason: 'sender_account_deleted',
              });
              if (inv.notificationId && inv.userId) {
                subBatch.update(
                  db().collection('users').doc(inv.userId)
                    .collection('notifications').doc(inv.notificationId),
                  {
                    status: 'cancelled',
                    processedAt: FieldValue.serverTimestamp(),
                  },
                );
              }
              await subBatch.commit();
            })().catch((err) => {
              console.warn(`Could not cancel sent invitation ${doc.id}: ${err.message}`);
            }));
          }
        }

        if (cleanupPromises.length > 0) {
          await Promise.all(cleanupPromises);
          console.log(`✓ Cleaned ${cleanupPromises.length} membership/invitation references for uid=${targetUid}`);
        }
      }
    } catch (err) {
      console.error('Warning: membership/invitation cleanup failed:', err);
      // Best-effort — never block deletion.
    }

    // === 6d) Delete pending product/edit application docs (4 collections) ===
    // Each pending application is the user's submission for review. Once the
    // user is gone there is nothing to approve, so they are removed entirely
    // (not status-flipped, since the original submitter no longer exists).
    const APPLICATION_COLLECTIONS = [
      'product_applications',
      'product_edit_applications',
      'vitrin_product_applications',
      'vitrin_edit_product_applications',
    ];
    for (const coll of APPLICATION_COLLECTIONS) {
      try {
        const count = await deleteByQuery(
          db().collection(coll)
            .where('userId', '==', targetUid)
            .where('status', '==', 'pending'),
          `applications ${coll}`,
        );
        cleanupCounts.applications += count;
        if (count > 0) console.log(`✓ Deleted ${count} pending ${coll} for uid=${targetUid}`);
      } catch (err) {
        console.warn(`Application cleanup failed for ${coll}: ${err.message}`);
      }
    }

    // === 7) Write audit row BEFORE Auth deletion ===
    // Compliance + debugging trail. Lives in account_deletions/{uid}, a
    // separate collection so the recursive purge of users/{uid} won't touch it.
    // Failure to write the audit row aborts the deletion (the user is intact).
    const auditRef = db().collection(AUDIT_COLLECTION).doc(targetUid);
    try {
      await auditRef.set({
        targetUid,
        email: targetEmail,
        displayName: targetDisplayName,
        isAdminDelete,
        deletedBy: callerUid,
        deletedAt: FieldValue.serverTimestamp(),
        soloOwnedDisabled: soloOwned.map((e) => ({
          id: e.id, type: e.type, name: e.data.name ?? '',
        })),
        archiveTaskNames,
        userProductArchiveTaskName,
        cleanupCounts,
        dataPurgeStatus: 'pending',
        purgeTaskName: null,
        dataPurgedAt: null,
        dataPurgeError: null,
      });
    } catch (err) {
      console.error('Failed to write audit row — aborting deletion:', err);
      throw new HttpsError('internal', 'Failed to record deletion audit entry. Please retry.');
    }

    // === 8) Delete Auth (point of no return for the user) ===
    // Ordering rationale (preserved from original): if Auth succeeds and Firestore
    // fails, the worst outcome is harmless orphaned data. The reverse would let
    // the user log in to a stripped-out account.
    try {
      await admin.auth().deleteUser(targetUid);
      console.log(`✓ Deleted Auth record for uid=${targetUid}`);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        console.log('Auth user was already deleted, continuing with Firestore cleanup');
      } else {
        console.error('Auth deletion failed:', err);
        // Mark audit row as auth_failed and rethrow.
        await auditRef.update({
          dataPurgeStatus: 'auth_failed',
          dataPurgeError: err.message,
        }).catch(() => {});
        throw new HttpsError('internal', 'Failed to delete authentication record.');
      }
    }

    // === 9) Enqueue Firestore purge (with retry → inline fallback) ===
    // Recursive deletes can be slow for users with large subcollections
    // (notifications, orders, etc.). Delegating to Cloud Tasks gives the work
    // its own 540s budget and a retry queue. If enqueue ultimately fails after
    // retries, fall back to inline so we don't strand orphan data on a
    // transient Cloud Tasks outage.
    let purgeStatus = 'queued';
    let purgeTaskName = null;
    let purgeError = null;

    try {
      purgeTaskName = await withRetry(
        () => enqueueAccountPurgeTask({ targetUid, isAdminDelete, deletedBy: callerUid }),
        { label: `enqueue purge uid=${targetUid}` },
      );
      console.log(`✓ Enqueued purge task for uid=${targetUid}: ${purgeTaskName}`);
    } catch (enqueueErr) {
      console.error('Purge enqueue failed after retries — falling back to inline delete:', enqueueErr);
      purgeError = `enqueue: ${enqueueErr.message}`;

      try {
        const docSnapshot = await userDocRef.get();
        if (docSnapshot.exists || await hasSubcollections(userDocRef)) {
          await db().recursiveDelete(userDocRef);
          console.log(`✓ Inline-deleted Firestore data for uid=${targetUid}`);
        }
        purgeStatus = 'inline_complete';
      } catch (inlineErr) {
        console.error('CRITICAL: inline Firestore deletion also failed:', inlineErr);
        purgeStatus = 'failed';
        purgeError = `${purgeError}; inline: ${inlineErr.message}`;

        try {
          await db().collection('_payment_alerts').add({
            type: 'user_deletion_firestore_failed',
            severity: 'high',
            userId: targetUid,
            isAdminDelete,
            deletedBy: callerUid,
            errorMessage: purgeError,
            message: `Auth deleted but neither queued nor inline Firestore cleanup succeeded for ${targetUid}. Manual cleanup required.`,
            isRead: false,
            isResolved: false,
            timestamp: FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
      }
    }

    // === 10) Final audit update with purge outcome ===
    await auditRef.update({
      dataPurgeStatus: purgeStatus,
      purgeTaskName,
      dataPurgeError: purgeError,
      ...(purgeStatus === 'inline_complete' ? { dataPurgedAt: FieldValue.serverTimestamp() } : {}),
    }).catch((err) => {
      console.warn(`Could not update audit row final status: ${err.message}`);
    });

    const partial = purgeStatus === 'failed';
    return {
      success: true,
      partial,
      message: isAdminDelete ?
        (partial ?
          `User account ${targetUid} has been deleted. Some data cleanup is pending.` :
          `User account ${targetUid} has been deleted.`) :
        (partial ?
          'Your account has been deleted. Some data cleanup is pending.' :
          'Your account has been deleted.'),
      deletedUid: targetUid,
      soloOwnedDisabled: soloOwned.length,
      dataPurgeStatus: purgeStatus,
    };
  },
);

// ─── processAccountDeletionShopArchive (Cloud Tasks worker) ───────────────────
// Pages through shop_products for a given shop, archives them via the internal
// helper, and self-enqueues a continuation task while pages remain.
//
// Idempotent: archiveProductInternal is a no-op if the source doc is gone,
// so retried tasks never double-archive. Returning 5xx triggers Cloud Tasks
// backoff retry; 2xx marks the attempt successful.

export const processAccountDeletionShopArchive = onRequest(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 540,
    invoker: 'private',
  },
  async (req, res) => {
    const { shopId, deletedUserId, startedAt, cursor } = req.body || {};

    if (!shopId || !deletedUserId) {
      console.error('[archive-worker] Missing required fields', req.body);
      res.status(400).json({ error: 'Missing shopId or deletedUserId' });
      return;
    }

    try {
      let query = db().collection('shop_products')
        .where('shopId', '==', shopId)
        .orderBy(FieldPath.documentId())
        .limit(ARCHIVE_PAGE_SIZE);

      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snap = await query.get();

      if (snap.empty) {
        console.log(`[archive-worker] shop=${shopId} complete (no more products)`);
        await db().collection('shops').doc(shopId).update({
          productsArchivedAt: FieldValue.serverTimestamp(),
          productsArchiveStatus: 'complete',
        }).catch((e) => console.warn(`Could not mark shop archive status: ${e.message}`));
        res.status(200).json({ success: true, complete: true, shopId, archivedCount: 0 });
        return;
      }

      let archivedCount = 0;
      let skippedCount = 0;
      let failedCount = 0;
      let lastId = cursor;

      for (const doc of snap.docs) {
        try {
          const result = await archiveProductInternal({
            productId: doc.id,
            modifiedBy: deletedUserId,
            sourceCollection: 'shop_products',
            destCollection: 'paused_shop_products',
            ownerField: 'shopId',
            ownerValue: shopId,
          });
          if (result?.archived) archivedCount++;
          else skippedCount++;
        } catch (err) {
          // Continue on per-product failure; the next pass will retry orphans.
          // The product remains in shop_products, so it'll be re-attempted by
          // the continuation. If it fails persistently, ops alert below catches it.
          console.error(`[archive-worker] product ${doc.id} failed: ${err.message}`);
          failedCount++;
        }
        lastId = doc.id;
      }

      const reachedEnd = snap.docs.length < ARCHIVE_PAGE_SIZE;

      console.log(
        `[archive-worker] shop=${shopId} archived=${archivedCount} ` +
        `skipped=${skippedCount} failed=${failedCount} cursor=${lastId} ` +
        `reachedEnd=${reachedEnd}`,
      );

      if (!reachedEnd) {
        // More pages — schedule continuation
        try {
          await enqueueShopArchiveTask({
            shopId,
            deletedUserId,
            startedAt,
            cursor: lastId,
          });
        } catch (enqueueErr) {
          // Returning 5xx makes Cloud Tasks retry the WHOLE current page,
          // which is safe because the helper is idempotent.
          console.error(`[archive-worker] could not enqueue continuation: ${enqueueErr.message}`);
          res.status(500).json({ error: 'continuation enqueue failed', details: enqueueErr.message });
          return;
        }
      } else {
        await db().collection('shops').doc(shopId).update({
          productsArchivedAt: FieldValue.serverTimestamp(),
          productsArchiveStatus: failedCount > 0 ? 'partial' : 'complete',
        }).catch((e) => console.warn(`Could not mark shop archive status: ${e.message}`));

        if (failedCount > 0) {
          try {
            await db().collection('_payment_alerts').add({
              type: 'account_deletion_archive_partial',
              severity: 'medium',
              shopId,
              userId: deletedUserId,
              failedCount,
              message: `Shop ${shopId} archive completed with ${failedCount} product failures. Inspect logs.`,
              isRead: false,
              isResolved: false,
              timestamp: FieldValue.serverTimestamp(),
            });
          } catch (_) {/* alerting must never throw */}
        }
      }

      res.status(200).json({
        success: true,
        complete: reachedEnd,
        shopId,
        archivedCount,
        skippedCount,
        failedCount,
        cursor: lastId,
      });
    } catch (err) {
      // Page-level failure → 5xx triggers Cloud Tasks retry with backoff.
      console.error('[archive-worker] page failed:', err);
      res.status(500).json({ error: err.message });
    }
  },
);

// ─── processAccountDeletionUserProductArchive (Cloud Tasks worker) ────────────
// Same shape as the shop-archive worker, but for individual sellers' personal
// listings: products → paused_products, filtered by userId.

export const processAccountDeletionUserProductArchive = onRequest(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 540,
    invoker: 'private',
  },
  async (req, res) => {
    const { deletedUserId, startedAt, cursor } = req.body || {};

    if (!deletedUserId) {
      console.error('[user-archive-worker] Missing deletedUserId', req.body);
      res.status(400).json({ error: 'Missing deletedUserId' });
      return;
    }

    try {
      let query = db().collection('products')
        .where('userId', '==', deletedUserId)
        .orderBy(FieldPath.documentId())
        .limit(ARCHIVE_PAGE_SIZE);

      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snap = await query.get();

      if (snap.empty) {
        console.log(`[user-archive-worker] uid=${deletedUserId} complete (no more products)`);
        res.status(200).json({ success: true, complete: true, deletedUserId, archivedCount: 0 });
        return;
      }

      let archivedCount = 0;
      let skippedCount = 0;
      let failedCount = 0;
      let lastId = cursor;

      for (const doc of snap.docs) {
        try {
          const result = await archiveProductInternal({
            productId: doc.id,
            modifiedBy: deletedUserId,
            sourceCollection: 'products',
            destCollection: 'paused_products',
            ownerField: 'userId',
            ownerValue: deletedUserId,
          });
          if (result?.archived) archivedCount++;
          else skippedCount++;
        } catch (err) {
          console.error(`[user-archive-worker] product ${doc.id} failed: ${err.message}`);
          failedCount++;
        }
        lastId = doc.id;
      }

      const reachedEnd = snap.docs.length < ARCHIVE_PAGE_SIZE;

      console.log(
        `[user-archive-worker] uid=${deletedUserId} archived=${archivedCount} ` +
        `skipped=${skippedCount} failed=${failedCount} cursor=${lastId} ` +
        `reachedEnd=${reachedEnd}`,
      );

      if (!reachedEnd) {
        try {
          await enqueueUserProductArchiveTask({
            deletedUserId,
            startedAt,
            cursor: lastId,
          });
        } catch (enqueueErr) {
          console.error(`[user-archive-worker] continuation enqueue failed: ${enqueueErr.message}`);
          res.status(500).json({ error: 'continuation enqueue failed', details: enqueueErr.message });
          return;
        }
      } else if (failedCount > 0) {
        try {
          await db().collection('_payment_alerts').add({
            type: 'account_deletion_user_product_archive_partial',
            severity: 'medium',
            userId: deletedUserId,
            failedCount,
            message: `User ${deletedUserId} product archive completed with ${failedCount} failures. Inspect logs.`,
            isRead: false,
            isResolved: false,
            timestamp: FieldValue.serverTimestamp(),
          });
        } catch (_) {/* alerting must never throw */}
      }

      res.status(200).json({
        success: true,
        complete: reachedEnd,
        deletedUserId,
        archivedCount,
        skippedCount,
        failedCount,
        cursor: lastId,
      });
    } catch (err) {
      console.error('[user-archive-worker] page failed:', err);
      res.status(500).json({ error: err.message });
    }
  },
);

// ─── processAccountDataPurge (Cloud Tasks worker) ─────────────────────────────
// Recursively deletes users/{targetUid} and all subcollections via the Admin
// SDK's BulkWriter-backed recursiveDelete. Runs in its own 540s budget so
// large users (many notifications/orders/etc.) don't pressure deleteUserAccount.
//
// Idempotent: recursiveDelete on an empty/missing tree is a no-op, so Cloud
// Tasks retries are safe. On failure, returns 5xx for backoff retry; persistent
// failures eventually move to the queue's dead-letter handling and the audit
// row records the error.

export const processAccountDataPurge = onRequest(
  {
    region: REGION,
    memory: '1GiB', // BulkWriter buffers in memory; bump for large purges
    timeoutSeconds: 540,
    invoker: 'private',
  },
  async (req, res) => {
    const { targetUid, isAdminDelete, deletedBy } = req.body || {};

    if (!targetUid || typeof targetUid !== 'string') {
      console.error('[purge-worker] Missing targetUid', req.body);
      res.status(400).json({ error: 'Missing targetUid' });
      return;
    }

    const auditRef = db().collection(AUDIT_COLLECTION).doc(targetUid);
    const userDocRef = db().collection('users').doc(targetUid);

    // Mark in-flight (best-effort — don't fail the purge over an audit blip)
    await auditRef.update({ dataPurgeStatus: 'running' }).catch((e) => {
      console.warn(`[purge-worker] could not mark audit running: ${e.message}`);
    });

    try {
      const docSnapshot = await userDocRef.get();
      if (docSnapshot.exists || await hasSubcollections(userDocRef)) {
        await db().recursiveDelete(userDocRef);
        console.log(`✓ [purge-worker] Deleted Firestore data for uid=${targetUid}`);
      } else {
        console.log(`[purge-worker] No Firestore data for uid=${targetUid} — already clean`);
      }

      await auditRef.update({
        dataPurgeStatus: 'complete',
        dataPurgedAt: FieldValue.serverTimestamp(),
        dataPurgeError: null,
      }).catch((e) => {
        console.warn(`[purge-worker] could not finalize audit row: ${e.message}`);
      });

      res.status(200).json({ success: true, targetUid });
    } catch (err) {
      console.error(`[purge-worker] Recursive delete failed for uid=${targetUid}:`, err);

      // Record the latest error on the audit row, but DO NOT mark 'failed' yet —
      // Cloud Tasks will retry with backoff. The audit only flips to 'failed'
      // after the queue exhausts retries (operator manually inspects).
      await auditRef.update({
        dataPurgeError: err.message,
      }).catch(() => {});

      // Alert ops at the first failure; later retries will overwrite the same
      // alert is acceptable (high signal, low volume).
      try {
        await db().collection('_payment_alerts').add({
          type: 'user_deletion_purge_attempt_failed',
          severity: 'medium',
          userId: targetUid,
          isAdminDelete: isAdminDelete === true,
          deletedBy: deletedBy ?? null,
          errorMessage: err.message,
          message: `Purge attempt failed for ${targetUid} — Cloud Tasks will retry. Inspect if alerts repeat.`,
          isRead: false,
          isResolved: false,
          timestamp: FieldValue.serverTimestamp(),
        });
      } catch (_) {/* alerting must never throw */}

      // 5xx triggers Cloud Tasks backoff retry.
      res.status(500).json({ error: err.message });
    }
  },
);
