import 'package:cloud_firestore/cloud_firestore.dart';
import 'parse_helpers.dart';
import 'product_summary.dart';

/// Full product model — used on the **detail screen** and for
/// write operations (create / update / cart / order).
///
/// For list / grid views, prefer [ProductSummary] which skips
/// ~50 fields that cards never display.
///
/// ### Migration path
/// 1. Provider pagination → swap `Product` lists for `ProductSummary`.
/// 2. Card widgets → accept `ProductSummary` instead of `Product`.
/// 3. Detail screen → fetch full `Product` on tap via `Product.fromDocument`.
/// 4. Everything that **writes** (cart, order, edit) stays on `Product`.
class Product {
  final String id;
  final String? sourceCollection;
  final String productName;
  final String description;
  final double price;
  final String currency;
  final String condition;
  final String? brandModel;
  final List<String> imageUrls;
  final double averageRating;
  final int reviewCount;
  final double? originalPrice;
  final int? discountPercentage;
  final Map<String, int> colorQuantities;
  final DocumentReference? reference;
  final int boostClickCountAtStart;
  final List<String> availableColors;
  final String? gender;
  final List<String> bundleIds;
  final List<Map<String, dynamic>>? bundleData;
  final int? maxQuantity;
  final int? discountThreshold;
  final int? bulkDiscountPercentage;
  final List<String> relatedProductIds;
  final Timestamp? relatedLastUpdated;
  final int relatedCount;

  final bool? needsUpdate;
  final String? archiveReason;
  final bool? archivedByAdmin;
  final Timestamp? archivedByAdminAt;
  final String? archivedByAdminId;

  final String userId;
  final double promotionScore;
  final String? campaign;
  final String ownerId;
  final String? shopId;
  final String ilanNo;
  final Timestamp createdAt;
  final String sellerName;
  final String category;
  final String subcategory;
  final String subsubcategory;
  final int quantity;
  final int? bestSellerRank;

  final int clickCount;
  final int clickCountAtStart;
  final int favoritesCount;
  final int cartCount;
  final int purchaseCount;
  final String deliveryOption;
  final int boostedImpressionCount;
  final int boostImpressionCountAtStart;
  final bool isFeatured;
  final bool isBoosted;
  final Timestamp? boostStartTime;
  final Timestamp? boostEndTime;
  final Timestamp? lastClickDate;
  final bool paused;
  final String? campaignName;
  final Map<String, List<String>> colorImages;
  final String? videoUrl;
  final Map<String, dynamic> attributes;

