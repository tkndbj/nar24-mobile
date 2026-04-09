// lib/services/click_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Tracks product and shop clicks via Redis-backed cloud function.
///
/// Clicks are buffered locally and sent as a single batch to
/// `trackProductClick`, which writes to Redis. A server-side scheduled
/// flush drains Redis → Firestore every minute.
class ClickService {
  static final ClickService instance = ClickService._();
  ClickService._();

  final _analytics = FirebaseAnalytics.instance;
  final _callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
      .httpsCallable('trackProductClick');

  // ── Cooldown ────────────────────────────────────────────────────────────────
  final Map<String, DateTime> _lastClick = {};
  static const _cooldown = Duration(seconds: 1);
  static const _maxCooldownEntries = 500;

  // ── Local buffer ────────────────────────────────────────────────────────────
  final List<_ClickRecord> _buffer = [];
  Timer? _batchTimer;
  static const _batchInterval = Duration(seconds: 15);
  static const _maxBatchSize = 30;
  static const _maxRetries = 3;
  int _retryCount = 0;
  bool _isSending = false;

  Future<void> trackClick({
    required String productId,
    String? shopId,
    required String collection,
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? brand,
    String? gender,
  }) async {
    final now = DateTime.now();
    if (_lastClick[productId] != null &&
        now.difference(_lastClick[productId]!) < _cooldown) {
      return;
    }
    _lastClick[productId] = now;
    _cleanCooldownMap();

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

    _buffer.add(_ClickRecord(
      productId: productId,
      collection: collection,
      shopId: shopId,
    ));

    _scheduleBatch();

    if (_buffer.length >= _maxBatchSize) {
      _sendBatch();
    }
  }

  Future<void> trackShopClick(String shopId) async {
    final now = DateTime.now();
    if (_lastClick[shopId] != null &&
        now.difference(_lastClick[shopId]!) < _cooldown) {
      return;
    }
    _lastClick[shopId] = now;
    _cleanCooldownMap();

    _analytics.logEvent(
      name: 'shop_click',
      parameters: {'shop_id': shopId},
    );

    _buffer.add(_ClickRecord(
      productId: shopId,
      collection: 'shops',
      shopId: shopId,
    ));

    _scheduleBatch();
  }

  void _cleanCooldownMap() {
    if (_lastClick.length > _maxCooldownEntries) {
      final sorted = _lastClick.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry
          in sorted.take(_lastClick.length - _maxCooldownEntries)) {
        _lastClick.remove(entry.key);
      }
    }
  }

  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchInterval, _sendBatch);
  }

  Future<void> _sendBatch() async {
    if (_buffer.isEmpty || _isSending) return;
    _isSending = true;

    final toSend = List<_ClickRecord>.from(_buffer);
    _buffer.clear();
    _batchTimer?.cancel();

    try {
      // Single cloud function call for the entire batch
      await _callable.call({
        'clicks': toSend
            .map((c) => <String, dynamic>{
                  'productId': c.productId,
                  'collection': c.collection,
                  'shopId': c.shopId,
                })
            .toList(),
      });

      debugPrint(
          '📊 ClickService: sent ${toSend.length} clicks in 1 batch call');
      _retryCount = 0;
    } catch (e) {
      debugPrint('❌ ClickService: batch send failed — $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        _buffer.insertAll(0, toSend);
        Future.delayed(
          Duration(seconds: 2 * _retryCount),
          _sendBatch,
        );
      } else {
        debugPrint(
            '❌ ClickService: max retries, dropping ${toSend.length} clicks');
        _retryCount = 0;
      }
    } finally {
      _isSending = false;
    }
  }

  /// Flush pending clicks immediately (call on app pause/dispose).
  Future<void> flush() async {
    _batchTimer?.cancel();
    await _sendBatch();
  }
}

class _ClickRecord {
  final String productId;
  final String collection;
  final String? shopId;

  _ClickRecord({
    required this.productId,
    required this.collection,
    this.shopId,
  });
}
