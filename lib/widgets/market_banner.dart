import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import '../services/ad_analytics_service.dart';
import '../providers/market_banner_provider.dart';

class MarketBannerItem {
  final String id;
  final String url;
  final String? linkType;
  final String? linkId;

  MarketBannerItem({
    required this.id,
    required this.url,
    this.linkType,
    this.linkId,
  });
}

/// A lazy-loading market banner sliver that:
/// 1. Only fetches from Firestore when the widget becomes visible
/// 2. Loads images progressively as user scrolls
/// 3. Prefetches next page when approaching the end
class MarketBannerSliver extends StatefulWidget {
  /// How close to the end (0.0-1.0) before triggering next page fetch
  final double prefetchThreshold;

  /// Minimum height for the placeholder when not yet loaded
  final double placeholderHeight;

  const MarketBannerSliver({
    Key? key,
    this.prefetchThreshold = 0.8,
    this.placeholderHeight = 200,
  }) : super(key: key);

  @override
  _MarketBannerSliverState createState() => _MarketBannerSliverState();
}

class _MarketBannerSliverState extends State<MarketBannerSliver>
    with AutomaticKeepAliveClientMixin<MarketBannerSliver> {
  // ============ State ============
  List<MarketBannerItem> _banners = [];
  bool _hasBeenVisible = false;
  bool _isProcessingBanners = false;

  // For viewport-based image lazy loading
  final Set<int> _visibleIndices = {};
  final Set<String> _prefetchedUrls = {};

  // Debounce for prefetch triggers
  Timer? _prefetchDebouncer;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _prefetchDebouncer?.cancel();
    super.dispose();
  }

  // ============ Banner Processing ============

  Future<void> _processBanners(List<dynamic> docs) async {
    if (_isProcessingBanners) return;
    _isProcessingBanners = true;

    try {
      final items = <MarketBannerItem>[];

      for (var doc in docs) {
        final data = doc.data()! as Map<String, dynamic>;
        final url = data['imageUrl'] as String? ?? '';
        if (url.isEmpty) continue;

        items.add(MarketBannerItem(
          id: doc.id,
          url: url,
          linkType: data['linkType'] as String?,
          linkId: data['linkedShopId'] ?? data['linkedProductId'],
        ));
      }

      if (!mounted) return;

      setState(() => _banners = items);

      // Prefetch only first 2 images for smooth initial render
      _prefetchInitialImages();
    } finally {
      _isProcessingBanners = false;
    }
  }

  void _prefetchInitialImages() {
    if (!mounted || _banners.isEmpty) return;

    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final screenWidth = MediaQuery.of(context).size.width;
    final cacheWidth = (screenWidth * devicePixelRatio).toInt();

    // Only prefetch first 2 images
    for (int i = 0; i < _banners.length && i < 2; i++) {
      _prefetchImage(_banners[i].url, cacheWidth);
    }
  }

  void _prefetchImage(String url, int cacheWidth) {
    if (_prefetchedUrls.contains(url)) return;
    _prefetchedUrls.add(url);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final provider = CachedNetworkImageProvider(
          url,
          maxWidth: cacheWidth,
        );
        precacheImage(provider, context).catchError((_) {
          // Silently handle prefetch errors
          _prefetchedUrls.remove(url);
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Image prefetch error: $e');
        }
      }
    });
  }

  // ============ Visibility & Lazy Loading ============

  /// Called when this sliver becomes visible in the viewport
  void _onBecameVisible(MarketBannerProvider provider) {
    if (_hasBeenVisible) return;

    if (kDebugMode) {
      debugPrint('📸 MarketBannerSliver became visible - initiating fetch');
    }

    // Set visibility flag and trigger rebuild
    _hasBeenVisible = true;

    // If provider already has docs (e.g., returning to screen), process them
    if (provider.docs.isNotEmpty && _banners.isEmpty) {
      _processBanners(provider.docs);
    } else if (provider.docs.isEmpty && !provider.isLoading && provider.hasMore) {
      // Only fetch if we haven't loaded anything yet
      provider.fetchNextPage(context: context);
    }

    // Trigger rebuild to show content (must be after setting _hasBeenVisible)
    if (mounted) {
      setState(() {});
    }
  }

  /// Handles scroll position to trigger pagination
  void _handleScrollForPagination(
      int visibleIndex, MarketBannerProvider provider) {
    if (_banners.isEmpty) return;

    // Calculate scroll progress
    final progress = visibleIndex / _banners.length;

    // If we're past the threshold and have more items, fetch next page
    if (progress >= widget.prefetchThreshold &&
        provider.hasMore &&
        !provider.isLoading) {
      // Debounce the fetch call
      _prefetchDebouncer?.cancel();
      _prefetchDebouncer = Timer(const Duration(milliseconds: 200), () {
        if (mounted && !provider.isLoading && provider.hasMore) {
          if (kDebugMode) {
            debugPrint(
                '📸 Prefetching next page at ${(progress * 100).toInt()}%');
          }
          provider.fetchNextPage(context: context);
        }
      });
    }
  }

  /// Prefetch images for items about to come into view
  void _prefetchNearbyImages(int centerIndex) {
    if (!mounted || _banners.isEmpty) return;

    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final screenWidth = MediaQuery.of(context).size.width;
    final cacheWidth = (screenWidth * devicePixelRatio).toInt();

    // Prefetch 2 items ahead
    for (int i = centerIndex;
        i < _banners.length && i <= centerIndex + 2;
        i++) {
      _prefetchImage(_banners[i].url, cacheWidth);
    }
  }

  // ============ Interaction Handlers ============

  void _handleBannerTap(MarketBannerItem item) {
    // Track click (non-blocking)
    AdAnalyticsService.trackAdClick(
      adId: item.id,
      adType: 'marketBanner',
      linkedType: item.linkType,
      linkedId: item.linkId,
    );

    if (item.linkType != null && item.linkId != null) {
      try {
        switch (item.linkType) {
          case 'shop':
            context.push('/shop_detail/${item.linkId}');
            break;
          case 'product':
          case 'shop_product':
            context.push('/product/${item.linkId}');
            break;
          default:
            context.push('/product/${item.linkId}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Navigation error: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Navigation error: $e')),
          );
        }
      }
    }
  }

  // ============ Build Methods ============

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer<MarketBannerProvider>(
      builder: (context, provider, _) {
        // ═══════════════════════════════════════════════════════════
        // SYNC BANNER PROCESSING: Process docs when available
        // This handles the case when returning to the screen with existing data
        // ═══════════════════════════════════════════════════════════
        if (provider.docs.isNotEmpty && _banners.length != provider.docs.length) {
          // Schedule processing for next frame to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _banners.length != provider.docs.length) {
              _processBanners(provider.docs);
            }
          });
        }

        // ═══════════════════════════════════════════════════════════
        // PRIORITY: If we already have banners processed, show them
        // This handles returning to the screen with existing data
        // ═══════════════════════════════════════════════════════════
        if (_banners.isNotEmpty) {
          // Mark as visible since we have content to show
          if (!_hasBeenVisible) {
            _hasBeenVisible = true;
          }
          return _buildBannerList(provider);
        }

        // ═══════════════════════════════════════════════════════════
        // LAZY LOADING: Use a visibility wrapper for initial load
        // Only applies when we don't have banners yet
        // ═══════════════════════════════════════════════════════════
        if (!_hasBeenVisible) {
          return SliverLayoutBuilder(
            builder: (context, constraints) {
              // Check if this sliver has any visible portion
              // remainingPaintExtent > 0 means we're in the viewport
              if (constraints.remainingPaintExtent > 0) {
                // We're visible! Trigger visibility handling
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _onBecameVisible(provider);
                  }
                });
              }

              // Show placeholder while waiting to become visible or load
              return _buildPlaceholder(provider);
            },
          );
        }

        // Error state
        if (provider.error != null && provider.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: _buildErrorWidget(provider),
          );
        }

        // Loading state (visible but no data yet)
        // Provider might have docs that are being processed
        return _buildLoadingShimmer();
      },
    );
  }

  Widget _buildPlaceholder(MarketBannerProvider provider) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;

    // If not visible yet, show a minimal placeholder
    // This prevents unnecessary work until user scrolls here
    return SliverToBoxAdapter(
      child: Container(
        height: widget.placeholderHeight,
        color: baseColor.withOpacity(0.3),
        child: provider.isLoading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildErrorWidget(MarketBannerProvider provider) {
    return Container(
      height: widget.placeholderHeight,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.grey[400], size: 32),
          const SizedBox(height: 8),
          Text(
            'Failed to load banners',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _hasBeenVisible = false; // Reset to allow retry
              provider.fetchNextPage(context: context);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return SliverToBoxAdapter(
      child: SizedBox(
        height: widget.placeholderHeight,
        child: Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            height: 150,
            width: double.infinity,
            color: baseColor,
          ),
        ),
      ),
    );
  }

  Widget _buildBannerList(MarketBannerProvider provider) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final screenWidth = MediaQuery.of(context).size.width;
    final cacheWidth = (screenWidth * devicePixelRatio).toInt();

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade200;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Handle loading indicator at the end
          if (index >= _banners.length) {
            if (provider.hasMore) {
              // Trigger next page fetch
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !provider.isLoading) {
                  provider.fetchNextPage(context: context);
                }
              });
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final item = _banners[index];

          // Trigger prefetch for nearby images
          _prefetchNearbyImages(index);

          // Check for pagination trigger
          _handleScrollForPagination(index, provider);

          // ═══════════════════════════════════════════════════════════
          // LAZY IMAGE LOADING: CachedNetworkImage handles this, but
          // we optimize with memCacheWidth and avoid unnecessary work
          // ═══════════════════════════════════════════════════════════
          return GestureDetector(
            onTap: () => _handleBannerTap(item),
            child: CachedNetworkImage(
              imageUrl: item.url,
              width: double.infinity,
              fit: BoxFit.fitWidth,

              // Placeholder while loading
              placeholder: (_, __) => Container(
                height: 150,
                width: double.infinity,
                color: placeholderColor,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),

              // Error state
              errorWidget: (_, __, ___) => Container(
                height: 150,
                width: double.infinity,
                color: placeholderColor,
                child: const Center(child: Icon(Icons.broken_image, size: 32)),
              ),

              // Performance optimizations
              fadeInDuration: const Duration(milliseconds: 150),
              fadeOutDuration: Duration.zero,
              memCacheWidth: cacheWidth, // Downscale for memory efficiency
              useOldImageOnUrlChange: true,
            ),
          );
        },

        childCount: _banners.length + (provider.hasMore ? 1 : 0),

        // Performance: Let SliverList handle lifecycle
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        addSemanticIndexes: false,
      ),
    );
  }
}
