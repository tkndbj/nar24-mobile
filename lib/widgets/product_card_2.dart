import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../providers/cart_provider.dart';
import '../providers/favorite_product_provider.dart';

class ProductCard2 extends StatelessWidget {
  final String imageUrl;
  final Map<String, List<String>> colorImages;
  final String? selectedColor;
  final String productName;
  final double price;
  final String currency;
  final double averageRating;
  final Timestamp? transactionTimestamp;
  final double scaleFactor;
  final bool showOverlayIcons;
  final String? productId;
  final VoidCallback? onFavoriteToggled;
  final double? originalPrice; // New parameter for original price
  final int? discountPercentage; // New parameter for discount percentage

  const ProductCard2({
    Key? key,
    required this.imageUrl,
    required this.colorImages,
    this.selectedColor,
    required this.productName,
    required this.price,
    required this.currency,
    this.averageRating = 0.0,
    this.transactionTimestamp,
    this.scaleFactor = 1.0,
    this.showOverlayIcons = false,
    this.productId,
    this.onFavoriteToggled,
    this.originalPrice,
    this.discountPercentage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkMode ? Colors.grey[700]! : Colors.grey[300]!;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final priceColor = isDarkMode ? Colors.orangeAccent : Colors.redAccent;
    const jadeGreen = Color(0xFF00A86B); // Jade green for discounted price

    final effectiveScaleFactor =
        _computeEffectiveScaleFactor(context) * scaleFactor;
    final imageHeight = 80 * effectiveScaleFactor;

    final displayImageUrl = _getDisplayImageUrl();

    final cardContent = Container(
      height: imageHeight,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.0),
        borderRadius: BorderRadius.circular(8.0 * effectiveScaleFactor),
        color: Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0 * effectiveScaleFactor),
              bottomLeft: Radius.circular(8.0 * effectiveScaleFactor),
            ),
            child: SizedBox(
              width: 90 * effectiveScaleFactor,
              height: imageHeight,
              child: CachedNetworkImage(
                imageUrl: displayImageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    _buildImagePlaceholder(context, effectiveScaleFactor),
                errorWidget: (context, url, error) =>
                    _buildImageErrorWidget(context, effectiveScaleFactor),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(4.0 * effectiveScaleFactor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      productName,
                      style: TextStyle(
                        fontSize: 14 * effectiveScaleFactor,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 1 * effectiveScaleFactor),
                  Row(
                    children: [
                      _buildStarRating(averageRating, effectiveScaleFactor),
                      SizedBox(width: 2 * effectiveScaleFactor),
                      Text(
                        averageRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 10 * effectiveScaleFactor,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 1 * effectiveScaleFactor),
                  Row(
                    children: [
                      if (originalPrice != null &&
                          discountPercentage != null &&
                          discountPercentage! > 0) ...[
                        Text(
                          '${originalPrice!.toStringAsFixed(0)} $currency',
                          style: TextStyle(
                            fontSize: 12 * effectiveScaleFactor,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        SizedBox(width: 4 * effectiveScaleFactor),
                        Text(
                          '${price.toStringAsFixed(0)} $currency',
                          style: TextStyle(
                            fontSize: 12 * effectiveScaleFactor,
                            fontWeight: FontWeight.bold,
                            color: jadeGreen,
                          ),
                        ),
                      ] else ...[
                        Text(
                          '${price.toStringAsFixed(0)} $currency',
                          style: TextStyle(
                            fontSize: 12 * effectiveScaleFactor,
                            fontWeight: FontWeight.bold,
                            color: priceColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Removed date widget block
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (showOverlayIcons && productId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8.0 * effectiveScaleFactor),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            cardContent,
            Positioned(
              bottom: 4 * effectiveScaleFactor,
              right: 4 * effectiveScaleFactor,
              child: Consumer2<FavoriteProvider, CartProvider>(
                builder: (context, favoriteProvider, cartProvider, child) {
                  final isFavorited =
                      favoriteProvider.favoriteProductIds.contains(productId);
                  final isInCart =
                      cartProvider.cartProductIds.contains(productId);

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final message = await favoriteProvider
                              .addToFavorites(productId!, context: context);
                          if (onFavoriteToggled != null) {
                            onFavoriteToggled!();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            FeatherIcons.heart,
                            color: isFavorited ? Colors.red : Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      SizedBox(width: 4 * effectiveScaleFactor),
                      GestureDetector(
                        onTap: () async {
                          final message = await cartProvider.addToCartById(productId!);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            FeatherIcons.shoppingCart,
                            color: isInCart ? Colors.orange : Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    } else {
      return cardContent;
    }
  }

  String _getDisplayImageUrl() {
    if (selectedColor != null &&
        colorImages.containsKey(selectedColor) &&
        colorImages[selectedColor]!.isNotEmpty) {
      return colorImages[selectedColor]!.first;
    }
    return imageUrl;
  }

  double _computeEffectiveScaleFactor(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    double dynamicFactor = (screenWidth / 375).clamp(0.8, 1.2);
    if (isLandscape && dynamicFactor > 1.0) {
      dynamicFactor = 1.0;
    }
    return dynamicFactor;
  }

  Widget _buildImagePlaceholder(BuildContext context, double scaleFactor) {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.image,
        size: 25 * scaleFactor,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildImageErrorWidget(BuildContext context, double scaleFactor) {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image,
        size: 25 * scaleFactor,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildStarRating(double rating, double scaleFactor) {
    final int fullStars = rating.floor();
    final bool hasHalfStar = (rating - fullStars) >= 0.5;
    final int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          Icon(FontAwesomeIcons.solidStar,
              color: Colors.amber, size: 12 * scaleFactor),
        if (hasHalfStar) _buildHalfStar(scaleFactor),
        for (var i = 0; i < emptyStars; i++)
          Icon(FontAwesomeIcons.star,
              color: Colors.grey, size: 12 * scaleFactor),
      ],
    );
  }

  Widget _buildHalfStar(double scaleFactor) {
    return Icon(FontAwesomeIcons.starHalfAlt,
        color: Colors.amber, size: 12 * scaleFactor);
  }
}
