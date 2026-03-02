// lib/screens/food/restaurant_detail_screen.dart
//
// Mirrors:
//   app/restaurantdetail/[id]/page.tsx  →  _RestaurantDetailScreenState (data fetch)
//   components/restaurants/RestaurantDetail.tsx  →  _RestaurantDetailBody (UI)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/restaurants/reviews.dart';
import '../../constants/foodData.dart';
import '../../constants/foodExtras.dart';
import '../../models/restaurant.dart';
import '../../models/food.dart';
import '../../providers/food_cart_provider.dart';
import '../../utils/restaurant_utils.dart';
import '../../services/typesense_service_manager.dart';
import '../../services/restaurant_typesense_service.dart';

// ─── Route ────────────────────────────────────────────────────────────────────
// GoRoute(
//   path: '/restaurant-detail/:id',
//   builder: (_, state) =>
//       RestaurantDetailScreen(restaurantId: state.pathParameters['id']!),
// )

// =============================================================================
// ENTRY POINT
// Mirrors RestaurantDetailPage — client-side data fetch via useCallback/useEffect
// =============================================================================

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

  @override
  void initState() {
    super.initState();
    _fetchData();
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

typedef _ActiveTab = String; // 'menu' | 'reviews'

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestaurantConflictDialog(
        currentRestaurantName: cart.currentRestaurant?.name ?? '',
        newRestaurantName: pending.restaurant.name,
        isDark: isDark,
        // Mirrors handleConflictReplace
        onReplace: () async {
          Navigator.of(context).pop();
          await context.read<FoodCartProvider>().clearAndAddFromNewRestaurant(
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
          setState(() => _pendingConflict = null);
        },
        // Mirrors onCancel={() => setPendingConflict(null)}
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

    // Not found state — mirrors the !restaurant early return
    if (restaurant == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text('Restaurant not found',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white),
                child: const Text('Back to Restaurants'),
              ),
            ],
          ),
        ),
      );
    }

    final isOpen = isRestaurantOpen(restaurant);

    return Consumer<FoodCartProvider>(
      builder: (context, cart, _) {
        final cartQtyMap = _cartQuantityMap(cart.items);
        final filtered = _filteredFoods();
        final grouped = _groupedFoods();

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: CustomScrollView(
            slivers: [
              // ── Restaurant Header ─────────────────────────────────────
              _RestaurantHeader(restaurant: restaurant, isDark: isDark),

              // ── Closed banner ─────────────────────────────────────────
              if (!isOpen) _buildClosedBanner(isDark),

              // ── Tab buttons + search row ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _TabAndSearchRow(
                    activeTab: _activeTab,
                    foodCount: widget.foods.length,
                    isDark: isDark,
                    searchController: _searchController,
                    onTabChange: (tab) => setState(() => _activeTab = tab),
                  ),
                ),
              ),

              // ── Menu tab content ──────────────────────────────────────
              if (_activeTab == 'menu') ...[
                // FilterIcons — only when categories loaded
                if (_restaurantFoodCategories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _FoodTypeIconRow(
                        selected: _selectedIconCategory,
                        isDark: isDark,
                        categories: _restaurantFoodCategories,
                        onSelect: (cat) {
                          setState(() {
                            _selectedIconCategory = cat;
                            // Re-run search with new category if text active
                            if (_searchQuery.trim().isNotEmpty) {
                              _performSearch();
                            } else {
                              _typesenseResults = null;
                            }
                          });
                        },
                      ),
                    ),
                  ),

                // Food list
                if (filtered.isNotEmpty)
                  grouped != null
                      ? _GroupedFoodList(
                          grouped: grouped,
                          restaurant: restaurant,
                          isDark: isDark,
                          isOpen: isOpen,
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
                  child: _ReviewsTab(
                    restaurantId: restaurant.id,
                    isDark: isDark,
                  ),
                ),
            ],
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
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.red.withOpacity(0.10) : Colors.red[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.red.withOpacity(0.20) : Colors.red[200]!,
            ),
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
                      'Currently closed',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.red[400] : Colors.red[600]),
                    ),
                    Text(
                      'Browse the menu and order when we reopen.',
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
      ),
    );
  }

  void _showCartSheet(
      BuildContext context, FoodCartProvider cart, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartBottomSheet(cart: cart, isDark: isDark),
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

  const _PendingConflict({
    required this.food,
    required this.restaurant,
    required this.quantity,
    required this.extras,
    required this.specialNotes,
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

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button — mirrors <Link href="/restaurants">
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded,
                      size: 18,
                      color: isDark ? Colors.grey[400] : Colors.grey[500]),
                  Text(
                    'Back to Restaurants',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[400] : Colors.grey[500]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark
                      ? Colors.grey[700]!.withOpacity(0.4)
                      : Colors.grey[200]!,
                ),
                borderRadius: BorderRadius.circular(16),
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
                          color: isDark ? Colors.grey[700]! : Colors.white,
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
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[500]),
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
                                    restaurant.averageRating!
                                        .toStringAsFixed(1),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (restaurant.reviewCount != null &&
                                      restaurant.reviewCount! > 0)
                                    Text(
                                      ' (${restaurant.reviewCount} reviews)',
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
                                restaurant.cuisineTypes!.join(', '),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500]),
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
                                                ? Colors.grey[700]
                                                : Colors.grey[100],
                                            borderRadius:
                                                BorderRadius.circular(20),
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
        color: isDark ? Colors.grey[700] : Colors.grey[100],
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

  const _TabAndSearchRow({
    required this.activeTab,
    required this.foodCount,
    required this.isDark,
    required this.searchController,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Tab buttons
            Row(
              children: [
                _TabBtn(
                  label: 'Menu',
                  badge: '($foodCount)',
                  isActive: activeTab == 'menu',
                  isDark: isDark,
                  onTap: () => onTabChange('menu'),
                ),
                const SizedBox(width: 4),
                _TabBtn(
                  label: 'Reviews',
                  isActive: activeTab == 'reviews',
                  isDark: isDark,
                  onTap: () => onTabChange('reviews'),
                ),
              ],
            ),

            const Spacer(),

            // Search — only when on menu tab
            if (activeTab == 'menu')
              SizedBox(
                width: 200,
                child: _SearchBar(
                    controller: searchController,
                    isDark: isDark,
                    hint: 'Search food…'),
              ),
          ],
        ),
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
                              ? Colors.grey[800]
                              : Colors.grey[100],
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
                      category,
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
  final Map<String, int> cartQtyMap;
  final ValueChanged<_PendingConflict> onConflict;
  final ValueChanged<String> onRemove;

  const _GroupedFoodList({
    required this.grouped,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    required this.cartQtyMap,
    required this.onConflict,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final entries = grouped.entries.toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, idx) {
            final category = entries[idx].key;
            final items = entries[idx].value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Divider between groups (idx > 0)
                if (idx > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Divider(
                      color: isDark ? Colors.grey[700] : Colors.grey[200],
                      height: 1,
                    ),
                  ),

                // Category heading
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                ),

                // Food cards
                ...items.map((food) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _FoodCard(
                        food: food,
                        restaurant: restaurant,
                        isDark: isDark,
                        isOpen: isOpen,
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
  final Map<String, int> cartQtyMap;
  final ValueChanged<_PendingConflict> onConflict;
  final ValueChanged<String> onRemove;

  const _FlatFoodList({
    required this.foods,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    required this.cartQtyMap,
    required this.onConflict,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _FoodCard(
              food: foods[i],
              restaurant: restaurant,
              isDark: isDark,
              isOpen: isOpen,
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
  final int cartQuantity;
  final ValueChanged<_PendingConflict> onConflict;
  final VoidCallback onRemoveFromCart;

  const _FoodCard({
    required this.food,
    required this.restaurant,
    required this.isDark,
    required this.isOpen,
    required this.cartQuantity,
    required this.onConflict,
    required this.onRemoveFromCart,
  });

  /// Mirrors: FoodCategoryData.kFoodTypeTranslationKeys[food.foodType]
  /// TODO: replace with AppLocalizations lookup when i18n is wired up.
  String get _displayType => food.foodType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isDark ? Colors.grey[700]!.withOpacity(0.4) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Food image — only shown when available (mirrors conditional in TS)
          if (food.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 112,
                height: 112,
                child: Image.network(
                  food.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    alignment: Alignment.center,
                    child: const Text('🍽️', style: TextStyle(fontSize: 24)),
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
                  _displayType,
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

                // Price + prep time + add button row
                Row(
                  children: [
                    // Price
                    Text(
                      '${food.price.toStringAsFixed(food.price % 1 == 0 ? 0 : 2)} TL',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.orange[400] : Colors.orange[600],
                      ),
                    ),

                    // Prep time
                    if (food.preparationTime != null &&
                        food.preparationTime! > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.access_time_rounded,
                          size: 14,
                          color: isDark ? Colors.grey[500] : Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text(
                        '${food.preparationTime} min',
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

  void _openExtrasSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoodExtrasSheet(
        food: food,
        isDark: isDark,
        // Mirrors handleExtrasConfirm
        onConfirm: (extras, specialNotes, quantity) async {
          final cartRestaurant = FoodCartRestaurant(
            id: restaurant.id,
            name: restaurant.name,
            profileImageUrl: restaurant.profileImageUrl,
          );

          final result = await context.read<FoodCartProvider>().addItem(
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

          if (result == AddItemResult.restaurantConflict) {
            onConflict(_PendingConflict(
              food: food,
              restaurant: cartRestaurant,
              quantity: quantity,
              extras: extras,
              specialNotes: specialNotes,
            ));
          }
        },
      ),
    );
  }
}

// ── Cart button inside FoodCard ───────────────────────────────────────────────

class _CartButton extends StatelessWidget {
  final bool isOpen;
  final int cartQuantity;
  final bool isDark;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _CartButton({
    required this.isOpen,
    required this.cartQuantity,
    required this.isDark,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Disabled state (closed)
    if (!isOpen) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Closed',
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[400])),
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
              'Add',
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

  late final List<String> _resolvedExtras;

  @override
  void initState() {
    super.initState();
    _resolvedExtras = FoodExtrasData.resolveExtras(
      category: widget.food.foodCategory,
      allowedExtras: widget.food.extras,
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final extras = _checked.entries
        .where((e) => e.value)
        .map((e) => SelectedExtra(name: e.key, quantity: 1, price: 0))
        .toList();

    try {
      await widget.onConfirm(extras, _notesController.text.trim(), _quantity);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final food = widget.food;
    final total = food.price * _quantity;

    return DraggableScrollableSheet(
      initialChildSize: _resolvedExtras.isNotEmpty ? 0.65 : 0.45,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
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
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
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
                      Text(
                        '${food.price.toStringAsFixed(0)} TL',
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
                      Text('Quantity',
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
                    Text('Extras',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[800])),
                    const SizedBox(height: 8),
                    ..._resolvedExtras.map(
                      (extra) => CheckboxListTile(
                        value: _checked[extra] ?? false,
                        onChanged: (v) => setState(() => _checked[extra] = v!),
                        title: Text(extra,
                            style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[200]
                                    : Colors.grey[900])),
                        subtitle: const Text('Free',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        activeColor: Colors.orange,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    ),
                  ],

                  // Special notes
                  const SizedBox(height: 16),
                  Text('Special notes (optional)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[300] : Colors.grey[800])),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'E.g. no onions…',
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Add to cart button
            Padding(
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
                      : Text('Add to cart — ${total.toStringAsFixed(0)} TL',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
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
                  ? Colors.grey[800]
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
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: Colors.orange,
      icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white),
      label: Text(
        '$itemCount item${itemCount == 1 ? '' : 's'} · ${subtotal.toStringAsFixed(0)} TL',
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// =============================================================================
// CART BOTTOM SHEET  —  mirrors FoodCartSidebar drawer/sheet content
// =============================================================================

class _CartBottomSheet extends StatelessWidget {
  final FoodCartProvider cart;
  final bool isDark;

  const _CartBottomSheet({required this.cart, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('Your order',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (cart.currentRestaurant != null)
                    Text(cart.currentRestaurant!.name,
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[600])),
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
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal',
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600])),
                      Text(
                        '${cart.totals.subtotal.toStringAsFixed(2)} TL',
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
                        Navigator.of(context).pop();
                        // TODO: navigate to checkout screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Proceed to Checkout',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
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

class _CartItemRow extends StatelessWidget {
  final FoodCartItem item;
  final bool isDark;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _CartItemRow({
    required this.item,
    required this.isDark,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    final extrasTotal =
        item.extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    final total = (item.price + extrasTotal) * item.quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _QuantityPicker(
            value: item.quantity,
            onChanged: (v) => v > item.quantity ? onIncrease() : onDecrease(),
            isDark: isDark,
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
                  Text(
                    item.extras.map((e) => e.name).join(', '),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[500]),
                  ),
              ],
            ),
          ),
          Text('${total.toStringAsFixed(0)} TL',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
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
  final bool isDark;
  final VoidCallback onReplace;
  final VoidCallback onCancel;

  const _RestaurantConflictDialog({
    required this.currentRestaurantName,
    required this.newRestaurantName,
    required this.isDark,
    required this.onReplace,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Start a new order?',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text(
        'Your cart has items from $currentRestaurantName. '
        'Adding from $newRestaurantName will clear your current cart.',
        style: TextStyle(
            fontSize: 14, color: isDark ? Colors.grey[300] : Colors.grey[700]),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text('Keep current',
              style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[700])),
        ),
        ElevatedButton(
          onPressed: onReplace,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Start new order'),
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
// EMPTY STATES
// =============================================================================

/// Mirrors UtensilsCrossed empty state when foods.length === 0
class _EmptyMenu extends StatelessWidget {
  final bool isDark;
  const _EmptyMenu({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_food_rounded,
              size: 64, color: isDark ? Colors.grey[600] : Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No menu items',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Check back later for new items.',
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No results',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Try a different search or category.',
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
              child: const Text('Clear all'),
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
    final bg = isDark ? Colors.grey[700]! : Colors.grey[200]!;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Back link skeleton
            Container(height: 14, width: 120, color: bg),
            const SizedBox(height: 16),

            // Header card skeleton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[100]!),
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
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey[800]!.withOpacity(0.6)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isDark
                            ? Colors.grey[700]!.withOpacity(0.5)
                            : Colors.grey[100]!),
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
        fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
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
