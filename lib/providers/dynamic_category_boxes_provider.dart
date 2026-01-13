// File: dynamic_category_boxes_provider.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/debouncer.dart';

/// A provider tailored to "category‐box" taps. It can filter by:
///   • category only
///   • category + subcategory
///   • category + subsubcategory
///
/// Otherwise it behaves just like ShopMarketProvider: pagination, caching,
/// dynamic brand/colors, quick‐filters, sorting, etc.
class CategoryBoxesProvider with ChangeNotifier {
  // ──────────────────────────────────────────────────────────────────────────
  // PAGED CACHE STATE
  // ──────────────────────────────────────────────────────────────────────────

  /// Holds each fetched Firestore page: pageIndex → List<Product>.
  final Map<int, List<Product>> _pageCache = {};

  /// For each pageIndex, stores the last DocumentSnapshot used as a cursor.
  final Map<int, DocumentSnapshot> _pageCursors = {};

  /// A flattened, concatenated list of all items currently in memory (unfiltered).
  final List<Product> _allLoaded = [];
  List<Product> get rawProducts => List.unmodifiable(_allLoaded);

  Map<int, List<Product>> get pageCache => _pageCache;
  Future<void> fetchPage(int page) => _fetchPage(page: page);

  // ──────────────────────────────────────────────────────────────────────────
  // FILTERED STATE FOR UI
  // ──────────────────────────────────────────────────────────────────────────

  /// The list your UI binds to after applying quick or dynamic filters.
  final List<Product> _products = [];
  List<Product> get products => List.unmodifiable(_products);

  // ──────────────────────────────────────────────────────────────────────────
  // BOOSTED PRODUCTS (Default tab only)
  // ──────────────────────────────────────────────────────────────────────────

  final List<Product> _boostedProducts = [];
  List<Product> get boostedProducts => List.unmodifiable(_boostedProducts);

  // ──────────────────────────────────────────────────────────────────────────
  // METADATA & FLAGS
  // ──────────────────────────────────────────────────────────────────────────

  bool get hasMore => _hasMore;
  bool _hasMore = true;

  bool get isLoadingMore => _isLoadingMore;
  bool _isLoadingMore = false;

  String get sortOption => _sortOption;
  String _sortOption = 'date';

  String? get quickFilter => _quickFilter;
  String? _quickFilter;

  // Dynamic filters - Updated to support multiple brands
  List<String> get dynamicBrands => List.unmodifiable(_dynamicBrands);
  List<String> get dynamicColors => List.unmodifiable(_dynamicColors);
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;

  List<String> _dynamicBrands = []; // Changed from single to multiple
  List<String> _dynamicColors = [];
  double? _minPrice;
  double? _maxPrice;

  // ──────────────────────────────────────────────────────────────────────────
  // PAGINATION STATE
  // ──────────────────────────────────────────────────────────────────────────

  static const int _limit = 20; // Firestore page size
  int _currentPage = 0; // Last fetched page

  // 5-minute TTL cache for each (category|subcategory|subsubcategory|page|sort)
  final Map<String, List<Product>> _cache = {};
  final Map<String, DateTime> _cacheTs = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  int _filterSeq = 0; // to guard against stale fetchPage calls

  String? _category;
  String? _subcategory;
  String? _subSubcategory;
  Future<void> fetchBoosted() => _fetchBoosted();

  // Firestore instance & debouncer
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Debouncer _notifyDebouncer =
      Debouncer(delay: const Duration(milliseconds: 200));

  // ──────────────────────────────────────────────────────────────────────────
  // PRUNING CONFIGURATION (page‐based)
  // ──────────────────────────────────────────────────────────────────────────

  /// Keep at most 5 pages (5 × 20 = 100 items) in memory
  static const int _maxCachedPages = 5;

  /// When over limit, drop this many oldest pages at a time
  static const int _prunePageBatchSize = 1;

  // ──────────────────────────────────────────────────────────────────────────
  // CONSTRUCTOR
  // ──────────────────────────────────────────────────────────────────────────

