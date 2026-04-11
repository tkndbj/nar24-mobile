import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

let _db;
const db = () => _db ?? (_db = admin.firestore());

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = 'europe-west3';
const FUNCTION_CONFIG = { region: REGION, maxInstances: 10 };

const VALID_INVITE_ROLES = ['co-owner', 'editor', 'viewer'];

const ROLE_TO_FIELD = {
  'co-owner': 'coOwners',
  'editor': 'editors',
  'viewer': 'viewers',
};

// ─── Business-type config ─────────────────────────────────────────────────────

const ENTITY_CONFIG = {
  shop: {
    entityCollection: 'shops',
    invitationsCollection: 'shopInvitations',
    memberField: 'memberOfShops',
    notificationType: 'shop_invitation',
    entityLabel: 'Shop',
  },
  restaurant: {
    entityCollection: 'restaurants',
    invitationsCollection: 'restaurantInvitations',
    memberField: 'memberOfRestaurants',
    notificationType: 'restaurant_invitation',
    entityLabel: 'Restaurant',
  },
};

function getEntityConfig(businessType) {
  if (businessType === 'restaurant') return ENTITY_CONFIG.restaurant;
  return ENTITY_CONFIG.shop;
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

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

  const payloadSize = new TextEncoder().encode(JSON.stringify(newClaims)).length;

  console.log(`[syncUserClaims] uid=${uid}`);
  console.log(`[syncUserClaims] BEFORE: ${JSON.stringify(existingClaims)}`);
  console.log(`[syncUserClaims] AFTER:  ${JSON.stringify(newClaims)}`);
  console.log(`[syncUserClaims] Payload size: ${payloadSize} bytes`);

  if (payloadSize > 900) {
    console.error(`[syncUserClaims] WARNING: payload is ${payloadSize}/1000 bytes for uid=${uid} — risk of silent claim loss!`);
  }

  await admin.auth().setCustomUserClaims(uid, newClaims);
  
  // Verify the write
  const verifyRecord = await admin.auth().getUser(uid);
  const verifyClaims = verifyRecord.customClaims ?? {};
  
  const lostKeys = Object.keys(newClaims).filter((k) => !(k in verifyClaims));
  if (lostKeys.length > 0) {
    console.error(`[syncUserClaims] CLAIMS LOST after write for uid=${uid}: ${lostKeys.join(', ')}`);
  } else {
    console.log(`[syncUserClaims] Verified OK for uid=${uid}`);
  }
}

async function syncUserClaimsSafe(uid) {
  try {
    await syncUserClaims(uid);
  } catch (err) {
    console.error(`[syncUserClaims] Failed for uid=${uid}:`, err);

    // Queue for the backfillShopClaims job to pick up
    try {
      await db().collection('claimsSyncQueue').add({
        uid,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
        error: err?.message ?? 'unknown',
        retryCount: 0,
      });
    } catch (queueErr) {
      // Last resort — at minimum it's in Cloud Logging
      console.error(`[syncUserClaims] Also failed to queue retry for uid=${uid}:`, queueErr);
    }

    // Do NOT rethrow — Firestore is consistent, claims sync is eventual
  }
}

async function isAdmin(uid) {
  const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
  return claims.isAdmin === true;
}

async function assertOwnerOrCoOwner(requesterId, entityId, entityCollection, entityLabel) {
  const snap = await db().collection(entityCollection).doc(entityId).get();

  if (!snap.exists) {
    throw new HttpsError('not-found', `${entityLabel} not found`);
  }

  const entity = snap.data();

  if (entity.ownerId === requesterId) return 'owner';
  if ((entity.coOwners ?? []).includes(requesterId)) return 'co-owner';

  throw new HttpsError(
    'permission-denied',
    `Only owners and co-owners can manage ${entityLabel.toLowerCase()} access`,
  );
}

// ─── sendShopInvitation ───────────────────────────────────────────────────────

