// lib/widgets/productdetail/product_detail_related_products.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/product_detail_provider.dart';
import '../../models/product.dart';
import '../product_card.dart';
import '../../generated/l10n/app_localizations.dart';

class ProductDetailRelatedProducts extends StatefulWidget {
  const ProductDetailRelatedProducts({Key? key}) : super(key: key);

  @override
  State<ProductDetailRelatedProducts> createState() =>
      _ProductDetailRelatedProductsState();
}

class _ProductDetailRelatedProductsState
    extends State<ProductDetailRelatedProducts> {
  bool _loadingInitiated = false;

  @override
  void initState() {
    super.initState();

    // ✅ LAZY LOADING: Trigger loading after widget is built
    // This ensures related products only load when user scrolls to this section
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_loadingInitiated && mounted) {
        _loadingInitiated = true;
        final provider = Provider.of<ProductDetailProvider>(
          context,
          listen: false,
        );
        provider.loadRelatedProductsIfNeeded();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scale factors - must match ProductCard
    final double cardScaleFactor = 0.85;
    final double internalScaleFactor = 1.1;

    // Get screen metrics
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    // Device type detection
    final bool isTablet = screenWidth >= 600;
    final bool isLargeTablet = screenWidth >= 900;
    final bool isTabletPortrait = isTablet && !isLandscape;
    final bool isTabletLandscape = isTablet && isLandscape;

    // Calculate effective scale factor (matching ProductCard's _computeEffectiveScaleFactor)
    double dynamicFactor = (screenWidth / 375).clamp(0.8, 1.2);
    if (isLandscape && dynamicFactor > 1.0) {
      dynamicFactor = 1.0;
    }
    final effectiveScaleFactor = dynamicFactor * cardScaleFactor;

    // Calculate image height (matching ProductCard's _ImageSection logic exactly)
    // ProductCard uses: screenHeight * 0.35 * effectiveScaleFactor
    final double baseImageHeight = screenHeight * 0.35;
    final double actualImageHeight = baseImageHeight * effectiveScaleFactor;

    // Calculate text section height more accurately
    // ProductCard text section contains:
    // - ProductName: ~18px (14 * textScaleFactor where textScaleFactor ≈ effectiveScaleFactor * 0.9 * internalScaleFactor)
    // - RotatingText: ~18px
    // - RatingRow: ~20px (stars + spacing)
    // - PriceRow: ~22px
    // - Padding: vertical ~10px (2 + 3 + various SizedBoxes)
    // - Horizontal padding affects layout
    final double textScaleFactor = effectiveScaleFactor * 0.9 * internalScaleFactor;
    final double textSectionHeight = (18 + 18 + 20 + 22) * textScaleFactor + 15;

    // Banner height (ProductCard adds this at the bottom of image section)
    final double bannerHeight = 20.0 * effectiveScaleFactor;

    // Calculate total card height
    double estimatedCardHeight = actualImageHeight + textSectionHeight + bannerHeight;

    // Apply device-specific adjustments to ensure full visibility
    double listViewHeight;
    double cardWidth;

    if (isLargeTablet) {
      // Large tablets (iPad Pro, etc.) - both orientations
      cardWidth = 200.0;
      // Add extra buffer for large screens where content may scale up
      listViewHeight = isLandscape
          ? estimatedCardHeight.clamp(260.0, 340.0)
          : estimatedCardHeight.clamp(300.0, 420.0);
    } else if (isTabletPortrait) {
      // Regular tablet in portrait
      cardWidth = 185.0;
      // Portrait tablets need controlled height to prevent overflow
      listViewHeight = estimatedCardHeight.clamp(280.0, 380.0);
    } else if (isTabletLandscape) {
      // Regular tablet in landscape
      cardWidth = 180.0;
      // Landscape has limited vertical space
      listViewHeight = estimatedCardHeight.clamp(240.0, 320.0);
    } else if (isLandscape) {
      // Phone in landscape
      cardWidth = 155.0;
      // Very limited vertical space
      listViewHeight = estimatedCardHeight.clamp(200.0, 280.0);
    } else {
      // Phone in portrait (default)
      cardWidth = 160.0;
      listViewHeight = estimatedCardHeight.clamp(280.0, 400.0);
    }

    // Ensure minimum height that can display all card content
    final double minSafeHeight = 250.0;
    if (listViewHeight < minSafeHeight) {
      listViewHeight = minSafeHeight;
    }

    return Selector<ProductDetailProvider,
        ({List<Product> products, bool isLoading})>(
      selector: (context, provider) => (
        products: provider.relatedProducts,
        isLoading: provider.isLoadingRelated,
      ),
      builder: (context, data, child) {
        // Hide widget if loading is complete AND no products found
        if (!data.isLoading && data.products.isEmpty) {
          return const SizedBox.shrink();
        }

        // Show shimmer ONLY while loading
        // Show products when available
        return Container(
          width: double.infinity,
          padding: EdgeInsets.only(bottom: Platform.isIOS ? 12.0 : 0),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color.fromARGB(255, 40, 38, 59)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                spreadRadius: 0,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 10.0),
                child: Text(
                  AppLocalizations.of(context).relatedProducts,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                height: listViewHeight,
                child: ClipRect(
                  child: data.products.isEmpty
                      ? _buildShimmerLoading(listViewHeight, cardWidth, context)
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          itemCount: data.products.length,
                          itemBuilder: (context, index) {
                            final relatedProduct = data.products[index];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: SizedBox(
                                width: cardWidth,
                                // Let the card determine its own height within the container
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ProductCard(
                                    product: relatedProduct.toSummary(),
                                    scaleFactor: cardScaleFactor,
                                    overrideInternalScaleFactor:
                                        internalScaleFactor,
                                    // Pass portrait image height to constrain image size on tablets
                                    portraitImageHeight: isTablet
                                        ? actualImageHeight / effectiveScaleFactor
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoading(double height, double cardWidth, BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final baseColor = isLightMode ? Colors.grey[300]! : const Color(0xFF1C1A29);
    final highlightColor =
        isLightMode ? Colors.grey[100]! : const Color.fromARGB(255, 51, 48, 73);

    // Calculate image height (approximately 68% of total height)
    final imageHeight = height * 0.68;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: SizedBox(
              width: cardWidth,
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image placeholder
                  Container(
                    width: double.infinity,
                    height: imageHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                  ),
                  // Text placeholders
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            width: double.infinity,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            width: cardWidth * 0.6,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            width: cardWidth * 0.4,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
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
        },
      ),
    );
  }
}
