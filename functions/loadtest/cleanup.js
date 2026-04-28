// Removes all artefacts created by simulate.js. Idempotent — safe to run
// repeatedly. Use this before going to real production launch to make sure
// no test data lingers in courier_alltime_stats, courier_daily_stats, or
// any of the dependent collections (e.g. food-accounting-daily already
// includes their delivered-revenue contributions).
//
// Run from the `functions/` directory:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json node loadtest/cleanup.js
//
// Optional flags:
//   --dry      list what would be deleted, don't actually delete
//   --keep-auth   leave the Firebase Auth users in place (default: deletes them)

import admin from 'firebase-admin';
import { getDatabase } from 'firebase-admin/database';

const PROJECT_ID   = 'emlak-mobile-app';
const DATABASE_URL = 'https://emlak-mobile-app-default-rtdb.europe-west1.firebasedatabase.app';

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  }),
);
const dryRun  = args.dry === true;
const keepAuth = args['keep-auth'] === true;

admin.initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL });
const db   = admin.firestore();
const rtdb = getDatabase();

async function findTestCourierUids() {
  const uids = [];
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const u of page.users) {
      if (u.email && u.email.startsWith('loadtest-courier-')) {
        uids.push(u.uid);
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

async function deleteCollectionByQuery(query, label) {
  const snap = await query.get();
  if (snap.empty) return 0;
  console.log(`  ${label}: ${snap.size} docs ${dryRun ? '(dry-run)' : 'deleting...'}`);
  if (dryRun) return snap.size;
  // Batch in chunks of 400 (Firestore batch cap is 500).
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    for (const d of snap.docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}

async function main() {
  console.log(`Cleanup starting. Project: ${PROJECT_ID}`);
  if (dryRun)   console.log('  Dry run — no writes');
  if (keepAuth) console.log('  Auth users will be kept');
  console.log('');

  // 1. Test orders by sourceType
  console.log('[1] Test orders (orders-food where sourceType == "loadtest")');
  await deleteCollectionByQuery(
    db.collection('orders-food').where('sourceType', '==', 'loadtest'),
    'orders-food',
  );

  // 2. Test couriers
  const testUids = await findTestCourierUids();
  console.log(`\n[2] Found ${testUids.length} test courier auth users`);
  if (testUids.length === 0) {
    console.log('Nothing else to clean up.');
    process.exit(0);
  }

  // 3. courier_alltime_stats
  console.log('\n[3] courier_alltime_stats');
  let allTimeDeleted = 0;
  for (const uid of testUids) {
    const ref = db.collection('courier_alltime_stats').doc(uid);
    const exists = (await ref.get()).exists;
    if (exists) {
      if (!dryRun) await ref.delete();
      allTimeDeleted++;
    }
  }
  console.log(`  ${allTimeDeleted} docs ${dryRun ? '(dry-run)' : 'deleted'}`);

  // 4. courier_daily_stats — query per courier (composite index on courierId)
  console.log('\n[4] courier_daily_stats');
  let dailyTotal = 0;
  for (const uid of testUids) {
    const n = await deleteCollectionByQuery(
      db.collection('courier_daily_stats').where('courierId', '==', uid),
      `courierId=${uid.substring(0, 8)}...`,
    );
    dailyTotal += n;
  }
  console.log(`  Total: ${dailyTotal} docs across ${testUids.length} couriers`);

  // 5. courier_actions — test ones reference orders that are gone, but be
  //    tidy and remove them by courierId too.
  console.log('\n[5] courier_actions');
  let actionsTotal = 0;
  for (const uid of testUids) {
    const n = await deleteCollectionByQuery(
      db.collection('courier_actions').where('courierId', '==', uid),
      `courierId=${uid.substring(0, 8)}...`,
    );
    actionsTotal += n;
  }
  console.log(`  Total: ${actionsTotal} docs`);

  // 6. RTDB couriers/{uid} — remove location/shift state
  console.log('\n[6] RTDB couriers/{uid}');
  for (const uid of testUids) {
    if (!dryRun) await rtdb.ref(`courier_locations/${uid}`).remove();
  }
  console.log(`  ${testUids.length} RTDB nodes ${dryRun ? '(dry-run)' : 'removed'}`);

  // 7. Auth users
  if (!keepAuth) {
    console.log('\n[7] Firebase Auth users');
    let authDeleted = 0;
    for (const uid of testUids) {
      try {
        if (!dryRun) await admin.auth().deleteUser(uid);
        authDeleted++;
      } catch (e) {
        console.warn(`  Failed to delete ${uid}: ${e.message}`);
      }
    }
    console.log(`  ${authDeleted}/${testUids.length} ${dryRun ? '(dry-run)' : 'deleted'}`);
  } else {
    console.log('\n[7] Skipped Auth user deletion (--keep-auth)');
  }

  console.log('\nCleanup complete.');
  console.log('Note: food-accounting-daily/weekly/monthly docs are NOT cleaned up here.');
  console.log('If you ran calculateDailyFoodAccounting during the test window, those');
  console.log('docs include load-test revenue. Re-run that CF for the same date(s) to');
  console.log('rebuild without the test orders (they are gone now).');
  process.exit(0);
}

main().catch((err) => {
  console.error('Cleanup failed:', err);
  process.exit(1);
});
