// lib/widgets/cloudinary_image.dart
// ===================================================================
// CloudinaryImage — the single image component for all product &
// banner rendering in the app.
//
// Responsibilities:
//   1. Build the primary (Cloudinary CDN) URL via CloudinaryUrl helpers.
//   2. Automatically fall back to the raw Firebase Storage URL if the
//      CDN request errors out (Cloudinary down, account deleted, 5xx,
//      DNS failure, etc.) — per image, no manual flip required.
//   3. Honor the global kill switch (CloudinaryUrl.enabled = false)
//      without double-fetching: in that mode the primary URL is
//      already the Firebase Storage URL and fallback is skipped.
//
// Do not render product/banner images with CachedNetworkImage directly
// anywhere else in the app. Go through this widget so the fallback
// behavior lives in one place.
// ===================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/cloudinary_url_builder.dart';

typedef CloudinaryPlaceholderBuilder = Widget Function(BuildContext context);
typedef CloudinaryErrorBuilder = Widget Function(BuildContext context);

class CloudinaryImage extends StatelessWidget {
  /// Primary URL to try first. Normally a Cloudinary CDN URL.
  final String primary;

  /// Firebase Storage fallback URL to try if [primary] errors.
  /// Null when no recovery is possible (kill switch path, opaque URL).
  final String? fallback;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double? borderRadius;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final bool useOldImageOnUrlChange;

  /// Decode-size cap applied to the **primary** CDN request. Usually
  /// unnecessary because Cloudinary already serves correctly-sized bytes,
  /// but useful for disk-cache scoping in grid lists.
  final int? primaryMaxDiskCacheWidth;

  /// Decode-size cap applied to the **fallback** request. The raw
  /// Firebase Storage original can be very large, so callers should set
  /// this to prevent memory spikes when CDN is unreachable.
  final int? fallbackMemCacheWidth;
  final int? fallbackMemCacheHeight;

  /// Optional custom placeholder. Defaults to a grey box.
  final CloudinaryPlaceholderBuilder? placeholderBuilder;

  /// Optional custom error widget (shown only when BOTH primary and
  /// fallback have failed, or fallback is null and primary failed).
  final CloudinaryErrorBuilder? errorBuilder;

  const CloudinaryImage._({
    Key? key,
    required this.primary,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.filterQuality = FilterQuality.medium,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
    this.useOldImageOnUrlChange = true,
    this.primaryMaxDiskCacheWidth,
    this.fallbackMemCacheWidth,
    this.fallbackMemCacheHeight,
    this.placeholderBuilder,
    this.errorBuilder,
  }) : super(key: key);

  // ─── Factory constructors ────────────────────────────────────────

