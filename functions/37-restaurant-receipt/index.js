/* eslint-disable valid-jsdoc */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';
import path from 'path';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REGION = 'europe-west3';

// ─── Receipt layout constants (80 mm thermal receipt) ───────────────────────
const W  = 227;   // page width  ≈ 80 mm in points (1 mm = 2.8346 pt)
const M  = 13;    // left / right margin
const CW = W - M * 2; // usable content width = 201 pt

// ============================================================================
// EXPORT: Schedule restaurant receipt task (call from createFoodOrderCore)
// ============================================================================

export async function scheduleRestaurantReceiptTask(orderDoc, orderId) {
  const db = admin.firestore();

  await db.collection('restaurantReceiptTasks').doc(orderId).set({
    // Identity
    orderId,

    // Restaurant
    restaurantId: orderDoc.restaurantId,
    restaurantName: orderDoc.restaurantName    || '',
    restaurantOwnerId: orderDoc.restaurantOwnerId || '',
    restaurantPhone: orderDoc.restaurantPhone   || '',

    // Buyer
    buyerName: orderDoc.buyerName  || '',
    buyerPhone: orderDoc.buyerPhone || '',

    // Order content
    items: orderDoc.items            || [],
    subtotal: orderDoc.subtotal         || 0,
    deliveryFee: orderDoc.deliveryFee      || 0,
    totalPrice: orderDoc.totalPrice       || 0,
    currency: orderDoc.currency         || 'TL',

    // Payment
    paymentMethod: orderDoc.paymentMethod || '',
    isPaid: orderDoc.isPaid        || false,

    // Delivery
    deliveryType: orderDoc.deliveryType     || 'delivery',
    deliveryAddress: orderDoc.deliveryAddress  || null,
    orderNotes: orderDoc.orderNotes       || '',
    estimatedPrepTime: orderDoc.estimatedPrepTime || 0,

    // Task meta
    orderDate: admin.firestore.FieldValue.serverTimestamp(),
    status: 'pending',
    retryCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    deleteAt: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
  });
}

// ============================================================================
// CLOUD FUNCTION: generateRestaurantReceiptBackground
// ============================================================================

