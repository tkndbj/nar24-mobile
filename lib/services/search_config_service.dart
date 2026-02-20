// lib/services/search_config_service.dart
// Remote Search Configuration Service
//
// Listens to Firestore `config/search` document in real-time.
// Allows admin to remotely switch search provider (typesense ↔ firestore)
// without pushing an app update.
//
// Cost: 1 Firestore read on init + 1 read per config change (snapshot listener).
// Typically <5 reads/day unless admin is actively toggling.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum SearchBackend {
  typesense,
  firestore,
}

class SearchConfig {
  final SearchBackend provider;
  final DateTime? updatedAt;
  final String? reason;

  const SearchConfig({
    this.provider = SearchBackend.typesense,
    this.updatedAt,
    this.reason,
  });

  bool get useTypesense => provider == SearchBackend.typesense;
  bool get useFirestore => provider == SearchBackend.firestore;

  factory SearchConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SearchConfig();

    final providerStr = data['provider'] as String? ?? 'typesense';
    final provider = providerStr == 'firestore'
        ? SearchBackend.firestore
        : SearchBackend.typesense;

    DateTime? updatedAt;
    final ts = data['updatedAt'];
    if (ts is Timestamp) {
      updatedAt = ts.toDate();
    }

    return SearchConfig(
      provider: provider,
      updatedAt: updatedAt,
      reason: data['reason'] as String?,
    );
  }

  @override
  String toString() =>
      'SearchConfig(provider: ${provider.name}, reason: $reason)';
}

class SearchConfigService with ChangeNotifier {
  static SearchConfigService? _instance;
  static SearchConfigService get instance {
    _instance ??= SearchConfigService._internal();
    return _instance!;
  }

  SearchConfigService._internal();

  // ── State ──────────────────────────────────────────────────────────────────

  SearchConfig _config = const SearchConfig(); // Default: Typesense
  StreamSubscription<DocumentSnapshot>? _subscription;
  bool _initialized = false;
  bool _disposed = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Current search configuration (synchronous access).
  SearchConfig get config => _config;

  /// Quick check: should we use Typesense? (default: true)
  bool get useTypesense => _config.useTypesense;

  /// Quick check: should we use Firestore fallback?
  bool get useFirestore => _config.useFirestore;

  /// Whether the service has received its first config snapshot.
  bool get isInitialized => _initialized;

  /// Initialize the listener. Call once at app startup.
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// Returns quickly: sets up a snapshot listener and resolves
  /// as soon as the first snapshot arrives (or after timeout).
  Future<void> initialize() async {
    if (_initialized || _disposed) return;

    final completer = Completer<void>();

    _subscription = FirebaseFirestore.instance
        .collection('config')
        .doc('search')
        .snapshots(includeMetadataChanges: false)
        .listen(
      (snapshot) {
        final newConfig = SearchConfig.fromMap(
          snapshot.exists ? snapshot.data() : null,
        );

        final changed = newConfig.provider != _config.provider;
        _config = newConfig;

        if (!_initialized) {
          _initialized = true;
          if (!completer.isCompleted) completer.complete();
          if (kDebugMode) {
            debugPrint(
              '🔧 SearchConfig initialized: ${_config.provider.name}',
            );
          }
        }

        if (changed) {
          if (kDebugMode) {
            debugPrint(
              '🔧 SearchConfig changed → ${_config.provider.name}'
              '${_config.reason != null ? ' (${_config.reason})' : ''}',
            );
          }
          notifyListeners();
        }
      },
      onError: (error) {
        // On error, default to Typesense (safe fallback).
        if (kDebugMode) {
          debugPrint('SearchConfig listener error: $error');
        }
        _config = const SearchConfig(); // Typesense default
        if (!_initialized) {
          _initialized = true;
          if (!completer.isCompleted) completer.complete();
        }
      },
    );

    // Don't block app startup for more than 3 seconds.
    // If Firestore is slow, default to Typesense and update when snapshot arrives.
    return completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        if (!_initialized) {
          _initialized = true;
          if (kDebugMode) {
            debugPrint(
              'SearchConfig timed out, defaulting to Typesense',
            );
          }
        }
      },
    );
  }

  /// Clean up resources. Call when app is shutting down.
  void shutdown() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }

  /// For testing: reset the singleton.
  @visibleForTesting
  static void resetForTesting() {
    _instance?.shutdown();
    _instance = null;
  }
}
