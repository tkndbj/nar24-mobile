// test/models/product/testable_product_model.dart
//
// TESTABLE MIRROR of Product model parsing logic from lib/models/product.dart
//
// This file contains EXACT copies of parsing functions from Product factories
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/models/product.dart
//
// Last synced with: product.dart (current version)

/// Mirrors parsing helpers from Product model
class TestableProductParser {
  // ==========================================================================
  // SAFE TYPE CONVERSIONS - Used across all Product factories
  // ==========================================================================

  /// Mirrors `_safeDouble` from Product.fromDocument
  static double safeDouble(dynamic v, [double d = 0]) {
    if (v == null) return d;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? d;
    return d;
  }

  /// Mirrors `_safeInt` from Product.fromDocument
  static int safeInt(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  /// Mirrors `_safeString` from Product.fromDocument
  static String safeString(dynamic v, [String d = '']) {
    if (v == null) return d;
    return v.toString();
  }

  /// Mirrors `_safeStringNullable` from Product.fromDocument
  static String? safeStringNullable(dynamic v) {
    if (v == null) return null;
    final str = v.toString().trim();
    return str.isEmpty ? null : str;
  }

  /// Mirrors `_safeStringList` from Product.fromDocument
  static List<String> safeStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String) return v.isEmpty ? [] : [v];
    return [];
  }

  /// Mirrors `_safeColorQty` from Product.fromDocument
  static Map<String, int> safeColorQuantities(dynamic v) {
    if (v is! Map) return {};
    final m = <String, int>{};
    v.forEach((k, val) => m[k.toString()] = safeInt(val));
    return m;
  }

  /// Mirrors `_safeColorImgs` from Product.fromDocument
  static Map<String, List<String>> safeColorImages(dynamic v) {
    if (v is! Map) return {};
    final m = <String, List<String>>{};
    v.forEach((k, val) {
      if (val is List) {
        m[k.toString()] = val.map((e) => e.toString()).toList();
      } else if (val is String && val.isNotEmpty) {
        m[k.toString()] = [val];
      }
    });
    return m;
  }

  /// Mirrors `_safeBundleData` from Product.fromDocument
  static List<Map<String, dynamic>>? safeBundleData(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;

    try {
      return v.map((item) {
        if (item is Map<String, dynamic>) {
          return item;
        } else if (item is Map) {
          return Map<String, dynamic>.from(item);
        }
        return <String, dynamic>{};
      }).toList();
    } catch (e) {
      return null;
    }
  }

  // ==========================================================================
  // TIMESTAMP PARSING - Used for date fields
  // ==========================================================================

  /// Mirrors `_parseCreatedAt` from Product (required timestamp)
  static DateTime parseCreatedAt(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    // Default to now if unparseable
    return DateTime.now();
  }

  /// Mirrors `_parseTimestamp` from Product (nullable timestamp)
  static DateTime? parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ==========================================================================
  // ALGOLIA-SPECIFIC PARSING
  // ==========================================================================

  /// Mirrors ID normalization from Product.fromAlgolia
  static String normalizeAlgoliaId(String? objectId) {
    if (objectId == null || objectId.isEmpty) return '';

    String normalizedId = objectId;

    // Remove common Algolia prefixes
    if (normalizedId.startsWith('products_')) {
      normalizedId = normalizedId.substring('products_'.length);
    } else if (normalizedId.startsWith('shop_products_')) {
      normalizedId = normalizedId.substring('shop_products_'.length);
    }

    return normalizedId;
  }

  // ==========================================================================
  // FROMJSON PARSING - Mirrors Product.fromJson logic
  // ==========================================================================

  /// Parses colorQuantities from JSON (slightly different from fromDocument)
  static Map<String, int> parseJsonColorQuantities(dynamic value) {
    if (value is! Map) return {};
    return (value).map((k, v) => MapEntry(
          k.toString(),
          (v is num) ? v.toInt() : 0,
        ));
  }

  /// Parses colorImages from JSON
  static Map<String, List<String>> parseJsonColorImages(dynamic value) {
    if (value is! Map) return {};
    return (value).map((k, v) => MapEntry(
          k.toString(),
          (v is List) ? v.map((e) => e.toString()).toList() : <String>[],
        ));
  }

  /// Parses bundleData from JSON
  static List<Map<String, dynamic>>? parseJsonBundleData(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;

    try {
      return (value).map((item) {
        if (item is Map<String, dynamic>) {
          return item;
        } else if (item is Map) {
          return Map<String, dynamic>.from(item);
        }
        return <String, dynamic>{};
      }).toList();
    } catch (e) {
      return null;
    }
  }

  // ==========================================================================
  // SOURCE COLLECTION DETECTION
  // ==========================================================================

  /// Detects source collection from document path
  static String? detectSourceCollection(String path) {
    if (path.startsWith('products/')) {
      return 'products';
    } else if (path.startsWith('shop_products/')) {
      return 'shop_products';
    }
    return null;
  }
}

