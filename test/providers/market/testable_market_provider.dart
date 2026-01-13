// test/providers/testable_market_provider.dart
//
// TESTABLE MIRROR of MarketProvider pure logic from lib/providers/market_provider.dart
//
// This file contains EXACT copies of pure logic functions from MarketProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/market_provider.dart
//
// Last synced with: market_provider.dart (current version)

import 'dart:async';

/// Mirrors _RequestDeduplicator from MarketProvider
class TestableRequestDeduplicator<T> {
  final Map<String, Future<T>> _pending = {};

  int get pendingCount => _pending.length;
  bool get hasPending => _pending.isNotEmpty;
  Set<String> get pendingKeys => _pending.keys.toSet();

  /// Mirrors deduplicate from _RequestDeduplicator
  Future<T> deduplicate(
    String key,
    Future<T> Function() request,
  ) async {
    // Return existing request if in progress
    if (_pending.containsKey(key)) {
      return _pending[key]!;
    }

    // Start new request
    final future = request();
    _pending[key] = future;

    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  void clear() => _pending.clear();
}

/// Mirrors cache configuration from MarketProvider
class TestableMarketCacheConfig {
  // Product cache
  static const Duration cacheTTL = Duration(minutes: 5);
  static const Duration maxAge = Duration(minutes: 5);
  static const int maxProductCacheSize = 30;
  static const int productCacheTrimTarget = 20;

  // Search cache
  static const int maxSearchCacheSize = 50;
  static const int searchCacheTrimTarget = 30;

  // Suggestion cache
  static const Duration suggestionCacheTTL = Duration(minutes: 1);
  static const int maxSuggestionCacheSize = 20;
  static const int suggestionCacheTrimTarget = 10;

  // Buyer category cache
  static const Duration buyerCategoryCacheTTL = Duration(minutes: 20);
  static const int maxBuyerCategoryCacheSize = 10;

  // Memory limit for products in list
  static const int maxProductsInMemory = 200;
}

/// Mirrors Algolia circuit breaker from MarketProvider
class TestableAlgoliaCircuitBreaker {
  int _failureCount = 0;
  DateTime? _lastFailure;
  bool _isOpen = false;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  static const int maxFailures = 8;
  static const Duration cooldown = Duration(minutes: 5);

