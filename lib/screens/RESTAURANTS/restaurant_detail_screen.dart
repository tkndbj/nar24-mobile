// lib/screens/food/restaurant_detail_screen.dart
//
// Mirrors:
//   app/restaurantdetail/[id]/page.tsx  →  _RestaurantDetailScreenState (data fetch)
//   components/restaurants/RestaurantDetail.tsx  →  _RestaurantDetailBody (UI)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../auth_service.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/login_modal.dart';
import '../../widgets/restaurants/food_location_picker.dart';
import '../../widgets/restaurants/reviews.dart';
import '../../constants/foodData.dart';
import '../../models/food_address.dart';
import '../../models/restaurant.dart';
import '../../models/food.dart';
import '../../providers/food_cart_provider.dart';
import '../../user_provider.dart';
import '../../utils/restaurant_utils.dart';
import '../../utils/food_localization.dart';
import '../../services/typesense_service_manager.dart';
import '../../services/restaurant_typesense_service.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final String restaurantId;
  const RestaurantDetailScreen({required this.restaurantId, super.key});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  Restaurant? _restaurant;
  List<Food> _foods = [];
  bool _loading = true;

  /// Whether the user was unauthenticated when they entered this screen.
  /// Used to detect fresh logins that should redirect to /restaurants.
  final bool _wasUnauthenticated = FirebaseAuth.instance.currentUser == null;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _fetchData();

    // If the user was unauthenticated when entering this screen, listen
    // for auth changes. When they log in (e.g. via the login modal),
    // redirect to /restaurants so the list is re-fetched with proper
    // delivery-region filtering and the food address picker is shown.
    if (_wasUnauthenticated) {
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null && mounted) {
          final nav = Navigator.of(context, rootNavigator: true);

          // Dismiss any open modals (e.g. login prompt) and wait for
          // the dismiss animation to complete before navigating.
          if (nav.canPop()) {
            nav.pop();
            await Future.delayed(const Duration(milliseconds: 350));
          }

          if (mounted) context.go('/restaurants');
        }
      });
    }
  }

  /// Mirrors fetchData in RestaurantDetailPage — Promise.all parallel fetch.
  Future<void> _fetchData() async {
    if (widget.restaurantId.isEmpty) return;

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .get(),
        FirebaseFirestore.instance
            .collection('foods')
            .where('restaurantId', isEqualTo: widget.restaurantId)
            .where('isAvailable', isEqualTo: true)
            .get(),
      ]);

      final restaurantSnap =
          results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final foodsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

      Restaurant? restaurant;
      if (restaurantSnap.exists) {
        final d = restaurantSnap.data()!;
        restaurant = Restaurant.fromMap(d, id: restaurantSnap.id);
      }

      final foodList = <Food>[];
      for (final docSnap in foodsSnap.docs) {
        final d = docSnap.data();
        if (d['name'] == null) continue;
        foodList.add(Food.fromMap(d, id: docSnap.id));
      }

      if (mounted) {
        setState(() {
          _restaurant = restaurant;
          _foods = foodList;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[RestaurantDetail] Fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _LoadingSkeleton(
          isDark: Theme.of(context).brightness == Brightness.dark);
    }

    return _RestaurantDetailBody(
      restaurant: _restaurant,
      foods: _foods,
    );
  }
}

// =============================================================================
// BODY
// Mirrors RestaurantDetail component
// =============================================================================

typedef _ActiveTab = String; // 'menu' | 'reviews' | 'info'

class _RestaurantDetailBody extends StatefulWidget {
  final Restaurant? restaurant;
  final List<Food> foods;

  const _RestaurantDetailBody({
    required this.restaurant,
    required this.foods,
  });

  @override
  State<_RestaurantDetailBody> createState() => _RestaurantDetailBodyState();
}

class _RestaurantDetailBodyState extends State<_RestaurantDetailBody> {
  // ── Tab — mirrors activeTab state ─────────────────────────────────────────
  _ActiveTab _activeTab = 'menu';

  // ── Search / filter — mirrors searchQuery, selectedIconCategory ───────────
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedIconCategory;

  // ── Restaurant food categories from Typesense facets ─────────────────────
  List<String> _restaurantFoodCategories = [];

  // ── Typesense results (null = use prop data) ──────────────────────────────
  List<Food>? _typesenseResults;
  Timer? _searchDebounce;

  // ── Conflict dialog state — mirrors pendingConflict ───────────────────────
  _PendingConflict? _pendingConflict;

  RestaurantTypesenseService get _typesense =>
      TypeSenseServiceManager.instance.restaurantService;

  // ── Derived (all mirrors useMemo) ─────────────────────────────────────────

  /// Mirrors cartQuantityMap — map from originalFoodId → total quantity
  Map<String, int> _cartQuantityMap(List<FoodCartItem> items) {
    final map = <String, int>{};
    for (final item in items) {
      map[item.originalFoodId] =
          (map[item.originalFoodId] ?? 0) + item.quantity;
    }
    return map;
  }

  /// Mirrors filteredFoods memo
  List<Food> _filteredFoods() {
    if (_typesenseResults != null) return _typesenseResults!;
    if (_selectedIconCategory != null) {
      return widget.foods
          .where((f) => f.foodCategory == _selectedIconCategory)
          .toList();
    }
    return widget.foods;
  }

  /// Mirrors hasActiveFilters memo
  bool get _hasActiveFilters =>
      _selectedIconCategory != null || _searchQuery.trim().isNotEmpty;

