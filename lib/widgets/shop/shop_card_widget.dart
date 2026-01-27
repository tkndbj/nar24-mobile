import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/shop_widget_provider.dart';
import '../../screens/SHOP-SCREENS/shop_detail_screen.dart';
import '../../providers/shop_provider.dart';

/// Production-grade ShopCardWidget with optimized image rendering
///
/// Key fixes for image glitching:
/// 1. Stable PageController lifecycle management
/// 2. Fixed cache dimensions (not reactive to mediaQuery changes)
/// 3. Disabled fade animations to prevent flicker
/// 4. RepaintBoundary for isolated rendering
/// 5. Proper key management for widget identity
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
  // Navigation throttle to prevent spam
  static DateTime? _lastNavigationTime;
  static const _navigationThrottle = Duration(milliseconds: 500);

  // Cached computed values - initialized once
  late final String _shopName;
  late final List<String> _coverImageList;
  late final String _profileImageUrl;
  late final String _ownerId;
  late final bool _hasCoverImages;

  // FIX 1: Stable PageController - created once, disposed properly
  PageController? _pageController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _initializeData() {
    // Parse cover images once and make immutable
    if (widget.shop['coverImageUrls'] is List) {
      _coverImageList = List<String>.unmodifiable(
        (widget.shop['coverImageUrls'] as List).cast<String>(),
      );
    } else if ((widget.shop['coverImageUrl'] as String?)?.isNotEmpty == true) {
      _coverImageList =
          List<String>.unmodifiable([widget.shop['coverImageUrl']]);
    } else {
      _coverImageList = const [];
    }

    _hasCoverImages = _coverImageList.isNotEmpty;
    _profileImageUrl = widget.shop['profileImageUrl'] as String? ?? '';
    _ownerId = widget.shop['ownerId'] as String? ?? '';
    _shopName = widget.shop['name'] as String? ?? '';

    // Initialize PageController only if needed
    if (_coverImageList.length > 1) {
      _pageController = PageController();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final l10n = AppLocalizations.of(context);
    final displayName = _shopName.isNotEmpty ? _shopName : l10n.noName;

    // FIX 2: RepaintBoundary isolates this widget's rendering
    return RepaintBoundary(
      child: _ShopCardContent(
        key: ValueKey('shop_card_${widget.shopId}'),
        shopId: widget.shopId,
        shopName: displayName,
        averageRating: widget.averageRating,
        coverImageList: _coverImageList,
        hasCoverImages: _hasCoverImages,
        profileImageUrl: _profileImageUrl,
        ownerId: _ownerId,
        pageController: _pageController,
        onNavigate: _navigateToShopDetail,
      ),
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
        return SlideTransition(
          position: animation.drive(
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOut)),
          ),
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
      // Fire and forget - don't await
      widgetProv.incrementClickCount(widget.shopId).catchError(
            (e) => debugPrint('Click count error: $e'),
          );
    }

    if (context.mounted) {
      Navigator.of(context).push(_shopDetailRoute(widget.shopId));
    }
  }
}

/// Stateless content widget - receives all data as parameters
/// This prevents rebuilds from propagating unnecessarily
class _ShopCardContent extends StatelessWidget {
  final String shopId;
  final String shopName;
  final double averageRating;
  final List<String> coverImageList;
  final bool hasCoverImages;
  final String profileImageUrl;
  final String ownerId;
  final PageController? pageController;
  final Future<void> Function(BuildContext, ShopWidgetProvider, bool)
      onNavigate;