  CategoryBoxesProvider() {
    // No-op until category/subcategory/subsubcategory is set.
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Set a new category → clear state + fetch page 0
  Future<void> setCategory(String category) async {
    if (_category == category) return;
    _category = category;
    _subcategory = null;
    _subSubcategory = null;
    await _resetAndFetch();
  }

  /// Narrow to a subcategory → clear state + fetch page 0
  Future<void> setSubcategory(String subcat) async {
    if (_subcategory == subcat) return;
    _subcategory = subcat;
    _subSubcategory = null;
    await _resetAndFetch();
  }

  /// Narrow to a subsubcategory → clear state + fetch page 0
  Future<void> setSubSubcategory(String subsub) async {
    if (_subSubcategory == subsub) return;
    _subSubcategory = subsub;
    _subcategory = null;
    await _resetAndFetch();
  }

  /// Change sort order → clear state + fetch page 0
  Future<void> setSortOption(String option) async {
    if (_sortOption == option) return;
    _sortOption = option;
    await _resetAndFetch();
  }

  /// Apply dynamic filters with additive behavior
  Future<void> setDynamicFilter({
    List<String>? brands,
    List<String>? colors,
    double? minPrice,
    double? maxPrice,
    bool additive = true,
  }) async {
    bool hasChanged = false;

    if (additive) {
      if (brands != null) {
        for (final brand in brands) {
          if (!_dynamicBrands.contains(brand)) {
            _dynamicBrands.add(brand);
            hasChanged = true;
          }
        }
      }
      if (colors != null) {
        for (final color in colors) {
          if (!_dynamicColors.contains(color)) {
            _dynamicColors.add(color);
            hasChanged = true;
          }
        }
      }
    } else {
      if (brands != null && !_listEquals(_dynamicBrands, brands)) {
        _dynamicBrands = List.from(brands);
        hasChanged = true;
      }
      if (colors != null && !_listEquals(_dynamicColors, colors)) {
        _dynamicColors = List.from(colors);
        hasChanged = true;
      }
    }

    if (minPrice != _minPrice) {
      _minPrice = minPrice;
      hasChanged = true;
    }
    if (maxPrice != _maxPrice) {
      _maxPrice = maxPrice;
      hasChanged = true;
    }

    if (hasChanged) {
      await _resetAndFetch();
    }
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Remove specific dynamic filters
  Future<void> removeDynamicFilter({
    String? brand,
    String? color,
    bool clearPrice = false,
  }) async {
    bool changed = false;

    if (brand != null && _dynamicBrands.contains(brand)) {
      _dynamicBrands.remove(brand);
      changed = true;
    }

    if (color != null && _dynamicColors.contains(color)) {
      _dynamicColors.remove(color);
      changed = true;
    }

    if (clearPrice && (_minPrice != null || _maxPrice != null)) {
      _minPrice = null;
      _maxPrice = null;
      changed = true;
    }

    if (changed) {
      await _resetAndFetch();
    }
  }

  /// Clear all dynamic filters
  Future<void> clearDynamicFilters() async {
    _dynamicBrands.clear();
    _dynamicColors.clear();
    _minPrice = null;
    _maxPrice = null;
    await _resetAndFetch();
  }

  /// Load the next page if `hasMore == true`
  Future<void> fetchMoreProducts() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _currentPage++;

    await _fetchPage(page: _currentPage);
    _isLoadingMore = false;
    _notifyDebouncer.run(notifyListeners);
  }

  /// Force a full refresh (clear all cached pages + fetch page 0)
  /// IMPORTANT: This preserves dynamic filters during refresh
  Future<void> refresh() async {
    // Store current filters before reset
    final preservedBrands = List<String>.from(_dynamicBrands);
    final preservedColors = List<String>.from(_dynamicColors);
    final preservedMinPrice = _minPrice;
    final preservedMaxPrice = _maxPrice;
    final preservedQuickFilter = _quickFilter;

    await _resetAndFetch();

    // Restore filters after reset
    _dynamicBrands = preservedBrands;
    _dynamicColors = preservedColors;
    _minPrice = preservedMinPrice;
    _maxPrice = preservedMaxPrice;
    _quickFilter = preservedQuickFilter;

    // Re-apply filters to new data
    await _resetAndFetch();
  }

  /// Check if any dynamic filters are active
  bool get hasDynamicFilters =>
      _dynamicBrands.isNotEmpty ||
      _dynamicColors.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null;

  /// Get count of active filters
  int get activeFiltersCount {
    int count = 0;
    count += _dynamicBrands.length;
    count += _dynamicColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    return count;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CORE LOGIC
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _resetAndFetch() async {
    _pageCache.clear();
    _pageCursors.clear();
    _allLoaded.clear();
    _products.clear();
    _boostedProducts.clear();
    _hasMore = true;
    _currentPage = 0;
    _filterSeq++;
    await _fetchPage(page: 0, forceRefresh: true);
    await _fetchBoosted();
  }

  String _buildCacheKey(int page) {
    final filterParts = <String>[];

    if (_dynamicBrands.isNotEmpty) {
      filterParts.add('brands:${_dynamicBrands.join(',')}');
    }
    if (_dynamicColors.isNotEmpty) {
      filterParts.add('colors:${_dynamicColors.join(',')}');
    }
    if (_minPrice != null) {
      filterParts.add('minPrice:$_minPrice');
    }
    if (_maxPrice != null) {
      filterParts.add('maxPrice:$_maxPrice');
    }
    if (_quickFilter != null) {
      filterParts.add('quick:$_quickFilter');
    }

    final filterString =
        filterParts.isNotEmpty ? '|${filterParts.join('|')}' : '';
    return '$_category|$_subcategory|$_subSubcategory|$page|$_sortOption$filterString';
  }

  Future<void> _fetchPage({
    required int page,
    bool forceRefresh = false,
  }) async {
    final seq = ++_filterSeq;
    final cacheKey = _buildCacheKey(page);

    final now = DateTime.now();
    final cached = _cache[cacheKey];
    final cachedTs = _cacheTs[cacheKey];
    final useCache = !forceRefresh &&
        cached != null &&
        cachedTs != null &&
        now.difference(cachedTs) < _cacheTtl;

    if (page == 0 && !useCache) {
      _pageCache.clear();
      _pageCursors.clear();
      _allLoaded.clear();
      _products.clear();
      _boostedProducts.clear();
      _hasMore = true;
      notifyListeners();
    }

    // Build Firestore query
    Query q = _firestore.collection('shop_products');
    if (_category != null) {
      q = q.where('category', isEqualTo: _category);
    }
    if (_subcategory != null) {
      q = q.where('subcategory', isEqualTo: _subcategory);
    }
    if (_subSubcategory != null) {
      q = q.where('subsubcategory', isEqualTo: _subSubcategory);
    }

// SERVER-SIDE Dynamic filters
    if (_dynamicBrands.isNotEmpty) {
      if (_dynamicBrands.length <= 10) {
        q = q.where('brandModel', whereIn: _dynamicBrands);
      }
    }
    if (_dynamicColors.isNotEmpty) {
      if (_dynamicColors.length <= 10) {
        q = q.where('availableColors', arrayContainsAny: _dynamicColors);
      }
    }
    if (_minPrice != null) {
      q = q.where('price', isGreaterThanOrEqualTo: _minPrice);
    }
    if (_maxPrice != null) {
      q = q.where('price', isLessThanOrEqualTo: _maxPrice);
    }

// SERVER-SIDE Quick filters with proper ordering
    if (_quickFilter == 'bestSellers') {
      q = q.orderBy('purchaseCount', descending: true);
    } else {
      // Apply quick filter conditions first
      switch (_quickFilter) {
        case 'deals':
          q = q.where('discountPercentage', isGreaterThan: 0);
          break;
        case 'boosted':
          q = q.where('isBoosted', isEqualTo: true);
          break;
        case 'trending':
          q = q.where('dailyClickCount', isGreaterThanOrEqualTo: 10);
          break;
        case 'fiveStar':
          q = q.where('averageRating', isEqualTo: 5);
          break;
      }

      // Then apply sorting
      switch (_sortOption) {
        case 'alphabetical':
          q = q.orderBy('productName');
          break;
        case 'price_asc':
          q = q.orderBy('price', descending: false);
          break;
        case 'price_desc':
          q = q.orderBy('price', descending: true);
          break;
        case 'date':
        default:
          q = q
              .orderBy('isBoosted', descending: true)
              .orderBy('rankingScore', descending: true);
          break;
      }
    }
    // If page > 0, startAfter the lastDoc of (page – 1)
    if (page > 0 && _pageCursors.containsKey(page - 1)) {
      final prevDoc = _pageCursors[page - 1];
      if (prevDoc != null) {
        q = q.startAfterDocument(prevDoc);
      }
    }

    // Limit to `_limit` items per page
    q = q.limit(_limit);

    try {
      // Execute Firestore query (server+cache)
      final snap = await q.get(GetOptions(source: Source.serverAndCache));
      if (seq != _filterSeq) return; // stale guard

      final docs = snap.docs;
      if (docs.isNotEmpty) {
        _pageCursors[page] = docs.last;
      } else {
        _pageCursors.remove(page);
      }

      final fetched = docs.map((d) => Product.fromDocument(d)).toList();
      _hasMore = fetched.length >= _limit;

      // Cache page 0 in our 5-minute TTL map
      if (page == 0) {
        _cache[cacheKey] = fetched;
        _cacheTs[cacheKey] = now;
      }

      // Store this page in _pageCache
      _pageCache[page] = fetched;

      // Rebuild the flattened in-memory list
      _rebuildAllLoaded();

      // Prune old pages if over limit
      _pruneIfNeeded();

      // Update the UI list (filters will be applied later by filterProducts())
      _products
        ..clear()
        ..addAll(_allLoaded);

      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      // Handle error gracefully
      debugPrint('Error fetching page $page: $e');
      _hasMore = false;
      _notifyDebouncer.run(notifyListeners);
    }
  }

  Future<void> setQuickFilter(String? filterKey) async {
    if (_quickFilter == filterKey) return;
    _quickFilter = filterKey;
    await _resetAndFetch();
  }

  /// Fetch "boosted" products. If subSubcategory is set, filter by it;
  /// else if subcategory is set, filter by that; else filter only by category.
  Future<void> _fetchBoosted() async {
    try {
      Query q = _firestore
          .collection('shop_products')
          .where('isBoosted', isEqualTo: true);

      if (_subSubcategory != null) {
        q = q.where('subsubcategory', isEqualTo: _subSubcategory);
      } else if (_subcategory != null) {
        q = q.where('subcategory', isEqualTo: _subcategory);
      } else if (_category != null) {
        q = q.where('category', isEqualTo: _category);
      }

      q = q.orderBy('createdAt', descending: true).limit(50);

      final snap = await q.get(GetOptions(source: Source.server));
      _boostedProducts
        ..clear()
        ..addAll(snap.docs.map((d) => Product.fromDocument(d)));
      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      debugPrint('Error fetching boosted products: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Concatenate pages in ascending pageIndex order into `_allLoaded`.
  void _rebuildAllLoaded() {
    final sortedPages = _pageCache.keys.toList()..sort();
    final combined = sortedPages.expand((pageIndex) => _pageCache[pageIndex]!);
    _allLoaded
      ..clear()
      ..addAll(combined);
  }

  /// If we have more than [_maxCachedPages] pages, drop the oldest page(s).
  void _pruneIfNeeded() {
    while (_pageCache.length > _maxCachedPages) {
      // Find the lowest page index (oldest)
      final oldestPage = _pageCache.keys.reduce((a, b) => a < b ? a : b);
      _pageCache.remove(oldestPage);
      _pageCursors.remove(oldestPage);
    }
  }

  @override
  void dispose() {
    _notifyDebouncer.dispose();
    super.dispose();
  }
}
