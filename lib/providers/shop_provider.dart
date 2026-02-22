// lib/providers/shop_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Nar24/generated/l10n/app_localizations.dart';
import '../models/product.dart';
import 'package:Nar24/models/mock_document_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:Nar24/constants/all_in_one_category_data.dart';
import '../services/typesense_service_manager.dart';

// Helper functions remain the same
Map<String, dynamic> _decodeAndConvertShopData(String jsonString) {
  final Map<String, dynamic> data = jsonDecode(jsonString);
  Map<String, dynamic> convert(Map<String, dynamic> m) {
    return m.map((key, value) {
      if ((key == 'createdAt' ||
              key == 'boostStartTime' ||
              key == 'boostEndTime' ||
              key == 'lastClickDate' ||
              key == 'timestamp') &&
          value is int) {
        return MapEntry(key, Timestamp.fromMillisecondsSinceEpoch(value));
      } else if (value is Map<String, dynamic>) {
        return MapEntry(key, convert(value));
      } else if (value is List) {
        return MapEntry(
            key,
            value.map((e) {
              if (e is Map<String, dynamic>) return convert(e);
              return e;
            }).toList());
      }
      return MapEntry(key, value);
    });
  }

  return convert(data);
}

List<Map<String, dynamic>> _decodeAndConvertListOfMaps(String jsonString) {
  final List<dynamic> list = jsonDecode(jsonString);
  return list.map((e) => _decodeAndConvertShopData(jsonEncode(e))).toList();
}

class ShopProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ValueNotifiers for frequently accessed data
  final ValueNotifier<bool> isLoadingShopDocNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingProductsNotifier =
      ValueNotifier<bool>(true);
  final ValueNotifier<bool> isLoadingReviewsNotifier =
      ValueNotifier<bool>(true);
  final ValueNotifier<List<Product>> allProductsNotifier =
      ValueNotifier<List<Product>>([]);
  final ValueNotifier<List<Product>> dealProductsNotifier =
      ValueNotifier<List<Product>>([]);
  final ValueNotifier<List<Product>> bestSellersNotifier =
      ValueNotifier<List<Product>>([]);
  final ValueNotifier<int> totalFiltersAppliedNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> shopDocErrorNotifier = ValueNotifier<bool>(false);
  List<Map<String, dynamic>> _collections = [];
  final ValueNotifier<List<Map<String, dynamic>>> collectionsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<bool> isLoadingCollectionsNotifier =
      ValueNotifier<bool>(false);

  Timer? _searchDebounce;
  List<Product> _searchResults = [];
  bool _isSearching = false;
  String _lastSearchQuery = '';

  // Race token for search deduplication
  int _searchRaceToken = 0;

  // Memory management constants
  static const int _maxProductsInMemory = 200;
  static const int _maxCacheSizeBytes = 5 * 1024 * 1024; // 5MB per shop
  static const Duration _cacheExpiryDuration = Duration(days: 7);

  // Circuit breaker for network resilience
  int _consecutiveFailures = 0;
  DateTime? _circuitBreakerResetTime;
  static const int _maxConsecutiveFailures = 3;
  static const Duration _circuitBreakerResetDuration = Duration(minutes: 1);

  List<Product> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