export const generateRestaurantReceiptBackground = onDocumentCreated(
  {
    document: 'restaurantReceiptTasks/{taskId}',
    region: REGION,
    memory: '1GiB',
    timeoutSeconds: 120,
  },
  async (event) => {
    const taskData = event.data.data();
    const taskId   = event.params.taskId;
    const db       = admin.firestore();

    try {
      // Firestore Timestamp → JS Date
      const orderDate =
        taskData.orderDate?.toDate ? taskData.orderDate.toDate() : new Date();

      // ── 1. Generate PDF buffer ──────────────────────────────────
      const receiptPdf = await generateRestaurantReceipt({ ...taskData, orderDate });

      // ── 2. Save to Cloud Storage ────────────────────────────────
      const bucket          = admin.storage().bucket();
      const receiptFileName = `restaurant-receipts/${taskData.restaurantId}/${taskData.orderId}.pdf`;
      const file            = bucket.file(receiptFileName);
      const downloadToken   = uuidv4();

      await file.save(receiptPdf, {
        metadata: {
          contentType: 'application/pdf',
          metadata: { firebaseStorageDownloadTokens: downloadToken },
        },
      });

      const downloadUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
        `${encodeURIComponent(receiptFileName)}?alt=media&token=${downloadToken}`;

      // ── 3. Write receipt reference to restaurant subcollection ──
      await db
        .collection('restaurants')
        .doc(taskData.restaurantId)
        .collection('orderReceipts')
        .doc(taskData.orderId)
        .set({
          receiptId: taskData.orderId,
          receiptType: 'restaurant_order_receipt',
          orderId: taskData.orderId,
          restaurantId: taskData.restaurantId,
          restaurantName: taskData.restaurantName || '',
          buyerName: taskData.buyerName      || '',
          totalPrice: taskData.totalPrice,
          currency: taskData.currency       || 'TL',
          paymentMethod: taskData.paymentMethod,
          isPaid: taskData.isPaid         || false,
          deliveryType: taskData.deliveryType,
          filePath: receiptFileName,
          downloadUrl,
          orderDate: taskData.orderDate,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

      // ── 4. Mark task complete ───────────────────────────────────
      await db.collection('restaurantReceiptTasks').doc(taskId).update({
        status: 'completed',
        filePath: receiptFileName,
        downloadUrl,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[RestaurantReceipt] OK — order ${taskData.orderId}`);
    } catch (error) {
      console.error('[RestaurantReceipt] Error:', error);

      const taskRef  = db.collection('restaurantReceiptTasks').doc(taskId);
      const taskSnap = await taskRef.get();
      const retryCount = (taskSnap.data()?.retryCount || 0) + 1;

      await taskRef.update({
        status: retryCount >= 3 ? 'failed' : 'pending',
        retryCount,
        lastError: error.message,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (retryCount >= 3) {
        await db.collection('_payment_alerts').add({
          type: 'restaurant_receipt_generation_failed',
          severity: 'medium',
          orderId: taskData.orderId,
          restaurantId: taskData.restaurantId,
          errorMessage: error.message,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (retryCount < 3) throw error;
    }
  },
);

// ============================================================================
// PDF GENERATOR — two-pass: measure first, then render at exact height
// ============================================================================

async function generateRestaurantReceipt(data) {
  // ── QR code (generated once, shared between both passes) ─────────────────
  let qrImageBuffer = null;

  if (data.deliveryType !== 'pickup') {
    try {
      const addr = data.deliveryAddress;
      let qrPayload = '';

      if (addr?.location?.latitude != null && addr?.location?.longitude != null) {
        qrPayload =
          `https://maps.google.com/?q=${addr.location.latitude},${addr.location.longitude}`;
      } else if (addr?.addressLine1) {
        const parts = [
          addr.addressLine1,
          addr.addressLine2,
          addr.city,
          addr.mainRegion,
        ].filter(Boolean).join(', ');
        qrPayload = `https://maps.google.com/?q=${encodeURIComponent(parts)}`;
      }

      if (qrPayload) {
        qrImageBuffer = await QRCode.toBuffer(qrPayload, {
          type: 'png',
          width: 200,
          margin: 1,
          errorCorrectionLevel: 'M',
          color: { dark: '#000000', light: '#FFFFFF' },
        });
      }
    } catch (qrErr) {
      console.warn('[RestaurantReceipt] QR generation skipped:', qrErr.message);
    }
  }

  // ── Pass 1: dry-run on a tall dummy page to measure real content height ───
  const measuredY = await measureReceiptHeight(data, qrImageBuffer);

  // ── Pass 2: render at the exact correct height ────────────────────────────
  const exactHeight = measuredY + M + 6; // content bottom + bottom margin + small padding
  return renderReceiptToPdf(data, qrImageBuffer, exactHeight);
}

// ── Pass 1: discard output, just return final y ───────────────────────────

function measureReceiptHeight(data, qrImageBuffer) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: [W, 4000],   // tall enough for any receipt
      margins: { top: M, bottom: M, left: M, right: M },
      compress: false,
      bufferPages: false,
    });

    // Drain output silently — we only care about the returned y
    doc.on('data',  () => {});
    doc.on('error', reject);

    const finalY = renderReceiptContent(doc, data, qrImageBuffer);

    doc.on('end', () => resolve(finalY));
    doc.end();
  });
}

// ── Pass 2: real PDF with exact page height ───────────────────────────────

function renderReceiptToPdf(data, qrImageBuffer, pageHeight) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: [W, pageHeight],
      margins: { top: M, bottom: M, left: M, right: M },
      compress: true,
      bufferPages: false,
    });

    const chunks = [];
    doc.on('data',  (c) => chunks.push(c));
    doc.on('end',   ()  => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    renderReceiptContent(doc, data, qrImageBuffer);
    doc.end();
  });
}

// ── Shared drawing logic — called in both passes ──────────────────────────
// Returns the final y position so the caller knows the true content height.

