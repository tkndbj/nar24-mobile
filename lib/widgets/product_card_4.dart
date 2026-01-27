import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../providers/cart_provider.dart';
import '../providers/favorite_product_provider.dart';

/// Production-grade ProductCard4 with optimized image rendering
///
/// Key fixes for image glitching:
/// 1. Fixed cache dimensions (not reactive to mediaQuery changes)
/// 2. Disabled fade animations to prevent flicker
/// 3. RepaintBoundary for isolated rendering
/// 4. Proper key management for widget identity
/// 5. Selector pattern for minimal rebuilds
class ProductCard4 extends StatefulWidget {
  final String imageUrl;
  final Map<String, List<String>> colorImages;
  final String? selectedColor;
  final String productName;
  final String brandModel;
  final double price;
  final String currency;
  final double averageRating;
  final double scaleFactor;
  final bool showOverlayIcons;
  final String? productId;
  final VoidCallback? onFavoriteToggled;
  final double? originalPrice;
  final int? discountPercentage;
  final bool isShopProduct;

  const ProductCard4({
    Key? key,
    required this.imageUrl,
    required this.colorImages,
    this.selectedColor,
    required this.productName,
    required this.brandModel,
    required this.price,
    required this.currency,
    this.averageRating = 0.0,
    this.scaleFactor = 1.0,
    this.showOverlayIcons = false,
    this.productId,
    this.onFavoriteToggled,
    this.originalPrice,
    this.discountPercentage,
    this.isShopProduct = false,
  }) : super(key: key);

  @override
  State<ProductCard4> createState() => _ProductCard4State();
}

class _ProductCard4State extends State<ProductCard4>
    with AutomaticKeepAliveClientMixin {
  // Cached computed values
  late String _displayImageUrl;
  late bool _hasValidImage;
  late bool _hasActiveDiscount;
  late bool _hasBrandModel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void didUpdateWidget(ProductCard4 oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only recalculate if relevant props actually changed
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.selectedColor != widget.selectedColor ||
        !mapEquals(oldWidget.colorImages, widget.colorImages) ||
        oldWidget.originalPrice != widget.originalPrice ||
        oldWidget.discountPercentage != widget.discountPercentage ||
        oldWidget.price != widget.price ||
        oldWidget.brandModel != widget.brandModel) {
      _initializeData();
    }
  }

  void _initializeData() {
    _displayImageUrl = _getDisplayImageUrl();
    _hasValidImage = _isValidImageUrl(_displayImageUrl);
    _hasActiveDiscount = _checkActiveDiscount();
    _hasBrandModel = widget.brandModel.isNotEmpty;
  }

  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;

    try {
      final uri = Uri.parse(url.trim());
      return uri.hasScheme &&
          uri.host.isNotEmpty &&
          (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Invalid URL format: $url - Error: $e');
      }
      return false;
    }
  }

  bool _checkActiveDiscount() {
    return widget.originalPrice != null &&
        widget.discountPercentage != null &&
        widget.discountPercentage! > 0 &&
        widget.originalPrice! > widget.price;
  }

  String _getDisplayImageUrl() {
    final color = widget.selectedColor;
    if (color != null &&
        widget.colorImages.containsKey(color) &&
        widget.colorImages[color]!.isNotEmpty) {
      return widget.colorImages[color]!.first;
    }
    return widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // FIX 1: RepaintBoundary isolates rendering
    return RepaintBoundary(
      child: _ProductCardContent(
        key: widget.productId != null
            ? ValueKey('product_card_${widget.productId}')
            : null,
        displayImageUrl: _displayImageUrl,
        hasValidImage: _hasValidImage,
        hasActiveDiscount: _hasActiveDiscount,
        hasBrandModel: _hasBrandModel,
        productName: widget.productName,
        brandModel: widget.brandModel,
        price: widget.price,
        currency: widget.currency,
        averageRating: widget.averageRating,
        originalPrice: widget.originalPrice,
        showOverlayIcons: widget.showOverlayIcons,
        productId: widget.productId,
        onFavoriteToggled: widget.onFavoriteToggled,
      ),
    );
  }
}

/// Stateless content widget - receives all data as parameters
class _ProductCardContent extends StatelessWidget {
  final String displayImageUrl;
  final bool hasValidImage;
  final bool hasActiveDiscount;
  final bool hasBrandModel;
  final String productName;
  final String brandModel;
  final double price;
  final String currency;
  final double averageRating;
  final double? originalPrice;
  final bool showOverlayIcons;
  final String? productId;
  final VoidCallback? onFavoriteToggled;

  // Fixed dimensions - prevents rebuilds from mediaQuery changes
  static const double imageHeight = 80.0;
  static const double imageWidth = 90.0;
  static const double borderRadius = 8.0;
  static const double paddingAll = 4.0;

