import admin from 'firebase-admin';
import Typesense from 'typesense';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
import mod from '../i18n.cjs';

const {localize} = mod;
const SUPPORTED_LOCALES = ['en', 'tr', 'ru'];

// Init Firebase Admin
admin.initializeApp({projectId: 'emlak-mobile-app'});
const db = admin.firestore();
const secretClient = new SecretManagerServiceClient();

async function getSecret(name) {
  const [version] = await secretClient.accessSecretVersion({name});
  return version.payload.data.toString('utf8');
}

async function getTypesenseClient() {
  const [host, adminKey] = await Promise.all([
    getSecret('projects/emlak-mobile-app/secrets/TYPESENSE_HOST/versions/latest'),
    getSecret('projects/emlak-mobile-app/secrets/TYPESENSE_ADMIN_KEY/versions/latest'),
  ]);
  return new Typesense.Client({
    nodes: [{host, port: 443, protocol: 'https'}],
    apiKey: adminKey,
    connectionTimeoutSeconds: 10,
  });
}

const toUnixSeconds = (val) => {
  if (!val) return null;
  if (typeof val === 'number') return val;
  if (val._seconds != null) return val._seconds;
  if (val.seconds != null) return val.seconds;
  if (val.toMillis) return Math.floor(val.toMillis() / 1000);
  return null;
};

const localizeProduct = (data) => {
  const localizedFields = {};
  for (const locale of SUPPORTED_LOCALES) {
    try {
       localizedFields[`category_${locale}`] = localize('category', data.category, locale);
       } catch (e) {
         localizedFields[`category_${locale}`] = data.category;
         }
    try {
       localizedFields[`subcategory_${locale}`] = localize('subcategory', data.subcategory, locale);
       } catch (e) {
         localizedFields[`subcategory_${locale}`] = data.subcategory;
         }
    try {
       localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', data.subsubcategory, locale);
       } catch (e) {
         localizedFields[`subsubcategory_${locale}`] = data.subsubcategory;
         }
    if (data.jewelryType) {
      try {
         localizedFields[`jewelryType_${locale}`] = localize('jewelryType', data.jewelryType, locale);
         } catch (e) {
           localizedFields[`jewelryType_${locale}`] = data.jewelryType;
           }
    }
    if (Array.isArray(data.jewelryMaterials)) {
      localizedFields[`jewelryMaterials_${locale}`] = data.jewelryMaterials.map((mat) => {
        try {
           return localize('jewelryMaterial', mat, locale);
           } catch (e) {
             return mat;
             }
      });
    }
  }
  return localizedFields;
};

const buildProductDoc = (id, collectionName, data) => {
  const localized = localizeProduct(data);
  const merged = {...data, ...localized};
  const d = {id: `${collectionName}_${id}`};

  const pick = (key) => {
     if (merged[key] != null) d[key] = merged[key];
     };
  const pickArr = (key) => {
     if (Array.isArray(merged[key]) && merged[key].length > 0) d[key] = merged[key];
     };

  // Core
  pick('productName');
  pick('price');
  pick('originalPrice');
  pick('discountPercentage');
  pick('condition');
  pick('currency');
  pick('description');
  pick('videoUrl');
  pick('sellerName');
  pick('ownerId');
  pick('quantity');
  pick('paused');
  pick('reviewCount');
  pick('clickCount');
  pick('bestSellerRank');
  pick('discountThreshold');
  pick('bulkDiscountPercentage');
  pickArr('imageUrls');
  pickArr('bundleIds');

  // colorImages and colorQuantities are nested maps — store as JSON string
  if (data.colorImages && typeof data.colorImages === 'object' && !Array.isArray(data.colorImages)) {
    d.colorImagesJson = JSON.stringify(data.colorImages);
  }
  if (data.colorQuantities && typeof data.colorQuantities === 'object' && !Array.isArray(data.colorQuantities)) {
    d.colorQuantitiesJson = JSON.stringify(data.colorQuantities);
  }

  // Classification
  pick('category');
  pick('subcategory');
  pick('subsubcategory');
  pick('productType');
  pick('gender');
  pick('brandModel');
  pick('clothingFit');
  pick('consoleBrand');
  pick('curtainMaxWidth');
  pick('curtainMaxHeight');
  pick('shopId');
  pick('userId');
  pick('jewelryType');
  pickArr('availableColors');
  pickArr('clothingSizes');
  pickArr('clothingTypes');
  pickArr('pantSizes');
  pickArr('pantFabricTypes');
  pickArr('footwearSizes');
  pickArr('jewelryMaterials');

  // Boost & stats
  pick('promotionScore');
  pick('isBoosted');
  pick('isFeatured');
  pick('campaignName');
  pick('averageRating');
  pick('purchaseCount');
  pick('deliveryOption');

  // Localized fields
  for (const locale of SUPPORTED_LOCALES) {
    pick(`category_${locale}`);
    pick(`subcategory_${locale}`);
    pick(`subsubcategory_${locale}`);
    pick(`jewelryType_${locale}`);
    pickArr(`jewelryMaterials_${locale}`);
  }

  // Timestamp
  const ts = toUnixSeconds(data.createdAt);
  if (ts != null) d.createdAt = ts;

  // promotionScore must never be null (it's the default_sorting_field)
  if (d.promotionScore == null) d.promotionScore = 0;

  return d;
};