/// Represents a parsed Product for testing purposes
/// Contains only the fields that involve complex parsing
class TestableProductData {
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
  final Map<String, List<String>> colorImages;
  final List<Map<String, dynamic>>? bundleData;
  final List<String> bundleIds;
  final int? maxQuantity;
  final int? discountThreshold;
  final int? bulkDiscountPercentage;
  final String? gender;
  final List<String> availableColors;
  final String userId;
  final String ownerId;
  final String? shopId;
  final String sellerName;
  final String category;
  final String subcategory;
  final String subsubcategory;
  final int quantity;
  final String deliveryOption;
  final DateTime createdAt;
  final DateTime? boostStartTime;
  final DateTime? boostEndTime;
  final bool isFeatured;
  final bool isTrending;
  final bool isBoosted;
  final bool paused;
  final Map<String, dynamic> attributes;

  TestableProductData({
    required this.id,
    this.sourceCollection,
    required this.productName,
    required this.description,
    required this.price,
    required this.currency,
    required this.condition,
    this.brandModel,
    required this.imageUrls,
    required this.averageRating,
    required this.reviewCount,
    this.originalPrice,
    this.discountPercentage,
    required this.colorQuantities,
    required this.colorImages,
    this.bundleData,
    required this.bundleIds,
    this.maxQuantity,
    this.discountThreshold,
    this.bulkDiscountPercentage,
    this.gender,
    required this.availableColors,
    required this.userId,
    required this.ownerId,
    this.shopId,
    required this.sellerName,
    required this.category,
    required this.subcategory,
    required this.subsubcategory,
    required this.quantity,
    required this.deliveryOption,
    required this.createdAt,
    this.boostStartTime,
    this.boostEndTime,
    required this.isFeatured,
    required this.isTrending,
    required this.isBoosted,
    required this.paused,
    required this.attributes,
  });

