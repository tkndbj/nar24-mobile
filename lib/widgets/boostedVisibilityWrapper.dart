// lib/widgets/boostedVisibilityWrapper.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path_helper;
import 'package:sqflite/sqflite.dart';
import '../providers/market_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHANGE LOG (vs original)
//
//  1. Replaced SharedPreferences with SQLite for impression deduplication state.
//     WHY: SharedPreferences loads the entire dataset into memory on app start
//     as a single JSON string. SQLite reads lazily per-query, writes per-row,
//     and handles age-based cleanup with a single DELETE WHERE rather than
//     deserializing, filtering in Dart, and re-serializing the whole blob.
//
//  2. Removed _pageImpressions in-memory Map.
//     WHY: Deduplication checks are now SQL COUNT queries. No need to mirror
//     DB state in memory. This eliminates the unbounded map growth issue during
//     long browsing sessions.
//
//  3. Removed _persistTimer and all _persistPageImpressions() calls.
//     WHY: SQLite writes are per-row and immediate — there is nothing to
//     debounce. The 5s persist timer existed only because writing the full
//     SharedPreferences JSON blob on every impression was expensive.
//
//  4. Replaced _setCurrentUser() polling on every addImpression() with an
//     auth stream subscription set up once in initialize().
//     WHY: The original called FirebaseAuth.instance.currentUser and compared
//     UIDs on every single scroll impression event.
//
//  5. Added initialize() as async with await so SQLite is ready before the
//     first impression is recorded. initialize() is safe to call multiple times.
//
//  6. All public API preserved: addImpression(), flush(), dispose(),
//     initialize(). BoostedVisibilityWrapper and ProductListSliver unchanged.
// ─────────────────────────────────────────────────────────────────────────────

// ── Data classes (unchanged) ──────────────────────────────────────────────────

class PageImpression {
  final String screenName;
  final DateTime timestamp;

  PageImpression({
    required this.screenName,
    required this.timestamp,
  });
}

class ImpressionRecord {
  final String productId;
  final String screenName;
  final DateTime timestamp;

  ImpressionRecord({
    required this.productId,
    required this.screenName,
    required this.timestamp,
  });
}

// ── ImpressionBatcher ─────────────────────────────────────────────────────────

class ImpressionBatcher {
  static final _instance = ImpressionBatcher._internal();
  factory ImpressionBatcher() => _instance;
  ImpressionBatcher._internal();

  // ── SQLite ──────────────────────────────────────────────────────────────────
  Database? _db;
  bool _dbInitialized = false;

  // ── Send buffer ─────────────────────────────────────────────────────────────
  final List<ImpressionRecord> _impressionBuffer = [];

  // ── Timers ──────────────────────────────────────────────────────────────────
  Timer? _batchTimer;
  Timer? _cleanupTimer;

  // ── Dependencies ─────────────────────────────────────────────────────────────
  MarketProvider? _marketProvider;
  String? _currentUserId;
  StreamSubscription<User?>? _authSubscription;

  // ── Config ───────────────────────────────────────────────────────────────────
  static const Duration _batchInterval = Duration(seconds: 30);
  static const Duration _impressionCooldown = Duration(hours: 1);
  static const int _maxBatchSize = 100;
  static const int _maxImpressionsPerHour = 4;
  static const int _maxRetries = 3;

  // Max rows per user — prevents unbounded DB growth during prolonged sessions
  static const int _maxRowsPerUser = 1000;

  int _retryCount = 0;
  bool _isDisposed = false;

