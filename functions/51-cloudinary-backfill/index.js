// functions/migrations/migrateImagePaths.js
// ===================================================================
// ONE-TIME MIGRATION: Backfill imageStoragePaths from imageUrls
//
// Run once via: firebase functions:shell → migrateProductImagePaths()
// Or deploy and call from admin panel.
//
// What it does:
// 1. Reads all product documents across all collections
// 2. Extracts Firebase Storage paths from download URLs
// 3. Writes imageStoragePaths, videoStoragePath, colorImageStoragePaths
// 4. Keeps original URL fields untouched (backward compat)
//
// Safe to run multiple times — skips docs that already have paths.
// ===================================================================

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';

// ── URL → Path extraction ───────────────────────────────────────────

function extractStoragePath(url) {
  if (!url || typeof url !== 'string') return null;

  try {
    // Format 1: firebasestorage.googleapis.com/v0/b/BUCKET/o/ENCODED_PATH?...
    if (url.includes('firebasestorage.googleapis.com')) {
      const match = url.match(/\/o\/([^?]+)/);
      if (match) {
        return decodeURIComponent(match[1]);
      }
    }

    // Format 2: storage.googleapis.com/BUCKET/PATH
    if (url.includes('storage.googleapis.com')) {
      const urlObj = new URL(url);
      // Remove leading /BUCKET_NAME/ from path
      const segments = urlObj.pathname.split('/').filter(Boolean);
      if (segments.length > 1) {
        return segments.slice(1).join('/');
      }
    }

    // Format 3: Already a path (no http)
    if (!url.startsWith('http')) {
      return url;
    }

    return null;
  } catch (e) {
    console.warn(`Failed to extract path from URL: ${url}`, e.message);
    return null;
  }
}

function extractColorPaths(colorImages) {
  if (!colorImages || typeof colorImages !== 'object') return {};

  const result = {};
  for (const [color, urls] of Object.entries(colorImages)) {
    if (Array.isArray(urls) && urls.length > 0) {
      const path = extractStoragePath(urls[0]);
      if (path) {
        result[color] = path;
      }
    } else if (typeof urls === 'string') {
      const path = extractStoragePath(urls);
      if (path) {
        result[color] = path;
      }
    }
  }
  return result;
}

// ── Migration logic ─────────────────────────────────────────────────

async function migrateCollection(db, collectionName, dryRun = false) {
  const stats = { total: 0, migrated: 0, skipped: 0, errors: 0 };

  console.log(`\n📂 Processing collection: ${collectionName}`);

  const snapshot = await db.collection(collectionName).get();
  stats.total = snapshot.size;

  if (stats.total === 0) {
    console.log(`   Empty collection, skipping.`);
    return stats;
  }

  // Process in batches of 500 (Firestore batch limit)
  const batchSize = 500;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // Skip if already migrated
    if (
      data.imageStoragePaths &&
      Array.isArray(data.imageStoragePaths) &&
      data.imageStoragePaths.length > 0
    ) {
      stats.skipped++;
      continue;
    }

    // Skip if no imageUrls to migrate from
    if (!data.imageUrls || !Array.isArray(data.imageUrls) || data.imageUrls.length === 0) {
      stats.skipped++;
      continue;
    }

    // Extract paths
    const imageStoragePaths = data.imageUrls
      .map(extractStoragePath)
      .filter(Boolean);

    const videoStoragePath = data.videoUrl ? extractStoragePath(data.videoUrl) : null;

    const colorImageStoragePaths = extractColorPaths(data.colorImages);

    // Only write if we extracted at least one path
    if (imageStoragePaths.length === 0) {
      stats.skipped++;
      continue;
    }

    const update = {
      imageStoragePaths,
      ...(videoStoragePath && { videoStoragePath }),
      ...(Object.keys(colorImageStoragePaths).length > 0 && { colorImageStoragePaths }),
    };

    if (dryRun) {
      console.log(`   [DRY RUN] ${doc.id}: ${imageStoragePaths.length} images, video: ${!!videoStoragePath}, colors: ${Object.keys(colorImageStoragePaths).length}`);
    } else {
      batch.update(doc.ref, update);
      batchCount++;

      if (batchCount >= batchSize) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
        console.log(`   Committed batch (${stats.migrated + batchCount} so far)`);
      }
    }

    stats.migrated++;
  }

  // Commit remaining
  if (!dryRun && batchCount > 0) {
    await batch.commit();
  }

  console.log(`   ✅ ${collectionName}: ${stats.migrated} migrated, ${stats.skipped} skipped, ${stats.errors} errors (of ${stats.total} total)`);
  return stats;
}

// ── Callable Cloud Function ─────────────────────────────────────────

export const migrateProductImagePaths = onCall(
  {
    region: 'europe-west3',
    maxInstances: 1,
    timeoutSeconds: 540, // 9 minutes (max for gen2)
    memory: '1GiB',
  },
  async (request) => {
    // Admin-only
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }

    // Optional: restrict to admin users
    // if (!request.auth.token.isAdmin) {
    //   throw new HttpsError('permission-denied', 'Admin access required.');
    // }

    const dryRun = request.data?.dryRun === true;
    const db = getFirestore();

    // All collections that store product documents with imageUrls
    const collections = [
      'shop_products',
      'products',
      'paused_shop_products',
      'product_applications',
      'product_edit_applications',
      'vitrin_product_applications',
      'vitrin_edit_product_applications',
    ];

    console.log(`\n🚀 Starting migration (dryRun: ${dryRun})`);

    const results = {};
    let totalMigrated = 0;

    for (const collection of collections) {
      try {
        const stats = await migrateCollection(db, collection, dryRun);
        results[collection] = stats;
        totalMigrated += stats.migrated;
      } catch (error) {
        console.error(`❌ Error migrating ${collection}:`, error.message);
        results[collection] = { error: error.message };
      }
    }

    const summary = `Migration ${dryRun ? '(DRY RUN) ' : ''}complete: ${totalMigrated} documents updated across ${collections.length} collections.`;
    console.log(`\n${summary}`);

    return {
      success: true,
      dryRun,
      summary,
      results,
    };
  }
);
