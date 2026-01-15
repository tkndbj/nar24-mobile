import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../providers/cart_provider.dart';
import '../providers/favorite_product_provider.dart';

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
  // Cache computed values (non-final to allow updates when props change)
  late String _displayImageUrl;
  late bool _hasValidImage;
  late bool _hasActiveDiscount;
  late bool _hasBrandModel;

  // ✅ OPTIMIZATION 2: Keep widget alive to avoid rebuilds when scrolling
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
    // Recalculate cached values when relevant props change
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.selectedColor != widget.selectedColor ||
        oldWidget.colorImages != widget.colorImages ||
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

  /// Validates if a URL is valid for network image loading
  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return false;
    }

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

  /// Check if product has an active discount
  bool _checkActiveDiscount() {
    return widget.originalPrice != null &&
        widget.discountPercentage != null &&
        widget.discountPercentage! > 0 &&
        widget.originalPrice! > widget.price;
  }

  String _getDisplayImageUrl() {
    if (widget.selectedColor != null &&
        widget.colorImages.containsKey(widget.selectedColor) &&
        widget.colorImages[widget.selectedColor]!.isNotEmpty) {
      return widget.colorImages[widget.selectedColor]!.first;
    }
    return widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Debug logging (only in debug mode)
    if (kDebugMode && widget.productId != null) {
      debugPrint(
          'ProductCard4 Build - Product: ${widget.productName} (ID: ${widget.productId})');
      debugPrint('  originalPrice: ${widget.originalPrice}');
      debugPrint('  discountPercentage: ${widget.discountPercentage}');
      debugPrint('  price: ${widget.price}');
      debugPrint('  hasActiveDiscount: $_hasActiveDiscount');
    }

    // ✅ OPTIMIZATION 3: Cache MediaQuery and Theme
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);

    return _ProductCard4Content(
      state: this,
      widget: widget,
      mediaQuery: mediaQuery,
      theme: theme,
    );
  }
}

// ✅ OPTIMIZATION 4: Split into separate widget to reduce rebuild scope
class _ProductCard4Content extends StatelessWidget {
  final _ProductCard4State state;
  final ProductCard4 widget;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  const _ProductCard4Content({
    Key? key,
    required this.state,
    required this.widget,
    required this.mediaQuery,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final priceColor = isDarkMode ? Colors.orangeAccent : Colors.redAccent;

    // Override system textScaleFactor so it never scales
    final fixedMq = mediaQuery.copyWith(textScaler: TextScaler.noScaling);

    return MediaQuery(
      data: fixedMq,
      child: _CardContent(
        state: state,
        widget: widget,
        textColor: textColor,
        priceColor: priceColor,
        mediaQuery: fixedMq,
      ),
    );
  }
}

// ✅ OPTIMIZATION 5: Extract card content
class _CardContent extends StatelessWidget {
  final _ProductCard4State state;
  final ProductCard4 widget;
  final Color textColor;
  final Color priceColor;
  final MediaQueryData mediaQuery;

  // ✅ OPTIMIZATION 6: Use const values for dimensions
  static const double imageHeight = 80.0;
  static const double imageWidth = 90.0;
  static const double borderRadius = 8.0;
  static const double paddingAll = 4.0;
  static const double spacingTiny = 1.0;
  static const double spacingSmall = 2.0;
  static const double spacingMid = 4.0;
  static const double fontLarge = 14.0;
  static const double fontMedium = 12.0;
  static const double fontSmall = 10.0;
  static const double iconSize = 16.0;
  static const double placeholderIconSize = 25.0;
  static const Color jadeGreen = Color(0xFF00A86B);

  const _CardContent({
    Key? key,
    required this.state,
    required this.widget,
    required this.textColor,
    required this.priceColor,
    required this.mediaQuery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      height: imageHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductImage(
            state: state,
            mediaQuery: mediaQuery,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(paddingAll),
              child: _ProductDetails(
                state: state,
                widget: widget,
                textColor: textColor,
                priceColor: priceColor,
              ),
            ),
          ),
        ],
      ),
    );

    // ✅ OPTIMIZATION 7: Only wrap with Stack if overlay icons are needed
    if (widget.showOverlayIcons && widget.productId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            cardContent,
            Positioned(
              bottom: spacingMid,
              right: spacingMid,
              child: _OverlayIcons(
                productId: widget.productId!,
                onFavoriteToggled: widget.onFavoriteToggled,
              ),
            ),
          ],
        ),
      );
    }

    return cardContent;
  }
}

