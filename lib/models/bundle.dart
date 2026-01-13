import 'package:cloud_firestore/cloud_firestore.dart';

class Bundle {
  final String id;
  final String shopId;
  final List<BundleProduct> products; // Changed from mainProduct + bundleItems
  final double totalBundlePrice; // Single price for entire bundle
  final double totalOriginalPrice; // Sum of all product prices
  final double discountPercentage; // Overall discount
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final int purchaseCount;

  Bundle({
    required this.id,
    required this.shopId,
    required this.products,
    required this.totalBundlePrice,
    required this.totalOriginalPrice,
    required this.discountPercentage,
    required this.currency,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.purchaseCount = 0,
  });

  // Validation
  bool get isValid => products.length >= 2 && products.length <= 6;
  int get productCount => products.length;

  factory Bundle.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Bundle(
      id: doc.id,
      shopId: data['shopId'] ?? '',
      products: (data['products'] as List<dynamic>? ?? [])
          .map((item) => BundleProduct.fromMap(item))
          .toList(),
      totalBundlePrice: (data['totalBundlePrice'] ?? 0.0).toDouble(),
      totalOriginalPrice: (data['totalOriginalPrice'] ?? 0.0).toDouble(),
      discountPercentage: (data['discountPercentage'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'TL',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
      purchaseCount: data['purchaseCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shopId': shopId,
      'products': products.map((p) => p.toMap()).toList(),
      'totalBundlePrice': totalBundlePrice,
      'totalOriginalPrice': totalOriginalPrice,
      'discountPercentage': discountPercentage,
      'currency': currency,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isActive': isActive,
      'purchaseCount': purchaseCount,
    };
  }

  Bundle copyWith({
    String? id,
    String? shopId,
    List<BundleProduct>? products,
    double? totalBundlePrice,
    double? totalOriginalPrice,
    double? discountPercentage,
    String? currency,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    int? purchaseCount,
  }) {
    return Bundle(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      products: products ?? this.products,
      totalBundlePrice: totalBundlePrice ?? this.totalBundlePrice,
      totalOriginalPrice: totalOriginalPrice ?? this.totalOriginalPrice,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      purchaseCount: purchaseCount ?? this.purchaseCount,
    );
  }
}

class BundleProduct {
  final String productId;
  final String productName;
  final double originalPrice;
  final String? imageUrl;

  BundleProduct({
    required this.productId,
    required this.productName,
    required this.originalPrice,
    this.imageUrl,
  });

  factory BundleProduct.fromMap(Map<String, dynamic> map) {
    return BundleProduct(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      originalPrice: (map['originalPrice'] ?? 0.0).toDouble(),
      imageUrl: map['imageUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'originalPrice': originalPrice,
      'imageUrl': imageUrl,
    };
  }
}
