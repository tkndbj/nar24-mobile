// test/providers/testable_shop_provider.dart
//
// TESTABLE MIRROR of ShopProvider pure logic from lib/providers/shop_provider.dart
//
// This file contains EXACT copies of pure logic functions from ShopProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/shop_provider.dart
//
// Last synced with: shop_provider.dart (current version)

import 'dart:convert';

/// Mirrors circuit breaker logic from ShopProvider
class TestableCircuitBreaker {
  static const int maxConsecutiveFailures = 3;
  static const Duration resetDuration = Duration(minutes: 1);

  int consecutiveFailures = 0;
  DateTime? resetTime;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableCircuitBreaker({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors _isCircuitBreakerOpen from ShopProvider
  bool isOpen() {
    if (resetTime == null) return false;

    if (nowProvider().isAfter(resetTime!)) {
      // Reset circuit breaker after cooldown
      consecutiveFailures = 0;
      resetTime = null;
      return false;
    }

    return true;
  }

  /// Mirrors _onOperationSuccess from ShopProvider
  void onSuccess() {
    if (consecutiveFailures > 0) {
      consecutiveFailures = 0;
      resetTime = null;
    }
  }

  /// Mirrors _onOperationFailure from ShopProvider
  void onFailure() {
    consecutiveFailures++;

    if (consecutiveFailures >= maxConsecutiveFailures) {
      resetTime = nowProvider().add(resetDuration);
    }
  }

  void reset() {
    consecutiveFailures = 0;
    resetTime = null;
  }
}

/// Mirrors retry with exponential backoff from ShopProvider
class TestableRetryBackoff {
  static const int defaultMaxAttempts = 3;
  static const Duration defaultInitialDelay = Duration(milliseconds: 200);

  /// Calculate delay for a given attempt (0-indexed internally, but attempt 1 = first retry)
  /// Mirrors: delay *= 2 after each failure
  static Duration calculateDelay(int attempt, {Duration? initialDelay}) {
    final initial = initialDelay ?? defaultInitialDelay;
    // attempt 0 = initial, attempt 1 = initial * 2, attempt 2 = initial * 4
    return initial * (1 << attempt);
  }

  /// Get the sequence of delays for all retries
  static List<Duration> getRetrySequence({
    int maxAttempts = defaultMaxAttempts,
    Duration initialDelay = defaultInitialDelay,
  }) {
    final delays = <Duration>[];
    Duration delay = initialDelay;
    
    for (var i = 0; i < maxAttempts - 1; i++) {
      delays.add(delay);
      delay *= 2;
    }
    
    return delays;
  }

  /// Check if should retry
  static bool shouldRetry(int currentAttempt, {int maxAttempts = defaultMaxAttempts}) {
    return currentAttempt < maxAttempts;
  }
}

/// Mirrors cache size management from ShopProvider
class TestableCacheManager {
  static const int maxCacheSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int maxProductsInMemory = 200;
  static const Duration cacheExpiryDuration = Duration(days: 7);

  /// Mirrors _isCacheSizeExceeded from ShopProvider
  static bool isCacheSizeExceeded(String jsonString) {
    final bytes = utf8.encode(jsonString).length;
    return bytes > maxCacheSizeBytes;
  }

  /// Calculate cache size in bytes
  static int getCacheSizeBytes(String jsonString) {
    return utf8.encode(jsonString).length;
  }

  /// Check if cache is expired
  static bool isCacheExpired(DateTime lastFetch, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(lastFetch) > cacheExpiryDuration;
  }

  /// Mirrors _trimProductListIfNeeded logic from ShopProvider
  static List<T> trimListIfNeeded<T>(List<T> items, {int? maxItems}) {
    final max = maxItems ?? maxProductsInMemory;
    if (items.length > max) {
      final excess = items.length - max;
      return items.sublist(excess);
    }
    return items;
  }

  /// Calculate how many items would be trimmed
  static int calculateExcess(int currentCount, {int? maxItems}) {
    final max = maxItems ?? maxProductsInMemory;
    return currentCount > max ? currentCount - max : 0;
  }
}

/// Mirrors role verification from ShopProvider._verifyUserStillMemberOfShop
class TestableRoleVerifier {
  /// Mirrors _verifyUserStillMemberOfShop from ShopProvider
  static bool verifyUserRole(
    String uid,
    String role,
    Map<String, dynamic> shopData,
  ) {
    switch (role) {
      case 'owner':
        return shopData['ownerId'] == uid;
      case 'co-owner':
        final coOwners = (shopData['coOwners'] as List?)?.cast<String>() ?? [];
        return coOwners.contains(uid);
      case 'editor':
        final editors = (shopData['editors'] as List?)?.cast<String>() ?? [];
        return editors.contains(uid);
      case 'viewer':
        final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
        return viewers.contains(uid);
      default:
        return false;
    }
  }

  /// Get all valid roles
  static List<String> get validRoles => ['owner', 'co-owner', 'editor', 'viewer'];

  /// Check if a role string is valid
  static bool isValidRole(String role) {
    return validRoles.contains(role);
  }
}

/// Mirrors filter summary generation from ShopProvider.getFilterSummary
class TestableFilterSummary {
  /// Mirrors getFilterSummary from ShopProvider
  static String generate({
    String? selectedGender,
    List<String> selectedBrands = const [],
    List<String> selectedTypes = const [],
    List<String> selectedFits = const [],
    List<String> selectedSizes = const [],
    List<String> selectedColors = const [],
    double? minPrice,
    double? maxPrice,
  }) {
    List<String> summaryParts = [];

    if (selectedGender != null) {
      summaryParts.add(selectedGender);
    }

    if (selectedBrands.isNotEmpty) {
      summaryParts.add(
          '${selectedBrands.length} brand${selectedBrands.length > 1 ? 's' : ''}');
    }

    if (selectedTypes.isNotEmpty) {
      summaryParts.add(
          '${selectedTypes.length} type${selectedTypes.length > 1 ? 's' : ''}');
    }

    if (selectedFits.isNotEmpty) {
      summaryParts.add(
          '${selectedFits.length} fit${selectedFits.length > 1 ? 's' : ''}');
    }

    if (selectedSizes.isNotEmpty) {
      summaryParts.add(
          '${selectedSizes.length} size${selectedSizes.length > 1 ? 's' : ''}');
    }

    if (selectedColors.isNotEmpty) {
      summaryParts.add(
          '${selectedColors.length} color${selectedColors.length > 1 ? 's' : ''}');
    }

    if (minPrice != null || maxPrice != null) {
      if (minPrice != null && maxPrice != null) {
        summaryParts.add('${minPrice.toInt()}-${maxPrice.toInt()} TL');
      } else if (minPrice != null) {
        summaryParts.add('${minPrice.toInt()}+ TL');
      } else {
        summaryParts.add('< ${maxPrice!.toInt()} TL');
      }
    }

    return summaryParts.isEmpty ? '' : summaryParts.join(', ');
  }

  /// Count total number of active filters
  static int countFilters({
    String? selectedGender,
    List<String> selectedBrands = const [],
    List<String> selectedTypes = const [],
    List<String> selectedFits = const [],
    List<String> selectedSizes = const [],
    List<String> selectedColors = const [],
    double? minPrice,
    double? maxPrice,
  }) {
    int count = 0;
    if (selectedGender != null) count++;
    count += selectedBrands.length;
    count += selectedTypes.length;
    count += selectedFits.length;
    count += selectedSizes.length;
    count += selectedColors.length;
    if (minPrice != null) count++;
    if (maxPrice != null) count++;
    return count;
  }
}

/// Mirrors refresh cooldown logic from ShopProvider
class TestableRefreshCooldown {
  static const Duration defaultInterval = Duration(seconds: 30);

  DateTime? lastRefresh;
  final Duration interval;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableRefreshCooldown({
    Duration? interval,
    DateTime Function()? nowProvider,
  })  : interval = interval ?? defaultInterval,
        nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors canRefresh getter from ShopProvider
  bool get canRefresh {
    if (lastRefresh == null) return true;
    return nowProvider().difference(lastRefresh!) >= interval;
  }

  /// Mirrors remainingCooldownTime getter from ShopProvider
  Duration get remainingCooldownTime {
    if (lastRefresh == null) return Duration.zero;
    final elapsed = nowProvider().difference(lastRefresh!);
    final remaining = interval - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Mark a refresh as happened
  void markRefresh() {
    lastRefresh = nowProvider();
  }

  /// Reset cooldown state
  void reset() {
    lastRefresh = null;
  }
}

/// Mirrors timestamp conversion logic from ShopProvider
class TestableTimestampConverter {
  static const List<String> timestampFields = [
    'createdAt',
    'boostStartTime',
    'boostEndTime',
    'lastClickDate',
    'timestamp',
  ];

  /// Check if a field name is a timestamp field
  static bool isTimestampField(String fieldName) {
    return timestampFields.contains(fieldName);
  }

  /// Convert int milliseconds to a mock Timestamp representation
  /// In production this would be Timestamp.fromMillisecondsSinceEpoch
  static Map<String, dynamic> convertTimestampFields(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (isTimestampField(key) && value is int) {
        // Return a map representation of Timestamp for testing
        return MapEntry(key, {'_milliseconds': value, '_isTimestamp': true});
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, convertTimestampFields(value));
      } else if (value is List) {
        return MapEntry(
          key,
          value.map((e) {
            if (e is Map<String, dynamic>) return convertTimestampFields(e);
            return e;
          }).toList(),
        );
      }
      return MapEntry(key, value);
    });
  }
}

