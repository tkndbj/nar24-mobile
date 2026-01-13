// functions/localization/en.js
export const localization = {
  new_review: {
    title: 'New Review',
    body: 'Someone has left a review for your product.',
  },
  seller_review: {
    title: 'Seller Review',
    body: 'Someone has left a review for you!',
  },
  product_sold: {
    title: 'Product Sold!',
    body: 'Your product has been sold!',
  },
  shipment_update: {
    title: 'Shipment Status Updated!',
    body: 'Your shipment status has been updated!',
  },
  message: {
    title: (senderName) => `${senderName}`,
    body: (messageText) => `${messageText}`,
  },
  boost_expired: {
    title: 'Boost Expired',
    body: '{itemName} boost has expired.',
  },
  // Add more notification types as needed
};
