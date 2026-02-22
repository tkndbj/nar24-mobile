// lib/screens/search_results_screen.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import '../providers/market_provider.dart';
import '../providers/search_results_provider.dart';
import '../models/product_summary.dart';
import '../widgets/product_list_sliver.dart';
import '../generated/l10n/app_localizations.dart';
import '../utils/attribute_localization_utils.dart';
import '../utils/color_localization.dart';

class SearchResultsScreen extends StatefulWidget {
  final String query;
  const SearchResultsScreen({Key? key, required this.query}) : super(key: key);

  @override
  _SearchResultsScreenState createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Core dependencies
  late final MarketProvider _marketProvider;

  // State management
  final List<String> _filterTypes = [
    '',
    'deals',
  ];

  String _currentFilter = '';
  int _currentFilterIndex = 0;

  // Pagination state
  final List<ProductSummary> _allSearchResults = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasError = false;

  // Sort options
  final List<String> _sortOptions = [
    'None',
    'Alphabetical',
    'Date',
    'Price Low to High',
    'Price High to Low'
  ];
  String _sortOption = 'None';

  // Dynamic filter state (local mirror for UI)
  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  Map<String, List<String>> _dynamicSpecFilters = {};
  double? _minPrice;
  double? _maxPrice;

  // Controllers
  late final PageController _pageController;
  final ScrollController _pillScroll = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  // Debouncing
  Timer? _debounce;