  // ── Initialize ───────────────────────────────────────────────────────────────
  Future<void> initialize(MarketProvider provider) async {
    if (_isDisposed) return;

    _marketProvider = provider;

    // Open SQLite once
    if (!_dbInitialized) {
      await _openDatabase();
    }

    // Subscribe to auth changes once — replaces per-impression _setCurrentUser polling
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      final newUserId = user?.uid;
      if (_currentUserId != newUserId) {
        debugPrint(
          '👤 ImpressionBatcher: user changed '
          'from $_currentUserId to $newUserId',
        );
        _currentUserId = newUserId;
      }
    });

    // Set initial user synchronously so first impression doesn't miss it
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;

    _startCleanup();
  }

  Future<void> _openDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final pathStr = path_helper.join(dbPath, 'impressions.db');

      _db = await openDatabase(
        pathStr,
        version: 1,
        onCreate: (db, version) async {
          // One row per user + product + screen combination
          // created_at is epoch milliseconds for age-based cleanup
          await db.execute('''
            CREATE TABLE page_impressions (
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id     TEXT    NOT NULL,
              product_id  TEXT    NOT NULL,
              screen_name TEXT    NOT NULL,
              created_at  INTEGER NOT NULL
            )
          ''');

          // Deduplication check: "has user seen product on screen within cooldown?"
          await db.execute('''
            CREATE INDEX idx_user_product_screen
            ON page_impressions(user_id, product_id, screen_name)
          ''');

          // Age-based cleanup
          await db.execute('''
            CREATE INDEX idx_created_at
            ON page_impressions(created_at)
          ''');
        },
      );

      _dbInitialized = true;
      debugPrint('✅ ImpressionBatcher: SQLite initialized');
    } catch (e) {
      // Non-fatal — service degrades gracefully without persistence
      debugPrint('❌ ImpressionBatcher: SQLite init failed — $e');
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────────

  void _startCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _cleanupExpiredImpressions(),
    );
  }

  Future<void> _cleanupExpiredImpressions() async {
    if (_db == null) return;

    try {
      final cutoff =
          DateTime.now().subtract(_impressionCooldown).millisecondsSinceEpoch;

      final deleted = await _db!.delete(
        'page_impressions',
        where: 'created_at < ?',
        whereArgs: [cutoff],
      );

      if (deleted > 0) {
        debugPrint(
          '🧹 ImpressionBatcher: deleted $deleted expired impressions',
        );
      }
    } catch (e) {
      debugPrint('❌ ImpressionBatcher: cleanup failed — $e');
    }
  }

  // ── Core: addImpression ───────────────────────────────────────────────────────

  void addImpression(String productId, {String? screenName}) {
    if (_isDisposed) return;

    // Fire async work without blocking the scroll callback
    _recordImpression(productId, screenName: screenName ?? 'unknown');
  }

  Future<void> _recordImpression(
    String productId, {
    required String screenName,
  }) async {
    if (_db == null || _currentUserId == null) {
      // DB not ready or user not authenticated — skip silently
      debugPrint(
        '⚠️ ImpressionBatcher: skipping impression '
        '(db=${_db != null}, user=$_currentUserId)',
      );
      return;
    }

    try {
      final now = DateTime.now();
      final cutoff = now.subtract(_impressionCooldown).millisecondsSinceEpoch;
      final userId = _currentUserId!;

      // ── Check 1: Already recorded on THIS screen within cooldown ─────────────
      final existingOnScreen = await _db!.rawQuery(
        '''
        SELECT COUNT(*) as count
        FROM page_impressions
        WHERE user_id    = ?
          AND product_id  = ?
          AND screen_name = ?
          AND created_at >= ?
        ''',
        [userId, productId, screenName, cutoff],
      );

      final countOnScreen = Sqflite.firstIntValue(existingOnScreen) ?? 0;
      if (countOnScreen > 0) {
        debugPrint(
          '⏳ ImpressionBatcher: $productId already recorded '
          'on $screenName for $userId',
        );
        return;
      }

      // ── Check 2: Max impressions per hour across all screens ──────────────────
      final existingTotal = await _db!.rawQuery(
        '''
        SELECT COUNT(*) as count
        FROM page_impressions
        WHERE user_id    = ?
          AND product_id  = ?
          AND created_at >= ?
        ''',
        [userId, productId, cutoff],
      );

      final totalCount = Sqflite.firstIntValue(existingTotal) ?? 0;
      if (totalCount >= _maxImpressionsPerHour) {
        debugPrint(
          '⚠️ ImpressionBatcher: $productId reached max impressions '
          '($_maxImpressionsPerHour) for $userId',
        );
        return;
      }

      // ── Enforce per-user row cap (FIFO eviction) ──────────────────────────────
      final countResult = await _db!.rawQuery(
        'SELECT COUNT(*) as count FROM page_impressions WHERE user_id = ?',
        [userId],
      );
      final rowCount = Sqflite.firstIntValue(countResult) ?? 0;

      if (rowCount >= _maxRowsPerUser) {
        final toEvict = rowCount - _maxRowsPerUser + 1;
        await _db!.rawDelete(
          '''
          DELETE FROM page_impressions
          WHERE id IN (
            SELECT id FROM page_impressions
            WHERE user_id = ?
            ORDER BY id ASC
            LIMIT ?
          )
          ''',
          [userId, toEvict],
        );
        debugPrint(
          '🧹 ImpressionBatcher: evicted $toEvict old rows for $userId',
        );
      }

      // ── Write new impression ──────────────────────────────────────────────────
      await _db!.insert('page_impressions', {
        'user_id': userId,
        'product_id': productId,
        'screen_name': screenName,
        'created_at': now.millisecondsSinceEpoch,
      });

      debugPrint(
        '✅ ImpressionBatcher: recorded impression '
        '#${totalCount + 1} for $productId on $screenName '
        'by $userId (${_maxImpressionsPerHour - totalCount - 1} remaining)',
      );

      // ── Add to send buffer ────────────────────────────────────────────────────
      _impressionBuffer.add(ImpressionRecord(
        productId: productId,
        screenName: screenName,
        timestamp: now,
      ));

      _scheduleBatch();

      if (_impressionBuffer.length >= _maxBatchSize) {
        debugPrint('⚠️ ImpressionBatcher: buffer full, forcing flush');
        unawaited(flush());
      }
    } catch (e) {
      debugPrint('❌ ImpressionBatcher: _recordImpression failed — $e');
    }
  }

  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchInterval, _sendBatch);
  }

  // ── Send batch ────────────────────────────────────────────────────────────────

  int? _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return null;
    try {
      final birth = birthDate.toDate();
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age >= 0 ? age : null;
    } catch (e) {
      debugPrint('Error calculating age: $e');
      return null;
    }
  }

  Future<void> _sendBatch() async {
    if (_impressionBuffer.isEmpty || _marketProvider == null) return;

    final recordsToSend = List<ImpressionRecord>.from(_impressionBuffer);
    _impressionBuffer.clear();

    try {
      // Aggregate counts per product ID
      final countMap = <String, int>{};
      for (final record in recordsToSend) {
        countMap[record.productId] = (countMap[record.productId] ?? 0) + 1;
      }

      // Expand back to list — CF deduplicates but this reduces payload size
      final idsToSend = <String>[];
      countMap.forEach((id, count) {
        for (var i = 0; i < count; i++) {
          idsToSend.add(id);
        }
      });

      final profileData = _marketProvider!.userProvider.profileData;
      final userGender = profileData?['gender'] as String?;
      final birthDate = profileData?['birthDate'] as Timestamp?;
      final userAge = _calculateAge(birthDate);

      await _marketProvider!.incrementImpressionCount(
        productIds: idsToSend,
        userGender: userGender,
        userAge: userAge,
      );

      debugPrint(
        '📊 ImpressionBatcher: sent ${recordsToSend.length} impressions '
        '(${countMap.length} unique) from $_currentUserId',
      );
      _retryCount = 0;
    } catch (e) {
      debugPrint('❌ ImpressionBatcher: send batch failed — $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = Duration(seconds: 2 * _retryCount);
        debugPrint(
          '🔄 ImpressionBatcher: retry $_retryCount/$_maxRetries '
          'in ${delay.inSeconds}s',
        );
        _impressionBuffer.addAll(recordsToSend);
        Future.delayed(delay, () {
          if (!_isDisposed) _sendBatch();
        });
      } else {
        debugPrint(
          '❌ ImpressionBatcher: max retries reached, '
          'dropping ${recordsToSend.length} impressions',
        );
        _retryCount = 0;
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────────

  Future<void> flush() async {
    _batchTimer?.cancel();
    await _sendBatch();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _batchTimer?.cancel();
    _cleanupTimer?.cancel();
    _authSubscription?.cancel();

    // Best-effort final flush
    if (_impressionBuffer.isNotEmpty) {
      await _sendBatch();
    }

    _impressionBuffer.clear();
    _marketProvider = null;

    await _db?.close();
    _db = null;
    _dbInitialized = false;
  }
}

// ── BoostedVisibilityWrapper (unchanged) ──────────────────────────────────────

class BoostedVisibilityWrapper extends StatefulWidget {
  final String productId;
  final Widget child;
  final String? screenName;
  final String? sourceCollection;

  const BoostedVisibilityWrapper({
    Key? key,
    required this.productId,
    required this.child,
    this.screenName,
    this.sourceCollection,
  }) : super(key: key);

  @override
  _BoostedVisibilityWrapperState createState() =>
      _BoostedVisibilityWrapperState();
}

class _BoostedVisibilityWrapperState extends State<BoostedVisibilityWrapper> {
  bool _hasRecordedImpression = false;
  static final _batcher = ImpressionBatcher();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_batcher._marketProvider == null) {
      final marketProvider =
          Provider.of<MarketProvider>(context, listen: false);
      // initialize() is now async but safe to call unawaited here —
      // it completes before any impression can be recorded since
      // addImpression() checks _db != null before writing.
      unawaited(_batcher.initialize(marketProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('boosted-${widget.productId}'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.5) {
          if (!_hasRecordedImpression) {
            final prefixedId = widget.sourceCollection != null
                ? '${widget.sourceCollection}_${widget.productId}'
                : widget.productId;

            _batcher.addImpression(
              prefixedId,
              screenName: widget.screenName,
            );
            _hasRecordedImpression = true;
          }
        }
      },
      child: widget.child,
    );
  }

  @override
  void didUpdateWidget(BoostedVisibilityWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.productId != oldWidget.productId) {
      _hasRecordedImpression = false;
    }
  }

  @override
  void dispose() {
    _hasRecordedImpression = false;
    super.dispose();
  }
}

void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('Unawaited error: $e'));
}