  /// Mirrors groupedFoods memo.
  /// Iterates FoodCategoryData.kCategories (same order as kCategories.forEach({ key }) in TS).
  /// Returns null when hasActiveFilters (flat list instead).
  Map<String, List<Food>>? _groupedFoods() {
    if (_hasActiveFilters) return null;
    final map = <String, List<Food>>{};
    for (final key in FoodCategoryData.kCategories) {
      final items = widget.foods.where((f) => f.foodCategory == key).toList();
      if (items.isNotEmpty) map[key] = items;
    }
    return map.isEmpty ? null : map;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.restaurant != null) _fetchFoodCategories();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  /// Mirrors the useEffect that calls fetchFoodFacets({ restaurantId }).
  Future<void> _fetchFoodCategories() async {
    try {
      final facets =
          await _typesense.fetchFoodFacets(restaurantId: widget.restaurant!.id);
      if (mounted && (facets.foodCategory?.isNotEmpty ?? false)) {
        setState(() {
          _restaurantFoodCategories =
              facets.foodCategory!.map((f) => f.value).toList();
        });
      }
    } catch (e) {
      debugPrint('[RestaurantDetail] Facets error: $e');
    }
  }

  // ── Search — mirrors the debouncedSearchFoods useEffect ──────────────────

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_searchController.text == _searchQuery) return;
      setState(() => _searchQuery = _searchController.text);
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchQuery.trim();

    // No text search — clear Typesense results, use prop data (client-side filter)
    if (query.isEmpty) {
      setState(() => _typesenseResults = null);
      return;
    }

    try {
      final result = await _typesense.debouncedSearchFoods(
        query: query,
        restaurantId: widget.restaurant?.id,
        foodCategory:
            _selectedIconCategory != null ? [_selectedIconCategory!] : null,
        hitsPerPage: 100,
      );
      if (mounted) setState(() => _typesenseResults = result.items);
    } catch (e) {
      debugPrint('[RestaurantDetail] Search error: $e');
    }
  }

  // ── Cart actions ──────────────────────────────────────────────────────────

  /// Mirrors handleRemoveFromCart — removes ALL cart items whose originalFoodId === foodId
  Future<void> _handleRemoveFromCart(
      String foodId, List<FoodCartItem> cartItems) async {
    final cart = context.read<FoodCartProvider>();
    final matching =
        cartItems.where((i) => i.originalFoodId == foodId).toList();
    for (final item in matching) {
      await cart.removeItem(item.foodId);
    }
  }

  // ── Conflict dialog ───────────────────────────────────────────────────────

  /// Mirrors handleConflict — stores pending conflict and shows dialog
  void _handleConflict(_PendingConflict pending) {
    setState(() => _pendingConflict = pending);
    _showConflictDialog(pending);
  }

  void _showConflictDialog(_PendingConflict pending) {
    final cart = context.read<FoodCartProvider>();

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestaurantConflictDialog(
        currentRestaurantName: cart.currentRestaurant?.name ?? '',
        newRestaurantName: pending.restaurant.name,
        onReplace: () async {
          Navigator.of(context).pop();
          setState(() => _pendingConflict = null);

          if (pending.onAfterReplace != null) {
            // Pre-extras conflict: clear cart, then open extras sheet
            await cart.clearCart();
            pending.onAfterReplace!();
          } else {
            // Post-extras conflict: clear cart and add item directly
            await cart.clearAndAddFromNewRestaurant(
              foodId: pending.food.id,
              foodName: pending.food.name,
              foodDescription: pending.food.description ?? '',
              price: pending.food.price,
              imageUrl: pending.food.imageUrl ?? '',
              foodCategory: pending.food.foodCategory,
              foodType: pending.food.foodType,
              preparationTime: pending.food.preparationTime,
              restaurant: pending.restaurant,
              quantity: pending.quantity,
              extras: pending.extras,
              specialNotes: pending.specialNotes,
            );
          }
        },
        onCancel: () {
          Navigator.of(context).pop();
          setState(() => _pendingConflict = null);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final restaurant = widget.restaurant;

    final loc = AppLocalizations.of(context);

    // Not found state — mirrors the !restaurant early return
    if (restaurant == null) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: isDark ? Colors.grey[400] : Colors.grey[700]),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(loc.restaurantNotFound,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white),
                child: Text(loc.backToRestaurants),
              ),
            ],
          ),
        ),
      );
    }

    final isOpen = isRestaurantOpen(restaurant);

    // ── Delivery check ────────────────────────────────────────────────
    final rawFoodAddress =
        context.watch<UserProvider>().profileData?['foodAddress'];
    final foodAddress = rawFoodAddress is Map<String, dynamic>
        ? FoodAddress.fromMap(rawFoodAddress)
        : null;
    final deliversToUser = _deliversToAddress(restaurant, foodAddress);

    return Consumer<FoodCartProvider>(
      builder: (context, cart, _) {
        final cartQtyMap = _cartQuantityMap(cart.items);
        final filtered = _filteredFoods();
        final grouped = _groupedFoods();

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
          appBar: AppBar(
            backgroundColor:
                isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[700]),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: CustomScrollView(
              slivers: [
                // ── Restaurant Header ─────────────────────────────────────
                _RestaurantHeader(restaurant: restaurant, isDark: isDark),

                // ── Closed banner ─────────────────────────────────────────
                if (!isOpen) _buildClosedBanner(isDark),

                // ── No-delivery banner ──────────────────────────────────────
                if (!deliversToUser) _buildNoDeliveryBanner(isDark),

                // ── Tab buttons + search row ──────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TabAndSearchRow(
                          activeTab: _activeTab,
                          foodCount: widget.foods.length,
                          isDark: isDark,
                          searchController: _searchController,
                          onTabChange: (tab) =>
                              setState(() => _activeTab = tab),
                          restaurant: restaurant,
                        ),
                        if (_activeTab == 'menu' &&
                            _restaurantFoodCategories.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _FoodTypeIconRow(
                            selected: _selectedIconCategory,
                            isDark: isDark,
                            categories: _restaurantFoodCategories,
                            onSelect: (cat) {
                              setState(() {
                                _selectedIconCategory = cat;
                                if (_searchQuery.trim().isNotEmpty) {
                                  _performSearch();
                                } else {
                                  _typesenseResults = null;
                                }
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Menu tab content ──────────────────────────────────────
                if (_activeTab == 'menu') ...[
                  // Food list
                  if (filtered.isNotEmpty)
                    grouped != null
                        ? _GroupedFoodList(
                            grouped: grouped,
                            restaurant: restaurant,
                            isDark: isDark,
                            isOpen: isOpen,
                            deliversToUser: deliversToUser,
                            cartQtyMap: cartQtyMap,
                            onConflict: _handleConflict,
                            onRemove: (id) =>
                                _handleRemoveFromCart(id, cart.items),
                          )
                        : _FlatFoodList(
                            foods: filtered,
                            restaurant: restaurant,
                            isDark: isDark,
                            isOpen: isOpen,
                            deliversToUser: deliversToUser,
                            cartQtyMap: cartQtyMap,
                            onConflict: _handleConflict,
                            onRemove: (id) =>
                                _handleRemoveFromCart(id, cart.items),
                          )
                  else if (widget.foods.isEmpty)
                    SliverFillRemaining(child: _EmptyMenu(isDark: isDark))
                  else
                    SliverFillRemaining(
                      child: _NoResults(
                        isDark: isDark,
                        hasActiveFilters: _hasActiveFilters,
                        onClearAll: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _selectedIconCategory = null;
                            _typesenseResults = null;
                          });
                        },
                      ),
                    ),
                ],

                // ── Reviews tab content ───────────────────────────────────
                if (_activeTab == 'reviews')
                  SliverFillRemaining(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: cart.itemCount > 0 ? 80 : 0,
                      ),
                      child: _ReviewsTab(
                        restaurantId: restaurant.id,
                        isDark: isDark,
                      ),
                    ),
                  ),

                // ── Info tab content ──────────────────────────────────────
                if (_activeTab == 'info')
                  SliverFillRemaining(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: cart.itemCount > 0 ? 80 : 0,
                      ),
                      child: _InfoTab(
                        restaurant: restaurant,
                        isDark: isDark,
                        isOpen: isOpen,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Cart FAB — mirrors FoodCartSidebar mode="mobile"
          floatingActionButton: cart.itemCount > 0
              ? _CartFab(
                  itemCount: cart.itemCount,
                  subtotal: cart.totals.subtotal,
                  onTap: () => _showCartSheet(context, cart, isDark),
                )
              : null,
        );
      },
    );
  }

  SliverToBoxAdapter _buildClosedBanner(bool isDark) {
    final loc = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.red.withOpacity(0.10) : Colors.red[50],
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
            Icon(Icons.access_time_rounded,
                size: 20, color: isDark ? Colors.red[400] : Colors.red[500]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.currentlyClosed,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.red[400] : Colors.red[600]),
                  ),
                  Text(
                    loc.browseMenuWhenReopen,
                    style: TextStyle(
                        fontSize: 12,
                        color: (isDark ? Colors.red[400]! : Colors.red[500]!)
                            .withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delivery check helper ────────────────────────────────────────────
  bool _deliversToAddress(Restaurant r, FoodAddress? foodAddress) {
    if (foodAddress == null ||
        r.minOrderPrices == null ||
        r.minOrderPrices!.isEmpty) return true;
    for (final e in r.minOrderPrices!) {
      if (e['subregion'] == foodAddress.city) return true;
    }
    return false;
  }

  SliverToBoxAdapter _buildNoDeliveryBanner(bool isDark) {
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.orange.withOpacity(0.10) : Colors.orange[50],
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
            Icon(Icons.location_off_rounded,
                size: 20,
                color: isDark ? Colors.orange[400] : Colors.orange[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context).noDeliveryBanner,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.orange[400] : Colors.orange[800]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCartSheet(
      BuildContext context, FoodCartProvider cart, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider<FoodCartProvider>.value(
        value: cart,
        child: _CartBottomSheet(isDark: isDark, restaurant: widget.restaurant),
      ),
    );
  }
}

// =============================================================================
// PENDING CONFLICT  —  mirrors PendingConflict interface
// =============================================================================

class _PendingConflict {
  final Food food;
  final FoodCartRestaurant restaurant;
  final int quantity;
  final List<SelectedExtra> extras;
  final String specialNotes;
  final VoidCallback? onAfterReplace;

  const _PendingConflict({
    required this.food,
    required this.restaurant,
    required this.quantity,
    required this.extras,
    required this.specialNotes,
    this.onAfterReplace,
  });
}

// =============================================================================
// RESTAURANT HEADER  —  mirrors RestaurantHeader component
// =============================================================================

class _RestaurantHeader extends StatelessWidget {
  final Restaurant restaurant;
  final bool isDark;

  const _RestaurantHeader({required this.restaurant, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile image
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        isDark ? Colors.white.withOpacity(0.1) : Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: restaurant.profileImageUrl != null
                    ? Image.network(
                        restaurant.profileImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _Placeholder(isDark: isDark),
                      )
                    : _Placeholder(isDark: isDark),
              ),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (restaurant.categories?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        restaurant.categories!.join(', '),
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[500]),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Rating
                      if (restaurant.averageRating != null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              restaurant.averageRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (restaurant.reviewCount != null &&
                                restaurant.reviewCount! > 0)
                              Text(
                                ' (${restaurant.reviewCount} ${AppLocalizations.of(context).reviews.toLowerCase()})',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500]),
                              ),
                          ],
                        ),
                      ],
                      // Cuisine types
                      if (restaurant.cuisineTypes?.isNotEmpty ?? false)
                        Text(
                          localizeCuisines(restaurant.cuisineTypes!, loc),
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[500]),
                        ),
                      // Food type chips
                      if (restaurant.foodType?.isNotEmpty ?? false)
                        Wrap(
                          spacing: 4,
                          children: restaurant.foodType!
                              .map((ft) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF2D2B3F)
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      ft,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.grey[300]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool isDark;
  const _Placeholder({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[100],
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 28)),
      );
}

