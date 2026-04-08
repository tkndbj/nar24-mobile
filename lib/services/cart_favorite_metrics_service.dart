import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class MetricsEventService {
  static final MetricsEventService instance = MetricsEventService._();
  MetricsEventService._();

  final _firestore = FirebaseFirestore.instance;
  final _analytics = FirebaseAnalytics.instance;
  final _auth = FirebaseAuth.instance;

  final Map<String, DateTime> _lastActionTime = {};
  static const _actionCooldown = Duration(seconds: 1);
  static const _maxCooldownEntries = 500;

  Future<void> initialize() async {
    debugPrint('✅ MetricsEventService initialized');
  }

  Future<void> flush() async {}

  Future<void> dispose() async {}

  // ── Cart ──────────────────────────────────────────────────────────────────

  Future<void> logCartAdded({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('cart_added:$productId')) return;
    _logAnalytics('cart_added', productId, shopId);
    await _incrementMetric(productId, shopId, cart: 1);
  }

  Future<void> logCartRemoved({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('cart_removed:$productId')) return;
    _logAnalytics('cart_removed', productId, shopId);
    await _incrementMetric(productId, shopId, cart: -1);
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  Future<void> logFavoriteAdded({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('favorite_added:$productId')) return;
    _logAnalytics('favorite_added', productId, shopId);
    await _incrementMetric(productId, shopId, favorite: 1);
  }

  Future<void> logFavoriteRemoved({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('favorite_removed:$productId')) return;
    _logAnalytics('favorite_removed', productId, shopId);
    await _incrementMetric(productId, shopId, favorite: -1);
  }

  // ── Batch operations ──────────────────────────────────────────────────────

  Future<void> logBatchCartRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) async {
    if (_auth.currentUser == null) return;

    final chunks = _chunkList(productIds, 200);

    for (final chunk in chunks) {
      final batch = _firestore.batch();

      for (final id in chunk) {
        if (!_checkCooldown('cart_removed:$id')) continue;
        _logAnalytics('cart_removed', id, shopIds[id]);

        final shopId = shopIds[id];
        final collection = shopId != null ? 'shop_products' : 'products';

        batch.update(
          _firestore.collection(collection).doc(id),
          {
            'cartCount': FieldValue.increment(-1),
            'metricsUpdatedAt': FieldValue.serverTimestamp(),
          },
        );

        if (shopId != null) {
          batch.update(
            _firestore.collection('shops').doc(shopId),
            {'metrics.lastUpdated': FieldValue.serverTimestamp()},
          );
        }
      }

      try {
        await batch.commit();
      } catch (e) {
        debugPrint('⚠️ MetricsEventService: batch cart removal failed — $e');
      }
    }
  }

  Future<void> logBatchFavoriteRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) async {
    if (_auth.currentUser == null) return;

    final chunks = _chunkList(productIds, 200);

    for (final chunk in chunks) {
      final batch = _firestore.batch();

      for (final id in chunk) {
        if (!_checkCooldown('favorite_removed:$id')) continue;
        _logAnalytics('favorite_removed', id, shopIds[id]);

        final shopId = shopIds[id];
        final collection = shopId != null ? 'shop_products' : 'products';

        batch.update(
          _firestore.collection(collection).doc(id),
          {
            'favoritesCount': FieldValue.increment(-1),
            'metricsUpdatedAt': FieldValue.serverTimestamp(),
          },
        );

        if (shopId != null) {
          batch.update(
            _firestore.collection('shops').doc(shopId),
            {'metrics.lastUpdated': FieldValue.serverTimestamp()},
          );
        }
      }

      try {
        await batch.commit();
      } catch (e) {
        debugPrint('⚠️ MetricsEventService: batch favorite removal failed — $e');
      }
    }
  }

  Future<void> logBatchEvents({
    required List<Map<String, dynamic>> events,
  }) async {
    for (final event in events) {
      final type = event['type'] as String?;
      final productId = event['productId'] as String?;
      final shopId = event['shopId'] as String?;
      if (type == null || productId == null) continue;

      switch (type) {
        case 'cart_added':
          await logCartAdded(productId: productId, shopId: shopId);
          break;
        case 'cart_removed':
          await logCartRemoved(productId: productId, shopId: shopId);
          break;
        case 'favorite_added':
          await logFavoriteAdded(productId: productId, shopId: shopId);
          break;
        case 'favorite_removed':
          await logFavoriteRemoved(productId: productId, shopId: shopId);
          break;
      }
    }
  }

  Future<void> logEvent({
    required String eventType,
    required String productId,
    String? shopId,
  }) async {
    switch (eventType) {
      case 'cart_added':
        await logCartAdded(productId: productId, shopId: shopId);
        break;
      case 'cart_removed':
        await logCartRemoved(productId: productId, shopId: shopId);
        break;
      case 'favorite_added':
        await logFavoriteAdded(productId: productId, shopId: shopId);
        break;
      case 'favorite_removed':
        await logFavoriteRemoved(productId: productId, shopId: shopId);
        break;
    }
  }

  // ── Core write ────────────────────────────────────────────────────────────

  Future<void> _incrementMetric(
    String productId,
    String? shopId, {
    int cart = 0,
    int favorite = 0,
  }) async {
    if (_auth.currentUser == null) return;

    final collection = shopId != null ? 'shop_products' : 'products';

    try {
      final batch = _firestore.batch();

      final updateData = <String, dynamic>{
        'metricsUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (cart != 0) {
        updateData['cartCount'] = FieldValue.increment(cart);
      }
      if (favorite != 0) {
        updateData['favoritesCount'] = FieldValue.increment(favorite);
      }

      batch.update(
        _firestore.collection(collection).doc(productId),
        updateData,
      );

      if (shopId != null) {
        final shopUpdate = <String, dynamic>{
          'metrics.lastUpdated': FieldValue.serverTimestamp(),
        };
        if (cart > 0) {
          shopUpdate['metrics.totalCartAdditions'] = FieldValue.increment(1);
        }
        if (favorite > 0) {
          shopUpdate['metrics.totalFavoriteAdditions'] =
              FieldValue.increment(1);
        }

        if (shopUpdate.length > 1) {
          batch.update(
            _firestore.collection('shops').doc(shopId),
            shopUpdate,
          );
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('⚠️ MetricsEventService: write failed — $e');
    }
  }

  // ── GA4 ───────────────────────────────────────────────────────────────────

  void _logAnalytics(String eventType, String productId, String? shopId) {
    _analytics.logEvent(
      name: eventType,
      parameters: {
        'product_id': productId,
        'shop_id': shopId ?? '',
      },
    );
  }

  // ── Cooldown ──────────────────────────────────────────────────────────────

  bool _checkCooldown(String key) {
    final now = DateTime.now();
    final last = _lastActionTime[key];
    if (last != null && now.difference(last) < _actionCooldown) return false;
    _lastActionTime[key] = now;

    if (_lastActionTime.length > _maxCooldownEntries) {
      final sorted = _lastActionTime.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry
          in sorted.take(_lastActionTime.length - _maxCooldownEntries)) {
        _lastActionTime.remove(entry.key);
      }
    }

    return true;
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(
        i,
        i + size > list.length ? list.length : i + size,
      ));
    }
    return chunks;
  }
}