// test/providers/testable_shop_market_provider.dart
//
// TESTABLE MIRROR of ShopMarketProvider pure logic from lib/providers/shop_market_provider.dart
//
// This file contains EXACT copies of pure logic functions from ShopMarketProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/shop_market_provider.dart
//
// Last synced with: shop_market_provider.dart (current version)


/// Mirrors SearchBackend enum from ShopMarketProvider
enum TestableSearchBackend { firestore, algolia }

/// Mirrors the backend decision logic from ShopMarketProvider
class TestableBackendDecider {
  String? quickFilter;
  String sortOption = 'date';
  List<String> dynamicBrands = [];
  List<String> dynamicColors = [];
  List<String> dynamicSubSubcategories = [];
  double? minPrice;
  double? maxPrice;

  /// Mirrors _hasPriceIneq from ShopMarketProvider
  bool hasPriceInequality() => minPrice != null || maxPrice != null;

  /// Mirrors _disjunctionFieldCount from ShopMarketProvider
  int disjunctionFieldCount() {
    int c = 0;
    if (dynamicBrands.length > 1) c++;
    if (dynamicColors.length > 1) c++;
    if (dynamicSubSubcategories.length > 1) c++;
    return c;
  }

  /// Mirrors _activeFilterCount from ShopMarketProvider
  int activeFilterCount() {
    return [
      dynamicBrands.isNotEmpty,
      dynamicColors.isNotEmpty,
      dynamicSubSubcategories.isNotEmpty,
      hasPriceInequality(),
      quickFilter != null,
    ].where((b) => b).length;
  }

  /// Mirrors _decideBackend from ShopMarketProvider
  TestableSearchBackend decideBackend() {
    // Quick filter'larda (deals, boosted, trending, fiveStar, bestSellers) ALGOLIA'ya zorla
    if (quickFilter != null) return TestableSearchBackend.algolia;

    final disj = disjunctionFieldCount();
    final count = activeFilterCount();

    // alfabetik + fiyat aralığı -> Firestore orderBy conflict
    final alphabeticalWithPrice = (sortOption == 'alphabetical') && hasPriceInequality();
    if (alphabeticalWithPrice) return TestableSearchBackend.algolia;

    if (disj >= 2) return TestableSearchBackend.algolia;
    if (count > 2) return TestableSearchBackend.algolia;
    return TestableSearchBackend.firestore;
  }

  void reset() {
    quickFilter = null;
    sortOption = 'date';
    dynamicBrands = [];
    dynamicColors = [];
    dynamicSubSubcategories = [];
    minPrice = null;
    maxPrice = null;
  }
}

/// Mirrors cache key building from ShopMarketProvider
class TestableCacheKeyBuilder {
  String? category;
  String? subcategory;
  String? subSubcategory;
  String sortOption = 'date';
  String? quickFilter;
  String? buyerCategory;
  String? buyerSubcategory;
  List<String> dynamicBrands = [];
  List<String> dynamicColors = [];
  List<String> dynamicSubSubcategories = [];
  double? minPrice;
  double? maxPrice;
  TestableSearchBackend lastBackend = TestableSearchBackend.firestore;

  /// Mirrors _buildCacheKey from ShopMarketProvider
  String buildCacheKey(int page) {
    final parts = <String>[];
    if (dynamicBrands.isNotEmpty) {
      parts.add('brands:${dynamicBrands.join(",")}');
    }
    if (dynamicColors.isNotEmpty) {
      parts.add('colors:${dynamicColors.join(",")}');
    }
    if (dynamicSubSubcategories.isNotEmpty) {
      parts.add('subsubs:${dynamicSubSubcategories.join(",")}');
    }
    if (minPrice != null) parts.add('minP:$minPrice');
    if (maxPrice != null) parts.add('maxP:$maxPrice');
    if (quickFilter != null) parts.add('quick:$quickFilter');
    if (buyerCategory != null) parts.add('buyer:$buyerCategory');
    if (buyerSubcategory != null) parts.add('buyerSub:$buyerSubcategory');
    parts.add('backend:${lastBackend.name}');
    final filters = parts.isNotEmpty ? '|${parts.join("|")}' : '';
    return '$category|$subcategory|$subSubcategory|$page|$sortOption$filters|v6';
  }

