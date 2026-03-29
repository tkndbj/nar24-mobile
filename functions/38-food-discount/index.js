import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import { CloudTasksClient } from '@google-cloud/tasks';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const tasksClient = new CloudTasksClient();
const QUEUE = 'projects/emlak-mobile-app/locations/europe-west3/queues/discount-expiry';

export const scheduleDiscountExpiry = onDocumentWritten(
  { region: 'europe-west3', document: 'foods/{foodId}' },
  async (event) => {
    const after = event.data.after?.data();
    const before = event.data.before?.data();

    if (!after?.discount?.endDate) return;
    if (before?.discount?.endDate?.seconds === after.discount.endDate.seconds) return;

    const endDate = after.discount.endDate.toDate();
    if (endDate <= new Date()) return;

    const scheduleTime = Math.floor(endDate.getTime() / 1000);

    await tasksClient.createTask({
      parent: QUEUE,
      task: {
        scheduleTime: { seconds: scheduleTime },
        httpRequest: {
          httpMethod: 'POST',
          url: 'https://europe-west3-emlak-mobile-app.cloudfunctions.net/restoreDiscountPrice',
          body: Buffer.from(JSON.stringify({ foodId: event.params.foodId })).toString('base64'),
          headers: { 'Content-Type': 'application/json' },
        },
      },
    });
  },
);

export const restoreDiscountPrice = onRequest(
  { region: 'europe-west3' },
  async (req, res) => {
    const db = getFirestore();
    const { foodId } = req.body;
    const ref = db.collection('foods').doc(foodId);
    const snap = await ref.get();
    if (!snap.exists) {res.sendStatus(200); return;}

    const data = snap.data();
    if (!data) {res.sendStatus(200); return;}

    const originalPrice = data.discount?.originalPrice;
    if (!originalPrice) {res.sendStatus(200); return;}

    const endDate = data.discount?.endDate?.toDate();
    if (endDate && endDate > new Date()) {res.sendStatus(200); return;}

    await ref.update({
      price: originalPrice,
      discount: FieldValue.delete(),
    });

    res.sendStatus(200);
  },
);
