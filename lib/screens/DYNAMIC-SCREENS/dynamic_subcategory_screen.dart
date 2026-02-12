import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/special_filter_provider_market.dart';
import '../../providers/market_provider.dart';
import '../../widgets/dynamicscreens/market_app_bar.dart';
import '../../widgets/product_list_sliver.dart';
import '../../widgets/product_card_shimmer.dart';
import '../../models/product_summary.dart';
import 'dart:async';
import '../../widgets/market_search_delegate.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/search_provider.dart';

class DynamicSubcategoryScreen extends StatefulWidget {
  final String category;
  final String subcategoryId;
  final String subcategoryName;
  final String? gender;
  final bool isGenderFilter;

  const DynamicSubcategoryScreen({
    Key? key,
    required this.category,
    required this.subcategoryId,
    required this.subcategoryName,
    this.gender,
    this.isGenderFilter = false,
  }) : super(key: key);

  @override
  DynamicSubcategoryScreenState createState() =>
      DynamicSubcategoryScreenState();
}

class DynamicSubcategoryScreenState extends State<DynamicSubcategoryScreen> {
  late SpecialFilterProviderMarket _specialFilterProvider;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _dynamicBrand;
  List<String> _dynamicColors = [];
  String? _dynamicSubsubcategory;
  String _searchTerm = '';
  bool _isSearching = false;
  late final MarketProvider _marketProvider;
  String _selectedSortOption = 'None';
  VoidCallback? _searchTextListener;

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
    _specialFilterProvider =
        Provider.of<SpecialFilterProviderMarket>(context, listen: false);
    _marketProvider = Provider.of<MarketProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isGenderFilter == true) {
        _specialFilterProvider.fetchProducts(
          filterType: widget.category,
          page: 0,
          limit: 20,
        );
      } else {
        // ✅ FIX: Pass gender parameter for Women/Men View All navigation
        _specialFilterProvider.fetchSubcategoryProducts(
          widget.category,
          widget.subcategoryId,
          gender: widget.gender,
        );
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _removeSearchListener(); // ✅ ADD: Clean up search listener
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  void _handleSearchStateChanged(bool searching, [SearchProvider? searchProv]) {
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

  Future<void> _refreshProducts() async {
    // ✅ FIX: Pass gender parameter for Women/Men View All refresh
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
      gender: widget.gender,
    );
  }

  Future<void> _submitSearch() async {
    _searchFocusNode.unfocus();
    final term = _searchController.text.trim();
    if (term.isEmpty) return;

    setState(() {
      _searchTerm = term;
    });

    _marketProvider.recordSearchTerm(term);
    _marketProvider.clearSearchCache();
    _marketProvider.resetSearch(triggerFilter: false);

    context.push('/search_results', extra: {'query': term});
  }

  Future<void> _handleDynamicFilterApplied(Map<String, dynamic> filters) async {
    setState(() {
      _dynamicBrand = filters['brand'] as String?;
      _dynamicColors = List<String>.from(filters['colors'] as List<dynamic>);
      _dynamicSubsubcategory = filters['subsubcategory'] as String?;
    });
    _specialFilterProvider.setDynamicFilter(
      brand: _dynamicBrand,
      colors: _dynamicColors,
      subsubcategory: _dynamicSubsubcategory,
    );
    // ✅ FIX: Pass gender parameter for Women/Men View All filter
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
      gender: widget.gender,
    );
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

  Future<void> _applySortOption(String option) async {
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

    if (mounted) {
      setState(() => _selectedSortOption = option);
    }

    _specialFilterProvider.setSubcategorySortOption(code);

    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
    );
  }

  Widget _buildFilterView() {
    return Consumer<SpecialFilterProviderMarket>(
      builder: (context, prov, child) {
        List<ProductSummary> allProducts;

        if (widget.isGenderFilter == true) {
          allProducts = prov.getProducts(widget.category);
        } else {
          // ✅ FIX: Pass gender for Women/Men View All
          allProducts = prov.getSubcategoryProductsById(
            widget.category,
            widget.subcategoryId,
            gender: widget.gender,
          );
        }

        // ✅ Server-side filtering is already applied by the provider
        // No client-side filtering needed - Firestore query handles all filters
        final displayProducts = allProducts;
        final boosted = displayProducts.where((p) => p.isBoosted).toList();
        final normal = displayProducts.where((p) => !p.isBoosted).toList();
        // ✅ FIX: Pass gender for Women/Men View All
        final hasMore = prov.hasMoreSubcategory(
          widget.category,
          widget.subcategoryId,
          gender: widget.gender,
        );

        return NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollEndNotification &&
                hasMore &&
                // ✅ FIX: Pass gender for Women/Men View All
                !prov.isLoadingMoreSubcategory(
                  widget.category,
                  widget.subcategoryId,
                  gender: widget.gender,
                ) &&
                notif.metrics.pixels >= notif.metrics.maxScrollExtent * 0.9) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 200), () {
                // Server-side filtering is already applied - just fetch more
                prov.fetchMoreSubcategoryProducts(
                  widget.category,
                  widget.subcategoryId,
                );
              });
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              if (displayProducts.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  sliver: ProductListSliver(
                    products: normal,
                    boostedProducts: boosted,
                    hasMore: hasMore,
                    screenName: 'dynamic_subcategory_screen',
                    // ✅ FIX: Pass gender for Women/Men View All
                    isLoadingMore: prov.isLoadingMoreSubcategory(
                      widget.category,
                      widget.subcategoryId,
                      gender: widget.gender,
                    ),
                    selectedColor:
                        _dynamicColors.isNotEmpty ? _dynamicColors.first : null,
                  ),
                ),
              if (displayProducts.isEmpty)
                SliverFillRemaining(
                  child: Center(
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
                          AppLocalizations.of(context).noProductsFound,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 20 + MediaQuery.of(context).padding.bottom,
                ),
              ),
            ],
          ),
        );
      },
    );
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
    final l10n = AppLocalizations.of(context);

    // If in search mode, create local providers
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
                onBackPressed: () {
                  setState(() {
                    _dynamicBrand = null;
                    _dynamicColors = [];
                    _dynamicSubsubcategory = null;
                    _searchTerm = '';
                  });
                  _specialFilterProvider.setDynamicFilter(
                    brand: null,
                    colors: [],
                    subsubcategory: null,
                  );
                  _specialFilterProvider.fetchSubcategoryProducts(
                    widget.category,
                    widget.subcategoryId,
                  );
                  Navigator.of(context).pop();
                },
                isSearching: _isSearching,
                onSearchStateChanged: (searching) {
                  _handleSearchStateChanged(searching, searchProv);
                },
              ),
              body: _buildSearchDelegateArea(ctx),
            );
          },
        ),
      );
    }

    // Normal subcategory view
    return Scaffold(
      appBar: MarketAppBar(
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onTakePhoto: () {},
        onSelectFromAlbum: () {},
        onSubmitSearch: _submitSearch,
        onBackPressed: () {
          setState(() {
            _dynamicBrand = null;
            _dynamicColors = [];
            _dynamicSubsubcategory = null;
            _searchTerm = '';
          });
          _specialFilterProvider.setDynamicFilter(
            brand: null,
            colors: [],
            subsubcategory: null,
          );
          // ✅ FIX: Pass gender for Women/Men View All
          _specialFilterProvider.fetchSubcategoryProducts(
            widget.category,
            widget.subcategoryId,
            gender: widget.gender,
          );
          Navigator.of(context).pop();
        },
        isSearching: _isSearching,
        onSearchStateChanged: _handleSearchStateChanged,
      ),
      body: Consumer<SpecialFilterProviderMarket>(
        builder: (context, prov, _) {
          // ✅ FIX: Pass gender for Women/Men View All
          final isLoading = prov.isLoadingSubcategory(
            widget.category,
            widget.subcategoryId,
            gender: widget.gender,
          );

          if (isLoading) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 6,
                itemBuilder: (_, __) => const ProductCardShimmer(
                  portraitImageHeight: 150,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshProducts,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      // Subcategory name
                      Expanded(
                        child: Text(
                          widget.subcategoryName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Filter button
                      Builder(
                        builder: (context) {
                          final l10n = AppLocalizations.of(context);
                          // ✅ FIX: Include category filter in count
                          final appliedCount = (_dynamicBrand != null ? 1 : 0) +
                              _dynamicColors.length +
                              (_dynamicSubsubcategory != null &&
                                      _dynamicSubsubcategory!.isNotEmpty
                                  ? 1
                                  : 0);
                          final hasApplied = appliedCount > 0;
                          final filterLabel = hasApplied
                              ? '${l10n.filter} ($appliedCount)'
                              : l10n.filter;

                          return GestureDetector(
                            onTap: () async {
                              final result = await context
                                  .push('/dynamic_subcategory_filter', extra: {
                                'category': widget.category,
                                'subcategoryId': widget.subcategoryId,
                                'subcategoryName': widget.subcategoryName,
                                'initialBrand': _dynamicBrand,
                                'initialColors': _dynamicColors,
                                'initialSubsubcategory': _dynamicSubsubcategory,
                                'isGenderFilter':
                                    widget.isGenderFilter, // Add this
                                'gender': widget.gender, // Add this
                              });
                              if (result is Map<String, dynamic>) {
                                _handleDynamicFilterApplied(result);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: hasApplied
                                    ? Colors.orange
                                    : Colors.transparent,
                                border: Border.all(
                                  color: hasApplied
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
                                    color: hasApplied
                                        ? Colors.white
                                        : (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.black),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    filterLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: hasApplied
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
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Sort button
                      Builder(
                        builder: (context) {
                          final l10n = AppLocalizations.of(context);
                          return GestureDetector(
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
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildFilterView(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
