import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Nar24/generated/l10n/app_localizations.dart';
import 'package:Nar24/models/dynamic_filter.dart';
import 'package:Nar24/models/product_summary.dart';
import 'package:Nar24/widgets/product_list_sliver.dart';
import 'package:Nar24/providers/market_dynamic_filter_provider.dart';
import 'package:Nar24/utils/color_localization.dart';
import 'package:Nar24/screens/FILTER-SCREENS/market_screen_dynamic_filters_filter_screen.dart';
import 'package:Nar24/constants/all_in_one_category_data.dart';
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

// Server-side filter query builder
class ServerSideFilterQueryBuilder {
  static Query buildFilteredQuery({
    required String collection,
    required DynamicFilter baseFilter,
    List<String> selectedBrands = const [],
    List<String> selectedColors = const [],
    String? selectedCategory,
    String? selectedSubcategory,
    String? selectedSubSubcategory,
    double? minPrice,
    double? maxPrice,
    String? sortBy,
    bool sortDescending = true,
  }) {
    Query query = FirebaseFirestore.instance.collection(collection);

    // Apply base filter conditions first
    query = _applyBaseFilterConditions(query, baseFilter);

    // Apply brand filter
    if (selectedBrands.isNotEmpty) {
      // For single brand, use ==, for multiple use array-contains-any
      if (selectedBrands.length == 1) {
        query = query.where('brandModel', isEqualTo: selectedBrands.first);
      } else {
        query = query.where('brandModel', whereIn: selectedBrands);
      }
    }

    // Apply color filter - using array-contains-any for colorImages keys
    if (selectedColors.isNotEmpty) {
      // Create a compound condition for colors
      // Since colorImages is a map, we need to check if any of the keys match
      if (selectedColors.isNotEmpty) {
        if (selectedColors.length == 1) {
          query = query.where('availableColors',
              arrayContains: selectedColors.first);
        } else {
          query =
              query.where('availableColors', arrayContainsAny: selectedColors);
        }
      }
    }

    // Apply category filters
    if (selectedCategory != null) {
      query = query.where('category', isEqualTo: selectedCategory);
    }

    if (selectedSubcategory != null) {
      query = query.where('subcategory', isEqualTo: selectedSubcategory);
    }

    if (selectedSubSubcategory != null) {
      query = query.where('subsubcategory', isEqualTo: selectedSubSubcategory);
    }

    // Apply price filters
    if (minPrice != null) {
      query = query.where('price', isGreaterThanOrEqualTo: minPrice);
    }

    if (maxPrice != null) {
      query = query.where('price', isLessThanOrEqualTo: maxPrice);
    }

    // Apply sorting
    if (sortBy != null) {
      query = query.orderBy(sortBy, descending: sortDescending);
    } else {
      // Default sort by creation date
      query = query.orderBy('createdAt', descending: true);
    }

    return query;
  }

  static Query _applyBaseFilterConditions(
      Query query, DynamicFilter baseFilter) {
    try {
      switch (baseFilter.type) {
        case FilterType.attribute:
          if (baseFilter.attribute != null &&
              baseFilter.operator != null &&
              baseFilter.attributeValue != null) {
            query = _applyAttributeFilter(query, baseFilter);
          }
          break;

        case FilterType.query:
          if (baseFilter.queryConditions != null &&
              baseFilter.queryConditions!.isNotEmpty) {
            query = _applyQueryConditions(query, baseFilter);
          }
          break;

        case FilterType.collection:
          break;
      }
    } catch (e) {
      debugPrint('Error applying base filter conditions: $e');
    }
    return query;
  }

  static Query _applyAttributeFilter(Query query, DynamicFilter filter) {
    final attribute = filter.attribute!;
    final operator = filter.operator!;
    final value = filter.attributeValue!;

    try {
      switch (operator) {
        case '==':
          return query.where(attribute, isEqualTo: value);
        case '!=':
          return query.where(attribute, isNotEqualTo: value);
        case '>':
          return query.where(attribute, isGreaterThan: value);
        case '>=':
          return query.where(attribute, isGreaterThanOrEqualTo: value);
        case '<':
          return query.where(attribute, isLessThan: value);
        case '<=':
          return query.where(attribute, isLessThanOrEqualTo: value);
        case 'array-contains':
          return query.where(attribute, arrayContains: value);
        case 'array-contains-any':
          return query.where(attribute, arrayContainsAny: value);
        case 'in':
          return query.where(attribute, whereIn: value);
        case 'not-in':
          return query.where(attribute, whereNotIn: value);
        default:
          return query.where(attribute, isEqualTo: value);
      }
    } catch (e) {
      debugPrint('Error applying attribute filter: $e');
      return query;
    }
  }

