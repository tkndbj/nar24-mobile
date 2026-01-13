import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/special_filter_provider_market.dart';
import '../../providers/market_provider.dart';
import '../../widgets/dynamicscreens/market_app_bar.dart';
import '../../widgets/product_list_sliver.dart';
import '../../models/product.dart';
import 'dart:async';
import '../../widgets/market_search_delegate.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/search_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final Map<String, List<Product>> _subsubcategoryCache = {};
  bool _isFetchingMoreForSubsubcategory = false;
  bool _isSearching = false;
  late final MarketProvider _marketProvider;
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
        _specialFilterProvider.fetchSubcategoryProducts(
          widget.category,
          widget.subcategoryId,
        );
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshProducts() async {
    _subsubcategoryCache.clear();
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
    );
  }

  Future<void> _submitSearch() async {
    _searchFocusNode.unfocus();
    final term = _searchController.text.trim();
    if (term.isEmpty) return;

    setState(() {
      _searchTerm = term;
      _subsubcategoryCache.clear();
    });

    _marketProvider.recordSearchTerm(term);
    _marketProvider.clearSearchCache();
    _marketProvider.resetSearch(triggerFilter: false);

    context.push('/search_results', extra: {'query': term});
  }

  Future<void> _fetchAllSubsubcategoryProducts() async {
    if (_dynamicSubsubcategory == null || _isFetchingMoreForSubsubcategory) {
      return;
    }
    _isFetchingMoreForSubsubcategory = true;
    try {
      while (_specialFilterProvider.hasMoreSubcategory(
          widget.category, widget.subcategoryId)) {
        await _specialFilterProvider.fetchMoreSubcategoryProducts(
          widget.category,
          widget.subcategoryId,
        );
        final products = _specialFilterProvider.getSubcategoryProductsById(
          widget.category,
          widget.subcategoryId,
        );
        final cacheKey =
            '${widget.category}|${widget.subcategoryId}|$_dynamicSubsubcategory';
        _subsubcategoryCache[cacheKey] = products
            .where((p) => p.subsubcategory == _dynamicSubsubcategory)
            .toList();
        setState(() {});
      }
    } finally {
      _isFetchingMoreForSubsubcategory = false;
    }
  }

  Future<void> _handleDynamicFilterApplied(Map<String, dynamic> filters) async {
    setState(() {
      _dynamicBrand = filters['brand'] as String?;
      _dynamicColors = List<String>.from(filters['colors'] as List<dynamic>);
      _dynamicSubsubcategory = filters['subsubcategory'] as String?;
      _subsubcategoryCache.clear();
    });
    _specialFilterProvider.setDynamicFilter(
      brand: _dynamicBrand,
      colors: _dynamicColors,
      subsubcategory: _dynamicSubsubcategory,
    );
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
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
        List<Product> allProducts;

        if (widget.isGenderFilter == true) {
          allProducts = prov.getProducts(widget.category);
        } else {
          allProducts = prov.getSubcategoryProductsById(
            widget.category,
            widget.subcategoryId,
          );
        }

        List<Product> filteredProducts = allProducts;

        if (_dynamicBrand != null && _dynamicBrand!.isNotEmpty) {
          filteredProducts = filteredProducts
              .where((p) => p.brandModel == _dynamicBrand)
              .toList();
        }

        if (_dynamicColors.isNotEmpty) {
          filteredProducts = filteredProducts.where((p) {
            if (p.availableColors.isEmpty) {
              return false;
            }
            return _dynamicColors.any(
                (selectedColor) => p.availableColors.contains(selectedColor));
          }).toList();
        }

        if (_dynamicSubsubcategory != null &&
            _dynamicSubsubcategory!.isNotEmpty) {
          filteredProducts = filteredProducts
              .where((p) => p.subsubcategory == _dynamicSubsubcategory)
              .toList();
        }

        final displayProducts = filteredProducts;
        final boosted = displayProducts.where((p) => p.isBoosted).toList();
        final normal = displayProducts.where((p) => !p.isBoosted).toList();
        final hasMore = prov.hasMoreSubcategory(
          widget.category,
          widget.subcategoryId,
        );

        return NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollEndNotification &&
                hasMore &&
                !prov.isLoadingMoreSubcategory(
                  widget.category,
                  widget.subcategoryId,
                ) &&
                notif.metrics.pixels >= notif.metrics.maxScrollExtent * 0.9) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 200), () {
                prov
                    .fetchMoreSubcategoryProducts(
                  widget.category,
                  widget.subcategoryId,
                )
                    .then((_) {
                  if (_dynamicSubsubcategory != null) {
                    final updatedProducts = prov.getSubcategoryProductsById(
                      widget.category,
                      widget.subcategoryId,
                    );
                    final cacheKey =
                        '${widget.category}|${widget.subcategoryId}|$_dynamicSubsubcategory';
                    _subsubcategoryCache[cacheKey] = updatedProducts
                        .where(
                            (p) => p.subsubcategory == _dynamicSubsubcategory)
                        .toList();
                    setState(() {});
                  }
                });
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
                    isLoadingMore: prov.isLoadingMoreSubcategory(
                      widget.category,
                      widget.subcategoryId,
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
                            color: Theme.of(context).brightness == Brightness.dark
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
                onSearchStateChanged: (bool searching) {
                  setState(() => _isSearching = searching);
                  if (!searching) {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                    if (searchProv.mounted) {
                      searchProv.clear();
                    }
                  } else {
                    // Setup listener when entering search mode
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      void onTextChanged() {
                        if (searchProv.mounted) {
                          searchProv.updateTerm(
                            _searchController.text,
                            l10n: AppLocalizations.of(context),
                          );
                        }
                      }

                      _searchController.addListener(onTextChanged);
                    });
                  }
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
          _specialFilterProvider.fetchSubcategoryProducts(
            widget.category,
            widget.subcategoryId,
          );
          Navigator.of(context).pop();
        },
        isSearching: _isSearching,
        onSearchStateChanged: (bool searching) {
          setState(() => _isSearching = searching);
        },
      ),
      body: Consumer<SpecialFilterProviderMarket>(
        builder: (context, prov, _) {
          final isLoading = prov.isLoadingSubcategory(
            widget.category,
            widget.subcategoryId,
          );

          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
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
                          final appliedCount = (_dynamicBrand != null ? 1 : 0) +
                              _dynamicColors.length;
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