  const _ShopCardContent({
    Key? key,
    required this.shopId,
    required this.shopName,
    required this.averageRating,
    required this.coverImageList,
    required this.hasCoverImages,
    required this.profileImageUrl,
    required this.ownerId,
    required this.pageController,
    required this.onNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final widgetProv = context.read<ShopWidgetProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mainTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor =
        isDark ? Colors.grey.shade300 : Colors.grey.shade700;

    final currentUser = widgetProv.currentUser;
    final isOwner = currentUser?.uid == ownerId;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onNavigate(context, widgetProv, isOwner),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: isTablet ? MainAxisSize.min : MainAxisSize.max,
            children: [
              _CoverSection(
                shopName: shopName,
                coverImageList: coverImageList,
                hasCoverImages: hasCoverImages,
                profileImageUrl: profileImageUrl,
                pageController: pageController,
              ),
              _ShopInfoSection(
                shopName: shopName,
                averageRating: averageRating,
                mainTextColor: mainTextColor,
                isTablet: isTablet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover section with images and action buttons
class _CoverSection extends StatelessWidget {
  final String shopName;
  final List<String> coverImageList;
  final bool hasCoverImages;
  final String profileImageUrl;
  final PageController? pageController;

  const _CoverSection({
    Key? key,
    required this.shopName,
    required this.coverImageList,
    required this.hasCoverImages,
    required this.profileImageUrl,
    required this.pageController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 138, // 120 + space for avatar overflow
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover image container
          Positioned.fill(
            bottom: 18, // Leave space for avatar
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              // FIX 4: RepaintBoundary for image section
              child: RepaintBoundary(
                child: hasCoverImages
                    ? _buildCoverImages()
                    : const _NoCoverPlaceholder(),
              ),
            ),
          ),

          // Profile avatar
          Positioned(
            right: 16,
            bottom: 0,
            child: _ProfileAvatar(
              profileImageUrl: profileImageUrl,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImages() {
    // Single image - no PageView needed
    if (coverImageList.length == 1) {
      return _OptimizedCoverImage(
        key: ValueKey('cover_${coverImageList[0].hashCode}'),
        imageUrl: coverImageList[0],
      );
    }

    // Multiple images - use PageView with stable controller
    return PageView.builder(
      controller: pageController,
      itemCount: coverImageList.length,
      // FIX 5: Keep only adjacent pages in memory
      allowImplicitScrolling: false,
      itemBuilder: (context, index) {
        return _OptimizedCoverImage(
          key: ValueKey('cover_${coverImageList[index].hashCode}'),
          imageUrl: coverImageList[index],
        );
      },
    );
  }
}

/// Optimized cover image with stable caching
class _OptimizedCoverImage extends StatelessWidget {
  final String imageUrl;

  const _OptimizedCoverImage({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => const _ImageLoadingPlaceholder(),
      errorWidget: (context, url, error) => const _ImageErrorPlaceholder(),
      filterQuality: FilterQuality.medium,
      useOldImageOnUrlChange: true,
    );
  }
}

/// Loading placeholder with consistent appearance
class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Image.asset(
          'assets/images/nargri.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          cacheWidth: 160, // 2x for retina
          cacheHeight: 160,
          // FIX 11: Ensure asset loading doesn't throw
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.image,
            size: 40,
            color: Colors.grey.shade400,
          ),
          // Disable animations on asset image
          filterQuality: FilterQuality.low,
          isAntiAlias: false,
        ),
      ),
    );
  }
}

/// Error placeholder
class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(
        Icons.broken_image_outlined,
        size: 40,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// No cover image placeholder
class _NoCoverPlaceholder extends StatelessWidget {
  const _NoCoverPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 40,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// Profile avatar with optimized image loading
class _ProfileAvatar extends StatelessWidget {
  final String profileImageUrl;

  const _ProfileAvatar({
    Key? key,
    required this.profileImageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasImage = profileImageUrl.isNotEmpty;

    // FIX 13: Use Container with DecorationImage for more stable rendering
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade200,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        image: hasImage
            ? DecorationImage(
                image: CachedNetworkImageProvider(
                  profileImageUrl,
                  maxHeight: 144, // 48 * 3 for retina
                  maxWidth: 144,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasImage
          ? null
          : const Icon(Icons.person, color: Colors.white, size: 24),
    );
  }
}

/// Shop info section
class _ShopInfoSection extends StatelessWidget {
  final String shopName;
  final double averageRating;
  final Color mainTextColor;

  final bool isTablet;

  const _ShopInfoSection({
    Key? key,
    required this.shopName,
    required this.averageRating,
    required this.mainTextColor,
    required this.isTablet,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shopName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: mainTextColor,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (averageRating > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  averageRating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 12,
                    color: mainTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
