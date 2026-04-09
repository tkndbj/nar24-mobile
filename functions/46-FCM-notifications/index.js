import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import admin from 'firebase-admin';
import {getMessaging} from 'firebase-admin/messaging';

export const TEMPLATES = {
    en: {
      // Notification types
      product_out_of_stock: {
        title: 'Out of Stock ⚠️',
        body: 'Your product is out of stock.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Shop Item Out of Stock ⚠️',
        body: 'A product is out of stock in your shop.',
      },
      boost_expired: {
        title: 'Boost Expired ⚠️',
        body: 'Your boost has expired.',
      },
      product_archived_by_admin: {
        title: 'Product Paused ⚠️',
        body: '"{productName}" was paused by admin',
      },
      product_review_shop: {
        title: 'New Product Review ⭐',
        body: 'Your product "{productName}" received a new review',
      },
      product_review_user: {
        title: 'New Product Review ⭐',
        body: 'Your product "{productName}" received a new review',
      },
      seller_review_shop: {
        title: 'New Shop Review ⭐',
        body: 'Your shop received a new review',
      },
      seller_review_user: {
        title: 'New Seller Review ⭐',
        body: 'You received a new seller review',
      },
      product_sold: {
        title: 'Product Sold! 🎉',
        body: 'Your product "{productName}" has been sold!',
      },
      product_sold_user: {
        title: 'Продукт Продан! 🎉',
        body: 'Ваш продукт "{productName}" был продан!',
      },
      campaign_ended: {
        title: 'Campaign Ended 🏁',
        body: 'Campaign "{campaignName}" has ended',
      },
      shipment_update: {
        title: 'Shipment Status Updated! ✅',
        body: 'Your shipment status has been updated!',
      },
      campaign: {
        title: '🎉 New Campaign: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'New Product Question 💬',
        body: 'Someone asked a question about your product: {productName}',
      },
      shop_invitation: {
        title: 'Shop Invitation 🏪',
        body: 'You have been invited to join {shopName} as {role}',
      },
      ad_expired: {
        title: 'Ad Expired ⚠️',
        body: 'Your ad for {shopName} has expired.',
      },
      ad_approved: {
        title: 'Ad Approved! 🎉',
        body: 'Your ad for {shopName} has been approved. Click to proceed with payment.',
      },
      ad_rejected: {
        title: 'Ad Rejected ❌',
        body: 'Your ad for {shopName} was rejected. Reason: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'Refund Request Approved ✅',
        body: 'Your refund request for receipt #{receiptNo} has been approved.',
      },
      refund_request_rejected: {
        title: 'Refund Request Rejected ❌',
        body: 'Your refund request for receipt #{receiptNo} has been rejected.',
      },
      order_delivered: {
        title: 'Order Delivered! 📦✨',
        body: 'Your order has been delivered! Tap to share your experience.',
      },
      product_question_answered: {
        title: 'Question Answered! 💬',
        body: 'Your question about "{productName}" has been answered!',
      },
      new_food_order: {
        title: 'New Order! 🍽️',
        body: 'A new order has been placed.',
      },
      food_order_status_update_accepted: {
        title: 'Order Accepted! ✅',
        body: '{restaurantName} has accepted your order.',
      },
      food_order_status_update_rejected: {
        title: 'Order Rejected ❌',
        body: '{restaurantName} has rejected your order.',
      },
      food_order_status_update_preparing: {
        title: 'Being Prepared! 🍳',
        body: '{restaurantName} is now preparing your order.',
      },
      food_order_status_update_ready: {
        title: 'Order Ready! 📦',
        body: 'Your order from {restaurantName} is ready!',
      },
      food_order_status_update_delivered: {
        title: 'Order Delivered! 🎉',
        body: 'Your order from {restaurantName} has been delivered.',
      },
      food_order_delivered_review: {
        title: 'Order Delivered! 🎉',
        body: 'Your order from {restaurantName} has arrived. Tap to leave a review!',
      },
      restaurant_new_review: {
        title: 'New Review! ⭐',
        body: 'One of your customers left a {rating}-star review.',
      },
      default: {
        title: 'New Notification',
        body: 'You have a new notification!',
      },
    },
  
    tr: {
      product_out_of_stock: {
        title: 'Ürün Stoğu Tükendi ⚠️',
        body: 'Ürününüz stokta kalmadı.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Mağaza Ürünü Stoğu Tükendi ⚠️',
        body: 'Mağanızdaki bir ürün stokta kalmadı.',
      },
      boost_expired: {
        title: 'Boost Süresi Doldu ⚠️',
        body: 'Öne çıkarılan ürünün süresi doldu.',
      },
      product_archived_by_admin: {
        title: 'Ürün Durduruldu ⚠️',
        body: '"{productName}" admin tarafından durduruldu',
      },
      product_review_shop: {
        title: 'Yeni Ürün Değerlendirmesi ⭐',
        body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
      },
      product_review_user: {
        title: 'Yeni Ürün Değerlendirmesi ⭐',
        body: 'Ürününüz "{productName}" yeni bir değerlendirme aldı',
      },
      seller_review_shop: {
        title: 'Yeni Mağaza Değerlendirmesi ⭐',
        body: 'Mağazanız yeni bir değerlendirme aldı',
      },
      seller_review_user: {
        title: 'Yeni Satıcı Değerlendirmesi ⭐',
        body: 'Yeni bir satıcı değerlendirmesi aldınız',
      },
      product_sold: {
        title: 'Mağaza Ürünü Satıldı! 🎉',
        body: 'Ürününüz "{productName}" satıldı!',
      },
      product_sold_user: {
        title: 'Ürün Satıldı! 🎉',
        body: 'Ürününüz "{productName}" satıldı!',
      },
      campaign_ended: {
        title: 'Kampanya Bitti 🏁',
        body: '"{campaignName}" kampanyası sona erdi',
      },
      shipment_update: {
        title: 'Gönderi Durumu Güncellendi! ✅',
        body: 'Gönderi durumunuz güncellendi!',
      },
      campaign: {
        title: '🎉 Yeni Kampanya: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'Yeni Ürün Sorusu 💬',
        body: 'Ürününüz hakkında soru soruldu: {productName}',
      },
      shop_invitation: {
        title: 'Mağaza Daveti 🏪',
        body: '{shopName} mağazasına {role} olarak katılmaya davet edildiniz',
      },
      ad_expired: {
        title: 'Reklam Süresi Doldu ⚠️',
        body: '{shopName} reklamınızın süresi doldu.',
      },
      ad_approved: {
        title: 'Reklam Onaylandı! 🎉',
        body: '{shopName} için reklamınız onaylandı. Ödeme yapmak için tıklayın.',
      },
      ad_rejected: {
        title: 'Reklam Reddedildi ❌',
        body: '{shopName} için reklamınız reddedildi. Neden: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'İade Talebi Onaylandı ✅',
        body: 'Fiş no #{receiptNo} için iade talebiniz onaylandı.',
      },
      refund_request_rejected: {
        title: 'İade Talebi Reddedildi ❌',
        body: 'Fiş no #{receiptNo} için iade talebiniz reddedildi.',
      },
      order_delivered: {
        title: 'Sipariş Teslim Edildi! 📦✨',
        body: 'Siparişiniz teslim edildi! Deneyiminizi paylaşmak için dokunun.',
      },
      product_question_answered: {
        title: 'Soru Yanıtlandı! 💬',
        body: '"{productName}" hakkındaki sorunuz yanıtlandı!',
      },
      new_food_order: {
        title: 'Yeni Sipariş! 🍽️',
        body: 'Yeni sipariş verildi.',
      },
      food_order_status_update_accepted: {
        title: 'Sipariş Onaylandı! ✅',
        body: '{restaurantName} siparişinizi onayladı.',
      },
      food_order_status_update_rejected: {
        title: 'Sipariş Reddedildi ❌',
        body: '{restaurantName} siparişinizi reddetti.',
      },
      food_order_status_update_preparing: {
        title: 'Hazırlanıyor! 🍳',
        body: '{restaurantName} siparişinizi hazırlamaya başladı.',
      },
      food_order_status_update_ready: {
        title: 'Sipariş Hazır! 📦',
        body: '{restaurantName} siparişiniz teslimata hazır!',
      },
      food_order_status_update_delivered: {
        title: 'Sipariş Teslim Edildi! 🎉',
        body: '{restaurantName} siparişiniz teslim edildi.',
      },
      food_order_delivered_review: {
        title: 'Sipariş Teslim Edildi! 🎉',
        body: '{restaurantName} siparişiniz ulaştı. Değerlendirme yapmak için tıklayın!',
      },
      restaurant_new_review: {
        title: 'Yeni Değerlendirme! ⭐',
        body: 'Bir müşteriniz {rating} yıldız verdi.',
      },
      default: {
        title: 'Yeni Bildirim',
        body: 'Yeni bir bildiriminiz var!',
      },
    },
  
    ru: {
      product_out_of_stock: {
        title: 'Товар Распродан',
        body: 'Ваш продукт “{productName}” распродан.',
      },
      product_out_of_stock_seller_panel: {
        title: 'Запасы Магазина Исчерпаны',
        body: 'Товар “{productName}” отсутствует в вашем магазине.',
      },
      boost_expired: {
        title: 'Срок Буста Истек',
        body: 'Время действия буста “{itemType}” истекло.',
      },
      product_archived_by_admin: {
        title: 'Продукт приостановлен ⚠️',
        body: '"{productName}" приостановлен администратором',
      },
      product_review_shop: {
        title: 'Новый Отзыв о Продукте ⭐',
        body: 'Ваш продукт "{productName}" получил новый отзыв',
      },
      product_review_user: {
        title: 'Новый Отзыв о Продукте ⭐',
        body: 'Ваш продукт "{productName}" получил новый отзыв',
      },
      seller_review_shop: {
        title: 'Новый Отзыв о Магазине ⭐',
        body: 'Ваш магазин получил новый отзыв',
      },
      seller_review_user: {
        title: 'Новый Отзыв Продавца ⭐',
        body: 'Вы получили новый отзыв продавца',
      },
      product_sold: {
        title: 'Товар Магазина Продан! 🎉',
        body: 'Ваш товар "{productName}" был продан!',
      },
      product_sold_user: {
        title: 'Продукт Продан! 🎉',
        body: 'Ваш продукт "{productName}" был продан!',
      },
      campaign_ended: {
        title: 'Кампания завершена 🏁',
        body: 'Кампания "{campaignName}" завершена',
      },
      shipment_update: {
        title: 'Статус Доставки Обновлен!',
        body: 'Статус вашей доставки был обновлен!',
      },
      campaign: {
        title: '🎉 Новая Кампания: {campaignName}',
        body: '{campaignDescription}',
      },
      product_question: {
        title: 'Новый Вопрос о Продукте 💬',
        body: 'Кто-то задал вопрос о вашем продукте: {productName}',
      },
      shop_invitation: {
        title: 'Приглашение в Магазин 🏪',
        body: 'Вас пригласили присоединиться к {shopName} как {role}',
      },
      ad_expired: {
        title: 'Срок Рекламы Истек ⚠️',
        body: 'Срок действия вашего объявления для {shopName} истек.',
      },
      ad_approved: {
        title: 'Реклама Одобрена! 🎉',
        body: 'Ваше объявление для {shopName} было одобрено. Нажмите, чтобы перейти к оплате.',
      },
      ad_rejected: {
        title: 'Реклама Отклонена ❌',
        body: 'Ваше объявление для {shopName} было отклонено. Причина: {rejectionReason}',
      },
      refund_request_approved: {
        title: 'Запрос на Возврат Одобрен ✅',
        body: 'Ваш запрос на возврат для чека #{receiptNo} был одобрен.',
      },
      refund_request_rejected: {
        title: 'Запрос на Возврат Отклонен ❌',
        body: 'Ваш запрос на возврат для чека #{receiptNo} был отклонен.',
      },
      order_delivered: {
        title: 'Заказ доставлен! 📦✨',
        body: 'Ваш заказ доставлен! Нажмите, чтобы поделиться впечатлениями.',
      },
      product_question_answered: {
        title: 'Вопрос Отвечен! 💬',
        body: 'На ваш вопрос о "{productName}" ответили!',
      },
      new_food_order: {
        title: 'Новый заказ! 🍽️',
        body: 'Был размещен новый заказ.',
      },
      food_order_status_update_accepted: {
        title: 'Заказ принят! ✅',
        body: '{restaurantName} принял ваш заказ.',
      },
      food_order_status_update_rejected: {
        title: 'Заказ отклонён ❌',
        body: '{restaurantName} отклонил ваш заказ.',
      },
      food_order_status_update_preparing: {
        title: 'Готовится! 🍳',
        body: '{restaurantName} начал готовить ваш заказ.',
      },
      food_order_status_update_ready: {
        title: 'Заказ готов! 📦',
        body: 'Ваш заказ из {restaurantName} готов!',
      },
      food_order_status_update_delivered: {
        title: 'Заказ доставлен! 🎉',
        body: 'Ваш заказ из {restaurantName} доставлен.',
      }, 
      food_order_delivered_review: {
        title: 'Заказ доставлен! 🎉',
        body: 'Ваш заказ из {restaurantName} прибыл. Нажмите, чтобы оставить отзыв!',
      },
      restaurant_new_review: {
        title: 'Новый отзыв! ⭐',
        body: 'Один из ваших клиентов оставил оценку {rating} звезды.',
      },  
      default: {
        title: 'Новое Уведомление',
        body: 'У вас новое уведомление!',
      },
    },
  };
  
  export const sendNotificationOnCreation = onDocumentCreated({
    region: 'europe-west3',
    document: 'users/{userId}/notifications/{notificationId}',
    maxInstances: 100,
  }, async (event) => {
    const snap = event.data;
    const notificationData = snap.data();
    const {userId, notificationId} = event.params;
  
    if (!notificationData) {
      console.log('No notification data, exiting.');
      return;
    }
  
    // 1) Load the user's FCM tokens and locale
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    const userData = userDoc.data() || {};
    const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];
    if (tokens.length === 0) {
      console.log(`No FCM tokens for user ${userId}.`);
      return;
    }
    const locale = userData.languageCode || 'en';
  
    // 2) Pick and interpolate the template
    const localeSet = TEMPLATES[locale] || TEMPLATES.en;
    const originalType = notificationData.type || 'default';
    let type = originalType;
    if (type === 'food_order_status_update' && notificationData.payload?.orderStatus) {
      type = `food_order_status_update_${notificationData.payload.orderStatus}`;
    }
    const tmpl = localeSet[type] || localeSet.default;
  
    let title = tmpl.title;
    let body = tmpl.body;
    if (notificationData.productName) {
      title = title.replace('{productName}', notificationData.productName);
      body = body .replace('{productName}', notificationData.productName);
    }
    if (notificationData.itemType) {
      title = title.replace('{itemType}', notificationData.itemType);
      body = body .replace('{itemType}', notificationData.itemType);
    }
    if (notificationData.campaignName) {
      title = title.replace('{campaignName}', notificationData.campaignName);
      body = body.replace('{campaignName}', notificationData.campaignName);
    }
    if (notificationData.campaignDescription) {
      title = title.replace('{campaignDescription}', notificationData.campaignDescription);
      body = body.replace('{campaignDescription}', notificationData.campaignDescription);
    }
    if (notificationData.shopName) {
      title = title.replace('{shopName}', notificationData.shopName);
      body = body.replace('{shopName}', notificationData.shopName);
    }
    if (notificationData.role) {
      title = title.replace('{role}', notificationData.role);
      body = body.replace('{role}', notificationData.role);
    }
    if (notificationData.adTypeLabel) {
      title = title.replace('{adTypeLabel}', notificationData.adTypeLabel);
      body = body.replace('{adTypeLabel}', notificationData.adTypeLabel);
    }
    if (notificationData.rejectionReason) {
      title = title.replace('{rejectionReason}', notificationData.rejectionReason);
      body = body.replace('{rejectionReason}', notificationData.rejectionReason);
    }
    if (notificationData.receiptNo) {
      title = title.replace('{receiptNo}', notificationData.receiptNo);
      body = body.replace('{receiptNo}', notificationData.receiptNo);
    }
    const payload = notificationData.payload || {};
  if (payload.restaurantName) {
    title = title.replace('{restaurantName}', payload.restaurantName);
    body  = body .replace('{restaurantName}', payload.restaurantName);
  }
  if (payload.orderStatus) {
    title = title.replace('{orderStatus}', payload.orderStatus);
    body  = body .replace('{orderStatus}', payload.orderStatus);
  }
  if (payload.orderId) {
    title = title.replace('{orderId}', payload.orderId);
    body  = body .replace('{orderId}', payload.orderId);
  }
  
    // 3) Compute the deep-link route for GoRouter
    //    (defaults to your in-app notifications list)
    let route = '/notifications';
    switch (originalType) {
    case 'product_out_of_stock':
      route = '/myproducts';
      break;
    case 'product_out_of_stock_seller_panel':
      if (notificationData.shopId) {
        route = `/seller-panel?shopId=${notificationData.shopId}&tab=2`;
      }
      break;
      case 'order_delivered':
        route = '/notifications';
        break;
      case 'boost_expired':
        route = '/notifications'; // User can tap the notification from the list
        break;
    case 'product_review_shop':
      if (notificationData.shopId) {
        route = `/seller_panel_reviews/${notificationData.shopId}`;
      }
      break;
      case 'food_order_delivered_review':
        route = payload.orderId ? `/food-order-detail/${payload.orderId}` : '/orders?tab=food';
        break;
        case 'food_order_status_update':
          route = '/my_food_orders';
          break;
    case 'product_review_user':
      if (notificationData.productId) {
        route = `/product/${notificationData.productId}`; 
      }
      break;
    case 'seller_review_shop':
      if (notificationData.shopId) {
        route = `/seller_panel_reviews/${notificationData.shopId}`;
      }
      break;
      case 'product_question_answered':
        route = '/user-product-questions';
        break;
    case 'ad_approved':
      route = '/notifications'; // User needs to see notification to click payment button
      break;
    case 'ad_rejected':
      route = '/notifications'; // User needs to see rejection reason
      break;
    case 'ad_expired':
      if (notificationData.shopId) {
        route = `/seller-panel?shopId=${notificationData.shopId}&tab=5`;
      }
      break;
    case 'seller_review_user':
      if (notificationData.sellerId) {
        route = `/seller_reviews/${notificationData.sellerId}`;
      }
      break;
    
    case 'product_sold_user':
      route = '/my_orders?tab=1';
      break;
    case 'shop_invitation':
      route = '/notifications';
      break;
  
    case 'campaign':
      route = '/seller-panel?tab=0';
      break;
    case 'product_question':
      if (notificationData.isShopProduct && notificationData.shopId) {
        route = `/seller_panel_product_questions/${notificationData.shopId}`;
      } else {
        route = '/user-product-questions';
      }
      break;
    case 'refund_request':
      route = '/notifications'; // User needs to see the notification details
      break;
      // default already '/notifications'
    }
  
    // 4) Build the data payload (including our new `route`)
    const dataPayload = {
      notificationId: String(notificationId),
      route,
    };
    Object.entries(notificationData).forEach(([key, value]) => {
      dataPayload[key] = typeof value === 'string' ?
        value :
        JSON.stringify(value);
    });
  
    // 5) Construct and send the multicast message
    const message = {
      tokens,
      notification: {title, body},
      data: dataPayload,
      android: {
        priority: 'high',
        notification: {
          channelId: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
            'food_orders_high' :
            'high_importance_channel',
          sound: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
            'order_alert' :
            'default',
          icon: 'ic_notification',
        },
      },
      apns: {
        headers: {'apns-priority': '10'},
        payload: { aps: {
          sound: originalType === 'food_order_delivered_review' || originalType === 'food_order_status_update' ?
            'order_alert.caf' :
            'default',
          badge: 1,
        }},
      },
    };
  
    console.log(
      `→ Sending localized notification (${locale}/${type}) to ${tokens.length} tokens`,
      {title, body, route},
    );
  
    let batchResponse;
    try {
      batchResponse = await getMessaging().sendEachForMulticast(message);
      console.log(
        `FCM: ${batchResponse.successCount}/${tokens.length} delivered, ${batchResponse.failureCount} failed`,
      );
    } catch (err) {
      console.error('FCM send error', err);
      throw err;
    }
  
    // 6) Clean up invalid tokens
    const badTokens = [];
    batchResponse.responses.forEach((resp, i) => {
      if (resp.error) {
        const code = resp.error.code;
        if (
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/registration-token-not-registered'
        ) {
          badTokens.push(tokens[i]);
        }
      }
    });
    if (badTokens.length) {
      console.log('Removing invalid tokens:', badTokens);
      const updates = {};
      badTokens.forEach((token) => {
        updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
      });
      await admin.firestore()
        .doc(`users/${userId}`)
        .update(updates);
    }
  });
  
  export const sendRestaurantNotificationOnCreation = onDocumentCreated({  
    region: 'europe-west3',
    document: 'restaurant_notifications/{notificationId}',
    memory: '512MiB',
    maxInstances: 100,
    timeoutSeconds: 60,
  }, async (event) => {
    const snap = event.data;
    const notificationData = snap?.data();
    const { notificationId } = event.params;
  
    if (!notificationData) {
      console.log('No notification data, exiting.');
      return;
    }
  
    const ownerId = notificationData.restaurantOwnerId;
    if (!ownerId) {
      console.log('No restaurantOwnerId in notification, exiting.');
      return;
    }
  
    // Idempotency guard
    const notifRef = admin.firestore()
      .collection('restaurant_notifications')
      .doc(notificationId);
  
    try {
      const shouldProcess = await admin.firestore().runTransaction(async (tx) => {
        const doc = await tx.get(notifRef);
        if (doc.data()?.fcmSent === true) return false;
        tx.update(notifRef, { fcmSent: true });
        return true;
      });
  
      if (!shouldProcess) {
        console.log(`FCM already sent for restaurant notification ${notificationId}, skipping.`);
        return;
      }
    } catch (error) {
      console.error(`Idempotency check failed for ${notificationId}:`, error);
      return;
    }
  
    // Load owner's FCM tokens and locale
    const userDoc = await admin.firestore().doc(`users/${ownerId}`).get();
    const userData = userDoc.data() || {};
    const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];
  
    if (tokens.length === 0) {
      console.log(`No FCM tokens for restaurant owner ${ownerId}.`);
      return;
    }
  
    const locale = ['en', 'tr', 'ru'].includes(userData.languageCode) ? userData.languageCode : 'en';
  
    // Pick and interpolate template
    const type = notificationData.type || 'default';
    const localeSet = TEMPLATES[locale] || TEMPLATES.en;
    const tmpl = localeSet[type] || localeSet.default;
  
    let title = tmpl.title;
    let body  = tmpl.body;
  
    const replacements = {
      '{buyerName}': notificationData.buyerName,
      '{itemCount}': notificationData.itemCount,
      '{totalPrice}': notificationData.totalPrice,
      '{restaurantName}': notificationData.restaurantName,
      '{orderId}': notificationData.orderId,
      '{rating}': notificationData.rating,
    };
  
    Object.entries(replacements).forEach(([placeholder, value]) => {
      if (value !== undefined && value !== null) {
        title = title.replace(placeholder, String(value));
        body  = body .replace(placeholder, String(value));
      }
    });
  
    let route;
    const restaurantId = notificationData.restaurantId ?? '';
    
    if (type === 'new_food_order') {
      // Opens SellerPanel → restaurant mode → tab 1 (FoodOrdersTab)
      route = `/seller-panel?shopId=${restaurantId}&tab=1`;
    } else if (type === 'restaurant_new_review') {
      // Opens SellerPanel → restaurant mode → tab 2 (RestaurantReviewsTab)
      route = `/seller-panel?shopId=${restaurantId}&tab=2`;
    } else {
      // Fallback for any future restaurant notification types
      route = restaurantId ? `/seller-panel?shopId=${restaurantId}&tab=0` : '/seller-panel';
    }
  
    // Data payload
    const dataPayload = {
      notificationId: String(notificationId),
      route,
      type,
    };
    Object.entries(notificationData).forEach(([key, value]) => {
      if (key === 'isRead' || key === 'timestamp' || key === 'route') return;
      dataPayload[key] = typeof value === 'string' ? value : JSON.stringify(value);
    });
  
    // Send — batch if somehow >500 tokens (defensive)
    const FCM_BATCH_SIZE = 500;
    let successCount = 0;
    let failureCount = 0;
    const badTokens = [];
  
    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
      const batch = tokens.slice(i, i + FCM_BATCH_SIZE);
      const message = {
        tokens: batch,
        notification: { title, body },
        data: dataPayload,
        android: {
          priority: 'high',
          notification: {
            channelId: type === 'new_food_order' || type === 'restaurant_new_review' ?
              'food_orders_high' :
              'high_importance_channel',
            sound: type === 'new_food_order' || type === 'restaurant_new_review' ?
              'order_alert' :
              'default',
            icon: 'ic_notification',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: {
            sound: type === 'new_food_order' || type === 'restaurant_new_review' ?
              'order_alert.caf' :
              'default',
            badge: 1,
          }},
        },
      };
  
      try {
        const batchResponse = await getMessaging().sendEachForMulticast(message);
        successCount += batchResponse.successCount;
        failureCount += batchResponse.failureCount;
  
        batchResponse.responses.forEach((resp, idx) => {
          if (resp.error) {
            const code = resp.error.code;
            if (
              code === 'messaging/invalid-registration-token' ||
              code === 'messaging/registration-token-not-registered'
            ) {
              badTokens.push(batch[idx]);
            }
          }
        });
      } catch (err) {
        console.error('FCM send error for restaurant notification:', err);
        failureCount += batch.length;
      }
    }
  
    // Update stats
    await notifRef.update({
      fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
      fcmStats: { successCount, failureCount, totalTokens: tokens.length },
    });
  
    // Clean up bad tokens
    if (badTokens.length > 0) {
      const updates = {};
      badTokens.forEach((token) => {
        updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
      });
      await admin.firestore().doc(`users/${ownerId}`).update(updates).catch((err) => {
        console.error('Failed to clean bad tokens:', err);
      });
    }
  
    console.log(
      `Restaurant notification ${notificationId} (${type}) → ${successCount} sent, ${failureCount} failed`
    );
  });
  
  function getWebRoute(type, shopId, orderId) {
    switch (type) {
      case 'product_sold':
        return '/orders';
      case 'product_out_of_stock_seller_panel':
        return '/stock';
      case 'product_review_shop':
      case 'seller_review_shop':
        return `/reviews/${shopId}`;
      case 'product_question':
        return `/productquestions/${shopId}`;
      case 'product_archived_by_admin':
        return `/archived/${shopId}`;
      case 'boost_expired':
        return '/boostanalysis';
      case 'ad_approved':
      case 'ad_rejected':
      case 'ad_expired':
        return `/homescreen-ads`;
      default:
        return '/dashboard';
    }
  }
  
  export const sendShopNotificationOnCreation = onDocumentCreated({  
    region: 'europe-west3',
    document: 'shop_notifications/{notificationId}',
    memory: '256MiB',
    maxInstances: 100,
    timeoutSeconds: 60,
  }, async (event) => {
    const snap = event.data;
    const notificationData = snap?.data();
    const { notificationId } = event.params;
  
    if (!notificationData) {
      console.log('No notification data, exiting.');
      return;
    }
  
    const shopId = notificationData.shopId;
    if (!shopId) {
      console.log('No shopId in notification, exiting.');
      return;
    }
  
    // Atomic idempotency check - prevent duplicate sends on retry
    const notificationRef = admin.firestore().collection('shop_notifications').doc(notificationId);
    
    try {
      const shouldProcess = await admin.firestore().runTransaction(async (transaction) => {
        const currentDoc = await transaction.get(notificationRef);
        
        if (currentDoc.data()?.fcmSent === true) {
          // Already sent, skip
          return false;
        }
        
        // Mark as sent atomically BEFORE processing to prevent duplicates
        transaction.update(notificationRef, { fcmSent: true });
        return true;
      });
  
      if (!shouldProcess) {
        console.log(`FCM already sent for ${notificationId}, skipping.`);
        return;
      }
    } catch (error) {
      // If transaction fails (e.g., doc doesn't exist), log and exit
      console.error(`Idempotency transaction failed for ${notificationId}:`, error);
      return;
    }
  
    // 1) Get shop to find all members
    const shopDoc = await admin.firestore().doc(`shops/${shopId}`).get();
    const shopData = shopDoc.data();
    if (!shopData) {
      console.log(`Shop ${shopId} not found.`);
      return;
    }
  
    // 2) Collect all member IDs
    const memberIds = new Set();
    if (shopData.ownerId) memberIds.add(shopData.ownerId);
    if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach((id) => memberIds.add(id));
    if (Array.isArray(shopData.editors)) shopData.editors.forEach((id) => memberIds.add(id));
    if (Array.isArray(shopData.viewers)) shopData.viewers.forEach((id) => memberIds.add(id));
  
    if (memberIds.size === 0) {
      console.log(`No members found for shop ${shopId}.`);
      return;
    }
  
    console.log(`Found ${memberIds.size} members for shop ${shopId}`);
  
    // 3) Fetch all members' user documents in parallel
    const memberDocs = await Promise.all(
      Array.from(memberIds).map((id) => admin.firestore().doc(`users/${id}`).get())
    );
  
    // 4) Group tokens by locale for efficient batch sending
    const tokensByLocale = {
      en: [],
      tr: [],
      ru: [],
    };
  
    const tokenToUserMap = new Map(); // For cleanup later
  
    for (const doc of memberDocs) {
      if (!doc.exists) continue;
      const userData = doc.data();
      const tokens = userData.fcmTokens && typeof userData.fcmTokens === 'object' ? Object.keys(userData.fcmTokens) : [];
      
      if (tokens.length === 0) continue;
  
      const locale = userData.languageCode || 'en';
      const validLocale = ['en', 'tr', 'ru'].includes(locale) ? locale : 'en';
  
      tokens.forEach((token) => {
        tokensByLocale[validLocale].push(token);
        tokenToUserMap.set(token, doc.id);
      });
    }
  
    const totalTokens = Object.values(tokensByLocale).flat().length;
    if (totalTokens === 0) {
      console.log('No FCM tokens found for any shop members.');
      await notificationRef.update({ 
        fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
        fcmStats: { successCount: 0, failureCount: 0, totalTokens: 0 },
      });
      return;
    }
  
    console.log(`Sending to ${totalTokens} tokens across ${memberIds.size} members`);
  
    // 5) Determine route for deep linking
    const type = notificationData.type || 'default';
    let route = `/seller-panel?shopId=${shopId}`;
    
    switch (type) {
      case 'product_sold':
        route = `/seller-panel?shopId=${shopId}&tab=3`;
        break;
      case 'product_review_shop':
      case 'seller_review_shop':
        route = `/seller_panel_reviews/${shopId}`;
        break;
      case 'product_question':
        route = `/seller_panel_product_questions/${shopId}`;
        break;
      case 'product_out_of_stock_seller_panel':
        route = `/seller-panel?shopId=${shopId}&tab=2`;
        break;
      case 'boost_expired':
        route = `/seller-panel?shopId=${shopId}&tab=5`;
        break;
        case 'product_archived_by_admin':
    route = `/seller_panel_archived_screen`;
    break;
      case 'campaign_ended':
        route = `/seller-panel?shopId=${shopId}&tab=0`;
        break;
      case 'ad_approved':
      case 'ad_rejected':
      case 'ad_expired':
        route = `/seller-panel?shopId=${shopId}&tab=5`; 
        break;
    }
  
    // Web URL for click action (computed once)
    const webBaseUrl = 'https://nar24panel.com';
    const webRoute = getWebRoute(type, shopId, notificationData.orderId);
    const webClickAction = `${webBaseUrl}${webRoute}`;
  
    // 6) Build data payload
    const dataPayload = {
      notificationId: String(notificationId),
      route,
      shopId,
      type,
      webRoute,
    };
    
    Object.entries(notificationData).forEach(([key, value]) => {
      if (key === 'isRead' || key === 'timestamp') return;
      dataPayload[key] = typeof value === 'string' ? value : JSON.stringify(value);
    });
  
    // 7) Send notifications grouped by locale
    const badTokens = [];
    let successCount = 0;
    let failureCount = 0;
  
    for (const [locale, tokens] of Object.entries(tokensByLocale)) {
      if (tokens.length === 0) continue;
  
      // Get localized template
      const localeSet = TEMPLATES[locale] || TEMPLATES.en;
      const tmpl = localeSet[type] || localeSet.default;
  
      // Interpolate template
      let title = tmpl.title;
      let body = tmpl.body;
  
      const replacements = {
        '{productName}': notificationData.productName,
        '{shopName}': notificationData.shopName,
        '{buyerName}': notificationData.buyerName,
        '{campaignName}': notificationData.campaignName,
        '{quantity}': notificationData.quantity,
        '{rating}': notificationData.rating,
        '{rejectionReason}': notificationData.rejectionReason,
      };
  
      Object.entries(replacements).forEach(([placeholder, value]) => {
        if (value !== undefined && value !== null) {
          title = title.replace(placeholder, String(value));
          body = body.replace(placeholder, String(value));
        }
      });
  
      // FCM has a 500 token limit per multicast call
      const FCM_BATCH_SIZE = 500;
      const tokenBatches = [];
      for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
        tokenBatches.push(tokens.slice(i, i + FCM_BATCH_SIZE));
      }
  
      for (const tokenBatch of tokenBatches) {
        const message = {
          tokens: tokenBatch,
          notification: { title, body },
          data: dataPayload,
          
          // iOS Configuration
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                sound: 'order_alert.caf',
                badge: 1,
                mutableContent: 1,
              }
            },
          },
          
          // Android Configuration
          android: {
            priority: 'high',
            notification: {
              channelId: 'food_orders_high',
              sound: 'order_alert',
              icon: 'ic_notification',
            },
          },
          
          // Web Push Configuration
          webpush: {
            headers: {
              Urgency: 'high',
            },
            notification: {
              title,
              body,
              icon: `${webBaseUrl}/icons/notification-icon-192.png`,
              badge: `${webBaseUrl}/icons/notification-badge-72.png`,
              tag: `shop-${shopId}-${type}`,
              renotify: true,
              requireInteraction: type === 'product_sold',
              actions: [
                {
                  action: 'open',
                  title: locale === 'tr' ? 'Görüntüle' : locale === 'ru' ? 'Открыть' : 'View',
                },
                {
                  action: 'dismiss',
                  title: locale === 'tr' ? 'Kapat' : locale === 'ru' ? 'Закрыть' : 'Dismiss',
                },
              ],
            },
            fcmOptions: {
              link: webClickAction,
            },
          },
        };
  
        console.log(
          `→ Sending shop notification (${locale}/${type}) to ${tokenBatch.length} tokens`,
          { title, body, route, webClickAction }
        );
  
        try {
          const batchResponse = await getMessaging().sendEachForMulticast(message);
          successCount += batchResponse.successCount;
          failureCount += batchResponse.failureCount;
  
          console.log(
            `FCM [${locale}]: ${batchResponse.successCount}/${tokenBatch.length} delivered`
          );
  
          // Collect bad tokens
          batchResponse.responses.forEach((resp, i) => {
            if (resp.error) {
              const code = resp.error.code;
              if (
                code === 'messaging/invalid-registration-token' ||
                code === 'messaging/registration-token-not-registered'
              ) {
                badTokens.push(tokenBatch[i]);
              }
            }
          });
        } catch (err) {
          console.error(`FCM send error for locale ${locale}:`, err);
          failureCount += tokenBatch.length;
        }
      }
    }
  
    // 8) Update notification with stats (fcmSent already set by transaction)
    await notificationRef.update({ 
      fcmSentAt: admin.firestore.FieldValue.serverTimestamp(),
      fcmStats: { successCount, failureCount, totalTokens },
    });
  
    // 9) Clean up invalid tokens
    if (badTokens.length > 0) {
      console.log(`Removing ${badTokens.length} invalid tokens`);
      
      const tokensByUser = new Map();
      badTokens.forEach((token) => {
        const userId = tokenToUserMap.get(token);
        if (userId) {
          if (!tokensByUser.has(userId)) {
            tokensByUser.set(userId, []);
          }
          tokensByUser.get(userId).push(token);
        }
      });
  
      const cleanupPromises = [];
      for (const [userId, userTokens] of tokensByUser) {
        const updates = {};
        userTokens.forEach((token) => {
          updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
        });
        cleanupPromises.push(
          admin.firestore().doc(`users/${userId}`).update(updates).catch((err) => {
            console.error(`Failed to clean tokens for user ${userId}:`, err);
          })
        );
      }
      
      await Promise.all(cleanupPromises);
    }
  
    console.log(`Shop notification ${notificationId} complete: ${successCount} sent, ${failureCount} failed`);
  });

  export const registerFcmToken = onCall(
    {
      region: 'europe-west3',
      timeoutSeconds: 10,
      memory: '256MiB',
    },
    async (req) => {
      const auth = req.auth;
      if (!auth?.uid) {
        throw new HttpsError('unauthenticated', 'Authentication required');
      }
  
      const {token, deviceId, platform} = req.data;
  
      // Validate inputs
      if (!token || typeof token !== 'string' || token.length < 50) {
        throw new HttpsError('invalid-argument', 'Invalid FCM token');
      }
  
      if (!deviceId || typeof deviceId !== 'string') {
        throw new HttpsError('invalid-argument', 'Device ID required');
      }
  
      const validPlatforms = ['ios', 'android', 'web'];
      if (!platform || !validPlatforms.includes(platform)) {
        throw new HttpsError('invalid-argument', 'Invalid platform');
      }
  
      const db = admin.firestore();
      const userRef = db.collection('users').doc(auth.uid);
  
      try {
        await db.runTransaction(async (transaction) => {
          const userDoc = await transaction.get(userRef);
  
          if (!userDoc.exists) {
            throw new HttpsError('not-found', 'User document not found');
          }
  
          const userData = userDoc.data() || {};
          let fcmTokens = userData.fcmTokens || {};
  
          // Step 1: Remove any existing tokens for this device
          Object.keys(fcmTokens).forEach((existingToken) => {
            if (fcmTokens[existingToken]?.deviceId === deviceId) {
              delete fcmTokens[existingToken];
            }
          });
  
          // Step 2: Also remove if this exact token exists under different device
          if (fcmTokens[token]) {
            delete fcmTokens[token];
          }
  
          // Step 3: Clean up old tokens BEFORE adding new one
          // (serverTimestamp is a sentinel that doesn't have toDate() yet)
          const existingEntries = Object.entries(fcmTokens)
            .sort((a, b) => {
              const aTime = a[1].lastSeen?.toDate?.()?.getTime() ||
                           a[1].registeredAt?.toDate?.()?.getTime() || 0;
              const bTime = b[1].lastSeen?.toDate?.()?.getTime() ||
                           b[1].registeredAt?.toDate?.()?.getTime() || 0;
              return bTime - aTime; // Most recent first
            });
  
          // Keep only 4 most recent (leaving room for the new token)
          if (existingEntries.length >= 5) {
            fcmTokens = Object.fromEntries(existingEntries.slice(0, 4));
          }
  
          // Step 4: NOW add the new token (guaranteed to be kept)
          fcmTokens[token] = {
            deviceId,
            platform,
            registeredAt: admin.firestore.FieldValue.serverTimestamp(),
            lastSeen: admin.firestore.FieldValue.serverTimestamp(),
          };
  
          transaction.update(userRef, {
            fcmTokens,
            lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
  
        return {success: true, deviceId};
      } catch (error) {
        console.error('FCM registration error:', error);
        
        if (error instanceof HttpsError) {
          throw error;
        }
        
        throw new HttpsError('internal', 'Failed to register token');
      }
    },
  );
  
  
  export const cleanupInvalidToken = onCall(
    {region: 'europe-west3'},
    async (req) => {
      const {userId, invalidToken} = req.data;
  
      if (!userId || !invalidToken) {
        throw new HttpsError('invalid-argument', 'Missing required parameters');
      }
  
      const db = admin.firestore();
      const userRef = db.collection('users').doc(userId);
  
      await userRef.update({
        [`fcmTokens.${invalidToken}`]: admin.firestore.FieldValue.delete(),
      });
  
      return {success: true};
    },
  );
  
  export const removeFcmToken = onCall(
    {
      region: 'europe-west3',
      timeoutSeconds: 5,
      memory: '256MB',
    },
    async (req) => {
      const auth = req.auth;
      if (!auth?.uid) {
        throw new HttpsError('unauthenticated', 'Authentication required');
      }
  
      const {token, deviceId} = req.data;
  
      console.log(`🔍 Removing token for user ${auth.uid}`);
      console.log(`🔍 Token received: ${token?.substring(0, 50)}...`);
      console.log(`🔍 DeviceId received: ${deviceId}`);
  
      if (!token && !deviceId) {
        throw new HttpsError('invalid-argument', 'Token or device ID required');
      }
  
      const db = admin.firestore();
      const userRef = db.collection('users').doc(auth.uid);
  
      try {
        await db.runTransaction(async (transaction) => {
          const userDoc = await transaction.get(userRef);
  
          if (!userDoc.exists) {
            console.log('⚠️ User document does not exist');
            return;
          }
  
          const userData = userDoc.data() || {};
          const fcmTokens = userData.fcmTokens || {};
  
          console.log(`📱 Current tokens count: ${Object.keys(fcmTokens).length}`);
  
          let removedCount = 0;
  
          if (token) {
            // Log if token exists in the map
            if (fcmTokens[token]) {
              console.log('✅ Found exact token match, removing...');
              delete fcmTokens[token];
              removedCount++;
            } else {
              console.log('⚠️ Token not found in user\'s token list');
              console.log('Available tokens:', Object.keys(fcmTokens).map((t) => t.substring(0, 50)));
            }
          }
  
          if (deviceId) {
            // Remove all tokens for this device
            Object.keys(fcmTokens).forEach((existingToken) => {
              if (fcmTokens[existingToken]?.deviceId === deviceId) {
                console.log(`✅ Removing token for deviceId: ${deviceId}`);
                delete fcmTokens[existingToken];
                removedCount++;
              }
            });
  
            if (removedCount === 0) {
              console.log(`⚠️ No tokens found for deviceId: ${deviceId}`);
              console.log('Available device IDs:', Object.values(fcmTokens).map((t) => t.deviceId));
            }
          }
  
          console.log(`🗑️ Removed ${removedCount} tokens`);
          console.log(`📱 Remaining tokens: ${Object.keys(fcmTokens).length}`);
  
          transaction.update(userRef, {
            fcmTokens,
            lastTokenUpdate: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
  
        return {success: true, removed: true};
      } catch (error) {
        console.error('FCM removal error:', error);
        throw new HttpsError('internal', 'Failed to remove token');
      }
    },
  );

  export const createProductQuestionNotification = onCall(
    {
      region: 'europe-west3',
      memory: '512MB',
      timeoutSeconds: 60,
    },
    async (request) => {
      const startTime = Date.now();
  
      try {
        // ============================================
        // STEP 1: AUTHENTICATION & VALIDATION
        // ============================================
        if (!request.auth) {
          throw new HttpsError('unauthenticated', 'User must be authenticated');
        }
  
        const {
          productId,
          productName,
          questionText,
          askerName,
          isShopProduct,
          shopId,
          sellerId,
        } = request.data;
  
        if (!productId || !productName || !questionText) {
          throw new HttpsError(
            'invalid-argument',
            'productId, productName, and questionText are required',
          );
        }
  
        if (isShopProduct && !shopId) {
          throw new HttpsError(
            'invalid-argument',
            'shopId is required for shop products',
          );
        }
  
        if (!isShopProduct && !sellerId) {
          throw new HttpsError(
            'invalid-argument',
            'sellerId is required for user products',
          );
        }
  
        const db = admin.firestore();
        const askerId = request.auth.uid;
  
        console.log(`📧 Creating notifications for product ${productId}`);
        console.log(`   Type: ${isShopProduct ? 'Shop Product' : 'User Product'}`);
  
        // ============================================
        // STEP 2: SHOP PRODUCT → shop_notifications
        // ============================================
        if (isShopProduct) {
          // Get shop to build isRead map
          const shopSnap = await db.collection('shops').doc(shopId).get();
  
          if (!shopSnap.exists) {
            throw new HttpsError('not-found', 'Shop not found');
          }
  
          const shopData = shopSnap.data();
  
          // Build isRead map for all members (excluding asker)
          const isReadMap = {};
          const addMember = (id) => {
            if (id && typeof id === 'string' && id !== askerId) {
              isReadMap[id] = false;
            }
          };
  
          addMember(shopData.ownerId);
          if (Array.isArray(shopData.coOwners)) shopData.coOwners.forEach(addMember);
          if (Array.isArray(shopData.editors)) shopData.editors.forEach(addMember);
          if (Array.isArray(shopData.viewers)) shopData.viewers.forEach(addMember);
  
          if (Object.keys(isReadMap).length === 0) {
            console.log('No recipients to notify');
            return { success: true, notificationsSent: 0 };
          }
  
          // ✅ Write to shop_notifications (triggers sendShopNotificationOnCreation)
          await db.collection('shop_notifications').add({
            type: 'product_question',
            shopId,
            shopName: shopData.name || '',
            productId,
            productName,
            questionText: questionText.substring(0, 500),
            askerName: askerName || 'Anonymous',
            askerId,
            isRead: isReadMap,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            message_en: `New question about "${productName}"`,
            message_tr: `"${productName}" hakkında yeni soru`,
            message_ru: `Новый вопрос о "${productName}"`,
          });
  
          console.log(`✅ Shop notification created for ${Object.keys(isReadMap).length} members`);
  
          return {
            success: true,
            notificationsSent: 1,
            recipients: Object.keys(isReadMap).length,
            processingTime: Date.now() - startTime,
          };
        }
  
        // ============================================
        // STEP 3: USER PRODUCT → users/{uid}/notifications
        // ============================================
        if (sellerId === askerId) {
          console.log('Asker is the product owner, no notification needed');
          return { success: true, notificationsSent: 0 };
        }
  
        await db.collection('users').doc(sellerId).collection('notifications').add({
          type: 'product_question',
          productId,
          productName,
          questionText: questionText.substring(0, 500),
          askerName: askerName || 'Anonymous',
          askerId,
          sellerId,
          isShopProduct: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          message_en: `New question about "${productName}"`,
          message_tr: `"${productName}" hakkında yeni soru`,
          message_ru: `Новый вопрос о "${productName}"`,
        });
  
        console.log(`✅ User notification created for seller ${sellerId}`);
  
        return {
          success: true,
          notificationsSent: 1,
          recipients: 1,
          processingTime: Date.now() - startTime,
        };
      } catch (error) {
        console.error('❌ Error:', error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', 'Failed to create notifications');
      }
    },
  );
