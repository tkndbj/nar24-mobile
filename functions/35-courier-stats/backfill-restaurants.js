// One-time backfill: populates `restaurants` map on every courier_daily_stats
// doc by scanning all delivered food + market orders, grouping by
// (courierId, dateKey), and writing the per-restaurant breakdown back to the
// matching daily doc.
//
// Run from the `functions/` directory:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
//     node 35-courier-stats/backfill-restaurants.js
//
// Optional flags:
//   --courier=<courierId>   limit to a single courier
//   --date=YYYY-MM-DD       limit to a single date
//   --dry                   print summary without writing

import admin from 'firebase-admin';

admin.initializeApp({ projectId: 'emlak-mobile-app' });
const db = admin.firestore();

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  }),
);
const onlyCourier = typeof args.courier === 'string' ? args.courier : null;
const onlyDate    = typeof args.date    === 'string' ? args.date    : null;
const dryRun      = args.dry === true;

function toDateKey(ts) {
  const d = ts?.toDate ? ts.toDate() : new Date();
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

const round2 = (n) => Math.round(n * 100) / 100;

function makeEntry() {
  return {
    name: '',
    count: 0,
    foodCount: 0,
    marketCount: 0,
    totalRevenue: 0,
    cashRevenue: 0,
    cardRevenue: 0,
    ibanRevenue: 0,
  };
}

async function scanCollection(collectionName, isMarket, groups) {
  console.log(`Scanning ${collectionName}...`);
  let lastDoc = null;
  const PAGE = 500;
  let total = 0;

  for (;;) {
    let q = db.collection(collectionName)
      .where('status', '==', 'delivered')
      .orderBy('updatedAt', 'asc')
      .limit(PAGE);
    if (lastDoc) q = q.startAfter(lastDoc);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const o = doc.data();
      if (!o.cargoUserId) continue;
      if (onlyCourier && o.cargoUserId !== onlyCourier) continue;

      const dateKey = toDateKey(o.updatedAt);
      if (onlyDate && dateKey !== onlyDate) continue;

      const groupKey = `${o.cargoUserId}_${dateKey}`;
      if (!groups.has(groupKey)) groups.set(groupKey, new Map());
      const restaurants = groups.get(groupKey);

      const rKey  = isMarket ? '__market__' : (o.restaurantId || '__unknown__');
      const rName = isMarket ?
        (o.marketName || 'Market') :
        (o.restaurantName || 'Restoran');

      if (!restaurants.has(rKey)) restaurants.set(rKey, makeEntry());
      const e = restaurants.get(rKey);
      e.name = rName;
      e.count += 1;
      if (isMarket) e.marketCount += 1; else e.foodCount += 1;

      const revenue  = typeof o.totalPrice === 'number' ? o.totalPrice : 0;
      const received = o.paymentReceivedMethod;
      const isCash   = received === 'cash' || (!received && o.isPaid === false);
      const isIban   = received === 'iban';
      const isCard   = received === 'card' || (!received && o.isPaid === true);

      e.totalRevenue += revenue;
      e.cashRevenue  += isCash ? revenue : 0;
      e.cardRevenue  += isCard ? revenue : 0;
      e.ibanRevenue  += isIban ? revenue : 0;
    }

    total += snap.size;
    lastDoc = snap.docs[snap.docs.length - 1];
    console.log(`  ${total} docs scanned in ${collectionName}`);
    if (snap.size < PAGE) break;
  }
}

async function main() {
  console.log('Backfill courier_daily_stats.restaurants');
  if (onlyCourier) console.log(`  Filter: courier=${onlyCourier}`);
  if (onlyDate)    console.log(`  Filter: date=${onlyDate}`);
  if (dryRun)      console.log('  Dry run — no writes');

  // groups: Map<`${courierId}_${date}`, Map<restaurantKey, entry>>
  const groups = new Map();

  await scanCollection('orders-food',   false, groups);
  await scanCollection('orders-market', true,  groups);

  console.log(`\nGrouped ${groups.size} (courier, date) pairs.`);

  if (dryRun) {
    let written = 0;
    for (const [k, restaurants] of groups) {
      written++;
      if (written <= 5) {
        console.log(`  ${k}: ${restaurants.size} restaurants`);
      }
    }
    console.log(`Would write ${groups.size} daily docs.`);
    return;
  }

  let written = 0;
  let missing = 0;
  const tasks = [];

  for (const [docKey, restaurants] of groups) {
    const docRef = db.collection('courier_daily_stats').doc(docKey);

    const restaurantsObj = {};
    for (const [rKey, e] of restaurants) {
      restaurantsObj[rKey] = {
        name: e.name,
        count: e.count,
        foodCount: e.foodCount,
        marketCount: e.marketCount,
        totalRevenue: round2(e.totalRevenue),
        cashRevenue: round2(e.cashRevenue),
        cardRevenue: round2(e.cardRevenue),
        ibanRevenue: round2(e.ibanRevenue),
      };
    }

    tasks.push(
      docRef.get().then((snap) => {
        if (!snap.exists) {
          missing++;
          return null;
        }
        return docRef.update({ restaurants: restaurantsObj });
      }).then(() => {
        written++;
        if (written % 50 === 0) console.log(`  ${written}/${groups.size} written`);
      })
    );

    // Throttle parallelism — flush every 50 promises.
    if (tasks.length >= 50) {
      await Promise.all(tasks);
      tasks.length = 0;
    }
  }
  await Promise.all(tasks);

  console.log(`\nDone. Wrote ${written} daily docs. Missing daily docs: ${missing}.`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {console.error(err); process.exit(1);});
