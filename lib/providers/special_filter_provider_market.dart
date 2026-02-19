import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import '../models/product_summary.dart';  
import '../models/dynamic_filter.dart';

import 'package:flutter/foundation.dart';

class SpecialFilterProviderMarket with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<ProductSummary>>? _productsStreamSubscription;

  // ValueNotifiers for frequently accessed state
  final ValueNotifier<String?> _specialFilterNotifier = ValueNotifier(null);
  final ValueNotifier<String?> _dynamicSubsubcategoryNotifier =
      ValueNotifier(null);
  final ValueNotifier<String?> _dynamicBrandNotifier = ValueNotifier(null);
  final ValueNotifier<List<String>> _dynamicColorsNotifier = ValueNotifier([]);
  final ValueNotifier<String> _searchTermNotifier = ValueNotifier('');
  final ValueNotifier<String?> _selectedFilterNotifier = ValueNotifier(null);

  // Expose ValueNotifiers for granular listening
  ValueListenable<String?> get specialFilterListenable =>
      _specialFilterNotifier;
  ValueListenable<String?> get dynamicSubsubcategoryListenable =>
      _dynamicSubsubcategoryNotifier;
  ValueListenable<String?> get dynamicBrandListenable => _dynamicBrandNotifier;
  ValueListenable<List<String>> get dynamicColorsListenable =>
      _dynamicColorsNotifier;
  ValueListenable<String> get searchTermListenable => _searchTermNotifier;
  ValueListenable<String?> get selectedFilterListenable =>
      _selectedFilterNotifier;

  // Getters that access ValueNotifier values
  String? get specialFilter => _specialFilterNotifier.value;
  String? get dynamicSubsubcategory => _dynamicSubsubcategoryNotifier.value;
  String? get dynamicBrand => _dynamicBrandNotifier.value;
  List<String> get dynamicColors => _dynamicColorsNotifier.value;
  String get searchTerm => _searchTermNotifier.value;
  String? get selectedFilter => _selectedFilterNotifier.value;

  // Loading state ValueNotifiers for UI responsiveness
  final Map<String, ValueNotifier<bool>> _filterLoadingNotifiers = {};
  final Map<String, ValueNotifier<bool>> _filterLoadingMoreNotifiers = {};
  final Map<String, ValueNotifier<bool>> _filterHasMoreNotifiers = {};

  // Subcategory-specific ValueNotifier management
  final Map<String, ValueNotifier<bool>> _subcategoryLoadingNotifiers = {};
  final Map<String, ValueNotifier<bool>> _subcategoryLoadingMoreNotifiers = {};
  final Map<String, ValueNotifier<bool>> _subcategoryHasMoreNotifiers = {};

  Future<List<ProductSummary>> fetchProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final products = <ProductSummary>[];

    // Flutter Firestore: Use whereIn queries (max 30 per query)
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.skip(i).take(30).toList();

      final snapshot = await _firestore
          .collection('shop_products')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        if (doc.exists) {
          products.add(ProductSummary.fromDocument(doc));
        }
      }
    }

    // Preserve original order (whereIn doesn't guarantee order)
    final productMap = {for (var p in products) p.id: p};
    return ids.map((id) => productMap[id]).whereType<ProductSummary>().toList();
  }

  String? _currentCategory;
  String? _currentSubcategoryId;
  String _subcategorySortOption =
      'date'; // Default sort option for subcategory screens

  static const Duration _cacheTTL = Duration(minutes: 5);
  final Map<String, DateTime> _lastFetched = {};

  bool _isStale(String filterType) {
    final last =
        _lastFetched[filterType] ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.now().difference(last) > _cacheTTL;
  }

  static const int MAX_CACHE_SIZE = 30;
  static const int MAX_PRODUCTS_PER_FILTER = 500;
  static const int MAX_NOTIFIERS_PER_TYPE = 20;

  // Enhanced ValueNotifier getters for loading states
  ValueListenable<bool> getFilterLoadingListenable(String filterType) {
    _filterLoadingNotifiers[filterType] ??= ValueNotifier(false);
    return _filterLoadingNotifiers[filterType]!;
  }

  ValueListenable<bool> getFilterLoadingMoreListenable(String filterType) {
    _filterLoadingMoreNotifiers[filterType] ??= ValueNotifier(false);
    return _filterLoadingMoreNotifiers[filterType]!;
  }

  ValueListenable<bool> getFilterHasMoreListenable(String filterType) {
    _filterHasMoreNotifiers[filterType] ??= ValueNotifier(true);
    return _filterHasMoreNotifiers[filterType]!;
  }

  // Expose subcategory ValueNotifiers
  ValueListenable<bool> getSubcategoryLoadingListenable(
      String category, String subcategoryId) {
    final key = '$category|$subcategoryId';
    _subcategoryLoadingNotifiers[key] ??= ValueNotifier(false);
    return _subcategoryLoadingNotifiers[key]!;
  }

  ValueListenable<bool> getSubcategoryLoadingMoreListenable(
      String category, String subcategoryId) {
    final key = '$category|$subcategoryId';
    _subcategoryLoadingMoreNotifiers[key] ??= ValueNotifier(false);
    return _subcategoryLoadingMoreNotifiers[key]!;
  }

  ValueListenable<bool> getSubcategoryHasMoreListenable(
      String category, String subcategoryId) {
    final key = '$category|$subcategoryId';
    _subcategoryHasMoreNotifiers[key] ??= ValueNotifier(true);
    return _subcategoryHasMoreNotifiers[key]!;
  }

  // Getter for subcategory sort option
  String get subcategorySortOption => _subcategorySortOption;

  // Setter for subcategory sort option
  void setSubcategorySortOption(String sortOption) {
    if (_subcategorySortOption != sortOption) {
      // Save snapshot BEFORE changing sort so we can restore on toggle-back
      if (_currentCategory != null && _currentSubcategoryId != null) {
        final key = _getSubcategoryKey(
            _currentCategory!, _currentSubcategoryId!,
            gender: _currentGender);
        _saveSubcategorySnapshot(key);
      }
      _subcategorySortOption = sortOption;
      notifyListeners();
    }
  }

  // Optimized setter methods using ValueNotifiers
  void setDynamicFilter({
    String? brand,
    List<String>? colors,
    String? subsubcategory,
  }) {
    bool hasChanges = false;

    if (_dynamicBrandNotifier.value != brand) {
      _dynamicBrandNotifier.value = brand;
      hasChanges = true;
    }

    final newColors = colors ?? [];
    if (_dynamicColorsNotifier.value != newColors) {
      _dynamicColorsNotifier.value = newColors;
      hasChanges = true;
    }

    if (_dynamicSubsubcategoryNotifier.value != subsubcategory) {
      _dynamicSubsubcategoryNotifier.value = subsubcategory;
      hasChanges = true;
    }

    if (hasChanges) {
      print(
          'SpecialFilterProviderMarket: Set dynamic filters - brand: $brand, colors: $newColors, subsubcategory: $subsubcategory');
      notifyListeners();
    }
  }

  void setSearchTerm(String term) {
    if (_searchTermNotifier.value != term) {
      _searchTermNotifier.value = term;
      print('SpecialFilterProviderMarket: Set search term: $term');
      notifyListeners();
    }
  }

  void cleanupOrphanedData(Set<String> validFilterTypes) {
    // Clean up product data for non-existent filters
    final keysToRemove = <String>[];
    _filterProducts.keys.forEach((key) {
      if (!validFilterTypes.contains(key)) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _filterProducts.remove(key);
      _filterProductIds.remove(key);
      _subcategoryProducts.remove(key);
      _currentPages.remove(key);
      _hasMore.remove(key);
      _isLoadingMore.remove(key);
      _lastDocuments.remove(key);
      _isFiltering.remove(key);
    }
  }

  Future<void> setQuickFilter(String? filterKey) async {
    if (_selectedFilterNotifier.value == filterKey) return;

    if (_currentCategory != null && _currentSubcategoryId != null) {
      // Save snapshot BEFORE changing quick filter so the key reflects OLD state
      final key = _getSubcategoryKey(
          _currentCategory!, _currentSubcategoryId!,
          gender: _currentGender);
      _saveSubcategorySnapshot(key);

      await fetchSubcategoryProducts(
        _currentCategory!,
        _currentSubcategoryId!,
        selectedFilter: filterKey,
        gender: _currentGender,
      );
    } else {
      _selectedFilterNotifier.value = filterKey;
      notifyListeners();
    }
  }

  // Helper methods for ValueNotifier management
  void _updateFilterLoadingState(String filterType, bool isLoading) {
    _isFiltering[filterType] = isLoading;
    _filterLoadingNotifiers[filterType]?.value = isLoading;
  }

  void _updateFilterLoadingMoreState(String filterType, bool isLoadingMore) {
    _isLoadingMore[filterType] = isLoadingMore;
    _filterLoadingMoreNotifiers[filterType]?.value = isLoadingMore;
  }

  void _updateFilterHasMoreState(String filterType, bool hasMore) {
    _hasMore[filterType] = hasMore;
    _filterHasMoreNotifiers[filterType]?.value = hasMore;
  }

  void _updateSubcategoryLoadingState(String key, bool isLoading) {
    _specificSubcategoryLoading[key] = isLoading;
    _subcategoryLoadingNotifiers[key]?.value = isLoading;
  }

  void _updateSubcategoryLoadingMoreState(String key, bool isLoadingMore) {
    _specificSubcategoryLoadingMore[key] = isLoadingMore;
    _subcategoryLoadingMoreNotifiers[key]?.value = isLoadingMore;
  }

  void _updateSubcategoryHasMoreState(String key, bool hasMore) {
    _specificSubcategoryHasMore[key] = hasMore;
    _subcategoryHasMoreNotifiers[key]?.value = hasMore;
  }

  // Store products for each filter type (including dynamic filters)
  final Map<String, List<ProductSummary>> _filterProducts = {};
  List<ProductSummary> getProducts(String filterType) =>
      _filterProducts[filterType] ?? [];

  // Store product IDs for each filter type
  final Map<String, Set<String>> _filterProductIds = {};

  // Store subcategories and their products for category filters
  final Map<String, List<Map<String, dynamic>>> _subcategoryProducts = {};
  List<Map<String, dynamic>> getSubcategoryProducts(String filterType) =>
      _subcategoryProducts[filterType] ?? [];

  // Store products for specific category|subcategoryId
  final Map<String, List<ProductSummary>> _specificSubcategoryProducts = {};
  final Map<String, Set<String>> _specificSubcategoryProductIds = {};
  final Map<String, int> _specificSubcategoryPages = {};
  final Map<String, bool> _specificSubcategoryLoading = {};
  final Map<String, bool> _specificSubcategoryLoadingMore = {};
  final Map<String, bool> _specificSubcategoryHasMore = {};
  final Map<String, DocumentSnapshot?> _specificSubcategoryLastDocs = {};

  // ──────────────────────────────────────────────────────────────────────────
  // DUAL-QUERY STATE (for gender + colors Firestore conflict resolution)
  // Firestore forbids whereIn + arrayContainsAny in the same query.
  // When both gender and colors are active we split into two parallel queries:
  //   Q1: gender == 'Women' + arrayContainsAny(colors)
  //   Q2: gender == 'Unisex' + arrayContainsAny(colors)
  // Each needs its own pagination cursor and hasMore flag.
  // ──────────────────────────────────────────────────────────────────────────
  final Map<String, DocumentSnapshot?> _dualQueryUnisexLastDocs = {};
  final Map<String, bool> _dualQueryGenderHasMore = {};
  final Map<String, bool> _dualQueryUnisexHasMore = {};

  /// Returns true when the combination of active filters would cause a
  /// Firestore conflict (whereIn for gender + arrayContainsAny for colors).
  bool _needsDualGenderQuery(String? gender) {
    return gender != null && gender.isNotEmpty && dynamicColors.isNotEmpty;
  }

  // Subcategory snapshot cache — for instant restore on filter/sort/quickFilter toggle.
  // Keyed by _buildSubcategorySnapshotKey(), stores full subcategory state per filter combo.
  static const Duration _snapshotTtl = Duration(minutes: 5);
  static const int _maxSnapshotEntries = 20;
  final Map<String, List<ProductSummary>> _snapshotProducts = {};
  final Map<String, Set<String>> _snapshotProductIds = {};
  final Map<String, int> _snapshotPages = {};
  final Map<String, bool> _snapshotHasMore = {};
  final Map<String, DocumentSnapshot?> _snapshotLastDocs = {};
  final Map<String, DateTime> _snapshotTs = {};

  final BehaviorSubject<List<String>> _productIdsSubject =
      BehaviorSubject<List<String>>.seeded([]);

  // Pagination and loading states per filter (dynamic support)
  final Map<String, int> _currentPages = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, bool> _isLoadingMore = {};
  final Map<String, DocumentSnapshot?> _lastDocuments = {};

  bool hasMore(String filterType) => _hasMore[filterType] ?? true;
  bool isLoadingMore(String filterType) => _isLoadingMore[filterType] ?? false;

  final Map<String, List<ProductSummary>> _productCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, bool> _isFiltering = {};

  bool isFiltering(String filterType) => _isFiltering[filterType] ?? false;

  // Initialize filter states for dynamic filters
  void _initializeFilterState(String filterType) {
    if (_filterLoadingNotifiers.length >= MAX_NOTIFIERS_PER_TYPE) {
      // Find and remove oldest non-permanent filter
      final permanentFilters = {
        'Home',
        'Women',
        'Men',
        'Electronics',
        'Home & Furniture',
        'Mother & Child'
      };
      final oldestKey = _filterLoadingNotifiers.keys
          .firstWhere((k) => !permanentFilters.contains(k), orElse: () => '');

      if (oldestKey.isNotEmpty) {
        removeFilterNotifiers(oldestKey);
      }
    }
    _filterProducts[filterType] ??= [];
    _filterProductIds[filterType] ??= <String>{};
    _subcategoryProducts[filterType] ??= [];
    _currentPages[filterType] ??= 0;
    _hasMore[filterType] ??= true;
    _isLoadingMore[filterType] ??= false;
    _lastDocuments[filterType] ??= null;
    _isFiltering[filterType] ??= false;
  }

  // Enhanced fetch method that handles dynamic filters
  Future<void> fetchProducts({
    required String filterType,
    int page = 0,
    int limit = 20,
    DynamicFilter? dynamicFilter,
  }) async {
    _initializeFilterState(filterType);

    if (filterType.isEmpty) {
      _filterProducts[filterType] = [];
      _filterProductIds[filterType] = <String>{};
      _subcategoryProducts[filterType] = [];
      _updateFilterHasMoreState(filterType, false);
      _updateFilterLoadingState(filterType, false);
      notifyListeners();
      return;
    }

    if (_isFiltering[filterType] == true) return;
    _updateFilterLoadingState(filterType, true);
    notifyListeners();

    final cacheKey = '$filterType|$page';
    final now = DateTime.now();
    final cachedTime = _cacheTimestamps[cacheKey];
    final isCacheValid =
        cachedTime != null && now.difference(cachedTime) < _cacheTTL;

    if (isCacheValid &&
        !_isStale(filterType) &&
        _productCache.containsKey(cacheKey)) {
      final cachedProducts = _productCache[cacheKey]!;
      if (page == 0) {
        _filterProducts[filterType] = [];
        _filterProductIds[filterType] = <String>{};
        _subcategoryProducts[filterType] = [];
      }

      final currentProducts = _filterProducts[filterType] ?? [];
      final currentProductIds = _filterProductIds[filterType] ?? <String>{};

      for (var product in cachedProducts) {
        if (currentProductIds.add(product.id)) {
          currentProducts.add(product);
        }
      }

      _filterProducts[filterType] = currentProducts;
      _filterProductIds[filterType] = currentProductIds;

      _updateFilterHasMoreState(filterType, cachedProducts.length >= limit);
      if (filterType == specialFilter) {
        _productIdsSubject.add(currentProducts.map((p) => p.id).toList());
      }
      _updateFilterLoadingState(filterType, false);
      notifyListeners();
      return;
    }

    try {
      if (dynamicFilter != null) {
        await _fetchDynamicFilterProducts(
            filterType, page, limit, dynamicFilter);
      } else if ([
        'Women',
        'Men',
        'Electronics',
        'Home & Furniture',
        'Mother & Child'
      ].contains(filterType)) {
        await _fetchSubcategoryProducts(filterType, page, limit);
      } else {
        await _fetchStaticFilterProducts(filterType, page, limit);
      }
    } catch (e) {
      debugPrint('Error fetching products for $filterType: $e');
      _updateFilterHasMoreState(filterType, false);
    } finally {
      _updateFilterLoadingState(filterType, false);
      notifyListeners();
    }
  }

  // Fetch products for dynamic filters
  Future<void> _fetchDynamicFilterProducts(
    String filterType,
    int page,
    int limit,
    DynamicFilter dynamicFilter,
  ) async {
    const int MAX_RETRIES = 3;
    const int MAX_PRODUCTS_PER_FILTER = 1000;
    int retryCount = 0;

    while (retryCount < MAX_RETRIES) {
      try {
        if (filterType.isEmpty || limit <= 0) {
          throw ArgumentError(
              'Invalid parameters: filterType=$filterType, limit=$limit');
        }

        Query query =
            _firestore.collection(dynamicFilter.collection ?? 'shop_products');

        switch (dynamicFilter.type) {
          case FilterType.attribute:
            if (dynamicFilter.attribute != null &&
                dynamicFilter.operator != null &&
                dynamicFilter.attributeValue != null) {
              dynamic filterValue = dynamicFilter.attributeValue;

              if (_isNumericField(dynamicFilter.attribute!)) {
                filterValue = _convertToNumber(filterValue);
              }

              query = _applyAttributeFilter(query, dynamicFilter.attribute!,
                  dynamicFilter.operator!, filterValue);
            }
            break;

          case FilterType.query:
            if (dynamicFilter.queryConditions != null &&
                dynamicFilter.queryConditions!.isNotEmpty) {
              for (final condition in dynamicFilter.queryConditions!) {
                dynamic conditionValue = condition.value;

                if (_isNumericField(condition.field)) {
                  conditionValue = _convertToNumber(conditionValue);
                }

                query = _applyAttributeFilter(
                    query, condition.field, condition.operator, conditionValue);
              }
            }
            break;

          case FilterType.collection:
            break;
        }

        query = _applyAdditionalFilters(query);
        query = _applySorting(query, dynamicFilter);
        query = _applyPagination(query, filterType, page);

        final effectiveLimit = (dynamicFilter.limit ?? limit).clamp(1, 100);
        query = query.limit(effectiveLimit);

        final snapshot = await query.get().timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException(
                  'Query timeout', const Duration(seconds: 10)),
            );

        var newProducts = snapshot.docs
            .map((doc) {
              try {
                return ProductSummary.fromDocument(doc);
              } catch (e) {
                debugPrint(
                    'Warning: Failed to parse product document ${doc.id}: $e');
                return null;
              }
            })
            .whereType<ProductSummary>()
            .where((product) => _isValidProduct(product))
            .toList();

        if (newProducts.length > MAX_PRODUCTS_PER_FILTER) {
          newProducts = newProducts.take(MAX_PRODUCTS_PER_FILTER).toList();
        }

        _updatePaginationState(snapshot, filterType, page);
        _updateProductCollections(newProducts, filterType, page);
        _cacheResults(newProducts, filterType, page);
        _updateProductStream(filterType);
        _updateFilterHasMoreState(
            filterType, newProducts.length >= effectiveLimit);

        break;
      } catch (e) {
        retryCount++;

        if (retryCount >= MAX_RETRIES) {
          await _handleFetchFailure(filterType, page, e);
          break;
        }

        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }

    _enforceMaxCacheSize();
  }

  bool _isNumericField(String fieldName) {
    return [
      'averageRating',
      'price',
      'discountPercentage',
      'stockQuantity',
      'purchaseCount'
    ].contains(fieldName);
  }

  dynamic _convertToNumber(dynamic value) {
    if (value is String) {
      return double.tryParse(value) ?? int.tryParse(value) ?? value;
    }
    return value;
  }

  Query _applyAttributeFilter(
      Query query, String attribute, String operator, dynamic value) {
    switch (operator) {
      case '==':
        return query.where(attribute, isEqualTo: value);
      case '!=':
        return query.where(attribute, isNotEqualTo: value);
      case '>':
        return query.where(attribute, isGreaterThan: value);
      case '>=':
        return query.where(attribute, isGreaterThanOrEqualTo: value);
      case '<':
        return query.where(attribute, isLessThan: value);
      case '<=':
        return query.where(attribute, isLessThanOrEqualTo: value);
      case 'array-contains':
        return query.where(attribute, arrayContains: value);
      case 'array-contains-any':
        return query.where(attribute, arrayContainsAny: value);
      case 'in':
        return query.where(attribute, whereIn: value);
      case 'not-in':
        return query.where(attribute, whereNotIn: value);
      default:
        return query.where(attribute, isEqualTo: value);
    }
  }

  Query _applyAdditionalFilters(Query query) {
    if (dynamicBrand != null && dynamicBrand!.isNotEmpty) {
      query = query.where('brandModel', isEqualTo: dynamicBrand);
    }

    if (searchTerm.isNotEmpty && searchTerm.length >= 2) {
      query = query
          .where('title', isGreaterThanOrEqualTo: searchTerm)
          .where('title', isLessThanOrEqualTo: searchTerm + '\uf8ff');
    }

    return query;
  }

  Query _applySorting(Query query, DynamicFilter dynamicFilter) {
    try {
      if (dynamicFilter.sortBy != null && dynamicFilter.sortBy!.isNotEmpty) {
        return query.orderBy(
          dynamicFilter.sortBy!,
          descending: dynamicFilter.sortOrder == 'desc',
        );
      } else {
        return query.orderBy('createdAt', descending: true);
      }
    } catch (e) {
      return query.orderBy('createdAt', descending: true);
    }
  }

  /// Apply sorting for subcategory screens based on selected sort option
  Query _applySubcategorySorting(Query query) {
    try {
      switch (_subcategorySortOption) {
        case 'alphabetical':
          // Sort by title alphabetically
          return query.orderBy('title', descending: false);
        case 'price_asc':
          // Sort by price low to high
          return query.orderBy('price', descending: false);
        case 'price_desc':
          // Sort by price high to low
          return query.orderBy('price', descending: true);
        case 'date':
        default:
          // Default: Sort by promotionScore and createdAt (newest first)
          return query
              .orderBy('promotionScore', descending: true)
              .orderBy('createdAt', descending: true);
      }
    } catch (e) {
      return query
          .orderBy('promotionScore', descending: true)
          .orderBy('createdAt', descending: true);
    }
  }

  Query _applyPagination(Query query, String filterType, int page) {
    if (page == 0) {
      _lastDocuments[filterType] = null;
    } else if (page > 0 && _lastDocuments[filterType] != null) {
      query = query.startAfterDocument(_lastDocuments[filterType]!);
    } else if (page > 0) {
      debugPrint(
          'Warning: Pagination requested but no last document available');
    }

    return query;
  }

  bool _isValidProduct(ProductSummary product) {
    return product.id.isNotEmpty &&
        product.productName.isNotEmpty &&
        product.price >= 0 &&
        product.averageRating >= 0 &&
        product.averageRating <= 5;
  }

  void _updatePaginationState(
      QuerySnapshot snapshot, String filterType, int page) {
    if (snapshot.docs.isNotEmpty) {
      _lastDocuments[filterType] = snapshot.docs.last;
    }
  }

  void _updateProductCollections(
      List<ProductSummary> newProducts, String filterType, int page) {
    if (page == 0) {
      _filterProducts[filterType] = [];
      _filterProductIds[filterType] = <String>{};
    }

    final currentProducts = _filterProducts[filterType] ?? [];
    final currentProductIds = _filterProductIds[filterType] ?? <String>{};

    for (var product in newProducts) {
      if (currentProductIds.add(product.id)) {
        currentProducts.add(product);
      }
    }

    _filterProducts[filterType] = currentProducts;
    _filterProductIds[filterType] = currentProductIds;
  }

  void _cacheResults(List<ProductSummary> newProducts, String filterType, int page) {
    final cacheKey = '$filterType|$page';
    _productCache[cacheKey] = List.from(newProducts);
    _cacheTimestamps[cacheKey] = DateTime.now();
    _lastFetched[filterType] = DateTime.now();
  }

  void _updateProductStream(String filterType) {
    if (filterType == specialFilter) {
      final products = _filterProducts[filterType] ?? [];
      _productIdsSubject.add(products.map((p) => p.id).toList());
    }
  }

  Future<void> _handleFetchFailure(
      String filterType, int page, dynamic error) async {
    final cacheKey = '$filterType|$page';
    final fallbackProducts = _productCache[cacheKey];

    if (fallbackProducts != null && fallbackProducts.isNotEmpty) {
      if (page == 0) {
        _filterProducts[filterType] = [];
        _filterProductIds[filterType] = <String>{};
      }

      final currentProducts = _filterProducts[filterType] ?? [];
      final currentProductIds = _filterProductIds[filterType] ?? <String>{};

      for (var product in fallbackProducts) {
        if (currentProductIds.add(product.id)) {
          currentProducts.add(product);
        }
      }

      _filterProducts[filterType] = currentProducts;
      _filterProductIds[filterType] = currentProductIds;

      _updateProductStream(filterType);
    } else {
      if (page == 0) {
        _filterProducts[filterType] = [];
        _filterProductIds[filterType] = <String>{};
        _updateProductStream(filterType);
      }
    }

    _updateFilterHasMoreState(filterType, false);
  }

  void _enforceMaxCacheSize() {
    const int MAX_CACHE_SIZE = 50;

    while (_productCache.length > MAX_CACHE_SIZE) {
      final oldestEntry = _cacheTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b);

      _productCache.remove(oldestEntry.key);
      _cacheTimestamps.remove(oldestEntry.key);
    }
  }

  // Fetch products for static filters (legacy method - no longer used with current filters)
  Future<void> _fetchStaticFilterProducts(
      String filterType, int page, int limit) async {
    Query query = _firestore.collection('shop_products');

    // No static filters currently defined - all filters are now category-based or dynamic
    // This method is kept for backward compatibility but can be removed if not needed

    if (dynamicBrand != null) {
      query = query.where('brandModel', isEqualTo: dynamicBrand);
    }
    if (searchTerm.isNotEmpty) {
      query = query
          .where('title', isGreaterThanOrEqualTo: searchTerm)
          .where('title', isLessThanOrEqualTo: searchTerm + '\uf8ff');
    }

    if (page > 0 && _lastDocuments[filterType] != null) {
      query = query.startAfterDocument(_lastDocuments[filterType]!);
    }
    query = query.limit(limit);

    final snapshot = await query.get();
    var newProducts =
        snapshot.docs.map((doc) => ProductSummary.fromDocument(doc)).toList();

    if (snapshot.docs.isNotEmpty) {
      _lastDocuments[filterType] = snapshot.docs.last;
    }

    if (page == 0) {
      _filterProducts[filterType] = [];
      _filterProductIds[filterType] = <String>{};
    }

    final currentProducts = _filterProducts[filterType] ?? [];
    final currentProductIds = _filterProductIds[filterType] ?? <String>{};

    for (var product in newProducts) {
      if (currentProductIds.add(product.id)) {
        currentProducts.add(product);
      }
    }

    _filterProducts[filterType] = currentProducts;
    _filterProductIds[filterType] = currentProductIds;

    final cacheKey = '$filterType|$page';
    _productCache[cacheKey] = List.from(newProducts);
    _cacheTimestamps[cacheKey] = DateTime.now();
    _lastFetched[filterType] = DateTime.now();

    if (filterType == specialFilter) {
      _productIdsSubject.add(currentProducts.map((p) => p.id).toList());
    }
    _updateFilterHasMoreState(filterType, newProducts.length >= limit);
  }

  /// Check if product is suitable for a specific gender
  /// Uses explicit gender field if available, otherwise falls back to keyword detection
  bool _isProductSuitableForGender(ProductSummary product, String gender) {
    // First check if product has an explicit gender field
    if (product.gender != null && product.gender!.isNotEmpty) {
      final productGender = product.gender!.toLowerCase();
      final targetGender = gender.toLowerCase();
      return productGender == targetGender ||
          productGender == 'unisex' ||
          productGender == 'both';
    }

    // Fallback to keyword-based logic
    final productName = product.productName.toLowerCase();
    final brandModel = product.brandModel?.toLowerCase() ?? '';

    if (gender == 'Women') {
      // Check for women-specific keywords
      final hasWomenKeywords = productName.contains('women') ||
          productName.contains('female') ||
          productName.contains('ladies') ||
          productName.contains('woman') ||
          productName.contains('kadın') ||
          productName.contains('bayan') ||
          brandModel.contains('women') ||
          brandModel.contains('ladies');

      // Exclude men-specific products
      final hasMenKeywords = productName.contains('men\'s') ||
          productName.contains('erkek') ||
          productName.contains('male') ||
          productName.contains('gentlemen');

      return hasWomenKeywords || !hasMenKeywords;
    } else if (gender == 'Men') {
      // Check for men-specific keywords
      final hasMenKeywords = productName.contains('men') ||
          productName.contains('male') ||
          productName.contains('gentlemen') ||
          productName.contains('man') ||
          productName.contains('erkek') ||
          productName.contains('bay') ||
          brandModel.contains('men') ||
          brandModel.contains('male');

      // Exclude women-specific products
      final hasWomenKeywords = productName.contains('women') ||
          productName.contains('kadın') ||
          productName.contains('bayan') ||
          productName.contains('female') ||
          productName.contains('ladies');

      return hasMenKeywords || !hasWomenKeywords;
    }

    // If no gender indicators found, include the product (could be unisex)
    return true;
  }

  /// Buyer subcategory to product category mapping for Women/Men
  static const Map<String, Map<String, String>>
      _kBuyerToProductCategoryMapping = {
    'Women': {
      'Fashion': 'Clothing & Fashion',
      'Shoes': 'Footwear',
      'Accessories': 'Accessories',
      'Bags': 'Bags & Luggage',
      'Self Care': 'Beauty & Personal Care',
    },
    'Men': {
      'Fashion': 'Clothing & Fashion',
      'Shoes': 'Footwear',
      'Accessories': 'Accessories',
      'Bags': 'Bags & Luggage',
      'Self Care': 'Beauty & Personal Care',
    },
  };

  /// Buyer subcategories for Women/Men
  static const Map<String, List<String>> _kBuyerSubcategories = {
    'Women': ['Fashion', 'Shoes', 'Accessories', 'Bags', 'Self Care'],
    'Men': ['Fashion', 'Shoes', 'Accessories', 'Bags', 'Self Care'],
  };

  /// Fetch products for Women/Men buyer categories
  /// Each buyer subcategory maps to a product category
  Future<void> _fetchBuyerCategoryProducts(
      String filterType, int page, int limit) async {
    final buyerSubcategories = _kBuyerSubcategories[filterType] ?? [];
    final categoryMapping = _kBuyerToProductCategoryMapping[filterType] ?? {};

    if (buyerSubcategories.isEmpty) return;

    final List<Map<String, dynamic>> subcategoryData = [];
    final List<ProductSummary> allProducts = [];
    final Set<String> allProductIds = <String>{};

    // Fetch products for each buyer subcategory (mapped to product category)
    for (var buyerSubcat in buyerSubcategories) {
      final productCategory = categoryMapping[buyerSubcat];
      if (productCategory == null) continue;

      try {
        // Query products from the mapped category, filtered by gender
        // Products have gender field: "Women", "Men", or "Unisex"

        Query query = _firestore
            .collection('shop_products')
            .where('category', isEqualTo: productCategory)
            .where('gender', whereIn: [filterType, 'Unisex'])
            .orderBy('promotionScore', descending: true)
            .limit(10); // Get up to 10 products per category

        final snapshot = await query.get();

        final products =
            snapshot.docs.map((doc) => ProductSummary.fromDocument(doc)).toList();

        if (products.isNotEmpty) {
          subcategoryData.add({
            'subcategoryId':
                productCategory, // Use product category as ID for View All
            'subcategoryName': buyerSubcat, // Display buyer subcategory name
            'products': products,
          });

          for (var product in products) {
            if (allProductIds.add(product.id)) {
              allProducts.add(product);
            }
          }
        }
      } catch (e) {
        debugPrint(
            '❌ Error fetching $filterType > $buyerSubcat ($productCategory): $e');
      }
    }

    // Update state

    _filterProducts[filterType] = allProducts;
    _filterProductIds[filterType] = allProductIds;
    _subcategoryProducts[filterType] = subcategoryData;

    final cacheKey = '$filterType|$page';
    _productCache[cacheKey] = List.from(allProducts);
    _cacheTimestamps[cacheKey] = DateTime.now();

    if (filterType == specialFilter) {
      _productIdsSubject.add(allProducts.map((p) => p.id).toList());
    }

    // For Women/Men, we fetch all subcategories at once, so no more pages
    _updateFilterHasMoreState(filterType, false);
  }

  Future<void> _fetchSubcategoryProducts(
      String filterType, int page, int limit) async {
    if (['Women', 'Men'].contains(filterType)) {
      // ✅ For Women/Men: Fetch products from each mapped category separately
      // Buyer subcategories (Fashion, Shoes, etc.) map to product categories
      await _fetchBuyerCategoryProducts(filterType, page, limit);
      return;
    }

    // For other category filters (Electronics, Home & Furniture, etc.)
    Query productsQuery = _firestore
        .collection('shop_products')
        .where('category', isEqualTo: filterType)
        .orderBy('subcategory', descending: false)
        .orderBy('promotionScore', descending: true);

    if (dynamicBrand != null) {
      productsQuery =
          productsQuery.where('brandModel', isEqualTo: dynamicBrand);
    }
    if (searchTerm.isNotEmpty) {
      productsQuery = productsQuery
          .where('title', isGreaterThanOrEqualTo: searchTerm)
          .where('title', isLessThanOrEqualTo: searchTerm + '\uf8ff');
    }

    if (page > 0 && _lastDocuments[filterType] != null) {
      productsQuery =
          productsQuery.startAfterDocument(_lastDocuments[filterType]!);
    }

    final fetchLimit = limit * 3;
    productsQuery = productsQuery.limit(fetchLimit);

    final productsSnapshot = await productsQuery.get();
    final allProducts =
        productsSnapshot.docs.map((doc) => ProductSummary.fromDocument(doc)).toList();

    if (productsSnapshot.docs.isNotEmpty) {
      _lastDocuments[filterType] = productsSnapshot.docs.last;
    }

    final Map<String, List<ProductSummary>> subcategoryMap = {};
    for (var product in allProducts) {
      final subcategory = product.subcategory;
      if (subcategory.isNotEmpty) {
        subcategoryMap.putIfAbsent(subcategory, () => []).add(product);
      }
    }

    final List<Map<String, dynamic>> subcatData = [];
    final subcategories = subcategoryMap.keys.toList()..sort();
    final startIndex = page * limit;
    final endIndex = (page + 1) * limit;
    final paginatedSubcategories =
        subcategories.skip(startIndex).take(limit).toList();

    for (var subcategory in paginatedSubcategories) {
      final products = subcategoryMap[subcategory] ?? [];

      products.sort((a, b) {
        final aScore = a.promotionScore ?? 0;
        final bScore = b.promotionScore ?? 0;
        return bScore.compareTo(aScore);
      });

      final selectedProducts = products.take(10).toList();

      if (selectedProducts.isNotEmpty) {
        subcatData.add({
          'subcategoryId': subcategory,
          'subcategoryName': subcategory,
          'products': selectedProducts,
        });
      }
    }

    final currentProducts = _filterProducts[filterType] ?? [];
    final currentProductIds = _filterProductIds[filterType] ?? <String>{};
    final currentSubcategoryProducts = _subcategoryProducts[filterType] ?? [];

    for (var subcat in subcatData) {
      final products = subcat['products'] as List<ProductSummary>;
      for (var product in products) {
        if (currentProductIds.add(product.id)) {
          currentProducts.add(product);
        }
      }
    }

    currentSubcategoryProducts.addAll(subcatData);

    _filterProducts[filterType] = currentProducts;
    _filterProductIds[filterType] = currentProductIds;
    _subcategoryProducts[filterType] = currentSubcategoryProducts;

    final cacheKey = '$filterType|$page';
    _productCache[cacheKey] = List.from(currentProducts);
    _cacheTimestamps[cacheKey] = DateTime.now();

    if (filterType == specialFilter) {
      _productIdsSubject.add(currentProducts.map((p) => p.id).toList());
    }
    _updateFilterHasMoreState(filterType, subcategories.length > endIndex);
  }

  /// Remove filter ValueNotifiers to prevent memory leaks
  void removeFilterNotifiers(String filterType) {
    _filterLoadingNotifiers[filterType]?.dispose();
    _filterLoadingNotifiers.remove(filterType);
    _filterLoadingMoreNotifiers[filterType]?.dispose();
    _filterLoadingMoreNotifiers.remove(filterType);
    _filterHasMoreNotifiers[filterType]?.dispose();
    _filterHasMoreNotifiers.remove(filterType);
  }

  /// Remove subcategory ValueNotifiers
  void removeSubcategoryNotifiers(String category, String subcategoryId) {
    final key = '$category|$subcategoryId';
    _subcategoryLoadingNotifiers[key]?.dispose();
    _subcategoryLoadingNotifiers.remove(key);
    _subcategoryLoadingMoreNotifiers[key]?.dispose();
    _subcategoryLoadingMoreNotifiers.remove(key);
    _subcategoryHasMoreNotifiers[key]?.dispose();
    _subcategoryHasMoreNotifiers.remove(key);
  }

  /// Cleanup old dynamic filter notifiers that are no longer active
  void cleanupOldFilterNotifiers(List<String> activeFilterIds) {
    // Keep static filters + active dynamic filters
    final permanentFilters = {
      'Home',
      'Women',
      'Men',
      'Electronics',
      'Deals',
      'Featured',
      'Trending',
      '5-Star',
      'Best Sellers'
    };

    final keepFilters = {...permanentFilters, ...activeFilterIds};

    // Clean up filter notifiers
    final filterKeysToRemove = <String>[];
    _filterLoadingNotifiers.forEach((key, notifier) {
      if (!keepFilters.contains(key)) {
        notifier.dispose();
        filterKeysToRemove.add(key);
      }
    });

    for (final key in filterKeysToRemove) {
      _filterLoadingNotifiers.remove(key);
      _filterLoadingMoreNotifiers[key]?.dispose();
      _filterLoadingMoreNotifiers.remove(key);
      _filterHasMoreNotifiers[key]?.dispose();
      _filterHasMoreNotifiers.remove(key);
    }

    // Clean up subcategory notifiers
    final subcategoryKeysToRemove = <String>[];
    _subcategoryLoadingNotifiers.forEach((key, notifier) {
      final filterType = key.split('|')[0];
      if (!keepFilters.contains(filterType)) {
        notifier.dispose();
        subcategoryKeysToRemove.add(key);
      }
    });

    for (final key in subcategoryKeysToRemove) {
      _subcategoryLoadingNotifiers.remove(key);
      _subcategoryLoadingMoreNotifiers[key]?.dispose();
      _subcategoryLoadingMoreNotifiers.remove(key);
      _subcategoryHasMoreNotifiers[key]?.dispose();
      _subcategoryHasMoreNotifiers.remove(key);
    }
  }

  // Enhanced setSpecialFilter method to handle dynamic filters
  void setSpecialFilter(String filter, {DynamicFilter? dynamicFilter}) {
    if (_specialFilterNotifier.value != filter) {
      _specialFilterNotifier.value = filter;
      _initializeFilterState(filter);

      _lastDocuments[filter] = null;
      _currentPages[filter] = 0;

      if (filter.isEmpty) {
        _productIdsSubject.add([]);
        notifyListeners();
        return;
      }

      if (dynamicFilter != null) {
        _productIdsSubject.add([]);
        fetchProducts(
          filterType: filter,
          page: 0,
          dynamicFilter: dynamicFilter,
        );
      } else if (_filterProducts[filter]?.isNotEmpty ?? false) {
        final products = _filterProducts[filter] ?? [];
        _productIdsSubject.add(products.map((p) => p.id).toList());
      } else {
        _productIdsSubject.add([]);
        fetchProducts(
          filterType: filter,
          page: 0,
          dynamicFilter: dynamicFilter,
        );
      }

      notifyListeners();
    }
  }

  Future<void> fetchMoreProducts(String filterType,
      {DynamicFilter? dynamicFilter}) async {
    final hasMore = _hasMore[filterType] ?? true;
    final isLoadingMore = _isLoadingMore[filterType] ?? false;

    if (!hasMore || isLoadingMore) return;

    _updateFilterLoadingMoreState(filterType, true);
    notifyListeners();
    _currentPages[filterType] = (_currentPages[filterType] ?? 0) + 1;
    await fetchProducts(
      filterType: filterType,
      page: _currentPages[filterType]!,
      limit: 10,
      dynamicFilter: dynamicFilter,
    );
    _updateFilterLoadingMoreState(filterType, false);
    notifyListeners();
  }

  Future<void> refreshProducts(String filterType,
      {DynamicFilter? dynamicFilter}) async {
    _currentPages[filterType] = 0;
    _updateFilterHasMoreState(filterType, true);
    _lastDocuments[filterType] = null;
    _filterProducts[filterType] = [];
    _filterProductIds[filterType] = <String>{};
    _subcategoryProducts[filterType] = [];

    final keysToRemove = _productCache.keys
        .where((key) => key.startsWith('$filterType|'))
        .toList();
    for (final key in keysToRemove) {
      _productCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    _lastFetched.remove(filterType);

    await fetchProducts(
      filterType: filterType,
      page: 0,
      limit: 20,
      dynamicFilter: dynamicFilter,
    );
  }

  void clearFilterCache(String filterType) {
    final keysToRemove = _productCache.keys
        .where((key) => key.startsWith('$filterType|'))
        .toList();
    for (final key in keysToRemove) {
      _productCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    _lastFetched.remove(filterType);
  }

  // Store current gender filter for pagination
  String? _currentGender;

  // ──────────────────────────────────────────────────────────────────────────
  // SUBCATEGORY SNAPSHOT CACHE
  // ──────────────────────────────────────────────────────────────────────────

  String _buildSubcategorySnapshotKey(String subcategoryKey) {
    final parts = <String>[subcategoryKey];
    parts.add('qf:${_selectedFilterNotifier.value ?? 'none'}');
    parts.add('sort:$_subcategorySortOption');
    if (_dynamicBrandNotifier.value != null) {
      parts.add('brand:${_dynamicBrandNotifier.value}');
    }
    if (_dynamicColorsNotifier.value.isNotEmpty) {
      final sorted = List<String>.from(_dynamicColorsNotifier.value)..sort();
      parts.add('colors:${sorted.join(",")}');
    }
    if (_dynamicSubsubcategoryNotifier.value != null) {
      parts.add('subsub:${_dynamicSubsubcategoryNotifier.value}');
    }
    return parts.join('|');
  }

  void _saveSubcategorySnapshot(String subcategoryKey) {
    final products = _specificSubcategoryProducts[subcategoryKey];
    if (products == null || products.isEmpty) return;

    final snapshotKey = _buildSubcategorySnapshotKey(subcategoryKey);
    _snapshotProducts[snapshotKey] = List<ProductSummary>.from(products);
    _snapshotProductIds[snapshotKey] =
        Set<String>.from(_specificSubcategoryProductIds[subcategoryKey] ?? {});
    _snapshotPages[snapshotKey] = _specificSubcategoryPages[subcategoryKey] ?? 0;
    _snapshotHasMore[snapshotKey] =
        _specificSubcategoryHasMore[subcategoryKey] ?? false;
    _snapshotLastDocs[snapshotKey] =
        _specificSubcategoryLastDocs[subcategoryKey];
    _snapshotTs[snapshotKey] = DateTime.now();
    _pruneSubcategorySnapshots();
  }

  bool _tryRestoreSubcategorySnapshot(
      String subcategoryKey, String snapshotKey) {
    final cached = _snapshotProducts[snapshotKey];
    final ts = _snapshotTs[snapshotKey];
    final now = DateTime.now();

    if (cached != null && ts != null && now.difference(ts) < _snapshotTtl) {
      _specificSubcategoryProducts[subcategoryKey] =
          List<ProductSummary>.from(cached);
      _specificSubcategoryProductIds[subcategoryKey] =
          Set<String>.from(_snapshotProductIds[snapshotKey] ?? {});
      _specificSubcategoryPages[subcategoryKey] =
          _snapshotPages[snapshotKey] ?? 0;
      _specificSubcategoryHasMore[subcategoryKey] =
          _snapshotHasMore[snapshotKey] ?? false;
      _specificSubcategoryLastDocs[subcategoryKey] =
          _snapshotLastDocs[snapshotKey];
      _snapshotTs[snapshotKey] = now; // LRU touch
      return true;
    }

    if (cached != null) {
      _removeSubcategorySnapshotEntry(snapshotKey);
    }
    return false;
  }

  void _removeSubcategorySnapshotEntry(String snapshotKey) {
    _snapshotProducts.remove(snapshotKey);
    _snapshotProductIds.remove(snapshotKey);
    _snapshotPages.remove(snapshotKey);
    _snapshotHasMore.remove(snapshotKey);
    _snapshotLastDocs.remove(snapshotKey);
    _snapshotTs.remove(snapshotKey);
  }

  void _pruneSubcategorySnapshots() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    _snapshotTs.forEach((key, timestamp) {
      if (now.difference(timestamp) >= _snapshotTtl) {
        keysToRemove.add(key);
      }
    });
    for (final key in keysToRemove) {
      _removeSubcategorySnapshotEntry(key);
    }

    if (_snapshotProducts.length > _maxSnapshotEntries) {
      final sortedEntries = _snapshotTs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final entriesToRemove = sortedEntries
          .take(_snapshotProducts.length - _maxSnapshotEntries)
          .map((e) => e.key);
      for (final key in entriesToRemove) {
        _removeSubcategorySnapshotEntry(key);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUBCATEGORY FETCH HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Builds the base Firestore query with all filters EXCEPT gender and colors.
  /// Gender and colors are handled separately by [_executeSubcategoryFetch]
  /// because Firestore forbids whereIn + arrayContainsAny in one query.
  Query _buildSubcategoryBaseQuery({
    required String category,
    required String subcategoryId,
    String? selectedFilter,
  }) {
    Query query = _firestore
        .collection('shop_products')
        .where('category', isEqualTo: category);

    // Only add subcategory filter if it's different from category
    if (subcategoryId.isNotEmpty && subcategoryId != category) {
      query = query.where('subcategory', isEqualTo: subcategoryId);
    }

    // Apply selectedFilter (quick filters) or default sorting
    if (selectedFilter != null && selectedFilter.isNotEmpty) {
      switch (selectedFilter) {
        case 'deals':
          query = query
              .where('discountPercentage', isGreaterThan: 0)
              .orderBy('promotionScore', descending: true)
              .orderBy('discountPercentage', descending: true);
          break;
        case 'boosted':
          query = query
              .where('isBoosted', isEqualTo: true)
              .orderBy('promotionScore', descending: true)
              .orderBy('createdAt', descending: true);
          break;
        case 'trending':
          query = query
              .where('dailyClickCount', isGreaterThanOrEqualTo: 10)
              .orderBy('promotionScore', descending: true)
              .orderBy('dailyClickCount', descending: true);
          break;
        case 'fiveStar':
          query = query
              .where('averageRating', isEqualTo: 5)
              .orderBy('promotionScore', descending: true)
              .orderBy('createdAt', descending: true);
          break;
        case 'bestSellers':
          query = query
              .where('purchaseCount', isGreaterThan: 0)
              .orderBy('promotionScore', descending: true)
              .orderBy('purchaseCount', descending: true);
          break;
        default:
          query = _applySubcategorySorting(query);
      }
    } else {
      query = _applySubcategorySorting(query);
    }

    // Subsubcategory filter
    if (dynamicSubsubcategory != null && dynamicSubsubcategory!.isNotEmpty) {
      if (subcategoryId == category || subcategoryId.isEmpty) {
        // Top-level: "Dresses" is actually a subcategory in DB
        query = query.where('subcategory', isEqualTo: dynamicSubsubcategory);
      } else {
        // Regular subcategory view: filter by actual subsubcategory
        query = query.where('subsubcategory', isEqualTo: dynamicSubsubcategory);
      }
    }

    // Brand filter (isEqualTo — safe with all query types)
    if (dynamicBrand != null && dynamicBrand!.isNotEmpty) {
      query = query.where('brandModel', isEqualTo: dynamicBrand);
    }

    // Search term
    if (searchTerm.isNotEmpty) {
      query = query
          .where('title', isGreaterThanOrEqualTo: searchTerm)
          .where('title', isLessThanOrEqualTo: searchTerm + '\uf8ff');
    }

    return query;
  }

  /// Executes the subcategory fetch, automatically splitting into two parallel
  /// queries when gender + colors are both active (Firestore conflict).
  ///
  /// Returns the fetched products. Updates pagination cursors internally.
  ///
  /// [baseQuery] — built by [_buildSubcategoryBaseQuery] (no gender/colors).
  /// [key]       — the subcategory state key (category|subcategoryId|gender).
  /// [limit]     — page size per query.
  /// [gender]    — optional gender filter (e.g. 'Women', 'Men').
  /// [isLoadMore]— if true, applies startAfterDocument from stored cursors.
  Future<List<ProductSummary>> _executeSubcategoryFetch({
    required Query baseQuery,
    required String key,
    required int limit,
    String? gender,
    bool isLoadMore = false,
  }) async {
    if (_needsDualGenderQuery(gender)) {
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      // DUAL-QUERY PATH: gender(isEqualTo) + colors(arrayContainsAny) each
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      Query genderQuery = baseQuery
          .where('gender', isEqualTo: gender)
          .where('availableColors', arrayContainsAny: dynamicColors)
          .limit(limit);

      Query unisexQuery = baseQuery
          .where('gender', isEqualTo: 'Unisex')
          .where('availableColors', arrayContainsAny: dynamicColors)
          .limit(limit);

      // Apply pagination cursors for load-more
      if (isLoadMore) {
        if (_specificSubcategoryLastDocs[key] != null) {
          genderQuery = genderQuery
              .startAfterDocument(_specificSubcategoryLastDocs[key]!);
        }
        if (_dualQueryUnisexLastDocs[key] != null) {
          unisexQuery = unisexQuery
              .startAfterDocument(_dualQueryUnisexLastDocs[key]!);
        }
      }

      // Execute both in parallel
      final results = await Future.wait([
        genderQuery.get(),
        unisexQuery.get(),
      ]);

      final genderSnapshot = results[0];
      final unisexSnapshot = results[1];

      // Update pagination cursors
      if (genderSnapshot.docs.isNotEmpty) {
        _specificSubcategoryLastDocs[key] = genderSnapshot.docs.last;
      }
      if (unisexSnapshot.docs.isNotEmpty) {
        _dualQueryUnisexLastDocs[key] = unisexSnapshot.docs.last;
      }

      // Track per-query hasMore for accurate pagination
      _dualQueryGenderHasMore[key] = genderSnapshot.docs.length >= limit;
      _dualQueryUnisexHasMore[key] = unisexSnapshot.docs.length >= limit;

      // Merge and deduplicate (preserve order: gender-specific first)
      final allDocs = [...genderSnapshot.docs, ...unisexSnapshot.docs];
      final seen = <String>{};
      final products = <ProductSummary>[];

      for (final doc in allDocs) {
        if (seen.add(doc.id)) {
          try {
            products.add(ProductSummary.fromDocument(doc));
          } catch (e) {
            debugPrint('⚠️ Failed to parse product ${doc.id}: $e');
          }
        }
      }

      return products;
    } else {
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      // SINGLE-QUERY PATH: no conflict, add gender/colors directly
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      Query query = baseQuery;

      if (gender != null && gender.isNotEmpty) {
        query = query.where('gender', whereIn: [gender, 'Unisex']);
      }
      if (dynamicColors.isNotEmpty) {
        query = query.where('availableColors', arrayContainsAny: dynamicColors);
      }

      query = query.limit(limit);

      // Apply pagination cursor for load-more
      if (isLoadMore && _specificSubcategoryLastDocs[key] != null) {
        query = query
            .startAfterDocument(_specificSubcategoryLastDocs[key]!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _specificSubcategoryLastDocs[key] = snapshot.docs.last;
      }

      // Clear dual-query state when using single-query path
      _dualQueryUnisexLastDocs.remove(key);
      _dualQueryGenderHasMore.remove(key);
      _dualQueryUnisexHasMore.remove(key);

      return snapshot.docs
          .map((doc) => ProductSummary.fromDocument(doc))
          .toList();
    }
  }

  /// Computes whether more pages are available.
  /// For dual-query: more data exists if EITHER sub-query has more.
  /// For single-query: uses standard count-vs-limit check.
  bool _computeHasMore(String key, int fetchedCount, int limit) {
    if (_dualQueryGenderHasMore.containsKey(key)) {
      return (_dualQueryGenderHasMore[key] ?? false) ||
          (_dualQueryUnisexHasMore[key] ?? false);
    }
    return fetchedCount >= limit;
  }

  Future<void> fetchSubcategoryProducts(String category, String subcategoryId,
      {String? selectedFilter, String? gender}) async {
    // ✅ FIX: Include gender in key to prevent cache conflicts
    final key = gender != null && gender.isNotEmpty
        ? '$category|$subcategoryId|$gender'
        : '$category|$subcategoryId';

    _currentCategory = category;
    _currentSubcategoryId = subcategoryId;
    _currentGender = gender;
    _selectedFilterNotifier.value = selectedFilter;

    _specificSubcategoryProducts[key] ??= [];
    _specificSubcategoryProductIds[key] ??= <String>{};
    _specificSubcategoryPages[key] ??= 0;
    _specificSubcategoryHasMore[key] ??= true;
    _specificSubcategoryLastDocs[key] ??= null;
    _specificSubcategoryLoading[key] ??= false;
    _specificSubcategoryLoadingMore[key] ??= false;

    if (_specificSubcategoryLoading[key] == true) return;

    // Try to restore from snapshot cache for this filter combination
    final snapshotKey = _buildSubcategorySnapshotKey(key);
    if (_tryRestoreSubcategorySnapshot(key, snapshotKey)) {
      _updateSubcategoryLoadingState(key, false);
      _updateSubcategoryHasMoreState(
          key, _specificSubcategoryHasMore[key] ?? false);
      notifyListeners();
      return;
    }

    _updateSubcategoryLoadingState(key, true);

    _specificSubcategoryPages[key] = 0;
    _updateSubcategoryHasMoreState(key, true);
    _specificSubcategoryLastDocs[key] = null;
    _dualQueryUnisexLastDocs[key] = null;
    _dualQueryGenderHasMore.remove(key);
    _dualQueryUnisexHasMore.remove(key);
    _specificSubcategoryProducts[key] = [];
    _specificSubcategoryProductIds[key] = {};

    notifyListeners();

    final cacheKey = '$key|0';
    final now = DateTime.now();
    final cachedTime = _cacheTimestamps[cacheKey];
    final isCacheValid =
        cachedTime != null && now.difference(cachedTime) < _cacheTTL;

    // ✅ FIX: Skip cache when any filters are applied (brand, colors, subsubcategory)
    final hasFilters = selectedFilter != null ||
        (dynamicBrand != null && dynamicBrand!.isNotEmpty) ||
        dynamicColors.isNotEmpty ||
        (dynamicSubsubcategory != null && dynamicSubsubcategory!.isNotEmpty);

    if (isCacheValid && _productCache.containsKey(cacheKey) && !hasFilters) {
      final cachedProducts = _productCache[cacheKey]!;
      _specificSubcategoryProducts[key] = List.from(cachedProducts);
      _specificSubcategoryProductIds[key] =
          cachedProducts.map((p) => p.id).toSet();
      _updateSubcategoryHasMoreState(key, cachedProducts.length >= 20);
      _updateSubcategoryLoadingState(key, false);
      notifyListeners();
      return;
    }

    try {
      final baseQuery = _buildSubcategoryBaseQuery(
        category: category,
        subcategoryId: subcategoryId,
        selectedFilter: selectedFilter,
      );

      final products = await _executeSubcategoryFetch(
        baseQuery: baseQuery,
        key: key,
        limit: 20,
        gender: gender,
        isLoadMore: false,
      );

      _specificSubcategoryProducts[key] = products;
      _specificSubcategoryProductIds[key] = products.map((p) => p.id).toSet();

      // Only cache unfiltered results to avoid stale filtered data on filter clear
      if (!hasFilters) {
        _productCache[cacheKey] = List.from(products);
        _cacheTimestamps[cacheKey] = now;
      }
      _updateSubcategoryHasMoreState(key, _computeHasMore(key, products.length, 20));
    } catch (e) {
      debugPrint('❌ fetchSubcategoryProducts error [$key]: $e');
      _updateSubcategoryHasMoreState(key, false);
    } finally {
      _updateSubcategoryLoadingState(key, false);
      notifyListeners();
    }
  }

  Future<void> fetchMoreSubcategoryProducts(
      String category, String subcategoryId,
      {String? selectedFilter}) async {
    // ✅ FIX: Use same key format as fetchSubcategoryProducts (include gender)
    final key = _currentGender != null && _currentGender!.isNotEmpty
        ? '$category|$subcategoryId|$_currentGender'
        : '$category|$subcategoryId';
    if (_specificSubcategoryLoadingMore[key] ?? false) return;
    if (!(_specificSubcategoryHasMore[key] ?? false)) return;

    _updateSubcategoryLoadingMoreState(key, true);
    notifyListeners();

    final page = (_specificSubcategoryPages[key] ?? 0) + 1;
    _specificSubcategoryPages[key] = page;

    final cacheKey = '$key|$page';
    final now = DateTime.now();
    final cachedTime = _cacheTimestamps[cacheKey];
    final isCacheValid =
        cachedTime != null && now.difference(cachedTime) < _cacheTTL;

    // ✅ FIX: Skip cache when any filters are applied
    final hasFilters = (selectedFilter != null && selectedFilter.isNotEmpty) ||
        (dynamicBrand != null && dynamicBrand!.isNotEmpty) ||
        dynamicColors.isNotEmpty ||
        (dynamicSubsubcategory != null && dynamicSubsubcategory!.isNotEmpty);

    if (isCacheValid && _productCache.containsKey(cacheKey) && !hasFilters) {
      final cachedProducts = _productCache[cacheKey]!;

      final currentProducts = _specificSubcategoryProducts[key] ?? [];
      final currentProductIds =
          _specificSubcategoryProductIds[key] ?? <String>{};

      currentProducts.addAll(cachedProducts);
      currentProductIds.addAll(cachedProducts.map((p) => p.id));

      _specificSubcategoryProducts[key] = currentProducts;
      _specificSubcategoryProductIds[key] = currentProductIds;

      _updateSubcategoryHasMoreState(key, cachedProducts.length >= 20);
      _updateSubcategoryLoadingMoreState(key, false);
      notifyListeners();
      return;
    }

    try {
      final baseQuery = _buildSubcategoryBaseQuery(
        category: category,
        subcategoryId: subcategoryId,
        selectedFilter: selectedFilter,
      );

      final newProducts = await _executeSubcategoryFetch(
        baseQuery: baseQuery,
        key: key,
        limit: 20,
        gender: _currentGender,
        isLoadMore: true,
      );

      final currentProducts = _specificSubcategoryProducts[key] ?? [];
      final currentProductIds =
          _specificSubcategoryProductIds[key] ?? <String>{};

      // Deduplicate against existing products
      for (final product in newProducts) {
        if (currentProductIds.add(product.id)) {
          currentProducts.add(product);
        }
      }

      _specificSubcategoryProducts[key] = currentProducts;
      _specificSubcategoryProductIds[key] = currentProductIds;

      // Only cache unfiltered results
      if (!hasFilters) {
        _productCache[cacheKey] = List.from(newProducts);
        _cacheTimestamps[cacheKey] = now;
      }
      _updateSubcategoryHasMoreState(key, _computeHasMore(key, newProducts.length, 20));
    } catch (e) {
      debugPrint('❌ fetchMoreSubcategoryProducts error [$key]: $e');
      _updateSubcategoryHasMoreState(key, false);
    } finally {
      _updateSubcategoryLoadingMoreState(key, false);
      notifyListeners();
    }
  }

  // ✅ Helper to generate consistent key
  String _getSubcategoryKey(String category, String subcategoryId,
      {String? gender}) {
    final effectiveGender = gender ?? _currentGender;
    return effectiveGender != null && effectiveGender.isNotEmpty
        ? '$category|$subcategoryId|$effectiveGender'
        : '$category|$subcategoryId';
  }

  List<ProductSummary> getSubcategoryProductsById(
      String category, String subcategoryId,
      {String? gender}) {
    final key = _getSubcategoryKey(category, subcategoryId, gender: gender);
    return _specificSubcategoryProducts[key] ?? [];
  }

  bool isLoadingSubcategory(String category, String subcategoryId,
      {String? gender}) {
    final key = _getSubcategoryKey(category, subcategoryId, gender: gender);
    return _specificSubcategoryLoading[key] ?? false;
  }

  bool isLoadingMoreSubcategory(String category, String subcategoryId,
      {String? gender}) {
    final key = _getSubcategoryKey(category, subcategoryId, gender: gender);
    return _specificSubcategoryLoadingMore[key] ?? false;
  }

  bool hasMoreSubcategory(String category, String subcategoryId,
      {String? gender}) {
    final key = _getSubcategoryKey(category, subcategoryId, gender: gender);
    return _specificSubcategoryHasMore[key] ?? false;
  }

  @override
  void dispose() {
    // 1. Cancel stream subscription
    _productsStreamSubscription?.cancel();
    _productsStreamSubscription = null;

    // 2. Close subjects
    if (!_productIdsSubject.isClosed) {
      _productIdsSubject.close();
    }

    // 3. Dispose all ValueNotifiers
    _specialFilterNotifier.dispose();
    _dynamicSubsubcategoryNotifier.dispose();
    _dynamicBrandNotifier.dispose();
    _dynamicColorsNotifier.dispose();
    _searchTermNotifier.dispose();
    _selectedFilterNotifier.dispose();

    // 4. Dispose filter loading notifiers
    for (final notifier in _filterLoadingNotifiers.values) {
      notifier.dispose();
    }
    _filterLoadingNotifiers.clear();

    for (final notifier in _filterLoadingMoreNotifiers.values) {
      notifier.dispose();
    }
    _filterLoadingMoreNotifiers.clear();

    for (final notifier in _filterHasMoreNotifiers.values) {
      notifier.dispose();
    }
    _filterHasMoreNotifiers.clear();

    // 5. Dispose subcategory loading notifiers
    for (final notifier in _subcategoryLoadingNotifiers.values) {
      notifier.dispose();
    }
    _subcategoryLoadingNotifiers.clear();

    for (final notifier in _subcategoryLoadingMoreNotifiers.values) {
      notifier.dispose();
    }
    _subcategoryLoadingMoreNotifiers.clear();

    for (final notifier in _subcategoryHasMoreNotifiers.values) {
      notifier.dispose();
    }
    _subcategoryHasMoreNotifiers.clear();

    // 6. ✅ NEW: Clear all data maps to prevent memory leaks
    _filterProducts.clear();
    _filterProductIds.clear();
    _subcategoryProducts.clear();
    _productCache.clear();
    _cacheTimestamps.clear();

    // ✅ NEW: Clear pagination state
    _currentPages.clear();
    _hasMore.clear();
    _isLoadingMore.clear();
    _lastDocuments.clear();
    _isFiltering.clear();
    _lastFetched.clear();

    // ✅ NEW: Clear specific subcategory data
    _specificSubcategoryProducts.clear();
    _specificSubcategoryProductIds.clear();
    _specificSubcategoryPages.clear();
    _specificSubcategoryLoading.clear();
    _specificSubcategoryLoadingMore.clear();
    _specificSubcategoryHasMore.clear();
    _specificSubcategoryLastDocs.clear();

    // ✅ Clear dual-query pagination state
    _dualQueryUnisexLastDocs.clear();
    _dualQueryGenderHasMore.clear();
    _dualQueryUnisexHasMore.clear();

    // Clear snapshot cache
    _snapshotProducts.clear();
    _snapshotProductIds.clear();
    _snapshotPages.clear();
    _snapshotHasMore.clear();
    _snapshotLastDocs.clear();
    _snapshotTs.clear();

    // 7. ✅ NEW: Reset state variables
    _currentCategory = null;
    _currentSubcategoryId = null;

    super.dispose();
  }
}