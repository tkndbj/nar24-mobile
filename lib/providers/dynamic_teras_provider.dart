import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product_summary.dart';
import '../utils/debouncer.dart';
import '../services/typesense_service.dart';

enum SearchBackend { firestore, TypeSense }

class DynamicTerasProvider with ChangeNotifier {
  final TypeSenseService _searchService;
  DynamicTerasProvider({required TypeSenseService searchService})
      : _searchService = searchService;

  static const int _docCacheMax = 1000; // tune
  final Map<String, ProductSummary> _docCache = {};
  final Map<String, DateTime> _docCacheTs = {};
  static const int _maxMainCacheEntries = 100;
  static String typesenseBaseIndex = 'products';

  // ──────────────────────────────────────────────────────────────────────────
  // PAGED CACHE STATE
  // ──────────────────────────────────────────────────────────────────────────
  String? _buyerCategory;
  String? _buyerSubcategory;

  String? get buyerCategory => _buyerCategory;
  String? get buyerSubcategory => _buyerSubcategory;

  final Map<int, List<ProductSummary>> _pageCache = {};
  final Map<int, DocumentSnapshot> _pageCursors = {};
  final List<ProductSummary> _allLoaded = [];
  List<ProductSummary> get rawProducts => List.unmodifiable(_allLoaded);
  Map<int, List<ProductSummary>> get pageCache => _pageCache;

  final Map<String, Map<int, List<ProductSummary>>> _filterPageCache = {};
  final Map<String, Map<int, DocumentSnapshot>> _filterPageCursors = {};
  final Map<String, bool> _filterHasMore = {};
  final Map<String, int> _filterCurrentPage = {};
  final Map<String, DateTime> _filterCacheTs = {};

  Future<void> fetchPage(int page) => _fetchPage(page: page);

  List<String> get dynamicSubSubcategories =>
      List.unmodifiable(_dynamicSubSubcategories);
  List<String> _dynamicSubSubcategories = [];

  // UI list
  final List<ProductSummary> _products = [];
  List<ProductSummary> get products => List.unmodifiable(_products);

  // Boosted (handled by promotionScore sorting, no separate query needed)
  List<ProductSummary> get boostedProducts => const [];

  // Flags
  bool get hasMore => _hasMore;
  bool _hasMore = true;

  bool get isLoadingMore => _isLoadingMore;
  bool _isLoadingMore = false;

  // Tracks whether data fetch is in progress
  // Uses a counter to handle concurrent fetch operations correctly
  bool get isLoading => _activeLoadingCount > 0;
  int _activeLoadingCount = 0;

  String get sortOption => _sortOption;
  String _sortOption = 'date';

  String? get quickFilter => _quickFilter;
  String? _quickFilter;

  // Dynamic filters
  List<String> get dynamicBrands => List.unmodifiable(_dynamicBrands);
  List<String> get dynamicColors => List.unmodifiable(_dynamicColors);
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;

  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  double? _minPrice;
  double? _maxPrice;

  /// Generic spec filters: field name → selected values
  final Map<String, List<String>> _dynamicSpecFilters = {};
  Map<String, List<String>> get dynamicSpecFilters =>
      Map.unmodifiable(_dynamicSpecFilters.map(
          (k, v) => MapEntry(k, List<String>.unmodifiable(v))));

  // ── Spec facets (fetched from Typesense, cached per category context) ──
  Map<String, List<Map<String, dynamic>>> _specFacets = {};
  Map<String, List<Map<String, dynamic>>> get specFacets =>
      Map.unmodifiable(_specFacets);

  final Map<String, Map<String, List<Map<String, dynamic>>>> _facetCache = {};
  final Map<String, DateTime> _facetCacheTs = {};
  static const Duration _facetCacheTtl = Duration(minutes: 5);

  // Pagination
  static const int _limit = 20;
  int _currentPage = 0;

  // TTL cache
  final Map<String, List<ProductSummary>> _cache = {};
  final Map<String, DateTime> _cacheTs = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  int _filterSeq = 0;
  String? _category;
  String? _subcategory;
  String? _subSubcategory;

  SearchBackend _lastBackend = SearchBackend.firestore;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Debouncer _notifyDebouncer =
      Debouncer(delay: const Duration(milliseconds: 200));

  static const int _maxCachedPages = 5;

