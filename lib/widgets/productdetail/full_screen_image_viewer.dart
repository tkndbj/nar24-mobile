// lib/widgets/productdetail/full_screen_image_viewer.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/cloudinary_url_builder.dart';

class FullScreenImageViewer extends StatefulWidget {
  /// Legacy full image URLs (Firebase Storage / already-built URLs).
  /// Used as the data source when [imageStoragePaths] is null, and as the
  /// fallback target when a storage path is available but the CDN fails.
  final List<String> imageUrls;

  /// Optional Firebase Storage paths for the images. When provided, the
  /// viewer serves optimized Cloudinary URLs (zoom size for the main view,
  /// thumbnail size for the strip) and falls back to the raw Firebase URL
  /// if the CDN request errors out.
  final List<String>? imageStoragePaths;

  /// Which image should be shown first (zero‐based)
  final int initialIndex;

  const FullScreenImageViewer({
    Key? key,
    required this.imageUrls,
    this.imageStoragePaths,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  _FullScreenImageViewerState createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final List<TransformationController> _transformControllers = [];
  bool _isZoomed = false;

  bool get _hasPaths =>
      widget.imageStoragePaths != null &&
      widget.imageStoragePaths!.isNotEmpty;

  int get _imageCount =>
      _hasPaths ? widget.imageStoragePaths!.length : widget.imageUrls.length;

  /// Build the primary (CDN) URL for an image at [index] at the given size.
  String _primaryUrl(int index, ProductImageSize size) {
    if (_hasPaths) {
      return CloudinaryUrl.product(
        widget.imageStoragePaths![index],
        size: size,
      );
    }
    return widget.imageUrls[index];
  }

  /// Build the fallback (raw Firebase Storage) URL if available. Returns
  /// null when there's no separate fallback (legacy list case).
  String? _fallbackUrl(int index) {
    if (_hasPaths) {
      return 'https://storage.googleapis.com/${CloudinaryUrl.storageBucket}/${widget.imageStoragePaths![index]}';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    for (int i = 0; i < _imageCount; i++) {
      _transformControllers.add(TransformationController());
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onInteractionUpdate(int pageIndex) {
    final scale = _transformControllers[pageIndex].value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom(int pageIndex) {
    _transformControllers[pageIndex].value = Matrix4.identity();
    setState(() => _isZoomed = false);
  }

  /// Build a single thumbnail at position [thumbIndex].
  Widget _buildThumbnail(int thumbIndex, double pixelRatio) {
    final bool isSelected = thumbIndex == _currentIndex;
    final String primaryUrl =
        _primaryUrl(thumbIndex, ProductImageSize.thumbnail);
    final String? fallbackUrl = _fallbackUrl(thumbIndex);

    // Cap for raw-Firebase fallback only. CDN thumbnails are already 200w.
    final thumbnailCacheSize = (72 * pixelRatio * 1.5).toInt();

    Widget placeholder() => Container(color: Colors.grey.shade800);
    Widget errorWidget() => Container(
          color: Colors.grey.shade800,
          child: const Icon(Icons.broken_image, color: Colors.white70),
        );

    return GestureDetector(
      onTap: () {
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
            imageUrl: primaryUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder(),
            errorWidget: (_, __, ___) {
              if (fallbackUrl == null) return errorWidget();
              return CachedNetworkImage(
                imageUrl: fallbackUrl,
                fit: BoxFit.cover,
                memCacheWidth: thumbnailCacheSize,
                memCacheHeight: thumbnailCacheSize,
                maxWidthDiskCache: thumbnailCacheSize,
                maxHeightDiskCache: thumbnailCacheSize,
                placeholder: (_, __) => placeholder(),
                errorWidget: (_, __, ___) => errorWidget(),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalImages = _imageCount;

    // Fallback decode cap — only applies to the raw Firebase original when
    // the CDN (zoom = 1600w) request fails. CDN bytes decode at native size.
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
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
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: totalImages,
              onPageChanged: (newIndex) {
                _resetZoom(_currentIndex);
                setState(() {
                  _currentIndex = newIndex;
                });
              },
              itemBuilder: (context, pageIndex) {
                final String primaryUrl =
                    _primaryUrl(pageIndex, ProductImageSize.zoom);
                final String? fallbackUrl = _fallbackUrl(pageIndex);

                Widget placeholder() =>
                    const Center(child: CircularProgressIndicator());
                Widget errorWidget() => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white54, size: 60),
                    );

                return InteractiveViewer(
                  transformationController: _transformControllers[pageIndex],
                  minScale: 1.0,
                  maxScale: 5.0,
                  onInteractionUpdate: (_) => _onInteractionUpdate(pageIndex),
                  onInteractionEnd: (_) => _onInteractionUpdate(pageIndex),
                  child: CachedNetworkImage(
                    imageUrl: primaryUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => placeholder(),
                    errorWidget: (_, __, ___) {
                      if (fallbackUrl == null) return errorWidget();
                      return CachedNetworkImage(
                        imageUrl: fallbackUrl,
                        fit: BoxFit.contain,
                        memCacheWidth: fullScreenCacheWidth,
                        memCacheHeight: fullScreenCacheHeight,
                        maxWidthDiskCache: fullScreenCacheWidth,
                        maxHeightDiskCache: fullScreenCacheHeight,
                        placeholder: (_, __) => placeholder(),
                        errorWidget: (_, __, ___) => errorWidget(),
                      );
                    },
                  ),
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
                itemCount: totalImages,
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
