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

// ── Shared aggregation: writes daily + alltime stats for a delivered order ──
//
// Collection-agnostic. Called by both the orders-food and orders-market
// delivery triggers. Orders in both collections carry the same
// cargoUserId / cargoName / assignedAt / totalPrice / paymentReceivedMethod
// fields after the lifecycle refactor, so a single aggregator is enough.
//
// Idempotent via a `statsAggregated` flag on the order doc. CF retries (or
// duplicate invocations) read the flag inside the transaction and no-op if
// it's already set, so counters can't drift under at-least-once delivery.
// The flag write re-fires this trigger, but the `before.status === after.status`
// guard in handleDeliveryUpdate catches it and returns before reaching here.

async function aggregateDelivery(orderData, orderId, collection) {
  const courierId = orderData.cargoUserId;
  if (!courierId) return;

  const deliveredAt = orderData.updatedAt ?? admin.firestore.Timestamp.now();
  const dateKey     = toDateKey(deliveredAt);
  const revenue     = typeof orderData.totalPrice === 'number' ? orderData.totalPrice : 0;

  const received = orderData.paymentReceivedMethod;
  const isCash   = received === 'cash' || (!received && orderData.isPaid === false);
  const isIban   = received === 'iban';
  const isCard   = received === 'card' || (!received && orderData.isPaid === true);
  const ms       = durationMs(orderData, deliveredAt);
  const inc      = admin.firestore.FieldValue.increment;
  const now      = admin.firestore.FieldValue.serverTimestamp();
  const db       = admin.firestore();

  const isMarket = collection === 'orders-market';

  const orderRef   = db.collection(collection).doc(orderId);
  const dailyRef   = db.collection('courier_daily_stats').doc(`${courierId}_${dateKey}`);
  const alltimeRef = db.collection('courier_alltime_stats').doc(courierId);

  const committed = await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) return false;
    if (orderSnap.data().statsAggregated === true) return false;

    tx.set(dailyRef, {
      courierId,
      courierName: orderData.cargoName || 'Courier',
      date: dateKey,
      deliveredCount: inc(1),
      foodDeliveredCount: inc(isMarket ? 0 : 1),
      marketDeliveredCount: inc(isMarket ? 1 : 0),
      totalRevenue: inc(revenue),
      foodRevenue: inc(isMarket ? 0 : revenue),
      marketRevenue: inc(isMarket ? revenue : 0),
      cashRevenue: inc(isCash ? revenue : 0),
      cardRevenue: inc(isCard ? revenue : 0),
      ibanRevenue: inc(isIban ? revenue : 0),
      totalDeliveryTimeMs: inc(ms),
      orderIds: admin.firestore.FieldValue.arrayUnion(orderId),
      lastDeliveryAt: now,
      updatedAt: now,
    }, { merge: true });

    tx.set(alltimeRef, {
      courierId,
      courierName: orderData.cargoName || 'Courier',
      totalDeliveries: inc(1),
      foodDeliveries: inc(isMarket ? 0 : 1),
      marketDeliveries: inc(isMarket ? 1 : 0),
      totalRevenue: inc(revenue),
      foodRevenue: inc(isMarket ? 0 : revenue),
      marketRevenue: inc(isMarket ? revenue : 0),
      cashRevenue: inc(isCash ? revenue : 0),
      cardRevenue: inc(isCard ? revenue : 0),
      ibanRevenue: inc(isIban ? revenue : 0),
      totalDeliveryTimeMs: inc(ms),
      lastDeliveryAt: now,
      updatedAt: now,
    }, { merge: true });

    tx.update(orderRef, { statsAggregated: true });
    return true;
  });

  if (committed) {
    console.log(`[CourierStats] ${collection}/${orderId} courier=${courierId} date=${dateKey}`);
  } else {
    console.log(`[CourierStats] ${collection}/${orderId} skipped (already aggregated)`);
  }
}

// ── Trigger helper: fires on status transition to 'delivered'
//
// CF-40 processDelivery writes `status: 'delivered'` and `paymentReceivedMethod`
// in the same transaction, so `after` already has both fields. No grace-period
// refetch needed.

async function handleDeliveryUpdate(event, collection) {
  const before = event.data.before.data();
  const after  = event.data.after.data();
  if (before.status === after.status || after.status !== 'delivered') return;
  if (!after.cargoUserId) return;

  await aggregateDelivery(after, event.params.orderId, collection);
}

// ── Trigger: food order delivered ─────────────────────────────────────────

export const onDeliveryCompleted = onDocumentUpdated(
  { document: 'orders-food/{orderId}', region: REGION, memory: '256MiB' },
  (event) => handleDeliveryUpdate(event, 'orders-food'),
);

// ── Trigger: market order delivered ───────────────────────────────────────

