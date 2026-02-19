import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/dynamic_market_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/product_list_sliver.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product_summary.dart';
import '../../widgets/dynamicscreens/market_app_bar.dart';
import 'package:go_router/go_router.dart';
import '../../route_observer.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/market_search_delegate.dart';
import '../../providers/search_history_provider.dart';
import '../../utils/color_localization.dart';
import '../../constants/all_in_one_category_data.dart';

class DynamicMarketScreen extends StatefulWidget {
  final String? selectedSubcategory;
  final String? selectedSubSubcategory;
  final String? displayName;
  final String category;
  final String? buyerCategory;
  final String? buyerSubcategory;

  const DynamicMarketScreen({
    Key? key,
    required this.category,
    this.selectedSubcategory,
    this.selectedSubSubcategory,
    this.displayName,
    this.buyerCategory,
    this.buyerSubcategory,
  }) : super(key: key);

  @override
  _DynamicMarketScreenState createState() => _DynamicMarketScreenState();
}

class _DynamicMarketScreenState extends State<DynamicMarketScreen>
    with RouteAware {
  late final ShopMarketProvider _shopMarketProvider;
  late final MarketProvider _marketProvider;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  List<String> _dynamicSubSubcategories = [];
  bool _isSearching = false;
  bool _isInitialized = false;
  String _selectedSortOption = 'None';
  VoidCallback? _searchTextListener;

  // Dynamic filter state
  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  double? _minPrice;
  double? _maxPrice;

  final List<String> _sortOptions = [
    'None',
    'Alphabetical',
    'Date',
    'Price Low to High',
    'Price High to Low',
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setupProvidersAndLoad();
      }
    });
  }

  void _initializeControllers() {
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _setupSearchListener(SearchProvider searchProv) {
    _removeSearchListener();

    _searchTextListener = () {
      if (searchProv.mounted) {
        searchProv.updateTerm(
          _searchController.text,
          l10n: AppLocalizations.of(context),
        );
      }
    };
    _searchController.addListener(_searchTextListener!);
  }

  void _removeSearchListener() {
    if (_searchTextListener != null) {
      _searchController.removeListener(_searchTextListener!);
      _searchTextListener = null;
    }
  }

  // Separate method for provider setup to avoid build-time issues
  Future<void> _setupProvidersAndLoad() async {
    if (!mounted) return;

    try {
      _shopMarketProvider = context.read<ShopMarketProvider>();
      _marketProvider = context.read<MarketProvider>();

      // Ensure we're not in a build phase
      await Future.delayed(Duration.zero);

      if (!mounted) return;

      // Set all state at once, single query
      await _shopMarketProvider.initialize(
        category: widget.category,
        subcategory: widget.selectedSubcategory,
        subSubcategory: widget.selectedSubSubcategory,
        buyerCategory: widget.buyerCategory,
        buyerSubcategory: widget.buyerSubcategory,
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Check if viewport needs more content (for tablets/large screens)
        _checkViewportAndLoadMoreIfNeeded();
      }
    } catch (e) {
      debugPrint('Error setting up providers: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true; // Set to true even on error to show UI
        });
      }
    }
  }

  @override
  void didPopNext() {
    super.didPopNext();
    Future.microtask(() {
      if (mounted) {
        FocusScope.of(context).unfocus();
        _clearSearchUI();
      }
    });
  }

  void _clearSearchUI() {
    if (!mounted) return;
    _searchController.clear();
    _searchFocusNode.unfocus();
    if (_isSearching) {
      setState(() => _isSearching = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _disposeControllers() {
    _removeSearchListener(); // ✅ Use helper method
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
  }

  void _onScroll() {
    if (!_isInitialized || !mounted) return;

    final shopProv = context.read<ShopMarketProvider>();

    // Load more products when near bottom
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (shopProv.hasMore && !shopProv.isLoadingMore) {
        shopProv.fetchMoreProducts();
      }
    }

    // Refetch page 0 if scrolled to top and it was dropped
    if (_scrollController.position.pixels <= 150) {
      final raw = shopProv.rawProducts;
      final page0 = shopProv.pageCache[0];
      final firstRawId = raw.isNotEmpty ? raw.first.id : null;
      final firstPage0Id =
          (page0 != null && page0.isNotEmpty) ? page0.first.id : null;

      if (firstRawId != firstPage0Id) {
        shopProv.fetchPage(0);
      }
    }
  }

  /// Checks if viewport is not filled with content and loads more if needed.
  /// This handles the tablet/large screen case where initial content doesn't
  /// require scrolling, so the scroll listener never triggers pagination.
  void _checkViewportAndLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isInitialized) return;
      if (!_scrollController.hasClients) return;

      final shopProv = context.read<ShopMarketProvider>();
      if (shopProv.isLoading || shopProv.isLoadingMore || !shopProv.hasMore) {
        return;
      }

      final position = _scrollController.position;

      // If maxScrollExtent is 0 or very small, content doesn't fill viewport
      final viewportNotFilled = position.maxScrollExtent <= 50;
      final atOrNearBottom = position.pixels >= position.maxScrollExtent - 300;

      if ((viewportNotFilled || atOrNearBottom) &&
          shopProv.hasMore &&
          !shopProv.isLoadingMore) {
        shopProv.fetchMoreProducts();
      }
    });
  }

  void _unfocusKeyboard() {
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _submitSearch() async {
    _unfocusKeyboard();
    final term = _searchController.text.trim();
    if (term.isEmpty) return;

    _marketProvider.recordSearchTerm(term);

    if (mounted) {
      context.push('/search_results', extra: {'query': term});
      _searchController.clear();
    }
  }

  String _localizedSortOption(String option, AppLocalizations l10n) {
    switch (option) {
      case 'None':
        return l10n.none;
      case 'Alphabetical':
        return l10n.alphabetical;
      case 'Date':
        return l10n.date;
      case 'Price Low to High':
        return l10n.priceLowToHigh;
      case 'Price High to Low':
        return l10n.priceHighToLow;
      default:
        return option;
    }
  }

  void _showSortOptionsModal() {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(
          l10n.sortBy,
          style: TextStyle(
            color: textColor,
            fontFamily: 'Figtree',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: _sortOptions.map((option) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _applySortOption(option);
            },
            child: Text(
              _localizedSortOption(option, l10n),
              style: TextStyle(
                color: textColor,
                fontFamily: 'Figtree',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: textColor,
              fontFamily: 'Figtree',
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _applySortOption(String option) {
    if (!mounted) return;

    String code;
    switch (option) {
      case 'Alphabetical':
        code = 'alphabetical';
        break;
      case 'Price Low to High':
        code = 'price_asc';
        break;
      case 'Price High to Low':
        code = 'price_desc';
        break;
      case 'Date':
        code = 'date';
        break;
      default:
        code = 'date';
        break;
    }

    final shopProv = context.read<ShopMarketProvider>();
    shopProv.setSortOption(code);

    if (mounted) {
      setState(() => _selectedSortOption = option);
    }
  }

  Widget _buildFilterView() {
    // Add a safety check at the very beginning
    if (!mounted) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    // Don't build content until initialized
    if (!_isInitialized) {
      return _buildShimmerLoading(baseColor, highlightColor);
    }

    return Consumer<ShopMarketProvider>(
      builder: (context, marketProvider, child) {
        // Show shimmer only while actively loading
        if (marketProvider.isLoading) {
          return _buildShimmerLoading(baseColor, highlightColor);
        }

        final displayProducts = marketProvider.products;

        // Loading completed - show empty state if no products found
        if (displayProducts.isEmpty) {
          return _buildEmptyState();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkViewportAndLoadMoreIfNeeded();
        });

        return _buildProductsList(
          displayProducts,
          marketProvider,
        );
      },
    );
  }

  Widget _buildShimmerLoading(Color baseColor, Color highlightColor) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/empty-product.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noProductsFound,
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList(
  List<ProductSummary> displayProducts,
  ShopMarketProvider marketProvider,
) {
    return RefreshIndicator(
      onRefresh: () async {
        await marketProvider.refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 300 &&
              !marketProvider.isLoadingMore &&
              marketProvider.hasMore) {
            marketProvider.fetchMoreProducts();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            ProductListSliver(
              products: displayProducts,
              boostedProducts: const [],
              hasMore: marketProvider.hasMore,
              isLoadingMore: marketProvider.isLoadingMore,
              screenName: 'dynamic_market_screen',
              selectedColor:
                  _dynamicColors.isNotEmpty ? _dynamicColors.first : null,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList({
    required String displayText,
  }) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _unfocusKeyboard,
      child: Column(
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4.0, horizontal: 8.0),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.pink]),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: const Text(
                        'Nar24',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Filter button
                    GestureDetector(
                      onTap: () async {
                        final appliedCount = _dynamicBrands.length +
                            _dynamicColors.length +
                            _dynamicSubSubcategories.length +
                            (_minPrice != null || _maxPrice != null ? 1 : 0);
                        final hasApplied = appliedCount > 0;
                        final filterLabel = hasApplied
                            ? '${l10n.filter} ($appliedCount)'
                            : l10n.filter;

                        final result =
                            await context.push('/dynamic_filter', extra: {
                          'category': widget.category,
                          'subcategory': widget.selectedSubcategory,
                          'buyerCategory': widget.buyerCategory,
                          'initialBrands': _dynamicBrands,
                          'initialColors': _dynamicColors,
                          'initialSubSubcategories': _dynamicSubSubcategories,
                          'initialMinPrice': _minPrice,
                          'initialMaxPrice': _maxPrice,
                        });
                        if (result is Map<String, dynamic>) {
                          _handleDynamicFilterApplied(result);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_dynamicBrands.isNotEmpty ||
                                  _dynamicColors.isNotEmpty ||
                                  _dynamicSubSubcategories.isNotEmpty ||
                                  _minPrice != null ||
                                  _maxPrice != null)
                              ? Colors.orange
                              : Colors.transparent,
                          border: Border.all(
                            color: (_dynamicBrands.isNotEmpty ||
                                    _dynamicColors.isNotEmpty ||
                                    _dynamicSubSubcategories.isNotEmpty ||
                                    _minPrice != null ||
                                    _maxPrice != null)
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune,
                              size: 16,
                              color: (_dynamicBrands.isNotEmpty ||
                                      _dynamicColors.isNotEmpty ||
                                      _dynamicSubSubcategories.isNotEmpty ||
                                      _minPrice != null ||
                                      _maxPrice != null)
                                  ? Colors.white
                                  : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (_dynamicBrands.isNotEmpty ||
                                      _dynamicColors.isNotEmpty ||
                                      _dynamicSubSubcategories.isNotEmpty ||
                                      _minPrice != null ||
                                      _maxPrice != null)
                                  ? '${l10n.filter} (${_dynamicBrands.length + _dynamicColors.length + _dynamicSubSubcategories.length + (_minPrice != null || _maxPrice != null ? 1 : 0)})'
                                  : l10n.filter,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (_dynamicBrands.isNotEmpty ||
                                        _dynamicColors.isNotEmpty ||
                                        _dynamicSubSubcategories.isNotEmpty ||
                                        _minPrice != null ||
                                        _maxPrice != null)
                                    ? Colors.white
                                    : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sort button
                    GestureDetector(
                      onTap: _showSortOptionsModal,
                      child: Row(
                        children: [
                          if (_selectedSortOption != 'None')
                            Padding(
                              padding: const EdgeInsets.only(right: 4.0),
                              child: Text(
                                _localizedSortOption(_selectedSortOption, l10n),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Figtree',
                                ),
                              ),
                            ),
                          const Icon(CupertinoIcons.sort_down, size: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Active Filters Display
          Consumer<ShopMarketProvider>(
            builder: (context, provider, child) {
              if (!provider.hasDynamicFilters) return const SizedBox.shrink();

              return Container(
                width: double.infinity,
                margin:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_list,
                            color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${l10n.activeFilters ?? "Active Filters"} (${provider.activeFiltersCount})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _clearAllDynamicFilters,
                          child: Text(
                            l10n.clearAll ?? 'Clear All',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...provider.dynamicBrands.map((brand) =>
                            _buildFilterChip('${l10n.brand ?? "Brand"}: $brand',
                                () {
                              _removeSingleDynamicFilter(brand: brand);
                            })),
                        ...provider.dynamicColors.map((color) =>
                            _buildFilterChip(
                                '${l10n.color ?? "Color"}: ${ColorLocalization.localizeColorName(color, l10n)}',
                                () {
                              _removeSingleDynamicFilter(color: color);
                            })),
                        ...provider.dynamicSubSubcategories
                            .map((subSubcategory) {
                          // For Women/Men categories, these are actual sub-subcategories
                          // that need to be localized with their parent category and subcategory
                          final localizedName = (widget.buyerCategory ==
                                      'Women' ||
                                  widget.buyerCategory == 'Men')
                              ? AllInOneCategoryData.localizeSubSubcategoryKey(
                                  widget
                                      .category, // The product category (e.g., "Clothing & Fashion")
                                  widget
                                      .selectedSubcategory!, // The product subcategory (e.g., "Dresses")
                                  subSubcategory, // The sub-subcategory (e.g., "Casual Dresses")
                                  l10n,
                                )
                              : AllInOneCategoryData.localizeSubcategoryKey(
                                  widget.category,
                                  subSubcategory,
                                  l10n,
                                );

                          return _buildFilterChip(
                            '${l10n.categories ?? "Category"}: $localizedName',
                            () {
                              _removeSingleDynamicFilter(
                                  subSubcategory: subSubcategory);
                            },
                          );
                        }),
                        if (provider.minPrice != null ||
                            provider.maxPrice != null)
                          _buildFilterChip(
                            '${l10n.price ?? "Price"}: ${provider.minPrice?.toStringAsFixed(0) ?? '0'} - ${provider.maxPrice?.toStringAsFixed(0) ?? '∞'} TL',
                            () {
                              _removeSingleDynamicFilter(clearPrice: true);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Product View
          Expanded(
            child: _buildFilterView(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 14,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDynamicFilterApplied(Map<String, dynamic> result) async {
    if (!mounted) return;

    final brands = List<String>.from(result['brands'] as List<dynamic>? ?? []);
    final colors = List<String>.from(result['colors'] as List<dynamic>? ?? []);
    final subSubcategories =
        List<String>.from(result['subSubcategories'] as List<dynamic>? ?? []);
    final minPrice = result['minPrice'] as double?;
    final maxPrice = result['maxPrice'] as double?;

    setState(() {
      _dynamicBrands = brands;
      _dynamicColors = colors;
      _dynamicSubSubcategories = subSubcategories;
      _minPrice = minPrice;
      _maxPrice = maxPrice;
    });

    final shopProv = context.read<ShopMarketProvider>();
    await shopProv.setDynamicFilter(
      brands: brands,
      colors: colors,
      subSubcategories: subSubcategories,
      minPrice: minPrice,
      maxPrice: maxPrice,
      additive: false,
    );
  }

  Future<void> _removeSingleDynamicFilter({
    String? brand,
    String? color,
    String? subSubcategory,
    bool clearPrice = false,
  }) async {
    if (!mounted) return;

    setState(() {
      if (brand != null) _dynamicBrands.remove(brand);
      if (color != null) _dynamicColors.remove(color);
      if (subSubcategory != null)
        _dynamicSubSubcategories.remove(subSubcategory);
      if (clearPrice) {
        _minPrice = null;
        _maxPrice = null;
      }
    });

    final shopProv = context.read<ShopMarketProvider>();
    await shopProv.removeDynamicFilter(
      brand: brand,
      color: color,
      subSubcategory: subSubcategory,
      clearPrice: clearPrice,
    );
  }

  Future<void> _clearAllDynamicFilters() async {
    if (!mounted) return;

    setState(() {
      _dynamicBrands.clear();
      _dynamicColors.clear();
      _dynamicSubSubcategories.clear();
      _minPrice = null;
      _maxPrice = null;
    });

    final shopProv = context.read<ShopMarketProvider>();
    await shopProv.clearDynamicFilters();
  }

  Widget _buildSearchDelegateArea(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delegate = MarketSearchDelegate(
      marketProv: Provider.of<MarketProvider>(context, listen: false),
      historyProv: Provider.of<SearchHistoryProvider>(context, listen: false),
      searchProv: Provider.of<SearchProvider>(context, listen: false),
      l10n: l10n,
    );
    delegate.query = _searchController.text;
    return delegate.buildSuggestions(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSearching) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SearchProvider>(
            create: (_) => SearchProvider(),
          ),
          // ✅ FIXED: Provider handles auth internally
          ChangeNotifierProvider<SearchHistoryProvider>(
            create: (_) => SearchHistoryProvider(),
          ),
        ],
        child: Consumer2<SearchProvider, SearchHistoryProvider>(
          builder: (ctx, searchProv, historyProv, _) {
            return Scaffold(
              appBar: MarketAppBar(
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                onTakePhoto: () {},
                onSelectFromAlbum: () {},
                onSubmitSearch: _submitSearch,
                onBackPressed: _handleBackPressed,
                isSearching: _isSearching,
                onSearchStateChanged: (searching) {
                  _handleSearchStateChanged(searching, searchProv);
                },
              ),
              body: SafeArea(
                top: false,
                child: _buildSearchDelegateArea(ctx),
              ),
            );
          },
        ),
      );
    }

    // Normal dynamic market view
    return Scaffold(
      appBar: MarketAppBar(
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onTakePhoto: () {},
        onSelectFromAlbum: () {},
        onSubmitSearch: _submitSearch,
        onBackPressed: _handleBackPressed,
        isSearching: _isSearching,
        onSearchStateChanged: _handleSearchStateChanged,
      ),
      body: SafeArea(
        top: false,
        child: _buildProductList(
          displayText: widget.displayName ?? widget.selectedSubcategory ?? '',
        ),
      ),
    );
  }

  void _handleBackPressed() {
    if (!mounted) return;

    final shopProv = context.read<ShopMarketProvider>();
    shopProv.clearDynamicFilters();

    setState(() {
      _dynamicBrands.clear();
      _dynamicColors.clear();
      _dynamicSubSubcategories.clear();
      _minPrice = null;
      _maxPrice = null;
    });

    context.pop();
  }

  void _handleSearchStateChanged(bool searching, [SearchProvider? searchProv]) {
    if (!mounted) return;

    setState(() => _isSearching = searching);

    if (!searching) {
      _removeSearchListener();
      _searchController.clear();
      _searchFocusNode.unfocus();
      searchProv?.clear();
    } else if (searchProv != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setupSearchListener(searchProv);
        }
      });
    }
  }
}
