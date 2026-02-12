import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../providers/cart_provider.dart';
import '../providers/favorite_product_provider.dart';

class ProductCard3 extends StatefulWidget {
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
  final bool showQuantityController;
  final int? maxQuantityAllowed;
  final bool showQuantityLabelOnly;
  final String? selectedColorImage;
  final int? availableStock;
  final int quantity;
  final ValueChanged<int>? onQuantityChanged;

  const ProductCard3({
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
    this.availableStock,
    this.discountPercentage,
    this.showQuantityController = true,
    required this.quantity,
    this.onQuantityChanged,
    this.maxQuantityAllowed,
    this.showQuantityLabelOnly = false,
    this.selectedColorImage,
  }) : super(key: key);

  @override
  State<ProductCard3> createState() => _ProductCard3State();
}

class _ProductCard3State extends State<ProductCard3>
    with AutomaticKeepAliveClientMixin {
  // ✅ OPTIMIZATION 1: Cache computed values
  late String _displayImageUrl;
  late bool _hasActiveDiscount;
  late bool _hasBrandModel;
  late bool _hasStock;

  // ✅ OPTIMIZATION 2: Keep widget alive to avoid rebuilds when scrolling
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void didUpdateWidget(ProductCard3 oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ Re-compute if critical properties change
    if (widget.selectedColorImage != oldWidget.selectedColorImage ||
        widget.selectedColor != oldWidget.selectedColor ||
        widget.availableStock != oldWidget.availableStock ||
        widget.maxQuantityAllowed != oldWidget.maxQuantityAllowed) {
      _initializeData();
    }
  }

  void _initializeData() {
    _displayImageUrl = _getDisplayImageUrl();
    _hasActiveDiscount = _checkActiveDiscount();
    _hasBrandModel = widget.brandModel.isNotEmpty;
    _hasStock = _checkStock();

    if (kDebugMode) {
      debugPrint(
          'ProductCard3 - availableStock: ${widget.availableStock}, maxQuantityAllowed: ${widget.maxQuantityAllowed}, hasStock: $_hasStock');
    }
  }

  bool _checkActiveDiscount() {
    return widget.originalPrice != null &&
        widget.discountPercentage != null &&
        widget.discountPercentage! > 0 &&
        widget.originalPrice! > widget.price;
  }

  bool _checkStock() {
    return widget.availableStock != null
        ? widget.availableStock! > 0
        : (widget.maxQuantityAllowed != null && widget.maxQuantityAllowed! > 0);
  }

  String _getDisplayImageUrl() {
    // Prioritize selectedColorImage passed from parent
    if (widget.selectedColorImage != null &&
        widget.selectedColorImage!.isNotEmpty) {
      return widget.selectedColorImage!;
    }

    // Fallback to colorImages lookup with null safety
    if (widget.selectedColor != null &&
        widget.selectedColor!.isNotEmpty &&
        widget.colorImages.isNotEmpty &&
        widget.colorImages.containsKey(widget.selectedColor)) {
      final colorImagesList = widget.colorImages[widget.selectedColor];
      if (colorImagesList != null && colorImagesList.isNotEmpty) {
        return colorImagesList.first;
      }
    }

    // Final fallback to default image with null safety
    return widget.imageUrl.isNotEmpty ? widget.imageUrl : '';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);

    return RepaintBoundary(
      child: _ProductCard3Content(
        key: widget.productId != null
            ? ValueKey('product_card3_${widget.productId}')
            : null,
        state: this,
        widget: widget,
        mediaQuery: mediaQuery,
        theme: theme,
      ),
    );
  }
}