function renderReceiptContent(doc, data, qrImageBuffer) {
  // ── Register fonts ──────────────────────────────────────────────────────
  const fontR = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
  const fontB = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
  doc.registerFont('R', fontR);
  doc.registerFont('B', fontB);

  let y = M;

  // ── Drawing utilities ───────────────────────────────────────────────────

  /** Centred single-line text, returns next y */
  const centre = (text, yPos, size = 9, font = 'R', color = '#000') => {
    doc.font(font).fontSize(size).fillColor(color)
      .text(text, M, yPos, { width: CW, align: 'center' });
    return yPos + doc.heightOfString(text, { width: CW, fontSize: size }) + 2;
  };

  /** Left-aligned text, returns next y */
  const left = (text, yPos, size = 8, font = 'R', color = '#333') => {
    doc.font(font).fontSize(size).fillColor(color)
      .text(text, M, yPos, { width: CW });
    return yPos + doc.heightOfString(text, { width: CW, fontSize: size }) + 2;
  };

  /** Dashed separator, returns next y */
  const dashed = (yPos) => {
    const dash = 4; const gap = 3;
    let x = M;
    doc.lineWidth(0.4).strokeColor('#bbb');
    while (x < W - M) {
      doc.moveTo(x, yPos).lineTo(Math.min(x + dash, W - M), yPos).stroke();
      x += dash + gap;
    }
    return yPos + 7;
  };

  /** Two-column label + value row, returns next y */
  const twoCol = (label, value, yPos, {
    labelSize  = 8,
    valueSize  = 8,
    labelFont  = 'R',
    valueFont  = 'B',
    labelColor = '#777',
    valueColor = '#000',
    split      = 0.42,
  } = {}) => {
    const lW = CW * split;
    const vW = CW * (1 - split);
    doc.font(labelFont).fontSize(labelSize).fillColor(labelColor)
      .text(label, M, yPos, { width: lW });
    doc.font(valueFont).fontSize(valueSize).fillColor(valueColor)
      .text(value, M + lW, yPos, { width: vW, align: 'right' });
    const h = Math.max(
      doc.heightOfString(label, { width: lW, fontSize: labelSize }),
      doc.heightOfString(value, { width: vW, fontSize: valueSize }),
    );
    return yPos + h + 3;
  };

  /** Micro grey-caps label, returns next y */
  const microLabel = (text, yPos) => {
    doc.font('R').fontSize(6.5).fillColor('#999')
      .text(text.toUpperCase(), M, yPos, { width: CW, characterSpacing: 0.6 });
    return yPos + 10;
  };

  // =========================================================
  // 1. LOGO
  // =========================================================
  try {
    const logoPath = path.join(__dirname, 'logosiyah.png');
    const logoW    = 72;   // slightly smaller
    const logoH    = 28;   // explicit max height cap
    doc.image(logoPath, (W - logoW) / 2, y, {
      fit: [logoW, logoH],  // scale to fit within box, preserve aspect ratio
      align: 'center',
      valign: 'center',
    });
    y += logoH + 10;  // exact capped height + breathing room before dashed line
  } catch (_) {
    y = centre('NAR24', y, 16, 'B', '#111');
    y += 6;
  }

  y = dashed(y);

  // =========================================================
  // 2. QR CODE  (delivery orders only)
  // =========================================================
  if (qrImageBuffer) {
    const qrSize = 90;
    doc.image(qrImageBuffer, (W - qrSize) / 2, y, { width: qrSize, height: qrSize });
    y += qrSize + 4;
    y = centre('Google Maps\'ta Acmak Icin Okutun', y, 7, 'R', '#666');
    y += 4;
  }

  // =========================================================
  // 3. PAYMENT TYPE BADGE
  // =========================================================
  const isPaid     = data.isPaid || data.paymentMethod === 'card';
  const badgeLabel = isPaid ? 'ONLINE ODENDI' : 'KAPIDA ODENECEK';
  const badgeBg    = isPaid ? '#e8f8f0' : '#fef9ec';
  const badgeFg    = isPaid ? '#00955a' : '#c87900';
  const badgeH     = 20;

  doc.rect(M, y, CW, badgeH).fillColor(badgeBg).fill();
  doc.moveTo(M, y).lineTo(M + CW, y).strokeColor(badgeFg).lineWidth(0.6).stroke();
  doc.moveTo(M, y + badgeH).lineTo(M + CW, y + badgeH).strokeColor(badgeFg).lineWidth(0.6).stroke();
  doc.font('B').fontSize(9).fillColor(badgeFg)
    .text(badgeLabel, M, y + 5, { width: CW, align: 'center' });
  y += badgeH + 8;

  y = dashed(y);

  // =========================================================
  // 4. ORDER NUMBER
  // =========================================================
  y += 2;
  y = microLabel('Siparis No', y);
  const shortId = data.orderId.substring(0, 8).toUpperCase();
  y = centre(`#${shortId}`, y, 14, 'B', '#111');
  y += 4;

  y = dashed(y);
  y += 2;

  // =========================================================
  // 5. BUYER INFO
  // =========================================================
  y = microLabel('Musteri', y);
  y = left(data.buyerName || 'Misafir', y, 10, 'B', '#000');

  const phone = data.buyerPhone || data.deliveryAddress?.phoneNumber || '';
  if (phone) {
    y = left(`Tel: ${phone}`, y, 8, 'R', '#444');
  }

  if (data.deliveryType !== 'pickup' && data.deliveryAddress) {
    y += 4;
    y = microLabel('Teslimat Adresi', y);

    const addr = data.deliveryAddress;
    const addrParts = [
      addr.addressLine1,
      addr.addressLine2,
      addr.city,
      addr.mainRegion,
    ].filter(Boolean);

    for (const part of addrParts) {
      y = left(part, y, 8, 'R', '#333');
    }

    if (addr.phoneNumber && addr.phoneNumber !== phone) {
      y = left(`Tel: ${addr.phoneNumber}`, y, 8, 'R', '#444');
    }
  } else if (data.deliveryType === 'pickup') {
    y += 4;
    y = centre('GEL-AL SIPARISI', y, 9, 'B', '#555');
  }

  y += 2;

  // =========================================================
  // 6. ORDER NOTES  (optional)
  // =========================================================
  if (data.orderNotes?.trim()) {
    y = dashed(y);
    y += 2;
    y = microLabel('Siparis Notu', y);
    doc.font('R').fontSize(8).fillColor('#444')
      .text(data.orderNotes.trim(), M, y, { width: CW });
    y += doc.heightOfString(data.orderNotes.trim(), { width: CW, fontSize: 8 }) + 4;
  }

  y = dashed(y);
  y += 2;

  // =========================================================
  // 7. ORDERED ITEMS
  // =========================================================
  y = microLabel('Urunler', y);

  for (const item of data.items || []) {
    const extrasTotal = (item.extras || []).reduce(
      (s, e) => s + (e.price || 0) * (e.quantity || 1), 0,
    );
    const unitPrice = (item.price || 0) + extrasTotal;
    const lineTotal = item.itemTotal ?? unitPrice * item.quantity;

    const itemLabel  = `${item.quantity}x ${item.name}`;
    const priceLabel = `${lineTotal.toFixed(0)} ${data.currency}`;

    const lW = CW * 0.68;
    const rW = CW * 0.32;
    const ih = doc.heightOfString(itemLabel, { width: lW, fontSize: 9 });

    doc.font('B').fontSize(9).fillColor('#000')
      .text(itemLabel, M, y, { width: lW });
    doc.font('B').fontSize(9).fillColor('#000')
      .text(priceLabel, M + lW, y, { width: rW, align: 'right' });
    y += Math.max(ih, 13) + 2;

    if (item.extras?.length) {
      const extrasText = item.extras
        .map((e) => (e.quantity > 1 ? `+ ${e.name} x${e.quantity}` : `+ ${e.name}`))
        .join('  ');
      doc.font('R').fontSize(7).fillColor('#777')
        .text(extrasText, M + 6, y, { width: CW - 6 });
      y += doc.heightOfString(extrasText, { width: CW - 6, fontSize: 7 }) + 2;
    }

    if (item.specialNotes) {
      doc.font('R').fontSize(6.5).fillColor('#aaa')
        .text(`Not: ${item.specialNotes}`, M + 6, y, { width: CW - 6 });
      y += doc.heightOfString(item.specialNotes, { width: CW - 6, fontSize: 6.5 }) + 2;
    }

    y += 4;
  }

  // =========================================================
  // 8. TOTALS
  // =========================================================
  y = dashed(y);
  y += 4;

  const deliveryFee = data.deliveryFee || 0;
  if (deliveryFee > 0) {
    y = twoCol('Ara Toplam',     `${(data.subtotal || 0).toFixed(0)} ${data.currency}`, y);
    y = twoCol('Teslimat Ucreti', `${deliveryFee.toFixed(0)} ${data.currency}`,          y);
    y = dashed(y);
    y += 2;
  }

  const totalRowH = 24;
  doc.rect(M, y - 2, CW, totalRowH).fillColor('#f3f3f3').fill();
  doc.font('B').fontSize(12).fillColor('#111')
    .text('TOPLAM', M + 4, y + 3, { width: CW * 0.5 });
  doc.font('B').fontSize(13).fillColor('#00955a')
    .text(
      `${(data.totalPrice || 0).toFixed(0)} ${data.currency}`,
      M + CW * 0.5, y + 2,
      { width: CW * 0.5, align: 'right' },
    );
  y += totalRowH + 6;

  const payNote = isPaid ?
    'Odeme online olarak alindi.' :
    'Odeme teslimat sirasinda alinacak.';
  y = centre(payNote, y, 7.5, 'R', isPaid ? '#00955a' : '#c87900');
  y += 4;

  // =========================================================
  // 9. DATE & TIME
  // =========================================================
  y = dashed(y);
  y += 4;

  const formattedDate = data.orderDate.toLocaleDateString('tr-TR', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  y = centre(formattedDate, y, 8.5, 'B', '#333');
  y += 6;

  y = centre('Nar24 — Yemek Siparisi', y, 7, 'R', '#bbb');

  // Return the final y so the caller can compute the exact page height
  return y;
}
