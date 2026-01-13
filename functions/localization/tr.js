// functions/localization/tr.js
export const localization = {
  new_review: {
    title: 'Yeni Yorum',
    body: 'Biri ürününüz için yorum bıraktı.',
  },
  seller_review: {
    title: 'Satıcı Yorumu',
    body: 'Biri size yorum bıraktı!',
  },
  product_sold: {
    title: 'Ürün Satıldı!',
    body: 'Ürününüz satıldı!',
  },
  shipment_update: {
    title: 'Gönderi Durumu Güncellendi!',
    body: 'Gönderi durumunuz güncellendi!',
  },
  message: {
    title: (senderName) => `${senderName}`,
    body: (messageText) => `${messageText}`,
  },
  boost_expired: {
    title: 'Boost Süresi Doldu',
    body: '{itemName} boost süresi doldu.',
  },
  // Add more notification types as needed
};
