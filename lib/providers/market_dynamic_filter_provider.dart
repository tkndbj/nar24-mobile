// Enhanced DynamicFilterProvider with memory management and race protection

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/dynamic_filter.dart';
import '../models/product_summary.dart';

class DynamicFilterProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DynamicFilter> _dynamicFilters = [];
  List<DynamicFilter> get dynamicFilters => _dynamicFilters;

  List<DynamicFilter> get activeFilters =>
      _dynamicFilters.where((f) => f.isActive).toList();

  StreamSubscription<QuerySnapshot>? _filtersSubscription;
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String? _error;
  String? get error => _error;

  // ========== PAGINATION STATE ==========
  static const int _pageSize = 20;
  
  // ✅ NEW: Maximum cache limits
  static const int _maxCachedFilters = 10;
  static const int _maxPagesPerFilter = 5; // Max 100 products per filter
  static const int _maxCachedProducts = 500; // Total products across all filters

  // Cache for paginated filter products
  final Map<String, Map<int, List<ProductSummary>>> _paginatedCache = {};
  final Map<String, int> _currentPages = {};
  final Map<String, bool> _hasMorePages = {};
  final Map<String, bool> _isLoadingMoreMap = {};
  final Map<String, Map<int, DocumentSnapshot>> _pageCursors = {};
  final Map<String, List<ProductSummary>> _filterProductsCache = {};
  final Map<String, DateTime> _filterCacheTimestamps = {};
  
  // ✅ NEW: Reduced cache timeout for mobile
  final Duration _cacheTimeout = const Duration(minutes: 2);

  // ✅ NEW: Race condition protection
  final Map<String, Completer<List<ProductSummary>>> _ongoingFetches = {};
  
  // ✅ NEW: LRU tracking for cache eviction
  final Map<String, DateTime> _filterAccessTimes = {};

  DynamicFilterProvider() {
    _initializeFiltersListener();
  }

  // ========== MEMORY MANAGEMENT ==========

  /// ✅ NEW: Enforce cache size limits
  void _enforceCacheLimits() {
    // 1. Limit number of cached filters
    if (_filterProductsCache.length > _maxCachedFilters) {
      _evictLeastRecentlyUsedFilters();
    }

    // 2. Limit total cached products
    int totalProducts = _filterProductsCache.values
        .fold(0, (sum, products) => sum + products.length);
    
    if (totalProducts > _maxCachedProducts) {
      _evictExcessProducts();
    }

    // 3. Limit pages per filter
    for (var filterId in _paginatedCache.keys.toList()) {
      final pages = _paginatedCache[filterId]!;
      if (pages.length > _maxPagesPerFilter) {
        // Keep only the first _maxPagesPerFilter pages
        final keysToRemove = pages.keys
            .where((page) => page >= _maxPagesPerFilter)
            .toList();
        
        for (var key in keysToRemove) {
          pages.remove(key);
          _pageCursors[filterId]?.remove(key);
        }
      }
    }
  }

  /// ✅ NEW: Evict least recently used filters
  void _evictLeastRecentlyUsedFilters() {
    if (_filterAccessTimes.isEmpty) return;

    // Sort filters by last access time
    final sortedFilters = _filterAccessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Remove oldest filters until we're under the limit
    while (_filterProductsCache.length > _maxCachedFilters && 
           sortedFilters.isNotEmpty) {
      final oldestFilter = sortedFilters.removeAt(0);
      clearFilterCache(oldestFilter.key);
      debugPrint('🗑️ Evicted filter cache: ${oldestFilter.key}');
    }
  }

  /// ✅ NEW: Evict excess products
  void _evictExcessProducts() {
    // Remove products from least recently used filters
    final sortedFilters = _filterAccessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    int totalProducts = _filterProductsCache.values
        .fold(0, (sum, products) => sum + products.length);

    for (var entry in sortedFilters) {
      if (totalProducts <= _maxCachedProducts) break;
      
      final filterId = entry.key;
      final products = _filterProductsCache[filterId];
      
      if (products != null && products.isNotEmpty) {
        // Remove half the products from this filter
        final halfSize = products.length ~/ 2;
        _filterProductsCache[filterId] = products.sublist(0, halfSize);
        totalProducts -= halfSize;
        
        // Also clean up related pagination data
        _paginatedCache[filterId]?.removeWhere((page, _) => page > 0);
        _currentPages[filterId] = 0;
        
        debugPrint('🗑️ Evicted ${halfSize} products from filter: $filterId');
      }
    }
  }

  /// ✅ NEW: Update filter access time (for LRU)
  void _updateFilterAccessTime(String filterId) {
    _filterAccessTimes[filterId] = DateTime.now();
  }

  // ========== RACE CONDITION PROTECTION ==========

  /// ✅ ENHANCED: Fetch with mutex protection
  Future<List<ProductSummary>> _fetchFilterProducts(
    String filterId, {
    required int page,
    bool useCache = true,
  }) async {
    // Check if fetch is already in progress
    if (_ongoingFetches.containsKey(filterId)) {
      debugPrint('⏳ Waiting for ongoing fetch: $filterId');
      return await _ongoingFetches[filterId]!.future;
    }

    // Create completer for this fetch
    final completer = Completer<List<ProductSummary>>();
    _ongoingFetches[filterId] = completer;

    try {
      final result = await _fetchFilterProductsInternal(
        filterId,
        page: page,
        useCache: useCache,
      );
      
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _ongoingFetches.remove(filterId);
    }
  }

  /// Internal fetch logic (protected by mutex)
  Future<List<ProductSummary>> _fetchFilterProductsInternal(
    String filterId, {
    required int page,
    bool useCache = true,
  }) async {
    final filter = _dynamicFilters.firstWhere(
      (f) => f.id == filterId,
      orElse: () => throw Exception('Filter not found: $filterId'),
    );

    // Initialize pagination state
    _paginatedCache.putIfAbsent(filterId, () => {});
    _pageCursors.putIfAbsent(filterId, () => {});
    _hasMorePages.putIfAbsent(filterId, () => true);
    _currentPages.putIfAbsent(filterId, () => 0);
    _filterProductsCache.putIfAbsent(filterId, () => []);

    // Update access time for LRU
    _updateFilterAccessTime(filterId);

    // Check cache
    if (useCache && _paginatedCache[filterId]!.containsKey(page)) {
      final cachedTime = _filterCacheTimestamps[filterId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheTimeout) {
        debugPrint('📦 Cache hit for $filterId page $page');
        return _paginatedCache[filterId]![page]!;
      }
    }

    // Reset on page 0
    if (page == 0 && !useCache) {
      _paginatedCache[filterId]!.clear();
      _pageCursors[filterId]!.clear();
      _filterProductsCache[filterId]!.clear();
      _hasMorePages[filterId] = true;
      _currentPages[filterId] = 0;
    }

    try {
      Query query = _firestore.collection(filter.collection ?? 'shop_products');
      query = _applyFilterConditions(query, filter);

      if (filter.sortBy != null) {
        query = query.orderBy(
          filter.sortBy!,
          descending: filter.sortOrder == 'desc',
        );
      }

      // Apply pagination cursor
      if (page > 0 && _pageCursors[filterId]!.containsKey(page - 1)) {
        final prevCursor = _pageCursors[filterId]![page - 1];
        query = query.startAfterDocument(prevCursor!);
      }

      query = query.limit(_pageSize);

      final snapshot = await query.get();
      final docs = snapshot.docs;

      // Store cursor
      if (docs.isNotEmpty) {
        _pageCursors[filterId]![page] = docs.last;
      }

      final products = docs.map((doc) => ProductSummary.fromDocument(doc)).toList();

      // Update state
      _hasMorePages[filterId] = products.length >= _pageSize;
      _paginatedCache[filterId]![page] = products;

      if (page == 0) {
        _filterProductsCache[filterId] = List.from(products);
      } else {
        _filterProductsCache[filterId]!.addAll(products);
      }

      _filterCacheTimestamps[filterId] = DateTime.now();

      // ✅ NEW: Enforce cache limits after fetch
      _enforceCacheLimits();

      debugPrint('✅ Fetched page $page for $filterId: ${products.length} products');

      return products;
    } catch (e) {
      debugPrint('❌ Error fetching $filterId page $page: $e');
      _hasMorePages[filterId] = false;
      return _paginatedCache[filterId]?[page] ?? [];
    }
  }

  // ========== PUBLIC API ==========

  int getCurrentPage(String filterId) => _currentPages[filterId] ?? 0;
  bool hasMorePages(String filterId) => _hasMorePages[filterId] ?? true;
  bool isLoadingMore(String filterId) => _isLoadingMoreMap[filterId] ?? false;
  int getLoadedProductsCount(String filterId) {
    return _filterProductsCache[filterId]?.length ?? 0;
  }

  /// ✅ ENHANCED: Load more with better protection
  Future<void> loadMoreProducts(String filterId) async {
    // Prevent concurrent loads
    if (!hasMorePages(filterId) || isLoadingMore(filterId)) {
      return;
    }

    // Check if already at max pages
    final currentPage = _currentPages[filterId] ?? 0;
    if (currentPage >= _maxPagesPerFilter - 1) {
      debugPrint('⚠️ Reached max pages for filter: $filterId');
      _hasMorePages[filterId] = false;
      return;
    }

    _isLoadingMoreMap[filterId] = true;
    notifyListeners();

    try {
      final nextPage = currentPage + 1;
      await _fetchFilterProducts(filterId, page: nextPage, useCache: false);
      _currentPages[filterId] = nextPage;
    } finally {
      _isLoadingMoreMap[filterId] = false;
      notifyListeners();
    }
  }

  Future<List<ProductSummary>> getFilterProducts(String filterId) async {
    return await _fetchFilterProducts(filterId, page: 0);
  }

  List<ProductSummary> getAllLoadedProducts(String filterId) {
    _updateFilterAccessTime(filterId);
    return _filterProductsCache[filterId] ?? [];
  }

  Future<void> refreshFilter(String filterId) async {
    _currentPages[filterId] = 0;
    await _fetchFilterProducts(filterId, page: 0, useCache: false);
  }

  // ========== INITIALIZATION ==========

  void _initializeFiltersListener() {
    _isLoading = true;
    _isInitialized = false;
    notifyListeners();

    try {
      _filtersSubscription = _firestore
          .collection('market_screen_filters')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .snapshots()
          .listen(
        (snapshot) {
          try {
            final newFilters = snapshot.docs
                .map((doc) => DynamicFilter.fromFirestore(doc))
                .where((filter) => filter != null)
                .cast<DynamicFilter>()
                .toList();

            if (!_filtersEqual(_dynamicFilters, newFilters)) {
              _dynamicFilters = newFilters;
              clearAllCache();
              _error = null;
              _isLoading = false;
              _isInitialized = true;

              debugPrint('✅ Dynamic filters loaded: ${_dynamicFilters.length}');
              notifyListeners();

              // ✅ MODIFIED: Delayed prefetch (less aggressive)
              Future.delayed(const Duration(seconds: 1), () {
                _prefetchFilterData();
              });
            } else if (_isLoading) {
              _isLoading = false;
              _isInitialized = true;
              notifyListeners();
            }
          } catch (e) {
            _error = 'Failed to parse filters: $e';
            _isLoading = false;
            _isInitialized = true;
            notifyListeners();
          }
        },
        onError: (error) {
          _error = 'Failed to load filters: $error';
          _isLoading = false;
          _isInitialized = true;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = 'Failed to initialize filters: $e';
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  bool _filtersEqual(List<DynamicFilter> list1, List<DynamicFilter> list2) {
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

  /// ✅ MODIFIED: Prefetch only 2 filters (was 3)
  void _prefetchFilterData() {
    if (!_isInitialized || _isLoading) return;
    final filtersToPreload = _dynamicFilters.take(2); // Reduced from 3
    for (final filter in filtersToPreload) {
      _fetchFilterProducts(filter.id, page: 0, useCache: false);
    }
  }

  Future<void> waitForInitialization() async {
    if (_isInitialized) return;

    final completer = Completer<void>();
    late VoidCallback listener;

    listener = () {
      if (_isInitialized) {
        removeListener(listener);
        completer.complete();
      }
    };

    addListener(listener);

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        removeListener(listener);
        debugPrint('⚠️ Filter initialization timeout');
      },
    );
  }

  Query _applyFilterConditions(Query query, DynamicFilter filter) {
    switch (filter.type) {
      case FilterType.attribute:
        if (filter.attribute != null &&
            filter.operator != null &&
            filter.attributeValue != null) {
          switch (filter.operator) {
            case '==':
              query = query.where(filter.attribute!,
                  isEqualTo: filter.attributeValue);
              break;
            case '!=':
              query = query.where(filter.attribute!,
                  isNotEqualTo: filter.attributeValue);
              break;
            case '>':
              query = query.where(filter.attribute!,
                  isGreaterThan: filter.attributeValue);
              break;
            case '>=':
              query = query.where(filter.attribute!,
                  isGreaterThanOrEqualTo: filter.attributeValue);
              break;
            case '<':
              query = query.where(filter.attribute!,
                  isLessThan: filter.attributeValue);
              break;
            case '<=':
              query = query.where(filter.attribute!,
                  isLessThanOrEqualTo: filter.attributeValue);
              break;
            case 'array-contains':
              query = query.where(filter.attribute!,
                  arrayContains: filter.attributeValue);
              break;
            case 'array-contains-any':
              query = query.where(filter.attribute!,
                  arrayContainsAny: filter.attributeValue);
              break;
            case 'in':
              query = query.where(filter.attribute!,
                  whereIn: filter.attributeValue);
              break;
            case 'not-in':
              query = query.where(filter.attribute!,
                  whereNotIn: filter.attributeValue);
              break;
          }
        }
        break;

      case FilterType.query:
        if (filter.queryConditions != null) {
          for (final condition in filter.queryConditions!) {
            switch (condition.operator) {
              case '==':
                query = query.where(condition.field, isEqualTo: condition.value);
                break;
              case '!=':
                query = query.where(condition.field, isNotEqualTo: condition.value);
                break;
              case '>':
                query = query.where(condition.field, isGreaterThan: condition.value);
                break;
              case '>=':
                query = query.where(condition.field, isGreaterThanOrEqualTo: condition.value);
                break;
              case '<':
                query = query.where(condition.field, isLessThan: condition.value);
                break;
              case '<=':
                query = query.where(condition.field, isLessThanOrEqualTo: condition.value);
                break;
              case 'array-contains':
                query = query.where(condition.field, arrayContains: condition.value);
                break;
              case 'array-contains-any':
                query = query.where(condition.field, arrayContainsAny: condition.value);
                break;
              case 'in':
                query = query.where(condition.field, whereIn: condition.value);
                break;
              case 'not-in':
                query = query.where(condition.field, whereNotIn: condition.value);
                break;
            }
          }
        }
        break;

      case FilterType.collection:
        break;
    }
    return query;
  }

  Future<int> getFilterProductCount(String filterId) async {
    final filter = _dynamicFilters.firstWhere(
      (f) => f.id == filterId,
      orElse: () => throw Exception('Filter not found: $filterId'),
    );

    try {
      Query query = _firestore.collection(filter.collection ?? 'shop_products');
      query = _applyFilterConditions(query, filter);
      final snapshot = await query.count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('❌ Error counting products for $filterId: $e');
      return 0;
    }
  }

  bool hasFilterCache(String filterId) {
    return _filterProductsCache.containsKey(filterId) &&
        _filterCacheTimestamps.containsKey(filterId) &&
        DateTime.now().difference(_filterCacheTimestamps[filterId]!) <
            _cacheTimeout;
  }

  List<ProductSummary>? getCachedFilterProducts(String filterId) {
    if (hasFilterCache(filterId)) {
      _updateFilterAccessTime(filterId);
      return _filterProductsCache[filterId];
    }
    return null;
  }

  void clearFilterCache(String filterId) {
    _paginatedCache.remove(filterId);
    _pageCursors.remove(filterId);
    _filterProductsCache.remove(filterId);
    _filterCacheTimestamps.remove(filterId);
    _currentPages.remove(filterId);
    _hasMorePages.remove(filterId);
    _isLoadingMoreMap.remove(filterId);
    _filterAccessTimes.remove(filterId);
    _ongoingFetches.remove(filterId);
  }

  void clearAllCache() {
    _paginatedCache.clear();
    _pageCursors.clear();
    _filterProductsCache.clear();
    _filterCacheTimestamps.clear();
    _currentPages.clear();
    _hasMorePages.clear();
    _isLoadingMoreMap.clear();
    _filterAccessTimes.clear();
    _ongoingFetches.clear();
  }

  String getFilterDisplayName(DynamicFilter filter, String languageCode) {
    return filter.displayName[languageCode] ??
        filter.displayName['tr'] ??
        filter.displayName['en'] ??
        filter.name;
  }

  Future<void> refreshFilters() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('market_screen_filters')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();

      _dynamicFilters = snapshot.docs
          .map((doc) => DynamicFilter.fromFirestore(doc))
          .where((filter) => filter != null)
          .cast<DynamicFilter>()
          .toList();

      _error = null;
      clearAllCache();

      debugPrint('✅ Filters refreshed: ${_dynamicFilters.length}');
    } catch (e) {
      _error = 'Failed to refresh filters: $e';
      debugPrint('❌ Error refreshing filters: $e');
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _filtersSubscription?.cancel();
    _ongoingFetches.clear();
    clearAllCache();
    super.dispose();
  }
}