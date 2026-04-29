                                                                                                                                                                                   
 import * as functions from 'firebase-functions/v2';
 import {onCall} from 'firebase-functions/v2/https';
 import admin from 'firebase-admin';
 import {Storage} from '@google-cloud/storage';
 import PDFDocument from 'pdfkit';
 import * as path from 'path';
 import {fileURLToPath} from 'url';
 import {dirname} from 'path';

 const storage = new Storage();
 const __filename = fileURLToPath(import.meta.url);
 const __dirname = dirname(__filename);
 const regularFontPath = path.join(__dirname, 'fonts', 'Inter-Light.ttf');
 const boldFontPath = path.join(__dirname, 'fonts', 'Inter-Medium.ttf');

const ReportTranslations = {
    en: {
      generated: 'Generated',
      dateRange: 'Date Range',
      products: 'Products',
      orders: 'Orders',
      boostHistory: 'Boost History',
      sortedBy: 'Sorted by',
      descending: 'Descending',
      ascending: 'Ascending',
      productName: 'Product Name',
      category: 'Category',
      price: 'Price',
      quantity: 'Quantity',
      views: 'Views',
      sales: 'Sales',
      favorites: 'Favorites',
      cartAdds: 'Cart Adds',
      product: 'Product',
      buyer: 'Buyer',
      status: 'Status',
      date: 'Date',
      item: 'Item',
      durationMinutes: 'Duration (min)',
      cost: 'Cost',
      impressions: 'Impressions',
      clicks: 'Clicks',
      notSpecified: 'Not specified',
      showingFirstItemsOfTotal: (shown, total) => `Showing first ${shown} items of ${total} total`,
      noDataAvailableForSection: 'No data available for this section',
      sortByDate: 'Date',
      sortByPurchaseCount: 'Purchase Count',
      sortByClickCount: 'Click Count',
      sortByFavoritesCount: 'Favorites Count',
      sortByCartCount: 'Cart Count',
      sortByPrice: 'Price',
      sortByDuration: 'Duration',
      sortByImpressionCount: 'Impression Count',
      statusPending: 'Pending',
      statusProcessing: 'Processing',
      statusShipped: 'Shipped',
      statusDelivered: 'Delivered',
      statusCancelled: 'Cancelled',
      statusReturned: 'Returned',
      unknownShop: 'Unknown Shop',
      reportGenerationFailed: 'Report generation failed',
      reportGeneratedSuccessfully: 'Report generated successfully',
    },
    tr: {
      generated: 'Oluşturuldu',
      dateRange: 'Tarih Aralığı',
      products: 'Ürünler',
      orders: 'Siparişler',
      boostHistory: 'Boost Geçmişi',
      sortedBy: 'Sıralama',
      descending: 'Azalan',
      ascending: 'Artan',
      productName: 'Ürün Adı',
      category: 'Kategori',
      price: 'Fiyat',
      quantity: 'Miktar',
      views: 'Görüntüleme',
      sales: 'Satış',
      favorites: 'Favoriler',
      cartAdds: 'Sepete Ekleme',
      product: 'Ürün',
      buyer: 'Alıcı',
      status: 'Durum',
      date: 'Tarih',
      item: 'Öğe',
      durationMinutes: 'Süre (dk)',
      cost: 'Maliyet',
      impressions: 'Gösterim',
      clicks: 'Tıklama',
      notSpecified: 'Belirtilmemiş',
      showingFirstItemsOfTotal: (shown, total) => `Toplam ${total} öğeden ilk ${shown} tanesi gösteriliyor`,
      noDataAvailableForSection: 'Bu bölüm için veri mevcut değil',
      sortByDate: 'Tarih',
      sortByPurchaseCount: 'Satın Alma Sayısı',
      sortByClickCount: 'Tıklama Sayısı',
      sortByFavoritesCount: 'Favori Sayısı',
      sortByCartCount: 'Sepet Sayısı',
      sortByPrice: 'Fiyat',
      sortByDuration: 'Süre',
      sortByImpressionCount: 'Gösterim Sayısı',
      statusPending: 'Beklemede',
      statusProcessing: 'İşleniyor',
      statusShipped: 'Kargoya Verildi',
      statusDelivered: 'Teslim Edildi',
      statusCancelled: 'İptal Edildi',
      statusReturned: 'İade Edildi',
      unknownShop: 'Bilinmeyen Mağaza',
      reportGenerationFailed: 'Rapor oluşturma başarısız',
      reportGeneratedSuccessfully: 'Rapor başarıyla oluşturuldu',
    },
    ru: {
      generated: 'Создано',
      dateRange: 'Диапазон дат',
      products: 'Товары',
      orders: 'Заказы',
      boostHistory: 'История продвижения',
      sortedBy: 'Сортировка',
      descending: 'По убыванию',
      ascending: 'По возрастанию',
      productName: 'Название товара',
      category: 'Категория',
      price: 'Цена',
      quantity: 'Количество',
      views: 'Просмотры',
      sales: 'Продажи',
      favorites: 'Избранное',
      cartAdds: 'Добавления в корзину',
      product: 'Товар',
      buyer: 'Покупатель',
      status: 'Статус',
      date: 'Дата',
      item: 'Элемент',
      durationMinutes: 'Длительность (мин)',
      cost: 'Стоимость',
      impressions: 'Показы',
      clicks: 'Клики',
      notSpecified: 'Не указано',
      showingFirstItemsOfTotal: (shown, total) => `Показаны первые ${shown} из ${total}`,
      noDataAvailableForSection: 'Нет данных для этого раздела',
      sortByDate: 'Дата',
      sortByPurchaseCount: 'Количество покупок',
      sortByClickCount: 'Количество кликов',
      sortByFavoritesCount: 'Количество избранного',
      sortByCartCount: 'Количество корзин',
      sortByPrice: 'Цена',
      sortByDuration: 'Длительность',
      sortByImpressionCount: 'Количество показов',
      statusPending: 'В ожидании',
      statusProcessing: 'Обработка',
      statusShipped: 'Отправлено',
      statusDelivered: 'Доставлено',
      statusCancelled: 'Отменено',
      statusReturned: 'Возвращено',
      unknownShop: 'Неизвестный магазин',
      reportGenerationFailed: 'Ошибка создания отчета',
      reportGeneratedSuccessfully: 'Отчет успешно создан',
    },
  };
  
  // Helper function to get translation
  function t(lang, key, ...args) {
    const translation = ReportTranslations[lang] || ReportTranslations.en;
    const value = translation[key] || ReportTranslations.en[key] || key;
    return typeof value === 'function' ? value(...args) : value;
  }
  
  // Helper function to format dates
  function formatDate(date, lang = 'en') {
    const options = {year: 'numeric', month: 'short', day: 'numeric'};
    const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
    return date.toLocaleDateString(locale, options);
  }
  
  function formatDateTime(date, lang = 'en') {
    const options = {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    };
    const locale = lang === 'tr' ? 'tr-TR' : lang === 'ru' ? 'ru-RU' : 'en-US';
    return date.toLocaleDateString(locale, options);
  }
  
  // Sort functions
  function sortProducts(products, sortBy, descending) {
    return [...products].sort((a, b) => {
      let comparison = 0;
      switch (sortBy) {
      case 'date': {
        const dateA = a.createdAt?.toDate() || new Date(1970, 0, 1);
        const dateB = b.createdAt?.toDate() || new Date(1970, 0, 1);
        comparison = dateA - dateB;
        break;
      }
      case 'purchaseCount': {
        comparison = (a.purchaseCount || 0) - (b.purchaseCount || 0);
        break;
      }
      case 'clickCount': {
        comparison = (a.clickCount || 0) - (b.clickCount || 0);
        break;
      }
      case 'favoritesCount': {
        comparison = (a.favoritesCount || 0) - (b.favoritesCount || 0);
        break;
      }
      case 'cartCount': {
        comparison = (a.cartCount || 0) - (b.cartCount || 0);
        break;
      }
      case 'price': {
        comparison = (a.price || 0) - (b.price || 0);
        break;
      }
      }
      return descending ? -comparison : comparison;
    });
  }
  
  function sortOrders(orders, sortBy, descending) {
    return [...orders].sort((a, b) => {
      let comparison = 0;
      switch (sortBy) {
      case 'date': {
        const dateA = a.timestamp?.toDate() || new Date(1970, 0, 1);
        const dateB = b.timestamp?.toDate() || new Date(1970, 0, 1);
        comparison = dateA - dateB;
        break;
      }
      case 'price': {
        comparison = (a.price || 0) - (b.price || 0);
        break;
      }
      }
      return descending ? -comparison : comparison;
    });
  }
  
  function sortBoosts(boosts, sortBy, descending) {
    return [...boosts].sort((a, b) => {
      let comparison = 0;
      switch (sortBy) {
      case 'date': {
        const dateA = a.createdAt?.toDate() || new Date(1970, 0, 1);
        const dateB = b.createdAt?.toDate() || new Date(1970, 0, 1);
        comparison = dateA - dateB;
        break;
      }
      case 'duration': {
        comparison = (a.boostDuration || 0) - (b.boostDuration || 0);
        break;
      }
      case 'price': {
        comparison = (a.boostPrice || 0) - (b.boostPrice || 0);
        break;
      }
      case 'impressionCount': {
        comparison = (a.impressionsDuringBoost || 0) - (b.impressionsDuringBoost || 0);
        break;
      }
      case 'clickCount': {
        comparison = (a.clicksDuringBoost || 0) - (b.clicksDuringBoost || 0);
        break;
      }
      }
      return descending ? -comparison : comparison;
    });
  }
  
  // Batch processing for large datasets
  async function* batchQuery(query, batchSize = 500) {
    let lastDoc = null;
    let hasMore = true;
  
    while (hasMore) {
      let batch = query.limit(batchSize);
  
      if (lastDoc) {
        batch = batch.startAfter(lastDoc);
      }
  
      const snapshot = await batch.get();
  
      if (snapshot.empty) {
        hasMore = false;
      } else {
        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        yield snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
  
        // If we got less than batchSize, we've reached the end
        if (snapshot.docs.length < batchSize) {
          hasMore = false;
        }
      }
    }
  }
  
  // Main Cloud Function
  export const generatePDFReport = onCall(
    {
      region: 'europe-west3',
      timeoutSeconds: 540, // 9 minutes timeout
      memory: '2GiB', // Note: v2 uses 'GiB' instead of 'GB'
    },
    async (request) => {
      try {
        // Validate authentication
        if (!request.auth) {
          throw new functions.https.HttpsError(
            'unauthenticated',
            'User must be authenticated',
          );
        }
  
        const {reportId, shopId} = request.data;
  
        if (!reportId || !shopId) {
          throw new functions.https.HttpsError(
            'invalid-argument',
            'Missing required parameters',
          );
        }
  
        // Get report config, user language, and shop info all in parallel
        const [reportDoc, userDoc, shopDoc] = await Promise.all([
          admin.firestore().collection('shops').doc(shopId).collection('reports').doc(reportId).get(),
          admin.firestore().collection('users').doc(request.auth.uid).get(),
          admin.firestore().collection('shops').doc(shopId).get(),
        ]);
  
        if (!reportDoc.exists) {
          throw new functions.https.HttpsError(
            'not-found',
            'Report not found',
          );
        }
  
        const config = reportDoc.data();
        const userLang = userDoc.exists ? (userDoc.data().languageCode || 'en') : 'en';
        const shopName = shopDoc.exists ? (shopDoc.data().name || t(userLang, 'unknownShop')) : t(userLang, 'unknownShop');
  
        // Update report status to processing
        await reportDoc.ref.update({
          status: 'processing',
          processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
  
       // Collect data with pagination
       const reportData = {};
  
       // Helper: drain a batchQuery into a flat array
       const collectAll = async (query) => {
         const results = [];
         for await (const batch of batchQuery(query)) {
           results.push(...batch);
         }
         return results;
       };
  
       // Build queries only for requested sections
       const buildProductsQuery = () => {
         let q = admin.firestore().collection('shop_products').where('shopId', '==', shopId);
         if (config.productCategory) q = q.where('category', '==', config.productCategory);
         if (config.productSubcategory) q = q.where('subcategory', '==', config.productSubcategory);
         if (config.productSubsubcategory) q = q.where('subsubcategory', '==', config.productSubsubcategory);
         if (config.dateRange) {
           q = q.where('createdAt', '>=', config.dateRange.start)
                .where('createdAt', '<=', config.dateRange.end);
         }
         return q;
       };
  
       const buildOrdersQuery = () => {
         let q = admin.firestore().collectionGroup('items').where('shopId', '==', shopId);
         if (config.dateRange) {
           q = q.where('timestamp', '>=', config.dateRange.start)
                .where('timestamp', '<=', config.dateRange.end);
         }
         return q;
       };
  
       const buildBoostQuery = () => {
         let q = admin.firestore().collection('shops').doc(shopId).collection('boostHistory');
         if (config.dateRange) {
           q = q.where('createdAt', '>=', config.dateRange.start)
                .where('createdAt', '<=', config.dateRange.end);
         }
         return q;
       };
  
       // Fetch all requested sections in parallel
       const [products, orders, boosts] = await Promise.all([
         config.includeProducts     ? collectAll(buildProductsQuery()) : Promise.resolve(null),
         config.includeOrders       ? collectAll(buildOrdersQuery())   : Promise.resolve(null),
         config.includeBoostHistory ? collectAll(buildBoostQuery())    : Promise.resolve(null),
       ]);
  
       if (products !== null) {
         reportData.products = sortProducts(products, config.productSortBy || 'date', config.productSortDescending !== false);
       }
       if (orders !== null) {
         reportData.orders = sortOrders(orders, config.orderSortBy || 'date', config.orderSortDescending !== false);
       }
       if (boosts !== null) {
         reportData.boostHistory = sortBoosts(boosts, config.boostSortBy || 'date', config.boostSortDescending !== false);
       }
  
        // Set up GCS stream first — PDF pipes into it as it's generated
        const bucket = storage.bucket(`${process.env.GCLOUD_PROJECT}.appspot.com`);
        const timestamp = Date.now();
        const fileName = `reports/${shopId}/${reportId}_${timestamp}.pdf`;
        const file = bucket.file(fileName);
  
        const writeStream = file.createWriteStream({
          metadata: {
            contentType: 'application/pdf',
            metadata: {
              reportId,
              shopId,
              generatedAt: new Date().toISOString(),
              userId: request.auth.uid,
            },
          },
          resumable: true,
        });
  
        // Generate PDF — streams directly into GCS, no in-memory buffer
        await generatePDF(config, reportData, shopName, userLang, writeStream);
  
        // Get download URL
        const [url] = await file.getSignedUrl({
          action: 'read',
          expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
        });
  
        // Update report with success status
        await reportDoc.ref.update({
          status: 'completed',
          pdfUrl: url,
          pdfSize: null, // Size no longer available without buffering — remove or compute separately if needed
          filePath: fileName,
          generationCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
          // Store summary data for quick access
          summary: {
            productsCount: reportData.products?.length || 0,
            ordersCount: reportData.orders?.length || 0,
            boostsCount: reportData.boostHistory?.length || 0,
          },
        });
  
        return {
          success: true,
          pdfUrl: url,
          message: t(userLang, 'reportGeneratedSuccessfully'),
        };
      } catch (error) {
        console.error('Error generating PDF report:', error);
  
        // Update report with error status
        if (request.data.reportId && request.data.shopId) {
          await admin.firestore()
            .collection('shops')
            .doc(request.data.shopId)
            .collection('reports')
            .doc(request.data.reportId)
            .update({
              status: 'failed',
              error: error.message,
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
            })
            .catch(console.error);
        }
  
        throw new functions.https.HttpsError(
          'internal',
          error.message || 'Failed to generate report',
        );
      }
    });
  
    async function generatePDF(config, reportData, shopName, lang, writeStream) {
      return new Promise((resolve, reject) => {
        try {
          const doc = new PDFDocument({
            size: 'A4',
            layout: 'landscape',
            margin: 50,
            bufferPages: false, // ← no longer need to buffer all pages in memory
          });
  
          doc.registerFont('Inter-Regular', regularFontPath);
          doc.registerFont('Inter-Bold', boldFontPath);
    
          // Pipe directly to GCS write stream — no in-memory buffer
          doc.pipe(writeStream);
          writeStream.on('finish', resolve);
          writeStream.on('error', reject);
          doc.on('error', reject);
    
          // --- everything below this line is identical to before ---
    
          const pageWidth = doc.page.width;
          const logoPath = path.join(__dirname, 'siyahlogo.png');
          const logoWidth = 350;
          const logoX = (pageWidth - logoWidth) / 2;
          const logoY = -100;
    
          const textStartY = 370;
          try {
            doc.image(logoPath, logoX, logoY, { width: logoWidth });
          } catch (logoError) {
            console.error('Error loading logo:', logoError);
          }
    
          doc.fontSize(36)
            .font('Inter-Bold')
            .fillColor('#000000')
            .text(shopName, 50, textStartY, { align: 'center', width: pageWidth - 100 });
    
          const reportNameY = textStartY + 60;
          doc.fontSize(24)
            .font('Inter-Regular')
            .text(config.reportName || 'Report', 50, reportNameY, { align: 'center', width: pageWidth - 100 });
    
          const dateY = reportNameY + 80;
          doc.fontSize(12)
            .fillColor('#666666')
            .text(`${t(lang, 'generated')}: ${formatDateTime(new Date(), lang)}`, 50, dateY, { align: 'center', width: pageWidth - 100 });
    
          if (config.dateRange) {
            const startDate = config.dateRange.start.toDate ? config.dateRange.start.toDate() : new Date(config.dateRange.start);
            const endDate = config.dateRange.end.toDate ? config.dateRange.end.toDate() : new Date(config.dateRange.end);
            const dateRangeY = dateY + 20;
            doc.text(`${t(lang, 'dateRange')}: ${formatDate(startDate, lang)} - ${formatDate(endDate, lang)}`, 50, dateRangeY, { align: 'center', width: pageWidth - 100 });
          }
    
          if (config.includeProducts && reportData.products) {
            doc.addPage();
            addSection(doc, t(lang, 'products'), reportData.products,
              [t(lang, 'productName'), t(lang, 'price'), t(lang, 'quantity'), t(lang, 'views'), t(lang, 'sales'), t(lang, 'favorites'), t(lang, 'cartAdds')],
              (item) => [
                item.productName || t(lang, 'notSpecified'),
                `${(Number(item.price) || 0).toFixed(2)} ${item.currency || 'TL'}`,
                String(item.quantity || 0),
                String(item.clickCount || 0),
                String(item.purchaseCount || 0),
                String(item.favoritesCount || 0),
                String(item.cartCount || 0),
              ], lang);
          }
    
          if (config.includeOrders && reportData.orders) {
            doc.addPage();
            addSection(doc, t(lang, 'orders'), reportData.orders,
              [t(lang, 'product'), t(lang, 'buyer'), t(lang, 'quantity'), t(lang, 'price'), t(lang, 'status'), t(lang, 'date')],
              (item) => {
                // Prefer the actual paid unit price (post bulk/bundle discounts).
                // Fallback to raw price for orders created before unitPrice was persisted.
                const paidUnit = (typeof item.unitPrice === 'number') ?
                  item.unitPrice :
                  (Number(item.price) || 0);
                return [
                  item.productName || t(lang, 'notSpecified'),
                  item.buyerName || t(lang, 'notSpecified'),
                  String(item.quantity || 0),
                  `${paidUnit.toFixed(2)} ${item.currency || 'TL'}`,
                  localizeShipmentStatus(item.shipmentStatus, lang),
                  item.timestamp ? formatDate(item.timestamp.toDate(), lang) : t(lang, 'notSpecified'),
                ];
              }, lang);
          }
    
          if (config.includeBoostHistory && reportData.boostHistory) {
            doc.addPage();
            addSection(doc, t(lang, 'boostHistory'), reportData.boostHistory,
              [t(lang, 'item'), t(lang, 'durationMinutes'), t(lang, 'cost'), t(lang, 'impressions'), t(lang, 'clicks'), t(lang, 'date')],
              (item) => [
                item.itemName || t(lang, 'notSpecified'),
                String(item.boostDuration || 0),
                `${(Number(item.boostPrice) || 0).toFixed(2)} ${item.currency || 'TL'}`,
                String(item.impressionsDuringBoost || 0),
                String(item.clicksDuringBoost || 0),
                item.createdAt ? formatDate(item.createdAt.toDate(), lang) : t(lang, 'notSpecified'),
              ], lang);
          }
    
          doc.end();
        } catch (error) {
          reject(error);
        }
      });
    }
  
  // Helper function to add sections to PDF with light background for headers
  function addSection(doc, title, data, headers, rowBuilder, lang) {
    doc.fontSize(18)
      .font('Inter-Bold')
      .fillColor('#000000')
      .text(title, {underline: true});
  
    doc.moveDown();
  
    if (!data || data.length === 0) {
      doc.fontSize(12)
        .font('Inter-Regular')
        .fillColor('#666666')
        .text(t(lang, 'noDataAvailableForSection'));
      return;
    }
  
  // Create table
  const itemsToShow = data.length;
  const columnWidth = (doc.page.width - 100) / headers.length;
  
  // Extracted: draws header row and returns the new y position
  const drawHeaders = (startY) => {
    doc.rect(50, startY - 5, doc.page.width - 100, 25).fillColor('#f0f0f0').fill();
    doc.fontSize(10).font('Inter-Bold').fillColor('#000000');
    headers.forEach((header, i) => {
      doc.text(header, 50 + (i * columnWidth), startY, { width: columnWidth - 5, ellipsis: true });
    });
    const afterHeaders = startY + 20;
    doc.moveTo(50, afterHeaders).lineTo(doc.page.width - 50, afterHeaders).strokeColor('#cccccc').stroke();
    return afterHeaders + 10;
  };
  
  let y = drawHeaders(doc.y);
  
    // Draw rows
    doc.fontSize(9)
      .font('Inter-Regular')
      .fillColor('#333333');
  
    for (let i = 0; i < itemsToShow; i++) {
      const row = rowBuilder(data[i]);
  
     // Check if we need a new page
     if (y > doc.page.height - 100) {
      doc.addPage();
      y = drawHeaders(50);
      doc.fontSize(9).font('Inter-Regular').fillColor('#333333');
    }
  
      let maxRowHeight = 15; // minimum height
      const rowTexts = [];
  
      // First pass: measure text heights
      row.forEach((cell) => {
        const textHeight = doc.heightOfString(cell, {
          width: columnWidth - 5,
        });
        rowTexts.push({text: cell, height: textHeight});
        maxRowHeight = Math.max(maxRowHeight, textHeight + 5); // +5 for padding
      });
  
      // Second pass: draw the text
      rowTexts.forEach((cellData, j) => {
        doc.text(cellData.text, 50 + (j * columnWidth), y, {
          width: columnWidth - 5,
          ellipsis: false, // Remove ellipsis since we're giving proper space
        });
      });
  
      y += maxRowHeight;
    }
  }
  
  // Helper function to localize shipment status
  function localizeShipmentStatus(status, lang) {
    if (!status) return t(lang, 'notSpecified');
  
    const statusKey = `status${status.charAt(0).toUpperCase() + status.slice(1).toLowerCase()}`;
    return t(lang, statusKey) || status;
  }
