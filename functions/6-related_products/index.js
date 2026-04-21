import {onSchedule} from 'firebase-functions/v2/scheduler';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
import Typesense from 'typesense';

const secretClient = new SecretManagerServiceClient();

async function getSecret(secretName) {
  const [version] = await secretClient.accessSecretVersion({name: secretName});
  return version.payload.data.toString('utf8');
}

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

function toJsDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'number') return new Date(value);
  if (typeof value === 'string') return new Date(value);
  if (typeof value === 'object' && typeof value.seconds === 'number') {
    return new Date(value.seconds * 1000);
  }
  return null;
}

function cleanTypesenseId(id) {
  if (!id || typeof id !== 'string') return '';
  if (id.startsWith('shop_products_')) return id.slice('shop_products_'.length);
  if (id.startsWith('products_')) return id.slice('products_'.length);
  return id;
}

const BATCH_SIZE = 50;
const CONCURRENCY = 20;
const MAX_CONSECUTIVE_ERRORS = 10;
const MAX_RELATED = 20;
const REFRESH_DAYS = 7;
const BUILDER_TIMEOUT_MS = 10000;

export const rebuildRelatedProducts = onSchedule({
  schedule: '0 2 * * *',
  timeZone: 'Europe/Istanbul',
  region: 'europe-west3',
  memory: '1GiB',
  timeoutSeconds: 1800,
}, async (event) => {
  console.log('Starting related products rebuild...');
  const db = getFirestore();

  const startTime = Date.now();
  const stats = {processed: 0, skipped: 0, errors: 0};

  try {
    const client = await getTypesenseClient();

    const checkpointRef = db.collection('system_state').doc('related_products_checkpoint');
    const checkpointDoc = await checkpointRef.get();
    const checkpoint = checkpointDoc.exists ? checkpointDoc.data() : {};
    const startPhase = checkpoint.phase || 'shop_products';
    const startId = checkpoint.lastProcessedId || null;

    // Phase 1: shop_products (related from shop_products)
    if (startPhase === 'shop_products') {
      await processCollection({
        db,
        collectionName: 'shop_products',
        client,
        checkpointRef,
        resumeId: startId,
        stats,
      });
    }

    // Phase 2: products (related from shop_products)
    const productsResumeId = startPhase === 'products' ? startId : null;
    await processCollection({
      db,
      collectionName: 'products',
      client,
      checkpointRef,
      resumeId: productsResumeId,
      stats,
    });

    if (stats.processed > 0 && stats.errors > stats.processed * 0.1) {
      throw new Error(`High error rate: ${stats.errors}/${stats.processed} failed (${stats.skipped} skipped)`);
    }

    await checkpointRef.delete();

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`Complete: ${stats.processed} processed, ${stats.skipped} skipped, ${stats.errors} errors, ${duration}s`);

    await db.collection('system_logs').add({
      type: 'related_products_rebuild',
      processed: stats.processed,
      skipped: stats.skipped,
      errors: stats.errors,
      duration: parseFloat(duration),
      timestamp: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Fatal error:', error);
    await db.collection('system_logs').add({
      type: 'related_products_rebuild_error',
      error: error.message,
      stack: error.stack,
      timestamp: FieldValue.serverTimestamp(),
    });
    throw error;
  }
});

async function processCollection({db, collectionName, client, checkpointRef, resumeId, stats}) {
  let lastDoc = null;
  let consecutiveErrors = 0;

  if (resumeId) {
    console.log(`Resuming ${collectionName} from checkpoint: ${resumeId}`);
    const resumeDoc = await db.collection(collectionName).doc(resumeId).get();
    if (resumeDoc.exists) lastDoc = resumeDoc;
  }

  // eslint-disable-next-line no-constant-condition
  while (true) {
    if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
      console.error(`Circuit breaker triggered for ${collectionName}`);
      break;
    }

    let query = db.collection(collectionName).orderBy('__name__').limit(BATCH_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (let i = 0; i < snapshot.docs.length; i += CONCURRENCY) {
      const batch = snapshot.docs.slice(i, i + CONCURRENCY);

      const promises = batch.map(async (doc) => {
        const data = doc.data();

        if (data.relatedLastUpdated) {
          const lastUpdate = toJsDate(data.relatedLastUpdated);
          if (lastUpdate) {
            const daysSinceUpdate = (Date.now() - lastUpdate.getTime()) / (1000 * 60 * 60 * 24);
            if (daysSinceUpdate < REFRESH_DAYS) {
              stats.skipped++;
              return {success: true, id: doc.id, skipped: true};
            }
          }
        }

        for (let attempt = 1; attempt <= 3; attempt++) {
          try {
            const relatedData = await Promise.race([
              buildRelatedFromShopProducts(doc.id, data, client),
              new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), BUILDER_TIMEOUT_MS)),
            ]);
            stats.processed++;
            consecutiveErrors = 0;
            return {success: true, id: doc.id, skipped: false, data: relatedData};
          } catch (err) {
            if (attempt === 3) {
              console.error(`Failed after 3 attempts ${doc.id}:`, err.message);
              stats.errors++;
              consecutiveErrors++;
              return {success: false, id: doc.id, skipped: false};
            }
            await new Promise((resolve) => setTimeout(resolve, 1000 * Math.pow(2, attempt - 1)));
          }
        }
      });

      const results = await Promise.all(promises);
      const updates = results.filter((r) => r && r.success && !r.skipped && r.data);

      for (let j = 0; j < updates.length; j += 400) {
        const chunk = updates.slice(j, j + 400);
        const writeBatch = db.batch();
        chunk.forEach(({data: updateData}) => {
          writeBatch.update(db.collection(collectionName).doc(updateData.productId), {
            relatedProductIds: updateData.relatedProductIds,
            relatedLastUpdated: FieldValue.serverTimestamp(),
            relatedCount: updateData.relatedCount,
          });
        });
        await writeBatch.commit();
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    await checkpointRef.set({
      phase: collectionName,
      lastProcessedId: lastDoc.id,
      timestamp: FieldValue.serverTimestamp(),
    }, {merge: true});

    console.log(`${collectionName} batch: ${stats.processed} processed, ${stats.skipped} skipped, ${stats.errors} errors`);
  }
}

