// test/providers/testable_seller_panel_provider.dart
//
// TESTABLE MIRROR of SellerPanelProvider pure logic from lib/providers/seller_panel_provider.dart
//
// This file contains EXACT copies of pure logic functions from SellerPanelProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/seller_panel_provider.dart
//
// Last synced with: seller_panel_provider.dart (current version)

import 'dart:collection';

/// Mirrors _StockMemoizedData from SellerPanelProvider
class TestableStockMemoizedData {
  String? searchQuery;
  String? category;
  String? subcategory;
  bool? outOfStock;
  Object? lastDoc; // Using Object instead of DocumentSnapshot for testing
  List<Object>? products; // Using Object instead of Product for testing

  /// Mirrors isUnchanged method exactly
  bool isUnchanged(
    String? newSearchQuery,
    String? newCategory,
    String? newSubcategory,
    bool? newOutOfStock,
    Object? newLastDoc,
  ) {
    return searchQuery == newSearchQuery &&
        category == newCategory &&
        subcategory == newSubcategory &&
        outOfStock == newOutOfStock &&
        lastDoc == newLastDoc;
  }

  void reset() {
    searchQuery = null;
    category = null;
    subcategory = null;
    outOfStock = null;
    lastDoc = null;
    products = null;
  }
}

/// Mirrors Circuit Breaker pattern from SellerPanelProvider
class TestableCircuitBreaker {
  final Map<String, int> _failureCounts = {};
  final Map<String, DateTime> _lastFailureTime = {};

  final int threshold;
  final Duration resetDuration;

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableCircuitBreaker({
    this.threshold = 3,
    this.resetDuration = const Duration(minutes: 1),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Get failure count for an operation (for testing inspection)
  int getFailureCount(String operationKey) => _failureCounts[operationKey] ?? 0;

  /// Get last failure time for an operation (for testing inspection)
  DateTime? getLastFailureTime(String operationKey) =>
      _lastFailureTime[operationKey];

  /// Mirrors _isCircuitOpen from SellerPanelProvider
  bool isCircuitOpen(String operationKey) {
    final failures = _failureCounts[operationKey] ?? 0;
    if (failures < threshold) return false;

    final lastFailure = _lastFailureTime[operationKey];
    if (lastFailure == null) return false;

    // Reset circuit if enough time has passed
    if (nowProvider().difference(lastFailure) > resetDuration) {
      _failureCounts[operationKey] = 0;
      _lastFailureTime.remove(operationKey);
      return false;
    }

    return true;
  }

  /// Mirrors _recordFailure from SellerPanelProvider
  void recordFailure(String operationKey) {
    _failureCounts[operationKey] = (_failureCounts[operationKey] ?? 0) + 1;
    _lastFailureTime[operationKey] = nowProvider();
  }

  /// Mirrors _recordSuccess from SellerPanelProvider
  void recordSuccess(String operationKey) {
    _failureCounts[operationKey] = 0;
    _lastFailureTime.remove(operationKey);
  }

  void reset() {
    _failureCounts.clear();
    _lastFailureTime.clear();
  }
}

/// Mirrors retry with exponential backoff from SellerPanelProvider
class TestableRetryWithBackoff {
  final TestableCircuitBreaker circuitBreaker;

  /// Track retry attempts for testing
  final List<RetryAttempt> attempts = [];

  TestableRetryWithBackoff(this.circuitBreaker);

  /// Mirrors _retryWithBackoff from SellerPanelProvider
  /// Returns the result or throws after maxAttempts
  Future<T> execute<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    String operationKey = 'default',
    int baseDelayMs = 200,
  }) async {
    // Check circuit breaker
    if (circuitBreaker.isCircuitOpen(operationKey)) {
      throw CircuitBreakerOpenException(operationKey);
    }

    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        final result = await operation();
        circuitBreaker.recordSuccess(operationKey);
        attempts.add(RetryAttempt(
          operationKey: operationKey,
          attemptNumber: attempt + 1,
          success: true,
          delayMs: attempt > 0 ? baseDelayMs * (1 << (attempt - 1)) : 0,
        ));
        return result;
      } catch (e) {
        attempt++;
        circuitBreaker.recordFailure(operationKey);

        final delayMs = baseDelayMs * (1 << (attempt - 1));
        attempts.add(RetryAttempt(
          operationKey: operationKey,
          attemptNumber: attempt,
          success: false,
          delayMs: delayMs,
          error: e.toString(),
        ));

        if (attempt >= maxAttempts) {
          rethrow;
        }

        // In real code: await Future.delayed(Duration(milliseconds: delayMs));
        // For testing, we track but don't actually delay
      }
    }
    throw Exception('Retry failed for $operationKey');
  }

  /// Calculate expected delay for a given attempt (for testing)
  static int calculateDelay(int attempt, {int baseDelayMs = 200}) {
    if (attempt <= 1) return 0;
    return baseDelayMs * (1 << (attempt - 2)); // 200, 400, 800...
  }

  void clearAttempts() {
    attempts.clear();
  }
}

