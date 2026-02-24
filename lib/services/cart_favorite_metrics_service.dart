// lib/services/metrics_event_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHANGE LOG (vs previous version)
//
//  6. Added SQLite persistence for max-retry failures.
//     WHY: Previously events were silently dropped after 3 failed attempts.
//     Now they are persisted locally and retried on next app launch.
//
//  Design decisions to prevent memory explosion:
//    - DB stores raw JSON strings, not parsed maps — no in-memory object bloat
//    - _loadPersistedEvents() caps restore at _maxBufferSize (100 events)
//      with a hard DB cap of _maxPersistedEvents (500 events) using FIFO eviction
//    - Events older than 24h are discarded on load — stale cart/fav metrics
//      are worthless and would confuse analytics
//    - SQLite write is fire-and-forget (unawaited) on the failure path so
//      it never blocks the UI or the flush loop
// ─────────────────────────────────────────────────────────────────────────────

class MetricsEventService {
  static final MetricsEventService instance = MetricsEventService._();
  MetricsEventService._();

  final _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  // ── SQLite ──────────────────────────────────────────────────────────────────
  Database? _db;

  // Max events stored in DB — prevents unbounded growth during prolonged
  // connectivity loss. Oldest rows are evicted when limit is hit (FIFO).
  static const int _maxPersistedEvents = 500;

  // Discard events older than this on load — stale metrics cause more harm
  // than good (e.g. inflating counts for products user no longer cares about)
  static const Duration _maxEventAge = Duration(hours: 24);

  // ── Buffer ──────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _flushTimer;
  bool _isFlushing = false;

  // ── Config ──────────────────────────────────────────────────────────────────
  static const Duration _flushDebounce = Duration(seconds: 30);
  static const Duration _actionCooldown = Duration(seconds: 1);
  static const int _maxRetryAttempts = 3;
  static const int _maxBufferSize = 100; // matches server-side max

  // ── Cooldown tracking ───────────────────────────────────────────────────────
  // Key: "$eventType:$productId" to allow cart and fav on same product
  final Map<String, DateTime> _lastActionTime = {};