export const sendShopInvitation = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { shopId, inviteeEmail, role, businessType } = request.data;

  if (!shopId || !inviteeEmail || !role) {
    throw new HttpsError('invalid-argument', 'shopId, inviteeEmail and role are required');
  }

  if (!VALID_INVITE_ROLES.includes(role)) {
    throw new HttpsError('invalid-argument', `Role must be one of: ${VALID_INVITE_ROLES.join(', ')}`);
  }

  const config = getEntityConfig(businessType);

  const requesterIsAdmin = await isAdmin(request.auth.uid);

if (!requesterIsAdmin) {
  await assertOwnerOrCoOwner(request.auth.uid, shopId, config.entityCollection, config.entityLabel);
}

  const inviteeQuery = await db()
    .collection('users')
    .where('email', '==', inviteeEmail.trim().toLowerCase())
    .limit(1)
    .get();

  if (inviteeQuery.empty) {
    throw new HttpsError('not-found', 'No account found with that email address');
  }

  const inviteeId = inviteeQuery.docs[0].id;

  if (!requesterIsAdmin && inviteeId === request.auth.uid) {
    throw new HttpsError('invalid-argument', 'You cannot invite yourself');
  }

  const existing = await db()
    .collection(config.invitationsCollection)
    .where('shopId', '==', shopId)
    .where('userId', '==', inviteeId)
    .where('status', '==', 'pending')
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new HttpsError('already-exists', 'A pending invitation already exists for this user');
  }

  const entitySnap = await db().collection(config.entityCollection).doc(shopId).get();
  const entityData = entitySnap.data();

  const alreadyMember =
    entityData.ownerId === inviteeId ||
    (entityData.coOwners ?? []).includes(inviteeId) ||
    (entityData.editors ?? []).includes(inviteeId) ||
    (entityData.viewers ?? []).includes(inviteeId);

  if (alreadyMember) {
    throw new HttpsError('already-exists', `User is already a member of this ${config.entityLabel.toLowerCase()}`);
  }

  const invitationRef = db().collection(config.invitationsCollection).doc();
  const notificationRef = db()
    .collection('users')
    .doc(inviteeId)
    .collection('notifications')
    .doc();

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db().batch();

  batch.set(invitationRef, {
    userId: inviteeId,
    shopId,
    shopName: entityData.name ?? '',
    role,
    senderId: request.auth.uid,
    email: inviteeEmail.trim().toLowerCase(),
    notificationId: notificationRef.id,
    status: 'pending',
    businessType: businessType ?? 'shop',
    timestamp: now,
  });

  batch.set(notificationRef, {
    userId: inviteeId,
    type: config.notificationType,
    shopId,
    shopName: entityData.name ?? '',
    role,
    senderId: request.auth.uid,
    invitationId: invitationRef.id,
    status: 'pending',
    isRead: false,
    businessType: businessType ?? 'shop',
    timestamp: now,
    message_en: `You have been invited to join ${entityData.name ?? `a ${config.entityLabel.toLowerCase()}`} as ${role}.`,
    message_tr: `${entityData.name ?? `Bir ${config.entityLabel.toLowerCase()}`} katılmaya davet edildiniz (${role}).`,
    message_ru: `Вас пригласили присоединиться к ${entityData.name ?? config.entityLabel.toLowerCase()} как ${role}.`,
  });

  await batch.commit();

  return { success: true, invitationId: invitationRef.id };
});

// ─── handleShopInvitation ─────────────────────────────────────────────────────

