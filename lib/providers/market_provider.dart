import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_summary.dart';
import '../services/typesense_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../constants/all_in_one_category_data.dart';
import '../utils/debouncer.dart';
import '../user_provider.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:retry/retry.dart';
import '../services/typesense_service_manager.dart';
import 'package:flutter/foundation.dart';
import '../services/analytics_service.dart';
import '../services/click_tracking_service.dart';
import '../services/user_activity_service.dart';
import '../services/lifecycle_aware.dart';
import '../services/app_lifecycle_manager.dart';
import '../services/search_config_service.dart';
import '../services/firestore_read_tracker.dart';

class _RequestDeduplicator {
  final Map<String, Future<List<ProductSummary>>> _pending = {};

  Future<List<ProductSummary>> deduplicate(
    String key,
    Future<List<ProductSummary>> Function() request,
  ) async {
    // Return existing request if in progress
    if (_pending.containsKey(key)) {
      return _pending[key]!;
    }

    // Start new request
    final future = request();
    _pending[key] = future;

    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  void clear() => _pending.clear();
}

/// -----------------------------------------------------------------------------
/// A more robust and efficient MarketProvider with improved concurrency,
/// owner verification caching, and transactional updates.
/// -----------------------------------------------------------------------------
class MarketProvider with ChangeNotifier, LifecycleAwareMixin {
  final UserProvider userProvider;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.low;

  // Auth subscription for lifecycle management
  StreamSubscription<User?>? _authSubscription;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  TypeSenseServiceManager get _typesenseManager =>
      TypeSenseServiceManager.instance;
  TypeSenseService get typesenseService => _typesenseManager.mainService;
  TypeSenseService get typesenseShopService => _typesenseManager.shopService;
  final Debouncer _notifyDebouncer =
      Debouncer(delay: const Duration(milliseconds: 200));

  final _RequestDeduplicator _searchDeduplicator = _RequestDeduplicator();

  String? _nextPageToken;
  String? get nextPageToken => _nextPageToken;

  DateTime? _nextCleanupNeeded;

  String? _selectedSubcategory;

  Timer? _cacheCleanupTimer;
  bool _isDisposed = false;

  bool get mounted => !_isDisposed;

  final Map<String, List<ProductSummary>> _buyerCategoryCache = {};
  final Map<String, DateTime> _buyerCategoryTimestamps = {};
  final Map<String, List<ProductSummary>> _buyerCategoryTerasCache = {};
  final Map<String, DateTime> _buyerCategoryTerasTimestamps = {};
  static const Duration _buyerCategoryCacheTTL = Duration(minutes: 20);
  static const int _maxBuyerCategoryCacheSize = 10;

  int _TypseSenseFailureCount = 0;
  DateTime? _lastTypseSenseFailure;
  bool _TypseSenseCircuitOpen = false;
  static const int _maxFailures = 8;
  static const Duration _circuitCooldown = Duration(minutes: 5);

  // Boosted products
  final List<ProductSummary> _boostedProducts = [];
  List<ProductSummary> get boostedProducts => _boostedProducts;

  // Current user info
  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  String? _dynamicBrand;
  List<String> _dynamicColors = [];

  /// Public getter if you need it elsewhere
  String? get dynamicBrand => _dynamicBrand;
  List<String> get dynamicColors => List.unmodifiable(_dynamicColors);

  final Map<String, List<ProductSummary>> _productCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 5);
  static const Duration _maxAge = Duration(minutes: 5);

  final Debouncer _cartDebouncer =
      Debouncer(delay: const Duration(milliseconds: 500));

  List<ProductSummary> _recommendedProducts = [];
  List<ProductSummary> get recommendedProducts => _recommendedProducts;

  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  // The main product list + set of IDs
  final List<ProductSummary> _products = [];
  List<ProductSummary> get products => _products;

  final Set<String> _productIds = {};
  // Filtering states
  bool _isFiltering = false;
  bool get isFiltering => _isFiltering;

  bool _isSearchActive = false;
  bool get isSearchActive => _isSearchActive;

  bool _recordImpressions = true;
  bool get recordImpressions => _recordImpressions;
  set recordImpressions(bool value) {
    _recordImpressions = value;
  }

  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  String? _selectedSubSubcategory;
  String? get selectedSubSubcategory => _selectedSubSubcategory;

  double? _minPrice;
  double? get minPrice => _minPrice;

