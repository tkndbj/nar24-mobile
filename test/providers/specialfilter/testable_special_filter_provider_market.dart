// test/providers/testable_special_filter_provider_market.dart
//
// TESTABLE MIRROR of SpecialFilterProviderMarket pure logic from lib/providers/special_filter_provider_market.dart
//
// This file contains EXACT copies of pure logic functions from SpecialFilterProviderMarket
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/special_filter_provider_market.dart
//
// Last synced with: special_filter_provider_market.dart (current version)

/// Configuration constants from SpecialFilterProviderMarket
class TestableSpecialFilterConfig {
  static const Duration cacheTTL = Duration(minutes: 5);
  static const int maxCacheSize = 30;
  static const int maxProductsPerFilter = 500;
  static const int maxNotifiersPerType = 20;
  static const int maxCacheSizeEnforced = 50; // Used in _enforceMaxCacheSize
  static const int maxRetries = 3;
  static const int defaultLimit = 20;

  /// Permanent filters that should never be cleaned up
  static const Set<String> permanentFilters = {
    'Home',
    'Women',
    'Men',
    'Electronics',
    'Home & Furniture',
    'Mother & Child',
  };

  /// Filters for cleanup that includes more types
  static const Set<String> permanentFiltersForCleanup = {
    'Home',
    'Women',
    'Men',
    'Electronics',
    'Deals',
    'Featured',
    'Trending',
    '5-Star',
    'Best Sellers',
  };

  /// Category filters that use subcategory grouping
  static const List<String> categoryFilters = [
    'Women',
    'Men',
    'Electronics',
    'Home & Furniture',
    'Mother & Child',
  ];

  /// Gender-based filters
  static const List<String> genderFilters = ['Women', 'Men'];
}

/// Mirrors cache staleness check from SpecialFilterProviderMarket
class TestableCacheStalenessChecker {
  final Map<String, DateTime> _lastFetched = {};
  final Duration cacheTTL;
  final DateTime Function() nowProvider;

