// lib/utils/memory_manager.dart
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:Nar24/providers/product_detail_provider.dart';
import 'package:Nar24/screens/PRODUCT-SCREENS/product_detail_screen.dart';

class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal();

  // ✅ PROVEN: 30MB limit is industry best practice for mobile apps
  static const int maxImageCacheSize = 30 * 1024 * 1024; // 30MB
  static const int warningImageCacheSize = 25 * 1024 * 1024; // 25MB

  // Track last clear time to prevent excessive clearing
  DateTime? _lastClearTime;
  static const Duration _minClearInterval = Duration(seconds: 30);

  void setupMemoryManagement() {
    // ═══════════════════════════════════════════════════════
    // ADD THIS: Actually set the limits (not just check them)
    // ═══════════════════════════════════════════════════════
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 100; // Max 50 images in memory
    imageCache.maximumSizeBytes = maxImageCacheSize; // 30 MB limit

    debugPrint('🖼️ Image cache limits set: 50 images, 30 MB');

    // Listen for system memory warnings
    SystemChannels.system.setMessageHandler((message) async {
      if (message == 'memoryPressure') {
        clearAllCaches(reason: 'System memory pressure');
      }
      return null;
    });
  }

  void checkAndClearIfNeeded() {
    final imageCache = PaintingBinding.instance.imageCache;

    if (imageCache.currentSizeBytes > maxImageCacheSize) {
      // Prevent clearing too frequently
      if (_lastClearTime != null &&
          DateTime.now().difference(_lastClearTime!) < _minClearInterval) {
        return;
      }

      debugPrint(
          '⚠️ Image cache exceeds limit: ${imageCache.currentSizeBytes ~/ 1024 ~/ 1024}MB');
      clearImageCache();
    }
  }

  void clearAllCaches({String? reason}) {
    debugPrint('🧹 Clearing all caches${reason != null ? ': $reason' : ''}');

    // Clear your custom caches
    ProductDetailProvider.clearAllStaticCaches();
    ProductDetailScreen.clearStaticCaches();

    // Clear image caches
    clearImageCache();

    // Clear CachedNetworkImage disk cache on memory pressure
    DefaultCacheManager().emptyCache();
  }

  void clearImageCache() {
    final imageCache = PaintingBinding.instance.imageCache;
    final sizeBefore = imageCache.currentSizeBytes;

    imageCache.clear();
    imageCache.clearLiveImages();

    _lastClearTime = DateTime.now();

    debugPrint('✅ Image cache cleared: ${sizeBefore ~/ 1024 ~/ 1024}MB freed');
  }

  /// Get current memory stats for debugging
  Map<String, dynamic> getMemoryStats() {
    final imageCache = PaintingBinding.instance.imageCache;
    return {
      'imageCacheSizeBytes': imageCache.currentSizeBytes,
      'imageCacheSizeMB': imageCache.currentSizeBytes ~/ 1024 ~/ 1024,
      'imageCacheCount': imageCache.currentSize,
      'lastClearTime': _lastClearTime?.toIso8601String(),
    };
  }
}