  const _ProductCardContent({
    Key? key,
    required this.displayImageUrl,
    required this.hasValidImage,
    required this.hasActiveDiscount,
    required this.hasBrandModel,
    required this.productName,
    required this.brandModel,
    required this.price,
    required this.currency,
    required this.averageRating,
    required this.originalPrice,
    required this.showOverlayIcons,
    required this.productId,
    required this.onFavoriteToggled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final priceColor = isDarkMode ? Colors.orangeAccent : Colors.redAccent;

    // FIX 2: Use MediaQuery.withNoTextScaling for consistent sizing
    return MediaQuery.withNoTextScaling(
      child: _buildCardContent(context, textColor, priceColor),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    Color textColor,
    Color priceColor,
  ) {
    final cardContent = Container(
      height: imageHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OptimizedProductImage(
            key: ValueKey('img_${displayImageUrl.hashCode}'),
            imageUrl: displayImageUrl,
            hasValidImage: hasValidImage,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(paddingAll),
              child: _ProductDetails(
                productName: productName,
                brandModel: brandModel,
                hasBrandModel: hasBrandModel,
                price: price,
                currency: currency,
                averageRating: averageRating,
                originalPrice: originalPrice,
                hasActiveDiscount: hasActiveDiscount,
                textColor: textColor,
                priceColor: priceColor,
              ),
            ),
          ),
        ],
      ),
    );

    // Only wrap with Stack if overlay icons are needed
    if (showOverlayIcons && productId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            cardContent,
            Positioned(
              bottom: 4,
              right: 4,
              child: _OverlayIcons(
                productId: productId!,
                onFavoriteToggled: onFavoriteToggled,
              ),
            ),
          ],
        ),
      );
    }

    return cardContent;
  }
}

/// Optimized product image with stable caching
class _OptimizedProductImage extends StatelessWidget {
  final String imageUrl;
  final bool hasValidImage;

  // FIX 3: Fixed cache dimensions - not reactive to devicePixelRatio
  // Using 3x for high-DPI displays (covers most devices)
  static const int _cacheHeight = 240; // 80 * 3
  static const int _cacheWidth = 270; // 90 * 3
  static const double imageHeight = 80.0;
  static const double imageWidth = 90.0;
  static const double borderRadius = 8.0;

  const _OptimizedProductImage({
    Key? key,
    required this.imageUrl,
    required this.hasValidImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        bottomLeft: Radius.circular(borderRadius),
      ),
      // FIX 4: RepaintBoundary for image isolation
      child: RepaintBoundary(
        child: SizedBox(
          width: imageWidth,
          height: imageHeight,
          child: hasValidImage
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: imageWidth,
                  height: imageHeight,
                  // FIX 5: Fixed cache dimensions for stability
                  memCacheHeight: _cacheHeight,
                  memCacheWidth: _cacheWidth,
                  maxHeightDiskCache: _cacheHeight,
                  maxWidthDiskCache: _cacheWidth,
                  // FIX 6: Disable fade animations to prevent flicker
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  // FIX 7: Stable cache key based on URL hash
                  cacheKey: 'product_img_${imageUrl.hashCode}',
                  // FIX 8: Keep old image while loading new one
                  useOldImageOnUrlChange: true,
                  // FIX 9: Medium quality filtering for smoother rendering
                  filterQuality: FilterQuality.medium,
                  placeholder: (_, __) => const _ImagePlaceholder(),
                  errorWidget: (_, __, ___) => const _ImageErrorWidget(),
                )
              : const _ImagePlaceholder(),
        ),
      ),
    );
  }
}

/// Image loading placeholder
class _ImagePlaceholder extends StatelessWidget {
  static const double _placeholderSize = 75.0; // 25 * 3
  static const int _assetCacheSize = 150; // 75 * 2 for retina

  const _ImagePlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Image.asset(
          'assets/images/nargri.png',
          width: _placeholderSize,
          height: _placeholderSize,
          fit: BoxFit.contain,
          // FIX 10: Fixed asset cache size
          cacheWidth: _assetCacheSize,
          cacheHeight: _assetCacheSize,
          filterQuality: FilterQuality.low,
          isAntiAlias: false,
          errorBuilder: (_, __, ___) => Icon(
            Icons.image_outlined,
            size: 25,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

/// Image error widget
class _ImageErrorWidget extends StatelessWidget {
  const _ImageErrorWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 25,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}

/// Product details section
class _ProductDetails extends StatelessWidget {
  final String productName;
  final String brandModel;
  final bool hasBrandModel;
  final double price;
  final String currency;
  final double averageRating;
  final double? originalPrice;
  final bool hasActiveDiscount;
  final Color textColor;
  final Color priceColor;

  const _ProductDetails({
    Key? key,
    required this.productName,
    required this.brandModel,
    required this.hasBrandModel,
    required this.price,
    required this.currency,
    required this.averageRating,
    required this.originalPrice,
    required this.hasActiveDiscount,
    required this.textColor,
    required this.priceColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _ProductTitle(
            brandModel: brandModel,
            productName: productName,
            textColor: textColor,
            hasBrandModel: hasBrandModel,
          ),
        ),
        const SizedBox(height: 1),
        _RatingRow(rating: averageRating),
        const SizedBox(height: 1),
        _PriceRow(
          price: price,
          currency: currency,
          originalPrice: originalPrice,
          hasActiveDiscount: hasActiveDiscount,
          priceColor: priceColor,
        ),
      ],
    );
  }
}

/// Product title with brand
class _ProductTitle extends StatelessWidget {
  final String brandModel;
  final String productName;
  final Color textColor;
  final bool hasBrandModel;