  double? _maxPrice;
  double? get maxPrice => _maxPrice;

  String _sortOption = 'date';
  String get sortOption => _sortOption;

  // For sidebar expansion
  final ValueNotifier<bool> _isSidebarExpanded = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isSidebarExpanded => _isSidebarExpanded;
  double get expandedWidth => 180;
  double get collapsedWidth => 60;

  // For bottom nav
  int _currentIndex = 1;
  int get currentIndex => _currentIndex;

  // For messages & notifications
  final ValueNotifier<int> unreadMessagesCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> favoritePropertiesCount = ValueNotifier<int>(0);

  double get bottomNavigationBarHeight => 50.0;

  // Provide categories to the UI
  List<Map<String, String>> get categories => AllInOneCategoryData.kCategories;
  Map<String, List<String>> get categoryKeywords =>
      AllInOneCategoryData.kCategoryKeywordsMap;
  Map<String, List<String>> get subcategories =>
      AllInOneCategoryData.kSubcategories;

  DocumentSnapshot? _lastDocument;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// ---------------------------------------------------------------------------
  /// Constructor
  /// ---------------------------------------------------------------------------
  MarketProvider(this.userProvider) {
    // Listen to user changes
    _authSubscription?.cancel();
    _authSubscription = _auth.userChanges().listen((user) async {
      // Make it async
      if (_currentUserId != user?.uid) {
        _currentUserId = user?.uid;
        if (user == null) {
          resetProviderState();
          // Clear recommendations - will be handled by PersonalizedRecommendationsProvider
          _recommendedProducts = [];
        } else {
          // Clear cache to force fresh personalized recommendations
          _recommendedProducts = [];
        }

        unreadNotificationsCount.value = 0;

        _notifyDebouncer.run(() => notifyListeners());
      }
    });

    // Initialize only cart and favorites (recommendations handled separately)
    _initializeMarketData();

    // 3) Start periodic cleanup and keep a reference for dispose()
    _cacheCleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupCaches(),
    );

    // Register with lifecycle manager
    AppLifecycleManager.instance.register(this, name: 'MarketProvider');
    markInitialized();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> onPause() async {
    await super.onPause();

    // Pause cache cleanup timer
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;

    // Clear any pending deduplicators
    _searchDeduplicator.clear();

    if (kDebugMode) {
      debugPrint('⏸️ MarketProvider: Timer paused, deduplicator cleared');
    }
  }

  @override
  Future<void> onResume(Duration pauseDuration) async {
    await super.onResume(pauseDuration);

    // Restart cache cleanup timer
    _cacheCleanupTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupCaches(),
    );

    // If long pause, clean up stale caches
    if (shouldFullRefresh(pauseDuration)) {
      if (kDebugMode) {
        debugPrint('🔄 MarketProvider: Long pause, cleaning stale caches');
      }
      _cleanupCaches();
    }