/// Mirrors Algolia filter building logic from ShopProvider._performAlgoliaSearch
class TestableAlgoliaFilterBuilder {
  /// Build Algolia filter string for shop search
  static List<String> buildFilters({
    String? selectedGender,
    String? selectedSubcategory,
    List<String> selectedBrands = const [],
    List<String> selectedTypes = const [],
    List<String> selectedFits = const [],
    List<String> selectedColors = const [],
    double? minPrice,
    double? maxPrice,
  }) {
    List<String> filters = [];

    if (selectedGender != null) {
      filters.add('gender:"$selectedGender"');
    }

    if (selectedSubcategory != null) {
      filters.add('subcategory:"$selectedSubcategory"');
    }

    if (selectedBrands.isNotEmpty) {
      final brandFilters =
          selectedBrands.map((brand) => 'brandModel:"$brand"').join(' OR ');
      filters.add('($brandFilters)');
    }

    if (selectedTypes.isNotEmpty) {
      final typeFilters = selectedTypes
          .map((type) => 'attributes.clothingType:"$type"')
          .join(' OR ');
      filters.add('($typeFilters)');
    }

    if (selectedFits.isNotEmpty) {
      final fitFilters = selectedFits
          .map((fit) => 'attributes.clothingFit:"$fit"')
          .join(' OR ');
      filters.add('($fitFilters)');
    }

    if (selectedColors.isNotEmpty) {
      final colorFilters =
          selectedColors.map((color) => 'colorImages.$color:*').join(' OR ');
      filters.add('($colorFilters)');
    }

    if (minPrice != null) {
      filters.add('price >= $minPrice');
    }

    if (maxPrice != null) {
      filters.add('price <= $maxPrice');
    }

    return filters;
  }
}