  static const double _fontSize = 14.0;
  static const Color _brandColor = Color.fromARGB(255, 66, 140, 201);

  const _ProductTitle({
    Key? key,
    required this.brandModel,
    required this.productName,
    required this.textColor,
    required this.hasBrandModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasBrandModel) ...[
          Text(
            '$brandModel ',
            style: const TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.w600,
              color: _brandColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        Expanded(
          child: Text(
            productName.isNotEmpty ? productName : 'Unknown Product',
            style: TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Rating display row
class _RatingRow extends StatelessWidget {
  final double rating;

  static const double _starSize = 10.0;
  static const double _fontSize = 10.0;

  const _RatingRow({
    Key? key,
    required this.rating,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RatingBarIndicator(
          rating: rating,
          itemBuilder: (_, __) => const Icon(Icons.star, color: Colors.amber),
          itemCount: 5,
          itemSize: _starSize,
          unratedColor: Colors.grey,
          direction: Axis.horizontal,
        ),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: _fontSize,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

/// Price display row with discount support
class _PriceRow extends StatelessWidget {
  final double price;
  final String currency;
  final double? originalPrice;
  final bool hasActiveDiscount;
  final Color priceColor;

  static const double _fontSize = 12.0;
  static const Color _discountColor = Color(0xFF00A86B);

  const _PriceRow({
    Key? key,
    required this.price,
    required this.currency,
    required this.originalPrice,
    required this.hasActiveDiscount,
    required this.priceColor,
  }) : super(key: key);

  String _formatPrice(num price) {
    final rounded = double.parse(price.toStringAsFixed(2));
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    if (hasActiveDiscount && originalPrice != null) {
      return Row(
        children: [
          Text(
            '${_formatPrice(originalPrice!)} $currency',
            style: const TextStyle(
              fontSize: _fontSize,
              color: Colors.grey,
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.grey,
              decorationThickness: 2.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_formatPrice(price)} $currency',
            style: const TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.bold,
              color: _discountColor,
            ),
          ),
        ],
      );
    }

    return Text(
      '${_formatPrice(price)} $currency',
      style: TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.bold,
        color: priceColor,
      ),
    );
  }
}

/// Overlay icons with optimized state management
class _OverlayIcons extends StatefulWidget {
  final String productId;
  final VoidCallback? onFavoriteToggled;

  const _OverlayIcons({
    Key? key,
    required this.productId,
    this.onFavoriteToggled,
  }) : super(key: key);

  @override
  State<_OverlayIcons> createState() => _OverlayIconsState();
}

class _OverlayIconsState extends State<_OverlayIcons> {
  bool _isFavoriteProcessing = false;
  bool _isCartProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FIX 11: Use Selector for minimal rebuilds on favorite
        Selector<FavoriteProvider, bool>(
          selector: (_, provider) =>
              provider.favoriteProductIds.contains(widget.productId),
          builder: (context, isFavorited, _) {
            return _ActionIcon(
              icon: FeatherIcons.heart,
              color: isFavorited ? Colors.red : Colors.white,
              isProcessing: _isFavoriteProcessing,
              onTap: _isFavoriteProcessing ? null : _handleFavoriteToggle,
            );
          },
        ),
        const SizedBox(width: 4),
        // FIX 12: Use Selector for minimal rebuilds on cart
        Selector<CartProvider, bool>(
          selector: (_, provider) =>
              provider.cartProductIds.contains(widget.productId),
          builder: (context, isInCart, _) {
            return _ActionIcon(
              icon: FeatherIcons.shoppingCart,
              color: isInCart ? Colors.orange : Colors.white,
              isProcessing: _isCartProcessing,
              onTap: _isCartProcessing ? null : _handleAddToCart,
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleFavoriteToggle() async {
    if (_isFavoriteProcessing) return;

    setState(() => _isFavoriteProcessing = true);

    try {
      final favProv = context.read<FavoriteProvider>();
      await favProv.addToFavorites(widget.productId, context: context);
      widget.onFavoriteToggled?.call();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Favorite toggle error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isFavoriteProcessing = false);
      }
    }
  }

  Future<void> _handleAddToCart() async {
    if (_isCartProcessing) return;

    setState(() => _isCartProcessing = true);

    try {
      final cartProv = context.read<CartProvider>();
      final msg = await cartProv.addToCartById(widget.productId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Add to cart error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCartProcessing = false);
      }
    }
  }
}

/// Reusable action icon button
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isProcessing;
  final VoidCallback? onTap;

  static const double _iconSize = 16.0;

  const _ActionIcon({
    Key? key,
    required this.icon,
    required this.color,
    this.isProcessing = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // FIX 13: Use Material + InkWell for proper touch feedback
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: isProcessing
              ? SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Icon(
                  icon,
                  size: _iconSize,
                  color: color,
                ),
        ),
      ),
    );
  }
}
