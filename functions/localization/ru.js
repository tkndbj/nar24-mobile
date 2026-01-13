// functions/localization/ru.js
export const localization = {
  new_review: {
    title: 'Новый отзыв',
    body: 'К вашему продукту был оставлен отзыв.',
  },
  seller_review: {
    title: 'Отзыв продавца',
    body: 'К вам был оставлен отзыв!',
  },
  product_sold: {
    title: 'Продукт Продан!',
    body: 'Ваш продукт был продан!',
  },
  shipment_update: {
    title: 'Статус доставки обновлен!',
    body: 'Статус вашей доставки обновлен!',
  },
  message: {
    title: (senderName) => `${senderName}`,
    body: (messageText) => `${messageText}`,
  },
  boost_expired: {
    title: 'Буст Истёк',
    body: 'Буст для {itemName} истёк.',
  },
  // Add more notification types as needed
};
