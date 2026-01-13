import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/shop_widget_provider.dart';
import '../../screens/SHOP-SCREENS/shop_detail_screen.dart';
import '../../providers/shop_provider.dart';

class ShopCardWidget extends StatefulWidget {
  final Map<String, dynamic> shop;
  final String shopId;
  final double averageRating;

  const ShopCardWidget({
    Key? key,
    required this.shop,
    required this.shopId,
    required this.averageRating,
  }) : super(key: key);

  @override
  State<ShopCardWidget> createState() => _ShopCardWidgetState();
}

class _ShopCardWidgetState extends State<ShopCardWidget>
    with AutomaticKeepAliveClientMixin {
  // ✅ CRITICAL: Prevent concurrent navigation spam
  static DateTime? _lastNavigationTime;
  static const _navigationThrottle = Duration(milliseconds: 500);

  // ✅ OPTIMIZATION 1: Cache computed values
  late String _shopName;
  late List<String> _coverImageList;
  late String _profileImageUrl;
  late String _ownerId;
  late bool _hasCoverImages;

  // ✅ Track initialization to avoid re-running
  bool _isInitialized = false;

  // ✅ OPTIMIZATION 2: Keep widget alive to avoid rebuilds when scrolling
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // ✅ Initialize data that doesn't depend on context
    _initializeContextFreeData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ Initialize data that depends on context (like AppLocalizations)
    if (!_isInitialized) {
      _initializeContextDependentData();
      _isInitialized = true;
    }
  }

  /// Data that doesn't need context - safe in initState
  void _initializeContextFreeData() {
    // Parse cover images once
    if (widget.shop['coverImageUrls'] is List) {
      _coverImageList = List<String>.from(widget.shop['coverImageUrls']);
    } else if ((widget.shop['coverImageUrl'] as String?)?.isNotEmpty == true) {
      _coverImageList = [widget.shop['coverImageUrl']];
    } else {
      _coverImageList = [];
    }

    _hasCoverImages = _coverImageList.isNotEmpty;
    _profileImageUrl = widget.shop['profileImageUrl'] as String? ?? '';
    _ownerId = widget.shop['ownerId'] as String? ?? '';
  }

  /// Data that needs context - must be in didChangeDependencies
  void _initializeContextDependentData() {
    final l10n = AppLocalizations.of(context);
    _shopName = widget.shop['name'] as String? ?? l10n.noName;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);

    return _ShopCardContent(
      state: this,
      widget: widget,
      mediaQuery: mediaQuery,
      theme: theme,
    );
  }

  Route _shopDetailRoute(String shopId) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        return ChangeNotifierProvider<ShopProvider>(
          create: (_) {
            final prov = ShopProvider();
            prov.initializeData(null, shopId);
            return prov;
          },
          child: ShopDetailScreen(shopId: shopId),
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
  }

  Future<void> _navigateToShopDetail(
    BuildContext context,
    ShopWidgetProvider widgetProv,
    bool isOwner,
  ) async {
    final now = DateTime.now();

    if (_lastNavigationTime != null &&
        now.difference(_lastNavigationTime!) < _navigationThrottle) {
      return;
    }

    _lastNavigationTime = now;

    if (!isOwner) {
      widgetProv
          .incrementClickCount(widget.shopId)
          .catchError((e) => debugPrint('Click count error: $e'));
    }

    Navigator.of(context).push(_shopDetailRoute(widget.shopId));
  }
}

// ✅ OPTIMIZATION 4: Split into separate widget to reduce rebuild scope
class _ShopCardContent extends StatelessWidget {
  final _ShopCardWidgetState state;
  final ShopCardWidget widget;
  final MediaQueryData mediaQuery;
  final ThemeData theme;

