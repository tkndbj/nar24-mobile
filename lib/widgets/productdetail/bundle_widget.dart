import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../models/bundle.dart';
import '../../providers/product_detail_provider.dart';
import '../../providers/product_repository.dart';
import '../../screens/PRODUCT-SCREENS/product_detail_screen.dart';
import 'package:shimmer/shimmer.dart';

class ProductBundleWidget extends StatefulWidget {
  final String productId;
  final String? shopId;

  const ProductBundleWidget({
    Key? key,
    required this.productId,
    this.shopId,
  }) : super(key: key);

  @override
  State<ProductBundleWidget> createState() => _ProductBundleWidgetState();
}

class _ProductBundleWidgetState extends State<ProductBundleWidget>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<BundleDisplayData>> _bundlesFuture;

  @override
  void initState() {
    super.initState();
    _bundlesFuture = _fetchProductBundles();
  }

  @override
  bool get wantKeepAlive => true;

  Future<List<BundleDisplayData>> _fetchProductBundles() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Only proceed if we have a shopId
      if (widget.shopId == null || widget.shopId!.isEmpty) {
        return [];
      }

      final bundleDisplayList = <BundleDisplayData>[];

      // Find all active bundles in this shop
      final bundlesSnapshot = await firestore
          .collection('bundles')
          .where('shopId', isEqualTo: widget.shopId)
          .where('isActive', isEqualTo: true)
          .get();

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
          try {
            final productDoc = await firestore
                .collection('shop_products')
                .doc(bundleProduct.productId)
                .get();

            if (productDoc.exists) {
              final product = Product.fromDocument(productDoc);

              // Only show if product is active
              if (product.paused != true) {
                bundleDisplayList.add(BundleDisplayData(
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
                'Error fetching bundled product ${bundleProduct.productId}: $e');
          }
        }
      }

      return bundleDisplayList;
    } catch (e) {
      debugPrint('Error fetching product bundles: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<List<BundleDisplayData>>(
      future: _bundlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState(isDark);
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final bundles = snapshot.data!;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(bundles.length, l10n, isDark),
              const SizedBox(height: 12),
              _buildBundlesList(bundles, isDark, l10n),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(bool isDark) {
    final baseColor = isDark ? const Color(0xFF1C1A29) : Colors.grey[300]!;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 51, 48, 73) : Colors.grey[100]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 200,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 150,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 2,
                itemBuilder: (_, idx) => Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int bundleCount, AppLocalizations l10n, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFF7931E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.buyTogetherAndSave,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                l10n.specialBundleOffersWithThisProduct,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBundlesList(
      List<BundleDisplayData> bundles, bool isDark, AppLocalizations l10n) {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: bundles.length,
        itemBuilder: (context, index) {
          final bundle = bundles[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < bundles.length - 1 ? 16 : 0,
            ),
            child: _BundleProductCard(bundleData: bundle, l10n: l10n),
          );
        },
      ),
    );
  }
}

class _BundleProductCard extends StatelessWidget {
  final BundleDisplayData bundleData;
  final AppLocalizations l10n;

  const _BundleProductCard({
    Key? key,
    required this.bundleData,
    required this.l10n,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = bundleData.product;
    final savings = bundleData.totalOriginalPrice - bundleData.totalBundlePrice;
    final savingsPercent = bundleData.discountPercentage;

    return GestureDetector(
      onTap: () {
        _navigateToProduct(context);
      },
      child: Container(
        width: 280,
        height: 110,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2A2D3A), const Color(0xFF1A1B23)]
                : [Colors.white, const Color(0xFFFAFBFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF6B35).withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Product image with bundle indicator
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                  child: Container(
                    width: 110,
                    height: 110,
                    child: product.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrls.first,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              child: Icon(
                                Icons.image,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                                size: 24,
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
                                size: 24,
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
                              size: 24,
                            ),
                          ),
                  ),
                ),
                // Discount badge with jade green color
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00A86B), Color(0xFF00875A)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '-${savingsPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Bundle indicator showing product count
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${bundleData.totalProductCount}',
                          style: const TextStyle(
                            fontSize: 9,
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

            // Product details with bundle pricing
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Product name with flexible layout
                    Flexible(
                      child: Text(
                        product.productName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Pricing with flexible layout
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bundle price label
                          Text(
                            l10n.bundlePrice,
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Bundle price and original price row
                          Row(
                            children: [
                              // Bundle price
                              Flexible(
                                child: Text(
                                  '${bundleData.totalBundlePrice.toStringAsFixed(2)} ${bundleData.currency}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6B35),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Original price
                              Flexible(
                                child: Text(
                                  '${bundleData.totalOriginalPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        isDark ? Colors.white54 : Colors.grey,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Savings amount
                          Text(
                            l10n.saveAmount(savings.toStringAsFixed(2),
                                bundleData.currency),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00A86B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
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

class BundleDisplayData {
  final String bundleId;
  final Product product;
  final double totalBundlePrice;
  final double totalOriginalPrice;
  final double discountPercentage;
  final String currency;
  final int totalProductCount;

  BundleDisplayData({
    required this.bundleId,
    required this.product,
    required this.totalBundlePrice,
    required this.totalOriginalPrice,
    required this.discountPercentage,
    required this.currency,
    required this.totalProductCount,
  });
}