// =============================================================================
// TAB + SEARCH ROW
// Mirrors the flex row: [Menu btn] [Reviews btn]  |  [search input]
// =============================================================================

class _TabAndSearchRow extends StatelessWidget {
  final String activeTab;
  final int foodCount;
  final bool isDark;
  final TextEditingController searchController;
  final ValueChanged<String> onTabChange;
  final Restaurant? restaurant;

  const _TabAndSearchRow({
    required this.activeTab,
    required this.foodCount,
    required this.isDark,
    required this.searchController,
    required this.onTabChange,
    this.restaurant,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            _TabBtn(
              label: loc.menuTab,
              badge: '($foodCount)',
              isActive: activeTab == 'menu',
              isDark: isDark,
              onTap: () => onTabChange('menu'),
            ),
            const SizedBox(width: 4),
            _TabBtn(
              label: loc.reviewsTab,
              isActive: activeTab == 'reviews',
              isDark: isDark,
              onTap: () => onTabChange('reviews'),
            ),
            const SizedBox(width: 4),
            _TabBtn(
              label: loc.infoTab,
              isActive: activeTab == 'info',
              isDark: isDark,
              onTap: () => onTabChange('info'),
            ),
          ],
        ),
        if (activeTab == 'menu') ...[
          const SizedBox(height: 12),
          _SearchBar(
              controller: searchController,
              isDark: isDark,
              hint: loc.searchFoodHint),
        ],
      ],
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final String? badge;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isActive
                    ? Colors.white
                    : isDark
                        ? Colors.grey[400]
                        : Colors.grey[500],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Text(
                badge!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: isActive
                      ? Colors.white.withOpacity(0.7)
                      : isDark
                          ? Colors.grey[500]
                          : Colors.grey[400],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FOOD TYPE ICON ROW  —  mirrors FilterIcons with categories prop
// Uses FoodCategoryData.kCategories order + kCategoryIcons asset filenames.
// assets/images/foods/<filename> — same filenames as web /public/foods/
// =============================================================================

class _FoodTypeIconRow extends StatelessWidget {
  final String? selected;
  final bool isDark;
  final ValueChanged<String?> onSelect;
  final List<String>? categories; // when set, shows only these categories

  const _FoodTypeIconRow({
    required this.selected,
    required this.isDark,
    required this.onSelect,
    this.categories,
  });

  @override
  Widget build(BuildContext context) {
    // Preserve FoodCategoryData.kCategories order, filter to subset if provided
    final visible = FoodCategoryData.kCategories
        .where((cat) => categories == null || categories!.contains(cat))
        .toList();

    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
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
                        : Icon(Icons.restaurant,
                            size: 22,
                            color: isActive
                                ? Colors.white
                                : isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 56,
                    child: Text(
                      localizeCategory(category, AppLocalizations.of(context)),
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
    );
  }
}

// =============================================================================
// GROUPED FOOD LIST  —  mirrors the groupedFoods Map.entries rendering
// =============================================================================

class _GroupedFoodList extends StatelessWidget {
  final Map<String, List<Food>> grouped;
  final Restaurant restaurant;
  final bool isDark;
  final bool isOpen;
  final bool deliversToUser;
  final Map<String, int> cartQtyMap;
  final ValueChanged<_PendingConflict> onConflict;
  final ValueChanged<String> onRemove;

  const _GroupedFoodList({
    required this.grouped,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    this.deliversToUser = true,
    required this.cartQtyMap,
    required this.onConflict,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final entries = grouped.entries.toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            final category = entries[idx].key;
            final items = entries[idx].value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Spacer between groups (idx > 0)
                if (idx > 0) const SizedBox(height: 20),

                // Category heading
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    localizeCategory(category, AppLocalizations.of(context)),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                ),

                // Food cards
                ...items.map((food) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FoodCard(
                        food: food,
                        restaurant: restaurant,
                        isDark: isDark,
                        isOpen: isOpen,
                        deliversToUser: deliversToUser,
                        cartQuantity: cartQtyMap[food.id] ?? 0,
                        onConflict: onConflict,
                        onRemoveFromCart: () => onRemove(food.id),
                      ),
                    )),
              ],
            );
          },
          childCount: entries.length,
        ),
      ),
    );
  }
}

