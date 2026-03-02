// models/food.dart

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

  /// List of available extra option keys for this food item,
  /// e.g. ["Extra Cheese", "Jalapeños"].
  /// The full extra definitions (price etc.) live in the restaurant document.
  final List<String>? extras;

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
  });

  factory Food.fromMap(Map<String, dynamic> map, {String? id}) {
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
          (map['extras'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
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
        if (extras != null) 'extras': extras,
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
    List<String>? extras,
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
