// lib/utils/app_image_cache_manager.dart
// ===================================================================
// AppImageCacheManager — the single shared disk/memory image cache.
//
// Every image widget in the app (CloudinaryImage and any direct
// CachedNetworkImage) must pass `cacheManager: AppImageCacheManager()`.
// Reasons:
//
//   • Bounded disk usage. DefaultCacheManager caps at 200 objects — far
//     too small for an e-commerce catalog. Past the cap, flutter_cache_manager
//     evicts + rewrites aggressively, and eviction-during-write is the
//     exact window where we see corrupt half-files. 1500 objects fits a
//     normal session without churn.
//
//   • Native single-flight dedup. When two widgets request the same URL
//     concurrently (common in product lists where color variants resolve
//     to the same thumbnail), flutter_cache_manager merges them into ONE
//     network fetch — but only if they share the same CacheManager
//     instance. Different CacheManagers = different queues = duplicate
//     downloads.
//
//   • Scoped stalePeriod. 7 days matches our catalog churn — sellers
//     update product images weekly, longer caches serve stale art.
//
//   • Named store. Separates image bytes from any future cache_manager
//     usage (PDFs, documents, avatars uploaded to other services). A bug
//     in one domain can't nuke another domain's cache.
//
//   • One eviction path. Corruption recovery (CloudinaryImage) calls
//     AppImageCacheManager().evict(url) and knows the entry is gone
//     everywhere. No mystery copies in alternate managers.
// ===================================================================

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'nar24_images_v1';

  static final AppImageCacheManager _instance = AppImageCacheManager._();
  factory AppImageCacheManager() => _instance;

  AppImageCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 1500,
            fileService: HttpFileService(),
          ),
        );

  /// Remove [url] from the disk cache and in-flight queue. Safe no-op if
  /// the URL isn't cached. Use from error handlers to purge corrupt entries
  /// so the next fetch downloads fresh bytes instead of re-serving rot.
  Future<void> evict(String url) async {
    try {
      await removeFile(url);
    } catch (_) {
      // Entry missing or store write race — next fetch will overwrite the
      // index regardless, so failure here is not load-bearing.
    }
  }
}
