import 'package:cloud_firestore/cloud_firestore.dart';
import 'parse_helpers.dart';
import 'product_summary.dart';

/// Full product model — used on the detail screen and for
/// write operations (create / update / cart / order).
///
/// For list / grid views, prefer [ProductSummary].
///
/// ### Field structure
/// Every field that exists in Firestore has a dedicated typed property here.
/// Nothing spec-related lives in [attributes] — that map is a true catch-all
/// for any one-off fields that don't warrant a named property.
///
/// ### Migration
/// Old documents stored spec fields inside an `attributes` sub-map.
/// The factories read top-level first and silently fall back to `attributes`
/// for legacy documents. [toMap] / [toJson] always write top-level,
/// so the document is migrated on the next write automatically.
class Product {
  final String id;
  final String? sourceCollection;

  // ── Core ──────────────────────────────────────────────────────────────────
  final String productName;
  final String description;
  final double price;
  final String currency;
  final String condition;
  final String? brandModel;
  final String? videoUrl;

  // ── Media ─────────────────────────────────────────────────────────────────
  final List<String> imageUrls;
  final Map<String, List<String>> colorImages;

  // ── Classification ────────────────────────────────────────────────────────
  final String category;
  final String subcategory;
  final String subsubcategory;
  final String? productType;
  final String? gender;

  // ── Spec fields (top-level in Firestore, typed here) ──────────────────────
  final List<String>? clothingSizes;
  final String? clothingFit;
  final List<String>? clothingTypes;
  final List<String>? pantSizes;
  final List<String>? pantFabricTypes;
  final List<String>? footwearSizes;
  final List<String>? jewelryMaterials;
  final String? consoleBrand;
  final double? curtainMaxWidth;
  final double? curtainMaxHeight;

  // ── Inventory ─────────────────────────────────────────────────────────────
  final int quantity;
  final int? maxQuantity;
  final Map<String, int> colorQuantities;
  final List<String> availableColors;
  final String deliveryOption;

  // ── Ownership ─────────────────────────────────────────────────────────────
  final String userId;
  final String ownerId;
  final String? shopId;
  final String sellerName;
  final String ilanNo;

  // ── Ratings & stats ───────────────────────────────────────────────────────
  final double averageRating;
  final int reviewCount;
  final int clickCount;
  final int clickCountAtStart;
  final int favoritesCount;
  final int cartCount;
  final int purchaseCount;
  final int? bestSellerRank;

  // ── Pricing extras ────────────────────────────────────────────────────────
  final double? originalPrice;
  final int? discountPercentage;
  final int? discountThreshold;
  final int? bulkDiscountPercentage;

  // ── Bundles ───────────────────────────────────────────────────────────────
  final List<String> bundleIds;
  final List<Map<String, dynamic>>? bundleData;

  // ── Related products ──────────────────────────────────────────────────────
  final List<String> relatedProductIds;
  final Timestamp? relatedLastUpdated;
  final int relatedCount;

  // ── Archive / moderation ──────────────────────────────────────────────────
  final bool? needsUpdate;
  final String? archiveReason;
  final bool? archivedByAdmin;
  final Timestamp? archivedByAdminAt;
  final String? archivedByAdminId;

  // ── Boost / promotion ─────────────────────────────────────────────────────
  final double promotionScore;
  final String? campaign;
  final String? campaignName;
  final bool isFeatured;
  final bool isBoosted;
  final bool paused;
  final int boostedImpressionCount;
  final int boostImpressionCountAtStart;
  final int boostClickCountAtStart;
  final Timestamp? boostStartTime;
  final Timestamp? boostEndTime;
  final Timestamp? lastClickDate;

  // ── Timestamps ────────────────────────────────────────────────────────────
  final Timestamp createdAt;

  // ── Misc ──────────────────────────────────────────────────────────────────
  final DocumentReference? reference;

  /// Truly miscellaneous fields with no dedicated property.
  /// Spec fields are NOT stored here.
  final Map<String, dynamic> attributes;

