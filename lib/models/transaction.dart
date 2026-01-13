// lib/models/transaction.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final String productId;
  final String productName;
  final double price;
  final String currency;
  final Timestamp timestamp;
  final String paymentMethod;
  final String sellerId;
  final String buyerId;
  final String shipmentStatus;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String phoneNumber;
  final String country;
  final GeoPoint location;
  final int quantity;
  final String role; // 'buyer' or 'seller'
  final String? receiptId;

  TransactionModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    required this.currency,
    required this.timestamp,
    required this.paymentMethod,
    required this.sellerId,
    required this.buyerId,
    required this.shipmentStatus,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.phoneNumber,
    required this.country,
    required this.location,
    required this.quantity,
    required this.role,
    this.receiptId,
  });

  // Factory constructor to create a TransactionModel from Firestore document
  factory TransactionModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'TRY',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      paymentMethod: data['paymentMethod'] ?? '',
      sellerId: data['sellerId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      shipmentStatus: data['shipmentStatus'] ?? 'Pending',
      addressLine1: data['addressLine1'] ?? '',
      addressLine2: data['addressLine2'] ?? '',
      city: data['city'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      country: data['country'] ?? '',
      location: data['location'] ?? GeoPoint(0, 0),
      quantity: data['quantity'] ?? 1,
      role: data['role'] ?? '',
      receiptId: data['receiptId'],
    );
  }

  // Method to convert TransactionModel to a Map (for Firestore)
  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'currency': currency,
      'timestamp': timestamp,
      'paymentMethod': paymentMethod,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'shipmentStatus': shipmentStatus,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'phoneNumber': phoneNumber,
      'country': country,
      'location': location,
      'quantity': quantity,
      'role': role,
      'receiptId': receiptId,
    };
  }
}
