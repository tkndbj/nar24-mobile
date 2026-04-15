// lib/screens/market/market_category_detail_screen.dart
//
// Hybrid data strategy:
//   Default browsing (no search, no filters, sort=newest) → Firestore
//   Search / brand filter / type filter / non-default sort  → Typesense
//   Facets → always Typesense

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/market_typesense_service.dart';
import '../../services/typesense_service_manager.dart';
import '../../providers/market_cart_provider.dart';
import '../../constants/market_categories.dart';

// ============================================================================
// SCREEN
// ============================================================================

class MarketCategoryDetailScreen extends StatefulWidget {
  final String categorySlug;

  const MarketCategoryDetailScreen({super.key, required this.categorySlug});

  @override
  State<MarketCategoryDetailScreen> createState() =>
      _MarketCategoryDetailScreenState();
}

class _MarketCategoryDetailScreenState
    extends State<MarketCategoryDetailScreen> {
  // ── Data ───────────────────────────────────────────────────────────────
  List<MarketItem> _items = [];
  MarketFacets _facets = MarketFacets.empty;

  // ── Filters ────────────────────────────────────────────────────────────
  final Set<String> _selectedBrands = {};
  final Set<String> _selectedTypes = {};
  MarketSortOption _sortOption = MarketSortOption.newest;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Pagination ─────────────────────────────────────────────────────────
  static const _kPageSize = 20;

  // Typesense pagination
  int _tsCurrentPage = 0;
  bool _tsHasMore = true;

  // Firestore cursor pagination
  DocumentSnapshot? _lastFirestoreDoc;
  bool _fsHasMore = true;

  bool _isLoadingMore = false;

  // ── Loading ────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isSearching = false;

  // ── Debounce ───────────────────────────────────────────────────────────
  Timer? _searchDebounce;

  // ── Scroll ─────────────────────────────────────────────────────────────
  final _scrollController = ScrollController();

  // ── Services ───────────────────────────────────────────────────────────
  late final MarketTypesenseService _typesense;
  final _firestore = FirebaseFirestore.instance;

  MarketCategory? get _category => kMarketCategoryMap[widget.categorySlug];

  /// Use Firestore when the user is just browsing: no search, no facet
  /// filters, and default sort (newest). Everything else → Typesense.
  bool get _useFirestore =>
      _searchQuery.trim().isEmpty &&
      _selectedBrands.isEmpty &&
      _selectedTypes.isEmpty &&
      _sortOption == MarketSortOption.newest;

  bool get _hasMore => _useFirestore ? _fsHasMore : _tsHasMore;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _typesense = TypeSenseServiceManager.instance.marketService;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialLoad();
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

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  // ============================================================================
  // DATA — ROUTING
  // ============================================================================

  Future<void> _initialLoad() async {
    _resetPagination();
    await Future.wait([_fetchItems(), _fetchFacets()]);
  }

  void _resetPagination() {
    _tsCurrentPage = 0;
    _tsHasMore = true;
    _lastFirestoreDoc = null;
    _fsHasMore = true;
  }

  Future<void> _fetchItems() async {
    if (_useFirestore) {
      await _fetchFromFirestore(isInitial: true);
    } else {
      await _fetchFromTypesense(isInitial: true);
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    if (_useFirestore) {
      await _fetchFromFirestore(isInitial: false);
    } else {
      await _fetchFromTypesense(isInitial: false);
    }

    if (mounted) setState(() => _isLoadingMore = false);
  }

  // ============================================================================
  // DATA — FIRESTORE (default browsing)
  // ============================================================================

  Future<void> _fetchFromFirestore({required bool isInitial}) async {
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('market-items')
          .where('category', isEqualTo: widget.categorySlug)
          .where('isAvailable', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_kPageSize);

      if (!isInitial && _lastFirestoreDoc != null) {
        q = q.startAfterDocument(_lastFirestoreDoc!);
      }

      final snap = await q.get();
      final newItems = snap.docs.map(_marketItemFromFirestore).toList();

      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _items = newItems;
        } else {
          _items = [..._items, ...newItems];
        }
        _lastFirestoreDoc =
            snap.docs.isNotEmpty ? snap.docs.last : _lastFirestoreDoc;
        _fsHasMore = newItems.length >= _kPageSize;
        _isLoading = false;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('[MarketDetail] Firestore fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSearching = false;
        });
      }
    }
  }

  static MarketItem _marketItemFromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return MarketItem(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      brand: (d['brand'] as String?) ?? '',
      type: (d['type'] as String?) ?? '',
      category: (d['category'] as String?) ?? '',
      price: (d['price'] as num?)?.toDouble() ?? 0,
      stock: (d['stock'] as num?)?.toInt() ?? 0,
      description: (d['description'] as String?) ?? '',
      imageUrl: (d['imageUrl'] as String?) ?? '',
      imageUrls: ((d['imageUrls'] as List?) ?? []).cast<String>(),
      isAvailable: (d['isAvailable'] as bool?) ?? true,
    );
  }

  // ============================================================================
  // DATA — TYPESENSE (search / filters / non-default sort)
  // ============================================================================

  Future<void> _fetchFromTypesense({required bool isInitial}) async {
    final page = isInitial ? 0 : _tsCurrentPage + 1;

    try {
      final result = await _typesense.searchItems(
        category: widget.categorySlug,
        query: _searchQuery,
        sort: _sortOption,
        brands: _selectedBrands.isNotEmpty ? _selectedBrands.toList() : null,
        types: _selectedTypes.isNotEmpty ? _selectedTypes.toList() : null,
        hitsPerPage: _kPageSize,
        page: page,
      );

      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _items = result.items;
        } else {
          _items = [..._items, ...result.items];
        }
        _tsCurrentPage = page;
        _tsHasMore = page < result.nbPages - 1;
        _isLoading = false;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('[MarketDetail] Typesense fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSearching = false;
        });
      }
    }
  }

  // ============================================================================
  // DATA — FACETS (always Typesense)
  // ============================================================================

  Future<void> _fetchFacets() async {
    try {
      final facets = await _typesense.fetchFacets(
        category: widget.categorySlug,
        query: _searchQuery,
        selectedBrands:
            _selectedBrands.isNotEmpty ? _selectedBrands.toList() : null,
        selectedTypes:
            _selectedTypes.isNotEmpty ? _selectedTypes.toList() : null,
      );

      if (mounted) setState(() => _facets = facets);
    } catch (e) {
      debugPrint('[MarketDetail] Facets error: $e');
    }
  }

  // ============================================================================
  // FILTER / SEARCH HANDLERS
  // ============================================================================

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_searchController.text != _searchQuery) {
        setState(() => _searchQuery = _searchController.text);
        _performSearch();
      }
    });
  }

  void _toggleBrand(String brand) {
    setState(() {
      if (_selectedBrands.contains(brand)) {
        _selectedBrands.remove(brand);
      } else {
        _selectedBrands.add(brand);
      }
    });
    _performSearch();
  }

  void _toggleType(String type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
    _performSearch();
  }

  void _cycleSortOption() {
    const cycle = [
      MarketSortOption.newest,
      MarketSortOption.priceAsc,
      MarketSortOption.priceDesc,
      MarketSortOption.nameAsc,
    ];
    final idx = cycle.indexOf(_sortOption);
    setState(() => _sortOption = cycle[(idx + 1) % cycle.length]);
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() => _isSearching = true);
    _resetPagination();
    await Future.wait([_fetchItems(), _fetchFacets()]);
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _selectedBrands.isNotEmpty ||
      _selectedTypes.isNotEmpty ||
      _sortOption != MarketSortOption.newest;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedBrands.clear();
      _selectedTypes.clear();
      _sortOption = MarketSortOption.newest;
    });
    _performSearch();
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final category = _category;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
        body: _isLoading
            ? SafeArea(child: _buildSkeleton(isDark))
            : RefreshIndicator(
                onRefresh: _initialLoad,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // ── App bar ──────────────────────────────────────
                    SliverAppBar(
                      title: Text(
                        category?.labelTr ?? 'Market',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      floating: true,
                      snap: true,
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      iconTheme: const IconThemeData(color: Colors.white),
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                    ),

                      // ── Search bar + sort ────────────────────────────
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Ürün ara...',
                                    prefixIcon:
                                        const Icon(Icons.search, size: 20),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF2D2B3F)
                                        : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide:
                                          const BorderSide(color: Colors.green),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _SortButton(
                                sortOption: _sortOption,
                                isDark: isDark,
                                onTap: _cycleSortOption,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Type filter chips ────────────────────────────
                      if (_facets.types.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _FacetChipRow(
                            label: 'Tür',
                            facets: _facets.types,
                            selected: _selectedTypes,
                            isDark: isDark,
                            onToggle: _toggleType,
                          ),
                        ),

                      // ── Brand filter chips ───────────────────────────
                      if (_facets.brands.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _FacetChipRow(
                            label: 'Marka',
                            facets: _facets.brands,
                            selected: _selectedBrands,
                            isDark: isDark,
                            onToggle: _toggleBrand,
                          ),
                        ),

                      // ── Active filters clear ────────────────────────
                      if (_hasActiveFilters)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: GestureDetector(
                              onTap: _clearFilters,
                              child: Row(
                                children: [
                                  Icon(Icons.close,
                                      size: 14, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Filtreleri Temizle',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── Items ────────────────────────────────────────
                      if (_isSearching)
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate: _gridDelegate,
                            delegate: SliverChildBuilderDelegate(
                              (_, __) => _ItemCardSkeleton(isDark: isDark),
                              childCount: 6,
                            ),
                          ),
                        )
                      else if (_items.isNotEmpty) ...[
                        SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: SliverGrid(
                            gridDelegate: _gridDelegate,
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _MarketItemCard(
                                item: _items[i],
                                isDark: isDark,
                              ),
                              childCount: _items.length,
                            ),
                          ),
                        ),
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
                                        AlwaysStoppedAnimation(Colors.green),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ] else
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📦',
                                    style: TextStyle(fontSize: 56)),
                                const SizedBox(height: 16),
                                Text(
                                  'Ürün bulunamadı',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_hasActiveFilters) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _clearFilters,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Filtreleri Temizle'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
        floatingActionButton: Consumer<MarketCartProvider>(
          builder: (context, cart, _) {
            if (cart.itemCount == 0) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => context.push('/market-cart'),
              backgroundColor: const Color(0xFF00A86B),
              icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white),
              label: Text(
                '${cart.itemCount} ürün • ${cart.totals.subtotal.toStringAsFixed(0)} TL',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
      ),
    );
  }

  SliverGridDelegateWithFixedCrossAxisCount get _gridDelegate =>
      const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.56,
      );

  Widget _buildSkeleton(bool isDark) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: _gridDelegate,
      itemCount: 6,
      itemBuilder: (_, __) => _ItemCardSkeleton(isDark: isDark),
    );
  }
}

