import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Nar24/generated/l10n/app_localizations.dart';
import 'package:Nar24/models/dynamic_filter.dart';
import 'package:Nar24/models/product_summary.dart';
import 'package:Nar24/widgets/product_list_sliver.dart';
import 'package:Nar24/providers/market_dynamic_filter_provider.dart';
import 'package:Nar24/utils/color_localization.dart';
import 'package:Nar24/utils/attribute_localization_utils.dart';
import 'package:Nar24/screens/FILTER-SCREENS/market_screen_dynamic_filters_filter_screen.dart';
import 'package:Nar24/constants/all_in_one_category_data.dart';
import 'package:Nar24/services/typesense_service_manager.dart';
import 'package:Nar24/services/typesense_service.dart';
import 'package:shimmer/shimmer.dart';

// Enhanced debounced filter for server requests
class ServerSideFilterDebouncer {
  Timer? _debounceTimer;
  final Duration delay;

  ServerSideFilterDebouncer({this.delay = const Duration(milliseconds: 500)});

  void call(VoidCallback callback) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, callback);
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}

// NOTE: ServerSideFilterQueryBuilder (Firestore) removed — all filtering now uses Typesense.
// NOTE: ServerSideResultCache removed — Typesense responses are fast enough without client-side caching.

class MarketScreenDynamicFiltersScreen extends StatefulWidget {
  final DynamicFilter dynamicFilter;

  const MarketScreenDynamicFiltersScreen({
    Key? key,
    required this.dynamicFilter,
  }) : super(key: key);

  @override
  State<MarketScreenDynamicFiltersScreen> createState() =>
      _MarketScreenDynamicFiltersScreenState();
}

