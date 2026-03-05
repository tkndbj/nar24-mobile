// models/food.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// An extra/add-on option defined on a food document.
class FoodExtra {
  final String name;
  final double price;

  const FoodExtra({required this.name, required this.price});

  factory FoodExtra.fromMap(dynamic map) {
    if (map is String) {
      // Legacy: extras stored as plain strings (no price)
      return FoodExtra(name: map, price: 0);
    }
    final m = Map<String, dynamic>.from(map as Map);
    return FoodExtra(
      name: (m['name'] as String?) ?? '',
      price: (m['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'price': price};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodExtra && other.name == name && other.price == price;

  @override
  int get hashCode => Object.hash(name, price);

  @override
  String toString() => 'FoodExtra(name: $name, price: $price)';
}

class Food {
  final String id;
  final String name;
  final String? description;
  final String foodCategory;
  final String foodType;
  final String? imageUrl;
  final bool isAvailable;
  final int? preparationTime;
  final double price;
  final String restaurantId;

  /// Available extras for this food item (each with name + price).
  final List<FoodExtra>? extras;

  // Discount fields
  final int? discountPercentage;
  final double? originalPrice;
  final DateTime? discountStartDate;
  final DateTime? discountEndDate;

  /// Whether the food currently has an active discount.
  bool get hasActiveDiscount {
    if (discountPercentage == null || discountPercentage! <= 0) return false;
    final now = DateTime.now();
    if (discountStartDate != null && now.isBefore(discountStartDate!)) {
      return false;
    }
    if (discountEndDate != null && now.isAfter(discountEndDate!)) return false;
    return true;
  }

  const Food({
    required this.id,
    required this.name,
    this.description,
    required this.foodCategory,
    required this.foodType,
    this.imageUrl,
    required this.isAvailable,
    this.preparationTime,
    required this.price,
    required this.restaurantId,
    this.extras,
    this.discountPercentage,
    this.originalPrice,
    this.discountStartDate,
    this.discountEndDate,
  });

  factory Food.fromMap(Map<String, dynamic> map, {String? id}) {
    final discount = map['discount'] as Map<String, dynamic>?;

    return Food(
      id: id ?? (map['id'] as String? ?? ''),
      name: (map['name'] as String?) ?? '',
      description: map['description'] as String?,
      foodCategory: (map['foodCategory'] as String?) ?? '',
      foodType: (map['foodType'] as String?) ?? '',
      imageUrl: map['imageUrl'] as String?,
      isAvailable: (map['isAvailable'] as bool?) ?? false,
      preparationTime: (map['preparationTime'] as num?)?.toInt(),
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      restaurantId: (map['restaurantId'] as String?) ?? '',
      extras:
          (map['extras'] as List<dynamic>?)?.map((e) => FoodExtra.fromMap(e)).toList(),
      discountPercentage: (discount?['percentage'] as num?)?.toInt(),
      originalPrice: (discount?['originalPrice'] as num?)?.toDouble(),
      discountStartDate:
          (discount?['startDate'] as Timestamp?)?.toDate(),
      discountEndDate:
          (discount?['endDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'foodCategory': foodCategory,
        'foodType': foodType,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'isAvailable': isAvailable,
        if (preparationTime != null) 'preparationTime': preparationTime,
        'price': price,
        'restaurantId': restaurantId,
        if (extras != null) 'extras': extras!.map((e) => e.toMap()).toList(),
        if (discountPercentage != null)
          'discount': {
            'percentage': discountPercentage,
            if (originalPrice != null) 'originalPrice': originalPrice,
            if (discountStartDate != null) 'startDate': discountStartDate,
            if (discountEndDate != null) 'endDate': discountEndDate,
          },
      };

  Food copyWith({
    String? id,
    String? name,
    String? description,
    String? foodCategory,
    String? foodType,
    String? imageUrl,
    bool? isAvailable,
    int? preparationTime,
    double? price,
    String? restaurantId,
    List<FoodExtra>? extras,
    int? discountPercentage,
    double? originalPrice,
    DateTime? discountStartDate,
    DateTime? discountEndDate,
  }) {
    return Food(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      foodCategory: foodCategory ?? this.foodCategory,
      foodType: foodType ?? this.foodType,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      preparationTime: preparationTime ?? this.preparationTime,
      price: price ?? this.price,
      restaurantId: restaurantId ?? this.restaurantId,
      extras: extras ?? this.extras,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      originalPrice: originalPrice ?? this.originalPrice,
      discountStartDate: discountStartDate ?? this.discountStartDate,
      discountEndDate: discountEndDate ?? this.discountEndDate,
    );
  }

  @override
  String toString() => 'Food(id: $id, name: $name, price: $price)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Food && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
