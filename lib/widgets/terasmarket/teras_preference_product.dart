import 'package:flutter/material.dart';
import '../../services/personalized_feed_service.dart';
import '../../models/product.dart';
import '../product_card.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class TerasPreferenceProduct extends StatefulWidget {
  const TerasPreferenceProduct({Key? key}) : super(key: key);

  static void clearCache() {
    _TerasPreferenceProductState.clearCache();
  }

  @override
  State<TerasPreferenceProduct> createState() => _TerasPreferenceProductState();
}

class _TerasPreferenceProductState extends State<TerasPreferenceProduct> {
  final PersonalizedFeedService _feedService = PersonalizedFeedService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static List<Product>? _cachedProducts;
  static DateTime? _productsCacheExpiry;
  static const Duration _productsCacheDuration = Duration(hours: 1);

  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  /// Load recommendations using the new service
  Future<void> _loadRecommendations() async {
    if (!mounted) return;

    // ✅ CHECK CACHE FIRST: Return cached products if still valid
    if (_cachedProducts != null &&
        _cachedProducts!.isNotEmpty &&
        _productsCacheExpiry != null &&
        _productsCacheExpiry!.isAfter(DateTime.now())) {
      debugPrint(
          '✅ Using cached preference products (${_cachedProducts!.length})');
      setState(() {
        _products = _cachedProducts!;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get product IDs from the service
      final productIds = await _feedService.getProductIds();

      if (productIds.isEmpty) {
        setState(() {
          _products = [];
          _isLoading = false;
        });
        return;
      }

      // ✅ RANDOM SAMPLING: Pick 30 random IDs from the 200
      final randomProductIds = _getRandomSample(productIds, 30);

      // Fetch product details (batch read - max 30 for this widget)
      final products = await _fetchProductDetails(randomProductIds);

      // ✅ CACHE THE PRODUCTS
      _cachedProducts = products;
      _productsCacheExpiry = DateTime.now().add(_productsCacheDuration);
      debugPrint('📦 Cached ${products.length} preference products for 1 hour');

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading personalized feed: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> refresh() async {
    // ✅ Clear the static cache
    _cachedProducts = null;
    _productsCacheExpiry = null;

    await _feedService.forceRefresh();
    await _loadRecommendations();
  }

  /// ✅ ADD: Static method to clear cache (call on logout or when needed)
  static void clearCache() {
    _cachedProducts = null;
    _productsCacheExpiry = null;
    debugPrint('🧹 Cleared preference products cache');
  }

  /// ✅ Efficient random sampling without modifying original list
  List<String> _getRandomSample(List<String> items, int sampleSize) {
    if (items.length <= sampleSize) {
      return List.from(items); // Return all if fewer than requested
    }

    final random = Random();
    final indices = <int>{};

    // Generate unique random indices
    while (indices.length < sampleSize) {
      indices.add(random.nextInt(items.length));
    }

    // Return items at those indices
    return indices.map((i) => items[i]).toList();
  }

  /// Fetch product details from Firestore in batches
  Future<List<Product>> _fetchProductDetails(List<String> productIds) async {
    if (productIds.isEmpty) return [];

    final products = <Product>[];

    // Firestore whereIn limit is 30, so we're safe with take(30)
    final snapshot = await _firestore
        .collection('shop_products')
        .where(FieldPath.documentId, whereIn: productIds)
        .get();

    for (final doc in snapshot.docs) {
      try {
        products.add(Product.fromDocument(doc));
      } catch (e) {
        debugPrint('Error parsing product ${doc.id}: $e');
      }
    }

    // Maintain order from productIds
    final productMap = {for (var p in products) p.id: p};
    return productIds
        .where((id) => productMap.containsKey(id))
        .map((id) => productMap[id]!)
        .toList();
  }

  /// Force refresh (pulls fresh data from backend)
  Future<void> _refresh() async {
    await _feedService.forceRefresh();
    await _loadRecommendations();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Detect tablet and orientation
    final bool isTablet = screenWidth >= 600;
    final bool isLandscape = screenWidth > screenHeight;
    final bool isTabletLandscape = isTablet && isLandscape;

    // Tablet landscape: increase info area height to prevent overlap with TerasProductList
    // Other views remain unchanged
    final double portraitImageHeight = isTablet ? screenHeight * 0.22 : screenHeight * 0.30;
    final double infoAreaHeight = isTabletLandscape ? 110.0 : (isTablet ? 95.0 : 80.0);
    final double rowHeight = portraitImageHeight + infoAreaHeight;

    // Card width - wider on tablets
    final double cardWidth = isTablet ? 195.0 : 170.0;

    // Show shimmer on initial load
    if (_isLoading && _products.isEmpty) {
      return _buildShimmer(rowHeight, cardWidth, isDarkMode);
    }

    // Hide section if no products
    if (_products.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    // Show error state (with retry)
    if (_error != null && _products.isEmpty) {
      return _buildErrorState(l10n, rowHeight);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      width: double.infinity,
      child: Stack(
        children: [
          // Background gradient
          Container(
            width: double.infinity,
            height: rowHeight / 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.purple, Colors.pink],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(l10n),
                const SizedBox(height: 8.0),
                _buildProductList(rowHeight, portraitImageHeight, cardWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                l10n.specialProductsForYou,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // Show loading indicator when refreshing
              if (_isLoading && _products.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 12,
                  height: 12,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
            ],
          ),
          GestureDetector(
            onTap: () => context.push("/special-for-you"),
            child: Text(
              l10n.viewAll,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n, double rowHeight) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      height: rowHeight / 2,
      child: Stack(
        children: [
          // Background gradient
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.orange, Colors.pink],
              ),
            ),
          ),
          // Error message
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.white70, size: 32),
                const SizedBox(height: 8),
                Text(
                  l10n.failedToLoadRecommendations ?? 'Failed to load',
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton(
                  onPressed: _refresh,
                  child: Text(
                    l10n.retry ?? 'Retry',
                    style: const TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(double rowHeight, double cardWidth, bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: rowHeight / 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.orange, Colors.pink],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                  child: Shimmer.fromColors(
                    baseColor: Colors.white70,
                    highlightColor: Colors.white,
                    child: Container(
                      height: 20,
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                SizedBox(
                  height: rowHeight,
                  child: Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 8.0),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) => Container(
                        width: cardWidth,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(double rowHeight, double portraitImageHeight, double cardWidth) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final scaleFactor = isLandscape ? 0.92 : 0.88;
    const overrideInnerScale = 1.2;

    return SizedBox(
      height: rowHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _products.length,
        padding: const EdgeInsets.only(left: 8.0),
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final product = _products[index];

          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 6.0),
            child: ProductCard(
              key: ValueKey(product.id),
              product: product,
              scaleFactor: scaleFactor,
              internalScaleFactor: 1.0,
              portraitImageHeight: portraitImageHeight,
              overrideInternalScaleFactor: overrideInnerScale,
              showCartIcon: false,
            ),
          );
        },
      ),
    );
  }
}