  static Query _applyQueryConditions(Query query, DynamicFilter filter) {
    try {
      for (final condition in filter.queryConditions!) {
        switch (condition.operator) {
          case '==':
            query = query.where(condition.field, isEqualTo: condition.value);
            break;
          case '!=':
            query = query.where(condition.field, isNotEqualTo: condition.value);
            break;
          case '>':
            query =
                query.where(condition.field, isGreaterThan: condition.value);
            break;
          case '>=':
            query = query.where(condition.field,
                isGreaterThanOrEqualTo: condition.value);
            break;
          case '<':
            query = query.where(condition.field, isLessThan: condition.value);
            break;
          case '<=':
            query = query.where(condition.field,
                isLessThanOrEqualTo: condition.value);
            break;
          case 'array-contains':
            query =
                query.where(condition.field, arrayContains: condition.value);
            break;
          case 'array-contains-any':
            query =
                query.where(condition.field, arrayContainsAny: condition.value);
            break;
          case 'in':
            query = query.where(condition.field, whereIn: condition.value);
            break;
          case 'not-in':
            query = query.where(condition.field, whereNotIn: condition.value);
            break;
          default:
            query = query.where(condition.field, isEqualTo: condition.value);
        }
      }
    } catch (e) {
      debugPrint('Error applying query conditions: $e');
    }
    return query;
  }
}

// Cache for server-side results
class ServerSideResultCache {
  static const int _maxCacheSize = 20;
  static const Duration _cacheExpiry = Duration(minutes: 10);

  final Map<String, _CacheEntry> _cache = {};

  String _generateCacheKey({
    required String collection,
    required DynamicFilter baseFilter,
    required List<String> selectedBrands,
    required List<String> selectedColors,
    required String? selectedCategory,
    required String? selectedSubcategory,
    required String? selectedSubSubcategory,
    required double? minPrice,
    required double? maxPrice,
    required String? sortBy,
    required bool sortDescending,
  }) {
    return '${collection}_${baseFilter.id}_${selectedBrands.join(',')}_${selectedColors.join(',')}_${selectedCategory ?? ''}_${selectedSubcategory ?? ''}_${selectedSubSubcategory ?? ''}_${minPrice ?? ''}_${maxPrice ?? ''}_${sortBy ?? ''}_$sortDescending';
  }

  List<ProductSummary>? getCachedResults({
    required String collection,
    required DynamicFilter baseFilter,
    required List<String> selectedBrands,
    required List<String> selectedColors,
    required String? selectedCategory,
    required String? selectedSubcategory,
    required String? selectedSubSubcategory,
    required double? minPrice,
    required double? maxPrice,
    required String? sortBy,
    required bool sortDescending,
  }) {
    final key = _generateCacheKey(
      collection: collection,
      baseFilter: baseFilter,
      selectedBrands: selectedBrands,
      selectedColors: selectedColors,
      selectedCategory: selectedCategory,
      selectedSubcategory: selectedSubcategory,
      selectedSubSubcategory: selectedSubSubcategory,
      minPrice: minPrice,
      maxPrice: maxPrice,
      sortBy: sortBy,
      sortDescending: sortDescending,
    );

    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      return entry.products;
    }

