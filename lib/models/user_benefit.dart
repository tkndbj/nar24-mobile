// lib/models/user_benefit.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum BenefitType {
  freeShipping,
  // Add more benefit types as needed in the future
  // percentageDiscount,
  // prioritySupport,
}

enum BenefitStatus {
  active,
  used,
  expired,
}

class UserBenefit {
  final String id;
  final String userId;
  final BenefitType type;
  final String? description;
  final Timestamp createdAt;
  final String createdBy;
  final Timestamp? expiresAt;
  final Timestamp? usedAt;
  final String? orderId;
  final bool isUsed;
  final Map<String, dynamic>? metadata; // For future extensibility

  UserBenefit({
    required this.id,
    required this.userId,
    required this.type,
    this.description,
    required this.createdAt,
    required this.createdBy,
    this.expiresAt,
    this.usedAt,
    this.orderId,
    required this.isUsed,
    this.metadata,
  });

  /// Check if benefit is currently valid for use
  BenefitStatus get status {
    if (isUsed) return BenefitStatus.used;
    if (expiresAt != null && expiresAt!.toDate().isBefore(DateTime.now())) {
      return BenefitStatus.expired;
    }
    return BenefitStatus.active;
  }

  bool get isValid => status == BenefitStatus.active;

  /// Days until expiration (null if no expiration)
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now();
    final expiry = expiresAt!.toDate();
    if (expiry.isBefore(now)) return 0;
    return expiry.difference(now).inDays;
  }

  /// Human-readable type name
  String get typeName {
    switch (type) {
      case BenefitType.freeShipping:
        return 'Free Shipping';
    }
  }

  /// Icon name for UI
  String get iconName {
    switch (type) {
      case BenefitType.freeShipping:
        return 'local_shipping';
    }
  }

  static BenefitType _parseType(String? typeStr) {
    switch (typeStr) {
      case 'free_shipping':
        return BenefitType.freeShipping;
      default:
        return BenefitType.freeShipping;
    }
  }

  static String _typeToString(BenefitType type) {
    switch (type) {
      case BenefitType.freeShipping:
        return 'free_shipping';
    }
  }

  factory UserBenefit.fromJson(Map<String, dynamic> json, String id) {
    return UserBenefit(
      id: id,
      userId: json['userId'] as String? ?? '',
      type: _parseType(json['type'] as String?),
      description: json['description'] as String?,
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      createdBy: json['createdBy'] as String? ?? '',
      expiresAt: json['expiresAt'] as Timestamp?,
      usedAt: json['usedAt'] as Timestamp?,
      orderId: json['orderId'] as String?,
      isUsed: json['isUsed'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'type': _typeToString(type),
      'description': description,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'expiresAt': expiresAt,
      'usedAt': usedAt,
      'orderId': orderId,
      'isUsed': isUsed,
      'metadata': metadata,
    };
  }

  UserBenefit copyWith({
    String? id,
    String? userId,
    BenefitType? type,
    String? description,
    Timestamp? createdAt,
    String? createdBy,
    Timestamp? expiresAt,
    Timestamp? usedAt,
    String? orderId,
    bool? isUsed,
    Map<String, dynamic>? metadata,
  }) {
    return UserBenefit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      expiresAt: expiresAt ?? this.expiresAt,
      usedAt: usedAt ?? this.usedAt,
      orderId: orderId ?? this.orderId,
      isUsed: isUsed ?? this.isUsed,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'UserBenefit(id: $id, type: $type, isUsed: $isUsed, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserBenefit && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
