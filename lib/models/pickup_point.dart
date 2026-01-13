import 'package:cloud_firestore/cloud_firestore.dart';

class PickupPoint {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String contactPerson;
  final String contactPhone;
  final String operatingHours;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PickupPoint({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.contactPerson,
    required this.contactPhone,
    required this.operatingHours,
    required this.isActive,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PickupPoint.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return PickupPoint(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      contactPerson: data['contactPerson'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      operatingHours: data['operatingHours'] ?? '',
      isActive: data['isActive'] ?? false,
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'contactPerson': contactPerson,
      'contactPhone': contactPhone,
      'operatingHours': operatingHours,
      'isActive': isActive,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  PickupPoint copyWith({
    String? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    String? contactPerson,
    String? contactPhone,
    String? operatingHours,
    bool? isActive,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PickupPoint(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactPerson: contactPerson ?? this.contactPerson,
      contactPhone: contactPhone ?? this.contactPhone,
      operatingHours: operatingHours ?? this.operatingHours,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'PickupPoint(id: $id, name: $name, address: $address, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PickupPoint && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
