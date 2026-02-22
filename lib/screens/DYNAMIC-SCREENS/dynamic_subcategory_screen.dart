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
import '../../utils/color_localization.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../constants/all_in_one_category_data.dart';

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
  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  List<String> _dynamicSubSubcategories = [];
  Map<String, List<String>> _dynamicSpecFilters = {};
  double? _minPrice;
  double? _maxPrice;
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
        _specialFilterProvider.fetchSubcategoryProducts(
          widget.category,
          widget.subcategoryId,
          gender: widget.gender,
        );
      }
      // Fetch spec facets in parallel
      _specialFilterProvider.fetchSpecFacets(
        category: widget.category,
        subcategoryId: widget.subcategoryId,
        gender: widget.gender,
      );
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

  Future<void> _handleDynamicFilterApplied(Map<String, dynamic> result) async {
    final brands = List<String>.from(result['brands'] as List<dynamic>? ?? []);
    final colors = List<String>.from(result['colors'] as List<dynamic>? ?? []);
    final subSubcategories = List<String>.from(
        result['subSubcategories'] as List<dynamic>? ?? []);
    final rawSpecFilters = result['specFilters'] as Map<String, List<String>>? ?? {};
    final specFilters = rawSpecFilters.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    );
    final minPrice = result['minPrice'] as double?;
    final maxPrice = result['maxPrice'] as double?;

    setState(() {
      _dynamicBrands = brands;
      _dynamicColors = colors;
      _dynamicSubSubcategories = subSubcategories;
      _dynamicSpecFilters = specFilters;
      _minPrice = minPrice;
      _maxPrice = maxPrice;
    });

    _specialFilterProvider.setDynamicFilter(
      brands: brands,
      colors: colors,
      subsubcategory: subSubcategories.isNotEmpty ? subSubcategories.first : null,
      specFilters: specFilters,
    );
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
      gender: widget.gender,
    );
  }

  Future<void> _removeSingleDynamicFilter({
    String? brand,
    String? color,
    String? subSubcategory,
    String? specField,
    String? specValue,
    bool clearPrice = false,
  }) async {
    if (!mounted) return;

    setState(() {
      if (brand != null) _dynamicBrands.remove(brand);
      if (color != null) _dynamicColors.remove(color);
      if (subSubcategory != null) _dynamicSubSubcategories.remove(subSubcategory);
      if (specField != null && specValue != null) {
        final list = _dynamicSpecFilters[specField];
        if (list != null) {
          list.remove(specValue);
          if (list.isEmpty) _dynamicSpecFilters.remove(specField);
        }
      }
      if (clearPrice) {
        _minPrice = null;
        _maxPrice = null;
      }
    });

    _specialFilterProvider.setDynamicFilter(
      brands: _dynamicBrands,
      colors: _dynamicColors,
      subsubcategory: _dynamicSubSubcategories.isNotEmpty
          ? _dynamicSubSubcategories.first
          : null,
      specFilters: _dynamicSpecFilters,
    );
    if (specField != null) {
      _specialFilterProvider.removeDynamicSpecFilter(specField, specValue!);
    }
    await _specialFilterProvider.fetchSubcategoryProducts(
      widget.category,
      widget.subcategoryId,
      gender: widget.gender,
    );
  }

  Future<void> _clearAllDynamicFilters() async {
    if (!mounted) return;

    setState(() {
      _dynamicBrands.clear();
      _dynamicColors.clear();
      _dynamicSubSubcategories.clear();
      _dynamicSpecFilters.clear();
      _minPrice = null;
      _maxPrice = null;
    });

    _specialFilterProvider.setDynamicFilter(
      brands: [],
      colors: [],
      subsubcategory: null,
      specFilters: {},
    );
    _specialFilterProvider.clearDynamicSpecFilters();
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
      gender: widget.gender,
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
                    _dynamicBrands.clear();
                    _dynamicColors = [];
                    _dynamicSubSubcategories.clear();
                    _dynamicSpecFilters.clear();
                    _minPrice = null;
                    _maxPrice = null;
                    _searchTerm = '';
                  });
                  _specialFilterProvider.setDynamicFilter(
                    brands: [],
                    colors: [],
                    subsubcategory: null,
                    specFilters: {},
                  );
                  _specialFilterProvider.clearDynamicSpecFilters();
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
            _dynamicBrands.clear();
            _dynamicColors = [];
            _dynamicSubSubcategories.clear();
            _dynamicSpecFilters.clear();
            _minPrice = null;
            _maxPrice = null;
            _searchTerm = '';
          });
          _specialFilterProvider.setDynamicFilter(
            brands: [],
            colors: [],
            subsubcategory: null,
            specFilters: {},
          );
          _specialFilterProvider.clearDynamicSpecFilters();
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
                          int specFilterCount = 0;
                          for (final vals in _dynamicSpecFilters.values) {
                            specFilterCount += vals.length;
                          }
                          final appliedCount = _dynamicBrands.length +
                              _dynamicColors.length +
                              _dynamicSubSubcategories.length +
                              specFilterCount +
                              (_minPrice != null || _maxPrice != null ? 1 : 0);
                          final hasApplied = appliedCount > 0;
                          final filterLabel = hasApplied
                              ? '${l10n.filter} ($appliedCount)'
                              : l10n.filter;

                          return GestureDetector(
                            onTap: () async {
                              final result = await context
                                  .push('/dynamic_filter', extra: {
                                'category': widget.category,
                                'subcategory': widget.subcategoryId,
                                'buyerCategory': (widget.gender == 'Women' || widget.gender == 'Men') ? widget.gender : null,
                                'initialBrands': _dynamicBrands,
                                'initialColors': _dynamicColors,
                                'initialSubSubcategories': _dynamicSubSubcategories,
                                'initialSpecFilters': _dynamicSpecFilters,
                                'availableSpecFacets': _specialFilterProvider.specFacets,
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
                // Active Filters Display
                if (_dynamicBrands.isNotEmpty ||
                    _dynamicColors.isNotEmpty ||
                    _dynamicSubSubcategories.isNotEmpty ||
                    _dynamicSpecFilters.isNotEmpty ||
                    _minPrice != null ||
                    _maxPrice != null)
                  _buildActiveFiltersDisplay(),

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

  Widget _buildActiveFiltersDisplay() {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, color: Colors.purple, size: 16),
              const SizedBox(width: 8),
              Text(
                '${l10n.activeFilters} (${_dynamicBrands.length + _dynamicColors.length + _dynamicSubSubcategories.length + _dynamicSpecFilters.values.fold(0, (sum, v) => sum + v.length) + (_minPrice != null || _maxPrice != null ? 1 : 0)})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.purple,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearAllDynamicFilters,
                child: Text(
                  l10n.clearAll,
                  style: const TextStyle(
                    color: Colors.purple,
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
              ..._dynamicBrands.map((brand) => _buildFilterChip(
                    '${l10n.brand}: $brand',
                    () => _removeSingleDynamicFilter(brand: brand),
                  )),
              ..._dynamicColors.map((color) => _buildFilterChip(
                    '${l10n.color}: ${ColorLocalization.localizeColorName(color, l10n)}',
                    () => _removeSingleDynamicFilter(color: color),
                  )),
              ..._dynamicSubSubcategories.map((value) {
                final isSubcategoryLevel =
                    widget.subcategoryId.isEmpty;
                final localizedValue = isSubcategoryLevel
                    ? AllInOneCategoryData.localizeSubcategoryKey(
                        widget.category, value, l10n)
                    : AllInOneCategoryData.localizeSubSubcategoryKey(
                        widget.category, widget.subcategoryId, value, l10n);
                return _buildFilterChip(
                  '${l10n.category}: $localizedValue',
                  () => _removeSingleDynamicFilter(subSubcategory: value),
                );
              }),
              ..._dynamicSpecFilters.entries.expand((entry) {
                final fieldTitle = AttributeLocalizationUtils
                    .getLocalizedAttributeTitle(entry.key, l10n);
                return entry.value.map((value) {
                  final localizedValue = AttributeLocalizationUtils
                      .getLocalizedSingleValue(entry.key, value, l10n);
                  return _buildFilterChip(
                    '$fieldTitle: $localizedValue',
                    () => _removeSingleDynamicFilter(
                        specField: entry.key, specValue: value),
                  );
                });
              }),
              if (_minPrice != null || _maxPrice != null)
                _buildFilterChip(
                  '${l10n.price}: ${_minPrice?.toStringAsFixed(0) ?? '0'} - ${_maxPrice?.toStringAsFixed(0) ?? '∞'} TL',
                  () => _removeSingleDynamicFilter(clearPrice: true),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.purple,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: Colors.purple),
          ),
        ],
      ),
    );
  }
}
