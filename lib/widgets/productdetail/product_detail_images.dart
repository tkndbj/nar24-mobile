// lib/widgets/productdetail/product_detail_images.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/product_detail_provider.dart';
import '../../models/product.dart';
import '../../utils/cloudinary_url_builder.dart';
import 'full_screen_image_viewer.dart';

class ProductDetailImages extends StatelessWidget {
  final Product product;
  final bool showPlayIcon;
  final VoidCallback onPlayIconTap;

  const ProductDetailImages({
    Key? key,
    required this.product,
    required this.showPlayIcon,
    required this.onPlayIconTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProductDetailProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode
        ? const Color.fromARGB(255, 33, 31, 49)
        : Colors.grey.shade200;

    // Prefer storage paths (new products) over legacy URLs.
    final storagePaths = provider.currentImageStoragePaths;
    final legacyUrls = provider.currentImageUrls;
    final hasPaths = storagePaths.isNotEmpty;
    final imageCount = hasPaths ? storagePaths.length : legacyUrls.length;

    if (imageCount == 0) {
      return Container(
        height: double.infinity,
        color: backgroundColor,
        child: const Icon(
          Icons.image_not_supported,
          size: 100,
          color: Colors.grey,
        ),
      );
    }

    final currentIndex = provider.currentImageIndex;

    // Fallback decode cap (only used if Cloudinary is unreachable and we
    // fall back to the raw Firebase Storage original).
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final fallbackCacheWidth = (screenWidth * devicePixelRatio * 1.5).toInt();
    final fallbackCacheHeight =
        (screenHeight * 0.70 * devicePixelRatio * 1.5).toInt();

    return Stack(
      children: [
        // Tappable, full‐screen PageView:
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(
                  imageUrls: legacyUrls,
                  imageStoragePaths: hasPaths ? storagePaths : null,
                  initialIndex: currentIndex,
                ),
              ),
            );
          },
          child: SizedBox.expand(
            child: Container(
              color: backgroundColor,
              child: PageView.builder(
                controller: PageController(initialPage: currentIndex),
                itemCount: imageCount,
                onPageChanged: provider.updateCurrentImageIndex,
                itemBuilder: (context, index) {
                  // Build render URL: CDN (detail size) if we have a storage
                  // path, otherwise the legacy URL as-is.
                  final String primaryUrl = hasPaths
                      ? CloudinaryUrl.product(
                          storagePaths[index],
                          size: ProductImageSize.detail,
                        )
                      : legacyUrls[index];
                  // Fallback URL: raw Firebase Storage original (used only
                  // when the CDN request errors out).
                  final String? fallbackUrl = hasPaths
                      ? 'https://storage.googleapis.com/${CloudinaryUrl.storageBucket}/${storagePaths[index]}'
                      : null;

                  final isTablet = screenWidth > 600;

                  final imageWidget = _DetailImage(
                    primaryUrl: primaryUrl,
                    fallbackUrl: fallbackUrl,
                    backgroundColor: backgroundColor,
                    fallbackCacheWidth: fallbackCacheWidth,
                    fallbackCacheHeight: fallbackCacheHeight,
                  );

                  return Container(
                    color: backgroundColor,
                    child: Center(
                      child: isTablet
                          ? AspectRatio(
                              aspectRatio: 1.0,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: screenWidth * 0.8,
                                ),
                                child: imageWidget,
                              ),
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: imageWidget,
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Only show dots if more than one image ──
        if (imageCount > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imageCount, (dotIndex) {
                final isActive = dotIndex == currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 10 : 6,
                  height: isActive ? 10 : 6,
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
      ],
    );
  }
}

/// Renders a single detail image with CDN primary + Firebase Storage fallback.
/// - Primary: Cloudinary already serves detail-sized bytes, so decode is clean
///   (no memCacheWidth needed).
/// - Fallback: only used if the CDN request errors; capped with memCacheWidth
///   because the raw Firebase original can be much larger.
class _DetailImage extends StatelessWidget {
  final String primaryUrl;
  final String? fallbackUrl;
  final Color backgroundColor;
  final int fallbackCacheWidth;
  final int fallbackCacheHeight;

  const _DetailImage({
    Key? key,
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.backgroundColor,
    required this.fallbackCacheWidth,
    required this.fallbackCacheHeight,
  }) : super(key: key);

  Widget _placeholder() => Container(
        color: backgroundColor,
        child: const Center(child: CircularProgressIndicator()),
      );

  Widget _error() => Container(
        color: backgroundColor,
        child: const Icon(
          Icons.image_not_supported,
          size: 100,
          color: Colors.grey,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: primaryUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) {
        if (fallbackUrl == null) return _error();
        return CachedNetworkImage(
          imageUrl: fallbackUrl!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: fallbackCacheWidth,
          memCacheHeight: fallbackCacheHeight,
          maxWidthDiskCache: fallbackCacheWidth,
          maxHeightDiskCache: fallbackCacheHeight,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _error(),
        );
      },
    );
  }
}