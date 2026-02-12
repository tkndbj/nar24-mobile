import 'package:cloud_firestore/cloud_firestore.dart';
import 'parse_helpers.dart';

/// A lightweight, **read-only** projection of a product used exclusively
/// in list / grid / card views.
///
/// ### Why this exists
/// The full [Product] model carries 70+ fields.  Most of them
/// (`archiveReason`, `boostClickCountAtStart`, `archivedByAdminId`, …)
/// are never displayed in a product card.  Deserializing, storing, and
/// GC-ing all those fields for every item on every scroll page wastes
/// memory and CPU — especially on budget Android devices.
///
/// `ProductSummary` keeps only the ~20 fields that a card actually
/// renders, cutting per-object cost roughly in half.
///
/// ### Usage
/// ```dart
/// // In your provider — browsing / pagination:
/// final summaries = docs.map(ProductSummary.fromDocument).toList();
///
/// // When user taps a card — fetch full detail:
/// final full = Product.fromDocument(await docRef.get());
/// ```
///
/// ### Rules
/// *  **Never add admin / analytics / boost-internal fields here.**
///    If a card doesn't show it, it doesn't belong.
/// *  If a new UI element is added to the card, add the field here
///    **and** in the `fromDocument` / `fromJson` / `fromAlgolia` factories.
class ProductSummary {
  final String id;
  final String? sourceCollection;

  // ── Display fields (what the card actually renders) ────────────────────
  final String productName;
  final double price;
  final String currency;
  final String condition;
  final String? brandModel;
  final List<String> imageUrls;
  final double averageRating;
  final int reviewCount;
  final double? originalPrice;
  final int? discountPercentage;

  // ── Category / filtering (needed for navigation & filter chips) ────────
  final String category;
  final String subcategory;
  final String subsubcategory;
  final String? gender;

  // ── Color variant display ─────────────────────────────────────────────
  final List<String> availableColors;
  final Map<String, List<String>> colorImages;

  // ── Seller display ────────────────────────────────────────────────────
  final String sellerName;
  final String? shopId;
  final String userId;
  final String ownerId;

  // ── Stock (for "out of stock" badge) ──────────────────────────────────
  final int quantity;
  final Map<String, int> colorQuantities;

  // ── Flags the card may use for badges / ribbons ───────────────────────
  final bool isBoosted;
  final bool isFeatured;
  final bool isTrending;
  final int purchaseCount;
  final int? bestSellerRank;
  final String deliveryOption;
  final bool paused;

  final String? campaignName;

  // ── Bundle indicator ──────────────────────────────────────────────────
  final List<String> bundleIds;

  // ── Discount thresholds (for "buy X get Y% off" badge) ────────────────
  final int? discountThreshold;
  final int? bulkDiscountPercentage;

  // ── Video indicator ───────────────────────────────────────────────────
  final String? videoUrl;

  // ── Timestamp (for "new" badge / sort) ────────────────────────────────
  final Timestamp createdAt;

  // ── Scores (used by provider for sorting, not displayed) ──────────────
  final double rankingScore;
  final double promotionScore;

