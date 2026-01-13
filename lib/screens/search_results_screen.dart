// lib/screens/search_results_screen.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/market_provider.dart';
import '../providers/search_results_provider.dart';
import '../models/product.dart';
import '../widgets/product_list_sliver.dart';
import '../generated/l10n/app_localizations.dart';

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
  final List<Product> _allSearchResults = [];
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
      });
      _didInit = true;
    }
  }

  @override
  void didUpdateWidget(covariant SearchResultsScreen old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _resetAndFetch();
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
      // Guard against multiple positions (happens during PageView transitions)
      if (!_mainScrollController.hasClients) return;

      // Use positions.length to check if we have exactly one position
      // During PageView swipes, we might have multiple positions temporarily
      if (_mainScrollController.positions.length != 1) return;

      // Safe to access position now
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

  /// Checks if viewport is not filled with content and loads more if needed.
  /// This handles the tablet/large screen case where initial content doesn't
  /// require scrolling, so the scroll listener never triggers pagination.
  void _checkViewportAndLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isLoading || !_hasMore) return;
      if (!_mainScrollController.hasClients) return;
      if (_mainScrollController.positions.length != 1) return;

      final position = _mainScrollController.position;

      // If maxScrollExtent is 0 or very small, content doesn't fill viewport
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
      final pageResults = await _marketProvider.searchOnly(
        query: widget.query,
        page: _currentPage,
        hitsPerPage: 50,
        l10n: l10n,
        filterType: '', // No server-side filtering, handled in provider
      );

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

    // Scroll to top on reset
    if (reset && _mainScrollController.hasClients) {
      // Only jump if we have exactly one position attached
      if (_mainScrollController.positions.length == 1) {
        _mainScrollController.jumpTo(0);
      }
    }

    // Check if viewport needs more content (for tablets/large screens)
    _checkViewportAndLoadMoreIfNeeded();
  }

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

    // Guard against multiple positions
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
            selectedColor: null,
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
          _buildFilterBar(l10n),
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
                    // Loading state
                    if (_isLoading && provider.hasNoData) {
                      return _buildLoadingShimmer(isDarkMode);
                    }

                    // Error state
                    if (_hasError) {
                      return _buildErrorState(l10n);
                    }

                    // Empty state
                    if (provider.isEmpty && !_isLoading) {
                      return _buildEmptyState(l10n);
                    }

                    // Products list
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
