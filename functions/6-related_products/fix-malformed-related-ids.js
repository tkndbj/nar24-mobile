import admin from 'firebase-admin';

admin.initializeApp({projectId: 'emlak-mobile-app'});
const db = admin.firestore();

async function main() {
  const snap = await db.collection('products').get();
  let fixed = 0, scanned = 0;

  for (const doc of snap.docs) {
    scanned++;
    const ids = doc.data().relatedProductIds || [];
    if (!ids.length) continue;

    const cleaned = ids
      .map((id) => id
        .replace(/^sp:shop_products_/, '')
        .replace(/^sp:products_/, '')
        .replace(/^p:products_/, '')
        .replace(/^p:/, '')
        .replace(/^sp:/, ''))
      .filter(Boolean);

    const changed = cleaned.length !== ids.length ||
      cleaned.some((v, i) => v !== ids[i]);
    if (!changed) continue;

    await doc.ref.update({
      relatedProductIds: cleaned,
      relatedCount: cleaned.length,
    });
    fixed++;
  }

  console.log(`Scanned ${scanned}, fixed ${fixed}`);
}

main().catch((e) => { console.error(e); process.exit(1); });