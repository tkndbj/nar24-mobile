import 'package:cloud_firestore/cloud_firestore.dart';

enum FoodOrderStatus {
  pending,
  accepted,
  rejected,
  preparing,
  ready,
  outForDelivery,
  delivered,
  completed,
  cancelled,
}

extension FoodOrderStatusX on FoodOrderStatus {
  static FoodOrderStatus fromString(String? value) {
    switch (value) {
      case 'accepted':
      case 'assigned':
        return FoodOrderStatus.accepted;
      case 'rejected':
        return FoodOrderStatus.rejected;
      case 'preparing':
        return FoodOrderStatus.preparing;
      case 'ready':
        return FoodOrderStatus.ready;
      case 'out_for_delivery':
      case 'outForDelivery':
        return FoodOrderStatus.outForDelivery;
      case 'delivered':
        return FoodOrderStatus.delivered;
      case 'completed':
        return FoodOrderStatus.completed;
      case 'cancelled':
        return FoodOrderStatus.cancelled;
      case 'pending':
      default:
        return FoodOrderStatus.pending;
    }
  }
}

class FoodOrderItem {
  final String foodId;
  final String name;
  final int quantity;
  final double price;
  final List<FoodOrderExtra> extras;

  const FoodOrderItem({
    required this.foodId,
    required this.name,
    required this.quantity,
    required this.price,
    required this.extras,
  });

  factory FoodOrderItem.fromMap(Map<String, dynamic> map) {
    final rawExtras = map['extras'];
    final extras = rawExtras is List
        ? rawExtras
            .whereType<Map<String, dynamic>>()
            .map(FoodOrderExtra.fromMap)
            .toList()
        : <FoodOrderExtra>[];

    return FoodOrderItem(
      foodId: map['foodId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      extras: extras,
    );
  }
}

class FoodOrderExtra {
  final String name;
  final double price;
  final int quantity;

  const FoodOrderExtra({
    required this.name,
    required this.price,
    required this.quantity,
  });

  factory FoodOrderExtra.fromMap(Map<String, dynamic> map) {
    return FoodOrderExtra(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

class FoodOrder {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String? restaurantProfileImage;
  final List<FoodOrderItem> items;
  final double totalPrice;
  final String currency;
  final String paymentMethod;
  final bool isPaid;
  final FoodOrderStatus status;
  final Timestamp createdAt;
  final Timestamp?
      lastInformedAt; // ← order-level courier notification timestamp

  const FoodOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantProfileImage,
    required this.items,
    required this.totalPrice,
    required this.currency,
    required this.paymentMethod,
    required this.isPaid,
    required this.status,
    required this.createdAt,
    this.lastInformedAt,
  });

  factory FoodOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    final rawItems = d['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(FoodOrderItem.fromMap)
            .toList()
        : <FoodOrderItem>[];

    return FoodOrder(
      id: doc.id,
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      restaurantProfileImage: d['restaurantProfileImage'] as String?,
      items: items,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0.0,
      currency: d['currency'] as String? ?? 'TL',
      paymentMethod: d['paymentMethod'] as String? ?? '',
      isPaid: d['isPaid'] as bool? ?? false,
      status: FoodOrderStatusX.fromString(d['status'] as String?),
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
      lastInformedAt: d['lastInformedAt'] as Timestamp?, // ← NEW
    );
  }

  /// Returns the first 2 item names as a preview string (e.g. "2× Burger, Fries +1")
  String get itemsPreview {
    final preview = items.take(2).map((i) {
      return i.quantity > 1 ? '${i.quantity}× ${i.name}' : i.name;
    }).join(', ');
    final extra = items.length > 2 ? ' +${items.length - 2}' : '';
    return '$preview$extra';
  }
}
