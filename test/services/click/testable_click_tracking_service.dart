// test/services/testable_click_tracking_service.dart
//
// TESTABLE MIRROR of ClickTrackingService pure logic from lib/services/click_tracking_service.dart
//
// This file contains EXACT copies of pure logic functions from ClickTrackingService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/click_tracking_service.dart
//
// Last synced with: click_tracking_service.dart (current version)

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Mirrors click cooldown logic from ClickTrackingService
class TestableClickCooldown {
  static const Duration cooldownDuration = Duration(seconds: 1);

  final Map<String, DateTime> _lastClickTime = {};

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableClickCooldown({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Check if click should be allowed (not in cooldown)
  /// Mirrors the cooldown check in trackProductClick/trackShopClick
  bool shouldAllowClick(String itemId) {
    final now = nowProvider();
    final lastClick = _lastClickTime[itemId];

    if (lastClick != null && now.difference(lastClick) < cooldownDuration) {
      return false;
    }

    return true;
  }

  /// Record a click (updates last click time)
  void recordClick(String itemId) {
    _lastClickTime[itemId] = nowProvider();
  }

  /// Check and record in one operation (returns true if allowed)
  bool tryClick(String itemId) {
    if (!shouldAllowClick(itemId)) {
      return false;
    }
    recordClick(itemId);
    return true;
  }

  /// Get time until next click is allowed
  Duration getTimeUntilAllowed(String itemId) {
    final lastClick = _lastClickTime[itemId];
    if (lastClick == null) return Duration.zero;

    final elapsed = nowProvider().difference(lastClick);
    final remaining = cooldownDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void clear() {
    _lastClickTime.clear();
  }
}

/// Mirrors buffer management logic from ClickTrackingService
class TestableClickBuffer {
  static const int maxBufferSize = 500;
  static const int maxMemoryBytes = 512 * 1024; // 512KB
  static const int estimatedBytesPerClick = 100;
  static const Duration maxTimeSinceFlush = Duration(minutes: 5);

  final Map<String, int> productClicks = {};
  final Map<String, int> shopProductClicks = {};
  final Map<String, int> shopClicks = {};
  final Map<String, String> shopIds = {};

  DateTime? lastSuccessfulFlush;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableClickBuffer({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors _getTotalBufferedCount from ClickTrackingService
  int getTotalBufferedCount() {
    return productClicks.length + shopProductClicks.length + shopClicks.length;
  }

  /// Estimate memory usage in bytes
  int getEstimatedMemoryBytes() {
    return getTotalBufferedCount() * estimatedBytesPerClick;
  }

  /// Mirrors _shouldForceFlush from ClickTrackingService
  bool shouldForceFlush() {
    final totalBuffered = getTotalBufferedCount();
    final estimatedMemory = getEstimatedMemoryBytes();

    return totalBuffered >= maxBufferSize ||
        estimatedMemory >= maxMemoryBytes ||
        (lastSuccessfulFlush != null &&
            nowProvider().difference(lastSuccessfulFlush!) > maxTimeSinceFlush);
  }

  /// Add a product click
  void addProductClick(String productId, {bool isShopProduct = true, String? shopId}) {
    final rawId = extractRawProductId(productId);

    if (isShopProduct) {
      shopProductClicks[rawId] = (shopProductClicks[rawId] ?? 0) + 1;
    } else {
      productClicks[rawId] = (productClicks[rawId] ?? 0) + 1;
    }

    if (shopId != null) {
      shopIds[rawId] = shopId;
    }
  }

  /// Add a shop click
  void addShopClick(String shopId) {
    shopClicks[shopId] = (shopClicks[shopId] ?? 0) + 1;
  }

  /// Mirrors product ID extraction from trackProductClick
  /// Strips prefix like "products_" or "shop_products_"
  static String extractRawProductId(String productId) {
    return productId.contains('_') ? productId.split('_').last : productId;
  }

  /// Clear all buffers (after successful flush)
  void clear() {
    productClicks.clear();
    shopProductClicks.clear();
    shopClicks.clear();
    shopIds.clear();
  }

  /// Mark successful flush
  void markFlushSuccess() {
    lastSuccessfulFlush = nowProvider();
    clear();
  }

  /// Check if buffer has any clicks
  bool get hasClicks => getTotalBufferedCount() > 0;
}

/// Mirrors circuit breaker logic from ClickTrackingService
class TestableClickCircuitBreaker {
  static const int maxFailures = 3;
  static const Duration cooldownDuration = Duration(minutes: 5);

  int failureCount = 0;
  bool isOpen = false;
  DateTime? lastFailure;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableClickCircuitBreaker({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Check if circuit breaker allows operation
  /// Mirrors the circuit breaker check in _flushClicks
  bool shouldAllowOperation() {
    if (!isOpen) return true;

    // Check if cooldown has passed
    if (lastFailure != null &&
        nowProvider().difference(lastFailure!) > cooldownDuration) {
      // Reset circuit breaker
      isOpen = false;
      failureCount = 0;
      return true;
    }

    return false;
  }

  /// Record a failure
  void recordFailure() {
    failureCount++;
    lastFailure = nowProvider();

    if (failureCount >= maxFailures) {
      isOpen = true;
    }
  }

  /// Record a success (resets state)
  void recordSuccess() {
    failureCount = 0;
    isOpen = false;
  }

  /// Get time until circuit breaker resets
  Duration getTimeUntilReset() {
    if (!isOpen || lastFailure == null) return Duration.zero;

    final elapsed = nowProvider().difference(lastFailure!);
    final remaining = cooldownDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void reset() {
    failureCount = 0;
    isOpen = false;
    lastFailure = null;
  }
}

/// Mirrors batch ID generation logic from ClickTrackingService
class TestableBatchIdGenerator {
  static const Duration batchIdTTL = Duration(seconds: 30);

  String? currentBatchId;
  DateTime? batchIdCreatedAt;
  String? currentUserId;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableBatchIdGenerator({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors _generateBatchId from ClickTrackingService
  String generateBatchId({String? userId}) {
    final now = nowProvider();
    final effectiveUserId = userId ?? currentUserId ?? 'anonymous';

    // Check if we can reuse current batch ID
    if (currentBatchId != null &&
        batchIdCreatedAt != null &&
        now.difference(batchIdCreatedAt!) < batchIdTTL) {
      return currentBatchId!;
    }

    // Create new deterministic batch ID
    final timestamp = now.millisecondsSinceEpoch;

    // Round timestamp to nearest 30 seconds for deduplication window
    final roundedTimestamp = (timestamp ~/ 30000) * 30000;

    final input = '$effectiveUserId-$roundedTimestamp';
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);

    currentBatchId = 'batch_${hash.toString().substring(0, 16)}';
    batchIdCreatedAt = now;

    return currentBatchId!;
  }

  /// Generate a chunk-specific batch ID
  String generateChunkBatchId(String baseBatchId, int chunkIndex) {
    return '${baseBatchId}_chunk_$chunkIndex';
  }

  /// Check if current batch ID is still valid
  bool isBatchIdValid() {
    if (currentBatchId == null || batchIdCreatedAt == null) return false;
    return nowProvider().difference(batchIdCreatedAt!) < batchIdTTL;
  }

  void reset() {
    currentBatchId = null;
    batchIdCreatedAt = null;
  }
}

/// Mirrors retry logic from ClickTrackingService
class TestableRetryManager {
  static const int maxRetryAttempts = 3;
  static const Duration baseRetryDelay = Duration(seconds: 10);

  int retryAttempts = 0;

  /// Calculate delay for current retry attempt
  /// Mirrors: Duration(seconds: 10 * _retryAttempts)
  Duration getRetryDelay() {
    return Duration(seconds: 10 * retryAttempts);
  }

  /// Record a retry attempt
  void recordRetry() {
    retryAttempts++;
  }

  /// Check if more retries are allowed
  bool get canRetry => retryAttempts < maxRetryAttempts;

  /// Check if should persist to database (max retries reached)
  bool get shouldPersist => retryAttempts >= maxRetryAttempts;

  /// Reset retry state (after success or persist)
  void reset() {
    retryAttempts = 0;
  }
}

/// Mirrors chunking logic from ClickTrackingService
class TestableClickChunker {
  static const int chunkSize = 500;
  static const int maxPayloadBytes = 1000000; // 1MB

  /// Check if payload needs chunking
  /// Mirrors condition in _flushClicks
  static bool needsChunking(int totalClicks, int payloadSizeBytes) {
    return totalClicks > chunkSize || payloadSizeBytes > maxPayloadBytes;
  }

  /// Calculate number of chunks needed
  static int calculateChunkCount(int totalItems) {
    if (totalItems == 0) return 0;
    return (totalItems / chunkSize).ceil();
  }

  /// Split items into chunks
  static List<List<T>> chunkItems<T>(List<T> items) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += chunkSize) {
      final end = (i + chunkSize > items.length) ? items.length : i + chunkSize;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  /// Get chunk at specific index
  static List<T> getChunk<T>(List<T> items, int chunkIndex) {
    final start = chunkIndex * chunkSize;
    if (start >= items.length) return [];
    final end = (start + chunkSize > items.length) ? items.length : start + chunkSize;
    return items.sublist(start, end);
  }
}

/// Represents a click item for chunking
class ClickItem {
  final String itemId;
  final String type; // 'product', 'shop_product', 'shop'
  final int count;
  final String? shopId;

  ClickItem({
    required this.itemId,
    required this.type,
    required this.count,
    this.shopId,
  });
}

/// Mirrors payload building logic from ClickTrackingService
class TestablePayloadBuilder {
  /// Build payload from click maps
  static Map<String, dynamic> buildPayload({
    required String batchId,
    required Map<String, int> productClicks,
    required Map<String, int> shopProductClicks,
    required Map<String, int> shopClicks,
    required Map<String, String> shopIds,
  }) {
    return {
      'batchId': batchId,
      'productClicks': productClicks,
      'shopProductClicks': shopProductClicks,
      'shopClicks': shopClicks,
      'shopIds': shopIds,
    };
  }

  /// Estimate payload size in bytes
  static int estimatePayloadSize(Map<String, dynamic> payload) {
    return jsonEncode(payload).length;
  }

  /// Convert buffer to list of ClickItems for chunking
  static List<ClickItem> bufferToClickItems({
    required Map<String, int> productClicks,
    required Map<String, int> shopProductClicks,
    required Map<String, int> shopClicks,
    required Map<String, String> shopIds,
  }) {
    final items = <ClickItem>[];

    productClicks.forEach((id, count) {
      items.add(ClickItem(itemId: id, type: 'product', count: count));
    });

    shopProductClicks.forEach((id, count) {
      items.add(ClickItem(
        itemId: id,
        type: 'shop_product',
        count: count,
        shopId: shopIds[id],
      ));
    });

    shopClicks.forEach((id, count) {
      items.add(ClickItem(itemId: id, type: 'shop', count: count));
    });

    return items;
  }

  /// Build payload from chunk of ClickItems
  static Map<String, dynamic> buildChunkPayload(
    String batchId,
    List<ClickItem> items,
  ) {
    final payload = <String, dynamic>{
      'batchId': batchId,
      'productClicks': <String, int>{},
      'shopProductClicks': <String, int>{},
      'shopClicks': <String, int>{},
      'shopIds': <String, String>{},
    };

    for (final item in items) {
      if (item.type == 'product') {
        (payload['productClicks'] as Map<String, int>)[item.itemId] = item.count;
      } else if (item.type == 'shop_product') {
        (payload['shopProductClicks'] as Map<String, int>)[item.itemId] = item.count;
        if (item.shopId != null) {
          (payload['shopIds'] as Map<String, String>)[item.itemId] = item.shopId!;
        }
      } else if (item.type == 'shop') {
        (payload['shopClicks'] as Map<String, int>)[item.itemId] = item.count;
      }
    }

    return payload;
  }
}

/// Mirrors metrics from ClickTrackingService.getMetrics
class TestableClickMetrics {
  final int bufferedClicks;
  final bool circuitOpen;
  final int failureCount;
  final int retryAttempts;
  final DateTime? lastFailure;
  final DateTime? lastSuccess;

  TestableClickMetrics({
    required this.bufferedClicks,
    required this.circuitOpen,
    required this.failureCount,
    required this.retryAttempts,
    this.lastFailure,
    this.lastSuccess,
  });

  Map<String, dynamic> toMap() {
    return {
      'bufferedClicks': bufferedClicks,
      'circuitOpen': circuitOpen,
      'failureCount': failureCount,
      'retryAttempts': retryAttempts,
      'lastFailure': lastFailure?.toIso8601String(),
      'lastSuccess': lastSuccess?.toIso8601String(),
    };
  }
}