import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

// ─────────────────────────────────────────────────────────────────────────────
// CREATE TEST COURIERS
// ─────────────────────────────────────────────────────────────────────────────

export const createTestCouriers = onCall({
  region: 'europe-west3',
  maxInstances: 5,
  timeoutSeconds: 120,
  memory: '256MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const adminId = request.auth.uid;
  const db = getFirestore();
  const auth = getAuth();

  // Verify caller is admin
  const adminDoc = await db.collection('users').doc(adminId).get();
  if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Only admins can create test couriers');
  }

  const { count = 10, prefix = 'courier' } = request.data || {};

  // Validate
  const courierCount = Math.min(Math.max(1, Number(count) || 10), 50); // 1–50
  const safePrefix = String(prefix).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 20) || 'courier';

  const created = [];
  const skipped = [];
  const errors = [];

  for (let i = 1; i <= courierCount; i++) {
    const email = `${safePrefix}${i}@test.local`;
    const displayName = `Test Kurye ${i}`;
    const password = 'Test123456';

    try {
      // Check if user already exists
      let user;
      try {
        user = await auth.getUserByEmail(email);
        skipped.push({ email, uid: user.uid, reason: 'already_exists' });
        continue;
      } catch (lookupErr) {
        if (lookupErr.code !== 'auth/user-not-found') {
          throw lookupErr;
        }
      }

      // Create auth user
      user = await auth.createUser({
        email,
        password,
        displayName,
        emailVerified: true,
      });

      // Set custom claims
      const existingClaims = user.customClaims ?? {};
      await auth.setCustomUserClaims(user.uid, {
        ...existingClaims,
        foodcargoguy: true,
      });

      // Create Firestore profile
      await db.collection('users').doc(user.uid).set({
        email,
        displayName,
        name: displayName,
        foodcargoguy: true,
        isTestAccount: true,
        testAccountPrefix: safePrefix,
        createdAt: FieldValue.serverTimestamp(),
        createdByAdmin: adminId,
      });

      created.push({ email, uid: user.uid, displayName });
      console.log(`✅ Created ${email} (${user.uid})`);
    } catch (err) {
      console.error(`❌ Failed to create ${email}:`, err.message);
      errors.push({ email, error: err.message });
    }
  }

  // Audit log
  await db.collection('admin_audit_logs').add({
    action: 'TEST_COURIERS_CREATED',
    adminId,
    adminEmail: adminDoc.data()?.email || 'unknown',
    prefix: safePrefix,
    requestedCount: courierCount,
    createdCount: created.length,
    skippedCount: skipped.length,
    errorCount: errors.length,
    timestamp: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    created: created.length,
    skipped: skipped.length,
    errors: errors.length,
    accounts: created,
    skippedAccounts: skipped,
    failedAccounts: errors,
    password: 'Test123456',
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE TEST COURIERS
// ─────────────────────────────────────────────────────────────────────────────

export const deleteTestCouriers = onCall({
  region: 'europe-west3',
  maxInstances: 5,
  timeoutSeconds: 120,
  memory: '256MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const adminId = request.auth.uid;
  const db = getFirestore();
  const auth = getAuth();

  // Verify caller is admin
  const adminDoc = await db.collection('users').doc(adminId).get();
  if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Only admins can delete test couriers');
  }

  const { prefix = 'courier', uids } = request.data || {};
  const safePrefix = String(prefix).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 20) || 'courier';

  const deleted = [];
  const errors = [];

  // If specific UIDs provided, delete those
  if (Array.isArray(uids) && uids.length > 0) {
    for (const uid of uids) {
      if (typeof uid !== 'string') continue;
      try {
        // Verify it's a test account before deleting
        const userDoc = await db.collection('users').doc(uid).get();
        if (userDoc.exists && userDoc.data()?.isTestAccount === true) {
          await auth.deleteUser(uid);
          await db.collection('users').doc(uid).delete();

          // Clean up RTDB courier location if exists
          try {
            const { getDatabase } = await import('firebase-admin/database');
            const rtdb = getDatabase();
            await rtdb.ref(`courier_locations/${uid}`).remove();
          } catch {/* non-critical */}

          deleted.push({ uid, email: userDoc.data()?.email || 'unknown' });
          console.log(`✅ Deleted ${uid}`);
        } else {
          errors.push({ uid, error: 'Not a test account — skipped for safety' });
        }
      } catch (err) {
        console.error(`❌ Failed to delete ${uid}:`, err.message);
        errors.push({ uid, error: err.message });
      }
    }
  } else {
    // Delete all test accounts matching prefix
    const testUsersSnap = await db.collection('users')
      .where('isTestAccount', '==', true)
      .where('testAccountPrefix', '==', safePrefix)
      .get();

    for (const doc of testUsersSnap.docs) {
      const uid = doc.id;
      try {
        await auth.deleteUser(uid);
        await db.collection('users').doc(uid).delete();

        // Clean up RTDB courier location
        try {
          const { getDatabase } = await import('firebase-admin/database');
          const rtdb = getDatabase();
          await rtdb.ref(`courier_locations/${uid}`).remove();
        } catch {/* non-critical */}

        deleted.push({ uid, email: doc.data()?.email || 'unknown' });
        console.log(`✅ Deleted ${uid}`);
      } catch (err) {
        console.error(`❌ Failed to delete ${uid}:`, err.message);
        errors.push({ uid, error: err.message });
      }
    }
  }

  // Audit log
  await db.collection('admin_audit_logs').add({
    action: 'TEST_COURIERS_DELETED',
    adminId,
    adminEmail: adminDoc.data()?.email || 'unknown',
    prefix: safePrefix,
    deletedCount: deleted.length,
    errorCount: errors.length,
    timestamp: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    deleted: deleted.length,
    errors: errors.length,
    deletedAccounts: deleted,
    failedAccounts: errors,
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// LIST TEST COURIERS
// ─────────────────────────────────────────────────────────────────────────────

export const listTestCouriers = onCall({
  region: 'europe-west3',
  maxInstances: 5,
  timeoutSeconds: 30,
  memory: '256MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const adminId = request.auth.uid;
  const db = getFirestore();

  // Verify caller is admin
  const adminDoc = await db.collection('users').doc(adminId).get();
  if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Only admins can list test couriers');
  }

  const { prefix } = request.data || {};

  let q = db.collection('users').where('isTestAccount', '==', true);
  if (prefix) {
    const safePrefix = String(prefix).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 20);
    q = q.where('testAccountPrefix', '==', safePrefix);
  }

  const snap = await q.get();

  const accounts = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      uid: doc.id,
      email: d.email || '',
      displayName: d.displayName || d.name || '',
      prefix: d.testAccountPrefix || '',
      foodcargoguy: d.foodcargoguy || false,
      createdAt: d.createdAt?.toDate?.()?.toISOString() || null,
    };
  });

  return {
    success: true,
    count: accounts.length,
    accounts,
    password: 'Test123456',
  };
});