// ✅ OPTIMIZATION 8: Extract product image section
class _ProductImage extends StatelessWidget {
  final _ProductCard4State state;
  final MediaQueryData mediaQuery;

  static const double imageHeight = 80.0;
  static const double imageWidth = 90.0;
  static const double borderRadius = 8.0;
  static const double placeholderIconSize = 25.0;

  const _ProductImage({
    Key? key,
    required this.state,
    required this.mediaQuery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        bottomLeft: Radius.circular(borderRadius),
      ),
      child: SizedBox(
        width: imageWidth,
        height: imageHeight,
        child: state._hasValidImage
            ? CachedNetworkImage(
                imageUrl: state._displayImageUrl,
                fit: BoxFit.cover,
                // ✅ OPTIMIZATION 9: Cache network images with size constraints
                memCacheHeight:
                    (imageHeight * mediaQuery.devicePixelRatio).round(),
                maxHeightDiskCache:
                    (imageHeight * mediaQuery.devicePixelRatio).round(),
                memCacheWidth:
                    (imageWidth * mediaQuery.devicePixelRatio).round(),
                maxWidthDiskCache:
                    (imageWidth * mediaQuery.devicePixelRatio).round(),
                placeholder: (_, __) => _buildImagePlaceholder(),
                errorWidget: (_, __, ___) => _buildImageErrorWidget(),
              )
            : _buildImagePlaceholder(),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Image.asset(
        'assets/images/narsiyah.png',
        width: placeholderIconSize * 3,
        height: placeholderIconSize * 3,
        fit: BoxFit.contain,
        // ✅ OPTIMIZATION 10: Cache asset images
        cacheWidth:
            (placeholderIconSize * 3 * mediaQuery.devicePixelRatio).round(),
        cacheHeight:
            (placeholderIconSize * 3 * mediaQuery.devicePixelRatio).round(),
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.image,
            size: placeholderIconSize,
            color: Colors.grey,
          );
        },
      ),
    );
  }

  Widget _buildImageErrorWidget() {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image,
        size: placeholderIconSize,
        color: Colors.grey,
      ),
    );
  }
}

// ✅ OPTIMIZATION 11: Extract product details section
class _ProductDetails extends StatelessWidget {
  final _ProductCard4State state;
  final ProductCard4 widget;
  final Color textColor;
  final Color priceColor;

  static const double spacingTiny = 1.0;
  static const double spacingSmall = 2.0;
  static const double spacingMid = 4.0;
  static const double fontLarge = 14.0;
  static const double fontMedium = 12.0;
  static const double fontSmall = 10.0;
  static const Color jadeGreen = Color(0xFF00A86B);

  const _ProductDetails({
    Key? key,
    required this.state,
    required this.widget,
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
            brandModel: widget.brandModel,
            productName: widget.productName,
            textColor: textColor,
            hasBrandModel: state._hasBrandModel,
          ),
        ),
        const SizedBox(height: spacingTiny),
        _RatingRow(
          rating: widget.averageRating,
        ),
        const SizedBox(height: spacingTiny),
        _PriceRow(
          price: widget.price,
          currency: widget.currency,
          originalPrice: widget.originalPrice,
          hasActiveDiscount: state._hasActiveDiscount,
          priceColor: priceColor,
        ),
      ],
    );
  }
}

// ✅ OPTIMIZATION 12: Extract product title
class _ProductTitle extends StatelessWidget {
  final String brandModel;
  final String productName;
  final Color textColor;
  final bool hasBrandModel;

