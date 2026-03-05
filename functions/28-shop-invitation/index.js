import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

let _db;
const db = () => _db ?? (_db = admin.firestore());

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = 'europe-west3';
const FUNCTION_CONFIG = { region: REGION, maxInstances: 10 };

const VALID_INVITE_ROLES = ['co-owner', 'editor', 'viewer'];

/**
 * Maps a role string to the Firestore array field name on the shop document.
 * Centralised here so it's impossible for callers to get it wrong.
 */
const ROLE_TO_FIELD = {
  'co-owner': 'coOwners',
  'editor': 'editors',
  'viewer': 'viewers',
};

// ─── Internal helpers ─────────────────────────────────────────────────────────

async function syncUserClaims(uid) {
  const userSnap = await db().doc(`users/${uid}`).get();
  const data = userSnap.data() ?? {};

  await admin.auth().setCustomUserClaims(uid, {
    shops: data.memberOfShops ?? {},
    restaurants: data.memberOfRestaurants ?? {},
  });
}

async function assertOwnerOrCoOwner(requesterId, shopId) {
  const shopSnap = await db().collection('shops').doc(shopId).get();

  if (!shopSnap.exists) {
    throw new HttpsError('not-found', 'Shop not found');
  }

  const shop = shopSnap.data();

  if (shop.ownerId === requesterId) return 'owner';
  if ((shop.coOwners ?? []).includes(requesterId)) return 'co-owner';

  throw new HttpsError(
    'permission-denied',
    'Only owners and co-owners can manage shop access',
  );
}

// ─── sendShopInvitation ───────────────────────────────────────────────────────

export const sendShopInvitation = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { shopId, inviteeEmail, role } = request.data;

  if (!shopId || !inviteeEmail || !role) {
    throw new HttpsError('invalid-argument', 'shopId, inviteeEmail and role are required');
  }

  if (!VALID_INVITE_ROLES.includes(role)) {
    throw new HttpsError('invalid-argument', `Role must be one of: ${VALID_INVITE_ROLES.join(', ')}`);
  }

  // Verify sender has permission
  await assertOwnerOrCoOwner(request.auth.uid, shopId);

  // Look up invitee by email server-side (avoids exposing UIDs to clients)
  const inviteeQuery = await db()
    .collection('users')
    .where('email', '==', inviteeEmail.trim().toLowerCase())
    .limit(1)
    .get();

  if (inviteeQuery.empty) {
    throw new HttpsError('not-found', 'No account found with that email address');
  }

  const inviteeId = inviteeQuery.docs[0].id;

  if (inviteeId === request.auth.uid) {
    throw new HttpsError('invalid-argument', 'You cannot invite yourself');
  }

  // Check for existing pending invitation
  const existing = await db()
    .collection('shopInvitations')
    .where('shopId', '==', shopId)
    .where('userId', '==', inviteeId)
    .where('status', '==', 'pending')
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new HttpsError('already-exists', 'A pending invitation already exists for this user');
  }

  // Check if user is already a member
  const shopSnap = await db().collection('shops').doc(shopId).get();
  const shopData = shopSnap.data();
  const alreadyMember =
    shopData.ownerId === inviteeId ||
    (shopData.coOwners ?? []).includes(inviteeId) ||
    (shopData.editors ?? []).includes(inviteeId) ||
    (shopData.viewers ?? []).includes(inviteeId);

  if (alreadyMember) {
    throw new HttpsError('already-exists', 'User is already a member of this shop');
  }

  // Pre-allocate both doc refs so we can cross-link them atomically
  const invitationRef = db().collection('shopInvitations').doc();
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
    shopName: shopData.name ?? '',
    role,
    senderId: request.auth.uid,
    email: inviteeEmail.trim().toLowerCase(),
    notificationId: notificationRef.id, // O(1) link for cancel/cleanup
    status: 'pending',
    timestamp: now,
  });

  batch.set(notificationRef, {
    userId: inviteeId,
    type: 'shop_invitation',
    shopId,
    shopName: shopData.name ?? '',
    role,
    senderId: request.auth.uid,
    invitationId: invitationRef.id, // O(1) link for accept/reject
    status: 'pending',
    isRead: false,
    timestamp: now,
    message_en: `You have been invited to join ${shopData.name ?? 'a shop'} as ${role}.`,
    message_tr: `${shopData.name ?? 'Bir mağazaya'} katılmaya davet edildiniz (${role}).`,
    message_ru: `Вас пригласили присоединиться к ${shopData.name ?? 'магазину'} как ${role}.`,
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

  // O(1) direct doc fetch — no collection query needed
  const invitationRef = db().collection('shopInvitations').doc(invitationId);
  const invitationSnap = await invitationRef.get();

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
  const roleField = ROLE_TO_FIELD[role];

  if (!roleField) {
    throw new HttpsError('internal', 'Invalid role stored in invitation');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db().batch();

  if (accepted) {
    const shopSnap = await db().collection('shops').doc(shopId).get();
    if (!shopSnap.exists) {
      throw new HttpsError('not-found', 'Shop no longer exists');
    }

    // 1. Add user to shop role array
    batch.update(db().collection('shops').doc(shopId), {
      [roleField]: admin.firestore.FieldValue.arrayUnion(userId),
    });

    // 2. Add shop to user's memberOfShops (merge so other shops are untouched)
    batch.set(
      db().collection('users').doc(userId),
      { memberOfShops: { [shopId]: role } },
      { merge: true },
    );

    // 3. Mark invitation accepted
    batch.update(invitationRef, { status: 'accepted', acceptedAt: now });

    // 4. Update linked notification — O(1) via stored notificationId
    if (notificationId) {
      batch.update(
        db().collection('users').doc(userId).collection('notifications').doc(notificationId),
        { status: 'accepted', processedAt: now },
      );
    }

    await batch.commit();

    // Sync custom claims AFTER the write so user doc is already updated
    await syncUserClaims(userId);
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
    shouldRefreshToken: accepted, // tells client to call user.getIdToken(true)
  };
});

// ─── revokeShopAccess ─────────────────────────────────────────────────────────

export const revokeShopAccess = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { targetUserId, shopId, role } = request.data;

  if (!targetUserId || !shopId || !role) {
    throw new HttpsError('invalid-argument', 'targetUserId, shopId and role are required');
  }

  if (role === 'owner') {
    throw new HttpsError('invalid-argument', 'Cannot revoke the shop owner');
  }

  const roleField = ROLE_TO_FIELD[role];
  if (!roleField) {
    throw new HttpsError('invalid-argument', 'Invalid role');
  }

  const requesterRole = await assertOwnerOrCoOwner(request.auth.uid, shopId);

  // Co-owners can only manage editors and viewers — not other co-owners
  if (requesterRole === 'co-owner' && role === 'co-owner') {
    throw new HttpsError('permission-denied', 'Co-owners cannot revoke other co-owners');
  }

  if (targetUserId === request.auth.uid) {
    throw new HttpsError('invalid-argument', 'Use the leaveShop endpoint to remove yourself');
  }

  const batch = db().batch();

  // 1. Remove from shop role array
  batch.update(db().collection('shops').doc(shopId), {
    [roleField]: admin.firestore.FieldValue.arrayRemove(targetUserId),
  });

  // 2. Remove shop from user's memberOfShops — deleteField avoids a read
  batch.update(db().collection('users').doc(targetUserId), {
    [`memberOfShops.${shopId}`]: admin.firestore.FieldValue.delete(),
  });

  await batch.commit();

  // Sync claims for the affected user
  await syncUserClaims(targetUserId);

  return { success: true, message: 'Access revoked successfully' };
});