  const ProductSummary({
    required this.id,
    this.sourceCollection,
    required this.productName,
    required this.price,
    this.currency = 'TL',
    required this.condition,
    this.brandModel,
    required this.imageUrls,
    required this.averageRating,
    required this.reviewCount,
    this.originalPrice,
    this.discountPercentage,
    this.campaignName,
    required this.category,
    required this.subcategory,
    required this.subsubcategory,
    this.gender,
    this.availableColors = const [],
    this.colorImages = const {},
    required this.sellerName,
    this.shopId,
    required this.userId,
    required this.ownerId,
    required this.quantity,
    this.colorQuantities = const {},
    this.isBoosted = false,
    this.isFeatured = false,
    this.isTrending = false,
    this.purchaseCount = 0,
    this.bestSellerRank,
    required this.deliveryOption,
    this.paused = false,
    this.bundleIds = const [],
    this.discountThreshold,
    this.bulkDiscountPercentage,
    this.videoUrl,
    required this.createdAt,
    this.rankingScore = 0,
    this.promotionScore = 0,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // FACTORIES
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse from a Firestore document.
  ///
  /// Intentionally skips ~50 fields that [Product.fromDocument] would parse.
  factory ProductSummary.fromDocument(DocumentSnapshot doc) {
    if (!doc.exists || doc.data() == null) {
      throw Exception('Missing product document! ID: ${doc.id}');
    }
    final d = doc.data()! as Map<String, dynamic>;

    return ProductSummary(
      id: doc.id,
      sourceCollection: Parse.sourceCollectionFromRef(doc.reference),
      productName: Parse.toStr(d['productName'] ?? d['title']),
      price: Parse.toDouble(d['price']),
      currency: Parse.toStr(d['currency'], 'TL'),
      condition: Parse.toStr(d['condition'], 'Brand New'),
      brandModel: Parse.toStrNullable(d['brandModel'] ?? d['brand']),
      imageUrls: Parse.toStringList(d['imageUrls']),
      averageRating: Parse.toDouble(d['averageRating']),
      reviewCount: Parse.toInt(d['reviewCount']),
      originalPrice:
          d['originalPrice'] != null ? Parse.toDouble(d['originalPrice']) : null,
      discountPercentage: d['discountPercentage'] != null
          ? Parse.toInt(d['discountPercentage'])
          : null,
      category: Parse.toStr(d['category'], 'Uncategorized'),
      subcategory: Parse.toStr(d['subcategory']),
      subsubcategory: Parse.toStr(d['subsubcategory']),
      gender: Parse.toStrNullable(d['gender']),
      availableColors: Parse.toStringList(d['availableColors']),
      colorImages: Parse.toColorImages(d['colorImages']),
      sellerName: Parse.toStr(d['sellerName'], 'Unknown'),
      campaignName: Parse.toStr(d['campaignName']),
      shopId: Parse.toStrNullable(d['shopId']),
      userId: Parse.toStr(d['userId']),
      ownerId: Parse.toStr(d['ownerId']),
      quantity: Parse.toInt(d['quantity']),
      colorQuantities: Parse.toColorQty(d['colorQuantities']),
      isBoosted: Parse.toBool(d['isBoosted']),
      isFeatured: Parse.toBool(d['isFeatured']),
      isTrending: Parse.toBool(d['isTrending']),
      purchaseCount: Parse.toInt(d['purchaseCount']),
      bestSellerRank:
          d['bestSellerRank'] != null ? Parse.toInt(d['bestSellerRank']) : null,
      deliveryOption: Parse.toStr(d['deliveryOption'], 'Self Delivery'),
      paused: Parse.toBool(d['paused']),
      bundleIds: Parse.toStringList(d['bundleIds']),
      discountThreshold: d['discountThreshold'] != null
          ? Parse.toInt(d['discountThreshold'])
          : null,
      bulkDiscountPercentage: d['bulkDiscountPercentage'] != null
          ? Parse.toInt(d['bulkDiscountPercentage'])
          : null,
      videoUrl: Parse.toStrNullable(d['videoUrl']),
      createdAt: Parse.toTimestamp(d['createdAt']),
      rankingScore: Parse.toDouble(d['rankingScore']),
      promotionScore: Parse.toDouble(d['promotionScore']),
    );
  }

  /// Parse from a plain JSON map (e.g. local cache, REST API).
  factory ProductSummary.fromJson(Map<String, dynamic> json) {
    return ProductSummary(
      id: json['id'] as String? ?? '',
      sourceCollection: Parse.sourceCollectionFromJson(json),
      productName: json['productName'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'TL',
      condition: json['condition'] as String? ?? 'Brand New',
      brandModel: json['brandModel'] as String?,
      imageUrls: json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'] as List)
          : const [],
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercentage: (json['discountPercentage'] as num?)?.toInt(),
      category: json['category'] as String? ?? '',
      subcategory: json['subcategory'] as String? ?? '',
      subsubcategory: json['subsubcategory'] as String? ?? '',
      gender: json['gender'] as String?,
      campaignName: Parse.toStr(json['campaignName']),
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'] as List)
          : const [],
      colorImages: json['colorImages'] is Map
          ? (json['colorImages'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List).map((e) => e.toString()).toList(),
              ),
            )
          : const {},
      sellerName: json['sellerName'] as String? ?? '',
      shopId: json['shopId'] as String?,
      userId: json['userId'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      colorQuantities: json['colorQuantities'] is Map
          ? (json['colorQuantities'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : const {},
      isBoosted: json['isBoosted'] as bool? ?? false,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isTrending: json['isTrending'] as bool? ?? false,
      purchaseCount: (json['purchaseCount'] as num?)?.toInt() ?? 0,
      bestSellerRank: (json['bestSellerRank'] as num?)?.toInt(),
      deliveryOption: json['deliveryOption'] as String? ?? 'Self Delivery',
      paused: json['paused'] as bool? ?? false,
      bundleIds: json['bundleIds'] != null
          ? List<String>.from(json['bundleIds'] as List)
          : const [],
      discountThreshold: (json['discountThreshold'] as num?)?.toInt(),
      bulkDiscountPercentage:
          (json['bulkDiscountPercentage'] as num?)?.toInt(),
      videoUrl: json['videoUrl'] as String?,
      createdAt: Parse.toTimestamp(json['createdAt']),
      rankingScore: (json['rankingScore'] as num?)?.toDouble() ?? 0.0,
      promotionScore: (json['promotionScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Parse from an Algolia hit.
  factory ProductSummary.fromAlgolia(Map<String, dynamic> json) {
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

    return ProductSummary(
      id: normalizedId,
      sourceCollection: sourceCollection,
      productName: json['productName']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'TL',
      condition: json['condition']?.toString() ?? 'Brand New',
      brandModel: json['brandModel']?.toString(),
      imageUrls: json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'])
          : const [],
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercentage: (json['discountPercentage'] as num?)?.toInt(),
      category: json['category']?.toString() ?? '',
      subcategory: json['subcategory']?.toString() ?? '',
      subsubcategory: json['subsubcategory']?.toString() ?? '',
      campaignName: json['campaignName']?.toString(),
      gender: json['gender'] as String?,
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'])
          : const [],
      colorImages: json['colorImages'] is Map
          ? (json['colorImages'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List).map((e) => e.toString()).toList(),
              ),
            )
          : const {},
      sellerName: json['sellerName']?.toString() ?? '',
      shopId: json['shopId']?.toString(),
      userId: json['userId']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      colorQuantities: json['colorQuantities'] is Map
          ? (json['colorQuantities'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : const {},
      isBoosted: json['isBoosted'] as bool? ?? false,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isTrending: json['isTrending'] as bool? ?? false,
      purchaseCount: (json['purchaseCount'] as num?)?.toInt() ?? 0,
      bestSellerRank: (json['bestSellerRank'] as num?)?.toInt(),
      deliveryOption: json['deliveryOption']?.toString() ?? 'Self Delivery',
      paused: json['paused'] as bool? ?? false,
      bundleIds: json['bundleIds'] != null
          ? List<String>.from(json['bundleIds'])
          : const [],
      discountThreshold: (json['discountThreshold'] as num?)?.toInt(),
      bulkDiscountPercentage:
          (json['bulkDiscountPercentage'] as num?)?.toInt(),
      videoUrl: json['videoUrl']?.toString(),
      createdAt: Parse.toTimestamp(json['createdAt']),
      rankingScore: (json['rankingScore'] as num?)?.toDouble() ?? 0.0,
      promotionScore: (json['promotionScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVENIENCE
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the product has any stock remaining.
  bool get isInStock {
    if (colorQuantities.isNotEmpty) {
      return colorQuantities.values.any((q) => q > 0);
    }
    return quantity > 0;
  }

  /// Whether this product has a discount.
  bool get hasDiscount =>
      discountPercentage != null && discountPercentage! > 0;

  /// Whether this product has a video.
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// Whether this product has bundles.
  bool get hasBundle => bundleIds.isNotEmpty;

  /// The Firestore collection this product belongs to.
  String get collection => sourceCollection ?? 'products';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}