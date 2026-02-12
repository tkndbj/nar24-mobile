// ===============================================
// OPTIMIZED dynamic_product_list_widget.dart
// One-time fetch pattern - NO LISTENERS
// ===============================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../models/product_summary.dart';
import 'product_card.dart';

class DynamicProductListsWidget extends StatefulWidget {
  const DynamicProductListsWidget({Key? key}) : super(key: key);

  @override
  State<DynamicProductListsWidget> createState() =>
      _DynamicProductListsWidgetState();
}

class _DynamicProductListsWidgetState extends State<DynamicProductListsWidget>
    with AutomaticKeepAliveClientMixin {
  // ✅ Memory limits
  static const int _maxCachedLists = 10;
  static const int _maxProductsPerList = 20;

  // ✅ NEW: Lists data (one-time fetch)
  List<Map<String, dynamic>> _lists = [];
  bool _isLoadingLists = true;
  String? _listsError;

  final Map<String, List<ProductSummary>> _productCache = {};
  final Map<String, bool> _loadingStates = {};
  final Set<String> _shouldLoadLists = {};

  // LRU tracking
  final Map<String, DateTime> _listAccessTimes = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchDynamicLists();
  }

  @override
  void dispose() {
    _productCache.clear();
    _loadingStates.clear();
    _shouldLoadLists.clear();
    _listAccessTimes.clear();
    _lists.clear();
    super.dispose();
  }

  /// ✅ NEW: One-time fetch for dynamic lists configuration
  Future<void> _fetchDynamicLists() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLists = true;
      _listsError = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('dynamic_product_lists')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();

      if (!mounted) return;

      final lists = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _lists = lists;
        _isLoadingLists = false;
      });

      debugPrint('✅ Fetched ${lists.length} dynamic product lists (one-time)');
    } catch (e) {
      debugPrint('❌ Error fetching dynamic lists: $e');
      if (mounted) {
        setState(() {
          _listsError = e.toString();
          _isLoadingLists = false;
        });
      }
    }
  }

  /// ✅ NEW: Manual refresh method
  Future<void> refresh() async {
    _productCache.clear();
    _loadingStates.clear();
    _shouldLoadLists.clear();
    _listAccessTimes.clear();
    await _fetchDynamicLists();
  }

  /// Enforce cache limits with LRU eviction
  void _enforceCacheLimit() {
    if (_productCache.length <= _maxCachedLists) return;

    final sortedLists = _listAccessTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    while (_productCache.length > _maxCachedLists && sortedLists.isNotEmpty) {
      final oldestList = sortedLists.removeAt(0);
      _productCache.remove(oldestList.key);
      _loadingStates.remove(oldestList.key);
      _listAccessTimes.remove(oldestList.key);

      debugPrint('🗑️ Evicted product list cache: ${oldestList.key}');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Loading state
    if (_isLoadingLists) {
      return _buildLoadingPlaceholder();
    }

    // Error state
    if (_listsError != null) {
      debugPrint('Error loading dynamic lists: $_listsError');
      return const SizedBox.shrink();
    }

    // Empty state
    if (_lists.isEmpty) {
      return const SizedBox.shrink();
    }

    // Detect tablet for spacing adjustments
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth >= 600;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Tablet-specific bottom padding to prevent overlap
    final double listBottomPadding =
        isTablet ? (isLandscape ? 32.0 : 26.0) : 18.0;

    return Column(
      children: _lists.map((listData) {
        final listId = listData['id'] as String;
        return Padding(
          padding: EdgeInsets.only(bottom: listBottomPadding),
          child: _ProductListSection(
            listId: listId,
            listData: listData,
            onVisibilityChanged: _handleVisibilityChanged,
            shouldLoad: _shouldLoadLists.contains(listId),
            cachedProducts: _productCache[listId],
            isLoading: _loadingStates[listId] ?? false,
            onProductsLoaded: (products) {
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _productCache[listId] =
                          products.take(_maxProductsPerList).toList();
                      _loadingStates[listId] = false;
                      _listAccessTimes[listId] = DateTime.now();
                    });

                    _enforceCacheLimit();
                  }
                });
              }
            },
            onLoadingStateChanged: (isLoading) {
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _loadingStates[listId] = isLoading;
                    });
                  }
                });
              }
            },
          ),
        );
      }).toList(),
    );
  }

  void _handleVisibilityChanged(String listId, bool isVisible) {
    final wasMarkedForLoading = _shouldLoadLists.contains(listId);

    if (isVisible && !wasMarkedForLoading) {
      debugPrint('👁️ List $listId became visible');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _shouldLoadLists.add(listId);
          });
        }
      });
    }
  }

  Widget _buildLoadingPlaceholder() {
    return SizedBox(
      height: 200,
      child: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

class _ProductListSection extends StatefulWidget {
  final String listId;
  final Map<String, dynamic> listData;
  final Function(String, bool) onVisibilityChanged;
  final bool shouldLoad;
  final List<ProductSummary>? cachedProducts;
  final bool isLoading;
  final Function(List<ProductSummary>) onProductsLoaded;
  final Function(bool) onLoadingStateChanged;

  const _ProductListSection({
    Key? key,
    required this.listId,
    required this.listData,
    required this.onVisibilityChanged,
    required this.shouldLoad,
    this.cachedProducts,
    required this.isLoading,
    required this.onProductsLoaded,
    required this.onLoadingStateChanged,
  }) : super(key: key);

  @override
  State<_ProductListSection> createState() => _ProductListSectionState();
}

class _ProductListSectionState extends State<_ProductListSection> {
  bool _hasStartedLoading = false;
  bool _isLocalLoading = false;

  // Prevent duplicate loads
  bool _isFetching = false;

  @override
  void didUpdateWidget(_ProductListSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.shouldLoad &&
        !_hasStartedLoading &&
        widget.cachedProducts == null &&
        !_isLocalLoading &&
        !_isFetching) {
      _hasStartedLoading = true;
      _isLocalLoading = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadProducts();
        }
      });
    }
  }

  Future<void> _loadProducts() async {
    if (widget.cachedProducts != null || _isFetching) {
      return;
    }

    _isFetching = true;
    widget.onLoadingStateChanged(true);

    try {
      final products = await _fetchProducts();

      if (mounted) {
        _isLocalLoading = false;
        widget.onProductsLoaded(products);
      }
    } catch (e) {
      debugPrint('Error loading products for list ${widget.listId}: $e');
      if (mounted) {
        _isLocalLoading = false;
        widget.onLoadingStateChanged(false);
      }
    } finally {
      _isFetching = false;
    }
  }

  Future<List<ProductSummary>> _fetchProducts() async {
    final listData = widget.listData;
    List<ProductSummary> products = [];

    try {
      if (listData['selectedProductIds'] != null &&
          (listData['selectedProductIds'] as List).isNotEmpty) {
        final List<String> productIds =
            List<String>.from(listData['selectedProductIds']);

        debugPrint(
            'Fetching ${productIds.length} products for ${widget.listId}');

        const batchSize = 10;
        const maxProducts = 20;

        int fetchedCount = 0;

        for (int i = 0;
            i < productIds.length && fetchedCount < maxProducts;
            i += batchSize) {
          if (!mounted) break;

          final end = (i + batchSize < productIds.length)
              ? i + batchSize
              : productIds.length;
          final batch = productIds.sublist(i, end);

          final batchDocs = await FirebaseFirestore.instance
              .collection('shop_products')
              .where(FieldPath.documentId, whereIn: batch)
              .get()
              .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('⚠️ Timeout fetching batch for ${widget.listId}');
              return FirebaseFirestore.instance
                  .collection('shop_products')
                  .limit(0)
                  .get();
            },
          );

          for (var doc in batchDocs.docs) {
            if (!mounted || fetchedCount >= maxProducts) break;
            products.add(ProductSummary.fromDocument(doc));
            fetchedCount++;
          }
        }
      } else if (listData['selectedShopId'] != null &&
          listData['selectedShopId'].toString().isNotEmpty) {
        final String shopId = listData['selectedShopId'].toString();
        final int limit = (listData['limit'] ?? 10).clamp(1, 20);

        debugPrint('Fetching products from shop $shopId with limit $limit');

        final snapshot = await FirebaseFirestore.instance
            .collection('shop_products')
            .where('shopId', isEqualTo: shopId)
            .limit(limit)
            .get()
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint(
                '⚠️ Timeout fetching shop products for ${widget.listId}');
            return FirebaseFirestore.instance
                .collection('shop_products')
                .limit(0)
                .get();
          },
        );

        if (mounted) {
          products =
              snapshot.docs.map((doc) => ProductSummary.fromDocument(doc)).toList();
        }
      }

      debugPrint('✅ Loaded ${products.length} products for ${widget.listId}');
      return products;
    } catch (e) {
      debugPrint('❌ Error fetching products: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final bool isTablet = screenWidth >= 600;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    double effectiveScaleFactor = (screenWidth / 375).clamp(0.8, 1.2);
    if (isLandscape && effectiveScaleFactor > 1.0) {
      effectiveScaleFactor = 1.0;
    }

    final double portraitImageHeight = isTablet
        ? (isLandscape ? screenHeight * 0.31 : screenHeight * 0.24)
        : screenHeight * 0.33;

    final double baseInfoHeight = 87.0;
    final double infoAreaHeight = isTablet
        ? (isLandscape ? 105.0 : 100.0)
        : (baseInfoHeight * effectiveScaleFactor).clamp(80.0, 105.0);

    final double rowHeight = portraitImageHeight + infoAreaHeight;

    final double cardWidth = isTablet ? 195.0 : 170.0;

    final double headerAreaHeight = 48.0;

    return VisibilityDetector(
      key: Key('visibility_${widget.listId}'),
      onVisibilityChanged: (info) {
        final isVisible = info.visibleFraction > 0.2;
        widget.onVisibilityChanged(widget.listId, isVisible);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        width: double.infinity,
        height:
            rowHeight + headerAreaHeight + (isTablet ? (isLandscape ? 8 : 4) : 0),
        clipBehavior: Clip.none,
        child: Stack(
          children: [
            _buildGradientBackground(rowHeight),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 8.0),
                  Expanded(
                    child: ClipRect(
                      clipBehavior: Clip.none,
                      child: _buildProductsContent(
                          context, cardWidth, portraitImageHeight),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientBackground(double height) {
    final Color startColor =
        _parseColor(widget.listData['gradientStart'] ?? '#FF6B35');
    final Color endColor =
        _parseColor(widget.listData['gradientEnd'] ?? '#FF8A65');

    return Container(
      width: double.infinity,
      height: height / 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [startColor, endColor],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.listData['title'] ?? 'Product List',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsContent(
      BuildContext context, double cardWidth, double portraitImageHeight) {
    if (widget.cachedProducts != null) {
      if (widget.cachedProducts!.isEmpty) {
        return _buildEmptyState();
      }
      return _buildProductsList(
          widget.cachedProducts!, cardWidth, portraitImageHeight);
    }

    if (!widget.shouldLoad || _isLocalLoading || widget.isLoading) {
      return _buildShimmer(context, cardWidth);
    }

    return _buildEmptyState();
  }

  Widget _buildProductsList(
      List<ProductSummary> products, double cardWidth, double portraitImageHeight) {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double scaleFactor = isLandscape ? 0.92 : 0.88;

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      padding: const EdgeInsets.only(left: 8.0),
      physics: const BouncingScrollPhysics(),
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final product = products[index];
        return Container(
          width: cardWidth,
          margin: const EdgeInsets.only(right: 6.0),
          child: ProductCard(
            product: product,
            scaleFactor: scaleFactor,
            internalScaleFactor: 1.0,
            portraitImageHeight: portraitImageHeight,
            overrideInternalScaleFactor: 1.2,
            showCartIcon: false,
          ),
        );
      },
    );
  }

  Widget _buildShimmer(BuildContext context, double cardWidth) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) => Container(
          width: cardWidth,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: Colors.white54,
            size: 32,
          ),
          SizedBox(height: 8),
          Text(
            'No products available',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
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
}