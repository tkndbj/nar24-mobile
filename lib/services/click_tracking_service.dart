// lib/services/click_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_activity_service.dart';

class ClickTrackingService {
  static final ClickTrackingService instance = ClickTrackingService._();
  ClickTrackingService._();

  Database? _db;
  final _auth = FirebaseAuth.instance;

  // In-memory buffers
  final Map<String, int> _productClicks = {};
  final Map<String, int> _shopProductClicks = {};
  final Map<String, int> _shopClicks = {};
  final Map<String, String> _shopIds = {};

  // Click cooldown
  final Map<String, DateTime> _lastClickTime = {};
  static const Duration _clickCooldown = Duration(seconds: 1);

  // Flush management
  Timer? _flushTimer;
  bool _isFlushingClicks = false;
  int _retryAttempts = 0;
  static const int _maxRetryAttempts = 3;

  // Buffer limits
  static const int _maxBufferSize = 500;
  static const int _maxMemoryBytes = 512 * 1024; // 512KB

  // Circuit breaker
  int _failureCount = 0;
  bool _circuitOpen = false;
  DateTime? _lastFailure;
  DateTime? _lastSuccessfulFlush;
  static const Duration _circuitCooldown = Duration(minutes: 5);
  static const int _maxFailures = 3;

  // ✅ NEW: Batch ID tracking for idempotency
  String? _currentBatchId;
  DateTime? _batchIdCreatedAt;
  static const Duration _batchIdTTL = Duration(seconds: 30);

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Initialize database
  Future<void> initialize() async {
    if (_db != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'click_tracking.db');

      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE pending_clicks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              item_id TEXT NOT NULL,
              count INTEGER NOT NULL,
              shop_id TEXT,
              created_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE INDEX idx_type_item ON pending_clicks(type, item_id)
          ''');
        },
      );

      await _loadPersistedClicks();
      debugPrint('✅ ClickTrackingService initialized with SQLite');
    } catch (e) {
      debugPrint('❌ Failed to initialize database: $e');
    }
  }

  /// ✅ NEW: Generate deterministic batch ID
  String _generateBatchId() {
    final now = DateTime.now();

    // Check if we can reuse current batch ID
    if (_currentBatchId != null &&
        _batchIdCreatedAt != null &&
        now.difference(_batchIdCreatedAt!) < _batchIdTTL) {
      return _currentBatchId!;
    }

    // Create new deterministic batch ID
    final userId = _auth.currentUser?.uid ?? 'anonymous';
    final timestamp = now.millisecondsSinceEpoch;

    // Round timestamp to nearest 30 seconds for deduplication window
    final roundedTimestamp = (timestamp ~/ 30000) * 30000;

    final input = '$userId-$roundedTimestamp';
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);

    _currentBatchId = 'batch_${hash.toString().substring(0, 16)}';
    _batchIdCreatedAt = now;

    return _currentBatchId!;
  }

  /// Track a product click
  Future<void> trackProductClick(
    String productId, {
    String? shopId,
    bool isShopProduct = true,
    String? productName,
    String? category, // ✅ ADD
    String? subcategory, // ✅ ADD
    String? subsubcategory, // ✅ ADD
    String? brand, // ✅ ADD
    String? gender, // ✅ ADD
  }) async {
    final now = DateTime.now();
    final lastClick = _lastClickTime[productId];

    if (lastClick != null && now.difference(lastClick) < _clickCooldown) {
      return;
    }
    _lastClickTime[productId] = now;

    UserActivityService.instance.trackClick(
      productId: productId,
      shopId: shopId,
      productName: productName,
      category: category, // ✅ ADD
      subcategory: subcategory, // ✅ ADD
      subsubcategory: subsubcategory, // ✅ ADD
      brand: brand, // ✅ ADD
      gender: gender, // ✅ ADD
    );

    // Check buffer limits
    final totalBuffered = _getTotalBufferedCount();
    if (_shouldForceFlush(totalBuffered)) {
      debugPrint('⚠️ Buffer limit reached, forcing flush');
      unawaited(_flushClicks());
    }

    final rawId =
        productId.contains('_') ? productId.split('_').last : productId;

    if (isShopProduct) {
      _shopProductClicks[rawId] = (_shopProductClicks[rawId] ?? 0) + 1;
    } else {
      _productClicks[rawId] = (_productClicks[rawId] ?? 0) + 1;
    }

    if (shopId != null) {
      _shopIds[rawId] = shopId;
    }

    _scheduleFlush();
  }

  /// Track a shop click
  Future<void> trackShopClick(String shopId) async {
    final now = DateTime.now();
    final lastClick = _lastClickTime[shopId];

    if (lastClick != null && now.difference(lastClick) < _clickCooldown) {
      return;
    }
    _lastClickTime[shopId] = now;

    final totalBuffered = _getTotalBufferedCount();
    if (_shouldForceFlush(totalBuffered)) {
      debugPrint('⚠️ Buffer limit reached, forcing flush');
      unawaited(_flushClicks());
    }

    _shopClicks[shopId] = (_shopClicks[shopId] ?? 0) + 1;
    _scheduleFlush();
  }

  int _getTotalBufferedCount() {
    return _productClicks.length +
        _shopProductClicks.length +
        _shopClicks.length;
  }

  bool _shouldForceFlush(int totalBuffered) {
    final estimatedMemory = totalBuffered * 100;

    return totalBuffered >= _maxBufferSize ||
        estimatedMemory >= _maxMemoryBytes ||
        (_lastSuccessfulFlush != null &&
            DateTime.now().difference(_lastSuccessfulFlush!) >
                Duration(minutes: 5));
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(Duration(seconds: 20), _flushClicks);
  }

  /// Flush clicks to Cloud Function
  Future<void> _flushClicks() async {
    if (_isFlushingClicks) {
      debugPrint('⏳ Flush already in progress');
      return;
    }

    // Check circuit breaker
    if (_circuitOpen) {
      if (_lastFailure != null &&
          DateTime.now().difference(_lastFailure!) > _circuitCooldown) {
        _circuitOpen = false;
        _failureCount = 0;
        debugPrint('🟢 Circuit breaker reset');
      } else {
        debugPrint('🔴 Circuit breaker open, skipping flush');
        return;
      }
    }

    final hasClicks = _productClicks.isNotEmpty ||
        _shopProductClicks.isNotEmpty ||
        _shopClicks.isNotEmpty;

    if (!hasClicks) return;

    _isFlushingClicks = true;

    try {
      final clicksToFlush = Map<String, int>.from(_productClicks);
      final shopProductClicksToFlush =
          Map<String, int>.from(_shopProductClicks);
      final shopClicksToFlush = Map<String, int>.from(_shopClicks);
      final shopIdsToFlush = Map<String, String>.from(_shopIds);

      _productClicks.clear();
      _shopProductClicks.clear();
      _shopClicks.clear();
      _shopIds.clear();

      final totalClicks = clicksToFlush.length +
          shopProductClicksToFlush.length +
          shopClicksToFlush.length;

      // ✅ NEW: Use deterministic batch ID
      final batchId = _generateBatchId();

      final payload = {
        'batchId': batchId, // ✅ ADD THIS
        'productClicks': clicksToFlush,
        'shopProductClicks': shopProductClicksToFlush,
        'shopClicks': shopClicksToFlush,
        'shopIds': shopIdsToFlush,
      };

      final payloadSize = jsonEncode(payload).length;

      // Chunk if too large
      if (totalClicks > 500 || payloadSize > 1000000) {
        await _flushInChunks(
          clicksToFlush,
          shopProductClicksToFlush,
          shopClicksToFlush,
          shopIdsToFlush,
        );
      } else {
        await _sendToFunction(payload);
      }

      _retryAttempts = 0;
      _failureCount = 0;
      _circuitOpen = false;
      _lastSuccessfulFlush = DateTime.now();

      await _clearPersistedClicks();
      debugPrint('✅ Flushed $totalClicks clicks successfully');
    } catch (e) {
      debugPrint('❌ Error flushing clicks: $e');
      _failureCount++;
      _lastFailure = DateTime.now();

      if (_failureCount >= _maxFailures) {
        _circuitOpen = true;
        debugPrint('🔴 Circuit opened after $_failureCount failures');
      }

      _retryAttempts++;
      if (_retryAttempts < _maxRetryAttempts) {
        final retryDelay = Duration(seconds: 10 * _retryAttempts);
        debugPrint('🔄 Retrying in ${retryDelay.inSeconds}s');

        Future.delayed(retryDelay, _flushClicks);
      } else {
        debugPrint('⚠️ Max retries reached, persisting to database');
        await _persistPendingClicks();
        _retryAttempts = 0;
      }
    } finally {
      _isFlushingClicks = false;
    }
  }

  Future<void> _flushInChunks(
    Map<String, int> productClicks,
    Map<String, int> shopProductClicks,
    Map<String, int> shopClicks,
    Map<String, String> shopIds,
  ) async {
    debugPrint('📦 Chunking large payload');

    const chunkSize = 500;
    final allItems = <MapEntry<String, dynamic>>[];

    productClicks.forEach(
        (k, v) => allItems.add(MapEntry(k, {'type': 'product', 'count': v})));
    shopProductClicks.forEach((k, v) =>
        allItems.add(MapEntry(k, {'type': 'shop_product', 'count': v})));
    shopClicks.forEach(
        (k, v) => allItems.add(MapEntry(k, {'type': 'shop', 'count': v})));

    // ✅ FIX: Generate base batch ID once, then append chunk index
    final baseBatchId = _generateBatchId();
    int chunkIndex = 0;

    for (var i = 0; i < allItems.length; i += chunkSize) {
      final chunk = allItems.skip(i).take(chunkSize);

      final chunkPayload = {
        'batchId':
            '${baseBatchId}_chunk_$chunkIndex', // ✅ FIXED: Unique per chunk
        'productClicks': <String, int>{},
        'shopProductClicks': <String, int>{},
        'shopClicks': <String, int>{},
        'shopIds': <String, String>{},
      };
      chunkIndex++;

      for (final item in chunk) {
        final type = item.value['type'] as String;
        final count = item.value['count'] as int;

        if (type == 'product') {
          (chunkPayload as Map<String, dynamic>)['productClicks']![item.key] =
              count;
        } else if (type == 'shop_product') {
          (chunkPayload
              as Map<String, dynamic>)['shopProductClicks']![item.key] = count;
          if (shopIds.containsKey(item.key)) {
            (chunkPayload as Map<String, dynamic>)['shopIds']![item.key] =
                shopIds[item.key]!;
          }
        } else if (type == 'shop') {
          (chunkPayload as Map<String, dynamic>)['shopClicks']![item.key] =
              count;
        }
      }

      await _sendToFunction(chunkPayload);
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _sendToFunction(Map<String, dynamic> payload) async {
    final callable = _functions.httpsCallable('batchUpdateClicks');

    await callable.call(payload).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Flush timeout'),
        );
  }

  Future<void> _persistPendingClicks() async {
    if (_db == null) return;

    try {
      final batch = _db!.batch();
      final now = DateTime.now().millisecondsSinceEpoch;

      _productClicks.forEach((id, count) {
        batch.insert('pending_clicks', {
          'type': 'product',
          'item_id': id,
          'count': count,
          'created_at': now,
        });
      });

      _shopProductClicks.forEach((id, count) {
        batch.insert('pending_clicks', {
          'type': 'shop_product',
          'item_id': id,
          'count': count,
          'shop_id': _shopIds[id],
          'created_at': now,
        });
      });

      _shopClicks.forEach((id, count) {
        batch.insert('pending_clicks', {
          'type': 'shop',
          'item_id': id,
          'count': count,
          'created_at': now,
        });
      });

      await batch.commit(noResult: true);
      debugPrint('💾 Persisted ${_getTotalBufferedCount()} clicks to SQLite');
    } catch (e) {
      debugPrint('❌ Error persisting clicks: $e');
    }
  }

  Future<void> _loadPersistedClicks() async {
    if (_db == null) return;

    try {
      final results = await _db!.query('pending_clicks');

      for (final row in results) {
        final type = row['type'] as String;
        final itemId = row['item_id'] as String;
        final count = row['count'] as int;
        final shopId = row['shop_id'] as String?;

        if (type == 'product') {
          _productClicks[itemId] = (_productClicks[itemId] ?? 0) + count;
        } else if (type == 'shop_product') {
          _shopProductClicks[itemId] =
              (_shopProductClicks[itemId] ?? 0) + count;
          if (shopId != null) _shopIds[itemId] = shopId;
        } else if (type == 'shop') {
          _shopClicks[itemId] = (_shopClicks[itemId] ?? 0) + count;
        }
      }

      final totalRestored = _getTotalBufferedCount();
      if (totalRestored > 0) {
        debugPrint('📦 Restored $totalRestored persisted clicks');
        _scheduleFlush();
      }
    } catch (e) {
      debugPrint('❌ Error loading persisted clicks: $e');
    }
  }

  Future<void> _clearPersistedClicks() async {
    if (_db == null) return;

    try {
      await _db!.delete('pending_clicks');
    } catch (e) {
      debugPrint('❌ Error clearing persisted clicks: $e');
    }
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();

    if (_getTotalBufferedCount() > 0) {
      debugPrint('⚡ Final flush before dispose');
      try {
        await _flushClicks().timeout(Duration(seconds: 5));
      } catch (e) {
        debugPrint('⚠️ Final flush failed: $e');
        await _persistPendingClicks();
      }
    }

    await _db?.close();
    _db = null;
  }

  /// Public flush method for lifecycle management
  Future<void> flush() async {
    await _flushClicks();
  }

  Map<String, dynamic> getMetrics() {
    return {
      'bufferedClicks': _getTotalBufferedCount(),
      'circuitOpen': _circuitOpen,
      'failureCount': _failureCount,
      'retryAttempts': _retryAttempts,
      'lastFailure': _lastFailure?.toIso8601String(),
      'lastSuccess': _lastSuccessfulFlush?.toIso8601String(),
    };
  }
}

void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('Unawaited error: $e'));
}