  /// Mirrors _buildFilterCacheKey from ShopMarketProvider
  String buildFilterCacheKey() {
    final parts = <String>[];

    // Include quick filter
    parts.add(quickFilter ?? 'default');

    // Include all dynamic filters (sorted for consistent keys)
    if (dynamicBrands.isNotEmpty) {
      final sortedBrands = List<String>.from(dynamicBrands)..sort();
      parts.add('b:${sortedBrands.join(",")}');
    }
    if (dynamicColors.isNotEmpty) {
      final sortedColors = List<String>.from(dynamicColors)..sort();
      parts.add('c:${sortedColors.join(",")}');
    }
    if (dynamicSubSubcategories.isNotEmpty) {
      final sortedSubSubs = List<String>.from(dynamicSubSubcategories)..sort();
      parts.add('s:${sortedSubSubs.join(",")}');
    }
    if (minPrice != null) parts.add('min:$minPrice');
    if (maxPrice != null) parts.add('max:$maxPrice');
    if (buyerCategory != null) parts.add('bc:$buyerCategory');
    if (buyerSubcategory != null) parts.add('bs:$buyerSubcategory');
    if (category != null) parts.add('cat:$category');
    if (subcategory != null) parts.add('sub:$subcategory');
    if (subSubcategory != null) parts.add('subsub:$subSubcategory');
    parts.add('sort:$sortOption');

    return parts.join('|');
  }

  void reset() {
    category = null;
    subcategory = null;
    subSubcategory = null;
    sortOption = 'date';
    quickFilter = null;
    buyerCategory = null;
    buyerSubcategory = null;
    dynamicBrands = [];
    dynamicColors = [];
    dynamicSubSubcategories = [];
    minPrice = null;
    maxPrice = null;
    lastBackend = TestableSearchBackend.firestore;
  }
}

/// Mirrors Algolia filter building from ShopMarketProvider
class TestableAlgoliaFilterBuilder {
  String? category;
  String? subcategory;
  String? subSubcategory;
  String? buyerCategory;
  String? quickFilter;
  List<String> dynamicBrands = [];
  List<String> dynamicColors = [];
  List<String> dynamicSubSubcategories = [];
  double? minPrice;
  double? maxPrice;

  /// Mirrors _buildAlgoliaFacetFilters from ShopMarketProvider
  List<List<String>> buildFacetFilters() {
    final List<List<String>> groups = [];

    // For Women/Men categories with null subsubcategory, don't add subsubcategory filter
    final bool isGenderedCategory =
        (buyerCategory == 'Women' || buyerCategory == 'Men');

    if (category != null) {
      groups.add(['category_en:$category']);
    }
    if (subcategory != null) {
      groups.add(['subcategory_en:$subcategory']);
    }

    // Only add subsubcategory filter if it's not null
    if (subSubcategory != null) {
      groups.add(['subsubcategory_en:$subSubcategory']);
    }

    // Gender field appears to be without suffix in your data
    if (buyerCategory == 'Women' || buyerCategory == 'Men') {
      groups.add(['gender:$buyerCategory', 'gender:Unisex']);
    }

    // brandModel appears to be without suffix
    if (dynamicBrands.isNotEmpty) {
      groups.add(dynamicBrands.map((b) => 'brandModel:$b').toList());
    }

    // availableColors
    if (dynamicColors.isNotEmpty) {
      groups.add(dynamicColors.map((c) => 'availableColors:$c').toList());
    }

    // For dynamic subsubcategories, use language suffix
    if (dynamicSubSubcategories.isNotEmpty) {
      groups.add(
          dynamicSubSubcategories.map((s) => 'subsubcategory_en:$s').toList());
    }

    if (quickFilter == 'boosted') {
      groups.add(['isBoosted:true']);
    }

    return groups;
  }