    return null;
  }

  void cacheResults({
    required String collection,
    required DynamicFilter baseFilter,
    required List<String> selectedBrands,
    required List<String> selectedColors,
    required String? selectedCategory,
    required String? selectedSubcategory,
    required String? selectedSubSubcategory,
    required double? minPrice,
    required double? maxPrice,
    required String? sortBy,
    required bool sortDescending,
    required List<ProductSummary> products,
  }) {
    final key = _generateCacheKey(
      collection: collection,
      baseFilter: baseFilter,
      selectedBrands: selectedBrands,
      selectedColors: selectedColors,
      selectedCategory: selectedCategory,
      selectedSubcategory: selectedSubcategory,
      selectedSubSubcategory: selectedSubSubcategory,
      minPrice: minPrice,
      maxPrice: maxPrice,
      sortBy: sortBy,
      sortDescending: sortDescending,
    );

    // Remove oldest entry if cache is full
    if (_cache.length >= _maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    _cache[key] = _CacheEntry(products, DateTime.now().add(_cacheExpiry));
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<ProductSummary> products;
  final DateTime expiresAt;

  _CacheEntry(this.products, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  // Server-side data
  List<ProductSummary> _allProducts = [];
  List<ProductSummary> _boostedProducts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  DocumentSnapshot? _lastDocument;
  late final ServerSideFilterDebouncer _serverDebouncer;
  late final ServerSideResultCache _resultCache;

  // Filter state
  List<String> _selectedBrands = [];
  List<String> _selectedColors = [];
  double? _minPrice;
  double? _maxPrice;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String? _selectedSubSubcategory;

  // Performance constants
  static const int _limit = 25;
  static const int _initialLimit = 50;
  static const double _scrollThreshold = 0.8;

  @override
  void initState() {
    super.initState();

    _serverDebouncer =
        ServerSideFilterDebouncer(delay: const Duration(milliseconds: 300));
    _resultCache = ServerSideResultCache();

    _setupScrollListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProductsFromServer();
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

  Future<void> _loadProductsFromServer({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _allProducts.clear();
        _boostedProducts.clear();
        _lastDocument = null;
        _hasMore = true;
        _error = null;
        _isLoading = true;
      });
      // Don't clear the entire cache — let different filter combinations
      // keep their separate cache entries for instant restore on toggle-back.
      // The cache already has max 20 entries with 10-minute expiry.
    }

    try {
      // Check cache first
      final cachedProducts = _resultCache.getCachedResults(
        collection: widget.dynamicFilter.collection ?? 'shop_products',
        baseFilter: widget.dynamicFilter,
        selectedBrands: _selectedBrands,
        selectedColors: _selectedColors,
        selectedCategory: _selectedCategory,
        selectedSubcategory: _selectedSubcategory,
        selectedSubSubcategory: _selectedSubSubcategory,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        sortBy: widget.dynamicFilter.sortBy,
        sortDescending: widget.dynamicFilter.sortOrder == 'desc',
      );

      if (cachedProducts != null && !isRefresh) {
        setState(() {
          _allProducts = cachedProducts.where((p) => !p.isBoosted).toList();
          _boostedProducts = cachedProducts.where((p) => p.isBoosted).toList();
          _isLoading = false;
        });
        return;
      }

      // Build server-side filtered query
      final query = ServerSideFilterQueryBuilder.buildFilteredQuery(
        collection: widget.dynamicFilter.collection ?? 'shop_products',
        baseFilter: widget.dynamicFilter,
        selectedBrands: _selectedBrands,
        selectedColors: _selectedColors,
        selectedCategory: _selectedCategory,
        selectedSubcategory: _selectedSubcategory,
        selectedSubSubcategory: _selectedSubSubcategory,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        sortBy: widget.dynamicFilter.sortBy,
        sortDescending: widget.dynamicFilter.sortOrder == 'desc',
      );

      // Execute query
      final snapshot =
          await query.limit(isRefresh ? _initialLimit : _initialLimit).get();

      if (mounted) {
        final products = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .where((product) => product != null)
            .cast<ProductSummary>()
            .toList();

        final boosted = products.where((p) => p.isBoosted).toList();
        final normal = products.where((p) => !p.isBoosted).toList();

        setState(() {
          _allProducts = normal;
          _boostedProducts = boosted;
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length ==
              (isRefresh ? _initialLimit : _initialLimit);
          _isLoading = false;
          _error = null;
        });

        // Cache results
        _resultCache.cacheResults(
          collection: widget.dynamicFilter.collection ?? 'shop_products',
          baseFilter: widget.dynamicFilter,
          selectedBrands: _selectedBrands,
          selectedColors: _selectedColors,
          selectedCategory: _selectedCategory,
          selectedSubcategory: _selectedSubcategory,
          selectedSubSubcategory: _selectedSubSubcategory,
          minPrice: _minPrice,
          maxPrice: _maxPrice,
          sortBy: widget.dynamicFilter.sortBy,
          sortDescending: widget.dynamicFilter.sortOrder == 'desc',
          products: products,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
      debugPrint('Error loading products from server: $e');
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Build the same filtered query but with pagination
      Query query = ServerSideFilterQueryBuilder.buildFilteredQuery(
        collection: widget.dynamicFilter.collection ?? 'shop_products',
        baseFilter: widget.dynamicFilter,
        selectedBrands: _selectedBrands,
        selectedColors: _selectedColors,
        selectedCategory: _selectedCategory,
        selectedSubcategory: _selectedSubcategory,
        selectedSubSubcategory: _selectedSubSubcategory,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        sortBy: widget.dynamicFilter.sortBy,
        sortDescending: widget.dynamicFilter.sortOrder == 'desc',
      );

      // Add pagination
      query = query.startAfterDocument(_lastDocument!).limit(_limit);

      final snapshot = await query.get();

      if (mounted) {
        final products = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .where((product) => product != null)
            .cast<ProductSummary>()
            .toList();

        final boosted = products.where((p) => p.isBoosted).toList();
        final normal = products.where((p) => !p.isBoosted).toList();

        setState(() {
          _allProducts.addAll(normal);
          _boostedProducts.addAll(boosted);
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length == _limit;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
      debugPrint('Error loading more products: $e');
    }
  }

  // Apply filters with server-side debouncing
  void _applyFiltersWithServerQuery() {
    _serverDebouncer(() {
      if (!mounted) return;
      _loadProductsFromServer(isRefresh: true);
    });
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
          initialCategory: _selectedCategory,
          initialSubcategory: _selectedSubcategory,
          initialSubSubcategory: _selectedSubSubcategory,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedBrands = List<String>.from(result['brands'] ?? []);
        _selectedColors = List<String>.from(result['colors'] ?? []);
        _minPrice = result['minPrice'];
        _maxPrice = result['maxPrice'];
        _selectedCategory = result['category'];
        _selectedSubcategory = result['subcategory'];
        _selectedSubSubcategory = result['subSubcategory'];
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
      _selectedCategory = null;
      _selectedSubcategory = null;
      _selectedSubSubcategory = null;
    });

    _applyFiltersWithServerQuery();
  }

  // Remove individual filter
  void _removeFilter({
    String? brand,
    String? color,
    bool clearPrice = false,
    bool clearCategory = false,
  }) {
    setState(() {
      if (brand != null) _selectedBrands.remove(brand);
      if (color != null) _selectedColors.remove(color);
      if (clearPrice) {
        _minPrice = null;
        _maxPrice = null;
      }
      if (clearCategory) {
        _selectedCategory = null;
        _selectedSubcategory = null;
        _selectedSubSubcategory = null;
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
      _selectedCategory != null ||
      _selectedSubcategory != null ||
      _selectedSubSubcategory != null;

  int get _activeFiltersCount {
    int count = 0;
    count += _selectedBrands.length;
    count += _selectedColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    if (_selectedCategory != null) count++;
    if (_selectedSubcategory != null) count++;
    if (_selectedSubSubcategory != null) count++;
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
    _resultCache.clearCache();
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
          // Filter button
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
            child: GestureDetector(
              onTap: _showFilterScreen,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _hasActiveFilters ? Colors.orange : Colors.transparent,
                  border: Border.all(
                    color: _hasActiveFilters
                        ? Colors.orange
                        : (isDark ? Colors.white : Colors.black),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _hasActiveFilters
                      ? '${l10n.filter ?? "Filter"} ($_activeFiltersCount)'
                      : (l10n.filter ?? "Filter"),
                  style: TextStyle(
                    color: _hasActiveFilters
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
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
      body: _buildBody(l10n, isDark),
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
        !_isLoading &&
        _hasActiveFilters) {
      return _buildEmptyState(l10n);
    }

    return RefreshIndicator(
      onRefresh: () => _loadProductsFromServer(isRefresh: true),
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
              onPressed: () => _loadProductsFromServer(isRefresh: true),
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
}
