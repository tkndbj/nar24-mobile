// lib/widgets/cloudinary_image.dart
// ===================================================================
// CloudinaryImage — drop-in Image.network replacement.
//
// Handles both legacy Firebase URLs and new storage paths.
// Automatically picks the right Cloudinary size for the context.
// Falls back gracefully on error.
// ===================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/cloudinary_url_builder.dart';

class CloudinaryImage extends StatelessWidget {
  /// Firebase Storage path OR legacy full URL.
  final String source;

  /// Which standard size to request from Cloudinary.
  final ProductImageSize size;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CloudinaryImage({
    Key? key,
    required this.source,
    this.size = ProductImageSize.card,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final url = CloudinaryUrl.productCompat(source, size: size);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) =>
            placeholder ??
            Container(
              width: width,
              height: height,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
        errorWidget: (_, __, ___) =>
            errorWidget ??
            Container(
              width: width,
              height: height,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Colors.grey[500],
                size: (width ?? 100) * 0.3,
              ),
            ),
        maxWidthDiskCache: _cacheDim(size),
      ),
    );
  }

  static int _cacheDim(ProductImageSize size) => switch (size) {
        ProductImageSize.thumbnail => 200,
        ProductImageSize.card => 400,
        ProductImageSize.detail => 800,
        ProductImageSize.zoom => 1600,
      };
}
