import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import admin from 'firebase-admin';

const REGION = 'europe-west3';

function toDateKey(ts) {
  const d = ts?.toDate ? ts.toDate() : new Date();
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

function durationMs(order, deliveredAt) {
  if (!order.assignedAt || !deliveredAt) return 0;
  const ms = deliveredAt.toDate().getTime() - order.assignedAt.toDate().getTime();
  return ms > 0 && ms < 4 * 60 * 60 * 1000 ? ms : 0;
}

// ── Trigger: fires on every delivery completion ───────────────────────────

export const onDeliveryCompleted = onDocumentUpdated(
  { document: 'orders-food/{orderId}', region: REGION, memory: '256MiB' },
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status || after.status !== 'delivered') return;

    const courierId = after.cargoUserId;
    if (!courierId) return;

    const orderId    = event.params.orderId;
    const deliveredAt = after.updatedAt ?? admin.firestore.Timestamp.now();
    const dateKey    = toDateKey(deliveredAt);
    const revenue    = typeof after.totalPrice === 'number' ? after.totalPrice : 0;
    const isCash     = after.isPaid === false;
    const ms         = durationMs(after, deliveredAt);
    const inc        = admin.firestore.FieldValue.increment;
    const now        = admin.firestore.FieldValue.serverTimestamp();
    const db         = admin.firestore();

    const batch = db.batch();

    batch.set(
      db.collection('courier_daily_stats').doc(`${courierId}_${dateKey}`),
      {
        courierId,
        courierName: after.cargoName || 'Courier',
        date: dateKey,
        deliveredCount: inc(1),
        totalRevenue: inc(revenue),
        cashRevenue: inc(isCash ? revenue : 0),
        cardRevenue: inc(isCash ? 0 : revenue),
        totalDeliveryTimeMs: inc(ms),
        orderIds: admin.firestore.FieldValue.arrayUnion(orderId),
        lastDeliveryAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

    batch.set(
      db.collection('courier_alltime_stats').doc(courierId),
      {
        courierId,
        courierName: after.cargoName || 'Courier',
        totalDeliveries: inc(1),
        totalRevenue: inc(revenue),
        cashRevenue: inc(isCash ? revenue : 0),
        cardRevenue: inc(isCash ? 0 : revenue),
        totalDeliveryTimeMs: inc(ms),
        lastDeliveryAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

    await batch.commit();
    console.log(`[CourierStats] order=${orderId} courier=${courierId} date=${dateKey}`);
  },
);

// ── Manual recalc: admin triggers this to rebuild today's stats ───────────

export const recalcCourierStats = onCall(
  { region: REGION, memory: '512MiB', timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');

    const record = await admin.auth().getUser(request.auth.uid);
    if (!record.customClaims?.isAdmin && !record.customClaims?.masterCourier) {
      throw new HttpsError('permission-denied', 'Admins and master couriers only.');
    }

    const db         = admin.firestore();
    const targetDate = request.data?.date ?? toDateKey(admin.firestore.Timestamp.now());

    if (!/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
      throw new HttpsError('invalid-argument', 'date must be YYYY-MM-DD');
    }

    const [year, month, day] = targetDate.split('-').map(Number);
    const startUtc = new Date(Date.UTC(year, month - 1, day, 0, 0, 0) - 3 * 60 * 60 * 1000);
    const endUtc   = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);

    const snap = await db.collection('orders-food')
      .where('status', '==', 'delivered')
      .where('updatedAt', '>=', admin.firestore.Timestamp.fromDate(startUtc))
      .where('updatedAt', '<',  admin.firestore.Timestamp.fromDate(endUtc))
      .orderBy('updatedAt', 'asc')
      .get();

    if (snap.empty) {
      return { date: targetDate, couriersProcessed: 0, ordersProcessed: 0, stats: [] };
    }

    // Aggregate in memory first
    const map = new Map();
    for (const doc of snap.docs) {
      const o = doc.data();
      if (!o.cargoUserId) continue;
      const revenue = typeof o.totalPrice === 'number' ? o.totalPrice : 0;
      const isCash  = o.isPaid === false;
      const ms      = durationMs(o, o.updatedAt);

      if (!map.has(o.cargoUserId)) {
        map.set(o.cargoUserId, {
          courierId: o.cargoUserId, courierName: o.cargoName || 'Courier',
          date: targetDate, deliveredCount: 0,
          totalRevenue: 0, cashRevenue: 0, cardRevenue: 0,
          totalDeliveryTimeMs: 0, orderIds: [],
          firstDeliveryAt: o.updatedAt, lastDeliveryAt: o.updatedAt,
        });
      }

      const e = map.get(o.cargoUserId);
      e.deliveredCount      += 1;
      e.totalRevenue        += revenue;
      e.cashRevenue         += isCash ? revenue : 0;
      e.cardRevenue         += isCash ? 0 : revenue;
      e.totalDeliveryTimeMs += ms;
      e.orderIds.push(doc.id);
      e.lastDeliveryAt = o.updatedAt;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await Promise.all(
      Array.from(map.values()).map((s) =>
        db.collection('courier_daily_stats')
          .doc(`${s.courierId}_${targetDate}`)
          .set({ ...s, totalRevenue: Math.round(s.totalRevenue * 100) / 100, updatedAt: now, recalculatedAt: now }, { merge: false })
      )
    );

    const stats = Array.from(map.values()).map((s) => ({
      courierId: s.courierId,
      courierName: s.courierName,
      deliveredCount: s.deliveredCount,
      totalRevenue: Math.round(s.totalRevenue * 100) / 100,
      cashRevenue: Math.round(s.cashRevenue * 100) / 100,
      cardRevenue: Math.round(s.cardRevenue * 100) / 100,
      avgDeliveryMinutes: s.deliveredCount > 0 && s.totalDeliveryTimeMs > 0 ? Math.round(s.totalDeliveryTimeMs / s.deliveredCount / 60000) : null,
    }));

    return { date: targetDate, couriersProcessed: map.size, ordersProcessed: snap.size, stats };
  },
);

// ── Summary read: dashboard calls this instead of reading docs individually ─

export const getCourierStatsSummary = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');

    const record = await admin.auth().getUser(request.auth.uid);
    if (!record.customClaims?.isAdmin && !record.customClaims?.masterCourier) {
      throw new HttpsError('permission-denied', 'Admins and master couriers only.');
    }

    const targetDate = request.data?.date ?? toDateKey(admin.firestore.Timestamp.now());
    const snap = await admin.firestore()
      .collection('courier_daily_stats')
      .where('date', '==', targetDate)
      .get();

    const couriers = snap.docs.map((doc) => {
      const d = doc.data();
      const avgMs = d.deliveredCount > 0 && d.totalDeliveryTimeMs > 0 ? d.totalDeliveryTimeMs / d.deliveredCount : 0;
      return {
        courierId: d.courierId,
        courierName: d.courierName,
        date: d.date,
        deliveredCount: d.deliveredCount ?? 0,
        totalRevenue: d.totalRevenue ?? 0,
        cashRevenue: d.cashRevenue ?? 0,
        cardRevenue: d.cardRevenue ?? 0,
        avgDeliveryMinutes: avgMs > 0 ? Math.round(avgMs / 60000) : null,
      };
    });

    return { date: targetDate, couriers };
  },
);
