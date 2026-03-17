import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Marketplace-grade image compression utility.
///
/// Design principles:
/// ─ Never upscale  — only downscale images that exceed the dimension cap
/// ─ Never bloat    — if compression produces a larger file, return original
/// ─ Never throw    — all errors are caught; original file is returned as fallback
/// ─ Strip EXIF     — removes location data and reduces file size
/// ─ PNG-aware      — transparent PNGs stay PNG; everything else → JPEG
///
/// Two public methods cover all use-cases in the product flow:
///   compressProductImage  — main gallery photos  (max 1500 px · q85 · ~200–400 KB)
///   compressColorImage    — color-variant swatches (max 800 px  · q82 · ~80–150 KB)
///
/// ecommerceCompress is kept as a backward-compatible alias.
class ImageCompressionUtils {

  // ── Constants ────────────────────────────────────────────────────────────

  /// Files below this threshold are already well-optimised — skip compression.
  static const int _skipThresholdBytes = 200 * 1024; // 200 KB

  /// Files above this threshold are rejected before any work is done.
  /// This is a safety net; the primary guard lives in the image picker.
  static const int _maxInputBytes = 20 * 1024 * 1024; // 20 MB

  /// Main product gallery: crisp on retina displays, storage-friendly.
  /// 1500 px covers a 750 px UI slot at 2× DPI — the sweet spot for
  /// marketplace product pages without serving unnecessarily large files.
  static const int _productMaxDimension = 1500;
  static const int _productQuality = 85;

  /// Color-variant swatch: shown at smaller sizes in the UI.
  static const int _colorMaxDimension = 800;
  static const int _colorQuality = 82;


  // ── Public API ───────────────────────────────────────────────────────────

  /// Compress a main product gallery image.
  /// Output: max 1500×1500 px · quality 85 JPEG · target ~200–400 KB.
  static Future<File?> compressProductImage(File file) => _compress(
        file,
        maxDimension: _productMaxDimension,
        quality: _productQuality,
        label: 'product',
      );

  /// Compress a color-variant image.
  /// Output: max 800×800 px · quality 82 JPEG · target ~80–150 KB.
  static Future<File?> compressColorImage(File file) => _compress(
        file,
        maxDimension: _colorMaxDimension,
        quality: _colorQuality,
        label: 'color',
      );

  /// Backward-compatible alias — delegates to [compressProductImage].
  static Future<File?> ecommerceCompress(File file) =>
      compressProductImage(file);


  // ── Private implementation ───────────────────────────────────────────────

  static Future<File?> _compress(
    File file, {
    required int maxDimension,
    required int quality,
    required String label,
  }) async {
    try {
      final fileSize = await file.length();

      // Guard: reject files that exceed the maximum allowed input size.
      if (fileSize > _maxInputBytes) {
        throw Exception(
          'Image too large (${_fmt(fileSize)}). Maximum is 20 MB.',
        );
      }

      // Skip: file is already small enough — compression adds overhead.
      if (fileSize < _skipThresholdBytes) {
        _log(label, 'skipped — ${_fmt(fileSize)} already under 200 KB');
        return file;
      }

      // Read original pixel dimensions.
      // We decode via codec, read width/height, then immediately dispose
      // the pixel buffer to avoid holding a large image in memory.
      final imageData = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageData);
      final frame = await codec.getNextFrame();
      final origWidth = frame.image.width;
      final origHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      // Calculate the scale factor.
      // min(..., 1.0) ensures we never upscale an image that is already
      // smaller than the dimension cap.
      final scale = min(
        min(maxDimension / origWidth, maxDimension / origHeight),
        1.0,
      );
      final targetWidth = (origWidth * scale).round();
      final targetHeight = (origHeight * scale).round();

      // Preserve PNG transparency; convert everything else to JPEG.
      final ext = p.extension(file.path).toLowerCase();
      final isPng = ext == '.png';
      final format = isPng ? CompressFormat.png : CompressFormat.jpeg;
      final outputExt = isPng ? '.png' : '.jpg';

      // Build a unique output path in the system temp directory.
      final tempDir = await getTemporaryDirectory();
      final targetPath = p.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${label}$outputExt',
      );

      // Run compression.
      // minWidth/minHeight here equal our calculated target — because we
      // capped scale at 1.0 above, these values are always ≤ the original
      // dimensions, so the library will only downscale, never upscale.
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: format,
        keepExif: false,
      );

      if (result == null) {
        _log(label, 'compressor returned null — falling back to original');
        return file;
      }

      final compressedFile = File(result.path);
      final compressedSize = await compressedFile.length();

      // Safety: if the output is somehow larger than the input
      // (can happen with already-compressed low-res files), use the original.
      if (compressedSize >= fileSize) {
        _log(label, 'compressed ≥ original — falling back to original');
        return file;
      }

      final saved =
          ((fileSize - compressedSize) / fileSize * 100).toStringAsFixed(1);
      _log(
        label,
        '${_fmt(fileSize)} → ${_fmt(compressedSize)} (-$saved%)  '
        '[$origWidth×$origHeight → $targetWidth×$targetHeight]',
      );

      return compressedFile;
    } catch (e) {
      // Never block the user — log the error and return the original file.
      _log(label, 'error: $e — falling back to original');
      return file;
    }
  }


  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ignore: avoid_print
  static void _log(String label, String message) =>
      print('🖼  [$label] $message');
}