async function backfillCollection(client, firestoreCollection, typesenseCollection, buildDocFn) {
  console.log(`\nBackfilling ${firestoreCollection}...`);
  const snapshot = await db.collection(firestoreCollection).get();
  console.log(`Found ${snapshot.size} documents`);

  const BATCH_SIZE = 100;
  const docs = snapshot.docs;
  let success = 0;
  let failed = 0;

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = docs.slice(i, i + BATCH_SIZE);
    const typesenseDocs = batch.map((doc) => buildDocFn(doc.id, doc.data())).filter(Boolean);

    try {
      const results = await client.collections(typesenseCollection).documents().import(typesenseDocs, {action: 'upsert'});
      const parsed = typeof results === 'string' ? results.split('\n').map((r) => JSON.parse(r)) : results;
      const batchSuccess = parsed.filter((r) => r.success).length;
      const batchFailed = parsed.filter((r) => !r.success);
      success += batchSuccess;
      failed += batchFailed.length;
      if (batchFailed.length > 0) console.error('Failed docs:', JSON.stringify(batchFailed, null, 2));
      console.log(`  Batch ${Math.floor(i / BATCH_SIZE) + 1}: ${batchSuccess}/${batch.length} succeeded`);
    } catch (e) {
      console.error(`  Batch error:`, e.message);
      failed += batch.length;
    }
  }

  console.log(`✓ ${firestoreCollection} done: ${success} succeeded, ${failed} failed`);
}

async function backfillOrders(client) {
  console.log(`\nBackfilling orders...`);
  const ordersSnapshot = await db.collection('orders').get();
  const allItems = [];

  for (const orderDoc of ordersSnapshot.docs) {
    const itemsSnapshot = await orderDoc.ref.collection('items').get();
    itemsSnapshot.docs.forEach((itemDoc) => {
      const data = itemDoc.data();
      const doc = {
        id: `orders_${itemDoc.id}`,
        productName: data.productName || null,
        price: data.price || null,
        category: data.category || null,
        subcategory: data.subcategory || null,
        brandModel: data.brandModel || null,
        shipmentStatus: data.shipmentStatus || null,
        buyerName: data.buyerName || null,
        sellerName: data.sellerName || null,
        timestampForSorting: data.timestamp?.seconds || Math.floor(Date.now() / 1000),
        searchableText: [
          data.productName, data.buyerName, data.sellerName,
          data.brandModel, data.category, data.subcategory,
          data.condition, data.shipmentStatus,
        ].filter(Boolean).join(' '),
      };
      Object.keys(doc).forEach((k) => doc[k] == null && delete doc[k]);
      allItems.push(doc);
    });
  }

  console.log(`Found ${allItems.length} order items`);
  if (allItems.length === 0) return;

  const BATCH_SIZE = 100;
  let success = 0;
  let failed = 0;

  for (let i = 0; i < allItems.length; i += BATCH_SIZE) {
    const batch = allItems.slice(i, i + BATCH_SIZE);
    try {
      const results = await client.collections('orders').documents().import(batch, {action: 'upsert'});
      const parsed = typeof results === 'string' ? results.split('\n').map((r) => JSON.parse(r)) : results;
      success += parsed.filter((r) => r.success).length;
      failed += parsed.filter((r) => !r.success).length;
    } catch (e) {
      console.error(`Batch error:`, e.message);
      failed += batch.length;
    }
  }
  console.log(`✓ orders done: ${success} succeeded, ${failed} failed`);
}

async function main() {
  const client = await getTypesenseClient();

  await backfillCollection(client, 'products', 'products',
    (id, data) => buildProductDoc(id, 'products', data));

  await backfillCollection(client, 'shop_products', 'shop_products',
    (id, data) => buildProductDoc(id, 'shop_products', data));

  await backfillCollection(client, 'shops', 'shops', (id, data) => {
    const doc = {
      id: `shops_${id}`,
      name: data.name || null,
      profileImageUrl: data.profileImageUrl || null,
      isActive: data.isActive ?? true,
      categories: Array.isArray(data.categories) && data.categories.length > 0 ? data.categories : undefined,
      searchableText: [data.name, ...(data.categories || [])].filter(Boolean).join(' '),
    };
    Object.keys(doc).forEach((k) => doc[k] == null && delete doc[k]);
    return doc;
  });

  await backfillOrders(client);

  console.log('\n✅ Backfill complete!');
  process.exit(0);
}

main().catch((e) => {
  console.error('Backfill failed:', e);
  process.exit(1);
});
