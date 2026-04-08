// lib/services/click_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class ClickService {
  static final ClickService instance = ClickService._();
  ClickService._();

  final _analytics = FirebaseAnalytics.instance;
  final _firestore = FirebaseFirestore.instance;

  // Cooldown to prevent spam
  final Map<String, DateTime> _lastClick = {};
  static const _cooldown = Duration(seconds: 1);
  static const _maxCooldownEntries = 500;

  Future<void> trackClick({
    required String productId,
    String? shopId,
    required String collection, // 'products' or 'shop_products'
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? brand,
    String? gender,
  }) async {
    // 1. Cooldown check
    final now = DateTime.now();
    if (_lastClick[productId] != null &&
        now.difference(_lastClick[productId]!) < _cooldown) {
      return;
    }
    _lastClick[productId] = now;

    // Prevent unbounded memory growth
    if (_lastClick.length > _maxCooldownEntries) {
      final sorted = _lastClick.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in sorted.take(_lastClick.length - _maxCooldownEntries)) {
        _lastClick.remove(entry.key);
      }
    }

    // 2. Firebase Analytics (the real tracking - free, scales infinitely)
    _analytics.logEvent(
      name: 'product_click',
      parameters: {
        'product_id': productId,
        'shop_id': shopId ?? '',
        'collection': collection,
        'product_name': (productName ?? '').length > 100
            ? productName!.substring(0, 100)
            : (productName ?? ''),
        'category': category ?? '',
        'subcategory': subcategory ?? '',
        'subsubcategory': subsubcategory ?? '',
        'brand': brand ?? '',
        'gender': gender ?? '',
      },
    );

    // 3. Increment display counter (fire-and-forget, GA4 has the real data)
    _incrementClickCount(productId, collection, shopId);
  }

  Future<void> trackShopClick(String shopId) async {
  final now = DateTime.now();
  if (_lastClick[shopId] != null &&
      now.difference(_lastClick[shopId]!) < _cooldown) {
    return;
  }
  _lastClick[shopId] = now;

  if (_lastClick.length > _maxCooldownEntries) {
    final sorted = _lastClick.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in sorted.take(_lastClick.length - _maxCooldownEntries)) {
      _lastClick.remove(entry.key);
    }
  }

  _analytics.logEvent(
    name: 'shop_click',
    parameters: {
      'shop_id': shopId,
    },
  );

  await _incrementShopClickCount(shopId);
}

Future<void> _incrementShopClickCount(String shopId) async {
  final shardIndex = shopId.hashCode.abs() % 10;

  try {
    final batch = _firestore.batch();

    batch.set(
      _firestore
          .collection('shops')
          .doc(shopId)
          .collection('click_shards')
          .doc('shard_$shardIndex'),
      {'count': FieldValue.increment(1)},
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection('_dirty_clicks').doc(shopId),
      {
        'collection': 'shops',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  } catch (_) {}
}

 Future<void> _incrementClickCount(
  String productId,
  String collection,
  String? shopId,
) async {
  final shardIndex = productId.hashCode.abs() % 10;

  try {
    final batch = _firestore.batch();

    batch.set(
      _firestore
          .collection(collection)
          .doc(productId)
          .collection('click_shards')
          .doc('shard_$shardIndex'),
      {'count': FieldValue.increment(1)},
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection('_dirty_clicks').doc(productId),
      {
        'collection': collection,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // REMOVED: shop-level tracking from product clicks

    await batch.commit();
  } catch (_) {}
}
}
