import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product_summary.dart';
import '../utils/debouncer.dart';
import '../services/algolia_service.dart';

enum SearchBackend { firestore, algolia }

class DynamicTerasProvider with ChangeNotifier {
  final AlgoliaService algoliaService; 
  DynamicTerasProvider({required this.algoliaService}); 
  // ──────────────────────────────────────────────────────────────────────────
  // Algolia entegrasyonu: DI ile tek yerden verilecek
  // main.dart: DynamicTerasProvider.algoliaService = AlgoliaServiceManager.instance.mainService;
  // ──────────────────────────────────────────────────────────────────────────
  static const int _docCacheMax = 1000; // tune
  final Map<String, ProductSummary> _docCache = {};
  final Map<String, DateTime> _docCacheTs = {};
  static const int _maxMainCacheEntries = 100;


  // Base index ve replica eşlemesi (dashboard'da varsa)
  static String algoliaBaseIndex = 'products';
  static Map<String, String> algoliaSortReplicas = {
    'date'        : 'products_createdAt_desc',
    'price_asc'   : 'products_price_asc',
    'price_desc'  : 'products_price_desc',
    'alphabetical': 'products_alphabetical',
  };

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
  final Map<String, List<ProductSummary>> _filterBoostedCache = {};
  final Map<String, DateTime> _filterCacheTs = {};

  Future<void> fetchPage(int page) => _fetchPage(page: page);

  List<String> get dynamicSubSubcategories => List.unmodifiable(_dynamicSubSubcategories);
  List<String> _dynamicSubSubcategories = [];

  // UI list
  final List<ProductSummary> _products = [];
  List<ProductSummary> get products => List.unmodifiable(_products);

  // Boosted
  final List<ProductSummary> _boostedProducts = [];
  List<ProductSummary> get boostedProducts => List.unmodifiable(_boostedProducts);

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
  final Debouncer _notifyDebouncer = Debouncer(delay: const Duration(milliseconds: 200));

  static const int _maxCachedPages = 5;

  String? get subcategory => _subcategory;

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> setBuyerCategory(String buyerCategory, String? buyerSubcategory) async {
    if (_buyerCategory == buyerCategory && _buyerSubcategory == buyerSubcategory) return;
    _buyerCategory = buyerCategory;
    _buyerSubcategory = buyerSubcategory;
    await _resetAndFetch();
  }

  String _buildCacheKey(int page) {
    final parts = <String>[];
    if (_dynamicBrands.isNotEmpty) parts.add('brands:${_dynamicBrands.join(",")}');
    if (_dynamicColors.isNotEmpty) parts.add('colors:${_dynamicColors.join(",")}');
    if (_dynamicSubSubcategories.isNotEmpty) parts.add('subsubs:${_dynamicSubSubcategories.join(",")}');
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
      ..sort((a,b) => a.value.compareTo(b.value));
    for (final e in oldest.take(nEvict)) {
      _docCache.remove(e.key);
      _docCacheTs.remove(e.key);
    }
  }
}