  const Product({
    required this.id,
    this.sourceCollection,
    required this.productName,
    required this.description,
    required this.price,
    this.currency = 'TL',
    required this.condition,
    this.brandModel,
    this.videoUrl,
    required this.imageUrls,
    this.colorImages = const {},
    required this.category,
    required this.subcategory,
    required this.subsubcategory,
    this.productType,
    this.gender,
    // Spec fields
    this.clothingSizes,
    this.clothingFit,
    this.clothingTypes,
    this.pantSizes,
    this.pantFabricTypes,
    this.footwearSizes,
    this.jewelryMaterials,
    this.consoleBrand,
    this.curtainMaxWidth,
    this.curtainMaxHeight,
    // Inventory
    required this.quantity,
    this.maxQuantity,
    this.colorQuantities = const {},
    this.availableColors = const [],
    required this.deliveryOption,
    // Ownership
    required this.userId,
    required this.ownerId,
    this.shopId,
    required this.sellerName,
    required this.ilanNo,
    // Ratings & stats
    required this.averageRating,
    this.reviewCount = 0,
    this.clickCount = 0,
    this.clickCountAtStart = 0,
    this.favoritesCount = 0,
    this.cartCount = 0,
    this.purchaseCount = 0,
    this.bestSellerRank,
    // Pricing extras
    this.originalPrice,
    this.discountPercentage,
    this.discountThreshold,
    this.bulkDiscountPercentage,
    // Bundles
    this.bundleIds = const [],
    this.bundleData,
    // Related
    this.relatedProductIds = const [],
    this.relatedLastUpdated,
    this.relatedCount = 0,
    // Archive
    this.needsUpdate,
    this.archiveReason,
    this.archivedByAdmin,
    this.archivedByAdminAt,
    this.archivedByAdminId,
    // Boost
    this.promotionScore = 0,
    this.campaign,
    this.campaignName,
    this.isFeatured = false,
    this.isBoosted = false,
    this.paused = false,
    this.boostedImpressionCount = 0,
    this.boostImpressionCountAtStart = 0,
    required this.boostClickCountAtStart,
    this.boostStartTime,
    this.boostEndTime,
    this.lastClickDate,
    // Timestamps
    required this.createdAt,
    // Misc
    this.reference,
    this.attributes = const {},
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS — top-level first, attributes fallback for legacy docs
  // ═══════════════════════════════════════════════════════════════════════════

  static List<String>? _specList(Map<String, dynamic> d, String key) {
    final raw = d[key] ?? (d['attributes'] as Map<String, dynamic>?)?[key];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return null;
  }

  static String? _specStr(Map<String, dynamic> d, String key) {
    final raw = d[key] ?? (d['attributes'] as Map<String, dynamic>?)?[key];
    return raw?.toString();
  }

  static double? _specDouble(Map<String, dynamic> d, String key) {
    final raw = d[key] ?? (d['attributes'] as Map<String, dynamic>?)?[key];
    return (raw as num?)?.toDouble();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY CONVERSION
  // ═══════════════════════════════════════════════════════════════════════════

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
  // FACTORIES — all three delegate to _fromMap
  // ═══════════════════════════════════════════════════════════════════════════

  factory Product.fromDocument(DocumentSnapshot doc) {
    if (!doc.exists || doc.data() == null) {
      throw Exception('Missing product document! ID: ${doc.id}');
    }
    return Product._fromMap(
      doc.data()! as Map<String, dynamic>,
      id: doc.id,
      ref: doc.reference,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product._fromMap(json, id: json['id'] as String? ?? '');
  }

  factory Product.fromAlgolia(Map<String, dynamic> json) {
    String id = json['objectID']?.toString() ?? '';
    String? sourceCollection;

    if (id.startsWith('products_')) {
      sourceCollection = 'products';
      id = id.substring('products_'.length);
    } else if (id.startsWith('shop_products_')) {
      sourceCollection = 'shop_products';
      id = id.substring('shop_products_'.length);
    } else {
      sourceCollection =
          (json['shopId'] != null && json['shopId'].toString().isNotEmpty)
              ? 'shop_products'
              : 'products';
    }

    return Product._fromMap(
      json,
      id: id,
      sourceCollectionOverride: sourceCollection,
    );
  }

  /// Single internal factory — all three public factories delegate here.
  factory Product._fromMap(
    Map<String, dynamic> d, {
    required String id,
    DocumentReference? ref,
    String? sourceCollectionOverride,
  }) {
    final rawAttrs = Parse.toAttributes(d['attributes']);

    // attributes map contains only truly miscellaneous fields —
    // strip everything that now has a dedicated typed property.
    final cleanAttrs = Map<String, dynamic>.from(rawAttrs)
      ..remove('gender')
      ..remove('productType')
      ..remove('clothingSizes')
      ..remove('clothingFit')
      ..remove('clothingTypes')
      ..remove('clothingType') // legacy singular
      ..remove('pantSizes')
      ..remove('pantFabricTypes')
      ..remove('pantFabricType') // legacy singular
      ..remove('footwearSizes')
      ..remove('jewelryMaterials')
      ..remove('consoleBrand')
      ..remove('curtainMaxWidth')
      ..remove('curtainMaxHeight');

    return Product(
      id: id,
      sourceCollection:
          sourceCollectionOverride ?? Parse.sourceCollectionFromJson(d),
      // ── Core ──────────────────────────────────────────────────────────────
      productName: Parse.toStr(d['productName'] ?? d['title']),
      description: Parse.toStr(d['description']),
      price: Parse.toDouble(d['price']),
      currency: Parse.toStr(d['currency'], 'TL'),
      condition: Parse.toStr(d['condition'], 'Brand New'),
      brandModel: Parse.toStrNullable(d['brandModel'] ?? d['brand']),
      videoUrl: Parse.toStrNullable(d['videoUrl']),
      // ── Media ─────────────────────────────────────────────────────────────
      imageUrls: Parse.toStringList(d['imageUrls']),
      colorImages: Parse.toColorImages(d['colorImages']),
      // ── Classification ────────────────────────────────────────────────────
      category: Parse.toStr(d['category'], 'Uncategorized'),
      subcategory: Parse.toStr(d['subcategory']),
      subsubcategory: Parse.toStr(d['subsubcategory']),
      productType: Parse.toStrNullable(d['productType']),
      // gender: top-level (new) → attributes fallback (old Flutter products)
      gender: Parse.toStrNullable(d['gender']) ??
          Parse.toStrNullable(rawAttrs['gender']),
      // ── Spec fields ───────────────────────────────────────────────────────
      clothingSizes: _specList(d, 'clothingSizes'),
      clothingFit: _specStr(d, 'clothingFit'),
      // clothingTypes: also promote legacy singular 'clothingType'
      clothingTypes: _specList(d, 'clothingTypes') ??
          (_specStr(d, 'clothingType') != null
              ? [_specStr(d, 'clothingType')!]
              : null),
      pantSizes: _specList(d, 'pantSizes'),
      // pantFabricTypes: also promote legacy singular 'pantFabricType'
      pantFabricTypes: _specList(d, 'pantFabricTypes') ??
          (_specStr(d, 'pantFabricType') != null
              ? [_specStr(d, 'pantFabricType')!]
              : null),
      footwearSizes: _specList(d, 'footwearSizes'),
      jewelryMaterials: _specList(d, 'jewelryMaterials'),
      consoleBrand: _specStr(d, 'consoleBrand'),
      curtainMaxWidth: _specDouble(d, 'curtainMaxWidth'),
      curtainMaxHeight: _specDouble(d, 'curtainMaxHeight'),
      // ── Inventory ─────────────────────────────────────────────────────────
      quantity: Parse.toInt(d['quantity']),
      maxQuantity:
          d['maxQuantity'] != null ? Parse.toInt(d['maxQuantity']) : null,
      colorQuantities: Parse.toColorQty(d['colorQuantities']),
      availableColors: Parse.toStringList(d['availableColors']),
      deliveryOption: Parse.toStr(d['deliveryOption'], 'Self Delivery'),
      // ── Ownership ─────────────────────────────────────────────────────────
      userId: Parse.toStr(d['userId']),
      ownerId: Parse.toStr(d['ownerId']),
      shopId: Parse.toStrNullable(d['shopId']),
      sellerName: Parse.toStr(d['sellerName'], 'Unknown'),
      ilanNo: Parse.toStr(d['ilan_no'] ?? d['id'], 'N/A'),
      // ── Ratings & stats ───────────────────────────────────────────────────
      averageRating: Parse.toDouble(d['averageRating']),
      reviewCount: Parse.toInt(d['reviewCount']),
      clickCount: Parse.toInt(d['clickCount']),
      clickCountAtStart: Parse.toInt(d['clickCountAtStart']),
      favoritesCount: Parse.toInt(d['favoritesCount']),
      cartCount: Parse.toInt(d['cartCount']),
      purchaseCount: Parse.toInt(d['purchaseCount']),
      bestSellerRank:
          d['bestSellerRank'] != null ? Parse.toInt(d['bestSellerRank']) : null,
      // ── Pricing extras ────────────────────────────────────────────────────
      originalPrice: d['originalPrice'] != null
          ? Parse.toDouble(d['originalPrice'])
          : null,
      discountPercentage: d['discountPercentage'] != null
          ? Parse.toInt(d['discountPercentage'])
          : null,
      discountThreshold: d['discountThreshold'] != null
          ? Parse.toInt(d['discountThreshold'])
          : null,
      bulkDiscountPercentage: d['bulkDiscountPercentage'] != null
          ? Parse.toInt(d['bulkDiscountPercentage'])
          : null,
      // ── Bundles ───────────────────────────────────────────────────────────
      bundleIds: Parse.toStringList(d['bundleIds']),
      bundleData: Parse.toBundleData(d['bundleData']),
      // ── Related ───────────────────────────────────────────────────────────
      relatedProductIds: Parse.toStringList(d['relatedProductIds']),
      relatedLastUpdated: Parse.toTimestampNullable(d['relatedLastUpdated']),
      relatedCount: Parse.toInt(d['relatedCount']),
      // ── Archive ───────────────────────────────────────────────────────────
      needsUpdate: Parse.toBool(d['needsUpdate']),
      archiveReason: Parse.toStrNullable(d['archiveReason']),
      archivedByAdmin: Parse.toBool(d['archivedByAdmin']),
      archivedByAdminAt: Parse.toTimestampNullable(d['archivedByAdminAt']),
      archivedByAdminId: Parse.toStrNullable(d['archivedByAdminId']),
      // ── Boost ─────────────────────────────────────────────────────────────
      promotionScore: Parse.toDouble(d['promotionScore']),
      campaign: Parse.toStrNullable(d['campaign']),
      campaignName: Parse.toStrNullable(d['campaignName']),
      isFeatured: Parse.toBool(d['isFeatured']),
      isBoosted: Parse.toBool(d['isBoosted']),
      paused: Parse.toBool(d['paused']),
      boostedImpressionCount: Parse.toInt(d['boostedImpressionCount']),
      boostImpressionCountAtStart:
          Parse.toInt(d['boostImpressionCountAtStart']),
      boostClickCountAtStart: Parse.toInt(d['boostClickCountAtStart']),
      boostStartTime: Parse.toTimestampNullable(d['boostStartTime']),
      boostEndTime: Parse.toTimestampNullable(d['boostEndTime']),
      lastClickDate: Parse.toTimestampNullable(d['lastClickDate']),
      // ── Timestamps ────────────────────────────────────────────────────────
      createdAt: Parse.toTimestamp(d['createdAt']),
      // ── Misc ──────────────────────────────────────────────────────────────
      reference: ref,
      attributes: cleanAttrs,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      // Core
      'productName': productName,
      'description': description,
      'price': price,
      'currency': currency,
      'condition': condition,
      'brandModel': brandModel,
      'videoUrl': videoUrl,
      // Media
      'imageUrls': imageUrls,
      'colorImages': colorImages,
      // Classification
      'category': category,
      'subcategory': subcategory,
      'subsubcategory': subsubcategory,
      'productType': productType,
      'gender': gender,
      // Spec fields — top-level, always
      'clothingSizes': clothingSizes,
      'clothingFit': clothingFit,
      'clothingTypes': clothingTypes,
      'pantSizes': pantSizes,
      'pantFabricTypes': pantFabricTypes,
      'footwearSizes': footwearSizes,
      'jewelryMaterials': jewelryMaterials,
      'consoleBrand': consoleBrand,
      'curtainMaxWidth': curtainMaxWidth,
      'curtainMaxHeight': curtainMaxHeight,
      // Inventory
      'quantity': quantity,
      'maxQuantity': maxQuantity,
      'colorQuantities': colorQuantities,
      'availableColors': availableColors,
      'deliveryOption': deliveryOption,
      // Ownership
      'userId': userId,
      'ownerId': ownerId,
      'shopId': shopId,
      'sellerName': sellerName,
      'ilan_no': ilanNo,
      // Ratings & stats
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'clickCount': clickCount,
      'clickCountAtStart': clickCountAtStart,
      'favoritesCount': favoritesCount,
      'cartCount': cartCount,
      'purchaseCount': purchaseCount,
      'bestSellerRank': bestSellerRank,
      // Pricing extras
      'originalPrice': originalPrice,
      'discountPercentage': discountPercentage,
      'discountThreshold': discountThreshold,
      'bulkDiscountPercentage': bulkDiscountPercentage,
      // Bundles
      'bundleIds': bundleIds,
      'bundleData': bundleData,
      // Related
      'relatedProductIds': relatedProductIds,
      'relatedLastUpdated': relatedLastUpdated,
      'relatedCount': relatedCount,
      // Archive
      'needsUpdate': needsUpdate,
      'archiveReason': archiveReason,
      'archivedByAdmin': archivedByAdmin,
      'archivedByAdminAt': archivedByAdminAt,
      'archivedByAdminId': archivedByAdminId,
      // Boost
      'promotionScore': promotionScore,
      'campaign': campaign,
      'campaignName': campaignName,
      'isFeatured': isFeatured,
      'isBoosted': isBoosted,
      'paused': paused,
      'boostedImpressionCount': boostedImpressionCount,
      'boostImpressionCountAtStart': boostImpressionCountAtStart,
      'boostClickCountAtStart': boostClickCountAtStart,
      'boostStartTime': boostStartTime,
      'boostEndTime': boostEndTime,
      'lastClickDate': lastClickDate,
      // Timestamps
      'createdAt': createdAt,
      // Misc — only written if non-empty
      if (attributes.isNotEmpty) 'attributes': attributes,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'sourceCollection': sourceCollection,
      // Core
      'productName': productName,
      'description': description,
      'price': price,
      'currency': currency,
      'condition': condition,
      'brandModel': brandModel,
      'videoUrl': videoUrl,
      // Media
      'imageUrls': imageUrls,
      'colorImages': colorImages,
      // Classification
      'category': category,
      'subcategory': subcategory,
      'subsubcategory': subsubcategory,
      'productType': productType,
      'gender': gender,
      // Spec fields — top-level, always
      'clothingSizes': clothingSizes,
      'clothingFit': clothingFit,
      'clothingTypes': clothingTypes,
      'pantSizes': pantSizes,
      'pantFabricTypes': pantFabricTypes,
      'footwearSizes': footwearSizes,
      'jewelryMaterials': jewelryMaterials,
      'consoleBrand': consoleBrand,
      'curtainMaxWidth': curtainMaxWidth,
      'curtainMaxHeight': curtainMaxHeight,
      // Inventory
      'quantity': quantity,
      'maxQuantity': maxQuantity,
      'colorQuantities': colorQuantities,
      'availableColors': availableColors,
      'deliveryOption': deliveryOption,
      // Ownership
      'userId': userId,
      'ownerId': ownerId,
      'shopId': shopId,
      'sellerName': sellerName,
      'ilan_no': ilanNo,
      // Ratings & stats
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'clickCount': clickCount,
      'clickCountAtStart': clickCountAtStart,
      'favoritesCount': favoritesCount,
      'cartCount': cartCount,
      'purchaseCount': purchaseCount,
      'bestSellerRank': bestSellerRank,
      // Pricing extras
      'originalPrice': originalPrice,
      'discountPercentage': discountPercentage,
      'discountThreshold': discountThreshold,
      'bulkDiscountPercentage': bulkDiscountPercentage,
      // Bundles
      'bundleIds': bundleIds,
      'bundleData': bundleData,
      // Related
      'relatedProductIds': relatedProductIds,
      'relatedLastUpdated': relatedLastUpdated?.millisecondsSinceEpoch,
      'relatedCount': relatedCount,
      // Archive
      'needsUpdate': needsUpdate,
      'archiveReason': archiveReason,
      'archivedByAdmin': archivedByAdmin,
      'archivedByAdminAt': archivedByAdminAt?.millisecondsSinceEpoch,
      'archivedByAdminId': archivedByAdminId,
      // Boost
      'promotionScore': promotionScore,
      'campaign': campaign,
      'campaignName': campaignName,
      'isFeatured': isFeatured,
      'isBoosted': isBoosted,
      'paused': paused,
      'boostedImpressionCount': boostedImpressionCount,
      'boostImpressionCountAtStart': boostImpressionCountAtStart,
      'boostClickCountAtStart': boostClickCountAtStart,
      'boostStartTime': boostStartTime?.millisecondsSinceEpoch,
      'boostEndTime': boostEndTime?.millisecondsSinceEpoch,
      'lastClickDate': lastClickDate?.millisecondsSinceEpoch,
      // Timestamps
      'createdAt': createdAt.millisecondsSinceEpoch,
      // Misc
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
    String? videoUrl,
    List<String>? imageUrls,
    Map<String, List<String>>? colorImages,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? productType,
    String? gender,
    List<String>? clothingSizes,
    String? clothingFit,
    List<String>? clothingTypes,
    List<String>? pantSizes,
    List<String>? pantFabricTypes,
    List<String>? footwearSizes,
    List<String>? jewelryMaterials,
    String? consoleBrand,
    double? curtainMaxWidth,
    double? curtainMaxHeight,
    int? quantity,
    int? maxQuantity,
    Map<String, int>? colorQuantities,
    List<String>? availableColors,
    String? deliveryOption,
    String? userId,
    String? ownerId,
    String? shopId,
    String? sellerName,
    String? ilanNo,
    double? averageRating,
    int? reviewCount,
    int? clickCount,
    int? clickCountAtStart,
    int? favoritesCount,
    int? cartCount,
    int? purchaseCount,
    int? bestSellerRank,
    double? originalPrice,
    int? discountPercentage,
    int? discountThreshold,
    int? bulkDiscountPercentage,
    List<String>? bundleIds,
    List<Map<String, dynamic>>? bundleData,
    List<String>? relatedProductIds,
    Timestamp? relatedLastUpdated,
    int? relatedCount,
    bool? needsUpdate,
    String? archiveReason,
    bool? archivedByAdmin,
    Timestamp? archivedByAdminAt,
    String? archivedByAdminId,
    double? promotionScore,
    String? campaign,
    String? campaignName,
    bool? isFeatured,
    bool? isBoosted,
    bool? paused,
    int? boostedImpressionCount,
    int? boostImpressionCountAtStart,
    int? boostClickCountAtStart,
    Timestamp? boostStartTime,
    Timestamp? boostEndTime,
    Timestamp? lastClickDate,
    Timestamp? createdAt,
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
      videoUrl: videoUrl ?? this.videoUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      colorImages: colorImages ?? this.colorImages,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      subsubcategory: subsubcategory ?? this.subsubcategory,
      productType: productType ?? this.productType,
      gender: gender ?? this.gender,
      clothingSizes: clothingSizes ?? this.clothingSizes,
      clothingFit: clothingFit ?? this.clothingFit,
      clothingTypes: clothingTypes ?? this.clothingTypes,
      pantSizes: pantSizes ?? this.pantSizes,
      pantFabricTypes: pantFabricTypes ?? this.pantFabricTypes,
      footwearSizes: footwearSizes ?? this.footwearSizes,
      jewelryMaterials: jewelryMaterials ?? this.jewelryMaterials,
      consoleBrand: consoleBrand ?? this.consoleBrand,
      curtainMaxWidth: curtainMaxWidth ?? this.curtainMaxWidth,
      curtainMaxHeight: curtainMaxHeight ?? this.curtainMaxHeight,
      quantity: quantity ?? this.quantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      colorQuantities: colorQuantities ?? this.colorQuantities,
      availableColors: availableColors ?? this.availableColors,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      userId: userId ?? this.userId,
      ownerId: ownerId ?? this.ownerId,
      shopId: shopId ?? this.shopId,
      sellerName: sellerName ?? this.sellerName,
      ilanNo: ilanNo ?? this.ilanNo,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      clickCount: clickCount ?? this.clickCount,
      clickCountAtStart: clickCountAtStart ?? this.clickCountAtStart,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      cartCount: cartCount ?? this.cartCount,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      bestSellerRank: bestSellerRank ?? this.bestSellerRank,
      originalPrice:
          setOriginalPriceNull ? null : (originalPrice ?? this.originalPrice),
      discountPercentage: setDiscountPercentageNull
          ? null
          : (discountPercentage ?? this.discountPercentage),
      discountThreshold: discountThreshold ?? this.discountThreshold,
      bulkDiscountPercentage:
          bulkDiscountPercentage ?? this.bulkDiscountPercentage,
      bundleIds: bundleIds ?? this.bundleIds,
      bundleData: bundleData ?? this.bundleData,
      relatedProductIds: relatedProductIds ?? this.relatedProductIds,
      relatedLastUpdated: relatedLastUpdated ?? this.relatedLastUpdated,
      relatedCount: relatedCount ?? this.relatedCount,
      needsUpdate: needsUpdate ?? this.needsUpdate,
      archiveReason: archiveReason ?? this.archiveReason,
      archivedByAdmin: archivedByAdmin ?? this.archivedByAdmin,
      archivedByAdminAt: archivedByAdminAt ?? this.archivedByAdminAt,
      archivedByAdminId: archivedByAdminId ?? this.archivedByAdminId,
      promotionScore: promotionScore ?? this.promotionScore,
      campaign: campaign ?? this.campaign,
      campaignName: campaignName ?? this.campaignName,
      isFeatured: isFeatured ?? this.isFeatured,
      isBoosted: isBoosted ?? this.isBoosted,
      paused: paused ?? this.paused,
      boostedImpressionCount:
          boostedImpressionCount ?? this.boostedImpressionCount,
      boostImpressionCountAtStart:
          boostImpressionCountAtStart ?? this.boostImpressionCountAtStart,
      boostClickCountAtStart:
          boostClickCountAtStart ?? this.boostClickCountAtStart,
      boostStartTime: boostStartTime ?? this.boostStartTime,
      boostEndTime: boostEndTime ?? this.boostEndTime,
      lastClickDate: lastClickDate ?? this.lastClickDate,
      createdAt: createdAt ?? this.createdAt,
      reference: reference,
      attributes: attributes ?? this.attributes,
    );
  }
}