  /// Mirrors _buildAlgoliaNumericFilters from ShopMarketProvider
  List<String> buildNumericFilters() {
    final List<String> filters = [];
    if (minPrice != null) filters.add('price>=${minPrice!.floor()}');
    if (maxPrice != null) filters.add('price<=${maxPrice!.ceil()}');

    switch (quickFilter) {
      case 'deals':
        filters.add('discountPercentage>0');
        break;
      case 'trending':
        filters.add('dailyClickCount>=10');
        break;
      case 'fiveStar':
        filters.add('averageRating=5');
        break;
      case 'bestSellers':
      default:
        break;
    }
    return filters;
  }

  void reset() {
    category = null;
    subcategory = null;
    subSubcategory = null;
    buyerCategory = null;
    quickFilter = null;
    dynamicBrands = [];
    dynamicColors = [];
    dynamicSubSubcategories = [];
    minPrice = null;
    maxPrice = null;
  }
}

/// Mirrors Algolia index selection from ShopMarketProvider
class TestableAlgoliaIndexSelector {
  static const String baseIndex = 'shop_products';
  static const Map<String, String> sortReplicas = {
    'date': 'shop_products_createdAt_desc',
    'price_asc': 'shop_products_price_asc',
    'price_desc': 'shop_products_price_desc',
    'alphabetical': 'shop_products_alphabetical',
  };

  /// Mirrors _algoliaIndexForCurrentIndex from ShopMarketProvider
  static String getIndexForSort(String sortOption) {
    final replica = sortReplicas[sortOption];
    return replica ?? baseIndex;
  }
}

/// Mirrors document cache LRU logic from ShopMarketProvider
class TestableDocumentCache<T> {
  final int maxSize;
  final double evictionPercent;
  final Map<String, T> _cache = {};
  final Map<String, DateTime> _timestamps = {};

