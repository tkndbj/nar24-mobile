// functions/index.js
import {setGlobalOptions} from 'firebase-functions/v2';
import { dedup } from './shared/redis.js';
import {onDocumentUpdated } from 'firebase-functions/v2/firestore';
import {onRequest, onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {onObjectFinalized} from 'firebase-functions/v2/storage';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import {getDominantColor} from './getDominantColor.js';
import {FieldValue} from 'firebase-admin/firestore';

setGlobalOptions({
  serviceAccount: 'emlak-mobile-app@appspot.gserviceaccount.com',
});

admin.initializeApp();

export const onShopProductStockChange = onDocumentUpdated(
  {
    document: 'shop_products/{productId}',
    region: 'europe-west3',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const productId = event.params.productId;

    // Check stock change conditions FIRST (before deduplication to avoid unnecessary transactions)
    const mainWentOutOfStock = before.quantity > 0 && after.quantity === 0;

    let colorWentOutOfStock = false;
    const cb = before.colorQuantities ?? {};
    const ca = after.colorQuantities ?? {};

    const allColors = new Set([...Object.keys(cb), ...Object.keys(ca)]);
    for (const color of allColors) {
      const b = cb[color] ?? 0;
      const a = ca[color] ?? 0;
      if (b > 0 && a === 0) {
        colorWentOutOfStock = true;
        break;
      }
    }

    if (!(mainWentOutOfStock || colorWentOutOfStock)) return;

    const shopId = after.shopId;
    if (!shopId) return;

    // Atomic deduplication via Redis (30s window)
    const shouldProcess = await dedup(`dedupe:shop_stock:${productId}`, 30);
    if (!shouldProcess) {
      console.log(`Skipping duplicate shop stock notification for product ${productId}`);
      return;
    }

    // Load shop for name and members
    const shopSnap = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopSnap.exists) return;
    const shopData = shopSnap.data();

    // Build isRead map for all members
    const isReadMap = {};
    const addMember = (id) => {
      if (id && typeof id === 'string') {
        isReadMap[id] = false;
      }
    };

    addMember(shopData.ownerId);
    if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach(addMember);
    if (Array.isArray(shopData.editors)) shopData.editors.forEach(addMember);
    if (Array.isArray(shopData.viewers)) shopData.viewers.forEach(addMember);

    if (Object.keys(isReadMap).length === 0) {
      console.log('No members to notify');
      return;
    }

    const productName = after.productName || 'Your product';

    // ✅ Write to shop_notifications (triggers sendShopNotificationOnCreation)
    await admin.firestore().collection('shop_notifications').add({
      type: 'product_out_of_stock_seller_panel',
      shopId,
      shopName: shopData.name || '',
      productId,
      productName,
      isRead: isReadMap,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      message_en: `Product "${productName}" is out of stock!`,
      message_tr: `"${productName}" ürünü stokta kalmadı!`,
      message_ru: `Товар "${productName}" закончился!`,
    });

    console.log(`✅ Shop notification created for ${Object.keys(isReadMap).length} members (product ${productId})`);
  },
);

export const onGeneralProductStockChange = onDocumentUpdated(
  {
    document: 'products/{productId}',
    region: 'europe-west3',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const productId = event.params.productId;

    // Check stock change conditions FIRST (before deduplication to avoid unnecessary transactions)
    const mainWentOutOfStock = before.quantity > 0 && after.quantity === 0;

    let colorWentOutOfStock = false;
    const cb = before.colorQuantities ?? {};
    const ca = after.colorQuantities ?? {};

    const allColors = new Set([...Object.keys(cb), ...Object.keys(ca)]);
    for (const color of allColors) {
      const b = cb[color] ?? 0;
      const a = ca[color] ?? 0;
      if (b > 0 && a === 0) {
        colorWentOutOfStock = true;
        break;
      }
    }

    if (!(mainWentOutOfStock || colorWentOutOfStock)) return;

    // Who owns this product?
    const sellerId = after.userId;
    if (!sellerId) return;

    // Atomic deduplication via Redis (30s window)
    const shouldProcess = await dedup(`dedupe:general_stock:${productId}`, 30);
    if (!shouldProcess) {
      console.log(`Skipping duplicate general stock notification for product ${productId}`);
      return;
    }

    // Prepare messages
    const name = after.productName || 'Your product';
    const en = `Your product "${name}" is out of stock.`;
    const tr = `Ürününüz "${name}" stokta kalmadı.`;
    const ru = `Ваш продукт "${name}" распродан.`;

    // Write single notification
    await admin.firestore().collection('users').doc(sellerId).collection('notifications').add({
      type: 'product_out_of_stock',
      productId,
      productName: name,
      message_en: en,
      message_tr: tr,
      message_ru: ru,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false,
    });

    console.log(`General stock notification sent to user ${sellerId} for product ${productId}`);
  },
);