// =============================================================================
// FLAT FOOD LIST  —  mirrors the flat grid when search/filter is active
// =============================================================================

class _FlatFoodList extends StatelessWidget {
  final List<Food> foods;
  final Restaurant restaurant;
  final bool isDark;
  final bool isOpen;
  final bool deliversToUser;
  final Map<String, int> cartQtyMap;
  final ValueChanged<_PendingConflict> onConflict;
  final ValueChanged<String> onRemove;

  const _FlatFoodList({
    required this.foods,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    this.deliversToUser = true,
    required this.cartQtyMap,
    required this.onConflict,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FoodCard(
              food: foods[i],
              restaurant: restaurant,
              isDark: isDark,
              isOpen: isOpen,
              deliversToUser: deliversToUser,
              cartQuantity: cartQtyMap[foods[i].id] ?? 0,
              onConflict: onConflict,
              onRemoveFromCart: () => onRemove(foods[i].id),
            ),
          ),
          childCount: foods.length,
        ),
      ),
    );
  }
}

// =============================================================================
// FOOD CARD  —  mirrors FoodCard component
// =============================================================================

class _FoodCard extends StatelessWidget {
  final Food food;
  final Restaurant restaurant;
  final bool isDark;
  final bool isOpen;
  final bool deliversToUser;
  final int cartQuantity;
  final ValueChanged<_PendingConflict> onConflict;
  final VoidCallback onRemoveFromCart;

  const _FoodCard({
    required this.food,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    this.deliversToUser = true,
    required this.cartQuantity,
    required this.onConflict,
    required this.onRemoveFromCart,
  });

  /// Mirrors: FoodCategoryData.kFoodTypeTranslationKeys[food.foodType]
  /// TODO: replace with AppLocalizations lookup when i18n is wired up.
  String get _displayType => food.foodType;

