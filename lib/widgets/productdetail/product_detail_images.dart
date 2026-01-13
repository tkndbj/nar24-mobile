// lib/widgets/productdetail/product_detail_images.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/product_detail_provider.dart';
import '../../models/product.dart';
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

    if (product.imageUrls.isEmpty) {
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

    final imageCount = provider.currentImageUrls.length;
    final currentIndex = provider.currentImageIndex;

    // Calculate optimal cache dimensions for memory efficiency
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    // Cache at 2x screen resolution for sharp display while limiting memory
    // This prevents loading 4000x4000 images when display is only 1080x1920
    final cacheWidth = (screenWidth * devicePixelRatio * 1.5).toInt();
    final cacheHeight = (screenHeight * 0.70 * devicePixelRatio * 1.5).toInt();

    return Stack(
      children: [
        // Tappable, full‐screen PageView:
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(
                  imageUrls: provider.currentImageUrls,
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
                  final imageUrl = provider.currentImageUrls[index];

                  // Check if we're on a tablet/large screen
                  final isTablet = screenWidth > 600;

                  return Container(
                    color: backgroundColor,
                    child: Center(
                      child: isTablet
                          ? AspectRatio(
                              aspectRatio: 1.0, // Square aspect ratio on tablets
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: screenWidth * 0.8,
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.contain,
                                  memCacheWidth: cacheWidth,
                                  memCacheHeight: cacheHeight,
                                  maxWidthDiskCache: cacheWidth,
                                  maxHeightDiskCache: cacheHeight,
                                  placeholder: (_, __) => const Center(
                                      child: CircularProgressIndicator()),
                                  errorWidget: (_, __, ___) => Container(
                                    color: backgroundColor,
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      size: 100,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              memCacheWidth: cacheWidth,
                              memCacheHeight: cacheHeight,
                              maxWidthDiskCache: cacheWidth,
                              maxHeightDiskCache: cacheHeight,
                              placeholder: (_, __) => Container(
                                color: backgroundColor,
                                child: const Center(
                                    child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: backgroundColor,
                                child: const Icon(
                                  Icons.image_not_supported,
                                  size: 100,
                                  color: Colors.grey,
                                ),
                              ),
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