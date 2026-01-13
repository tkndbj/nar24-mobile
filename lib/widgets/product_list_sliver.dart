import 'package:flutter/material.dart';
import 'dart:io';
import '../generated/l10n/app_localizations.dart';
import '../models/product.dart';
import 'product_card.dart';
import 'boostedVisibilityWrapper.dart';

class ProductListSliver extends StatelessWidget {
  final List<Product> products;
  final List<Product> boostedProducts;
  final bool hasMore;
  final bool isLoadingMore;
  final String? selectedColor;
  final String screenName;

  const ProductListSliver({
    Key? key,
    required this.products,
    required this.boostedProducts,
    required this.hasMore,
    required this.isLoadingMore,
    this.selectedColor,
    required this.screenName,
  }) : super(key: key);

  // Determine if current device is a tablet
  bool _isTablet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final orientation = mediaQuery.orientation;

    // Consider it a tablet if:
    // 1. Shortest side is >= 600dp (standard tablet breakpoint)
    // 2. OR if in landscape and width >= 900dp
    final shortestSide =
        orientation == Orientation.portrait ? screenWidth : screenHeight;
    return shortestSide >= 600 ||
        (orientation == Orientation.landscape && screenWidth >= 900);
  }

  // Calculate optimal number of columns based on screen size and orientation
  int _calculateCrossAxisCount(BuildContext context) {
    if (!_isTablet(context)) {
      return 2; // Always 2 for mobile devices
    }

    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;
    final screenWidth = mediaQuery.size.width;

    if (orientation == Orientation.portrait) {
      // Tablet portrait: 4 columns
      return 4;
    } else {
      // Tablet landscape: 6 columns for large tablets, 4 for smaller ones
      return screenWidth >= 1200 ? 6 : 5;
    }
  }

  // Calculate responsive card dimensions
  Map<String, double> _calculateCardDimensions(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final crossAxisCount = _calculateCrossAxisCount(context);
    final isTablet = _isTablet(context);

    // Image height calculation
    double imageHeight;
    if (isTablet) {
      // For tablets, use a smaller percentage to fit more content
      final orientation = mediaQuery.orientation;
      if (orientation == Orientation.portrait) {
        imageHeight = screenHeight * 0.22; // Reduced from 0.30
      } else {
        imageHeight = screenHeight * 0.28; // Landscape needs slightly more
      }
    } else {
      imageHeight = screenHeight * 0.30; // Keep original mobile size
    }

    // Info area height - increased for tablets to prevent info section from being obscured
    final double infoAreaHeight = isTablet ? 100.0 : 90.0;
    final double cardHeight = imageHeight + infoAreaHeight;

    // Platform-specific padding
    final double extraPadding =
        Platform.isIOS ? (isTablet ? 20.0 : 25.0) : (isTablet ? 8.0 : 10.0);
    final double totalCardHeight = cardHeight + extraPadding;

    // Spacing calculations
    final double crossAxisSpacing = isTablet
        ? (Platform.isIOS ? 16.0 : 14.0)
        : (Platform.isIOS ? 14.0 : 12.0);

    final double mainAxisSpacing = isTablet
        ? (Platform.isIOS ? 44.0 : 40.0)
        : (Platform.isIOS ? 20.0 : 16.0);

    // Calculate available width and card width
    final double horizontalPadding = isTablet
        ? (Platform.isIOS ? 16.0 : 12.0)
        : (Platform.isIOS ? 20.0 : 16.0);

    final double availableWidth = screenWidth - horizontalPadding;
    final double totalSpacing = crossAxisSpacing * (crossAxisCount - 1);
    final double cardWidth = (availableWidth - totalSpacing) / crossAxisCount;

    // Calculate aspect ratio
    final double aspectRatio = cardWidth / totalCardHeight;

    return {
      'imageHeight': imageHeight,
      'cardHeight': cardHeight,
      'totalCardHeight': totalCardHeight,
      'crossAxisSpacing': crossAxisSpacing,
      'mainAxisSpacing': mainAxisSpacing,
      'aspectRatio': aspectRatio,
      'horizontalPadding':
          horizontalPadding / 2, // Divide by 2 for symmetric padding
    };
  }

  @override
  Widget build(BuildContext context) {
    final boostedIds = boostedProducts.map((p) => p.id).toSet();
    final combinedProducts = <Product>[
      ...boostedProducts,
      ...products.where((p) => !boostedIds.contains(p.id)),
    ];

    if (combinedProducts.isEmpty && !isLoadingMore) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(AppLocalizations.of(context).noProductsFound),
        ),
      );
    }

    final crossAxisCount = _calculateCrossAxisCount(context);
    final dimensions = _calculateCardDimensions(context);
    final isTablet = _isTablet(context);

    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: dimensions['horizontalPadding']!,
        vertical: isTablet
            ? (Platform.isIOS ? 12.0 : 10.0)
            : (Platform.isIOS ? 8.0 : 6.0),
      ),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: dimensions['mainAxisSpacing']!,
          crossAxisSpacing: dimensions['crossAxisSpacing']!,
          childAspectRatio: dimensions['aspectRatio']!,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index < combinedProducts.length) {
              final product = combinedProducts[index];

              // ✅ OPTIMIZATION: Wrap in RepaintBoundary to prevent unnecessary repaints
              Widget card = RepaintBoundary(
                child: Container(
                  height: dimensions['totalCardHeight'],
                  child: ProductCard(
                    key: ValueKey(product.id),
                    product: product,
                    selectedColor: selectedColor,
                    portraitImageHeight: dimensions['imageHeight']!,
                  ),
                ),
              );

              if (product.isBoosted) {
                card = BoostedVisibilityWrapper(
                  productId: product.id,
                  screenName: screenName,
                  child: card,
                );
              }

              return card;
            }

            if (isLoadingMore) {
              return Container(
                height: dimensions['totalCardHeight'],
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 12 : 16),
                    child: CircularProgressIndicator(
                      strokeWidth: isTablet ? 2.0 : 3.0,
                    ),
                  ),
                ),
              );
            }

            return const SizedBox.shrink();
          },
          childCount: combinedProducts.length + (isLoadingMore ? 1 : 0),
        ),
      ),
    );
  }
}
