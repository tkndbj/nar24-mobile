// ── 50-cloudinary/index.js ──────────────────────────────────────────
//
// Cloudinary integration — Auto Upload architecture.
//
// Source of truth: Firebase Storage (you own the files)
// CDN/transforms:  Cloudinary Auto Upload (fetches from your bucket)
//
// This file provides:
//   1. deleteCloudinaryCache — Invalidate Cloudinary cache when product deleted
//   2. validateStoragePaths  — Validate storage paths belong to user
//   3. sanitizeStoragePath   — Clean path strings
// ─────────────────────────────────────────────────────────────────────

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

const cloudinaryApiSecret = defineSecret('CLOUDINARY_API_SECRET');
const cloudinaryApiKey = defineSecret('CLOUDINARY_API_KEY');
const cloudinaryCloudName = defineSecret('CLOUDINARY_CLOUD_NAME');

// ── Auto-upload folder name (must match Cloudinary dashboard config) ──
// This is the folder prefix Cloudinary uses for auto-uploaded assets.
const AUTO_UPLOAD_FOLDER = 'fb';

// ─────────────────────────────────────────────────────────────────────
// 1. Cache Invalidation
//
// When a product is deleted, call this to purge Cloudinary's cached
// copies. The source files in Firebase Storage are deleted separately
// via your existing Storage cleanup logic.
// ─────────────────────────────────────────────────────────────────────

export const deleteCloudinaryCache = onCall(
  {
    region: 'europe-west3',
    maxInstances: 50,
    timeoutSeconds: 30,
    memory: '128MiB',
    secrets: [cloudinaryApiSecret, cloudinaryApiKey, cloudinaryCloudName],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }

    const { storagePaths, resourceType = 'image' } = request.data || {};

    if (!Array.isArray(storagePaths) || storagePaths.length === 0) {
      throw new HttpsError('invalid-argument', 'storagePaths array is required.');
    }

    // Security: paths must belong to this user
    const uid = request.auth.uid;
    const unauthorized = storagePaths.filter(
      (p) => !p.startsWith(`products/${uid}/`)
    );
    if (unauthorized.length > 0) {
      throw new HttpsError('permission-denied', 'You can only delete your own assets.');
    }

    try {
      const apiKey = cloudinaryApiKey.value();
      const apiSecret = cloudinaryApiSecret.value();
      const cloudName = cloudinaryCloudName.value();
      const basicAuth = Buffer.from(`${apiKey}:${apiSecret}`).toString('base64');

      // Convert storage paths to Cloudinary public_ids
      // Storage path: products/uid/main/image.jpg
      // Cloudinary id: fb/products/uid/main/image (no extension)
      const publicIds = storagePaths.map((p) => {
        const withoutExt = p.replace(/\.[^/.]+$/, '');
        return `${AUTO_UPLOAD_FOLDER}/${withoutExt}`;
      });

      // Batch delete (max 100 per request)
      const results = [];
      for (let i = 0; i < publicIds.length; i += 100) {
        const batch = publicIds.slice(i, i + 100);
        const params = new URLSearchParams();
        batch.forEach((id) => params.append('public_ids[]', id));

        const response = await fetch(
          `https://api.cloudinary.com/v1_1/${cloudName}/resources/${resourceType}/upload?${params.toString()}`,
          {
            method: 'DELETE',
            headers: { 'Authorization': `Basic ${basicAuth}` },
          }
        );
        results.push(await response.json());
      }

      return { success: true, result: results };
    } catch (error) {
      console.error('Cloudinary cache invalidation failed:', error);
      throw new HttpsError('internal', 'Failed to invalidate cache.');
    }
  }
);

// ─────────────────────────────────────────────────────────────────────
// 2. Validation — use in submitProduct / submitProductEdit
// ─────────────────────────────────────────────────────────────────────

export function validateStoragePaths(data, uid) {
  const errors = [];
  const prefix = `products/${uid}/`;

  // Main images
  const imagePaths = data.imageStoragePaths;
  if (!Array.isArray(imagePaths) || imagePaths.length === 0) {
    errors.push('At least one product image is required.');
  } else {
    for (let i = 0; i < imagePaths.length; i++) {
      const p = imagePaths[i];
      if (typeof p !== 'string' || p.length === 0) {
        errors.push(`imageStoragePaths[${i}] must be a non-empty string.`);
      } else if (!p.startsWith(prefix)) {
        errors.push(`imageStoragePaths[${i}] does not belong to your account.`);
      } else if (p.includes('..') || p.includes('//')) {
        errors.push(`imageStoragePaths[${i}] contains invalid path segments.`);
      }
    }
    if (imagePaths.length > 10) {
      errors.push('Maximum 10 product images allowed.');
    }
  }

  // Video
  if (data.videoStoragePath) {
    if (typeof data.videoStoragePath !== 'string') {
      errors.push('videoStoragePath must be a string.');
    } else if (!data.videoStoragePath.startsWith(prefix)) {
      errors.push('videoStoragePath does not belong to your account.');
    }
  }

  // Color images
  if (data.colorImageStoragePaths && typeof data.colorImageStoragePaths === 'object') {
    for (const [color, p] of Object.entries(data.colorImageStoragePaths)) {
      if (typeof p !== 'string' || p.length === 0) {
        errors.push(`colorImageStoragePaths["${color}"] must be a non-empty string.`);
      } else if (!p.startsWith(prefix)) {
        errors.push(`colorImageStoragePaths["${color}"] does not belong to your account.`);
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

export function sanitizeStoragePath(path) {
  if (typeof path !== 'string') return '';
  return path
    .replace(/\.\./g, '')
    .replace(/\/\//g, '/')
    .replace(/[<>'"]/g, '')
    .trim();
}
