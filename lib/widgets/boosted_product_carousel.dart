import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/boosted_rotation_provider.dart';
import '../../models/product_summary.dart';
import 'product_card.dart';
import '../generated/l10n/app_localizations.dart';
import 'package:shimmer/shimmer.dart';

class BoostedProductsCarousel extends StatelessWidget {
  const BoostedProductsCarousel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    final double portraitImageHeight = screenHeight * 0.33; // Increased from 0.30 for taller images
    const double infoAreaHeight = 80.0;
    final double rowHeight = portraitImageHeight + infoAreaHeight;

    return Consumer<BoostedRotationProvider>(
      builder: (context, provider, child) {
        // Show shimmer only on initial load
        if (provider.isLoading && !provider.hasProducts) {
          return _buildShimmer(rowHeight, isDarkMode);
        }

        // Hide section if no products and not loading
        if (!provider.hasProducts && !provider.isLoading) {
          return const SizedBox.shrink();
        }

        // Show error state if error occurred and no cached data
        if (provider.error != null && !provider.hasProducts) {
          return _buildErrorState(l10n, provider, rowHeight);
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          width: double.infinity,
          child: Stack(
            children: [
              // Background gradient (half height)
              Container(
                width: double.infinity,
                height: rowHeight / 2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(l10n, provider),
                    const SizedBox(height: 8.0),
                    _buildProductList(
                      context,
                      provider.boostedProducts.map((p) => p.toSummary()).toList(),
                      rowHeight,
                      portraitImageHeight,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    AppLocalizations l10n,
    BoostedRotationProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.boostedProducts ?? 'Boosted Products',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // Show loading indicator when refreshing existing data
              if (provider.isLoading && provider.hasProducts)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 12,
                  height: 12,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
              // Show total count if more than 10
              if (provider.totalBoosted > 10)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${provider.totalBoosted}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    AppLocalizations l10n,
    BoostedRotationProvider provider,
    double rowHeight,
  ) {
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
                colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
              ),
            ),
          ),
          // Error message
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white70,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.failedToLoadBoostedProducts ?? 'Failed to load',
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton(
                  onPressed: () => provider.refresh(),
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

  Widget _buildShimmer(double rowHeight, bool isDarkMode) {
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
                colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
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
                      width: 180,
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
                        width: 170,
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

  Widget _buildProductList(
    BuildContext context,
    List<ProductSummary> products, // Changed from List<dynamic>
    double rowHeight,
    double portraitImageHeight,
  ) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final scaleFactor = isLandscape ? 0.92 : 0.88;
    const overrideInnerScale = 1.2;

    return SizedBox(
      height: rowHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        padding: const EdgeInsets.only(left: 8.0),
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final product =
              products[index]; // Already Product type, no conversion needed

          return Container(
            width: 170,
            margin: const EdgeInsets.only(right: 6.0),
            child: Stack(
              children: [
                ProductCard(
                  key: ValueKey(product.id),
                  product: product,
                  scaleFactor: scaleFactor,
                  internalScaleFactor: 1.0,
                  portraitImageHeight: portraitImageHeight,
                  overrideInternalScaleFactor: overrideInnerScale,
                  showCartIcon: false,
                ),
                // Boost indicator badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'BOOSTED',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