  // Initialization flag
  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _currentFilter = _filterTypes[0];
    _setupScrollListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _marketProvider = Provider.of<MarketProvider>(context, listen: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchInitialResults();
        // Fetch spec facets in parallel for the search query
        final provider = context.read<SearchResultsProvider>();
        provider.fetchSpecFacets(widget.query);
      });
      _didInit = true;
    }
  }

  @override
  void didUpdateWidget(covariant SearchResultsScreen old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _resetAndFetch();
      // Re-fetch facets for new query
      final provider = context.read<SearchResultsProvider>();
      provider.fetchSpecFacets(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageController.dispose();
    _pillScroll.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _mainScrollController.addListener(() {
      if (!_mainScrollController.hasClients) return;
      if (_mainScrollController.positions.length != 1) return;

      final position = _mainScrollController.position;
      if (position.pixels >= position.maxScrollExtent - 200) {
        _loadMoreIfNeeded();
      }
    });
  }

  void _loadMoreIfNeeded() {
    if (_hasMore && !_isLoading) {
      if (_debounce?.isActive ?? false) return;
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _fetchMoreResults();
      });
    }
  }

  void _checkViewportAndLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isLoading || !_hasMore) return;
      if (!_mainScrollController.hasClients) return;
      if (_mainScrollController.positions.length != 1) return;

      final position = _mainScrollController.position;
      final viewportNotFilled = position.maxScrollExtent <= 50;
      final atOrNearBottom = position.pixels >= position.maxScrollExtent - 200;

      if ((viewportNotFilled || atOrNearBottom) && _hasMore && !_isLoading) {
        _fetchMoreResults();
      }
    });
  }

  Future<void> _fetchInitialResults() async {
    await _fetchResults(reset: true);
  }

  Future<void> _resetAndFetch() async {
    _allSearchResults.clear();
    _currentPage = 0;
    _hasMore = true;
    _hasError = false;

    final provider = context.read<SearchResultsProvider>();
    provider.clearProducts();

    await _fetchResults(reset: true);
  }

  Future<void> _fetchMoreResults() async {
    if (_isLoading || !_hasMore) return;
    await _fetchResults(reset: false);
  }

  Future<void> _fetchResults({required bool reset}) async {
    if (_isLoading) return;

    final l10n = AppLocalizations.of(context);
    final provider = context.read<SearchResultsProvider>();

    // Connectivity check
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noInternet)),
      );
      if (reset) {
        setState(() => _hasError = true);
      }
      return;
    }

    if (reset) {
      _allSearchResults.clear();
      _currentPage = 0;
      _hasMore = true;
      _hasError = false;
      provider.clearProducts();
    }

    setState(() => _isLoading = true);

    try {
      List<ProductSummary> pageResults;

      // Use Typesense when any filters or non-default sort are active.
      // Typesense handles arbitrary filter+sort combos without composite
      // indexes, ensuring correct server-side ordering.
      final useTypesense =
          provider.hasDynamicFilters || provider.sortOption != 'None';

      if (useTypesense) {
        // Filtered / sorted path — shop_products via Typesense
        pageResults = await provider.fetchFilteredPage(
          query: widget.query,
          page: _currentPage,
          hitsPerPage: 50,
        );
      } else {
        // Unfiltered path — both indexes via MarketProvider
        pageResults = await _marketProvider.searchOnly(
          query: widget.query,
          page: _currentPage,
          hitsPerPage: 50,
          l10n: l10n,
          filterType: '',
        );
      }

      if (!mounted) return;

      if (reset) {
        _allSearchResults.clear();
        _allSearchResults.addAll(pageResults);
        provider.setRawProducts(_allSearchResults);
      } else {
        _allSearchResults.addAll(pageResults);
        provider.addMoreProducts(pageResults);
      }
      _currentPage++;

      _hasMore = pageResults.length == 50;
      _hasError = false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching search results: $e');
      }
      if (reset && mounted) {
        setState(() => _hasError = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (reset && _mainScrollController.hasClients) {
      if (_mainScrollController.positions.length == 1) {
        _mainScrollController.jumpTo(0);
      }
    }

    _checkViewportAndLoadMoreIfNeeded();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DYNAMIC FILTER HANDLERS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _handleDynamicFilterApplied(Map<String, dynamic> result) async {
    if (!mounted) return;

    final brands = List<String>.from(result['brands'] as List<dynamic>? ?? []);
    final colors = List<String>.from(result['colors'] as List<dynamic>? ?? []);
    final rawSpecFilters =
        result['specFilters'] as Map<String, List<String>>? ?? {};
    final specFilters = rawSpecFilters.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    );
    final minPrice = result['minPrice'] as double?;
    final maxPrice = result['maxPrice'] as double?;

    setState(() {
      _dynamicBrands = brands;
      _dynamicColors = colors;
      _dynamicSpecFilters = specFilters;
      _minPrice = minPrice;
      _maxPrice = maxPrice;
    });

    final provider = context.read<SearchResultsProvider>();
    provider.setDynamicFilter(
      brands: brands,
      colors: colors,
      specFilters: specFilters,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );

    await _resetAndFetch();
  }

  Future<void> _removeSingleDynamicFilter({
    String? brand,
    String? color,
    String? specField,
    String? specValue,
    bool clearPrice = false,
  }) async {
    if (!mounted) return;

    setState(() {
      if (brand != null) _dynamicBrands.remove(brand);
      if (color != null) _dynamicColors.remove(color);
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

    final provider = context.read<SearchResultsProvider>();
    provider.removeDynamicFilter(
      brand: brand,
      color: color,
      specField: specField,
      specValue: specValue,
      clearPrice: clearPrice,
    );

    await _resetAndFetch();
  }

  Future<void> _clearAllDynamicFilters() async {
    if (!mounted) return;

    setState(() {
      _dynamicBrands.clear();
      _dynamicColors.clear();
      _dynamicSpecFilters.clear();
      _minPrice = null;
      _maxPrice = null;
    });

    final provider = context.read<SearchResultsProvider>();
    provider.clearDynamicFilters();

    await _resetAndFetch();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILTER / SORT UI
  // ──────────────────────────────────────────────────────────────────────────

  void _onFilterTap(String filterKey, int index) {
    if (filterKey == _currentFilter) return;
    if (!mounted) return;

    setState(() {
      _currentFilter = filterKey;
      _currentFilterIndex = index;
    });

    final provider = context.read<SearchResultsProvider>();
    provider.setFilter(filterKey.isEmpty ? null : filterKey);

    _pageController.jumpToPage(index);
    _scrollFilterBar(index);
  }

  void _scrollFilterBar(int index) {
    if (!_pillScroll.hasClients) return;
    if (_pillScroll.positions.length != 1) return;

    const pillWidth = 80.0;
    final screenW = MediaQuery.of(context).size.width;
    final offset = index * pillWidth - screenW / 2 + pillWidth / 2;

    final position = _pillScroll.position;
    _pillScroll.animateTo(
      offset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onSortChanged(String? sortOption) {
    if (sortOption == null || sortOption == _sortOption) return;
    if (!mounted) return;

    setState(() => _sortOption = sortOption);

    final provider = context.read<SearchResultsProvider>();
    provider.setSortOption(sortOption);

    // Always re-fetch: non-default sort routes through Typesense for
    // correct server-side ordering; default sort restores relevance path.
    _resetAndFetch();
  }

  String _localizedSortLabel(String opt, AppLocalizations l) {
    switch (opt) {
      case 'None':
        return l.none;
      case 'Alphabetical':
        return l.alphabetical;
      case 'Date':
        return l.date;
      case 'Price Low to High':
        return l.priceLowToHigh;
      case 'Price High to Low':
        return l.priceHighToLow;
      default:
        return opt;
    }
  }

  String _localizedFilterLabel(String key, AppLocalizations l) {
    switch (key) {
      case 'deals':
        return l.deals;
      case 'boosted':
        return l.boosted;
      case 'trending':
        return l.trending;
      case 'fiveStar':
        return l.fiveStar;
      case 'bestSellers':
        return l.bestSellers;
      default:
        return l.all;
    }
  }

  Widget _buildFilterBar(AppLocalizations l10n) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        controller: _pillScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _filterTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (ctx, i) {
          final key = _filterTypes[i];
          final isAll = key.isEmpty;
          final label = isAll ? l10n.all : _localizedFilterLabel(key, l10n);
          final isSelected = key == _currentFilter;

          return InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => _onFilterTap(key, i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.orange : Colors.transparent,
                border: Border.all(
                  color: isSelected ? Colors.orange : Colors.grey.shade300,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow(AppLocalizations l10n) {
    final provider = context.read<SearchResultsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int specCount = 0;
    for (final vals in _dynamicSpecFilters.values) {
      specCount += vals.length;
    }
    final hasFilters = _dynamicBrands.isNotEmpty ||
        _dynamicColors.isNotEmpty ||
        _dynamicSpecFilters.isNotEmpty ||
        _minPrice != null ||
        _maxPrice != null;
    final filterCount = _dynamicBrands.length +
        _dynamicColors.length +
        specCount +
        (_minPrice != null || _maxPrice != null ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          // Filter bar pills
          Expanded(child: _buildFilterBar(l10n)),
          const SizedBox(width: 8),
          // Filter button
          GestureDetector(
            onTap: () async {
              final result = await context.push('/dynamic_filter', extra: {
                'category': '',
                'initialBrands': _dynamicBrands,
                'initialColors': _dynamicColors,
                'initialSpecFilters': _dynamicSpecFilters,
                'availableSpecFacets': provider.specFacets,
                'initialMinPrice': _minPrice,
                'initialMaxPrice': _maxPrice,
              });
              if (result is Map<String, dynamic>) {
                _handleDynamicFilterApplied(result);
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasFilters ? Colors.orange : Colors.transparent,
                border: Border.all(
                  color: hasFilters ? Colors.orange : Colors.grey.shade300,
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
                        : (isDark ? Colors.white : Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasFilters
                        ? '${l10n.filter} ($filterCount)'
                        : l10n.filter,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasFilters
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersChips(AppLocalizations l10n) {
    return Consumer<SearchResultsProvider>(
      builder: (context, provider, child) {
        if (!provider.hasDynamicFilters) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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
                      _buildFilterChip(
                          '${l10n.brand ?? "Brand"}: $brand', () {
                        _removeSingleDynamicFilter(brand: brand);
                      })),
                  ...provider.dynamicColors.map((color) =>
                      _buildFilterChip(
                          '${l10n.color ?? "Color"}: ${ColorLocalization.localizeColorName(color, l10n)}',
                          () {
                        _removeSingleDynamicFilter(color: color);
                      })),
                  // Generic spec filter chips
                  ...provider.dynamicSpecFilters.entries.expand((entry) {
                    final fieldName = entry.key;
                    final fieldTitle = AttributeLocalizationUtils
                        .getLocalizedAttributeTitle(fieldName, l10n);
                    return entry.value.map((value) {
                      final localizedValue = AttributeLocalizationUtils
                          .getLocalizedSingleValue(fieldName, value, l10n);
                      return _buildFilterChip(
                        '$fieldTitle: $localizedValue',
                        () {
                          _removeSingleDynamicFilter(
                              specField: fieldName, specValue: value);
                        },
                      );
                    });
                  }),
                  if (provider.minPrice != null || provider.maxPrice != null)
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

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingShimmer(bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                },
                childCount: 6,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 32,
                crossAxisSpacing: 16,
                childAspectRatio: 0.65,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white38
                      : Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.searchFailedTryAgain,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _resetAndFetch,
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/empty-search-result.png',
                  width: 130,
                  height: 130,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noProductsFound,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsList(SearchResultsProvider provider) {
    return RefreshIndicator(
      onRefresh: _resetAndFetch,
      child: CustomScrollView(
        controller: _mainScrollController,
        slivers: [
          ProductListSliver(
            products: provider.filteredProducts,
            boostedProducts: provider.boostedProducts,
            hasMore: _hasMore,
            screenName: 'search_results_screen',
            isLoadingMore: _isLoading && !provider.hasNoData,
            selectedColor:
                _dynamicColors.isNotEmpty ? _dynamicColors.first : null,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: const BackButton(),
        title: Text(l10n.searchResults),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () {
              showCupertinoModalPopup(
                context: context,
                builder: (context) => CupertinoActionSheet(
                  title: Text(l10n.sortBy),
                  actions: _sortOptions.map((opt) {
                    return CupertinoActionSheetAction(
                      onPressed: () {
                        Navigator.pop(context);
                        _onSortChanged(opt);
                      },
                      child: Text(_localizedSortLabel(opt, l10n)),
                    );
                  }).toList(),
                  cancelButton: CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(context),
                    isDefaultAction: true,
                    child: Text(l10n.cancel),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header row with filter pills + filter button
          _buildHeaderRow(l10n),

          // Active filter chips
          _buildActiveFiltersChips(l10n),

          // Product list
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _filterTypes.length,
              onPageChanged: (i) {
                final key = _filterTypes[i];
                if (key != _currentFilter && mounted) {
                  _onFilterTap(key, i);
                }
              },
              itemBuilder: (_, idx) {
                return Consumer<SearchResultsProvider>(
                  builder: (context, provider, child) {
                    if (_isLoading && provider.hasNoData) {
                      return _buildLoadingShimmer(isDarkMode);
                    }
                    if (_hasError) {
                      return _buildErrorState(l10n);
                    }
                    if (provider.isEmpty && !_isLoading) {
                      return _buildEmptyState(l10n);
                    }
                    return _buildProductsList(provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
