// functions/coupons.js
// Cloud Functions for coupon and benefit management (ES6 Module)

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

// Region configuration
const REGION = 'europe-west3';

// Lazy initialization - get db when needed, not at module load
const getDb = () => getFirestore();


function generateCouponCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Avoid confusing chars
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * Grant a discount coupon to a user
 * Only admins can call this function
 */
export const grantUserCoupon = onCall(
  { region: REGION },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Verify admin
    const adminDoc = await getDb().collection('users').doc(auth.uid).get();
    const adminData = adminDoc.data();

    if (!adminData?.isAdmin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can grant coupons'
      );
    }

    // Validate input
    if (!data.userId || typeof data.userId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'userId is required'
      );
    }

    if (!data.amount || typeof data.amount !== 'number' || data.amount <= 0) {
      throw new HttpsError(
        'invalid-argument',
        'amount must be a positive number'
      );
    }

    // Verify target user exists
    const userDoc = await getDb().collection('users').doc(data.userId).get();
    if (!userDoc.exists) {
      throw new HttpsError(
        'not-found',
        'Target user not found'
      );
    }

    const userData = userDoc.data();
    const now = Timestamp.now();

    // Calculate expiration
    let expiresAt = null;
    if (data.expiresInDays && data.expiresInDays > 0) {
      const expiryDate = new Date();
      expiryDate.setDate(expiryDate.getDate() + data.expiresInDays);
      expiryDate.setHours(23, 59, 59, 999); // End of day
      expiresAt = Timestamp.fromDate(expiryDate);
    }

    // Create coupon
    const couponData = {
      userId: data.userId,
      amount: data.amount,
      currency: data.currency || 'TL',
      code: generateCouponCode(),
      description: data.description || `${data.amount} TL discount coupon`,
      createdAt: now,
      createdBy: auth.uid,
      expiresAt: expiresAt,
      usedAt: null,
      orderId: null,
      isUsed: false,
    };

    const couponRef = await getDb()
      .collection('users')
      .doc(data.userId)
      .collection('coupons')
      .add(couponData);

    // Log admin activity
    await getDb().collection('admin_activity_logs').add({
      time: now,
      adminId: auth.uid,
      displayName: adminData.displayName || 'Admin',
      email: userData?.email || data.userId,
      activity: `Granted ${data.amount} ${data.currency || 'TL'} coupon`,
      metadata: {
        couponId: couponRef.id,
        amount: data.amount,
        currency: data.currency || 'TL',
        targetUserId: data.userId,
        targetUserEmail: userData?.email,
        expiresInDays: data.expiresInDays,
      },
    });

    console.log(`✅ Coupon granted: ${couponRef.id} to user ${data.userId}`);

    return {
      success: true,
      couponId: couponRef.id,
      code: couponData.code,
      amount: couponData.amount,
      currency: couponData.currency,
    };
  }
);

/**
 * Grant free shipping benefit to a user
 * Only admins can call this function
 */
export const grantFreeShipping = onCall(
  { region: REGION },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Verify admin
    const adminDoc = await getDb().collection('users').doc(auth.uid).get();
    const adminData = adminDoc.data();

    if (!adminData?.isAdmin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can grant benefits'
      );
    }

    // Validate input
    if (!data.userId || typeof data.userId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'userId is required'
      );
    }

    // Verify target user exists
    const userDoc = await getDb().collection('users').doc(data.userId).get();
    if (!userDoc.exists) {
      throw new HttpsError(
        'not-found',
        'Target user not found'
      );
    }

    const userData = userDoc.data();
    const now = Timestamp.now();

    // Calculate expiration (default 30 days if not specified)
    const expiresInDays = data.expiresInDays || 30;
    const expiryDate = new Date();
    expiryDate.setDate(expiryDate.getDate() + expiresInDays);
    expiryDate.setHours(23, 59, 59, 999);
    const expiresAt = Timestamp.fromDate(expiryDate);

    // Create benefit
    const benefitData = {
      userId: data.userId,
      type: 'free_shipping',
      description: data.description || 'Free shipping for your next order',
      createdAt: now,
      createdBy: auth.uid,
      expiresAt: expiresAt,
      usedAt: null,
      orderId: null,
      isUsed: false,
      metadata: null,
    };

    const benefitRef = await getDb()
      .collection('users')
      .doc(data.userId)
      .collection('benefits')
      .add(benefitData);

    // Log admin activity
    await getDb().collection('admin_activity_logs').add({
      time: now,
      adminId: auth.uid,
      displayName: adminData.displayName || 'Admin',
      email: userData?.email || data.userId,
      activity: 'Granted free shipping benefit',
      metadata: {
        benefitId: benefitRef.id,
        type: 'free_shipping',
        targetUserId: data.userId,
        targetUserEmail: userData?.email,
        expiresInDays: expiresInDays,
      },
    });

    console.log(`✅ Free shipping granted: ${benefitRef.id} to user ${data.userId}`);

    return {
      success: true,
      benefitId: benefitRef.id,
      type: 'free_shipping',
      expiresAt: expiresAt.toDate().toISOString(),
    };
  }
);

