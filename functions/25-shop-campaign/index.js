import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

const getDb = () => getFirestore();

// ─────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────

const MIN_DISCOUNT = 5.0;
const MAX_DISCOUNT = 90.0;
const BATCH_SIZE = 450;
const REGION = 'europe-west3';

// ─────────────────────────────────────────────
// Auth & ownership helpers
// ─────────────────────────────────────────────

function requireAuth(auth) {
  if (!auth?.uid) {
    throw new HttpsError(
      'unauthenticated',
      'You must be signed in to perform this action.'
    );
  }
  return auth.uid;
}

async function verifyShopAccess(uid, shopId) {
  const shopSnap = await getDb().collection('shops').doc(shopId).get();

  if (!shopSnap.exists) {
    throw new HttpsError('not-found', 'Shop not found.');
  }

  const shop = shopSnap.data();

  const isOwner = shop.ownerId === uid;
  const isMember =
    Array.isArray(shop.memberIds) && shop.memberIds.includes(uid);
  const isEditor =
    shop.members?.[uid]?.role === 'editor' ||
    shop.members?.[uid]?.role === 'admin';

  if (!isOwner && !isMember && !isEditor) {
    throw new HttpsError(
      'permission-denied',
      'You do not have permission to modify this shop.'
    );
  }
}


async function verifyCampaignAccess(campaignId, shopId) {
  const campaignSnap = await getDb().collection('campaigns').doc(campaignId).get();

  if (!campaignSnap.exists) {
    throw new HttpsError('not-found', 'Campaign not found.');
  }

  const campaign = campaignSnap.data();

  if (campaign.shopId !== shopId) {
    throw new HttpsError(
      'permission-denied',
      'Campaign does not belong to this shop.'
    );
  }

  return { id: campaignSnap.id, ...campaign };
}


function validateDiscount(discount) {
  if (typeof discount !== 'number' || isNaN(discount)) {
    throw new HttpsError('invalid-argument', 'Discount must be a number.');
  }
  if (discount < MIN_DISCOUNT || discount > MAX_DISCOUNT) {
    throw new HttpsError(
      'invalid-argument',
      `Discount must be between ${MIN_DISCOUNT}% and ${MAX_DISCOUNT}%.`
    );
  }
}


function isProductBlocked(product) {
  const hasSalePreference =
    product.discountThreshold != null &&
    product.bulkDiscountPercentage != null &&
    product.discountThreshold > 0 &&
    product.bulkDiscountPercentage > 0;
  const inBundle = (product.bundleIds?.length ?? 0) > 0;
  return hasSalePreference || inBundle;
}

// ─────────────────────────────────────────────
// CF 1 — addProductsToCampaign
// ─────────────────────────────────────────────
//
// Atomically adds one or more products to a campaign with their discounts.
// Runs entirely server-side — safe against tab-close mid-write.
//
// Payload:
//   campaignId   string
//   shopId       string
//   products     Array<{ productId, discount }>
//
// Returns:
//   { success: true, updatedCount: number }

