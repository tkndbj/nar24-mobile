import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../generated/l10n/app_localizations.dart';
import '../providers/market_provider.dart';
import '../user_provider.dart';
import '../widgets/agreement_modal.dart';
import '../providers/search_provider.dart';
import '../providers/special_filter_provider_market.dart';
import '../providers/market_dynamic_filter_provider.dart';
import '../widgets/filter_sort_row.dart';
import '../widgets/preference_product.dart';
import '../widgets/market_banner.dart';
import '../widgets/market_app_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/product_list_sliver.dart';
import 'package:shimmer/shimmer.dart';
import '../models/product_summary.dart';
import '../models/dynamic_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../widgets/shop_horizontal_list_widget.dart';
import '../widgets/market_thin_banner.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'CATEGORIES/categories_screen.dart';
import 'CATEGORIES/categories_teras.dart';
import 'CART-FAVORITE/favorite_product_screen.dart';
import 'CART-FAVORITE/my_cart_screen.dart';
import 'USER-PROFILE/profile_screen.dart';
import 'teras_market.dart';
import '../providers/shop_widget_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/all_in_one_category_data.dart';
import '../route_observer.dart';
import '../widgets/market_top_ads_banner.dart';
import '../widgets/market_bubbles.dart';
import '../widgets/market_search_delegate.dart';
import '../providers/search_history_provider.dart';
import '../widgets/dynamic_product_list_widget.dart';
import '../services/market_layout_service.dart';
import 'DYNAMIC-SCREENS/market_screen_dynamic_filters_screen.dart';
import '../widgets/boosted_product_carousel.dart';
import '../widgets/coupon_celebration_overlay.dart';

class _HomeLayoutState {
  final String? error;
  final List<MarketWidgetConfig> widgets;
  final bool isLoading;

  _HomeLayoutState({
    required this.error,
    required this.widgets,
    required this.isLoading,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _HomeLayoutState &&
          error == other.error &&
          isLoading == other.isLoading &&
          _listEquals(widgets, other.widgets);

  @override
  int get hashCode =>
      error.hashCode ^ widgets.length.hashCode ^ isLoading.hashCode;

  bool _listEquals(List<MarketWidgetConfig> a, List<MarketWidgetConfig> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// Optimized keep-alive wrapper with better memory management
class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _KeepAliveWrapper({
    Key? key,
    required this.child,
    this.enabled = true,
  }) : super(key: key);

  @override
  _KeepAliveWrapperState createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.enabled;

  // ✅ OPTIMIZATION: Update keep-alive state when enabled changes
  @override
  void didUpdateWidget(_KeepAliveWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class MarketScreen extends StatefulWidget {
  final int? initialTab;

  const MarketScreen({Key? key, this.initialTab}) : super(key: key);

  @override
  MarketScreenState createState() => MarketScreenState();
}

class _Debouncer {
  _Debouncer(this.delay);
  final Duration delay;
  Timer? _t;
  void call(VoidCallback action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  void cancel() => _t?.cancel();
}

class MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  // Core controllers - initialized immediately
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  late final ScrollController _filterScrollController;
  late final PageController _pageController;
  late final ValueNotifier<Color> _adsBannerBgColor;
  late final GlobalKey<TerasMarketState> _terasKey;
  bool _couponOverlayChecked = false;
  // Providers - lazy loaded
  MarketProvider? _marketProvider;
  SpecialFilterProviderMarket? _specialFilterProvider;
  DynamicFilterProvider? _dynamicFilterProvider;

  // Batching mechanism to prevent cascade rebuilds
  bool _isBatchUpdating = false;
  int _pendingUpdates = 0;

  bool _showTerasCategories = false;

  // State management - optimized
  bool _isSearching = false;
  bool _isInitialized = false;
  int _selectedIndex = 0;
  int _currentPage = 0;
  String? _lastKnownUserId;
  Timer? _cleanupTimer;
  bool _isRouteActive = true; // Track if route is currently visible

  bool _isRebuilding = false;
  static const int _maxScrollDebouncers = 20;
  static const int _maxFilterRefreshEntries = 15;

  final Set<int> _builtFilterIndices = {0};

  // Filter views - optimized storage
  late final List<Widget> _filterViews;
  late final Map<String, int> _filterTabIndices;

  late final _Debouncer _searchDebounce;
  late final _Debouncer _pageDebounce;
  late final _Debouncer _listenerDebounce;

  final Map<String, Timer> _scrollDebouncers = {};
  bool _dynamicFilterAttached = false;

  // Listeners - optimized
  VoidCallback? _dynamicFilterListener;
  StreamSubscription<User?>? _authSubscription;

  // Performance tracking
  DateTime? _lastRefreshTime;
  // Reduced from 30s
  static const Duration _debounceDelay =
      Duration(milliseconds: 150); // Reduced from 500ms
  final Duration _refreshCooldown = Duration(seconds: 30);
  final Map<String, DateTime> _filterLastRefresh = {};

  // Agreement modal tracking - prevent showing multiple times
  bool _agreementModalShown = false;

  // Computed properties - cached
  bool get _isDynamicFiltersReady =>
      _dynamicFilterProvider?.isLoading == false &&
      _dynamicFilterProvider?.error == null;

  @override
  void initState() {
    super.initState();

    // Core
    _initializeCoreComponents();
    _setupInitialState();

    // Debouncer'lar (ADD)
    _searchDebounce = _Debouncer(_debounceDelay);
    _pageDebounce = _Debouncer(_debounceDelay);
    _listenerDebounce = _Debouncer(_debounceDelay);

    // Ağır işler sonraya
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProvidersAsync();
      _setupAsyncComponents();
    });
  }

  /// Immediate synchronous initialization
  void _initializeCoreComponents() {
    // Initialize controllers immediately
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController();
    _filterScrollController = ScrollController();
    _pageController = PageController();
    _adsBannerBgColor = ValueNotifier<Color>(Colors.transparent);
    _terasKey = GlobalKey<TerasMarketState>();

    // Initialize collections
    _filterViews = <Widget>[];
    _filterTabIndices = <String, int>{};

    // System setup
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addObserver(this);
  }

  /// Setup initial state
  void _setupInitialState() {
    // Set initial tab if provided
    if (widget.initialTab != null &&
        widget.initialTab! >= 0 &&
        widget.initialTab! < 7) {
      // CHANGE FROM 6 TO 7
      _selectedIndex = widget.initialTab!;
    }

    _lastKnownUserId = FirebaseAuth.instance.currentUser?.uid;

    // Initialize basic filter structure immediately
    _initializeBasicFilters();
  }

  /// Check if dynamic banner color should be applied.
  /// Returns true ONLY when user is on Market screen's Home filter.
  bool _shouldUseDynamicColor() {
    // Must be on Market tab (index 0)
    if (_selectedIndex != 0) return false;

    // Must be on Home filter page
    final homeIndex = _filterTabIndices['Home'] ?? 0;
    if (_currentPage != homeIndex) return false;

    // Must not be searching
    if (_isSearching) return false;

    return true;
  }

  /// Async provider initialization
  Future<void> _initializeProvidersAsync() async {
    try {
      // Phase 1: CRITICAL DATA ONLY (blocks UI ~200ms)
      _marketProvider = Provider.of<MarketProvider>(context, listen: false);
      _specialFilterProvider =
          Provider.of<SpecialFilterProviderMarket>(context, listen: false);
      _dynamicFilterProvider =
          Provider.of<DynamicFilterProvider>(context, listen: false);

      _marketProvider?.recordImpressions = false;
      _setupListeners(); // Just setup, no fetching

      if (mounted) {
        setState(() => _isInitialized = true);
      }

      // Phase 2: DEFERRED INITIALIZATION (non-blocking)
      Future.microtask(() async {
        if (!mounted) return;

        // Load layout service in background
        await _initializeLayoutService();

        // Only rebuild filters if dynamic filters already exist
        if (_dynamicFilterProvider?.activeFilters.isNotEmpty == true) {
          _rebuildFilterViewsWithDynamic();
        }

        if (mounted) setState(() {});
      });

      // Phase 3: LAZY LOADING (load when user actually needs it)
      // Don't call _startBackgroundTasks() here anymore
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Provider initialization error: $e');
      }
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    }
  }

  void _setupAsyncComponents() {
    _setupControllerListeners();
    _rebuildFilterViewsWithDynamic();

    // ✅ FIXED: Start cleanup timer (now properly cancellable)
    _schedulePeriodicCacheCleanup();

    // Check and show agreement modal for Google users who haven't accepted
    _checkAndShowAgreementModal();

    _checkAndShowCouponCelebration();
  }

  Future<void> _checkAndShowCouponCelebration() async {
    // Prevent multiple checks
    if (_couponOverlayChecked) return;
    _couponOverlayChecked = true;

    try {
      // Wait a bit for the app to settle and agreement modal to finish
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      // Check if agreement modal is still showing (don't overlap)
      if (_agreementModalShown) {
        // Wait for agreement modal to be dismissed
        await Future.delayed(const Duration(seconds: 2));
      }

      if (!mounted) return;

      // Only show on market tab (index 0)
      if (_selectedIndex != 0) return;

      // Show the coupon celebration if eligible
      final shown = await CouponCelebrationOverlay.showIfEligible(context);

      if (shown && kDebugMode) {
        debugPrint('🎟️ Coupon celebration overlay was shown');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🎟️ Error showing coupon celebration: $e');
      }
    }
  }

  /// Check if user needs to accept agreements and show modal if needed.
  /// This only applies to Google-registered users who haven't accepted yet.
  Future<void> _checkAndShowAgreementModal() async {
    // Prevent showing multiple times
    if (_agreementModalShown) return;

    try {
      // CRITICAL: Double-check auth state directly from Firebase
      // This prevents showing modal when user isn't truly authenticated
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) return;

      // Verify the user can actually get a valid token (proves they're authenticated)
      try {
        await firebaseUser.getIdToken();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('User token invalid, skipping agreement modal: $e');
        }
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // Only check for social users (Google/Apple) who bypass registration form
      if (!userProvider.isSocialUser) return;

      // Check local storage first (this is the primary source)
      final hasAcceptedLocally =
          await AgreementModal.hasAcceptedAgreements(firebaseUser.uid);
      if (hasAcceptedLocally) return;

      // Wait for profile state to be ready (max 3 seconds)
      // This prevents showing modal before we know if they've already accepted
      int waitAttempts = 0;
      const maxWaitAttempts = 30; // 30 * 100ms = 3 seconds max
      while (
          !userProvider.isProfileStateReady && waitAttempts < maxWaitAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitAttempts++;
        if (!mounted) return;
      }

      // Re-check auth after waiting (user might have logged out)
      if (FirebaseAuth.instance.currentUser == null) return;

      // Check Firestore as secondary source
      final profileData = userProvider.profileData;
      final hasAcceptedInFirestore = profileData?['agreementsAccepted'] == true;

      if (hasAcceptedInFirestore) return;

      // Mark as shown to prevent duplicate modals
      _agreementModalShown = true;

      // Small delay to ensure UI is ready
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      // Final auth check before showing modal
      if (FirebaseAuth.instance.currentUser == null) {
        _agreementModalShown =
            false; // Reset so it can show later if they login
        return;
      }

      // Show the agreement modal
      await AgreementModal.show(context);

      // Refresh user data after acceptance
      if (mounted) {
        await userProvider.refreshUser();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking agreement status: $e');
      }
    }
  }

Future<void> _initializeLayoutService() async {
  try {
    final layoutService =
        Provider.of<MarketLayoutService>(context, listen: false);
    await layoutService.initialize();
    // One-time fetch only, no listeners needed
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Layout service initialization error: $e');
    }
  }
}