export const deleteUserAccount = onCall(
  {
    region: 'europe-west3',
    timeoutSeconds: 540,
    memory: '512MiB',
    maxInstances: 5
  },
  async (request) => {
    const {auth, data} = request;
 
    // === 1) Authentication check ===
    if (!auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const callerUid = auth.uid;
 
    // === 2) Determine target UID (admin or self-delete) ===
    let targetUid;
    let isAdminDelete = false;
 
    if (data.uid) {
      // — Admin path —
      isAdminDelete = true;
 
      if (typeof data.uid !== 'string' || !data.uid.trim()) {
        throw new HttpsError(
          'invalid-argument',
          'You must provide a valid target uid.',
        );
      }
 
      const adminDoc = await admin
        .firestore()
        .collection('users')
        .doc(callerUid)
        .get();
 
      if (!adminDoc.exists || adminDoc.data()?.isAdmin !== true) {
        throw new HttpsError(
          'permission-denied',
          'Only admins can delete other users.',
        );
      }
 
      targetUid = data.uid.trim();
 
      if (targetUid === callerUid) {
        throw new HttpsError(
          'invalid-argument',
          'Use self-delete to remove your own account.',
        );
      }
    } else {
      // — Self-delete path —
      if (typeof data.email !== 'string' || !data.email.trim()) {
        throw new HttpsError(
          'invalid-argument',
          'You must provide your email to confirm deletion.',
        );
      }
 
      const userRecord = await admin.auth().getUser(callerUid);
      if (userRecord.email?.toLowerCase() !== data.email.trim().toLowerCase()) {
        throw new HttpsError(
          'permission-denied',
          'Provided email does not match your account.',
        );
      }
 
      targetUid = callerUid;
    }
 
    // === 3) Verify target user exists ===
    try {
      await admin.auth().getUser(targetUid);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        throw new HttpsError(
          'not-found',
          'Target user account does not exist.',
        );
      }
      throw new HttpsError('internal', 'Failed to verify user account.');
    }
 
    const db = admin.firestore();
    const userDocRef = db.collection('users').doc(targetUid);
 
    // === 4) Remove user from all shops/restaurants (best-effort) ===
    try {
      const userSnap = await userDocRef.get();
      if (userSnap.exists) {
        const userData = userSnap.data();
        const roleToField = {
          'co-owner': 'coOwners',
          'editor': 'editors',
          'viewer': 'viewers',
        };
 
        const removalPromises = [];
 
        // Remove from shops
        const memberOfShops = userData.memberOfShops ?? {};
        for (const [shopId, role] of Object.entries(memberOfShops)) {
          const field = roleToField[role];
          if (field) {
            removalPromises.push(
              db.collection('shops').doc(shopId).update({
                [field]: admin.firestore.FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from shop ${shopId}:`, err.message);
              }),
            );
          }
        }
 
        // Remove from restaurants
        const memberOfRestaurants = userData.memberOfRestaurants ?? {};
        for (const [restId, role] of Object.entries(memberOfRestaurants)) {
          const field = roleToField[role];
          if (field) {
            removalPromises.push(
              db.collection('restaurants').doc(restId).update({
                [field]: admin.firestore.FieldValue.arrayRemove(targetUid),
              }).catch((err) => {
                console.warn(`Could not remove user from restaurant ${restId}:`, err.message);
              }),
            );
          }
        }
 
        // Cancel pending invitations sent TO this user
        const invCollections = ['shopInvitations', 'restaurantInvitations'];
        const invQueryResults = await Promise.all(
          invCollections.map((coll) =>
            db.collection(coll)
              .where('userId', '==', targetUid)
              .where('status', '==', 'pending')
              .get(),
          ),
        );
        for (const snapshot of invQueryResults) {
          for (const doc of snapshot.docs) {
            removalPromises.push(
              doc.ref.update({status: 'cancelled'}).catch((err) => {
                console.warn(`Could not cancel invitation ${doc.id}:`, err.message);
              }),
            );
          }
        }
 
        if (removalPromises.length > 0) {
          await Promise.all(removalPromises);
          console.log(`✓ Removed user ${targetUid} from ${removalPromises.length} shop/restaurant/invitation references`);
        }
      }
    } catch (err) {
      console.error('Warning: Failed to clean up shop/restaurant memberships:', err);
      // Best-effort — don't block deletion
    }
 
    // === 5) Delete Auth account FIRST ===
    // Auth first so if Firestore fails, user just has orphaned data (harmless).
    // If we did Firestore first and Auth failed, user could log in with no data (broken).
    try {
      await admin.auth().deleteUser(targetUid);
      console.log(`✓ Deleted Auth record for uid=${targetUid}`);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        console.log('Auth user was already deleted, continuing with Firestore cleanup');
      } else {
        // Auth failed — nothing else was touched, user is fully intact
        console.error('Auth deletion failed:', err);
        throw new HttpsError(
          'internal',
          'Failed to delete authentication record.',
        );
      }
    }
 
    // === 6) Delete Firestore data (including all subcollections) ===
    // At this point Auth is already gone. If this fails, we have harmless
    // orphaned data. We log a critical alert so ops can clean it up manually.
    try {
      const docSnapshot = await userDocRef.get();
 
      if (docSnapshot.exists || await hasSubcollections(userDocRef)) {
        await db.recursiveDelete(userDocRef);
        console.log(`✓ Deleted Firestore data (including subcollections) for uid=${targetUid}`);
      } else {
        console.log(`No Firestore data found for uid=${targetUid}`);
      }
    } catch (err) {
      console.error('CRITICAL: Firestore deletion failed after Auth was already deleted:', err);
 
      // Alert ops — Auth is gone but data remains, needs manual cleanup
      try {
        await db.collection('_payment_alerts').add({
          type: 'user_deletion_firestore_failed',
          severity: 'high',
          userId: targetUid,
          isAdminDelete,
          deletedBy: callerUid,
          errorMessage: err.message,
          message: `Auth deleted but Firestore cleanup failed for ${targetUid}. Manual cleanup required.`,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {/* alerting must never throw */}
 
      // Still return success — the account (Auth) IS deleted, the user cannot log in.
      // Orphaned Firestore data is a cleanup task, not a user-facing failure.
      return {
        success: true,
        partial: true,
        message: isAdminDelete ? `User account ${targetUid} has been deleted. Some data cleanup is pending.` : 'Your account has been deleted. Some data cleanup is pending.',
        deletedUid: targetUid,
      };
    }
 
    // === 7) Return success ===
    return {
      success: true,
      message: isAdminDelete ? `User account ${targetUid} has been deleted.` : 'Your account has been deleted.',
      deletedUid: targetUid,
    };
  },
);
 
async function hasSubcollections(docRef) {
  const collections = await docRef.listCollections();
  return collections.length > 0;
}

export const onBannerUpload = onObjectFinalized(
  {region: 'europe-west2'},
  async (event) => {
    const object = event.data;
    if (!object) return;

    const filePath = object.name;
    if (!filePath || !filePath.startsWith('market_top_ads_banners/')) {
      return;
    }

    const bucketName = object.bucket;
    const docId = path.basename(filePath); // e.g. "1623456789012_my.jpg"

    // 1) Build the public URL
    const imageUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
      `${encodeURIComponent(filePath)}?alt=media`;

    // 2) Download to a temp file
    const tmpFile = path.join(os.tmpdir(), docId);
    await admin
      .storage()
      .bucket(bucketName)
      .file(filePath)
      .download({destination: tmpFile});

    // 3) Compute dominant edge color
    let dominantColor;
    try {
      dominantColor = await getDominantColor(tmpFile);
    } finally {
      fs.unlinkSync(tmpFile);
    }

    // 4) Write (or overwrite) the Firestore doc in one go
    await admin
      .firestore()
      .collection('market_top_ads_banners')
      .doc(docId)
      .set({
        imageUrl,
        storagePath: filePath,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        dominantColor,
        isActive: true,
      });
  },
);

const esc = (s) => String(s)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

// Main redirect handler for shared favorites URLs
export const sharedFavoritesRedirect = onRequest({region: 'europe-west3', maxInstances: 100}, async (req, res) => {
  try {
    const shareId = req.path.split('/').pop();

    if (!shareId) {
      res.redirect('https://app.nar24.com');
      return;
    }

    // Get share data for meta tags
    const doc = await admin.firestore().collection('shared_favorites').doc(shareId).get();

    if (!doc.exists) {
      res.redirect('https://app.nar24.com');
      return;
    }

    const data = doc.data();

    // Check if expired
    if (data.expiresAt && data.expiresAt.toDate() < new Date()) {
      res.redirect('https://app.nar24.com');
      return;
    }

    const shareTitle = data.shareTitle || 'Nar24 - Shared Favorites';
    const shareDescription = data.shareDescription || 'Check out these amazing products!';
    const shareUrl = `https://app.nar24.com/shared-favorites/${shareId}`;
    const appIcon = data.appIcon || 'https://app.nar24.com/assets/images/naricon.png?v=2';
    const langCode = data.languageCode || 'en';

    const html = `
<!DOCTYPE html>
<html lang="${esc(langCode)}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${esc(shareTitle)}</title>
    
    <!-- Open Graph meta tags -->
    <meta property="og:title" content="${esc(shareTitle)}">
    <meta property="og:description" content="${esc(shareDescription)}">
    <meta property="og:image" content="${esc(appIcon)}">
    <meta property="og:image:url" content="${esc(appIcon)}">
    <meta property="og:image:secure_url" content="${esc(appIcon)}">
    <meta property="og:image:width" content="120">
    <meta property="og:image:height" content="120">
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:alt" content="Nar24 App Icon">
    <meta property="og:url" content="${esc(shareUrl)}">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Nar24">
    <meta property="og:locale" content="${esc(langCode)}_${esc(langCode.toUpperCase())}">
    
    <!-- Additional meta tags -->
    <meta name="image" content="${esc(appIcon)}">
    <meta name="thumbnail" content="${esc(appIcon)}">
    
    <!-- Twitter Card meta tags -->
    <meta name="twitter:card" content="summary">
    <meta name="twitter:title" content="${esc(shareTitle)}">
    <meta name="twitter:description" content="${esc(shareDescription)}">
    <meta name="twitter:image" content="${esc(appIcon)}">
    <meta name="twitter:image:src" content="${esc(appIcon)}">
    <meta name="twitter:site" content="@nar24app">
    
    <!-- WhatsApp specific -->
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:alt" content="Nar24 App Icon">
    
    <!-- Telegram -->
    <meta name="telegram:channel" content="@nar24app">
    
    <!-- App store meta tags -->
    <meta name="apple-itunes-app" content="app-id=YOUR_IOS_APP_ID">
    <meta name="google-play-app" content="app-id=com.cts.emlak">
    
    <!-- Favicon -->
    <link rel="icon" type="image/png" href="${esc(appIcon)}">
    <link rel="apple-touch-icon" href="${esc(appIcon)}">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #00A86B 0%, #00C851 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        
        .container {
            text-align: center;
            max-width: 400px;
            padding: 40px 20px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.2);
        }
        
        .app-icon {
            width: 80px;
            height: 80px;
            border-radius: 18px;
            margin: 0 auto 20px;
            display: block;
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.3);
        }
        
        .app-name {
            font-size: 28px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .share-title {
            font-size: 18px;
            margin-bottom: 8px;
            opacity: 0.9;
        }
        
        .share-description {
            font-size: 14px;
            margin-bottom: 30px;
            opacity: 0.8;
        }
        
        .share-url {
            font-size: 12px;
            margin-bottom: 20px;
            opacity: 0.7;
            word-break: break-all;
            background: rgba(255, 255, 255, 0.1);
            padding: 8px 12px;
            border-radius: 8px;
        }
        
        .download-buttons {
            display: flex;
            flex-direction: column;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .download-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 12px 24px;
            background: rgba(255, 255, 255, 0.9);
            color: #333;
            text-decoration: none;
            border-radius: 12px;
            font-weight: 600;
            transition: all 0.3s ease;
            gap: 10px;
        }
        
        .download-btn:hover {
            background: white;
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.2);
        }
        
        .open-app-btn {
            background: #FF6B35;
            color: white;
            font-size: 16px;
            padding: 15px 30px;
        }
        
        .open-app-btn:hover {
            background: #E55A2B;
        }
        
        .footer {
            margin-top: 20px;
            font-size: 12px;
            opacity: 0.7;
        }
        
        @media (max-width: 480px) {
            .container {
                margin: 20px;
                padding: 30px 15px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="${esc(appIcon)}" alt="Nar24" class="app-icon" 
             onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22
              width=%2280%22 height=%2280%22 viewBox=%220 0 80 80%22%3E%3Crect width=%2280%22
               height=%2280%22 rx=%2218%22 fill=%22%2300A86B%22/%3E%3Ctext x=%2240%22 y=%2250%22
                text-anchor=%22middle%22 dy=%22.3em%22 font-family=%22Arial%22 font-size=%2240%22
                 fill=%22white%22%3EN%3C/text%3E%3C/svg%3E'">
        
        <h1 class="app-name">Nar24</h1>
        <h2 class="share-title">${esc(shareTitle)}</h2>
        <p class="share-description">${esc(shareDescription)}</p>
        
        <div class="share-url">🔗 ${esc(shareUrl)}</div>
        
        <div class="download-buttons">
            <a href="#" class="download-btn open-app-btn" onclick="openApp()">
                📱 Open in Nar24 App
            </a>
            <a href="https://play.google.com/store/apps/details?id=com.cts.emlak" class="download-btn" target="_blank">
                📲 Download for Android
            </a>
            <a href="https://apps.apple.com/app/id6752034508" class="download-btn" target="_blank">
                🍎 Download for iOS
            </a>
        </div>
        
        <div class="footer">
            <p>Powered by Nar24</p>
        </div>
    </div>

    <script>
        var SHARE_ID = ${JSON.stringify(shareId)};
        
        function openApp() {
            var deepLink = 'nar24app://shared-favorites/' + SHARE_ID;
            var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
            var isAndroid = /Android/.test(navigator.userAgent);
            
            if (isIOS) {
                window.location.href = deepLink;
                setTimeout(function() {
                    window.location.href = 'https://apps.apple.com/app/id6752034508';
                }, 2000);
            } else if (isAndroid) {
                window.location.href = deepLink;
                setTimeout(function() {
                    window.location.href = 'https://play.google.com/store/apps/details?id=com.cts.emlak';
                }, 2000);
            } else {
                alert('Please download the Nar24 app on your mobile device to view shared favorites.');
            }
        }
        
        if (/Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)) {
            setTimeout(function() {
                var iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = 'nar24app://shared-favorites/' + SHARE_ID;
                document.body.appendChild(iframe);
                
                setTimeout(function() {
                    if (iframe.parentNode) {
                        document.body.removeChild(iframe);
                    }
                }, 1000);
            }, 1000);
        }
    </script>
</body>
</html>`;

    res.set('Content-Type', 'text/html');
    res.send(html);
  } catch (error) {
    console.error('Error in shared favorites redirect:', error);
    res.redirect('https://app.nar24.com');
  }
});

// ✅ FIXED: Updated getShareImage function with consistent domain
export const getShareImage = onRequest({region: 'europe-west3', maxInstances: 100}, async (req, res) => {
  try {
    const shareId = req.query.shareId;

    if (!shareId) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com/assets/images/naricon.png');
      return;
    }

    // Get share data
    const doc = await admin.firestore().collection('shared_favorites').doc(shareId).get();

    if (!doc.exists) {
      // ✅ FIXED: Use app.nar24.com consistently
      res.redirect('https://app.nar24.com/assets/images/naricon.png');
      return;
    }

    const data = doc.data();
    // ✅ FIXED: Use app.nar24.com consistently
    const appIcon = data.appIcon || 'https://app.nar24.com/assets/images/naricon.png';

    // Redirect to the app icon (or you could generate a custom image here)
    res.redirect(appIcon);
  } catch (error) {
    console.error('Error serving share image:', error);
    // ✅ FIXED: Use app.nar24.com consistently
    res.redirect('https://app.nar24.com/assets/images/naricon.png');
  }
});

export const checkOrderCompletion = onDocumentUpdated({
  document: 'orders/{orderId}/items/{itemId}',
  region: 'europe-west3',
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Only run if arrivedAt was just set (not on other updates)
  if (!before.arrivedAt && after.arrivedAt) {
    const orderId = event.params.orderId;
    const db = admin.firestore();

    try {
      // First, get the order to check its current status
      const orderDoc = await db
        .collection('orders')
        .doc(orderId)
        .get();

      const orderData = orderDoc.data();

      // IMPORTANT: Don't update if order is already delivered (partial or complete)
      if (orderData && orderData.distributionStatus === 'delivered') {
        console.log(`Order ${orderId} is already delivered (partial delivery), skipping status update`);

        // Just update that all items are gathered without changing distribution status
        const itemsSnapshot = await db
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .where('gatheringStatus', '!=', 'at_warehouse')
          .limit(1)
          .get();

        if (itemsSnapshot.empty) {
          await db
            .collection('orders')
            .doc(orderId)
            .update({
              allItemsGathered: true,
              // DO NOT update distributionStatus for delivered orders
              readyForDistributionAt: FieldValue.serverTimestamp(),
            });
          console.log(`Order ${orderId} has all items gathered but keeping delivered status (partial delivery)`);
        }
        return;
      }

      // For non-delivered orders, check if all items are at warehouse
      const itemsSnapshot = await db
        .collection('orders')
        .doc(orderId)
        .collection('items')
        .where('gatheringStatus', '!=', 'at_warehouse')
        .limit(1)
        .get();

      // If query returns empty, ALL items are at warehouse
      if (itemsSnapshot.empty) {
        await db
          .collection('orders')
          .doc(orderId)
          .update({
            allItemsGathered: true,
            distributionStatus: 'ready',
            readyForDistributionAt: FieldValue.serverTimestamp(),
          });

        console.log(`Order ${orderId} marked as ready for distribution`);
      }
    } catch (error) {
      console.error(`Error checking order ${orderId} completion:`, error);
      throw error;
    }
  }
});

export {deleteCampaign, processCampaignDeletion, getCampaignDeletionStatus, cleanupCampaignDeletionQueue} from './4-campaigns/index.js';
export {submitReview, updateProductMetrics, updateShopProductMetrics, updateShopMetrics, updateUserSellerMetrics, sendReviewNotifications} from './5-reviews/index.js';
export {rebuildRelatedProducts} from './6-related_products/index.js';
export {trackProductClick, flushClicks} from './7-click-analytics/index.js';
export {validateCartCheckout, updateCartCache} from './8-cart-validation/index.js';
export {calculateCartTotals} from './9-cart-total-price/index.js';
export {clampNegativeMetrics} from './10-cart&favorite-metrics/index.js';
export {
  batchUserActivity,
  cleanupOldActivityEvents,
  computeUserPreferences,
  processActivityDLQ,
} from './11-user-activity/index.js';
export {computeTrendingProductsScheduled, cleanupTrendingHistory} from './12-trending-products/index.js';
export {updatePersonalizedFeeds, processPersonalizedFeedBatch} from './13-personalized-feed/index.js';
export {adminToggleProductArchiveStatus, approveArchivedProductEdit, approveProductApplication, rejectProductApplication, setCargoGuyClaim} from './14-admin-actions/index.js';
export {translateText, translateBatch} from './15-openai-translation/index.js';
export {processQRCodeGeneration, verifyQRCode, markQRScanned, retryQRGeneration} from './16-qr-for-orders/index.js';
export {
  grantUserCoupon,
  grantFreeShipping,
  getUserCouponsAndBenefits,
  revokeCoupon,
  revokeBenefit,
} from './17-coupons/index.js';
export {alertOnPaymentIssue, detectPaymentAnomalies} from './18-payment-alerts/index.js';
export {weeklyAccountingScheduled, triggerWeeklyAccounting} from './19-accounting-sales-reports/index.js';
export { computeWeeklyAnalytics, computeMonthlySummary, computeDateRangeAnalytics } from './20-admin-analytics/index.js';
export {
  createTypesenseCollections,
  syncProductsWithTypesense,
  syncShopProductsWithTypesense,
  syncShopsWithTypesense,
  syncOrdersWithTypesense,
  syncFoodsWithTypesense,
  syncRestaurantsWithTypesense
} from './23-typesense/index.js';
export { computeRankingScores } from './24-promotion-score/index.js';
export { addProductsToCampaign, removeProductFromCampaign, updateCampaignProductDiscount } from './25-shop-campaign/index.js';
export { submitProduct, submitProductEdit } from './26-list-product/index.js';
export { processFoodOrder, initializeFoodPayment, foodPaymentCallback, checkFoodPaymentStatus, generateFoodReceiptBackground, updateFoodOrderStatus, submitRestaurantReview } from './27-food-payment/index.js';
export { sendShopInvitation, handleShopInvitation, revokeShopAccess, leaveShop, cancelShopInvitation, backfillShopClaims, setAdminClaim } from './28-shop-invitation/index.js';
export { initializeIsbankPayment, isbankPaymentCallback, checkIsbankPaymentStatus, clearPurchasedCartItems, processOrderNotification, recoverStuckPayments, processPostOrderWork } from './29-product-payment/index.js';
export { onFoodOrderStatusChange, informFoodCourier, cleanupExpiredCourierNotifications, callFoodCourier, createScannedRestaurantOrder, cleanupExpiredCourierCalls } from './30-food-courier-notifications/index.js';
export { extractColorOnly, initializeIsbankAdPayment, isbankAdPaymentCallback, checkIsbankAdPaymentStatus, processAdColorExtraction, processAdExpiration, processAdAnalytics, trackAdClick, trackAdConversion, createDailyAdAnalyticsSnapshot, cleanupExpiredAds, recoverStuckAdPayments } from './31-homescreen-ads-payment/index.js';
export { expireSingleBoost, initializeBoostPayment, boostPaymentCallback, checkBoostPaymentStatus, recoverStuckBoostPayments } from './32-product-boost-payment/index.js';
export { cleanupPaymentCollections } from './33-payment-cleanup/index.js';
export { setMasterCourierClaim } from './34-master-courier/index.js';
export { onDeliveryCompleted, recalcCourierStats, getCourierStatsSummary } from './35-courier-stats/index.js';
export { calculateDailyFoodAccounting, calculateWeeklyFoodAccounting, calculateMonthlyFoodAccounting } from './36-food-accounting/index.js';
export { generateRestaurantReceiptBackground } from './37-restaurant-receipt/index.js';
export { scheduleDiscountExpiry, restoreDiscountPrice } from './38-food-discount/index.js';
export { createTestCouriers, deleteTestCouriers, listTestCouriers } from './39-fake-accounts/index.js';
export { processCourierAction } from './40-courier-actions/index.js';
export { generateBusinessReport } from './41-business-client-side-accounting/index.js';
export { moderateImage } from './42-moderate-image-vision-api/index.js';
export { generateReceiptBackground } from './43-receipt-product-payment/index.js';
export { generatePDFReport } from './44-business-report-creation/index.js';
export { startEmail2FA, verifyEmail2FA, resendEmail2FA, createTotpSecret, verifyTotp, disableTotp, hasTotp, cleanupExpiredVerificationData } from './45-2FA/index.js'; 
export { sendNotificationOnCreation, sendRestaurantNotificationOnCreation, sendShopNotificationOnCreation, registerFcmToken, cleanupInvalidToken, removeFcmToken, createProductQuestionNotification } from './46-FCM-notifications/index.js';
export { registerWithEmailPassword, verifyEmailCode, resendEmailVerificationCode, sendPasswordResetEmail, sendReceiptEmail, sendReportEmail, shopWelcomeEmail } from './47-emails/index.js';
export { removeShopProduct, deleteProduct, toggleProductPauseStatus } from './48-product-management/index.js';
export { incrementImpressionCount, flushImpressions } from './49-impression/index.js';
