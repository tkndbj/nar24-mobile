// lib/widgets/productdetail/full_screen_image_viewer.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FullScreenImageViewer extends StatefulWidget {
  /// List of image URLs to display
  final List<String> imageUrls;

  /// Which image should be shown first (zero‐based)
  final int initialIndex;

  const FullScreenImageViewer({
    Key? key,
    required this.imageUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  _FullScreenImageViewerState createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Build a single thumbnail at position [thumbIndex].
  Widget _buildThumbnail(int thumbIndex, double pixelRatio) {
    final bool isSelected = thumbIndex == _currentIndex;
    final String url = widget.imageUrls[thumbIndex];

    // Thumbnail cache size: 72x72 display * devicePixelRatio for sharp rendering
    final thumbnailCacheSize = (72 * pixelRatio * 1.5).toInt();

    return GestureDetector(
      onTap: () {
        // Jump to that page when thumbnail is tapped
        _pageController.animateToPage(
          thumbIndex,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      },
      child: Container(
        width: 72,
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade700,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: thumbnailCacheSize,
            memCacheHeight: thumbnailCacheSize,
            maxWidthDiskCache: thumbnailCacheSize,
            maxHeightDiskCache: thumbnailCacheSize,
            placeholder: (_, __) => Container(color: Colors.grey.shade800),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey.shade800,
              child: const Icon(
                Icons.broken_image,
                color: Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalImages = widget.imageUrls.length;

    // Calculate optimal cache sizes for full-screen viewing
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;

    // Full screen images: cache at device resolution for perfect quality
    final fullScreenCacheWidth = (screenWidth * pixelRatio).toInt();
    final fullScreenCacheHeight = (screenHeight * pixelRatio).toInt();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          "${_currentIndex + 1}/$totalImages",
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (newIndex) {
                setState(() {
                  _currentIndex = newIndex;
                });
              },
              itemBuilder: (context, pageIndex) {
                final imageUrl = widget.imageUrls[pageIndex];
                return CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: fullScreenCacheWidth,
                  memCacheHeight: fullScreenCacheHeight,
                  maxWidthDiskCache: fullScreenCacheWidth,
                  maxHeightDiskCache: fullScreenCacheHeight,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white54, size: 60)),
                );
              },
            ),
          ),

          // Thumbnails row:
          SafeArea(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 8),
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.imageUrls.length,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (context, thumbIndex) {
                  return _buildThumbnail(thumbIndex, pixelRatio);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
