// lib/models/receipt.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../generated/l10n/app_localizations.dart';

class Receipt {
  final String receiptId;
  final String orderId;
  final double totalPrice;
  final double itemsSubtotal;
  final double deliveryPrice;
  final String currency;
  final DateTime timestamp;
  final String paymentMethod;
  final String? deliveryOption;
  final String? receiptUrl;
  final String? filePath;
  // Boost receipt fields
  final String? receiptType;
  final int? boostDuration;
  final int? itemCount;
  // Coupon/Benefit fields
  final String? couponCode;
  final double couponDiscount;
  final bool freeShippingApplied;
  final double originalDeliveryPrice;
  final String? adType;
  final String? adDuration;
  final double? taxAmount;

  Receipt({
    required this.receiptId,
    required this.orderId,
    required this.totalPrice,
    required this.itemsSubtotal,
    required this.deliveryPrice,
    required this.currency,
    required this.timestamp,
    required this.paymentMethod,
    this.adType,
    this.adDuration,
    this.taxAmount,
    this.deliveryOption,
    this.receiptUrl,
    this.receiptType,
    this.boostDuration,
    this.itemCount,
    this.filePath,
    this.couponCode,
    this.couponDiscount = 0.0,
    this.freeShippingApplied = false,
    this.originalDeliveryPrice = 0.0,
  });

  factory Receipt.fromDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Handle receiptUrl - it might be an array or a string
    String? receiptUrlValue;
    if (data['receiptUrl'] != null) {
      if (data['receiptUrl'] is List) {
        receiptUrlValue = (data['receiptUrl'] as List).isNotEmpty
            ? data['receiptUrl'][0].toString()
            : null;
      } else if (data['receiptUrl'] is String) {
        receiptUrlValue = data['receiptUrl'] as String;
      }
    }

    return Receipt(
      receiptId: doc.id,
      orderId: data['orderId'] ?? '',
      totalPrice: (data['totalPrice'] as num?)?.toDouble() ?? 0.0,
      itemsSubtotal: (data['itemsSubtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryPrice: (data['deliveryPrice'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'TL',
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      paymentMethod: data['paymentMethod'] ?? 'Card',
      deliveryOption: data['deliveryOption'],
      receiptUrl: receiptUrlValue,
      receiptType: data['receiptType'] ?? 'order',
      boostDuration: data['boostDuration'] as int?,
      itemCount: data['itemCount'] as int?,
      adType: data['adType'] as String?,
      adDuration: data['adDuration'] as String?,
      taxAmount: (data['taxAmount'] as num?)?.toDouble() ?? 0.0,
      filePath: data['filePath'] as String?,
      // Coupon/Benefit fields
      couponCode: data['couponCode'] as String?,
      couponDiscount: (data['couponDiscount'] as num?)?.toDouble() ?? 0.0,
      freeShippingApplied: data['freeShippingApplied'] as bool? ?? false,
      originalDeliveryPrice:
          (data['originalDeliveryPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }

  bool get isBoostReceipt => receiptType == 'boost';
  bool get isAdReceipt => receiptType == 'ad';

  // Calculate total savings
  double get totalSavings {
    final shippingSavings = freeShippingApplied ? originalDeliveryPrice : 0.0;
    return couponDiscount + shippingSavings;
  }

  // Check if any discount was applied
  bool get hasDiscounts => couponDiscount > 0 || freeShippingApplied;

  String get formattedDeliveryOption {
    if (deliveryOption == null) return 'N/A';

    switch (deliveryOption) {
      case 'gelal':
        return 'Gel Al (Pick Up)';
      case 'express':
        return 'Express Delivery';
      case 'normal':
      default:
        return 'Normal Delivery';
    }
  }

  String getLocalizedDeliveryOption(AppLocalizations l10n) {
    if (deliveryOption == null) return 'N/A';

    switch (deliveryOption) {
      case 'gelal':
        return l10n.deliveryOption1 ?? 'Gel Al (Pick Up)';
      case 'express':
        return l10n.deliveryOption2 ?? 'Express Delivery';
      case 'normal':
      default:
        return l10n.deliveryOption3 ?? 'Normal Delivery';
    }
  }

  String getFormattedBoostDuration(AppLocalizations l10n) {
    if (boostDuration == null) return 'N/A';

    if (boostDuration! < 60) {
      return '$boostDuration ${l10n.minutes ?? 'minutes'}';
    } else if (boostDuration! < 1440) {
      final hours = (boostDuration! / 60).floor();
      final minutes = boostDuration! % 60;
      if (minutes == 0) {
        return '$hours ${l10n.hours ?? 'hours'}';
      }
      return '$hours ${l10n.hours ?? 'hours'} $minutes ${l10n.minutes ?? 'minutes'}';
    } else {
      final days = (boostDuration! / 1440).floor();
      return '$days ${l10n.days ?? 'days'}';
    }
  }

  String getReceiptTypeDisplay(AppLocalizations l10n) {
    if (isBoostReceipt) return l10n.boost ?? 'Boost';
    if (isAdReceipt) return l10n.ad;
    return l10n.orders ?? 'Order';
  }
}
