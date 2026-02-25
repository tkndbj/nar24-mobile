import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
import Typesense from 'typesense';
import mod from '../i18n.cjs';

const {localize} = mod;
const SUPPORTED_LOCALES = ['en', 'tr', 'ru'];
const secretClient = new SecretManagerServiceClient();

async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({name: secretName});
  return version.payload.data.toString('utf8');
}

// ─── Typesense Client ────────────────────────────────────────────────────────
let typesenseClient = null;
async function getTypesenseClient() {
  if (!typesenseClient) {
    const [host, adminKey] = await Promise.all([
      getSecret('projects/emlak-mobile-app/secrets/TYPESENSE_HOST/versions/latest'),
      getSecret('projects/emlak-mobile-app/secrets/TYPESENSE_ADMIN_KEY/versions/latest'),
    ]);
    typesenseClient = new Typesense.Client({
      nodes: [{host, port: 443, protocol: 'https'}],
      apiKey: adminKey,
      connectionTimeoutSeconds: 5,
    });
  }
  return typesenseClient;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
const toUnixSeconds = (val) => {
  if (!val) return null;
  if (typeof val === 'number') return val;
  if (val._seconds != null) return val._seconds;
  if (val.seconds != null) return val.seconds;
  if (val.toMillis) return Math.floor(val.toMillis() / 1000);
  return null;
};

// ─── Field comparison (handles arrays / objects that fail ===) ────────────────
const fieldChanged = (a, b) => {
  if (a === b) return false;
  if (a == null || b == null) return a !== b;
  if (Array.isArray(a) && Array.isArray(b)) return JSON.stringify(a) !== JSON.stringify(b);
  if (typeof a === 'object' && typeof b === 'object') return JSON.stringify(a) !== JSON.stringify(b);
  return a !== b;
};

// ─── Sanitize ─────────────────────────────────────────────────────────────────
const sanitizeForShopProducts = (data) => {
  const d = {};
  const pick = (key) => {
     if (data[key] != null) d[key] = data[key];
     };
  const pickArr = (key) => {
     if (Array.isArray(data[key]) && data[key].length > 0) d[key] = data[key];
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

  // colorImages: stored as map of string→string[] — Typesense can't index nested maps
  // so we store it as a JSON string and parse on the Flutter side
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

  // Boost
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

  const ts = toUnixSeconds(data.createdAt);
  if (ts != null) d.createdAt = ts;

  return d;
};

const sanitizeForProducts = (data) => sanitizeForShopProducts(data);

const sanitizeForShops = (data) => {
  const d = {};
  if (data.name != null) d.name = data.name;
  if (data.profileImageUrl != null) d.profileImageUrl = data.profileImageUrl;
  if (data.isActive != null) d.isActive = data.isActive;
  if (Array.isArray(data.categories) && data.categories.length > 0) d.categories = data.categories;
  if (data.searchableText != null) d.searchableText = data.searchableText;
  return d;
};

const sanitizeForOrders = (data) => {
  const d = {};
  const pick = (key) => {
     if (data[key] != null) d[key] = data[key];
    };
  pick('productName');
  pick('price');
  pick('category');
  pick('subcategory');
  pick('brandModel');
  pick('shipmentStatus');
  pick('buyerName');
  pick('sellerName');
  pick('buyerId');
  pick('sellerId');
  pick('shopId');
  pick('orderId');
  pick('productId');
  pick('searchableText');
  pick('timestampForSorting');
  return d;
};

// ─── Core sync helper ─────────────────────────────────────────────────────────
const syncDocumentToTypesense = async (collectionName, productId, beforeData, afterData, sanitizeFn) => {
  try {
    const client = await getTypesenseClient();
    const id = `${collectionName}_${productId}`;

    if (!beforeData && afterData) {
      const doc = {id, ...sanitizeFn(afterData)};
      await client.collections(collectionName).documents().upsert(doc);
      console.log(`[Typesense] ${collectionName}/${productId} created.`);
    } else if (beforeData && afterData) {
      const doc = {id, ...sanitizeFn(afterData)};
      await client.collections(collectionName).documents().upsert(doc);
      console.log(`[Typesense] ${collectionName}/${productId} updated.`);
    } else if (beforeData && !afterData) {
      await client.collections(collectionName).documents(id).delete();
      console.log(`[Typesense] ${collectionName}/${productId} deleted.`);
    }
  } catch (error) {
    console.error(`[Typesense] Error syncing ${collectionName}/${productId}:`, error);
    throw error;
  }
};

// ─── Collection schemas ───────────────────────────────────────────────────────
const initTypesenseCollections = async (dropExisting = false) => {
  const client = await getTypesenseClient();

  const productFields = [
    {name: 'id', type: 'string'},
    // Core
    {name: 'productName', type: 'string', optional: true},
    {name: 'price', type: 'float', optional: true},
    {name: 'originalPrice', type: 'float', optional: true},
    {name: 'discountPercentage', type: 'int32', optional: true},
    {name: 'condition', type: 'string', facet: true, optional: true},
    {name: 'currency', type: 'string', optional: true},
    {name: 'description', type: 'string', optional: true},
    {name: 'videoUrl', type: 'string', optional: true},
    {name: 'sellerName', type: 'string', optional: true},
    {name: 'ownerId', type: 'string', optional: true},
    {name: 'quantity', type: 'int32', optional: true},
    {name: 'paused', type: 'bool', optional: true},
    {name: 'reviewCount', type: 'int32', optional: true},
    {name: 'clickCount', type: 'int32', optional: true},
    {name: 'bestSellerRank', type: 'int32', optional: true},
    {name: 'discountThreshold', type: 'int32', optional: true},
    {name: 'bulkDiscountPercentage', type: 'int32', optional: true},
    {name: 'imageUrls', type: 'string[]', optional: true},
    {name: 'bundleIds', type: 'string[]', optional: true},
    {name: 'colorImagesJson', type: 'string', optional: true},
    {name: 'colorQuantitiesJson', type: 'string', optional: true},
    // Classification
    {name: 'category', type: 'string', facet: true, optional: true},
    {name: 'subcategory', type: 'string', facet: true, optional: true},
    {name: 'subsubcategory', type: 'string', facet: true, optional: true},
    {name: 'productType', type: 'string', facet: true, optional: true},
    {name: 'gender', type: 'string', facet: true, optional: true},
    // Localized
    {name: 'category_en', type: 'string', facet: true, optional: true},
    {name: 'subcategory_en', type: 'string', facet: true, optional: true},
    {name: 'subsubcategory_en', type: 'string', facet: true, optional: true},
    {name: 'category_tr', type: 'string', facet: true, optional: true},
    {name: 'subcategory_tr', type: 'string', facet: true, optional: true},
    {name: 'subsubcategory_tr', type: 'string', facet: true, optional: true},
    {name: 'category_ru', type: 'string', facet: true, optional: true},
    {name: 'subcategory_ru', type: 'string', facet: true, optional: true},
    {name: 'subsubcategory_ru', type: 'string', facet: true, optional: true},
    // Brand & colors
    {name: 'brandModel', type: 'string', facet: true, optional: true},
    {name: 'availableColors', type: 'string[]', facet: true, optional: true},
    // Clothing
    {name: 'clothingSizes', type: 'string[]', facet: true, optional: true},
    {name: 'clothingFit', type: 'string', facet: true, optional: true},
    {name: 'clothingTypes', type: 'string[]', facet: true, optional: true},
    // Pants
    {name: 'pantSizes', type: 'string[]', facet: true, optional: true},
    {name: 'pantFabricTypes', type: 'string[]', facet: true, optional: true},
    // Footwear
    {name: 'footwearSizes', type: 'string[]', facet: true, optional: true},
    // Jewelry
    {name: 'jewelryMaterials', type: 'string[]', facet: true, optional: true},
    {name: 'jewelryType', type: 'string', facet: true, optional: true},
    {name: 'jewelryType_en', type: 'string', facet: true, optional: true},
    {name: 'jewelryType_tr', type: 'string', facet: true, optional: true},
    {name: 'jewelryType_ru', type: 'string', facet: true, optional: true},
    {name: 'jewelryMaterials_en', type: 'string[]', facet: true, optional: true},
    {name: 'jewelryMaterials_tr', type: 'string[]', facet: true, optional: true},
    {name: 'jewelryMaterials_ru', type: 'string[]', facet: true, optional: true},
    // Electronics
    {name: 'consoleBrand', type: 'string', facet: true, optional: true},
    // Curtains
    {name: 'curtainMaxWidth', type: 'float', optional: true},
    {name: 'curtainMaxHeight', type: 'float', optional: true},
    // Boost
    {name: 'promotionScore', type: 'float'},
    {name: 'isBoosted', type: 'bool', optional: true},
    {name: 'isFeatured', type: 'bool', optional: true},
    {name: 'campaignName', type: 'string', facet: true, optional: true},
    // Stats
    {name: 'averageRating', type: 'float', optional: true},
    {name: 'purchaseCount', type: 'int32', optional: true},
    {name: 'deliveryOption', type: 'string', facet: true, optional: true},
    // Ownership
    {name: 'shopId', type: 'string', facet: true, optional: true},
    {name: 'userId', type: 'string', optional: true},
    // Timestamps
    {name: 'createdAt', type: 'int64', optional: true},
  ];

  const collections = [
    {name: 'shop_products', fields: productFields, default_sorting_field: 'promotionScore', token_separators: ['-', '_']},
    {name: 'products', fields: productFields, default_sorting_field: 'promotionScore', token_separators: ['-', '_']},
    {
      name: 'shops',
      fields: [
        {name: 'id', type: 'string'},
        {name: 'name', type: 'string', optional: true},
        {name: 'profileImageUrl', type: 'string', optional: true},
        {name: 'isActive', type: 'bool', optional: true},
        {name: 'categories', type: 'string[]', facet: true, optional: true},
        {name: 'searchableText', type: 'string', optional: true},
      ],
      token_separators: ['-', '_'],
    },
    {
      name: 'orders',
      fields: [
        {name: 'id', type: 'string'},
        {name: 'productName', type: 'string', optional: true},
        {name: 'price', type: 'float', optional: true},
        {name: 'category', type: 'string', facet: true, optional: true},
        {name: 'subcategory', type: 'string', facet: true, optional: true},
        {name: 'brandModel', type: 'string', facet: true, optional: true},
        {name: 'shipmentStatus', type: 'string', facet: true, optional: true},
        {name: 'buyerName', type: 'string', optional: true},
        {name: 'sellerName', type: 'string', optional: true},
        {name: 'buyerId', type: 'string', facet: true, optional: true},
        {name: 'sellerId', type: 'string', facet: true, optional: true},
        {name: 'shopId', type: 'string', facet: true, optional: true},
        {name: 'orderId', type: 'string', optional: true},
        {name: 'productId', type: 'string', optional: true},
        {name: 'timestampForSorting', type: 'int64', optional: true},
        {name: 'searchableText', type: 'string', optional: true},
      ],
      token_separators: ['-', '_'],
    },
  ];

  for (const schema of collections) {
    try {
      if (dropExisting) {
        try {
          await client.collections(schema.name).delete();
          console.log(`[Typesense] Dropped collection ${schema.name}.`);
        } catch (e) {
          // didn't exist, no problem
        }
      } else {
        await client.collections(schema.name).retrieve();
        console.log(`[Typesense] Collection ${schema.name} already exists, skipping.`);
        continue;
      }
    } catch (e) {
      // collection doesn't exist, proceed to create
    }
    await client.collections().create(schema);
    console.log(`[Typesense] Collection ${schema.name} created.`);
  }
};

// ─── HTTP endpoint ────────────────────────────────────────────────────────────
// Pass ?drop=true to drop and recreate all collections (re-schema).
export const createTypesenseCollections = onRequest(
  {region: 'europe-west3'},
  async (req, res) => {
    try {
      const drop = req.query.drop === 'true';
      await initTypesenseCollections(drop);
      res.status(200).send(`Typesense collections ${drop ? 'recreated' : 'created'} successfully.`);
    } catch (error) {
      console.error('[Typesense] Error creating collections:', error);
      res.status(500).send(`Error: ${error.message}`);
    }
  },
);

// ─── Firestore triggers ───────────────────────────────────────────────────────

export const syncProductsWithTypesense = onDocumentWritten(
  {region: 'europe-west3', document: 'products/{productId}'},
  async (event) => {
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;

    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory',
        'price', 'brandModel', 'subsubcategory', 'averageRating',
        'imageUrls', 'sellerName', 'isBoosted', 'paused'];
      const hasRelevantChanges = searchFields.some((f) => fieldChanged(beforeData[f], afterData[f]));
      if (!hasRelevantChanges) return;
    }

    if (!afterData) {
      return syncDocumentToTypesense('products', event.params.productId, beforeData, null, sanitizeForProducts);
    }

    const localizedFields = {};
    for (const locale of SUPPORTED_LOCALES) {
      try {
         localizedFields[`category_${locale}`] = localize('category', afterData.category, locale);
         } catch (e) { 
            localizedFields[`category_${locale}`] = afterData.category;
         }
      try {
         localizedFields[`subcategory_${locale}`] = localize('subcategory', afterData.subcategory, locale);
         } catch (e) {
             localizedFields[`subcategory_${locale}`] = afterData.subcategory;
             }
      try {
         localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', afterData.subsubcategory, locale);
         } catch (e) {
             localizedFields[`subsubcategory_${locale}`] = afterData.subsubcategory;
             }
      if (afterData.jewelryType) {
        try {
             localizedFields[`jewelryType_${locale}`] = localize('jewelryType', afterData.jewelryType, locale);
             } catch (e) {
                 localizedFields[`jewelryType_${locale}`] = afterData.jewelryType;
                 }
      }
      if (Array.isArray(afterData.jewelryMaterials)) {
        try {
             localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials.map((mat) => {
                 try {
                     return localize('jewelryMaterial', mat, locale);
                     } catch (e) {
                         return mat;
                         } 
                        });
                     } catch (e) {
                         localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials;
                         }
      }
    }

    const augmented = {...afterData, ...localizedFields};
    await syncDocumentToTypesense('products', event.params.productId, beforeData, augmented, sanitizeForProducts);
  },
);

