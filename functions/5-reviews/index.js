import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
// ===================================
// 1. MAIN FUNCTION - Fast & Simple
// ===================================
export const submitReview = onCall(
    {region: 'europe-west3'},
    async (req) => {
      const auth = req.auth;
      if (!auth) {
        throw new HttpsError('unauthenticated', 'You must be signed in to submit a review.');
      }
  
      const db = admin.firestore();
  
      const {
        isProduct,
        isShopProduct,
        productId,
        sellerId,
        shopId,
        transactionId,
        orderId,
        rating,
        review,
        imageUrls = [],
      } = req.data || {};
  
      // Validation
      if (typeof rating !== 'number' || rating < 1 || rating > 5) {
        throw new HttpsError('invalid-argument', 'Rating must be a number between 1 and 5.');
      }
      if (typeof review !== 'string' || !review.trim()) {
        throw new HttpsError('invalid-argument', 'Review text must be a non-empty string.');
      }
      if (!transactionId || !orderId) {
        throw new HttpsError('invalid-argument', 'Missing transactionId or orderId.');
      }
      if (isProduct && !productId) {
        throw new HttpsError('invalid-argument', 'Missing productId for a product review.');
      }
      if (!isProduct && !sellerId && !shopId) {
        throw new HttpsError('invalid-argument', 'Missing sellerId or shopId for a seller review.');
      }
  
      return db.runTransaction(async (tx) => {
        // ============================================
        // READS
        // ============================================
        
        // Fetch the order item
        const itemRef = db
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .doc(transactionId);
        const itemSnap = await tx.get(itemRef);
        
        if (!itemSnap.exists) {
          throw new HttpsError('not-found', `No order item found for ID ${transactionId}.`);
        }
        const itemData = itemSnap.data();

        if (itemData.deliveryStatus !== 'delivered') {
          throw new HttpsError(
            'failed-precondition',
            'Cannot review an item that has not been delivered yet.'
          );
        }
  
        // Check if review already submitted
        if (isProduct) {
          if (!itemData.needsProductReview) {
            throw new HttpsError('failed-precondition', 'Product review already submitted.');
          }
        } else {
          if (!itemData.needsSellerReview) {
            throw new HttpsError('failed-precondition', 'Seller review already submitted.');
          }
        }
  
        // Get reviewer info
        const reviewerRef = db.collection('users').doc(auth.uid);
        const reviewerSnap = await tx.get(reviewerRef);
        const reviewerData = reviewerSnap.data() || {};
        const reviewerName = reviewerData.displayName || reviewerData.name || 'Anonymous';
  
        // Determine target collection and get seller info
        let actualShopId = null;
        let actualSellerId = null;
        let sellerNameDenorm = '';
        let parentRef;
  
        if (isProduct) {
          const col = isShopProduct ? 'shop_products' : 'products';
          parentRef = db.collection(col).doc(productId);
  
          if (isShopProduct) {
            actualShopId = itemData.shopId;
            const sellerSnap = await tx.get(db.collection('shops').doc(actualShopId));
            sellerNameDenorm = sellerSnap.data()?.name || 'Unknown Shop';
            actualSellerId = actualShopId;
          } else {
            actualSellerId = itemData.sellerId;
            const sellerSnap = await tx.get(db.collection('users').doc(actualSellerId));
            sellerNameDenorm = sellerSnap.data()?.displayName || 'Unknown Seller';
          }
        } else {
          // Seller review
          if (shopId) {
            actualShopId = shopId;
            actualSellerId = shopId;
            parentRef = db.collection('shops').doc(shopId);
            const sellerSnap = await tx.get(parentRef);
            sellerNameDenorm = sellerSnap.data()?.name || 'Unknown Shop';
          } else {
            actualSellerId = sellerId;
            parentRef = db.collection('users').doc(sellerId);
            const sellerSnap = await tx.get(parentRef);
            sellerNameDenorm = sellerSnap.data()?.displayName || 'Unknown Seller';
          }
        }
  
        // ============================================
        // WRITES - Only Critical Data
        // ============================================
  
        // Write the review document
        const reviewsRef = parentRef.collection('reviews').doc(transactionId);
        const reviewDoc = {
          rating,
          review,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          userId: auth.uid,
          userName: reviewerName,
          transactionId,
          orderId,
  
          // Product-specific fields
          productId: isProduct ? productId : null,
          productName: isProduct ? (itemData.productName || 'Unknown Product') : null,
          productImage: isProduct ? (
            itemData.selectedColorImage ||
            itemData.productImage ||
            null
          ) : null,
  
          // Product metadata
          brand: isProduct ? (itemData.brand || null) : null,
          brandModel: isProduct ? (itemData.brandModel || null) : null,
          category: isProduct ? (itemData.category || null) : null,
          subcategory: isProduct ? (itemData.subcategory || null) : null,
          condition: isProduct ? (itemData.condition || null) : null,
  
          // Pricing info
          price: isProduct ? (itemData.price || 0) : null,
          currency: isProduct ? (itemData.currency || 'TL') : null,
  
          // Product rating at time of purchase
          productAverageRatingAtPurchase: isProduct ? (itemData.productAverageRating || 0) : null,
          productReviewCountAtPurchase: isProduct ? (itemData.productReviewCount || 0) : null,
  
          // Seller-specific fields
          sellerId: actualSellerId,
          sellerName: sellerNameDenorm,
          shopId: actualShopId,
          isShopProduct: isShopProduct,
          isProductReview: isProduct,
  
          // Images
          imageUrls: Array.isArray(imageUrls) ? imageUrls : [],
  
          // Selected attributes
          selectedColor: itemData.selectedColor || null,
          selectedSize: itemData.selectedSize || null,
          selectedAttributes: itemData.selectedAttributes || null,
  
          // Purchase context
          quantity: itemData.quantity || 1,
          purchaseTimestamp: itemData.timestamp || null,
  
          // Processing flag
          metricsProcessed: false, // ⬅️ NEW: For idempotency
        };
  
        tx.set(reviewsRef, reviewDoc);
  
        // Clear the "needsReview" flags
        const itemUpdates = {};
        if (isProduct) {
          itemUpdates.needsProductReview = false;
          if (!itemData.needsSellerReview) {
            itemUpdates.needsAnyReview = false;
          }
        } else {
          itemUpdates.needsSellerReview = false;
          if (!itemData.needsProductReview) {
            itemUpdates.needsAnyReview = false;
          }
        }
        tx.update(itemRef, itemUpdates);
  
        return {success: true};
      });
    },
  );
  
  // ===================================
  // 2. METRICS UPDATE TRIGGER
  // ===================================
  export const updateProductMetrics = onDocumentCreated(
    {
      document: 'products/{productId}/reviews/{reviewId}',
      region: 'europe-west3',
    },
    async (event) => {
      const reviewData = event.data?.data();
      if (!reviewData || reviewData.metricsProcessed) {
        return; // Already processed or invalid
      }
  
      const db = admin.firestore();
      const productId = event.params.productId;
      const reviewId = event.params.reviewId;
      const productRef = db.collection('products').doc(productId);
  
      return db.runTransaction(async (tx) => {
        const reviewRef = db.collection('products').doc(productId).collection('reviews').doc(reviewId);
        const reviewSnap = await tx.get(reviewRef);
        
        // Double-check to prevent race conditions
        if (!reviewSnap.exists || reviewSnap.data()?.metricsProcessed) {
          return;
        }
  
        const productSnap = await tx.get(productRef);
        const productData = productSnap.data() || {};
        
        const curAvg = typeof productData.averageRating === 'number' ? productData.averageRating : 0;
        const curCount = typeof productData.reviewCount === 'number' ? productData.reviewCount : 0;
        
        const newCount = curCount + 1;
        const newAvg = (curAvg * curCount + reviewData.rating) / newCount;
  
        // Update product metrics
        tx.update(productRef, {
          averageRating: newAvg,
          reviewCount: newCount,
        });
  
        // Mark as processed
        tx.update(reviewRef, {
          metricsProcessed: true,
        });
      });
    },
  );
  
  // ===================================
  // 3. SHOP PRODUCT METRICS TRIGGER
  // ===================================
  export const updateShopProductMetrics = onDocumentCreated(
    {
      document: 'shop_products/{productId}/reviews/{reviewId}',
      region: 'europe-west3',
    },
    async (event) => {
      const reviewData = event.data?.data();
      if (!reviewData || reviewData.metricsProcessed) {
        return;
      }
  
      const db = admin.firestore();
      const productId = event.params.productId;
      const reviewId = event.params.reviewId;
      const productRef = db.collection('shop_products').doc(productId);
  
      return db.runTransaction(async (tx) => {
        const reviewRef = db.collection('shop_products').doc(productId).collection('reviews').doc(reviewId);
        const reviewSnap = await tx.get(reviewRef);
        
        if (!reviewSnap.exists || reviewSnap.data()?.metricsProcessed) {
          return;
        }
  
        const productSnap = await tx.get(productRef);
        const productData = productSnap.data() || {};
        
        const curAvg = typeof productData.averageRating === 'number' ? productData.averageRating : 0;
        const curCount = typeof productData.reviewCount === 'number' ? productData.reviewCount : 0;
        
        const newCount = curCount + 1;
        const newAvg = (curAvg * curCount + reviewData.rating) / newCount;
  
        tx.update(productRef, {
          averageRating: newAvg,
          reviewCount: newCount,
        });
  
        tx.update(reviewRef, {
          metricsProcessed: true,
        });
      });
    },
  );
  
  // ===================================
  // 4. SELLER METRICS TRIGGER (Shops)
  // ===================================
  export const updateShopMetrics = onDocumentCreated(
    {
      document: 'shops/{shopId}/reviews/{reviewId}',
      region: 'europe-west3',
    },
    async (event) => {
      const reviewData = event.data?.data();
      if (!reviewData || reviewData.metricsProcessed) {
        return;
      }
  
      const db = admin.firestore();
      const shopId = event.params.shopId;
      const reviewId = event.params.reviewId;
      const shopRef = db.collection('shops').doc(shopId);
  
      return db.runTransaction(async (tx) => {
        const reviewRef = db.collection('shops').doc(shopId).collection('reviews').doc(reviewId);
        const reviewSnap = await tx.get(reviewRef);
        
        if (!reviewSnap.exists || reviewSnap.data()?.metricsProcessed) {
          return;
        }
  
        const shopSnap = await tx.get(shopRef);
        const shopData = shopSnap.data() || {};
        
        const curAvg = typeof shopData.averageRating === 'number' ? shopData.averageRating : 0;
        const curCount = typeof shopData.reviewCount === 'number' ? shopData.reviewCount : 0;
        
        const newCount = curCount + 1;
        const newAvg = (curAvg * curCount + reviewData.rating) / newCount;
  
        tx.update(shopRef, {
          averageRating: newAvg,
          reviewCount: newCount,
        });
  
        tx.update(reviewRef, {
          metricsProcessed: true,
        });
      });
    },
  );
  
  // ===================================
  // 5. SELLER METRICS TRIGGER (Users)
  // ===================================
  export const updateUserSellerMetrics = onDocumentCreated(
    {
      document: 'users/{userId}/reviews/{reviewId}',
      region: 'europe-west3',
    },
    async (event) => {
      const reviewData = event.data?.data();
      if (!reviewData || reviewData.metricsProcessed) {
        return;
      }
  
      const db = admin.firestore();
      const userId = event.params.userId;
      const reviewId = event.params.reviewId;
      const userRef = db.collection('users').doc(userId);
  
      return db.runTransaction(async (tx) => {
        const reviewRef = db.collection('users').doc(userId).collection('reviews').doc(reviewId);
        const reviewSnap = await tx.get(reviewRef);
        
        if (!reviewSnap.exists || reviewSnap.data()?.metricsProcessed) {
          return;
        }
  
        const userSnap = await tx.get(userRef);
        const userData = userSnap.data() || {};
        
        const curAvg = typeof userData.averageRating === 'number' ? userData.averageRating : 0;
        const curCount = typeof userData.reviewCount === 'number' ? userData.reviewCount : 0;
        
        const newCount = curCount + 1;
        const newAvg = (curAvg * curCount + reviewData.rating) / newCount;
  
        tx.update(userRef, {
          averageRating: newAvg,
          reviewCount: newCount,
        });
  
        tx.update(reviewRef, {
          metricsProcessed: true,
        });
      });
    },
  );
  
  // ===================================
  // 6. NOTIFICATION TRIGGER
  // ===================================
  export const sendReviewNotifications = onDocumentCreated(
    {
      document: '{collection}/{docId}/reviews/{reviewId}',
      region: 'europe-west3',
    },
    async (event) => {
      const reviewData = event.data?.data();
      if (!reviewData) return;
  
      const db = admin.firestore();
      const collection = event.params.collection;
      
      // Only process valid collections
      if (!['products', 'shop_products', 'shops', 'users'].includes(collection)) {
        return;
      }
  
      // ============================================
      // SHOP-RELATED REVIEWS → shop_notifications
      // ============================================
      const isShopReview = 
        (reviewData.isProductReview && reviewData.isShopProduct && reviewData.shopId) ||
        (!reviewData.isProductReview && reviewData.shopId);
  
      if (isShopReview) {
        const shopSnap = await db.collection('shops').doc(reviewData.shopId).get();
        
        if (!shopSnap.exists) {
          console.log(`Shop ${reviewData.shopId} not found`);
          return;
        }
  
        const shopData = shopSnap.data();
  
        // Build isRead map for all members (excluding reviewer)
        const isReadMap = {};
        const addMember = (id) => {
          if (id && typeof id === 'string' && id !== reviewData.userId) {
            isReadMap[id] = false;
          }
        };
  
        addMember(shopData.ownerId);
        if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach(addMember);
        if (Array.isArray(shopData.editors)) shopData.editors.forEach(addMember);
        if (Array.isArray(shopData.viewers)) shopData.viewers.forEach(addMember);
  
        if (Object.keys(isReadMap).length === 0) {
          console.log('No recipients to notify');
          return;
        }
  
        // Determine notification type
        const notificationType = reviewData.isProductReview ? 
          'product_review_shop' : 
          'seller_review_shop';
  
        // ✅ Write to shop_notifications (triggers sendShopNotificationOnCreation)
        await db.collection('shop_notifications').add({
          type: notificationType,
          shopId: reviewData.shopId,
          shopName: shopData.name || '',
          productId: reviewData.productId || null,
          productName: reviewData.productName || null,
          reviewerId: reviewData.userId,
          reviewerName: reviewData.userName,
          rating: reviewData.rating,
          reviewText: reviewData.review?.substring(0, 200) || '',
          transactionId: reviewData.transactionId,
          orderId: reviewData.orderId,
          isProductReview: reviewData.isProductReview,
          isRead: isReadMap,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          message_en: reviewData.isProductReview ?
            `New ${reviewData.rating}★ review for "${reviewData.productName}"` :
            `New ${reviewData.rating}★ seller review`,
          message_tr: reviewData.isProductReview ?
            `"${reviewData.productName}" için yeni ${reviewData.rating}★ değerlendirme` :
            `Yeni ${reviewData.rating}★ satıcı değerlendirmesi`,
          message_ru: reviewData.isProductReview ?
            `Новый отзыв ${reviewData.rating}★ для "${reviewData.productName}"` :
            `Новый отзыв продавца ${reviewData.rating}★`,
        });
  
        console.log(`✅ Shop notification created for ${Object.keys(isReadMap).length} members`);
        return;
      }
  
      // ============================================
      // USER-RELATED REVIEWS → users/{uid}/notifications
      // ============================================
      let recipientId = null;
      let notificationType = '';
  
      if (reviewData.isProductReview && reviewData.sellerId) {
        recipientId = reviewData.sellerId;
        notificationType = 'product_review_user';
      } else if (!reviewData.isProductReview && reviewData.sellerId) {
        recipientId = reviewData.sellerId;
        notificationType = 'seller_review_user';
      }
  
      // Skip if no recipient or reviewer is the recipient
      if (!recipientId || recipientId === reviewData.userId) {
        return;
      }
  
      await db.collection('users').doc(recipientId).collection('notifications').add({
        type: notificationType,
        productId: reviewData.productId,
        productName: reviewData.productName,
        sellerId: reviewData.sellerId,
        reviewerId: reviewData.userId,
        reviewerName: reviewData.userName,
        rating: reviewData.rating,
        reviewText: reviewData.review?.substring(0, 200) || '',
        transactionId: reviewData.transactionId,
        orderId: reviewData.orderId,
        isProductReview: reviewData.isProductReview,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        message_en: reviewData.isProductReview ?
          `New ${reviewData.rating}★ review for "${reviewData.productName}"` :
          `New ${reviewData.rating}★ seller review`,
        message_tr: reviewData.isProductReview ?
          `"${reviewData.productName}" için yeni ${reviewData.rating}★ değerlendirme` :
          `Yeni ${reviewData.rating}★ satıcı değerlendirmesi`,
        message_ru: reviewData.isProductReview ?
          `Новый отзыв ${reviewData.rating}★ для "${reviewData.productName}"` :
          `Новый отзыв продавца ${reviewData.rating}★`,
      });
  
      console.log(`✅ User notification created for ${recipientId}`);
    },
  );
