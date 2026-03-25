// functions/src/setMasterCourierClaim.js
//
// ES6 module — deploy alongside your other functions.
// Manages the `masterCourier` custom claim + mirrors it on the Firestore user doc.

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

// ─── Helper: verify caller is an admin ───────────────────────────────────────

async function assertAdmin(uid) {
  const record = await admin.auth().getUser(uid);
  if (record.customClaims?.isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Only admins can manage master couriers.');
  }
}

// ─── setMasterCourierClaim ────────────────────────────────────────────────────
//
// Request payload:
//   { userId: string, value: boolean }
//
// - Merges `masterCourier` into existing custom claims (preserves isAdmin, shops, etc.)
// - Mirrors `masterCourier` on the Firestore `users/{userId}` document

export const setMasterCourierClaim = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    await assertAdmin(request.auth.uid);

    const { userId, value } = request.data;

    if (!userId || typeof userId !== 'string') {
      throw new HttpsError('invalid-argument', 'userId is required.');
    }
    if (typeof value !== 'boolean') {
      throw new HttpsError('invalid-argument', 'value must be a boolean.');
    }

    // ── 1. Fetch target user ────────────────────────────────────────────────
    let targetRecord;
    try {
      targetRecord = await admin.auth().getUser(userId);
    } catch {
      throw new HttpsError('not-found', 'User not found in Firebase Auth.');
    }

    // ── 2. Merge claim — preserve everything else ───────────────────────────
    const existingClaims = targetRecord.customClaims ?? {};
    const updatedClaims = {
      ...existingClaims,
      masterCourier: value,
    };

    // If revoking, remove the key entirely rather than setting false
    if (!value) {
      delete updatedClaims.masterCourier;
    }

    await admin.auth().setCustomUserClaims(userId, updatedClaims);

    // ── 3. Mirror on Firestore user doc ─────────────────────────────────────
    const db = admin.firestore();
    await db
      .collection('users')
      .doc(userId)
      .set(
        { masterCourier: value || admin.firestore.FieldValue.delete() },
        { merge: true },
      );

    console.log(
      `[MasterCourier] ${value ? 'Granted' : 'Revoked'} masterCourier claim for uid=${userId} by admin=${request.auth.uid}`,
    );

    return {
      success: true,
      userId,
      masterCourier: value,
      displayName: targetRecord.displayName ?? targetRecord.email ?? userId,
    };
  },
);
