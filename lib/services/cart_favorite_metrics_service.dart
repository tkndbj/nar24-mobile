// lib/services/metrics_event_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MetricsEventService {
  static final MetricsEventService instance = MetricsEventService._();
  MetricsEventService._();

  final _analytics = FirebaseAnalytics.instance;
  final _auth = FirebaseAuth.instance;
  final _callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
      .httpsCallable('trackCartFavEvent');

  // ── Cooldown ────────────────────────────────────────────────────────────────
  final Map<String, DateTime> _lastActionTime = {};
  static const _actionCooldown = Duration(seconds: 1);
  static const _maxCooldownEntries = 500;

  // ── Buffer ──────────────────────────────────────────────────────────────────
  final List<_EventRecord> _buffer = [];
  Timer? _batchTimer;
  static const _batchInterval = Duration(seconds: 15);
  static const _maxBatchSize = 30;
  static const _maxRetries = 3;
  int _retryCount = 0;
  bool _isSending = false;

  static const _persistKey = 'pending_cartfav_buffer';

  Future<void> initialize() async {
    await _loadPersistedBuffer();
    debugPrint('✅ MetricsEventService initialized');
  }

  Future<void> flush() async {
    _batchTimer?.cancel();
    await _sendBatch();
  }

  Future<void> dispose() async {
    _batchTimer?.cancel();
    await _persistBuffer();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> logCartAdded({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('cart_added:$productId')) return;
    _logAnalytics('cart_added', productId, shopId);
    _enqueue(_EventRecord(
      productId: productId,
      collection: shopId != null ? 'shop_products' : 'products',
      shopId: shopId,
      type: 'cart',
      delta: 1,
    ));
  }

  Future<void> logCartRemoved({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('cart_removed:$productId')) return;
    _logAnalytics('cart_removed', productId, shopId);
    _enqueue(_EventRecord(
      productId: productId,
      collection: shopId != null ? 'shop_products' : 'products',
      shopId: shopId,
      type: 'cart',
      delta: -1,
    ));
  }

  Future<void> logFavoriteAdded({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('favorite_added:$productId')) return;
    _logAnalytics('favorite_added', productId, shopId);
    _enqueue(_EventRecord(
      productId: productId,
      collection: shopId != null ? 'shop_products' : 'products',
      shopId: shopId,
      type: 'favorite',
      delta: 1,
    ));
  }

  Future<void> logFavoriteRemoved({
    required String productId,
    String? shopId,
  }) async {
    if (!_checkCooldown('favorite_removed:$productId')) return;
    _logAnalytics('favorite_removed', productId, shopId);
    _enqueue(_EventRecord(
      productId: productId,
      collection: shopId != null ? 'shop_products' : 'products',
      shopId: shopId,
      type: 'favorite',
      delta: -1,
    ));
  }

  // ── Batch operations ──────────────────────────────────────────────────────

  Future<void> logBatchCartRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) async {
    for (final id in productIds) {
      await logCartRemoved(productId: id, shopId: shopIds[id]);
    }
  }

  Future<void> logBatchFavoriteRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) async {
    for (final id in productIds) {
      await logFavoriteRemoved(productId: id, shopId: shopIds[id]);
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

  // ── Internal: enqueue ─────────────────────────────────────────────────────

  void _enqueue(_EventRecord event) {
    if (_auth.currentUser == null) return;

    _buffer.add(event);
    _scheduleBatch();

    if (_buffer.length >= _maxBatchSize) {
      _sendBatch();
    }
  }

  // ── Batch sending ─────────────────────────────────────────────────────────

  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchInterval, _sendBatch);
  }

  Future<void> _sendBatch() async {
    if (_buffer.isEmpty || _isSending) return;
    if (_auth.currentUser == null) return;
    _isSending = true;

    final toSend = List<_EventRecord>.from(_buffer);
    _buffer.clear();
    _batchTimer?.cancel();

    try {
      await _callable.call({
        'events': toSend.map((e) => e.toMap()).toList(),
      });

      debugPrint(
          '📊 MetricsEventService: sent ${toSend.length} events in 1 batch call');
      _retryCount = 0;
    } catch (e) {
      debugPrint('❌ MetricsEventService: batch send failed — $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        _buffer.insertAll(0, toSend);
        Future.delayed(
          Duration(seconds: 2 * _retryCount),
          _sendBatch,
        );
      } else {
        debugPrint(
            '❌ MetricsEventService: max retries, dropping ${toSend.length} events');
        _retryCount = 0;
      }
    } finally {
      _isSending = false;
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _persistBuffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_buffer.isEmpty) {
        await prefs.remove(_persistKey);
        return;
      }
      final encoded = jsonEncode(_buffer.map((e) => e.toMap()).toList());
      await prefs.setString(_persistKey, encoded);
    } catch (e) {
      debugPrint('⚠️ MetricsEventService: persist failed — $e');
    }
  }

  Future<void> _loadPersistedBuffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_persistKey);
      if (stored == null) return;
      final decoded = jsonDecode(stored) as List<dynamic>;
      for (final item in decoded) {
        _buffer.add(_EventRecord.fromMap(item as Map<String, dynamic>));
      }
      await prefs.remove(_persistKey);
      if (_buffer.isNotEmpty) {
        debugPrint(
            '📦 MetricsEventService: restored ${_buffer.length} buffered events');
        _scheduleBatch();
      }
    } catch (e) {
      debugPrint('⚠️ MetricsEventService: load persisted failed — $e');
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
}

class _EventRecord {
  final String productId;
  final String collection;
  final String? shopId;
  final String type; // 'cart' | 'favorite'
  final int delta;   // 1 | -1

  _EventRecord({
    required this.productId,
    required this.collection,
    required this.shopId,
    required this.type,
    required this.delta,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'collection': collection,
        'shopId': shopId,
        'type': type,
        'delta': delta,
      };

  factory _EventRecord.fromMap(Map<String, dynamic> map) => _EventRecord(
        productId: map['productId'] as String,
        collection: map['collection'] as String,
        shopId: map['shopId'] as String?,
        type: map['type'] as String,
        delta: map['delta'] as int,
      );
}