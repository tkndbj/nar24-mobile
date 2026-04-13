// lib/screens/food/restaurants_screen.dart
//
// Mirrors:  pages/restaurants/page.tsx  (server data fetch)
//        +  components/restaurants/RestaurantsPage.tsx  (UI)

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/foodData.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/food_address.dart';
import '../../models/restaurant.dart';
import '../../user_provider.dart';
import '../../utils/restaurant_utils.dart';
import '../../services/typesense_service_manager.dart';
import '../../services/restaurant_typesense_service.dart';
import '../../auth_service.dart';
import '../../widgets/login_modal.dart';
import '../../widgets/restaurants/food_location_picker.dart';
import '../../widgets/restaurants/restaurant_top_banner.dart';
import '../../utils/food_localization.dart';

// ============================================================================
// SCREEN
// ============================================================================

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  // ── Data ───────────────────────────────────────────────────────────────
  List<Restaurant> _restaurants = [];
  List<FacetValue> _cuisineFacets = [];

  // ── Filters / sort ─────────────────────────────────────────────────────
  String? _selectedCuisine;
  String? _selectedFoodType;
  RestaurantSortOption _sortOption = RestaurantSortOption.defaultSort;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Pagination ─────────────────────────────────────────────────────────
  static const _kPageSize = 30;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // ── Loading ────────────────────────────────────────────────────────────
  bool _isLoadingData = true;
  bool _isSearching = false;

  // ── Debounce ───────────────────────────────────────────────────────────
  Timer? _searchDebounce;

  // ── Auto-show picker guard ────────────────────────────────────────────
  bool _hasShownPicker = false;

  // ── Track food address for re-fetching on change ────────────────────
  String? _lastDeliveryCity;

  // ── Scroll controller for infinite scrolling ──────────────────────────
  final _scrollController = ScrollController();

  RestaurantTypesenseService get _typesense =>
      TypeSenseServiceManager.instance.restaurantService;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-show food location picker if authenticated user has no foodAddress
      if (!_hasShownPicker) {
        final userProvider = context.read<UserProvider>();
        if (userProvider.user != null) {
          final foodAddress = userProvider.profileData?['foodAddress'];
          if (foodAddress == null) {
            _hasShownPicker = true;
            showFoodLocationPicker(context, isDismissible: true);
          }
        }
      }

      // Try cache first, fall back to Typesense
_fetchFromCache();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final raw = context.read<UserProvider>().profileData?['foodAddress'];
    final addr = raw is Map<String, dynamic> ? FoodAddress.fromMap(raw) : null;
    final city = (addr == null || addr.city.isEmpty) ? null : addr.city;

    if (city != _lastDeliveryCity) {
      _lastDeliveryCity = city;

     if (!_isLoadingData) {
  if (_selectedCuisine != null) {
    setState(() => _selectedCuisine = null);
  }
  _fetchFromCache();
}
    }
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Trigger load when within 200px of the bottom
    if (currentScroll >= maxScroll - 200) {
      _loadNextPage();
    }
  }

  // ============================================================================
  // DATA FETCHING
  // ============================================================================

  /// Tries to load the default view from the pre-computed Firestore cache.