// ─── leaveShop ────────────────────────────────────────────────────────────────

export const leaveShop = onCall(FUNCTION_CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { shopId } = request.data;
  if (!shopId) {
    throw new HttpsError('invalid-argument', 'shopId is required');
  }

  const userId = request.auth.uid;
  const shopSnap = await db().collection('shops').doc(shopId).get();

  if (!shopSnap.exists) {
    throw new HttpsError('not-found', 'Shop not found');
  }

  const shopData = shopSnap.data();

  if (shopData.ownerId === userId) {
    throw new HttpsError(
      'failed-precondition',
      'Owners cannot leave their own shop. Transfer ownership first.',
    );
  }

  let roleField = null;
  if ((shopData.coOwners ?? []).includes(userId)) roleField = 'coOwners';
  else if ((shopData.editors ?? []).includes(userId)) roleField = 'editors';
  else if ((shopData.viewers ?? []).includes(userId)) roleField = 'viewers';

  if (!roleField) {
    throw new HttpsError('not-found', 'You are not a member of this shop');
  }

  const batch = db().batch();

  batch.update(db().collection('shops').doc(shopId), {
    [roleField]: admin.firestore.FieldValue.arrayRemove(userId),
  });

  batch.update(db().collection('users').doc(userId), {
    [`memberOfShops.${shopId}`]: admin.firestore.FieldValue.delete(),
  });

  await batch.commit();
  await syncUserClaims(userId);

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

  const invitationSnap = await db().collection('shopInvitations').doc(invitationId).get();

  if (!invitationSnap.exists) {
    throw new HttpsError('not-found', 'Invitation not found');
  }

  const invitation = invitationSnap.data();

  if (invitation.status !== 'pending') {
    throw new HttpsError('failed-precondition', 'Only pending invitations can be cancelled');
  }

  await assertOwnerOrCoOwner(request.auth.uid, invitation.shopId);

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db().batch();

  batch.update(db().collection('shopInvitations').doc(invitationId), {
    status: 'cancelled',
    cancelledAt: now,
  });

  // Update the linked in-app notification if cross-linked
  if (invitation.notificationId && invitation.userId) {
    batch.update(
      db().collection('users').doc(invitation.userId).collection('notifications').doc(invitation.notificationId),
      { status: 'cancelled', processedAt: now },
    );
  }

  await batch.commit();

  return { success: true };
});

export const backfillShopClaims = onRequest(FUNCTION_CONFIG, async (req, res) => {
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

  export const setAdminClaim = onRequest(async (req, res) => {
    await admin.auth().setCustomUserClaims('AUt9QlHVEFXy8PCGQ1wPxsd7dFW2', {
      isAdmin: true,
    });
    res.json({ success: true });
  });

