import 'package:cloud_firestore/cloud_firestore.dart';

/// A model class representing a user notification.
class NotificationModel {
  /// The Firestore document ID
  final String id;

  /// Type of the notification (e.g., 'message', 'boosted', 'shipment', etc.)
  final String type;

  /// Timestamp when the notification was created
  final Timestamp timestamp;

  /// Whether the notification has been read
  final bool isRead;

  /// Generic message field (fallback)
  final String? message;
  final String? reason;

  /// Localized messages
  final String? messageEn;
  final String? messageTr;
  final String? messageRu;
  final String? campaignName;
  final String? campaignDescription;

  /// Additional metadata fields (all optional)
  final String? itemType;
  final String? productId;
  final String? shopId;
  final String? transactionId;
  final String? senderId;
  final String? sellerId;
  final String? inviterName;
  final String? shopName;
  final String? role;
  final String? status;
  final String? orderId;
  final String? adType;
  final String? duration;
  final double? price;
  final String? imageUrl;
  final String? paymentLink;
  final String? submissionId;
  final bool? needsUpdate;
  final String? archiveReason;
  final bool? boostExpired;

  /// Rejection reason for rejected applications
  final String? rejectionReason;

  // NEW FIELDS FOR PRODUCT QUESTIONS
  /// The text content of the question (for product_question notifications)
  final String? questionText;

  /// The name of the person who asked the question
  final String? askerName;

  /// The ID of the person who asked the question
  final String? askerId;

  /// Whether this is a question about a shop product (true) or individual product (false)
  final bool? isShopProduct;

  /// The name of the product for which the question was asked
  final String? productName;

  NotificationModel({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.isRead,
    this.message,
    this.messageEn,
    this.messageTr,
    this.messageRu,
    this.itemType,
    this.productId,
    this.shopId,
    this.needsUpdate,
    this.archiveReason,
    this.boostExpired,
    this.transactionId,
    this.campaignName,
    this.campaignDescription,
    this.reason,
    this.senderId,
    this.sellerId,
    this.inviterName,
    this.shopName,
    this.role,
    this.status,
    this.rejectionReason,
    this.adType,
    this.duration,
    this.price,
    this.imageUrl,
    this.paymentLink,
    this.submissionId,
    this.orderId,
    this.questionText,
    this.askerName,
    this.askerId,
    this.isShopProduct,
    this.productName,
  });

  /// Factory constructor to create an instance from Firestore data.
  factory NotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return NotificationModel(
      id: snapshot.id,
      type: data['type'] as String? ?? 'general',
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      isRead: data['isRead'] as bool? ?? false,
      message: data['message'] as String?,
      messageEn: data['message_en'] as String?,
      messageTr: data['message_tr'] as String?,
      messageRu: data['message_ru'] as String?,
      itemType: data['itemType'] as String?,
      productId: data['productId'] as String?,
      shopId: data['shopId'] as String?,
      transactionId: data['transactionId'] as String?,
      reason: data['reason'] as String?,
      orderId: data['orderId'] as String?,
      senderId: data['senderId'] as String?,
      sellerId: data['sellerId'] as String?,
      needsUpdate: data['needsUpdate'] as bool?,
      archiveReason: data['archiveReason'] as String?,
      boostExpired: data['boostExpired'] as bool?,
      campaignName: data['campaignName'] as String?,
      campaignDescription: data['campaignDescription'] as String?,
      inviterName: data['inviterName'] as String?,
      shopName: data['shopName'] as String?,
      role: data['role'] as String?,
      status: data['status'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      adType: data['adType'] as String?,
      duration: data['duration'] as String?,
      price: (data['price'] as num?)?.toDouble(),
      imageUrl: data['imageUrl'] as String?,
      paymentLink: data['paymentLink'] as String?,
      submissionId: data['submissionId'] as String?,
      // NEW FIELDS FOR PRODUCT QUESTIONS
      questionText: data['questionText'] as String?,
      askerName: data['askerName'] as String?,
      askerId: data['askerId'] as String?,
      isShopProduct: data['isShopProduct'] as bool?,
      productName: data['productName'] as String?,
    );
  }

  /// Convert this model into a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'type': type,
      'timestamp': timestamp,
      'isRead': isRead,
    };
    if (message != null) map['message'] = message;
    if (messageEn != null) map['message_en'] = messageEn;
    if (messageTr != null) map['message_tr'] = messageTr;
    if (messageRu != null) map['message_ru'] = messageRu;
    if (itemType != null) map['itemType'] = itemType;
    if (productId != null) map['productId'] = productId;
    if (shopId != null) map['shopId'] = shopId;
    if (orderId != null) map['orderId'] = orderId;
    if (transactionId != null) map['transactionId'] = transactionId;
    if (reason != null) map['reason'] = reason;
    if (senderId != null) map['senderId'] = senderId;
    if (sellerId != null) map['sellerId'] = sellerId;
    if (campaignName != null) map['campaignName'] = campaignName;
    if (campaignDescription != null)
      map['campaignDescription'] = campaignDescription;
    if (inviterName != null) map['inviterName'] = inviterName;
    if (shopName != null) map['shopName'] = shopName;
    if (needsUpdate != null) map['needsUpdate'] = needsUpdate;
    if (archiveReason != null) map['archiveReason'] = archiveReason;
    if (boostExpired != null) map['boostExpired'] = boostExpired;
    if (role != null) map['role'] = role;
    if (status != null) map['status'] = status;
    if (rejectionReason != null) map['rejectionReason'] = rejectionReason;
    if (adType != null) map['adType'] = adType;
    if (duration != null) map['duration'] = duration;
    if (price != null) map['price'] = price;
    if (imageUrl != null) map['imageUrl'] = imageUrl;
    if (paymentLink != null) map['paymentLink'] = paymentLink;
    if (submissionId != null) map['submissionId'] = submissionId;
    // NEW FIELDS FOR PRODUCT QUESTIONS
    if (questionText != null) map['questionText'] = questionText;
    if (askerName != null) map['askerName'] = askerName;
    if (askerId != null) map['askerId'] = askerId;
    if (isShopProduct != null) map['isShopProduct'] = isShopProduct;
    if (productName != null) map['productName'] = productName;
    return map;
  }
}

/// Extension to apply Firestore converter without shadowing the built-in.
extension NotificationConverterExtension
    on CollectionReference<Map<String, dynamic>> {
  /// Attaches the NotificationModel converter to this collection.
  CollectionReference<NotificationModel> withNotificationConverter() {
    return this.withConverter<NotificationModel>(
      fromFirestore: NotificationModel.fromFirestore,
      toFirestore: (model, _) => model.toFirestore(),
    );
  }
}