export const addProductsToCampaign = onCall(
  { region: REGION, timeoutSeconds: 120, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request.auth);

    // ── Validate payload ──────────────────────
    const { campaignId, shopId, products } = request.data;

    if (!campaignId || typeof campaignId !== 'string') {
      throw new HttpsError('invalid-argument', 'campaignId is required.');
    }
    if (!shopId || typeof shopId !== 'string') {
      throw new HttpsError('invalid-argument', 'shopId is required.');
    }
    if (!Array.isArray(products) || products.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'products must be a non-empty array.'
      );
    }

    // ── Auth & ownership ──────────────────────
    await verifyShopAccess(uid, shopId);
    const campaign = await verifyCampaignAccess(campaignId, shopId);

    // ── Validate all discounts up front ───────
    for (const item of products) {
      if (!item.productId || typeof item.productId !== 'string') {
        throw new HttpsError('invalid-argument', 'Each product must have a valid productId.');
      }
      validateDiscount(item.discount);
    }

    // ── Fetch all products server-side ────────
    // Batch into groups of 30 (Firestore 'in' limit)
    const productIds = products.map((p) => p.productId);
    const chunks = [];
    for (let i = 0; i < productIds.length; i += 30) {
      chunks.push(productIds.slice(i, i + 30));
    }

    const snapshots = await Promise.all(
      chunks.map((chunk) =>
        getDb()
          .collection('shop_products')
          .where('__name__', 'in', chunk)
          .get()
      )
    );

    const productMap = new Map();
    snapshots.forEach((snap) => {
      snap.docs.forEach((d) => productMap.set(d.id, { id: d.id, ...d.data() }));
    });

    // ── Server-side validation per product ────
    const validProducts = [];
    const skipped = [];

    for (const item of products) {
      const product = productMap.get(item.productId);

      if (!product) {
        skipped.push({ productId: item.productId, reason: 'not_found' });
        continue;
      }
      if (product.shopId !== shopId) {
        skipped.push({ productId: item.productId, reason: 'wrong_shop' });
        continue;
      }
      if (isProductBlocked(product)) {
        skipped.push({ productId: item.productId, reason: 'blocked' });
        continue;
      }
      // Already in a different campaign
      if (
        product.campaign &&
        product.campaign !== '' &&
        product.campaign !== campaignId
      ) {
        skipped.push({ productId: item.productId, reason: 'in_other_campaign' });
        continue;
      }

      validProducts.push({ product, discount: item.discount });
    }

    if (validProducts.length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'No eligible products to add.',
        { skipped }
      );
    }

    // ── Batch writes in groups of BATCH_SIZE ──
    const total = validProducts.length;
    let updatedCount = 0;

    for (let i = 0; i < total; i += BATCH_SIZE) {
        const db = getDb();
        const batch = db.batch();
      const end = Math.min(i + BATCH_SIZE, total);

      for (let j = i; j < end; j++) {
        const { product, discount } = validProducts[j];
        const basePrice = product.originalPrice ?? product.price;
        const discountedPrice = basePrice * (1 - discount / 100);

        batch.update(db.collection('shop_products').doc(product.id), {
          campaign: campaignId,
          campaignName: campaign.name ?? '',
          discountPercentage: discount,
          originalPrice: basePrice,
          price: discountedPrice,
          updatedAt: FieldValue.serverTimestamp(),
        });

        updatedCount++;
      }

      await batch.commit();
    }

    return { success: true, updatedCount, skipped };
  }
);

// ─────────────────────────────────────────────
// CF 2 — removeProductFromCampaign
// ─────────────────────────────────────────────
//
// Removes a product from a campaign.
// Uses a Firestore transaction to prevent concurrent-edit races.
//
// Payload:
//   productId    string
//   campaignId   string
//   shopId       string
//   keepDiscount boolean  — true = keep discount, false = restore original price
//
// Returns:
//   { success: true, restoredPrice?: number }

