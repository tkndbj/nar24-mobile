import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services/ad_analytics_service.dart';

class AdsBannerWidget extends StatefulWidget {
  final ValueNotifier<Color> backgroundColorNotifier;
  final bool shouldAutoPlay;

  const AdsBannerWidget({
    Key? key,
    required this.backgroundColorNotifier,
    this.shouldAutoPlay = true,
  }) : super(key: key);

  @override
  _AdsBannerWidgetState createState() => _AdsBannerWidgetState();
}

class BannerItem {
  final String id;
  final String url;
  final Color color;
  final String? linkType;
  final String? linkId;

  BannerItem({
    required this.id,
    required this.url,
    required this.color,
    this.linkType,
    this.linkId,
  });
}

class _AdsBannerWidgetState extends State<AdsBannerWidget>
    with
        AutomaticKeepAliveClientMixin<AdsBannerWidget>,
        TickerProviderStateMixin {
  final Set<String> _cachedUrls = <String>{};
  List<BannerItem> _banners = <BannerItem>[];
  StreamSubscription<QuerySnapshot>? _subscription;

  SharedPreferences? _prefs;

  late double _screenWidth;
  late double _devicePixelRatio;
  late int _maxWidth;
  late int _maxHeight;

  AnimationController? _autoPlayController;
  int _currentIndex = 0;
  PageController? _pageController;

  static const int _kMiddlePage = 10000;

  // ✅ NEW: Track actual visibility in viewport
  bool _isVisibleInViewport = true;

  @override
  bool get wantKeepAlive => true;

  // ✅ NEW: Computed property combining both conditions
  bool get _effectiveAutoPlay =>
      widget.shouldAutoPlay && _isVisibleInViewport && _banners.length > 1;

  bool _isLargerScreen(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final orientation = mediaQuery.orientation;

    final shortestSide =
        orientation == Orientation.portrait ? screenWidth : screenHeight;
    return shortestSide >= 600 ||
        (orientation == Orientation.landscape && screenWidth >= 900);
  }

  double _calculateBannerHeight(BuildContext context) {
    if (!_isLargerScreen(context)) {
      return 150.0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;

    if (orientation == Orientation.portrait) {
      return (screenWidth * 0.38).clamp(280.0, 400.0);
    } else {
      final screenHeight = MediaQuery.of(context).size.height;
      return (screenHeight * 0.52).clamp(320.0, 480.0);
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _kMiddlePage);
    _initializeAsync();
  }

  // ✅ UPDATED: Respects both shouldAutoPlay AND visibility
  void _setupAutoPlayController() {
    _autoPlayController?.removeStatusListener(_onAutoPlayStatus);
    _autoPlayController?.dispose();

    if (_banners.length > 1) {
      _autoPlayController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 4),
      )..addStatusListener(_onAutoPlayStatus);

      // Only start if effectively should auto-play
      if (_effectiveAutoPlay) {
        _autoPlayController!.forward();
      }
    } else {
      _autoPlayController = null;
    }
  }

  void _onAutoPlayStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _effectiveAutoPlay) {
      final currentPage = _pageController?.page?.round() ?? _kMiddlePage;
      _pageController?.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _autoPlayController!.forward(from: 0);
    }
  }

  // ✅ NEW: Handle visibility changes from VisibilityDetector
  void _onVisibilityChanged(VisibilityInfo info) {
    // Don't process visibility changes if widget is disposed
    if (!mounted) return;

    // Consider visible if more than 50% is shown
    final isVisible = info.visibleFraction > 0.5;

    if (_isVisibleInViewport != isVisible) {
      _isVisibleInViewport = isVisible;
      _updateAutoPlayState();
    }
  }

  // ✅ NEW: Centralized auto-play state management
  void _updateAutoPlayState() {
    // Guard against calls after dispose or when controller doesn't exist
    if (!mounted) return;

    final controller = _autoPlayController;
    if (controller == null) return;

    if (_effectiveAutoPlay) {
      if (!controller.isAnimating) {
        controller.forward();
      }
    } else {
      // Only stop if actively animating (disposed controllers won't be animating)
      if (controller.isAnimating) {
        controller.stop();
      }
    }
  }

  @override
  void didUpdateWidget(AdsBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle shouldAutoPlay prop changes
    if (widget.shouldAutoPlay != oldWidget.shouldAutoPlay) {
      _updateAutoPlayState();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _devicePixelRatio = mediaQuery.devicePixelRatio;
    _maxWidth = (_screenWidth * _devicePixelRatio).toInt();

    final bannerHeight = _calculateBannerHeight(context);
    _maxHeight = (bannerHeight * _devicePixelRatio).toInt();
  }

  Future<void> _initializeAsync() async {
    try {
      _prefs = await SharedPreferences.getInstance();

      final stored = _prefs?.getInt('lastAdsBannerColor');
      if (stored != null && mounted) {
        widget.backgroundColorNotifier.value = Color(stored);
      }

      _setupFirestoreListener();
    } catch (e) {
      debugPrint('Error initializing AdsBannerWidget: $e');
    }
  }

  void _setupFirestoreListener() {
    _subscription = FirebaseFirestore.instance
        .collection('market_top_ads_banners')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      _onBannerSnapshot,
      onError: (error) {
        debugPrint('Firestore error in AdsBannerWidget: $error');
      },
    );
  }

  Future<void> _onBannerSnapshot(QuerySnapshot snap) async {
    if (!mounted) return;

    try {
      final items = <BannerItem>[];

      for (int i = 0; i < snap.docs.length; i++) {
        final doc = snap.docs[i];
        final data = doc.data()! as Map<String, dynamic>;
        final url = data['imageUrl'] as String? ?? '';
        if (url.isEmpty) continue;

        final cInt = data['dominantColor'] as int?;
        final color = cInt != null ? Color(cInt) : Colors.grey;

        if (!_cachedUrls.contains(url)) {
          _cachedUrls.add(url);
          _prefetchImageAsync(url);
        }

        items.add(BannerItem(
          id: doc.id,
          url: url,
          color: color,
          linkType: data['linkType'] as String?,
          linkId: data['linkedShopId'] ?? data['linkedProductId'],
        ));

        if (i % 3 == 0 && i > 0) {
          await Future.delayed(const Duration(microseconds: 1));
        }
      }

      if (mounted) {
        setState(() => _banners = items);
        _updateBackgroundColor(items);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setupAutoPlayController();
        });
      }
    } catch (e) {
      debugPrint('Error processing banner snapshot: $e');
    }
  }

  void _prefetchImageAsync(String url) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Fixed width constraint - height scales proportionally
        final provider = CachedNetworkImageProvider(url, maxWidth: 1200);
        precacheImage(provider, context).catchError((error) {
          debugPrint('Failed to prefetch image: $url, error: $error');
        });
      }
    });
  }

  void _updateBackgroundColor(List<BannerItem> items) {
    if (items.isNotEmpty) {
      final firstColor = items.first.color;
      widget.backgroundColorNotifier.value = firstColor;

      _prefs
          ?.setInt('lastAdsBannerColor', firstColor.value)
          .catchError((error) {
        debugPrint('Failed to save banner color: $error');
        return false;
      });
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

    final bannerHeight = _calculateBannerHeight(context);
    final isLargerScreen = _isLargerScreen(context);

    if (_banners.isEmpty) {
      return Container(
        height: bannerHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(isLargerScreen ? 12 : 8),
        ),
        child: Center(
          child: Container(
            width: isLargerScreen ? 40 : 32,
            height: isLargerScreen ? 40 : 32,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(isLargerScreen ? 20 : 16),
            ),
          ),
        ),
      );
    }

    // ✅ WRAP WITH VisibilityDetector
    return VisibilityDetector(
      key: const Key('ads_banner_widget'),
      onVisibilityChanged: _onVisibilityChanged,
      child: RepaintBoundary(
        child: SizedBox(
          height: bannerHeight,
          width: double.infinity,
          child: ValueListenableBuilder<Color>(
            valueListenable: widget.backgroundColorNotifier,
            builder: (context, bgColor, child) {
              return Container(color: bgColor, child: child);
            },
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (idx) {
                final actualIndex = idx % _banners.length;
                setState(() => _currentIndex = actualIndex);
                _handlePageChange(actualIndex);
                // Reset auto-play timer on manual swipe (only if effective)
                if (_effectiveAutoPlay) {
                  _autoPlayController?.forward(from: 0);
                }
              },
              itemBuilder: (context, index) {
                final actualIndex = index % _banners.length;
                final item = _banners[actualIndex];
                return RepaintBoundary(
                  child: GestureDetector(
                    onTap: () => _handleBannerTap(item),
                    child: Container(
                      width: double.infinity,
                      color: isLargerScreen ? item.color : null,
                      child: CachedNetworkImage(
                        imageUrl: item.url,
                        fit: isLargerScreen ? BoxFit.contain : BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[200],
                          width: double.infinity,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          width: double.infinity,
                          child: Icon(
                            Icons.error,
                            color: Colors.grey,
                            size: isLargerScreen ? 32 : 24,
                          ),
                        ),
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        useOldImageOnUrlChange: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _handleBannerTap(BannerItem item) {
    AdAnalyticsService.trackAdClick(
      adId: item.id,
      adType: 'topBanner',
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

  void _handlePageChange(int idx) {
    if (idx < _banners.length) {
      final color = _banners[idx].color;
      widget.backgroundColorNotifier.value = color;
      _prefs?.setInt('lastAdsBannerColor', color.value);
    }
  }
}
