// functions/submitProduct.js
// ===================================================================
// CLOUD FUNCTION: submitProduct
// Handles new product listing submissions.
//
// Flow:
// 1. Client uploads files to Firebase Storage (with progress bar)
// 2. Client calls this function with product data + file URLs
// 3. This function validates everything, verifies files, creates Firestore doc
// 4. Returns success/failure to client
//
// Security:
// - Requires authentication
// - Verifies shop membership
// - Validates all Storage URLs belong to this project
// - Sanitizes all inputs
// ===================================================================

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import {
  validateProductFields,
  validateStorageUrls,
  verifyShopMembership,
  sanitizeString,
  sanitizeNumber,
  sanitizeInteger,
  sanitizeForFirestore,
  cleanAttributes,
  SPEC_FIELD_KEYS,
} from '../utils/validation.js';

export const submitProduct = onCall(
  {
    region: 'europe-west3',
    maxInstances: 100,
    timeoutSeconds: 60,
    memory: '256MiB',
    // Enforce authentication
    enforceAppCheck: false, // Enable if you use App Check
  },
  async (request) => {
    // ─── 1. AUTH CHECK ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }

    const uid = request.auth.uid;
    const data = request.data;

    if (!data || typeof data !== 'object') {
      throw new HttpsError('invalid-argument', 'Product data is required.');
    }

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const projectBucket = bucket.name;

    // ─── 2. VALIDATE REQUIRED FIELDS ────────────────────────────────
    const fieldValidation = validateProductFields(data);
    if (!fieldValidation.valid) {
      throw new HttpsError(
        'invalid-argument',
        `Validation failed: ${fieldValidation.errors.join(' ')}`
      );
    }

    // ─── 3. VALIDATE STORAGE URLS ───────────────────────────────────
    const urlValidation = validateStorageUrls(data, projectBucket);
    if (!urlValidation.valid) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid file URLs: ${urlValidation.errors.join(' ')}`
      );
    }

    // ─── 4. VERIFY SHOP MEMBERSHIP ──────────────────────────────────
    const shopId = sanitizeString(data.shopId);
    const isMember = await verifyShopMembership(db, uid, shopId);
    if (!isMember) {
      throw new HttpsError(
        'permission-denied',
        'You are not a member of this shop.'
      );
    }

    // ─── 5. GET SELLER INFO ─────────────────────────────────────────
    let sellerName = 'Unknown Seller';
    try {
      const shopDoc = await db.collection('shops').doc(shopId).get();
      if (shopDoc.exists) {
        sellerName = shopDoc.data()?.name || 'Unknown Seller';
      }
    } catch (error) {
      console.warn('Failed to fetch shop name:', error.message);
    }

    // Get seller contact info
    let sellerInfo = {};
    try {
      const sellerInfoDoc = await db
        .collection('shops')
        .doc(shopId)
        .collection('seller_info')
        .doc('info')
        .get();

      if (sellerInfoDoc.exists) {
        sellerInfo = sellerInfoDoc.data() || {};
      } else {
        // Fallback to user doc
        const userDoc = await db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          sellerInfo = userDoc.data()?.sellerInfo || {};
        }
      }
    } catch (error) {
      console.warn('Failed to fetch seller info:', error.message);
    }

    // ─── 6. BUILD PRODUCT DOCUMENT ──────────────────────────────────
    const productId = data.productId || crypto.randomUUID();

    // Extract and clean spec fields from attributes
    const rawAttributes = data.attributes || {};
    const cleanedAttributes = cleanAttributes(rawAttributes);

    // Build spec fields object (top-level fields)
    const specFields = {};
    for (const key of SPEC_FIELD_KEYS) {
      // Check both top-level data and attributes (backward compat)
      const value = data[key] ?? rawAttributes[key];
      if (value !== undefined && value !== null) {
        specFields[key] = value;
      }
    }

    // Handle legacy singular → plural promotion
    if (!specFields.clothingTypes && (data.clothingType || rawAttributes.clothingType)) {
      specFields.clothingTypes = [sanitizeString(data.clothingType || rawAttributes.clothingType)];
    }
    if (!specFields.pantFabricTypes && (data.pantFabricType || rawAttributes.pantFabricType)) {
      specFields.pantFabricTypes = [sanitizeString(data.pantFabricType || rawAttributes.pantFabricType)];
    }

    // Build color data
    const colorQuantities = {};
    const availableColors = [];
    if (data.colorQuantities && typeof data.colorQuantities === 'object') {
      for (const [color, qty] of Object.entries(data.colorQuantities)) {
        const parsedQty = parseInt(qty, 10);
        if (!isNaN(parsedQty) && parsedQty > 0) {
          colorQuantities[color] = parsedQty;
          availableColors.push(color);
        }
      }
    } else if (data.availableColors && Array.isArray(data.availableColors)) {
      for (const color of data.availableColors) {
        availableColors.push(color);
      }
    }

    const now = FieldValue.serverTimestamp();

    const productDocument = {
      // ── Identity ──────────────────────────────────────────────────
      id: productId,
      ilan_no: productId,
      status: 'pending',

      // ── Core Product Info ─────────────────────────────────────────
      productName: sanitizeString(data.productName),
      description: sanitizeString(data.description),
      price: sanitizeNumber(data.price),
      currency: 'TL',
      condition: sanitizeString(data.condition, 'Brand New'),
      brandModel: sanitizeString(data.brandModel) || null,
      productType: sanitizeString(data.productType) || null,
      gender: sanitizeString(data.gender) || null,

      // ── Categories ────────────────────────────────────────────────
      category: sanitizeString(data.category),
      subcategory: sanitizeString(data.subcategory),
      subsubcategory: sanitizeString(data.subsubcategory),

      // ── Inventory ─────────────────────────────────────────────────
      quantity: sanitizeInteger(data.quantity, 1),
      colorQuantities,
      availableColors,
      deliveryOption: sanitizeString(data.deliveryOption, 'Self Delivery'),

      // ── Spec Fields (top-level) ───────────────────────────────────
      ...specFields,

      // ── Misc Attributes ───────────────────────────────────────────
      ...(Object.keys(cleanedAttributes).length > 0 ?
        { attributes: cleanedAttributes } :
        {}),

      // ── Media URLs (already uploaded by client) ───────────────────
      imageUrls: data.imageUrls || [],
      videoUrl: data.videoUrl || null,
      colorImages: data.colorImages || {},

      // ── Ownership ─────────────────────────────────────────────────
      userId: uid,
      ownerId: uid,
      shopId: shopId,
      sellerName: sellerName,

      // ── Seller Info ───────────────────────────────────────────────
      phone: sanitizeString(sellerInfo.phone || data.phone),
      region: sanitizeString(sellerInfo.region || data.region),
      address: sanitizeString(sellerInfo.address || data.address),
      ibanOwnerName: sanitizeString(sellerInfo.ibanOwnerName || data.ibanOwnerName),
      ibanOwnerSurname: sanitizeString(sellerInfo.ibanOwnerSurname || data.ibanOwnerSurname),
      iban: sanitizeString(sellerInfo.iban || data.iban),

      // ── Timestamps ────────────────────────────────────────────────
      createdAt: now,
      updatedAt: now,

      // ── Stats (initialized) ───────────────────────────────────────
      averageRating: 0,
      reviewCount: 0,
      clickCount: 0,
      favoritesCount: 0,
      cartCount: 0,
      purchaseCount: 0,
      paused: false,
      isFeatured: false,
      isTrending: false,
      isBoosted: false,
      rankingScore: 0,
      promotionScore: 0,
      boostedImpressionCount: 0,
      boostImpressionCountAtStart: 0,
      boostClickCountAtStart: 0,
      clickCountAtStart: 0,
      boostStartTime: null,
      boostEndTime: null,
      dailyClickCount: 0,
      lastClickDate: null,
      campaign: '',
      campaignName: '',

      // ── Related Products ──────────────────────────────────────────
      relatedProductIds: [],
      relatedLastUpdated: new Date(1970, 0, 1),
      relatedCount: 0,
    };

    // ─── 7. WRITE TO FIRESTORE ──────────────────────────────────────
    try {
      const sanitized = sanitizeForFirestore(productDocument);

      // Safety net: re-assign in case sanitizeForFirestore detection fails
       sanitized.createdAt = FieldValue.serverTimestamp();
       sanitized.updatedAt = FieldValue.serverTimestamp();

      await db
        .collection('product_applications')
        .doc(productId)
        .set(sanitized);

      console.log(`✅ Product application created: ${productId} by user: ${uid}`);

      return {
        success: true,
        productId: productId,
        message: 'Product submitted successfully for review.',
      };
    } catch (error) {
      console.error(`❌ Failed to create product application: ${error.message}`);
      throw new HttpsError(
        'internal',
        'Failed to save product. Please try again.'
      );
    }
  }
);

export const submitProductEdit = onCall(
    {
      region: 'europe-west3',
      maxInstances: 100,
      timeoutSeconds: 120, // Longer timeout for edit processing
      memory: '512MiB', // More memory for loading original product
      enforceAppCheck: false,
    },
    async (request) => {
      // ─── 1. AUTH CHECK ──────────────────────────────────────────────
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Authentication required.');
      }
  
      const uid = request.auth.uid;
      const data = request.data;
  
      if (!data || typeof data !== 'object') {
        throw new HttpsError('invalid-argument', 'Edit data is required.');
      }
  
      const db = getFirestore();
      const bucket = getStorage().bucket();
      const projectBucket = bucket.name;
  
      // ─── 2. VALIDATE EDIT-SPECIFIC FIELDS ───────────────────────────
      const originalProductId = sanitizeString(data.originalProductId);
      if (!originalProductId) {
        throw new HttpsError('invalid-argument', 'Original product ID is required.');
      }
  
      const isArchivedEdit = data.isArchivedEdit === true;
      const sourceCollection = isArchivedEdit ? 'paused_shop_products' : 'shop_products';
  
      // Validate standard product fields
      const fieldValidation = validateProductFields(data);
      if (!fieldValidation.valid) {
        throw new HttpsError(
          'invalid-argument',
          `Validation failed: ${fieldValidation.errors.join(' ')}`
        );
      }
  
      // Validate storage URLs
      const urlValidation = validateStorageUrls(data, projectBucket);
      if (!urlValidation.valid) {
        throw new HttpsError(
          'invalid-argument',
          `Invalid file URLs: ${urlValidation.errors.join(' ')}`
        );
      }
  
      // ─── 3. VERIFY SHOP MEMBERSHIP ──────────────────────────────────
      const shopId = sanitizeString(data.shopId);
      const isMember = await verifyShopMembership(db, uid, shopId);
      if (!isMember) {
        throw new HttpsError(
          'permission-denied',
          'You are not a member of this shop.'
        );
      }
  
      // ─── 4. LOAD ORIGINAL PRODUCT ───────────────────────────────────
      let originalProduct;
      try {
        const originalDoc = await db
          .collection(sourceCollection)
          .doc(originalProductId)
          .get();
  
        if (!originalDoc.exists) {
          throw new HttpsError('not-found', 'Original product not found.');
        }
  
        originalProduct = originalDoc.data();
  
        // Verify ownership
        if (originalProduct.userId !== uid && originalProduct.ownerId !== uid) {
          throw new HttpsError(
            'permission-denied',
            'You do not own this product.'
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        console.error('Failed to load original product:', error);
        throw new HttpsError('internal', 'Failed to load original product.');
      }
  
      // ─── 5. GET SELLER INFO ─────────────────────────────────────────
      let sellerName = originalProduct.sellerName || 'Unknown Seller';
      try {
        const shopDoc = await db.collection('shops').doc(shopId).get();
        if (shopDoc.exists) {
          sellerName = shopDoc.data()?.name || sellerName;
        }
      } catch (error) {
        console.warn('Failed to fetch shop name:', error.message);
      }
  
      // ─── 6. BUILD NEW PRODUCT DATA ──────────────────────────────────
      const rawAttributes = data.attributes || {};
      const cleanedAttributes = cleanAttributes(rawAttributes);
  
      // Build spec fields
      const specFields = {};
      for (const key of SPEC_FIELD_KEYS) {
        const value = data[key] ?? rawAttributes[key];
        if (value !== undefined && value !== null) {
          specFields[key] = value;
        }
      }
  
      // Handle legacy singular → plural promotion
      if (!specFields.clothingTypes && (data.clothingType || rawAttributes.clothingType)) {
        specFields.clothingTypes = [sanitizeString(data.clothingType || rawAttributes.clothingType)];
      }
      if (!specFields.pantFabricTypes && (data.pantFabricType || rawAttributes.pantFabricType)) {
        specFields.pantFabricTypes = [sanitizeString(data.pantFabricType || rawAttributes.pantFabricType)];
      }
  
      // Build color data
      const colorQuantities = {};
      const availableColors = [];
      if (data.colorQuantities && typeof data.colorQuantities === 'object') {
        for (const [color, qty] of Object.entries(data.colorQuantities)) {
          const parsedQty = parseInt(qty, 10);
          if (!isNaN(parsedQty) && parsedQty > 0) {
            colorQuantities[color] = parsedQty;
            availableColors.push(color);
          }
        }
      } else if (data.availableColors && Array.isArray(data.availableColors)) {
        for (const color of data.availableColors) {
          availableColors.push(color);
        }
      }
  
      // Resolve gender (priority: submitted > original root > original attributes)
      const genderValue =
        sanitizeString(data.gender) ||
        sanitizeString(originalProduct.gender) ||
        sanitizeString(originalProduct.attributes?.gender) ||
        null;
  
      const deletedColors = Array.isArray(data.deletedColors) ?
        data.deletedColors :
        [];
  
      const newData = {
        productName: sanitizeString(data.productName),
        description: sanitizeString(data.description),
        price: sanitizeNumber(data.price),
        condition: sanitizeString(data.condition),
        brandModel: sanitizeString(data.brandModel) || null,
        category: sanitizeString(data.category),
        subcategory: sanitizeString(data.subcategory),
        subsubcategory: sanitizeString(data.subsubcategory),
        productType: sanitizeString(data.productType) || originalProduct.productType || null,
        gender: genderValue,
        quantity: sanitizeInteger(data.quantity, 1),
        deliveryOption: sanitizeString(data.deliveryOption),
        colorQuantities,
        availableColors,
        deletedColors,
        ...specFields,
      };
  
      // ─── 7. DETECT CHANGES ──────────────────────────────────────────
      const editedFields = [];
      const changes = {};
  
      const normalizeValue = (val) => {
        if (val === null || val === '' || val === undefined) return null;
        if (Array.isArray(val) && val.length === 0) return null;
        if (typeof val === 'object' && val !== null && !(val instanceof Date) && Object.keys(val).length === 0) return null;
        return val;
      };
  
      for (const [field, newValue] of Object.entries(newData)) {
        const oldValue = originalProduct[field];
        const normalizedOld = normalizeValue(oldValue);
        const normalizedNew = normalizeValue(newValue);
  
        if (JSON.stringify(normalizedOld) !== JSON.stringify(normalizedNew)) {
          editedFields.push(field);
          changes[field] = { old: oldValue ?? null, new: newValue };
        }
      }
  
      // Detect media changes
      const mediaChanges = {};
  
      // Image changes
      const originalImageUrls = originalProduct.imageUrls || [];
      const newImageUrls = data.imageUrls || [];
      if (JSON.stringify(originalImageUrls) !== JSON.stringify(newImageUrls)) {
        editedFields.push('imageUrls');
        mediaChanges.imageUrls = {
          old: originalImageUrls,
          new: newImageUrls,
        };
      }
  
      // Video changes
      const originalVideoUrl = originalProduct.videoUrl || null;
      const newVideoUrl = data.videoUrl || null;
      if (originalVideoUrl !== newVideoUrl) {
        editedFields.push('videoUrl');
        mediaChanges.videoUrl = {
          old: originalVideoUrl,
          new: newVideoUrl,
        };
      }
  
      // Color image changes
      const originalColorImages = originalProduct.colorImages || {};
      const newColorImages = data.colorImages || {};
      if (JSON.stringify(originalColorImages) !== JSON.stringify(newColorImages)) {
        editedFields.push('colorImages');
        mediaChanges.colorImages = {
          old: originalColorImages,
          new: newColorImages,
        };
      }
  
      // ─── 8. BUILD EDIT APPLICATION ──────────────────────────────────
      const editApplicationId = crypto.randomUUID();
      const now = FieldValue.serverTimestamp();
      const editType = isArchivedEdit ? 'archived_product_update' : 'product_edit';
  
      const editApplication = {
        // ── Application Metadata ──────────────────────────────────────
        applicationId: editApplicationId,
        originalProductId,
        status: 'pending',
        editType,
        submittedAt: now,
        sourceCollection: isArchivedEdit ? sourceCollection : null,
  
        // ── Identity ──────────────────────────────────────────────────
        id: originalProductId,
        ilan_no: originalProductId,
  
        // ── Ownership ─────────────────────────────────────────────────
        userId: uid,
        ownerId: uid,
        shopId,
        sellerName,
  
        // ── Core Product Info ─────────────────────────────────────────
        productName: newData.productName,
        description: newData.description,
        price: newData.price,
        currency: 'TL',
        condition: newData.condition,
        brandModel: newData.brandModel,
        productType: newData.productType,
        gender: newData.gender,
  
        // ── Categories ────────────────────────────────────────────────
        category: newData.category,
        subcategory: newData.subcategory,
        subsubcategory: newData.subsubcategory,
  
        // ── Inventory ─────────────────────────────────────────────────
        quantity: newData.quantity,
        deliveryOption: newData.deliveryOption,
        colorQuantities: newData.colorQuantities,
        availableColors: newData.availableColors,
        deletedColors: newData.deletedColors,
  
        // ── Spec Fields ───────────────────────────────────────────────
        ...specFields,
  
        // ── Misc Attributes ───────────────────────────────────────────
        ...(Object.keys(cleanedAttributes).length > 0 ?
          { attributes: cleanedAttributes } :
          {}),
  
        // ── Timestamps ────────────────────────────────────────────────
        createdAt: originalProduct.createdAt || now,
        updatedAt: now,
  
        // ── Preserve Original Stats ───────────────────────────────────
        averageRating: originalProduct.averageRating || 0,
        reviewCount: originalProduct.reviewCount || 0,
        clickCount: originalProduct.clickCount || 0,
        favoritesCount: originalProduct.favoritesCount || 0,
        cartCount: originalProduct.cartCount || 0,
        purchaseCount: originalProduct.purchaseCount || 0,
        campaign: originalProduct.campaign ?? '',
        campaignName: originalProduct.campaignName ?? '',
        isFeatured: originalProduct.isFeatured || false,
        isBoosted: originalProduct.isBoosted || false,
        paused: isArchivedEdit ? false : (originalProduct.paused || false),
        promotionScore: originalProduct.promotionScore || 0,
        boostedImpressionCount: originalProduct.boostedImpressionCount || 0,
        boostImpressionCountAtStart: originalProduct.boostImpressionCountAtStart || 0,
        boostClickCountAtStart: originalProduct.boostClickCountAtStart || 0,
        boostStartTime: originalProduct.boostStartTime || null,
        boostEndTime: originalProduct.boostEndTime || null,
        lastClickDate: originalProduct.lastClickDate || null,
        clickCountAtStart: originalProduct.clickCountAtStart || 0,
  
        // ── Related Products ──────────────────────────────────────────
        relatedProductIds: originalProduct.relatedProductIds || [],
        relatedLastUpdated: originalProduct.relatedLastUpdated || new Date(1970, 0, 1),
        relatedCount: originalProduct.relatedCount || 0,
  
        // ── Media URLs ────────────────────────────────────────────────
        imageUrls: data.imageUrls || originalProduct.imageUrls || [],
        videoUrl: data.videoUrl ?? originalProduct.videoUrl ?? null,
        colorImages: data.colorImages || originalProduct.colorImages || {},
  
        // ── Change Tracking ───────────────────────────────────────────
        editedFields,
        changes: { ...changes, ...mediaChanges },
        originalProductData: sanitizeForFirestore(originalProduct),
  
        // ── Seller Info ───────────────────────────────────────────────
        phone: sanitizeString(data.phone || originalProduct.phone),
        region: sanitizeString(data.region || originalProduct.region),
        address: sanitizeString(data.address || originalProduct.address),
        ibanOwnerName: sanitizeString(data.ibanOwnerName || originalProduct.ibanOwnerName),
        ibanOwnerSurname: sanitizeString(data.ibanOwnerSurname || originalProduct.ibanOwnerSurname),
        iban: sanitizeString(data.iban || originalProduct.iban),
  
        // ── Archive Info ──────────────────────────────────────────────
        archiveReason: originalProduct.archiveReason || null,
      };
  
      // ─── 9. WRITE TO FIRESTORE ──────────────────────────────────────
      try {
        const sanitized = sanitizeForFirestore(editApplication);

        sanitized.submittedAt = FieldValue.serverTimestamp();
        sanitized.updatedAt = FieldValue.serverTimestamp();
        // Preserve original createdAt (Firestore Timestamp from original doc)
      sanitized.createdAt = originalProduct.createdAt || FieldValue.serverTimestamp();
  
        await db
          .collection('product_edit_applications')
          .doc(editApplicationId)
          .set(sanitized);
  
        console.log(
          `✅ Edit application created: ${editApplicationId} for product: ${originalProductId} by user: ${uid} (type: ${editType})`
        );
  
        return {
          success: true,
          applicationId: editApplicationId,
          originalProductId,
          editType,
          editedFieldCount: editedFields.length,
          message: isArchivedEdit ?
            'Product update submitted for review. It will be reactivated upon approval.' :
            'Product edit submitted for approval.',
        };
      } catch (error) {
        console.error(`❌ Failed to create edit application: ${error.message}`);
        throw new HttpsError(
          'internal',
          'Failed to save edit. Please try again.'
        );
      }
    }
  );
  