  const _ShopCardContent({
    Key? key,
    required this.state,
    required this.widget,
    required this.mediaQuery,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final widgetProv = context.read<ShopWidgetProvider>();
    final l10n = AppLocalizations.of(context);
    final currentUser = widgetProv.currentUser;

    final isDark = theme.brightness == Brightness.dark;
    final mainTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor =
        isDark ? Colors.grey.shade300 : Colors.grey.shade700;

    final isOwner = currentUser?.uid == state._ownerId;

    // Detect tablet for shorter card height
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return InkWell(
      onTap: () => state._navigateToShopDetail(context, widgetProv, isOwner),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // Tablet: minimize height to content, Mobile: expand to fill
          mainAxisSize: isTablet ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _CoverSection(
              state: state,
              widgetProv: widgetProv,
              secondaryTextColor: secondaryTextColor,
              l10n: l10n,
              mediaQuery: mediaQuery,
            ),
            _ShopInfo(
              shopName: state._shopName,
              averageRating: widget.averageRating,
              mainTextColor: mainTextColor,
              secondaryTextColor: secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ OPTIMIZATION 5: Extract cover section to avoid rebuilds
class _CoverSection extends StatelessWidget {
  final _ShopCardWidgetState state;
  final ShopWidgetProvider widgetProv;
  final Color secondaryTextColor;
  final AppLocalizations l10n;
  final MediaQueryData mediaQuery;

  const _CoverSection({
    Key? key,
    required this.state,
    required this.widgetProv,
    required this.secondaryTextColor,
    required this.l10n,
    required this.mediaQuery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: state._hasCoverImages
                ? _CoverImageCarousel(
                    coverImages: state._coverImageList,
                    mediaQuery: mediaQuery,
                  )
                : _NoCoverImage(),
          ),
        ),
        Positioned(
          top: 8,
          right: 4,
          child: _ActionButtons(
            shopId: state.widget.shopId,
            shopName: state._shopName,
            widgetProv: widgetProv,
            secondaryTextColor: secondaryTextColor,
            l10n: l10n,
          ),
        ),
        Positioned(
          right: 16,
          bottom: -18,
          child: _ProfileAvatar(
            profileImageUrl: state._profileImageUrl,
          ),
        ),
      ],
    );
  }
}

// ✅ OPTIMIZATION 6: Separate carousel widget with optimizations
class _CoverImageCarousel extends StatelessWidget {
  final List<String> coverImages;
  final MediaQueryData mediaQuery;

  const _CoverImageCarousel({
    Key? key,
    required this.coverImages,
    required this.mediaQuery,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ✅ Single image optimization - no PageView needed
    if (coverImages.length == 1) {
      return _buildCoverImage(coverImages[0]);
    }

    return PageView.builder(
      itemCount: coverImages.length,
      // ✅ OPTIMIZATION 7: Limit pre-cached pages for memory efficiency
      controller: PageController(viewportFraction: 1.0),
      itemBuilder: (ctx, i) => _buildCoverImage(coverImages[i]),
    );
  }

  Widget _buildCoverImage(String imageUrl) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      // ✅ OPTIMIZATION 8: Cache network images with size constraints
      memCacheHeight: (120 * mediaQuery.devicePixelRatio).round(),
      maxHeightDiskCache: (120 * mediaQuery.devicePixelRatio).round(),
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (_, __, ___) => _buildErrorWidget(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/images/narsiyah.png',
        width: 80,
        height: 80,
        fit: BoxFit.contain,
        // ✅ OPTIMIZATION 9: Cache asset images
        cacheWidth: 80,
        cacheHeight: 80,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.image,
            size: 40,
            color: Colors.grey,
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(
        Icons.broken_image,
        size: 40,
        color: Colors.grey,
      ),
    );
  }
}

// ✅ OPTIMIZATION 10: Extract static no-cover widget
class _NoCoverImage extends StatelessWidget {
  const _NoCoverImage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported),
    );
  }
}

// ✅ OPTIMIZATION 11: Extract action buttons
class _ActionButtons extends StatefulWidget {
  final String shopId;
  final String shopName;
  final ShopWidgetProvider widgetProv;
  final Color secondaryTextColor;
  final AppLocalizations l10n;

  const _ActionButtons({
    Key? key,
    required this.shopId,
    required this.shopName,
    required this.widgetProv,
    required this.secondaryTextColor,
    required this.l10n,
  }) : super(key: key);

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final isFavorite =
        widget.widgetProv.favoriteShopIds.contains(widget.shopId);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? Colors.red : widget.secondaryTextColor,
          isProcessing: _isProcessing,
          onPressed: _isProcessing ? null : _handleFavoriteToggle,
        ),
        const SizedBox(width: 2),
        _ActionButton(
          icon: Icons.share,
          color: widget.secondaryTextColor,
          onPressed: _handleShare,
        ),
      ],
    );
  }

  Future<void> _handleFavoriteToggle() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      await widget.widgetProv.toggleFavorite(widget.shopId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.widgetProv.favoriteShopIds.contains(widget.shopId)
                ? widget.l10n.addedToFavorites
                : widget.l10n.removedFromFavorites,
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('Fav error: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.l10n.errorTogglingFavorite),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleShare() {
    Share.share(widget.shopName);
  }
}

// ✅ OPTIMIZATION 12: Reusable action button widget
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool isProcessing;

  const _ActionButton({
    Key? key,
    required this.icon,
    required this.color,
    this.onPressed,
    this.isProcessing = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFFFFDD0),
      ),
      child: isProcessing
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              icon: Icon(icon, color: color),
              onPressed: onPressed,
            ),
    );
  }
}

// ✅ OPTIMIZATION 13: Extract profile avatar
class _ProfileAvatar extends StatelessWidget {
  final String profileImageUrl;

  const _ProfileAvatar({
    Key? key,
    required this.profileImageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasImage = profileImageUrl.isNotEmpty;

    return CircleAvatar(
      radius: 24,
      backgroundImage:
          hasImage ? CachedNetworkImageProvider(profileImageUrl) : null,
      backgroundColor: hasImage ? Colors.transparent : Colors.grey.shade200,
      child: hasImage
          ? null
          : const Icon(Icons.person, color: Colors.white, size: 24),
    );
  }
}

// ✅ OPTIMIZATION 14: Extract shop info section
class _ShopInfo extends StatelessWidget {
  final String shopName;
  final double averageRating;
  final Color mainTextColor;
  final Color secondaryTextColor;

  const _ShopInfo({
    Key? key,
    required this.shopName,
    required this.averageRating,
    required this.mainTextColor,
    required this.secondaryTextColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    // Tablet: reduce top spacing to prevent excessive empty gap
    final double topSpacing = isTablet ? 8.0 : 16.0;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topSpacing),
          Text(
            shopName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: mainTextColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (averageRating > 0) ...[
            const SizedBox(height: 2),
            _RatingRow(
              rating: averageRating,
              textColor: secondaryTextColor,
            ),
          ],
        ],
      ),
    );
  }
}

// ✅ OPTIMIZATION 15: Extract rating widget
class _RatingRow extends StatelessWidget {
  final double rating;
  final Color textColor;

  const _RatingRow({
    Key? key,
    required this.rating,
    required this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 14),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: 11, color: textColor),
        ),
      ],
    );
  }
}
