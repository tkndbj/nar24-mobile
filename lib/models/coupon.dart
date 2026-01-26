// lib/models/coupon.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum CouponStatus {
  active,
  used,
  expired,
}

class Coupon {
  final String id;
  final String userId;
  final double amount;
  final String currency;
  final String? code;
  final String? description;
  final Timestamp createdAt;
  final String createdBy;
  final Timestamp? expiresAt;
  final Timestamp? usedAt;
  final String? orderId;
  final bool isUsed;

  Coupon({
    required this.id,
    required this.userId,
    required this.amount,
    required this.currency,
    this.code,
    this.description,
    required this.createdAt,
    required this.createdBy,
    this.expiresAt,
    this.usedAt,
    this.orderId,
    required this.isUsed,
  });

  /// Check if coupon is currently valid for use
  CouponStatus get status {
    if (isUsed) return CouponStatus.used;
    if (expiresAt != null && expiresAt!.toDate().isBefore(DateTime.now())) {
      return CouponStatus.expired;
    }
    return CouponStatus.active;
  }

  bool get isValid => status == CouponStatus.active;

  /// Days until expiration (null if no expiration)
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now();
    final expiry = expiresAt!.toDate();
    if (expiry.isBefore(now)) return 0;
    return expiry.difference(now).inDays;
  }

  factory Coupon.fromJson(Map<String, dynamic> json, String id) {
    return Coupon(
      id: id,
      userId: json['userId'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'TL',
      code: json['code'] as String?,
      description: json['description'] as String?,
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      createdBy: json['createdBy'] as String? ?? '',
      expiresAt: json['expiresAt'] as Timestamp?,
      usedAt: json['usedAt'] as Timestamp?,
      orderId: json['orderId'] as String?,
      isUsed: json['isUsed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'amount': amount,
      'currency': currency,
      'code': code,
      'description': description,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'expiresAt': expiresAt,
      'usedAt': usedAt,
      'orderId': orderId,
      'isUsed': isUsed,
    };
  }

  Coupon copyWith({
    String? id,
    String? userId,
    double? amount,
    String? currency,
    String? code,
    String? description,
    Timestamp? createdAt,
    String? createdBy,
    Timestamp? expiresAt,
    Timestamp? usedAt,
    String? orderId,
    bool? isUsed,
  }) {
    return Coupon(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      code: code ?? this.code,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      expiresAt: expiresAt ?? this.expiresAt,
      usedAt: usedAt ?? this.usedAt,
      orderId: orderId ?? this.orderId,
      isUsed: isUsed ?? this.isUsed,
    );
  }

  @override
  String toString() {
    return 'Coupon(id: $id, amount: $amount $currency, isUsed: $isUsed, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Coupon && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
