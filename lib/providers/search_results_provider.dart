import 'package:flutter/foundation.dart';
import '../models/product_summary.dart';
import '../services/typesense_service.dart';

class SearchResultsProvider with ChangeNotifier {
  final TypeSenseService _searchService;

  SearchResultsProvider({required TypeSenseService searchService})
      : _searchService = searchService;

  // ──────────────────────────────────────────────────────────────────────────
  // EXISTING STATE (unfiltered path)
  // ──────────────────────────────────────────────────────────────────────────
  List<ProductSummary> _rawProducts = [];

  List<ProductSummary> _filteredProducts = [];
  List<ProductSummary> get filteredProducts =>
      List.unmodifiable(_filteredProducts);

  String? _currentFilter;
  String? get currentFilter => _currentFilter;

  String _sortOption = 'None';
  String get sortOption => _sortOption;

  // ──────────────────────────────────────────────────────────────────────────
  // DYNAMIC FILTER STATE
  // ──────────────────────────────────────────────────────────────────────────
  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  final Map<String, List<String>> _dynamicSpecFilters = {};
  double? _minPrice;
  double? _maxPrice;
  double? _minRating;

  List<String> get dynamicBrands => List.unmodifiable(_dynamicBrands);
  List<String> get dynamicColors => List.unmodifiable(_dynamicColors);
  Map<String, List<String>> get dynamicSpecFilters =>
      Map.unmodifiable(_dynamicSpecFilters.map(
          (k, v) => MapEntry(k, List<String>.unmodifiable(v))));
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;
  double? get minRating => _minRating;

  bool get hasDynamicFilters =>
      _dynamicBrands.isNotEmpty ||
      _dynamicColors.isNotEmpty ||
      _dynamicSpecFilters.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null ||
      _minRating != null;

