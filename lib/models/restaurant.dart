// models/restaurant.dart

class WorkingHours {
  /// "HH:mm" format, e.g. "08:00"
  final String open;

  /// "HH:mm" format, e.g. "22:00"
  final String close;

  const WorkingHours({
    required this.open,
    required this.close,
  });

  factory WorkingHours.fromMap(Map<String, dynamic> map) {
    return WorkingHours(
      open: (map['open'] as String?) ?? '',
      close: (map['close'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'open': open,
        'close': close,
      };

  @override
  String toString() => 'WorkingHours(open: $open, close: $close)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkingHours && other.open == open && other.close == close;

  @override
  int get hashCode => Object.hash(open, close);
}

class Restaurant {
  final String id;
  final String name;
  final String? address;
  final double? averageRating;
  final int? reviewCount;
  final List<String>? categories;
  final String? contactNo;
  final List<String>? coverImageUrls;
  final String? profileImageUrl;
  final int? followerCount;
  final bool? isActive;
  final bool? isBoosted;
  final String? ownerId;
  final double? latitude;
  final double? longitude;
  final int? clickCount;
  final List<String>? foodType;
  final List<String>? cuisineTypes;
  final List<String>? workingDays;
  final WorkingHours? workingHours;

  const Restaurant({
    required this.id,
    required this.name,
    this.address,
    this.averageRating,
    this.reviewCount,
    this.categories,
    this.contactNo,
    this.coverImageUrls,
    this.profileImageUrl,
    this.followerCount,
    this.isActive,
    this.isBoosted,
    this.ownerId,
    this.latitude,
    this.longitude,
    this.clickCount,
    this.foodType,
    this.cuisineTypes,
    this.workingDays,
    this.workingHours,
  });

  factory Restaurant.fromMap(Map<String, dynamic> map, {String? id}) {
    return Restaurant(
      id: id ?? (map['id'] as String? ?? ''),
      name: (map['name'] as String?) ?? '',
      address: map['address'] as String?,
      averageRating: (map['averageRating'] as num?)?.toDouble(),
      reviewCount: (map['reviewCount'] as num?)?.toInt(),
      categories: (map['categories'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      contactNo: map['contactNo'] as String?,
      coverImageUrls: (map['coverImageUrls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      profileImageUrl: map['profileImageUrl'] as String?,
      followerCount: (map['followerCount'] as num?)?.toInt(),
      isActive: map['isActive'] as bool?,
      isBoosted: map['isBoosted'] as bool?,
      ownerId: map['ownerId'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      clickCount: (map['clickCount'] as num?)?.toInt(),
      foodType: (map['foodType'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      cuisineTypes: (map['cuisineTypes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      workingDays: (map['workingDays'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      workingHours: map['workingHours'] != null
          ? WorkingHours.fromMap(
              Map<String, dynamic>.from(map['workingHours'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (address != null) 'address': address,
        if (averageRating != null) 'averageRating': averageRating,
        if (reviewCount != null) 'reviewCount': reviewCount,
        if (categories != null) 'categories': categories,
        if (contactNo != null) 'contactNo': contactNo,
        if (coverImageUrls != null) 'coverImageUrls': coverImageUrls,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (followerCount != null) 'followerCount': followerCount,
        if (isActive != null) 'isActive': isActive,
        if (isBoosted != null) 'isBoosted': isBoosted,
        if (ownerId != null) 'ownerId': ownerId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (clickCount != null) 'clickCount': clickCount,
        if (foodType != null) 'foodType': foodType,
        if (cuisineTypes != null) 'cuisineTypes': cuisineTypes,
        if (workingDays != null) 'workingDays': workingDays,
        if (workingHours != null) 'workingHours': workingHours!.toMap(),
      };

  Restaurant copyWith({
    String? id,
    String? name,
    String? address,
    double? averageRating,
    int? reviewCount,
    List<String>? categories,
    String? contactNo,
    List<String>? coverImageUrls,
    String? profileImageUrl,
    int? followerCount,
    bool? isActive,
    bool? isBoosted,
    String? ownerId,
    double? latitude,
    double? longitude,
    int? clickCount,
    List<String>? foodType,
    List<String>? cuisineTypes,
    List<String>? workingDays,
    WorkingHours? workingHours,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      categories: categories ?? this.categories,
      contactNo: contactNo ?? this.contactNo,
      coverImageUrls: coverImageUrls ?? this.coverImageUrls,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      followerCount: followerCount ?? this.followerCount,
      isActive: isActive ?? this.isActive,
      isBoosted: isBoosted ?? this.isBoosted,
      ownerId: ownerId ?? this.ownerId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      clickCount: clickCount ?? this.clickCount,
      foodType: foodType ?? this.foodType,
      cuisineTypes: cuisineTypes ?? this.cuisineTypes,
      workingDays: workingDays ?? this.workingDays,
      workingHours: workingHours ?? this.workingHours,
    );
  }

  @override
  String toString() => 'Restaurant(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Restaurant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