  TestableCacheStalenessChecker({
    this.cacheTTL = TestableSpecialFilterConfig.cacheTTL,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Mirrors _isStale from SpecialFilterProviderMarket
  bool isStale(String filterType) {
    final last = _lastFetched[filterType] ?? DateTime.fromMillisecondsSinceEpoch(0);
    return nowProvider().difference(last) > cacheTTL;
  }

  /// Mark filter as fetched
  void markFetched(String filterType) {
    _lastFetched[filterType] = nowProvider();
  }

  /// Get time since last fetch
  Duration? getTimeSinceLastFetch(String filterType) {
    final last = _lastFetched[filterType];
    if (last == null) return null;
    return nowProvider().difference(last);
  }

  /// Check if filter has ever been fetched
  bool hasBeenFetched(String filterType) {
    return _lastFetched.containsKey(filterType);
  }

  /// Clear fetch time for filter
  void clearFetchTime(String filterType) {
    _lastFetched.remove(filterType);
  }
}

/// Mirrors cache key building from SpecialFilterProviderMarket
class TestableCacheKeyBuilder {
  /// Build cache key for filter + page
  /// Format: 'filterType|page'
  static String buildFilterPageKey(String filterType, int page) {
    return '$filterType|$page';
  }

  /// Build subcategory key
  /// Format: 'category|subcategoryId'
  static String buildSubcategoryKey(String category, String subcategoryId) {
    return '$category|$subcategoryId';
  }

  /// Build full subcategory page key
  /// Format: 'category|subcategoryId|page'
  static String buildSubcategoryPageKey(String category, String subcategoryId, int page) {
    final subcategoryKey = buildSubcategoryKey(category, subcategoryId);
    return '$subcategoryKey|$page';
  }

  /// Parse filter type from cache key
  static String? parseFilterType(String cacheKey) {
    final parts = cacheKey.split('|');
    return parts.isNotEmpty ? parts[0] : null;
  }

  /// Parse page from cache key
  static int? parsePage(String cacheKey) {
    final parts = cacheKey.split('|');
    if (parts.length >= 2) {
      return int.tryParse(parts.last);
    }
    return null;
  }

  /// Check if key matches filter type prefix
  static bool matchesFilterType(String cacheKey, String filterType) {
    return cacheKey.startsWith('$filterType|');
  }
}

/// Mirrors numeric field detection from SpecialFilterProviderMarket
class TestableNumericFieldDetector {
  /// Numeric fields that need type conversion
  static const List<String> numericFields = [
    'averageRating',
    'price',
    'discountPercentage',
    'stockQuantity',
    'purchaseCount',
  ];

  /// Mirrors _isNumericField from SpecialFilterProviderMarket
  static bool isNumericField(String fieldName) {
    return numericFields.contains(fieldName);
  }

  /// Mirrors _convertToNumber from SpecialFilterProviderMarket
  static dynamic convertToNumber(dynamic value) {
    if (value is String) {
      return double.tryParse(value) ?? int.tryParse(value) ?? value;
    }
    return value;
  }

  /// Convert value if field is numeric
  static dynamic convertIfNumeric(String fieldName, dynamic value) {
    if (isNumericField(fieldName)) {
      return convertToNumber(value);
    }
    return value;
  }
}

/// Mirrors product validation from SpecialFilterProviderMarket
class TestableProductValidator {
  /// Mirrors _isValidProduct from SpecialFilterProviderMarket
  static bool isValidProduct({
    required String id,
    required String productName,
    required double price,
    required double averageRating,
  }) {
    return id.isNotEmpty &&
        productName.isNotEmpty &&
        price >= 0 &&
        averageRating >= 0 &&
        averageRating <= 5;
  }

  /// Validate product map
  static bool isValidProductMap(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final name = data['productName'] as String? ?? data['title'] as String? ?? '';
    final price = (data['price'] as num?)?.toDouble() ?? -1;
    final rating = (data['averageRating'] as num?)?.toDouble() ?? 0;

    return isValidProduct(
      id: id,
      productName: name,
      price: price,
      averageRating: rating,
    );
  }

  /// Get validation errors
  static List<String> getValidationErrors({
    required String id,
    required String productName,
    required double price,
    required double averageRating,
  }) {
    final errors = <String>[];

    if (id.isEmpty) errors.add('Empty ID');
    if (productName.isEmpty) errors.add('Empty product name');
    if (price < 0) errors.add('Negative price');
    if (averageRating < 0) errors.add('Rating below 0');
    if (averageRating > 5) errors.add('Rating above 5');

    return errors;
  }
}

/// Mirrors sort option mapping from SpecialFilterProviderMarket
class TestableSortOptionMapper {
  /// Sort options for subcategory screens
  static const String sortDate = 'date';
  static const String sortAlphabetical = 'alphabetical';
  static const String sortPriceAsc = 'price_asc';
  static const String sortPriceDesc = 'price_desc';

  /// Get sort field for option
  static String getSortField(String sortOption) {
    switch (sortOption) {
      case 'alphabetical':
        return 'title';
      case 'price_asc':
      case 'price_desc':
        return 'price';
      case 'date':
      default:
        return 'promotionScore'; // Primary sort for date
    }
  }

  /// Get sort descending flag
  static bool isSortDescending(String sortOption) {
    switch (sortOption) {
      case 'alphabetical':
        return false;
      case 'price_asc':
        return false;
      case 'price_desc':
        return true;
      case 'date':
      default:
        return true;
    }
  }

  /// Check if sort option needs secondary sort
  static bool needsSecondarySort(String sortOption) {
    return sortOption == 'date';
  }

  /// Get secondary sort field (for date sorting)
  static String? getSecondarySortField(String sortOption) {
    if (sortOption == 'date') {
      return 'createdAt';
    }
    return null;
  }

  /// Validate sort option
  static bool isValidSortOption(String sortOption) {
    return [sortDate, sortAlphabetical, sortPriceAsc, sortPriceDesc].contains(sortOption);
  }
}

/// Mirrors quick filter mapping from SpecialFilterProviderMarket
class TestableQuickFilterMapper {
  /// Quick filter types
  static const String filterDeals = 'deals';
  static const String filterBoosted = 'boosted';
  static const String filterTrending = 'trending';
  static const String filterFiveStar = 'fiveStar';
  static const String filterBestSellers = 'bestSellers';

  /// Get filter condition for quick filter
  static FilterCondition? getFilterCondition(String? filterKey) {
    if (filterKey == null || filterKey.isEmpty) return null;

    switch (filterKey) {
      case 'deals':
        return FilterCondition(
          field: 'discountPercentage',
          operator: '>',
          value: 0,
        );
      case 'boosted':
        return FilterCondition(
          field: 'isBoosted',
          operator: '==',
          value: true,
        );
      case 'trending':
        return FilterCondition(
          field: 'dailyClickCount',
          operator: '>=',
          value: 10,
        );
      case 'fiveStar':
        return FilterCondition(
          field: 'averageRating',
          operator: '==',
          value: 5,
        );
      case 'bestSellers':
        return FilterCondition(
          field: 'purchaseCount',
          operator: '>',
          value: 0,
        );
      default:
        return null;
    }
  }

  /// Get sort field for quick filter
  static String? getSortField(String filterKey) {
    switch (filterKey) {
      case 'deals':
        return 'discountPercentage';
      case 'trending':
        return 'dailyClickCount';
      case 'bestSellers':
        return 'purchaseCount';
      case 'boosted':
      case 'fiveStar':
        return 'createdAt';
      default:
        return null;
    }
  }

  /// Check if filter key is valid
  static bool isValidFilterKey(String filterKey) {
    return [filterDeals, filterBoosted, filterTrending, filterFiveStar, filterBestSellers]
        .contains(filterKey);
  }
}

/// Filter condition structure
class FilterCondition {
  final String field;
  final String operator;
  final dynamic value;

  FilterCondition({
    required this.field,
    required this.operator,
    required this.value,
  });
}

/// Mirrors LRU cache enforcement from SpecialFilterProviderMarket
class TestableLRUCacheEnforcer<T> {
  final Map<String, T> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  final int maxSize;
  final DateTime Function() nowProvider;

  TestableLRUCacheEnforcer({
    this.maxSize = TestableSpecialFilterConfig.maxCacheSizeEnforced,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  Map<String, T> get cache => Map.unmodifiable(_cache);
  int get size => _cache.length;

  /// Add to cache
  void set(String key, T value) {
    _cache[key] = value;
    _timestamps[key] = nowProvider();
    _enforceMaxSize();
  }

  /// Get from cache
  T? get(String key) => _cache[key];

  /// Check if key exists
  bool containsKey(String key) => _cache.containsKey(key);

  /// Remove specific key
  void remove(String key) {
    _cache.remove(key);
    _timestamps.remove(key);
  }

  /// Mirrors _enforceMaxCacheSize from SpecialFilterProviderMarket
  void _enforceMaxSize() {
    while (_cache.length > maxSize) {
      // Find oldest entry
      final oldestEntry = _timestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b);

      _cache.remove(oldestEntry.key);
      _timestamps.remove(oldestEntry.key);
    }
  }

  /// Remove all keys matching prefix
  void removeByPrefix(String prefix) {
    final keysToRemove = _cache.keys
        .where((key) => key.startsWith('$prefix|'))
        .toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
      _timestamps.remove(key);
    }
  }

  /// Clear all
  void clear() {
    _cache.clear();
    _timestamps.clear();
  }

  /// Get oldest key
  String? get oldestKey {
    if (_timestamps.isEmpty) return null;
    return _timestamps.entries
        .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
        .key;
  }
}

/// Mirrors has more calculation from SpecialFilterProviderMarket
class TestableHasMoreCalculator {
  /// Calculate hasMore based on result count and limit
  static bool calculateHasMore(int resultCount, int limit) {
    return resultCount >= limit;
  }

  /// Calculate hasMore for paginated subcategories
  static bool calculateHasMoreForSubcategories(int totalCount, int endIndex) {
    return totalCount > endIndex;
  }
}

/// Mirrors orphaned data cleanup logic from SpecialFilterProviderMarket
class TestableOrphanedDataCleaner {
  /// Find keys to remove based on valid filter types
  static List<String> findOrphanedKeys(
    Set<String> existingKeys,
    Set<String> validFilterTypes,
  ) {
    return existingKeys
        .where((key) => !validFilterTypes.contains(key))
        .toList();
  }

  /// Find filter notifiers to clean up
  static List<String> findNotifiersToCleanup(
    Set<String> existingKeys,
    Set<String> activeFilterIds,
  ) {
    final keepFilters = {
      ...TestableSpecialFilterConfig.permanentFiltersForCleanup,
      ...activeFilterIds,
    };

    return existingKeys.where((key) => !keepFilters.contains(key)).toList();
  }

  /// Find subcategory notifiers to clean up
  static List<String> findSubcategoryNotifiersToCleanup(
    Set<String> existingKeys,
    Set<String> activeFilterIds,
  ) {
    final keepFilters = {
      ...TestableSpecialFilterConfig.permanentFiltersForCleanup,
      ...activeFilterIds,
    };

    return existingKeys.where((key) {
      final filterType = key.split('|')[0];
      return !keepFilters.contains(filterType);
    }).toList();
  }
}

/// Mirrors subcategory filter logic from SpecialFilterProviderMarket
class TestableSubcategoryFilterLogic {
  /// Determine if subcategory filter should be applied
  /// When subcategoryId == category, we're at top level, don't filter by subcategory
  static bool shouldApplySubcategoryFilter(String category, String subcategoryId) {
    return subcategoryId.isNotEmpty && subcategoryId != category;
  }

  /// Determine if subsubcategory acts as subcategory filter
  /// When subcategoryId == category, "subsubcategory" selection is actually a subcategory
  static bool isSubsubcategoryActingAsSubcategory(String category, String subcategoryId) {
    return subcategoryId == category;
  }

  /// Get the appropriate field to filter on for dynamic subsubcategory
  static String getSubsubcategoryFilterField(String category, String subcategoryId) {
    if (isSubsubcategoryActingAsSubcategory(category, subcategoryId)) {
      return 'subcategory';
    }
    return 'subsubcategory';
  }
}

/// Mirrors attribute filter operator application
class TestableAttributeFilterOperator {
  /// Valid operators
  static const List<String> validOperators = [
    '==',
    '!=',
    '>',
    '>=',
    '<',
    '<=',
    'array-contains',
    'array-contains-any',
    'in',
    'not-in',
  ];

  /// Check if operator is valid
  static bool isValidOperator(String operator) {
    return validOperators.contains(operator);
  }

  /// Get default operator
  static String get defaultOperator => '==';

  /// Check if operator requires array value
  static bool requiresArrayValue(String operator) {
    return ['array-contains-any', 'in', 'not-in'].contains(operator);
  }

  /// Check if operator is comparison
  static bool isComparisonOperator(String operator) {
    return ['>', '>=', '<', '<='].contains(operator);
  }
}

/// Mirrors pagination state management
class TestablePaginationState {
  int currentPage = 0;
  bool hasMore = true;
  bool isLoading = false;
  bool isLoadingMore = false;

  void reset() {
    currentPage = 0;
    hasMore = true;
    isLoading = false;
    isLoadingMore = false;
  }

  void incrementPage() {
    currentPage++;
  }

  void setHasMore(int resultCount, int limit) {
    hasMore = resultCount >= limit;
  }
}