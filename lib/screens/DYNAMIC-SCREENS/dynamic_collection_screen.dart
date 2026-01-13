import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../models/dynamic_filter.dart';
import '../../widgets/product_list_sliver.dart';
import '../../screens/FILTER-SCREENS/market_screen_dynamic_filters_filter_screen.dart';

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
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Product> _boostedProducts = [];

  // Loading states
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Filter states
  Map<String, dynamic>? _appliedFilters;
  int _filterCount = 0;

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

      // Load products
      await _loadProducts(productIds);
    } catch (e) {
      debugPrint('Error loading collection: $e');
      _showError('Failed to load collection');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProducts(List<String> productIds) async {
  try {
    final products = <Product>[];

    // Load products in batches to avoid Firestore limits
    for (int i = 0; i < productIds.length; i += 10) {
      final batch = productIds.skip(i).take(10).toList();

      final snapshot = await _firestore
          .collection('shop_products')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        try {
          // **FIXED**: Use fromDocument which properly handles doc.id
          final product = Product.fromDocument(doc);
          
          // **VALIDATION**: Check if product ID is valid
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

    // Sort products by creation date (newest first)
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

    setState(() => _isLoadingMore = true);

    try {
      // Since we're loading from a predefined list, we don't need real pagination
      // This is just for consistency with your existing pattern
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isLoadingMore = false;
        _hasMore = false; // Collection has fixed products
      });
    } catch (e) {
      debugPrint('Error loading more products: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  void _applyFilters() {
    if (_appliedFilters == null) {
      _filteredProducts = List.from(_products);
    } else {
      _filteredProducts = _products.where((product) {
        return _matchesFilters(product, _appliedFilters!);
      }).toList();
    }

    _separateBoostedProducts();
    _updateFilterCount();
  }

  bool _matchesFilters(Product product, Map<String, dynamic> filters) {
    // Brand filter
    final selectedBrands = filters['brands'] as List<String>?;
    if (selectedBrands != null && selectedBrands.isNotEmpty) {
      if (!selectedBrands.contains(product.brandModel)) {
        return false;
      }
    }

    // Color filter
    final selectedColors = filters['colors'] as List<String>?;
    if (selectedColors != null && selectedColors.isNotEmpty) {
      final productColors = product.colorImages.keys.toList();
      if (!selectedColors.any((color) => productColors.contains(color))) {
        return false;
      }
    }

    // Price filter
    final minPrice = filters['minPrice'] as double?;
    final maxPrice = filters['maxPrice'] as double?;
    final productPrice = double.tryParse(product.price.toString()) ?? 0.0;

    if (minPrice != null && productPrice < minPrice) {
      return false;
    }
    if (maxPrice != null && productPrice > maxPrice) {
      return false;
    }

    // Category filter
    final selectedCategory = filters['category'] as String?;
    if (selectedCategory != null && product.category != selectedCategory) {
      return false;
    }

    // Subcategory filter
    final selectedSubcategory = filters['subcategory'] as String?;
    if (selectedSubcategory != null &&
        product.subcategory != selectedSubcategory) {
      return false;
    }

    // Sub-subcategory filter
    final selectedSubSubcategory = filters['subSubcategory'] as String?;
    if (selectedSubSubcategory != null &&
        product.subsubcategory != selectedSubSubcategory) {
      return false;
    }

    return true;
  }

  void _updateFilterCount() {
    int count = 0;
    if (_appliedFilters != null) {
      final brands = _appliedFilters!['brands'] as List<String>?;
      final colors = _appliedFilters!['colors'] as List<String>?;
      final minPrice = _appliedFilters!['minPrice'] as double?;
      final maxPrice = _appliedFilters!['maxPrice'] as double?;
      final category = _appliedFilters!['category'] as String?;
      final subcategory = _appliedFilters!['subcategory'] as String?;
      final subSubcategory = _appliedFilters!['subSubcategory'] as String?;

      if (brands != null && brands.isNotEmpty) count++;
      if (colors != null && colors.isNotEmpty) count++;
      if (minPrice != null || maxPrice != null) count++;
      if (category != null) count++;
      if (subcategory != null) count++;
      if (subSubcategory != null) count++;
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
      // Create base filter for shop products
      final baseFilter = DynamicFilter(
        id: 'shopId',
        name: 'shopId',
        displayName: {'en': 'shopId', 'tr': 'shopId', 'ru': 'shopId'},
        isActive: true,
        order: 0,
        type: FilterType.attribute,
        attribute: 'shopId',
        operator: '==',
        attributeValue: widget.shopId,
        collection: 'shop_products',
      );

      final result = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (context) => MarketScreenDynamicFiltersFilterScreen(
            baseFilter: baseFilter,
            initialBrands: _appliedFilters?['brands']?.cast<String>(),
            initialColors: _appliedFilters?['colors']?.cast<String>(),
            initialMinPrice: _appliedFilters?['minPrice']?.toDouble(),
            initialMaxPrice: _appliedFilters?['maxPrice']?.toDouble(),
            initialCategory: _appliedFilters?['category'],
            initialSubcategory: _appliedFilters?['subcategory'],
            initialSubSubcategory: _appliedFilters?['subSubcategory'],
          ),
        ),
      );

      if (result != null) {
        setState(() {
          _appliedFilters = result;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Error opening filter screen: $e');
      _showError('Failed to open filters');
    }
  }

  void _clearAllFilters() {
    setState(() {
      _appliedFilters = null;
      _filteredProducts = List.from(_products);
      _separateBoostedProducts();
      _filterCount = 0;
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.tealAccent.withOpacity(0.1)
            : Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.tealAccent : Colors.teal,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.filter_list,
            color: isDark ? Colors.tealAccent : Colors.teal,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_filterCount ${l10n.filtersApplied}',
              style: TextStyle(
                color: isDark ? Colors.tealAccent : Colors.teal,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearAllFilters,
            child: Text(
              l10n.clear,
              style: TextStyle(
                color: isDark ? Colors.tealAccent : Colors.teal,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
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
