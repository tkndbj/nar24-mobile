import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/market_provider.dart';
import '../models/product_summary.dart';
import '../screens/PRODUCT-SCREENS/product_detail_screen.dart';
import '../generated/l10n/app_localizations.dart';
import '../providers/cart_provider.dart';
import '../providers/favorite_product_provider.dart';
import 'package:flutter/cupertino.dart';
import '../providers/product_repository.dart';
import '../providers/product_detail_provider.dart';
import 'product_option_selector.dart';
import 'dart:ui';

class ProductCard extends StatefulWidget {
  final ProductSummary product;
  final double scaleFactor;
  final double internalScaleFactor;
  final double? portraitImageHeight;
  final double? overrideInternalScaleFactor;
  final bool showCartIcon;
  final bool showExtraLabels;
  final String? extraLabel;
  final List<Color>? extraLabelGradient;
  final String? selectedColor;
  final VoidCallback? onTap;

  const ProductCard({
    Key? key,
    required this.product,
    this.scaleFactor = 1.0,
    this.internalScaleFactor = 1.0,
    this.portraitImageHeight,
    this.overrideInternalScaleFactor,
    this.showCartIcon = true,
    this.showExtraLabels = false,
    this.extraLabel,
    this.onTap,
    this.extraLabelGradient,
    this.selectedColor,
  }) : super(key: key);

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with AutomaticKeepAliveClientMixin {
  String? _selectedColor;
  int _currentImageIndex = 0;
  static const Color jadeGreen = Color(0xFF00A86B);
  late List<String> _displayedColors;
  PageController? _pageController;

  // ✅ CRITICAL: Prevent concurrent navigation spam
  static DateTime? _lastNavigationTime;
  static const _navigationThrottle = Duration(milliseconds: 500);

  // ✅ OPTIMIZATION 1: Cache computed values
  late bool _isFantasyProduct;
  late List<String> _imageUrls;
  late int _imageCount;

  // ✅ OPTIMIZATION 2: Keep widget alive to avoid rebuilds when scrolling
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // ✅ OPTIMIZATION 3: Compute expensive values once
    _isFantasyProduct =
        widget.product.subsubcategory.toLowerCase() == 'fantasy';
    _imageUrls = widget.product.imageUrls;
    _imageCount = _imageUrls.length;

    _initializeColorOptions();

    if (widget.selectedColor != null) {
      _selectedColor = widget.selectedColor;
    }

    // ✅ OPTIMIZATION 4: Only create PageController if needed
    if (_imageCount > 1 && !_isFantasyProduct) {
      _pageController = PageController(initialPage: _currentImageIndex);
    }
  }

