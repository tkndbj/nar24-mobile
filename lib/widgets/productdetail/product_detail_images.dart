// lib/widgets/productdetail/product_detail_images.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_detail_provider.dart';
import '../../models/product.dart';
import '../../utils/cloudinary_url_builder.dart';
import '../cloudinary_image.dart';
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

    // Fallback decode cap — only applies when the CDN fails and we fall
    // back to the raw Firebase Storage original.
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final fallbackCacheWidth = (screenWidth * devicePixelRatio * 1.5).toInt();
    final fallbackCacheHeight =
        (screenHeight * 0.70 * devicePixelRatio * 1.5).toInt();

    String sourceAt(int index) =>
        hasPaths ? storagePaths[index] : legacyUrls[index];

    return Stack(
      children: [
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
                  final isTablet = screenWidth > 600;

                  final imageWidget = CloudinaryImage.product(
                    source: sourceAt(index),
                    size: ProductImageSize.detail,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    fallbackMemCacheWidth: fallbackCacheWidth,
                    fallbackMemCacheHeight: fallbackCacheHeight,
                    placeholderBuilder: (_) => Container(
                      color: backgroundColor,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorBuilder: (_) => Container(
                      color: backgroundColor,
                      child: const Icon(
                        Icons.image_not_supported,
                        size: 100,
                        color: Colors.grey,
                      ),
                    ),
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