/**
 * Get user's coupons and benefits (for admin view)
 */
export const getUserCouponsAndBenefits = onCall(
  { region: REGION },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Verify admin
    const adminDoc = await getDb().collection('users').doc(auth.uid).get();
    if (!adminDoc.data()?.isAdmin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can view user coupons'
      );
    }

    if (!data.userId) {
      throw new HttpsError(
        'invalid-argument',
        'userId is required'
      );
    }

    // Fetch coupons
    const couponsSnapshot = await getDb()
      .collection('users')
      .doc(data.userId)
      .collection('coupons')
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const coupons = couponsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      expiresAt: doc.data().expiresAt?.toDate?.()?.toISOString() || null,
      usedAt: doc.data().usedAt?.toDate?.()?.toISOString() || null,
    }));

    // Fetch benefits
    const benefitsSnapshot = await getDb()
      .collection('users')
      .doc(data.userId)
      .collection('benefits')
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();

    const benefits = benefitsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      expiresAt: doc.data().expiresAt?.toDate?.()?.toISOString() || null,
      usedAt: doc.data().usedAt?.toDate?.()?.toISOString() || null,
    }));

    return {
      coupons,
      benefits,
    };
  }
);

/**
 * Revoke (delete) a coupon - only if not used
 */
export const revokeCoupon = onCall(
  { region: REGION },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Verify admin
    const adminDoc = await getDb().collection('users').doc(auth.uid).get();
    if (!adminDoc.data()?.isAdmin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can revoke coupons'
      );
    }

    if (!data.userId || !data.couponId) {
      throw new HttpsError(
        'invalid-argument',
        'userId and couponId are required'
      );
    }

    const couponRef = getDb()
      .collection('users')
      .doc(data.userId)
      .collection('coupons')
      .doc(data.couponId);

    const couponDoc = await couponRef.get();
    if (!couponDoc.exists) {
      throw new HttpsError('not-found', 'Coupon not found');
    }

    if (couponDoc.data()?.isUsed) {
      throw new HttpsError(
        'failed-precondition',
        'Cannot revoke a used coupon'
      );
    }

    await couponRef.delete();

    // Log activity
    const userDoc = await getDb().collection('users').doc(data.userId).get();
    await getDb().collection('admin_activity_logs').add({
      time: Timestamp.now(),
      adminId: auth.uid,
      displayName: adminDoc.data()?.displayName || 'Admin',
      email: userDoc.data()?.email || data.userId,
      activity: `Revoked coupon ${data.couponId}`,
      metadata: {
        couponId: data.couponId,
        targetUserId: data.userId,
      },
    });

    console.log(`✅ Coupon revoked: ${data.couponId} from user ${data.userId}`);

    return { success: true };
  }
);

/**
 * Revoke (delete) a benefit - only if not used
 */
export const revokeBenefit = onCall(
  { region: REGION },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    // Verify admin
    const adminDoc = await getDb().collection('users').doc(auth.uid).get();
    if (!adminDoc.data()?.isAdmin) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can revoke benefits'
      );
    }

    if (!data.userId || !data.benefitId) {
      throw new HttpsError(
        'invalid-argument',
        'userId and benefitId are required'
      );
    }

    const benefitRef = getDb()
      .collection('users')
      .doc(data.userId)
      .collection('benefits')
      .doc(data.benefitId);

    const benefitDoc = await benefitRef.get();
    if (!benefitDoc.exists) {
      throw new HttpsError('not-found', 'Benefit not found');
    }

    if (benefitDoc.data()?.isUsed) {
      throw new HttpsError(
        'failed-precondition',
        'Cannot revoke a used benefit'
      );
    }

    await benefitRef.delete();

    // Log activity
    const userDoc = await getDb().collection('users').doc(data.userId).get();
    await getDb().collection('admin_activity_logs').add({
      time: Timestamp.now(),
      adminId: auth.uid,
      displayName: adminDoc.data()?.displayName || 'Admin',
      email: userDoc.data()?.email || data.userId,
      activity: `Revoked benefit ${data.benefitId}`,
      metadata: {
        benefitId: data.benefitId,
        targetUserId: data.userId,
      },
    });

    console.log(`✅ Benefit revoked: ${data.benefitId} from user ${data.userId}`);

    return { success: true };
  }
);