// ============================================================================
// FACET CHIP ROW
// ============================================================================

class _FacetChipRow extends StatelessWidget {
  final String label;
  final List<MarketFacetValue> facets;
  final Set<String> selected;
  final bool isDark;
  final ValueChanged<String> onToggle;

  const _FacetChipRow({
    required this.label,
    required this.facets,
    required this.selected,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: facets.length,
          itemBuilder: (_, i) {
            final f = facets[i];
            final isActive = selected.contains(f.value);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onToggle(f.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green
                        : isDark
                            ? const Color(0xFF2D2B3F)
                            : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive
                          ? Colors.green
                          : isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${f.count}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive
                              ? Colors.white70
                              : isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
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
// MARKET ITEM CARD (with add-to-cart)
// ============================================================================

class _MarketItemCard extends StatelessWidget {
  final MarketItem item;
  final bool isDark;

  const _MarketItemCard({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<MarketCartProvider>();
    final qtyInCart = cart.quantityOf(item.id);
    final isOutOfStock = item.stock <= 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: isDark ? const Color(0xFF1C1A29) : Colors.white,
                    child: item.imageUrl.isNotEmpty
                        ? GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              PageRouteBuilder(
                                opaque: false,
                                barrierColor: Colors.black,
                                pageBuilder: (_, __, ___) => _FullScreenImage(
                                  imageUrl: item.imageUrl,
                                  heroTag: 'market-item-${item.id}',
                                ),
                              ),
                            ),
                            child: Hero(
                              tag: 'market-item-${item.id}',
                              child: Image.network(
                                item.imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    _imagePlaceholder(isDark),
                              ),
                            ),
                          )
                        : _imagePlaceholder(isDark),
                  ),
                  if (isOutOfStock)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      alignment: Alignment.center,
                      child: const Text(
                        'Stokta Yok',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.brand.isNotEmpty)
                    Text(
                      item.brand,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        '${item.price.toStringAsFixed(2)} TL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                      const Spacer(),
                      if (qtyInCart == 0)
                        _AddButton(
                          isOutOfStock: isOutOfStock,
                          onTap: isOutOfStock ? null : () => cart.addItem(item),
                        )
                      else
                        _QuantityStepper(
                          quantity: qtyInCart,
                          isDark: isDark,
                          onDecrement: () =>
                              cart.updateQuantity(item.id, qtyInCart - 1),
                          onIncrement: () =>
                              cart.updateQuantity(item.id, qtyInCart + 1),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF3A3850) : Colors.grey[100],
      alignment: Alignment.center,
      child:
          Icon(Icons.shopping_bag_outlined, size: 40, color: Colors.grey[400]),
    );
  }
}

// ============================================================================
// ADD BUTTON
// ============================================================================

class _AddButton extends StatelessWidget {
  final bool isOutOfStock;
  final VoidCallback? onTap;

  const _AddButton({required this.isOutOfStock, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isOutOfStock ? Colors.grey[400] : const Color(0xFF00A86B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 20),
      ),
    );
  }
}

// ============================================================================
// QUANTITY STEPPER
// ============================================================================

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final bool isDark;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.isDark,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF00A86B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onDecrement,
            child: const SizedBox(
              width: 28,
              height: 34,
              child: Icon(Icons.remove, color: Colors.white, size: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: onIncrement,
            child: const SizedBox(
              width: 28,
              height: 34,
              child: Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SORT BUTTON
// ============================================================================

class _SortButton extends StatelessWidget {
  final MarketSortOption sortOption;
  final bool isDark;
  final VoidCallback onTap;

  const _SortButton({
    required this.sortOption,
    required this.isDark,
    required this.onTap,
  });

  String get _label {
    switch (sortOption) {
      case MarketSortOption.priceAsc:
        return 'Ucuz';
      case MarketSortOption.priceDesc:
        return 'Pahalı';
      case MarketSortOption.nameAsc:
        return 'A-Z';
      case MarketSortOption.newest:
        return 'Sırala';
    }
  }

  bool get _isActive => sortOption != MarketSortOption.newest;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isActive
              ? Colors.green
              : isDark
                  ? const Color(0xFF2D2B3F)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isActive
                ? Colors.green
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
              _label,
              style: TextStyle(
                fontSize: 12,
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

// ============================================================================
// SKELETON
// ============================================================================

class _ItemCardSkeleton extends StatelessWidget {
  final bool isDark;

  const _ItemCardSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF3A3850) : Colors.grey[200]!;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 10, width: 50, color: bg),
                  const SizedBox(height: 6),
                  Container(height: 12, width: 100, color: bg),
                  const Spacer(),
                  Container(height: 14, width: 60, color: bg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// FULL SCREEN IMAGE VIEWER
// ============================================================================

class _FullScreenImage extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const _FullScreenImage({required this.imageUrl, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