export const handleShopInvitation = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { invitationId, accepted } = request.data;

  if (!invitationId || accepted === undefined) {
    throw new HttpsError('invalid-argument', 'invitationId and accepted are required');
  }

  const userId = request.auth.uid;

  let invitationRef = db().collection('shopInvitations').doc(invitationId);
  let invitationSnap = await invitationRef.get();

  if (!invitationSnap.exists) {
    invitationRef = db().collection('restaurantInvitations').doc(invitationId);
    invitationSnap = await invitationRef.get();
  }

  if (!invitationSnap.exists) {
    throw new HttpsError('not-found', 'Invitation not found');
  }

  const invitation = invitationSnap.data();

  if (invitation.userId !== userId) {
    throw new HttpsError('permission-denied', 'This invitation does not belong to you');
  }

  if (invitation.status !== 'pending') {
    throw new HttpsError('failed-precondition', 'This invitation has already been processed');
  }

  const { shopId, role, notificationId } = invitation;
  const config = getEntityConfig(invitation.businessType);

  const roleField = ROLE_TO_FIELD[role];
  if (!roleField) {
    throw new HttpsError('internal', 'Invalid role stored in invitation');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db().batch();

  if (accepted) {
    const entitySnap = await db().collection(config.entityCollection).doc(shopId).get();

    if (!entitySnap.exists) {
      throw new HttpsError('not-found', `${config.entityLabel} no longer exists`);
    }

    batch.update(db().collection(config.entityCollection).doc(shopId), {
      [roleField]: admin.firestore.FieldValue.arrayUnion(userId),
    });

    batch.set(
      db().collection('users').doc(userId),
      { [config.memberField]: { [shopId]: role } },
      { merge: true },
    );

    batch.update(invitationRef, { status: 'accepted', acceptedAt: now });

    if (notificationId) {
      batch.update(
        db().collection('users').doc(userId).collection('notifications').doc(notificationId),
        { status: 'accepted', processedAt: now },
      );
    }

    await batch.commit();
    await syncUserClaimsSafe(userId);
  } else {
    batch.update(invitationRef, { status: 'rejected', rejectedAt: now });

    if (notificationId) {
      batch.update(
        db().collection('users').doc(userId).collection('notifications').doc(notificationId),
        { status: 'rejected', processedAt: now },
      );
    }

    await batch.commit();
  }

  return {
    success: true,
    accepted,
    shopId,
    businessType: config === ENTITY_CONFIG.restaurant ? 'restaurant' : 'shop',
    shouldRefreshToken: accepted,
  };
});

// ─── revokeShopAccess ─────────────────────────────────────────────────────────

export const revokeShopAccess = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { targetUserId, shopId, role, businessType } = request.data;

  if (!targetUserId || !shopId || !role) {
    throw new HttpsError('invalid-argument', 'targetUserId, shopId and role are required');
  }

  if (role === 'owner') {
    throw new HttpsError('invalid-argument', 'Cannot revoke the owner');
  }

  const roleField = ROLE_TO_FIELD[role];
  if (!roleField) {
    throw new HttpsError('invalid-argument', 'Invalid role');
  }

  const config = getEntityConfig(businessType);
  const requesterIsAdmin = await isAdmin(request.auth.uid);

  const requesterRole = requesterIsAdmin ?
    'owner' : // treat admin as owner for permission purposes
    await assertOwnerOrCoOwner(
        request.auth.uid,
        shopId,
        config.entityCollection,
        config.entityLabel,
      );
  
  if (!requesterIsAdmin && requesterRole === 'co-owner' && role === 'co-owner') {
    throw new HttpsError('permission-denied', 'Co-owners cannot revoke other co-owners');
  }

  if (!requesterIsAdmin && targetUserId === request.auth.uid) {
    throw new HttpsError('invalid-argument', 'Use the leaveShop endpoint to remove yourself');
  }

  const batch = db().batch();

  batch.update(db().collection(config.entityCollection).doc(shopId), {
    [roleField]: admin.firestore.FieldValue.arrayRemove(targetUserId),
  });

  batch.update(db().collection('users').doc(targetUserId), {
    [`${config.memberField}.${shopId}`]: admin.firestore.FieldValue.delete(),
  });

  await batch.commit();
  await syncUserClaimsSafe(targetUserId);

  return { success: true, message: 'Access revoked successfully' };
});

// ─── leaveShop ────────────────────────────────────────────────────────────────