  /// Mirrors Product.fromJson parsing logic
  factory TestableProductData.fromJson(Map<String, dynamic> json) {
    return TestableProductData(
      id: json['id'] as String? ?? '',
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
      originalPrice: (json['originalPrice'] as num?)?.toDouble(),
      discountPercentage: json['discountPercentage'] as int?,
      maxQuantity: json['maxQuantity'] as int?,
      discountThreshold: json['discountThreshold'] as int?,
      bulkDiscountPercentage: json['bulkDiscountPercentage'] as int?,
      colorQuantities: TestableProductParser.parseJsonColorQuantities(json['colorQuantities']),
      colorImages: TestableProductParser.parseJsonColorImages(json['colorImages']),
      bundleData: TestableProductParser.parseJsonBundleData(json['bundleData']),
      bundleIds: json['bundleIds'] != null
          ? List<String>.from(json['bundleIds'] as List)
          : [],
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'] as List)
          : [],
      userId: json['userId'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      shopId: json['shopId'] as String?,
      sellerName: json['sellerName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      subcategory: json['subcategory'] as String? ?? '',
      subsubcategory: json['subsubcategory'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      deliveryOption: json['deliveryOption'] as String? ?? 'Self Delivery',
      createdAt: TestableProductParser.parseCreatedAt(json['createdAt']),
      boostStartTime: TestableProductParser.parseTimestamp(json['boostStartTime']),
      boostEndTime: TestableProductParser.parseTimestamp(json['boostEndTime']),
      isFeatured: json['isFeatured'] as bool? ?? false,
      isTrending: json['isTrending'] as bool? ?? false,
      isBoosted: json['isBoosted'] as bool? ?? false,
      paused: json['paused'] as bool? ?? false,
      attributes: json['attributes'] is Map<String, dynamic>
          ? json['attributes'] as Map<String, dynamic>
          : {},
    );
  }

  /// Mirrors Product.fromAlgolia parsing logic
  factory TestableProductData.fromAlgolia(Map<String, dynamic> json) {
    // Normalize ID by removing Algolia prefixes
    final normalizedId = TestableProductParser.normalizeAlgoliaId(json['objectID']?.toString());

    return TestableProductData(
      id: normalizedId,
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
      discountThreshold: (json['discountThreshold'] as num?)?.toInt(),
      bulkDiscountPercentage: (json['bulkDiscountPercentage'] as num?)?.toInt(),
      colorQuantities: json['colorQuantities'] is Map
          ? (json['colorQuantities'] as Map).map((k, v) => MapEntry(
                k.toString(),
                (v as num).toInt(),
              ))
          : {},
      colorImages: json['colorImages'] is Map
          ? (json['colorImages'] as Map).map((k, v) => MapEntry(
                k.toString(),
                (v as List).map((e) => e.toString()).toList(),
              ))
          : {},
      bundleData: null, // Algolia doesn't typically include bundleData
      bundleIds: json['bundleIds'] != null
          ? List<String>.from(json['bundleIds'])
          : [],
      availableColors: json['availableColors'] != null
          ? List<String>.from(json['availableColors'])
          : [],
      userId: json['userId']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      shopId: json['shopId']?.toString(),
      sellerName: json['sellerName']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      subcategory: json['subcategory']?.toString() ?? '',
      subsubcategory: json['subsubcategory']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      deliveryOption: json['deliveryOption']?.toString() ?? 'Self Delivery',
      createdAt: TestableProductParser.parseCreatedAt(json['createdAt']),
      boostStartTime: TestableProductParser.parseTimestamp(json['boostStartTime']),
      boostEndTime: TestableProductParser.parseTimestamp(json['boostEndTime']),
      isFeatured: json['isFeatured'] as bool? ?? false,
      isTrending: json['isTrending'] as bool? ?? false,
      isBoosted: json['isBoosted'] as bool? ?? false,
      paused: json['paused'] as bool? ?? false,
      attributes: json['attributes'] is Map<String, dynamic>
          ? json['attributes'] as Map<String, dynamic>
          : {},
    );
  }

  /// Mirrors Product.fromDocument parsing logic (without Firestore dependency)
  factory TestableProductData.fromDocument(
    String docId,
    Map<String, dynamic> data, {
    String? documentPath,
  }) {
    String? sourceCollection;
    if (documentPath != null) {
      sourceCollection = TestableProductParser.detectSourceCollection(documentPath);
    }

    return TestableProductData(
      id: docId,
      sourceCollection: sourceCollection,
      productName: TestableProductParser.safeString(data['productName'] ?? data['title']),
      description: TestableProductParser.safeString(data['description']),
      price: TestableProductParser.safeDouble(data['price']),
      currency: TestableProductParser.safeString(data['currency'], 'TL'),
      condition: TestableProductParser.safeString(data['condition'], 'Brand New'),
      brandModel: TestableProductParser.safeString(data['brandModel'] ?? data['brand'] ?? ''),
      imageUrls: TestableProductParser.safeStringList(data['imageUrls']),
      averageRating: TestableProductParser.safeDouble(data['averageRating']),
      reviewCount: TestableProductParser.safeInt(data['reviewCount']),
      gender: TestableProductParser.safeStringNullable(data['gender']),
      originalPrice: data['originalPrice'] != null
          ? TestableProductParser.safeDouble(data['originalPrice'])
          : null,
      discountPercentage: data['discountPercentage'] != null
          ? TestableProductParser.safeInt(data['discountPercentage'])
          : null,
      maxQuantity:
          data['maxQuantity'] != null ? TestableProductParser.safeInt(data['maxQuantity']) : null,
      discountThreshold: data['discountThreshold'] != null
          ? TestableProductParser.safeInt(data['discountThreshold'])
          : null,
      bulkDiscountPercentage: data['bulkDiscountPercentage'] != null
          ? TestableProductParser.safeInt(data['bulkDiscountPercentage'])
          : null,
      colorQuantities: TestableProductParser.safeColorQuantities(data['colorQuantities']),
      colorImages: TestableProductParser.safeColorImages(data['colorImages']),
      bundleData: TestableProductParser.safeBundleData(data['bundleData']),
      bundleIds: TestableProductParser.safeStringList(data['bundleIds']),
      availableColors: TestableProductParser.safeStringList(data['availableColors']),
      userId: TestableProductParser.safeString(data['userId']),
      ownerId: TestableProductParser.safeString(data['ownerId']),
      shopId: data['shopId']?.toString(),
      sellerName: TestableProductParser.safeString(data['sellerName'], 'Unknown'),
      category: TestableProductParser.safeString(data['category'], 'Uncategorized'),
      subcategory: TestableProductParser.safeString(data['subcategory']),
      subsubcategory: TestableProductParser.safeString(data['subsubcategory']),
      quantity: TestableProductParser.safeInt(data['quantity']),
      deliveryOption: TestableProductParser.safeString(data['deliveryOption'], 'Self Delivery'),
      createdAt: TestableProductParser.parseCreatedAt(data['createdAt']),
      boostStartTime: TestableProductParser.parseTimestamp(data['boostStartTime']),
      boostEndTime: TestableProductParser.parseTimestamp(data['boostEndTime']),
      isFeatured: data['isFeatured'] == true,
      isTrending: data['isTrending'] == true,
      isBoosted: data['isBoosted'] == true,
      paused: data['paused'] == true,
      attributes: data['attributes'] is Map<String, dynamic>
          ? data['attributes'] as Map<String, dynamic>
          : {},
    );
  }
}