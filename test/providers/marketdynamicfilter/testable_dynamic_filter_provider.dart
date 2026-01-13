// test/providers/testable_dynamic_filter_provider.dart
//
// TESTABLE MIRROR of DynamicFilterProvider pure logic from lib/providers/dynamic_filter_provider.dart
//
// This file contains EXACT copies of pure logic functions from DynamicFilterProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/dynamic_filter_provider.dart
//
// Last synced with: dynamic_filter_provider.dart (current version)

/// Configuration constants from DynamicFilterProvider
class TestableDynamicFilterConfig {
  static const int pageSize = 20;
  static const int maxCachedFilters = 10;
  static const int maxPagesPerFilter = 5; // Max 100 products per filter
  static const int maxCachedProducts = 500; // Total products across all filters
  static const Duration cacheTimeout = Duration(minutes: 2);
  static const int prefetchCount = 2;
  static const Duration initializationTimeout = Duration(seconds: 10);
}

/// Mirrors filter equality check from DynamicFilterProvider
class TestableFilterEqualityChecker {
  /// Mirrors _filtersEqual from DynamicFilterProvider
  /// Compares two filter lists for equality based on id, isActive, and order
  static bool filtersEqual(
    List<TestableFilterData> list1,
    List<TestableFilterData> list2,
  ) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].isActive != list2[i].isActive ||
          list1[i].order != list2[i].order) {
        return false;
      }
    }
    return true;
  }

  /// Check if a specific filter changed
  static bool filterChanged(TestableFilterData? old, TestableFilterData? current) {
    if (old == null && current == null) return false;
    if (old == null || current == null) return true;
    return old.id != current.id ||
        old.isActive != current.isActive ||
        old.order != current.order;
  }
}

/// Simple filter data for testing
class TestableFilterData {
  final String id;
  final bool isActive;
  final int order;
  final String name;
  final Map<String, String> displayName;

  TestableFilterData({
    required this.id,
    this.isActive = true,
    this.order = 0,
    this.name = '',
    this.displayName = const {},
  });

  TestableFilterData copyWith({
    String? id,
    bool? isActive,
    int? order,
    String? name,
    Map<String, String>? displayName,
  }) {
    return TestableFilterData(
      id: id ?? this.id,
      isActive: isActive ?? this.isActive,
      order: order ?? this.order,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
    );
  }
}

/// Mirrors display name resolution from DynamicFilterProvider
class TestableDisplayNameResolver {
  /// Mirrors getFilterDisplayName from DynamicFilterProvider
  /// Language fallback: languageCode -> 'tr' -> 'en' -> name
  static String getDisplayName({
    required Map<String, String> displayName,
    required String name,
    required String languageCode,
  }) {
    return displayName[languageCode] ??
        displayName['tr'] ??
        displayName['en'] ??
        name;
  }

  /// Get all available languages
  static List<String> getAvailableLanguages(Map<String, String> displayName) {
    return displayName.keys.toList();
  }

  /// Check if language is available
  static bool hasLanguage(Map<String, String> displayName, String languageCode) {
    return displayName.containsKey(languageCode);
  }
}

/// Mirrors cache validity check from DynamicFilterProvider
class TestableCacheValidator {
  final Duration cacheTimeout;
  final DateTime Function() nowProvider;

