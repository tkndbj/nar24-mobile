import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../generated/l10n/app_localizations.dart';
import '../models/product.dart';
import '../models/bundle.dart';
import '../providers/product_detail_provider.dart';
import '../providers/product_repository.dart';
import '../screens/PRODUCT-SCREENS/product_detail_screen.dart';

class CompactBundleWidget extends StatefulWidget {
  final String productId;
  final String? shopId;

  const CompactBundleWidget({
    Key? key,
    required this.productId,
    this.shopId,
  }) : super(key: key);

  @override
  State<CompactBundleWidget> createState() => _CompactBundleWidgetState();
}

class _CompactBundleWidgetState extends State<CompactBundleWidget>
    with AutomaticKeepAliveClientMixin {
  // Cache the future to prevent rebuilds
  Future<List<CompactBundleDisplayData>>? _bundlesFuture;

  // Cache key to detect when we need to refetch
  String? _lastCacheKey;

  @override
  bool get wantKeepAlive => true; // Keep widget alive during scrolling

  @override
  void initState() {
    super.initState();
    _initializeBundles();
  }

  @override
  void didUpdateWidget(CompactBundleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only refetch if key parameters changed
    if (oldWidget.productId != widget.productId ||
        oldWidget.shopId != widget.shopId) {
      _initializeBundles();
    }
  }

  void _initializeBundles() {
    final cacheKey = '${widget.productId}_${widget.shopId ?? 'null'}';

    // Only create new future if cache key changed
    if (_lastCacheKey != cacheKey) {
      _lastCacheKey = cacheKey;
      _bundlesFuture = _fetchProductBundles();
    }
  }

  // Add static cache for extremely frequent requests
  static final Map<String, Future<List<CompactBundleDisplayData>>>
      _globalCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  Future<List<CompactBundleDisplayData>> _fetchProductBundles() async {
    final cacheKey = '${widget.productId}_${widget.shopId ?? 'null'}';

    // Check global cache first
    if (_globalCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _globalCache[cacheKey]!;
      } else {
        // Remove expired cache
        _globalCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
      }
    }

    // Create and cache new future
    final future = _performBundleFetch();
    _globalCache[cacheKey] = future;
    _cacheTimestamps[cacheKey] = DateTime.now();

    return future;
  }

  Future<List<CompactBundleDisplayData>> _performBundleFetch() async {
    try {
      final firestore = FirebaseFirestore.instance;

      if (widget.shopId == null || widget.shopId!.isEmpty) {
        return [];
      }

      final bundleDisplayList = <CompactBundleDisplayData>[];

      // Find all active bundles in this shop
      final bundlesSnapshot = await firestore
          .collection('bundles')
          .where('shopId', isEqualTo: widget.shopId)
          .where('isActive', isEqualTo: true)
          .get();

      // Process bundles in parallel
      final productFutures = <Future<void>>[];

      for (final bundleDoc in bundlesSnapshot.docs) {
        final bundle = Bundle.fromDocument(bundleDoc);

        // Check if current product is in this bundle
        final productInBundle =
            bundle.products.any((bp) => bp.productId == widget.productId);

        if (!productInBundle) continue;

        // Get all OTHER products in this bundle (not the current one)
        final otherProducts = bundle.products
            .where((bp) => bp.productId != widget.productId)
            .toList();

        // Fetch the actual Product objects for other products
        for (final bundleProduct in otherProducts) {
          productFutures.add(
            _processBundleProduct(
              bundleProduct,
              bundle,
              bundleDisplayList,
            ),
          );
        }
      }

      // Wait for all product fetches to complete
      await Future.wait(productFutures);

      // Remove duplicates and limit results
      final seen = <String>{};
      return bundleDisplayList
          .where((bundle) => seen.add(bundle.product.id))
          .take(5) // Limit to prevent UI overflow
          .toList();
    } catch (e) {
      debugPrint('Error fetching product bundles: $e');
      return [];
    }
  }

  Future<void> _processBundleProduct(
    BundleProduct bundleProduct,
    Bundle bundle,
    List<CompactBundleDisplayData> bundleDisplayList,
  ) async {
    try {
      final productDoc = await FirebaseFirestore.instance
          .collection('shop_products')
          .doc(bundleProduct.productId)
          .get();

      if (productDoc.exists) {
        final product = Product.fromDocument(productDoc);

        // Only show if product is active
        if (product.paused != true) {
          bundleDisplayList.add(CompactBundleDisplayData(
            bundleId: bundle.id,
            product: product,
            totalBundlePrice: bundle.totalBundlePrice,
            totalOriginalPrice: bundle.totalOriginalPrice,
            discountPercentage: bundle.discountPercentage,
            currency: bundle.currency,
            totalProductCount: bundle.products.length,
          ));
        }
      }
    } catch (e) {
      debugPrint(
          'Error processing bundle product ${bundleProduct.productId}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<List<CompactBundleDisplayData>>(
      future: _bundlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final bundles = snapshot.data!;

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? const Color.fromARGB(255, 40, 38, 59)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFF6B35).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompactHeader(bundles.length, l10n, isDark),
              const SizedBox(height: 8),
              _buildCompactBundlesList(bundles, isDark, l10n),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactHeader(
      int bundleCount, AppLocalizations l10n, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFF7931E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.buyTogetherAndSave,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        Text(
          '+$bundleCount',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBundlesList(List<CompactBundleDisplayData> bundles,
      bool isDark, AppLocalizations l10n) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: bundles.length,
        itemBuilder: (context, index) {
          final bundle = bundles[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < bundles.length - 1 ? 8 : 0,
            ),
            child: _CompactBundleProductCard(bundleData: bundle, l10n: l10n),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    // Clean up old cache entries on dispose
    final currentTime = DateTime.now();
    final keysToRemove = <String>[];

    _cacheTimestamps.forEach((key, timestamp) {
      if (currentTime.difference(timestamp) > _cacheExpiry) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _globalCache.remove(key);
      _cacheTimestamps.remove(key);
    }

    super.dispose();
  }
}

class _CompactBundleProductCard extends StatelessWidget {
  final CompactBundleDisplayData bundleData;
  final AppLocalizations l10n;

  const _CompactBundleProductCard({
    Key? key,
    required this.bundleData,
    required this.l10n,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = bundleData.product;
    final savings = bundleData.totalOriginalPrice - bundleData.totalBundlePrice;

    return GestureDetector(
      onTap: () => _navigateToProduct(context),
      child: Container(
        width: 180,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2A2D3A), const Color(0xFF1A1B23)]
                : [Colors.white, const Color(0xFFFAFBFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF6B35).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Compact product image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(7),
                    bottomLeft: Radius.circular(7),
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    child: product.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrls.first,
                            fit: BoxFit.cover,
                            memCacheHeight: 60, // Optimize memory usage
                            memCacheWidth: 60,
                            placeholder: (context, url) => Container(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              child: Icon(
                                Icons.image,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                                size: 16,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              child: Icon(
                                Icons.image_not_supported,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                                size: 16,
                              ),
                            ),
                          )
                        : Container(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                            child: Icon(
                              Icons.image,
                              color: isDark
                                  ? Colors.white30
                                  : Colors.grey.shade400,
                              size: 16,
                            ),
                          ),
                  ),
                ),
                // Compact discount badge
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00A86B), Color(0xFF00875A)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-${bundleData.discountPercentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Product count badge
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          size: 8,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${bundleData.totalProductCount}',
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Compact product details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Product name
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Bundle price label
                    Text(
                      l10n.bundle,
                      style: TextStyle(
                        fontSize: 7,
                        color: isDark ? Colors.white54 : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    // Compact pricing
                    Row(
                      children: [
                        // Bundle price
                        Flexible(
                          child: Text(
                            '${bundleData.totalBundlePrice.toStringAsFixed(2)} ${bundleData.currency}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B35),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Original price
                        Flexible(
                          child: Text(
                            '${bundleData.totalOriginalPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 8,
                              color: isDark ? Colors.white54 : Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Savings
                    Text(
                      l10n.saveAmount(
                          savings.toStringAsFixed(0), bundleData.currency),
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00A86B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToProduct(BuildContext context) {
    try {
      final product = bundleData.product;

      if (product.id.trim().isEmpty) {
        debugPrint('Error: Cannot navigate to product with empty ID');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.productNotAvailable)),
        );
        return;
      }

      final repo = context.read<ProductRepository>();

      final route = PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) =>
            ChangeNotifierProvider(
          create: (_) => ProductDetailProvider(
            productId: product.id,
            repository: repo,
            initialProduct: product,
          ),
          child: ProductDetailScreen(productId: product.id),
        ),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          final tween = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      );

      Navigator.of(context).push(route);
    } catch (e) {
      debugPrint('Error navigating to bundled product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.navigationError(e.toString()))),
      );
    }
  }
}

class CompactBundleDisplayData {
  final String bundleId;
  final Product product;
  final double totalBundlePrice;
  final double totalOriginalPrice;
  final double discountPercentage;
  final String currency;
  final int totalProductCount;

  CompactBundleDisplayData({
    required this.bundleId,
    required this.product,
    required this.totalBundlePrice,
    required this.totalOriginalPrice,
    required this.discountPercentage,
    required this.currency,
    required this.totalProductCount,
  });
}
