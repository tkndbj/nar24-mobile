import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/typesense_service_manager.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/product.dart';
import 'dart:async';
import 'dart:collection';
import '../services/analytics_service.dart';


class SellerPanelProvider with ChangeNotifier {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  static const int _maxCacheSize = 100;
  static const int _maxProductMapSize = 500;
  static const Duration _listenerCancelDelay = Duration(milliseconds: 50);

  DateTime? _metricsLastFetched;
  static const _metricsCacheDuration = Duration(minutes: 5);

  // ValueNotifiers for frequently accessed/filtered data
  final ValueNotifier<List<Product>> _filteredProductsNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<Product>> _filteredStockProductsNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<DocumentSnapshot>> _filteredTransactionsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _isLoadingStockNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isFetchingMoreProductsNotifier =
      ValueNotifier(false);
  final ValueNotifier<String> _stockSearchQueryNotifier = ValueNotifier('');
  final ValueNotifier<String?> _stockCategoryNotifier = ValueNotifier(null);
  final ValueNotifier<String?> _stockSubcategoryNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _stockOutOfStockNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isLoadingTransactionsNotifier =
      ValueNotifier(false);
  final ValueNotifier<bool> _isLoadingMoreTransactionsNotifier =
      ValueNotifier(false);
  final ValueNotifier<List<DocumentSnapshot>> _shipmentsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _isLoadingMoreShipmentsNotifier =
      ValueNotifier(false);

  final ValueNotifier<bool> _isSearchingNotifier = ValueNotifier(false);
  final ValueNotifier<List<Product>> _searchResultsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isLoadingMoreSearchResultsNotifier =
      ValueNotifier(false);

  Timer? _searchDebounceTimer;
  int _currentSearchPage = 0;
  bool _hasMoreSearchResults = true;
  String _lastSearchQuery = '';
  bool _isSearchMode = false;

  int _activeQueryId = 0; // race guard for search
  int _activeProductQueryId = 0; // race guard for product filtering
  int _activeStockQueryId = 0; // race guard for stock filtering
  bool _initInFlight = false;
  bool _warmupInFlight = false;

  ValueNotifier<bool> get isSearchingNotifier => _isSearchingNotifier;
  ValueNotifier<List<Product>> get searchResultsNotifier =>
      _searchResultsNotifier;
  ValueNotifier<bool> get isLoadingMoreSearchResultsNotifier =>
      _isLoadingMoreSearchResultsNotifier;
  bool get isSearchMode => _isSearchMode;
  bool get hasMoreSearchResults => _hasMoreSearchResults;

  // Typesense page-based pagination for products
  int _currentProductPage = 0;
  bool _hasMoreProducts = true;

  // Typesense page-based pagination for stock
  int _currentStockPage = 0;
  bool _hasMoreStockProducts = true;  Map<String, dynamic>? _activeCampaign;
  bool _campaignDismissed = false;

  // Flag to request showing seller info modal on dashboard tab
  bool _pendingShowSellerInfoModal = false;
  bool get pendingShowSellerInfoModal => _pendingShowSellerInfoModal;

  // Tab switch request for cross-tab navigation
  int? _requestedTabIndex;
  int? get requestedTabIndex => _requestedTabIndex;

  /// Request to switch to dashboard tab and show seller info modal
  void requestShowSellerInfoOnDashboard() {
    _pendingShowSellerInfoModal = true;
    _requestedTabIndex = 0;
    notifyListeners();
  }

  void clearPendingSellerInfoModal() {
    _pendingShowSellerInfoModal = false;
  }

  void clearRequestedTabIndex() {
    _requestedTabIndex = null;
  }

  Map<String, dynamic>? get activeCampaign => _activeCampaign;
  bool get campaignDismissed => _campaignDismissed;
  bool get shouldShowCampaignBanner =>
      _activeCampaigns.isNotEmpty && !_campaignDismissed;

  List<Map<String, dynamic>> _activeCampaigns = [];
  Map<String, bool> _campaignParticipationStatus = {};
  int _currentCampaignIndex = 0;

  List<Map<String, dynamic>> get activeCampaigns => _activeCampaigns;
  Map<String, bool> get campaignParticipationStatus =>
      _campaignParticipationStatus;
  int get currentCampaignIndex => _currentCampaignIndex;

  StreamSubscription<QuerySnapshot>? _questionsSub;
  bool _hasUnansweredQuestions = false;
  bool get hasUnansweredQuestions => _hasUnansweredQuestions;

  // Shop notifications unread count
  StreamSubscription<QuerySnapshot>? _shopNotificationsSub;
  String? _currentNotificationShopId;
  final ValueNotifier<int> _unreadNotificationCountNotifier = ValueNotifier(0);
  ValueNotifier<int> get unreadNotificationCountNotifier =>
      _unreadNotificationCountNotifier;
  int get unreadNotificationCount => _unreadNotificationCountNotifier.value;

  bool get isFetchingMoreProducts => _isFetchingMoreProductsNotifier.value;
  bool get hasMoreProducts => _hasMoreProducts;

  final StreamController<List<DocumentSnapshot>> _shipmentsStreamController =
      StreamController<List<DocumentSnapshot>>.broadcast();
  Stream<List<DocumentSnapshot>> get shipmentsStream =>
      _shipmentsStreamController.stream;

  List<DocumentSnapshot> get shipments => _shipmentsNotifier.value;

  String? get stockCategory => _stockCategoryNotifier.value;
  String? get stockSubcategory => _stockSubcategoryNotifier.value;

  bool _hasCampaignedProducts = false;
  bool get hasCampaignedProducts => _hasCampaignedProducts;

  bool get hasNewTransactions => _filteredTransactionsNotifier.value.isNotEmpty;

  String? _switchingToShopId; // Track ongoing switch operation
  final Map<String, Completer<void>> _switchCompleters = {};

  bool get hasOutOfStock => _filteredStockProductsNotifier.value.any((p) =>
      (p.quantity == 0) ||
      ((p.colorQuantities as Map<String, int>?)?.values.any((q) => q == 0) ??
          false));

  DocumentSnapshot? _lastShipmentDoc;
  bool _hasMoreShipments = true;

  bool get isLoadingMoreShipments => _isLoadingMoreShipmentsNotifier.value;
  bool get hasMoreShipments => _hasMoreShipments;

  // Product image cache for ShipmentsTab
  final LinkedHashMap<String, Map<String, dynamic>> _productImageCache =
      LinkedHashMap<String, Map<String, dynamic>>();
  Map<String, Map<String, dynamic>> get productImageCache => _productImageCache;

  bool get isFetchingMoreTransactions =>
      _isLoadingMoreTransactionsNotifier.value;

  Map<String, Product> _productMap = {};
  Map<String, Product> get productMap => _productMap;

  DateTime? _selectedDate;
  DateTimeRange? _selectedDateRange;
  bool _isSingleDateMode = true;
  bool _showGraph = false;

  DateTime? get selectedDate => _selectedDate;
  DateTimeRange? get selectedDateRange => _selectedDateRange;
  bool get isSingleDateMode => _isSingleDateMode;
  bool get showGraph => _showGraph;

  List<DocumentSnapshot> _shops = [];
  DocumentSnapshot? _selectedShop;
  List<Product> _products = [];
  List<DocumentSnapshot> _transactions = [];
  List<DocumentSnapshot> get transactions =>
      _filteredTransactionsNotifier.value;
  List<DocumentSnapshot> _pastBoostHistory = [];
  int _currentTransactionPage = 0;
  bool _hasMoreTransactions = true;
  String _transactionSearchQuery = '';

  bool _isLoadingShops = false;
  bool _isLoadingProducts = false;
  bool _isLoadingPastBoostHistory = false;
  String? _transactionError;

  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedSubcategory;

  Map<String, int>? _cachedMetrics;
  Map<String, Product?>? _cachedTopProducts;

  StreamSubscription<QuerySnapshot>? _transactionSubscription;

  // ValueNotifier getters for UI to listen to specific changes
  ValueNotifier<List<Product>> get filteredProductsNotifier =>
      _filteredProductsNotifier;
  ValueNotifier<List<Product>> get filteredStockProductsNotifier =>
      _filteredStockProductsNotifier;
  ValueNotifier<List<DocumentSnapshot>> get filteredTransactionsNotifier =>
      _filteredTransactionsNotifier;
  ValueNotifier<bool> get isLoadingStockNotifier => _isLoadingStockNotifier;
  ValueNotifier<bool> get isFetchingMoreProductsNotifier =>
      _isFetchingMoreProductsNotifier;
  ValueNotifier<String> get stockSearchQueryNotifier =>
      _stockSearchQueryNotifier;
  ValueNotifier<String?> get stockCategoryNotifier => _stockCategoryNotifier;
  ValueNotifier<String?> get stockSubcategoryNotifier =>
      _stockSubcategoryNotifier;
  ValueNotifier<bool> get stockOutOfStockNotifier => _stockOutOfStockNotifier;
  ValueNotifier<bool> get isLoadingTransactionsNotifier =>
      _isLoadingTransactionsNotifier;
  ValueNotifier<bool> get isLoadingMoreTransactionsNotifier =>
      _isLoadingMoreTransactionsNotifier;
  ValueNotifier<List<DocumentSnapshot>> get shipmentsNotifier =>
      _shipmentsNotifier;
  ValueNotifier<bool> get isLoadingMoreShipmentsNotifier =>
      _isLoadingMoreShipmentsNotifier;

