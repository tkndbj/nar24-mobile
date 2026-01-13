// File: dynamic_category_boxes_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/market_provider.dart'; // For search-related functions
import '../../providers/dynamic_category_boxes_provider.dart'; // New provider
import '../../providers/search_provider.dart';
import '../../widgets/product_list_sliver.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../widgets/dynamicscreens/market_app_bar.dart';
import 'package:go_router/go_router.dart';
import '../../route_observer.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/market_search_delegate.dart';
import '../../providers/search_history_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DynamicCategoryBoxesScreen extends StatefulWidget {
  final String category;
  final String? subcategory;
  final String? subsubcategory;
  final String? displayName;

  const DynamicCategoryBoxesScreen({
    Key? key,
    required this.category,
    this.subcategory,
    this.subsubcategory,
    this.displayName,
  }) : super(key: key);

  @override
  _DynamicCategoryBoxesScreenState createState() =>
      _DynamicCategoryBoxesScreenState();
}

class _DynamicCategoryBoxesScreenState extends State<DynamicCategoryBoxesScreen>
    with RouteAware {
  late final CategoryBoxesProvider _categoryBoxesProvider;
  late final MarketProvider _marketProvider;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  bool _isSearching = false;
  String _selectedSortOption = 'None';

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
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController()..addListener(_onScroll);

    _categoryBoxesProvider = context.read<CategoryBoxesProvider>();
    _marketProvider = context.read<MarketProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _categoryBoxesProvider.setCategory(widget.category);
      if (widget.subsubcategory != null) {
        await _categoryBoxesProvider.setSubSubcategory(widget.subsubcategory!);
      } else if (widget.subcategory != null) {
        await _categoryBoxesProvider.setSubcategory(widget.subcategory!);
      }
      await _categoryBoxesProvider.fetchBoosted();
    });
  }

  @override
  void didPopNext() {
    super.didPopNext();
    Future.microtask(() => FocusScope.of(context).unfocus());

    // Clear search UI and exit search mode
    _searchController.clear();
    _searchFocusNode.unfocus();

    if (_isSearching) {
      setState(() => _isSearching = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final prov = context.read<CategoryBoxesProvider>();
    // 1) Near bottom → load next page
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (prov.hasMore && !prov.isLoadingMore) {
        prov.fetchMoreProducts();
      }
    }
    // 2) If scrolled near top, check if page0 was pruned and re-fetch
    if (_scrollController.position.pixels <= 150) {
      final raw = prov.rawProducts;
      final page0 = prov.pageCache[0];
      final firstRawId = raw.isNotEmpty ? raw.first.id : null;
      final firstPage0Id =
          (page0 != null && page0.isNotEmpty) ? page0.first.id : null;

      if (firstRawId != firstPage0Id) {
        prov.fetchPage(0);
      }
    }
  }

  void _unfocusKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _submitSearch() {
    _unfocusKeyboard();
    final term = _searchController.text.trim();
    if (term.isEmpty) return Future.value();

    _marketProvider.recordSearchTerm(term);
    context.push('/search_results', extra: {'query': term});
    _searchController.clear();

    return Future.value();
  }

  List<Product> _getSortedProducts(List<Product> products) {
    final sorted = List<Product>.from(products);
    switch (_selectedSortOption) {
      case 'Alphabetical':
        sorted.sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        break;
      case 'Date':
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'Price Low to High':
        sorted.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'Price High to Low':
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'None':
      default:
        break;
    }
    return sorted;
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
              final prov = context.read<CategoryBoxesProvider>();
              prov.setSortOption(code);
              setState(() => _selectedSortOption = option);
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

  Widget _buildFilterView() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Consumer<CategoryBoxesProvider>(
      builder: (context, provider, child) {
        if (provider.products.isEmpty && !provider.isLoadingMore) {
          return _buildShimmerLoading(baseColor, highlightColor);
        }

        final displayProducts = provider.products;
        final effectiveBoosted = provider.boostedProducts;

        if (displayProducts.isEmpty) {
          return _buildEmptyState();
        }

        return _buildProductsList(
          displayProducts,
          effectiveBoosted,
          provider,
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
    List<Product> displayProducts,
    List<Product> boostedProducts,
    CategoryBoxesProvider provider,
  ) {    
    return RefreshIndicator(
      onRefresh: () async {
        // Preserve filters during refresh
        await provider.refresh();
        await provider.fetchBoosted();
        // Filters are automatically reapplied in the provider
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 300 &&
              !provider.isLoadingMore &&
              provider.hasMore) {
            provider.fetchMoreProducts();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            ProductListSliver(
              products: displayProducts,
              boostedProducts: boostedProducts,
              hasMore: provider.hasMore,
              isLoadingMore: provider.isLoadingMore,
              screenName: 'dynamic_category_boxes_screen',
              selectedColor: provider.dynamicColors.isNotEmpty
                  ? provider.dynamicColors.first
                  : null,
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
                Consumer<CategoryBoxesProvider>(
                  builder: (context, provider, child) {
                    final hasFilters = provider.dynamicBrands.isNotEmpty ||
                        provider.dynamicColors.isNotEmpty ||
                        provider.minPrice != null ||
                        provider.maxPrice != null;
                    final appliedCount = provider.dynamicBrands.length +
                        provider.dynamicColors.length +
                        (provider.minPrice != null || provider.maxPrice != null
                            ? 1
                            : 0);

                    return Row(
                      children: [
                        // Filter button
                        GestureDetector(
                          onTap: () async {
                            final result =
                                await context.push('/dynamic_filter', extra: {
                              'category': widget.category,
                              'subcategory': widget.subcategory,
                              'buyerCategory': null,
                              'initialBrands': provider.dynamicBrands,
                              'initialColors': provider.dynamicColors,
                              'initialSubSubcategories': <String>[],
                              'initialMinPrice': provider.minPrice,
                              'initialMaxPrice': provider.maxPrice,
                            });
                            if (result is Map<String, dynamic>) {
                              await context
                                  .read<CategoryBoxesProvider>()
                                  .setDynamicFilter(
                                    brands: List<String>.from(
                                        result['brands'] ?? []),
                                    colors: List<String>.from(
                                        result['colors'] ?? []),
                                    minPrice: result['minPrice'],
                                    maxPrice: result['maxPrice'],
                                    additive: false,
                                  );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  hasFilters ? Colors.orange : Colors.transparent,
                              border: Border.all(
                                color: hasFilters
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
                                  color: hasFilters
                                      ? Colors.white
                                      : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasFilters
                                      ? '${l10n.filter} ($appliedCount)'
                                      : l10n.filter,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: hasFilters
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
                                    _localizedSortOption(
                                        _selectedSortOption, l10n),
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
                    );
                  },
                ),
              ],
            ),
          ),

          // Active Filters Display
          Consumer<CategoryBoxesProvider>(
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
                        // Individual brand chips
                        ...provider.dynamicBrands.map((brand) =>
                            _buildFilterChip('${l10n.brand ?? "Brand"}: $brand',
                                () {
                              _removeSingleDynamicFilter(brand: brand);
                            })),
                        // Individual color chips
                        ...provider.dynamicColors.map((color) =>
                            _buildFilterChip('${l10n.color ?? "Color"}: $color',
                                () {
                              _removeSingleDynamicFilter(color: color);
                            })),
                        // Price range chip
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
    final brands = List<String>.from(result['brands'] as List<dynamic>? ?? []);
    final colors = List<String>.from(result['colors'] as List<dynamic>? ?? []);
    final minPrice = result['minPrice'] as double?;
    final maxPrice = result['maxPrice'] as double?;

    final prov = context.read<CategoryBoxesProvider>();
    await prov.setDynamicFilter(
      brands: brands,
      colors: colors,
      minPrice: minPrice,
      maxPrice: maxPrice,
      additive:
          false, // Replace existing filters when applying from filter screen
    );
  }

  Future<void> _removeSingleDynamicFilter({
    String? brand,
    String? color,
    bool clearPrice = false,
  }) async {
    final prov = context.read<CategoryBoxesProvider>();
    await prov.removeDynamicFilter(
      brand: brand,
      color: color,
      clearPrice: clearPrice,
    );
  }

  Future<void> _clearAllDynamicFilters() async {
    final prov = context.read<CategoryBoxesProvider>();
    await prov.clearDynamicFilters();
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
    // If in search mode, create local providers
    if (_isSearching) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SearchProvider>(
              create: (_) => SearchProvider()),
          ChangeNotifierProvider<SearchHistoryProvider>(
            create: (_) {
              final provider = SearchHistoryProvider();
              final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                provider.fetchSearchHistory(uid);
              });
              return provider;
            },
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
                onSearchStateChanged: _handleSearchStateChanged,
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

    // Normal category view
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
          displayText: widget.displayName ??
              widget.subsubcategory ??
              widget.subcategory ??
              widget.category,
        ),
      ),
    );
  }

  void _handleBackPressed() {
    final prov = context.read<CategoryBoxesProvider>();
    prov.clearDynamicFilters();
    context.pop();
  }

  void _handleSearchStateChanged(bool searching) {
    setState(() => _isSearching = searching);
    if (!searching) {
      // Clear the search controller text when exiting search mode
      _searchController.clear();
      _searchFocusNode.unfocus();
    } else {
      // Setup search listener when entering search mode
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void onTextChanged() {
          // Handle search text changes if needed
        }
        _searchController.addListener(onTextChanged);
      });
    }
  }
}