export const removeProductFromCampaign = onCall(
  { region: REGION, timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request.auth);

    // ── Validate payload ──────────────────────
    const { productId, campaignId, shopId, keepDiscount } = request.data;

    if (!productId || typeof productId !== 'string') {
      throw new HttpsError('invalid-argument', 'productId is required.');
    }
    if (!campaignId || typeof campaignId !== 'string') {
      throw new HttpsError('invalid-argument', 'campaignId is required.');
    }
    if (!shopId || typeof shopId !== 'string') {
      throw new HttpsError('invalid-argument', 'shopId is required.');
    }
    if (typeof keepDiscount !== 'boolean') {
      throw new HttpsError('invalid-argument', 'keepDiscount must be a boolean.');
    }

    // ── Auth & ownership ──────────────────────
    await verifyShopAccess(uid, shopId);
    await verifyCampaignAccess(campaignId, shopId);

    // ── Transaction — safe against concurrent edits ──
    const productRef = getDb().collection('shop_products').doc(productId);
    let restoredPrice;

    await getDb().runTransaction(async (txn) => {
      const productSnap = await txn.get(productRef);

      if (!productSnap.exists) {
        throw new HttpsError('not-found', 'Product not found.');
      }

      const product = productSnap.data();

      // Ownership check
      if (product.shopId !== shopId) {
        throw new HttpsError('permission-denied', 'Product does not belong to this shop.');
      }

      // Idempotency — already removed, nothing to do
      if (!product.campaign || product.campaign !== campaignId) {
        return;
      }

      if (keepDiscount) {
        // Remove from campaign, keep discount as-is
        txn.update(productRef, {
          campaign: '',
          campaignName: '',
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        // Remove from campaign AND restore original price
        const updateData = {
          campaign: '',
          campaignName: '',
          discountPercentage: FieldValue.delete(),
          originalPrice: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        };

        if (product.originalPrice != null) {
          updateData.price = product.originalPrice;
          restoredPrice = product.originalPrice;
        }

        txn.update(productRef, updateData);
      }
    });

    return { success: true, ...(restoredPrice != null && { restoredPrice }) };
  }
);

// ─────────────────────────────────────────────
// CF 3 — updateCampaignProductDiscount
// ─────────────────────────────────────────────
//
// Updates the discount for a product already in a campaign.
// Uses a transaction to prevent concurrent-edit races.
//
// Payload:
//   productId    string
//   campaignId   string
//   shopId       string
//   newDiscount  number  (0 = remove discount)
//
// Returns:
//   { success: true, newPrice: number }

export const updateCampaignProductDiscount = onCall(
  { region: REGION, timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request.auth);

    // ── Validate payload ──────────────────────
    const { productId, campaignId, shopId, newDiscount } = request.data;

    if (!productId || typeof productId !== 'string') {
      throw new HttpsError('invalid-argument', 'productId is required.');
    }
    if (!campaignId || typeof campaignId !== 'string') {
      throw new HttpsError('invalid-argument', 'campaignId is required.');
    }
    if (!shopId || typeof shopId !== 'string') {
      throw new HttpsError('invalid-argument', 'shopId is required.');
    }
    if (typeof newDiscount !== 'number') {
      throw new HttpsError('invalid-argument', 'newDiscount must be a number.');
    }

    // Allow 0 (remove discount) or valid range
    if (newDiscount !== 0) {
      validateDiscount(newDiscount);
    }

    // ── Auth & ownership ──────────────────────
    await verifyShopAccess(uid, shopId);
    await verifyCampaignAccess(campaignId, shopId);

    // ── Transaction ───────────────────────────
    const productRef = getDb().collection('shop_products').doc(productId);
    let newPrice;

    await getDb().runTransaction(async (txn) => {
      const productSnap = await txn.get(productRef);

      if (!productSnap.exists) {
        throw new HttpsError('not-found', 'Product not found.');
      }

      const product = productSnap.data();

      if (product.shopId !== shopId) {
        throw new HttpsError('permission-denied', 'Product does not belong to this shop.');
      }

      if (product.campaign !== campaignId) {
        throw new HttpsError(
          'failed-precondition',
          'Product is not in this campaign.'
        );
      }

      const basePrice = product.originalPrice ?? product.price;

      if (newDiscount > 0) {
        newPrice = basePrice * (1 - newDiscount / 100);
        txn.update(productRef, {
          discountPercentage: newDiscount,
          originalPrice: basePrice,
          price: newPrice,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        // Remove discount, restore original price
        newPrice = basePrice;
        txn.update(productRef, {
          discountPercentage: FieldValue.delete(),
          originalPrice: FieldValue.delete(),
          price: basePrice,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });

    return { success: true, newPrice };
  }
);