// ✅ OPTIMIZATION 4: Split into separate widget to reduce rebuild scope
class _ProductCard3Content extends StatelessWidget {
  final _ProductCard3State state;
  final ProductCard3 widget;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  const _ProductCard3Content({
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

    // ✅ OPTIMIZATION 5: Compute scale factor once
    final effectiveScaleFactor =
        _computeEffectiveScaleFactor() * widget.scaleFactor;

    return _CardContent(
      state: state,
      widget: widget,
      textColor: textColor,
      priceColor: priceColor,
      effectiveScaleFactor: effectiveScaleFactor,
      mediaQuery: mediaQuery,
      theme: theme,
    );
  }

  double _computeEffectiveScaleFactor() {
    final w = mediaQuery.size.width;
    return (w / 375).clamp(0.8, 1.0);
  }
}

// ✅ OPTIMIZATION 6: Extract card content
class _CardContent extends StatelessWidget {
  final _ProductCard3State state;
  final ProductCard3 widget;
  final Color textColor;
  final Color priceColor;
  final double effectiveScaleFactor;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  static const Color jadeGreen = Color(0xFF00A86B);

  const _CardContent({
    Key? key,
    required this.state,
    required this.widget,
    required this.textColor,
    required this.priceColor,
    required this.effectiveScaleFactor,
    required this.mediaQuery,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final imageHeight = 80 * effectiveScaleFactor;
    final l10n = AppLocalizations.of(context);

    final bool canShowController = state._hasStock &&
        widget.onQuantityChanged != null &&
        !widget.showQuantityLabelOnly;

    final cardContent = Container(
      height: imageHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0 * effectiveScaleFactor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductImage(
            state: state,
            effectiveScaleFactor: effectiveScaleFactor,
            imageHeight: imageHeight,
            mediaQuery: mediaQuery,
            theme: theme,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(4.0 * effectiveScaleFactor),
              child: _ProductDetails(
                state: state,
                widget: widget,
                textColor: textColor,
                priceColor: priceColor,
                effectiveScaleFactor: effectiveScaleFactor,
                canShowController: canShowController,
                l10n: l10n,
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );

    // ✅ OPTIMIZATION 7: Only wrap with Stack if overlay icons are needed
    if (widget.showOverlayIcons && widget.productId != null) {
      return Stack(
        children: [
          cardContent,
          Positioned(
            bottom: 4 * effectiveScaleFactor,
            right: 4 * effectiveScaleFactor,
            child: _OverlayIcons(
              productId: widget.productId!,
              onFavoriteToggled: widget.onFavoriteToggled,
              scaleFactor: effectiveScaleFactor,
            ),
          ),
        ],
      );
    }

    return cardContent;
  }
}

// ✅ OPTIMIZATION 8: Extract product image section
class _ProductImage extends StatelessWidget {
  final _ProductCard3State state;
  final double effectiveScaleFactor;
  final double imageHeight;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  // FIX: Fixed cache dimensions for stability
  static const int _cacheHeight = 240; // 80 * 3
  static const int _cacheWidth = 270; // 90 * 3

  const _ProductImage({
    super.key,
    required this.state,
    required this.effectiveScaleFactor,
    required this.imageHeight,
    required this.mediaQuery,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidth = 90 * effectiveScaleFactor;

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(8.0 * effectiveScaleFactor),
        bottomLeft: Radius.circular(8.0 * effectiveScaleFactor),
      ),
      // FIX: RepaintBoundary for image isolation
      child: RepaintBoundary(
        child: SizedBox(
          width: imageWidth,
          height: imageHeight,
          child: CachedNetworkImage(
            imageUrl: state._displayImageUrl,
            fit: BoxFit.cover,
            memCacheHeight: _cacheHeight,
            memCacheWidth: _cacheWidth,
            useOldImageOnUrlChange: true,
            filterQuality: FilterQuality.medium,
            placeholder: (_, __) => _buildShimmerPlaceholder(),
            errorWidget: (_, __, ___) => _buildError(),
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerPlaceholder() {
    final isDarkMode = theme.brightness == Brightness.dark;
    final baseColor =
        isDarkMode ? const Color(0xFF2D2A41) : Colors.grey.shade300;
    final highlightColor =
        isDarkMode ? const Color(0xFF3D3A51) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        color: baseColor,
      ),
    );
  }

  Widget _buildError() {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      color: isDarkMode ? const Color(0xFF2D2A41) : Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        size: 24 * effectiveScaleFactor,
        color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }
}

// ✅ OPTIMIZATION 11: Extract product details section
class _ProductDetails extends StatelessWidget {
  final _ProductCard3State state;
  final ProductCard3 widget;
  final Color textColor;
  final Color priceColor;
  final double effectiveScaleFactor;
  final bool canShowController;
  final AppLocalizations l10n;
  final ThemeData theme;

  static const Color jadeGreen = Color(0xFF00A86B);

  const _ProductDetails({
    Key? key,
    required this.state,
    required this.widget,
    required this.textColor,
    required this.priceColor,
    required this.effectiveScaleFactor,
    required this.canShowController,
    required this.l10n,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProductTitle(
          brandModel: widget.brandModel,
          productName: widget.productName,
          textColor: textColor,
          hasBrandModel: state._hasBrandModel,
          scaleFactor: effectiveScaleFactor,
        ),
        SizedBox(height: 2 * effectiveScaleFactor),
        _RatingRow(
          rating: widget.averageRating,
          scaleFactor: effectiveScaleFactor,
        ),
        SizedBox(height: 4 * effectiveScaleFactor),
        _PriceAndQuantityRow(
          price: widget.price,
          currency: widget.currency,
          originalPrice: widget.originalPrice,
          discountPercentage: widget.discountPercentage,
          hasActiveDiscount: state._hasActiveDiscount,
          priceColor: priceColor,
          scaleFactor: effectiveScaleFactor,
          showQuantityLabelOnly: widget.showQuantityLabelOnly,
          quantity: widget.quantity,
          canShowController: canShowController,
          hasStock: state._hasStock,
          l10n: l10n,
          onQuantityChanged: widget.onQuantityChanged,
          maxQuantityAllowed: widget.maxQuantityAllowed,
          availableStock: widget.availableStock,
          theme: theme,
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
  final double scaleFactor;

  const _ProductTitle({
    Key? key,
    required this.brandModel,
    required this.productName,
    required this.textColor,
    required this.hasBrandModel,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasBrandModel)
          Text(
            '$brandModel ',
            style: TextStyle(
              fontSize: 14 * scaleFactor,
              fontWeight: FontWeight.w600,
              color: const Color.fromARGB(255, 66, 140, 201),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        Expanded(
          child: Text(
            productName,
            style: TextStyle(
              fontSize: 14 * scaleFactor,
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
  final double scaleFactor;

  const _RatingRow({
    Key? key,
    required this.rating,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RatingBarIndicator(
          rating: rating,
          itemBuilder: (_, __) => const Icon(Icons.star, color: Colors.amber),
          itemCount: 5,
          itemSize: 12 * scaleFactor,
          unratedColor: Colors.grey,
          direction: Axis.horizontal,
        ),
        SizedBox(width: 4 * scaleFactor),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 10 * scaleFactor,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ✅ OPTIMIZATION 14: Extract price and quantity row
class _PriceAndQuantityRow extends StatelessWidget {
  final double price;
  final String currency;
  final double? originalPrice;
  final int? discountPercentage;
  final bool hasActiveDiscount;
  final Color priceColor;
  final double scaleFactor;
  final bool showQuantityLabelOnly;
  final int quantity;
  final bool canShowController;
  final bool hasStock;
  final AppLocalizations l10n;
  final ValueChanged<int>? onQuantityChanged;
  final int? maxQuantityAllowed;
  final int? availableStock;
  final ThemeData theme;

  static const Color jadeGreen = Color(0xFF00A86B);

  const _PriceAndQuantityRow({
    Key? key,
    required this.price,
    required this.currency,
    required this.originalPrice,
    required this.discountPercentage,
    required this.hasActiveDiscount,
    required this.priceColor,
    required this.scaleFactor,
    required this.showQuantityLabelOnly,
    required this.quantity,
    required this.canShowController,
    required this.hasStock,
    required this.l10n,
    required this.onQuantityChanged,
    required this.maxQuantityAllowed,
    required this.availableStock,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Price section
        Flexible(
          child: _PriceDisplay(
            price: price,
            currency: currency,
            originalPrice: originalPrice,
            hasActiveDiscount: hasActiveDiscount,
            priceColor: priceColor,
            scaleFactor: scaleFactor,
          ),
        ),
        // Quantity/Stock section
        if (showQuantityLabelOnly)
          Text(
            '($quantity)',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 12 * scaleFactor,
              fontWeight: FontWeight.bold,
            ),
          )
        else if (canShowController)
          _QuantityController(
            quantity: quantity,
            scaleFactor: scaleFactor,
            onQuantityChanged: onQuantityChanged,
            maxQuantityAllowed: maxQuantityAllowed,
            availableStock: availableStock,
            theme: theme,
          )
        else
          _NoStockBadge(
            l10n: l10n,
            scaleFactor: scaleFactor,
          ),
      ],
    );
  }
}

// ✅ OPTIMIZATION 15: Extract price display
class _PriceDisplay extends StatelessWidget {
  final double price;
  final String currency;
  final double? originalPrice;
  final bool hasActiveDiscount;
  final Color priceColor;
  final double scaleFactor;

  static const Color jadeGreen = Color(0xFF00A86B);

  const _PriceDisplay({
    Key? key,
    required this.price,
    required this.currency,
    required this.originalPrice,
    required this.hasActiveDiscount,
    required this.priceColor,
    required this.scaleFactor,
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
    if (hasActiveDiscount) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${formatPrice(originalPrice!)} $currency',
            style: TextStyle(
              fontSize: 12 * scaleFactor,
              color: Colors.grey,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          SizedBox(width: 4 * scaleFactor),
          Text(
            '${formatPrice(price)} $currency',
            style: TextStyle(
              fontSize: 12 * scaleFactor,
              fontWeight: FontWeight.bold,
              color: jadeGreen,
            ),
          ),
        ],
      );
    }

    return Text(
      '${formatPrice(price)} $currency',
      style: TextStyle(
        fontSize: 12 * scaleFactor,
        fontWeight: FontWeight.bold,
        color: priceColor,
      ),
    );
  }
}

// ✅ OPTIMIZATION 16: Extract quantity controller
class _QuantityController extends StatefulWidget {
  final int quantity;
  final double scaleFactor;
  final ValueChanged<int>? onQuantityChanged;
  final int? maxQuantityAllowed;
  final int? availableStock;
  final ThemeData theme;

  const _QuantityController({
    Key? key,
    required this.quantity,
    required this.scaleFactor,
    required this.onQuantityChanged,
    required this.maxQuantityAllowed,
    required this.availableStock,
    required this.theme,
  }) : super(key: key);

  @override
  State<_QuantityController> createState() => _QuantityControllerState();
}

class _QuantityControllerState extends State<_QuantityController> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final canDecrement = widget.quantity > 1;
    final effectiveMaxQuantity =
        widget.maxQuantityAllowed ?? widget.availableStock ?? 999;
    final canIncrement = widget.quantity < effectiveMaxQuantity;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!, width: 1),
        borderRadius: BorderRadius.circular(20 * widget.scaleFactor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // DECREMENT
          GestureDetector(
            onTap: _isProcessing || !canDecrement
                ? null
                : () => _handleDecrement(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8 * widget.scaleFactor,
                vertical: 4 * widget.scaleFactor,
              ),
              child: Icon(
                FeatherIcons.minus,
                size: 16 * widget.scaleFactor,
                color: canDecrement ? Colors.orange : Colors.grey,
              ),
            ),
          ),

          // CURRENT QUANTITY
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8 * widget.scaleFactor,
              vertical: 4 * widget.scaleFactor,
            ),
            color: widget.theme.brightness == Brightness.dark
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.grey[200],
            child: Text(
                    '${widget.quantity}',
                    style: TextStyle(
                      fontSize: 14 * widget.scaleFactor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),

          // INCREMENT
          GestureDetector(
            onTap: _isProcessing || !canIncrement
                ? null
                : () => _handleIncrement(effectiveMaxQuantity),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8 * widget.scaleFactor,
                vertical: 4 * widget.scaleFactor,
              ),
              child: Icon(
                FeatherIcons.plus,
                size: 16 * widget.scaleFactor,
                color: canIncrement ? Colors.orange : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleDecrement() {
    if (_isProcessing || widget.onQuantityChanged == null) return;

    setState(() => _isProcessing = true);
    widget.onQuantityChanged!(widget.quantity - 1);

    // Reset processing state after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }

  void _handleIncrement(int effectiveMaxQuantity) {
    if (_isProcessing || widget.onQuantityChanged == null) return;

    final newQuantity = widget.quantity + 1;

    // Show feedback if hitting sale preference limit
    if (widget.maxQuantityAllowed != null &&
        newQuantity > widget.maxQuantityAllowed!) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.maxAllowedQuantity(widget.maxQuantityAllowed!)),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    widget.onQuantityChanged!(newQuantity);

    // Reset processing state after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }
}

// ✅ OPTIMIZATION 17: Extract no stock badge
class _NoStockBadge extends StatelessWidget {
  final AppLocalizations l10n;
  final double scaleFactor;

  const _NoStockBadge({
    Key? key,
    required this.l10n,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.pink, width: 1.0),
        borderRadius: BorderRadius.circular(20 * scaleFactor),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 12 * scaleFactor,
        vertical: 4 * scaleFactor,
      ),
      child: Text(
        l10n.noStock,
        style: TextStyle(
          color: Colors.pink,
          fontSize: 12 * scaleFactor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ✅ OPTIMIZATION 18: Extract overlay icons with state management
class _OverlayIcons extends StatefulWidget {
  final String productId;
  final VoidCallback? onFavoriteToggled;
  final double scaleFactor;

  const _OverlayIcons({
    Key? key,
    required this.productId,
    this.onFavoriteToggled,
    required this.scaleFactor,
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
        // FIX: Selector for minimal rebuilds - only rebuilds when this product's favorite status changes
        Selector<FavoriteProvider, bool>(
          selector: (_, provider) =>
              provider.favoriteProductIds.contains(widget.productId),
          builder: (context, isFav, _) {
            return _ActionIcon(
              icon: FeatherIcons.heart,
              color: isFav ? Colors.red : Colors.white,
              isProcessing: _isFavoriteProcessing,
              onTap: _isFavoriteProcessing
                  ? null
                  : () =>
                      _handleFavoriteToggle(context.read<FavoriteProvider>()),
            );
          },
        ),
        SizedBox(width: 8 * widget.scaleFactor),
        // FIX: Selector for cart status
        Selector<CartProvider, bool>(
          selector: (_, provider) =>
              provider.cartProductIds.contains(widget.productId),
          builder: (context, inCart, _) {
            return _ActionIcon(
              icon: FeatherIcons.shoppingCart,
              color: inCart ? Colors.orange : Colors.white,
              isProcessing: _isCartProcessing,
              onTap: _isCartProcessing
                  ? null
                  : () => _handleAddToCart(context.read<CartProvider>()),
            );
          },
        ),
      ],
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

// ✅ OPTIMIZATION 19: Reusable action icon widget
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isProcessing;
  final VoidCallback? onTap;

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
      child: Icon(
        icon,
        color: color,
        size: 16,
      ),
    );
  }
}
