// functions/migrations/migrateImagePaths.js
// ===================================================================
// MIGRATION: Backfill storage paths from download URLs
//
// Targets: products, ads, shops, restaurants
// Call from admin panel with { target: 'ads', dryRun: false }
//
// What it does:
// 1. Reads documents across configured collections
// 2. Extracts Firebase Storage paths from download URLs
// 3. Writes *StoragePath fields alongside original URL fields
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


// ── Field migration configs ─────────────────────────────────────────

const MIGRATION_TARGETS = {
  ads: [
    { collection: 'ad_submissions',        fields: [{ from: 'imageUrl', to: 'imageStoragePath', type: 'single' }] },
    { collection: 'market_top_ads_banners', fields: [{ from: 'imageUrl', to: 'imageStoragePath', type: 'single' }] },
    { collection: 'market_thin_banners',    fields: [{ from: 'imageUrl', to: 'imageStoragePath', type: 'single' }] },
    { collection: 'market_banners',         fields: [{ from: 'imageUrl', to: 'imageStoragePath', type: 'single' }] },
  ],
  shops: [
    {
      collection: 'shopApplications',
      fields: [
        { from: 'profileImageUrl',          to: 'profileImageStoragePath',     type: 'single' },
        { from: 'coverImageUrl',            to: 'coverImageStoragePaths',      type: 'csv' },    // comma-separated → array
        { from: 'taxPlateCertificateUrl',   to: 'taxCertificateStoragePath',   type: 'single' },
      ],
    },
    {
      collection: 'shops',
      fields: [
        { from: 'profileImageUrl',          to: 'profileImageStoragePath',     type: 'single' },
        { from: 'coverImageUrls',           to: 'coverImageStoragePaths',      type: 'array' },  // string[] → string[]
        { from: 'taxPlateCertificateUrl',   to: 'taxCertificateStoragePath',   type: 'single' },
      ],
    },
  ],
  restaurants: [
    {
      collection: 'restaurantApplications',
      fields: [
        { from: 'profileImageUrl',          to: 'profileImageStoragePath',     type: 'single' },
        { from: 'taxPlateCertificateUrl',   to: 'taxCertificateStoragePath',   type: 'single' },
      ],
    },
    {
      collection: 'restaurants',
      fields: [
        { from: 'profileImageUrl',          to: 'profileImageStoragePath',     type: 'single' },
        { from: 'taxPlateCertificateUrl',   to: 'taxCertificateStoragePath',   type: 'single' },
      ],
    },
    {
      collection: 'restaurant_banners',
      fields: [
        { from: 'imageUrl', to: 'imageStoragePath', type: 'single' },
      ],
    },
  ],
  foods: [
    {
      collection: 'foods',
      fields: [
        { from: 'imageUrl', to: 'imageStoragePath', type: 'single' },
      ],
    },
  ],
  products: [
    { collection: 'shop_products',                  fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'products',                       fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'paused_shop_products',           fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'product_applications',           fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'product_edit_applications',      fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'vitrin_product_applications',    fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
    { collection: 'vitrin_edit_product_applications', fields: [{ from: 'imageUrls', to: 'imageStoragePaths', type: 'array' }, { from: 'videoUrl', to: 'videoStoragePath', type: 'single' }, { from: 'colorImages', to: 'colorImageStoragePaths', type: 'colorMap' }] },
  ],
  marketItems: [
    {
      collection: 'market-items',
      fields: [
        { from: 'imageUrl',  to: 'imageStoragePath',  type: 'single' },
        { from: 'imageUrls', to: 'imageStoragePaths', type: 'array' },
      ],
    },
  ],
};

// ── Extract path from any field type ────────────────────────────────

function extractFieldPaths(data, field) {
  const sourceValue = data[field.from];
  if (sourceValue === undefined || sourceValue === null) return null;

  // Skip if target already populated
  const existing = data[field.to];

  switch (field.type) {
    case 'single': {
      if (existing && typeof existing === 'string') return null; // already migrated
      if (typeof sourceValue !== 'string' || !sourceValue) return null;
      const path = extractStoragePath(sourceValue);
      return path ? { [field.to]: path } : null;
    }

    case 'array': {
      if (Array.isArray(existing) && existing.length > 0) return null; // already migrated
      if (!Array.isArray(sourceValue) || sourceValue.length === 0) return null;
      const paths = sourceValue.map(extractStoragePath).filter(Boolean);
      return paths.length > 0 ? { [field.to]: paths } : null;
    }

    case 'csv': {
      // comma-separated URL string → array of paths
      if (Array.isArray(existing) && existing.length > 0) return null;
      if (typeof sourceValue !== 'string' || !sourceValue) return null;
      const urls = sourceValue.split(',').map((u) => u.trim()).filter(Boolean);
      const paths = urls.map(extractStoragePath).filter(Boolean);
      return paths.length > 0 ? { [field.to]: paths } : null;
    }

    case 'colorMap': {
      // { color: [url, ...] } → { color: path }
      if (existing && typeof existing === 'object' && Object.keys(existing).length > 0) return null;
      if (!sourceValue || typeof sourceValue !== 'object') return null;
      const result = {};
      for (const [color, urls] of Object.entries(sourceValue)) {
        if (Array.isArray(urls) && urls.length > 0) {
          const path = extractStoragePath(urls[0]);
          if (path) result[color] = path;
        } else if (typeof urls === 'string') {
          const path = extractStoragePath(urls);
          if (path) result[color] = path;
        }
      }
      return Object.keys(result).length > 0 ? { [field.to]: result } : null;
    }

    default:
      return null;
  }
}

// ── Generic collection migrator ─────────────────────────────────────

async function migrateGenericCollection(db, collectionName, fields, dryRun = false) {
  const stats = { total: 0, migrated: 0, skipped: 0, errors: 0 };

  console.log(`\n📂 Processing: ${collectionName} (${fields.length} field(s))`);

  const snapshot = await db.collection(collectionName).get();
  stats.total = snapshot.size;

  if (stats.total === 0) {
    console.log(`   Empty collection, skipping.`);
    return stats;
  }

  const batchSize = 500;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // Merge all field extractions for this document
    const update = {};
    for (const field of fields) {
      const extracted = extractFieldPaths(data, field);
      if (extracted) {
        Object.assign(update, extracted);
      }
    }

    if (Object.keys(update).length === 0) {
      stats.skipped++;
      continue;
    }

    if (dryRun) {
      console.log(`   [DRY RUN] ${doc.id}: ${JSON.stringify(Object.keys(update))}`);
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

  if (!dryRun && batchCount > 0) {
    await batch.commit();
  }

  console.log(`   ✅ ${collectionName}: ${stats.migrated} migrated, ${stats.skipped} skipped (of ${stats.total} total)`);
  return stats;
}


export const migrateImagePaths = onCall(
  {
    region: 'europe-west3',
    maxInstances: 1,
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentication required.');
    }

    const dryRun = request.data?.dryRun === true;
    // 'products' | 'ads' | 'shops' | 'restaurants' | 'all'
    const target = request.data?.target || 'all';
    const db = getFirestore();

    const validTargets = Object.keys(MIGRATION_TARGETS);

    // Determine which targets to run
    const targetsToRun = target === 'all' ?
      validTargets :
      validTargets.filter((t) => t === target);

    if (targetsToRun.length === 0) {
      throw new HttpsError('invalid-argument', `Invalid target: ${target}. Valid: ${validTargets.join(', ')}, all`);
    }

    console.log(`\n🚀 Starting migration (dryRun: ${dryRun}, target: ${target})`);

    const results = {};
    let totalMigrated = 0;

    for (const targetKey of targetsToRun) {
      console.log(`\n━━━ Target: ${targetKey} ━━━`);
      const configs = MIGRATION_TARGETS[targetKey];

      for (const config of configs) {
        try {
          const stats = await migrateGenericCollection(
            db, config.collection, config.fields, dryRun
          );
          results[config.collection] = stats;
          totalMigrated += stats.migrated;
        } catch (error) {
          console.error(`❌ Error migrating ${config.collection}:`, error.message);
          results[config.collection] = { error: error.message };
        }
      }
    }

    const summary = `Migration ${dryRun ? '(DRY RUN) ' : ''}complete: ${totalMigrated} documents updated (target: ${target}).`;
    console.log(`\n${summary}`);

    return { success: true, dryRun, target, summary, results };
  }
);
