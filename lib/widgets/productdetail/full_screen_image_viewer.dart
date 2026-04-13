// lib/widgets/productdetail/full_screen_image_viewer.dart

import 'package:flutter/material.dart';
import '../../utils/cloudinary_url_builder.dart';
import '../cloudinary_image.dart';

class FullScreenImageViewer extends StatefulWidget {
  /// Legacy full image URLs (Firebase Storage / already-built URLs).
  /// Used as the data source when [imageStoragePaths] is null.
  final List<String> imageUrls;

  /// Optional Firebase Storage paths for the images. When provided, the
  /// viewer serves optimized Cloudinary URLs (zoom size for the main view,
  /// thumbnail size for the strip). Fallback is handled automatically by
  /// CloudinaryImage.
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

  /// Returns the source string for index [index]: storage path if available,
  /// otherwise the legacy URL. CloudinaryImage.product resolves either form.
  String _sourceAt(int index) =>
      _hasPaths ? widget.imageStoragePaths![index] : widget.imageUrls[index];

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

    // Cap for raw-Firebase fallback only. CDN thumbnails are already 200w.
    final thumbnailCacheSize = (72 * pixelRatio * 1.5).toInt();

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
        child: CloudinaryImage.product(
          source: _sourceAt(thumbIndex),
          size: ProductImageSize.thumbnail,
          fit: BoxFit.cover,
          borderRadius: 4,
          fallbackMemCacheWidth: thumbnailCacheSize,
          fallbackMemCacheHeight: thumbnailCacheSize,
          placeholderBuilder: (_) => Container(color: Colors.grey.shade800),
          errorBuilder: (_) => Container(
            color: Colors.grey.shade800,
            child: const Icon(Icons.broken_image, color: Colors.white70),
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
                return InteractiveViewer(
                  transformationController: _transformControllers[pageIndex],
                  minScale: 1.0,
                  maxScale: 5.0,
                  onInteractionUpdate: (_) => _onInteractionUpdate(pageIndex),
                  onInteractionEnd: (_) => _onInteractionUpdate(pageIndex),
                  child: CloudinaryImage.product(
                    source: _sourceAt(pageIndex),
                    size: ProductImageSize.zoom,
                    fit: BoxFit.contain,
                    fallbackMemCacheWidth: fullScreenCacheWidth,
                    fallbackMemCacheHeight: fullScreenCacheHeight,
                    placeholderBuilder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_) => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white54, size: 60),
                    ),
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