export const syncShopProductsWithTypesense = onDocumentWritten(
  {region: 'europe-west3', document: 'shop_products/{productId}'},
  async (event) => {
    const productId = event.params.productId;
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;

    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory',
        'price', 'brandModel', 'subsubcategory', 'averageRating',
        'discountPercentage', 'campaignName', 'isBoosted', 'imageUrls',
        'sellerName', 'paused', 'quantity'];
      const hasRelevantChanges = searchFields.some((f) => fieldChanged(beforeData[f], afterData[f]));
      if (!hasRelevantChanges) return;
    }

    if (!afterData) {
      return syncDocumentToTypesense('shop_products', productId, beforeData, null, sanitizeForShopProducts);
    }

    const localizedFields = {};
    for (const locale of SUPPORTED_LOCALES) {
      try {
         localizedFields[`category_${locale}`] = localize('category', afterData.category, locale);
         } catch (e) {
             localizedFields[`category_${locale}`] = afterData.category;
             }
      try {
         localizedFields[`subcategory_${locale}`] = localize('subcategory', afterData.subcategory, locale);
         } catch (e) {
             localizedFields[`subcategory_${locale}`] = afterData.subcategory;
             }
      try {
         localizedFields[`subsubcategory_${locale}`] = localize('subSubcategory', afterData.subsubcategory, locale);
         } catch (e) {
             localizedFields[`subsubcategory_${locale}`] = afterData.subsubcategory;
             }
      if (afterData.jewelryType) {
        try {
             localizedFields[`jewelryType_${locale}`] = localize('jewelryType', afterData.jewelryType, locale);
             } catch (e) {
                 localizedFields[`jewelryType_${locale}`] = afterData.jewelryType;
                 }
      }
      if (Array.isArray(afterData.jewelryMaterials)) {
        try {
             localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials.map((mat) => {
                 try {
                     return localize('jewelryMaterial', mat, locale);
                     } catch (e) {
                         return mat;
                         }
                         });
                         } catch (e) {
                             localizedFields[`jewelryMaterials_${locale}`] = afterData.jewelryMaterials;
                             }
      }
    }

    const augmented = {...afterData, ...localizedFields};
    await syncDocumentToTypesense('shop_products', productId, beforeData, augmented, sanitizeForShopProducts);
  },
);