async function buildRelatedFromShopProducts(productId, productData, client) {
  const {category, subcategory, subsubcategory, gender, price} = productData;

  if (!category || !subcategory || !price || price <= 0) {
    return {productId, relatedProductIds: [], relatedCount: 0};
  }

  const relatedProducts = new Map();

  const primaryFilter = gender ?
    `category:=${category} && subcategory:=${subcategory} && gender:=${gender}` :
    `category:=${category} && subcategory:=${subcategory}`;

  const primaryHits = await searchShopProductsTypesense(client, productId, {
    filterBy: primaryFilter,
    perPage: 40,
  });
  primaryHits.forEach((hit) => {
    const score = (gender && hit.gender === gender) ? 100 : 80;
    addProduct(relatedProducts, hit, score);
  });

  if (relatedProducts.size < MAX_RELATED && subsubcategory) {
    const subsubHits = await searchShopProductsTypesense(client, productId, {
      filterBy: `category:=${category} && subsubcategory:=${subsubcategory}`,
      perPage: 20,
    });
    subsubHits.forEach((hit) => addProduct(relatedProducts, hit, 60));
  }

  if (relatedProducts.size < MAX_RELATED) {
    const priceMin = Math.floor(price * 0.7);
    const priceMax = Math.ceil(price * 1.3);
    const priceHits = await searchShopProductsTypesense(client, productId, {
      filterBy: `category:=${category} && price:[${priceMin}..${priceMax}]`,
      perPage: 20,
    });
    priceHits.forEach((hit) => addProduct(relatedProducts, hit, 40));
  }

  const rankedProducts = Array.from(relatedProducts.entries())
    .map(([id, data]) => ({id, score: calculateFinalScore(data, productData)}))
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_RELATED)
    .map((item) => item.id);

  return {
    productId,
    relatedProductIds: rankedProducts,
    relatedCount: rankedProducts.length,
  };
}

async function searchShopProductsTypesense(client, currentProductId, params) {
  const searchResult = await client.collections('shop_products').documents().search({
    q: '*',
    query_by: 'productName',
    filter_by: params.filterBy,
    per_page: params.perPage || 20,
    include_fields: 'id,category,subcategory,subsubcategory,gender,price',
  });

  const hits = (searchResult.hits || []).map((h) => h.document);
  return hits
    .map((hit) => ({...hit, id: cleanTypesenseId(hit.id)}))
    .filter((hit) => hit.id && hit.id !== currentProductId);
}

function addProduct(map, hit, baseScore) {
  if (!hit.id) return;
  const existing = map.get(hit.id);
  if (!existing) {
    map.set(hit.id, {baseScore, price: hit.price, matchCount: 1});
  } else {
    existing.baseScore = Math.max(existing.baseScore, baseScore);
    existing.matchCount++;
  }
}

function calculateFinalScore(data, originalProduct) {
  let score = data.baseScore;
  score += data.matchCount * 10;

  if (originalProduct.price && data.price) {
    const priceDiff = Math.abs(data.price - originalProduct.price) / originalProduct.price;
    if (priceDiff < 0.2) score += 15;
    else if (priceDiff < 0.4) score += 5;
  }

  return score;
}