  void _openFullScreenImage(
      BuildContext context, String imageUrl, String title) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageViewer(
            imageUrl: imageUrl,
            title: title,
            heroTag: 'food-image-${food.id}',
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Food image — only shown when available (mirrors conditional in TS)
          if (food.imageUrl != null) ...[
            GestureDetector(
              onTap: () =>
                  _openFullScreenImage(context, food.imageUrl!, food.name),
              child: Hero(
                tag: 'food-image-${food.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: Image.network(
                      food.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color:
                            isDark ? const Color(0xFF2D2B3F) : Colors.grey[100],
                        alignment: Alignment.center,
                        child:
                            const Text('🍽️', style: TextStyle(fontSize: 24)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Food info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Name
                Text(
                  food.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Type (translated)
                Text(
                  localizeFoodType(food.foodType, loc),
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[500] : Colors.grey[400]),
                ),

                // Description
                if (food.description != null && food.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      food.description!,
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[500]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 8),

                // Discount row (only when active)
                if (food.hasActiveDiscount && food.originalPrice != null) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          loc.foodDiscountPercent(food.discountPercentage ?? 0),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        loc.foodPriceTL(food.originalPrice!.toStringAsFixed(
                            food.originalPrice! % 1 == 0 ? 0 : 2)),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                          decoration: TextDecoration.lineThrough,
                          decorationColor:
                              isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        loc.foodPriceTL(food.price
                            .toStringAsFixed(food.price % 1 == 0 ? 0 : 2)),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],

                // Price (normal) + prep time + add button row
                Row(
                  children: [
                    if (!(food.hasActiveDiscount && food.originalPrice != null))
                      Text(
                        loc.foodPriceTL(food.price
                            .toStringAsFixed(food.price % 1 == 0 ? 0 : 2)),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? Colors.orange[400] : Colors.orange[600],
                        ),
                      ),

                    // Prep time
                    if (food.preparationTime != null &&
                        food.preparationTime! > 0) ...[
                      if (!(food.hasActiveDiscount &&
                          food.originalPrice != null))
                        const SizedBox(width: 8),
                      Icon(Icons.access_time_rounded,
                          size: 14,
                          color: isDark ? Colors.grey[500] : Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text(
                        loc.foodPrepTime(food.preparationTime!),
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[400]),
                      ),
                    ],

                    const Spacer(),

                    // Add / in-cart button
                    _CartButton(
                      isOpen: isOpen,
                      deliversToUser: deliversToUser,
                      cartQuantity: cartQuantity,
                      isDark: isDark,
                      onAdd: () => _openExtrasSheet(context),
                      onRemove: onRemoveFromCart,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExtrasSheet(BuildContext context) async {
    if (FirebaseAuth.instance.currentUser == null) {
      showCupertinoModalPopup(
        context: context,
        builder: (_) => LoginPromptModal(authService: AuthService()),
      );
      return;
    }

    // Authenticated but no delivery address — show the picker here.
    // After address is set, redirect to /restaurants so Typesense can
    // re-fetch the list filtered by the chosen delivery region.
    final rawFoodAddress =
        context.read<UserProvider>().profileData?['foodAddress'];
    if (rawFoodAddress == null) {
      final address = await showFoodLocationPicker(
        context,
        isDismissible: true,
      );
      if (!context.mounted) return;
      if (address != null) {
        context.go('/restaurants');
      }
      return;
    }

    final cart = context.read<FoodCartProvider>();
    final hasConflict = cart.currentRestaurant != null &&
        cart.currentRestaurant!.id != restaurant.id;

    if (hasConflict) {
      onConflict(_PendingConflict(
        food: food,
        restaurant: FoodCartRestaurant(
          id: restaurant.id,
          name: restaurant.name,
          profileImageUrl: restaurant.profileImageUrl,
        ),
        quantity: 1,
        extras: const [],
        specialNotes: '',
        onAfterReplace: () => _showExtrasSheet(context),
      ));
      return;
    }

    _showExtrasSheet(context);
  }

  void _showExtrasSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoodExtrasSheet(
        food: food,
        isDark: isDark,
        onConfirm: (extras, specialNotes, quantity) async {
          final cartRestaurant = FoodCartRestaurant(
            id: restaurant.id,
            name: restaurant.name,
            profileImageUrl: restaurant.profileImageUrl,
          );

          await context.read<FoodCartProvider>().addItem(
                foodId: food.id,
                foodName: food.name,
                foodDescription: food.description ?? '',
                price: food.price,
                imageUrl: food.imageUrl ?? '',
                foodCategory: food.foodCategory,
                foodType: food.foodType,
                preparationTime: food.preparationTime,
                restaurant: cartRestaurant,
                quantity: quantity,
                extras: extras,
                specialNotes: specialNotes,
              );
        },
      ),
    );
  }
}

// ── Cart button inside FoodCard ───────────────────────────────────────────────

class _CartButton extends StatelessWidget {
  final bool isOpen;
  final bool deliversToUser;
  final int cartQuantity;
  final bool isDark;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _CartButton({
    required this.isOpen,
    this.deliversToUser = true,
    required this.cartQuantity,
    required this.isDark,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    // Disabled state (closed)
    if (!isOpen) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(loc.foodClosedButton,
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[400])),
      );
    }

    // Disabled state (no delivery)
    if (!deliversToUser) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.block_rounded,
            size: 16, color: isDark ? Colors.grey[500] : Colors.grey[400]),
      );
    }