export const syncShopsWithTypesense = onDocumentWritten(
  {region: 'europe-west3', document: 'shops/{shopId}'},
  async (event) => {
    const shopId = event.params.shopId;
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;

    if (beforeData && afterData) {
      const relevantFields = ['name', 'profileImageUrl', 'isActive', 'categories'];
      const hasRelevantChanges = relevantFields.some((f) => fieldChanged(beforeData[f], afterData[f]));
      if (!hasRelevantChanges) return;
    }

    if (!afterData) {
      return syncDocumentToTypesense('shops', shopId, beforeData, null, sanitizeForShops);
    }

    const augmented = {
      name: afterData.name,
      profileImageUrl: afterData.profileImageUrl || null,
      categories: afterData.categories || [],
      isActive: afterData.isActive ?? true,
      searchableText: [afterData.name, ...(afterData.categories || [])].filter(Boolean).join(' '),
    };

    await syncDocumentToTypesense('shops', shopId, beforeData, augmented, sanitizeForShops);
  },
);

export const syncOrdersWithTypesense = onDocumentWritten(
  {region: 'europe-west3', document: 'orders/{orderId}/items/{itemId}'},
  async (event) => {
    const beforeData = event.data.before?.data() ?? null;
    const afterData = event.data.after?.data() ?? null;
    const itemId = event.params.itemId;

    if (beforeData && afterData) {
      const searchFields = ['productName', 'category', 'subcategory',
        'price', 'brandModel', 'shipmentStatus', 'buyerName', 'sellerName'];
      const hasRelevantChanges = searchFields.some((f) => beforeData[f] !== afterData[f]);
      if (!hasRelevantChanges) return;
    }

    if (!afterData) {
      return syncDocumentToTypesense('orders', itemId, beforeData, null, sanitizeForOrders);
    }

    const augmented = {
      ...afterData,
      searchableText: [
        afterData.productName, afterData.buyerName, afterData.sellerName,
        afterData.brandModel, afterData.category, afterData.subcategory,
        afterData.condition, afterData.shipmentStatus,
      ].filter(Boolean).join(' '),
      timestampForSorting: afterData.timestamp?.seconds || Math.floor(Date.now() / 1000),
    };

    await syncDocumentToTypesense('orders', itemId, beforeData, augmented, sanitizeForOrders);
  },
);