void _pruneMainCache() {
  if (_cache.length > _maxMainCacheEntries) {
    final oldest = _cacheTs.entries.toList()
      ..sort((a,b) => a.value.compareTo(b.value));
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
  double? minPrice,
  double? maxPrice,
  bool additive = true,
}) async {
  bool changed = false;
  _saveFilterSnapshot();

  if (additive) {
    if (brands != null) for (final b in brands) if (!_dynamicBrands.contains(b)) { _dynamicBrands.add(b); changed = true; }
    if (colors != null) for (final c in colors) if (!_dynamicColors.contains(c)) { _dynamicColors.add(c); changed = true; }
    if (subSubcategories != null) for (final s in subSubcategories) if (!_dynamicSubSubcategories.contains(s)) { _dynamicSubSubcategories.add(s); changed = true; }
  } else {
    if (brands != null && !_listEquals(_dynamicBrands, brands)) { _dynamicBrands = List.from(brands); changed = true; }
    if (colors != null && !_listEquals(_dynamicColors, colors)) { _dynamicColors = List.from(colors); changed = true; }
    if (subSubcategories != null && !_listEquals(_dynamicSubSubcategories, subSubcategories)) { _dynamicSubSubcategories = List.from(subSubcategories); changed = true; }
  }
  if (minPrice != _minPrice) { _minPrice = minPrice; changed = true; }
  if (maxPrice != _maxPrice) { _maxPrice = maxPrice; changed = true; }

  if (changed) {
    await _restoreOrFetch();
  }
}

 Future<void> removeDynamicFilter({
  String? brand,
  String? color,
  String? subSubcategory,
  bool clearPrice = false,
}) async {
  bool changed = false;
  _saveFilterSnapshot();

  if (brand != null && _dynamicBrands.contains(brand)) { _dynamicBrands.remove(brand); changed = true; }
  if (color != null && _dynamicColors.contains(color)) { _dynamicColors.remove(color); changed = true; }
  if (subSubcategory != null && _dynamicSubSubcategories.contains(subSubcategory)) { _dynamicSubSubcategories.remove(subSubcategory); changed = true; }
  if (clearPrice && (_minPrice != null || _maxPrice != null)) { _minPrice = null; _maxPrice = null; changed = true; }

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
  if (_boostedProducts.isNotEmpty) {
    _filterBoostedCache[key] = List<ProductSummary>.from(_boostedProducts);
  }
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
        (cached.keys.isEmpty ? 0 : cached.keys.reduce((a, b) => a > b ? a : b));
    _rebuildAllLoaded();
    _products
      ..clear()
      ..addAll(_allLoaded);

    final cachedBoosted = _filterBoostedCache[key];
    if (cachedBoosted != null) {
      _boostedProducts
        ..clear()
        ..addAll(cachedBoosted);
    } else {
      _boostedProducts.clear();
    }

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
  _filterBoostedCache.remove(key);
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
      _minPrice != null ||
      _maxPrice != null;

  int get activeFiltersCount {
    int c = 0;
    c += _dynamicBrands.length;
    c += _dynamicColors.length;
    c += _dynamicSubSubcategories.length;
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
    _boostedProducts.clear();
    _hasMore = true;
    _currentPage = 0;
    _filterSeq++;
    _activeLoadingCount++;
    notifyListeners();
    try {
      await _fetchPage(page: 0, forceRefresh: true);
      if (_quickFilter == null) {
        await fetchBoosted();
      }
    } finally {
      _activeLoadingCount--;
      notifyListeners();
    }
  }

  bool _hasPriceIneq() => _minPrice != null || _maxPrice != null;

  int _disjunctionFieldCount() {
    int c = 0;
    if (_dynamicBrands.length > 1) c++;
    if (_dynamicColors.length > 1) c++;
    if (_dynamicSubSubcategories.length > 1) c++;
    return c;
  }

  int _activeFilterCount() {
    return [
      _dynamicBrands.isNotEmpty,
      _dynamicColors.isNotEmpty,
      _dynamicSubSubcategories.isNotEmpty,
      _hasPriceIneq(),
      _quickFilter != null,
    ].where((b) => b).length;
  }

 SearchBackend _decideBackend() {
  // Quick filter'larda (deals, boosted, trending, fiveStar, bestSellers) ALGOLIA'ya zorla
  if (_quickFilter != null) return SearchBackend.algolia;

  final disj = _disjunctionFieldCount();
  final count = _activeFilterCount();

  // alfabetik + fiyat aralığı -> Firestore orderBy conflict
  final alphabeticalWithPrice = (_sortOption == 'alphabetical') && _hasPriceIneq();
  if (alphabeticalWithPrice) return SearchBackend.algolia;

  if (disj >= 2) return SearchBackend.algolia;
  if (count > 2) return SearchBackend.algolia;
  return SearchBackend.firestore;
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
    final useCache = !forceRefresh && cached != null && ts != null && now.difference(ts) < _cacheTtl;

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
      _products..clear()..addAll(_allLoaded);
      _notifyDebouncer.run(notifyListeners);
      return;
    }

    if (_lastBackend == SearchBackend.firestore) {
      await _fetchPageFromFirestore(page: page, seq: seq);
    } else {
      await _fetchPageFromAlgolia(page: page, seq: seq);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FIRESTORE PATH
  // ──────────────────────────────────────────────────────────────────────────
    Future<void> _fetchPageFromFirestore({
    required int page,
    required int seq,
  }) async {
    Query q = _buildFirestoreQuerySafe();

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

      _products..clear()..addAll(_allLoaded);
      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      debugPrint('Firestore query error (will fallback): $e');

      // ---- FALLBACK: sadece WHERE + minimal ORDER BY ----
      try {
        Query fb = _applyWhereClauses(_firestore.collection('products'));

        if (_hasPriceIneq()) {
          fb = fb.orderBy('price')
                 .orderBy('createdAt', descending: true)
                 .orderBy(FieldPath.documentId);
        } else {
          fb = fb.orderBy('createdAt', descending: true)
                 .orderBy(FieldPath.documentId);
        }

        if (page > 0 && _pageCursors.containsKey(page - 1)) {
          final prev = _pageCursors[page - 1];
          if (prev != null) fb = fb.startAfterDocument(prev);
        }

        final snap2 = await fb.limit(_limit).get(const GetOptions(source: Source.serverAndCache));
        if (seq != _filterSeq) return;

        final docs = snap2.docs;
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

        _products..clear()..addAll(_allLoaded);
        _notifyDebouncer.run(notifyListeners);
      } catch (e2) {
        debugPrint('Fallback Firestore query error: $e2');
        _hasMore = false;
        _notifyDebouncer.run(notifyListeners);
      }
    }
  }

    Query _applyWhereClauses(Query q) {
    if (_category != null) q = q.where('category', isEqualTo: _category);
    if (_subcategory != null) q = q.where('subcategory', isEqualTo: _subcategory);
    if (_subSubcategory != null) q = q.where('subsubcategory', isEqualTo: _subSubcategory);

    if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
      q = q.where('gender', whereIn: [_buyerCategory, 'Unisex']);
    }

    if (_dynamicBrands.isNotEmpty && _dynamicBrands.length <= 10) {
      q = q.where('brandModel', whereIn: _dynamicBrands);
    }
    if (_dynamicColors.isNotEmpty && _dynamicColors.length <= 10) {
      q = q.where('availableColors', arrayContainsAny: _dynamicColors);
    }
    if (_dynamicSubSubcategories.isNotEmpty && _dynamicSubSubcategories.length <= 10) {
      q = q.where('subsubcategory', whereIn: _dynamicSubSubcategories);
    }
    if (_minPrice != null) q = q.where('price', isGreaterThanOrEqualTo: _minPrice);
    if (_maxPrice != null) q = q.where('price', isLessThanOrEqualTo: _maxPrice);

    return q;
  }

  Query _buildFirestoreQuerySafe() {
    Query q = _firestore.collection('products');

    if (_category != null) q = q.where('category', isEqualTo: _category);
    if (_subcategory != null) q = q.where('subcategory', isEqualTo: _subcategory);
    if (_subSubcategory != null) q = q.where('subsubcategory', isEqualTo: _subSubcategory);

    if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
      q = q.where('gender', whereIn: [_buyerCategory, 'Unisex']);
    }

    if (_dynamicBrands.isNotEmpty && _dynamicBrands.length <= 10) {
      q = q.where('brandModel', whereIn: _dynamicBrands);
    }
    if (_dynamicColors.isNotEmpty && _dynamicColors.length <= 10) {
      q = q.where('availableColors', arrayContainsAny: _dynamicColors);
    }
    if (_dynamicSubSubcategories.isNotEmpty && _dynamicSubSubcategories.length <= 10) {
      q = q.where('subsubcategory', whereIn: _dynamicSubSubcategories);
    }

    if (_minPrice != null) q = q.where('price', isGreaterThanOrEqualTo: _minPrice);
    if (_maxPrice != null) q = q.where('price', isLessThanOrEqualTo: _maxPrice);    

    final hasPrice = _hasPriceIneq();
    if (_quickFilter == 'bestSellers') {
      // No special query filter for bestSellers
    }

    switch (_sortOption) {
      case 'price_asc':
        q = q.orderBy('price').orderBy('isBoosted', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        break;
      case 'price_desc':
        q = q.orderBy('price', descending: true).orderBy('isBoosted', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        break;
      case 'alphabetical':
        if (hasPrice) {
          q = q.orderBy('price').orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        } else {
          q = q.orderBy('productName').orderBy(FieldPath.documentId);
        }
        break;
      case 'date':
      default:
        try {
          if (hasPrice) {
            q = q.orderBy('price').orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
          } else {
            q = q.orderBy('promotionScore', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
          }
        } catch (_) {
          q = q.orderBy('isBoosted', descending: true).orderBy('promotionScore', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        }
        break;
    }

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

  // ──────────────────────────────────────────────────────────────────────────
  // ALGOLIA PATH (AlgoliaService üzerinden id → Firestore hydrate)
  // ──────────────────────────────────────────────────────────────────────────
 Future<void> _fetchPageFromAlgolia({
  required int page,
  required int seq,
}) async {
  final svc = algoliaService;
  final indexName = _algoliaIndexForCurrentIndex();
  final facetFilters = _buildAlgoliaFacetFilters();
  final numericFilters = _buildAlgoliaNumericFilters();

  try {
    final res = await svc.searchIdsWithFacets(
      indexName: indexName,
      page: page,
      hitsPerPage: _limit,
      facetFilters: facetFilters,
      numericFilters: numericFilters,
    );
    if (seq != _filterSeq) return;

    // ✅ Parse directly from Algolia hits — no Firestore round-trip
    final fetched = res.hits.map((hit) {
      final summary = ProductSummary.fromAlgolia(hit);
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

    _products..clear()..addAll(_allLoaded);
    _notifyDebouncer.run(notifyListeners);
  } catch (e) {
    debugPrint('Algolia service query error: $e');
    await _fetchPageFromFirestore(page: page, seq: seq);
  }
}

String _algoliaIndexForCurrentIndex() {
  // Since you don't have filter replicas, always use sort replicas
  // Filters (facet/numeric) work on any index/replica
  final replica = algoliaSortReplicas[_sortOption];
  return replica ?? algoliaBaseIndex;
}

List<List<String>> _buildAlgoliaFacetFilters() {
  final List<List<String>> groups = [];
  
  debugPrint('Building filters: category=$_category, subcategory=$_subcategory, subSubcategory=$_subSubcategory, buyerCategory=$_buyerCategory');
  
  // For Women/Men categories with null subsubcategory, don't add subsubcategory filter
  final bool isGenderedCategory = (_buyerCategory == 'Women' || _buyerCategory == 'Men');
  final bool shouldSkipSubSubcategory = isGenderedCategory && _subSubcategory == null;
  
  if (_category != null) {
    groups.add(['category_en:${_category!}']);
  }
  if (_subcategory != null) {
    groups.add(['subcategory_en:${_subcategory!}']);
  }
  
  // Only add subsubcategory filter if:
  // 1. It's not null
  // 2. OR it's not a gendered category (Women/Men)
  if (_subSubcategory != null) {
    groups.add(['subsubcategory_en:${_subSubcategory!}']);
  } else if (!isGenderedCategory) {
    // For non-gendered categories, we might still want the filter even if null
    // This depends on your data structure
  }

  // Gender field appears to be without suffix in your data
  if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
    groups.add(['gender:${_buyerCategory!}', 'gender:Unisex']);
  }

  // brandModel appears to be without suffix
  if (_dynamicBrands.isNotEmpty) {
    groups.add(_dynamicBrands.map((b) => 'brandModel:$b').toList());
  }
  
  // availableColors might need to be checked - it's not in your example
  if (_dynamicColors.isNotEmpty) {
    groups.add(_dynamicColors.map((c) => 'availableColors:$c').toList());
  }
  
  // For dynamic subsubcategories, use language suffix
  if (_dynamicSubSubcategories.isNotEmpty) {
    groups.add(_dynamicSubSubcategories.map((s) => 'subsubcategory_en:$s').toList());
  }

  if (_quickFilter == 'boosted') {
    groups.add(['isBoosted:true']);
  }

  debugPrint('Final facet filters: $groups');
  return groups;
}

  List<String> _buildAlgoliaNumericFilters() {
    final List<String> filters = [];
    if (_minPrice != null) filters.add('price>=${_minPrice!.floor()}');
if (_maxPrice != null) filters.add('price<=${_maxPrice!.ceil()}');

    switch (_quickFilter) {
      case 'deals':
        filters.add('discountPercentage>0');
        break;
      case 'trending':
        break;
      case 'fiveStar':
        break;
      case 'bestSellers':
      default:
        break;
    }
    return filters;
  }

  Future<List<ProductSummary>> _fetchProductsByIdsPreservingOrder(List<String> ids) async {
    if (ids.isEmpty) {
      debugPrint('No IDs to fetch from Firestore');
      return [];
    }

    // Yalnızca ihtiyaç olanları çek
    final need = <String>[];
    for (final id in ids) {
      if (!_docCache.containsKey(id)) need.add(id);
    }

    if (need.isNotEmpty) {
      final futures = <Future<QuerySnapshot>>[];
      for (final chunk in _chunks(need, 10)) {
        futures.add(_firestore
            .collection('products')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.serverAndCache))); // server doğruluğu
      }
      final snaps = await Future.wait(futures);
      for (final d in snaps.expand((s) => s.docs)) {
  final product = ProductSummary.fromDocument(d);
  _docCachePut(d.id, product); // ⬅️ use the LRU-aware put
}
    }

    final ordered = <ProductSummary>[];
for (final id in ids) {
  final p = _docCache[id];
  if (p != null) {
    ordered.add(p);
    _docCacheTs[id] = DateTime.now(); // ⬅️ touch
  }
}
    return ordered;
  }

  Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BOOSTED
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> fetchBoosted() async {
    if (_category == null || _subSubcategory == null) return;

    try {
      Query q = _firestore
          .collection('products')
          .where('isBoosted', isEqualTo: true)
          .where('category', isEqualTo: _category)
          .where('subsubcategory', isEqualTo: _subSubcategory);

      if (_buyerCategory == 'Women' || _buyerCategory == 'Men') {
        q = q.where('gender', whereIn: [_buyerCategory, 'Unisex']);
      }
      if (_dynamicBrands.isNotEmpty && _dynamicBrands.length <= 10) {
        q = q.where('brandModel', whereIn: _dynamicBrands);
      }
      if (_dynamicColors.isNotEmpty && _dynamicColors.length <= 10) {
        q = q.where('availableColors', arrayContainsAny: _dynamicColors);
      }
      if (_dynamicSubSubcategories.isNotEmpty && _dynamicSubSubcategories.length <= 10) {
        q = q.where('subsubcategory', whereIn: _dynamicSubSubcategories);
      }
      if (_minPrice != null) q = q.where('price', isGreaterThanOrEqualTo: _minPrice);
      if (_maxPrice != null) q = q.where('price', isLessThanOrEqualTo: _maxPrice);

      if (_hasPriceIneq()) {
        q = q.orderBy('price').orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
      } else {
        try {
          q = q.orderBy('promotionScore', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        } catch (_) {
          q = q.orderBy('promotionScore', descending: true).orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
        }
      }

      final snap = await q.limit(50).get(GetOptions(source: Source.server));
      _boostedProducts..clear()..addAll(snap.docs.map((d) => ProductSummary.fromDocument(d)));
      _notifyDebouncer.run(notifyListeners);
    } catch (e) {
      debugPrint('Error fetching boosted products: $e');
      _boostedProducts.clear();
      _notifyDebouncer.run(notifyListeners);
    }
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