  String? get subcategory => _subcategory;

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────
  /// Sets all category/gender state at once and fires a single query.
  Future<void> initialize({
    required String category,
    String? subcategory,
    String? subSubcategory,
    String? buyerCategory,
    String? buyerSubcategory,
  }) async {
    _category = category;
    _subcategory = subcategory;
    _subSubcategory = subSubcategory;
    _buyerCategory = buyerCategory;
    _buyerSubcategory = buyerSubcategory;

    // Fire product fetch and facet fetch in parallel
    await Future.wait([
      _resetAndFetch(),
      _fetchSpecFacets(),
    ]);
  }

  Future<void> setBuyerCategory(
      String buyerCategory, String? buyerSubcategory) async {
    if (_buyerCategory == buyerCategory &&
        _buyerSubcategory == buyerSubcategory) return;
    _buyerCategory = buyerCategory;
    _buyerSubcategory = buyerSubcategory;
    await _resetAndFetch();
  }

  String _buildCacheKey(int page) {
    final parts = <String>[];
    if (_dynamicBrands.isNotEmpty)
      parts.add('brands:${_dynamicBrands.join(",")}');
    if (_dynamicColors.isNotEmpty)
      parts.add('colors:${_dynamicColors.join(",")}');
    if (_dynamicSubSubcategories.isNotEmpty)
      parts.add('subsubs:${_dynamicSubSubcategories.join(",")}');
    for (final entry in _dynamicSpecFilters.entries) {
      if (entry.value.isNotEmpty) {
        parts.add('spec_${entry.key}:${entry.value.join(",")}');
      }
    }
    if (_minPrice != null) parts.add('minP:$_minPrice');
    if (_maxPrice != null) parts.add('maxP:$_maxPrice');
    if (_quickFilter != null) parts.add('quick:$_quickFilter');
    if (_buyerCategory != null) parts.add('buyer:$_buyerCategory');
    if (_buyerSubcategory != null) parts.add('buyerSub:$_buyerSubcategory');
    parts.add('backend:${_lastBackend.name}');
    final filters = parts.isNotEmpty ? '|${parts.join("|")}' : '';
    return '$_category|$_subcategory|$_subSubcategory|$page|$_sortOption$filters|v6';
  }

  Future<void> setCategory(String category) async {
    if (_category == category) return;
    _category = category;
    _subSubcategory = null;
    await _resetAndFetch();
  }

  Future<void> setSubcategory(String sub) async {
    if (_subcategory == sub) return;
    _subcategory = sub;
    _subSubcategory = null;
    await _resetAndFetch();
  }

  Future<void> setSubSubcategory(String sub) async {
    if (_subSubcategory == sub) return;
    _subSubcategory = sub;
    await _resetAndFetch();
  }

  Future<void> setSortOption(String option) async {
    if (_sortOption == option) return;
    _saveFilterSnapshot();
    _sortOption = option;
    await _restoreOrFetch();
  }

