// lib/services/firestore_read_tracker.dart
//
// Debug-only Firestore read/write tracker.
// Logs a rolling summary of all Firestore operations with caller info.
// Zero overhead in release builds — all logic is guarded by kDebugMode.

import 'dart:async';
import 'package:flutter/foundation.dart';

class FirestoreReadTracker {
  FirestoreReadTracker._();
  static final instance = FirestoreReadTracker._();

  // Cumulative counters since app launch (or last reset)
  int _totalReads = 0;
  int _totalWrites = 0;
  int _sessionReads = 0;
  int _sessionWrites = 0;

  // App launch tracking
  int _launchReads = 0;
  bool _launchPhase = true;
  Timer? _launchTimer;

  // Per-source breakdown: source label → count
  final Map<String, int> _readsBySource = {};
  final Map<String, int> _writesBySource = {};
  final Map<String, int> _launchReadsBySource = {};

  // Periodic summary timer
  Timer? _summaryTimer;

  int get totalReads => _totalReads;
  int get totalWrites => _totalWrites;

  /// Call once at app startup (inside kDebugMode guard).
  void initialize() {
    if (!kDebugMode) return;

    _summaryTimer?.cancel();
    _summaryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      printSummary();
    });

    // Track launch phase for 10 seconds after init
    _launchPhase = true;
    _launchReads = 0;
    _launchReadsBySource.clear();
    _launchTimer?.cancel();
    _launchTimer = Timer(const Duration(seconds: 10), () {
      _launchPhase = false;
      _printLaunchSummary();
    });

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════╗');
    debugPrint('║  📊 Firestore Read Tracker ACTIVE            ║');
    debugPrint('║  Filter logs with: [READS] or [WRITES]       ║');
    debugPrint('║  Launch summary prints after 10s             ║');
    debugPrint('║  Rolling summary prints every 1 min          ║');
    debugPrint('╚══════════════════════════════════════════════╝');
    debugPrint('');
  }

  /// Track a read operation.
  /// [source] — short label like "CartProvider", "UserProvider"
  /// [detail] — what was read, e.g. "users/{uid}/cart"
  /// [count]  — number of documents in the snapshot/result
  void trackRead(String source, String detail, int count) {
    if (!kDebugMode) return;

    _totalReads += count;
    _sessionReads += count;
    _readsBySource[source] = (_readsBySource[source] ?? 0) + count;

    // Track launch reads separately
    if (_launchPhase) {
      _launchReads += count;
      _launchReadsBySource[source] =
          (_launchReadsBySource[source] ?? 0) + count;
    }

    debugPrint('📊 [READS] $source: $count ($detail)');
  }

  /// Track a write operation.
  void trackWrite(String source, String detail, [int count = 1]) {
    if (!kDebugMode) return;

    _totalWrites += count;
    _sessionWrites += count;
    _writesBySource[source] = (_writesBySource[source] ?? 0) + count;

    debugPrint('📊 [WRITES] $source: $count ($detail)');
  }

  /// Print launch-only summary (first 10 seconds).
  void _printLaunchSummary() {
    if (!kDebugMode) return;

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════╗');
    debugPrint('║     🚀 APP LAUNCH READS (first 10s)          ║');
    debugPrint('╠══════════════════════════════════════════════╣');
    debugPrint('║  Launch Reads: $_launchReads');
    debugPrint('╠══════════════════════════════════════════════╣');

    final sorted = _launchReadsBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      final pct = (_launchReads > 0)
          ? ' (${(entry.value / _launchReads * 100).toStringAsFixed(1)}%)'
          : '';
      debugPrint('║    ${entry.key}: ${entry.value}$pct');
    }

    // Show what's missing (0 reads)
    final allSources = [
      'UserProvider', 'BadgeProvider', 'CartProvider', 'FavoriteProvider',
      'CouponService', 'SalesConfigService', 'SearchConfigService',
      'BoostedRotationProvider',
    ];
    for (final source in allSources) {
      if (!_launchReadsBySource.containsKey(source)) {
        debugPrint('║    $source: 0 ✅');
      }
    }

    debugPrint('╚══════════════════════════════════════════════╝');
    debugPrint('');
  }

  /// Print a full summary to the console.
  void printSummary() {
    if (!kDebugMode) return;

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════╗');
    debugPrint('║       📊 FIRESTORE USAGE SUMMARY             ║');
    debugPrint('╠══════════════════════════════════════════════╣');
    debugPrint('║  Total Reads:  $_totalReads');
    debugPrint('║  Total Writes: $_totalWrites');
    debugPrint('╠══════════════════════════════════════════════╣');
    debugPrint('║  READS BY SOURCE:');

    // Sort by count descending
    final sortedReads = _readsBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedReads) {
      final pct = (_totalReads > 0)
          ? ' (${(entry.value / _totalReads * 100).toStringAsFixed(1)}%)'
          : '';
      debugPrint('║    ${entry.key}: ${entry.value}$pct');
    }

    if (_writesBySource.isNotEmpty) {
      debugPrint('╠══════════════════════════════════════════════╣');
      debugPrint('║  WRITES BY SOURCE:');
      final sortedWrites = _writesBySource.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedWrites) {
        debugPrint('║    ${entry.key}: ${entry.value}');
      }
    }

    debugPrint('╚══════════════════════════════════════════════╝');
    debugPrint('');
  }

  /// Reset session counters (e.g. on hot restart).
  void resetSession() {
    if (!kDebugMode) return;

    debugPrint(
        '📊 [RESET] Session reads: $_sessionReads, writes: $_sessionWrites');
    _sessionReads = 0;
    _sessionWrites = 0;
  }

  void dispose() {
    _summaryTimer?.cancel();
    _launchTimer?.cancel();
  }
}