  static const double fontLarge = 14.0;

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
              fontSize: fontLarge,
              fontWeight: FontWeight.w600,
              color: Color.fromARGB(255, 66, 140, 201),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        Expanded(
          child: Text(
            productName.isNotEmpty ? productName : 'Unknown Product',
            style: TextStyle(
              fontSize: fontLarge,
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

// ✅ OPTIMIZATION 13: Extract rating row
class _RatingRow extends StatelessWidget {
  final double rating;

  static const double spacingSmall = 2.0;
  static const double fontSmall = 10.0;

  const _RatingRow({
    Key? key,
    required this.rating,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RatingBarIndicator(
          rating: rating,
          itemBuilder: (_, __) => const Icon(Icons.star, color: Colors.amber),
          itemCount: 5,
          itemSize: fontSmall,
          unratedColor: Colors.grey,
          direction: Axis.horizontal,
        ),
        const SizedBox(width: spacingSmall),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: fontSmall,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ✅ OPTIMIZATION 14: Extract price row
class _PriceRow extends StatelessWidget {
  final double price;
  final String currency;
  final double? originalPrice;
  final bool hasActiveDiscount;
  final Color priceColor;

  static const double spacingMid = 4.0;
  static const double fontMedium = 12.0;
  static const Color jadeGreen = Color(0xFF00A86B);

  const _PriceRow({
    Key? key,
    required this.price,
    required this.currency,
    required this.originalPrice,
    required this.hasActiveDiscount,
    required this.priceColor,
  }) : super(key: key);

  String formatPrice(num price) {
    double rounded = double.parse(price.toStringAsFixed(2));
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ SAFE: Check both hasActiveDiscount AND originalPrice is not null
    if (hasActiveDiscount && originalPrice != null) {
      return Row(
        children: [
          // Original price with strikethrough
          Text(
            '${formatPrice(originalPrice!)} $currency',
            style: const TextStyle(
              fontSize: fontMedium,
              color: Colors.grey,
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.grey,
              decorationThickness: 2.0,
            ),
          ),
          const SizedBox(width: spacingMid),
          // Discounted price in green
          Text(
            '${formatPrice(price)} $currency',
            style: const TextStyle(
              fontSize: fontMedium,
              fontWeight: FontWeight.bold,
              color: jadeGreen,
            ),
          ),
        ],
      );
    }

    // Regular price (no discount)
    return Text(
      '${formatPrice(price)} $currency',
      style: TextStyle(
        fontSize: fontMedium,
        fontWeight: FontWeight.bold,
        color: priceColor,
      ),
    );
  }
}

// ✅ OPTIMIZATION 15: Extract overlay icons with state management
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

  static const double spacingMid = 4.0;
  static const double iconSize = 16.0;

  @override
  Widget build(BuildContext context) {
    return Consumer2<FavoriteProvider, CartProvider>(
      builder: (context, favProv, cartProv, child) {
        final isFavorited =
            favProv.favoriteProductIds.contains(widget.productId);
        final isInCart = cartProv.cartProductIds.contains(widget.productId);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionIcon(
              icon: FeatherIcons.heart,
              color: isFavorited ? Colors.red : Colors.white,
              isProcessing: _isFavoriteProcessing,
              onTap: _isFavoriteProcessing
                  ? null
                  : () => _handleFavoriteToggle(favProv),
            ),
            const SizedBox(width: spacingMid),
            _ActionIcon(
              icon: FeatherIcons.shoppingCart,
              color: isInCart ? Colors.orange : Colors.white,
              isProcessing: _isCartProcessing,
              onTap:
                  _isCartProcessing ? null : () => _handleAddToCart(cartProv),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFavoriteToggle(FavoriteProvider favProv) async {
    if (_isFavoriteProcessing) return;

    setState(() => _isFavoriteProcessing = true);

    try {
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

  Future<void> _handleAddToCart(CartProvider cartProv) async {
    if (_isCartProcessing) return;

    setState(() => _isCartProcessing = true);

    try {
      final msg = await cartProv.addToCartById(widget.productId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 1),
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

// ✅ OPTIMIZATION 16: Reusable action icon widget
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isProcessing;
  final VoidCallback? onTap;

  static const double iconSize = 16.0;

  const _ActionIcon({
    Key? key,
    required this.icon,
    required this.color,
    this.isProcessing = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: isProcessing
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(
                icon,
                size: iconSize,
                color: color,
              ),
      ),
    );
  }
}
