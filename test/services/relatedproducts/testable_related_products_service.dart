// test/services/testable_related_products_service.dart
//
// TESTABLE MIRROR of RelatedProductsService pure logic from lib/services/related_products_service.dart
//
// This file contains EXACT copies of pure logic functions from RelatedProductsService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/related_products_service.dart
//
// Last synced with: related_products_service.dart (current version)

/// Mirrors cache configuration from RelatedProductsService
class TestableRelatedCacheConfig {
  /// Cache TTL
  /// Mirrors _cacheTTL
  static const Duration cacheTTL = Duration(hours: 2);

  /// Maximum cache entries before LRU eviction
  /// Mirrors _maxCacheSize
  static const int maxCacheSize = 30;

  /// Firestore batch fetch limit
  static const int batchFetchLimit = 10;
}

/// Mirrors _CachedRelated from RelatedProductsService
class TestableCachedRelated<T> {
  final List<T> products;
  final DateTime timestamp;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableCachedRelated({
    required this.products,
    required this.timestamp,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors isExpired getter from _CachedRelated
  bool get isExpired {
    return nowProvider().difference(timestamp) >
        TestableRelatedCacheConfig.cacheTTL;
  }

  /// Get age of cache entry
  Duration get age => nowProvider().difference(timestamp);

  /// Get remaining TTL
  Duration get remainingTTL {
    final remaining = TestableRelatedCacheConfig.cacheTTL - age;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Mirrors _chunkList from RelatedProductsService
class TestableListChunker {
  /// Mirrors _chunkList from RelatedProductsService
  /// Utility: Chunk list into smaller lists
  static List<List<T>> chunkList<T>(List<T> list, int size) {
    if (size <= 0) {
      throw ArgumentError('Chunk size must be positive');
    }
    
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }

  /// Get number of chunks needed
  static int getChunkCount(int listLength, int chunkSize) {
    if (chunkSize <= 0) return 0;
    return (listLength / chunkSize).ceil();
  }

  /// Check if list needs chunking
  static bool needsChunking(int listLength, int chunkSize) {
    return listLength > chunkSize;
  }
}

/// Mirrors LRU cache management from RelatedProductsService
class TestableRelatedCache<T> {
  final Map<String, TestableCachedRelated<T>> _cache = {};
  final int maxSize;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableRelatedCache({
    this.maxSize = TestableRelatedCacheConfig.maxCacheSize,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? (() => DateTime.now());

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;
  bool get isNotEmpty => _cache.isNotEmpty;
  bool get isFull => _cache.length >= maxSize;

  /// Get cached entry if valid
  List<T>? get(String key) {
    final cached = _cache[key];
    if (cached == null) return null;

    if (cached.isExpired) {
      _cache.remove(key);
      return null;
    }

    return cached.products;
  }

  /// Check if key exists and is valid
  bool containsValid(String key) {
    final cached = _cache[key];
    if (cached == null) return false;
    return !cached.isExpired;
  }

  /// Mirrors _cacheRelatedProducts from RelatedProductsService
  /// Cache with LRU eviction when full
  void set(String key, List<T> products) {
    _cache[key] = TestableCachedRelated<T>(
      products: products,
      timestamp: nowProvider(),
      nowProvider: nowProvider,
    );

    // Evict oldest if cache is full
    if (_cache.length > maxSize) {
      _evictOldest();
    }
  }

  /// Evict oldest entry (LRU)
  void _evictOldest() {
    if (_cache.isEmpty) return;

    final sortedKeys = _cache.entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
    _cache.remove(sortedKeys.first.key);
  }

  /// Remove specific entry
  bool remove(String key) {
    return _cache.remove(key) != null;
  }

  /// Clear all entries
  void clear() {
    _cache.clear();
  }

  /// Mirrors getCacheStats from RelatedProductsService
  Map<String, dynamic> getStats() {
    return {
      'totalEntries': _cache.length,
      'expiredEntries': _cache.values.where((c) => c.isExpired).length,
      'freshEntries': _cache.values.where((c) => !c.isExpired).length,
    };
  }

  /// Get all keys (for testing)
  List<String> get keys => _cache.keys.toList();

  /// Get oldest entry key (for testing LRU)
  String? get oldestKey {
    if (_cache.isEmpty) return null;
    final sortedKeys = _cache.entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
    return sortedKeys.first.key;
  }

  /// Get newest entry key
  String? get newestKey {
    if (_cache.isEmpty) return null;
    final sortedKeys = _cache.entries.toList()
      ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
    return sortedKeys.first.key;
  }
}

/// Mirrors related product ID extraction
class TestableRelatedIdExtractor {
  /// Extract related product IDs from document data
  static List<String> extractRelatedIds(Map<String, dynamic>? data) {
    if (data == null) return [];
    return List<String>.from(data['relatedProductIds'] ?? []);
  }

  /// Check if product has related IDs computed
  static bool hasRelatedIds(Map<String, dynamic>? data) {
    if (data == null) return false;
    final ids = data['relatedProductIds'];
    return ids != null && ids is List && ids.isNotEmpty;
  }
}

/// Mirrors self-exclusion logic from fallback strategy
class TestableProductFilter {
  /// Filter out the source product from results
  static List<T> excludeSourceProduct<T>(
    List<T> products,
    String sourceId,
    String Function(T) getId,
  ) {
    return products.where((p) => getId(p) != sourceId).toList();
  }

  /// Limit results to max count
  static List<T> limitResults<T>(List<T> products, int limit) {
    if (products.length <= limit) return products;
    return products.sublist(0, limit);
  }
}