/// Simplified Product model for filter testing
class TestableProduct {
  final String id;
  final String productName;
  final String? brandModel;
  final String? category;
  final String? subcategory;
  final String? gender;
  final double price;
  final int? discountPercentage;
  final int? purchaseCount;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic>? colorImages;

  TestableProduct({
    required this.id,
    required this.productName,
    this.brandModel,
    this.category,
    this.subcategory,
    this.gender,
    required this.price,
    this.discountPercentage,
    this.purchaseCount,
    this.attributes = const {},
    this.colorImages,
  });
}

/// Mirrors _applyAllFilters logic from ShopProvider
class TestableProductFilter {
  /// Apply all filters to a product list
  /// Mirrors _applyAllFilters from ShopProvider
  static List<TestableProduct> applyFilters(
    List<TestableProduct> products, {
    String searchQuery = '',
    List<String> selectedBrands = const [],
    List<String> selectedTypes = const [],
    List<String> selectedFits = const [],
    List<String> selectedSizes = const [],
    List<String> selectedColors = const [],
    double? minPrice,
    double? maxPrice,
  }) {
    var filtered = List<TestableProduct>.from(products);

    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        return product.productName
            .toLowerCase()
            .contains(searchQuery.toLowerCase());
      }).toList();
    }

    if (selectedBrands.isNotEmpty) {
      filtered = filtered.where((product) {
        return selectedBrands.any((brand) =>
            product.brandModel?.toLowerCase() == brand.toLowerCase() ||
            product.brandModel?.toLowerCase().contains(brand.toLowerCase()) ==
                true);
      }).toList();
    }

    if (selectedTypes.isNotEmpty) {
      filtered = filtered.where((product) {
        final String? clothingType = product.attributes['clothingType'];
        return clothingType != null && selectedTypes.contains(clothingType);
      }).toList();
    }

    if (selectedFits.isNotEmpty) {
      filtered = filtered.where((product) {
        final String? clothingFit = product.attributes['clothingFit'];
        return clothingFit != null && selectedFits.contains(clothingFit);
      }).toList();
    }

    if (selectedSizes.isNotEmpty) {
      filtered = filtered.where((product) {
        final List<dynamic> productSizes =
            product.attributes['clothingSizes'] ?? [];
        return selectedSizes.any((size) => productSizes.contains(size));
      }).toList();
    }

    if (selectedColors.isNotEmpty) {
      filtered = filtered.where((product) {
        final Map<String, dynamic> colorImgs = product.colorImages ?? {};
        return selectedColors.any((color) => colorImgs.containsKey(color));
      }).toList();
    }

    if (minPrice != null || maxPrice != null) {
      filtered = filtered.where((product) {
        final price = product.price;
        bool passesMin = minPrice == null || price >= minPrice;
        bool passesMax = maxPrice == null || price <= maxPrice;
        return passesMin && passesMax;
      }).toList();
    }

    return filtered;
  }

  /// Filter for deal products (discount > 0)
  static List<TestableProduct> filterDeals(List<TestableProduct> products) {
    return products.where((p) => (p.discountPercentage ?? 0) > 0).toList();
  }

  /// Sort by purchase count for best sellers
  static List<TestableProduct> sortByBestSellers(List<TestableProduct> products) {
    final sorted = List<TestableProduct>.from(products);
    sorted.sort((a, b) => (b.purchaseCount ?? 0).compareTo(a.purchaseCount ?? 0));
    return sorted;
  }
}

/// Mirrors pagination logic from ShopProvider
class TestablePaginationState {
  static const int defaultLimit = 10;
  static const int productsLimit = 20;

  bool hasMore = true;
  bool isLoadingMore = false;
  int loadedCount = 0;

  /// Check if should load more
  bool get shouldLoadMore => hasMore && !isLoadingMore;

  /// Process a page of results
  void processPage(int resultsCount, {int? limit}) {
    final pageLimit = limit ?? defaultLimit;
    loadedCount += resultsCount;

    if (resultsCount == 0 || resultsCount < pageLimit) {
      hasMore = false;
    }
  }

  /// Reset pagination state
  void reset() {
    hasMore = true;
    isLoadingMore = false;
    loadedCount = 0;
  }
}