  int get activeFiltersCount {
    int c = 0;
    c += _dynamicBrands.length;
    c += _dynamicColors.length;
    for (final vals in _dynamicSpecFilters.values) {
      c += vals.length;
    }
    if (_minPrice != null || _maxPrice != null) c++;
    if (_minRating != null) c++;
    return c;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SPEC FACETS
  // ──────────────────────────────────────────────────────────────────────────
  Map<String, List<Map<String, dynamic>>> _specFacets = {};
  Map<String, List<Map<String, dynamic>>> get specFacets =>
      Map.unmodifiable(_specFacets);

  /// Fetch spec facets scoped to the given search query.
  Future<void> fetchSpecFacets(String query) async {
    try {
      final result = await _searchService.fetchSpecFacets(
        indexName: 'shop_products',
        query: query,
      );
      _specFacets = result;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching search spec facets: $e');
      _specFacets = {};
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UNFILTERED PATH (existing)
  // ──────────────────────────────────────────────────────────────────────────
  void setRawProducts(List<ProductSummary> products) {
    _rawProducts = List.from(products);
    _applyFiltersAndSort();
  }

  void addMoreProducts(List<ProductSummary> products) {
    _rawProducts.addAll(products);
    _applyFiltersAndSort();
  }

  void clearProducts() {
    _rawProducts.clear();
    _filteredProducts.clear();
    notifyListeners();
  }

  void setFilter(String? filter) {
    if (_currentFilter == filter) return;
    _currentFilter = filter;
    _applyFiltersAndSort();
  }

  void setSortOption(String sortOption) {
    if (_sortOption == sortOption) return;
    _sortOption = sortOption;
    _applyFiltersAndSort();
  }

  void _applyFiltersAndSort() {
    List<ProductSummary> result = List.from(_rawProducts);
    _applySorting(result);
    // Only prioritize boosted in default (relevance) mode.
    // When user explicitly sorts (e.g. by price), their intent takes priority.
    if (_sortOption == 'None') {
      _prioritizeBoosted(result);
    }
    _filteredProducts = result;
    notifyListeners();
  }

  void _applySorting(List<ProductSummary> products) {
    switch (_sortOption) {
      case 'Alphabetical':
        products.sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        break;
      case 'Date':
        products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'Price Low to High':
        products.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Price High to Low':
        products.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'None':
      default:
        break;
    }
  }

  void _prioritizeBoosted(List<ProductSummary> products) {
    products.sort((a, b) {
      if (a.isBoosted && !b.isBoosted) return -1;
      if (!a.isBoosted && b.isBoosted) return 1;
      return 0;
    });
  }

  List<ProductSummary> get boostedProducts {
    return _filteredProducts.where((p) => p.isBoosted).toList();
  }

  bool get isEmpty => _filteredProducts.isEmpty;
  bool get hasNoData => _rawProducts.isEmpty;

  // ──────────────────────────────────────────────────────────────────────────
  // FILTERED PATH (Typesense direct)
  // ──────────────────────────────────────────────────────────────────────────

  /// Convert sort UI option to Typesense sort code.
  String _toSortCode(String uiOption) {
    switch (uiOption) {
      case 'Alphabetical':
        return 'alphabetical';
      case 'Price Low to High':
        return 'price_asc';
      case 'Price High to Low':
        return 'price_desc';
      case 'Date':
        return 'date';
      default:
        return 'date';
    }
  }

  /// Build facet filter groups from current dynamic filter state.
  List<List<String>> _buildFacetFilters() {
    final groups = <List<String>>[];

    if (_dynamicBrands.isNotEmpty) {
      groups.add(_dynamicBrands.map((b) => 'brandModel:$b').toList());
    }
    if (_dynamicColors.isNotEmpty) {
      groups.add(_dynamicColors.map((c) => 'availableColors:$c').toList());
    }
    for (final entry in _dynamicSpecFilters.entries) {
      if (entry.value.isNotEmpty) {
        groups.add(entry.value.map((v) => '${entry.key}:$v').toList());
      }
    }

    return groups;
  }

  /// Build numeric filter strings for price range and rating.
  List<String> _buildNumericFilters() {
    final filters = <String>[];
    if (_minPrice != null) filters.add('price>=${_minPrice!.floor()}');
    if (_maxPrice != null) filters.add('price<=${_maxPrice!.ceil()}');
    if (_minRating != null) filters.add('averageRating>=${_minRating!}');
    return filters;
  }

  /// Fetch a page of filtered results from Typesense (shop_products only).
  Future<List<ProductSummary>> fetchFilteredPage({
    required String query,
    required int page,
    int hitsPerPage = 50,
  }) async {
    final facetFilters = _buildFacetFilters();
    final numericFilters = _buildNumericFilters();

    try {
      final res = await _searchService.searchIdsWithFacets(
        indexName: 'shop_products',
        query: query,
        page: page,
        hitsPerPage: hitsPerPage,
        facetFilters: facetFilters,
        numericFilters: numericFilters,
        sortOption: _toSortCode(_sortOption),
      );

      return res.hits.map((hit) => ProductSummary.fromTypeSense(hit)).toList();
    } catch (e) {
      debugPrint('Filtered search error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DYNAMIC FILTER MUTATIONS
  // ──────────────────────────────────────────────────────────────────────────

  void setDynamicFilter({
    List<String>? brands,
    List<String>? colors,
    Map<String, List<String>>? specFilters,
    double? minPrice,
    double? maxPrice,
    double? minRating,
  }) {
    if (brands != null) _dynamicBrands = List.from(brands);
    if (colors != null) _dynamicColors = List.from(colors);
    if (specFilters != null) {
      _dynamicSpecFilters.clear();
      for (final entry in specFilters.entries) {
        if (entry.value.isNotEmpty) {
          _dynamicSpecFilters[entry.key] = List.from(entry.value);
        }
      }
    }
    _minPrice = minPrice;
    _maxPrice = maxPrice;
    _minRating = minRating;
    notifyListeners();
  }

  void removeDynamicFilter({
    String? brand,
    String? color,
    String? specField,
    String? specValue,
    bool clearPrice = false,
    bool clearRating = false,
  }) {
    if (brand != null) _dynamicBrands.remove(brand);
    if (color != null) _dynamicColors.remove(color);
    if (specField != null && specValue != null) {
      final list = _dynamicSpecFilters[specField];
      if (list != null) {
        list.remove(specValue);
        if (list.isEmpty) _dynamicSpecFilters.remove(specField);
      }
    }
    if (clearPrice) {
      _minPrice = null;
      _maxPrice = null;
    }
    if (clearRating) {
      _minRating = null;
    }
    notifyListeners();
  }

  void clearDynamicFilters() {
    _dynamicBrands.clear();
    _dynamicColors.clear();
    _dynamicSpecFilters.clear();
    _minPrice = null;
    _maxPrice = null;
    _minRating = null;
    notifyListeners();
  }
}
