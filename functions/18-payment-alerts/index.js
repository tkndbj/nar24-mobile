// functions/18-payment-alerts/index.js
//
// Payment Observability Layer
//
// Two functions:
//   1. alertOnPaymentIssue      — Firestore trigger, fires instantly on status change
//   2. detectPaymentAnomalies   — Scheduled every 10 min, catches time-based issues
//
// Writes to:
//   - _payment_alerts collection (for admin dashboard)
//   - FCM topic "admin_alerts" (push notification to admin devices)
//
// Does NOT modify any existing payment/order logic.

import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import admin from 'firebase-admin';
import { getMessaging } from 'firebase-admin/messaging';

// ════════════════════════════════════════════════════════════════════════════
// CONFIG
// ════════════════════════════════════════════════════════════════════════════

const REGION = 'europe-west3';
const ALERTS_COLLECTION = '_payment_alerts';
const FCM_TOPIC = 'admin_alerts';

// Statuses that trigger an INSTANT alert when a pendingPayment transitions to them
const ALERT_STATUSES = {
  payment_succeeded_order_failed: {
    severity: 'critical',
    title: '🚨 KRİTİK: Ödeme alındı, sipariş oluşturulamadı',
    description: 'Müşteriden ödeme alındı ancak sipariş oluşturulamadı. Acil müdahale gerekiyor.',
  },
  hash_verification_failed: {
    severity: 'high',
    title: '⚠️ Hash doğrulama hatası',
    description: 'Ödeme callback hash doğrulaması başarısız. Olası güvenlik sorunu.',
  },
};

// Time thresholds for scheduled anomaly detection
const STUCK_PROCESSING_THRESHOLD_MS = 5 * 60 * 1000;      // 5 minutes
const EXPIRED_3D_THRESHOLD_MS = 15 * 60 * 1000;            // 15 minutes
const COMPLETED_NO_ORDER_CHECK_WINDOW_MS = 30 * 60 * 1000; // 30 minutes

// ════════════════════════════════════════════════════════════════════════════
// 1. INSTANT ALERT — Firestore trigger on pendingPayments
// ════════════════════════════════════════════════════════════════════════════

