import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product_summary.dart';
import '../../widgets/product_list_sliver.dart';
import '../../services/typesense_service_manager.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../utils/color_localization.dart';

class DynamicCollectionScreen extends StatefulWidget {
  final String collectionId;
  final String shopId;
  final String? collectionName;

  const DynamicCollectionScreen({
    Key? key,
    required this.collectionId,
    required this.shopId,
    this.collectionName,
  }) : super(key: key);

  @override
  State<DynamicCollectionScreen> createState() =>
      _DynamicCollectionScreenState();
}

class _DynamicCollectionScreenState extends State<DynamicCollectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  // Collection data
  Map<String, dynamic>? _collectionData;
  List<ProductSummary> _products = [];
  List<ProductSummary> _filteredProducts = [];
  List<ProductSummary> _boostedProducts = [];

  // Loading states
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Filter states
  List<String> _dynamicBrands = [];
  List<String> _dynamicColors = [];
  Map<String, List<String>> _dynamicSpecFilters = {};
  double? _minPrice;
  double? _maxPrice;
  int _filterCount = 0;

  // Spec facets from Typesense
  Map<String, List<Map<String, dynamic>>> _specFacets = {};

  // Typesense pagination (used when spec filters are active)
  int _typesensePage = 0;
  bool _typesenseHasMore = true;

  // Pagination
  static const int _pageSize = 20;
  DocumentSnapshot? _lastDocument;

  // Scroll state
  double _scrollOffset = 0.0;
  double get _overlayOpacity {
    // Base opacity starts at 0.3, increases as user scrolls
    return (0.3 + (_scrollOffset / 200 * 0.4)).clamp(0.3, 0.7);
  }

  double get _titleOpacity {
    // Title becomes visible in header after scrolling 75px (synchronized with header fade)
    return ((_scrollOffset - 75) / 50).clamp(0.0, 1.0);
  }

  // Fixed: Better control for header opacity - smooth fade based on scroll position
  double get _headerOpacity {
    // Header fades out smoothly as user scrolls down
    return (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);
  }

  bool get _showHeaderBackground {
    return _scrollOffset > 50;
  }

  @override
  void initState() {
    super.initState();
    _loadCollectionData();
    _setupScrollListener();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Update scroll offset for smooth transitions
      setState(() {
        _scrollOffset = _scrollController.offset;
      });

      // Load more products
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.8) {
        if (!_isLoadingMore && _hasMore) {
          _loadMoreProducts();
        }
      }
    });
  }

  Future<void> _loadCollectionData() async {
    try {
      setState(() => _isLoading = true);

      // Load collection metadata
      final collectionDoc = await _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('collections')
          .doc(widget.collectionId)
          .get();

      if (!collectionDoc.exists) {
        _showError('Collection not found');
        return;
      }

      _collectionData = collectionDoc.data();
      final productIds =
          List<String>.from(_collectionData!['productIds'] ?? []);

      if (productIds.isEmpty) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        return;
      }

      // Load products and fetch spec facets in parallel
      await Future.wait([
        _loadProducts(productIds),
        _fetchSpecFacets(),
      ]);
    } catch (e) {
      debugPrint('Error loading collection: $e');
      _showError('Failed to load collection');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchSpecFacets() async {
    try {
      final svc = TypeSenseServiceManager.instance.shopService;
      final result = await svc.fetchSpecFacets(
        indexName: 'shop_products',
        additionalFilterBy: 'shopId:=${widget.shopId}',
      );
      if (mounted) {
        setState(() => _specFacets = result);
      }
    } catch (e) {
      debugPrint('Error fetching spec facets: $e');
    }
  }

 Future<void> _loadProducts(List<String> productIds) async {
  try {
    final products = <ProductSummary>[];  // ← changed

    for (int i = 0; i < productIds.length; i += 10) {
      final batch = productIds.skip(i).take(10).toList();

      final snapshot = await _firestore
          .collection('shop_products')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        try {
          final product = ProductSummary.fromDocument(doc);  // ← changed

          if (product.id.trim().isEmpty) {
            debugPrint('Warning: Product with empty ID found in document: ${doc.id}');
            continue;
          }

          products.add(product);
        } catch (e) {
          debugPrint('Error parsing product ${doc.id}: $e');
        }
      }
    }

    products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _products = products;
      _filteredProducts = products;
      _separateBoostedProducts();
    });
  } catch (e) {
    debugPrint('Error loading products: $e');
    _showError('Failed to load products');
  }
}

  void _separateBoostedProducts() {
    _boostedProducts = _filteredProducts.where((p) => p.isBoosted).toList();
    _filteredProducts = _filteredProducts.where((p) => !p.isBoosted).toList();
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore) return;

    // If in Typesense mode, load next page
    if (_dynamicSpecFilters.isNotEmpty) {
      setState(() => _isLoadingMore = true);
      try {
        _typesensePage++;
        final newProducts = await _fetchFromTypesense(page: _typesensePage);
        if (mounted) {
          final existingIds = _filteredProducts.map((p) => p.id).toSet();
          existingIds.addAll(_boostedProducts.map((p) => p.id));
          final deduped = newProducts.where((p) => !existingIds.contains(p.id)).toList();
          setState(() {
            _filteredProducts.addAll(deduped.where((p) => !p.isBoosted));
            _boostedProducts.addAll(deduped.where((p) => p.isBoosted));
            _hasMore = _typesenseHasMore;
            _isLoadingMore = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading more products (Typesense): $e');
        if (mounted) setState(() => _isLoadingMore = false);
      }
      return;
    }

    // Client-side: collection has fixed products, no real pagination
    setState(() {
      _isLoadingMore = false;
      _hasMore = false;
    });
  }

  void _applyFilters() {
    if (_dynamicSpecFilters.isNotEmpty) {
      // Spec filters active — use Typesense
      _applyTypesenseFilters();
      return;
    }

    // Client-side filtering (brands, colors, price only)
    final hasAnyFilter = _dynamicBrands.isNotEmpty ||
        _dynamicColors.isNotEmpty ||
        _minPrice != null ||
        _maxPrice != null;

    if (!hasAnyFilter) {
      _filteredProducts = List.from(_products);
    } else {
      _filteredProducts = _products.where((product) {
        return _matchesClientFilters(product);
      }).toList();
    }

    _separateBoostedProducts();
    _updateFilterCount();
  }

  bool _matchesClientFilters(ProductSummary product) {
    // Brand filter
    if (_dynamicBrands.isNotEmpty) {
      if (!_dynamicBrands.contains(product.brandModel)) {
        return false;
      }
    }

    // Color filter
    if (_dynamicColors.isNotEmpty) {
      final productColors = product.colorImages.keys.toList();
      if (!_dynamicColors.any((color) => productColors.contains(color))) {
        return false;
      }
    }

    // Price filter
    final productPrice = double.tryParse(product.price.toString()) ?? 0.0;
    if (_minPrice != null && productPrice < _minPrice!) {
      return false;
    }
    if (_maxPrice != null && productPrice > _maxPrice!) {
      return false;
    }

    return true;
  }

  Future<void> _applyTypesenseFilters() async {
    setState(() => _isLoading = true);
    try {
      _typesensePage = 0;
      final products = await _fetchFromTypesense(page: 0);
      if (mounted) {
        setState(() {
          _filteredProducts = products;
          _separateBoostedProducts();
          _hasMore = _typesenseHasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error applying Typesense filters: $e');
      if (mounted) setState(() => _isLoading = false);
    }
    _updateFilterCount();
  }

  Future<List<ProductSummary>> _fetchFromTypesense({required int page}) async {
    final svc = TypeSenseServiceManager.instance.shopService;

    final facetFilters = <List<String>>[];
    if (_dynamicBrands.isNotEmpty) {
      facetFilters.add(_dynamicBrands.map((b) => 'brandModel:$b').toList());
    }
    if (_dynamicColors.isNotEmpty) {
      facetFilters.add(_dynamicColors.map((c) => 'availableColors:$c').toList());
    }
    for (final entry in _dynamicSpecFilters.entries) {
      if (entry.value.isNotEmpty) {
        facetFilters.add(entry.value.map((v) => '${entry.key}:$v').toList());
      }
    }

    final numericFilters = <String>[];
    if (_minPrice != null) numericFilters.add('price:>=${_minPrice!.toInt()}');
    if (_maxPrice != null) numericFilters.add('price:<=${_maxPrice!.toInt()}');

    final res = await svc.searchIdsWithFacets(
      indexName: 'shop_products',
      page: page,
      hitsPerPage: 20,
      facetFilters: facetFilters.isNotEmpty ? facetFilters : null,
      numericFilters: numericFilters.isNotEmpty ? numericFilters : null,
      sortOption: 'date',
      additionalFilterBy: 'shopId:=${widget.shopId}',
    );

    _typesenseHasMore = res.page < (res.nbPages - 1);
    return res.hits.map((hit) => ProductSummary.fromTypeSense(hit)).toList();
  }

  void _updateFilterCount() {
    int count = 0;
    count += _dynamicBrands.length;
    count += _dynamicColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    for (final vals in _dynamicSpecFilters.values) {
      count += vals.length;
    }

    setState(() {
      _filterCount = count;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFilterScreen() async {
    try {
      final result = await context.push<Map<String, dynamic>?>(
        '/dynamic_filter',
        extra: {
          'category': '',
          'initialBrands': _dynamicBrands,
          'initialColors': _dynamicColors,
          'initialMinPrice': _minPrice,
          'initialMaxPrice': _maxPrice,
          'initialSpecFilters': _dynamicSpecFilters,
          'availableSpecFacets': _specFacets,
        },
      );

      if (result is Map<String, dynamic>) {
        _handleFilterResult(result);
      }
    } catch (e) {
      debugPrint('Error opening filter screen: $e');
      _showError('Failed to open filters');
    }
  }

  Future<void> _handleFilterResult(Map<String, dynamic> result) async {
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

    _applyFilters();
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

    _applyFilters();
  }

  void _clearAllFilters() {
    setState(() {
      _dynamicBrands.clear();
      _dynamicColors.clear();
      _dynamicSpecFilters.clear();
      _minPrice = null;
      _maxPrice = null;
      _filteredProducts = List.from(_products);
      _separateBoostedProducts();
      _filterCount = 0;
      _hasMore = false;
    });
  }

  void _showImageFullscreen() {
    final imageUrl = _collectionData?['imageUrl'] as String?;
    if (imageUrl == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullScreenImageView(imageUrl: imageUrl),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  // Fixed: New shimmer loading method matching dynamic market style
  Widget _buildShimmerLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

    return Column(
      children: [
        // Cover image shimmer
        Container(
          height: 200,
          width: double.infinity,
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Container(
              color: baseColor,
            ),
          ),
        ),

        // Collection name shimmer
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Container(
              height: 24,
              width: 200,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),

        // Products shimmer
        Expanded(
          child: ListView.builder(
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
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1A29)
          : const Color.fromARGB(255, 244, 244, 244),
      body: Stack(
        children: [
          // Main content
          _isLoading
              ? _buildShimmerLoading() // Fixed: Use shimmer instead of loading indicator
              : _buildContent(l10n, isDark),

          // App bar overlay
          _buildAppBarOverlay(l10n, isDark),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n, bool isDark) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Cover image (always show, but manage visibility through opacity)
        if (_collectionData != null)
          SliverToBoxAdapter(
            child: _buildCoverImage(isDark),
          ),

        // Collection name header
        if (_collectionData != null)
          SliverToBoxAdapter(
            child: _buildCollectionNameHeader(l10n, isDark),
          ),

        // Active filters
        if (_filterCount > 0)
          SliverToBoxAdapter(
            child: _buildActiveFilters(l10n, isDark),
          ),

        // Products grid
        ProductListSliver(
          products: _filteredProducts,
          boostedProducts: _boostedProducts,
          hasMore: _hasMore,
          screenName: 'dynamic_collection_screen',
          isLoadingMore: _isLoadingMore,
          
        ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }

  Widget _buildAppBarOverlay(AppLocalizations l10n, bool isDark) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _showHeaderBackground
              ? (isDark
                  ? const Color(0xFF1C1A29)
                  : const Color.fromARGB(255, 244, 244, 244))
              : Colors.transparent,
          boxShadow: _showHeaderBackground
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Back button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _showHeaderBackground
                        ? (isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05))
                        : (isDark
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.9)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios,
                        color: _showHeaderBackground
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white : Colors.black),
                        size: 20,
                      ),
                      onPressed: () => context.pop(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),

                // Collection name in header (animated)
                if (_titleOpacity > 0)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: AnimatedOpacity(
                        opacity: _titleOpacity,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _collectionData?['name'] ?? l10n.collection,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                const Spacer(),

                // Filter button
                Container(
                  decoration: BoxDecoration(
                    color: _showHeaderBackground
                        ? (isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05))
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _showHeaderBackground
                          ? (isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1))
                          : Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: TextButton.icon(
                    onPressed: _openFilterScreen,
                    icon: Icon(
                      Icons.filter_list,
                      color: _showHeaderBackground
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      _filterCount > 0
                          ? '${l10n.filter} ($_filterCount)'
                          : l10n.filter,
                      style: TextStyle(
                        color: _showHeaderBackground
                            ? (isDark ? Colors.white : Colors.black)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(bool isDark) {
    final imageUrl = _collectionData!['imageUrl'] as String?;

    return GestureDetector(
      onTap: _showImageFullscreen,
      child: Container(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover image
            imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                      child: Icon(
                        Icons.collections_outlined,
                        color: isDark ? Colors.white30 : Colors.grey.shade600,
                        size: 60,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                      child: Icon(
                        Icons.collections_outlined,
                        color: isDark ? Colors.white30 : Colors.grey.shade600,
                        size: 60,
                      ),
                    ),
                  )
                : Container(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                    child: Icon(
                      Icons.collections_outlined,
                      color: isDark ? Colors.white30 : Colors.grey.shade600,
                      size: 60,
                    ),
                  ),

            // Dark overlay (animated based on scroll)
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              color: Colors.black.withOpacity(_overlayOpacity),
            ),
          ],
        ),
      ),
    );
  }

  // Fixed: Improved collection name header with proper fade animation
  Widget _buildCollectionNameHeader(AppLocalizations l10n, bool isDark) {
    return AnimatedOpacity(
      opacity: _headerOpacity,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          _collectionData!['name'] ?? l10n.collection,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilters(AppLocalizations l10n, bool isDark) {
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
                '${l10n.activeFilters} ($_filterCount)',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.purple,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearAllFilters,
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

class _FullScreenImageView extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageView({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen image
          Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