  Product({
    required this.id,
    this.sourceCollection,
    required this.productName,
    required this.description,
    required this.price,
    this.currency = 'TL',
    required this.condition,
    this.brandModel,
    required this.imageUrls,
    required this.averageRating,
    required this.reviewCount,
    this.originalPrice,
    this.discountPercentage,
    this.colorQuantities = const {},
    this.maxQuantity,
    this.reference,
    this.gender,
    this.bundleIds = const [],
    this.bundleData,
    required this.boostClickCountAtStart,
    this.availableColors = const [],
    required this.userId,
    this.discountThreshold,
    this.bulkDiscountPercentage,
    this.promotionScore = 0,
    this.campaign,
    required this.ownerId,
    this.shopId,
    required this.ilanNo,
    required this.createdAt,
    required this.sellerName,
    required this.category,
    required this.subcategory,
    required this.subsubcategory,
    required this.quantity,
    this.bestSellerRank,
    this.clickCount = 0,
    this.clickCountAtStart = 0,
    this.favoritesCount = 0,
    this.cartCount = 0,
    this.purchaseCount = 0,
    this.needsUpdate,
    this.archiveReason,
    this.archivedByAdmin,
    this.archivedByAdminAt,
    this.archivedByAdminId,
    required this.deliveryOption,
    this.boostedImpressionCount = 0,
    required this.boostImpressionCountAtStart,
    this.isFeatured = false,
    this.isBoosted = false,
    this.boostStartTime,
    this.boostEndTime,
    this.lastClickDate,
    this.paused = false,
    this.campaignName,
    this.colorImages = const {},
    this.videoUrl,
    this.attributes = const {},
    this.relatedProductIds = const [],
    this.relatedLastUpdated,
    this.relatedCount = 0,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY CONVERSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Downcast to a lightweight [ProductSummary] for use in list views.
  ///
  /// This is cheap — it just copies references, no deep cloning.
  ProductSummary toSummary() {
    return ProductSummary(
      id: id,
      sourceCollection: sourceCollection,
      productName: productName,
      price: price,
      currency: currency,
      condition: condition,
      brandModel: brandModel,
      imageUrls: imageUrls,
      averageRating: averageRating,
      reviewCount: reviewCount,
      originalPrice: originalPrice,
      discountPercentage: discountPercentage,
      campaignName: campaignName,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      gender: gender,
      availableColors: availableColors,
      colorImages: colorImages,
      sellerName: sellerName,
      shopId: shopId,
      userId: userId,
      ownerId: ownerId,
      quantity: quantity,
      colorQuantities: colorQuantities,
      isBoosted: isBoosted,
      isFeatured: isFeatured,
      purchaseCount: purchaseCount,
      bestSellerRank: bestSellerRank,
      deliveryOption: deliveryOption,
      paused: paused,
      bundleIds: bundleIds,
      discountThreshold: discountThreshold,
      bulkDiscountPercentage: bulkDiscountPercentage,
      videoUrl: videoUrl,
      createdAt: createdAt,
      promotionScore: promotionScore,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORIES — now using shared [Parse] helpers
  // ═══════════════════════════════════════════════════════════════════════════

  factory Product.fromDocument(DocumentSnapshot doc) {
    if (!doc.exists || doc.data() == null) {
      throw Exception('Missing product document! ID: ${doc.id}');
    }
    final d = doc.data()! as Map<String, dynamic>;

    return Product(
      id: doc.id,
      sourceCollection: Parse.sourceCollectionFromRef(doc.reference),
      productName: Parse.toStr(d['productName'] ?? d['title']),
      description: Parse.toStr(d['description']),
      price: Parse.toDouble(d['price']),
      currency: Parse.toStr(d['currency'], 'TL'),
      condition: Parse.toStr(d['condition'], 'Brand New'),
      brandModel: Parse.toStr(d['brandModel'] ?? d['brand'] ?? ''),
      imageUrls: Parse.toStringList(d['imageUrls']),
      averageRating: Parse.toDouble(d['averageRating']),
      reviewCount: Parse.toInt(d['reviewCount']),
      gender: Parse.toStrNullable(d['gender']),
      bundleIds: Parse.toStringList(d['bundleIds']),
      maxQuantity:
          d['maxQuantity'] != null ? Parse.toInt(d['maxQuantity']) : null,
      bundleData: Parse.toBundleData(d['bundleData']),
      originalPrice: d['originalPrice'] != null
          ? Parse.toDouble(d['originalPrice'])
          : null,
      discountPercentage: d['discountPercentage'] != null
          ? Parse.toInt(d['discountPercentage'])
          : null,
      colorQuantities: Parse.toColorQty(d['colorQuantities']),
      reference: doc.reference,
      boostClickCountAtStart: Parse.toInt(d['boostClickCountAtStart']),
      availableColors: Parse.toStringList(d['availableColors']),
      userId: Parse.toStr(d['userId']),
      discountThreshold: d['discountThreshold'] != null
          ? Parse.toInt(d['discountThreshold'])
          : null,
      bulkDiscountPercentage: d['bulkDiscountPercentage'] != null
          ? Parse.toInt(d['bulkDiscountPercentage'])
          : null,
      promotionScore: Parse.toDouble(d['promotionScore']),
      campaign: Parse.toStrNullable(d['campaign']),
      ownerId: Parse.toStr(d['ownerId']),
      shopId: Parse.toStrNullable(d['shopId']),
      ilanNo: Parse.toStr(d['ilan_no'] ?? d['id'], 'N/A'),
      createdAt: Parse.toTimestamp(d['createdAt']),
      sellerName: Parse.toStr(d['sellerName'], 'Unknown'),
      category: Parse.toStr(d['category'], 'Uncategorized'),
      subcategory: Parse.toStr(d['subcategory']),
      subsubcategory: Parse.toStr(d['subsubcategory']),
      needsUpdate: Parse.toBool(d['needsUpdate']),
      archiveReason: Parse.toStrNullable(d['archiveReason']),
      archivedByAdmin: Parse.toBool(d['archivedByAdmin']),
      archivedByAdminAt: Parse.toTimestampNullable(d['archivedByAdminAt']),
      archivedByAdminId: Parse.toStrNullable(d['archivedByAdminId']),
      quantity: Parse.toInt(d['quantity']),
      relatedProductIds: Parse.toStringList(d['relatedProductIds']),
      relatedLastUpdated: Parse.toTimestampNullable(d['relatedLastUpdated']),
      relatedCount: Parse.toInt(d['relatedCount']),
      bestSellerRank:
          d['bestSellerRank'] != null ? Parse.toInt(d['bestSellerRank']) : null,
      clickCount: Parse.toInt(d['clickCount']),
      clickCountAtStart: Parse.toInt(d['clickCountAtStart']),
      favoritesCount: Parse.toInt(d['favoritesCount']),
      cartCount: Parse.toInt(d['cartCount']),
      purchaseCount: Parse.toInt(d['purchaseCount']),
      deliveryOption: Parse.toStr(d['deliveryOption'], 'Self Delivery'),
      boostedImpressionCount: Parse.toInt(d['boostedImpressionCount']),
      boostImpressionCountAtStart:
          Parse.toInt(d['boostImpressionCountAtStart']),
      isFeatured: Parse.toBool(d['isFeatured']),
      isBoosted: Parse.toBool(d['isBoosted']),
      boostStartTime: Parse.toTimestampNullable(d['boostStartTime']),
      boostEndTime: Parse.toTimestampNullable(d['boostEndTime']),
      lastClickDate: Parse.toTimestampNullable(d['lastClickDate']),
      paused: Parse.toBool(d['paused']),
      campaignName: Parse.toStrNullable(d['campaignName']),
      colorImages: Parse.toColorImages(d['colorImages']),
      videoUrl: Parse.toStrNullable(d['videoUrl']),
      attributes: Parse.toAttributes(d['attributes']),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String? ?? '',
      sourceCollection: Parse.sourceCollectionFromJson(json),
      productName: json['productName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'TL',
      condition: json['condition'] as String? ?? 'Brand New',
      brandModel: json['brandModel'] as String? ?? '',
      imageUrls: json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'] as List)
          : [],
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: json['reviewCount'] as int? ?? 0,
      gender: json['gender'] as String?,
      bundleIds: json['bundleIds'] != null
          ? List<String>.from(json['bundleIds'] as List)
          : [],
      bundleData: Parse.toBundleData(json['bundleData']),
      maxQuantity: json['maxQuantity'] as int?,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercentage: json['discountPercentage'] as int?,
      colorQuantities: json['colorQuantities'] is Map
          ? (json['colorQuantities'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {},
      reference: null,
      boostClickCountAtStart: json['boostClickCountAtStart'] as int? ?? 0,
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'] as List)
          : [],
      userId: json['userId'] as String? ?? '',
      discountThreshold: json['discountThreshold'] as int?,
      relatedProductIds: json['relatedProductIds'] != null
          ? List<String>.from(json['relatedProductIds'] as List)
          : [],
      relatedLastUpdated: Parse.toTimestampNullable(json['relatedLastUpdated']),
      relatedCount: json['relatedCount'] as int? ?? 0,
      promotionScore: (json['promotionScore'] as num?)?.toDouble() ?? 0.0,
      campaign: json['campaign'] as String?,
      ownerId: json['ownerId'] as String? ?? '',
      shopId: json['shopId'] as String?,
      ilanNo: json['ilan_no'] as String? ?? '',
      needsUpdate: json['needsUpdate'] as bool? ?? false,
      archiveReason: json['archiveReason'] as String?,
      archivedByAdmin: json['archivedByAdmin'] as bool? ?? false,
      archivedByAdminAt: Parse.toTimestampNullable(json['archivedByAdminAt']),
      archivedByAdminId: json['archivedByAdminId'] as String?,
      createdAt: Parse.toTimestamp(json['createdAt']),
      sellerName: json['sellerName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      subcategory: json['subcategory'] as String? ?? '',
      subsubcategory: json['subsubcategory'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      bestSellerRank: json['bestSellerRank'] as int?,
      clickCount: json['clickCount'] as int? ?? 0,
      clickCountAtStart: json['clickCountAtStart'] as int? ?? 0,
      favoritesCount: json['favoritesCount'] as int? ?? 0,
      cartCount: json['cartCount'] as int? ?? 0,
      purchaseCount: json['purchaseCount'] as int? ?? 0,
      deliveryOption: json['deliveryOption'] as String? ?? 'Self Delivery',
      boostedImpressionCount: json['boostedImpressionCount'] as int? ?? 0,
      boostImpressionCountAtStart:
          json['boostImpressionCountAtStart'] as int? ?? 0,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isBoosted: json['isBoosted'] as bool? ?? false,
      boostStartTime: Parse.toTimestampNullable(json['boostStartTime']),
      boostEndTime: Parse.toTimestampNullable(json['boostEndTime']),
      lastClickDate: Parse.toTimestampNullable(json['lastClickDate']),
      paused: json['paused'] as bool? ?? false,
      campaignName: json['campaignName'] as String?,
      colorImages: json['colorImages'] is Map
          ? (json['colorImages'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List).map((e) => e.toString()).toList(),
              ),
            )
          : {},
      videoUrl: json['videoUrl'] as String?,
      attributes: Parse.toAttributes(json['attributes']),
    );
  }

  factory Product.fromAlgolia(Map<String, dynamic> json) {
    String normalizedId = json['objectID']?.toString() ?? '';
    String? sourceCollection;

    if (normalizedId.startsWith('products_')) {
      sourceCollection = 'products';
      normalizedId = normalizedId.substring('products_'.length);
    } else if (normalizedId.startsWith('shop_products_')) {
      sourceCollection = 'shop_products';
      normalizedId = normalizedId.substring('shop_products_'.length);
    } else {
      sourceCollection =
          (json['shopId'] != null && json['shopId'].toString().isNotEmpty)
              ? 'shop_products'
              : 'products';
    }

    return Product(
      id: normalizedId,
      sourceCollection: sourceCollection,
      productName: json['productName']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'TL',
      condition: json['condition']?.toString() ?? 'Brand New',
      brandModel: json['brandModel']?.toString() ?? '',
      imageUrls: json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'])
          : [],
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      gender: json['gender'] as String?,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercentage: (json['discountPercentage'] as num?)?.toInt(),
      maxQuantity: (json['maxQuantity'] as num?)?.toInt(),
      colorQuantities: json['colorQuantities'] is Map
          ? (json['colorQuantities'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {},
      reference: null,
      boostClickCountAtStart:
          (json['boostClickCountAtStart'] as num?)?.toInt() ?? 0,
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'])
          : [],
      userId: json['userId']?.toString() ?? '',
      discountThreshold: (json['discountThreshold'] as num?)?.toInt(),
      promotionScore: (json['promotionScore'] as num?)?.toDouble() ?? 0.0,
      campaign: json['campaign']?.toString(),
      relatedProductIds: json['relatedProductIds'] != null
          ? List<String>.from(json['relatedProductIds'] as List)
          : [],
      relatedLastUpdated: Parse.toTimestampNullable(json['relatedLastUpdated']),
      relatedCount: json['relatedCount'] as int? ?? 0,
      ownerId: json['ownerId']?.toString() ?? '',
      shopId: json['shopId']?.toString(),
      ilanNo: json['ilan_no']?.toString() ?? '',
      createdAt: Parse.toTimestamp(json['createdAt']),
      sellerName: json['sellerName']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      needsUpdate: json['needsUpdate'] as bool? ?? false,
      archiveReason: json['archiveReason'] as String?,
      archivedByAdmin: json['archivedByAdmin'] as bool? ?? false,
      archivedByAdminAt: Parse.toTimestampNullable(json['archivedByAdminAt']),
      archivedByAdminId: json['archivedByAdminId'] as String?,
      subcategory: json['subcategory']?.toString() ?? '',
      subsubcategory: json['subsubcategory']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      bestSellerRank: (json['bestSellerRank'] as num?)?.toInt(),
      clickCount: (json['clickCount'] as num?)?.toInt() ?? 0,
      clickCountAtStart: (json['clickCountAtStart'] as num?)?.toInt() ?? 0,
      favoritesCount: (json['favoritesCount'] as num?)?.toInt() ?? 0,
      cartCount: (json['cartCount'] as num?)?.toInt() ?? 0,
      purchaseCount: (json['purchaseCount'] as num?)?.toInt() ?? 0,
      deliveryOption: json['deliveryOption']?.toString() ?? 'Self Delivery',
      boostedImpressionCount:
          (json['boostedImpressionCount'] as num?)?.toInt() ?? 0,
      boostImpressionCountAtStart:
          (json['boostImpressionCountAtStart'] as num?)?.toInt() ?? 0,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isBoosted: json['isBoosted'] as bool? ?? false,
      boostStartTime: Parse.toTimestampNullable(json['boostStartTime']),
      boostEndTime: Parse.toTimestampNullable(json['boostEndTime']),
      lastClickDate: Parse.toTimestampNullable(json['lastClickDate']),
      paused: json['paused'] as bool? ?? false,
      campaignName: json['campaignName']?.toString(),
      colorImages: json['colorImages'] is Map
          ? (json['colorImages'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List).map((e) => e.toString()).toList(),
              ),
            )
          : {},
      videoUrl: json['videoUrl']?.toString(),
      attributes: Parse.toAttributes(json['attributes']),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'productName': productName,
      'description': description,
      'price': price,
      'currency': currency,
      'condition': condition,
      'brandModel': brandModel,
      'imageUrls': imageUrls,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'originalPrice': originalPrice,
      'discountPercentage': discountPercentage,
      'colorQuantities': colorQuantities,
      'bundleIds': bundleIds,
      'bundleData': bundleData,
      'maxQuantity': maxQuantity,
      'boostClickCountAtStart': boostClickCountAtStart,
      'availableColors': availableColors,
      'userId': userId,
      'discountThreshold': discountThreshold,
      'bulkDiscountPercentage': bulkDiscountPercentage,
      'promotionScore': promotionScore,
      'campaign': campaign,
      'ownerId': ownerId,
      'shopId': shopId,
      'ilan_no': ilanNo,
      'gender': gender,
      'needsUpdate': needsUpdate,
      'archiveReason': archiveReason,
      'archivedByAdmin': archivedByAdmin,
      'archivedByAdminAt': archivedByAdminAt,
      'archivedByAdminId': archivedByAdminId,
      'createdAt': createdAt,
      'sellerName': sellerName,
      'category': category,
      'subcategory': subcategory,
      'subsubcategory': subsubcategory,
      'quantity': quantity,
      'bestSellerRank': bestSellerRank,
      'clickCount': clickCount,
      'clickCountAtStart': clickCountAtStart,
      'favoritesCount': favoritesCount,
      'cartCount': cartCount,
      'purchaseCount': purchaseCount,
      'deliveryOption': deliveryOption,
      'boostedImpressionCount': boostedImpressionCount,
      'boostImpressionCountAtStart': boostImpressionCountAtStart,
      'isFeatured': isFeatured,
      'isBoosted': isBoosted,
      'boostStartTime': boostStartTime,
      'boostEndTime': boostEndTime,
      'lastClickDate': lastClickDate,
      'paused': paused,
      'campaignName': campaignName,
      'colorImages': colorImages,
      'videoUrl': videoUrl,
      'relatedProductIds': relatedProductIds,
      'relatedLastUpdated': relatedLastUpdated,
      'relatedCount': relatedCount,
      if (attributes.isNotEmpty) 'attributes': attributes,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'sourceCollection': sourceCollection,
      'productName': productName,
      'description': description,
      'price': price,
      'currency': currency,
      'condition': condition,
      'brandModel': brandModel,
      'imageUrls': imageUrls,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'originalPrice': originalPrice,
      'discountPercentage': discountPercentage,
      'discountThreshold': discountThreshold,
      'maxQuantity': maxQuantity,
      'boostClickCountAtStart': boostClickCountAtStart,
      'userId': userId,
      'ownerId': ownerId,
      'shopId': shopId,
      'ilan_no': ilanNo,
      'gender': gender,
      'availableColors': availableColors,
      'needsUpdate': needsUpdate,
      'archiveReason': archiveReason,
      'archivedByAdmin': archivedByAdmin,
      'archivedByAdminAt': archivedByAdminAt?.millisecondsSinceEpoch,
      'archivedByAdminId': archivedByAdminId,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'sellerName': sellerName,
      'category': category,
      'subcategory': subcategory,
      'subsubcategory': subsubcategory,
      'quantity': quantity,
      'bestSellerRank': bestSellerRank,
      'clickCount': clickCount,
      'clickCountAtStart': clickCountAtStart,
      'favoritesCount': favoritesCount,
      'cartCount': cartCount,
      'purchaseCount': purchaseCount,
      'deliveryOption': deliveryOption,
      'relatedProductIds': relatedProductIds,
      'relatedLastUpdated': relatedLastUpdated?.millisecondsSinceEpoch,
      'relatedCount': relatedCount,
      'boostedImpressionCount': boostedImpressionCount,
      'boostImpressionCountAtStart': boostImpressionCountAtStart,
      'isFeatured': isFeatured,
      'isBoosted': isBoosted,
      'boostStartTime': boostStartTime?.millisecondsSinceEpoch,
      'boostEndTime': boostEndTime?.millisecondsSinceEpoch,
      'lastClickDate': lastClickDate?.millisecondsSinceEpoch,
      'paused': paused,
      'promotionScore': promotionScore,
      'campaign': campaign,
      'campaignName': campaignName,
      'colorImages': colorImages,
      'videoUrl': videoUrl,
      'attributes': attributes,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COPY WITH
  // ═══════════════════════════════════════════════════════════════════════════

  Product copyWith({
    String? sourceCollection,
    String? productName,
    String? description,
    double? price,
    String? currency,
    String? condition,
    String? brandModel,
    List<String>? imageUrls,
    double? averageRating,
    int? reviewCount,
    double? originalPrice,
    int? discountPercentage,
    Map<String, int>? colorQuantities,
    List<String>? bundleIds,
    int? boostClickCountAtStart,
    List<String>? availableColors,
    bool? needsUpdate,
    String? archiveReason,
    bool? archivedByAdmin,
    Timestamp? archivedByAdminAt,
    String? archivedByAdminId,
    String? userId,
    int? discountThreshold,
    int? bulkDiscountPercentage,
    List<Map<String, dynamic>>? bundleData,
    double? promotionScore,
    int? maxQuantity,
    String? campaign,
    String? gender,
    String? ownerId,
    String? shopId,
    String? ilanNo,
    List<String>? relatedProductIds,
    Timestamp? relatedLastUpdated,
    int? relatedCount,
    Timestamp? createdAt,
    String? sellerName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    int? quantity,
    int? bestSellerRank,
    int? clickCount,
    int? clickCountAtStart,
    int? favoritesCount,
    int? cartCount,
    int? purchaseCount,
    String? deliveryOption,
    int? boostedImpressionCount,
    int? boostImpressionCountAtStart,
    bool? isFeatured,
    bool? isBoosted,
    Timestamp? boostStartTime,
    Timestamp? boostEndTime,
    Timestamp? lastClickDate,
    bool? paused,
    String? campaignName,
    Map<String, List<String>>? colorImages,
    String? videoUrl,
    Map<String, dynamic>? attributes,
    bool setOriginalPriceNull = false,
    bool setDiscountPercentageNull = false,
  }) {
    return Product(
      id: id,
      sourceCollection: sourceCollection ?? this.sourceCollection,
      productName: productName ?? this.productName,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      condition: condition ?? this.condition,
      brandModel: brandModel ?? this.brandModel,
      imageUrls: imageUrls ?? this.imageUrls,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      originalPrice:
          setOriginalPriceNull ? null : (originalPrice ?? this.originalPrice),
      discountPercentage: setDiscountPercentageNull
          ? null
          : (discountPercentage ?? this.discountPercentage),
      colorQuantities: colorQuantities ?? this.colorQuantities,
      reference: reference,
      gender: gender ?? this.gender,
      bundleIds: bundleIds ?? this.bundleIds,
      bundleData: bundleData ?? this.bundleData,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      boostClickCountAtStart:
          boostClickCountAtStart ?? this.boostClickCountAtStart,
      availableColors: availableColors ?? this.availableColors,
      userId: userId ?? this.userId,
      discountThreshold: discountThreshold ?? this.discountThreshold,
      bulkDiscountPercentage:
          bulkDiscountPercentage ?? this.bulkDiscountPercentage,
      needsUpdate: needsUpdate ?? this.needsUpdate,
      archiveReason: archiveReason ?? this.archiveReason,
      archivedByAdmin: archivedByAdmin ?? this.archivedByAdmin,
      archivedByAdminAt: archivedByAdminAt ?? this.archivedByAdminAt,
      archivedByAdminId: archivedByAdminId ?? this.archivedByAdminId,
      promotionScore: promotionScore ?? this.promotionScore,
      campaign: campaign ?? this.campaign,
      ownerId: ownerId ?? this.ownerId,
      shopId: shopId ?? this.shopId,
      ilanNo: ilanNo ?? this.ilanNo,
      createdAt: createdAt ?? this.createdAt,
      sellerName: sellerName ?? this.sellerName,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      subsubcategory: subsubcategory ?? this.subsubcategory,
      quantity: quantity ?? this.quantity,
      bestSellerRank: bestSellerRank ?? this.bestSellerRank,
      clickCount: clickCount ?? this.clickCount,
      clickCountAtStart: clickCountAtStart ?? this.clickCountAtStart,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      cartCount: cartCount ?? this.cartCount,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      boostedImpressionCount:
          boostedImpressionCount ?? this.boostedImpressionCount,
      boostImpressionCountAtStart:
          boostImpressionCountAtStart ?? this.boostImpressionCountAtStart,
      isFeatured: isFeatured ?? this.isFeatured,
      isBoosted: isBoosted ?? this.isBoosted,
      boostStartTime: boostStartTime ?? this.boostStartTime,
      boostEndTime: boostEndTime ?? this.boostEndTime,
      lastClickDate: lastClickDate ?? this.lastClickDate,
      paused: paused ?? this.paused,
      campaignName: campaignName ?? this.campaignName,
      colorImages: colorImages ?? this.colorImages,
      videoUrl: videoUrl ?? this.videoUrl,
      attributes: attributes ?? this.attributes,
      relatedProductIds: relatedProductIds ?? this.relatedProductIds,
      relatedLastUpdated: relatedLastUpdated ?? this.relatedLastUpdated,
      relatedCount: relatedCount ?? this.relatedCount,
    );
  }
}