  @override
  void didUpdateWidget(ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.product.id != oldWidget.product.id) {
      _isFantasyProduct =
          widget.product.subsubcategory.toLowerCase() == 'fantasy';
      _imageUrls = widget.product.imageUrls;
      _imageCount = _imageUrls.length;
      _currentImageIndex = 0;
      _selectedColor = widget.selectedColor;
      _initializeColorOptions();

      // FIX: Synchronous disposal, deferred creation
      final oldController = _pageController;
      _pageController = null; // Clear reference immediately

      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController?.dispose(); // Dispose after frame

        if (!mounted) return;

        if (_imageCount > 1 && !_isFantasyProduct) {
          _pageController = PageController(initialPage: 0);
          setState(() {}); // Only setState if we created a new controller
        }
      });
      return;
    }

    if (widget.selectedColor != oldWidget.selectedColor) {
      _selectedColor = widget.selectedColor;
      _currentImageIndex = 0;

      final oldController = _pageController;
      _pageController = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController?.dispose();

        if (!mounted) return;

        final newUrls = _getCurrentImageUrls();
        if (newUrls.length > 1 && !_isFantasyProduct) {
          _pageController = PageController(initialPage: 0);
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _pageController = null;
    super.dispose();
  }

  void _initializeColorOptions() {
    final List<String> availableColors =
        widget.product.colorImages.keys.toList();
    if (availableColors.isEmpty) {
      _displayedColors = [];
      return;
    }
    availableColors.shuffle(Random());
    _displayedColors = availableColors.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);

    // FIX: Add RepaintBoundary for render isolation
    return RepaintBoundary(
      child: MediaQuery(
        data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
        child: _ProductCardContent(
          key: ValueKey('product_card_${widget.product.id}'),
          widget: widget,
          state: this,
          mediaQuery: mediaQuery,
          theme: theme,
        ),
      ),
    );
  }

  List<String> _getCurrentImageUrls() {
    if (_selectedColor != null &&
        widget.product.colorImages.containsKey(_selectedColor!) &&
        widget.product.colorImages[_selectedColor!]!.isNotEmpty) {
      return widget.product.colorImages[_selectedColor!]!;
    }
    return _imageUrls;
  }

  Future<void> _onProductTap(BuildContext context) async {
    final now = DateTime.now();

    // ✅ CRITICAL: Throttle rapid taps (500ms between navigations)
    if (_lastNavigationTime != null &&
        now.difference(_lastNavigationTime!) < _navigationThrottle) {
      return;
    }

    _lastNavigationTime = now;

    final market = context.read<MarketProvider>();
    final repo = context.read<ProductRepository>();

    // ✅ OPTIMIZATION: Precache hero image during navigation for instant display
    if (widget.product.imageUrls.isNotEmpty) {
      try {
        precacheImage(
          CachedNetworkImageProvider(widget.product.imageUrls.first),
          context,
        );
      } catch (e) {
        // Silent fail - not critical
      }
    }

    final bool isShopProduct =
        widget.product.sourceCollection == 'shop_products';

    market.incrementClickCount(
      widget.product.id,
      shopId: widget.product.shopId,
      isShopProduct: isShopProduct,
      productName: widget.product.productName,
      category: widget.product.category,
      subcategory: widget.product.subcategory,
      subsubcategory: widget.product.subsubcategory,
      brand: widget.product.brandModel,
    );

    // ✅ OPTIMIZATION: Use lighter curve for smoother animation on low-end devices
    final route = PageRouteBuilder(
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          ChangeNotifierProvider(
        create: (_) => ProductDetailProvider(
  productId: widget.product.id,
  repository: repo,
),
        child: ProductDetailScreen(productId: widget.product.id),
      ),
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        // ✅ Use FastOutSlowIn for perceived smoothness
        final tween = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.fastOutSlowIn));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );

    Navigator.of(context).push(route);
  }

  Color _getColorFromName(String colorName) {
    // ✅ OPTIMIZATION 6: Use a static map for color lookups
    return _colorMap[colorName.toLowerCase()] ?? Colors.grey;
  }

  // Handler for page changes from _ImageSection
  void _handlePageChanged(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _currentImageIndex = index;
        });
      }
    });
  }

  // Handler for color selection from _ImageSection
  void _handleColorSelected(String? color) {
    _selectedColor = color;
    _currentImageIndex = 0;

    final oldController = _pageController;
    _pageController = null; // Clear reference immediately

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController?.dispose();

      if (!mounted) return;

      final newUrls = _getCurrentImageUrls();
      if (newUrls.length > 1 && !_isFantasyProduct) {
        _pageController = PageController(initialPage: 0);
      }
      setState(() {});
    });
  }

  // ✅ Static color map - computed once
  static final Map<String, Color> _colorMap = {
    'blue': Colors.blue,
    'orange': Colors.orange,
    'yellow': Colors.yellow,
    'black': Colors.black,
    'brown': Colors.brown,
    'dark blue': Color(0xFF00008B),
    'gray': Colors.grey,
    'pink': Colors.pink,
    'red': Colors.red,
    'white': Colors.white,
    'green': Colors.green,
    'purple': Colors.purple,
    'teal': Colors.teal,
    'lime': Colors.lime,
    'cyan': Colors.cyan,
    'magenta': Color(0xFFFF00FF),
    'indigo': Colors.indigo,
    'amber': Colors.amber,
    'deep orange': Colors.deepOrange,
    'light blue': Colors.lightBlue,
    'deep purple': Colors.deepPurple,
    'light green': Colors.lightGreen,
    'dark gray': Color(0xFF444444),
    'beige': Color(0xFFF5F5DC),
    'turquoise': Color(0xFF40E0D0),
    'violet': Color(0xFFEE82EE),
    'olive': Color(0xFF808000),
    'maroon': Color(0xFF800000),
    'navy': Color(0xFF000080),
    'silver': Color(0xFFC0C0C0),
  };
}