  /// Track evictions for testing
  final List<String> evictedKeys = [];

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableDocumentCache({
    this.maxSize = 1000,
    this.evictionPercent = 0.1,
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;

  bool containsKey(String key) => _cache.containsKey(key);
  T? operator [](String key) => _cache[key];

  /// Mirrors _docCachePut from ShopMarketProvider
  void put(String id, T item) {
    _cache[id] = item;
    _timestamps[id] = nowProvider();

    if (_cache.length > maxSize) {
      // evict oldest ~10%
      final nEvict = (maxSize * evictionPercent).round();
      final oldest = _timestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in oldest.take(nEvict)) {
        _cache.remove(e.key);
        _timestamps.remove(e.key);
        evictedKeys.add(e.key);
      }
    }
  }

  /// Touch a key to update its timestamp (for LRU)
  void touch(String id) {
    if (_timestamps.containsKey(id)) {
      _timestamps[id] = nowProvider();
    }
  }

  void clear() {
    _cache.clear();
    _timestamps.clear();
    evictedKeys.clear();
  }
}

/// Mirrors main cache TTL logic from ShopMarketProvider
class TestableMainCache<T> {
  final int maxEntries;
  final Duration ttl;
  final Map<String, List<T>> _cache = {};
  final Map<String, DateTime> _timestamps = {};

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableMainCache({
    this.maxEntries = 100,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  int get length => _cache.length;

  bool containsKey(String key) => _cache.containsKey(key);

  /// Check if cache entry is valid (exists and not expired)
  bool isValid(String key) {
    if (!_cache.containsKey(key)) return false;
    final ts = _timestamps[key];
    if (ts == null) return false;
    return nowProvider().difference(ts) < ttl;
  }

  List<T>? getIfValid(String key) {
    if (isValid(key)) return _cache[key];
    return null;
  }

  void put(String key, List<T> items) {
    _cache[key] = items;
    _timestamps[key] = nowProvider();
    _prune();
  }

  /// Mirrors _pruneMainCache from ShopMarketProvider
  void _prune() {
    if (_cache.length > maxEntries) {
      final oldest = _timestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final toRemove = oldest.take(_cache.length - maxEntries);
      for (final e in toRemove) {
        _cache.remove(e.key);
        _timestamps.remove(e.key);
      }
    }
  }

  void clear() {
    _cache.clear();
    _timestamps.clear();
  }
}

/// Mirrors filter cache logic from ShopMarketProvider
class TestableFilterCache<T> {
  final int maxEntries;
  final Duration ttl;
  final Map<String, Map<int, List<T>>> _pageCache = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, DateTime> _timestamps = {};

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableFilterCache({
    this.maxEntries = 20,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  int get length => _pageCache.length;

  bool containsKey(String key) => _pageCache.containsKey(key);

  /// Check if cache entry is valid
  bool isValid(String key) {
    final ts = _timestamps[key];
    if (ts == null) return false;
    return nowProvider().difference(ts) < ttl;
  }

  Map<int, List<T>>? getPages(String key) {
    if (isValid(key)) {
      // Update timestamp on access
      _timestamps[key] = nowProvider();
      return _pageCache[key];
    }
    return null;
  }

  bool? getHasMore(String key) {
    if (isValid(key)) return _hasMore[key];
    return null;
  }

  void put(String key, Map<int, List<T>> pages, bool hasMore) {
    _pageCache[key] = pages;
    _hasMore[key] = hasMore;
    _timestamps[key] = nowProvider();
    _prune();
  }

  /// Mirrors _pruneFilterCache from ShopMarketProvider
  void _prune() {
    final now = nowProvider();

    // First remove expired entries
    final keysToRemove = <String>[];
    _timestamps.forEach((key, timestamp) {
      if (now.difference(timestamp) >= ttl) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _pageCache.remove(key);
      _hasMore.remove(key);
      _timestamps.remove(key);
    }

    // Then apply size limit
    if (_pageCache.length > maxEntries) {
      // Sort by timestamp to remove oldest first
      final sortedEntries = _timestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final entriesToRemove = sortedEntries
          .take(_pageCache.length - maxEntries)
          .map((e) => e.key);

      for (final key in entriesToRemove) {
        _pageCache.remove(key);
        _hasMore.remove(key);
        _timestamps.remove(key);
      }
    }
  }

  void clear() {
    _pageCache.clear();
    _hasMore.clear();
    _timestamps.clear();
  }
}

/// Mirrors page cache pruning from ShopMarketProvider
class TestablePageCache<T> {
  final int maxPages;
  final Map<int, List<T>> _pages = {};
  final Map<int, Object?> _cursors = {};

  /// Track pruned pages for testing
  final List<int> prunedPages = [];

  TestablePageCache({this.maxPages = 5});

  int get length => _pages.length;
  Map<int, List<T>> get pages => Map.unmodifiable(_pages);

  List<T>? operator [](int page) => _pages[page];

  void put(int page, List<T> items, {Object? cursor}) {
    _pages[page] = items;
    if (cursor != null) {
      _cursors[page] = cursor;
    }
    _pruneIfNeeded();
  }

  Object? getCursor(int page) => _cursors[page];

  /// Mirrors _pruneIfNeeded from ShopMarketProvider
  void _pruneIfNeeded() {
    while (_pages.length > maxPages) {
      final oldest = _pages.keys.reduce((a, b) => a < b ? a : b);
      _pages.remove(oldest);
      _cursors.remove(oldest);
      prunedPages.add(oldest);
    }
  }

  void clear() {
    _pages.clear();
    _cursors.clear();
    prunedPages.clear();
  }
}

/// Mirrors dynamic filter state management from ShopMarketProvider
class TestableDynamicFilterState {
  List<String> brands = [];
  List<String> colors = [];
  List<String> subSubcategories = [];
  double? minPrice;
  double? maxPrice;

  /// Mirrors hasDynamicFilters from ShopMarketProvider
  bool get hasDynamicFilters =>
      brands.isNotEmpty ||
      colors.isNotEmpty ||
      subSubcategories.isNotEmpty ||
      minPrice != null ||
      maxPrice != null;

  /// Mirrors activeFiltersCount from ShopMarketProvider
  int get activeFiltersCount {
    int c = 0;
    c += brands.length;
    c += colors.length;
    c += subSubcategories.length;
    if (minPrice != null || maxPrice != null) c++;
    return c;
  }

  /// Mirrors setDynamicFilter (additive mode) from ShopMarketProvider
  bool addFilters({
    List<String>? newBrands,
    List<String>? newColors,
    List<String>? newSubSubcategories,
    double? newMinPrice,
    double? newMaxPrice,
  }) {
    bool changed = false;

    if (newBrands != null) {
      for (final b in newBrands) {
        if (!brands.contains(b)) {
          brands.add(b);
          changed = true;
        }
      }
    }
    if (newColors != null) {
      for (final c in newColors) {
        if (!colors.contains(c)) {
          colors.add(c);
          changed = true;
        }
      }
    }
    if (newSubSubcategories != null) {
      for (final s in newSubSubcategories) {
        if (!subSubcategories.contains(s)) {
          subSubcategories.add(s);
          changed = true;
        }
      }
    }
    if (newMinPrice != minPrice) {
      minPrice = newMinPrice;
      changed = true;
    }
    if (newMaxPrice != maxPrice) {
      maxPrice = newMaxPrice;
      changed = true;
    }

    return changed;
  }

  /// Mirrors setDynamicFilter (replace mode) from ShopMarketProvider
  bool setFilters({
    List<String>? newBrands,
    List<String>? newColors,
    List<String>? newSubSubcategories,
    double? newMinPrice,
    double? newMaxPrice,
  }) {
    bool changed = false;

    if (newBrands != null && !_listEquals(brands, newBrands)) {
      brands = List.from(newBrands);
      changed = true;
    }
    if (newColors != null && !_listEquals(colors, newColors)) {
      colors = List.from(newColors);
      changed = true;
    }
    if (newSubSubcategories != null &&
        !_listEquals(subSubcategories, newSubSubcategories)) {
      subSubcategories = List.from(newSubSubcategories);
      changed = true;
    }
    if (newMinPrice != minPrice) {
      minPrice = newMinPrice;
      changed = true;
    }
    if (newMaxPrice != maxPrice) {
      maxPrice = newMaxPrice;
      changed = true;
    }

    return changed;
  }

  /// Mirrors removeDynamicFilter from ShopMarketProvider
  bool removeFilter({
    String? brand,
    String? color,
    String? subSubcategory,
    bool clearPrice = false,
  }) {
    bool changed = false;

    if (brand != null && brands.contains(brand)) {
      brands.remove(brand);
      changed = true;
    }
    if (color != null && colors.contains(color)) {
      colors.remove(color);
      changed = true;
    }
    if (subSubcategory != null && subSubcategories.contains(subSubcategory)) {
      subSubcategories.remove(subSubcategory);
      changed = true;
    }
    if (clearPrice && (minPrice != null || maxPrice != null)) {
      minPrice = null;
      maxPrice = null;
      changed = true;
    }

    return changed;
  }

  /// Mirrors clearDynamicFilters from ShopMarketProvider
  bool clearAll() {
    if (!hasDynamicFilters) return false;

    brands.clear();
    colors.clear();
    subSubcategories.clear();
    minPrice = null;
    maxPrice = null;
    return true;
  }

  void reset() {
    brands = [];
    colors = [];
    subSubcategories = [];
    minPrice = null;
    maxPrice = null;
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Mirrors _listEquals helper from ShopMarketProvider
class TestableListUtils {
  /// Mirrors _listEquals from ShopMarketProvider
  static bool listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Mirrors _chunks from ShopMarketProvider
  static Iterable<List<T>> chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }
}

/// Mirrors _rebuildAllLoaded deduplication from ShopMarketProvider
class TestableProductDeduplicator {
  /// Mirrors _rebuildAllLoaded from ShopMarketProvider
  /// Takes page cache and returns deduplicated, ordered list
  static List<T> rebuildAllLoaded<T>(
    Map<int, List<T>> pageCache,
    String Function(T) getId,
  ) {
    final sortedPages = pageCache.keys.toList()..sort();
    final seen = <String>{};
    final combined = <T>[];

    for (final i in sortedPages) {
      for (final item in pageCache[i]!) {
        final id = getId(item);
        if (seen.add(id)) combined.add(item);
      }
    }

    return combined;
  }
}