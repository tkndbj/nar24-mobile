import {onSchedule} from 'firebase-functions/v2/scheduler';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {SecretManagerServiceClient} from '@google-cloud/secret-manager';
import Typesense from 'typesense';

// DON'T call getFirestore() here at module level
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

export const rebuildRelatedProducts = onSchedule({
  schedule: '0 2 * * *',
  timeZone: 'Europe/Istanbul',
  region: 'europe-west3',
  memory: '1GiB',
  timeoutSeconds: 1800,
}, async (event) => {
  console.log('Starting related products rebuild...');

  // Get Firestore instance HERE, inside the function
  const db = getFirestore();

  try {
    const startTime = Date.now();
    let processed = 0;
    let skipped = 0;
    let errors = 0;

    const client = await getTypesenseClient();

    // Checkpoint system
    const checkpointRef = db.collection('system_state').doc('related_products_checkpoint');
    const checkpointDoc = await checkpointRef.get();
    const lastProcessedId = checkpointDoc.exists ? checkpointDoc.data().lastProcessedId : null;

    const batchSize = 50;
    const concurrency = 20;
    let lastDoc = null;
    let consecutiveErrors = 0;
    const MAX_CONSECUTIVE_ERRORS = 3;

    // Resume from checkpoint
    if (lastProcessedId) {
      console.log(`Resuming from checkpoint: ${lastProcessedId}`);
      const resumeDoc = await db.collection('shop_products').doc(lastProcessedId).get();
      if (resumeDoc.exists) lastDoc = resumeDoc;
    }
    // eslint-disable-next-line no-constant-condition
    while (true) {
      if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
        console.error(`Circuit breaker triggered`);
        break;
      }

      let query = db.collection('shop_products')
        .orderBy('__name__')
        .limit(batchSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      let batchProcessed = 0;

      // Process with concurrency control
      for (let i = 0; i < snapshot.docs.length; i += concurrency) {
        const batch = snapshot.docs.slice(i, i + concurrency);

        const promises = batch.map(async (doc) => {
          const data = doc.data();

          // Skip recent updates
          if (data.relatedLastUpdated) {
            const lastUpdate = data.relatedLastUpdated.toDate();
            const daysSinceUpdate = (Date.now() - lastUpdate.getTime()) / (1000 * 60 * 60 * 24);

            if (daysSinceUpdate < 7) {
              skipped++;
              return {success: true, id: doc.id, skipped: true};
            }
          }

          // Retry logic
          for (let attempt = 1; attempt <= 3; attempt++) {
            try {
              await Promise.race([
                buildRelatedForProduct(doc.id, data, client, db),
                new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout')), 10000)),
              ]);
              processed++;
              consecutiveErrors = 0;
              return {success: true, id: doc.id, skipped: false};
            } catch (err) {
              if (attempt === 3) {
                console.error(`Failed after 3 attempts ${doc.id}:`, err.message);
                errors++;
                consecutiveErrors++;
                return {success: false, id: doc.id, skipped: false};
              }
              await new Promise((resolve) => setTimeout(resolve, 1000 * Math.pow(2, attempt - 1)));
            }
          }
        });

        const results = await Promise.all(promises);

        // Track last successfully processed (not skipped) document
        for (const result of results) {
          if (result.success && !result.skipped) {
            batchProcessed++;
            lastDoc = snapshot.docs.find((d) => d.id === result.id);
          }
        }
      }

      // Only save checkpoint if we actually processed something
      if (batchProcessed > 0 && lastDoc) {
        await checkpointRef.set({
          lastProcessedId: lastDoc.id,
          timestamp: FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      console.log(`Batch: ${processed} processed, ${skipped} skipped, ${errors} errors`);

      // Move to next batch
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
    }

    // Check error rate only against actually processed products
    if (processed > 0 && errors > processed * 0.1) {
      throw new Error(`High error rate: ${errors}/${processed} failed (${skipped} skipped)`);
    }

    // Clear checkpoint on success
    await checkpointRef.delete();

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`Complete: ${processed} processed, ${skipped} skipped, ${errors} errors, ${duration}s`);

    await db.collection('system_logs').add({
      type: 'related_products_rebuild',
      processed,
      skipped,
      errors,
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

// Pass db as parameter now
async function buildRelatedForProduct(productId, productData, client, db) {
    const {category, subcategory, subsubcategory, gender, price} = productData;

    if (!category || !subcategory) {
      console.warn(`Product ${productId} missing category/subcategory`);
      return;
    }

    if (!price || price <= 0) {
      console.warn(`Product ${productId} has invalid price`);
      return;
    }

    const relatedProducts = new Map();

    // Query 1: Primary match
    const primaryFilter = gender ?
      `category:=${category} && subcategory:=${subcategory} && gender:=${gender}` :
      `category:=${category} && subcategory:=${subcategory}`;

    const primaryHits = await searchTypesense(client, productId, {
      filterBy: primaryFilter,
      perPage: 40,
    });

    primaryHits.forEach((hit) => {
      const hasGenderMatch = gender && hit.gender === gender;
      const score = hasGenderMatch ? 100 : 80;
      addProduct(relatedProducts, hit, score);
    });

    // Query 2: Subsubcategory fallback
    if (relatedProducts.size < 20 && subsubcategory) {
      const subsubHits = await searchTypesense(client, productId, {
        filterBy: `category:=${category} && subsubcategory:=${subsubcategory}`,
        perPage: 20,
      });
      subsubHits.forEach((hit) => addProduct(relatedProducts, hit, 60));
    }

    // Query 3: Price range fallback
    if (relatedProducts.size < 20) {
      const priceMin = Math.floor(price * 0.7);
      const priceMax = Math.ceil(price * 1.3);
      const priceHits = await searchTypesense(client, productId, {
        filterBy: `category:=${category} && price:[${priceMin}..${priceMax}]`,
        perPage: 20,
      });
      priceHits.forEach((hit) => addProduct(relatedProducts, hit, 40));
    }

    // Rank and save
    const rankedProducts = Array.from(relatedProducts.entries())
      .map(([id, data]) => ({id, score: calculateFinalScore(data, productData)}))
      .sort((a, b) => b.score - a.score)
      .slice(0, 20)
      .map((item) => item.id);

    // Strip prefixes from IDs before saving
    const cleanedIds = rankedProducts.map((id) => {
      if (id.startsWith('shop_products_')) {
        return id.replace('shop_products_', '');
      }
      if (id.startsWith('products_')) {
        return id.replace('products_', '');
      }
      return id;
    });

    await db.collection('shop_products').doc(productId).update({
      relatedProductIds: cleanedIds,
      relatedLastUpdated: FieldValue.serverTimestamp(),
      relatedCount: cleanedIds.length,
    });
  }

async function searchTypesense(client, currentProductId, params) {
  const searchResult = await client.collections('shop_products').documents().search({
    q: '*',
    query_by: 'productName',
    filter_by: params.filterBy,
    per_page: params.perPage || 20,
    include_fields: 'id,category,subcategory,subsubcategory,gender,price,promotionScore',
  });

  const hits = (searchResult.hits || []).map((h) => h.document);
  return hits.filter((hit) => {
    // Strip prefix from Typesense ID before comparing
    let cleanId = hit.id || '';
    if (cleanId.startsWith('shop_products_')) {
      cleanId = cleanId.replace('shop_products_', '');
    }
    if (cleanId.startsWith('products_')) {
      cleanId = cleanId.replace('products_', '');
    }
    return cleanId !== currentProductId;
  });
}

function addProduct(map, hit, baseScore) {
  const hitId = hit.id || '';
  const existing = map.get(hitId);

  if (!existing) {
    map.set(hitId, {
      baseScore,
      promotionScore: hit.promotionScore || 0,
      price: hit.price,
      matchCount: 1,
    });
  } else {
    existing.baseScore = Math.max(existing.baseScore, baseScore);
    existing.matchCount++;
  }
}

function calculateFinalScore(data, originalProduct) {
  let score = data.baseScore;
  score += data.matchCount * 10;
  score += (data.promotionScore || 0) * 0.5;

  const priceDiff = Math.abs(data.price - originalProduct.price) / originalProduct.price;
  if (priceDiff < 0.2) score += 15;
  else if (priceDiff < 0.4) score += 5;

  return score;
}