// ✅ OPTIMIZATION 7: Split into separate widget to reduce rebuild scope
class _ProductCardContent extends StatelessWidget {
  final ProductCard widget;
  final _ProductCardState state;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  const _ProductCardContent({
    Key? key,
    required this.widget,
    required this.state,
    required this.mediaQuery,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = mediaQuery.orientation == Orientation.landscape;
    final bool isDarkMode = theme.brightness == Brightness.dark;

    final double effectiveScaleFactor = _computeEffectiveScaleFactor();
    final double finalInternalScaleFactor =
        widget.overrideInternalScaleFactor ?? widget.internalScaleFactor;
    final double textScaleFactor =
        effectiveScaleFactor * 0.9 * finalInternalScaleFactor;
    final double extraScaleFactor =
        _computeExtraScaleFactor(effectiveScaleFactor);

    final productName = widget.product.productName;
    final price = widget.product.price;
    final originalPrice = widget.product.originalPrice ?? 0.0;
    final discountPercentage = widget.product.discountPercentage ?? 0;
    final hasDiscount = discountPercentage > 0;
    final imageUrls = state._getCurrentImageUrls();

    return GestureDetector(
      onTap: widget.onTap ?? () async => await state._onProductTap(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ImageSection(
            imageUrls: imageUrls,
            effectiveScaleFactor: effectiveScaleFactor,
            hasDiscount: hasDiscount,
            isLandscape: isLandscape,
            widget: widget,
            mediaQuery: mediaQuery,
            theme: theme,
            isFantasyProduct: state._isFantasyProduct,
            currentImageIndex: state._currentImageIndex,
            pageController: state._pageController,
            displayedColors: state._displayedColors,
            selectedColor: state._selectedColor,
            onPageChanged: state._handlePageChanged,
            onColorSelected: state._handleColorSelected,
            getColorFromName: state._getColorFromName,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              8.0 * effectiveScaleFactor,
              2.0 * effectiveScaleFactor,
              8.0 * effectiveScaleFactor,
              3.0 * effectiveScaleFactor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductName(text: productName, scaleFactor: textScaleFactor),
                RotatingText(
  duration: const Duration(milliseconds: 1500),
  children: _buildRotatingChildren(
    context: context,
    brandModel: widget.product.brandModel ?? '',
                    condition: widget.product.condition,
                    quantity: widget.product.quantity,
                    textScaleFactor: textScaleFactor,
                    isDarkMode: isDarkMode,
                  ),
                ),
                SizedBox(height: 1 * effectiveScaleFactor),
                _RatingRow(
                  rating: widget.product.averageRating,
                  scaleFactor:
                      effectiveScaleFactor * widget.internalScaleFactor,
                ),
                SizedBox(height: 1 * effectiveScaleFactor),
                _PriceRow(
                  price: price,
                  originalPrice: originalPrice,
                  hasDiscount: hasDiscount,
                  discountPercentage: discountPercentage,
                  currency: widget.product.currency,
                  textScaleFactor: textScaleFactor,
                  extraScaleFactor: extraScaleFactor,
                  product: widget.product,
                  showCartIcon: widget.showCartIcon,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _computeEffectiveScaleFactor() {
    final double screenWidth = mediaQuery.size.width;
    final bool isLandscape = mediaQuery.orientation == Orientation.landscape;
    double dynamicFactor = (screenWidth / 375).clamp(0.8, 1.2);
    if (isLandscape && dynamicFactor > 1.0) {
      dynamicFactor = 1.0;
    }
    return dynamicFactor * widget.scaleFactor;
  }

  double _computeExtraScaleFactor(double effectiveScaleFactor) {
    const double smallScreenThreshold = 360.0;
    final double adjustedWidth = effectiveScaleFactor * mediaQuery.size.width;
    if (adjustedWidth < smallScreenThreshold) {
      return effectiveScaleFactor *
          (mediaQuery.size.width / smallScreenThreshold);
    }
    return 1.0;
  }

  List<Widget> _buildRotatingChildren({
    required BuildContext context,    
    required String brandModel,
    required String condition,
    required int quantity,
    required double textScaleFactor,
    required bool isDarkMode,
  }) {
    final baseTextStyle = TextStyle(fontSize: 12 * textScaleFactor);

    if (quantity <= 5 && quantity > 0) {
      return [
        if (brandModel.isNotEmpty)
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              brandModel,
              key: const ValueKey('brand'),
              style: baseTextStyle.copyWith(color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Align(
          alignment: Alignment.topLeft,
          child: Text(
            AppLocalizations.of(context).onlyLeft(quantity),
            key: const ValueKey('only_left'),
            style: baseTextStyle.copyWith(
              color: _ProductCardState.jadeGreen,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ];
    } else {
      return [
        if (brandModel.isNotEmpty)
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              brandModel,
              key: const ValueKey('brand'),
              style: baseTextStyle.copyWith(color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ];
    }
  }
}

// ✅ OPTIMIZATION 8: Extract static widgets to avoid rebuilds
class _ProductName extends StatelessWidget {
  final String text;
  final double scaleFactor;

  const _ProductName({
    Key? key,
    required this.text,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14 * scaleFactor,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _StarRating(rating: rating, scaleFactor: scaleFactor),
            SizedBox(width: 2 * scaleFactor),
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 10 * scaleFactor * 0.9,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StarRating extends StatelessWidget {
  final double rating;
  final double scaleFactor;

  const _StarRating({
    Key? key,
    required this.rating,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final int fullStars = rating.floor();
    final bool hasHalfStar = (rating - fullStars) >= 0.5;
    final int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    const starColor = Colors.amber;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          Icon(Icons.star, color: starColor, size: 14 * scaleFactor),
        if (hasHalfStar)
          Icon(Icons.star_half, color: starColor, size: 14 * scaleFactor),
        for (var i = 0; i < emptyStars; i++)
          Icon(Icons.star_border, color: starColor, size: 14 * scaleFactor),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final double price;
  final double originalPrice;
  final bool hasDiscount;
  final int discountPercentage;
  final String currency;
  final double textScaleFactor;
  final double extraScaleFactor;
  final ProductSummary product;
  final bool showCartIcon;

  const _PriceRow({
    Key? key,
    required this.price,
    required this.originalPrice,
    required this.hasDiscount,
    required this.discountPercentage,
    required this.currency,
    required this.textScaleFactor,
    required this.extraScaleFactor,
    required this.product,
    required this.showCartIcon,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: hasDiscount
              ? Row(
                  children: [
                    Text(
                      '${formatPrice(price)} $currency ',
                      style: TextStyle(
                        fontSize: 14 * textScaleFactor,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(width: 4 * textScaleFactor),
                    Text(
                      '%$discountPercentage',
                      style: TextStyle(
                        fontSize: 12 * textScaleFactor * extraScaleFactor,
                        color: _ProductCardState.jadeGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : Text(
                  '${formatPrice(price)} $currency ',
                  style: TextStyle(
                    fontSize: 14 * textScaleFactor,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (showCartIcon)
          _AddToCartIconButton(
  productId: product.id,
  scaleFactor: textScaleFactor,
),
      ],
    );
  }
}

// ✅ OPTIMIZATION 9: Lazy-load image section
class _ImageSection extends StatelessWidget {
  final List<String> imageUrls;
  final double effectiveScaleFactor;
  final bool hasDiscount;
  final bool isLandscape;
  final ProductCard widget;
  final MediaQueryData mediaQuery;
  final ThemeData theme;
  // State values needed for rendering
  final bool isFantasyProduct;
  final int currentImageIndex;
  final PageController? pageController;
  final List<String> displayedColors;
  final String? selectedColor;
  // Callbacks to update parent state
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String?> onColorSelected;
  final Color Function(String) getColorFromName;

  const _ImageSection({
    Key? key,
    required this.imageUrls,
    required this.effectiveScaleFactor,
    required this.hasDiscount,
    required this.isLandscape,
    required this.widget,
    required this.mediaQuery,
    required this.theme,
    required this.isFantasyProduct,
    required this.currentImageIndex,
    required this.pageController,
    required this.displayedColors,
    required this.selectedColor,
    required this.onPageChanged,
    required this.onColorSelected,
    required this.getColorFromName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double screenHeight = mediaQuery.size.height;
    double baseHeight = screenHeight * 0.35;
    if (!isLandscape && widget.portraitImageHeight != null) {
      baseHeight = widget.portraitImageHeight!;
    }
    final double actualHeight = baseHeight * effectiveScaleFactor;

    final bool hasBanner = (widget.product.deliveryOption == "Fast Delivery") ||
        ((widget.product.discountPercentage ?? 0) >= 10);
    final double bannerHeight = hasBanner ? 20.0 * effectiveScaleFactor : 0;
    final double overlayBottomOffset = hasBanner
        ? bannerHeight + (8 * effectiveScaleFactor)
        : 8 * effectiveScaleFactor;

    final double featuredBottomOffset = hasBanner
        ? bannerHeight + (4 * effectiveScaleFactor)
        : (4 * effectiveScaleFactor);

    final int imageCount = imageUrls.length;
    if (imageCount == 0) {
      return _buildNoImageWidget(effectiveScaleFactor);
    }

    int activeDotIndex;
    if (imageCount <= 3) {
      activeDotIndex = currentImageIndex.clamp(0, imageCount - 1);
    } else {
      if (currentImageIndex == 0) {
        activeDotIndex = 0;
      } else if (currentImageIndex == imageCount - 1) {
        activeDotIndex = 2;
      } else {
        activeDotIndex = 1;
      }
    }
    final int dotCount = min(imageCount, 3);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.0 * effectiveScaleFactor),
            topRight: Radius.circular(12.0 * effectiveScaleFactor),
          ),
          child: SizedBox(
            width: double.infinity,
            height: actualHeight,
            child: imageUrls.isNotEmpty
                ? Stack(
                    children: [
                      if (!isFantasyProduct || imageCount == 1)
                        PageView.builder(
                          // FIX: Add key for widget identity when images change
                          key: ValueKey('pageview_${imageUrls.hashCode}'),
                          controller: pageController,
                          itemCount: imageUrls.length,
                          onPageChanged: onPageChanged,
                          // FIX: Disable implicit scrolling for memory efficiency
                          allowImplicitScrolling: false,
                          itemBuilder: (context, index) {
                            return _buildImageWidget(
                                imageUrls[index], actualHeight);
                          },
                        )
                      else
                        _buildImageWidget(imageUrls[0], actualHeight),
                      if (isFantasyProduct) ...[
                        Positioned.fill(
                          child: BackdropFilter(
                            filter:
                                ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                            child: Container(
                              color: Colors.black.withOpacity(0.1),
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24 * effectiveScaleFactor,
                              vertical: 12 * effectiveScaleFactor,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(
                                  12 * effectiveScaleFactor),
                              border: Border.all(
                                color: Colors.white,
                                width: 2 * effectiveScaleFactor,
                              ),
                            ),
                            child: Text(
                              '+18',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32 * effectiveScaleFactor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                : _buildNoImageWidget(effectiveScaleFactor),
          ),
        ),
        Positioned(
          top: 6 * effectiveScaleFactor,
          right: 6 * effectiveScaleFactor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showExtraLabels) ...[
                _ExtraLabel(
                  text: "Nar24",
                  gradientColors: const [Colors.orange, Colors.pink],
                  scaleFactor:
                      effectiveScaleFactor * widget.internalScaleFactor,
                ),
                SizedBox(width: 4 * effectiveScaleFactor),
                _ExtraLabel(
                  text: "Vitrin",
                  gradientColors: const [Colors.purple, Colors.pink],
                  scaleFactor:
                      effectiveScaleFactor * widget.internalScaleFactor,
                ),
                SizedBox(width: 4 * effectiveScaleFactor),
              ],
              _FavoriteIcon(
                product: widget.product,
                scaleFactor: effectiveScaleFactor * widget.internalScaleFactor,
              ),
            ],
          ),
        ),
        if (displayedColors.isNotEmpty)
          Positioned(
            bottom: overlayBottomOffset,
            right: 8 * effectiveScaleFactor,
            child: Column(
              children: displayedColors.map((color) {
                final Color displayColor = getColorFromName(color);
                final bool isSelected = selectedColor == color;
                return GestureDetector(
                  onTap: () {
                    // Toggle color selection via callback
                    onColorSelected(selectedColor == color ? null : color);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: theme.colorScheme.secondary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: displayColor,
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12 * effectiveScaleFactor,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        if (widget.product.campaignName != null &&
            widget.product.campaignName!.isNotEmpty)
          Positioned(
            bottom: featuredBottomOffset +
                (widget.product.isBoosted ? 25 * effectiveScaleFactor : 0),
            left: 8 * effectiveScaleFactor,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 8 * effectiveScaleFactor,
                vertical: 4 * effectiveScaleFactor,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.pink],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12 * effectiveScaleFactor),
              ),
              child: MediaQuery(
                data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
                child: Text(
                  widget.product.campaignName!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10 * effectiveScaleFactor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        if (widget.product.isBoosted)
          Positioned(
            bottom: featuredBottomOffset,
            left: 8 * effectiveScaleFactor,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 6 * effectiveScaleFactor,
                vertical: 2 * effectiveScaleFactor,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12 * effectiveScaleFactor),
              ),
              child: MediaQuery(
                data: mediaQuery.copyWith(textScaler: TextScaler.linear(1.0)),
                child: Text(
                  AppLocalizations.of(context).featured,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10 * effectiveScaleFactor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _Banner(
            product: widget.product,
            effectiveScaleFactor: effectiveScaleFactor,
            mediaQuery: mediaQuery,
          ),
        ),
        if (imageCount > 1 && !isFantasyProduct)
          Positioned(
            bottom: overlayBottomOffset,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * effectiveScaleFactor,
                  vertical: 4 * effectiveScaleFactor,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius:
                      BorderRadius.circular(16 * effectiveScaleFactor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(dotCount, (dotIndex) {
                    final bool isActive = dotIndex == activeDotIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(
                          horizontal: 3 * effectiveScaleFactor),
                      width: isActive
                          ? 8 * effectiveScaleFactor
                          : 6 * effectiveScaleFactor,
                      height: isActive
                          ? 8 * effectiveScaleFactor
                          : 6 * effectiveScaleFactor,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.orange
                            : Colors.white.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageWidget(String imageUrl, double height) {
    return RepaintBoundary(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) =>
            _buildImagePlaceholder(effectiveScaleFactor),
        errorWidget: (context, url, error) =>
            _buildImageErrorWidget(effectiveScaleFactor),
      ),
    );
  }

  Widget _buildNoImageWidget(double effectiveScaleFactor) {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported,
        size: 35 * effectiveScaleFactor * widget.internalScaleFactor,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildImagePlaceholder(double effectiveScaleFactor) {
    final isDark = theme.brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E1C2C) : const Color(0xFFE0E0E0),
      highlightColor:
          isDark ? const Color(0xFF211F31) : const Color(0xFFF5F5F5),
      period: const Duration(milliseconds: 1200),
      child: const ColoredBox(
        color: Colors.white,
        child: SizedBox.expand(),
      ),
    );
  }

  Widget _buildImageErrorWidget(double effectiveScaleFactor) {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image,
        size: 35 * effectiveScaleFactor * widget.internalScaleFactor,
        color: Colors.grey,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final ProductSummary product;
  final double effectiveScaleFactor;
  final MediaQueryData mediaQuery;

  const _Banner({
    Key? key,
    required this.product,
    required this.effectiveScaleFactor,
    required this.mediaQuery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasFastDelivery = product.deliveryOption == "Fast Delivery";
    final int discountPercentage = product.discountPercentage ?? 0;
    final bool hasDiscount = discountPercentage >= 10;

    if (!hasFastDelivery && !hasDiscount) {
      return const SizedBox.shrink();
    }

    final double bannerHeight = 20.0 * effectiveScaleFactor;

    Widget bannerText(String text) {
      return MediaQuery(
        data: mediaQuery.copyWith(textScaler: TextScaler.linear(1.0)),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 * effectiveScaleFactor,
          ),
        ),
      );
    }

    if (hasFastDelivery && hasDiscount) {
      return _RotatingBanner(
        height: bannerHeight,
        duration: const Duration(seconds: 2),
        children: [
          Container(
            width: double.infinity,
            height: bannerHeight,
            color: Colors.orange,
            alignment: Alignment.center,
            child: bannerText(AppLocalizations.of(context).fastDelivery),
          ),
          Container(
            width: double.infinity,
            height: bannerHeight,
            color: _ProductCardState.jadeGreen,
            alignment: Alignment.center,
            child: bannerText(AppLocalizations.of(context).discount),
          ),
        ],
      );
    } else if (hasFastDelivery) {
      return Container(
        width: double.infinity,
        height: bannerHeight,
        color: Colors.orange,
        alignment: Alignment.center,
        child: bannerText(AppLocalizations.of(context).fastDelivery),
      );
    } else {
      return Container(
        width: double.infinity,
        height: bannerHeight,
        color: _ProductCardState.jadeGreen,
        alignment: Alignment.center,
        child: bannerText(AppLocalizations.of(context).discount),
      );
    }
  }
}

class _FavoriteIcon extends StatefulWidget {
  final ProductSummary product;
  final double scaleFactor;

  const _FavoriteIcon({
    Key? key,
    required this.product,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  State<_FavoriteIcon> createState() => _FavoriteIconState();
}

class _FavoriteIconState extends State<_FavoriteIcon> {
  @override
  Widget build(BuildContext context) {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);

    return ValueListenableBuilder<Set<String>>(
      valueListenable: favoriteProvider.globalFavoriteIdsNotifier,
      builder: (context, globalFavoriteIds, child) {
        final bool isFavorited = globalFavoriteIds.contains(widget.product.id);

        return GestureDetector(
          onTap: () async {
            if (favoriteProvider.isGloballyFavorited(widget.product.id)) {
              final inBasket =
                  await favoriteProvider.isFavoritedInBasket(widget.product.id);

              if (!mounted) return; // ✅ Add mounted check

              if (inBasket) {
                final basketName = await favoriteProvider
                        .getBasketNameForProduct(widget.product.id) ??
                    'Basket';

                if (!mounted) return; // ✅ Add mounted check

                final confirm = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (dialogContext) {
                    return CupertinoAlertDialog(
                      title: Text(AppLocalizations.of(context)
                          .removeFromBasketTitle(basketName)),
                      content: Text(AppLocalizations.of(context)
                          .removeFromBasketContent(basketName)),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(
                            AppLocalizations.of(context).cancel,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Figtree',
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(
                            AppLocalizations.of(context).confirm,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Figtree',
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );

                if (!mounted) return; // ✅ Add mounted check after dialog
                if (confirm != true) return;
              }
              await favoriteProvider
                  .removeGloballyFromFavorites(widget.product.id);
              return;
            } else {
              if (!mounted) return; // ✅ Add mounted check
              await favoriteProvider.addToFavorites(
                widget.product.id,
                quantity: 1,
                selectedColor: null,
                selectedColorImage: widget.product.imageUrls.isNotEmpty
                    ? widget.product.imageUrls.first
                    : null,
                additionalAttributes: {},
                context: context,
              );
            }
          },
          child: Container(
            width: 18 * widget.scaleFactor,
            height: 18 * widget.scaleFactor,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(230),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(26),
                  blurRadius: 2 * widget.scaleFactor,
                  offset: Offset(0, 1 * widget.scaleFactor),
                ),
              ],
            ),
            child: Icon(
              isFavorited ? Icons.favorite : Icons.favorite_border,
              color: isFavorited ? Colors.red : Colors.grey,
              size: 12 * widget.scaleFactor,
            ),
          ),
        );
      },
    );
  }
}

class _AddToCartIconButton extends StatefulWidget {
  final String productId;
  final double scaleFactor;

  const _AddToCartIconButton({
    Key? key,
    required this.productId,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  State<_AddToCartIconButton> createState() => _AddToCartIconButtonState();
}

class _AddToCartIconButtonState extends State<_AddToCartIconButton> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cartIconColor = isDarkMode ? Colors.white : Colors.black;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: Provider.of<CartProvider>(context, listen: false)
          .cartProductIdsNotifier,
      builder: (context, cartIds, child) {
        final isInCart = cartIds.contains(widget.productId);
        final iconToShow = isInCart ? Icons.check : Icons.add_shopping_cart;

        return GestureDetector(
          onTap: _isProcessing
    ? null
    : () async {
        setState(() => _isProcessing = true);
        try {
          final cartProvider =
              Provider.of<CartProvider>(context, listen: false);

          if (isInCart) {
            await cartProvider.removeFromCart(widget.productId);
          } else {
            // Fetch full product for option selector
            final repo = context.read<ProductRepository>();
            final fullProduct = await repo.fetchById(widget.productId);
            if (!context.mounted) return;

            final selections =
                await showCupertinoModalPopup<Map<String, dynamic>?>(
              context: context,
              builder: (_) => ProductOptionSelector(
                product: fullProduct,
                isBuyNow: false,
              ),
            );

                      if (selections == null) {
                        setState(() => _isProcessing = false);
                        return;
                      }

                      if (!context.mounted) return;

                      final qty = selections['quantity'] as int? ?? 1;
                      final selectedColor =
                          selections['selectedColor'] as String?;
                      final attrs = Map<String, dynamic>.from(selections)
                        ..remove('quantity')
                        ..remove('selectedColor');

                     await cartProvider.addProductToCart(
  fullProduct,         // ← use the fetched full Product
  quantity: qty,
  selectedColor: selectedColor,
  attributes: attrs.isNotEmpty ? attrs : null,
);
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint('Cart icon error: $e');
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isProcessing = false);
                    }
                  }
                },
          child: SizedBox(
            width: 24 * widget.scaleFactor,
            height: 24 * widget.scaleFactor,
            child: Transform.translate(
              offset: Offset(0, -4 * widget.scaleFactor),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _isProcessing
                    ? SizedBox(
                        width: 14 * widget.scaleFactor,
                        height: 14 * widget.scaleFactor,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(cartIconColor),
                        ),
                        key: const ValueKey('processing'),
                      )
                    : Icon(
                        iconToShow,
                        key: ValueKey(iconToShow),
                        color: cartIconColor,
                        size: 16 * widget.scaleFactor,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ✅ OPTIMIZATION 13: Optimize RotatingText with SingleTickerProviderStateMixin
class RotatingText extends StatefulWidget {
  final List<Widget> children;
  final Duration duration;

  const RotatingText({
    Key? key,
    required this.children,
    this.duration = const Duration(milliseconds: 1500),
  }) : super(key: key);

  @override
  _RotatingTextState createState() => _RotatingTextState();
}

class _RotatingTextState extends State<RotatingText>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  void _setupController() {
    if (widget.children.length > 1) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.duration,
      )..addStatusListener(_onAnimationStatus);
      _controller!.forward();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.children.length;
      });
      _controller!.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(RotatingText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.children.length <= 1) {
      _controller?.dispose();
      _controller = null;
      _currentIndex = 0;
    } else if (_controller == null) {
      _setupController();
    } else if (widget.children.length > 1) {
      _currentIndex = _currentIndex.clamp(0, widget.children.length - 1);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (widget.children.length == 1) {
      return widget.children[0];
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    double localScaleFactor = (screenWidth / 375).clamp(0.8, 1.0);

    return SizedBox(
      height: 18 * localScaleFactor,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: widget.children[_currentIndex],
        ),
      ),
    );
  }
}

class _RotatingBanner extends StatefulWidget {
  final List<Widget> children;
  final Duration duration;
  final double height;

  const _RotatingBanner({
    Key? key,
    required this.children,
    required this.duration,
    required this.height,
  }) : super(key: key);

  @override
  __RotatingBannerState createState() => __RotatingBannerState();
}

class __RotatingBannerState extends State<_RotatingBanner>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  void _setupController() {
    if (widget.children.length > 1) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.duration,
      )..addStatusListener(_onAnimationStatus);
      _controller!.forward();
    }
  }

  @override
  void didUpdateWidget(_RotatingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.children.length <= 1) {
      _controller?.dispose();
      _controller = null;
      _currentIndex = 0;
    } else if (_controller == null) {
      _setupController();
    } else if (widget.children.length > 1) {
      _currentIndex = _currentIndex.clamp(0, widget.children.length - 1);
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.children.length;
      });
      _controller!.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller?.removeStatusListener(_onAnimationStatus);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: widget.children[_currentIndex],
        ),
      ),
    );
  }
}

class _ExtraLabel extends StatelessWidget {
  final String text;
  final List<Color> gradientColors;
  final double scaleFactor;

  const _ExtraLabel({
    Key? key,
    required this.text,
    required this.gradientColors,
    required this.scaleFactor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 4 * scaleFactor,
        vertical: 2 * scaleFactor,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(4 * scaleFactor),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10 * scaleFactor,
        ),
      ),
    );
  }
}