class RetryAttempt {
  final String operationKey;
  final int attemptNumber;
  final bool success;
  final int delayMs;
  final String? error;

  RetryAttempt({
    required this.operationKey,
    required this.attemptNumber,
    required this.success,
    required this.delayMs,
    this.error,
  });
}

class CircuitBreakerOpenException implements Exception {
  final String operationKey;
  CircuitBreakerOpenException(this.operationKey);

  @override
  String toString() => 'Circuit breaker open for $operationKey';
}

/// Mirrors LRU cache logic from SellerPanelProvider (_productImageCache)
class TestableLRUCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  TestableLRUCache({this.maxSize = 100});

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;
  bool get isFull => _cache.length >= maxSize;

  Iterable<K> get keys => _cache.keys;
  Iterable<V> get values => _cache.values;

  bool containsKey(K key) => _cache.containsKey(key);

  /// Mirrors _cacheProductData from SellerPanelProvider
  void put(K key, V value) {
    // Implement LRU cache with size limit
    if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// Mirrors getProductData access pattern (touch to refresh LRU order)
  V? get(K key) {
    final value = _cache[key];
    if (value != null) {
      // Touch entry to refresh LRU order
      _cache.remove(key);
      _cache[key] = value;
    }
    return value;
  }

  /// Get without touching (for inspection)
  V? peek(K key) => _cache[key];

  void remove(K key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
  }

  /// Get keys in insertion order (oldest first)
  List<K> getKeysInOrder() => _cache.keys.toList();
}

/// Mirrors product map size limiting from SellerPanelProvider
class TestableProductMap<K, V> {
  final int maxSize;
  final int evictionCount;
  final Map<K, V> _map = {};

  /// Track evictions for testing
  final List<K> evictedKeys = [];

  TestableProductMap({
    this.maxSize = 500,
    this.evictionCount = 50,
  });

  int get length => _map.length;
  bool get isEmpty => _map.isEmpty;

  bool containsKey(K key) => _map.containsKey(key);

  V? operator [](K key) => _map[key];

  /// Mirrors _updateProductMap from SellerPanelProvider
  void put(K key, V value) {
    // Implement size limit for product map
    if (_map.length >= maxSize && !_map.containsKey(key)) {
      // Remove oldest entries (simple FIFO)
      final keysToRemove = _map.keys.take(evictionCount).toList();
      for (var k in keysToRemove) {
        _map.remove(k);
        evictedKeys.add(k);
      }
    }
    _map[key] = value;
  }

  void remove(K key) {
    _map.remove(key);
  }

  void clear() {
    _map.clear();
    evictedKeys.clear();
  }
}

