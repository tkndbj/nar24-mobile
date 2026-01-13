// test/repositories/testable_product_repository.dart
//
// TESTABLE MIRROR of ProductRepository pure logic from lib/repositories/product_repository.dart
//
// This file contains EXACT copies of pure logic functions from ProductRepository
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/repositories/product_repository.dart
//
// Last synced with: product_repository.dart (current version)

/// Mirrors ID normalization logic from ProductRepository.fetchById
class TestableProductIdNormalizer {
  static const String prefix1 = 'products_';
  static const String prefix2 = 'shop_products_';

  /// Mirrors the ID normalization in ProductRepository.fetchById
  /// Returns normalized ID or throws ArgumentError for invalid input
  static String normalize(String id) {
    // 1️⃣ Validate input
    if (id.trim().isEmpty) {
      throw ArgumentError('Product ID cannot be empty');
    }

    // 2️⃣ Normalize out any Algolia prefix:
    var rawId = id.trim();
    if (rawId.startsWith(prefix1)) {
      rawId = rawId.substring(prefix1.length);
    } else if (rawId.startsWith(prefix2)) {
      rawId = rawId.substring(prefix2.length);
    }

    // Validate normalized ID
    if (rawId.isEmpty) {
      throw ArgumentError('Invalid product ID format: $id');
    }

    return rawId;
  }

  /// Check if an ID has an Algolia prefix
  static bool hasAlgoliaPrefix(String id) {
    final trimmed = id.trim();
    return trimmed.startsWith(prefix1) || trimmed.startsWith(prefix2);
  }
}

/// Mirrors cache logic from ProductRepository
class TestableProductCache<T> {
  final int maxSize;
  final Duration ttl;
  final Map<String, T> _cache = {};
  final Map<String, DateTime> _timestamps = {};

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableProductCache({
    this.maxSize = 30,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;

  bool containsKey(String key) => _cache.containsKey(key);
  T? operator [](String key) => _cache[key];

  /// Check if cache entry is valid (exists and not expired)
  /// Mirrors the TTL check in ProductRepository.fetchById
  bool isValid(String key) {
    if (!_cache.containsKey(key) || !_timestamps.containsKey(key)) {
      return false;
    }
    final cacheTime = _timestamps[key]!;
    return nowProvider().difference(cacheTime) < ttl;
  }

  /// Get item if valid, otherwise return null and remove expired entry
  /// Mirrors cache check in ProductRepository.fetchById
  T? getIfValid(String key) {
    if (!_cache.containsKey(key) || !_timestamps.containsKey(key)) {
      return null;
    }

    final cacheTime = _timestamps[key]!;
    if (nowProvider().difference(cacheTime) < ttl) {
      return _cache[key];
    } else {
      // Cache expired, remove it
      _cache.remove(key);
      _timestamps.remove(key);
      return null;
    }
  }

  /// Put item in cache with current timestamp
  void put(String key, T item) {
    _cache[key] = item;
    _timestamps[key] = nowProvider();

    if (_cache.length > maxSize) {
      evictOldestEntries();
    }
  }

  /// Mirrors _evictOldestEntries from ProductRepository
  void evictOldestEntries() {
    if (_cache.length <= maxSize) return;

    final sortedEntries = _timestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = sortedEntries.take(_cache.length - maxSize);
    for (final entry in toRemove) {
      _cache.remove(entry.key);
      _timestamps.remove(entry.key);
    }
  }

  /// Mirrors cleanupExpiredCache from ProductRepository
  void cleanupExpired() {
    final now = nowProvider();
    final expiredKeys = <String>[];

    for (final entry in _timestamps.entries) {
      if (now.difference(entry.value) > ttl) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _cache.remove(key);
      _timestamps.remove(key);
    }
  }

  /// Mirrors getCacheStats from ProductRepository
  Map<String, dynamic> getStats() {
    return {
      'cacheSize': _cache.length,
      'oldestCacheEntry': _timestamps.values.isEmpty
          ? null
          : _timestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
    };
  }

  void clear() {
    _cache.clear();
    _timestamps.clear();
  }
}

/// Mirrors in-flight request deduplication from ProductRepository
class TestableInFlightTracker {
  final Set<String> _inFlight = {};

  bool isInFlight(String id) => _inFlight.contains(id);

  /// Returns true if this is a new request, false if already in flight
  bool tryStart(String id) {
    if (_inFlight.contains(id)) {
      return false;
    }
    _inFlight.add(id);
    return true;
  }

  void complete(String id) {
    _inFlight.remove(id);
  }

  int get count => _inFlight.length;

  void clear() {
    _inFlight.clear();
  }
}