import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../user_provider.dart';
import '../constants/all_in_one_category_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/debouncer.dart';

/// -----------------------------------------------------------------------------
/// A lightweight TerasProvider used only for display on the vitrin (teras_market)
/// screen. Data fetching is done on demand (no heavy initialization), and all
/// queries come from the "products" collection.
/// -----------------------------------------------------------------------------
class TerasProvider with ChangeNotifier {
  final UserProvider userProvider;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  // Boosted products list – these can be fetched on demand.
  final List<Product> _boostedProducts = [];
  List<Product> get boostedProducts => _boostedProducts;

  // Current user info placeholder.
  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  final Map<String, List<Product>> _productCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 5);
  final Debouncer _notifyDebouncer =
      Debouncer(delay: const Duration(milliseconds: 200));

  // Pagination controls.
  final int _limit = 50;
  int _currentPage = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  // Main product list.
  final List<Product> _products = [];
  List<Product> get products => _products;

  bool _recordImpressions = true;
  bool get recordImpressions => _recordImpressions;
  set recordImpressions(bool value) {
    _recordImpressions = value;
  }

  final Map<String, DateTime> _lastScreenVisitTime = {};

  // Filtering state variables.
  bool _isFiltering = false;
  bool get isFiltering => _isFiltering;

  bool _isSearchActive = false;
  bool get isSearchActive => _isSearchActive;

  String _searchTerm = '';
  String get searchTerm => _searchTerm;
  set searchTerm(String value) {
    _searchTerm = value;
    notifyListeners();
  }

  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  String? _selectedSubSubcategory;
  String? get selectedSubSubcategory => _selectedSubSubcategory;

  double? _minPrice;
  double? get minPrice => _minPrice;

  String? _dynamicBrand;
  List<String> _dynamicColors = [];

  String? get dynamicBrand => _dynamicBrand;
  List<String> get dynamicColors => List.unmodifiable(_dynamicColors);

  double? _maxPrice;
  double? get maxPrice => _maxPrice;

  String _sortOption = 'date';
  String get sortOption => _sortOption;
  set sortOption(String value) {
    _sortOption = value;
    notifyListeners();
  }

  // Expose basic UI data.
  List<Map<String, String>> get categories => AllInOneCategoryData.kCategories;
  Map<String, List<String>> get categoryKeywords =>
      AllInOneCategoryData.kCategoryKeywordsMap;
  Map<String, List<String>> get subcategories =>
      AllInOneCategoryData.kSubcategories;

  // Instead of constructing a stream that listens to Firestore,
  // simply provide a stream that emits the current products list.
  Stream<List<Product>> get productsStream =>
      Stream<List<Product>>.value(_products);

  // Local loading state.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Pagination: track the last document fetched.
  DocumentSnapshot? _lastDocument;

  /// ---------------------------------------------------------------------------
  /// Constructor: simply holds a reference to the user provider.
  /// ---------------------------------------------------------------------------
  TerasProvider(this.userProvider);

  @override
  void dispose() {
    super.dispose();
  }

  void setDynamicFilter({
    String? brand,
    List<String> colors = const [],
  }) {
    _dynamicBrand = brand;
    _dynamicColors = colors;
  }

  /// ---------------------------------------------------------------------------
  /// Filters the products and fetches the first page.
  /// ---------------------------------------------------------------------------
  Future<void> filterProducts() async {
    _isSearchActive = _searchTerm.isNotEmpty ||
        _minPrice != null ||
        _maxPrice != null ||
        _selectedCategory != null ||
        _selectedSubSubcategory != null;

    // ✅ Fetch handles clearing and notification after await
    await fetchProductsFromFirestore(
      page: 0,
      limit: _limit,
      forceRefresh: true,
    );

    // ✅ Apply dynamic filters after fetch completes
    if (_dynamicBrand != null) {
      _products.retainWhere((p) => p.brandModel == _dynamicBrand);
    }
    if (_dynamicColors.isNotEmpty) {
      _products.retainWhere((p) {
        final availableColors = p.colorImages.keys.toSet() ?? {};
        return _dynamicColors.any(availableColors.contains);
      });
    }

    await fetchBoostedProducts();
  }

  /// ---------------------------------------------------------------------------
  /// Resets search/filter parameters and clears the product list.
  /// ---------------------------------------------------------------------------
  Future<void> resetSearch({
    bool triggerFilter = true,
    bool preserveSubSubcategory = false,
  }) async {
    _selectedCategory = preserveSubSubcategory ? _selectedCategory : null;
    if (!preserveSubSubcategory) {
      _selectedSubSubcategory = null;
    }
    _minPrice = null;
    _maxPrice = null;
    _isSearchActive = false;

    _currentPage = 0;
    _hasMore = true;
    _products.clear();
    _productCache.clear();
    _cacheTimestamps.clear();

    // ✅ If triggering filter, let filterProducts handle notification
    if (triggerFilter) {
      await filterProducts();
    } else {
      // ✅ Only notify if we're not filtering (after state is set)
      _notifyDebouncer.run(() => notifyListeners());
    }
  }

  /// ---------------------------------------------------------------------------
  /// Records the search term in the Firestore "searches" collection.
  /// ---------------------------------------------------------------------------
  Future<void> recordSearchTerm(String searchTerm) async {
    final User? user = _auth.currentUser;
    final String userId = user?.uid ?? 'anonymous';

    try {
      await _firestore.collection('searches').add({
        'userId': userId,
        'searchTerm': searchTerm,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('Search term recorded: $searchTerm by user: $userId');
    } catch (e) {
      debugPrint('Error saving search term: $e');
    }
  }

  /// ---------------------------------------------------------------------------
  /// On-refresh: re-fetches the first page.
  /// ---------------------------------------------------------------------------
  Future<void> onRefresh({bool ignoreCategory = false}) async {
    await fetchProductsFromFirestore(
      page: 0,
      limit: _limit,
      ignoreCategory: ignoreCategory,
      forceRefresh: true,
    );
  }

  /// ---------------------------------------------------------------------------
  /// Fetches boosted products from the "products" collection.
  /// ---------------------------------------------------------------------------
  Future<void> fetchBoostedProducts() async {
    try {
      Query query =
          _firestore.collection('products').where('isBoosted', isEqualTo: true);
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        query = query.where('category', isEqualTo: _selectedCategory);
      }
      if (_selectedSubSubcategory != null &&
          _selectedSubSubcategory!.isNotEmpty) {
        query =
            query.where('subsubcategory', isEqualTo: _selectedSubSubcategory);
      }
      query = query.orderBy('createdAt', descending: true).limit(100);

      final snapshot = await query.get();

      // ✅ All mutations after await - safe to notify
      final fetchedBoosted =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();
      _boostedProducts
        ..clear()
        ..addAll(fetchedBoosted);
      notifyListeners();
    } catch (e) {
      debugPrint("fetchBoostedProducts error: $e");
    }
  }

  Future<void> recordScreenVisit(String screenType,
      {Duration debounceDuration = const Duration(seconds: 10)}) async {
    if (!_recordImpressions) return;

    final now = DateTime.now();
    final lastVisit = _lastScreenVisitTime[screenType];
    if (lastVisit == null || now.difference(lastVisit) > debounceDuration) {
      await incrementImpressionOnVisit(
        userId: _currentUserId,
        sessionId: 'sessionId',
        screenType: screenType,
      );
      _lastScreenVisitTime[screenType] = now;
      debugPrint('Screen visit recorded for $screenType at $now');
    } else {
      debugPrint(
          'Debounced recordScreenVisit for $screenType; last visit at $lastVisit');
    }
  }

  Future<void> incrementImpressionOnVisit({
    String? userId,
    String? sessionId,
    required String screenType,
  }) async {
    try {
      final callable = _functions.httpsCallable('incrementImpressionOnVisit');
      await callable.call({
        'userId': userId,
        'sessionId': sessionId,
        'screenType': screenType,
      });
    } catch (e) {
      debugPrint('Error incrementing impressions on visit for $screenType: $e');
    }
  }

  Future<void> incrementImpressionCount({
    required List<String> productIds,
    required String screenType,
  }) async {
    if (productIds.isEmpty) return;
    try {
      final callable = _functions.httpsCallable('incrementImpressionCount');
      await callable.call({
        'productIds': productIds,
        'screenType': screenType,
      });
    } catch (e) {
      debugPrint('Error incrementing impression counts: $e');
    }
  }

  /// ---------------------------------------------------------------------------
  /// Fetches products from the "products" collection using filtering and pagination.
  /// ---------------------------------------------------------------------------
  Future<void> fetchProductsFromFirestore({
    int page = 0,
    int limit = 50,
    bool ignoreCategory = false,
    bool forceRefresh = false,
  }) async {
    if (_isFiltering && !forceRefresh) return;
    _isFiltering = true;

    final bool shouldClear = page == 0 || forceRefresh;

    try {
      Query query = _firestore.collection('products');

      if (!ignoreCategory) {
        if (_selectedCategory?.isNotEmpty == true) {
          query = query.where('category', isEqualTo: _selectedCategory);
        }
        if (_selectedSubSubcategory?.isNotEmpty == true) {
          query =
              query.where('subsubcategory', isEqualTo: _selectedSubSubcategory);
        }
      }
      if (_minPrice != null) {
        query = query.where('price', isGreaterThanOrEqualTo: _minPrice);
      }
      if (_maxPrice != null) {
        query = query.where('price', isLessThanOrEqualTo: _maxPrice);
      }

      switch (_sortOption.toLowerCase()) {
        case 'alphabetical':
          query = query.orderBy('productName', descending: false);
          break;
        case 'price low to high':
          query = query.orderBy('price', descending: false);
          break;
        case 'price high to low':
          query = query.orderBy('price', descending: true);
          break;
        case 'date':
        default:
          query = query.orderBy('createdAt', descending: true);
      }

      // ✅ Only use lastDocument if not clearing
      if (!shouldClear && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      query = query.limit(limit);

      final snap = await query.get();

      // ✅ ALL state mutations happen AFTER await - guaranteed outside build phase
      var fetched = snap.docs.map((d) => Product.fromDocument(d)).toList();

      if (_dynamicBrand != null) {
        fetched = fetched.where((p) => p.brandModel == _dynamicBrand).toList();
      }
      if (_dynamicColors.isNotEmpty) {
        fetched = fetched.where((p) {
          final avail = p.colorImages.keys.toSet() ?? {};
          return _dynamicColors.any(avail.contains);
        }).toList();
      }

      // ✅ Clear AFTER await, right before adding new data
      if (shouldClear) {
        _products.clear();
        _currentPage = 0;
        _lastDocument = null;
        _hasMore = true;
      }

      _hasMore = fetched.length == limit;

      if (snap.docs.isNotEmpty) {
        _lastDocument = snap.docs.last;
      }

      _products.addAll(fetched);
      _currentPage = page;
    } catch (e) {
      debugPrint("fetchProductsFromFirestore error: $e");
      _hasMore = false;
    }

    // ✅ Single notification point - always after await completes
    _isFiltering = false;
    notifyListeners();
  }

  /// ---------------------------------------------------------------------------
  /// Loads more products (for infinite scrolling).
  /// ---------------------------------------------------------------------------
  Future<void> fetchMoreProducts() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;

    // ✅ No notification here - let fetchProductsFromFirestore handle it
    _currentPage += 1;
    await fetchProductsFromFirestore(page: _currentPage, limit: _limit);

    _pruneProductsIfNeeded();
    _isLoadingMore = false;
    notifyListeners();
  }

  void _pruneProductsIfNeeded() {
    const int maxStoredProducts = 30;
    if (_products.length > maxStoredProducts) {
      const int removeCount = 10;
      _products.removeRange(0, removeCount);
      debugPrint(
          'Pruned $removeCount stale products; now holding ${_products.length}');
      // ✅ No notification here - caller will notify
    }
  }

  /// ---------------------------------------------------------------------------
  /// Allows an external update of the product list.
  /// ---------------------------------------------------------------------------
  void setProducts(List<Product> products) {
    _products
      ..clear()
      ..addAll(products);
    notifyListeners();
  }

  /// ---------------------------------------------------------------------------
  /// Methods to update filters.
  /// ---------------------------------------------------------------------------
  Future<void> setCategory(String? category, {bool shouldFilter = true}) async {
    _selectedCategory = category;
    if (category == null) {
      _selectedSubSubcategory = null;
    }
    if (shouldFilter) {
      await filterProducts();
    } else {
      notifyListeners();
    }
  }

  Future<void> setSubSubcategory(String? subSubcategory,
      {bool shouldFilter = true}) async {
    _selectedSubSubcategory = subSubcategory;
    await fetchBoostedProducts();
    if (shouldFilter) {
      await filterProducts();
    }
  }
}