// Add getter
  List<Map<String, dynamic>> get collections => collectionsNotifier.value;
  bool get isLoadingCollections => isLoadingCollectionsNotifier.value;

  // Filter state
  List<String> _selectedBrands = [];
  double? _minPrice;
  double? _maxPrice;
  String? _selectedGender;
  List<String> _selectedTypes = [];
  List<String> _selectedFits = [];
  List<String> _selectedSizes = [];
  List<String> _selectedColors = [];
  String? _selectedSubcategory;
  String? _selectedColorForDisplay;

  // Dynamic spec filters (Typesense facets)
  Map<String, List<Map<String, dynamic>>> _specFacets = {};
  Map<String, List<String>> _dynamicSpecFilters = {};

  // Shop Detail Screen state
  MockDocumentSnapshot? _shopDoc;
  List<Map<String, dynamic>> _reviews = [];
  String _sortOption = 'date';
  String _searchQuery = '';
  DateTime? _lastShopFetch;
  DateTime? _lastProductsFetch;
  DateTime? _lastShopsRefresh;
  final Duration _shopsRefreshInterval = const Duration(seconds: 30);
  List<Product> _unfilteredProducts = [];

  // Shop list state
  String? selectedCategoryCode;
  List<QueryDocumentSnapshot> _shops = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = false;
  bool _hasError = false;
  final int _limit = 10;
  final ScrollController scrollController = ScrollController();
  Map<String, double> _averageRatings = {};
  bool? _userOwnsShop;
  final TextEditingController searchController = TextEditingController();
  String searchTerm = '';
  bool _isFiltering = false;
  bool _isSearchActive = false;
  bool _isSearchExpanded = false;
  final ValueNotifier<int> unreadMessagesCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> cartCount = ValueNotifier<int>(0);

  User? _currentUser;
  int _currentIndex = 0;

  StreamSubscription<User?>? _authSub;

  // Reliability improvements
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isDisposed =
      false; // Track disposal state to prevent notifyListeners after dispose
  Timer? _debounceTimer;
  Timer? _timeoutTimer;
  final Duration _loadTimeout = const Duration(seconds: 10);
  DateTime? _lastManualRefresh;
  final Duration _refreshInterval = const Duration(seconds: 30);

  DocumentSnapshot? _lastProductDocument;
  bool _hasMoreProducts = true;
  bool _isLoadingMoreProducts = false;
  final int _productsLimit = 20;
  List<Product> _allFetchedProducts = [];

  bool get hasMoreProducts => _hasMoreProducts;
  bool get isLoadingMoreProducts => _isLoadingMoreProducts;

  // Getters
  List<String> get selectedBrands => _selectedBrands;
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;
  MockDocumentSnapshot? get shopDoc => _shopDoc;
  bool get isLoadingShopDoc => isLoadingShopDocNotifier.value;
  List<Product> get allProducts => allProductsNotifier.value;
  List<Product> get dealProducts => dealProductsNotifier.value;
  List<Product> get bestSellers => bestSellersNotifier.value;
  List<Map<String, dynamic>> get reviews => _reviews;
  bool get isLoadingProducts => isLoadingProductsNotifier.value;
  bool get isLoadingReviews => isLoadingReviewsNotifier.value;
  int get totalFiltersApplied => totalFiltersAppliedNotifier.value;
  String get sortOption => _sortOption;
  String get searchQuery => _searchQuery;
  String? get selectedGender => _selectedGender;
  List<String> get selectedTypes => _selectedTypes;
  List<String> get selectedFits => _selectedFits;
  List<String> get selectedSizes => _selectedSizes;
  List<String> get selectedColors => _selectedColors;
  String? get selectedSubcategory => _selectedSubcategory;
  String? get selectedColorForDisplay => _selectedColorForDisplay;
  Map<String, List<Map<String, dynamic>>> get specFacets => _specFacets;
  Map<String, List<String>> get dynamicSpecFilters => _dynamicSpecFilters;

  List<QueryDocumentSnapshot> get shops => _shops;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get isInitialLoading => _isInitialLoading;
  bool get hasError => _hasError;
  bool get isSearchActive => _isSearchActive;
  bool get isSearchExpanded => _isSearchExpanded;

  int get currentIndex => _currentIndex;
  Map<String, double> get averageRatings => _averageRatings;
  User? get currentUser => _currentUser;
  bool get userOwnsShop => _userOwnsShop ?? false;
  bool get hasShopDocError => shopDocErrorNotifier.value;

  ShopProvider() {
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _userOwnsShop = false;
        _safeNotifyListeners();
      } else {
        _checkUserMembership(user.uid);
      }
    });

    // Run cache cleanup on initialization (non-blocking)
    _cleanupOldCaches();
  }

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;

    _isInitialized = true;
    _currentUser = _auth.currentUser;

    scrollController.addListener(_scrollListener);

    await _fetchInitialShopsWithTimeout();
  }

  Future<void> _fetchInitialShopsWithTimeout() async {
    _hasError = false;
    _isInitialLoading = true;
    _safeNotifyListeners();

    try {
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_loadTimeout, () {
        if (_isInitialLoading) {
          _handleLoadingTimeout();
        }
      });

      await _fetchInitialShops();

      _timeoutTimer?.cancel();
      _isInitialLoading = false;
      _safeNotifyListeners();

      // Check if viewport needs more content (for tablets/large screens)
      _checkViewportAndLoadMoreIfNeeded();
    } catch (e) {
      _timeoutTimer?.cancel();
      _handleLoadingError(e);
    }
  }

  void _handleLoadingTimeout() {
    print('Shop loading timed out');
    _isInitialLoading = false;
    _isLoadingMore = false;
    _hasError = true;
    _safeNotifyListeners();
  }

  void _handleLoadingError(dynamic error) {
    print('Error loading shops: $error');
    _isInitialLoading = false;
    _isLoadingMore = false;
    _hasError = true;
    _safeNotifyListeners();
  }

  Future<void> retryLoading() async {
    _hasError = false;
    _shops.clear();
    _lastDocument = null;
    _hasMore = true;
    _averageRatings.clear();
    await _fetchInitialShopsWithTimeout();
  }

  Future<void> fetchCollections() async {
    if (_shopDoc == null) {
      collectionsNotifier.value = [];
      isLoadingCollectionsNotifier.value = false;
      return;
    }

    final String shopId = _shopDoc!.id;
    isLoadingCollectionsNotifier.value = true;

    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .orderBy('createdAt', descending: true)
          .get();

      final collections = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .toList();

      collectionsNotifier.value = collections;
      _collections = collections;

      isLoadingCollectionsNotifier.value = false;
      _safeNotifyListeners();
    } catch (e) {
      print('Error fetching collections: $e');
      isLoadingCollectionsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  void _scrollListener() {
    if (_debounceTimer?.isActive ?? false) return;

    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 300 &&
          !_isLoadingMore &&
          !_isInitialLoading &&
          _hasMore &&
          !_hasError) {
        _fetchMoreShops();
      }
    });
  }

  /// Checks if viewport is not filled with content and loads more if needed.
  /// This handles the tablet/large screen case where initial content doesn't
  /// require scrolling, so the scroll listener never triggers pagination.
  void _checkViewportAndLoadMoreIfNeeded() {
    // Wait for the next frame to ensure layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;

      // Guard against calling when conditions aren't met
      if (_isLoadingMore || _isInitialLoading || !_hasMore || _hasError) return;

      // Check if scroll controller is attached
      if (!scrollController.hasClients) return;

      final position = scrollController.position;

      // If maxScrollExtent is 0 or very small, content doesn't fill viewport
      // Also check if we're already at the bottom (for cases with minimal scroll)
      final viewportNotFilled = position.maxScrollExtent <= 50;
      final atOrNearBottom = position.pixels >= position.maxScrollExtent - 300;

      if ((viewportNotFilled || atOrNearBottom) &&
          _hasMore &&
          !_isLoadingMore) {
        _fetchMoreShops();
      }
    });
  }

  Future<void> _fetchInitialShops() async {
    _shops.clear();
    _lastDocument = null;
    _hasMore = true;
    _averageRatings.clear();

    try {
      final query = _getShopsQuery().limit(_limit);
      final snapshot = await query.get();
      _processShops(snapshot);
    } catch (e) {
      print('Error fetching initial shops: $e');
      _hasMore = false;
      rethrow;
    }
  }

  Future<void> _fetchMoreShops() async {
    if (!_hasMore || _isLoadingMore || _lastDocument == null || _hasError)
      return;

    _isLoadingMore = true;
    _safeNotifyListeners();

    try {
      final query =
          _getShopsQuery().startAfterDocument(_lastDocument!).limit(_limit);
      final snapshot = await query.get().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Pagination timeout'),
          );
      _processShops(snapshot);
    } catch (e) {
      print('Error fetching more shops: $e');
      _hasMore = false;
    } finally {
      _isLoadingMore = false;
      _safeNotifyListeners();

      // Check if viewport still needs more content (for tablets/large screens)
      // This ensures continuous loading until the viewport is filled
      _checkViewportAndLoadMoreIfNeeded();
    }
  }

  void _processShops(QuerySnapshot snapshot) {
    if (snapshot.docs.isEmpty) {
      _hasMore = false;
      return;
    }

    if (snapshot.docs.length < _limit) {
      _hasMore = false;
    }

    _lastDocument = snapshot.docs.last;
    _shops.addAll(snapshot.docs);
  }

  Future<void> refreshShops() async {
    final now = DateTime.now();
    if (_lastShopsRefresh != null &&
        now.difference(_lastShopsRefresh!) < _shopsRefreshInterval) {
      return;
    }

    _lastShopsRefresh = now;
    _hasError = false;
    _isInitialLoading = true;
    _isLoadingMore = false;
    _safeNotifyListeners();

    try {
      // Fetch new data first before clearing
      final query = _getShopsQuery().limit(_limit);
      final snapshot = await query.get();

      // Only clear and update after successful fetch
      _shops.clear();
      _lastDocument = null;
      _hasMore = true;
      _averageRatings.clear();

      _processShops(snapshot);
    } catch (e) {
      _handleLoadingError(e);
    } finally {
      _isInitialLoading = false;
      _safeNotifyListeners();

      // Check if viewport needs more content (for tablets/large screens)
      _checkViewportAndLoadMoreIfNeeded();
    }
  }

  Future<void> clearShopSearch() async {
    searchController.clear();
    searchTerm = '';
    _isSearchActive = false;
    _isSearchExpanded = false;
    _hasError = false;
    _isInitialLoading = true;
    _safeNotifyListeners();

    try {
      // Fetch fresh data
      final query = _getShopsQuery().limit(_limit);
      final snapshot = await query.get();

      // Clear and update only after successful fetch
      _shops.clear();
      _lastDocument = null;
      _hasMore = true;
      _averageRatings.clear();

      _processShops(snapshot);
    } catch (e) {
      print('Error clearing shop search: $e');
      _hasError = true;
    } finally {
      _isInitialLoading = false;
      _safeNotifyListeners();

      // Check if viewport needs more content (for tablets/large screens)
      _checkViewportAndLoadMoreIfNeeded();
    }
  }

  // IMPROVED: More robust initialization with better error recovery
  Future<void> initializeData(
    MockDocumentSnapshot? shopDoc,
    String? shopId,
  ) async {
    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      print('Already initializing, waiting...');
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;

    try {
      await _performInitialization(shopDoc, shopId);
    } catch (e) {
      print('Initialization error: $e');
      _handleInitializationError();
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _performInitialization(
    MockDocumentSnapshot? shopDoc,
    String? shopId,
  ) async {
    // Clear previous data if switching shops
    final currentShopId = _shopDoc?.id;
    if (currentShopId != null && shopId != null && currentShopId != shopId) {
      await _clearPreviousShopData(currentShopId);
    }

    _resetShopState();

    if (shopDoc != null) {
      await _handleDirectShopDoc(shopDoc, shopId ?? shopDoc.id);
    } else if (shopId != null) {
      await _handleShopIdFetch(shopId);
    } else {
      throw Exception('No shop document or ID provided');
    }
  }

  Future<void> _clearPreviousShopData(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'shop_data_$shopId',
      'shop_products_$shopId',
      'shop_reviews_$shopId',
      'shop_last_fetch_$shopId'
    ];

    for (String key in keys) {
      await prefs.remove(key);
    }
  }

  void _resetShopState() {
    _shopDoc = null;
    allProductsNotifier.value = [];
    dealProductsNotifier.value = [];
    bestSellersNotifier.value = [];
    _reviews = [];
    _unfilteredProducts = [];

    shopDocErrorNotifier.value = false;
    isLoadingShopDocNotifier.value = true;
    isLoadingProductsNotifier.value = true;
    isLoadingReviewsNotifier.value = true;

    totalFiltersAppliedNotifier.value = 0;
    _sortOption = 'date';
    _searchQuery = '';
    _selectedGender = null;
    _selectedTypes = [];
    _selectedFits = [];
    _selectedSizes = [];
    _selectedColors = [];
    _selectedSubcategory = null;
    _selectedColorForDisplay = null;
    _lastShopFetch = null;
    _lastProductsFetch = null;

    _selectedBrands = [];
    _minPrice = null;
    _maxPrice = null;
    _specFacets = {};
    _dynamicSpecFilters = {};

    _lastProductDocument = null;
    _hasMoreProducts = true;
    _isLoadingMoreProducts = false;
    _allFetchedProducts = [];

    _safeNotifyListeners();
  }

  Future<void> _handleDirectShopDoc(
      MockDocumentSnapshot shopDoc, String shopId) async {
    _shopDoc = shopDoc;
    isLoadingShopDocNotifier.value = false;

    await loadCachedData(shopId);

    // Start parallel fetching
    final futures = [
      _fetchProductsWithTimeout(),
      _fetchReviewsWithTimeout(),
      fetchCollections(),
      _fetchSpecFacets(),
    ];

    await Future.wait(futures, eagerError: false);
  }

  Future<void> _handleShopIdFetch(String shopId) async {
    await loadCachedData(shopId);

    try {
      await _fetchShopDocumentWithTimeout(shopId);

      if (_shopDoc != null && !shopDocErrorNotifier.value) {
        final futures = [
          _fetchProductsWithTimeout(),
          _fetchReviewsWithTimeout(),
          fetchCollections(),
          _fetchSpecFacets(),
        ];

        await Future.wait(futures, eagerError: false);
      }
    } catch (e) {
      print('Failed to fetch shop document: $e');
      _handleInitializationError();
    }
  }

  Future<void> _fetchShopDocumentWithTimeout(String shopId) async {
    try {
      final doc =
          await _firestore.collection('shops').doc(shopId).get().timeout(
                _loadTimeout,
                onTimeout: () =>
                    throw TimeoutException('Shop document fetch timed out'),
              );

      if (doc.exists) {
        _shopDoc =
            MockDocumentSnapshot(shopId, doc.data() as Map<String, dynamic>);
        isLoadingShopDocNotifier.value = false;
        _lastShopFetch = DateTime.now();
        await _saveCachedData(shopId);
        _safeNotifyListeners();
      } else {
        throw Exception('Shop document does not exist');
      }
    } catch (e) {
      print('Error fetching shop document: $e');
      shopDocErrorNotifier.value = true;
      isLoadingShopDocNotifier.value = false;
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> _fetchProductsWithTimeout() async {
    try {
      await fetchProducts().timeout(
        _loadTimeout,
        onTimeout: () => throw TimeoutException('Products fetch timed out'),
      );
    } catch (e) {
      print('Error fetching products: $e');
      isLoadingProductsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  Future<void> _fetchReviewsWithTimeout() async {
    try {
      await fetchReviews().timeout(
        _loadTimeout,
        onTimeout: () => throw TimeoutException('Reviews fetch timed out'),
      );
    } catch (e) {
      print('Error fetching reviews: $e');
      isLoadingReviewsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  void _handleInitializationError() {
    shopDocErrorNotifier.value = true;
    isLoadingShopDocNotifier.value = false;
    isLoadingProductsNotifier.value = false;
    isLoadingReviewsNotifier.value = false;
    _safeNotifyListeners();
  }

  /// Safe notifyListeners that checks if provider is disposed
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners(); // ✅ CORRECT: Call the parent's notifyListeners()
    }
  }

  @override
  void dispose() {
    _isDisposed =
        true; // Mark as disposed first to prevent any pending notifyListeners calls
    _debounceTimer?.cancel();
    _timeoutTimer?.cancel();
    scrollController.dispose();
    searchController.dispose();

    _authSub?.cancel();

    // Dispose ValueNotifiers
    isLoadingShopDocNotifier.dispose();
    isLoadingProductsNotifier.dispose();
    isLoadingReviewsNotifier.dispose();
    allProductsNotifier.dispose();
    dealProductsNotifier.dispose();
    bestSellersNotifier.dispose();
    totalFiltersAppliedNotifier.dispose();
    shopDocErrorNotifier.dispose();
    unreadMessagesCount.dispose();
    unreadNotificationsCount.dispose();
    cartCount.dispose();
    collectionsNotifier.dispose();
    isLoadingCollectionsNotifier.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ————————————————————————————————————————————————————————————————————————————
  // RETRY LOGIC WITH EXPONENTIAL BACKOFF
  // ————————————————————————————————————————————————————————————————————————————

  /// Retries an operation with exponential backoff
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 200),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        final result = await operation();
        _onOperationSuccess();
        return result;
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) {
          _onOperationFailure();
          rethrow;
        }
        debugPrint(
            'Retry attempt $attempt/$maxAttempts after ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
  }

  // ————————————————————————————————————————————————————————————————————————————
  // CIRCUIT BREAKER PATTERN
  // ————————————————————————————————————————————————————————————————————————————

  /// Checks if circuit breaker is open (too many failures)
  bool _isCircuitBreakerOpen() {
    if (_circuitBreakerResetTime == null) return false;

    if (DateTime.now().isAfter(_circuitBreakerResetTime!)) {
      // Reset circuit breaker after cooldown
      _consecutiveFailures = 0;
      _circuitBreakerResetTime = null;
      debugPrint('Circuit breaker reset');
      return false;
    }

    return true;
  }

  void _onOperationSuccess() {
    if (_consecutiveFailures > 0) {
      _consecutiveFailures = 0;
      _circuitBreakerResetTime = null;
      debugPrint('Circuit breaker: Success, reset failure count');
    }
  }

  void _onOperationFailure() {
    _consecutiveFailures++;
    debugPrint('Circuit breaker: Failure count = $_consecutiveFailures');

    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _circuitBreakerResetTime =
          DateTime.now().add(_circuitBreakerResetDuration);
      debugPrint('Circuit breaker opened until $_circuitBreakerResetTime');
    }
  }

  // ————————————————————————————————————————————————————————————————————————————
  // CACHE SIZE MANAGEMENT
  // ————————————————————————————————————————————————————————————————————————————

  /// Cleans up old cache entries that exceed the expiry duration
  Future<void> _cleanupOldCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final now = DateTime.now();
      final keysToRemove = <String>[];

      for (final key in keys) {
        if (key.startsWith('shop_last_fetch_')) {
          final timestamp = prefs.getInt(key);
          if (timestamp != null) {
            final lastFetch = DateTime.fromMillisecondsSinceEpoch(timestamp);
            if (now.difference(lastFetch) > _cacheExpiryDuration) {
              // Extract shopId and remove all related keys
              final shopId = key.replaceFirst('shop_last_fetch_', '');
              keysToRemove.addAll([
                'shop_data_$shopId',
                'shop_products_$shopId',
                'shop_reviews_$shopId',
                'shop_last_fetch_$shopId',
              ]);
            }
          }
        }
      }

      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        debugPrint(
            'Cleaned up ${keysToRemove.length ~/ 4} expired shop caches');
      }
    } catch (e) {
      debugPrint('Error cleaning up old caches: $e');
    }
  }

  /// Checks if a cache entry exceeds the size limit
  bool _isCacheSizeExceeded(String jsonString) {
    final bytes = utf8.encode(jsonString).length;
    return bytes > _maxCacheSizeBytes;
  }

  /// Trims product list to maximum allowed size (LRU eviction)
  void _trimProductListIfNeeded() {
    if (_allFetchedProducts.length > _maxProductsInMemory) {
      final excess = _allFetchedProducts.length - _maxProductsInMemory;
      _allFetchedProducts = _allFetchedProducts.sublist(excess);
    }
  }

  void setShopDocError(bool err) {
    shopDocErrorNotifier.value = err;
    isLoadingShopDocNotifier.value = false;
  }

  Future<void> _checkUserMembership(String uid) async {
    try {
      // 1. Direct lookup on user document
      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        _userOwnsShop = false;
        _safeNotifyListeners();
        return;
      }

      final userData = userDoc.data();
      Map<String, dynamic> memberOfShops =
          Map<String, dynamic>.from(userData?['memberOfShops'] ?? {});

      if (memberOfShops.isEmpty) {
        _userOwnsShop = false;
        _safeNotifyListeners();
        return;
      }

      // 2. Iterate through all shop memberships to find at least one valid
      final List<String> shopsToRemove = [];
      bool foundValidMembership = false;

      for (final entry in memberOfShops.entries) {
        final shopId = entry.key;
        final userRole = entry.value as String;

        try {
          final shopDoc =
              await _firestore.collection('shops').doc(shopId).get();

          if (!shopDoc.exists) {
            // Shop was deleted, mark for cleanup
            shopsToRemove.add(shopId);
            continue;
          }

          final shopData = shopDoc.data() as Map<String, dynamic>;
          final stillMember =
              _verifyUserStillMemberOfShop(uid, userRole, shopData);

          if (stillMember) {
            foundValidMembership = true;
            // Found at least one valid membership, we can stop checking
            break;
          } else {
            // User is no longer member of this shop, mark for cleanup
            shopsToRemove.add(shopId);
          }
        } catch (e) {
          debugPrint('Error checking shop $shopId: $e');
          // Skip this shop but continue checking others
          continue;
        }
      }

      // 3. Clean up invalid memberships in a single batch operation
      if (shopsToRemove.isNotEmpty) {
        await _cleanupInvalidMemberships(uid, shopsToRemove);
      }

      // 4. Set the final state
      _userOwnsShop = foundValidMembership;
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('Error checking shop membership: $e');
      // Fallback to old method if new approach fails
      await _checkUserMembershipFallback(uid);
    }
  }