/// Falls back to Typesense if the cache doc doesn't exist or on error.
 Future<void> _fetchFromCache() async {
    final regions = _deliveryFilterRegions();
    if (regions == null || regions.isEmpty) {
      // No address → can't determine region → use Typesense directly
      await Future.wait([_fetchRestaurants(), _fetchFacets()]);
      return;
    }
 
    final region = regions.first;
 
    try {
      final doc = await FirebaseFirestore.instance
          .doc('food_cache/region_$region')
          .get(const GetOptions(source: Source.serverAndCache));
 
      if (!doc.exists || doc.data() == null) {
        debugPrint('[RestaurantsScreen] No cache for $region, falling back.');
        await Future.wait([_fetchRestaurants(), _fetchFacets()]);
        return;
      }
 
      final data = doc.data()!;
 
      // ── Parse restaurants ────────────────────────────────────────────
      final rawList = (data['restaurants'] as List<dynamic>?) ?? [];
      final restaurants = rawList.map((r) {
        final map = Map<String, dynamic>.from(r as Map);
        return Restaurant.fromMap(map, id: map['id']?.toString() ?? '');
      }).toList();
 
      // ── Parse cuisine facets ─────────────────────────────────────────
      final rawCuisines = (data['cuisineFacets'] as List<dynamic>?) ?? [];
      final cuisines = rawCuisines
          .map((f) {
            final m = f as Map;
            return FacetValue(
              value: m['value']?.toString() ?? '',
              count: (m['count'] as num?)?.toInt() ?? 0,
            );
          })
          .where((fv) => fv.value.isNotEmpty && fv.count > 0)
          .toList();
 
      // ── Detect whether the cache has all restaurants ─────────────────
      // The CF writes `restaurantCount` as the true Typesense total.
      // If it exceeds what we cached (200 cap), allow pagination via
      // Typesense so the user can still reach the rest.
      final totalInRegion =
          (data['restaurantCount'] as num?)?.toInt() ?? restaurants.length;
      final cacheIsComplete = restaurants.length >= totalInRegion;

      // If the cache doesn't have all restaurants for this region,
      // fall back to Typesense entirely — mixing cache + Typesense
      // pagination with different page sizes causes duplicates.
      if (!cacheIsComplete) {
        debugPrint(
          '[RestaurantsScreen] Cache incomplete for $region '
          '(${restaurants.length}/$totalInRegion), falling back.',
        );
        await Future.wait([_fetchRestaurants(), _fetchFacets()]);
        return;
      }

      if (mounted) {
        setState(() {
          _restaurants = _openFirst(restaurants);
          _cuisineFacets = cuisines;
          _currentPage = 0;
          _hasMore = false;
          _isLoadingData = false;
        });
      } 
    } catch (e) {
      debugPrint('[RestaurantsScreen] Cache read failed: $e');
      await Future.wait([_fetchRestaurants(), _fetchFacets()]);
    }
  }

  /// Initial load via Typesense (with delivery-region filter).
  /// Resets pagination and fetches page 0.
  Future<void> _fetchRestaurants() async {
    try {
      final result = await _typesense.searchRestaurants(
        isActive: true,
        deliveryRegions: _deliveryFilterRegions(),
        hitsPerPage: _kPageSize,
        page: 0,
      );

      if (mounted) {
        setState(() {
          _restaurants = _openFirst(result.items);
          _currentPage = 0;
          _hasMore = result.page < result.nbPages - 1;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('[RestaurantsScreen] Fetch error: $e');
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  /// Loads the next page and appends results.
  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _currentPage + 1;

    try {
      final query = _searchQuery.trim();
      final result = await _typesense.searchRestaurants(
        query: query,
        cuisineTypes: _selectedCuisine != null ? [_selectedCuisine!] : null,
        foodType: _selectedFoodType != null ? [_selectedFoodType!] : null,
        isActive: true,
        sort: _sortOption,
        deliveryRegions: _deliveryFilterRegions(),
        hitsPerPage: _kPageSize,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          // Insert new open items before the closed section,
          // append new closed items at the end — avoids re-sorting
          // the entire list and prevents visible shifts.
          final firstClosedIdx =
              _restaurants.indexWhere((r) => !isRestaurantOpen(r));
          final insertAt =
              firstClosedIdx == -1 ? _restaurants.length : firstClosedIdx;

          final newOpen = <Restaurant>[];
          final newClosed = <Restaurant>[];
          for (final r in result.items) {
            (isRestaurantOpen(r) ? newOpen : newClosed).add(r);
          }

          _restaurants = [
            ..._restaurants.sublist(0, insertAt),
            ...newOpen,
            ..._restaurants.sublist(insertAt),
            ...newClosed,
          ];
          _currentPage = nextPage;
          _hasMore = nextPage < result.nbPages - 1;
        });
      }
    } catch (e) {
      debugPrint('[RestaurantsScreen] LoadMore error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Stable-partitions restaurants so open ones appear before closed ones,
  /// preserving the original Typesense sort order within each group.
  List<Restaurant> _openFirst(List<Restaurant> list) {
    final open = <Restaurant>[];
    final closed = <Restaurant>[];
    for (final r in list) {
      (isRestaurantOpen(r) ? open : closed).add(r);
    }
    return [...open, ...closed];
  }

  /// Returns [city, mainRegion] from the user's foodAddress for Typesense
  /// delivery-region filtering, or null if no address is set.
  /// Returns the user's city (subregion) from foodAddress for Typesense
  /// delivery-region filtering. Only the subregion matters — restaurants
  /// list specific subregions they deliver to, not entire main regions.
  List<String>? _deliveryFilterRegions() {
    final raw = context.read<UserProvider>().profileData?['foodAddress'];
    if (raw is! Map<String, dynamic>) return null;
    final addr = FoodAddress.fromMap(raw);
    if (addr.city.isEmpty) return null;
    return [addr.city];
  }

  /// Fetch cuisine facets from Typesense for the filter pills.
  /// Uses the same delivery-region filter as the restaurant list so facets
  /// only reflect cuisines the user can actually order from.
  Future<void> _fetchFacets() async {
    try {
      final facets = await _typesense.fetchRestaurantFacets(
        deliveryRegions: _deliveryFilterRegions(),
      );
      if (mounted) {
        setState(() => _cuisineFacets = facets.cuisineTypes ?? <FacetValue>[]);
      }
    } catch (e) {
      debugPrint('[RestaurantsScreen] Facets error: $e');
    }
  }

  // ── Search / filter ────────────────────────────────────────────────────

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_searchController.text != _searchQuery) {
        setState(() => _searchQuery = _searchController.text);
        _performSearch();
      }
    });
  }

  void _onCuisineChanged(String? cuisine) {
    setState(() => _selectedCuisine = cuisine);
    _performSearch();
  }

  void _onFoodTypeChanged(String? foodType) {
    setState(() => _selectedFoodType = foodType);
    _performSearch();
  }

  void _cycleSortOption() {
    const cycle = [
      RestaurantSortOption.defaultSort,
      RestaurantSortOption.ratingDesc,
      RestaurantSortOption.ratingAsc,
    ];
    final idx = cycle.indexOf(_sortOption);
    setState(() => _sortOption = cycle[(idx + 1) % cycle.length]);
    _performSearch();
  }

  /// Resets pagination and performs a fresh search with current filters.
  Future<void> _performSearch() async {
    setState(() => _isSearching = true);

    try {
      final query = _searchQuery.trim();
      final result = await _typesense.searchRestaurants(
        query: query,
        cuisineTypes: _selectedCuisine != null ? [_selectedCuisine!] : null,
        foodType: _selectedFoodType != null ? [_selectedFoodType!] : null,
        isActive: true,
        sort: _sortOption,
        deliveryRegions: _deliveryFilterRegions(),
        hitsPerPage: _kPageSize,
        page: 0,
      );

      if (mounted) {
        setState(() {
          _restaurants = _openFirst(result.items);
          _currentPage = 0;
          _hasMore = result.page < result.nbPages - 1;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('[RestaurantsScreen] Search error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _selectedCuisine != null ||
      _selectedFoodType != null ||
      _sortOption != RestaurantSortOption.defaultSort;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCuisine = null;
      _selectedFoodType = null;
      _sortOption = RestaurantSortOption.defaultSort;
    });
    _fetchFromCache();
  }

  // ── Min order price helper ─────────────────────────────────────────────
  int? _getMinOrderPrice(Restaurant r, FoodAddress? foodAddress) {
    if (foodAddress == null || r.minOrderPrices == null) return null;
    for (final e in r.minOrderPrices!) {
      if (e['subregion'] == foodAddress.city) {
        return (e['minOrderPrice'] as num?)?.toInt();
      }
    }
    return null;
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rawFoodAddress =
        context.watch<UserProvider>().profileData?['foodAddress'];
    final foodAddress = rawFoodAddress is Map<String, dynamic>
        ? FoodAddress.fromMap(rawFoodAddress)
        : null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        body: SafeArea(
          child: _isLoadingData
              ? _buildSkeleton(isDark)
              : RefreshIndicator(
                  onRefresh: () async {
                    await Future.wait([_fetchRestaurants(), _fetchFacets()]);
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // ── App bar ──────────────────────────────────────────
                      SliverAppBar(
                        title: Text(loc.restaurantsTitle),
                        floating: true,
                        snap: true,
                        backgroundColor: isDark
                            ? const Color(0xFF1C1A29)
                            : const Color(0xFFE5E7EB),
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        scrolledUnderElevation: 0,
                        leading: context.canPop()
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => context.pop(),
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => context.go('/'),
                              ),
                        automaticallyImplyLeading:
                            false, // prevent Flutter adding its own
                      ),

                      // ── Content ──────────────────────────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Banner
                              const RestaurantTopBanner(),
                              const SizedBox(height: 20),

                              // Title row
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          loc.restaurantsTitle,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          loc.discoverNearbyRestaurants,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: isDark
                                                      ? Colors.grey[400]
                                                      : Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Sort button
                                  _SortButton(
                                    sortOption: _sortOption,
                                    isDark: isDark,
                                    onTap: _cycleSortOption,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Address prompt banner
                              Builder(builder: (context) {
                                final userProvider =
                                    context.watch<UserProvider>();
                                final isLoggedIn = userProvider.user != null;
                                final hasFoodAddress =
                                    userProvider.profileData?['foodAddress'] !=
                                        null;
                                if (isLoggedIn && hasFoodAddress) {
                                  return const SizedBox.shrink();
                                }
                                final l10n = AppLocalizations.of(context);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GestureDetector(
                                    onTap: () {
                                      if (!isLoggedIn) {
                                        showCupertinoModalPopup(
                                          context: context,
                                          builder: (_) => LoginPromptModal(
                                            authService: AuthService(),
                                          ),
                                        );
                                      } else {
                                        showFoodLocationPicker(context);
                                      }
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.orange
                                                .withValues(alpha: 0.12)
                                            : Colors.white,
                                        borderRadius: isDark
                                            ? null
                                            : BorderRadius.circular(8),
                                        border: isDark
                                            ? null
                                            : Border.all(
                                                color: Colors.orange,
                                                width: 1,
                                              ),
                                        boxShadow: isDark
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.15),
                                                  spreadRadius: 0,
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.location_on_outlined,
                                            size: 18,
                                            color: isDark
                                                ? Colors.orange[300]
                                                : Colors.orange[700],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              isLoggedIn
                                                  ? l10n.setAddressBanner
                                                  : l10n.setAddressLoginBanner,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.orange[300]
                                                    : Colors.orange[800],
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                            color: isDark
                                                ? Colors.orange[300]
                                                : Colors.orange[700],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),

                              // Search bar
                              _SearchBar(
                                controller: _searchController,
                                isDark: isDark,
                                hint: loc.searchRestaurantsHint,
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),

                      // ── Cuisine pills + Food type icon row ──────────────────
                      SliverToBoxAdapter(
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color.fromARGB(255, 40, 38, 59)
                                : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                spreadRadius: 0,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              if (_cuisineFacets.isNotEmpty)
                                _CuisinePillRow(
                                  facets: _cuisineFacets,
                                  selected: _selectedCuisine,
                                  isDark: isDark,
                                  onSelect: _onCuisineChanged,
                                ),
                              _FoodTypeIconRow(
                                selected: _selectedFoodType,
                                isDark: isDark,
                                onSelect: _onFoodTypeChanged,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Current delivery address pill ────────────────────────
                      if (foodAddress != null)
                        SliverToBoxAdapter(
                          child: GestureDetector(
                            onTap: () => showFoodLocationPicker(context),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              margin: const EdgeInsets.only(top: 10),
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      foodAddress.displayLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── Restaurant list ────────────────────────────────────
                      if (_isSearching)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RestaurantCardSkeleton(isDark: isDark),
                            ),
                            childCount: 6,
                          ),
                        )
                      else if (_restaurants.isNotEmpty) ...[
                        SliverPadding(
                          padding: EdgeInsets.only(
                              top: foodAddress != null ? 4 : 10),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _RestaurantCard(
                                  restaurant: _restaurants[i],
                                  isDark: isDark,
                                  minOrderPrice: _getMinOrderPrice(
                                      _restaurants[i], foodAddress),
                                  onTap: () => context.push(
                                    '/restaurant-detail/${_restaurants[i].id}',
                                  ),
                                ),
                              ),
                              childCount: _restaurants.length,
                            ),
                          ),
                        ),
                        // Loading indicator at bottom
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.orange),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          // Bottom padding
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 24),
                          ),
                      ] else if (!_hasActiveFilters)
                        // No restaurants at all
                        SliverFillRemaining(
                          child: _EmptyState(
                            emoji: '🍽️',
                            title: loc.noRestaurantsYet,
                            subtitle: loc.checkBackSoonRestaurants,
                          ),
                        )
                      else
                        // Has filters active but no results
                        SliverFillRemaining(
                          child: _EmptyState(
                            emoji: '🔍',
                            title: loc.foodNoResults,
                            subtitle: loc.tryDifferentCuisine,
                            actionLabel: loc.clearFilters,
                            onAction: _clearFilters,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ── Loading skeleton ───────────────────────────────────────────────────
  Widget _buildSkeleton(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Banner placeholder
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RestaurantCardSkeleton(isDark: isDark),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CUISINE PILL ROW
// ============================================================================

class _CuisinePillRow extends StatelessWidget {
  final List<FacetValue> facets;
  final String? selected;
  final bool isDark;
  final ValueChanged<String?> onSelect;

  const _CuisinePillRow({
    required this.facets,
    required this.selected,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // "All" pill
          _CuisinePill(
            label: loc.allCuisines,
            isActive: selected == null,
            isDark: isDark,
            onTap: () => onSelect(null),
          ),
          ...facets.map(
            (f) => _CuisinePill(
              label: localizeCuisineType(f.value, loc),
              count: f.count,
              isActive: selected == f.value,
              isDark: isDark,
              onTap: () => onSelect(selected == f.value ? null : f.value),
            ),
          ),
        ],
      ),
    );
  }
}

class _CuisinePill extends StatelessWidget {
  final String label;
  final int? count;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _CuisinePill({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.orange
                : isDark
                    ? const Color(0xFF2D2B3F)
                    : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? Colors.orange
                  : isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey[300]!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : isDark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive
                        ? Colors.white70
                        : isDark
                            ? Colors.grey[500]
                            : Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// FOOD TYPE ICON ROW
// Mirrors FilterIcons component.
// Iterates FoodCategoryData.kCategories in order, loads icons from
// assets/images/foods/<filename> via FoodCategoryData.kCategoryIcons.
// Optional [categories] parameter limits which categories are shown
// (used on the restaurant detail screen to show only that restaurant's
// food categories — mirrors the `categories` prop on FilterIcons).
// ============================================================================

class _FoodTypeIconRow extends StatelessWidget {
  final String? selected;
  final bool isDark;
  final ValueChanged<String?> onSelect;

  /// When non-null, only categories in this list are shown.
  final List<String>? categories;

  const _FoodTypeIconRow({
    required this.selected,
    required this.isDark,
    required this.onSelect,
    this.categories,
  });

  @override
  Widget build(BuildContext context) {
    // Show all categories in kCategories order, or only the provided subset.
    final visible = FoodCategoryData.kCategories
        .where((cat) => categories == null || categories!.contains(cat))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: visible.length,
          itemBuilder: (_, i) {
            final category = visible[i];
            final iconFile = FoodCategoryData.kCategoryIcons[category];
            final isActive = selected == category;

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => onSelect(isActive ? null : category),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.orange
                            : isDark
                                ? const Color.fromARGB(255, 39, 36, 57)
                                : const Color.fromARGB(255, 243, 243, 243),
                        borderRadius: BorderRadius.circular(12),
                        border: isActive
                            ? Border.all(color: Colors.orange, width: 2)
                            : null,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: iconFile != null
                          ? Image.asset(
                              'assets/images/foods/$iconFile',
                              fit: BoxFit.contain,
                              color: isActive ? Colors.white : null,
                              colorBlendMode: isActive ? BlendMode.srcIn : null,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.restaurant,
                                size: 22,
                                color: isActive
                                    ? Colors.white
                                    : isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                              ),
                            )
                          : Icon(
                              Icons.restaurant,
                              size: 22,
                              color: isActive
                                  ? Colors.white
                                  : isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                            ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 56,
                      child: Text(
                        localizeCategory(
                            category, AppLocalizations.of(context)),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive
                              ? Colors.orange
                              : isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// RESTAURANT CARD
// ============================================================================

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final bool isDark;
  final int? minOrderPrice;
  final VoidCallback onTap;

  const _RestaurantCard({
    required this.restaurant,
    required this.isDark,
    required this.onTap,
    this.minOrderPrice,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isOpen = isRestaurantOpen(restaurant);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              spreadRadius: 0,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Profile image ──────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: restaurant.profileImageUrl != null
                    ? Image.network(
                        restaurant.profileImageUrl!,
                        fit: BoxFit.cover,
                        color: isOpen ? null : Colors.grey,
                        colorBlendMode: isOpen ? null : BlendMode.saturation,
                        errorBuilder: (_, __, ___) =>
                            _PlaceholderIcon(isDark: isDark),
                      )
                    : _PlaceholderIcon(isDark: isDark),
              ),
            ),
            const SizedBox(width: 12),

            // ── Info ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    restaurant.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Cuisine types
                  if (restaurant.cuisineTypes?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        localizeCuisines(restaurant.cuisineTypes!,
                            AppLocalizations.of(context)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Food type chips
                  if (restaurant.foodType?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: restaurant.foodType!
                            .map(
                              (ft) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2D2B3F)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  localizeFoodType(
                                      ft, AppLocalizations.of(context)),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // Rating row
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        if (restaurant.averageRating != null) ...[
                          _StarRating(rating: restaurant.averageRating!),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.averageRating!.toStringAsFixed(1),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[800],
                            ),
                          ),
                        ],
                        if (restaurant.reviewCount != null &&
                            restaurant.reviewCount! > 0)
                          Text(
                            ' (${restaurant.reviewCount})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Badges column ──────────────────────────────────────────
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isOpen)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      loc.closedLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (minOrderPrice != null) ...[
                  if (!isOpen) const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF00A36C).withOpacity(0.2)
                          : const Color(0xFF00A36C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppLocalizations.of(context)
                          .minOrderBadge(minOrderPrice.toString()),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF00A36C),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _PlaceholderIcon extends StatelessWidget {
  final bool isDark;

  const _PlaceholderIcon({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[100],
      alignment: Alignment.center,
      child: const Text('🍽️', style: TextStyle(fontSize: 24)),
    );
  }
}

class _StarRating extends StatelessWidget {
  final double rating;

  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final fill = (rating - i).clamp(0.0, 1.0);
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.grey),
              if (fill > 0)
                ClipRect(
                  clipper: _FractionClipper(fill),
                  child: const Icon(Icons.star_rounded,
                      size: 14, color: Colors.amber),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  final double fraction;

  _FractionClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper old) => old.fraction != fraction;
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String hint;

  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        filled: true,
        fillColor: isDark ? const Color(0xFF2D2B3F) : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final RestaurantSortOption sortOption;
  final bool isDark;
  final VoidCallback onTap;

  const _SortButton({
    required this.sortOption,
    required this.isDark,
    required this.onTap,
  });

  String _label(BuildContext context) {
    final loc = AppLocalizations.of(context);
    switch (sortOption) {
      case RestaurantSortOption.ratingDesc:
        return loc.sortHighRating;
      case RestaurantSortOption.ratingAsc:
        return loc.sortLowRating;
      default:
        return loc.sortLabel;
    }
  }

  bool get _isActive => sortOption != RestaurantSortOption.defaultSort;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isActive
              ? Colors.orange
              : isDark
                  ? const Color(0xFF2D2B3F)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isActive
                ? Colors.orange
                : isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 16,
              color: _isActive
                  ? Colors.white
                  : isDark
                      ? Colors.grey[300]
                      : Colors.grey[700],
            ),
            const SizedBox(width: 4),
            Text(
              _label(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _isActive
                    ? Colors.white
                    : isDark
                        ? Colors.grey[300]
                        : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantCardSkeleton extends StatelessWidget {
  final bool isDark;

  const _RestaurantCardSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2D2B3F) : Colors.grey[200]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 140, color: bg),
                const SizedBox(height: 6),
                Container(height: 12, width: 100, color: bg),
                const SizedBox(height: 6),
                Container(height: 12, width: 120, color: bg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
