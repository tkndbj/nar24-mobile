import 'package:cloud_firestore/cloud_firestore.dart';

class FoodAddress {
  final String? addressId;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String mainRegion;
  final String? phoneNumber;
  final GeoPoint? location;

  const FoodAddress({
    this.addressId,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.mainRegion,
    this.phoneNumber,
    this.location,
  });

  factory FoodAddress.fromMap(Map<String, dynamic> map) {
    GeoPoint? loc;
    final l = map['location'];
    if (l is GeoPoint) {
      loc = l;
    } else if (l is Map) {
      loc = GeoPoint(
        (l['latitude'] as num).toDouble(),
        (l['longitude'] as num).toDouble(),
      );
    }

    return FoodAddress(
      addressId: map['addressId'] as String?,
      addressLine1: (map['addressLine1'] as String?) ?? '',
      addressLine2: map['addressLine2'] as String?,
      city: (map['city'] as String?) ?? '',
      mainRegion: (map['mainRegion'] as String?) ?? '',
      phoneNumber: map['phoneNumber'] as String?,
      location: loc,
    );
  }

  Map<String, dynamic> toMap() => {
        if (addressId != null) 'addressId': addressId,
        'addressLine1': addressLine1,
        if (addressLine2 != null) 'addressLine2': addressLine2,
        'city': city,
        'mainRegion': mainRegion,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (location != null) 'location': location,
      };

  /// Short display label: "MainRegion > City > AddressLine1"
  String get displayLabel {
    return [mainRegion, city, addressLine1]
        .where((s) => s.isNotEmpty)
        .join(' > ');
  }

  @override
  String toString() => 'FoodAddress(city: $city, mainRegion: $mainRegion)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodAddress &&
          other.addressId == addressId &&
          other.city == city &&
          other.mainRegion == mainRegion;

  @override
  int get hashCode => Object.hash(addressId, city, mainRegion);
}