  TestableAlgoliaCircuitBreaker({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  int get failureCount => _failureCount;
  bool get isOpen => _isOpen;
  DateTime? get lastFailure => _lastFailure;

  /// Mirrors _isAlgoliaCircuitOpen from MarketProvider
  bool isCircuitOpen() {
    if (!_isOpen) return false;

    if (_lastFailure != null) {
      final timeSinceFailure = nowProvider().difference(_lastFailure!);
      if (timeSinceFailure > cooldown) {
        _isOpen = false;
        _failureCount = 0;
        return false;
      }
    }

    return true;
  }

  /// Mirrors _recordAlgoliaFailure from MarketProvider
  void recordFailure() {
    _failureCount++;
    _lastFailure = nowProvider();

    if (_failureCount >= maxFailures) {
      _isOpen = true;
    }
  }

  /// Mirrors _recordAlgoliaSuccess from MarketProvider
  void recordSuccess() {
    if (_failureCount > 0 || _isOpen) {
      _failureCount = 0;
      _isOpen = false;
      _lastFailure = null;
    }
  }

  /// Reset circuit breaker (for testing)
  void reset() {
    _failureCount = 0;
    _isOpen = false;
    _lastFailure = null;
  }
}

/// Mirrors search cache key building from MarketProvider
class TestableSearchCacheKeyBuilder {
  /// Mirrors cache key construction in searchOnly
  /// Format: '$query|$filterType|$page|$_sortOption'
  static String buildKey({
    required String query,
    required String filterType,
    required int page,
    required String sortOption,
  }) {
    return '$query|$filterType|$page|$sortOption';
  }

  /// Parse cache key back to components
  static Map<String, dynamic>? parseKey(String key) {
    final parts = key.split('|');
    if (parts.length != 4) return null;

    return {
      'query': parts[0],
      'filterType': parts[1],
      'page': int.tryParse(parts[2]) ?? 0,
      'sortOption': parts[3],
    };
  }

  /// Check if two keys represent same search (ignoring page)
  static bool isSameSearch(String key1, String key2) {
    final parts1 = key1.split('|');
    final parts2 = key2.split('|');
    if (parts1.length != 4 || parts2.length != 4) return false;

    return parts1[0] == parts2[0] && // query
        parts1[1] == parts2[1] && // filterType
        parts1[3] == parts2[3]; // sortOption
  }
}

/// Mirrors filter type to facet filter mapping from MarketProvider
class TestableFilterTypeMapper {
  /// Mirrors switch statement in searchOnly
  static List<String>? mapFilterTypeToFacets(String filterType) {
    switch (filterType) {
      case 'deals':
        return ['discountPercentage>0'];
      case 'boosted':
        return ['isBoosted:true'];
      case 'trending':
        return ['dailyClickCount>=10'];
      case 'fiveStar':
        return ['averageRating=5'];
      case 'bestSellers':
        // Uses replica index, no facet filter
        return null;
      default:
        return null;
    }
  }

  /// Get all supported filter types
  static List<String> get supportedFilterTypes =>
      ['deals', 'boosted', 'trending', 'fiveStar', 'bestSellers'];

  /// Check if filter type is supported
  static bool isSupported(String filterType) {
    return filterType.isEmpty || supportedFilterTypes.contains(filterType);
  }
}

/// Mirrors sanitizeFieldName from MarketProvider
class TestableFieldSanitizer {
  /// Mirrors sanitizeFieldName from MarketProvider
  static String sanitize(String fieldName) {
    return fieldName.replaceAll('.', '_').replaceAll('/', '_');
  }

  /// Check if field name needs sanitization
  static bool needsSanitization(String fieldName) {
    return fieldName.contains('.') || fieldName.contains('/');
  }
}

/// Mirrors _updateSearchResults logic from MarketProvider
class TestableSearchResultUpdater<T> {
  final List<T> products = [];
  final Set<String> productIds = {};
  bool hasMore = true;

  final String Function(T) getId;
  final int maxProductsInMemory;

  TestableSearchResultUpdater({
    required this.getId,
    this.maxProductsInMemory = TestableMarketCacheConfig.maxProductsInMemory,
  });

  /// Mirrors _updateSearchResults from MarketProvider
  void updateResults(List<T> results, int page, int hitsPerPage) {
    hasMore = results.length >= hitsPerPage;

    if (page == 0) {
      products.clear();
      productIds.clear();
    }

    // Enforce memory limit before adding
    if (products.length > maxProductsInMemory) {
      var removeCount = products.length - maxProductsInMemory + 50;
      // Clamp to actual list size to prevent RangeError
      removeCount = removeCount.clamp(0, products.length);
      final toRemove = products.take(removeCount).map(getId).toSet();
      products.removeRange(0, removeCount);
      productIds.removeWhere((id) => toRemove.contains(id));
    }

    // Add new results with deduplication
    for (final product in results) {
      final id = getId(product);
      if (productIds.add(id)) {
        products.add(product);
      }
    }
  }

  void clear() {
    products.clear();
    productIds.clear();
    hasMore = true;
  }
}

/// Mirrors cache with TTL and LRU eviction from MarketProvider
class TestableLRUCache<T> {
  final Map<String, T> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  final int maxSize;
  final int trimTarget;
  final Duration ttl;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableLRUCache({
    required this.maxSize,
    required this.trimTarget,
    required this.ttl,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? (() => DateTime.now());

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;

  /// Get value if exists and not expired
  T? get(String key) {
    final timestamp = _timestamps[key];
    if (timestamp == null) return null;

    final now = nowProvider();
    if (now.difference(timestamp) > ttl) {
      // Expired
      _cache.remove(key);
      _timestamps.remove(key);
      return null;
    }

    return _cache[key];
  }

  /// Set value with current timestamp
  void set(String key, T value) {
    _cache[key] = value;
    _timestamps[key] = nowProvider();

    // Enforce size limit
    if (_cache.length > maxSize) {
      _enforceLimit();
    }
  }

  /// Remove specific key
  bool remove(String key) {
    _timestamps.remove(key);
    return _cache.remove(key) != null;
  }

  /// Clear all entries
  void clear() {
    _cache.clear();
    _timestamps.clear();
  }

  /// Mirrors cache limit enforcement from MarketProvider
  void _enforceLimit() {
    final sortedKeys = _timestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // Oldest first

    final toRemove = sortedKeys.take(sortedKeys.length - trimTarget).map((e) => e.key);

    for (final key in toRemove) {
      _cache.remove(key);
      _timestamps.remove(key);
    }
  }

  /// Clean up expired entries
  int cleanupExpired() {
    final now = nowProvider();
    int removedCount = 0;

    _timestamps.removeWhere((key, timestamp) {
      if (now.difference(timestamp) > ttl) {
        _cache.remove(key);
        removedCount++;
        return true;
      }
      return false;
    });

    return removedCount;
  }

  /// Get all keys (for testing)
  Set<String> get keys => _cache.keys.toSet();
}

/// Mirrors buyer category cache from MarketProvider
class TestableBuyerCategoryCache<T> {
  final Map<String, List<T>> _cache = {};
  final Map<String, DateTime> _timestamps = {};

  final int maxSize;
  final Duration ttl;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableBuyerCategoryCache({
    this.maxSize = TestableMarketCacheConfig.maxBuyerCategoryCacheSize,
    this.ttl = TestableMarketCacheConfig.buyerCategoryCacheTTL,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? (() => DateTime.now());

  int get length => _cache.length;

  /// Mirrors _getBuyerCategoryCache from MarketProvider
  List<T>? get(String category) {
    final timestamp = _timestamps[category];
    if (timestamp == null) return null;

    final now = nowProvider();
    if (now.difference(timestamp) > ttl) {
      // Cache expired, remove it
      _cache.remove(category);
      _timestamps.remove(category);
      return null;
    }

    return _cache[category];
  }

  /// Mirrors _setBuyerCategoryCache from MarketProvider
  void set(String category, List<T> products) {
    // Enforce cache size limit
    if (_cache.length >= maxSize && !_cache.containsKey(category)) {
      // Remove oldest entry
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _timestamps.entries) {
        if (oldestTime == null || entry.value.isBefore(oldestTime)) {
          oldestTime = entry.value;
          oldestKey = entry.key;
        }
      }

      if (oldestKey != null) {
        _cache.remove(oldestKey);
        _timestamps.remove(oldestKey);
      }
    }

    _cache[category] = products;
    _timestamps[category] = nowProvider();
  }

  /// Mirrors clearBuyerCategoryCache from MarketProvider
  void clear([String? specificCategory]) {
    if (specificCategory != null) {
      _cache.remove(specificCategory);
      _timestamps.remove(specificCategory);
    } else {
      _cache.clear();
      _timestamps.clear();
    }
  }
}

/// Mirrors suggestion cache from MarketProvider
class TestableSuggestionCache<T> {
  final Map<String, List<T>> _cache = {};
  final Map<String, DateTime> _timestamps = {};

  final Duration ttl;
  final int maxSize;
  final int trimTarget;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableSuggestionCache({
    this.ttl = TestableMarketCacheConfig.suggestionCacheTTL,
    this.maxSize = TestableMarketCacheConfig.maxSuggestionCacheSize,
    this.trimTarget = TestableMarketCacheConfig.suggestionCacheTrimTarget,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? (() => DateTime.now());

  int get length => _cache.length;

  /// Get suggestions if cached and not expired
  List<T>? get(String query) {
    if (!_cache.containsKey(query)) return null;

    final ts = _timestamps[query]!;
    final now = nowProvider();

    if (now.difference(ts) < ttl) {
      return _cache[query];
    } else {
      _cache.remove(query);
      _timestamps.remove(query);
      return null;
    }
  }

  /// Set suggestions with timestamp
  void set(String query, List<T> suggestions) {
    _cache[query] = suggestions;
    _timestamps[query] = nowProvider();

    // Enforce limit
    if (_cache.length > maxSize) {
      _enforceLimit();
    }
  }

  void _enforceLimit() {
    final sortedKeys = _timestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // Oldest first

    final toRemove = sortedKeys.take(sortedKeys.length - trimTarget).map((e) => e.key);

    for (final key in toRemove) {
      _cache.remove(key);
      _timestamps.remove(key);
    }
  }

  void clear() {
    _cache.clear();
    _timestamps.clear();
  }
}