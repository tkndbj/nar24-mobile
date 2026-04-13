// lib/utils/cloudinary_url_builder.dart
// ===================================================================
// Cloudinary URL Builder — Auto Upload Architecture
//
// Source of truth: Firebase Storage (you own the files)
// CDN/transforms:  Cloudinary Auto Upload (fetches + caches from bucket)
//
// All widgets go through this utility. If Cloudinary is down, [enabled]
// is false (via Remote Config kill switch) and the app serves originals
// directly from Firebase Storage — or the CloudinaryImage widget falls
// back to Firebase on per-image errors automatically.
//
// Usage:
//   CloudinaryUrl.product('products/uid/main/shoe.jpg', size: ProductImageSize.card)
//   → https://res.cloudinary.com/cloud/image/upload/c_limit,w_400,f_auto,q_auto/fb/products/uid/main/shoe.jpg
//
// Fallback (enabled = false, or per-image error recovery):
//   → https://storage.googleapis.com/bucket/products/uid/main/shoe.jpg
// ===================================================================

enum ProductImageSize {
  /// 200w — Thumbnails, search results, cart line items
  thumbnail,

  /// 400w — Shop cards, grid product cards (2-col), banners
  card,

  /// 800w — Product detail hero, full-width banners
  detail,

  /// 1600w — Zoom/fullscreen, pinch-to-zoom
  zoom,
}

/// Resolved image URLs: the primary (CDN) URL to try first, plus an
/// optional Firebase Storage fallback to try on error.
///
/// When [fallback] is null, there is no recovery URL — either the caller
/// is already on the fallback path (kill switch), or the source URL was
/// opaque (not a Firebase URL we can rebuild).
class ResolvedImage {
  final String primary;
  final String? fallback;
  const ResolvedImage(this.primary, [this.fallback]);
}

class CloudinaryUrl {
  CloudinaryUrl._();

  // ── Configuration (set once in main.dart) ─────────────────────────

  static String cloudName = '';
  static String storageBucket = '';

  /// Must match Cloudinary dashboard: Settings → Upload → Auto Upload Mapping → Folder
  static String autoUploadFolder = 'fb';

  /// Kill switch. Set false → bypass Cloudinary, serve from Firebase Storage.
  static bool enabled = true;

  static void init({
    required String cloudName,
    required String storageBucket,
    String autoUploadFolder = 'fb',
    bool enabled = true,
  }) {
    CloudinaryUrl.cloudName = cloudName;
    CloudinaryUrl.storageBucket = storageBucket;
    CloudinaryUrl.autoUploadFolder = autoUploadFolder;
    CloudinaryUrl.enabled = enabled;
  }

  // ── Size map ──────────────────────────────────────────────────────

  static const Map<ProductImageSize, int> _sizeWidths = {
    ProductImageSize.thumbnail: 200,
    ProductImageSize.card: 400,
    ProductImageSize.detail: 800,
    ProductImageSize.zoom: 1600,
  };

  static int widthFor(ProductImageSize size) => _sizeWidths[size]!;

  // ── Public URL builders ───────────────────────────────────────────

  /// Optimized product image at a standard size.
  /// [storagePath] — Firebase Storage path, e.g. "products/uid/main/shoe.jpg"
  static String product(String storagePath, {required ProductImageSize size}) {
    if (!enabled || cloudName.isEmpty) return firebaseStorageUrl(storagePath);
    final w = _sizeWidths[size]!;
    return 'https://res.cloudinary.com/$cloudName'
        '/image/upload'
        '/c_limit,w_$w,f_auto,q_auto'
        '/$autoUploadFolder/$storagePath';
  }

  /// Product video (CDN delivery, no resize).
  static String video(String storagePath) {
    if (!enabled || cloudName.isEmpty) return firebaseStorageUrl(storagePath);
    return 'https://res.cloudinary.com/$cloudName'
        '/video/upload/q_auto'
        '/$autoUploadFolder/$storagePath';
  }

  /// Video poster thumbnail from first frame.
  static String videoThumbnail(String storagePath, {int width = 400}) {
    if (!enabled || cloudName.isEmpty) return firebaseStorageUrl(storagePath);
    return 'https://res.cloudinary.com/$cloudName'
        '/video/upload'
        '/c_limit,w_$width,f_auto,q_auto,so_0'
        '/$autoUploadFolder/$storagePath';
  }

  /// Custom size for one-off cases.
  static String custom(String storagePath,
      {required int width, int? height, String crop = 'limit'}) {
    if (!enabled || cloudName.isEmpty) return firebaseStorageUrl(storagePath);
    final h = height != null ? ',h_$height' : '';
    return 'https://res.cloudinary.com/$cloudName'
        '/image/upload/c_$crop,w_$width${h},f_auto,q_auto'
        '/$autoUploadFolder/$storagePath';
  }