/// Mirrors todaySales calculation from SellerPanelProvider
class TestableSalesCalculator {
  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableSalesCalculator({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? DateTime.now;

  /// Mirrors todaySales getter logic from SellerPanelProvider
  /// Takes a list of transaction data maps
  double calculateTodaySales(List<Map<String, dynamic>> transactions) {
    final today = nowProvider();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd =
        DateTime(today.year, today.month, today.day, 23, 59, 59, 999);

    double total = 0.0;

    for (final data in transactions) {
      final timestamp = data['timestamp'];
      DateTime? date;

      if (timestamp is DateTime) {
        date = timestamp;
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }

      if (date != null) {
        if (date.isAfter(todayStart) && date.isBefore(todayEnd)) {
          // Use calculatedTotal from selectedAttributes or fallback to price * quantity
          final selectedAttributes =
              data['selectedAttributes'] as Map<String, dynamic>?;
          final calculatedTotal =
              selectedAttributes?['calculatedTotal'] as num?;

          if (calculatedTotal != null) {
            // Use the denormalized calculatedTotal which includes all discounts
            total += calculatedTotal.toDouble();
          } else {
            // Fallback to price * quantity if calculatedTotal is not available
            final itemPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
            final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
            total += itemPrice * quantity;
          }
        }
      }
    }

    return total;
  }

  /// Filter transactions by date range
  List<Map<String, dynamic>> filterByDateRange(
    List<Map<String, dynamic>> transactions,
    DateTime start,
    DateTime end,
  ) {
    return transactions.where((data) {
      final timestamp = data['timestamp'];
      DateTime? date;

      if (timestamp is DateTime) {
        date = timestamp;
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }

      if (date == null) return false;
      return date.isAfter(start) && date.isBefore(end);
    }).toList();
  }
}

/// Mirrors product normalization from SellerPanelProvider
class TestableProductNormalizer {
  /// Mirrors _normalizeProduct from SellerPanelProvider
  static Map<String, dynamic> normalize(Map<String, dynamic> product) {
    return {
      ...product,
      'category': (product['category'] as String?)?.trim(),
      'subcategory': (product['subcategory'] as String?)?.trim(),
      'subsubcategory': (product['subsubcategory'] as String?)?.trim(),
    };
  }
}

/// Mirrors transaction search/filter logic from SellerPanelProvider
class TestableTransactionFilter {
  /// Mirrors _updateFilteredTransactions search logic
  static List<Map<String, dynamic>> filterTransactions(
    List<Map<String, dynamic>> transactions,
    String searchQuery, {
    Map<String, Map<String, dynamic>>? productMap,
  }) {
    if (searchQuery.isEmpty) {
      return transactions;
    }

    final q = searchQuery.toLowerCase();

    return transactions.where((data) {
      // Check product name from product map or denormalized data
      final productId = data['productId'] as String?;
      String productName = '';

      if (productId != null && productMap?.containsKey(productId) == true) {
        productName =
            (productMap![productId]!['productName'] as String?)?.toLowerCase() ??
                '';
      } else {
        productName =
            (data['productName'] as String?)?.toLowerCase() ?? '';
      }

      final customerName =
          (data['customerName'] as String?)?.toLowerCase() ?? '';
      final orderId = (data['orderId'] as String?)?.toLowerCase() ?? '';

      return productName.contains(q) ||
          customerName.contains(q) ||
          orderId.contains(q);
    }).toList();
  }
}

/// Mirrors stock product search logic from SellerPanelProvider
class TestableStockProductFilter {
  /// Mirrors the search filtering in fetchStockProducts
  static List<Map<String, dynamic>> filterProducts(
    List<Map<String, dynamic>> products,
    String searchQuery,
  ) {
    if (searchQuery.isEmpty) {
      return products;
    }

    final q = searchQuery.toLowerCase();

    return products.where((p) {
      final productName =
          (p['productName'] as String?)?.toLowerCase() ?? '';
      final brandModel =
          (p['brandModel'] as String?)?.toLowerCase() ?? '';
      final category = (p['category'] as String?)?.toLowerCase() ?? '';
      final subcategory =
          (p['subcategory'] as String?)?.toLowerCase() ?? '';
      final subsubcategory =
          (p['subsubcategory'] as String?)?.toLowerCase() ?? '';

      return productName.contains(q) ||
          brandModel.contains(q) ||
          category.contains(q) ||
          subcategory.contains(q) ||
          subsubcategory.contains(q);
    }).toList();
  }
}

/// Mirrors hasOutOfStock getter from SellerPanelProvider
class TestableOutOfStockChecker {
  /// Mirrors hasOutOfStock logic
  static bool hasOutOfStock(List<Map<String, dynamic>> products) {
    return products.any((p) {
      final quantity = (p['quantity'] as num?)?.toInt() ?? 0;
      if (quantity == 0) return true;

      final colorQuantities = p['colorQuantities'] as Map<String, dynamic>?;
      if (colorQuantities != null) {
        return colorQuantities.values.any((q) => (q as num?)?.toInt() == 0);
      }

      return false;
    });
  }
}

/// Mirrors metrics cache logic from SellerPanelProvider
class TestableMetricsCache {
  Map<String, int>? _cachedMetrics;
  DateTime? _lastFetched;
  final Duration cacheDuration;

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableMetricsCache({
    this.cacheDuration = const Duration(minutes: 5),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  bool get hasCachedMetrics => _cachedMetrics != null;
  Map<String, int>? get cachedMetrics => _cachedMetrics;
  DateTime? get lastFetched => _lastFetched;

  /// Check if cache is valid
  bool isCacheValid() {
    if (_cachedMetrics == null || _lastFetched == null) return false;
    final age = nowProvider().difference(_lastFetched!);
    return age < cacheDuration;
  }

  /// Get cached metrics if valid, otherwise return null
  Map<String, int>? getIfValid() {
    if (isCacheValid()) {
      return _cachedMetrics;
    }
    return null;
  }

  /// Update cache
  void update(Map<String, int> metrics) {
    _cachedMetrics = metrics;
    _lastFetched = nowProvider();
  }

  /// Force invalidate cache
  void invalidate() {
    _lastFetched = null;
  }

  void clear() {
    _cachedMetrics = null;
    _lastFetched = null;
  }
}

/// Mirrors search debounce logic from SellerPanelProvider
class TestableSearchDebouncer {
  final Duration debounceDuration;
  String _lastQuery = '';
  DateTime? _lastQueryTime;
  int _queryCount = 0;

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableSearchDebouncer({
    this.debounceDuration = const Duration(milliseconds: 300),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  String get lastQuery => _lastQuery;
  int get queryCount => _queryCount;

  /// Check if a new query should trigger a search
  /// Returns true if query is different and debounce period has passed
  bool shouldTriggerSearch(String query) {
    final now = nowProvider();

    // Same query, don't trigger
    if (query == _lastQuery) return false;

    // Check debounce
    if (_lastQueryTime != null) {
      final elapsed = now.difference(_lastQueryTime!);
      if (elapsed < debounceDuration) {
        return false;
      }
    }

    return true;
  }

  /// Record that a search was triggered
  void recordSearch(String query) {
    _lastQuery = query;
    _lastQueryTime = nowProvider();
    _queryCount++;
  }

  void reset() {
    _lastQuery = '';
    _lastQueryTime = null;
    _queryCount = 0;
  }
}

/// Mirrors race condition guard (_activeQueryId) from SellerPanelProvider
class TestableRaceGuard {
  int _activeQueryId = 0;

  int get currentId => _activeQueryId;

  /// Start a new query and get its ID
  int startQuery() {
    return ++_activeQueryId;
  }

  /// Check if a query ID is still the active one
  bool isActive(int queryId) {
    return queryId == _activeQueryId;
  }

  /// Invalidate all current queries
  void invalidateAll() {
    _activeQueryId++;
  }

  void reset() {
    _activeQueryId = 0;
  }
}