  bool _shouldKeepAlive(int index) {
    final distance = (index - _currentPage).abs();
    return distance <= 1; // Only keep current and adjacent pages
  }

  void _schedulePeriodicCacheCleanup() {
    // Cancel any existing timer
    _cleanupTimer?.cancel();

    // Create periodic timer (runs every 5 minutes)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) {
        _cleanupTimer?.cancel();
        return;
      }

      _performCacheCleanup();
    });
  }

  /// ✅ NEW: Extracted cleanup logic (easier to test/maintain)
  void _performCacheCleanup() {
    int cleanedItems = 0;

    // 1. Clean scroll debouncers
    if (_scrollDebouncers.length > _maxScrollDebouncers) {
      final sortedKeys = _scrollDebouncers.keys.toList();
      final removeCount = _scrollDebouncers.length - _maxScrollDebouncers;

      for (int i = 0; i < removeCount; i++) {
        _scrollDebouncers[sortedKeys[i]]?.cancel();
        _scrollDebouncers.remove(sortedKeys[i]);
        cleanedItems++;
      }
    }

    // 2. Clean filter refresh cache
    if (_filterLastRefresh.length > _maxFilterRefreshEntries) {
      final sortedEntries = _filterLastRefresh.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final removeCount = _filterLastRefresh.length - _maxFilterRefreshEntries;

      for (int i = 0; i < removeCount; i++) {
        _filterLastRefresh.remove(sortedEntries[i].key);
        cleanedItems++;
      }
    }

    // 3. Clean built filter indices
    if (_builtFilterIndices.length > 20) {
      final currentPage = _currentPage;
      final oldSize = _builtFilterIndices.length;

      _builtFilterIndices.clear();
      _builtFilterIndices.add(currentPage);
      if (currentPage > 0) _builtFilterIndices.add(currentPage - 1);
      if (currentPage < _filterViews.length - 1) {
        _builtFilterIndices.add(currentPage + 1);
      }

      cleanedItems += oldSize - _builtFilterIndices.length;
    }

    if (cleanedItems > 0 && kDebugMode) {
      debugPrint('🗑️ Periodic cleanup: Removed $cleanedItems items');
    }
  }

  /// Basic filter initialization - minimal setup
  void _initializeBasicFilters() {
    _filterViews.clear();
    _filterTabIndices.clear();

    // Add home filter
    _filterViews.add(
      _KeepAliveWrapper(
        enabled: true, // Home should always be kept alive
        child: Builder(builder: (context) => _buildHomeContent()),
      ),
    );
    _filterTabIndices['Home'] = 0;

    // Add static category filters
    final staticFilters = [
      'Women',
      'Men',
      'Electronics',
      'Home & Furniture',
      'Mother & Child'
    ];

    for (int i = 0; i < staticFilters.length; i++) {
      final filter = staticFilters[i];
      final index = i + 1;
      _filterTabIndices[filter] = index;

      _filterViews.add(
        _KeepAliveWrapper(
          enabled: _shouldKeepAlive(index),
          child: Builder(
              builder: (context) =>
                  _buildFilterView(filter)), // Build actual widget
        ),
      );
    }
  }

  /// Optimized listener setup
  void _setupListeners() {
    _setupDynamicFilterListener();
  }

  /// Setup controller listeners
  void _setupControllerListeners() {
    _searchController.addListener(() {
      if (kDebugMode) {
        debugPrint('🔍 Search changed: "${_searchController.text}"');
      }
    });
  }

  /// Optimized dynamic filter listener
  void _setupDynamicFilterListener() {
    _dynamicFilterListener = () {
      if (kDebugMode) {
        debugPrint('🔄 Dynamic filter listener triggered');
      }
      _listenerDebounce(() {
        if (!mounted) return;

        // ✅ ADD: Cleanup old filter notifiers before rebuilding
        if (_dynamicFilterProvider != null && _specialFilterProvider != null) {
          final activeIds =
              _dynamicFilterProvider!.activeFilters.map((f) => f.id).toList();
          _specialFilterProvider!.cleanupOldFilterNotifiers(activeIds);
        }

        if (kDebugMode) {
          debugPrint('🏗️ Rebuilding filter views with dynamic filters');
        }
        _rebuildFilterViewsWithDynamic();
      });
    };
    if (_dynamicFilterProvider != null) {
      _dynamicFilterProvider!.addListener(_dynamicFilterListener!);
      _dynamicFilterAttached = true;
    }

    // İlk yüklemede zaten aktif filtreler varsa
    if (_dynamicFilterProvider?.activeFilters.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildFilterViewsWithDynamic();
      });
    }
  }

  bool _shouldLoadMore(
    ScrollNotification notif,
    SpecialFilterProviderMarket prov,
    String filterType,
  ) {
    return notif is ScrollEndNotification &&
        prov.hasMore(filterType) &&
        !prov.isLoadingMore(filterType) &&
        notif.metrics.pixels >= notif.metrics.maxScrollExtent * 0.9;
  }