  /// Raw Firebase Storage download URL for a storage path.
  /// Requires [storageBucket] to have public object-level read access.
  static String firebaseStorageUrl(String storagePath) {
    assert(
        storageBucket.isNotEmpty, 'CloudinaryUrl.init() must be called first');
    return 'https://storage.googleapis.com/$storageBucket/$storagePath';
  }

  // ── Resolvers (primary + fallback pair) ───────────────────────────

  /// Resolve a product image source (storage path OR legacy full URL) to
  /// a primary CDN URL + Firebase Storage fallback pair.
  ///
  /// Kill switch path: primary routes straight to Firebase, fallback=null
  /// (no wasted second attempt).
  static ResolvedImage resolveProduct(String source,
      {required ProductImageSize size}) {
    if (source.isEmpty) return const ResolvedImage('');

    // Kill switch — skip CDN entirely.
    if (!enabled || cloudName.isEmpty) {
      if (isStoragePath(source)) {
        return ResolvedImage(firebaseStorageUrl(source));
      }
      return ResolvedImage(source);
    }

    // New-style: storage path.
    if (isStoragePath(source)) {
      return ResolvedImage(
        product(source, size: size),
        firebaseStorageUrl(source),
      );
    }

    // Legacy full URL — try to extract a path so we can CDN-optimize it.
    final path = extractPathFromUrl(source);
    if (path != null) {
      return ResolvedImage(
        custom(path, width: _sizeWidths[size]!),
        source,
      );
    }

    // Unknown/opaque URL — pass through, no fallback.
    return ResolvedImage(source);
  }

  /// Resolve a banner-style image (arbitrary Firestore URL) at an
  /// explicit CDN width. Used for ad banners that store `imageUrl`.
  static ResolvedImage resolveUrl(String url, {required int width}) {
    if (url.isEmpty) return const ResolvedImage('');
    if (!enabled || cloudName.isEmpty) return ResolvedImage(url);

    final path = extractPathFromUrl(url);
    if (path != null) {
      return ResolvedImage(custom(path, width: width), url);
    }
    return ResolvedImage(url);
  }

  /// If [url] is a Cloudinary auto-upload URL built by this class,
  /// returns the Firebase Storage fallback URL. Otherwise null.
  ///
  /// Used when the caller only has a pre-built URL (e.g. a cached list
  /// of Cloudinary URLs) and wants a recovery path.
  static String? fallbackFromCloudinaryUrl(String url) {
    if (storageBucket.isEmpty) return null;
    final marker = '/$autoUploadFolder/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    final storagePath = url.substring(idx + marker.length);
    if (storagePath.isEmpty) return null;
    return firebaseStorageUrl(storagePath);
  }

  // ── Migration helpers ─────────────────────────────────────────────

  /// True if value is a storage path (not a full URL).
  static bool isStoragePath(String value) =>
      !value.startsWith('http://') && !value.startsWith('https://');

  /// Handles both legacy full URLs and new storage paths.
  /// Use during migration; remove once all docs store paths.
  static String productCompat(String urlOrPath,
      {required ProductImageSize size}) {
    if (isStoragePath(urlOrPath)) return product(urlOrPath, size: size);
    return urlOrPath;
  }

  /// Convert a full Firebase Storage URL into a Cloudinary-optimized URL.
  /// Used by banner widgets where Firestore docs store full download URLs.
  static String fromUrl(String url, {required int width}) {
    if (!enabled || cloudName.isEmpty) return url;
    final path = extractPathFromUrl(url);
    if (path == null) return url;
    return custom(path, width: width);
  }

  /// Extract storage path from a Firebase Storage download URL.
  /// "https://firebasestorage.../o/products%2Fuid%2Fmain%2Fshoe.jpg?alt=media&token=..."
  /// → "products/uid/main/shoe.jpg"
  /// Also handles "storage.googleapis.com/bucket/path" form.
  static String? extractPathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);

      // Firebase download URL: .../o/<encoded path>?alt=media&token=...
      if (uri.pathSegments.contains('o')) {
        final idx = uri.pathSegments.indexOf('o');
        if (idx + 1 < uri.pathSegments.length) {
          return Uri.decodeComponent(uri.pathSegments[idx + 1]);
        }
      }

      // storage.googleapis.com/<bucket>/<path...>
      if (uri.host == 'storage.googleapis.com' &&
          uri.pathSegments.length > 1) {
        return uri.pathSegments.sublist(1).join('/');
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