  /// Product image. [source] may be a Firebase Storage path
  /// (e.g. "products/uid/main/x.jpg") OR a legacy full URL.
  ///
  /// [size] selects a standard width bucket (200/400/800/1600) to
  /// maximize Cloudinary cache hit ratio.
  factory CloudinaryImage.product({
    Key? key,
    required String source,
    required ProductImageSize size,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    double? borderRadius,
    FilterQuality filterQuality = FilterQuality.medium,
    Duration fadeInDuration = Duration.zero,
    Duration fadeOutDuration = Duration.zero,
    bool useOldImageOnUrlChange = true,
    int? fallbackMemCacheWidth,
    int? fallbackMemCacheHeight,
    CloudinaryPlaceholderBuilder? placeholderBuilder,
    CloudinaryErrorBuilder? errorBuilder,
  }) {
    final resolved = CloudinaryUrl.resolveProduct(source, size: size);
    return CloudinaryImage._(
      key: key,
      primary: resolved.primary,
      fallback: resolved.fallback,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      filterQuality: filterQuality,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      primaryMaxDiskCacheWidth: CloudinaryUrl.widthFor(size),
      fallbackMemCacheWidth:
          fallbackMemCacheWidth ?? CloudinaryUrl.widthFor(size),
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  /// Banner-style image from an arbitrary full URL at an explicit CDN
  /// width. Falls back to the raw URL on CDN error.
  factory CloudinaryImage.fromUrl({
    Key? key,
    required String url,
    required int cdnWidth,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    double? borderRadius,
    FilterQuality filterQuality = FilterQuality.medium,
    Duration fadeInDuration = Duration.zero,
    Duration fadeOutDuration = Duration.zero,
    bool useOldImageOnUrlChange = true,
    int? fallbackMemCacheWidth,
    int? fallbackMemCacheHeight,
    CloudinaryPlaceholderBuilder? placeholderBuilder,
    CloudinaryErrorBuilder? errorBuilder,
  }) {
    final resolved = CloudinaryUrl.resolveUrl(url, width: cdnWidth);
    return CloudinaryImage._(
      key: key,
      primary: resolved.primary,
      fallback: resolved.fallback,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      filterQuality: filterQuality,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      primaryMaxDiskCacheWidth: cdnWidth,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? cdnWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  /// Use when the caller already holds a pre-built URL (e.g. a cached
  /// list of Cloudinary URLs built elsewhere). The widget auto-detects
  /// whether a Firebase Storage fallback can be derived from the URL.
  factory CloudinaryImage.fromResolvedUrl({
    Key? key,
    required String url,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    double? borderRadius,
    FilterQuality filterQuality = FilterQuality.medium,
    Duration fadeInDuration = Duration.zero,
    Duration fadeOutDuration = Duration.zero,
    bool useOldImageOnUrlChange = true,
    int? fallbackMemCacheWidth,
    int? fallbackMemCacheHeight,
    CloudinaryPlaceholderBuilder? placeholderBuilder,
    CloudinaryErrorBuilder? errorBuilder,
  }) {
    return CloudinaryImage._(
      key: key,
      primary: url,
      fallback: CloudinaryUrl.fallbackFromCloudinaryUrl(url),
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      filterQuality: filterQuality,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      fallbackMemCacheWidth: fallbackMemCacheWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  /// Ad/banner image. [source] may be a Firebase Storage path
  /// (e.g. "ad_submissions/shopId/x.jpg") OR a legacy full URL.
  factory CloudinaryImage.banner({
    Key? key,
    required String source,
    required int cdnWidth,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    double? borderRadius,
    FilterQuality filterQuality = FilterQuality.medium,
    Duration fadeInDuration = Duration.zero,
    Duration fadeOutDuration = Duration.zero,
    bool useOldImageOnUrlChange = true,
    int? fallbackMemCacheWidth,
    int? fallbackMemCacheHeight,
    CloudinaryPlaceholderBuilder? placeholderBuilder,
    CloudinaryErrorBuilder? errorBuilder,
  }) {
    final resolved = CloudinaryUrl.resolveBanner(source, width: cdnWidth);
    return CloudinaryImage._(
      key: key,
      primary: resolved.primary,
      fallback: resolved.fallback,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      filterQuality: filterQuality,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      primaryMaxDiskCacheWidth: cdnWidth,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? cdnWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget placeholder(BuildContext ctx, String _) =>
        placeholderBuilder?.call(ctx) ?? _defaultPlaceholder(ctx);
    Widget error(BuildContext ctx) =>
        errorBuilder?.call(ctx) ?? _defaultError(ctx);

    Widget image = CachedNetworkImage(
      imageUrl: primary,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      filterQuality: filterQuality,
      maxWidthDiskCache: primaryMaxDiskCacheWidth,
      placeholder: placeholder,
      errorWidget: (ctx, _, __) {
        if (fallback == null || fallback == primary) return error(ctx);
        return CachedNetworkImage(
          imageUrl: fallback!,
          width: width,
          height: height,
          fit: fit,
          fadeInDuration: fadeInDuration,
          fadeOutDuration: fadeOutDuration,
          useOldImageOnUrlChange: useOldImageOnUrlChange,
          filterQuality: filterQuality,
          memCacheWidth: fallbackMemCacheWidth,
          memCacheHeight: fallbackMemCacheHeight,
          placeholder: placeholder,
          errorWidget: (ctx2, _, __) => error(ctx2),
        );
      },
    );

    if (borderRadius != null && borderRadius! > 0) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius!),
        child: image,
      );
    }
    return image;
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
    );
  }

  Widget _defaultError(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey[500],
        size: ((width ?? height ?? 100) * 0.3).clamp(16, 48),
      ),
    );
  }
}