  void _docCachePut(String id, ProductSummary p) {
    _docCache[id] = p;
    _docCacheTs[id] = DateTime.now();
    if (_docCache.length > _docCacheMax) {
      // evict oldest ~10%
      final nEvict = (_docCacheMax * 0.1).round();
      final oldest = _docCacheTs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in oldest.take(nEvict)) {
        _docCache.remove(e.key);
        _docCacheTs.remove(e.key);
      }
    }
  }

  void _pruneMainCache() {
    if (_cache.length > _maxMainCacheEntries) {
      final oldest = _cacheTs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final toRemove = oldest.take(_cache.length - _maxMainCacheEntries);
      for (final e in toRemove) {
        _cache.remove(e.key);
        _cacheTs.remove(e.key);
      }
    }
  }

  Future<void> setDynamicFilter({
    List<String>? brands,
    List<String>? colors,
    List<String>? subSubcategories,
    Map<String, List<String>>? specFilters,
    double? minPrice,
    double? maxPrice,
    bool additive = true,
  }) async {
    bool changed = false;
    _saveFilterSnapshot();

    if (additive) {
      if (brands != null)
        for (final b in brands)
          if (!_dynamicBrands.contains(b)) {
            _dynamicBrands.add(b);
            changed = true;
          }
      if (colors != null)
        for (final c in colors)
          if (!_dynamicColors.contains(c)) {
            _dynamicColors.add(c);
            changed = true;
          }
      if (subSubcategories != null)
        for (final s in subSubcategories)
          if (!_dynamicSubSubcategories.contains(s)) {
            _dynamicSubSubcategories.add(s);
            changed = true;
          }
      if (specFilters != null) {
        for (final entry in specFilters.entries) {
          final existing = _dynamicSpecFilters[entry.key] ??= [];
          for (final v in entry.value) {
            if (!existing.contains(v)) {
              existing.add(v);
              changed = true;
            }
          }
        }
      }
    } else {
      if (brands != null && !_listEquals(_dynamicBrands, brands)) {
        _dynamicBrands = List.from(brands);
        changed = true;
      }
      if (colors != null && !_listEquals(_dynamicColors, colors)) {
        _dynamicColors = List.from(colors);
        changed = true;
      }
      if (subSubcategories != null &&
          !_listEquals(_dynamicSubSubcategories, subSubcategories)) {
        _dynamicSubSubcategories = List.from(subSubcategories);
        changed = true;
      }
      if (specFilters != null) {
        final newKeys = specFilters.keys.toSet();
        final oldKeys = _dynamicSpecFilters.keys.toSet();
        if (!newKeys.containsAll(oldKeys) || !oldKeys.containsAll(newKeys)) {
          changed = true;
        } else {
          for (final key in newKeys) {
            if (!_listEquals(
                _dynamicSpecFilters[key] ?? [], specFilters[key] ?? [])) {
              changed = true;
              break;
            }
          }
        }
        if (changed) {
          _dynamicSpecFilters.clear();
          for (final entry in specFilters.entries) {
            if (entry.value.isNotEmpty) {
              _dynamicSpecFilters[entry.key] = List.from(entry.value);
            }
          }
        }
      }
    }
    if (minPrice != _minPrice) {
      _minPrice = minPrice;
      changed = true;
    }
    if (maxPrice != _maxPrice) {
      _maxPrice = maxPrice;
      changed = true;
    }

    if (changed) {
      await _restoreOrFetch();
    }
  }

  Future<void> removeDynamicFilter({
    String? brand,
    String? color,
    String? subSubcategory,
    String? specField,
    String? specValue,
    bool clearPrice = false,
  }) async {
    bool changed = false;
    _saveFilterSnapshot();

    if (brand != null && _dynamicBrands.contains(brand)) {
      _dynamicBrands.remove(brand);
      changed = true;
    }
    if (color != null && _dynamicColors.contains(color)) {
      _dynamicColors.remove(color);
      changed = true;
    }
    if (subSubcategory != null &&
        _dynamicSubSubcategories.contains(subSubcategory)) {
      _dynamicSubSubcategories.remove(subSubcategory);
      changed = true;
    }
    if (specField != null && specValue != null) {
      final list = _dynamicSpecFilters[specField];
      if (list != null && list.contains(specValue)) {
        list.remove(specValue);
        if (list.isEmpty) _dynamicSpecFilters.remove(specField);
        changed = true;
      }
    }
    if (clearPrice && (_minPrice != null || _maxPrice != null)) {
      _minPrice = null;
      _maxPrice = null;
      changed = true;
    }

    if (changed) {
      await _restoreOrFetch();
    }
  }

  Future<void> clearDynamicFilters() async {
    if (!hasDynamicFilters) return;
    _saveFilterSnapshot();
    _dynamicBrands.clear();
    _dynamicColors.clear();
    _dynamicSubSubcategories.clear();
    _dynamicSpecFilters.clear();
    _minPrice = null;
    _maxPrice = null;
    await _restoreOrFetch();
  }

  void _saveFilterSnapshot() {
    if (_pageCache.isEmpty) return;
    final key = _buildFilterCacheKey();
    _filterPageCache[key] = Map<int, List<ProductSummary>>.from(
      _pageCache.map((k, v) => MapEntry(k, List<ProductSummary>.from(v))),
    );
    _filterPageCursors[key] = Map<int, DocumentSnapshot>.from(_pageCursors);
    _filterHasMore[key] = _hasMore;
    _filterCurrentPage[key] = _currentPage;
    _filterCacheTs[key] = DateTime.now();
    _pruneFilterCache();
  }

  Future<void> _restoreOrFetch() async {
    final key = _buildFilterCacheKey();
    final cached = _filterPageCache[key];
    final ts = _filterCacheTs[key];
    final now = DateTime.now();

    if (cached != null && ts != null && now.difference(ts) < _cacheTtl) {
      _pageCache.clear();
      _pageCache.addAll(cached);

      _pageCursors.clear();
      final cachedCursors = _filterPageCursors[key];
      if (cachedCursors != null) {
        _pageCursors.addAll(cachedCursors);
      }

      _hasMore = _filterHasMore[key] ?? true;
      _currentPage = _filterCurrentPage[key] ??
          (cached.keys.isEmpty
              ? 0
              : cached.keys.reduce((a, b) => a > b ? a : b));
      _rebuildAllLoaded();
      _products
        ..clear()
        ..addAll(_allLoaded);

      _filterCacheTs[key] = now;
      notifyListeners();
    } else {
      if (cached != null) {
        _removeFilterCacheEntry(key);
      }
      await _resetAndFetch();
    }
  }

  void _removeFilterCacheEntry(String key) {
    _filterPageCache.remove(key);
    _filterPageCursors.remove(key);
    _filterHasMore.remove(key);
    _filterCurrentPage.remove(key);
    _filterCacheTs.remove(key);
  }

  void _pruneFilterCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    _filterCacheTs.forEach((key, timestamp) {
      if (now.difference(timestamp) >= _cacheTtl) {
        keysToRemove.add(key);
      }
    });
    for (final key in keysToRemove) {
      _removeFilterCacheEntry(key);
    }

    const maxCacheEntries = 20;
    if (_filterPageCache.length > maxCacheEntries) {
      final sortedEntries = _filterCacheTs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final entriesToRemove = sortedEntries
          .take(_filterPageCache.length - maxCacheEntries)
          .map((e) => e.key);
      for (final key in entriesToRemove) {
        _removeFilterCacheEntry(key);
      }
    }
  }

  Future<void> setQuickFilter(String? filterKey) async {
    if (_quickFilter == filterKey) return;
    _saveFilterSnapshot();
    _quickFilter = filterKey;
    await _restoreOrFetch();
  }

  Future<void> fetchMoreProducts() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _currentPage++;
    await _fetchPage(page: _currentPage);
    _isLoadingMore = false;
    _notifyDebouncer.run(notifyListeners);
  }

  Future<void> refresh() async => _resetAndFetch();

  bool get hasDynamicFilters =>
      _dynamicBrands.isNotEmpty ||
      _dynamicColors.isNotEmpty ||
      _dynamicSubSubcategories.isNotEmpty ||
      _dynamicSpecFilters.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null;

  int get activeFiltersCount {
    int c = 0;
    c += _dynamicBrands.length;
    c += _dynamicColors.length;
    c += _dynamicSubSubcategories.length;
    for (final vals in _dynamicSpecFilters.values) {
      c += vals.length;
    }
    if (_minPrice != null || _maxPrice != null) c++;
    return c;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CORE
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _resetAndFetch() async {
    _pageCache.clear();
    _pageCursors.clear();
    _allLoaded.clear();
    _products.clear();
    _hasMore = true;
    _currentPage = 0;
    _filterSeq++;
    _activeLoadingCount++;
    notifyListeners();
    try {
      await _fetchPage(page: 0, forceRefresh: true);
    } finally {
      _activeLoadingCount--;
      notifyListeners();
    }
  }

  SearchBackend _decideBackend() {
    if (_sortOption != 'date') return SearchBackend.TypeSense;
    if (hasDynamicFilters) return SearchBackend.TypeSense;
    return SearchBackend.firestore;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SPEC FACETS FETCH
  // ──────────────────────────────────────────────────────────────────────────
  String _buildFacetCacheKey() {
    return 'facet|$_category|$_subcategory|$_subSubcategory|$_buyerCategory';
  }

  Future<void> _fetchSpecFacets() async {
    final cacheKey = _buildFacetCacheKey();
    final now = DateTime.now();

    final cached = _facetCache[cacheKey];
    final ts = _facetCacheTs[cacheKey];
    if (cached != null && ts != null && now.difference(ts) < _facetCacheTtl) {
      _specFacets = cached;
      return;
    }

    try {
      final facetFilters = <List<String>>[];
      if (_category != null) {
        facetFilters.add(['category_en:${_category!}']);
      }
      if (_subcategory != null) {
        facetFilters.add(['subcategory_en:${_subcategory!}']);
      }
      if (_subSubcategory != null) {
        facetFilters.add(['subsubcategory_en:${_subSubcategory!}']);
      }
      if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
        facetFilters.add(['gender:${_buyerCategory!}', 'gender:Unisex']);
      }

      final result = await _searchService.fetchSpecFacets(
        indexName: 'products',
        facetFilters: facetFilters,
      );

      _specFacets = result;

      _facetCache[cacheKey] = result;
      _facetCacheTs[cacheKey] = now;

      if (_facetCache.length > 20) {
        final oldest = _facetCacheTs.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final e in oldest.take(_facetCache.length - 20)) {
          _facetCache.remove(e.key);
          _facetCacheTs.remove(e.key);
        }
      }
    } catch (e) {
      debugPrint('Error fetching spec facets: $e');
      _specFacets = {};
    }
  }

  Future<void> _fetchPage({
    required int page,
    bool forceRefresh = false,
  }) async {
    final seq = ++_filterSeq;

    _lastBackend = _decideBackend();

    final cacheKey = _buildCacheKey(page);
    final now = DateTime.now();
    final cached = _cache[cacheKey];
    final ts = _cacheTs[cacheKey];
    final useCache = !forceRefresh &&
        cached != null &&
        ts != null &&
        now.difference(ts) < _cacheTtl;

    if (page == 0 && !useCache) {
      _pageCache.clear();
      _pageCursors.clear();
      _allLoaded.clear();
      _products.clear();
      _hasMore = true;
      notifyListeners();
    }

    if (useCache) {
      _pageCache[page] = cached;
      _hasMore = cached.length >= _limit;
      _rebuildAllLoaded();
      _products
        ..clear()
        ..addAll(_allLoaded);
      _notifyDebouncer.run(notifyListeners);
      return;
    }

    if (_lastBackend == SearchBackend.firestore) {
      await _fetchPageFromFirestore(page: page, seq: seq);
    } else {
      await _fetchPageFromTypeSense(page: page, seq: seq);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FIRESTORE PATH
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _fetchPageFromFirestore({
    required int page,
    required int seq,
  }) async {
    Query q = _buildFirestoreQuery();

    if (page > 0 && _pageCursors.containsKey(page - 1)) {
      final prev = _pageCursors[page - 1];
      if (prev != null) q = q.startAfterDocument(prev);
    }
    q = q.limit(_limit);

    try {
      final snap = await q.get(const GetOptions(source: Source.serverAndCache));
      if (seq != _filterSeq) return;

      final docs = snap.docs;
      if (docs.isNotEmpty) {
        _pageCursors[page] = docs.last;
      } else {
        _pageCursors.remove(page);
      }

      final fetched = docs.map((d) => ProductSummary.fromDocument(d)).toList();
      _hasMore = fetched.length >= _limit;

      final key = _buildCacheKey(page);
      _cache[key] = fetched;
      _cacheTs[key] = DateTime.now();
      _pruneMainCache();
      _pageCache[page] = fetched;
      _rebuildAllLoaded();
      _pruneIfNeeded();

      _products
        ..clear()
        ..addAll(_allLoaded);
      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      debugPrint('Firestore query error: $e');
      _hasMore = false;
      _notifyDebouncer.run(notifyListeners);
    }
  }

  /// Only 2 possible Firestore queries:
  /// 1. category + subcategory + subsubcategory (no gender)
  /// 2. category + subcategory + gender whereIn (with gender)
  /// Always ordered by promotionScore DESC, __name__ ASC.
  Query _buildFirestoreQuery() {
    Query q = _firestore.collection('products');

    if (_category != null) q = q.where('category', isEqualTo: _category);
    if (_subcategory != null)
      q = q.where('subcategory', isEqualTo: _subcategory);
    if (_subSubcategory != null)
      q = q.where('subsubcategory', isEqualTo: _subSubcategory);

    if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
      q = q.where('gender', whereIn: [_buyerCategory, 'Unisex']);
    }

    q = q
        .orderBy('promotionScore', descending: true)
        .orderBy(FieldPath.documentId);

    return q;
  }

  String _buildFilterCacheKey() {
    final parts = <String>[];

    // Include quick filter
    parts.add(_quickFilter ?? 'default');

    // Include all dynamic filters (sorted for consistent keys)
    if (_dynamicBrands.isNotEmpty) {
      final sortedBrands = List<String>.from(_dynamicBrands)..sort();
      parts.add('b:${sortedBrands.join(",")}');
    }
    if (_dynamicColors.isNotEmpty) {
      final sortedColors = List<String>.from(_dynamicColors)..sort();
      parts.add('c:${sortedColors.join(",")}');
    }
    if (_dynamicSubSubcategories.isNotEmpty) {
      final sortedSubSubs = List<String>.from(_dynamicSubSubcategories)..sort();
      parts.add('s:${sortedSubSubs.join(",")}');
    }
    // Generic spec filters
    final sortedSpecKeys = _dynamicSpecFilters.keys.toList()..sort();
    for (final field in sortedSpecKeys) {
      final vals = _dynamicSpecFilters[field];
      if (vals != null && vals.isNotEmpty) {
        final sorted = List<String>.from(vals)..sort();
        parts.add('sf_$field:${sorted.join(",")}');
      }
    }
    if (_minPrice != null) parts.add('min:$_minPrice');
    if (_maxPrice != null) parts.add('max:$_maxPrice');
    if (_buyerCategory != null) parts.add('bc:$_buyerCategory');
    if (_buyerSubcategory != null) parts.add('bs:$_buyerSubcategory');
    if (_category != null) parts.add('cat:$_category');
    if (_subcategory != null) parts.add('sub:$_subcategory');
    if (_subSubcategory != null) parts.add('subsub:$_subSubcategory');
    parts.add('sort:$_sortOption');

    return parts.join('|');
  }

  List<String> _buildTypeSenseNumericFilters() {
    final List<String> filters = [];
    if (_minPrice != null) filters.add('price>=${_minPrice!.floor()}');
    if (_maxPrice != null) filters.add('price<=${_maxPrice!.ceil()}');
    return filters;
  }

  Future<void> _fetchPageFromTypeSense(
      {required int page, required int seq}) async {
    final svc = _searchService;
    final indexName = 'products'; // hardcoded
    final facetFilters = _buildTypeSenseFacetFilters();
    final numericFilters = _buildTypeSenseNumericFilters();

    try {
      final res = await svc.searchIdsWithFacets(
        indexName: indexName,
        page: page,
        hitsPerPage: _limit,
        facetFilters: facetFilters,
        numericFilters: numericFilters,
        sortOption: _sortOption,
      );
      if (seq != _filterSeq) return;

      // ✅ Parse directly from TypeSense hits — no Firestore round-trip
      final fetched = res.hits.map((hit) {
        final summary = ProductSummary.fromTypeSense(hit);
        _docCachePut(summary.id, summary);
        return summary;
      }).toList();

      _hasMore = res.page < (res.nbPages - 1);

      final key = _buildCacheKey(page);
      _cache[key] = fetched;
      _cacheTs[key] = DateTime.now();
      _pruneMainCache();
      _pageCache[page] = fetched;
      _rebuildAllLoaded();
      _pruneIfNeeded();

      _products
        ..clear()
        ..addAll(_allLoaded);
      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      debugPrint('TypeSense service query error: $e');
      await _fetchPageFromFirestore(page: page, seq: seq);
    }
  }

  List<List<String>> _buildTypeSenseFacetFilters() {
    final List<List<String>> groups = [];

    debugPrint(
        'Building filters: category=$_category, subcategory=$_subcategory, subSubcategory=$_subSubcategory, buyerCategory=$_buyerCategory');

    if (_category != null) {
      groups.add(['category_en:${_category!}']);
    }
    if (_subcategory != null) {
      groups.add(['subcategory_en:${_subcategory!}']);
    }

    if (_subSubcategory != null) {
      groups.add(['subsubcategory_en:${_subSubcategory!}']);
    }

    if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
      groups.add(['gender:${_buyerCategory!}', 'gender:Unisex']);
    }

    if (_dynamicBrands.isNotEmpty) {
      groups.add(_dynamicBrands.map((b) => 'brandModel:$b').toList());
    }

    if (_dynamicColors.isNotEmpty) {
      groups.add(_dynamicColors.map((c) => 'availableColors:$c').toList());
    }

    if (_dynamicSubSubcategories.isNotEmpty) {
      groups.add(
          _dynamicSubSubcategories.map((s) => 'subsubcategory_en:$s').toList());
    }

    // Generic spec filters — each field becomes its own filter group
    for (final entry in _dynamicSpecFilters.entries) {
      if (entry.value.isNotEmpty) {
        groups.add(entry.value.map((v) => '${entry.key}:$v').toList());
      }
    }

    debugPrint('Final facet filters: $groups');
    return groups;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _rebuildAllLoaded() {
    final sortedPages = _pageCache.keys.toList()..sort();
    final seen = <String>{};
    final combined = <ProductSummary>[];
    for (final i in sortedPages) {
      for (final p in _pageCache[i]!) {
        if (seen.add(p.id)) combined.add(p);
      }
    }
    _allLoaded
      ..clear()
      ..addAll(combined);
  }

  void _pruneIfNeeded() {
    while (_pageCache.length > _maxCachedPages) {
      final oldest = _pageCache.keys.reduce((a, b) => a < b ? a : b);
      _pageCache.remove(oldest);
      _pageCursors.remove(oldest);
    }
  }

  @override
  void dispose() {
    _notifyDebouncer.dispose();
    super.dispose();
  }
}
