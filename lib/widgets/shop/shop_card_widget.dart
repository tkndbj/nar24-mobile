import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
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

/// Optimized cover image with stable caching and constrained memory footprint.
/// memCacheWidth caps the decoded bitmap size in memory so large originals
/// don't blow up the image cache and cause re-decode flicker on scroll.
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
      // Eliminate ALL fade transitions to prevent flicker
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      // Cap decoded bitmap at ~360px wide (covers ~120dp cover at 3x).
      // This keeps memory usage predictable when many cards are loaded.
      memCacheWidth: 360,
      memCacheHeight: 240,
      placeholder: (context, url) => const _ShimmerCoverPlaceholder(),
      errorWidget: (context, url, error) => const _ImageErrorPlaceholder(),
      filterQuality: FilterQuality.medium,
      useOldImageOnUrlChange: true,
    );
  }
}

/// Shimmer placeholder for cover image loading.
/// Uses the same dark/light color scheme as the rest of the app.
class _ShimmerCoverPlaceholder extends StatelessWidget {
  const _ShimmerCoverPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

/// Profile avatar with flicker-free image loading.
///
/// Uses CachedNetworkImage inside ClipOval instead of DecorationImage +
/// CachedNetworkImageProvider. DecorationImage has no fade-duration control
/// and triggers a visible flash every time the widget rebuilds. Wrapping
/// CachedNetworkImage lets us set fadeIn/fadeOut to Duration.zero.
class _ProfileAvatar extends StatelessWidget {
  final String profileImageUrl;

  // Pre-computed constant decoration for the outer ring + shadow.
  // Allocated once and reused across all instances.
  static const _outerDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: Color(0xFFEEEEEE), // Colors.grey.shade200 equivalent
    boxShadow: [
      BoxShadow(
        color: Color(0x1A000000), // black12-ish
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
    ],
  );

  const _ProfileAvatar({
    Key? key,
    required this.profileImageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasImage = profileImageUrl.isNotEmpty;

    return DecoratedBox(
      decoration: _outerDecoration,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: ClipOval(
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: profileImageUrl,
                  fit: BoxFit.cover,
                  width: 44, // 48 - 2*2 border
                  height: 44,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholderFadeInDuration: Duration.zero,
                  memCacheWidth: 132, // 44 * 3 for retina
                  memCacheHeight: 132,
                  useOldImageOnUrlChange: true,
                  placeholder: (context, url) =>
                      const _ShimmerAvatarPlaceholder(),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 24,
                  ),
                )
              : const Icon(Icons.person, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// Shimmer placeholder for the circular profile avatar.
class _ShimmerAvatarPlaceholder extends StatelessWidget {
  const _ShimmerAvatarPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
