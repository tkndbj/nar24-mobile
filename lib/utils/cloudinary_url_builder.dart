// lib/utils/cloudinary_url_builder.dart
// ===================================================================
// Cloudinary URL Builder — Auto Upload Architecture
//
// Source of truth: Firebase Storage (you own the files)
// CDN/transforms:  Cloudinary Auto Upload (fetches + caches from bucket)
//
// All widgets go through this utility. If Cloudinary is down, flip
// [enabled] to false and the app serves originals from Firebase Storage.
//
// Usage:
//   CloudinaryUrl.product('products/uid/main/shoe.jpg', size: ProductImageSize.card)
//   → https://res.cloudinary.com/cloud/image/upload/c_limit,w_400,f_auto,q_auto/fb/products/uid/main/shoe.jpg
//
// Fallback (enabled = false):
//   → https://firebasestorage.googleapis.com/v0/b/bucket/o/products%2F...?alt=media
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

  // ── Public API ────────────────────────────────────────────────────

  /// Optimized product image at a standard size.
  /// [storagePath] — Firebase Storage path, e.g. "products/uid/main/shoe.jpg"
  static String product(String storagePath, {required ProductImageSize size}) {
    if (!enabled || cloudName.isEmpty) return _firebaseUrl(storagePath);
    final w = _sizeWidths[size]!;
    return 'https://res.cloudinary.com/$cloudName'
        '/image/upload'
        '/c_limit,w_$w,f_auto,q_auto'
        '/$autoUploadFolder/$storagePath';
  }

  /// Product video (CDN delivery, no resize).
  static String video(String storagePath) {
    if (!enabled || cloudName.isEmpty) return _firebaseUrl(storagePath);
    return 'https://res.cloudinary.com/$cloudName'
        '/video/upload/q_auto'
        '/$autoUploadFolder/$storagePath';
  }

  /// Video poster thumbnail from first frame.
  static String videoThumbnail(String storagePath, {int width = 400}) {
    if (!enabled || cloudName.isEmpty) return _firebaseUrl(storagePath);
    return 'https://res.cloudinary.com/$cloudName'
        '/video/upload'
        '/c_limit,w_$width,f_auto,q_auto,so_0'
        '/$autoUploadFolder/$storagePath';
  }

  /// Custom size for one-off cases.
  static String custom(String storagePath,
      {required int width, int? height, String crop = 'limit'}) {
    if (!enabled || cloudName.isEmpty) return _firebaseUrl(storagePath);
    final h = height != null ? ',h_$height' : '';
    return 'https://res.cloudinary.com/$cloudName'
        '/image/upload/c_$crop,w_$width${h},f_auto,q_auto'
        '/$autoUploadFolder/$storagePath';
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
    return urlOrPath; // Legacy URL — return as-is
  }

  /// Convert a full Firebase Storage URL into a Cloudinary-optimized URL.
  /// Used by banner widgets where Firestore docs store full download URLs.
  ///
  /// Returns the original URL unchanged if:
  ///  - Cloudinary is disabled
  ///  - The URL isn't a Firebase Storage URL (can't extract a path)
  static String fromUrl(String url, {required int width}) {
    if (!enabled || cloudName.isEmpty) return url;
    final path = extractPathFromUrl(url);
    if (path == null) return url;
    return custom(path, width: width);
  }

  /// Extract storage path from a Firebase Storage download URL.
  /// "https://firebasestorage.../o/products%2Fuid%2Fmain%2Fshoe.jpg?alt=media&token=..."
  /// → "products/uid/main/shoe.jpg"
  static String? extractPathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.contains('o')) {
        final idx = uri.pathSegments.indexOf('o');
        if (idx + 1 < uri.pathSegments.length) {
          return Uri.decodeComponent(uri.pathSegments[idx + 1]);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  static String _firebaseUrl(String storagePath) {
    assert(
        storageBucket.isNotEmpty, 'CloudinaryUrl.init() must be called first');
    return 'https://storage.googleapis.com/$storageBucket/$storagePath';
  }
}