export const alertOnPaymentIssue = onDocumentWritten(
  {
    document: 'pendingPayments/{orderNumber}',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    maxInstances: 50,
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // Document deleted — ignore
    if (!after) return;

    const newStatus = after.status;
    const oldStatus = before?.status;

    // Only alert on STATUS TRANSITIONS (not on initial creates that are normal)
    // If status didn't change, or it's not an alertable status, skip
    if (newStatus === oldStatus) return;
    if (!ALERT_STATUSES[newStatus]) return;

    const orderNumber = event.params.orderNumber;
    const alertConfig = ALERT_STATUSES[newStatus];

    console.log(`🚨 [ALERT] ${alertConfig.severity.toUpperCase()}: ${orderNumber} → ${newStatus}`);

    const db = admin.firestore();

    // ── Idempotency: use deterministic doc ID ──
    // If this function retries, it overwrites the same doc instead of creating duplicates
    const alertId = `${orderNumber}_${newStatus}`;
    const alertRef = db.collection(ALERTS_COLLECTION).doc(alertId);

    try {
      // Check if alert already exists (fast path to avoid unnecessary writes)
      const existing = await alertRef.get();
      if (existing.exists) {
        console.log(`ℹ️ Alert already exists for ${alertId}, skipping`);
        return;
      }
    } catch (e) {
      // If read fails, continue anyway — the set() below is idempotent via doc ID
      console.warn(`⚠️ Alert existence check failed: ${e.message}`);
    }

    // ── Build alert document ──
    const customerInfo = after.customerInfo || {};
    const cartData = after.cartData || {};
    const serverCalc = after.serverCalculation || {};

    const alertDoc = {
      // Identity
      type: newStatus,
      severity: alertConfig.severity,
      orderNumber,
      pendingPaymentId: orderNumber,

      // Buyer
      userId: after.userId || '',
      buyerName: customerInfo.name || '',
      buyerEmail: customerInfo.email || '',
      buyerPhone: customerInfo.phone || '',

      // Financial
      amount: after.amount || 0,
      clientAmount: after.clientAmount || null,
      serverCalculation: serverCalc.finalTotal ? {
        itemsSubtotal: serverCalc.itemsSubtotal || 0,
        couponDiscount: serverCalc.couponDiscount || 0,
        deliveryPrice: serverCalc.deliveryPrice || 0,
        finalTotal: serverCalc.finalTotal || 0,
      } : null,

      // Items summary (lightweight — full details are in pendingPayments)
      itemCount: Array.isArray(cartData.items) ? cartData.items.length : 0,
      itemsSummary: Array.isArray(cartData.items) ? cartData.items.slice(0, 5).map((item) => ({
            productId: item.productId,
            productName: item.productName || null,
            quantity: item.quantity || 1,
            selectedColor: item.selectedColor || null,
          })) : [],

      // Error context
      errorMessage: after.orderError || after.errorMessage || null,
      previousStatus: oldStatus || null,

      // Metadata
      isRead: false,
      isResolved: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      paymentCreatedAt: after.createdAt || null,
    };

    // ── Write alert ──
    try {
      await alertRef.set(alertDoc);
      console.log(`✅ Alert written: ${alertId}`);
    } catch (e) {
      console.error(`❌ Failed to write alert ${alertId}:`, e);
      // Don't throw — we still want to try sending the push notification
    }

    // ── Send FCM push notification to admin topic ──
    try {
      const message = {
        topic: FCM_TOPIC,
        notification: {
          title: alertConfig.title,
          body: `${customerInfo.name || 'Müşteri'} — ${(after.amount || 0).toFixed(2)} TL — ${orderNumber}`,
        },
        data: {
          type: 'payment_alert',
          alertId,
          orderNumber,
          severity: alertConfig.severity,
          status: newStatus,
          amount: String(after.amount || 0),
          click_action: 'OPEN_PAYMENT_ISSUES',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'payment_alerts',
            priority: 'max',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
                'sound': 'default',
                'badge': 1,
                'content-available': 1,
              },
          },
          headers: {
            'apns-priority': '10',
          },
        },
      };

      await getMessaging().send(message);
      console.log(`📱 Push notification sent to topic: ${FCM_TOPIC}`);
    } catch (e) {
      // FCM failure should never block the alert write
      // Common reason: no devices subscribed to topic yet — that's fine
      console.warn(`⚠️ FCM send failed (non-critical): ${e.message}`);
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// 2. SCHEDULED ANOMALY DETECTION — Runs every 10 minutes
// ════════════════════════════════════════════════════════════════════════════

export const detectPaymentAnomalies = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 60,
    retryCount: 1,
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const alerts = [];

    console.log('🔍 [SCHEDULER] Running payment anomaly detection...');

    // ── Check 1: Stuck in "processing" (>5 min) ──
    try {
      const stuckCutoff = new Date(now - STUCK_PROCESSING_THRESHOLD_MS);
      const stuckSnap = await db.collection('pendingPayments')
        .where('status', '==', 'processing')
        .where('createdAt', '<', stuckCutoff)
        .limit(50)
        .get();

      for (const doc of stuckSnap.docs) {
        const data = doc.data();
        const alertId = `${doc.id}_stuck_processing`;

        // Dedup: skip if alert already exists
        const existingAlert = await db.collection(ALERTS_COLLECTION).doc(alertId).get();
        if (existingAlert.exists) continue;

        const age = Math.round((now - data.createdAt?.toMillis()) / 60000);

        alerts.push({
          alertId,
          doc: {
            type: 'stuck_processing',
            severity: 'high',
            orderNumber: doc.id,
            pendingPaymentId: doc.id,
            userId: data.userId || '',
            buyerName: data.customerInfo?.name || '',
            buyerEmail: data.customerInfo?.email || '',
            buyerPhone: data.customerInfo?.phone || '',
            amount: data.amount || 0,
            itemCount: Array.isArray(data.cartData?.items) ? data.cartData.items.length : 0,
            errorMessage: `Ödeme ${age} dakikadır "processing" durumunda takılı.`,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            paymentCreatedAt: data.createdAt || null,
            detectedBy: 'scheduler',
          },
        });
      }

      if (stuckSnap.size > 0) {
        console.log(`⚠️ Found ${stuckSnap.size} stuck processing payments`);
      }
    } catch (e) {
      console.error('❌ Error checking stuck processing:', e);
    }

    // ── Check 2: Expired 3D Secure sessions (>15 min) ──
    try {
      const expiredCutoff = new Date(now - EXPIRED_3D_THRESHOLD_MS);
      const expiredSnap = await db.collection('pendingPayments')
        .where('status', '==', 'awaiting_3d')
        .where('createdAt', '<', expiredCutoff)
        .limit(100)
        .get();

      for (const doc of expiredSnap.docs) {
        const data = doc.data();
        const alertId = `${doc.id}_expired_3d`;

        const existingAlert = await db.collection(ALERTS_COLLECTION).doc(alertId).get();
        if (existingAlert.exists) continue;

        const age = Math.round((now - data.createdAt?.toMillis()) / 60000);

        alerts.push({
          alertId,
          doc: {
            type: 'expired_3d_secure',
            severity: 'low',
            orderNumber: doc.id,
            pendingPaymentId: doc.id,
            userId: data.userId || '',
            buyerName: data.customerInfo?.name || '',
            buyerEmail: data.customerInfo?.email || '',
            buyerPhone: data.customerInfo?.phone || '',
            amount: data.amount || 0,
            itemCount: Array.isArray(data.cartData?.items) ? data.cartData.items.length : 0,
            errorMessage: `3D Secure oturumu ${age} dakikadır tamamlanmadı. Kullanıcı işlemi terk etmiş olabilir.`,
            isRead: false,
            isResolved: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            paymentCreatedAt: data.createdAt || null,
            detectedBy: 'scheduler',
          },
        });
      }

      if (expiredSnap.size > 0) {
        console.log(`ℹ️ Found ${expiredSnap.size} expired 3D Secure sessions`);
      }
    } catch (e) {
      console.error('❌ Error checking expired 3D:', e);
    }

    // ── Check 3: Completed payments with no matching order ──
    try {
      const recentCutoff = new Date(now - COMPLETED_NO_ORDER_CHECK_WINDOW_MS);
      const completedSnap = await db.collection('pendingPayments')
        .where('status', '==', 'completed')
        .where('createdAt', '>', recentCutoff)
        .limit(100)
        .get();

      for (const docSnap of completedSnap.docs) {
        const data = docSnap.data();
        const orderId = data.orderId;

        if (!orderId) {
          // Completed but no orderId stored — something wrong
          const alertId = `${docSnap.id}_completed_no_orderid`;
          const existingAlert = await db.collection(ALERTS_COLLECTION).doc(alertId).get();
          if (existingAlert.exists) continue;

          alerts.push({
            alertId,
            doc: {
              type: 'completed_no_order_id',
              severity: 'critical',
              orderNumber: docSnap.id,
              pendingPaymentId: docSnap.id,
              userId: data.userId || '',
              buyerName: data.customerInfo?.name || '',
              buyerEmail: data.customerInfo?.email || '',
              buyerPhone: data.customerInfo?.phone || '',
              amount: data.amount || 0,
              itemCount: Array.isArray(data.cartData?.items) ? data.cartData.items.length : 0,
              errorMessage: 'Ödeme "completed" durumunda ancak orderId kaydedilmemiş.',
              isRead: false,
              isResolved: false,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              paymentCreatedAt: data.createdAt || null,
              detectedBy: 'scheduler',
            },
          });
          continue;
        }

        // Verify order actually exists
        const orderSnap = await db.collection('orders').doc(orderId).get();
        if (!orderSnap.exists) {
          const alertId = `${docSnap.id}_missing_order`;
          const existingAlert = await db.collection(ALERTS_COLLECTION).doc(alertId).get();
          if (existingAlert.exists) continue;

          alerts.push({
            alertId,
            doc: {
              type: 'missing_order',
              severity: 'critical',
              orderNumber: docSnap.id,
              pendingPaymentId: docSnap.id,
              userId: data.userId || '',
              buyerName: data.customerInfo?.name || '',
              buyerEmail: data.customerInfo?.email || '',
              buyerPhone: data.customerInfo?.phone || '',
              amount: data.amount || 0,
              expectedOrderId: orderId,
              itemCount: Array.isArray(data.cartData?.items) ? data.cartData.items.length : 0,
              errorMessage: `Ödeme tamamlandı ancak sipariş (${orderId}) veritabanında bulunamadı.`,
              isRead: false,
              isResolved: false,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              paymentCreatedAt: data.createdAt || null,
              detectedBy: 'scheduler',
            },
          });
        }
      }
    } catch (e) {
      console.error('❌ Error checking completed payments:', e);
    }

    // ── Write all alerts in batch ──
    if (alerts.length > 0) {
      const BATCH_SIZE = 500;

      for (let i = 0; i < alerts.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = alerts.slice(i, i + BATCH_SIZE);

        for (const alert of chunk) {
          const ref = db.collection(ALERTS_COLLECTION).doc(alert.alertId);
          batch.set(ref, alert.doc);
        }

        try {
          await batch.commit();
          console.log(`✅ Batch wrote ${chunk.length} alerts`);
        } catch (e) {
          console.error(`❌ Failed to write alert batch:`, e);
        }
      }

      // ── Send ONE summary push for all scheduler-detected issues ──
      const criticalCount = alerts.filter((a) => a.doc.severity === 'critical').length;
      const highCount = alerts.filter((a) => a.doc.severity === 'high').length;

      if (criticalCount > 0 || highCount > 0) {
        try {
          const title = criticalCount > 0 ? `🚨 ${criticalCount} kritik ödeme sorunu tespit edildi` : `⚠️ ${highCount} ödeme sorunu tespit edildi`;

          const totalAmount = alerts
            .filter((a) => a.doc.severity === 'critical' || a.doc.severity === 'high')
            .reduce((sum, a) => sum + (a.doc.amount || 0), 0);

          await getMessaging().send({
            topic: FCM_TOPIC,
            notification: {
              title,
              body: `Toplam risk: ${totalAmount.toFixed(2)} TL. Detaylar için Ödeme Sorunları sayfasını kontrol edin.`,
            },
            data: {
              type: 'payment_anomaly_scan',
              alertCount: String(alerts.length),
              criticalCount: String(criticalCount),
              click_action: 'OPEN_PAYMENT_ISSUES',
            },
            android: {
              priority: 'high',
              notification: {
                channelId: 'payment_alerts',
                sound: 'default',
              },
            },
            apns: {
              payload: {
                aps: {
                    'sound': 'default',
                    'badge': criticalCount + highCount,
                  },
              },
            },
          });
          console.log(`📱 Summary push sent: ${criticalCount} critical, ${highCount} high`);
        } catch (e) {
          console.warn(`⚠️ Summary FCM failed: ${e.message}`);
        }
      }

      console.log(`🔍 [SCHEDULER] Done. ${alerts.length} new alerts created.`);
    } else {
      console.log('✅ [SCHEDULER] No anomalies detected.');
    }
  },
);
