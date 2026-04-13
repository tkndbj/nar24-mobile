// lib/services/product_upload_service.dart
// ===================================================================
// Product Upload Service
//
// Wraps Firebase Storage uploads, returning STORAGE PATHS instead of
// download URLs. Cloudinary URL builder constructs display URLs from
// these paths at render time.
//
// This replaces the inline _uploadAllFiles / _uploadFileWithRetry
// methods in ListProductPreviewScreen, making them testable and
// reusable.
//
// Key change from before:
//   BEFORE: upload → getDownloadURL() → store URL in Firestore
//   AFTER:  upload → ref.fullPath     → store path in Firestore
//           display URLs constructed by CloudinaryUrl at render time
// ===================================================================

import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/image_compression_utils.dart';

/// Result of uploading all product files.
class ProductUploadResult {
  /// Firebase Storage paths for main images (in order).
  final List<String> imageStoragePaths;

  /// Firebase Storage path for video, or null.
  final String? videoStoragePath;

  /// Map of colorKey → Firebase Storage path for color images.
  final Map<String, String> colorImageStoragePaths;

  const ProductUploadResult({
    required this.imageStoragePaths,
    this.videoStoragePath,
    required this.colorImageStoragePaths,
  });
}

/// Progress callback: (bytesTransferred, totalBytes, completedFiles, totalFiles)
typedef UploadProgressCallback = void Function(
    int bytesTransferred, int totalBytes, int completedFiles, int totalFiles);

// ─── Internal job descriptor ────────────────────────────────────────
class _UploadJob {
  final File file;
  final String storagePath;
  final String? colorKey;
  final bool isVideo;

  const _UploadJob({
    required this.file,
    required this.storagePath,
    this.colorKey,
    this.isVideo = false,
  });
}

// ─────────────────────────────────────────────────────────────────────

class ProductUploadService {
  static const int _maxConcurrent = 3;
  static const int _maxRetries = 2;

  final List<StreamSubscription<TaskSnapshot>> _activeSubs = [];

  /// Cancel all in-flight uploads. Call from widget dispose().
  void dispose() {
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
  }

  /// Upload all new product files to Firebase Storage.
  ///
  /// Returns [ProductUploadResult] with storage paths (not URLs).
  /// Existing paths from edit mode are passed through unchanged.
  Future<ProductUploadResult> uploadProductFiles({
    required String userId,
    List<String> existingImagePaths = const [],
    String? existingVideoPath,
    Map<String, String> existingColorPaths = const {},
    List<File> newImages = const [],
    Map<String, File> newColorImages = const {},
    File? newVideo,
    UploadProgressCallback? onProgress,
  }) async {
    final jobs = <_UploadJob>[];

    // ── Main images (already compressed at pick time) ────────────
    for (final file in newImages) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      jobs.add(_UploadJob(
        file: file,
        storagePath: 'products/$userId/main/$fileName',
      ));
    }

    // ── Color images (compress here since color picker doesn't) ──
    for (final entry in newColorImages.entries) {
      final compressed =
          await ImageCompressionUtils.compressColorImage(entry.value);
      final file = compressed ?? entry.value;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      jobs.add(_UploadJob(
        file: file,
        storagePath: 'products/$userId/colors/${entry.key}/$fileName',
        colorKey: entry.key,
      ));
    }

    // ── Video (no compression) ───────────────────────────────────
    if (newVideo != null) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${newVideo.path.split('/').last}';
      jobs.add(_UploadJob(
        file: newVideo,
        storagePath: 'products/$userId/video/$fileName',
        isVideo: true,
      ));
    }

    // Nothing new → return existing
    if (jobs.isEmpty) {
      return ProductUploadResult(
        imageStoragePaths: List.from(existingImagePaths),
        videoStoragePath: existingVideoPath,
        colorImageStoragePaths: Map.from(existingColorPaths),
      );
    }

    // ── Measure file sizes ───────────────────────────────────────
    int totalBytes = 0;
    final fileSizes = <int>[];
    for (final job in jobs) {
      final size = await job.file.length();
      fileSizes.add(size);
      totalBytes += size;
    }

    // ── Upload in batches of 3 ───────────────────────────────────
    final bytesPerFile = List<int>.filled(jobs.length, 0);
    int completedFiles = 0;
    final uploadedPaths = List<String?>.filled(jobs.length, null);

    void reportProgress() {
      onProgress?.call(
        bytesPerFile.fold<int>(0, (a, b) => a + b),
        totalBytes,
        completedFiles,
        jobs.length,
      );
    }

    for (int start = 0; start < jobs.length; start += _maxConcurrent) {
      final end = (start + _maxConcurrent).clamp(0, jobs.length);

      await Future.wait(
        List.generate(end - start, (i) => start + i).map((idx) async {
          uploadedPaths[idx] = await _uploadWithRetry(
            job: jobs[idx],
            onBytesTransferred: (bytes) {
              bytesPerFile[idx] = bytes;
              reportProgress();
            },
          );
          completedFiles++;
          bytesPerFile[idx] = fileSizes[idx];
          reportProgress();
        }),
      );
    }

    // ── Assemble results ─────────────────────────────────────────
    final imagePaths = List<String>.from(existingImagePaths);
    String? videoPath = existingVideoPath;
    final colorPaths = Map<String, String>.from(existingColorPaths);

    for (int i = 0; i < jobs.length; i++) {
      final path = uploadedPaths[i]!;
      if (jobs[i].isVideo) {
        videoPath = path;
      } else if (jobs[i].colorKey != null) {
        colorPaths[jobs[i].colorKey!] = path;
      } else {
        imagePaths.add(path);
      }
    }

    return ProductUploadResult(
      imageStoragePaths: imagePaths,
      videoStoragePath: videoPath,
      colorImageStoragePaths: colorPaths,
    );
  }

  // ── Single file upload with retry ─────────────────────────────────

  Future<String> _uploadWithRetry({
    required _UploadJob job,
    required void Function(int) onBytesTransferred,
  }) async {
    int attempt = 0;

    while (true) {
      StreamSubscription<TaskSnapshot>? sub;
      try {
        final ref = FirebaseStorage.instance.ref(job.storagePath);
        final task = ref.putFile(job.file);

        sub = task.snapshotEvents.listen(
          (snap) => onBytesTransferred(snap.bytesTransferred),
        );
        _activeSubs.add(sub);

        await task;
        sub.cancel();
        _activeSubs.remove(sub);

        // KEY CHANGE: return storage path, NOT download URL.
        // Cloudinary URL builder constructs display URLs from this path.
        return ref.fullPath;
      } catch (e) {
        sub?.cancel();
        if (sub != null) _activeSubs.remove(sub);

        attempt++;
        if (attempt > _maxRetries) rethrow;
        onBytesTransferred(0);
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
}