export const leaveShop = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { shopId, businessType } = request.data;

  if (!shopId) {
    throw new HttpsError('invalid-argument', 'shopId is required');
  }

  const config = getEntityConfig(businessType);
  const userId = request.auth.uid;

  const entitySnap = await db().collection(config.entityCollection).doc(shopId).get();

  if (!entitySnap.exists) {
    throw new HttpsError('not-found', `${config.entityLabel} not found`);
  }

  const entityData = entitySnap.data();

  if (entityData.ownerId === userId) {
    throw new HttpsError(
      'failed-precondition',
      `Owners cannot leave their own ${config.entityLabel.toLowerCase()}. Transfer ownership first.`,
    );
  }

  let roleField = null;
  if ((entityData.coOwners ?? []).includes(userId)) roleField = 'coOwners';
  else if ((entityData.editors ?? []).includes(userId)) roleField = 'editors';
  else if ((entityData.viewers ?? []).includes(userId)) roleField = 'viewers';

  if (!roleField) {
    throw new HttpsError('not-found', `You are not a member of this ${config.entityLabel.toLowerCase()}`);
  }

  const batch = db().batch();

  batch.update(db().collection(config.entityCollection).doc(shopId), {
    [roleField]: admin.firestore.FieldValue.arrayRemove(userId),
  });

  batch.update(db().collection('users').doc(userId), {
    [`${config.memberField}.${shopId}`]: admin.firestore.FieldValue.delete(),
  });

  await batch.commit();
  await syncUserClaimsSafe(userId);

  return { success: true };
});

// ─── cancelShopInvitation ─────────────────────────────────────────────────────

export const cancelShopInvitation = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { invitationId } = request.data;

  if (!invitationId) {
    throw new HttpsError('invalid-argument', 'invitationId is required');
  }

  let invitationDocRef = db().collection('shopInvitations').doc(invitationId);
  let invitationSnap = await invitationDocRef.get();

  if (!invitationSnap.exists) {
    invitationDocRef = db().collection('restaurantInvitations').doc(invitationId);
    invitationSnap = await invitationDocRef.get();
  }

  if (!invitationSnap.exists) {
    throw new HttpsError('not-found', 'Invitation not found');
  }

  const invitation = invitationSnap.data();

  if (invitation.status !== 'pending') {
    throw new HttpsError('failed-precondition', 'Only pending invitations can be cancelled');
  }

  const config = getEntityConfig(invitation.businessType);

  const requesterIsAdmin = await isAdmin(request.auth.uid);

if (!requesterIsAdmin) {
  await assertOwnerOrCoOwner(
    request.auth.uid,
    invitation.shopId,
    config.entityCollection,
    config.entityLabel,
  );
}

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db().batch();

  batch.update(invitationDocRef, {
    status: 'cancelled',
    cancelledAt: now,
  });

  if (invitation.notificationId && invitation.userId) {
    batch.update(
      db().collection('users').doc(invitation.userId).collection('notifications').doc(invitation.notificationId),
      { status: 'cancelled', processedAt: now },
    );
  }

  await batch.commit();

  return { success: true };
});

// ─── backfillShopClaims ───────────────────────────────────────────────────────

export const backfillShopClaims = onRequest(
  { ...FUNCTION_CONFIG, invoker: 'private' },
  async (req, res) => {
  const usersSnap = await db().collection('users').get();

  let synced = 0;
  let skipped = 0;
  let errors = 0;

  for (const doc of usersSnap.docs) {
    const data = doc.data();
    if (data.memberOfShops || data.memberOfRestaurants) {
      try {
        await syncUserClaims(doc.id);
        synced++;
      } catch (err) {
        console.warn(`Skipping ${doc.id}: ${err.message}`);
        errors++;
      }
    } else {
      skipped++;
    }
  }

  res.json({ success: true, synced, skipped, errors });
});

export const setAdminClaim = onRequest({ invoker: 'private' }, async (req, res) => {
  const uid = 'AUt9QlHVEFXy8PCGQ1wPxsd7dFW2';
  const existing = (await admin.auth().getUser(uid)).customClaims ?? {};
  await admin.auth().setCustomUserClaims(uid, {
    ...existing,
    isAdmin: true,
  });
  res.json({ success: true, claims: { ...existing, isAdmin: true } });
});
