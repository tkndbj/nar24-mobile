// lib/services/firestore_read_tracker.dart
//
// Session-based Firestore usage tracker.
// Buffers counters in memory and writes at most one document update per
// flush interval (default 60s) to `firestore_usage_sessions/{sessionId}`.
// Intended to run for a few months in production and then be removed.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

class FirestoreReadTracker {
  FirestoreReadTracker._();
  static final FirestoreReadTracker instance = FirestoreReadTracker._();

  static const String _collection = 'firestore_usage_sessions';
  static const Duration _flushInterval = Duration(seconds: 60);

  // Hard caps so a single session document cannot exceed Firestore limits
  // (1 MiB / doc, ~20k field paths).
  static const int _maxFiles = 200;
  static const int _maxOperationsPerFile = 50;

  bool _initialized = false;
  String? _sessionId;
  DocumentReference<Map<String, dynamic>>? _doc;
  Timer? _flushTimer;
  bool _flushInFlight = false;
  bool _sessionWritten = false;

  String? _appVersion;
  String? _platform;

  int _pendingReads = 0;
  int _pendingWrites = 0;
  final Map<String, _FileBucket> _pending = {};

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _sessionId = const Uuid().v4();
    _doc = FirebaseFirestore.instance.collection(_collection).doc(_sessionId);

    _platform = _resolvePlatform();
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // package_info_plus not available — non-fatal.
    }

    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  /// Track a read operation.
  /// [file]      - snake_case basename of the calling file (e.g. "cart_provider").
  /// [operation] - short human description (e.g. "user cart items").
  /// [count]     - number of documents actually read.
  void trackRead(String file, String operation, int count) {
    if (!_initialized || count <= 0) return;
    _record(file, operation, count, isWrite: false);
  }

  /// Track a write operation. [count] defaults to 1.
  void trackWrite(String file, String operation, [int count = 1]) {
    if (!_initialized || count <= 0) return;
    _record(file, operation, count, isWrite: true);
  }

  void _record(String file, String operation, int count,
      {required bool isWrite}) {
    final safeFile = _sanitize(file);
    final safeOp = _sanitize(operation);
    if (safeFile.isEmpty || safeOp.isEmpty) return;

    final bucketKey =
        _pending.containsKey(safeFile) || _pending.length < _maxFiles
            ? safeFile
            : '_other';
    final bucket = _pending.putIfAbsent(bucketKey, () => _FileBucket());

    if (isWrite) {
      _pendingWrites += count;
      bucket.writes += count;
    } else {
      _pendingReads += count;
      bucket.reads += count;
    }

    final ops = bucket.operations;
    if (ops.containsKey(safeOp)) {
      ops[safeOp] = ops[safeOp]! + count;
    } else if (ops.length < _maxOperationsPerFile) {
      ops[safeOp] = count;
    } else {
      ops['_other'] = (ops['_other'] ?? 0) + count;
    }
  }

  /// Flush pending counters to Firestore immediately.
  /// Safe to call from app lifecycle handlers (paused/detached).
  Future<void> flushNow() => _flush();

  Future<void> _flush() async {
    if (!_initialized || _flushInFlight) return;
    if (_pendingReads == 0 && _pendingWrites == 0 && _pending.isEmpty) return;

    _flushInFlight = true;

    // Snapshot + clear so new events can accumulate during the write.
    final readsDelta = _pendingReads;
    final writesDelta = _pendingWrites;
    final fileDeltas = <String, _FileBucket>{};
    _pending.forEach((k, v) {
      fileDeltas[k] = _FileBucket()
        ..reads = v.reads
        ..writes = v.writes
        ..operations.addAll(v.operations);
    });
    _pendingReads = 0;
    _pendingWrites = 0;
    _pending.clear();

    try {
      final doc = _doc!;
      final user = FirebaseAuth.instance.currentUser;

      if (!_sessionWritten) {
        await doc.set({
          'sessionId': _sessionId,
          'date': _today(),
          'startedAt': FieldValue.serverTimestamp(),
          'appVersion': _appVersion,
          'platform': _platform,
          'userId': user?.uid,
          'displayName': user?.displayName,
          'email': user?.email,
          'totals': {'reads': 0, 'writes': 0},
        }, SetOptions(merge: true));
        _sessionWritten = true;
      }

      final payload = <String, Object?>{
        'lastActivityAt': FieldValue.serverTimestamp(),
        'totals.reads': FieldValue.increment(readsDelta),
        'totals.writes': FieldValue.increment(writesDelta),
      };
      if (user != null) {
        payload['userId'] = user.uid;
        if (user.displayName != null) payload['displayName'] = user.displayName;
        if (user.email != null) payload['email'] = user.email;
      }

      fileDeltas.forEach((file, b) {
        if (b.reads > 0) {
          payload['byFile.$file.reads'] = FieldValue.increment(b.reads);
        }
        if (b.writes > 0) {
          payload['byFile.$file.writes'] = FieldValue.increment(b.writes);
        }
        b.operations.forEach((op, c) {
          payload['byFile.$file.operations.$op'] = FieldValue.increment(c);
        });
      });

      await doc.set(payload, SetOptions(merge: true));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('⚠️ FirestoreReadTracker flush failed: $e');
        debugPrint('$st');
      }
      // Re-queue on failure so no data is lost across transient errors.
      _pendingReads += readsDelta;
      _pendingWrites += writesDelta;
      fileDeltas.forEach((file, b) {
        final existing = _pending.putIfAbsent(file, () => _FileBucket());
        existing.reads += b.reads;
        existing.writes += b.writes;
        b.operations.forEach((op, c) {
          existing.operations[op] = (existing.operations[op] ?? 0) + c;
        });
      });
    } finally {
      _flushInFlight = false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _initialized = false;
  }

  static String _sanitize(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'[.\/\\\[\]\*`~\x00-\x1F]'), '_');
  }

  String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  String _resolvePlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

class _FileBucket {
  int reads = 0;
  int writes = 0;
  final Map<String, int> operations = {};
}