    // In-cart state
    if (cartQuantity > 0) {
      return GestureDetector(
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.green.withOpacity(0.15) : Colors.green[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded,
                  size: 14,
                  color: isDark ? Colors.green[400] : Colors.green[600]),
              const SizedBox(width: 6),
              Text(
                '$cartQuantity',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.green[400] : Colors.green[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Default — add state
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.orange.withOpacity(0.15) : Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded,
                size: 14,
                color: isDark ? Colors.orange[400] : Colors.orange[600]),
            const SizedBox(width: 6),
            Text(
              loc.foodAddLabel,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.orange[400] : Colors.orange[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FOOD EXTRAS SHEET  —  mirrors FoodExtrasSheet component
// foodCategory + allowedExtras drive resolveExtras — same as the props:
//   foodCategory={food.foodCategory}
//   allowedExtras={food.extras}
// =============================================================================

class _FoodExtrasSheet extends StatefulWidget {
  final Food food;
  final bool isDark;
  final Future<void> Function(
      List<SelectedExtra> extras, String specialNotes, int quantity) onConfirm;

  const _FoodExtrasSheet({
    required this.food,
    required this.isDark,
    required this.onConfirm,
  });

  @override
  State<_FoodExtrasSheet> createState() => _FoodExtrasSheetState();
}

class _FoodExtrasSheetState extends State<_FoodExtrasSheet> {
  int _quantity = 1;
  final Map<String, bool> _checked = {};
  final _notesController = TextEditingController();
  bool _submitting = false;

  late final List<FoodExtra> _resolvedExtras;

  @override
  void initState() {
    super.initState();
    _resolvedExtras = widget.food.extras ?? [];
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final extras = _checked.entries.where((e) => e.value).map((e) {
      final foodExtra =
          _resolvedExtras.where((x) => x.name == e.key).firstOrNull;
      return SelectedExtra(
          name: e.key, quantity: 1, price: foodExtra?.price ?? 0);
    }).toList();

    try {
      await widget.onConfirm(extras, _notesController.text.trim(), _quantity);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDark = widget.isDark;
    final food = widget.food;
    final selectedExtrasTotal = _resolvedExtras
        .where((e) => _checked[e.name] == true)
        .fold<double>(0, (sum, e) => sum + e.price);
    final total = (food.price + selectedExtrasTotal) * _quantity;

    return DraggableScrollableSheet(
      initialChildSize: _resolvedExtras.isNotEmpty ? 0.65 : 0.45,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF211F31) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // Food name + base price
                  Row(
                    children: [
                      Expanded(
                        child: Text(food.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      if (food.hasActiveDiscount &&
                          food.originalPrice != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            loc.foodDiscountPercent(
                                food.discountPercentage ?? 0),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          loc.foodPriceTL(
                              food.originalPrice!.toStringAsFixed(0)),
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[400],
                              decoration: TextDecoration.lineThrough,
                              decorationColor:
                                  isDark ? Colors.grey[500] : Colors.grey[400]),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          loc.foodPriceTL(food.price.toStringAsFixed(0)),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF059669)),
                        ),
                      ] else
                        Text(
                          loc.foodPriceTL(food.price.toStringAsFixed(0)),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.orange[400]
                                  : Colors.orange[600]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quantity
                  Row(
                    children: [
                      Text(loc.foodQuantityLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800])),
                      const Spacer(),
                      _QuantityPicker(
                          value: _quantity,
                          onChanged: (v) => setState(() => _quantity = v),
                          isDark: isDark),
                    ],
                  ),

                  // Extras
                  if (_resolvedExtras.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(loc.foodExtrasLabel,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[800])),
                    const SizedBox(height: 8),
                    ..._resolvedExtras.map(
                      (extra) => CheckboxListTile(
                        value: _checked[extra.name] ?? false,
                        onChanged: (v) =>
                            setState(() => _checked[extra.name] = v!),
                        title: Text(localizeExtra(extra.name, loc),
                            style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[200]
                                    : Colors.grey[900])),
                        subtitle: Text(
                            extra.price > 0
                                ? loc.foodExtraPriceTL(
                                    extra.price.toStringAsFixed(0))
                                : loc.foodFreeExtra,
                            style: TextStyle(
                                fontSize: 12,
                                color: extra.price > 0
                                    ? (isDark
                                        ? Colors.orange[300]
                                        : Colors.orange[700])
                                    : Colors.grey)),
                        activeColor: Colors.orange,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ),
                  ],

                  // Special notes
                  const SizedBox(height: 16),
                  Text(loc.foodSpecialNotes,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[300] : Colors.grey[800])),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: loc.foodNotesHint,
                      filled: true,
                      fillColor:
                          isDark ? const Color(0xFF211F31) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF2D2B3F)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Colors.orange,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Add to cart button
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(loc.foodAddToCart(total.toStringAsFixed(0)),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// QUANTITY PICKER
// =============================================================================

class _QuantityPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _QuantityPicker(
      {required this.value, required this.onChanged, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QtyBtn(
            icon: Icons.remove_rounded,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
            isDark: isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$value',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        _QtyBtn(
            icon: Icons.add_rounded,
            onTap: () => onChanged(value + 1),
            isDark: isDark),
      ],
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _QtyBtn(
      {required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.orange
              : isDark
                  ? const Color(0xFF2D2B3F)
                  : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color: enabled
                ? Colors.white
                : isDark
                    ? Colors.grey[600]
                    : Colors.grey[400]),
      ),
    );
  }
}

// =============================================================================
// CART FAB  —  mirrors FoodCartSidebar mode="mobile"
// =============================================================================

class _CartFab extends StatelessWidget {
  final int itemCount;
  final double subtotal;
  final VoidCallback onTap;

  const _CartFab(
      {required this.itemCount, required this.subtotal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: Colors.orange,
      icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white),
      label: Text(
        loc.foodItemsFab(itemCount, subtotal.toStringAsFixed(0)),
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// =============================================================================
// CART BOTTOM SHEET  —  mirrors FoodCartSidebar drawer/sheet content
// =============================================================================

class _CartBottomSheet extends StatefulWidget {
  final bool isDark;
  final Restaurant? restaurant;

  const _CartBottomSheet({required this.isDark, this.restaurant});

  @override
  State<_CartBottomSheet> createState() => _CartBottomSheetState();
}

class _CartBottomSheetState extends State<_CartBottomSheet> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final loc = AppLocalizations.of(context);
    return Consumer<FoodCartProvider>(
      builder: (context, cart, _) {
        // Auto-close when cart becomes empty — guard against double-pop
        if (cart.items.isEmpty && !_dismissed) {
          _dismissed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        if (_dismissed) return const SizedBox.shrink();

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, sc) => Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF211F31) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(loc.foodYourOrder,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (cart.currentRestaurant != null)
                        Text(cart.currentRestaurant!.name,
                            style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600])),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: cart.items.length,
                    itemBuilder: (_, i) {
                      final item = cart.items[i];
                      return _CartItemRow(
                        item: item,
                        isDark: isDark,
                        onIncrease: () =>
                            cart.updateQuantity(item.foodId, item.quantity + 1),
                        onDecrease: () =>
                            cart.updateQuantity(item.foodId, item.quantity - 1),
                        onRemove: () => cart.removeItem(item.foodId),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(loc.foodSubtotal,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600])),
                            Text(
                              loc.foodPriceTL(
                                  cart.totals.subtotal.toStringAsFixed(2)),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final r = widget.restaurant;
                              if (r != null) {
                                // 1. Check if restaurant is open
                                if (!checkRestaurantOpenAndAlert(context,
                                    restaurant: r)) {
                                  return;
                                }
                                // 2. Check minimum order price
                                final raw = context
                                    .read<UserProvider>()
                                    .profileData?['foodAddress'];
                                final foodAddress = raw is Map<String, dynamic>
                                    ? FoodAddress.fromMap(raw)
                                    : null;
                                final minOrder = getMinOrderPriceForAddress(
                                    r.minOrderPrices, foodAddress);
                                if (minOrder != null &&
                                    !checkMinOrderAndAlert(context,
                                        minOrderPrice: minOrder,
                                        cartSubtotal: cart.totals.subtotal)) {
                                  return;
                                }
                              }
                              Navigator.of(context).pop();
                              context.push('/food-checkout');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(loc.foodProceedToCheckout,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final FoodCartItem item;
  final bool isDark;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const _CartItemRow({
    required this.item,
    required this.isDark,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final extrasTotal =
        item.extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    final total = (item.price + extrasTotal) * item.quantity;

    return Dismissible(
      key: ValueKey(item.foodId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _QuantityPicker(
                value: item.quantity,
                onChanged: (v) =>
                    v > item.quantity ? onIncrease() : onDecrease(),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (item.extras.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: item.extras.map((ext) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2D2B3F)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF2D2B3F)
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('+',
                                    style: TextStyle(
                                        fontSize: 9, color: Colors.orange)),
                                const SizedBox(width: 2),
                                Text(
                                  localizeExtra(ext.name, loc),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                  ),
                                ),
                                if (ext.quantity > 1) ...[
                                  const SizedBox(width: 2),
                                  Text(
                                    '×${ext.quantity}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ],
                                if (ext.price > 0) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    loc.foodPriceTL(
                                        ext.price.toStringAsFixed(0)),
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.orange[300]
                                          : Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(loc.foodPriceTL(total.toStringAsFixed(0)),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18,
                      color: isDark ? Colors.red[300] : Colors.red[400]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RESTAURANT CONFLICT DIALOG  —  mirrors RestaurantConflictDialog component
// =============================================================================

class _RestaurantConflictDialog extends StatelessWidget {
  final String currentRestaurantName;
  final String newRestaurantName;
  final VoidCallback onReplace;
  final VoidCallback onCancel;

  const _RestaurantConflictDialog({
    required this.currentRestaurantName,
    required this.newRestaurantName,
    required this.onReplace,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoAlertDialog(
      title: Text(l10n.foodCartConflictTitle),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.foodCartConflictBody(currentRestaurantName, newRestaurantName),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: onCancel,
          child: Text(l10n.foodCartConflictKeep),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: onReplace,
          child: Text(l10n.foodCartConflictReplace),
        ),
      ],
    );
  }
}

// =============================================================================
// REVIEWS TAB  —  mirrors RestaurantReviews component (placeholder)
// =============================================================================

class _ReviewsTab extends StatelessWidget {
  final String restaurantId;
  final bool isDark;

  const _ReviewsTab({required this.restaurantId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RestaurantReviews(
        restaurantId: restaurantId,
        isDark: isDark,
      ),
    );
  }
}

// =============================================================================
// INFO TAB  —  working days, hours, address, contact
// =============================================================================

class _InfoTab extends StatelessWidget {
  final Restaurant restaurant;
  final bool isDark;
  final bool isOpen;

  const _InfoTab({
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
  });

  /// Maps a Firestore day string (e.g. "Monday") to the localized string.
  String _localizeDay(String day, AppLocalizations loc) {
    switch (day.toLowerCase()) {
      case 'monday':
        return loc.dayMonday;
      case 'tuesday':
        return loc.dayTuesday;
      case 'wednesday':
        return loc.dayWednesday;
      case 'thursday':
        return loc.dayThursday;
      case 'friday':
        return loc.dayFriday;
      case 'saturday':
        return loc.daySaturday;
      case 'sunday':
        return loc.daySunday;
      default:
        return day;
    }
  }

  /// Returns a compact, grouped day representation like "Mon – Fri, Sat, Sun".
  /// Consecutive days are collapsed into a range.
  List<String> _buildDayRanges(
      List<String> workingDays, AppLocalizations loc) {
    // Fixed ordering so we can detect consecutive runs
    const order = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    final activeLower =
        workingDays.map((d) => d.toLowerCase()).toSet();

    // Build sorted indices of active days
    final activeIndices = order
        .asMap()
        .entries
        .where((e) => activeLower.contains(e.value))
        .map((e) => e.key)
        .toList();

    if (activeIndices.isEmpty) return [];

    // Group consecutive indices into runs
    final runs = <List<int>>[];
    var current = [activeIndices.first];
    for (var i = 1; i < activeIndices.length; i++) {
      if (activeIndices[i] == activeIndices[i - 1] + 1) {
        current.add(activeIndices[i]);
      } else {
        runs.add(current);
        current = [activeIndices[i]];
      }
    }
    runs.add(current);

    return runs.map((run) {
      final first = _localizeDay(order[run.first], loc);
      final last = _localizeDay(order[run.last], loc);
      return run.length == 1
          ? first
          : run.length == 2
              ? '$first, $last'
              : '$first – $last';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final workingDays = restaurant.workingDays ?? [];
    final workingHours = restaurant.workingHours;
    final dayRanges = _buildDayRanges(workingDays, loc);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Open / Closed status pill ──────────────────────────────
          _StatusPill(isOpen: isOpen, isDark: isDark),
          const SizedBox(height: 20),

          // ── Working hours card ─────────────────────────────────────
          if (workingHours != null || workingDays.isNotEmpty)
            _InfoCard(
              isDark: isDark,
              icon: Icons.access_time_rounded,
              iconColor: Colors.orange,
              title: loc.workingHours,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hours row
                  if (workingHours != null) ...[
                    Row(
                      children: [
                        _InfoChip(
                          label:
                              '${workingHours.open}  –  ${workingHours.close}',
                          isDark: isDark,
                          highlight: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Working days
                  if (workingDays.isNotEmpty) ...[
                    Text(
                      loc.workingDays,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _WorkingDaysGrid(
                      allDays: const [
                        'Monday',
                        'Tuesday',
                        'Wednesday',
                        'Thursday',
                        'Friday',
                        'Saturday',
                        'Sunday',
                      ],
                      activeDays: workingDays,
                      isDark: isDark,
                      localizeDay: (d) => _localizeDay(d, loc),
                    ),
                    if (dayRanges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        dayRanges.join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

        ],
      ),
    );
  }
}

// ── Status pill ──────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final bool isOpen;
  final bool isDark;

  const _StatusPill({required this.isOpen, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = isOpen ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOpen
                ? AppLocalizations.of(context).restaurantDashboardStatusOpen
                : AppLocalizations.of(context).currentlyClosed,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? color[200] : color[700],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info card container ──────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _InfoCard({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor =
        isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white;
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Highlight chip (used for opening hours) ──────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final bool highlight;

  const _InfoChip({
    required this.label,
    required this.isDark,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.orange.withOpacity(isDark ? 0.15 : 0.10)
            : (isDark ? const Color(0xFF2D2B3F) : Colors.grey[100]),
        borderRadius: BorderRadius.circular(10),
        border: highlight
            ? Border.all(
                color: Colors.orange.withOpacity(0.35), width: 1)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: highlight
              ? (isDark ? Colors.orange[300] : Colors.orange[800])
              : (isDark ? Colors.grey[200] : Colors.grey[800]),
        ),
      ),
    );
  }
}

// ── Working days 7-cell grid ─────────────────────────────────────────────────

class _WorkingDaysGrid extends StatelessWidget {
  final List<String> allDays;
  final List<String> activeDays;
  final bool isDark;
  final String Function(String) localizeDay;

  const _WorkingDaysGrid({
    required this.allDays,
    required this.activeDays,
    required this.isDark,
    required this.localizeDay,
  });

  @override
  Widget build(BuildContext context) {
    final activeLower = activeDays.map((d) => d.toLowerCase()).toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: allDays.map((day) {
        final active = activeLower.contains(day.toLowerCase());
        // Show only first 3 letters of the localized day
        final label = localizeDay(day);
        final short = label.length > 3 ? label.substring(0, 3) : label;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active
                ? Colors.orange
                : (isDark
                    ? const Color(0xFF2D2B3F)
                    : Colors.grey[100]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? Colors.orange
                  : (isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey[300]!),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              short,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
                color: active
                    ? Colors.white
                    : (isDark ? Colors.grey[500] : Colors.grey[400]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// =============================================================================
// EMPTY STATES
// =============================================================================

/// Mirrors UtensilsCrossed empty state when foods.length === 0
class _EmptyMenu extends StatelessWidget {
  final bool isDark;
  const _EmptyMenu({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_food_rounded,
              size: 64, color: isDark ? Colors.grey[600] : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(loc.foodNoMenuItems,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(loc.foodCheckBackLater,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[500])),
        ],
      ),
    );
  }
}

/// Mirrors the no-results state when filteredFoods is empty but foods is not
class _NoResults extends StatelessWidget {
  final bool isDark;
  final bool hasActiveFilters;
  final VoidCallback onClearAll;

  const _NoResults({
    required this.isDark,
    required this.hasActiveFilters,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(loc.foodNoResults,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            loc.foodTryDifferentSearch,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[500]),
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onClearAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(loc.foodClearAll),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// LOADING SKELETON  —  mirrors LoadingSkeleton component
// =============================================================================

class _LoadingSkeleton extends StatelessWidget {
  final bool isDark;
  const _LoadingSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2D2B3F) : Colors.grey[200]!;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Back link skeleton
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(height: 14, width: 120, color: bg),
            ),
            const SizedBox(height: 16),

            // Header card skeleton
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(16))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 22, width: 180, color: bg),
                        const SizedBox(height: 8),
                        Container(height: 14, width: 120, color: bg),
                        const SizedBox(height: 8),
                        Container(height: 14, width: 220, color: bg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Food card skeletons
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(12))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 18, width: 140, color: bg),
                            const SizedBox(height: 8),
                            Container(height: 12, width: 80, color: bg),
                            const SizedBox(height: 8),
                            Container(
                                height: 14, width: double.infinity, color: bg),
                            const SizedBox(height: 8),
                            Container(height: 20, width: 80, color: bg),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SEARCH BAR
// =============================================================================

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String hint;

  const _SearchBar(
      {required this.controller, required this.isDark, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        filled: true,
        fillColor: isDark ? const Color(0xFF211F31) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange),
        ),
      ),
    );
  }
}

// =============================================================================
// FULL SCREEN IMAGE VIEWER
// =============================================================================

class _FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String heroTag;

  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.title,
    required this.heroTag,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dismiss on tap outside image
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox.expand(),
          ),

          // Zoomable image
          Center(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 4.0,
              child: Hero(
                tag: widget.heroTag,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),

          // Title bar at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
