// functions/utils/validation.js
// ===================================================================
// SHARED VALIDATION & SANITIZATION UTILITIES
// ===================================================================

// ===================================================================
// STRING SANITIZATION
// ===================================================================

/**
 * Sanitize a string value - trim, ensure it's a string, return fallback if empty.
 * @param {*} value - The value to sanitize.
 * @param {string} fallback - Fallback if value is empty.
 * @return {string} Sanitized string.
 */
export function sanitizeString(value, fallback = '') {
    if (value === null || value === undefined) return fallback;
    const str = String(value).trim();
    return str.length > 0 ? str : fallback;
  }
  
  /**
   * Sanitize to a number, return fallback if invalid.
   * @param {*} value - The value to sanitize.
   * @param {number} fallback - Fallback if value is invalid.
   * @return {number} Sanitized number.
   */
  export function sanitizeNumber(value, fallback = 0) {
    if (value === null || value === undefined) return fallback;
    const num = Number(value);
    return isNaN(num) ? fallback : num;
  }
  
  /**
   * Sanitize to a positive integer, return fallback if invalid.
   * @param {*} value - The value to sanitize.
   * @param {number} fallback - Fallback if value is invalid.
   * @return {number} Sanitized integer.
   */
  export function sanitizeInteger(value, fallback = 0) {
    if (value === null || value === undefined) return fallback;
    const num = parseInt(value, 10);
    return isNaN(num) ? fallback : num;
  }
  
  /**
   * Sanitize a value for Firestore - convert undefined to null recursively.
   * @param {*} obj - The object to sanitize.
   * @return {*} Sanitized object safe for Firestore.
   */
  export function sanitizeForFirestore(obj) {
    if (obj === undefined) return null;
    if (obj === null) return null;
    if (typeof obj !== 'object') return obj;
    if (obj instanceof Date) return obj;
    if (Array.isArray(obj)) return obj.map(sanitizeForFirestore);
  
    // Preserve Firestore Timestamps and FieldValue sentinels
    if (obj.constructor && obj.constructor.name === 'Timestamp') return obj;
    if (obj.constructor && obj.constructor.name === 'FieldValue') return obj;
    if (typeof obj.toDate === 'function') return obj;
    if (typeof obj.isEqual === 'function' && obj._methodName) return obj;
  
    const sanitized = {};
    for (const key of Object.keys(obj)) {
      const value = obj[key];
      if (value === undefined) {
        sanitized[key] = null;
      } else if (value !== null && typeof value === 'object' && !(value instanceof Date)) {
        sanitized[key] = sanitizeForFirestore(value);
      } else {
        sanitized[key] = value;
      }
    }
    return sanitized;
  }
  
  // ===================================================================
  // FIELD VALIDATION
  // ===================================================================
  
  /**
   * Validate required product fields.
   * @param {Object} data - Product data to validate.
   * @return {{valid: boolean, errors: string[]}} Validation result.
   */
  export function validateProductFields(data) {
    const errors = [];
  
    const requiredStrings = [
      {field: 'productName', label: 'Product name'},
      {field: 'description', label: 'Description'},
      {field: 'category', label: 'Category'},
      {field: 'subcategory', label: 'Subcategory'},
      {field: 'subsubcategory', label: 'Sub-subcategory'},
      {field: 'condition', label: 'Condition'},
      {field: 'deliveryOption', label: 'Delivery option'},
      {field: 'shopId', label: 'Shop ID'},
    ];
  
    for (const {field, label} of requiredStrings) {
      if (!data[field] || String(data[field]).trim().length === 0) {
        errors.push(`${label} is required.`);
      }
    }
  
    const price = Number(data.price);
    if (isNaN(price) || price <= 0) {
      errors.push('Price must be greater than 0.');
    }
  
    const quantity = parseInt(data.quantity, 10);
    if (isNaN(quantity) || quantity <= 0) {
      errors.push('Quantity must be greater than 0.');
    }
  
    if (!data.imageUrls || !Array.isArray(data.imageUrls) || data.imageUrls.length === 0) {
      errors.push('At least one product image is required.');
    }
  
    const allowedConditions = ['Brand New', 'Used', 'Refurbished'];
    if (data.condition && !allowedConditions.includes(data.condition)) {
      errors.push(`Invalid condition. Allowed: ${allowedConditions.join(', ')}`);
    }
  
    const allowedDelivery = ['Fast Delivery', 'Self Delivery'];
    if (data.deliveryOption && !allowedDelivery.includes(data.deliveryOption)) {
      errors.push(`Invalid delivery option. Allowed: ${allowedDelivery.join(', ')}`);
    }
  
    return {
      valid: errors.length === 0,
      errors,
    };
  }
  
  // ===================================================================
  // FIREBASE STORAGE URL VALIDATION
  // ===================================================================
  
  /**
   * Verify that a URL is a valid Firebase Storage download URL from this project.
   * @param {string} url - The URL to validate.
   * @param {string} projectBucket - The Firebase Storage bucket name.
   * @return {boolean} True if the URL is valid.
   */
  export function isValidFirebaseStorageUrl(url, projectBucket) {
    if (!url || typeof url !== 'string') return false;
  
    const patterns = [
      `https://firebasestorage.googleapis.com/v0/b/${projectBucket}/`,
      `https://storage.googleapis.com/${projectBucket}/`,
    ];
  
    return patterns.some((pattern) => url.startsWith(pattern));
  }
  
  /**
   * Validate all URLs in the product data belong to our Firebase Storage.
   * @param {Object} data - Product data containing URLs.
   * @param {string} projectBucket - The Firebase Storage bucket name.
   * @return {{valid: boolean, errors: string[]}} Validation result.
   */
  export function validateStorageUrls(data, projectBucket) {
    const errors = [];
  
    if (data.imageUrls && Array.isArray(data.imageUrls)) {
      for (let i = 0; i < data.imageUrls.length; i++) {
        if (!isValidFirebaseStorageUrl(data.imageUrls[i], projectBucket)) {
          errors.push(`Invalid storage URL for image ${i + 1}.`);
        }
      }
    }
  
    if (data.videoUrl && !isValidFirebaseStorageUrl(data.videoUrl, projectBucket)) {
      errors.push('Invalid storage URL for video.');
    }
  
    if (data.colorImages && typeof data.colorImages === 'object') {
      for (const [color, urls] of Object.entries(data.colorImages)) {
        if (Array.isArray(urls)) {
          for (const url of urls) {
            if (!isValidFirebaseStorageUrl(url, projectBucket)) {
              errors.push(`Invalid storage URL for color image: ${color}.`);
            }
          }
        }
      }
    }
  
    return {
      valid: errors.length === 0,
      errors,
    };
  }
  
  // ===================================================================
  // SHOP OWNERSHIP VERIFICATION
  // ===================================================================
  
  /**
   * Verify user is a member of the specified shop.
   * @param {Object} db - Firestore database instance.
   * @param {string} uid - User ID to verify.
   * @param {string} shopId - Shop ID to check membership for.
   * @return {Promise<boolean>} True if user is a member.
   */
  export async function verifyShopMembership(db, uid, shopId) {
    try {
      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;
  
      const userData = userDoc.data();
      const memberOfShops = userData?.memberOfShops;
  
      if (Array.isArray(memberOfShops) && memberOfShops.includes(shopId)) {
        return true;
      }
  
      const shopDoc = await db.collection('shops').doc(shopId).get();
      if (!shopDoc.exists) return false;
  
      const shopData = shopDoc.data();
      return shopData?.ownerId === uid || shopData?.userId === uid;
    } catch (error) {
      console.error('Shop membership verification failed:', error);
      return false;
    }
  }
  
  // ===================================================================
  // SPEC FIELD KEYS
  // ===================================================================
  
  /**
   * Known spec field keys that are stored top-level (not in attributes).
   * @type {string[]}
   */
  export const SPEC_FIELD_KEYS = [
    'clothingSizes',
    'clothingFit',
    'clothingTypes',
    'pantSizes',
    'pantFabricTypes',
    'footwearSizes',
    'jewelryMaterials',
    'consoleBrand',
    'curtainMaxWidth',
    'curtainMaxHeight',
  ];
  
  /**
   * Keys that should be extracted from attributes to top-level.
   * @type {string[]}
   */
  export const PROMOTED_ATTRIBUTE_KEYS = [
    'gender',
    'productType',
    ...SPEC_FIELD_KEYS,
    'clothingType',
    'pantFabricType',
  ];
  
  /**
   * Clean attributes: remove promoted keys, return only truly misc fields.
   * @param {Object} attributes - Raw attributes map.
   * @return {Object} Cleaned attributes with only misc fields.
   */
  export function cleanAttributes(attributes) {
    if (!attributes || typeof attributes !== 'object') return {};
  
    const cleaned = {...attributes};
  
    for (const key of PROMOTED_ATTRIBUTE_KEYS) {
      delete cleaned[key];
    }
  
    delete cleaned._deletedColors;
    delete cleaned._colorDeletionMode;
  
    return Object.keys(cleaned).length > 0 ? cleaned : {};
  }