// New helper method to clean up multiple invalid memberships at once
  Future<void> _cleanupInvalidMemberships(
      String uid, List<String> shopIds) async {
    try {
      final Map<String, dynamic> updates = {};

      for (final shopId in shopIds) {
        updates['memberOfShops.$shopId'] = FieldValue.delete();
      }

      if (updates.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updates);
        debugPrint(
            'Cleaned up ${shopIds.length} invalid shop memberships for user $uid');
      }
    } catch (e) {
      debugPrint('Error cleaning up invalid memberships: $e');
      // If batch cleanup fails, try individual cleanup (less efficient but more resilient)
      for (final shopId in shopIds) {
        try {
          await _firestore.collection('users').doc(uid).update({
            'memberOfShops.$shopId': FieldValue.delete(),
          });
        } catch (individualError) {
          debugPrint(
              'Failed to cleanup membership for shop $shopId: $individualError');
        }
      }
    }
  }

  bool _verifyUserStillMemberOfShop(
      String uid, String role, Map<String, dynamic> shopData) {
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

  Future<void> _checkUserMembershipFallback(String uid) async {
    try {
      final futures = <Future<QuerySnapshot>>[
        _firestore
            .collection('shops')
            .where('ownerId', isEqualTo: uid)
            .limit(1)
            .get(),
        _firestore
            .collection('shops')
            .where('coOwners', arrayContains: uid)
            .limit(1)
            .get(),
        _firestore
            .collection('shops')
            .where('editors', arrayContains: uid)
            .limit(1)
            .get(),
        _firestore
            .collection('shops')
            .where('viewers', arrayContains: uid)
            .limit(1)
            .get(),
      ];

      final results = await Future.wait(futures);
      final ownsOrMember = results.any((snap) => snap.docs.isNotEmpty);

      if (ownsOrMember != _userOwnsShop) {
        _userOwnsShop = ownsOrMember;
        _safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('Fallback membership check failed: $e');
      _userOwnsShop = false;
      _safeNotifyListeners();
    }
  }

  Future<void> addUserToShopMembership(
      String userId, String shopId, String role) async {
    final batch = _firestore.batch();

    final shopRef = _firestore.collection('shops').doc(shopId);
    final userRef = _firestore.collection('users').doc(userId);

    // Update shop document
    switch (role) {
      case 'co-owner':
        batch.update(shopRef, {
          'coOwners': FieldValue.arrayUnion([userId])
        });
        break;
      case 'editor':
        batch.update(shopRef, {
          'editors': FieldValue.arrayUnion([userId])
        });
        break;
      case 'viewer':
        batch.update(shopRef, {
          'viewers': FieldValue.arrayUnion([userId])
        });
        break;
    }

    batch.set(
        userRef,
        {
          'memberOfShops': {shopId: role}
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> removeUserFromShopMembership(
      String userId, String shopId, String role) async {
    try {
      // Update shop document (your existing logic)
      final shopRef = _firestore.collection('shops').doc(shopId);

      switch (role) {
        case 'co-owner':
          await shopRef.update({
            'coOwners': FieldValue.arrayRemove([userId])
          });
          break;
        case 'editor':
          await shopRef.update({
            'editors': FieldValue.arrayRemove([userId])
          });
          break;
        case 'viewer':
          await shopRef.update({
            'viewers': FieldValue.arrayRemove([userId])
          });
          break;
      }

      // Also remove from user document
      await _firestore.collection('users').doc(userId).update({
        'memberOfShops.$shopId': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('Error removing user from shop membership: $e');
      rethrow;
    }
  }

  Query _getShopsQuery() {
    Query query = _firestore.collection('shops');

    // Only fetch active shops
    query = query.where('isActive', isEqualTo: true);

    if (selectedCategoryCode != null && selectedCategoryCode!.isNotEmpty) {
      query = query.where('category', isEqualTo: selectedCategoryCode);
    }

    if (searchTerm.isNotEmpty) {
      query = query
          .where('name', isGreaterThanOrEqualTo: searchTerm)
          .where('name', isLessThanOrEqualTo: searchTerm + '\uf8ff');
    }

    return query.orderBy('createdAt', descending: true);
  }

  Future<void> filterShops() async {
    _isFiltering = true;
    searchTerm = searchController.text.trim();
    _isSearchActive = searchTerm.isNotEmpty || selectedCategoryCode != null;

    _shops.clear();
    _lastDocument = null;
    _hasMore = true;
    _averageRatings.clear();
    _hasError = false;

    _safeNotifyListeners();

    try {
      await _fetchInitialShops();
    } catch (e) {
      print('Error filtering shops: $e');
    } finally {
      _isFiltering = false;
      _safeNotifyListeners();

      // Check if viewport needs more content (for tablets/large screens)
      _checkViewportAndLoadMoreIfNeeded();
    }
  }

  void resetSearch() {
    searchController.clear();
    searchTerm = '';
    selectedCategoryCode = null;
    _isSearchActive = false;
    _isSearchExpanded = false;
    _shops.clear();
    _lastDocument = null;
    _hasMore = true;
    _averageRatings.clear();
    _hasError = false;
    _safeNotifyListeners();
    filterShops();
  }

  void toggleSearchExpanded() {
    _isSearchExpanded = !_isSearchExpanded;
    _safeNotifyListeners();
  }

  void removeShop(String shopId) {
    _shops.removeWhere((shopDoc) => shopDoc.id == shopId);
    _safeNotifyListeners();
  }

  Future<void> incrementClickCount(String shopId) async {
    try {
      final shopRef = _firestore.collection('shops').doc(shopId);
      await shopRef.update({'clickCount': FieldValue.increment(1)});
    } catch (e) {
      print('Error incrementing click count: $e');
      rethrow;
    }
  }

  Future<void> loadCachedData(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedShopData = prefs.getString('shop_data_$shopId');
    final String? cachedProducts = prefs.getString('shop_products_$shopId');
    final String? cachedReviews = prefs.getString('shop_reviews_$shopId');
    final int? lastFetchTimestamp = prefs.getInt('shop_last_fetch_$shopId');

    if (cachedShopData != null && lastFetchTimestamp != null) {
      _lastShopFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchTimestamp);
      if (DateTime.now().difference(_lastShopFetch!) < Duration(minutes: 2)) {
        final Map<String, dynamic> shopMap =
            await compute(_decodeAndConvertShopData, cachedShopData);
        _shopDoc = MockDocumentSnapshot(shopId, shopMap);
        isLoadingShopDocNotifier.value = false;
        _safeNotifyListeners();
      }
    }

    if (cachedProducts != null && lastFetchTimestamp != null) {
      _lastProductsFetch =
          DateTime.fromMillisecondsSinceEpoch(lastFetchTimestamp);
      if (DateTime.now().difference(_lastProductsFetch!) <
          Duration(minutes: 2)) {
        final List<Map<String, dynamic>> productMaps =
            await compute(_decodeAndConvertListOfMaps, cachedProducts);

        final products =
            productMaps.map((json) => Product.fromJson(json)).toList();
        allProductsNotifier.value = products;
        dealProductsNotifier.value =
            products.where((p) => (p.discountPercentage ?? 0) > 0).toList();
        bestSellersNotifier.value = List.from(products)
          ..sort(
              (a, b) => (b.purchaseCount ?? 0).compareTo(a.purchaseCount ?? 0));
        isLoadingProductsNotifier.value = false;
        _safeNotifyListeners();
      }
    }

    if (cachedReviews != null) {
      final List<Map<String, dynamic>> reviewsList =
          await compute(_decodeAndConvertListOfMaps, cachedReviews);
      _reviews = reviewsList;
      isLoadingReviewsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  Future<void> refreshShopDetail() async {
    final now = DateTime.now();
    if (_lastManualRefresh != null &&
        now.difference(_lastManualRefresh!) < _refreshInterval) {
      return;
    }
    _lastManualRefresh = now;

    if (_shopDoc == null) return;

    _lastShopFetch = null;
    _lastProductsFetch = null;

    final shopId = _shopDoc!.id;
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'shop_data_$shopId',
      'shop_products_$shopId',
      'shop_reviews_$shopId',
      'shop_last_fetch_$shopId'
    ];
    for (String key in keys) {
      await prefs.remove(key);
    }

    isLoadingShopDocNotifier.value = true;
    isLoadingProductsNotifier.value = true;
    isLoadingReviewsNotifier.value = true;
    _safeNotifyListeners();

    try {
      await Future.wait([
        fetchShopDocument(shopId),
        fetchProducts(),
        fetchReviews(),
        fetchCollections(),
      ], eagerError: false);
    } catch (e) {
      print('Error during manual refresh: $e');
    } finally {
      isLoadingShopDocNotifier.value = false;
      isLoadingProductsNotifier.value = false;
      isLoadingReviewsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  Future<void> fetchShopDocumentIfNeeded(
      MockDocumentSnapshot? shopDoc, String? shopId) async {
    if (shopDoc != null) {
      _shopDoc = shopDoc;
      isLoadingShopDocNotifier.value = false;
      _safeNotifyListeners();
      await _saveCachedData(shopId ?? shopDoc.id);
      return;
    }

    if (shopId == null) return;

    if (_lastShopFetch != null &&
        DateTime.now().difference(_lastShopFetch!) <
            const Duration(minutes: 5)) {
      isLoadingShopDocNotifier.value = false;
      _safeNotifyListeners();
      return;
    }

    await fetchShopDocument(shopId);
  }

  Future<void> _saveCachedData(String shopId) async {
    final prefs = await SharedPreferences.getInstance();

    Map<String, dynamic> _convertTimestamps(Map<String, dynamic> data) {
      return data.map((key, value) {
        if (value is Timestamp) {
          return MapEntry(key, value.millisecondsSinceEpoch);
        } else if (value is Map<String, dynamic>) {
          return MapEntry(key, _convertTimestamps(value));
        } else if (value is List) {
          return MapEntry(
              key,
              value.map((item) {
                if (item is Timestamp) {
                  return item.millisecondsSinceEpoch;
                } else if (item is Map<String, dynamic>) {
                  return _convertTimestamps(item);
                }
                return item;
              }).toList());
        }
        return MapEntry(key, value);
      });
    }

    if (_shopDoc != null) {
      Map<String, dynamic> shopDataWithId = {
        'id': _shopDoc!.id,
        ..._shopDoc!.data() as Map<String, dynamic>,
      };
      Map<String, dynamic> encodableShopData =
          _convertTimestamps(shopDataWithId);
      final shopDataJson = jsonEncode(encodableShopData);

      // Only save if within size limit
      if (!_isCacheSizeExceeded(shopDataJson)) {
        await prefs.setString('shop_data_$shopId', shopDataJson);
      } else {
        debugPrint('Shop data cache exceeds size limit, skipping save');
      }
    }

    if (allProductsNotifier.value.isNotEmpty) {
      final productsJson =
          jsonEncode(allProductsNotifier.value.map((p) => p.toJson()).toList());

      // Only save if within size limit
      if (!_isCacheSizeExceeded(productsJson)) {
        await prefs.setString('shop_products_$shopId', productsJson);
      } else {
        debugPrint('Products cache exceeds size limit, skipping save');
      }
    }

    List<Map<String, dynamic>> encodableReviews =
        _reviews.map((review) => _convertTimestamps(review)).toList();
    final reviewsJson = jsonEncode(encodableReviews);

    // Only save if within size limit
    if (!_isCacheSizeExceeded(reviewsJson)) {
      await prefs.setString('shop_reviews_$shopId', reviewsJson);
    } else {
      debugPrint('Reviews cache exceeds size limit, skipping save');
    }

    await prefs.setInt(
        'shop_last_fetch_$shopId', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> fetchShopDocument(String shopId) async {
    if (_lastShopFetch != null &&
        DateTime.now().difference(_lastShopFetch!) <
            const Duration(minutes: 2)) {
      return;
    }

    // Check circuit breaker
    if (_isCircuitBreakerOpen()) {
      debugPrint('Circuit breaker open, skipping shop document fetch');
      shopDocErrorNotifier.value = true;
      isLoadingShopDocNotifier.value = false;
      _safeNotifyListeners();
      return;
    }

    isLoadingShopDocNotifier.value = true;
    _safeNotifyListeners();

    try {
      // Apply retry logic with exponential backoff
      DocumentSnapshot doc = await _retryWithBackoff(() async {
        return await _firestore.collection('shops').doc(shopId).get();
      });

      if (doc.exists) {
        _shopDoc =
            MockDocumentSnapshot(shopId, doc.data() as Map<String, dynamic>);
        isLoadingShopDocNotifier.value = false;
        _lastShopFetch = DateTime.now();
        await _saveCachedData(shopId);

        // Start fetching related data
        unawaited(fetchProducts());
        unawaited(fetchReviews());
      } else {
        isLoadingShopDocNotifier.value = false;
        shopDocErrorNotifier.value = true;
      }
      _safeNotifyListeners();
    } catch (e) {
      print('Error fetching shop document: $e');
      isLoadingShopDocNotifier.value = false;
      shopDocErrorNotifier.value = true;
      _safeNotifyListeners();
    }
  }

  bool _shouldUseTypesense() {
    if (_sortOption != 'date') return true;
    if (_dynamicSpecFilters.values.any((v) => v.isNotEmpty)) return true;
    return false;
  }

  Future<void> _fetchSpecFacets() async {
    if (_shopDoc == null) return;
    try {
      final shopId = _shopDoc!.id;
      final facets = await TypeSenseServiceManager.instance.shopService
          .fetchSpecFacets(
        indexName: 'shop_products',
        additionalFilterBy: 'shopId:=$shopId',
      );
      _specFacets = facets;
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('Error fetching spec facets for shop: $e');
    }
  }

  Future<void> _fetchProductsFromTypesense({bool loadMore = false}) async {
    if (_shopDoc == null) return;

    if (loadMore) {
      if (!_hasMoreProducts || _isLoadingMoreProducts) return;
      _isLoadingMoreProducts = true;
    } else {
      _hasMoreProducts = true;
      _allFetchedProducts = [];
      _lastProductDocument = null;
      isLoadingProductsNotifier.value = true;
    }
    _safeNotifyListeners();

    try {
      final shopId = _shopDoc!.id;

      // Build facet filters
      final facetFilters = <List<String>>[];
      if (_selectedGender != null) {
        facetFilters.add(['gender:$_selectedGender']);
      }
      if (_selectedSubcategory != null) {
        facetFilters.add(['subcategory:$_selectedSubcategory']);
      }
      if (_selectedBrands.isNotEmpty) {
        facetFilters.add(
            _selectedBrands.map((b) => 'brandModel:$b').toList());
      }
      if (_selectedTypes.isNotEmpty) {
        facetFilters.add(_selectedTypes
            .map((t) => 'attributes.clothingType:$t')
            .toList());
      }
      if (_selectedFits.isNotEmpty) {
        facetFilters.add(
            _selectedFits.map((f) => 'attributes.clothingFit:$f').toList());
      }
      if (_selectedColors.isNotEmpty) {
        facetFilters.add(
            _selectedColors.map((c) => 'colorImages.$c:*').toList());
      }

      // Dynamic spec filters
      for (final entry in _dynamicSpecFilters.entries) {
        if (entry.value.isNotEmpty) {
          facetFilters.add(
              entry.value.map((v) => '${entry.key}:$v').toList());
        }
      }

      // Numeric filters
      final numericFilters = <String>[];
      if (_minPrice != null) numericFilters.add('price >= $_minPrice');
      if (_maxPrice != null) numericFilters.add('price <= $_maxPrice');

      final page = loadMore
          ? (_allFetchedProducts.length / _productsLimit).floor()
          : 0;

      final result = await TypeSenseServiceManager.instance.shopService
          .searchIdsWithFacets(
        indexName: 'shop_products',
        query: _searchQuery.isNotEmpty ? _searchQuery : '',
        page: page,
        hitsPerPage: _productsLimit,
        facetFilters: facetFilters.isNotEmpty ? facetFilters : null,
        numericFilters: numericFilters.isNotEmpty ? numericFilters : null,
        sortOption: _sortOption,
        additionalFilterBy: 'shopId:=$shopId',
      );

      final newProducts = result.hits
          .map((hit) => Product.fromTypeSense(hit))
          .toList();

      if (newProducts.length < _productsLimit) {
        _hasMoreProducts = false;
      }

      if (loadMore) {
        _allFetchedProducts.addAll(newProducts);
      } else {
        _allFetchedProducts = newProducts;
      }

      _unfilteredProducts = List.from(_allFetchedProducts);
      // No need for local _applyAllFilters — Typesense already filtered
      allProductsNotifier.value = List.from(_allFetchedProducts);
      dealProductsNotifier.value = _allFetchedProducts
          .where((p) => (p.discountPercentage ?? 0) > 0)
          .toList();
      bestSellersNotifier.value = List.from(_allFetchedProducts)
        ..sort(
            (a, b) => (b.purchaseCount ?? 0).compareTo(a.purchaseCount ?? 0));
    } catch (e) {
      debugPrint('Error fetching products from Typesense: $e');
    } finally {
      if (loadMore) {
        _isLoadingMoreProducts = false;
      } else {
        isLoadingProductsNotifier.value = false;
      }
      _safeNotifyListeners();
    }
  }

  Future<void> fetchProducts({bool loadMore = false}) async {
    // Route to Typesense when sort or spec filters are active
    if (_shouldUseTypesense()) {
      return _fetchProductsFromTypesense(loadMore: loadMore);
    }

    if (_shopDoc == null) {
      allProductsNotifier.value = [];
      dealProductsNotifier.value = [];
      bestSellersNotifier.value = [];
      _unfilteredProducts = [];
      isLoadingProductsNotifier.value = false;
      _safeNotifyListeners();
      return;
    }

    // If loading more, check if we can
    if (loadMore) {
      if (!_hasMoreProducts ||
          _isLoadingMoreProducts ||
          _lastProductDocument == null) {
        return;
      }
      _isLoadingMoreProducts = true;
    } else {
      // Reset pagination for new fetch
      _lastProductDocument = null;
      _hasMoreProducts = true;
      _allFetchedProducts = [];
      isLoadingProductsNotifier.value = true;
    }

    _safeNotifyListeners();

    try {
      final String shopId = _shopDoc!.id;
      Query query = _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId);

      // Apply server-side filters
      if (_selectedGender != null) {
        query = query.where('gender', isEqualTo: _selectedGender);
      }

      if (_selectedSubcategory != null) {
        query = query.where('subcategory', isEqualTo: _selectedSubcategory);
      }

      if (_minPrice != null) {
        query = query.where('price', isGreaterThanOrEqualTo: _minPrice);
      }
      if (_maxPrice != null) {
        query = query.where('price', isLessThanOrEqualTo: _maxPrice);
      }

      // Apply sorting
      switch (_sortOption) {
        case 'alphabetical':
          query = query.orderBy('productName', descending: false);
          break;
        case 'price_asc':
          query = query.orderBy('price', descending: false);
          break;
        case 'price_desc':
          query = query.orderBy('price', descending: true);
          break;
        case 'date':
        default:
          query = query.orderBy('createdAt', descending: true);
          break;
      }

      // Add pagination
      if (loadMore && _lastProductDocument != null) {
        query = query.startAfterDocument(_lastProductDocument!);
      }
      query = query.limit(_productsLimit);

      // Apply retry logic with exponential backoff
      QuerySnapshot snapshot = await _retryWithBackoff(() async {
        return await query.get();
      });
      List<Product> newProducts =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

      if (snapshot.docs.isEmpty || newProducts.length < _productsLimit) {
        _hasMoreProducts = false;
      }

      if (snapshot.docs.isNotEmpty) {
        _lastProductDocument = snapshot.docs.last;
      }

      if (loadMore) {
        _allFetchedProducts.addAll(newProducts);
        // Apply memory management: trim if exceeds limit
        _trimProductListIfNeeded();
      } else {
        _allFetchedProducts = newProducts;
      }

      _unfilteredProducts = List.from(_allFetchedProducts);
      _applyAllFilters(List.from(_allFetchedProducts));

      _lastProductsFetch = DateTime.now();
      await _saveCachedData(_shopDoc!.id);
    } catch (e) {
      print('Error fetching products: $e');
      if (!loadMore) {
        isLoadingProductsNotifier.value = false;
      }
    } finally {
      if (loadMore) {
        _isLoadingMoreProducts = false;
      } else {
        isLoadingProductsNotifier.value = false;
      }
      _safeNotifyListeners();
    }
  }

  Future<void> loadMoreProducts() async {
    await fetchProducts(loadMore: true);
  }

  void _applyAllFilters(List<Product> products) {
    if (_searchQuery.isNotEmpty) {
      products = products.where((product) {
        return product.productName
            .toLowerCase()
            .contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedBrands.isNotEmpty) {
      products = products.where((product) {
        return _selectedBrands.any((brand) =>
            product.brandModel?.toLowerCase() == brand.toLowerCase() ||
            product.brandModel?.toLowerCase().contains(brand.toLowerCase()) ==
                true);
      }).toList();
    }

    if (_selectedTypes.isNotEmpty) {
      products = products.where((product) {
        final String? clothingType = product.attributes['clothingType'];
        return clothingType != null && _selectedTypes.contains(clothingType);
      }).toList();
    }

    if (_selectedFits.isNotEmpty) {
      products = products.where((product) {
        final String? clothingFit = product.attributes['clothingFit'];
        return clothingFit != null && _selectedFits.contains(clothingFit);
      }).toList();
    }

    if (_selectedSizes.isNotEmpty) {
      products = products.where((product) {
        final List<dynamic> productSizes =
            product.attributes['clothingSizes'] ?? [];
        return _selectedSizes.any((size) => productSizes.contains(size));
      }).toList();
    }

    if (_selectedColors.isNotEmpty) {
      products = products.where((product) {
        final Map<String, dynamic> colorImages = product.colorImages ?? {};
        return _selectedColors.any((color) => colorImages.containsKey(color));
      }).toList();
    }

    if (_minPrice != null || _maxPrice != null) {
      products = products.where((product) {
        final price = product.price;
        bool passesMin = _minPrice == null || price >= _minPrice!;
        bool passesMax = _maxPrice == null || price <= _maxPrice!;
        return passesMin && passesMax;
      }).toList();
    }

    allProductsNotifier.value = products;
    dealProductsNotifier.value =
        products.where((p) => (p.discountPercentage ?? 0) > 0).toList();
    bestSellersNotifier.value = List.from(products)
      ..sort((a, b) => (b.purchaseCount ?? 0).compareTo(a.purchaseCount ?? 0));
  }

  List<String> getAvailableCategories() {
    final Set<String> categories = <String>{};

    for (final product in allProductsNotifier.value) {
      if (product.subcategory.isNotEmpty) {
        categories.add(product.subcategory);
      }
    }

    return categories.toList()..sort();
  }

  String getLocalizedCategoryName(String category, AppLocalizations l10n) {
    if (_shopDoc == null) return category;

    final Map<String, dynamic> shopData =
        _shopDoc!.data() as Map<String, dynamic>;
    final dynamic shopCategories = shopData['categories'];
    String shopMainCategory = '';

    if (shopCategories is List && shopCategories.isNotEmpty) {
      shopMainCategory = shopCategories.first;
    } else if (shopCategories is String) {
      shopMainCategory = shopCategories;
    }

    try {
      return AllInOneCategoryData.localizeSubcategoryKey(
          shopMainCategory, category, l10n);
    } catch (e) {
      for (String mainCategory in AllInOneCategoryData.kSubcategories.keys) {
        if (AllInOneCategoryData.kSubcategories[mainCategory]
                ?.contains(category) ==
            true) {
          try {
            return AllInOneCategoryData.localizeSubcategoryKey(
                mainCategory, category, l10n);
          } catch (e) {
            continue;
          }
        }
      }
    }

    return category;
  }

  void filterProductsLocally(String query) {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      // If query is empty, show original products
      _searchQuery = '';
      _searchResults = [];
      _applyAllFilters(List.from(_unfilteredProducts));
      _safeNotifyListeners();
      return;
    }

    _searchQuery = trimmedQuery;

    // Cancel previous search
    _searchDebounce?.cancel();

    // Start new debounced search
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performTypesenseSearch(trimmedQuery);
    });
  }

  Future<void> _performTypesenseSearch(String query) async {
    if (_shopDoc == null || query.isEmpty) return;

    // Check circuit breaker
    if (_isCircuitBreakerOpen()) {
      debugPrint('Circuit breaker open, skipping Typesense search');
      _fallbackToLocalSearch(query);
      return;
    }

    // Increment race token to invalidate previous searches
    _searchRaceToken++;
    final currentToken = _searchRaceToken;

    _isSearching = true;
    _lastSearchQuery = query;
    _safeNotifyListeners();

    try {
      final shopId = _shopDoc!.id;

      // Build filters for current shop
      List<String> filters = [];

      // Add existing filters
      if (_selectedGender != null) {
        filters.add('gender:"$_selectedGender"');
      }

      if (_selectedSubcategory != null) {
        filters.add('subcategory:"$_selectedSubcategory"');
      }

      if (_selectedBrands.isNotEmpty) {
        final brandFilters =
            _selectedBrands.map((brand) => 'brandModel:"$brand"').join(' OR ');
        filters.add('($brandFilters)');
      }

      if (_selectedTypes.isNotEmpty) {
        final typeFilters = _selectedTypes
            .map((type) => 'attributes.clothingType:"$type"')
            .join(' OR ');
        filters.add('($typeFilters)');
      }

      if (_selectedFits.isNotEmpty) {
        final fitFilters = _selectedFits
            .map((fit) => 'attributes.clothingFit:"$fit"')
            .join(' OR ');
        filters.add('($fitFilters)');
      }

      if (_selectedColors.isNotEmpty) {
        final colorFilters =
            _selectedColors.map((color) => 'colorImages.$color:*').join(' OR ');
        filters.add('($colorFilters)');
      }

      if (_minPrice != null) {
        filters.add('price >= $_minPrice');
      }

      if (_maxPrice != null) {
        filters.add('price <= $_maxPrice');
      }

      // Use the shop-specific search method with retry logic
      final results = await _retryWithBackoff(() async {
        return await TypeSenseServiceManager.instance.shopService
            .searchShopProducts(
          shopId: shopId,
          query: query,
          sortOption: _sortOption,
          additionalFilters: filters,
          hitsPerPage: 100,
        );
      });

      // Only update if this is still the latest search (race token check)
      if (currentToken == _searchRaceToken) {
        _searchResults = results;

        // Update the main product lists with search results
        allProductsNotifier.value = results;
        dealProductsNotifier.value =
            results.where((p) => (p.discountPercentage ?? 0) > 0).toList();
        bestSellersNotifier.value = List.from(results)
          ..sort(
              (a, b) => (b.purchaseCount ?? 0).compareTo(a.purchaseCount ?? 0));
      } else {
        debugPrint('Stale search result discarded (token mismatch)');
      }
    } catch (e) {
      print('Typesense search error: $e');
      // Fallback to local search if Typesense fails
      _fallbackToLocalSearch(query);
    } finally {
      _isSearching = false;
      _safeNotifyListeners();
    }
  }

  void _fallbackToLocalSearch(String query) {
    final filteredProducts = _unfilteredProducts.where((product) {
      final searchableText = [
        product.productName,
        product.brandModel ?? '',
        product.category ?? '',
        product.subcategory ?? '',
      ].join(' ').toLowerCase();

      return searchableText.contains(query.toLowerCase());
    }).toList();

    _applyAllFilters(filteredProducts);
  }

  void clearAllFilters() {
    _selectedGender = null;
    _selectedBrands = [];
    _selectedTypes = [];
    _selectedFits = [];
    _selectedSizes = [];
    _selectedColors = [];
    _minPrice = null;
    _maxPrice = null;
    _selectedSubcategory = null;
    _selectedColorForDisplay = null;
    _dynamicSpecFilters = {};
    totalFiltersAppliedNotifier.value = 0;

    // Clear search
    _searchQuery = '';
    _searchResults = [];
    _lastSearchQuery = '';

    _lastProductsFetch = null;
    fetchProducts();
    _safeNotifyListeners();
  }

  String getFilterSummary() {
    List<String> summaryParts = [];

    if (_selectedGender != null) {
      summaryParts.add(_selectedGender!);
    }

    if (_selectedBrands.isNotEmpty) {
      summaryParts.add(
          '${_selectedBrands.length} brand${_selectedBrands.length > 1 ? 's' : ''}');
    }

    if (_selectedTypes.isNotEmpty) {
      summaryParts.add(
          '${_selectedTypes.length} type${_selectedTypes.length > 1 ? 's' : ''}');
    }

    if (_selectedFits.isNotEmpty) {
      summaryParts.add(
          '${_selectedFits.length} fit${_selectedFits.length > 1 ? 's' : ''}');
    }

    if (_selectedSizes.isNotEmpty) {
      summaryParts.add(
          '${_selectedSizes.length} size${_selectedSizes.length > 1 ? 's' : ''}');
    }

    if (_selectedColors.isNotEmpty) {
      summaryParts.add(
          '${_selectedColors.length} color${_selectedColors.length > 1 ? 's' : ''}');
    }

    if (_minPrice != null || _maxPrice != null) {
      if (_minPrice != null && _maxPrice != null) {
        summaryParts.add('${_minPrice!.toInt()}-${_maxPrice!.toInt()} TL');
      } else if (_minPrice != null) {
        summaryParts.add('${_minPrice!.toInt()}+ TL');
      } else {
        summaryParts.add('< ${_maxPrice!.toInt()} TL');
      }
    }

    return summaryParts.isEmpty ? '' : summaryParts.join(', ');
  }

  Future<void> fetchReviews() async {
    if (_shopDoc == null) return;
    String shopId = _shopDoc!.id;

    isLoadingReviewsNotifier.value = true;
    _safeNotifyListeners();

    try {
      // Apply retry logic with exponential backoff
      QuerySnapshot snapshot = await _retryWithBackoff(() async {
        return await _firestore
            .collection('shops')
            .doc(shopId)
            .collection('reviews')
            .orderBy('timestamp', descending: true)
            .get();
      });

      _reviews = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        // ✅ FIX: Convert Timestamp to milliseconds for serialization
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] =
              (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }

        return data;
      }).toList();

      isLoadingReviewsNotifier.value = false;
      await _saveCachedData(shopId);
      _safeNotifyListeners();
    } catch (e) {
      print('Error fetching reviews: $e');
      isLoadingReviewsNotifier.value = false;
      _safeNotifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _lastProductsFetch = null;
    fetchProducts();
  }

  void setSortOption(String option) {
    _sortOption = option;

    // If there's an active search, re-run it with new sort option
    if (_searchQuery.isNotEmpty) {
      _performTypesenseSearch(_searchQuery);
    } else {
      _lastProductsFetch = null;
      fetchProducts();
    }
  }

  void updateFilters({
    String? gender,
    List<String> brands = const [],
    List<String> types = const [],
    List<String> fits = const [],
    List<String> sizes = const [],
    List<String> colors = const [],
    double? minPrice,
    double? maxPrice,
    int totalFilters = 0,
    Map<String, List<String>> specFilters = const {},
  }) {
    _selectedGender = gender;
    _selectedBrands = brands;
    _selectedTypes = types;
    _selectedFits = fits;
    _selectedSizes = sizes;
    _selectedColors = colors;
    _minPrice = minPrice;
    _maxPrice = maxPrice;
    _dynamicSpecFilters = Map.from(specFilters);
    _selectedColorForDisplay = colors.isNotEmpty ? colors.first : null;

    // Count includes spec filter selections
    int specCount = 0;
    for (final vals in _dynamicSpecFilters.values) {
      specCount += vals.length;
    }
    totalFiltersAppliedNotifier.value = totalFilters + specCount;

    // If there's an active search, re-run it with new filters
    if (_searchQuery.isNotEmpty) {
      _performTypesenseSearch(_searchQuery);
    } else {
      _lastProductsFetch = null;
      fetchProducts();
    }
  }

  void setSelectedSubcategory(String? subcategory) {
    _selectedSubcategory = subcategory;

    // If there's an active search, re-run it with new subcategory filter
    if (_searchQuery.isNotEmpty) {
      _performTypesenseSearch(_searchQuery);
    } else {
      _lastProductsFetch = null;
      fetchProducts();
    }
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    _lastSearchQuery = '';
    _searchDebounce?.cancel();

    // Return to showing all products with current filters
    _applyAllFilters(List.from(_unfilteredProducts));
    _safeNotifyListeners();
  }

  Future<void> checkUserOwnsShop() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _userOwnsShop = false;
      _safeNotifyListeners();
      return;
    }

    QuerySnapshot snapshot = await _firestore
        .collection('shops')
        .where('ownerId', isEqualTo: userId)
        .limit(1)
        .get();
    _userOwnsShop = snapshot.docs.isNotEmpty;
    _safeNotifyListeners();
  }

  Future<void> toggleShopReviewLike(
      String shopId, String reviewId, bool currentlyLiked) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final reviewRef = _firestore
        .collection('shops')
        .doc(shopId)
        .collection('reviews')
        .doc(reviewId);

    try {
      final docSnapshot = await reviewRef.get();
      if (!docSnapshot.exists) return;

      if (currentlyLiked) {
        await reviewRef.update({
          'likes': FieldValue.arrayRemove([userId])
        });
      } else {
        await reviewRef.update({
          'likes': FieldValue.arrayUnion([userId])
        });
      }

      final reviewIndex = _reviews.indexWhere((r) => r['id'] == reviewId);
      if (reviewIndex != -1) {
        final updatedLikes =
            List<dynamic>.from(_reviews[reviewIndex]['likes'] ?? []);

        if (currentlyLiked) {
          updatedLikes.remove(userId);
        } else {
          if (!updatedLikes.contains(userId)) {
            updatedLikes.add(userId);
          }
        }

        _reviews[reviewIndex] = Map<String, dynamic>.from(_reviews[reviewIndex])
          ..['likes'] = updatedLikes;

        await _saveCachedData(shopId);
        _safeNotifyListeners();
      }
    } catch (e) {
      print('Error toggling review like: $e');
      rethrow;
    }
  }

  bool get canRefresh {
    if (_lastShopsRefresh == null) return true;
    return DateTime.now().difference(_lastShopsRefresh!) >=
        _shopsRefreshInterval;
  }

  Duration get remainingCooldownTime {
    if (_lastShopsRefresh == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_lastShopsRefresh!);
    final remaining = _shopsRefreshInterval - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

// Helper function for unawaited futures
void unawaited(Future<void> future) {
  future.catchError((error) => print('Unawaited future error: $error'));
}