    if (kDebugMode) {
      debugPrint('▶️ MarketProvider: Timer resumed');
    }
  }

  void _cleanupCaches() {
    if (_nextCleanupNeeded == null ||
        DateTime.now().isBefore(_nextCleanupNeeded!)) {
      return; // Nothing to clean yet
    }

    final now = DateTime.now();
    int removedCount = 0;

    // O(n) single pass removal of expired entries
    _cacheTimestamps.removeWhere((key, timestamp) {
      if (now.difference(timestamp) > _maxAge) {
        // ✅ Use class constant
        _productCache.remove(key);
        _searchCache.remove(key);
        removedCount++;
        return true;
      }
      return false;
    });

    // Enforce size limits only if needed (avoids unnecessary sorting)
    if (_productCache.length > 30) {
      _enforceProductCacheLimit();
    }

    if (_searchCache.length > 50) {
      _enforceSearchCacheLimit();
    }

    // ✅ Calculate next cleanup time
    _nextCleanupNeeded = null;
    for (final timestamp in _cacheTimestamps.values) {
      final expiresAt = timestamp.add(_maxAge);
      if (_nextCleanupNeeded == null ||
          expiresAt.isBefore(_nextCleanupNeeded!)) {
        _nextCleanupNeeded = expiresAt;
      }
    }

    if (kDebugMode && removedCount > 0) {
      debugPrint('🧹 Cleaned $removedCount expired cache entries');
    }
  }

  void _enforceProductCacheLimit() {
    // Only sort when we actually need to remove items
    final sortedKeys = _cacheTimestamps.entries
        .where((e) => _productCache.containsKey(e.key))
        .map((e) => MapEntry(e.key, e.value))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = sortedKeys.take(sortedKeys.length - 20).map((e) => e.key);
    for (final key in toRemove) {
      _productCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  void _enforceSearchCacheLimit() {
    // Only sort when we actually need to remove items
    final sortedKeys = _cacheTimestamps.entries
        .where((e) => _searchCache.containsKey(e.key))
        .map((e) => MapEntry(e.key, e.value))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // Oldest first

    // Keep only 30 newest search results
    final toRemove = sortedKeys.take(sortedKeys.length - 30).map((e) => e.key);

    for (final key in toRemove) {
      _searchCache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (kDebugMode) {
      debugPrint('🧹 Search cache trimmed to ${_searchCache.length} entries');
    }
  }

  @override
  void dispose() {
    debugPrint('🗑️ MarketProvider: Starting disposal...');
    _isDisposed = true;
    // Rest of cleanup (synchronous)...
    _cacheCleanupTimer?.cancel();

    _notifyDebouncer.cancel();
    _cartDebouncer.cancel();
    _searchDeduplicator.clear();

    _isSidebarExpanded.dispose();
    unreadMessagesCount.dispose();
    unreadNotificationsCount.dispose();
    favoritePropertiesCount.dispose();

    _products.clear();
    _productIds.clear();
    _recommendedProducts.clear();
    _boostedProducts.clear();

    _productCache.clear();
    _cacheTimestamps.clear();
    _searchCache.clear();

    _buyerCategoryCache.clear();
    _buyerCategoryTimestamps.clear();
    _buyerCategoryTerasCache.clear();
    _buyerCategoryTerasTimestamps.clear();

    _currentUserId = null;
    _lastDocument = null;
    _nextPageToken = null;
    _nextCleanupNeeded = null;
    _selectedCategory = null;
    _selectedSubcategory = null;
    _selectedSubSubcategory = null;
    _dynamicBrand = null;
    _dynamicColors = [];
    _minPrice = null;
    _maxPrice = null;
    _sortOption = 'date';
    _hasMore = true;
    _isLoadingMore = false;
    _isFiltering = false;
    _isSearchActive = false;
    _TypseSenseFailureCount = 0;
    _lastTypseSenseFailure = null;
    _TypseSenseCircuitOpen = false;

    debugPrint('✅ MarketProvider: Disposal complete');
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// Initialization
  /// ---------------------------------------------------------------------------

  Future<void> _initializeMarketData() async {
    try {
      if (_auth.currentUser == null) {
        _recommendedProducts =
            []; // Initialize as empty, let UI handle fetching
      } else {
        // Authenticated: recommendations will be handled by the new provider
        // Just initialize as empty here
        _recommendedProducts = [];
      }
    } catch (e) {
      debugPrint("Error initializing market data: $e");
      _recommendedProducts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> incrementImpressionCount({
    required List<String> productIds,
    String? userGender, // ADD
    int? userAge, // ADD
  }) async {
    if (productIds.isEmpty) return;

    try {
      await AnalyticsService.trackCloudFunction(
        functionName: 'incrementImpressionCount',
        execute: () async {
          final callable = _functions.httpsCallable('incrementImpressionCount');
          return await callable.call({
            'productIds': productIds,
            'userGender': userGender, // ADD
            'userAge': userAge, // ADD
          });
        },
        metadata: {'batch_size': productIds.length},
      );
    } catch (e) {
      debugPrint('Error incrementing impression counts: $e');
    }
  }

  /// Circuit breaker management
  bool _isTypseSenseCircuitOpen() {
    if (!_TypseSenseCircuitOpen) return false;

    if (_lastTypseSenseFailure != null) {
      final timeSinceFailure =
          DateTime.now().difference(_lastTypseSenseFailure!);
      if (timeSinceFailure > _circuitCooldown) {
        _TypseSenseCircuitOpen = false;
        _TypseSenseFailureCount = 0;
        print('TypseSense circuit breaker reset after cooldown');
        return false;
      }
    }

    return true;
  }

  void _recordTypseSenseFailure() {
    _TypseSenseFailureCount++;
    _lastTypseSenseFailure = DateTime.now();

    if (_TypseSenseFailureCount >= _maxFailures) {
      _TypseSenseCircuitOpen = true;
      print(
          'TypseSense circuit breaker opened after $_TypseSenseFailureCount failures');
    }
  }

  void _recordTypseSenseSuccess() {
    if (_TypseSenseFailureCount > 0 || _TypseSenseCircuitOpen) {
      print('TypseSense service recovered, resetting circuit breaker');
      _TypseSenseFailureCount = 0;
      _TypseSenseCircuitOpen = false;
      _lastTypseSenseFailure = null;
    }
  }

  /// ---------------------------------------------------------------------------
  /// Searching via TypseSense
  /// ---------------------------------------------------------------------------
  Future<void> searchProducts({
    String query = '',
    int page = 0,
    int hitsPerPage = 50,
    AppLocalizations? l10n,
  }) async {
    if (query.isEmpty) {
      _isFiltering = false;
      notifyListeners();
      return;
    }

    _isFiltering = true;
    notifyListeners();

    try {
      // ✅ ADD: Check remote config
      if (SearchConfigService.instance.useFirestore) {
        await _searchProductsFirestore(
            query: query, page: page, hitsPerPage: hitsPerPage);
        return; // skip TypseSense entirely
      }
      // Check circuit breaker first
      if (_isTypseSenseCircuitOpen()) {
        print('TypseSense circuit open, using Firestore for search');
        await _searchProductsFirestore(
            query: query, page: page, hitsPerPage: hitsPerPage);
        return;
      }

      // Build localized filters
      final locale = l10n?.localeName ?? 'en';
      final catField = 'category_$locale';
      final subField = 'subcategory_$locale';
      final subsubField = 'subsubcategory_$locale';

      final List<String> filters = [];
      if (_selectedCategory?.isNotEmpty ?? false) {
        final locCat = l10n == null
            ? _selectedCategory!
            : AllInOneCategoryData.localizeCategoryKey(
                _selectedCategory!, l10n);
        filters.add('$catField:"$locCat"');
      }
      if (_selectedSubSubcategory?.isNotEmpty ?? false) {
        final locSubsub = l10n == null
            ? _selectedSubSubcategory!
            : AllInOneCategoryData.localizeSubSubcategoryKey(
                _selectedCategory!,
                _selectedSubcategory!,
                _selectedSubSubcategory!,
                l10n,
              );
        filters.add('$subsubField:"$locSubsub"');
      }
      if (_minPrice != null) filters.add('price >= ${_minPrice!}');
      if (_maxPrice != null) filters.add('price <= ${_maxPrice!}');

      // Execute search with timeout and fallback
      try {
        final results = await AnalyticsService.trackTypesenseSearch(
          operation: 'market_search_TypseSense',
          execute: () => Future.wait([
            typesenseService.searchProducts(
              query: query,
              sortOption: _sortOption,
              page: page,
              hitsPerPage: hitsPerPage,
              filters: filters.isNotEmpty ? filters : null,
            ),
            typesenseShopService.searchProducts(
              query: query,
              sortOption: _sortOption,
              page: page,
              hitsPerPage: hitsPerPage,
              filters: filters.isNotEmpty ? filters : null,
            ),
          ]).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                  'Search timeout', const Duration(seconds: 10));
            },
          ),
          metadata: {
            'query': query.substring(0, query.length > 50 ? 50 : query.length),
            'page': page,
            'has_filters': filters.isNotEmpty,
          },
        );

        // Process successful results
        final combined = <ProductSummary>[];
        final seen = <String>{};
        for (final list in results) {
          for (final p in list) {
            if (seen.add(p.id)) combined.add(p);
          }
        }

        if (_products.length > 200) {
          // Add limit
          _products.removeRange(0, _products.length - 200);
          _productIds.removeWhere((id) => !_products.any((p) => p.id == id));
        }

        _recordTypseSenseSuccess();
        _updateSearchResults(combined, page, hitsPerPage);
      } catch (e) {
        print('TypseSense search failed, falling back to Firestore: $e');
        _recordTypseSenseFailure();
        await _searchProductsFirestore(
            query: query, page: page, hitsPerPage: hitsPerPage);
      }
    } catch (e) {
      print('Search error: $e');
      _hasMore = false;
    } finally {
      _isFiltering = false;
      notifyListeners();
    }
  }

  Future<void> _searchProductsFirestore({
    required String query,
    int page = 0,
    int hitsPerPage = 50,
  }) async {
    try {
      final lower = query.toLowerCase();
      final capitalized = query.substring(0, 1).toUpperCase() +
          query.substring(1).toLowerCase();

      final snapshots = await Future.wait([
        _firestore
            .collection('products')
            .orderBy('productName')
            .startAt([lower])
            .endAt(['$lower\uf8ff'])
            .limit(hitsPerPage)
            .get(),
        _firestore
            .collection('products')
            .orderBy('productName')
            .startAt([capitalized])
            .endAt(['$capitalized\uf8ff'])
            .limit(hitsPerPage)
            .get(),
        _firestore
            .collection('shop_products')
            .orderBy('productName')
            .startAt([lower])
            .endAt(['$lower\uf8ff'])
            .limit(hitsPerPage)
            .get(),
        _firestore
            .collection('shop_products')
            .orderBy('productName')
            .startAt([capitalized])
            .endAt(['$capitalized\uf8ff'])
            .limit(hitsPerPage)
            .get(),
      ]).timeout(const Duration(seconds: 8));

      final combined = <ProductSummary>[];
      final seen = <String>{};

      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          if (combined.length >= hitsPerPage) break;
          if (seen.add(doc.id)) {
            combined.add(ProductSummary.fromDocument(doc));
          }
        }
      }

      _updateSearchResults(combined, page, hitsPerPage);
    } catch (e) {
      debugPrint('Firestore search fallback failed: $e');
      _updateSearchResults([], page, hitsPerPage);
    }
  }

  /// Helper to update search results consistently
  void _updateSearchResults(
      List<ProductSummary> results, int page, int hitsPerPage) {
    const MAX_PRODUCTS_IN_MEMORY = 200; // ✅ NEW: Hard limit

    _hasMore = results.length >= hitsPerPage;

    if (page == 0) {
      _products.clear();
      _productIds.clear();
      _lastDocument = null;
    }

    // ✅ NEW: Enforce memory limit before adding
    if (_products.length > MAX_PRODUCTS_IN_MEMORY) {
      final removeCount = _products.length - MAX_PRODUCTS_IN_MEMORY + 50;
      final toRemove = _products.take(removeCount).map((p) => p.id).toSet();
      _products.removeRange(0, removeCount);
      _productIds.removeWhere((id) => toRemove.contains(id));

      debugPrint('🧹 Trimmed ${removeCount} old products from memory');
    }

    for (final product in results) {
      if (_productIds.add(product.id)) {
        _products.add(product);
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// Search term
  /// ---------------------------------------------------------------------------

  void setBottomNavIndex(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  /// Reset search
  void resetSearch({
    bool triggerFilter = true,
    bool preserveSubSubcategory = false,
  }) {
    // 0) wipe our in‐memory searchOnly cache
    clearSearchCache();

    // 1) reset any category/subcategory state
    _selectedCategory = preserveSubSubcategory ? _selectedCategory : null;
    if (!preserveSubSubcategory) {
      _selectedSubSubcategory = null;
    }

    // 2) reset your price‐filter & search‐active flags
    _minPrice = null;
    _maxPrice = null;
    _isSearchActive = false;

    _hasMore = true;

    // 4) clear any loaded product lists & caches you had for the home/feed
    _products.clear();
    _productCache.clear();
    _cacheTimestamps
        .clear(); // (this is your own feed‐cache, keep it if you still need it)

    // finally, notify listeners once (debounced)
    _notifyDebouncer.run(() => notifyListeners());
  }

  /// Pull-to-refresh
  Future<void> onRefresh({String? screenType}) async {
    _isFiltering = true;

    _products.clear();
    _productIds.clear();
    _productCache.clear();
    _cacheTimestamps.clear();
    clearBuyerCategoryCache();
    clearBuyerCategoryTerasCache();
    _hasMore = true;

    notifyListeners();
  }

  /// Additional
  String sanitizeFieldName(String fieldName) {
    return fieldName.replaceAll('.', '_').replaceAll('/', '_');
  }

  Future<List<ProductSummary>> fetchProductsForBuyerCategory(
      String buyerCategory) async {
    // Check cache first
    final cached = _getBuyerCategoryCache(buyerCategory);
    if (cached != null) {
      debugPrint(
          'Returning cached products for buyer category (Market): $buyerCategory');
      return cached;
    }

    try {
      List<ProductSummary> allProducts = [];

      if (buyerCategory == 'Women' || buyerCategory == 'Men') {
        Query query = _firestore
            .collection('shop_products')
            .where('gender', whereIn: [buyerCategory, 'Unisex'])
            .orderBy('promotionScore', descending: true)
            .limit(20);

        final snapshot = await query.get();
        allProducts = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .toList();

        debugPrint(
            'Fetched ${allProducts.length} products with single optimized query');
      } else {
        Query query = _firestore
            .collection('shop_products')
            .where('category', isEqualTo: buyerCategory)
            .orderBy('promotionScore', descending: true)
            .limit(20);

        final snapshot = await query.get();
        allProducts = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .toList();
      }

      _setBuyerCategoryCache(buyerCategory, allProducts);

      FirestoreReadTracker.instance.trackRead('MarketProvider',
          'buyerCategory:$buyerCategory (Firestore)', allProducts.length);
      return allProducts;
    } catch (e) {
      debugPrint(
          'Error fetching products for buyer category $buyerCategory: $e');

      try {
        List<ProductSummary> fallbackProducts = [];

        if (buyerCategory == 'Women' || buyerCategory == 'Men') {
          Query fallbackQuery = _firestore
              .collection('shop_products')
              .where('gender', whereIn: [buyerCategory, 'Unisex'])
              .orderBy('createdAt', descending: true)
              .limit(20);

          final snapshot = await fallbackQuery.get();
          fallbackProducts = snapshot.docs
              .map((doc) => ProductSummary.fromDocument(doc))
              .toList();

          debugPrint(
              'Fallback: Single query returned ${fallbackProducts.length} products');
        } else {
          Query fallbackQuery = _firestore
              .collection('shop_products')
              .where('category', isEqualTo: buyerCategory)
              .orderBy('createdAt', descending: true)
              .limit(20);

          final snapshot = await fallbackQuery.get();
          fallbackProducts = snapshot.docs
              .map((doc) => ProductSummary.fromDocument(doc))
              .toList();
        }

        _setBuyerCategoryCache(buyerCategory, fallbackProducts);

        debugPrint(
            'Fallback: Fetched ${fallbackProducts.length} products for buyer category: $buyerCategory');
        return fallbackProducts;
      } catch (fallbackError) {
        debugPrint(
            'Fallback also failed for buyer category $buyerCategory: $fallbackError');
        return [];
      }
    }
  }

  // Cache helper methods for buyer categories
  List<ProductSummary>? _getBuyerCategoryCache(String buyerCategory) {
    final timestamp = _buyerCategoryTimestamps[buyerCategory];
    if (timestamp == null) return null;

    final now = DateTime.now();
    if (now.difference(timestamp) > _buyerCategoryCacheTTL) {
      // Cache expired, remove it
      _buyerCategoryCache.remove(buyerCategory);
      _buyerCategoryTimestamps.remove(buyerCategory);
      return null;
    }

    return _buyerCategoryCache[buyerCategory];
  }

  void _setBuyerCategoryCache(
      String buyerCategory, List<ProductSummary> products) {
    // Enforce cache size limit
    if (_buyerCategoryCache.length >= _maxBuyerCategoryCacheSize) {
      // Remove oldest entry
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _buyerCategoryTimestamps.entries) {
        if (oldestTime == null || entry.value.isBefore(oldestTime)) {
          oldestTime = entry.value;
          oldestKey = entry.key;
        }
      }

      if (oldestKey != null) {
        _buyerCategoryCache.remove(oldestKey);
        _buyerCategoryTimestamps.remove(oldestKey);
      }
    }

    _buyerCategoryCache[buyerCategory] = products;
    _buyerCategoryTimestamps[buyerCategory] = DateTime.now();
  }

  // Clear buyer category cache (call when needed)
  void clearBuyerCategoryCache([String? specificCategory]) {
    if (specificCategory != null) {
      _buyerCategoryCache.remove(specificCategory);
      _buyerCategoryTimestamps.remove(specificCategory);
    } else {
      _buyerCategoryCache.clear();
      _buyerCategoryTimestamps.clear();
    }
  }

  // Cache helper methods for Teras buyer categories
  List<ProductSummary>? _getBuyerCategoryTerasCache(String buyerCategory) {
    final timestamp = _buyerCategoryTerasTimestamps[buyerCategory];
    if (timestamp == null) return null;

    final now = DateTime.now();
    if (now.difference(timestamp) > _buyerCategoryCacheTTL) {
      // Cache expired, remove it
      _buyerCategoryTerasCache.remove(buyerCategory);
      _buyerCategoryTerasTimestamps.remove(buyerCategory);
      return null;
    }

    return _buyerCategoryTerasCache[buyerCategory];
  }

  void _setBuyerCategoryTerasCache(
      String buyerCategory, List<ProductSummary> products) {
    // Enforce cache size limit
    if (_buyerCategoryTerasCache.length >= _maxBuyerCategoryCacheSize) {
      // Remove oldest entry
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _buyerCategoryTerasTimestamps.entries) {
        if (oldestTime == null || entry.value.isBefore(oldestTime)) {
          oldestTime = entry.value;
          oldestKey = entry.key;
        }
      }

      if (oldestKey != null) {
        _buyerCategoryTerasCache.remove(oldestKey);
        _buyerCategoryTerasTimestamps.remove(oldestKey);
      }
    }

    _buyerCategoryTerasCache[buyerCategory] = products;
    _buyerCategoryTerasTimestamps[buyerCategory] = DateTime.now();
  }

  // Clear Teras buyer category cache
  void clearBuyerCategoryTerasCache([String? specificCategory]) {
    if (specificCategory != null) {
      _buyerCategoryTerasCache.remove(specificCategory);
      _buyerCategoryTerasTimestamps.remove(specificCategory);
    } else {
      _buyerCategoryTerasCache.clear();
      _buyerCategoryTerasTimestamps.clear();
    }
  }

  Future<List<ProductSummary>> fetchProductsForBuyerCategoryTeras(
      String buyerCategory) async {
    // Check TERAS cache first (separate from regular cache)
    final cached = _getBuyerCategoryTerasCache(buyerCategory);
    if (cached != null) {
      debugPrint(
          'Returning cached products for buyer category (Teras): $buyerCategory');
      return cached;
    }

    try {
      List<ProductSummary> allProducts = [];

      if (buyerCategory == 'Women' || buyerCategory == 'Men') {
        // ✅ OPTIMIZED: Single query instead of 2 separate queries
        Query query = _firestore
            .collection('products')
            .where('gender',
                whereIn: [buyerCategory, 'Unisex']) // ✅ Combined query
            .orderBy('promotionScore', descending: true)
            .limit(20); // ✅ Direct limit - no need to fetch 30 and trim to 20

        final snapshot = await query.get();
        allProducts = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .toList();

        debugPrint(
            '✅ Fetched ${allProducts.length} products with single optimized query');
      } else {
        // For other categories, filter by category field directly
        Query query = _firestore
            .collection('products')
            .where('category', isEqualTo: buyerCategory)
            .orderBy('promotionScore', descending: true)
            .limit(20);

        final snapshot = await query.get();
        allProducts = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .toList();
      }

      // Cache the results in TERAS cache before returning
      _setBuyerCategoryTerasCache(buyerCategory, allProducts);

      debugPrint(
          'Total fetched ${allProducts.length} products for buyer category: $buyerCategory');
      return allProducts;
    } catch (e) {
      debugPrint(
          'Error fetching products for buyer category $buyerCategory: $e');

      // ✅ OPTIMIZED: Simplified fallback with single query
      try {
        List<ProductSummary> fallbackProducts = [];

        if (buyerCategory == 'Women' || buyerCategory == 'Men') {
          // ✅ Single fallback query instead of 2
          Query fallbackQuery = _firestore
              .collection('products')
              .where('gender', whereIn: [buyerCategory, 'Unisex']) // ✅ Combined
              .orderBy('createdAt', descending: true)
              .limit(20); // ✅ Direct limit

          final snapshot = await fallbackQuery.get();
          fallbackProducts = snapshot.docs
              .map((doc) => ProductSummary.fromDocument(doc))
              .toList();

          debugPrint(
              '✅ Fallback: Single query returned ${fallbackProducts.length} products');
        } else {
          // Fallback for other categories
          Query fallbackQuery = _firestore
              .collection('products')
              .where('category', isEqualTo: buyerCategory)
              .orderBy('createdAt', descending: true)
              .limit(20);

          final snapshot = await fallbackQuery.get();
          fallbackProducts = snapshot.docs
              .map((doc) => ProductSummary.fromDocument(doc))
              .toList();
        }

        // Cache even the fallback results in TERAS cache
        _setBuyerCategoryTerasCache(buyerCategory, fallbackProducts);

        debugPrint(
            'Fallback: Fetched ${fallbackProducts.length} products for buyer category: $buyerCategory');
        return fallbackProducts;
      } catch (fallbackError) {
        debugPrint(
            'Fallback also failed for buyer category $buyerCategory: $fallbackError');
        return [];
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// Logout
  /// ---------------------------------------------------------------------------
  Future<void> logout() async {
    await _auth.signOut();
    resetProviderState();
  }

  void resetProviderState({bool resetFavoritesAndCart = true}) {
    _products.clear();
    _productIds.clear();
    _lastDocument = null;
    _hasMore = true;
    _isLoadingMore = false;

    _isFiltering = false;
    _isSearchActive = false;

    _selectedCategory = null;
    _selectedSubSubcategory = null;
    _minPrice = null;
    _maxPrice = null;
    _sortOption = 'date';

    if (resetFavoritesAndCart) {
      unreadMessagesCount.value = 0;
      unreadNotificationsCount.value = 0;
      favoritePropertiesCount.value = 0;
    }

    notifyListeners();
  }

  /// Expose FirebaseAuth if needed
  FirebaseAuth get auth => _auth;

  /// Page Route transition
  Route createRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final begin = const Offset(1.0, 0.0);
        final end = Offset.zero;
        final curve = Curves.easeInOut;
        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// Unread counts, Search logging, and Sharing
  /// ---------------------------------------------------------------------------
  Future<void> recordSearchTerm(String searchTerm) async {
    UserActivityService.instance.trackSearch(query: searchTerm);
    final User? user = _auth.currentUser;
    final String userId = user?.uid ?? 'anonymous';

    try {
      await AnalyticsService.trackWrite(
        operation: 'market_record_search_term',
        execute: () => _firestore.collection('searches').add({
          'userId': userId,
          'searchTerm': searchTerm,
          'timestamp': FieldValue.serverTimestamp(),
        }),
        writeCount: 1,
        metadata: {'user_type': user != null ? 'authenticated' : 'anonymous'},
      );
      debugPrint('Search term recorded: $searchTerm by user: $userId');
    } catch (e) {
      debugPrint('Error saving search term: $e');
    }
  }

  final _searchCache = <String, List<ProductSummary>>{};

  Future<List<ProductSummary>> searchOnly({
    required String query,
    int page = 0,
    int hitsPerPage = 50,
    AppLocalizations? l10n,
  }) async {
    if (query.isEmpty) return [];

    final cacheKey = '$query|$page|$_sortOption';
    final now = DateTime.now();

    // 1) Return cache if fresh
    if (_searchCache.containsKey(cacheKey)) {
      final ts = _cacheTimestamps[cacheKey]!;
      if (now.difference(ts) < _cacheTTL) {
        return _searchCache[cacheKey]!;
      }
      _searchCache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
    }

    return _searchDeduplicator.deduplicate(cacheKey, () async {
      // Wrap each Typesense call in a retry + timeout
      final r = RetryOptions(
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 200),
      );

      // Typesense main index
      final mainResults = await r.retry(
        () => typesenseService
            .searchProducts(
              query: query,
              sortOption: '',
              page: page,
              hitsPerPage: hitsPerPage,
            )
            .timeout(const Duration(seconds: 2)),
      );

      // Typesense shop products index
      final shopResults = await r.retry(
        () => typesenseShopService
            .searchProducts(
              query: query,
              sortOption: '',
              page: page,
              hitsPerPage: hitsPerPage,
            )
            .timeout(const Duration(seconds: 2)),
      );

      // Merge & dedupe
      final merged = <ProductSummary>[];
      final seen = <String>{};
      for (final list in [mainResults, shopResults]) {
        for (final p in list) {
          if (seen.add(p.id)) merged.add(p);
        }
      }

      // Cache & return
      _searchCache[cacheKey] = merged;
      _cacheTimestamps[cacheKey] = now;
      return merged;
    });
  }

  void clearSearchCache() {
    _searchCache.clear();
    _cacheTimestamps.clear();
  }

/*----------------------------------------------------------------------------------------------*/
}