// Per-filter debounced loadMore (ADD)
  void _scheduleInfiniteScroll(String key, VoidCallback action) {
    // Var olanı iptal et
    _scrollDebouncers[key]?.cancel();
    _scrollDebouncers[key] = Timer(_debounceDelay, () {
      action();
      // tamamlanınca kaldır
      _scrollDebouncers.remove(key);
    });
  }

  void _rebuildFilterViewsWithDynamic() {
    if (!mounted) return;

    // ✅ ENHANCED: Better race condition handling
    if (_isRebuilding) {
      if (kDebugMode) {
        debugPrint('⏭️ Skipping rebuild - already in progress');
      }
      return;
    }

    // Set flag before any async operations
    _isRebuilding = true;

    // ✅ NEW: Use try-catch-finally pattern for guaranteed cleanup
    try {
      _builtFilterIndices.clear();
      _builtFilterIndices.add(0);

      // Clean up old notifiers BEFORE rebuilding
      if (_dynamicFilterProvider != null && _specialFilterProvider != null) {
        final activeIds =
            _dynamicFilterProvider!.activeFilters.map((f) => f.id).toList();
        _specialFilterProvider!.cleanupOldFilterNotifiers(activeIds);
      }

      // Check if rebuild is needed
      if (_dynamicFilterProvider != null) {
        final newFilterIds =
            _dynamicFilterProvider!.activeFilters.map((f) => f.id).toSet();

        final currentDynamicFilterIds = _filterTabIndices.keys
            .where((k) => ![
                  'Home',
                  'Women',
                  'Men',
                  'Electronics',
                  'Home & Furniture',
                  'Mother & Child'
                ].contains(k))
            .toSet();

        if (setEquals(newFilterIds, currentDynamicFilterIds) &&
            _filterViews.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('⏭️ Skipping rebuild - no structural changes');
          }
          return; // ✅ Flag will be reset in finally
        }

        if (kDebugMode) {
          debugPrint('🔄 Rebuilding filters - structure changed');
        }
      }

      final currentFilterType = _getCurrentFilterType();
      final currentPageIndex = _currentPage;

      if (_dynamicFilterProvider == null) {
        if (_filterViews.isEmpty) {
          _initializeBasicFilters();
        }
        return; // ✅ Flag will be reset in finally
      }

      final allActiveFilters = _dynamicFilterProvider!.activeFilters;
      final activeFilters = allActiveFilters.take(10).toList();

      if (allActiveFilters.length > 10 && kDebugMode) {
        debugPrint(
            '⚠️ Limiting dynamic filters from ${allActiveFilters.length} to 10');
      }

      final staticFilters = [
        'Women',
        'Men',
        'Electronics',
        'Home & Furniture',
        'Mother & Child'
      ];

      // Clean up old filter views
      for (int i = 0; i < _filterViews.length; i++) {
        if (i >= 10 + staticFilters.length + 1) {
          _filterViews[i] = const SizedBox.shrink();
        }
      }

      _filterViews.clear();
      _filterTabIndices.clear();

      if (kDebugMode) {
        debugPrint(
            '📊 Rebuilding with ${activeFilters.length} dynamic filters');
      }

      // 1. Add Home
      _filterViews.add(
        _KeepAliveWrapper(
          enabled: _shouldKeepAlive(0),
          child: Builder(builder: (context) => _buildHomeContent()),
        ),
      );
      _filterTabIndices['Home'] = 0;

      // 2. Add dynamic filters
      for (int i = 0; i < activeFilters.length; i++) {
        final filter = activeFilters[i];
        final index = i + 1;
        _filterTabIndices[filter.id] = index;

        _filterViews.add(
          _KeepAliveWrapper(
            enabled: _shouldKeepAlive(index),
            child:
                Builder(builder: (context) => _buildDynamicFilterView(filter)),
          ),
        );
      }

      // 3. Add static filters
      for (int i = 0; i < staticFilters.length; i++) {
        final filter = staticFilters[i];
        final index = 1 + activeFilters.length + i;
        _filterTabIndices[filter] = index;

        _filterViews.add(
          _KeepAliveWrapper(
            enabled: _shouldKeepAlive(index),
            child: Builder(builder: (context) => _buildFilterView(filter)),
          ),
        );
      }

      if (kDebugMode) {
        debugPrint('✅ Filter rebuild complete: ${_filterViews.length} views');
      }

      if (mounted) setState(() {});

      // Clean up orphaned data
      if (_specialFilterProvider != null) {
        final validFilterTypes = _filterTabIndices.keys.toSet();
        _specialFilterProvider!.cleanupOrphanedData(validFilterTypes);
      }

      _handlePageRestoration(currentFilterType, currentPageIndex, false);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Error rebuilding filter views: $e');
        debugPrint('Stack trace: $stackTrace');
      }

      // ✅ ENHANCED: Better error recovery
      try {
        _filterViews.clear();
        _filterTabIndices.clear();
        _initializeBasicFilters();

        if (mounted) setState(() {});
      } catch (fallbackError) {
        if (kDebugMode) {
          debugPrint('❌ Critical: Fallback failed: $fallbackError');
        }
      }
    } finally {
      // ✅ CRITICAL: Always reset flag, even on early return or exception
      _isRebuilding = false;
    }
  }

  /// Optimized page restoration
  void _handlePageRestoration(String? currentFilterType, int currentPageIndex,
      bool wasOnDynamicFilter) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      final specialFilter = _specialFilterProvider?.specialFilter;
      final shouldStayOnHome = specialFilter?.isEmpty ?? true;

      if (shouldStayOnHome) {
        final homeIndex = _filterTabIndices['Home'] ?? 0;
        if (_currentPage != homeIndex) {
          _jumpToPageSafely(homeIndex);
        }
        return;
      }

      // Use microtask for better performance
      Future.microtask(() {
        if (!mounted || !_pageController.hasClients) return;

        int targetPage = _calculateTargetPage(
            currentFilterType, currentPageIndex, wasOnDynamicFilter);
        _jumpToPageSafely(targetPage);
      });
    });
  }

  /// Calculate target page efficiently
  int _calculateTargetPage(String? currentFilterType, int currentPageIndex,
      bool wasOnDynamicFilter) {
    if (currentFilterType != null &&
        _filterTabIndices.containsKey(currentFilterType)) {
      return _filterTabIndices[currentFilterType]!;
    }

    if (wasOnDynamicFilter && !_isDynamicFiltersReady) {
      return _filterTabIndices['Home'] ?? 0;
    }

    if (currentPageIndex < _filterViews.length) {
      return currentPageIndex;
    }

    return 0;
  }

  /// Safe page jumping with error handling
  void _jumpToPageSafely(int targetPage) {
    if (targetPage >= _filterViews.length) targetPage = 0;
    try {
      _pageController.jumpToPage(targetPage);
      // ✅ REACTIVE: setState triggers rebuild, which computes correct color
      setState(() {
        _currentPage = targetPage;
      });
    } catch (_) {
      _pageController.jumpToPage(0);
      setState(() {
        _currentPage = 0;
      });
    }
  }

  /// Navigation methods - optimized
  void navigateToTab(int idx) => _onNavItemTapped(idx);

  void _onNavItemTapped(int idx) {
    if (_isSearching) {
      _setSearchMode(false);
      setState(() {
        _selectedIndex = idx;
        if (idx != 1) {
          _showTerasCategories = false;
        }
      });
      return;
    }

    if (idx < 0 || idx >= 6) {
      if (kDebugMode) {
        debugPrint('Invalid navigation index: $idx');
      }
      return;
    }

    if (idx != _selectedIndex) {
      final wasOnMarket = _selectedIndex == 0;
      _clearSearch();

      setState(() {
        _selectedIndex = idx;
        if (idx != 1) _showTerasCategories = false;
      });

      // When returning to market screen (idx 0), restore the saved filter page
      if (idx == 0 && !wasOnMarket) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController.hasClients &&
              _currentPage < _filterViews.length) {
            _pageController.jumpToPage(_currentPage);
          }
        });
      }
    } else if (idx == 0) {
      _animateToHomePage();
    } else if (idx == 1) {
      setState(() {
        _showTerasCategories = !_showTerasCategories;
      });
    }
  }

  /// Optimized home page animation
  void _animateToHomePage() {
    final futures = <Future>[];

    if (_pageController.hasClients) {
      futures.add(_pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      ));
    }

    if (_filterScrollController.hasClients) {
      futures.add(_filterScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      ));
    }
  }

  /// Optimized search management
  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  /// Single entry point for all search mode transitions.
  /// Handles cleanup (clear text, unfocus) when exiting search.
  void _setSearchMode(bool searching) {
    if (_isSearching == searching) return;
    if (!searching) {
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
    setState(() {
      _isSearching = searching;
    });
  }

  void exitSearchMode() {
    _setSearchMode(false);
  }

  Future<void> _submitSearch() async {
    try {
      _unfocusKeyboard();

      final term = _searchController.text.trim();
      if (term.isEmpty) return;

      _marketProvider?.recordSearchTerm(term);
      _marketProvider?.clearSearchCache();
      _marketProvider?.resetSearch(triggerFilter: false);

      // Exit search mode before navigation. The PageView stays mounted
      // (Stack approach), so the filter page position is preserved.
      _setSearchMode(false);

      if (mounted) {
        context.push('/search_results', extra: {'query': term});
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in submit search: $e');
      }
    }
  }

  /// Utility methods
  void _unfocusKeyboard() => FocusScope.of(context).unfocus();

  int getCurrentPage() => _currentPage;

  String? _getCurrentFilterType() {
    final match =
        _filterTabIndices.entries.where((e) => e.value == _currentPage);
    return match.firstOrNull?.key;
  }

  bool _isDynamicFilter(String? filterType) {
    if (filterType == null) return false;
    return _dynamicFilterProvider?.activeFilters
            .any((f) => f.id == filterType) ??
        false;
  }

  /// Optimized throttled refresh
  /// Enhanced throttled refresh with per-filter cooldown
  Future<void> _throttledRefresh(Future<dynamic> Function() action,
      {String? filterType}) async {
    final now = DateTime.now();

    // Check global cooldown
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _refreshCooldown) {
      if (kDebugMode) {
        debugPrint('⏰ Global refresh cooldown active');
      }
      return;
    }

    // Check filter-specific cooldown if provided
    if (filterType != null) {
      final lastFilterRefresh = _filterLastRefresh[filterType];
      if (lastFilterRefresh != null &&
          now.difference(lastFilterRefresh) < _refreshCooldown) {
        if (kDebugMode) {
          debugPrint('⏰ Filter $filterType refresh cooldown active');
        }
        return;
      }
      _filterLastRefresh[filterType] = now;
    }

    _lastRefreshTime = now;
    try {
      await action();
      if (kDebugMode) {
        debugPrint('✅ Refresh completed for ${filterType ?? 'global'}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Refresh failed for ${filterType ?? 'global'}: $e');
      }
    }
  }

  void _handlePageChange(int page, {required bool debounced}) {
    if (page < 0 || page >= _filterViews.length) return;

    final filterType = _getFilterTypeForPage(page);
    if (filterType == null) return;

    // ✅ ADD: Mark this page and adjacent pages as built
    _builtFilterIndices.add(page);
    if (page > 0) _builtFilterIndices.add(page - 1);
    if (page < _filterViews.length - 1) _builtFilterIndices.add(page + 1);

    if (debounced && filterType != 'Home') {
      _lazyLoadFilterIfNeeded(filterType);
    }

    final isDynamic = _isDynamicFilter(filterType);

    if (isDynamic && _dynamicFilterProvider?.activeFilters.isEmpty == true) {
      if (kDebugMode) {
        debugPrint('⚠️ Dynamic filter $filterType not available yet');
      }
      return;
    }

    DynamicFilter? dynamicFilter;
    if (isDynamic) {
      dynamicFilter = _getDynamicFilterById(filterType);
      if (dynamicFilter == null) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ Dynamic filter $filterType not found in active filters');
        }
        return;
      }
    }

    if (kDebugMode) {
      debugPrint(
          '🎯 Page change: $page -> $filterType (dynamic: $isDynamic, debounced: $debounced)');
    }

    if (debounced) {
      _specialFilterProvider?.setSpecialFilter(
        filterType == 'Home' ? '' : filterType,
        dynamicFilter: dynamicFilter,
      );

      if (filterType != 'Home') {
        final products = _specialFilterProvider?.getProducts(filterType) ?? [];
        if (products.isEmpty) {
          _specialFilterProvider?.fetchProducts(
            filterType: filterType,
            page: 0,
            limit: 20,
            dynamicFilter: dynamicFilter,
          );
        }
        _scrollToFilterButton(filterType);
      }
    }
  }

  void _lazyLoadFilterIfNeeded(String filterType) {
    if (_specialFilterProvider == null) return;

    final products = _specialFilterProvider!.getProducts(filterType);

    // Only fetch if empty
    if (products.isEmpty) {
      final dynamicFilter = _isDynamicFilter(filterType)
          ? _getDynamicFilterById(filterType)
          : null;

      _specialFilterProvider!.fetchProducts(
        filterType: filterType,
        page: 0,
        limit: 20,
        dynamicFilter: dynamicFilter,
      );

      if (kDebugMode) {
        debugPrint('⚡ Lazy loaded filter: $filterType');
      }
    }
  }

  /// Helper methods for page handling
  String? _getFilterTypeForPage(int page) {
    return _filterTabIndices.entries
        .where((entry) => entry.value == page)
        .firstOrNull
        ?.key;
  }

  DynamicFilter? _getDynamicFilterById(String filterId) {
    try {
      return _dynamicFilterProvider?.activeFilters
          .where((f) => f.id == filterId)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Optimized filter tab switching
  void switchToFilterTab(String filterType) {
    final idx = _filterTabIndices[filterType];
    if (idx == null) {
      if (kDebugMode) {
        debugPrint('⚠️ Filter tab not found: $filterType');
        debugPrint('📋 Available tabs: ${_filterTabIndices.keys.toList()}');
      }
      return;
    }

    final isDynamic = _isDynamicFilter(filterType);

    // Allow switching to dynamic filters even if they're still loading
    if (isDynamic && _dynamicFilterProvider?.activeFilters.isEmpty == true) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ Dynamic filter $filterType not available, ignoring tab switch');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '🎯 Switching to filter tab: $filterType (index: $idx, dynamic: $isDynamic)');
    }

    _currentPage = idx;

    if (_pageController.hasClients) {
      _pageController.jumpToPage(idx);
    }

    final dynamicFilter = isDynamic ? _getDynamicFilterById(filterType) : null;
    _specialFilterProvider?.setSpecialFilter(filterType,
        dynamicFilter: dynamicFilter);
  }

  /// Optimized scroll to filter button
  void _scrollToFilterButton(String filterType) {
    if (!_filterScrollController.hasClients) return;

    try {
      final shopProvider =
          Provider.of<ShopWidgetProvider>(context, listen: false);
      final hasShop = _hasUserShop(shopProvider);

      final buttonIndex = _calculateButtonIndex(filterType, hasShop);
      if (buttonIndex == null) return;

      _animateToFilterButton(buttonIndex);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error scrolling to filter button: $e');
      }
    }
  }

  /// Check if user has shop
  bool _hasUserShop(ShopWidgetProvider shopProvider) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    return shopProvider.shops.any((shop) {
      final data = shop.data() as Map<String, dynamic>;
      return data['ownerId'] == uid ||
          (data['coOwners']?.contains(uid) ?? false) ||
          (data['editors']?.contains(uid) ?? false) ||
          (data['viewers']?.contains(uid) ?? false);
    });
  }

  /// Calculate button index efficiently
  int? _calculateButtonIndex(String filterType, bool hasShop) {
    final baseOffset = hasShop ? 1 : 0;
    const shopsOffset = 1;
    final dynamicFiltersCount =
        _dynamicFilterProvider?.activeFilters.length ?? 0;

    // Check dynamic filters first
    final dynamicFilterIndex = _dynamicFilterProvider?.activeFilters
            .indexWhere((f) => f.id == filterType) ??
        -1;

    if (dynamicFilterIndex != -1) {
      return baseOffset + shopsOffset + dynamicFilterIndex;
    }

    // Check static category filters
    final staticFilterOffsets = {
      'Women': baseOffset + shopsOffset + dynamicFiltersCount,
      'Men': baseOffset + shopsOffset + dynamicFiltersCount + 1,
      'Electronics': baseOffset + shopsOffset + dynamicFiltersCount + 2,
      'Home & Furniture': baseOffset + shopsOffset + dynamicFiltersCount + 3,
      'Mother & Child': baseOffset + shopsOffset + dynamicFiltersCount + 4,
    };

    return staticFilterOffsets[filterType];
  }

  /// Animate to filter button
  void _animateToFilterButton(int buttonIndex) {
    const buttonWidth = 100.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final target =
        buttonIndex * buttonWidth - screenWidth / 2 + buttonWidth / 2;

    final clampedTarget =
        target.clamp(0.0, _filterScrollController.position.maxScrollExtent);

    _filterScrollController.animateTo(
      clampedTarget,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Color parsing helper - optimized
  Color _parseColor(String colorString) {
    try {
      final cleanColor = colorString.replaceAll('#', '');
      if (cleanColor.length == 6) {
        return Color(int.parse('FF$cleanColor', radix: 16));
      } else if (cleanColor.length == 8) {
        return Color(int.parse(cleanColor, radix: 16));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing color $colorString: $e');
      }
    }
    return Colors.orange;
  }

  /// Widget builders - optimized with better error handling
  Widget _buildHomeContent() {
    return Selector<MarketLayoutService, _HomeLayoutState>(
      selector: (_, service) => _HomeLayoutState(
        error: service.error,
        widgets: service.visibleWidgets,
        isLoading: service.isLoading,
      ),
      builder: (context, state, child) {
        if (state.error != null) {
          return _buildErrorView(state.error);
        }
        return _buildHomeScrollView(state.widgets);
      },
    );
  }

  Widget _buildErrorView(String? error) {
    return RefreshIndicator(
      onRefresh: () async {
        final layoutService =
            Provider.of<MarketLayoutService>(context, listen: false);
        await layoutService.refresh();
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    error ?? 'Layout yüklenirken hata oluştu',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      // ✅ Get layoutService here too
                      final layoutService = Provider.of<MarketLayoutService>(
                          context,
                          listen: false);
                      layoutService.refresh();
                    },
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeScrollView(List<MarketWidgetConfig> visibleWidgets) {
    return RefreshIndicator(
      onRefresh: () => _throttledRefresh(
        () async {
          // PreferenceProduct widget manages its own refresh via service
          // No need to manually trigger it here - it will reload automatically
          // when the parent rebuilds
        },
        filterType: 'Home',
      ),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: _buildDynamicSlivers(visibleWidgets),
      ),
    );
  }

  void _clearFilterCache(String filterType) {
    _specialFilterProvider?.clearFilterCache(filterType);
    if (_isDynamicFilter(filterType)) {
      _dynamicFilterProvider?.clearFilterCache(filterType);
    }
    if (kDebugMode) {
      debugPrint('🗑️ Cleared cache for filter: $filterType');
    }
  }

  /// Force refresh a specific filter (bypasses cooldown)
  Future<void> _forceRefreshFilter(String filterType) async {
    _clearFilterCache(filterType);
    _filterLastRefresh.remove(filterType);

    final dynamicFilter =
        _isDynamicFilter(filterType) ? _getDynamicFilterById(filterType) : null;

    await _specialFilterProvider?.refreshProducts(
      filterType,
      dynamicFilter: dynamicFilter,
    );

    if (kDebugMode) {
      debugPrint('🔄 Force refreshed filter: $filterType');
    }
  }

  /// Optimized dynamic slivers builder
  List<Widget> _buildDynamicSlivers(List<MarketWidgetConfig> visibleWidgets) {
    // ✅ OPTIMIZATION: Cache MediaQuery
    final mediaQuery = MediaQuery.of(context);
    final List<Widget> slivers = [];

    // Detect tablet for spacing adjustments
    final screenWidth = mediaQuery.size.width;
    final bool isTablet = screenWidth >= 600;
    final bool isLandscape = mediaQuery.orientation == Orientation.landscape;

    // Tablet-specific spacing: more spacing to prevent widget overlap
    // Landscape tablets need even more spacing due to shorter viewport
    final double widgetSpacing = isTablet
        ? (isLandscape ? 28.0 : 22.0) // Tablets: 28px landscape, 22px portrait
        : 12.0; // Mobile: 12px (unchanged)

    for (int i = 0; i < visibleWidgets.length; i++) {
      final widget = visibleWidgets[i];
      final isLastWidget = i == visibleWidgets.length - 1;

      // Build widget based on type
      final sliverWidget = _buildSliverForType(widget.type);
      if (sliverWidget != null) {
        slivers.add(sliverWidget);

        // Add spacing between widgets (except last one)
        if (!isLastWidget) {
          slivers.add(SliverToBoxAdapter(
            child: SizedBox(height: widgetSpacing),
          ));
        }
      }
    }

    // Add bottom padding
    slivers.add(SliverToBoxAdapter(
      child: SizedBox(
        height: 20 + mediaQuery.padding.bottom,
      ),
    ));

    return slivers;
  }

  /// Build sliver for specific widget type
  Widget? _buildSliverForType(String type) {
    switch (type) {
      case 'ads_banner':
        return SliverToBoxAdapter(
          child: ValueListenableBuilder<Color>(
            valueListenable: _adsBannerBgColor,
            child: AdsBannerWidget(
              backgroundColorNotifier: _adsBannerBgColor,
              shouldAutoPlay: _isRouteActive, // Pause when route is not active
            ),
            builder: (context, bg, child) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              color: bg,
              child: child,
            ),
          ),
        );

      case 'market_bubbles':
        return SliverToBoxAdapter(
          child: MarketBubbles(onNavItemTapped: _onNavItemTapped),
        );

      case 'thin_banner':
        return SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Determine if it's a tablet/larger screen
              final isTablet = constraints.maxWidth >= 600;

              if (!isTablet) {
                // Mobile: use original widget as-is
                return MarketThinBanner(shouldAutoPlay: _isRouteActive);
              }

              // Tablet: center the banner with max width
              final maxWidth = constraints.maxWidth > 1200 ? 800.0 : 600.0;

              return Center(
                child: Container(
                  width: maxWidth,
                  child: MarketThinBanner(shouldAutoPlay: _isRouteActive),
                ),
              );
            },
          ),
        );

      case 'preference_product':
        return const SliverToBoxAdapter(child: PreferenceProduct());

      case 'boosted_product_carousel':
        return const SliverToBoxAdapter(child: BoostedProductsCarousel());

      case 'dynamic_product_list':
        return const SliverToBoxAdapter(child: DynamicProductListsWidget());

      case 'market_banner':
        return const MarketBannerSliver();

      case 'shop_horizontal_list':
        return const SliverToBoxAdapter(child: ShopHorizontalListWidget());

      default:
        if (kDebugMode) {
          debugPrint('Unknown widget type: $type');
        }
        return null;
    }
  }

  /// Optimized home screen body
  Widget _buildHomeScreenBody() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _unfocusKeyboard,
      child: Column(
        children: [
          _buildFilterSortRow(),
          _buildPageView(),
        ],
      ),
    );
  }

  /// Build filter sort row with optimized animations
  Widget _buildFilterSortRow() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final fallbackColor = isDarkMode ? const Color(0xFF1C1A29) : Colors.white;
    final onHomeFilter = _shouldUseDynamicColor();

    // ✅ REACTIVE: Only listen to banner color when on Home filter
    if (onHomeFilter) {
      return ValueListenableBuilder<Color>(
        valueListenable: _adsBannerBgColor,
        builder: (_, bannerColor, __) {
          return FilterSortRow(
            scrollController: _filterScrollController,
            backgroundColor: bannerColor,
            animate: true,
            textColor: Colors.white,
          );
        },
      );
    }

    // Not on Home filter - use static fallback color
    return FilterSortRow(
      scrollController: _filterScrollController,
      backgroundColor: fallbackColor,
      animate: false,
      textColor: isDarkMode ? Colors.white : Colors.black,
    );
  }

  /// Build optimized page view
  Widget _buildPageView() {
    return Expanded(
      child: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: _filterViews.length,
        itemBuilder: (context, index) {
          // ✅ Build on-demand when page is viewed
          if (!_builtFilterIndices.contains(index)) {
            // Return placeholder until user swipes near this page
            if ((index - _currentPage).abs() > 1) {
              return const Center(child: CircularProgressIndicator());
            }
            // Mark as built when coming into view
            _builtFilterIndices.add(index);
          }

          return index < _filterViews.length
              ? _filterViews[index]
              : const SizedBox.shrink();
        },
        onPageChanged: _handlePageViewChange,
        allowImplicitScrolling: true,
      ),
    );
  }

  /// Handle page view changes with validation
  void _handlePageViewChange(int page) {
    if (page < 0 || page >= _filterViews.length) return;

    // ✅ REACTIVE: Just update state, the build method will compute correct color
    setState(() {
      _currentPage = page;
    });

    _pageDebounce(() {
      _handlePageChange(page, debounced: true);
    });
  }

  /// Build teras market screen body
  Widget _buildTerasMarketScreenBody() {
    return TerasMarket(
      key: _terasKey,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSubmitSearch: _submitSearch,
    );
  }

  /// Build optimized navigation item
  Widget _buildNavItem(IconData icon, String label, bool isSelected) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color unselectedFill =
        dark ? Colors.white : const Color.fromARGB(255, 58, 58, 58);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: isSelected ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: isSelected
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.orange, Colors.pink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Icon(icon, size: 22, color: Colors.white),
                )
              : Icon(icon, size: 22, color: unselectedFill),
        ),
        const SizedBox(height: 2),
        isSelected
            ? ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.orange, Colors.pink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: unselectedFill,
                  fontSize: 10,
                ),
              ),
      ],
    );
  }

  /// Build optimized dynamic filter view
  Widget _buildDynamicFilterView(DynamicFilter dynamicFilter) {
    // ✅ OPTIMIZATION: Use Selector to only rebuild when products for THIS filter change
    return Selector<SpecialFilterProviderMarket, List<ProductSummary>>(
      selector: (_, prov) => prov.getProducts(dynamicFilter.id),
      builder: (context, products, _) {
        final l10n = AppLocalizations.of(context);
        final prov =
            Provider.of<SpecialFilterProviderMarket>(context, listen: false);
        final boosted = products.where((p) => p.isBoosted).toList();
        final normal = products.where((p) => !p.isBoosted).toList();

        return RefreshIndicator(
          onRefresh: () => _throttledRefresh(
            () => prov.refreshProducts(
              dynamicFilter.id,
              dynamicFilter: dynamicFilter,
            ),
            filterType:
                dynamicFilter.id, // Pass filter type for cooldown tracking
          ),
          child: _buildDynamicFilterScrollView(
              dynamicFilter, prov, l10n, products, boosted, normal),
        );
      },
    );
  }

  /// Build dynamic filter scroll view
  Widget _buildDynamicFilterScrollView(
    DynamicFilter dynamicFilter,
    SpecialFilterProviderMarket prov,
    AppLocalizations l10n,
    List<ProductSummary> products,
    List<ProductSummary> boosted,
    List<ProductSummary> normal,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (_shouldLoadMore(notif, prov, dynamicFilter.id)) {
          _scheduleInfiniteScroll('dyn:${dynamicFilter.id}', () {
            prov.fetchMoreProducts(dynamicFilter.id,
                dynamicFilter: dynamicFilter);
          });
        }
        return false;
      },
      child: SafeArea(
        top: false,
        bottom: true,
        child: CustomScrollView(
          key: PageStorageKey(dynamicFilter.id),
          slivers: _buildDynamicFilterSlivers(
              dynamicFilter, prov, l10n, products, normal, boosted),
        ),
      ),
    );
  }

  /// Build dynamic filter slivers
  List<Widget> _buildDynamicFilterSlivers(
    DynamicFilter dynamicFilter,
    SpecialFilterProviderMarket prov,
    AppLocalizations l10n,
    List<ProductSummary> products,
    List<ProductSummary> normal,
    List<ProductSummary> boosted,
  ) {
    // ✅ OPTIMIZATION: Cache MediaQuery
    final mediaQuery = MediaQuery.of(context);
    final slivers = <Widget>[];

    // Filter description
    if (dynamicFilter.description?.isNotEmpty == true) {
      slivers.add(_buildFilterDescription(dynamicFilter));
    }

    // View all button and product count
    slivers.add(_buildViewAllSection(dynamicFilter, l10n, products.length));

    // Products list
    slivers.add(SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      sliver: ProductListSliver(
        products: normal,
        boostedProducts: boosted,
        hasMore: prov.hasMore(dynamicFilter.id),
        screenName: 'dynamic_filter_view',
        isLoadingMore: prov.isLoadingMore(dynamicFilter.id),
      ),
    ));

    // Bottom padding
    slivers.add(SliverToBoxAdapter(
      child: SizedBox(
        height: 20 + mediaQuery.padding.bottom,
      ),
    ));

    return slivers;
  }

  /// Build filter description widget
  Widget _buildFilterDescription(DynamicFilter dynamicFilter) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: _parseColor(dynamicFilter.color ?? '#FF6B35').withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color:
                _parseColor(dynamicFilter.color ?? '#FF6B35').withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            if (dynamicFilter.icon?.isNotEmpty == true) ...[
              Text(
                dynamicFilter.icon!,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                dynamicFilter.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build view all section
  Widget _buildViewAllSection(
      DynamicFilter dynamicFilter, AppLocalizations l10n, int productCount) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$productCount ${l10n.products ?? 'products'}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[400]
                    : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            _buildViewAllButton(dynamicFilter, l10n),
          ],
        ),
      ),
    );
  }

  /// Build view all button
  Widget _buildViewAllButton(
      DynamicFilter dynamicFilter, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MarketScreenDynamicFiltersScreen(
              dynamicFilter: dynamicFilter,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: _parseColor(dynamicFilter.color ?? '#FF6B35').withOpacity(0.1),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color:
                _parseColor(dynamicFilter.color ?? '#FF6B35').withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.viewAll,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _parseColor(dynamicFilter.color ?? '#FF6B35'),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: _parseColor(dynamicFilter.color ?? '#FF6B35'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build optimized filter view
  Widget _buildFilterView(String filterType) {
    // ✅ OPTIMIZATION: Use Selector to only rebuild when this specific filter's data changes
    final isCategory = [
      'Women',
      'Men',
      'Electronics',
      'Home & Furniture',
      'Mother & Child'
    ].contains(filterType);

    if (isCategory) {
      return Selector<SpecialFilterProviderMarket, List<Map<String, dynamic>>>(
        selector: (_, prov) => prov.getSubcategoryProducts(filterType),
        builder: (context, subcategories, _) {
          final l10n = AppLocalizations.of(context);
          final prov =
              Provider.of<SpecialFilterProviderMarket>(context, listen: false);
          return _buildCategoryFilterView(filterType, prov, l10n);
        },
      );
    } else {
      return Selector<SpecialFilterProviderMarket, List<ProductSummary>>(
        selector: (_, prov) => prov.getProducts(filterType),
        builder: (context, products, _) {
          final l10n = AppLocalizations.of(context);
          final prov =
              Provider.of<SpecialFilterProviderMarket>(context, listen: false);
          return _buildGenericFilterView(filterType, prov, l10n);
        },
      );
    }
  }

  /// Build category filter view
  Widget _buildCategoryFilterView(
    String filterType,
    SpecialFilterProviderMarket prov,
    AppLocalizations l10n,
  ) {
    final subcategories = prov.getSubcategoryProducts(filterType);

    return RefreshIndicator(
      onRefresh: () => _throttledRefresh(
        () => prov.refreshProducts(filterType),
        filterType: filterType,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (_shouldLoadMore(notif, prov, filterType)) {
            _scheduleInfiniteScroll('cat:$filterType', () {
              prov.fetchMoreProducts(filterType);
            });
          }
          return false;
        },
        child: SafeArea(
          top: false,
          bottom: true,
          child: CustomScrollView(
            key: PageStorageKey(filterType),
            slivers:
                _buildCategorySlivers(subcategories, filterType, l10n, prov),
          ),
        ),
      ),
    );
  }

  /// Build category slivers
  List<Widget> _buildCategorySlivers(
    List<Map<String, dynamic>> subcategories,
    String filterType,
    AppLocalizations l10n,
    SpecialFilterProviderMarket prov,
  ) {
    // ✅ OPTIMIZATION: Cache MediaQuery
    final mediaQuery = MediaQuery.of(context);
    final slivers = <Widget>[];

    // Show shimmer when initially loading (no products yet)
    if (subcategories.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ValueListenableBuilder<bool>(
            valueListenable: prov.getFilterLoadingListenable(filterType),
            builder: (context, isLoading, _) {
              if (isLoading) {
                return _buildShimmerPlaceholder();
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ];
    }

    slivers.add(SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < subcategories.length) {
            return _buildSubcategorySection(
                subcategories[index], filterType, l10n);
          }
          return prov.isLoadingMore(filterType)
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                )
              : const SizedBox.shrink();
        },
        childCount:
            subcategories.length + (prov.isLoadingMore(filterType) ? 1 : 0),
      ),
    ));

    // Bottom padding
    slivers.add(SliverToBoxAdapter(
      child: SizedBox(
        height: 20 + mediaQuery.padding.bottom,
      ),
    ));

    return slivers;
  }

  /// Build lightweight shimmer placeholder for loading state
  Widget _buildShimmerPlaceholder() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 30, 28, 44)
        : Colors.grey[300]!;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 33, 31, 49)
        : Colors.grey[100]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(3, (sectionIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header shimmer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      height: 20,
                      width: 150,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Product shimmer (full-width, like dynamic_market)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Build subcategory section
  Widget _buildSubcategorySection(
    Map<String, dynamic> subcategory,
    String filterType,
    AppLocalizations l10n,
  ) {
    final products = subcategory['products'] as List<ProductSummary>;
    final subcategoryName = subcategory['subcategoryName'] as String;

    // For Women/Men filters, the subcategoryName is actually a category name
    // For Electronics filter, the subcategoryName is a subcategory name
    String localizedName;

    if (['Women', 'Men'].contains(filterType)) {
      // For gender filters, subcategoryName contains category names like "Clothing & Fashion"
      localizedName =
          AllInOneCategoryData.localizeCategoryKey(subcategoryName, l10n);
    } else {
      // For category filters like Electronics, subcategoryName contains actual subcategory names
      localizedName = AllInOneCategoryData.localizeSubcategoryKey(
        filterType, // This is the category (like "Electronics")
        subcategoryName, // This is the subcategory
        l10n,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubcategoryHeader(localizedName, l10n, subcategory, filterType),
          const SizedBox(height: 12),
          _buildSubcategoryProductList(products),
        ],
      ),
    );
  }

  /// Build subcategory header
  Widget _buildSubcategoryHeader(
    String localizedName,
    AppLocalizations l10n,
    Map<String, dynamic> subcategory,
    String filterType,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            localizedName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          GestureDetector(
            onTap: () {
              if (['Women', 'Men'].contains(filterType)) {
                // For Women/Men: pass the actual category, but empty subcategoryId to get all products
                context.push(
                  '/subcategory_products',
                  extra: {
                    'category': subcategory[
                        'subcategoryId'], // The actual category like "Accessories"
                    'subcategoryId':
                        '', // ← CHANGED: Empty string to skip subcategory filter
                    'subcategoryName': localizedName,
                    'gender':
                        filterType, // Pass the gender for additional filtering if needed
                  },
                );
              } else {
                // For Electronics and other category filters (unchanged)
                context.push(
                  '/subcategory_products',
                  extra: {
                    'category': filterType,
                    'subcategoryId': subcategory['subcategoryId'],
                    'subcategoryName': localizedName,
                  },
                );
              }
            },
            child: Text(
              l10n.viewAll,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build subcategory product list
  Widget _buildSubcategoryProductList(List<ProductSummary> products) {
    // ✅ OPTIMIZATION: Cache MediaQuery
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Detect tablet
    final bool isTablet = screenWidth >= 600;

    // Tablets: wider cards, shorter height
    final double cardWidth = isTablet ? 185.0 : 160.0;
    final double portraitImageHeight = isTablet
        ? screenHeight * 0.24
        : screenHeight * 0.33; // Increased for taller images

    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          bottom: mediaQuery.padding.bottom + 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final product in products)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: cardWidth,
                  child: ProductCard(
                    product: product,
                    portraitImageHeight: portraitImageHeight,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build generic filter view
  Widget _buildGenericFilterView(
    String filterType,
    SpecialFilterProviderMarket prov,
    AppLocalizations l10n,
  ) {
    final products = prov.getProducts(filterType);
    final boosted = products.where((p) => p.isBoosted).toList();
    final normal = products.where((p) => !p.isBoosted).toList();

    return RefreshIndicator(
      onRefresh: () => _throttledRefresh(
        () => prov.refreshProducts(filterType),
        filterType: filterType,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (_shouldLoadMore(notif, prov, filterType)) {
            _scheduleInfiniteScroll('gen:$filterType', () {
              prov.fetchMoreProducts(filterType);
            });
          }
          return false;
        },
        child: SafeArea(
          top: false,
          bottom: true,
          child: CustomScrollView(
            key: PageStorageKey(filterType),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                sliver: ProductListSliver(
                  products: normal,
                  boostedProducts: boosted,
                  hasMore: prov.hasMore(filterType),
                  screenName: 'generic_filter_view',
                  isLoadingMore: prov.isLoadingMore(filterType),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 20 + MediaQuery.of(context).padding.bottom,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build search delegate area
  Widget _buildSearchDelegateArea(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final marketProv = Provider.of<MarketProvider>(context, listen: false);
    final historyProv =
        Provider.of<SearchHistoryProvider>(context, listen: false);
    final searchProv = Provider.of<SearchProvider>(context, listen: false);

    final delegate = MarketSearchDelegate(
      marketProv: marketProv,
      historyProv: historyProv,
      searchProv: searchProv,
      l10n: l10n,
    );
    delegate.query = _searchController.text;
    return delegate.buildSuggestions(context);
  }

  /// Lifecycle methods - optimized
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // ✅ NEW: Trigger cleanup when app goes to background
    if (state == AppLifecycleState.paused) {
      _performCacheCleanup();
    }

    // Existing search resume logic
    if (state == AppLifecycleState.resumed && _isSearching) {
      final term = _searchController.text.trim();
      if (term.isNotEmpty) {
        try {
          final searchProv =
              Provider.of<SearchProvider>(context, listen: false);
          searchProv.search(term, l10n: AppLocalizations.of(context));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Error resuming search: $e');
          }
        }
      }
    }
  }

  /// Batch multiple setState calls into a single frame to prevent cascade rebuilds
  void _batchedSetState(VoidCallback fn) {
    if (_isBatchUpdating) {
      // Already in a batch, just track pending updates
      _pendingUpdates++;
      fn();
      return;
    }

    _isBatchUpdating = true;
    _pendingUpdates = 1;
    fn();

    // Consolidate all updates into a single setState after the current event loop
    scheduleMicrotask(() {
      if (!mounted || !_isBatchUpdating) return;

      setState(() {
        // All state changes have been applied via fn() calls
        // This setState just triggers the single consolidated rebuild
      });

      _isBatchUpdating = false;
      _pendingUpdates = 0;
    });
  }

  @override
  void didPopNext() {
    super.didPopNext();

    // Only unfocus keyboard immediately - this is lightweight
    FocusScope.of(context).unfocus();

    // Handle search mode immediately if needed
    if (_isSearching) {
      _setSearchMode(false);
      _specialFilterProvider?.setSpecialFilter('');

      final homeIndex = _filterTabIndices['Home'] ?? 0;
      if (_pageController.hasClients) _pageController.jumpToPage(homeIndex);
      if (_filterScrollController.hasClients) {
        _filterScrollController.jumpTo(0.0);
      }

      setState(() {
        _currentPage = homeIndex;
        _isRouteActive = true;
      });
      return;
    }

    // Defer animation resume to next frame to avoid jank during route transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isRouteActive = true);
    });
  }

  @override
  void didPush() {
    super.didPush();
    // Initial push - set immediately since there's no transition competing for resources
    _isRouteActive = true;
  }

  @override
  void didPushNext() {
    super.didPushNext();
    // Defer pause to next frame - low priority, doesn't need to block transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _isRouteActive = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Optimized disposal
  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('🗑️ MarketScreen: Starting disposal...');
    }

    // 1. Cancel all timers FIRST (including cleanup timer)
    _cleanupTimer?.cancel(); // ✅ NEW: Cancel periodic cleanup
    _searchDebounce.cancel();
    _pageDebounce.cancel();
    _listenerDebounce.cancel();

    for (final timer in _scrollDebouncers.values) {
      timer.cancel();
    }
    _scrollDebouncers.clear();

    // 2. Remove listeners with safety checks
    if (_dynamicFilterAttached && _dynamicFilterListener != null) {
      try {
        _dynamicFilterProvider?.removeListener(_dynamicFilterListener!);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Error removing dynamic filter listener: $e');
        }
      }
      _dynamicFilterListener = null;
    }

    // 3. Clean up subscriptions
    _authSubscription?.cancel();
    _authSubscription = null;

    // 4. Unsubscribe from observers
    try {
      routeObserver.unsubscribe(this);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error unsubscribing from route observer: $e');
      }
    }

    WidgetsBinding.instance.removeObserver(this);


    // 6. Clean up provider notifiers
    if (_specialFilterProvider != null) {
      try {
        _specialFilterProvider!.cleanupOldFilterNotifiers([]);

        final staticFilters = [
          'Home',
          'Women',
          'Men',
          'Electronics',
          'Home & Furniture',
          'Mother & Child'
        ];

        for (final filter in staticFilters) {
          _specialFilterProvider!.removeFilterNotifiers(filter);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Error cleaning provider notifiers: $e');
        }
      }
    }

    // 7. Dispose controllers (with safety checks)
    try {
      _filterScrollController.dispose();
    } catch (e) {
      if (kDebugMode)
        debugPrint('⚠️ Error disposing _filterScrollController: $e');
    }

    try {
      _pageController.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error disposing _pageController: $e');
    }

    try {
      _scrollController.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error disposing _scrollController: $e');
    }

    try {
      _searchFocusNode.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error disposing _searchFocusNode: $e');
    }

    try {
      _searchController.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error disposing _searchController: $e');
    }

    // 8. Dispose ValueNotifiers (with safety checks)
    try {
      _adsBannerBgColor.dispose();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error disposing _adsBannerBgColor: $e');
      }
    }

    // 9. Clear collections
    _filterViews.clear();
    _filterTabIndices.clear();
    _builtFilterIndices.clear();
    _filterLastRefresh.clear();

    if (kDebugMode) {
      debugPrint('✅ MarketScreen: Disposal complete');
    }
    super.dispose();
  }

  /// Optimized build method
  @override
  Widget build(BuildContext context) {
    // ✅ OPTIMIZATION: Cache MediaQuery and Theme
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final onHomeFilter = _shouldUseDynamicColor();
    final iconWhite = isDarkMode || onHomeFilter;

    final bottomPad = mediaQuery.padding.bottom;
    final bottomNav = _buildBottomNavigation(isDarkMode, bottomPad, l10n);

    // ✅ REACTIVE PATTERN: Listen to banner color changes only when needed.
    // The ValueListenableBuilder only rebuilds AppBar when banner color changes
    // AND we're in the correct context (Market tab + Home filter).
    return _buildUnifiedScaffold(
      _adsBannerBgColor,
      onHomeFilter,
      iconWhite,
      bottomNav,
      isDarkMode,
    );
  }

  /// Build bottom navigation
  Widget _buildBottomNavigation(
      bool dark, double bottomPad, AppLocalizations l10n) {
    return Container(
      height: 55 + bottomPad,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 2,
          )
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: Colors.transparent,
        unselectedItemColor: dark ? Colors.white : Colors.black,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: [
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.home, l10n.home, _selectedIndex == 0),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.grid, l10n.categories, _selectedIndex == 1),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.heart, l10n.favorites, _selectedIndex == 2),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.shoppingCart, l10n.cart, _selectedIndex == 3),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.sidebar, 'Vitrin', _selectedIndex == 4),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildNavItem(
                FeatherIcons.user, l10n.profile, _selectedIndex == 5),
            label: '',
          ),
        ],
      ),
    );
  }

  /// Unified scaffold — PageView stays mounted via Stack overlay approach.
  /// Search delegate is layered on top when active, rather than replacing the body.
  Widget _buildUnifiedScaffold(
    ValueNotifier<Color> bannerColorNotifier,
    bool onHomeFilter,
    bool iconWhite,
    Widget bottomNav,
    bool isDarkMode,
  ) {
    final fallbackColor = isDarkMode ? const Color(0xFF1C1A29) : Colors.white;

    // AppBar color: use fallback when searching, otherwise use effective color
    final effectiveColorNotifier =
        (_isSearching || !onHomeFilter)
            ? ValueNotifier<Color>(fallbackColor)
            : bannerColorNotifier;

    // Show AppBar when searching OR on tabs that need it
    final showAppBar = _isSearching ||
        _selectedIndex == 0 ||
        _selectedIndex == 1 ||
        _selectedIndex == 4 ||
        _selectedIndex == 6;

    return Scaffold(
      appBar: showAppBar
          ? _buildAppBar(
              effectiveColorNotifier,
              _isSearching ? false : onHomeFilter,
              _isSearching ? false : iconWhite,
              isSearching: _isSearching,
              onSearchStateChanged: _setSearchMode,
            )
          : null,
      body: Stack(
        children: [
          // Bottom layer: tab content (always mounted — PageView stays alive)
          _buildBodyContent(),

          // Top layer: search overlay (instant mount/unmount)
          if (_isSearching)
            Positioned.fill(
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider<SearchProvider>(
                    create: (_) => SearchProvider(),
                  ),
                  ChangeNotifierProvider<SearchHistoryProvider>(
                    create: (_) => SearchHistoryProvider(),
                  ),
                ],
                child: Builder(
                  builder: (ctx) => Material(
                    color: isDarkMode
                        ? const Color(0xFF1C1A29)
                        : Colors.white,
                    // ValueListenableBuilder rebuilds on every keystroke,
                    // ensuring the delegate gets the latest query text
                    // and talks to the correct (overlay) SearchProvider.
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (_, __, ___) =>
                          _buildSearchDelegateArea(ctx),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: bottomNav,
    );
  }

  /// Build app bar
  PreferredSizeWidget _buildAppBar(
    ValueNotifier<Color> appBarBgNotifier,
    bool onHomeFilter,
    bool iconWhite, {
    required bool isSearching,
    required Function(bool) onSearchStateChanged,
  }) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: MarketAppBar(
        isDefaultView:
            isSearching ? false : onHomeFilter, // ← was: onHomeFilter
        backgroundColorNotifier: appBarBgNotifier,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onSubmitSearch: _submitSearch,
        useWhiteColors: isSearching ? false : iconWhite,
        isSearching: isSearching,
        onSearchStateChanged: onSearchStateChanged,
      ),
    );
  }

  void navigateToCategoriesTeras() {
    if (kDebugMode) {
      debugPrint('🔄 Navigating to CategoriesTeras');
    }

    if (_isSearching) {
      _setSearchMode(false);
      setState(() {
        _selectedIndex = 1;
        _showTerasCategories = true;
      });
      return;
    }
    setState(() {
      _selectedIndex = 1; // Go to categories tab
      _showTerasCategories = true; // Show teras version
    });
  }

  /// Build body content based on selected index
  void navigateToCategories() {
    // ✅ REACTIVE: setState triggers rebuild with correct color
    setState(() {
      _selectedIndex = 1;
      _showTerasCategories = false; // Show normal version
    });
  }

  Widget _buildBodyContent() {
    final validIndex = _selectedIndex.clamp(0, 5);

    switch (validIndex) {
      case 0:
        return _buildHomeScreenBody();
      case 1:
        return _buildCategoriesScreen();
      case 2:
        return const FavoritesScreen();
      case 3:
        return const MyCartScreen();
      case 4:
        return _buildTerasMarketScreenBody();
      case 5:
        return const ProfileScreen();
      default:
        return _buildHomeScreenBody();
    }
  }

  Widget _buildCategoriesScreen() {
    return _showTerasCategories
        ? const CategoriesTerasScreen()
        : const CategoriesScreen();
  }
}