  // Backward compatibility getters
  List<Product> get filteredProducts => _filteredProductsNotifier.value;
  bool get isLoadingStock => _isLoadingStockNotifier.value;
  String get stockSearchQuery => _stockSearchQueryNotifier.value;
  bool get stockOutOfStock => _stockOutOfStockNotifier.value;
  bool get isLoadingTransactions => _isLoadingTransactionsNotifier.value;
  bool get isLoadingMoreTransactions =>
      _isLoadingMoreTransactionsNotifier.value;

  SellerPanelProvider(this._firebaseAuth, this._firestore) {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  // ✅ OPTIMIZATION: Circuit breaker pattern for network resilience
  Map<String, int> _failureCounts = {};
  Map<String, DateTime> _lastFailureTime = {};
  static const int _circuitBreakerThreshold = 3;
  static const Duration _circuitBreakerResetDuration = Duration(minutes: 1);

  bool _isCircuitOpen(String operationKey) {
    final failures = _failureCounts[operationKey] ?? 0;
    if (failures < _circuitBreakerThreshold) return false;

    final lastFailure = _lastFailureTime[operationKey];
    if (lastFailure == null) return false;

    // Reset circuit if enough time has passed
    if (DateTime.now().difference(lastFailure) > _circuitBreakerResetDuration) {
      _failureCounts[operationKey] = 0;
      _lastFailureTime.remove(operationKey);
      return false;
    }

    return true;
  }

  void _recordFailure(String operationKey) {
    _failureCounts[operationKey] = (_failureCounts[operationKey] ?? 0) + 1;
    _lastFailureTime[operationKey] = DateTime.now();
  }

  void _recordSuccess(String operationKey) {
    _failureCounts[operationKey] = 0;
    _lastFailureTime.remove(operationKey);
  }

  // ✅ OPTIMIZATION: Retry logic with exponential backoff
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    String operationKey = 'default',
  }) async {
    // Check circuit breaker
    if (_isCircuitOpen(operationKey)) {
      debugPrint(
          '⚠️ Circuit breaker open for $operationKey, skipping operation');
      throw Exception('Circuit breaker open for $operationKey');
    }

    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        final result = await operation();
        _recordSuccess(operationKey);
        return result;
      } catch (e) {
        attempt++;
        _recordFailure(operationKey);

        if (attempt >= maxAttempts) {
          debugPrint(
              '❌ Operation $operationKey failed after $maxAttempts attempts: $e');
          rethrow;
        }

        // Exponential backoff: 200ms, 400ms, 800ms
        final delayMs = 200 * (1 << (attempt - 1));
        debugPrint(
            '⚠️ Retry $attempt/$maxAttempts for $operationKey after ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw Exception('Retry failed for $operationKey');
  }

  String get userId => _firebaseAuth.currentUser?.uid ?? '';

  List<DocumentSnapshot> get shops => _shops;
  DocumentSnapshot? get selectedShop => _selectedShop;

  List<DocumentSnapshot> get pastBoostHistory => _pastBoostHistory;
  Map<String, int>? get cachedMetrics => _cachedMetrics;
  Map<String, Product?>? get cachedTopProducts => _cachedTopProducts;
  String? get transactionError => _transactionError;

  bool get isLoadingShops => _isLoadingShops;
  bool get isLoadingProducts => _isLoadingProducts;
  bool get isLoadingPastBoostHistory => _isLoadingPastBoostHistory;

  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String? get selectedSubcategory => _selectedSubcategory;

  bool get hasMoreTransactions => _hasMoreTransactions;
  String get transactionSearchQuery => _transactionSearchQuery;

  double _totalSoldPrice = 0.0;
  double get totalSales => _totalSoldPrice;

  String get selectedShopName {
    final shopData = _selectedShop?.data() as Map<String, dynamic>?;
    return shopData?['name'] ?? '';
  }

  void resetState() {
    _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _shopNotificationsSub?.cancel();
    _shopNotificationsSub = null;
    _currentNotificationShopId = null;
    _unreadNotificationCountNotifier.value = 0;
    _shops = [];
    _selectedShop = null;
    _products = [];
    _filteredProductsNotifier.value = [];
    _filteredStockProductsNotifier.value = [];
    _transactions = [];
    _filteredTransactionsNotifier.value = [];
    _pastBoostHistory = [];
    _cachedMetrics = null;
    _totalSoldPrice = 0.0;
    _cachedTopProducts = null;
    _searchQuery = '';
    _selectedCategory = null;
    _selectedSubcategory = null;
    _transactionError = null;
    _currentProductPage = 0;
    _hasMoreProducts = true;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;
    _isFetchingMoreProductsNotifier.value = false;
    _productMap = {};
    _selectedDate = null;
    _selectedDateRange = null;
    _isSingleDateMode = true;
    _showGraph = false;
    _transactionSearchQuery = '';
    _shipmentsNotifier.value = [];
    _lastShipmentDoc = null;
    _hasMoreShipments = true;
    _isLoadingMoreShipmentsNotifier.value = false;
    _productImageCache.clear();

    // Reset ValueNotifiers
    _isLoadingStockNotifier.value = false;
    _stockSearchQueryNotifier.value = '';
    _stockCategoryNotifier.value = null;
    _stockSubcategoryNotifier.value = null;
    _stockOutOfStockNotifier.value = false;
    _isLoadingTransactionsNotifier.value = false;
    _isLoadingMoreTransactionsNotifier.value = false;

    // Reset campaign-related state
    _activeCampaigns = [];
    _campaignParticipationStatus = {};
    _currentCampaignIndex = 0;
    _campaignDismissed = false;

    _searchDebounceTimer?.cancel();
    _isSearchingNotifier.value = false;
    _searchResultsNotifier.value = [];
    _isLoadingMoreSearchResultsNotifier.value = false;
    _currentSearchPage = 0;
    _hasMoreSearchResults = true;
    _lastSearchQuery = '';
    _isSearchMode = false;

    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint('🧹 Disposing SellerPanelProvider...');

    // 1. Cancel timers first
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;

    // 2. Cancel stream subscriptions
    _transactionSubscription?.cancel();
    _transactionSubscription = null;

    _questionsSub?.cancel();
    _questionsSub = null;

    _shopNotificationsSub?.cancel();
    _shopNotificationsSub = null;

    // 3. Close stream controllers
    if (!_shipmentsStreamController.isClosed) {
      _shipmentsStreamController.close();
    }

    // 4. Dispose ValueNotifiers
    _filteredProductsNotifier.dispose();
    _filteredStockProductsNotifier.dispose();
    _filteredTransactionsNotifier.dispose();
    _isLoadingStockNotifier.dispose();
    _isFetchingMoreProductsNotifier.dispose();
    _stockSearchQueryNotifier.dispose();
    _stockCategoryNotifier.dispose();
    _stockSubcategoryNotifier.dispose();
    _stockOutOfStockNotifier.dispose();
    _isLoadingTransactionsNotifier.dispose();
    _isLoadingMoreTransactionsNotifier.dispose();
    _shipmentsNotifier.dispose();
    _isLoadingMoreShipmentsNotifier.dispose();
    _isSearchingNotifier.dispose();
    _searchResultsNotifier.dispose();
    _isLoadingMoreSearchResultsNotifier.dispose();
    _unreadNotificationCountNotifier.dispose();

    // 5. Clear large collections
    _productImageCache.clear();
    _productMap.clear();
    _products.clear();
    _transactions.clear();
    _shops.clear();

    // 6. Clear completers
    _switchCompleters.clear();

    // 7. Clear circuit breaker state
    _failureCounts.clear();
    _lastFailureTime.clear();

    debugPrint('✅ SellerPanelProvider disposed');

    // 8. Finally call super
    super.dispose();
  }

  double get todaySales {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd =
        DateTime(today.year, today.month, today.day, 23, 59, 59, 999);

    double total = 0.0;

    // Sum up individual item prices for today using calculatedTotal
    for (final transactionDoc in _transactions) {
      final data = transactionDoc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] is Timestamp
          ? data['timestamp'] as Timestamp
          : null;

      if (timestamp != null) {
        final date = timestamp.toDate();
        if (date.isAfter(todayStart) && date.isBefore(todayEnd)) {
          // Use calculatedTotal from selectedAttributes or fallback to price * quantity
          final selectedAttributes =
              data['selectedAttributes'] as Map<String, dynamic>?;
          final calculatedTotal =
              selectedAttributes?['calculatedTotal'] as num?;

          if (calculatedTotal != null) {
            // Use the denormalized calculatedTotal which includes all discounts
            total += calculatedTotal.toDouble();
          } else {
            // Fallback to price * quantity if calculatedTotal is not available
            final itemPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
            final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
            total += itemPrice * quantity;
          }
        }
      }
    }

    return total;
  }

  Future<void> _fetchTotalSalesFromShop() async {
    if (_selectedShop == null) return;

    try {
      final shopDoc =
          await _firestore.collection('shops').doc(_selectedShop!.id).get();
      final shopData = shopDoc.data() ?? {};
      _totalSoldPrice = (shopData['totalSoldPrice'] as num?)?.toDouble() ?? 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching total sales: $e');
      _totalSoldPrice = 0.0;
    }
  }

  // ✅ Public method to refresh total sales (for transactions tab)
  Future<void> refreshTotalSales() async {
    await _fetchTotalSalesFromShop();
  }

  Product _normalizeProduct(Product p) {
    return p.copyWith(
      category: p.category.trim(),
      subcategory: p.subcategory.trim(),
      subsubcategory: p.subsubcategory.trim(),
    );
  }

  Future<void> _warmupForSelectedShop() async {
    if (_selectedShop == null || _warmupInFlight) return;
    _warmupInFlight = true;

    try {
      // Only load Dashboard essentials
      await Future.wait([
        fetchActiveCampaigns(),
        _fetchTotalSalesFromShop(),
        getMetrics(), // This needs products, so fetch minimal
      ]);

      // Re-check after async gap - shop may have changed or been cleared
      if (_selectedShop == null) return;

      // Setup listeners (lightweight)
      _setupQuestionListener(_selectedShop!.id);
      _setupShopNotificationsListener(_selectedShop!.id);

      // Don't load other tabs' data here
    } finally {
      _warmupInFlight = false;
    }
  }

  // In SellerPanelProvider.initialize():
  Future<void> initialize() async {
    if (_initInFlight) return;
    _initInFlight = true;

    try {
      await fetchShops().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ Shop fetch timed out during initialization');
          // Set empty state so UI can show error
          _shops = [];
          _isLoadingShops = false;
          notifyListeners();
        },
      );

      if (_selectedShop == null && _shops.isNotEmpty) {
        _selectedShop = _shops.first;
        notifyListeners();
        _warmupForSelectedShop();
      }
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> fetchActiveCampaigns() async {
    try {
      // ✅ OPTIMIZATION: Apply retry logic with exponential backoff
      final campaignSnapshot = await _retryWithBackoff(
        () => _firestore
            .collection('campaigns')
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .get(),
        operationKey: 'fetchActiveCampaigns',
      );

      if (campaignSnapshot.docs.isNotEmpty) {
        _activeCampaigns = campaignSnapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();

        _campaignDismissed = false;
        _currentCampaignIndex = 0;

        await checkAllCampaignParticipation();
      } else {
        _activeCampaigns = [];
        _campaignParticipationStatus = {};
        _currentCampaignIndex = 0;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching active campaigns: $e');
      _activeCampaigns = [];
      _campaignParticipationStatus = {};
      _currentCampaignIndex = 0;
      notifyListeners();
    }
  }

  Future<void> checkAllCampaignParticipation() async {
    if (_selectedShop == null || _activeCampaigns.isEmpty) {
      _campaignParticipationStatus = {};
      return;
    }

    try {
      _campaignParticipationStatus.clear();

      // ✅ OPTIMIZATION: Batched campaign participation queries to avoid N+1 problem
      // Instead of N queries (one per campaign), we do 1 query to fetch all participating campaigns
      final campaignIds =
          _activeCampaigns.map((c) => c['id'] as String).toList();

      // Firestore whereIn supports up to 10 items, so batch if needed
      for (int i = 0; i < campaignIds.length; i += 10) {
        final batch = campaignIds.skip(i).take(10).toList();

        // ✅ OPTIMIZATION: Apply retry logic
        final snapshot = await _retryWithBackoff(
          () => _firestore
              .collection('shop_products')
              .where('shopId', isEqualTo: _selectedShop!.id)
              .where('campaign', whereIn: batch)
              .get(),
          operationKey: 'checkCampaignParticipation_$i',
        );

        // Mark which campaigns have products
        final participatingCampaigns = snapshot.docs
            .map((doc) => doc.data()['campaign'] as String?)
            .whereType<String>()
            .toSet();

        for (var campaignId in batch) {
          _campaignParticipationStatus[campaignId] =
              participatingCampaigns.contains(campaignId);
        }
      }
    } catch (e) {
      debugPrint('Error checking campaign participation: $e');
      _campaignParticipationStatus = {};
    }
  }

  void dismissCampaign() {
    _campaignDismissed = true;
    notifyListeners();
  }

  Future<void> refreshCampaignStatus() async {
    await checkAllCampaignParticipation();
    notifyListeners();
  }

  /// Optimistically update campaign participation status for immediate UI feedback.
  /// Call this after successfully saving products to a campaign.
  void setCampaignParticipation(String campaignId, bool participated) {
    _campaignParticipationStatus[campaignId] = participated;
    notifyListeners();
  }

  Map<String, dynamic>? get currentCampaign {
    if (_activeCampaigns.isEmpty ||
        _currentCampaignIndex >= _activeCampaigns.length) {
      return null;
    }
    return _activeCampaigns[_currentCampaignIndex];
  }

  bool get currentCampaignHasParticipation {
    final campaign = currentCampaign;
    if (campaign == null) return false;
    return _campaignParticipationStatus[campaign['id']] ?? false;
  }

  void updateCampaignIndex(int index) {
    if (_activeCampaigns.isEmpty) {
      _currentCampaignIndex = 0;
      return;
    }

    if (index >= 0 && index < _activeCampaigns.length) {
      _currentCampaignIndex = index;
      notifyListeners();
    } else {
      _currentCampaignIndex = 0;
      debugPrint('Campaign index out of bounds: $index, setting to 0');
      notifyListeners();
    }
  }

  Future<void> fetchStockProducts({String? shopId, int limit = 20}) async {
    if (_firebaseAuth.currentUser == null) {
      _filteredStockProductsNotifier.value = [];
      _isLoadingStockNotifier.value = false;
      return;
    }

    // Request deduplication - cancel stale requests when filters change rapidly
    final myQueryId = ++_activeStockQueryId;

    _isLoadingStockNotifier.value = true;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;

    try {
      final effectiveShopId = shopId ?? _selectedShop?.id;
      final filters = <List<String>>[
        if (effectiveShopId != null) ['shopId:$effectiveShopId'],
      ];

      if (_stockCategoryNotifier.value != null) {
        filters.add(['category:${_stockCategoryNotifier.value}']);
      }
      if (_stockSubcategoryNotifier.value != null) {
        filters.add(['subcategory:${_stockSubcategoryNotifier.value}']);
      }

      String? additionalFilter;
      if (_stockOutOfStockNotifier.value) {
        additionalFilter = 'quantity:=0';
      }

      final typesense = TypeSenseServiceManager.instance.shopService;
      final result = await typesense.searchIdsWithFacets(
        indexName: 'shop_products',
        query: _stockSearchQueryNotifier.value.isEmpty
            ? '*'
            : _stockSearchQueryNotifier.value,
        page: 0,
        hitsPerPage: limit,
        facetFilters: filters,
        sortOption: 'date',
        additionalFilterBy: additionalFilter,
      );

      // Drop stale responses
      if (myQueryId != _activeStockQueryId) {
        debugPrint(
            'Dropping stale stock query response (ID: $myQueryId, current: $_activeStockQueryId)');
        return;
      }

      final products = result.hits
          .map((hit) => Product.fromTypeSense(hit))
          .map(_normalizeProduct)
          .toList();

      for (final product in products) {
        _updateProductMap(product);
      }

      _filteredStockProductsNotifier.value = products;
      _currentStockPage = result.page;
      _hasMoreStockProducts = result.page < result.nbPages - 1;
    } catch (e) {
      debugPrint('Error fetching stock products: $e');
      if (myQueryId == _activeStockQueryId) {
        _filteredStockProductsNotifier.value = [];
      }
    } finally {
      if (myQueryId == _activeStockQueryId) {
        _isLoadingStockNotifier.value = false;
      }
    }
  }

  Future<void> fetchNextStockPage({String? shopId, int limit = 20}) async {
    if (!_hasMoreStockProducts || _isFetchingMoreProductsNotifier.value) return;

    _isFetchingMoreProductsNotifier.value = true;

    try {
      final effectiveShopId = shopId ?? _selectedShop?.id;
      final filters = <List<String>>[
        if (effectiveShopId != null) ['shopId:$effectiveShopId'],
      ];

      if (_stockCategoryNotifier.value != null) {
        filters.add(['category:${_stockCategoryNotifier.value}']);
      }
      if (_stockSubcategoryNotifier.value != null) {
        filters.add(['subcategory:${_stockSubcategoryNotifier.value}']);
      }

      String? additionalFilter;
      if (_stockOutOfStockNotifier.value) {
        additionalFilter = 'quantity:=0';
      }

      final typesense = TypeSenseServiceManager.instance.shopService;
      final result = await typesense.searchIdsWithFacets(
        indexName: 'shop_products',
        query: _stockSearchQueryNotifier.value.isEmpty
            ? '*'
            : _stockSearchQueryNotifier.value,
        page: _currentStockPage + 1,
        hitsPerPage: limit,
        facetFilters: filters,
        sortOption: 'date',
        additionalFilterBy: additionalFilter,
      );

      final newProducts = result.hits
          .map((hit) => Product.fromTypeSense(hit))
          .map(_normalizeProduct)
          .toList();

      for (final product in newProducts) {
        _updateProductMap(product);
      }

      // Dedup: skip products already in the list
      final existingIds =
          _filteredStockProductsNotifier.value.map((p) => p.id).toSet();
      final deduped = newProducts.where((p) => !existingIds.contains(p.id));
      _filteredStockProductsNotifier.value =
          List<Product>.from(_filteredStockProductsNotifier.value)
            ..addAll(deduped);

      _currentStockPage = result.page;
      _hasMoreStockProducts = result.page < result.nbPages - 1;
    } catch (e) {
      debugPrint('Error fetching next stock page: $e');
    } finally {
      _isFetchingMoreProductsNotifier.value = false;
    }
  }

  void setStockSearchQuery(String query, {bool reset = false}) {
    if (_stockSearchQueryNotifier.value == query && !reset) return;
    _stockSearchQueryNotifier.value = query;
    if (reset) {
      _currentStockPage = 0;
      _hasMoreStockProducts = true;
    }
    fetchStockProducts(shopId: _selectedShop?.id);
  }

  void setStockCategory(String? category) {
    if (_stockCategoryNotifier.value == category) return;
    _stockCategoryNotifier.value = category;
    _stockSubcategoryNotifier.value = null;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;
    fetchStockProducts(shopId: _selectedShop?.id);
  }

  void setStockSubcategory(String? subcategory) {
    if (_stockSubcategoryNotifier.value == subcategory) return;
    _stockSubcategoryNotifier.value = subcategory;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;
    fetchStockProducts(shopId: _selectedShop?.id);
  }

  void setOutOfStockFilter(bool value) {
    if (_stockOutOfStockNotifier.value == value) return;
    _stockOutOfStockNotifier.value = value;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;
    fetchStockProducts(shopId: _selectedShop?.id);
  }

  void setSearchModeImmediate(bool isSearchMode) {
    if (_isSearchMode != isSearchMode) {
      _isSearchMode = isSearchMode;
      notifyListeners();
    }
  }

  Future<void> fetchShipments({
    String? shopId,
    bool forceRefresh = false,
    bool loadMore = false,
    String? statusFilter,
    int limit = 20,
  }) async {
    if (_firebaseAuth.currentUser == null) {
      _shipmentsNotifier.value = [];
      _shipmentsStreamController.add(_shipmentsNotifier.value);
      _isLoadingMoreShipmentsNotifier.value = false;
      return;
    }

    // CRITICAL: Must have a selected shop
    final effectiveShopId = shopId ?? _selectedShop?.id;
    if (effectiveShopId == null) {
      debugPrint('❌ No shop selected for shipments query');
      _shipmentsNotifier.value = [];
      _shipmentsStreamController.add(_shipmentsNotifier.value);
      _isLoadingMoreShipmentsNotifier.value = false;
      return;
    }

    if (!forceRefresh && !loadMore && _shipmentsNotifier.value.isNotEmpty) {
      _shipmentsStreamController.add(_shipmentsNotifier.value);
      return;
    }

    if (loadMore) {
      if (!_hasMoreShipments || _isLoadingMoreShipmentsNotifier.value) return;
      _isLoadingMoreShipmentsNotifier.value = true;
    } else {
      _lastShipmentDoc = null;
      _hasMoreShipments = true;
      _isLoadingMoreShipmentsNotifier.value = true;
    }

    try {
      Query query = _firestore.collectionGroup('items');

      // FIX: Query by shopId (which matches sellerId in items)
      query = query.where('shopId', isEqualTo: effectiveShopId);

      // Apply status filter if specified
      if (statusFilter != null && statusFilter.isNotEmpty) {
        if (statusFilter == 'delivered') {
          query = query.where('deliveredInPartial', isEqualTo: true);
        } else if (statusFilter == 'pending') {
          query = query.where('gatheringStatus', isEqualTo: 'pending');
        } else if (statusFilter == 'in_progress') {
          query = query.where('gatheringStatus',
              whereIn: ['assigned', 'gathered', 'at_warehouse']);
        } else if (statusFilter == 'failed') {
          query = query.where('gatheringStatus', isEqualTo: 'failed');
        }
      }

      query = query.orderBy('timestamp', descending: true).limit(limit);

      if (loadMore && _lastShipmentDoc != null) {
        query = query.startAfterDocument(_lastShipmentDoc!);
      }

      final snapshot = await _retryWithBackoff(
        () => query.get(),
        operationKey: 'fetchShipments',
      );

      List<DocumentSnapshot> docs = snapshot.docs;

      debugPrint(
          '📦 Fetched ${docs.length} shipment items for shop: $effectiveShopId');

      if (loadMore) {
        final updatedShipments =
            List<DocumentSnapshot>.from(_shipmentsNotifier.value)..addAll(docs);
        _shipmentsNotifier.value = updatedShipments;
      } else {
        _shipmentsNotifier.value = docs;
      }

      _lastShipmentDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMoreShipments = snapshot.docs.length == limit;
      _shipmentsStreamController.add(_shipmentsNotifier.value);

// ADD THIS LINE - Notify listeners to rebuild UI
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error fetching shipments: $e');
      if (!loadMore) {
        _shipmentsNotifier.value = [];
        _shipmentsStreamController.add(_shipmentsNotifier.value);
      }
    } finally {
      _isLoadingMoreShipmentsNotifier.value = false;
    }
  }

  Future<void> resetAndLoadShipments({
    required int pageSize,
    String? statusFilter,
  }) async {
    _shipmentsNotifier.value = [];
    _lastShipmentDoc = null;
    _hasMoreShipments = true;

    await fetchShipments(
      shopId: _selectedShop?.id,
      forceRefresh: true,
      statusFilter: statusFilter,
      limit: pageSize,
    );
  }

  Future<void> loadMoreShipments({
    required int pageSize,
    String? statusFilter,
  }) async {
    await fetchShipments(
      shopId: _selectedShop?.id,
      loadMore: true,
      statusFilter: statusFilter,
      limit: pageSize,
    );
  }

  Map<String, dynamic> getProductData(String productId) {
    final v = _productImageCache[productId];
    if (v == null) {
      return {
        'imageUrls': <String>[],
        'colorImages': <String, List<String>>{},
      };
    }
    // Touch entry to refresh LRU order using the safe method
    _cacheProductData(productId, v);
    return v;
  }

  void setFilterDate(DateTime? date) {
    _selectedDate = date;
    _selectedDateRange = null;

    // Instead of just updating filtered transactions, refetch with server-side filtering
    fetchTransactions(
      shopId: _selectedShop?.id,
      forceRefresh: true,
      startDate:
          date != null ? DateTime(date.year, date.month, date.day) : null,
      endDate: date != null
          ? DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
          : null,
    );

    notifyListeners();
  }

  void setFilterRange(DateTimeRange? range) {
    _selectedDateRange = range;
    _selectedDate = null;

    // Refetch with date range filtering
    fetchTransactions(
      shopId: _selectedShop?.id,
      forceRefresh: true,
      startDate: range?.start,
      endDate: range != null
          ? DateTime(
              range.end.year, range.end.month, range.end.day, 23, 59, 59, 999)
          : null,
    );

    notifyListeners();
  }

  void setDateMode(bool isSingleDate) {
    _isSingleDateMode = isSingleDate;
    notifyListeners();
  }

  void toggleShowGraph() {
    _showGraph = !_showGraph;
    notifyListeners();
  }

  void clearFilters() {
    _selectedDate = null;
    _selectedDateRange = null;
    _transactionSearchQuery = '';
    fetchTransactions(shopId: _selectedShop?.id, forceRefresh: true);
    notifyListeners();
  }

  void _updateFilteredTransactions() {
    if (_transactionSearchQuery.isEmpty) {
      _filteredTransactionsNotifier.value = _transactions;
      return;
    }

    final q = _transactionSearchQuery.toLowerCase();
    final filtered = _transactions.where((tx) {
      final data = tx.data() as Map<String, dynamic>;

      // ✅ Lazy-load product if not in map
      final productId = data['productId'] as String?;
      final productName =
          productId != null && _productMap.containsKey(productId)
              ? _productMap[productId]!.productName.toLowerCase()
              : (data['productName']?.toString().toLowerCase() ??
                  ''); // Fallback to denormalized data

      final customerName = data['customerName']?.toString().toLowerCase() ?? '';
      final orderId = data['orderId']?.toString().toLowerCase() ?? '';

      return productName.contains(q) ||
          customerName.contains(q) ||
          orderId.contains(q);
    }).toList();

    _filteredTransactionsNotifier.value = filtered;
  }

  // Keep backward compatibility getter
  List<DocumentSnapshot> get filteredTransactions =>
      _filteredTransactionsNotifier.value;

  Future<void> fetchShops() async {
    if (_firebaseAuth.currentUser == null) {
      _shops = [];
      _isLoadingShops = false;
      notifyListeners();
      return;
    }

    _isLoadingShops = true;
    notifyListeners();

    try {
      // ✅ OPTIMIZATION: Apply retry logic with exponential backoff for all shop queries
      final queries = await AnalyticsService.trackRead(
        operation: 'seller_fetch_all_shops',
        execute: () => _retryWithBackoff(
          () => Future.wait([
            _firestore
                .collection('shops')
                .where('ownerId', isEqualTo: userId)
                .get(),
            _firestore
                .collection('shops')
                .where('editors', arrayContains: userId)
                .get(),
            _firestore
                .collection('shops')
                .where('coOwners', arrayContains: userId)
                .get(),
            _firestore
                .collection('shops')
                .where('viewers', arrayContains: userId)
                .get(),
          ]),
          operationKey: 'fetchShops',
        ),
        metadata: {'query_count': 4, 'has_retry': true},
      );

      final shops = queries.fold<List<DocumentSnapshot>>([], (acc, snapshot) {
        acc.addAll(snapshot.docs);
        return acc;
      });

      // De-dupe and assign
      _shops = {for (final doc in shops) doc.id: doc}.values.toList();

      // If we don't have a selected shop yet, pick the first now that we surely have the list
      if (_selectedShop == null && _shops.isNotEmpty) {
        _selectedShop = _shops.first;
      }
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      _shops = [];
    } finally {
      _isLoadingShops = false;
      notifyListeners();
    }
  }

  Future<void> updateProductQuantity(
    String productId,
    int newQuantity, {
    String? color,
  }) async {
    try {
      final int index = _products.indexWhere((p) => p.id == productId);
      if (index == -1) return;
      final Product oldProduct = _products[index];

      final Map<String, dynamic> updateData = {};
      late final Product updatedProduct;
      if (color == null) {
        updateData['quantity'] = newQuantity;
        updatedProduct = oldProduct.copyWith(quantity: newQuantity);
      } else {
        final currentColors =
            Map<String, int>.from(oldProduct.colorQuantities ?? {});
        currentColors[color] = newQuantity;
        updateData['colorQuantities'] = currentColors;
        updatedProduct = oldProduct.copyWith(colorQuantities: currentColors);
      }

      await AnalyticsService.trackWrite(
        operation: 'seller_stock_update_quantity',
        execute: () => _firestore
            .collection('shop_products')
            .doc(productId)
            .update(updateData),
        writeCount: 1,
        metadata: {
          'has_color_variant': color != null,
          'new_quantity': newQuantity,
        },
      );

      _products[index] = updatedProduct;
      // Update products tab
      final filteredIndex =
          _filteredProductsNotifier.value.indexWhere((p) => p.id == productId);
      if (filteredIndex != -1) {
        final updatedFiltered =
            List<Product>.from(_filteredProductsNotifier.value);
        updatedFiltered[filteredIndex] = updatedProduct;
        _filteredProductsNotifier.value = updatedFiltered;
      }
      // Update stock tab
      final stockIndex = _filteredStockProductsNotifier.value
          .indexWhere((p) => p.id == productId);
      if (stockIndex != -1) {
        final updatedStock =
            List<Product>.from(_filteredStockProductsNotifier.value);
        updatedStock[stockIndex] = updatedProduct;
        _filteredStockProductsNotifier.value = updatedStock;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating product quantity: $e');
    }
  }

  Future<void> removeProduct(String productId) async {
    try {
      // Call the cloud function instead of direct deletion
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('removeShopProduct');

      final result = await AnalyticsService.trackCloudFunction(
        functionName: 'removeShopProduct',
        execute: () => callable.call({
          'productId': productId,
          'shopId': _selectedShop?.id,
        }),
        metadata: {'product_id': productId},
      );

      if (result.data['success'] == true) {
        // Remove from local state
        _products.removeWhere((product) => product.id == productId);

        // Remove from filtered products
        final updatedFiltered =
            List<Product>.from(_filteredProductsNotifier.value);
        updatedFiltered.removeWhere((p) => p.id == productId);
        _filteredProductsNotifier.value = updatedFiltered;

        // Remove from stock products
        final updatedStock =
            List<Product>.from(_filteredStockProductsNotifier.value);
        updatedStock.removeWhere((p) => p.id == productId);
        _filteredStockProductsNotifier.value = updatedStock;

        // Remove from search results if in search mode
        if (_isSearchMode) {
          final updatedSearch =
              List<Product>.from(_searchResultsNotifier.value);
          updatedSearch.removeWhere((p) => p.id == productId);
          _searchResultsNotifier.value = updatedSearch;
        }

        // Remove from product map if exists
        _productMap.remove(productId);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error removing product: $e');
      rethrow; // Let the UI handle the error
    }
  }

  Future<void> toggleProductPauseStatus(
      String productId, bool pauseStatus) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('toggleProductPauseStatus');

      final result = await AnalyticsService.trackCloudFunction(
        functionName: 'toggleProductPauseStatus',
        execute: () => callable.call({
          'productId': productId,
          'shopId': _selectedShop?.id,
          'pauseStatus': pauseStatus,
        }),
        metadata: {'pause_status': pauseStatus},
      );

      if (result.data['success'] == true) {
        // Update local state
        final index = _products.indexWhere((p) => p.id == productId);
        if (index != -1) {
          _products[index] = _products[index].copyWith(paused: pauseStatus);
        }

        // Update filtered products
        final filteredIndex = _filteredProductsNotifier.value
            .indexWhere((p) => p.id == productId);
        if (filteredIndex != -1) {
          final updatedFiltered =
              List<Product>.from(_filteredProductsNotifier.value);
          updatedFiltered[filteredIndex] =
              updatedFiltered[filteredIndex].copyWith(paused: pauseStatus);
          _filteredProductsNotifier.value = updatedFiltered;
        }

        // Update stock products
        final stockIndex = _filteredStockProductsNotifier.value
            .indexWhere((p) => p.id == productId);
        if (stockIndex != -1) {
          final updatedStock =
              List<Product>.from(_filteredStockProductsNotifier.value);
          updatedStock[stockIndex] =
              updatedStock[stockIndex].copyWith(paused: pauseStatus);
          _filteredStockProductsNotifier.value = updatedStock;
        }

        // Update search results if in search mode
        if (_isSearchMode) {
          final searchIndex =
              _searchResultsNotifier.value.indexWhere((p) => p.id == productId);
          if (searchIndex != -1) {
            final updatedSearch =
                List<Product>.from(_searchResultsNotifier.value);
            updatedSearch[searchIndex] =
                updatedSearch[searchIndex].copyWith(paused: pauseStatus);
            _searchResultsNotifier.value = updatedSearch;
          }
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error toggling product pause status: $e');
      rethrow;
    }
  }

  void updateProduct(String productId, Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _products[index] = updatedProduct;
    }

    final filteredIndex =
        _filteredProductsNotifier.value.indexWhere((p) => p.id == productId);
    if (filteredIndex != -1) {
      final updatedFiltered =
          List<Product>.from(_filteredProductsNotifier.value);
      updatedFiltered[filteredIndex] = updatedProduct;
      _filteredProductsNotifier.value = updatedFiltered;
    }

    final stockIndex = _filteredStockProductsNotifier.value
        .indexWhere((p) => p.id == productId);
    if (stockIndex != -1) {
      final updatedStock =
          List<Product>.from(_filteredStockProductsNotifier.value);
      updatedStock[stockIndex] = updatedProduct;
      _filteredStockProductsNotifier.value = updatedStock;
    }

    if (_productMap.containsKey(productId)) {
      _updateProductMap(updatedProduct);
    }

    notifyListeners();
  }

  Future<void> fetchProducts({String? shopId, bool loadMore = false}) async {
    final myQueryId = ++_activeProductQueryId;

    if (loadMore) {
      _isFetchingMoreProductsNotifier.value = true;
    } else {
      _isLoadingProducts = true;
      _currentProductPage = 0;
      _hasMoreProducts = true;
      notifyListeners();
    }

    try {
      // Determine Typesense index and owner filter
      final String indexName;
      final List<List<String>> filters;
      if (shopId != null) {
        indexName = 'shop_products';
        filters = [
          ['shopId:$shopId']
        ];
      } else {
        indexName = 'products';
        filters = [
          ['ownerId:$userId']
        ];
      }

      // Category filtering via Typesense facets
      if (_selectedCategory != null) {
        filters.add(['category:$_selectedCategory']);
      }
      if (_selectedSubcategory != null) {
        filters.add(['subcategory:$_selectedSubcategory']);
      }

      final typesense = TypeSenseServiceManager.instance.shopService;
      final result = await typesense.searchIdsWithFacets(
        indexName: indexName,
        query: '*',
        page: loadMore ? _currentProductPage + 1 : 0,
        hitsPerPage: 20,
        facetFilters: filters,
        sortOption: 'date',
      );

      // Drop stale responses
      if (myQueryId != _activeProductQueryId) return;

      final newProducts = result.hits
          .map((hit) => Product.fromTypeSense(hit))
          .map(_normalizeProduct)
          .toList();

      for (final product in newProducts) {
        _updateProductMap(product);
      }

      if (loadMore) {
        // Dedup: skip products already in the list
        final existingIds = _products.map((p) => p.id).toSet();
        _products.addAll(newProducts.where((p) => !existingIds.contains(p.id)));
      } else {
        _products = newProducts;
      }

      _currentProductPage = result.page;
      _hasMoreProducts = result.page < result.nbPages - 1;

      _updateFilteredProducts();
    } catch (e) {
      debugPrint('Error fetching products: $e');
      if (myQueryId == _activeProductQueryId && !loadMore) {
        _products = [];
        _filteredProductsNotifier.value = [];
      }
    } finally {
      if (myQueryId == _activeProductQueryId) {
        if (loadMore) {
          _isFetchingMoreProductsNotifier.value = false;
        } else {
          _isLoadingProducts = false;
          notifyListeners();
        }
      }
    }
  }

  Future<void> fetchMoreProducts({String? shopId}) async {
    if (!_hasMoreProducts || _isFetchingMoreProductsNotifier.value) return;
    await fetchProducts(shopId: shopId, loadMore: true);
  }

  Future<void> fetchTransactions({
    String? shopId,
    bool forceRefresh = false,
    bool loadMore = false,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_firebaseAuth.currentUser == null) {
      _transactions = [];
      _filteredTransactionsNotifier.value = [];
      _transactionError = null;
      _isLoadingTransactionsNotifier.value = false;
      return;
    }

    // Early return if already loaded and no refresh requested
    if (!forceRefresh &&
        !loadMore &&
        _transactions.isNotEmpty &&
        _transactionError == null) {
      return;
    }

    if (loadMore) {
      _isLoadingMoreTransactionsNotifier.value = true;
    } else {
      _isLoadingTransactionsNotifier.value = true;
      _currentTransactionPage = 0;
      _hasMoreTransactions = true;

      // Cancel existing subscription if migrating from old real-time listener
      if (_transactionSubscription != null) {
        await _transactionSubscription!.cancel();
        _transactionSubscription = null;
        await Future.delayed(_listenerCancelDelay);
      }
    }

    _transactionError = null;

    try {
      // Build Typesense filters
      final filters = <List<String>>[];
      if (shopId != null) {
        filters.add(['shopId:$shopId']);
      } else {
        filters.add(['sellerId:$userId']);
      }

      // Date filtering via Typesense numeric filter
      String? additionalFilter;
      final dateFilters = <String>[];
      if (startDate != null) {
        final startUnix = startDate.millisecondsSinceEpoch ~/ 1000;
        dateFilters.add('timestampForSorting:>=$startUnix');
      }
      if (endDate != null) {
        final endUnix = endDate.millisecondsSinceEpoch ~/ 1000;
        dateFilters.add('timestampForSorting:<=$endUnix');
      }
      if (dateFilters.isNotEmpty) {
        additionalFilter = dateFilters.join(' && ');
      }

      final typesense = TypeSenseServiceManager.instance.ordersService;
      final page = loadMore ? _currentTransactionPage + 1 : 0;
      final result = await typesense.searchIdsWithFacets(
        indexName: 'orders',
        query: '*',
        page: page,
        hitsPerPage: 20,
        facetFilters: filters,
        sortOption: 'timestamp',
        additionalFilterBy: additionalFilter,
        queryBy: 'searchableText,productName,buyerName,sellerName',
        includeFields: 'id,orderId,productId,shopId,sellerId,buyerId,timestampForSorting',
      );

      // Hydrate from Firestore by ID (cheap reads, no composite indexes)
      final docs = await typesense
          .fetchDocumentSnapshotsFromTypeSenseResults(result.hits);

      if (loadMore) {
        // Dedup: skip transactions already in the list
        final existingIds = _transactions.map((d) => d.id).toSet();
        _transactions.addAll(docs.where((d) => !existingIds.contains(d.id)));
        _isLoadingMoreTransactionsNotifier.value = false;
      } else {
        _transactions = docs;
        _isLoadingTransactionsNotifier.value = false;
      }

      _currentTransactionPage = result.page;
      _hasMoreTransactions = result.page < result.nbPages - 1;
      _transactionError = null;
      _updateFilteredTransactions();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      _transactionError = 'Failed to load transactions.';
      if (!loadMore) {
        _transactions = [];
        _filteredTransactionsNotifier.value = [];
      }
      _isLoadingTransactionsNotifier.value = false;
      _isLoadingMoreTransactionsNotifier.value = false;
      notifyListeners();
    }
  }

  Future<void> fetchMoreTransactions({String? shopId}) async {
    if (!_hasMoreTransactions || _isLoadingMoreTransactionsNotifier.value)
      return;

    // Pass current date filters when loading more
    await fetchTransactions(
      shopId: shopId,
      loadMore: true,
      startDate: _selectedDate != null
          ? DateTime(
              _selectedDate!.year, _selectedDate!.month, _selectedDate!.day)
          : _selectedDateRange?.start,
      endDate: _selectedDate != null
          ? DateTime(_selectedDate!.year, _selectedDate!.month,
              _selectedDate!.day, 23, 59, 59, 999)
          : _selectedDateRange != null
              ? DateTime(
                  _selectedDateRange!.end.year,
                  _selectedDateRange!.end.month,
                  _selectedDateRange!.end.day,
                  23,
                  59,
                  59,
                  999)
              : null,
    );
  }

  Future<void> switchShop(String shopId) async {
    // Early exit for same shop
    if (_selectedShop?.id == shopId) {
      debugPrint('✅ Already on shop $shopId, skipping switch');
      return;
    }

    // ========== CONCURRENCY GUARD ==========
    if (_switchingToShopId == shopId) {
      debugPrint('⏳ Already switching to $shopId, waiting...');
      return _switchCompleters[shopId]?.future ?? Future.value();
    }

    if (_switchingToShopId != null) {
      debugPrint(
          '⚠️ Cancelling switch to $_switchingToShopId, switching to $shopId instead');
      _switchCompleters[_switchingToShopId!]
          ?.completeError('Cancelled by new switch operation');
      _switchCompleters.remove(_switchingToShopId);
    }

    _switchingToShopId = shopId;
    final completer = Completer<void>();
    _switchCompleters[shopId] = completer;

    try {
      // Find target shop
      DocumentSnapshot? target;
      try {
        target = _shops.firstWhere((s) => s.id == shopId);
      } catch (_) {
        await fetchShops();
        try {
          target = _shops.firstWhere((s) => s.id == shopId);
        } catch (_) {
          debugPrint('❌ Shop $shopId not found after refresh');
          completer.completeError('Shop not found');
          return;
        }
      }

      // Cleanup old state
      await _cleanupShopListeners();

      // Update selection
      _selectedShop = target;
      _selectedCategory = null;
      _selectedSubcategory = null;
      _resetShopState();

      // ✅ Immediate UI update with try-catch
      try {
        notifyListeners();
      } catch (e) {
        debugPrint('⚠️ notifyListeners failed: $e');
      }

      // Load data in background
      await Future.wait([
        fetchActiveCampaigns(),
      ], eagerError: false);

      await _setupQuestionListener(shopId);
      await _setupShopNotificationsListener(shopId);

      final dataFutures = [
        fetchProducts(shopId: shopId).catchError((e) {
          debugPrint('⚠️ fetchProducts error: $e');
          return null;
        }),
        fetchTransactions(shopId: shopId, forceRefresh: true).catchError((e) {
          debugPrint('⚠️ fetchTransactions error: $e');
          return null;
        }),
        resetAndLoadShipments(pageSize: 20).catchError((e) {
          debugPrint('⚠️ resetAndLoadShipments error: $e');
          return null;
        }),
        fetchStockProducts(shopId: shopId).catchError((e) {
          debugPrint('⚠️ fetchStockProducts error: $e');
          return null;
        }),
        _fetchTotalSalesFromShop().catchError((e) {
          debugPrint('⚠️ _fetchTotalSalesFromShop error: $e');
          return null;
        }),
      ];

      await Future.wait(dataFutures, eagerError: false)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('⚠️ Shop data fetch timed out after 10s');
        return [];
      });

      completer.complete();
    } catch (e, stackTrace) {
      debugPrint('❌ switchShop error: $e\n$stackTrace');
      completer.completeError(e);
      rethrow;
    } finally {
      _switchingToShopId = null;
      _switchCompleters.remove(shopId);
    }
  }

  Future<void> _cleanupShopListeners() async {
    debugPrint('🧹 Cleaning up shop listeners...');

    // Cancel transaction subscription
    if (_transactionSubscription != null) {
      await _transactionSubscription!.cancel();
      _transactionSubscription = null;
      await Future.delayed(_listenerCancelDelay);
    }

    // Cancel questions subscription
    if (_questionsSub != null) {
      await _questionsSub!.cancel();
      _questionsSub = null;
      await Future.delayed(_listenerCancelDelay);
    }

    // Cancel shop notifications subscription
    if (_shopNotificationsSub != null) {
      await _shopNotificationsSub!.cancel();
      _shopNotificationsSub = null;
      _currentNotificationShopId = null;
      _unreadNotificationCountNotifier.value = 0;
      await Future.delayed(_listenerCancelDelay);
    }

    debugPrint('✅ Shop listeners cleaned up');
  }

  Future<void> _setupQuestionListener(String shopId) async {
    try {
      // Cancel existing listener first
      if (_questionsSub != null) {
        await _questionsSub!.cancel();
        _questionsSub = null;
        await Future.delayed(_listenerCancelDelay);
      }

      // Verify shop hasn't changed
      if (_selectedShop?.id != shopId) {
        debugPrint('⚠️ Shop changed during listener setup, aborting');
        return;
      }

      _questionsSub = _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_questions')
          .where('answered', isEqualTo: false)
          .limit(1)
          .snapshots()
          .listen(
        (snap) {
          // Double-check shop hasn't changed
          if (_selectedShop?.id == shopId) {
            _hasUnansweredQuestions = snap.docs.isNotEmpty;
            notifyListeners();
          } else {
            debugPrint('⚠️ Shop changed, ignoring question listener update');
            _questionsSub?.cancel();
            _questionsSub = null;
          }
        },
        onError: (error) {
          debugPrint('⚠️ Question listener error: $error');
          _hasUnansweredQuestions = false;
          _questionsSub?.cancel();
          _questionsSub = null;
        },
        cancelOnError: true, // Important: auto-cancel on error
      );
    } catch (e, stackTrace) {
      debugPrint('⚠️ Failed to setup question listener: $e\n$stackTrace');
      _questionsSub?.cancel();
      _questionsSub = null;
    }
  }

  /// Sets up a real-time listener for shop notifications to track unread count.
  /// Each user has their own read status tracked via isRead map.
  Future<void> _setupShopNotificationsListener(String shopId) async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) {
      debugPrint('⚠️ No user logged in, skipping notifications listener');
      return;
    }

    // Skip if already listening to the same shop
    if (_currentNotificationShopId == shopId && _shopNotificationsSub != null) {
      debugPrint('✅ Already listening to notifications for shop $shopId');
      return;
    }

    try {
      // Cancel existing listener first
      if (_shopNotificationsSub != null) {
        await _shopNotificationsSub!.cancel();
        _shopNotificationsSub = null;
        await Future.delayed(_listenerCancelDelay);
      }

      // Verify shop hasn't changed
      if (_selectedShop?.id != shopId) {
        debugPrint(
            '⚠️ Shop changed during notification listener setup, aborting');
        return;
      }

      _currentNotificationShopId = shopId;

      _shopNotificationsSub = _firestore
          .collection('shop_notifications')
          .where('shopId', isEqualTo: shopId)
          .orderBy('timestamp', descending: true)
          .limit(100) // Limit to recent notifications for efficiency
          .snapshots()
          .listen(
        (snapshot) {
          // Double-check shop hasn't changed and user is still logged in
          final userId = _firebaseAuth.currentUser?.uid;
          if (_selectedShop?.id != shopId || userId == null) {
            debugPrint('⚠️ Context changed, ignoring notification update');
            _shopNotificationsSub?.cancel();
            _shopNotificationsSub = null;
            _currentNotificationShopId = null;
            return;
          }

          // Count unread notifications for current user
          int unreadCount = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final isReadMap = data['isRead'] as Map<String, dynamic>? ?? {};
            if (isReadMap[userId] != true) {
              unreadCount++;
            }
          }

          _unreadNotificationCountNotifier.value = unreadCount;
          debugPrint('📬 Unread notifications for shop $shopId: $unreadCount');
        },
        onError: (error) {
          debugPrint('⚠️ Shop notifications listener error: $error');
          _unreadNotificationCountNotifier.value = 0;
          _shopNotificationsSub?.cancel();
          _shopNotificationsSub = null;
          _currentNotificationShopId = null;
        },
        cancelOnError: true,
      );

      debugPrint('✅ Shop notifications listener setup for $shopId');
    } catch (e, stackTrace) {
      debugPrint(
          '⚠️ Failed to setup shop notifications listener: $e\n$stackTrace');
      _shopNotificationsSub?.cancel();
      _shopNotificationsSub = null;
      _currentNotificationShopId = null;
      _unreadNotificationCountNotifier.value = 0;
    }
  }

  void _updateProductMap(Product product) {
    // Implement size limit for product map
    if (_productMap.length >= _maxProductMapSize &&
        !_productMap.containsKey(product.id)) {
      // Remove oldest entries (simple FIFO)
      final keysToRemove = _productMap.keys.take(50).toList();
      for (var key in keysToRemove) {
        _productMap.remove(key);
      }
    }
    _productMap[product.id] = product;
  }

  void _cacheProductData(String productId, Map<String, dynamic> data) {
    // Implement LRU cache with size limit
    if (_productImageCache.length >= _maxCacheSize) {
      _productImageCache.remove(_productImageCache.keys.first);
    }
    _productImageCache[productId] = data;
  }

  void _resetShopState() {
    // Products state
    _products = [];
    _filteredProductsNotifier.value = [];
    _filteredStockProductsNotifier.value = [];
    _currentProductPage = 0;
    _hasMoreProducts = true;
    _currentStockPage = 0;
    _hasMoreStockProducts = true;
    _productMap.clear();

    // Cache state
    _productImageCache.clear();
    _cachedMetrics = null;
    _metricsLastFetched = null;

    // Shipments state
    _shipmentsNotifier.value = [];
    _lastShipmentDoc = null;
    _hasMoreShipments = true;

    // Transactions state
    _transactions = [];
    _filteredTransactionsNotifier.value = [];
    _currentTransactionPage = 0;
    _hasMoreTransactions = true;
    _transactionError = null;

    // Search state
    _searchQuery = '';
    _stockSearchQueryNotifier.value = '';
    _stockCategoryNotifier.value = null;
    _stockSubcategoryNotifier.value = null;
    _stockOutOfStockNotifier.value = false;

    // Search mode state
    _isSearchMode = false;
    _isSearchingNotifier.value = false;
    _searchResultsNotifier.value = [];
    _currentSearchPage = 0;
    _hasMoreSearchResults = true;
    _lastSearchQuery = '';
  }

  Future<Map<String, int>> getMetrics({bool forceRefresh = false}) async {
    // Force refresh by clearing cache if requested
    if (forceRefresh) {
      _metricsLastFetched = null;
    }

    // Call the private method
    return await _fetchMetrics();
  }

  Future<Map<String, int>> _fetchMetrics() async {
    // Check cache first
    if (_cachedMetrics != null && _metricsLastFetched != null) {
      final age = DateTime.now().difference(_metricsLastFetched!);
      if (age < _metricsCacheDuration) {
        return _cachedMetrics!;
      }
    }

    if (_selectedShop == null) {
      return {
        'productViews': 0,
        'soldProducts': 0,
        'carts': 0,
        'favorites': 0,
        'shopViews': 0,
        'boosts': 0,
      };
    }

    try {
      // NO NETWORK CALL - just read from already loaded shop document
      final shopData = _selectedShop!.data() as Map<String, dynamic>;
      final metrics = shopData['metrics'] as Map<String, dynamic>? ?? {};

      final result = {
        'productViews': metrics['totalProductViews'] as int? ?? 0,
        'carts': metrics['totalCartAdditions'] as int? ?? 0,
        'favorites': metrics['totalFavoriteAdditions'] as int? ?? 0,
        'soldProducts': shopData['totalProductsSold'] as int? ?? 0,
        'shopViews': shopData['clickCount'] as int? ?? 0,
        'boosts':
            metrics['boostCount'] as int? ?? 0, // From denormalized field now!
      };

      _cachedMetrics = result;
      _metricsLastFetched = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('Error reading metrics: $e');
      return {
        'productViews': 0,
        'soldProducts': 0,
        'carts': 0,
        'favorites': 0,
        'shopViews': 0,
        'boosts': 0,
      };
    }
  }

  Future<void> updateBoostOnProduct(String productId) async {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;

    final coll = _products[idx].shopId != null ? 'shop_products' : 'products';

    try {
      final snap = await _firestore.collection(coll).doc(productId).get();

      if (!snap.exists) {
        _products.removeAt(idx);
        _filteredProductsNotifier.value = _filteredProductsNotifier.value
            .where((p) => p.id != productId)
            .toList();
        _filteredStockProductsNotifier.value = _filteredStockProductsNotifier
            .value
            .where((p) => p.id != productId)
            .toList();
        notifyListeners();
        return;
      }

      final updated = Product.fromDocument(snap);
      final Product resolved;

      final now = DateTime.now();
      if (updated.boostEndTime != null &&
          updated.boostEndTime!.toDate().isBefore(now)) {
        resolved = updated.copyWith(
          isBoosted: false,
          boostStartTime: null,
          boostEndTime: null,
        );
      } else {
        resolved = updated;
      }

      _products[idx] = resolved;

      // Update products/ads tab
      final filteredIndex = _filteredProductsNotifier.value
          .indexWhere((p) => p.id == productId);
      if (filteredIndex != -1) {
        final updatedFiltered =
            List<Product>.from(_filteredProductsNotifier.value);
        updatedFiltered[filteredIndex] = resolved;
        _filteredProductsNotifier.value = updatedFiltered;
      }

      // Update stock tab
      final stockIndex = _filteredStockProductsNotifier.value
          .indexWhere((p) => p.id == productId);
      if (stockIndex != -1) {
        final updatedStock =
            List<Product>.from(_filteredStockProductsNotifier.value);
        updatedStock[stockIndex] = resolved;
        _filteredStockProductsNotifier.value = updatedStock;
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint('🛑 updateBoostOnProduct failed: $e\n$st');
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;

    if (query.trim().isEmpty) {
      // Exit search mode, show regular filtered products
      _exitSearchMode();
    } else {
      // Enter search mode and perform Typesense search
      _performSearch(query.trim());
    }

    notifyListeners();
  }

  void _performSearch(String query) {
    if (query == _lastSearchQuery && _isSearchMode) return;

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (_selectedShop == null) {
      debugPrint('❌ No selected shop');
      return;
    }

    final currentShopId = _selectedShop!.id;

    _isSearchMode = true;
    _isSearchingNotifier.value = true;
    _lastSearchQuery = query;
    _currentSearchPage = 0;
    _hasMoreSearchResults = true;

    // race token
    final myId = ++_activeQueryId;

    try {
      final results =
          await TypeSenseServiceManager.instance.shopService.searchShopProducts(
        shopId: currentShopId,
        query: query,
        sortOption: 'date',
        page: 0,
        hitsPerPage: 20,
      );

      // drop stale responses
      if (myId != _activeQueryId) return;

      _searchResultsNotifier.value = results;
      _hasMoreSearchResults = results.length == 20;
    } catch (e, st) {
      if (myId != _activeQueryId) return;
      debugPrint('Typesense search error: $e\n$st');
      _searchResultsNotifier.value = [];
      _hasMoreSearchResults = false;
    } finally {
      if (myId == _activeQueryId) {
        _isSearchingNotifier.value = false;
      }
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (!_hasMoreSearchResults ||
        _isLoadingMoreSearchResultsNotifier.value ||
        !_isSearchMode ||
        _selectedShop == null) return;

    _isLoadingMoreSearchResultsNotifier.value = true;
    _currentSearchPage++;

    // capture token
    final myId = _activeQueryId;

    try {
      final results =
          await TypeSenseServiceManager.instance.shopService.searchShopProducts(
        shopId: _selectedShop!.id,
        query: _lastSearchQuery,
        sortOption: 'date',
        page: _currentSearchPage,
        hitsPerPage: 20,
      );

      if (myId != _activeQueryId)
        return; // user changed query -> drop this page

      final current = List<Product>.from(_searchResultsNotifier.value);
      current.addAll(results);
      _searchResultsNotifier.value = current;
      _hasMoreSearchResults = results.length == 20;
    } catch (e) {
      if (myId != _activeQueryId) return;
      debugPrint('Load more search results error: $e');
      _hasMoreSearchResults = false;
    } finally {
      if (myId == _activeQueryId) {
        _isLoadingMoreSearchResultsNotifier.value = false;
      }
    }
  }

  void _exitSearchMode() {
    _searchDebounceTimer?.cancel();
    _isSearchMode = false;
    _isSearchingNotifier.value = false;
    _searchResultsNotifier.value = [];
    _isLoadingMoreSearchResultsNotifier.value = false;
    _lastSearchQuery = '';
    _currentSearchPage = 0;
    _hasMoreSearchResults = true;

    // invalidate current queries
    _activeQueryId++;

    _updateFilteredProducts();
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    _selectedSubcategory = null;

    // Reset pagination since we're changing the query
    _currentProductPage = 0;
    _hasMoreProducts = true;

    // Refetch products with new category filter
    fetchProducts(shopId: _selectedShop?.id);
    notifyListeners();
  }

  void setSubcategory(String? subcategory) {
    _selectedSubcategory = subcategory;

    // Reset pagination since we're changing the query
    _currentProductPage = 0;
    _hasMoreProducts = true;

    // Refetch products with new subcategory filter
    fetchProducts(shopId: _selectedShop?.id);
    notifyListeners();
  }

  void _updateFilteredProducts() {
    var filtered = _products;

    // Only apply search query filtering on client-side
    // Category filtering is now handled server-side
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        final name = product.productName.toLowerCase();
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    _filteredProductsNotifier.value = filtered;
  }

  void setTransactionSearchQuery(String query) {
    _transactionSearchQuery = query;
    _updateFilteredTransactions();
    notifyListeners();
  }

  Future<String> sendShopInvitation(String email, String role) async {
    if (selectedShop == null) return 'No shop selected.';
    try {
      return await AnalyticsService.trackTransaction(
        operation: 'seller_team_send_invitation',
        execute: () async {
          final userQuery = await _firestore
              .collection('users')
              .where('email', isEqualTo: email.trim())
              .limit(1)
              .get();
          if (userQuery.docs.isEmpty) return 'User with this email not found.';

          final inviteeId = userQuery.docs.first.id;
          final shopId = selectedShop!.id;
          final shopData = selectedShop!.data() as Map<String, dynamic>;
          final shopName = shopData['name'] as String? ?? 'Unnamed Shop';

          // Send notification (your existing logic)
          await _firestore
              .collection('users')
              .doc(inviteeId)
              .collection('notifications')
              .add({
            'userId': inviteeId,
            'type': 'shop_invitation',
            'shopId': shopId,
            'shopName': shopName,
            'role': role == 'co-owner' ? 'co-owner' : role,
            'senderId': userId,
            'status': 'pending',
            'timestamp': FieldValue.serverTimestamp(),
            'message_en': 'You have been invited to join a shop.',
            'message_tr': 'Bir mağazaya katılmanız için davet edildiniz.',
            'message_ru': 'Вас пригласили присоединиться к магазину.',
            'isRead': false,
          });

          // Create invitation record (your existing logic)
          await _firestore.collection('shopInvitations').add({
            'userId': inviteeId,
            'shopId': shopId,
            'shopName': shopName,
            'role': role == 'co-owner' ? 'co-owner' : role,
            'senderId': userId,
            'email': email,
            'status': 'pending',
            'timestamp': FieldValue.serverTimestamp(),
          });

          return 'Invitation sent to $email.';
        },
        readCount: 1, // user lookup
        writeCount: 2, // notification + invitation
        metadata: {
          'role': role,
          'target_email': email.substring(0, email.indexOf('@') + 2)
        }, // Partial email for privacy
      );
    } catch (e) {
      debugPrint('Failed to send invitation: $e');
      return 'Failed to send invitation: $e';
    }
  }

  Future<List<Map<String, dynamic>>> fetchPendingInvitations() async {
    if (_selectedShop == null) return [];
    try {
      final snapshot = await AnalyticsService.trackRead(
        operation: 'seller_team_fetch_pending_invitations',
        execute: () => _firestore
            .collection('shopInvitations')
            .where('shopId', isEqualTo: _selectedShop!.id)
            .where('status', isEqualTo: 'pending')
            .get(),
      );
      return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (e) {
      debugPrint('Error fetching pending invitations: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAcceptedInvitations() async {
    if (_selectedShop == null) return [];
    final shopData = _selectedShop!.data() as Map<String, dynamic>;
    final editors = (shopData['editors'] as List? ?? []).cast<String>();
    final viewers = (shopData['viewers'] as List? ?? []).cast<String>();
    final coOwners = (shopData['coOwners'] as List? ?? []).cast<String>();
    final ownerId = shopData['ownerId'] as String;

    List<Map<String, dynamic>> acceptedUsers = [];
    acceptedUsers.add({'userId': ownerId, 'role': 'owner'});
    for (var id in coOwners)
      acceptedUsers.add({'userId': id, 'role': 'co-owner'});
    for (var id in editors) acceptedUsers.add({'userId': id, 'role': 'editor'});
    for (var id in viewers) acceptedUsers.add({'userId': id, 'role': 'viewer'});

    // Track all user lookups
    await AnalyticsService.trackRead(
      operation: 'seller_team_fetch_member_details',
      execute: () async {
        for (var user in acceptedUsers) {
          try {
            final userDoc =
                await _firestore.collection('users').doc(user['userId']).get();
            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;
              user['displayName'] = userData['displayName'] ?? user['userId'];
            } else {
              user['displayName'] = user['userId'];
            }
          } catch (e) {
            debugPrint('Error fetching user data for ${user['userId']}: $e');
            user['displayName'] = user['userId'];
          }
        }
        return acceptedUsers.length; // Return count for analytics
      },
      metadata: {'member_count': acceptedUsers.length},
    );
    return acceptedUsers;
  }

  Future<String> cancelInvitation(String invitationId) async {
    // First get the invitation to find the invitee
    final invDoc =
        await _firestore.collection('shopInvitations').doc(invitationId).get();
    final invData = invDoc.data();

    if (invData != null) {
      final inviteeId = invData['userId'];
      // Now directly delete the notification
      final notifQuery = await _firestore
          .collection('users')
          .doc(inviteeId)
          .collection('notifications')
          .where('shopId', isEqualTo: _selectedShop!.id)
          .where('type', isEqualTo: 'shop_invitation')
          .get();

      for (var doc in notifQuery.docs) {
        await doc.reference.delete();
      }
    }

    await _firestore.collection('shopInvitations').doc(invitationId).delete();
    return 'Invitation cancelled successfully.';
  }

  Future<String> revokeUserAccess(String userId, String role) async {
    if (_selectedShop == null) return 'No shop selected.';

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('revokeShopAccess');

      await callable.call({
        'targetUserId': userId,
        'shopId': _selectedShop!.id,
        'role': role,
      });

      // Refresh the shop data
      final updatedShop =
          await _firestore.collection('shops').doc(_selectedShop!.id).get();
      _selectedShop = updatedShop;
      notifyListeners();

      return 'User access revoked successfully.';
    } catch (e) {
      debugPrint('Error revoking access: $e');
      return 'Failed to revoke access: ${e.toString()}';
    }
  }

  Future<void> fetchPastBoostHistory({String? shopId}) async {
    if (shopId == null) return;

    _isLoadingPastBoostHistory = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId)
          .where('boostEndTime', isLessThan: Timestamp.now())
          .orderBy('boostEndTime', descending: true)
          .get();

      _pastBoostHistory = snapshot.docs;
    } catch (e) {
      debugPrint('Error fetching past boost history: $e');
      _pastBoostHistory = [];
    } finally {
      _isLoadingPastBoostHistory = false;
      notifyListeners();
    }
  }
}
