import {onSchedule} from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';

export const clampNegativeMetrics = onSchedule({
  schedule: '0 4 * * *',
  timeZone: 'UTC',
  timeoutSeconds: 120,
  memory: '256MiB',
  region: 'europe-west3',
}, async () => {
  const db = admin.firestore();
  let totalClamped = 0;

  for (const collection of ['products', 'shop_products']) {
    for (const field of ['cartCount', 'favoritesCount']) {
      const snapshot = await db.collection(collection)
        .where(field, '<', 0)
        .limit(500)
        .get();

      if (!snapshot.empty) {
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.update(doc.ref, {[field]: 0}));
        await batch.commit();
        totalClamped += snapshot.size;
      }
    }
  }

  console.log(JSON.stringify({
    level: 'INFO',
    event: 'clamp_completed',
    totalClamped,
  }));

  return {success: true, clamped: totalClamped};
});
