// lib/widgets/cloudinary_image.dart
// ===================================================================
// CloudinaryImage — single image component for product & banner.
//
// Render primary (CDN). If it errors, swap to the Firebase Storage
// fallback once (widget-local state — no global blacklist, no cache
// eviction). Flutter re-decodes naturally on the next build once
// memory pressure eases, so transient failures self-heal.
// All requests share AppImageCacheManager so the disk cache and
// in-flight dedup queue are unified.
// ===================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/cloudinary_url_builder.dart';
import '../utils/app_image_cache_manager.dart';

typedef CloudinaryPlaceholderBuilder = Widget Function(BuildContext context);
typedef CloudinaryErrorBuilder = Widget Function(BuildContext context);

class CloudinaryImage extends StatefulWidget {
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

  /// Decode-size cap for the primary CDN image. Caps the decoded bitmap
  /// in Flutter's ImageCache so the codec doesn't corrupt frames under
  /// memory pressure. Safe because each CDN width has a unique URL (no
  /// cache-key collisions between size variants).
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Decode-size cap for the fallback. The raw Firebase Storage original
  /// can be huge, so callers should set this to prevent memory spikes
  /// when CDN is unreachable.
  final int? fallbackMemCacheWidth;
  final int? fallbackMemCacheHeight;

  final CloudinaryPlaceholderBuilder? placeholderBuilder;
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
    this.memCacheWidth,
    this.memCacheHeight,
    this.fallbackMemCacheWidth,
    this.fallbackMemCacheHeight,
    this.placeholderBuilder,
    this.errorBuilder,
  }) : super(key: key);

  // ─── Factory constructors ────────────────────────────────────────

  /// Product image. [source] may be a Firebase Storage path
  /// (e.g. "products/uid/main/x.jpg") OR a legacy full URL.
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
    final cdnW = CloudinaryUrl.widthFor(size);
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
      memCacheWidth: cdnW,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? cdnW,
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
      memCacheWidth: cdnWidth,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? cdnWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  /// Use when the caller already holds a pre-built URL. The widget
  /// auto-detects whether a Firebase Storage fallback can be derived.
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
    int? memCacheWidth,
    int? memCacheHeight,
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
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? memCacheWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight ?? memCacheHeight,
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
      memCacheWidth: cdnWidth,
      fallbackMemCacheWidth: fallbackMemCacheWidth ?? cdnWidth,
      fallbackMemCacheHeight: fallbackMemCacheHeight,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  @override
  State<CloudinaryImage> createState() => _CloudinaryImageState();
}

class _CloudinaryImageState extends State<CloudinaryImage> {
  // True once we've swapped to the fallback for this widget instance.
  // Prevents infinite fallback loops if the fallback also errors.
  bool _onFallback = false;

  @override
  void didUpdateWidget(CloudinaryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primary != widget.primary ||
        oldWidget.fallback != widget.fallback) {
      _onFallback = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget placeholder(BuildContext ctx, String _) =>
        widget.placeholderBuilder?.call(ctx) ?? _defaultPlaceholder(ctx);
    Widget errorW(BuildContext ctx) =>
        widget.errorBuilder?.call(ctx) ?? _defaultError(ctx);

    final canUseFallback =
        widget.fallback != null && widget.fallback != widget.primary;
    final url = (_onFallback && canUseFallback) ? widget.fallback! : widget.primary;
    final memW = (_onFallback && canUseFallback)
        ? widget.fallbackMemCacheWidth
        : widget.memCacheWidth;
    final memH = (_onFallback && canUseFallback)
        ? widget.fallbackMemCacheHeight
        : widget.memCacheHeight;

    Widget image = CachedNetworkImage(
      // Key by URL so a primary→fallback swap spawns a fresh element
      // rather than reusing the failed one.
      key: ValueKey(url),
      cacheManager: AppImageCacheManager(),
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
      useOldImageOnUrlChange: widget.useOldImageOnUrlChange,
      filterQuality: widget.filterQuality,
      memCacheWidth: memW,
      memCacheHeight: memH,
      placeholder: placeholder,
      errorWidget: (ctx, _, __) {
        if (!_onFallback && canUseFallback) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _onFallback = true);
          });
          return placeholder(ctx, '');
        }
        return errorW(ctx);
      },
    );

    if (widget.borderRadius != null && widget.borderRadius! > 0) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius!),
        child: image,
      );
    }
    return image;
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      height: widget.height,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
    );
  }

  Widget _defaultError(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      height: widget.height,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey[500],
        size: ((widget.width ?? widget.height ?? 100) * 0.3).clamp(16, 48),
      ),
    );
  }
}
