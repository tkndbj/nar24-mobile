import crypto from 'crypto';
import { onRequest, onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { transliterate } from 'transliteration';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import {CloudTasksClient} from '@google-cloud/tasks';
import path from 'path';
import os from 'os';
import fs from 'fs';
import {getDominantColor} from '../getDominantColor.js';
import { setAdPaymentExpiresAt } from '../33-payment-cleanup/index.js';

const tasksClient = new CloudTasksClient();

const secretClient = new SecretManagerServiceClient();

// Helper to fetch a secret
async function getSecret(secretName) {
    const [version] = await secretClient.accessSecretVersion({name: secretName});
    return version.payload.data.toString('utf8');
  } 
  
  // İş Bankası Configuration
  let isbankConfig = null;
  
  async function getIsbankConfig() {
    if (!isbankConfig) {
      const [clientId, apiUser, apiPassword, storeKey] = await Promise.all([
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_CLIENT_ID/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_USER/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_API_PASSWORD/versions/latest'),
        getSecret('projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest'),
      ]);
  
      isbankConfig = {
        clientId,
        apiUser,
        apiPassword,
        storeKey,
        gatewayUrl: 'https://sanalpos.isbank.com.tr/fim/est3Dgate',
        currency: '949',
        storeType: '3d_pay_hosting',
      };
    }
    return isbankConfig;
  }

async function generateHashVer3(params) {
    // Get all parameter keys except 'hash' and 'encoding'!!!
    const keys = Object.keys(params)
      .filter((key) => key !== 'hash' && key !== 'encoding')
      .sort((a, b) => {
        // Case-insensitive sort - convert both to lowercase for comparison
        return a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US');
      });
      const isbankConfig = await getIsbankConfig();
    // Build the plain text with pipe separators
    const values = keys.map((key) => {
      let value = String(params[key] || '');
      // Escape special characters as per documentation
      value = value.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
      return value;
    });
  
    const plainText = values.join('|') + '|' + isbankConfig.storeKey.trim();
  
    console.log('Hash keys order:', keys.join('|'));
    console.log('Hash plain text:', plainText);
  
    return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
  }
  
  export const extractColorOnly = onCall(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 30,
    },
    async (request) => {
      try {
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {imageUrl} = request.data;
  
        if (!imageUrl) {
          throw new HttpsError('invalid-argument', 'imageUrl is required');
        }
  
        console.log(`🎨 Extracting color from: ${imageUrl}`);
  
        // Extract color using your existing function
        const dominantColor = await extractDominantColorFromUrl(imageUrl);
  
        console.log(`✅ Color extracted: 0x${dominantColor.toString(16).toUpperCase()}`);
  
        return {
          success: true,
          dominantColor: dominantColor,
        };
      } catch (error) {
        console.error('❌ Error extracting color:', error);
        // Return default gray color if extraction fails
        return {
          success: false,
          dominantColor: 0xFF9E9E9E,
          error: error.message,
        };
      }
    },
  );
  
  async function extractDominantColorFromUrl(imageUrl) {
    let tmpFile = null;
  
    try {
      // Create unique temporary file
      tmpFile = path.join(os.tmpdir(), `ad_color_${Date.now()}_${Math.random().toString(36).substr(2, 9)}.jpg`);
  
      console.log(`Downloading image from: ${imageUrl}`);
  
      // Download image from Firebase Storage URL
      const response = await fetch(imageUrl);
  
      if (!response.ok) {
        throw new Error(`Failed to fetch image: ${response.statusText}`);
      }
  
      const buffer = await response.arrayBuffer();
      fs.writeFileSync(tmpFile, Buffer.from(buffer));
  
      console.log(`Image downloaded to: ${tmpFile}`);
  
      // Extract dominant color using your existing function
      const dominantColor = await getDominantColor(tmpFile);
  
      console.log(`✅ Dominant color extracted: ${dominantColor} (0x${dominantColor.toString(16).toUpperCase()})`);
  
      return dominantColor;
    } catch (error) {
      console.error('❌ Error extracting dominant color:', error);
      // Return a default pleasant gray color if extraction fails
      return 0xFF9E9E9E;
    } finally {
      // Cleanup: Always delete temp file
      if (tmpFile && fs.existsSync(tmpFile)) {
        try {
          fs.unlinkSync(tmpFile);
          console.log(`🗑️ Cleaned up temp file: ${tmpFile}`);
        } catch (cleanupError) {
          console.error('⚠️ Failed to cleanup temp file:', cleanupError);
        }
      }
    }
  }
  
  async function queueDominantColorExtraction(adId, imageUrl, adType) {
    // Only process topBanner ads
    if (adType !== 'topBanner') {
      console.log(`⏭️ Skipping color extraction for ${adType} (not a topBanner)`);
      return;
    }
  
    const project = 'emlak-mobile-app';
    const location = 'europe-west3';
    const queue = 'ad-color-extraction';
  
    try {
      const parent = tasksClient.queuePath(project, location, queue);
  
      const task = {
        httpRequest: {
          httpMethod: 'POST',
          url: `https://${location}-${project}.cloudfunctions.net/processAdColorExtraction`,
          body: Buffer.from(JSON.stringify({
            adId,
            imageUrl,
            adType,
          })).toString('base64'),
          headers: {
            'Content-Type': 'application/json',
          },
          oidcToken: {
            serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
          },
        },
      };
  
      await tasksClient.createTask({parent, task});
      console.log(`✅ Color extraction task queued for ad ${adId}`);
    } catch (error) {
      console.error('❌ Error queuing color extraction task:', error);
      // Don't throw - color extraction is non-critical
      // The ad is already activated, color extraction is a bonus feature
    }
  }
  
  function calculateExpirationDate(duration) {
    const now = new Date();
  
    switch (duration) {
    case 'oneWeek':
        return new Date(now.getTime() + 1 * 60 * 1000);
    case 'twoWeeks':
      return new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
    case 'oneMonth':
      return new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    default:
      return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    }
  }
  
  // Helper to schedule ad expiration task
  async function scheduleAdExpiration(submissionId, expirationDate) {
    const project = 'emlak-mobile-app';
    const location = 'europe-west3';
    const queue = 'ad-expirations';
  
    try {
      const parent = tasksClient.queuePath(project, location, queue);
  
      const task = {
        httpRequest: {
          httpMethod: 'POST',
          url: `https://${location}-${project}.cloudfunctions.net/processAdExpiration`,
          body: Buffer.from(JSON.stringify({submissionId})).toString('base64'),
          headers: {'Content-Type': 'application/json'},
          oidcToken: {
            serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
          },
        },
        scheduleTime: {
          seconds: Math.floor(expirationDate.getTime() / 1000),
        },
      };
  
      await tasksClient.createTask({parent, task});
      console.log(`✅ Scheduled expiration task for ad ${submissionId}`);
    } catch (error) {
      console.error('Error scheduling ad expiration:', error);
      // Don't throw - task scheduling is non-critical
    }
  }
  
  // Initialize Ad Payment
  export const initializeIsbankAdPayment = onCall(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 30,
    },
    async (request) => {
      try {
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {submissionId, paymentLink} = request.data;
  
        if (!submissionId || !paymentLink) {
          throw new HttpsError(
            'invalid-argument',
            'submissionId and paymentLink are required',
          );
        }
  
        const db = admin.firestore();
  
        // Get submission details
        const submissionRef = db.collection('ad_submissions').doc(submissionId);
        const submissionSnap = await submissionRef.get();
  
        if (!submissionSnap.exists) {
          throw new HttpsError('not-found', 'Ad submission not found');
        }
  
        const submission = submissionSnap.data();
  
        // Verify ownership
        if (submission.userId !== request.auth.uid) {
          throw new HttpsError('permission-denied', 'Unauthorized');
        }
  
        // Verify status
        if (submission.status !== 'approved') {
          throw new HttpsError(
            'failed-precondition',
            'Ad submission must be approved',
          );
        }
  
        // Verify payment link matches
        if (submission.paymentLink !== paymentLink) {
          throw new HttpsError('invalid-argument', 'Invalid payment link');
        }
  
        const amount = submission.price;
        const orderNumber = `AD-${submissionId}-${Date.now()}`;
        const isbankConfig = await getIsbankConfig();
        // Get user info
        const userSnap = await db.collection('users').doc(request.auth.uid).get();
        const userData = userSnap.data() || {};
        const customerName = userData.displayName || userData.name || 'Customer';
        const customerEmail = userData.email || '';
        const customerPhone = userData.phoneNumber || '';
  
        const sanitizedCustomerName = transliterate(customerName)
          .replace(/[^a-zA-Z0-9\s]/g, '')
          .trim()
          .substring(0, 50) || 'Customer';
  
        const formattedAmount = (parseFloat(amount) * 1.2).toFixed(2); // Include 20% tax
        const rnd = Date.now().toString();
  
        const baseUrl = `https://europe-west3-emlak-mobile-app.cloudfunctions.net`;
        const okUrl = `${baseUrl}/isbankAdPaymentCallback`;
        const failUrl = `${baseUrl}/isbankAdPaymentCallback`;
        const callbackUrl = `${baseUrl}/isbankAdPaymentCallback`;
  
        // Hash params
        const hashParams = {
          BillToName: sanitizedCustomerName || '',
          amount: formattedAmount,
          callbackurl: callbackUrl,
          clientid: isbankConfig.clientId,
          currency: isbankConfig.currency,
          email: customerEmail || '',
          failurl: failUrl,
          hashAlgorithm: 'ver3',
          islemtipi: 'Auth',
          lang: 'tr',
          oid: orderNumber,
          okurl: okUrl,
          rnd: rnd,
          storetype: isbankConfig.storeType,
          taksit: '',
          tel: customerPhone || '',
        };
  
        const hash = await generateHashVer3(hashParams);
  
        // Payment params
        const paymentParams = {
          clientid: isbankConfig.clientId,
          storetype: isbankConfig.storeType,
          hash: hash,
          hashAlgorithm: 'ver3',
          islemtipi: 'Auth',
          amount: formattedAmount,
          currency: isbankConfig.currency,
          oid: orderNumber,
          okurl: okUrl,
          failurl: failUrl,
          callbackurl: callbackUrl,
          lang: 'tr',
          rnd: rnd,
          taksit: '',
          BillToName: sanitizedCustomerName || '',
          email: customerEmail || '',
          tel: customerPhone || '',
        };
  
        console.log('Ad Payment params:', JSON.stringify(paymentParams, null, 2));

        const docData = {
          userId: request.auth.uid,
          submissionId: submissionId,
          amount: amount,
          totalAmount: parseFloat(formattedAmount),
          formattedAmount: formattedAmount,
          orderNumber: orderNumber,
          status: 'awaiting_3d',
          paymentParams: paymentParams,
          adData: {
            adType: submission.adType,
            duration: submission.duration,
            shopId: submission.shopId,
            shopName: submission.shopName,
            imageUrl: submission.imageUrl,
            linkType: submission.linkType || null,
            linkedShopId: submission.linkedShopId || null,
            linkedProductId: submission.linkedProductId || null,
          },
          customerInfo: {
            name: sanitizedCustomerName,
            email: customerEmail,
            phone: customerPhone,
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
        };

        let docWritten = false;
let lastWriteError = null;

for (let attempt = 1; attempt <= 3; attempt++) {
  try {
    const batch = db.batch();
    batch.set(db.collection('pendingAdPayments').doc(orderNumber), docData);
    batch.set(db.collection('pendingAdPaymentsBackup').doc(orderNumber), { ...docData, _isBackup: true });
    await batch.commit();
    docWritten = true;
    break;
  } catch (writeErr) {
    lastWriteError = writeErr;
    console.error(`[initializeIsbankAdPayment] Write attempt ${attempt}/3 failed:`, writeErr.message);
    if (attempt < 3) await new Promise((r) => setTimeout(r, 300 * attempt));
  }
}

if (!docWritten) {
  console.error(`[initializeIsbankAdPayment] All 3 write attempts failed for ${orderNumber}`);
  try {
    await db.collection('_payment_alerts').add({
      type: 'ad_payment_doc_write_failed',
      severity: 'high',
      orderNumber,
      userId: request.auth.uid,
      errorMessage: lastWriteError?.message || 'Unknown write error',
      isRead: false,
      isResolved: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {/* alerting must never throw */}
  throw new HttpsError('internal', 'Payment session could not be created. Please try again.');
}
      
  
        return {
          success: true,
          gatewayUrl: isbankConfig.gatewayUrl,
          paymentParams: paymentParams,
          orderNumber: orderNumber,
        };
      } catch (error) {
        console.error('İşbank ad payment initialization error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );

  function buildAdRedirectHtml(deepLink, title, subtitle = '') {
    const esc = (s) => String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    return `<!DOCTYPE html>
  <html>
  <head><title>${esc(title)}</title></head>
  <body>
    <div style="text-align:center;padding:50px;">
      <h2>${esc(title)}</h2>
      ${subtitle ? `<p>${esc(subtitle)}</p>` : ''}
    </div>
    <script>window.location.href = ${JSON.stringify(deepLink)};</script>
  </body>
  </html>`;
  }

  async function activateAdAfterPayment(db, oid, pendingPayment) {
    const adData = pendingPayment.adData;
    const submissionId = pendingPayment.submissionId;
  
    const expirationDate = calculateExpirationDate(adData.duration);
    const adActivationRef = db.collection(getAdCollectionName(adData.adType)).doc();
  
    const activationBatch = db.batch();
  
    activationBatch.update(db.collection('ad_submissions').doc(submissionId), {
      status: 'active',
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expirationDate),
      paymentOrderId: oid,
      activeAdId: adActivationRef.id,
    });
  
    activationBatch.set(adActivationRef, {
      submissionId,
      shopId: adData.shopId,
      shopName: adData.shopName,
      imageUrl: adData.imageUrl,
      adType: adData.adType,
      duration: adData.duration,
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expirationDate),
      isActive: true,
      isManual: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      linkType: adData.linkType || null,
      linkedShopId: adData.linkedShopId || null,
      linkedProductId: adData.linkedProductId || null,
      dominantColor: null,
      colorExtractionQueued: adData.adType === 'topBanner',
    });
  
    await activationBatch.commit();
  
    await queueDominantColorExtraction(adActivationRef.id, adData.imageUrl, adData.adType);
    await scheduleAdExpiration(submissionId, expirationDate);
  
    await db.collection('receiptTasks').add({
      receiptType: 'ad',
      ownerType: 'shop',
      ownerId: adData.shopId,
      buyerId: adData.shopId,
      orderId: oid,
      buyerName: adData.shopName,
      buyerEmail: pendingPayment.customerInfo?.email || '',
      buyerPhone: pendingPayment.customerInfo?.phone || '',
      totalPrice: pendingPayment.totalAmount,
      itemsSubtotal: pendingPayment.amount,
      taxAmount: pendingPayment.totalAmount - pendingPayment.amount,
      currency: 'TL',
      paymentMethod: 'Credit Card (3D Secure)',
      language: 'tr',
      adData: {
        adType: adData.adType,
        duration: adData.duration,
        shopName: adData.shopName,
        submissionId,
      },
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      orderDate: admin.firestore.FieldValue.serverTimestamp(),
    });
  
    return adActivationRef.id;
  }
  
  // Ad Payment Callback
  export const isbankAdPaymentCallback = onRequest(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 90,
      cors: true,
      invoker: 'public',
    },
    async (request, response) => {
        const startTime = Date.now();
        const db = admin.firestore();
      
        try {
          console.log('Ad payment callback invoked - method:', request.method);
          console.log('All callback parameters:', JSON.stringify(request.body, null, 2));
      
          const {Response, mdStatus, oid, ProcReturnCode, ErrMsg, HASH} = request.body;
      
          // İşbank probe request guard
          if (!request.body.oid && request.body.HASH && request.body.rnd) {
            console.log('[AdPayment] İşbank probe request — responding OK');
            response.status(200).send('<html><body></body></html>');
            return;
          }
      
          if (!oid) {
            console.error('Missing oid in callback. Full body:', request.body);
            response.status(400).send('Order number missing');
            return;
          }
      
          // Fetch storeKey BEFORE transaction (no async allowed inside tx)
          const storeKey = (await getSecret(
            'projects/emlak-mobile-app/secrets/ISBANK_STORE_KEY/versions/latest',
          )).trim();
      
          // Compute hash OUTSIDE transaction
          const computedHash = (() => {
            const keys = Object.keys(request.body)
              .filter((key) => {
                const lower = key.toLowerCase();
                return lower !== 'encoding' && lower !== 'hash' &&
                       lower !== 'countdown' && lower !== 'nationalidno';
              })
              .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase(), 'en-US'));
      
            const plainText =
              keys
                .map((key) => String(request.body[key] ?? '')
                  .replace(/\\/g, '\\\\').replace(/\|/g, '\\|'))
                .join('|') +
              '|' +
              storeKey.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
      
            return crypto.createHash('sha512').update(plainText, 'utf8').digest('base64');
          })();
      
          const hashValid = HASH && computedHash === HASH;
  
        // Log callback
        const callbackLogRef = db.collection('ad_payment_callback_logs').doc();
        await callbackLogRef.set({
          oid: oid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          requestBody: request.body,
          userAgent: request.headers['user-agent'] || null,
          ip: request.ip || request.headers['x-forwarded-for'] || null,
          processingStarted: new Date(startTime).toISOString(),
        });
  
        const pendingPaymentRef = db.collection('pendingAdPayments').doc(oid);
  
        const transactionResult = await db.runTransaction(async (transaction) => {
          const pendingPaymentSnap = await transaction.get(pendingPaymentRef);
        
          if (!pendingPaymentSnap.exists) {
            // Backup restore (mirrors product payment system)
            const backupSnap = await transaction.get(db.collection('pendingAdPaymentsBackup').doc(oid));
            if (backupSnap.exists) {
              console.warn(`[AdPayment] Primary doc missing for ${oid} — restoring from backup`);
              const backupData = backupSnap.data();
              transaction.set(pendingPaymentRef, {
                ...backupData,
                _restoredFromBackup: true,
                _restoredAt: admin.firestore.FieldValue.serverTimestamp(),
              });
        
              if (!hashValid) {
                transaction.update(pendingPaymentRef, {
                  status: 'hash_verification_failed',
                  receivedHash: HASH || null,
                  computedHash,
                  callbackLogId: callbackLogRef.id,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  ...setAdPaymentExpiresAt('hash_verification_failed'),
                });
                return { error: 'hash_failed' };
              }
        
              const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
              const isTransactionSuccess = Response === 'Approved' && ProcReturnCode === '00';
              if (!isAuthSuccess || !isTransactionSuccess) {
                transaction.update(pendingPaymentRef, {
                  status: 'payment_failed',
                  mdStatus, procReturnCode: ProcReturnCode,
                  errorMessage: ErrMsg || 'Payment failed',
                  rawResponse: request.body,
                  callbackLogId: callbackLogRef.id,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  ...setAdPaymentExpiresAt('payment_failed'),
                });
                return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
              }
        
              transaction.update(pendingPaymentRef, {
                status: 'processing',
                mdStatus, procReturnCode: ProcReturnCode,
                processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
                rawResponse: request.body,
                callbackLogId: callbackLogRef.id,
                ...setAdPaymentExpiresAt('processing'),
              });
              return { success: true, pendingPayment: backupData, restoredFromBackup: true };
            }
        
            return { error: 'not_found', message: 'Payment session not found' };
          }
        
          const pendingPayment = pendingPaymentSnap.data();
        
          if (pendingPayment.status === 'completed')
            {return { alreadyProcessed: true, status: 'completed' };}
          if (pendingPayment.status === 'payment_succeeded_activation_failed')
            {return { alreadyProcessed: true, status: pendingPayment.status };}
          if (pendingPayment.status === 'payment_failed')
            {return { alreadyProcessed: true, status: pendingPayment.status };}
          if (pendingPayment.status === 'hash_verification_failed')
            {return { alreadyProcessed: true, status: pendingPayment.status };}
          if (pendingPayment.status === 'processing' ||
              pendingPayment.status === 'payment_verified_activating_ad')
            {return { retry: true, pendingPayment };}
          if (pendingPayment.status !== 'awaiting_3d')
            {return { alreadyProcessed: true, status: pendingPayment.status };}
        
          if (!hashValid) {
            transaction.update(pendingPaymentRef, {
              status: 'hash_verification_failed',
              receivedHash: HASH || null,
              computedHash,
              callbackLogId: callbackLogRef.id,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              ...setAdPaymentExpiresAt('hash_verification_failed'),
            });
            return { error: 'hash_failed' };
          }
        
          const isAuthSuccess = ['1', '2', '3', '4'].includes(mdStatus);
          const isTransactionSuccess = Response === 'Approved' && ProcReturnCode === '00';
        
          if (!isAuthSuccess || !isTransactionSuccess) {
            transaction.update(pendingPaymentRef, {
              status: 'payment_failed',
              mdStatus, procReturnCode: ProcReturnCode,
              errorMessage: ErrMsg || 'Payment failed',
              rawResponse: request.body,
              callbackLogId: callbackLogRef.id,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              ...setAdPaymentExpiresAt('payment_failed'),
            });
            return { error: 'payment_failed', message: ErrMsg || 'Payment failed' };
          }
        
          transaction.update(pendingPaymentRef, {
            status: 'processing',
            mdStatus, procReturnCode: ProcReturnCode,
            processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
            rawResponse: request.body,
            callbackLogId: callbackLogRef.id,
            ...setAdPaymentExpiresAt('processing'),
          });
        
          return { success: true, pendingPayment };
        });  
  
        // Handle transaction results
        if (transactionResult.error) {
          if (transactionResult.error === 'not_found') {
            response.status(404).send('Payment session not found');
            return;
          }
  
          if (transactionResult.error === 'hash_failed') {
            response.send(buildAdRedirectHtml(
                'ad-payment-failed://hash-error',
                'Ödeme Doğrulama Hatası',
                'Lütfen tekrar deneyin.',
              ));
            return;
          }
  
          if (transactionResult.error === 'payment_failed') {
            response.send(buildAdRedirectHtml(
                `ad-payment-failed://${encodeURIComponent(transactionResult.message)}`,
                'Ödeme Başarısız',
                transactionResult.message,
              ));
            return;
          }
        }
  
        // Handle already processed
        if (transactionResult.alreadyProcessed) {
          console.log(`Ad payment ${oid} already processed: ${transactionResult.status}`);
  
          if (transactionResult.status === 'completed') {
            response.send(buildAdRedirectHtml(
                'ad-payment-success://',
                '✓ Ödeme Başarılı',
                'Reklamınız aktif edildi.',
              ));
            return;
          } else {
            response.send(buildAdRedirectHtml(
                `ad-payment-status://${transactionResult.status}`,
                'İşlem Zaten İşlendi',
                transactionResult.message,
              ));
            return;
          }
        }
  
        if (transactionResult.retry) {
          console.log(`[AdPayment] ${oid} already processing — client listener will handle completion`);
          response.send(buildAdRedirectHtml(
            'ad-payment-status://processing',
            'İşleminiz Devam Ediyor',
            'Ödemeniz işleniyor, lütfen bekleyin.',
          ));
          return;
        }
  
        // Activate ad
        try {
          const { pendingPayment } = transactionResult;
          const activeAdId = await activateAdAfterPayment(db, oid, pendingPayment);
        
          await pendingPaymentRef.update({
            status: 'completed',
            activeAdId,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            processingDuration: Date.now() - startTime,
            ...setAdPaymentExpiresAt('completed'),
          });
        
          await callbackLogRef.update({
            processingCompleted: admin.firestore.FieldValue.serverTimestamp(),
            activeAdId,
            success: true,
            processingDuration: Date.now() - startTime,
          });
        
          response.send(buildAdRedirectHtml('ad-payment-success://', '✓ Ödeme Başarılı', 'Reklamınız aktif edildi.'));
        } catch (activationError) {
          console.error('Ad activation failed after payment:', activationError);
        
          await pendingPaymentRef.update({
            status: 'payment_succeeded_activation_failed',
            activationError: activationError.message,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...setAdPaymentExpiresAt('payment_succeeded_activation_failed'),
          });
        
          await db.collection('_payment_alerts').doc(`ad_${oid}`).set({
            type: 'ad_activation_failed_after_payment',
            severity: 'high',
            paymentOrderId: oid,
            userId: transactionResult.pendingPayment?.userId,
            submissionId: transactionResult.pendingPayment?.submissionId,
            errorMessage: activationError.message,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        
          await callbackLogRef.update({
            processingFailed: admin.firestore.FieldValue.serverTimestamp(),
            error: activationError.message,
            success: false,
          });
        
          response.send(buildAdRedirectHtml(
            'ad-payment-failed://activation-error',
            'Ödeme alındı ancak reklam aktif edilemedi',
            `Lütfen destek ile iletişime geçin. Referans: ${oid}`,
          ));
        } 
      } catch (error) {
        console.error('Ad payment callback critical error:', error);
  
        try {
          await db.collection('ad_payment_callback_errors').add({
            oid: request.body?.oid || 'unknown',
            error: error.message,
            stack: error.stack,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            requestBody: request.body,
          });
        } catch (logError) {
          console.error('Failed to log error:', logError);
        }
  
        response.status(500).send('Internal server error');
      }
    },
  );
  
  // Check Ad Payment Status
  export const checkIsbankAdPaymentStatus = onCall(
    {
      region: 'europe-west3',
      memory: '128MB',
      timeoutSeconds: 10,
    },
    async (request) => {
      try {
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {orderNumber} = request.data;
  
        if (!orderNumber) {
          throw new HttpsError('invalid-argument', 'Order number is required');
        }
  
        const db = admin.firestore();
        const pendingPaymentSnap = await db
          .collection('pendingAdPayments')
          .doc(orderNumber)
          .get();
  
        if (!pendingPaymentSnap.exists) {
          throw new HttpsError('not-found', 'Payment not found');
        }
  
        const pendingPayment = pendingPaymentSnap.data();
  
        if (pendingPayment.userId !== request.auth.uid) {
          throw new HttpsError('permission-denied', 'Unauthorized');
        }
  
        return {
          orderNumber: orderNumber,
          status: pendingPayment.status,
          activeAdId: pendingPayment.activeAdId || null,
          errorMessage: pendingPayment.errorMessage || null,
        };
      } catch (error) {
        console.error('Check ad payment status error:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );
  
  export const processAdColorExtraction = onRequest(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 120, // 2 minutes - plenty of time for download + processing
      invoker: 'private', // Only Cloud Tasks can invoke this
    },
    async (request, response) => {
      const startTime = Date.now();
  
      try {
        const {adId, imageUrl, adType} = request.body;
  
        // Validate input
        if (!adId || !imageUrl || !adType) {
          console.error('❌ Missing required parameters:', {adId, imageUrl, adType});
          response.status(400).send('adId, imageUrl, and adType are required');
          return;
        }
  
        console.log(`🎨 Processing color extraction for ad: ${adId}`);
        console.log(`   Type: ${adType}`);
        console.log(`   URL: ${imageUrl}`);
  
        // Only process topBanner ads
        if (adType !== 'topBanner') {
          console.log(`⏭️ Skipping: Not a topBanner ad`);
          response.status(200).send('Not a topBanner ad, skipping');
          return;
        }
  
        const db = admin.firestore();
        const adCollectionName = getAdCollectionName(adType);
        const adRef = db.collection(adCollectionName).doc(adId);
  
        // Check if ad still exists and is active
        const adSnap = await adRef.get();
  if (!adSnap.exists) {
    console.warn(`⚠️ Ad ${adId} not found, may have been deleted`);
    response.status(404).send('Ad not found');
    return;
  }
  
  const adData = adSnap.data();
  
  // ✅ CRITICAL FIX: Skip if color already extracted (prevents duplicate processing)
  if (adData.dominantColor !== null && adData.dominantColor !== undefined) {
    console.log(`⏭️ Ad ${adId} already has dominant color (${adData.dominantColor}), skipping duplicate extraction`);
    response.status(200).send({
      success: true,
      message: 'Color already extracted',
      dominantColor: adData.dominantColor,
    });
    return;
  }
  
  // Skip if not active
  if (!adData.isActive) {
    console.warn(`⚠️ Ad ${adId} is no longer active, skipping color extraction`);
    response.status(200).send('Ad is not active, skipping');
    return;
  }
  
        // Extract dominant color
        console.log(`🔍 Extracting dominant color...`);
        const dominantColor = await extractDominantColorFromUrl(imageUrl);
  
        const processingTime = Date.now() - startTime;
        console.log(`⏱️ Color extraction completed in ${processingTime}ms`);
  
        // Update ad document with dominant color
        await adRef.update({
          dominantColor: dominantColor,
          colorExtractedAt: admin.firestore.FieldValue.serverTimestamp(),
          colorExtractionQueued: false,
          colorExtractionDuration: processingTime,
        });
  
        // Also update the submission document for consistency
        if (adData.submissionId) {
          await db
            .collection('ad_submissions')
            .doc(adData.submissionId)
            .update({
              dominantColor: dominantColor,
              colorExtractedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
  
        console.log(`✅ Dominant color saved successfully for ad ${adId}`);
        console.log(`   Color: 0x${dominantColor.toString(16).toUpperCase()}`);
        console.log(`   Total processing time: ${processingTime}ms`);
  
        response.status(200).send({
          success: true,
          adId: adId,
          dominantColor: dominantColor,
          processingTime: processingTime,
        });
      } catch (error) {
        console.error('❌ Critical error processing color extraction:', error);
        console.error('   Stack trace:', error.stack);
  
        // Log error to Firestore for debugging
        try {
          await admin.firestore().collection('ad_color_extraction_errors').add({
            adId: request.body?.adId || 'unknown',
            imageUrl: request.body?.imageUrl || 'unknown',
            error: error.message,
            stack: error.stack,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            processingTime: Date.now() - startTime,
          });
        } catch (logError) {
          console.error('❌ Failed to log error to Firestore:', logError);
        }
  
        response.status(500).send({
          success: false,
          error: error.message,
        });
      }
    },
  );
  
  // Process Ad Expiration (Cloud Task Handler)
  export const processAdExpiration = onRequest(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 30,
      invoker: 'private',
    },
    async (request, response) => {
      try {
        const {submissionId} = request.body;
  
        if (!submissionId) {
          response.status(400).send('submissionId is required');
          return;
        }
  
        const db = admin.firestore();
        const submissionRef = db.collection('ad_submissions').doc(submissionId);
        const submissionSnap = await submissionRef.get();
  
        if (!submissionSnap.exists) {
          console.log(`Submission ${submissionId} not found`);
          response.status(404).send('Submission not found');
          return;
        }
  
        // ✅ FIX: Get the data first
        const submissionData = submissionSnap.data();
  
        // Only expire if still active
        if (submissionData.status === 'active') {
          // Update submission status
          await submissionRef.update({
            status: 'expired',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          });
  
          // Deactivate the ad
          if (submissionData.activeAdId) {
            const adCollectionName = getAdCollectionName(submissionData.adType);
            await db
              .collection(adCollectionName)
              .doc(submissionData.activeAdId)
              .update({
                isActive: false,
                expiredAt: admin.firestore.FieldValue.serverTimestamp(),
              });
          }
  
          // ✅ FIX: Create submission object with ID
          const submission = {
            ...submissionData,
            id: submissionId,
          };
  
          // ✅ SEND NOTIFICATIONS TO SHOP MEMBERS
          await sendAdExpirationNotifications(db, submission);
  
          console.log(`✅ Ad ${submissionId} expired successfully`);
        } else {
          console.log(`Ad ${submissionId} is not active, skipping expiration`);
        }
  
        response.status(200).send('Ad expiration processed');
      } catch (error) {
        console.error('Error processing ad expiration:', error);
        response.status(500).send('Error processing ad expiration');
      }
    },
  );
  
  async function sendAdExpirationNotifications(db, submission) {
    try {
      const shopId = submission.shopId;
  
      if (!shopId) {
        console.log('No shopId in submission, skipping notification');
        return;
      }
  
      const adTypeLabel = getAdTypeLabel(submission.adType);
  
      await db.collection('shop_notifications').add({
        type: 'ad_expired',
        adType: submission.adType,
        adTypeLabel: adTypeLabel,
        shopId: shopId,
        shopName: submission.shopName,
        submissionId: submission.id,
        imageUrl: submission.imageUrl || null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: {},
      });
  
      console.log(`✅ Sent shop expiration notification for ad ${submission.id}`);
    } catch (error) {
      console.error('Error sending ad expiration notifications:', error);
    }
  }
  
  function getAdTypeLabel(adType) {
    switch (adType) {
    case 'topBanner':
      return 'Top Banner';
    case 'thinBanner':
      return 'Thin Banner';
    case 'marketBanner':
      return 'Market Banner';
    default:
      return 'Banner';
    }
  }
  
  // Daily cleanup of expired ads (Scheduled Function)
  export const cleanupExpiredAds = onSchedule(
    {
      schedule: 'every day 03:00',
      timeZone: 'Europe/Istanbul',
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 540,
    },
    async (event) => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
  
      try {
        // Find all active ads that have expired
        const expiredAdsQuery = db
          .collection('ad_submissions')
          .where('status', '==', 'active')
          .where('expiresAt', '<=', now);
  
        const expiredAdsSnap = await expiredAdsQuery.get();
  
        console.log(`Found ${expiredAdsSnap.size} expired ads to clean up`);
  
        let batch = db.batch();
        let batchCount = 0;
  
        for (const doc of expiredAdsSnap.docs) {
          const submission = doc.data();
  
          // Update submission status
          batch.update(doc.ref, {
            status: 'expired',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          });
  
          // Deactivate the ad
          if (submission.activeAdId) {
            const adCollectionName = getAdCollectionName(submission.adType);
            const adRef = db.collection(adCollectionName).doc(submission.activeAdId);
            batch.update(adRef, {
              isActive: false,
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
  
          batchCount++;
  
          // Firestore batch limit is 500
          if (batchCount >= 450) {
            await batch.commit();
            batch = db.batch(); // ← new batch after commit
            batchCount = 0;
          }
        }
  
        if (batchCount > 0) {
          await batch.commit();
        }
  
        // ✅ SEND NOTIFICATIONS FOR ALL EXPIRED ADS
        for (const doc of expiredAdsSnap.docs) {
          const submission = {
            ...doc.data(),
            id: doc.id,
          };
          await sendAdExpirationNotifications(db, submission);
        }
  
        console.log(`✅ Cleaned up ${expiredAdsSnap.size} expired ads`);
      } catch (error) {
        console.error('Error cleaning up expired ads:', error);
      }
    },
  );
  
  // Helper function to get collection name based on ad type
  function getAdCollectionName(adType) {
    switch (adType) {
    case 'topBanner':
      return 'market_top_ads_banners';
    case 'thinBanner':
      return 'market_thin_banners';
    case 'marketBanner':
      return 'market_banners';
    default:
      return 'market_banners';
    }
  }
  
  // ================================
  // AD ANALYTICS SYSTEM
  // ================================
  
  // Helper to calculate age from birthDate
  function calculateAge(birthDate) {
    if (!birthDate || !birthDate.toDate) return null;
  
    const birth = birthDate.toDate();
    const today = new Date();
    let age = today.getFullYear() - birth.getFullYear();
    const monthDiff = today.getMonth() - birth.getMonth();
  
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
      age--;
    }
  
    return age;
  }
  
  // Helper to get age group
  function getAgeGroup(age) {
    if (!age || age < 0) return 'Unknown';
    if (age < 18) return 'Under 18';
    if (age < 25) return '18-24';
    if (age < 35) return '25-34';
    if (age < 45) return '35-44';
    if (age < 55) return '45-54';
    if (age < 65) return '55-64';
    return '65+';
  }
  
  // Helper to create analytics task (non-blocking)
  async function createAnalyticsTask(analyticsData) {
    const project = 'emlak-mobile-app';
    const location = 'europe-west3';
    const queue = 'ad-analytics';
  
    try {
      const parent = tasksClient.queuePath(project, location, queue);
  
      const task = {
        httpRequest: {
          httpMethod: 'POST',
          url: `https://${location}-${project}.cloudfunctions.net/processAdAnalytics`,
          body: Buffer.from(JSON.stringify(analyticsData)).toString('base64'),
          headers: {'Content-Type': 'application/json'},
          oidcToken: {
            serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
          },
        },
      };
  
      await tasksClient.createTask({parent, task});
      console.log(`✅ Analytics task queued for ad ${analyticsData.adId}`);
    } catch (error) {
      console.error('Error creating analytics task:', error);
      // Don't throw - analytics are non-critical
    }
  }
  
  // Track Ad Click (Called from Flutter)
  export const trackAdClick = onCall(
    {
      region: 'europe-west3',
      memory: '128MB',
      timeoutSeconds: 10,
    },
    async (request) => {
      try {
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {adId, adType, linkedType, linkedId} = request.data;
  
        if (!adId || !adType) {
          throw new HttpsError('invalid-argument', 'adId and adType are required');
        }
  
        const db = admin.firestore();
        const userId = request.auth.uid;
  
        // Get user data for demographics
        const userSnap = await db.collection('users').doc(userId).get();
        const userData = userSnap.data() || {};
  
        const age = calculateAge(userData.birthDate);
        const ageGroup = getAgeGroup(age);
        const gender = userData.gender || 'Not specified';
  
        // Queue analytics processing (non-blocking)
        await createAnalyticsTask({
          adId,
          adType,
          userId,
          gender,
          age,
          ageGroup,
          linkedType: linkedType || null,
          linkedId: linkedId || null,
          timestamp: Date.now(),
          eventType: 'click',
        });
  
        return {
          success: true,
          tracked: true,
        };
      } catch (error) {
        console.error('Error tracking ad click:', error);
        // Don't fail the user experience
        return {
          success: false,
          tracked: false,
          error: error.message,
        };
      }
    },
  );
  
  // Process Ad Analytics (Cloud Task Handler)
  export const processAdAnalytics = onRequest(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 60,
      invoker: 'private',
    },
    async (request, response) => {
      try {
        const {
          adId,
          adType,
          userId,
          gender,
          age,
          ageGroup,
          linkedType,
          linkedId,
          timestamp,
        } = request.body;
  
        if (!adId || !userId) {
          response.status(400).send('adId and userId are required');
          return;
        }
  
        const db = admin.firestore();
        const clickTimestamp = admin.firestore.Timestamp.fromMillis(timestamp);
  
        // Get the ad collection name
        const adCollectionName = getAdCollectionName(adType);
        const adRef = db.collection(adCollectionName).doc(adId);
  
        // Use batched write for efficiency
        const batch = db.batch();
  
        // 1. Update ad document with aggregated metrics
        batch.update(adRef, {
          totalClicks: admin.firestore.FieldValue.increment(1),
          [`demographics.gender.${gender}`]: admin.firestore.FieldValue.increment(1),
          [`demographics.ageGroups.${ageGroup}`]: admin.firestore.FieldValue.increment(1),
          lastClickedAt: admin.firestore.FieldValue.serverTimestamp(),
          metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        // 2. Store individual click record for detailed analytics
        const clickRecordRef = db
          .collection(adCollectionName)
          .doc(adId)
          .collection('clicks')
          .doc();
  
        batch.set(clickRecordRef, {
          userId,
          gender,
          age: age || null,
          ageGroup,
          linkedType,
          linkedId,
          clickedAt: clickTimestamp,
          converted: false, // Will be updated if user makes purchase
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        // 3. Create user click record (for conversion tracking)
        const userClickRef = db
          .collection('users')
          .doc(userId)
          .collection('ad_clicks')
          .doc();
  
        batch.set(userClickRef, {
          adId,
          adType,
          linkedType,
          linkedId,
          clickedAt: clickTimestamp,
          converted: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        await batch.commit();
  
        console.log(`✅ Analytics processed for ad ${adId}, user ${userId}`);
        response.status(200).send('Analytics processed');
      } catch (error) {
        console.error('Error processing ad analytics:', error);
        response.status(500).send('Error processing analytics');
      }
    },
  );
  
  // Track Ad Conversion (Called when order is created)
  export const trackAdConversion = onCall(
    {
      region: 'europe-west3',
      memory: '256MB',
      timeoutSeconds: 30,
    },
    async (request) => {
      try {
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {orderId, productIds, shopIds} = request.data;
  
        if (!orderId || !productIds || !Array.isArray(productIds)) {
          throw new HttpsError('invalid-argument', 'orderId and productIds array are required');
        }
  
        const db = admin.firestore();
        const userId = request.auth.uid;
  
        // Get user's recent ad clicks (last 30 days)
        const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
          Date.now() - 30 * 24 * 60 * 60 * 1000,
        );
  
        const userClicksSnap = await db
          .collection('users')
          .doc(userId)
          .collection('ad_clicks')
          .where('clickedAt', '>=', thirtyDaysAgo)
          .where('converted', '==', false)
          .get();
  
        if (userClicksSnap.empty) {
          return {success: true, conversions: 0};
        }
  
        const batch = db.batch();
        let conversionsCount = 0;
  
        // Check each click to see if it led to a conversion
        for (const clickDoc of userClicksSnap.docs) {
          const clickData = clickDoc.data();
  
          // Check if the linked product/shop matches the purchase
          let isConversion = false;
  
          if (clickData.linkedType === 'product' && productIds.includes(clickData.linkedId)) {
            isConversion = true;
          } else if (clickData.linkedType === 'shop' && shopIds && shopIds.includes(clickData.linkedId)) {
            isConversion = true;
          }
  
          if (isConversion) {
            conversionsCount++;
  
            // Update user's click record
            batch.update(clickDoc.ref, {
              converted: true,
              convertedAt: admin.firestore.FieldValue.serverTimestamp(),
              orderId: orderId,
            });
  
            // Update the ad's aggregated metrics
            const adCollectionName = getAdCollectionName(clickData.adType);
            const adRef = db.collection(adCollectionName).doc(clickData.adId);
  
            batch.update(adRef, {
              totalConversions: admin.firestore.FieldValue.increment(1),
              lastConvertedAt: admin.firestore.FieldValue.serverTimestamp(),
              metricsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
  
            // Update the specific click record
            const clickRecordsSnap = await db
              .collection(adCollectionName)
              .doc(clickData.adId)
              .collection('clicks')
              .where('userId', '==', userId)
              .where('clickedAt', '==', clickData.clickedAt)
              .limit(1)
              .get();
  
            if (!clickRecordsSnap.empty) {
              batch.update(clickRecordsSnap.docs[0].ref, {
                converted: true,
                convertedAt: admin.firestore.FieldValue.serverTimestamp(),
                orderId: orderId,
              });
            }
          }
        }
  
        await batch.commit();
  
        console.log(`✅ Tracked ${conversionsCount} conversions for order ${orderId}`);
        return {success: true, conversions: conversionsCount};
      } catch (error) {
        console.error('Error tracking ad conversion:', error);
        throw new HttpsError('internal', error.message);
      }
    },
  );
  
  // Batch Analytics Snapshot (Daily scheduled function)
  export const createDailyAdAnalyticsSnapshot = onSchedule(
    {
      schedule: 'every day 02:00',
      timeZone: 'Europe/Istanbul',
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 540,
    },
    async (event) => {
      const db = admin.firestore();
      const today = new Date();
      const snapshotDate = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  
      try {
        console.log('Creating daily analytics snapshots...');
  
        const adCollections = ['market_top_ads_banners', 'market_thin_banners', 'market_banners'];
        let totalSnapshots = 0;
  
        for (const collectionName of adCollections) {
          // Get all active ads
          const adsSnap = await db
            .collection(collectionName)
            .where('isActive', '==', true)
            .get();
  
            let batch = db.batch();
            let batchCount = 0;
  
          for (const adDoc of adsSnap.docs) {
            const adData = adDoc.data();
  
            // Create daily snapshot
            const snapshotRef = db
              .collection(collectionName)
              .doc(adDoc.id)
              .collection('daily_snapshots')
              .doc(snapshotDate.toISOString().split('T')[0]);
  
            batch.set(snapshotRef, {
              date: admin.firestore.Timestamp.fromDate(snapshotDate),
              totalClicks: adData.totalClicks || 0,
              totalConversions: adData.totalConversions || 0,
              conversionRate: adData.totalClicks > 0 ? ((adData.totalConversions || 0) / adData.totalClicks) * 100 : 0,
              demographics: adData.demographics || {gender: {}, ageGroups: {}},
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
  
            batchCount++;
            totalSnapshots++;
  
            // Firestore batch limit is 500
            if (batchCount >= 450) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
              }
          }
  
          if (batchCount > 0) {
            await batch.commit();
          }
        }
  
        console.log(`✅ Created ${totalSnapshots} daily analytics snapshots`);
      } catch (error) {
        console.error('Error creating daily analytics snapshots:', error);
      }
    },
  );

  export const recoverStuckAdPayments = onSchedule(
    { schedule: '*/5 * * * *', region: 'europe-west3', memory: '256MiB', timeoutSeconds: 300 },
    async () => {
      const db = admin.firestore();
      const fiveMinutesAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);
  
      const stuckSnap = await db.collection('pendingAdPayments')
        .where('status', 'in', ['processing', 'payment_verified_activating_ad'])
        .where('processingStartedAt', '<=', fiveMinutesAgo)
        .limit(50)
        .get();
  
      if (stuckSnap.empty) return;
  
      console.warn(`[AdRecovery] Found ${stuckSnap.docs.length} stuck ad payment(s)`);
  
      const results = { recovered: 0, skipped: 0, failed: 0 };
  
      for (let i = 0; i < stuckSnap.docs.length; i += 3) {
        const chunk = stuckSnap.docs.slice(i, i + 3);
  
        const settled = await Promise.allSettled(chunk.map(async (doc) => {
          const oid = doc.id;
          const p   = doc.data();
  
          if ((p.recoveryAttemptCount || 0) >= 5) {
            console.error(`[AdRecovery] ${oid} exceeded max attempts, giving up`);
            await doc.ref.update({
              status: 'payment_succeeded_activation_failed',
              activationError: 'Max recovery attempts exceeded',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              ...setAdPaymentExpiresAt('payment_succeeded_activation_failed'),
            });
            await db.collection('_payment_alerts').add({
              type: 'ad_recovery_max_attempts', severity: 'high',
              orderNumber: oid, userId: p.userId,
              message: `Ad payment ${oid} exceeded max recovery attempts`,
              isRead: false, isResolved: false,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            }).catch(() => {});
            return 'skipped';
          }
  
          // Atomic claim
          const claimed = await db.runTransaction(async (tx) => {
            const fresh = (await tx.get(doc.ref)).data();
            if (!['processing', 'payment_verified_activating_ad'].includes(fresh.status)) return false;
            tx.update(doc.ref, {
              status: 'payment_verified_activating_ad',
              recoveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
              recoveryAttemptCount: admin.firestore.FieldValue.increment(1),
            });
            return true;
          });
  
          if (!claimed) return 'skipped';
  
          const activeAdId = await activateAdAfterPayment(db, oid, p);
  
          await doc.ref.update({
            status: 'completed',
            activeAdId,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            recoveredBy: 'ad_recovery_scheduler',
            ...setAdPaymentExpiresAt('completed'),
          });
  
          await db.collection('_payment_alerts').add({
            type: 'ad_payment_recovered', severity: 'medium',
            orderNumber: oid, userId: p.userId, activeAdId,
            message: `Recovery scheduler fixed stuck ad payment: ${oid}`,
            isRead: false, isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          }).catch(() => {});
  
          console.log(`[AdRecovery] ✅ Recovered ${oid} → ad ${activeAdId}`);
          return 'recovered';
        }));
  
        settled.forEach((result, idx) => {
          if (result.status === 'fulfilled') {
            result.value === 'recovered' ? results.recovered++ : results.skipped++;
          } else {
            results.failed++;
            const oid  = chunk[idx].id;
            const p    = chunk[idx].data();
            console.error(`[AdRecovery] Failed to recover ${oid}:`, result.reason?.message);
  
            db.runTransaction(async (tx) => {
              const fresh = (await tx.get(chunk[idx].ref)).data();
              if (fresh.status === 'payment_verified_activating_ad') {
                tx.update(chunk[idx].ref, {
                  status: 'payment_succeeded_activation_failed',
                  activationError: result.reason?.message || 'Recovery failed',
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  ...setAdPaymentExpiresAt('payment_succeeded_activation_failed'),
                });
              }
            }).catch(console.error);
  
            db.collection('_payment_alerts').add({
              type: 'ad_recovery_failed', severity: 'high',
              orderNumber: oid, userId: p.userId,
              errorMessage: result.reason?.message || 'Unknown error',
              isRead: false, isResolved: false,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
            }).catch(() => {});
          }
        });
      }
  
      console.log(`[AdRecovery] Done — ${results.recovered} recovered, ${results.skipped} skipped, ${results.failed} failed`);
    },
  );