export const updateTestCourierName = onCall({
  region: 'europe-west3',
  maxInstances: 5,
  timeoutSeconds: 30,
  memory: '256MiB',
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const adminId = request.auth.uid;
  const db = getFirestore();
  const auth = getAuth();

  // Verify caller is admin
  const adminDoc = await db.collection('users').doc(adminId).get();
  if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', 'Only admins can update test couriers');
  }

  const { uid, displayName } = request.data || {};

  // Validate inputs
  if (typeof uid !== 'string' || !uid) {
    throw new HttpsError('invalid-argument', 'uid is required');
  }
  const trimmed = String(displayName || '').trim();
  if (trimmed.length < 1 || trimmed.length > 60) {
    throw new HttpsError('invalid-argument', 'displayName must be 1–60 characters');
  }

  // CRITICAL: verify it's a test account before mutating
  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists || userDoc.data()?.isTestAccount !== true) {
    throw new HttpsError('permission-denied', 'Can only rename test accounts');
  }

  const previousName = userDoc.data()?.displayName || '';

  // Update Auth + Firestore
  await auth.updateUser(uid, { displayName: trimmed });
  await db.collection('users').doc(uid).update({
    displayName: trimmed,
    name: trimmed,
    updatedAt: FieldValue.serverTimestamp(),
    updatedByAdmin: adminId,
  });

  // Audit log
  await db.collection('admin_audit_logs').add({
    action: 'TEST_COURIER_RENAMED',
    adminId,
    adminEmail: adminDoc.data()?.email || 'unknown',
    targetUid: uid,
    previousName,
    newName: trimmed,
    timestamp: FieldValue.serverTimestamp(),
  });

  return { success: true, uid, displayName: trimmed };
});
