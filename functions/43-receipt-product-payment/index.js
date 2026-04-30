import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import PDFDocument from 'pdfkit';
import * as path from 'path';
import {fileURLToPath} from 'url';
import {dirname} from 'path';
import {localizeAttributeKey, localizeAttributeValue} from '../attributeLocalization.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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
  
    // Fire-and-forget alert for post-order task failures
    function logTaskFailureAlert(taskName, orderId, buyerId, buyerName, error) {
      try {
        admin.firestore().collection('_payment_alerts').doc(`${orderId}_${taskName}`).set({
          type: `task_${taskName}_failed`,
          severity: 'low',
          orderNumber: orderId,
          pendingPaymentId: null,
          orderId,
          userId: buyerId,
          buyerName: buyerName || '',
          amount: 0,
          errorMessage: `${taskName} failed: ${error?.message || String(error)}`,
          isRead: false,
          isResolved: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          detectedBy: 'task_catch',
        });
      } catch (_) {
        // Silent — alerting should never break anything
      }
    }
  

// Background function to generate receipts
export const generateReceiptBackground = onDocumentCreated(
    {
      document: 'receiptTasks/{taskId}',
      region: 'europe-west3',
      memory: '1GB', // More memory for PDF generation
      timeoutSeconds: 120,
    },
    async (event) => {
      const taskData = event.data.data();
      const taskId = event.params.taskId;
      const db = admin.firestore();
  
      try {
        // Convert Firestore timestamp to Date
        const orderDate = taskData.orderDate.toDate ? taskData.orderDate.toDate() : new Date();
  
        // Generate PDF with converted date
        const receiptData = {
          ...taskData,
          orderDate,
        };
  
        const receiptPdf = await generateReceipt(receiptData);
  
        // Save to storage
        // Sensitive product-payment receipts live in a private bucket, separate
        // from the public marketplace assets bucket.
        const bucket = admin.storage().bucket('emlak-mobile-app-private');
        const receiptFileName = `receipts/${taskData.orderId}.pdf`;
        const file = bucket.file(receiptFileName);
  
        await file.save(receiptPdf, {
          metadata: {
            contentType: 'application/pdf',
          },
        });
  
        const filePath = receiptFileName;
  
        let receiptRef;
        
        if (taskData.ownerType === 'shop') {
          // Create receipt in shop's receipts collection
          receiptRef = db.collection('shops')
            .doc(taskData.ownerId)
            .collection('receipts')
            .doc();
        } else {
          // Create receipt in user's receipts collection
          receiptRef = db.collection('users')
            .doc(taskData.ownerId)
            .collection('receipts')
            .doc();
        }
  
        const receiptDocument = {
          receiptId: receiptRef.id,
          receiptType: taskData.receiptType || 'order', // 'order' or 'boost'
          orderId: taskData.orderId,
          buyerId: taskData.buyerId,
          totalPrice: taskData.totalPrice,
          itemsSubtotal: taskData.itemsSubtotal,
          deliveryPrice: taskData.deliveryPrice || 0,
          currency: taskData.currency,
          paymentMethod: taskData.paymentMethod,
          deliveryOption: taskData.deliveryOption || 'normal',
          couponCode: taskData.couponCode || null,
          couponDiscount: taskData.couponDiscount || 0,
          freeShippingApplied: taskData.freeShippingApplied || false,
          originalDeliveryPrice: taskData.originalDeliveryPrice || 0,
          totalSavings: (taskData.couponDiscount || 0) + 
            (taskData.freeShippingApplied ? (taskData.originalDeliveryPrice || 0) : 0),
          filePath,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        };
  
        // Add boost-specific fields if it's a boost receipt
        if (taskData.receiptType === 'boost' && taskData.boostData) {
          receiptDocument.boostDuration = taskData.boostData.boostDuration;
          receiptDocument.itemCount = taskData.boostData.itemCount;
        }
  
        // Add ad-specific fields if it's an ad receipt
  if (taskData.receiptType === 'ad' && taskData.adData) {
    receiptDocument.adType = taskData.adData.adType;
    receiptDocument.adDuration = taskData.adData.duration;
  }
  
        // Add delivery info for regular orders
        if (taskData.deliveryOption === 'pickup' && taskData.pickupPoint) {
          receiptDocument.pickupPointName = taskData.pickupPoint.name;
          receiptDocument.pickupPointAddress = taskData.pickupPoint.address;
        } else if (taskData.buyerAddress) {
          receiptDocument.deliveryAddress = `${taskData.buyerAddress.addressLine1}, ${taskData.buyerAddress.city}`;
        }
  
        await receiptRef.set(receiptDocument);
  
        // Mark task as complete
        await db.collection('receiptTasks').doc(taskId).update({
          status: 'completed',
          filePath,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        console.log(`Receipt generated successfully for ${taskData.receiptType || 'order'} ${taskData.orderId}`);
      } catch (error) {
        console.error('Error generating receipt:', error);
  
        // Mark task as failed with retry count
        const taskRef = db.collection('receiptTasks').doc(taskId);
        const taskDoc = await taskRef.get();
        const retryCount = (taskDoc.data()?.retryCount || 0) + 1;
  
        await taskRef.update({
          status: retryCount >= 3 ? 'failed' : 'pending',
          retryCount,
          lastError: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
        // If permanently failed, log to payment alerts
        if (retryCount >= 3) {
          logTaskFailureAlert('receipt_generation', taskData.orderId, taskData.buyerId, taskData.buyerName, error);
        }
  
        // If under retry limit, throw error to trigger function retry
        if (retryCount < 3) {
          throw error;
        }
      }
    },
  );
  
  async function generateReceipt(data) {
    const lang = data.language || 'en';
  
    return new Promise((resolve, reject) => {
      const doc = new PDFDocument({
        size: 'A4',
        margin: 50,
        bufferPages: true,
        compress: true,
      });
  
      const chunks = [];
  
      doc.on('data', (chunk) => chunks.push(chunk));
      doc.on('end', () => {
        const result = Buffer.concat(chunks);
        chunks.length = 0;
        resolve(result);
      });
      doc.on('error', reject);
  
      // Register Inter fonts that support Turkish characters
      const fontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
      const fontBoldPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');
  
      doc.registerFont('Inter', fontPath);
      doc.registerFont('Inter-Bold', fontBoldPath);
  
      const titleFont = 'Inter-Bold';
      const normalFont = 'Inter';
  
      // Localized text labels
      const labels = {
        en: {
          title: 'Nar24 Receipt',
          orderInfo: 'Order Information',
          buyerInfo: 'Buyer Information',
          pickupInfo: 'Pickup Point Information',
          purchasedItems: 'Purchased Items',
          orderId: 'Order ID',
          date: 'Date',
          paymentMethod: 'Payment Method',
          deliveryOption: 'Delivery Option',
          name: 'Name',
          phone: 'Phone',
          address: 'Address',
          city: 'City',
          deliveryPrice: 'Delivery',
          subtotal: 'Subtotal',
          free: 'Free',
          pickupName: 'Pickup Point',
          couponDiscount: 'Coupon Discount',
      freeShippingBenefit: 'Free Shipping Benefit',    
          pickupAddress: 'Address',
          pickupPhone: 'Contact Phone',
          pickupHours: 'Operating Hours',
          pickupContact: 'Contact Person',
          pickupNotes: 'Notes',
          seller: 'Seller',
          product: 'Product',
          attributes: 'Attributes',
          qty: 'Qty',
          unitPrice: 'Unit Price',
          total: 'Total',
          footer: 'This is a computer-generated receipt and does not require a signature.',
          boostDuration: 'Boost Duration',
      boostedItems: 'Boosted Items',
      duration: 'Duration',
      shopName: 'Shop Name',
      adType: 'Ad Type',
  tax: 'Tax (20%)',
        },
        tr: {
          title: 'Nar24 Fatura',
          orderInfo: 'Sipariş Bilgileri',
          buyerInfo: 'Alıcı Bilgileri',
          pickupInfo: 'Gel-Al Noktası Bilgileri',
          purchasedItems: 'Satın Alınan Ürünler',
          orderId: 'Sipariş No',
          date: 'Tarih',
          paymentMethod: 'Ödeme Yöntemi',
          deliveryOption: 'Teslimat Seçeneği',
          name: 'Ad-Soyad',
          phone: 'Telefon',
          address: 'Adres',
          city: 'Şehir',
          deliveryPrice: 'Kargo',
          subtotal: 'Ara Toplam',
          free: 'Ücretsiz',
          pickupName: 'Gel-Al Noktası',
          pickupAddress: 'Adres',
          couponDiscount: 'Kupon İndirimi',
          freeShippingBenefit: 'Ücretsiz Kargo Avantajı',
          pickupPhone: 'İletişim Telefonu',
          pickupHours: 'Çalışma Saatleri',
          pickupContact: 'İletişim Kişisi',
          pickupNotes: 'Notlar',
          seller: 'Satıcı',
          product: 'Ürün',
          attributes: 'Özellikler',
          qty: 'Adet',
          unitPrice: 'Birim Fiyat',
          total: 'Toplam',
          footer: 'Bu bilgisayar tarafından oluşturulan bir makbuzdur ve imza gerektirmez.',
          boostDuration: 'Boost Süresi',
          boostedItems: 'Boost Edilen',
          duration: 'Süre',
          shopName: 'Dükkan İsmi',
          adType: 'Reklam Türü',
  tax: 'KDV (%20)',
        },
        ru: {
          title: 'Nar24 Счет',
          orderInfo: 'Информация о заказе',
          buyerInfo: 'Информация о покупателе',
          pickupInfo: 'Информация о пункте выдачи',
          purchasedItems: 'Купленные товары',
          orderId: 'Номер заказа',
          date: 'Дата',
          paymentMethod: 'Способ оплаты',
          deliveryOption: 'Вариант доставки',
          name: 'Имя',
          phone: 'Телефон',
          address: 'Адрес',
          city: 'Город',
          couponDiscount: 'Скидка по купону',
          freeShippingBenefit: 'Бесплатная доставка',
          pickupName: 'Пункт выдачи',
          pickupAddress: 'Адрес',
          pickupPhone: 'Контактный телефон',
          pickupHours: 'Часы работы',
          deliveryPrice: 'Доставка',
          subtotal: 'Промежуточный итог',
          free: 'Бесплатно',
          pickupContact: 'Контактное лицо',
          pickupNotes: 'Примечания',
          seller: 'Продавец',
          product: 'Товар',
          attributes: 'Характеристики',
          qty: 'Кол-во',
          unitPrice: 'Цена за единицу',
          total: 'Итого',
          footer: 'Это компьютерный чек и не требует подписи.',
          boostDuration: 'Длительность буста',
          boostedItems: 'Усиленные товары',
          duration: 'Длительность',
          shopName: 'Название магазина',
          adType: 'Тип рекламы',
  tax: 'Налог (20%)',
        },
      };
  
      const t = labels[lang] || labels.en;
  
      // Header with logo and title
      doc.fontSize(24)
        .font(titleFont)
        .text(t.title, 50, 50);
  
      // Add logo on the right side
      try {
        const logoPath = path.join(__dirname, 'siyahlogo.png');
        doc.image(logoPath, 460, 0, {width: 70});
      } catch (err) {
        console.log('Logo not found:', err);
      }
  
      // Divider line
      doc.moveTo(50, 100)
        .lineTo(550, 100)
        .strokeColor('#e0e0e0')
        .lineWidth(1)
        .stroke();
  
      // Order Information Section - LEFT COLUMN
      doc.fontSize(14)
        .fillColor('#333')
        .font(titleFont)
        .text(t.orderInfo, 50, 115);
  
      // Format date based on language
      const dateOptions = {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      };
      const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
      const formattedDate = data.orderDate.toLocaleDateString(locale, dateOptions);
  
      // LEFT COLUMN - Order details
      const leftColumnX = 50;
      const rightColumnX = 320;
      const labelWidth = 110;
      const valueX = leftColumnX + labelWidth;
  
      doc.fontSize(10)
        .font(normalFont)
        .fillColor('#666');
  
      // Order ID row
      doc.text(`${t.orderId}:`, leftColumnX, 140, {width: labelWidth, align: 'left'})
        .fillColor('#000')
        .font(titleFont)
        .text(data.orderId.substring(0, 8).toUpperCase(), valueX, 140);
  
      // Date row
      doc.font(normalFont)
        .fillColor('#666')
        .text(`${t.date}:`, leftColumnX, 160, {width: labelWidth, align: 'left'})
        .fillColor('#000')
        .text(formattedDate, valueX, 160);
  
      // Payment method row
      let currentY = 180; // DEFINE IT HERE FIRST!
  doc.fillColor('#666')
    .text(`${t.paymentMethod}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
    .fillColor('#000')
    .text(data.paymentMethod, valueX, currentY);
  currentY += 20;
  
  if (data.receiptType === 'boost' && data.boostData) {
    doc.fillColor('#666')
      .text(`${t.boostDuration}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
      .fillColor('#000')
      .text(`${data.boostData.boostDuration} ${lang === 'tr' ? 'dakika' : lang === 'ru' ? 'минут' : 'minutes'}`, valueX, currentY);
    currentY += 20;
    
    doc.fillColor('#666')
      .text(`${t.boostedItems}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
      .fillColor('#000')
      .text(`${data.boostData.itemCount} ${lang === 'tr' ? 'ürün' : lang === 'ru' ? 'товаров' : 'items'}`, valueX, currentY);
    currentY += 20;
  }
  
  // Delivery option (skip for boost receipts)
  if (data.receiptType !== 'boost' && data.receiptType !== 'ad') {
    doc.fillColor('#666')
      .text(`${t.deliveryOption}:`, leftColumnX, currentY, {width: labelWidth, align: 'left'})
      .fillColor('#000')
      .text(formatDeliveryOption(data.deliveryOption, lang), valueX, currentY);
  }
  
  // RIGHT COLUMN - Conditional buyer/pickup information
  let rightCurrentY = 115;
  const buyerLabelWidth = 90;
  const buyerValueX = rightColumnX + buyerLabelWidth;
  
  if (data.pickupPoint) {
    // PICKUP POINT INFORMATION
    doc.font(titleFont)
      .fillColor('#333')
      .fontSize(14)
      .text(t.pickupInfo, rightColumnX, rightCurrentY);
  
    doc.font(normalFont)
      .fontSize(10);
    rightCurrentY += 25;
  
    // Pickup point details...
    doc.fillColor('#666')
      .text(`${t.pickupName}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.pickupPoint.name, buyerValueX, rightCurrentY, {width: 160});
    rightCurrentY += 20;
  
    doc.fillColor('#666')
      .text(`${t.pickupAddress}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.pickupPoint.address, buyerValueX, rightCurrentY, {width: 160});
    rightCurrentY += 20;
  
    if (data.pickupPoint.phone) {
      doc.fillColor('#666')
        .text(`${t.pickupPhone}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
        .fillColor('#000')
        .text(data.pickupPoint.phone, buyerValueX, rightCurrentY);
      rightCurrentY += 20;
    }
  
    doc.fillColor('#666')
      .text(`${t.name}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(data.buyerName, buyerValueX, rightCurrentY);
    rightCurrentY += 20;
  } else {
    // BUYER INFORMATION (works for both regular orders and boost receipts)
    doc.font(titleFont)
      .fillColor('#333')
      .fontSize(14)
      .text(t.buyerInfo, rightColumnX, rightCurrentY);
  
    doc.font(normalFont)
      .fontSize(10);
    rightCurrentY += 25;
  
   // Buyer name - Use shopName label for boost receipts where owner is a shop
   const nameLabel = ((data.receiptType === 'boost' && data.ownerType === 'shop') || data.receiptType === 'ad') ? t.shopName : t.name;
  doc.fillColor('#666')
    .text(`${nameLabel}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
    .fillColor('#000')
    .text(data.buyerName || 'N/A', buyerValueX, rightCurrentY, {width: 160});
    rightCurrentY += 20;
  
    // Email (for boost receipts)
    if (data.buyerEmail) {
      doc.fillColor('#666')
        .text('Email:', rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
        .fillColor('#000')
        .text(data.buyerEmail, buyerValueX, rightCurrentY, {width: 160});
      rightCurrentY += 20;
    }
  
    // Phone - handle both boost and regular order formats
    const phoneNumber = data.buyerPhone || data.buyerAddress?.phoneNumber || 'N/A';
    doc.fillColor('#666')
      .text(`${t.phone}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
      .fillColor('#000')
      .text(phoneNumber, buyerValueX, rightCurrentY);
    rightCurrentY += 20;
  
    // Only show full address for regular orders (not boost)
    if (data.receiptType !== 'boost' && data.receiptType !== 'ad' && data.buyerAddress) {
      doc.fillColor('#666')
        .text(`${t.address}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
        .fillColor('#000')
        .text(data.buyerAddress.addressLine1, buyerValueX, rightCurrentY, {width: 160});
      rightCurrentY += 20;
  
      if (data.buyerAddress.addressLine2) {
        doc.fillColor('#000')
          .text(data.buyerAddress.addressLine2, buyerValueX, rightCurrentY, {width: 160});
        rightCurrentY += 20;
      }
  
      doc.fillColor('#666')
        .text(`${t.city}:`, rightColumnX, rightCurrentY, {width: buyerLabelWidth, align: 'left'})
        .fillColor('#000')
        .text(data.buyerAddress.city, buyerValueX, rightCurrentY);
      rightCurrentY += 20;
    }
  }
  
      // Items section
      let yPosition = Math.max(rightCurrentY + 20, 240);
  
      doc.moveTo(50, yPosition)
        .lineTo(550, yPosition)
        .strokeColor('#e0e0e0')
        .lineWidth(1)
        .stroke();
  
      yPosition += 15;
  
      doc.fontSize(14)
        .font(titleFont)
        .fillColor('#333')
        .text(t.purchasedItems, 50, yPosition);
  
      yPosition += 25;
  
      if (data.receiptType === 'ad' && data.adData) {
        // AD RECEIPT: Simple single-row table
        doc.fontSize(9)
          .font(titleFont)
          .fillColor('#666')
          .text(t.product, 55, yPosition, {width: 200})
          .text(t.duration, 260, yPosition, {width: 100})
          .text(t.unitPrice, 365, yPosition, {width: 70, align: 'right'})
          .text(t.total, 480, yPosition, {width: 65, align: 'right'});
      
        yPosition += 18;
      
        doc.moveTo(55, yPosition - 3)
          .lineTo(545, yPosition - 3)
          .strokeColor('#e0e0e0')
          .lineWidth(0.5)
          .stroke();
      
        doc.font(normalFont)
          .fillColor('#000');
      
        const adTypeLabel = getAdTypeLabel(data.adData.adType);
        const durationLabel = formatAdDuration(data.adData.duration, lang);
      
        doc.fontSize(9)
          .text(adTypeLabel, 55, yPosition, {width: 200})
          .text(durationLabel, 260, yPosition, {width: 100})
          .text(`${data.itemsSubtotal.toFixed(2)} ${data.currency}`, 365, yPosition, {width: 70, align: 'right'})
          .text(`${data.itemsSubtotal.toFixed(2)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
      
        yPosition += 30;
      } else if (data.receiptType === 'boost' && data.boostData) {
        // BOOST RECEIPT: Simple table header
        doc.fontSize(9)
          .font(titleFont)
          .fillColor('#666')
          .text(t.product, 55, yPosition, {width: 200})
          .text(t.duration, 260, yPosition, {width: 100})
          .text(t.unitPrice, 365, yPosition, {width: 70, align: 'right'})
          .text(t.total, 480, yPosition, {width: 65, align: 'right'});
      
        yPosition += 18;
      
        // Draw line under header
        doc.moveTo(55, yPosition - 3)
          .lineTo(545, yPosition - 3)
          .strokeColor('#e0e0e0')
          .lineWidth(0.5)
          .stroke();
      
        // Render boost items
        doc.font(normalFont)
          .fillColor('#000');
      
        for (const item of data.boostData.items) {
          if (yPosition > 700) {
            doc.addPage();
            yPosition = 50;
          }
          
          doc.fontSize(9)
            .text(item.productName || 'Boost Item', 55, yPosition, {width: 200})
            .text(`${data.boostData.boostDuration} ${lang === 'tr' ? 'dakika' : lang === 'ru' ? 'минут' : 'minutes'}`, 260, yPosition, {width: 100})
            .text(`${item.unitPrice.toFixed(2)} ${data.currency}`, 365, yPosition, {width: 70, align: 'right'})
            .text(`${item.totalPrice.toFixed(2)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
          
          yPosition += 20;
        }
      
        yPosition += 10;
      } else {
        // REGULAR ORDER RECEIPT: Original sellerGroups rendering
        for (const sellerGroup of data.sellerGroups) {
          // Seller header with background
          doc.rect(50, yPosition - 5, 500, 22)
            .fillColor('#f5f5f5')
            .fill();
      
          doc.fontSize(11)
            .font(titleFont)
            .fillColor('#333')
            .text(`${t.seller}: ${sellerGroup.sellerName}`, 55, yPosition);
      
          yPosition += 25;
      
          // Table header
          doc.fontSize(9)
            .font(titleFont)
            .fillColor('#666')
            .text(t.product, 55, yPosition, {width: 140})
            .text(t.attributes, 200, yPosition, {width: 160})
            .text(t.qty, 365, yPosition, {width: 35, align: 'center'})
            .text(t.unitPrice, 405, yPosition, {width: 70, align: 'right'})
            .text(t.total, 480, yPosition, {width: 65, align: 'right'});
      
          yPosition += 18;
      
          // Draw line under header
          doc.moveTo(55, yPosition - 3)
            .lineTo(545, yPosition - 3)
            .strokeColor('#e0e0e0')
            .lineWidth(0.5)
            .stroke();
      
          // Items for this seller
          doc.font(normalFont)
            .fillColor('#000');
      
          for (const item of sellerGroup.items) {
            // Check if we need a new page
            if (yPosition > 700) {
              doc.addPage();
              yPosition = 50;
            }
      
            doc.fontSize(9);
      
            // Product name
            const productName = item.productName || 'Unknown Product';
            doc.text(productName, 55, yPosition, {width: 140});
      
            // Display localized attributes
            const attrs = item.selectedAttributes || {};
            const attrTexts = [];
      
            Object.entries(attrs).forEach(([key, value]) => {
              const systemFields = [
                'productId', 'quantity', 'addedAt', 'updatedAt',
                'sellerId', 'sellerName', 'isShop', 'finalPrice',
                'selectedColorImage', 'productImage',
                'ourComission', 'calculatedTotal', 'calculatedUnitPrice',
                'isBundleItem', 'unitPrice', 'totalPrice', 'currency', 'sellerContactNo',
              ];
      
              if (value && value !== '' && value !== null && !systemFields.includes(key)) {
                const localizedKey = localizeAttributeKey(key, lang);
                const localizedValue = localizeAttributeValue(key, value, lang);
                attrTexts.push(`${localizedKey}: ${localizedValue}`);
              }
            });
      
            const attrText = attrTexts.join(', ');
      
            if (attrText) {
              doc.fontSize(8)
                .fillColor('#666')
                .text(attrText, 200, yPosition, {width: 160});
            } else {
              doc.text('-', 200, yPosition, {width: 160});
            }
      
            // Quantity, unit price, and total
            doc.fontSize(9)
              .fillColor('#000')
              .text(item.quantity.toString(), 365, yPosition, {width: 35, align: 'center'})
              .text(`${item.unitPrice.toFixed(2)} ${data.currency}`, 405, yPosition, {width: 70, align: 'right'})
              .text(`${item.totalPrice.toFixed(2)} ${data.currency}`, 480, yPosition, {width: 65, align: 'right'});
      
            yPosition += 20;
          }
      
          yPosition += 10;
        }
      }
  
      // Total section
      if (yPosition > 650) {
        doc.addPage();
        yPosition = 50;
      }
  
      doc.moveTo(50, yPosition)
        .lineTo(550, yPosition)
        .strokeColor('#e0e0e0')
        .lineWidth(1)
        .stroke();
  
      yPosition += 15;
  
      // Calculate values FIRST
      const originalDeliveryPrice = data.originalDeliveryPrice || data.deliveryPrice || 0;
  const deliveryPrice = data.deliveryPrice || 0;
  const couponDiscount = data.couponDiscount || 0;
  const freeShippingApplied = data.freeShippingApplied || false;
  const subtotal = data.itemsSubtotal || (data.totalPrice - deliveryPrice + couponDiscount);
  const grandTotal = data.totalPrice;
  
      // Subtotal row
      doc.font(titleFont)
        .fontSize(11)
        .fillColor('#666')
        .text(`${t.subtotal}:`, 390, yPosition)
        .fillColor('#333')
        .text(`${subtotal.toFixed(2)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});
  
      yPosition += 20;
  
      if (couponDiscount > 0) {
        doc.font(titleFont)
          .fontSize(11)
          .fillColor('#666')
          .text(`${t.couponDiscount}:`, 390, yPosition)
          .fillColor('#00A86B')
          .text(`-${couponDiscount.toFixed(2)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});
      
        yPosition += 20;
      }
  
      if (data.receiptType !== 'boost' && data.receiptType !== 'ad') {
        // ✅ UPDATED: Show free shipping benefit
        if (freeShippingApplied && originalDeliveryPrice > 0) {
          // Show original price struck through and "Free" 
          doc.font(titleFont)
            .fontSize(11)
            .fillColor('#666')
            .text(`${t.deliveryPrice}:`, 390, yPosition);
          
          // Show original price with strikethrough effect (gray)
          doc.fillColor('#999')
            .text(`${originalDeliveryPrice.toFixed(2)}`, 460, yPosition, {width: 40, align: 'right'});
          
          // Draw strikethrough line
          const textWidth = doc.widthOfString(`${originalDeliveryPrice.toFixed(2)}`);
          doc.moveTo(500 - textWidth, yPosition + 5)
            .lineTo(502, yPosition + 5)
            .strokeColor('#999')
            .lineWidth(1)
            .stroke();
          
          // Show "Free" in green
          doc.fillColor('#00A86B')
            .text(t.free, 505, yPosition, {width: 35, align: 'right'});
          
          yPosition += 18;
          
          // Show benefit label
          doc.fontSize(9)
            .fillColor('#00A86B')
            .text(`✓ ${t.freeShippingBenefit}`, 390, yPosition);
          
          yPosition += 20;
        } else {
          // Normal delivery display (no free shipping benefit)
          const deliveryText = deliveryPrice === 0 ? t.free : `${deliveryPrice.toFixed(2)} ${data.currency}`;
          const deliveryColor = deliveryPrice === 0 ? '#00A86B' : '#333';
      
          doc.font(titleFont)
            .fontSize(11)
            .fillColor('#666')
            .text(`${t.deliveryPrice}:`, 390, yPosition)
            .fillColor(deliveryColor)
            .text(deliveryText, 460, yPosition, {width: 80, align: 'right'});
      
          yPosition += 25;
        }
      }
  
      // Tax row (for ad receipts)
  if (data.receiptType === 'ad' && data.taxAmount) {
    doc.font(titleFont)
      .fontSize(11)
      .fillColor('#666')
      .text(`${t.tax}:`, 390, yPosition)
      .fillColor('#333')
      .text(`${data.taxAmount.toFixed(2)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});
  
    yPosition += 20;
  }
      
      yPosition += 5;
      
      // Divider line
      doc.moveTo(380, yPosition - 5)
        .lineTo(550, yPosition - 5)
        .strokeColor('#333')
        .lineWidth(1.5)
        .stroke();
      
      yPosition += 10;
      
      // Total with background
      doc.rect(380, yPosition - 10, 170, 35)
        .fillColor('#f0f8f0')
        .fill();
      
      doc.font(titleFont)
        .fontSize(14)
        .fillColor('#333')
        .text(`${t.total}:`, 390, yPosition)
        .fillColor('#00A86B')
        .fontSize(16)
        .text(`${grandTotal.toFixed(2)} ${data.currency}`, 460, yPosition, {width: 80, align: 'right'});
  
      // Footer
      doc.fontSize(8)
        .font(normalFont)
        .fillColor('#999')
        .text(t.footer, 50, 750, {
          align: 'center',
          width: 500,
        });
  
      doc.end();
    });
  }
  
  function formatAdDuration(duration, lang = 'en') {
    const durations = {
      en: {
        oneWeek: '1 Week',
        twoWeeks: '2 Weeks',
        oneMonth: '1 Month',
      },
      tr: {
        oneWeek: '1 Hafta',
        twoWeeks: '2 Hafta',
        oneMonth: '1 Ay',
      },
      ru: {
        oneWeek: '1 Неделя',
        twoWeeks: '2 Недели',
        oneMonth: '1 Месяц',
      },
    };
    return durations[lang]?.[duration] || durations['en'][duration] || duration;
  }
  
  
  // Helper functions for formatting
  function formatDeliveryOption(option, lang = 'en') {
    const options = {
      en: {
        'normal': 'Normal Delivery',
        'express': 'Express Delivery',
      },
      tr: {
        'normal': 'Normal Teslimat',
        'express': 'Express Teslimat',
      },
      ru: {
        'normal': 'Обычная доставка',
        'express': 'Экспресс-доставка',
      },
    };
    return options[lang]?.[option] || options['en'][option] || option;
  }