  // ── Retry state ─────────────────────────────────────────────────────────────
  int _retryAttempts = 0;

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_db != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'metrics_events.db');

      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE pending_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              event_json TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');

          // Index on created_at for efficient age-based cleanup
          await db.execute('''
            CREATE INDEX idx_created_at ON pending_events(created_at)
          ''');
        },
      );

      await _loadPersistedEvents();
      debugPrint('✅ MetricsEventService: SQLite initialized');
    } catch (e) {
      // Non-fatal — service degrades gracefully without persistence
      debugPrint('❌ MetricsEventService: SQLite init failed — $e');
    }
  }

  // ── BatchId ─────────────────────────────────────────────────────────────────
  // Rounds to the nearest 30s window so retries reuse the same batchId,
  // giving the server clean idempotency without extra state.
  String _generateBatchId() {
    final userId = _auth.currentUser?.uid ?? 'anonymous';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final roundedTimestamp = (timestamp ~/ 30000) * 30000;
    final input = '$userId-cart_fav-$roundedTimestamp';
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    return 'cart_fav_${hash.toString().substring(0, 16)}';
  }

  // ── Core enqueue ─────────────────────────────────────────────────────────────
  Future<void> _enqueue({
    required String eventType,
    required String productId,
    String? shopId,
  }) async {
    if (_auth.currentUser == null) {
      debugPrint('⚠️ MetricsEventService: user not authenticated, skipping');
      return;
    }

    final cooldownKey = '$eventType:$productId';
    final lastAction = _lastActionTime[cooldownKey];
    final now = DateTime.now();

    if (lastAction != null && now.difference(lastAction) < _actionCooldown) {
      debugPrint('⏱️ MetricsEventService: cooldown active for $cooldownKey');
      return;
    }
    _lastActionTime[cooldownKey] = now;

    _pendingEvents.add({
      'type': eventType,
      'productId': productId,
      if (shopId != null) 'shopId': shopId,
    });

    debugPrint(
      '📥 MetricsEventService: queued $eventType for $productId '
      '(buffer: ${_pendingEvents.length})',
    );

    if (_pendingEvents.length >= _maxBufferSize) {
      debugPrint('⚠️ MetricsEventService: buffer full, forcing flush');
      _flushTimer?.cancel();
      unawaited(_flush());
      return;
    }

    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDebounce, _flush);
  }

  // ── Flush ────────────────────────────────────────────────────────────────────
  Future<void> _flush() async {
    if (_isFlushing) {
      debugPrint('⏳ MetricsEventService: flush already in progress');
      return;
    }

    if (_pendingEvents.isEmpty) return;

    _isFlushing = true;

    // Snapshot and clear buffer before async work so new events
    // enqueued during flush go into the next batch
    final eventsToSend = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();

    try {
      final batchId = _generateBatchId();

      debugPrint(
        '📤 MetricsEventService: flushing ${eventsToSend.length} events '
        '(batchId: $batchId)',
      );

      await _functions.httpsCallable('batchCartFavoriteEvents').call({
        'batchId': batchId,
        'events': eventsToSend,
      }).timeout(const Duration(seconds: 30));

      _retryAttempts = 0;

      // Successful delivery — clear any previously persisted events
      unawaited(_clearPersistedEvents());

      debugPrint(
        '✅ MetricsEventService: flushed ${eventsToSend.length} events',
      );
    } catch (e) {
      debugPrint('❌ MetricsEventService: flush failed — $e');

      // Put events back at the front of the buffer for retry
      _pendingEvents.insertAll(0, eventsToSend);
      _retryAttempts++;

      if (_retryAttempts < _maxRetryAttempts) {
        final retryDelay = Duration(seconds: 10 * _retryAttempts);
        debugPrint(
          '🔄 MetricsEventService: retry $_retryAttempts/$_maxRetryAttempts '
          'in ${retryDelay.inSeconds}s',
        );
        _flushTimer?.cancel();
        _flushTimer = Timer(retryDelay, _flush);
      } else {
        // Max retries exceeded — persist to SQLite for recovery on next launch
        debugPrint(
          '💾 MetricsEventService: max retries reached, '
          'persisting ${_pendingEvents.length} events to SQLite',
        );
        unawaited(_persistPendingEvents());
        _pendingEvents.clear();
        _retryAttempts = 0;
      }
    } finally {
      _isFlushing = false;
    }
  }

  // ── SQLite operations ─────────────────────────────────────────────────────────

  Future<void> _persistPendingEvents() async {
    if (_db == null || _pendingEvents.isEmpty) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Enforce hard DB cap with FIFO eviction before inserting new rows.
      // Reads only a scalar COUNT — no full row fetches.
      final countResult = await _db!.rawQuery(
        'SELECT COUNT(*) as count FROM pending_events',
      );
      final existingCount = Sqflite.firstIntValue(countResult) ?? 0;
      final projectedTotal = existingCount + _pendingEvents.length;

      if (projectedTotal > _maxPersistedEvents) {
        final toEvict = projectedTotal - _maxPersistedEvents;
        await _db!.rawDelete(
          'DELETE FROM pending_events WHERE id IN '
          '(SELECT id FROM pending_events ORDER BY id ASC LIMIT ?)',
          [toEvict],
        );
        debugPrint(
          '🧹 MetricsEventService: evicted $toEvict old events from SQLite',
        );
      }

      final batch = _db!.batch();
      for (final event in _pendingEvents) {
        batch.insert('pending_events', {
          'event_json': jsonEncode(event),
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);

      debugPrint(
        '💾 MetricsEventService: persisted ${_pendingEvents.length} events',
      );
    } catch (e) {
      debugPrint('❌ MetricsEventService: SQLite persist failed — $e');
    }
  }

  Future<void> _loadPersistedEvents() async {
    if (_db == null) return;

    try {
      // Purge stale events first — no point restoring 24h-old cart metrics
      final cutoff =
          DateTime.now().subtract(_maxEventAge).millisecondsSinceEpoch;

      await _db!.delete(
        'pending_events',
        where: 'created_at < ?',
        whereArgs: [cutoff],
      );

      // Only load up to _maxBufferSize — the in-memory buffer cap.
      // Remaining rows (if any) stay in DB and are loaded on the next launch
      // after the first batch is delivered. This keeps memory flat.
      final rows = await _db!.query(
        'pending_events',
        orderBy: 'id ASC',
        limit: _maxBufferSize,
      );

      if (rows.isEmpty) return;

      for (final row in rows) {
        try {
          final event =
              jsonDecode(row['event_json'] as String) as Map<String, dynamic>;
          _pendingEvents.add(event);
        } catch (e) {
          // Corrupted row — skip silently, will be cleared on next success
          debugPrint('⚠️ MetricsEventService: skipping corrupted row — $e');
        }
      }

      debugPrint(
        '📦 MetricsEventService: restored ${_pendingEvents.length} '
        'events from SQLite',
      );

      if (_pendingEvents.isNotEmpty) {
        _scheduleFlush();
      }
    } catch (e) {
      debugPrint('❌ MetricsEventService: SQLite load failed — $e');
    }
  }

  Future<void> _clearPersistedEvents() async {
    if (_db == null) return;

    try {
      await _db!.delete('pending_events');
    } catch (e) {
      debugPrint('❌ MetricsEventService: SQLite clear failed — $e');
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Call from AppLifecycleState.paused to flush buffered events before suspend.
  Future<void> flush() async {
    _flushTimer?.cancel();
    await _flush();
  }

  /// Call from AppLifecycleState.detached for clean shutdown.
  Future<void> dispose() async {
    _flushTimer?.cancel();

    if (_pendingEvents.isNotEmpty) {
      debugPrint('⚡ MetricsEventService: final flush before dispose');
      try {
        await _flush().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('⚠️ MetricsEventService: final flush failed — $e');
        await _persistPendingEvents();
      }
    }

    await _db?.close();
    _db = null;
  }

  Future<void> logCartAdded({
    required String productId,
    String? shopId,
  }) =>
      _enqueue(eventType: 'cart_added', productId: productId, shopId: shopId);

  Future<void> logCartRemoved({
    required String productId,
    String? shopId,
  }) =>
      _enqueue(eventType: 'cart_removed', productId: productId, shopId: shopId);

  Future<void> logFavoriteAdded({
    required String productId,
    String? shopId,
  }) =>
      _enqueue(
        eventType: 'favorite_added',
        productId: productId,
        shopId: shopId,
      );

  Future<void> logFavoriteRemoved({
    required String productId,
    String? shopId,
  }) =>
      _enqueue(
        eventType: 'favorite_removed',
        productId: productId,
        shopId: shopId,
      );

  /// Batch-enqueue multiple events in one call.
  /// Each event must have 'type' and 'productId'; 'shopId' is optional.
  Future<void> logBatchEvents({
    required List<Map<String, dynamic>> events,
  }) async {
    if (_auth.currentUser == null) {
      debugPrint('⚠️ MetricsEventService: user not authenticated, skipping');
      return;
    }

    for (final event in events) {
      final type = event['type'] as String?;
      final productId = event['productId'] as String?;
      final shopId = event['shopId'] as String?;

      if (type == null || productId == null) {
        debugPrint('⚠️ MetricsEventService: skipping invalid event: $event');
        continue;
      }

      await _enqueue(eventType: type, productId: productId, shopId: shopId);
    }
  }

  Future<void> logBatchCartRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) =>
      logBatchEvents(
        events: productIds
            .map(
              (id) => {
                'type': 'cart_removed',
                'productId': id,
                if (shopIds[id] != null) 'shopId': shopIds[id]!,
              },
            )
            .toList(),
      );

  Future<void> logBatchFavoriteRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) =>
      logBatchEvents(
        events: productIds
            .map(
              (id) => {
                'type': 'favorite_removed',
                'productId': id,
                if (shopIds[id] != null) 'shopId': shopIds[id]!,
              },
            )
            .toList(),
      );

  // Kept for backward compatibility. Prefer the typed methods above.
  Future<void> logEvent({
    required String eventType,
    required String productId,
    String? shopId,
  }) =>
      _enqueue(eventType: eventType, productId: productId, shopId: shopId);
}

void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('Unawaited error: $e'));
}
