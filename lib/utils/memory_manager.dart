// lib/utils/memory_manager.dart
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:Nar24/providers/product_detail_provider.dart';
import 'package:Nar24/screens/PRODUCT-SCREENS/product_detail_screen.dart';

class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal();

  // ✅ PROVEN: 30MB limit is industry best practice for mobile apps
  static const int maxImageCacheSize = 30 * 1024 * 1024; // 30MB
  static const int warningImageCacheSize = 25 * 1024 * 1024; // 25MB

  void setupMemoryManagement() {
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
  }

  void clearImageCache() {
    final imageCache = PaintingBinding.instance.imageCache;
    final sizeBefore = imageCache.currentSizeBytes;

    imageCache.clear();
    imageCache.clearLiveImages();

    debugPrint('✅ Image cache cleared: ${sizeBefore ~/ 1024 ~/ 1024}MB freed');
  }
}