class _MarketScreenDynamicFiltersScreenState
    extends State<MarketScreenDynamicFiltersScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  // Server-side data
  List<ProductSummary> _allProducts = [];
  List<ProductSummary> _boostedProducts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  late final ServerSideFilterDebouncer _serverDebouncer;

  // Sort state
  String _selectedSortOption = 'None';
  final List<String> _sortOptions = [
    'None',
    'Alphabetical',
    'Date',
    'Price Low to High',
    'Price High to Low',
  ];

  // Filter state
  List<String> _selectedBrands = [];
  List<String> _selectedColors = [];
  double? _minPrice;
  double? _maxPrice;
  double? _minRating;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String? _selectedSubSubcategory;
  Map<String, List<String>> _dynamicSpecFilters = {};

  // Spec facets (unified — populated by disjunctive multi-search)
  Map<String, List<Map<String, dynamic>>> _facets = {};

  // Typesense pagination (used when spec filters are active)
  int _typesensePage = 0;
  bool _typesenseHasMore = true;

  // Performance constants
  static const int _limit = 25;
  static const double _scrollThreshold = 0.8;

  @override
  void initState() {
    super.initState();

    _serverDebouncer =
        ServerSideFilterDebouncer(delay: const Duration(milliseconds: 300));

    _setupScrollListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts();
      _fetchSpecFacets();
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final position = _scrollController.position;

      if (position.pixels >= position.maxScrollExtent * _scrollThreshold &&
          !_isLoadingMore &&
          _hasMore) {
        _loadMoreProducts();
      }
    });
  }

  Future<void> _loadProducts({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _allProducts.clear();
        _boostedProducts.clear();
        _hasMore = true;
        _error = null;
        _isLoading = true;
      });
    }

    try {
      _typesensePage = 0;
      List<ProductSummary> products;
      try {
        products = await _fetchFromTypesense(page: 0);
      } catch (e) {
        debugPrint('Typesense failed, falling back to Firestore: $e');
        products = [];
      }

      // Fallback to Firestore via DynamicFilterProvider when Typesense
      // returns empty on the initial unfiltered load.
      if (products.isEmpty && !_hasActiveFilters && mounted) {
        try {
          final provider =
              Provider.of<DynamicFilterProvider>(context, listen: false);
          products = await provider.getFilterProducts(widget.dynamicFilter.id);
        } catch (e) {
          debugPrint('Firestore fallback also failed: $e');
        }
      }

      if (mounted) {
        final boosted = products.where((p) => p.isBoosted).toList();
        final normal = products.where((p) => !p.isBoosted).toList();
        setState(() {
          _allProducts = normal;
          _boostedProducts = boosted;
          _hasMore = _typesenseHasMore;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
      debugPrint('Error loading products: $e');
    }
  }

  /// Build the Typesense additionalFilterBy string from the base DynamicFilter.
  String? _buildBaseFilterBy() {
    final filter = widget.dynamicFilter;
    final parts = <String>[];

    switch (filter.type) {
      case FilterType.attribute:
        if (filter.attribute != null && filter.attributeValue != null) {
          final op = filter.operator ?? '==';
          final field = filter.attribute!;
          final value = filter.attributeValue!;
          switch (op) {
            case '==':
              parts.add('$field:=$value');
              break;
            case '!=':
              parts.add('$field:!=$value');
              break;
            case '>':
              parts.add('$field:>$value');
              break;
            case '>=':
              parts.add('$field:>=$value');
              break;
            case '<':
              parts.add('$field:<$value');
              break;
            case '<=':
              parts.add('$field:<=$value');
              break;
            case 'array-contains':
              parts.add('$field:=$value');
              break;
            case 'array-contains-any':
            case 'in':
              if (value is List) {
                final orParts = value.map((v) => '$field:=$v').toList();
                if (orParts.length == 1) {
                  parts.add(orParts.first);
                } else if (orParts.length > 1) {
                  parts.add('(${orParts.join(' || ')})');
                }
              } else {
                parts.add('$field:=$value');
              }
              break;
            case 'not-in':
              if (value is List) {
                for (final v in value) {
                  parts.add('$field:!=$v');
                }
              } else {
                parts.add('$field:!=$value');
              }
              break;
            default:
              parts.add('$field:=$value');
          }
        }
        break;
      case FilterType.query:
        if (filter.queryConditions != null) {
          for (final cond in filter.queryConditions!) {
            final field = cond.field;
            final value = cond.value;
            switch (cond.operator) {
              case '==':
                parts.add('$field:=$value');
                break;
              case '!=':
                parts.add('$field:!=$value');
                break;
              case '>':
                parts.add('$field:>$value');
                break;
              case '>=':
                parts.add('$field:>=$value');
                break;
              case '<':
                parts.add('$field:<$value');
                break;
              case '<=':
                parts.add('$field:<=$value');
                break;
              case 'array-contains':
                parts.add('$field:=$value');
                break;
              case 'array-contains-any':
              case 'in':
                if (value is List) {
                  final orParts = value.map((v) => '$field:=$v').toList();
                  if (orParts.length == 1) {
                    parts.add(orParts.first);
                  } else if (orParts.length > 1) {
                    parts.add('(${orParts.join(' || ')})');
                  }
                } else {
                  parts.add('$field:=$value');
                }
                break;
              case 'not-in':
                if (value is List) {
                  for (final v in value) {
                    parts.add('$field:!=$v');
                  }
                } else {
                  parts.add('$field:!=$value');
                }
                break;
              default:
                parts.add('$field:=$value');
            }
          }
        }
        break;
      case FilterType.collection:
        // Collection type has no additional filter — the collection name is already the index
        break;
    }

    return parts.isNotEmpty ? parts.join(' && ') : null;
  }

  Future<void> _fetchSpecFacets() async {
    try {
      final svc = TypeSenseServiceManager.instance.shopService;

      // Build context filter
      final baseFilterBy = _buildBaseFilterBy();
      final contextParts = <String>[];
      if (baseFilterBy != null) contextParts.add(baseFilterBy);
      if (_selectedCategory != null) {
        contextParts.add('category_en:=`$_selectedCategory`');
      }
      if (_selectedSubcategory != null) {
        contextParts.add('subcategory_en:=`$_selectedSubcategory`');
      }
      if (_selectedSubSubcategory != null) {
        contextParts.add('subsubcategory_en:=`$_selectedSubSubcategory`');
      }

      // Disjunctive filters matching current selection
      final disjunctiveFilters = <String, List<String>>{};
      if (_selectedBrands.isNotEmpty) {
        disjunctiveFilters['brandModel'] = _selectedBrands;
      }
      if (_selectedColors.isNotEmpty) {
        disjunctiveFilters['availableColors'] = _selectedColors;
      }
      for (final entry in _dynamicSpecFilters.entries) {
        if (entry.value.isNotEmpty) {
          disjunctiveFilters[entry.key] = entry.value;
        }
      }

      final numericFilters = <String>[];
      if (_minPrice != null) numericFilters.add('price>=${_minPrice!.toInt()}');
      if (_maxPrice != null) numericFilters.add('price<=${_maxPrice!.toInt()}');
      if (_minRating != null) numericFilters.add('averageRating>=${_minRating!}');

      final res = await svc.searchWithDisjunctiveFacets(
        indexName: widget.dynamicFilter.collection ?? 'shop_products',
        hitsPerPage: 0, // facets only
        additionalFilterBy:
            contextParts.isNotEmpty ? contextParts.join(' && ') : null,
        disjunctiveFilters: disjunctiveFilters,
        numericFilters: numericFilters,
        sortOption: _typesenseSortCode(),
        facetBy: 'brandModel,productType,consoleBrand,clothingFit,clothingTypes,clothingSizes,'
            'jewelryType,jewelryMaterials,pantSizes,pantFabricTypes,footwearSizes',
      );
      if (mounted) {
        setState(() => _facets = res.facets);
      }
    } catch (e) {
      debugPrint('Error fetching spec facets: $e');
    }
  }

  /// Convert sort to a Typesense sort code.
  /// User-selected sort takes priority over the DynamicFilter's configured sort.
  String _typesenseSortCode() {
    if (_selectedSortOption != 'None') {
      switch (_selectedSortOption) {
        case 'Alphabetical':
          return 'alphabetical';
        case 'Date':
          return 'date';
        case 'Price Low to High':
          return 'price_asc';
        case 'Price High to Low':
          return 'price_desc';
        default:
          return 'date';
      }
    }
    final sortBy = widget.dynamicFilter.sortBy;
    final desc = widget.dynamicFilter.sortOrder == 'desc';
    switch (sortBy) {
      case 'createdAt':
        return 'date';
      case 'productName':
        return 'alphabetical';
      case 'price':
        return desc ? 'price_desc' : 'price_asc';
      default:
        return 'date';
    }
  }

  Future<List<ProductSummary>> _fetchFromTypesense({required int page}) async {
    final svc = TypeSenseServiceManager.instance.shopService;

    // Base context filter from the DynamicFilter config
    final baseFilterBy = _buildBaseFilterBy();

    // Additional conjunctive context filters (category drill-down)
    final contextParts = <String>[];
    if (baseFilterBy != null) contextParts.add(baseFilterBy);
    if (_selectedCategory != null) {
      contextParts.add('category_en:=`$_selectedCategory`');
    }
    if (_selectedSubcategory != null) {
      contextParts.add('subcategory_en:=`$_selectedSubcategory`');
    }
    if (_selectedSubSubcategory != null) {
      contextParts.add('subsubcategory_en:=`$_selectedSubSubcategory`');
    }

    // Disjunctive filters
    final disjunctiveFilters = <String, List<String>>{};
    if (_selectedBrands.isNotEmpty) {
      disjunctiveFilters['brandModel'] = _selectedBrands;
    }
    if (_selectedColors.isNotEmpty) {
      disjunctiveFilters['availableColors'] = _selectedColors;
    }
    for (final entry in _dynamicSpecFilters.entries) {
      if (entry.value.isNotEmpty) {
        disjunctiveFilters[entry.key] = entry.value;
      }
    }

    final numericFilters = <String>[];
    if (_minPrice != null) numericFilters.add('price>=${_minPrice!.toInt()}');
    if (_maxPrice != null) numericFilters.add('price<=${_maxPrice!.toInt()}');
    if (_minRating != null) numericFilters.add('averageRating>=${_minRating!}');

    final res = await svc.searchWithDisjunctiveFacets(
      indexName: widget.dynamicFilter.collection ?? 'shop_products',
      page: page,
      hitsPerPage: _limit,
      additionalFilterBy:
          contextParts.isNotEmpty ? contextParts.join(' && ') : null,
      disjunctiveFilters: disjunctiveFilters,
      numericFilters: numericFilters,
      sortOption: _typesenseSortCode(),
      facetBy: 'brandModel,productType,consoleBrand,clothingFit,clothingTypes,clothingSizes,'
          'jewelryType,jewelryMaterials,pantSizes,pantFabricTypes,footwearSizes',
    );

    _typesenseHasMore = res.page < (res.nbPages - 1);

    if (mounted) {
      setState(() => _facets = res.facets);
    }

    return res.hits.map((hit) => ProductSummary.fromTypeSense(hit)).toList();
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      _typesensePage++;
      final newProducts = await _fetchFromTypesense(page: _typesensePage);
      if (mounted) {
        final existingIds = _allProducts.map((p) => p.id).toSet();
        existingIds.addAll(_boostedProducts.map((p) => p.id));
        final deduped =
            newProducts.where((p) => !existingIds.contains(p.id)).toList();
        setState(() {
          _allProducts.addAll(deduped.where((p) => !p.isBoosted));
          _boostedProducts.addAll(deduped.where((p) => p.isBoosted));
          _hasMore = _typesenseHasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading more products: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // Apply filters with server-side debouncing
  void _applyFiltersWithServerQuery() {
    _serverDebouncer(() {
      if (!mounted) return;
      _loadProducts(isRefresh: true);
    });
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

    setState(() => _selectedSortOption = option);
    _loadProducts(isRefresh: true);
  }

  // Show filter screen
  Future<void> _showFilterScreen() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => MarketScreenDynamicFiltersFilterScreen(
          baseFilter: widget.dynamicFilter,
          initialBrands: _selectedBrands,
          initialColors: _selectedColors,
          initialMinPrice: _minPrice,
          initialMaxPrice: _maxPrice,
          initialMinRating: _minRating,
          initialCategory: _selectedCategory,
          initialSubcategory: _selectedSubcategory,
          initialSubSubcategory: _selectedSubSubcategory,
          initialSpecFilters: _dynamicSpecFilters,
          availableSpecFacets: _facets,
        ),
      ),
    );

    if (result != null && mounted) {
      final rawSpecFilters =
          result['specFilters'] as Map<String, List<String>>? ?? {};
      final specFilters = rawSpecFilters.map(
        (k, v) => MapEntry(k, List<String>.from(v)),
      );

      setState(() {
        _selectedBrands = List<String>.from(result['brands'] ?? []);
        _selectedColors = List<String>.from(result['colors'] ?? []);
        _minPrice = result['minPrice'];
        _maxPrice = result['maxPrice'];
        _minRating = result['minRating'];
        _selectedCategory = result['category'];
        _selectedSubcategory = result['subcategory'];
        _selectedSubSubcategory = result['subSubcategory'];
        _dynamicSpecFilters = specFilters;
      });

      _applyFiltersWithServerQuery();
    }
  }

  // Clear all filters
  void _clearAllFilters() {
    setState(() {
      _selectedBrands.clear();
      _selectedColors.clear();
      _minPrice = null;
      _maxPrice = null;
      _minRating = null;
      _selectedCategory = null;
      _selectedSubcategory = null;
      _selectedSubSubcategory = null;
      _dynamicSpecFilters.clear();
    });

    _applyFiltersWithServerQuery();
  }

  // Remove individual filter
  void _removeFilter({
    String? brand,
    String? color,
    bool clearPrice = false,
    bool clearRating = false,
    bool clearCategory = false,
    String? specField,
    String? specValue,
  }) {
    setState(() {
      if (brand != null) _selectedBrands.remove(brand);
      if (color != null) _selectedColors.remove(color);
      if (clearPrice) {
        _minPrice = null;
        _maxPrice = null;
      }
      if (clearRating) _minRating = null;
      if (clearCategory) {
        _selectedCategory = null;
        _selectedSubcategory = null;
        _selectedSubSubcategory = null;
      }
      if (specField != null && specValue != null) {
        final list = _dynamicSpecFilters[specField];
        if (list != null) {
          list.remove(specValue);
          if (list.isEmpty) _dynamicSpecFilters.remove(specField);
        }
      }
    });

    _applyFiltersWithServerQuery();
  }

  // Check if any filters are active
  bool get _hasActiveFilters =>
      _selectedBrands.isNotEmpty ||
      _selectedColors.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null ||
      _minRating != null ||
      _selectedCategory != null ||
      _selectedSubcategory != null ||
      _selectedSubSubcategory != null ||
      _dynamicSpecFilters.isNotEmpty;

  int get _activeFiltersCount {
    int count = 0;
    count += _selectedBrands.length;
    count += _selectedColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    if (_minRating != null) count++;
    if (_selectedCategory != null) count++;
    if (_selectedSubcategory != null) count++;
    if (_selectedSubSubcategory != null) count++;
    for (final vals in _dynamicSpecFilters.values) {
      count += vals.length;
    }
    return count;
  }

  Color _parseColor(String colorString) {
    try {
      final cleanColor = colorString.replaceAll('#', '');
      if (cleanColor.length == 6) {
        return Color(int.parse('FF$cleanColor', radix: 16));
      } else if (cleanColor.length == 8) {
        return Color(int.parse(cleanColor, radix: 16));
      }
    } catch (e) {
      debugPrint('Error parsing color $colorString: $e');
    }
    return Colors.orange;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _serverDebouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dynamicFilterProvider =
        Provider.of<DynamicFilterProvider>(context, listen: false);
    final displayName = dynamicFilterProvider.getFilterDisplayName(
      widget.dynamicFilter,
      Localizations.localeOf(context).languageCode,
    );

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (widget.dynamicFilter.icon != null &&
              widget.dynamicFilter.icon!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  widget.dynamicFilter.icon!,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header row with filter + sort buttons
          _buildHeaderRow(l10n, isDark),
          // Body content
          Expanded(child: _buildBody(l10n, isDark)),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(AppLocalizations l10n, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          const Spacer(),
          // Filter button
          GestureDetector(
            onTap: _showFilterScreen,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    _hasActiveFilters ? Colors.orange : Colors.transparent,
                border: Border.all(
                  color: _hasActiveFilters
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
                    color: _hasActiveFilters
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _hasActiveFilters
                        ? '${l10n.filter} ($_activeFiltersCount)'
                        : l10n.filter,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _hasActiveFilters
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedSortOption != 'None')
                  Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: Text(
                      _localizedSortOption(_selectedSortOption, l10n),
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                  ),
                const Icon(CupertinoIcons.sort_down, size: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

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

  Widget _buildBody(AppLocalizations l10n, bool isDark) {
    if (_isLoading && _allProducts.isEmpty) {
      return _buildShimmerLoading(isDark);
    }

    if (_error != null && _allProducts.isEmpty) {
      return _buildErrorState(l10n);
    }

    if (_allProducts.isEmpty &&
        _boostedProducts.isEmpty &&
        !_isLoading) {
      return _buildEmptyState(l10n);
    }

    return RefreshIndicator(
      onRefresh: () => _loadProducts(isRefresh: true),
      color: Colors.orange,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Filter description if available
          if (widget.dynamicFilter.description != null &&
              widget.dynamicFilter.description!.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: _parseColor(widget.dynamicFilter.color ?? '#FF6B35')
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: _parseColor(widget.dynamicFilter.color ?? '#FF6B35')
                        .withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    if (widget.dynamicFilter.icon != null &&
                        widget.dynamicFilter.icon!.isNotEmpty) ...[
                      Text(
                        widget.dynamicFilter.icon!,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.dynamicFilter.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Active filters display
          if (_hasActiveFilters) _buildActiveFiltersWidget(l10n, isDark),

          // Product count when filters are active
          if (_hasActiveFilters && !_isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '${_allProducts.length + _boostedProducts.length} ${l10n.productsFound}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ),

          // Enhanced ProductListSliver
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            sliver: ProductListSliver(
              products: _allProducts,
              boostedProducts: _boostedProducts,
              hasMore: _hasMore,
              screenName: 'market_screen_dynamic_filters_screen',
              isLoadingMore: _isLoadingMore,
              
            ),
          ),

          // Loading more indicator
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16.0),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  color: Colors.orange,
                  strokeWidth: 2,
                ),
              ),
            ),

          // Bottom padding
          SliverToBoxAdapter(
            child: SizedBox(
              height: 20 + MediaQuery.of(context).padding.bottom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersWidget(AppLocalizations l10n, bool isDark) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${l10n.activeFilters ?? "Active Filters"} ($_activeFiltersCount)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.clearAll ?? 'Clear All',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
                // Brand chips
                ..._selectedBrands.map((brand) => _buildFilterChip(
                      '${l10n.brand ?? "Brand"}: $brand',
                      () => _removeFilter(brand: brand),
                    )),
                // Color chips
                ..._selectedColors.map((color) => _buildFilterChip(
                      '${l10n.color ?? "Color"}: ${ColorLocalization.localizeColorName(color, l10n)}',
                      () => _removeFilter(color: color),
                    )),
                // Price chip
                if (_minPrice != null || _maxPrice != null)
                  _buildFilterChip(
                    '${l10n.price ?? "Price"}: ${_minPrice?.toStringAsFixed(0) ?? '0'} - ${_maxPrice?.toStringAsFixed(0) ?? '∞'} TL',
                    () => _removeFilter(clearPrice: true),
                  ),
                // Rating chip
                if (_minRating != null)
                  _buildFilterChip(
                    '${l10n.rating ?? "Rating"}: ${_minRating!.toInt()}+',
                    () => _removeFilter(clearRating: true),
                  ),
                // Category chip
                if (_selectedCategory != null)
                  _buildFilterChip(
                    '${l10n.category ?? "Category"}: ${AllInOneCategoryData.localizeCategoryKey(_selectedCategory!, l10n)}',
                    () => _removeFilter(clearCategory: true),
                  ),
                // Subcategory chip
                if (_selectedSubcategory != null)
                  _buildFilterChip(
                    '${l10n.subcategory ?? "Subcategory"}: ${AllInOneCategoryData.localizeSubcategoryKey(_selectedCategory!, _selectedSubcategory!, l10n)}',
                    () => _removeFilter(clearCategory: true),
                  ),
                // Sub-subcategory chip
                if (_selectedSubSubcategory != null)
                  _buildFilterChip(
                    '${l10n.subSubcategory ?? "Sub-subcategory"}: ${AllInOneCategoryData.localizeSubSubcategoryKey(_selectedCategory!, _selectedSubcategory!, _selectedSubSubcategory!, l10n)}',
                    () => _removeFilter(clearCategory: true),
                  ),
                // Spec filter chips
                ..._dynamicSpecFilters.entries.expand((entry) {
                  final fieldTitle = AttributeLocalizationUtils
                      .getLocalizedAttributeTitle(entry.key, l10n);
                  return entry.value.map((value) {
                    final localizedValue = AttributeLocalizationUtils
                        .getLocalizedSingleValue(entry.key, value, l10n);
                    return _buildFilterChip(
                      '$fieldTitle: $localizedValue',
                      () => _removeFilter(
                          specField: entry.key, specValue: value),
                    );
                  });
                }),
              ],
            ),
          ],
        ),
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
            child: Container(
              padding: const EdgeInsets.all(2),
              child: const Icon(
                Icons.close,
                size: 12,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingProducts ?? 'Error loading products',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadProducts(isRefresh: true),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.tryAgain ?? 'Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () => _loadProducts(isRefresh: true),
      color: Colors.orange,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
            ),
          ),
        ),
      ),
    );
  }
}