export const onMarketDeliveryCompleted = onDocumentUpdated(
  { document: 'orders-market/{orderId}', region: REGION, memory: '256MiB' },
  (event) => handleDeliveryUpdate(event, 'orders-market'),
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
    const startTs  = admin.firestore.Timestamp.fromDate(startUtc);
    const endTs    = admin.firestore.Timestamp.fromDate(endUtc);

    const queryCollection = (collection) => db.collection(collection)
      .where('status', '==', 'delivered')
      .where('updatedAt', '>=', startTs)
      .where('updatedAt', '<',  endTs)
      .orderBy('updatedAt', 'asc')
      .get();

    const [foodSnap, marketSnap] = await Promise.all([
      queryCollection('orders-food'),
      queryCollection('orders-market'),
    ]);

    const totalDocs = foodSnap.size + marketSnap.size;
    if (totalDocs === 0) {
      return { date: targetDate, couriersProcessed: 0, ordersProcessed: 0, stats: [] };
    }

    // Aggregate in memory first
    const map = new Map();

    const ingest = (doc, isMarket) => {
      const o = doc.data();
      if (!o.cargoUserId) return;
      const revenue = typeof o.totalPrice === 'number' ? o.totalPrice : 0;
      const received = o.paymentReceivedMethod;
      const isCash   = received === 'cash' || (!received && o.isPaid === false);
      const isIban   = received === 'iban';
      const isCard   = received === 'card' || (!received && o.isPaid === true);
      const ms       = durationMs(o, o.updatedAt);

      if (!map.has(o.cargoUserId)) {
        map.set(o.cargoUserId, {
          courierId: o.cargoUserId,
          courierName: o.cargoName || 'Courier',
          date: targetDate,
          deliveredCount: 0,
          foodDeliveredCount: 0,
          marketDeliveredCount: 0,
          totalRevenue: 0,
          foodRevenue: 0,
          marketRevenue: 0,
          cashRevenue: 0,
          cardRevenue: 0,
          ibanRevenue: 0,
          totalDeliveryTimeMs: 0,
          orderIds: [],
          firstDeliveryAt: o.updatedAt,
          lastDeliveryAt: o.updatedAt,
        });
      }

      const e = map.get(o.cargoUserId);
      e.deliveredCount      += 1;
      if (isMarket) {
        e.marketDeliveredCount += 1;
        e.marketRevenue        += revenue;
      } else {
        e.foodDeliveredCount += 1;
        e.foodRevenue        += revenue;
      }
      e.totalRevenue        += revenue;
      e.cashRevenue         += isCash ? revenue : 0;
      e.cardRevenue         += isCard ? revenue : 0;
      e.ibanRevenue         += isIban ? revenue : 0;
      e.totalDeliveryTimeMs += ms;
      e.orderIds.push(doc.id);
      e.lastDeliveryAt = o.updatedAt;
    };

    for (const doc of foodSnap.docs)   ingest(doc, false);
    for (const doc of marketSnap.docs) ingest(doc, true);

    const round2 = (n) => Math.round(n * 100) / 100;
    const now = admin.firestore.FieldValue.serverTimestamp();
    await Promise.all(
      Array.from(map.values()).map((s) =>
        db.collection('courier_daily_stats')
          .doc(`${s.courierId}_${targetDate}`)
          .set({
            ...s,
            totalRevenue: round2(s.totalRevenue),
            foodRevenue: round2(s.foodRevenue),
            marketRevenue: round2(s.marketRevenue),
            cashRevenue: round2(s.cashRevenue),
            cardRevenue: round2(s.cardRevenue),
            ibanRevenue: round2(s.ibanRevenue),
            updatedAt: now,
            recalculatedAt: now,
          }, { merge: false })
      )
    );

    const stats = Array.from(map.values()).map((s) => ({
      courierId: s.courierId,
      courierName: s.courierName,
      deliveredCount: s.deliveredCount,
      foodDeliveredCount: s.foodDeliveredCount,
      marketDeliveredCount: s.marketDeliveredCount,
      totalRevenue: round2(s.totalRevenue),
      foodRevenue: round2(s.foodRevenue),
      marketRevenue: round2(s.marketRevenue),
      cashRevenue: round2(s.cashRevenue),
      cardRevenue: round2(s.cardRevenue),
      ibanRevenue: round2(s.ibanRevenue), avgDeliveryMinutes: s.deliveredCount > 0 && s.totalDeliveryTimeMs > 0 ? Math.round(s.totalDeliveryTimeMs / s.deliveredCount / 60000) : null,
    }));

    return { date: targetDate, couriersProcessed: map.size, ordersProcessed: totalDocs, stats };
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
        foodDeliveredCount: d.foodDeliveredCount ?? 0,
        marketDeliveredCount: d.marketDeliveredCount ?? 0,
        totalRevenue: d.totalRevenue  ?? 0,
        foodRevenue: d.foodRevenue   ?? 0,
        marketRevenue: d.marketRevenue ?? 0,
        cashRevenue: d.cashRevenue   ?? 0,
        cardRevenue: d.cardRevenue   ?? 0,
        ibanRevenue: d.ibanRevenue   ?? 0,
        avgDeliveryMinutes: avgMs > 0 ? Math.round(avgMs / 60000) : null,
      };
    });

    return { date: targetDate, couriers };
  },
);
