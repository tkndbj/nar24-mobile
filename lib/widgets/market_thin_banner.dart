import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../services/ad_analytics_service.dart';
import '../utils/cloudinary_url_builder.dart';
import 'cloudinary_image.dart';

// Thin banner target width — matches max device width at 2x DPR.
const int _kThinBannerCdnWidth = 800;

class MarketThinBanner extends StatefulWidget {
  final bool shouldAutoPlay;
  const MarketThinBanner({
    Key? key,
    this.shouldAutoPlay = true, // Default to true for backwards compatibility
  }) : super(key: key);

  @override
  _MarketThinBannerState createState() => _MarketThinBannerState();
}

class ThinBannerItem {
  final String id;
  final String url;
  final String? linkType;
  final String? linkId;

  ThinBannerItem({
    required this.id,
    required this.url,
    this.linkType,
    this.linkId,
  });
}

class _MarketThinBannerState extends State<MarketThinBanner>
    with
        AutomaticKeepAliveClientMixin<MarketThinBanner>,
        SingleTickerProviderStateMixin {
  final Set<String> _cachedUrls = {};
  List<ThinBannerItem> _banners = [];
  StreamSubscription<QuerySnapshot>? _subscription;

  // ✅ VSYNC-controlled auto-play
  AnimationController? _autoPlayController;
  int _currentIndex = 0;
  PageController? _pageController;

  @override
  bool get wantKeepAlive => true;

  // ✅ For infinite scroll simulation
  static const int _kMiddlePage = 10000;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _kMiddlePage);

    // Listen to thin banners collection
    _subscription = FirebaseFirestore.instance
        .collection('market_thin_banners')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(_onBannerSnapshot);
  }

  void _setupAutoPlayController() {
    _autoPlayController?.removeStatusListener(_onAutoPlayStatus);
    _autoPlayController?.dispose();

    if (_banners.length > 1 && widget.shouldAutoPlay) {
      _autoPlayController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 4),
      )..addStatusListener(_onAutoPlayStatus);
      _autoPlayController!.forward();
    } else {
      _autoPlayController = null;
    }
  }

  void _onAutoPlayStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        mounted &&
        widget.shouldAutoPlay) {
      // ✅ Always move forward for infinite right-to-left scroll
      final currentPage = _pageController?.page?.round() ?? _kMiddlePage;
      _pageController?.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _autoPlayController!.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(MarketThinBanner oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle shouldAutoPlay changes
    if (widget.shouldAutoPlay != oldWidget.shouldAutoPlay) {
      if (widget.shouldAutoPlay && _banners.length > 1) {
        if (_autoPlayController == null) {
          _setupAutoPlayController();
        } else {
          _autoPlayController!.forward();
        }
      } else {
        _autoPlayController?.stop();
      }
    }
  }

  Future<void> _onBannerSnapshot(QuerySnapshot snap) async {
    final items = <ThinBannerItem>[];

    for (var doc in snap.docs) {
      final data = doc.data()! as Map<String, dynamic>;
      // ✅ Prefer storage path, fall back to URL
      final source = (data['imageStoragePath'] as String?) ??
          (data['imageUrl'] as String? ?? '');
      if (source.isEmpty) continue;

      // Prefetch the CDN URL so cache keys match.
      if (!_cachedUrls.contains(source)) {
        _cachedUrls.add(source);
        final cdnUrl = CloudinaryUrl.bannerCdn(source, width: _kThinBannerCdnWidth);
        final provider = CachedNetworkImageProvider(cdnUrl);
        precacheImage(provider, context);
      }

      items.add(ThinBannerItem(
        id: doc.id,
        url: source,
        linkType: data['linkType'] as String?,
        linkId: data['linkedShopId'] ?? data['linkedProductId'],
      ));
    }

    setState(() => _banners = items);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setupAutoPlayController();
    });
  }

 Widget _buildBannerImage(String source, double bannerHeight) {
    return CloudinaryImage.banner(
      source: source,
      cdnWidth: _kThinBannerCdnWidth,
      width: double.infinity,
      height: bannerHeight,
      fit: BoxFit.fill,
      placeholderBuilder: (_) => Container(
        width: double.infinity,
        height: bannerHeight,
        color: Colors.grey.shade200,
      ),
      errorBuilder: (_) => const Center(child: Icon(Icons.error)),
    );
  }

  void _handleBannerTap(ThinBannerItem item) {
    // ✅ TRACK CLICK
    AdAnalyticsService.trackAdClick(
      adId: item.id,
      adType: 'thinBanner',
      linkedType: item.linkType,
      linkedId: item.linkId,
    );

    if (item.linkType != null && item.linkId != null) {
      switch (item.linkType) {
        case 'shop':
          context.push('/shop_detail/${item.linkId}');
          break;
        case 'product':
        case 'shop_product':
        default:
          context.push('/product/${item.linkId}');
      }
    }
  }

  @override
  void dispose() {
    _autoPlayController?.removeStatusListener(_onAutoPlayStatus);
    _autoPlayController?.dispose();
    _pageController?.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_banners.isEmpty) {
      return const SizedBox.shrink();
    }

    // Reuse a const gradient—no need to recreate each build
    const LinearGradient marketGradient = LinearGradient(
      colors: [Colors.orange, Colors.pink, Color.fromARGB(255, 252, 178, 18)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    const double bannerHeight = 48;

    return Container(
      height: bannerHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: marketGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _banners.length <= 1
          // Single image: CachedNetworkImage for caching
          ? GestureDetector(
              onTap: () => _handleBannerTap(_banners.first),
              child: _buildBannerImage(_banners.first.url, bannerHeight),
            )
          // ✅ VSYNC-controlled PageView with infinite scroll
          : PageView.builder(
              controller: _pageController,
              // ✅ No itemCount = infinite in both directions
              onPageChanged: (index) {
                final actualIndex = index % _banners.length;
                setState(() => _currentIndex = actualIndex);
                // Reset auto-play timer on manual swipe
                if (widget.shouldAutoPlay) {
                  _autoPlayController?.forward(from: 0);
                }
              },
              itemBuilder: (context, index) {
                // ✅ Use modulo for infinite loop
                final actualIndex = index % _banners.length;
                final item = _banners[actualIndex];
                return GestureDetector(
                  onTap: () => _handleBannerTap(item),
                  child: _buildBannerImage(item.url, bannerHeight),
                );
              },
            ),
    );
  }
}