  TestableCacheValidator({
    this.cacheTimeout = TestableDynamicFilterConfig.cacheTimeout,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Mirrors hasFilterCache logic from DynamicFilterProvider
  bool isCacheValid(DateTime? cacheTimestamp) {
    if (cacheTimestamp == null) return false;
    return nowProvider().difference(cacheTimestamp) < cacheTimeout;
  }

  /// Get remaining cache time
  Duration? getRemainingCacheTime(DateTime? cacheTimestamp) {
    if (cacheTimestamp == null) return null;
    final elapsed = nowProvider().difference(cacheTimestamp);
    if (elapsed >= cacheTimeout) return Duration.zero;
    return cacheTimeout - elapsed;
  }

  /// Check if cache is about to expire (within 30 seconds)
  bool isCacheAboutToExpire(DateTime? cacheTimestamp) {
    final remaining = getRemainingCacheTime(cacheTimestamp);
    if (remaining == null) return true;
    return remaining <= const Duration(seconds: 30);
  }
}

/// Mirrors LRU cache management from DynamicFilterProvider
class TestableLRUFilterCache<T> {
  final Map<String, List<T>> _cache = {};
  final Map<String, DateTime> _accessTimes = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final int maxCachedFilters;
  final int maxCachedProducts;
  final int Function(List<T>) getProductCount;
  final DateTime Function() nowProvider;

  TestableLRUFilterCache({
    this.maxCachedFilters = TestableDynamicFilterConfig.maxCachedFilters,
    this.maxCachedProducts = TestableDynamicFilterConfig.maxCachedProducts,
    required this.getProductCount,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  Map<String, List<T>> get cache => Map.unmodifiable(_cache);
  int get filterCount => _cache.length;
  
  int get totalProductCount {
    return _cache.values.fold(0, (sum, products) => sum + getProductCount(products));
  }

  /// Set cache for filter
  void set(String filterId, List<T> products) {
    _cache[filterId] = products;
    _accessTimes[filterId] = nowProvider();
    _cacheTimestamps[filterId] = nowProvider();
    _enforceCacheLimits();
  }

  /// Get cache for filter
  List<T>? get(String filterId) {
    if (_cache.containsKey(filterId)) {
      _accessTimes[filterId] = nowProvider();
      return _cache[filterId];
    }
    return null;
  }

  /// Update access time (for LRU)
  void updateAccessTime(String filterId) {
    if (_cache.containsKey(filterId)) {
      _accessTimes[filterId] = nowProvider();
    }
  }

  /// Check if filter is cached
  bool containsKey(String filterId) => _cache.containsKey(filterId);

  /// Clear specific filter
  void remove(String filterId) {
    _cache.remove(filterId);
    _accessTimes.remove(filterId);
    _cacheTimestamps.remove(filterId);
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
    _accessTimes.clear();
    _cacheTimestamps.clear();
  }

  /// Mirrors _enforceCacheLimits from DynamicFilterProvider
  void _enforceCacheLimits() {
    // 1. Limit number of cached filters
    if (_cache.length > maxCachedFilters) {
      _evictLeastRecentlyUsedFilters();
    }

    // 2. Limit total cached products
    if (totalProductCount > maxCachedProducts) {
      _evictExcessProducts();
    }
  }

  /// Mirrors _evictLeastRecentlyUsedFilters from DynamicFilterProvider
  void _evictLeastRecentlyUsedFilters() {
    if (_accessTimes.isEmpty) return;

    // Sort filters by last access time
    final sortedFilters = _accessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Remove oldest filters until we're under the limit
    while (_cache.length > maxCachedFilters && sortedFilters.isNotEmpty) {
      final oldestFilter = sortedFilters.removeAt(0);
      remove(oldestFilter.key);
    }
  }

  /// Mirrors _evictExcessProducts from DynamicFilterProvider
  void _evictExcessProducts() {
    // Remove products from least recently used filters
    final sortedFilters = _accessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    int currentTotal = totalProductCount;

    for (var entry in sortedFilters) {
      if (currentTotal <= maxCachedProducts) break;

      final filterId = entry.key;
      final products = _cache[filterId];

      if (products != null && products.isNotEmpty) {
        // Remove half the products from this filter
        final halfSize = getProductCount(products) ~/ 2;
        if (halfSize > 0) {
          _cache[filterId] = (products).sublist(0, halfSize);
          currentTotal -= halfSize;
        }
      }
    }
  }

  /// Get oldest filter (LRU)
  String? get oldestFilterId {
    if (_accessTimes.isEmpty) return null;
    return _accessTimes.entries
        .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
        .key;
  }

  /// Get newest filter (MRU)
  String? get newestFilterId {
    if (_accessTimes.isEmpty) return null;
    return _accessTimes.entries
        .reduce((a, b) => a.value.isAfter(b.value) ? a : b)
        .key;
  }
}

/// Mirrors pagination state management from DynamicFilterProvider
class TestablePaginationManager {
  final Map<String, int> _currentPages = {};
  final Map<String, bool> _hasMorePages = {};
  final Map<String, bool> _isLoadingMore = {};
  final int maxPagesPerFilter;
  final int pageSize;

  TestablePaginationManager({
    this.maxPagesPerFilter = TestableDynamicFilterConfig.maxPagesPerFilter,
    this.pageSize = TestableDynamicFilterConfig.pageSize,
  });

  int getCurrentPage(String filterId) => _currentPages[filterId] ?? 0;
  bool hasMorePages(String filterId) => _hasMorePages[filterId] ?? true;
  bool isLoadingMore(String filterId) => _isLoadingMore[filterId] ?? false;

  /// Initialize pagination for filter
  void initialize(String filterId) {
    _currentPages.putIfAbsent(filterId, () => 0);
    _hasMorePages.putIfAbsent(filterId, () => true);
    _isLoadingMore.putIfAbsent(filterId, () => false);
  }

  /// Reset pagination for filter
  void reset(String filterId) {
    _currentPages[filterId] = 0;
    _hasMorePages[filterId] = true;
    _isLoadingMore[filterId] = false;
  }

  /// Check if can load more
  bool canLoadMore(String filterId) {
    if (!hasMorePages(filterId)) return false;
    if (isLoadingMore(filterId)) return false;
    
    final currentPage = getCurrentPage(filterId);
    if (currentPage >= maxPagesPerFilter - 1) {
      _hasMorePages[filterId] = false;
      return false;
    }
    
    return true;
  }

  /// Start loading more
  void startLoading(String filterId) {
    _isLoadingMore[filterId] = true;
  }

  /// Finish loading with results
  void finishLoading(String filterId, int resultCount) {
    _isLoadingMore[filterId] = false;
    _currentPages[filterId] = (_currentPages[filterId] ?? 0) + 1;
    _hasMorePages[filterId] = resultCount >= pageSize;
  }

  /// Finish loading with error
  void finishLoadingWithError(String filterId) {
    _isLoadingMore[filterId] = false;
    _hasMorePages[filterId] = false;
  }

  /// Get max products that can be loaded
  int getMaxProducts(String filterId) {
    return maxPagesPerFilter * pageSize;
  }

  /// Clear pagination for filter
  void clear(String filterId) {
    _currentPages.remove(filterId);
    _hasMorePages.remove(filterId);
    _isLoadingMore.remove(filterId);
  }

  /// Clear all pagination
  void clearAll() {
    _currentPages.clear();
    _hasMorePages.clear();
    _isLoadingMore.clear();
  }
}

/// Mirrors paginated cache from DynamicFilterProvider
class TestablePaginatedCache<T> {
  final Map<String, Map<int, List<T>>> _paginatedCache = {};
  final int maxPagesPerFilter;

  TestablePaginatedCache({
    this.maxPagesPerFilter = TestableDynamicFilterConfig.maxPagesPerFilter,
  });

  /// Set page cache
  void setPage(String filterId, int page, List<T> products) {
    _paginatedCache.putIfAbsent(filterId, () => {});
    _paginatedCache[filterId]![page] = products;
    _enforcePageLimits(filterId);
  }

  /// Get page cache
  List<T>? getPage(String filterId, int page) {
    return _paginatedCache[filterId]?[page];
  }

  /// Check if page is cached
  bool hasPage(String filterId, int page) {
    return _paginatedCache[filterId]?.containsKey(page) ?? false;
  }

  /// Get all pages for filter
  int getPageCount(String filterId) {
    return _paginatedCache[filterId]?.length ?? 0;
  }

  /// Enforce page limits
  void _enforcePageLimits(String filterId) {
    final pages = _paginatedCache[filterId];
    if (pages == null) return;

    if (pages.length > maxPagesPerFilter) {
      // Keep only the first maxPagesPerFilter pages
      final keysToRemove = pages.keys
          .where((page) => page >= maxPagesPerFilter)
          .toList();

      for (var key in keysToRemove) {
        pages.remove(key);
      }
    }
  }

  /// Clear filter cache
  void clear(String filterId) {
    _paginatedCache.remove(filterId);
  }

  /// Clear all cache
  void clearAll() {
    _paginatedCache.clear();
  }
}

/// Mirrors race condition protection from DynamicFilterProvider
class TestableRaceConditionProtector {
  final Set<String> _ongoingFetches = {};

  /// Check if fetch is in progress
  bool isFetching(String filterId) => _ongoingFetches.contains(filterId);

  /// Start fetch (returns false if already fetching)
  bool tryStartFetch(String filterId) {
    if (_ongoingFetches.contains(filterId)) {
      return false;
    }
    _ongoingFetches.add(filterId);
    return true;
  }

  /// End fetch
  void endFetch(String filterId) {
    _ongoingFetches.remove(filterId);
  }

  /// Clear all
  void clear() {
    _ongoingFetches.clear();
  }

  /// Get ongoing fetch count
  int get ongoingFetchCount => _ongoingFetches.length;
}