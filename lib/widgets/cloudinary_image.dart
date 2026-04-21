// lib/widgets/cloudinary_image.dart
// ===================================================================
// CloudinaryImage — the single image component for product & banner
// rendering. Corruption-resistant, dedup-friendly, fallback-aware.
//
// Pipeline per image:
//   1. Build primary (Cloudinary CDN) URL via CloudinaryUrl.
//   2. Try primary against the shared AppImageCacheManager.
//   3. On error OR if the primary is in the session's known-bad set:
//        a. Evict the primary from BOTH disk and in-memory ImageCache
//           so the rotten entry can't resurface next view.
//        b. Record the primary as known-bad for the rest of the session
//           (avoids paying the CDN roundtrip on every redisplay of an
//           image Cloudinary can't serve).
//        c. Swap the active URL to the Firebase Storage fallback.
//   4. If the fallback also errors, evict it too and render the error
//      widget. No further retries — the image is unrecoverable.
//
// Why stateful (not nested CachedNetworkImage like before):
//   • Nested widgets in errorWidget rebuild an entire subtree on every
//     error event, losing placeholder state and re-downloading.
//   • A setState-driven URL swap reuses the same CachedNetworkImage
//     element — fewer allocations, no double-download if the error
//     callback fires twice, and we control eviction timing.
//
// Why a session-scoped known-bad set (not persistent):
//   • Persistent negative cache would lock out a URL even after the
//     Cloudinary auto-upload mapping recovers. A session reset (hours
//     at most) is enough to re-check.
//
// Why ONE CacheManager across all widgets:
//   • flutter_cache_manager deduplicates concurrent requests for the
//     same URL only when they share the manager instance. Product lists
//     often request identical thumbnails (color variants resolving to
//     the same image) — shared manager = one fetch, not N.
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
  /// Session-scoped set of primary URLs that have failed at least once.
  /// Cleared on app restart — Cloudinary may have recovered by then.
  static final Set<String> _knownBadPrimaries = <String>{};

  /// Which URL is currently being rendered.
  late String _activeUrl;
  late int? _activeMemCacheWidth;
  late int? _activeMemCacheHeight;

  /// True once we've swapped to the fallback (either up-front because the
  /// primary was known-bad, or after a primary error). Prevents infinite
  /// fallback loops and signals the error path to render the final error
  /// widget instead of attempting another swap.
  bool _onFallback = false;

  /// Guards against scheduling the primary-error handler more than once
  /// while it's in flight. errorWidget fires repeatedly during rebuilds;
  /// we only want one eviction + one setState per failed URL.
  bool _primaryErrorHandled = false;
  bool _fallbackErrorHandled = false;

  @override
  void initState() {
    super.initState();
    _resetActiveUrl();
  }

  @override
  void didUpdateWidget(CloudinaryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primary != widget.primary ||
        oldWidget.fallback != widget.fallback) {
      _primaryErrorHandled = false;
      _fallbackErrorHandled = false;
      _resetActiveUrl();
    }
  }

  void _resetActiveUrl() {
    final primaryKnownBad = _knownBadPrimaries.contains(widget.primary);
    final canUseFallback =
        widget.fallback != null && widget.fallback != widget.primary;

    if (primaryKnownBad && canUseFallback) {
      _activeUrl = widget.fallback!;
      _activeMemCacheWidth = widget.fallbackMemCacheWidth;
      _activeMemCacheHeight = widget.fallbackMemCacheHeight;
      _onFallback = true;
    } else {
      _activeUrl = widget.primary;
      _activeMemCacheWidth = widget.memCacheWidth;
      _activeMemCacheHeight = widget.memCacheHeight;
      _onFallback = false;
    }
  }

  Future<void> _handlePrimaryError() async {
    if (_primaryErrorHandled) return;
    _primaryErrorHandled = true;

    _knownBadPrimaries.add(widget.primary);

    // Memory cache — evict the decoded image so a rebuild can't reuse it.
    await CachedNetworkImageProvider(
      widget.primary,
      cacheManager: AppImageCacheManager(),
    ).evict();
    // Disk cache — remove the file + index entry so next fetch downloads fresh.
    await AppImageCacheManager().evict(widget.primary);

    if (!mounted) return;

    final canUseFallback =
        widget.fallback != null && widget.fallback != widget.primary;
    if (!canUseFallback) {
      // No fallback available — stay on the failing primary so the error
      // widget renders. Flagging _onFallback prevents another eviction pass.
      setState(() {
        _onFallback = true;
      });
      return;
    }

    setState(() {
      _activeUrl = widget.fallback!;
      _activeMemCacheWidth = widget.fallbackMemCacheWidth;
      _activeMemCacheHeight = widget.fallbackMemCacheHeight;
      _onFallback = true;
    });
  }

  Future<void> _handleFallbackError(String failedUrl) async {
    if (_fallbackErrorHandled) return;
    _fallbackErrorHandled = true;
    // Purge the fallback too — corruption could live on either side.
    await CachedNetworkImageProvider(
      failedUrl,
      cacheManager: AppImageCacheManager(),
    ).evict();
    await AppImageCacheManager().evict(failedUrl);
  }

  @override
  Widget build(BuildContext context) {
    Widget placeholder(BuildContext ctx, String _) =>
        widget.placeholderBuilder?.call(ctx) ?? _defaultPlaceholder(ctx);
    Widget errorW(BuildContext ctx) =>
        widget.errorBuilder?.call(ctx) ?? _defaultError(ctx);

    Widget image = CachedNetworkImage(
      // Key by URL so state transitions primary→fallback force a fresh
      // CachedNetworkImage element instead of reusing the failed one.
      key: ValueKey(_activeUrl),
      cacheManager: AppImageCacheManager(),
      imageUrl: _activeUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
      useOldImageOnUrlChange: widget.useOldImageOnUrlChange,
      filterQuality: widget.filterQuality,
      memCacheWidth: _activeMemCacheWidth,
      memCacheHeight: _activeMemCacheHeight,
      placeholder: placeholder,
      errorWidget: (ctx, _, __) {
        if (_onFallback) {
          // Already on fallback — evict and render final error.
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _handleFallbackError(_activeUrl));
          return errorW(ctx);
        }
        // Primary failed — schedule eviction + swap. Show placeholder
        // during the transition so the user sees loading, not a flash of
        // the broken icon.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _handlePrimaryError());
        return placeholder(ctx, '');
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
