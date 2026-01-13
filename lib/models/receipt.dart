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
  // NEW: Boost receipt fields
  final String? receiptType; // 'order' or 'boost'
  final int? boostDuration; // in minutes
  final int? itemCount; // number of items boosted

  Receipt({
    required this.receiptId,
    required this.orderId,
    required this.totalPrice,
    required this.itemsSubtotal,
    required this.deliveryPrice,
    required this.currency,
    required this.timestamp,
    required this.paymentMethod,
    this.deliveryOption,
    this.receiptUrl,
    this.receiptType,
    this.boostDuration,
    this.itemCount,
    this.filePath,
  });

  factory Receipt.fromDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Handle receiptUrl - it might be an array or a string
    String? receiptUrlValue;
    if (data['receiptUrl'] != null) {
      if (data['receiptUrl'] is List) {
        // If it's a list, take the first element
        receiptUrlValue = (data['receiptUrl'] as List).isNotEmpty
            ? data['receiptUrl'][0].toString()
            : null;
      } else if (data['receiptUrl'] is String) {
        // If it's already a string, use it directly
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
      deliveryOption: data['deliveryOption'], // Can be null for boost receipts
      receiptUrl: receiptUrlValue,
      // NEW: Boost receipt fields
      receiptType: data['receiptType'] ?? 'order', // Default to 'order' for backwards compatibility
      boostDuration: data['boostDuration'] as int?,
      itemCount: data['itemCount'] as int?,
      filePath: data['filePath'] as String?,
    );
  }

  // Helper to check if this is a boost receipt
  bool get isBoostReceipt => receiptType == 'boost';

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

  // NEW: Get formatted boost duration
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

  // NEW: Get receipt type display name
  String getReceiptTypeDisplay(AppLocalizations l10n) {
    if (isBoostReceipt) {
      return l10n.boost ?? 'Boost';
    }
    return l10n.orders ?? 'Order';
  }
}