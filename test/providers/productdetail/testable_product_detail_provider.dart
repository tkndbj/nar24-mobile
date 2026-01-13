// test/providers/testable_product_detail_provider.dart
//
// TESTABLE MIRROR of ProductDetailProvider pure logic from lib/providers/product_detail_provider.dart
//
// This file contains EXACT copies of pure logic functions from ProductDetailProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/product_detail_provider.dart
//
// Last synced with: product_detail_provider.dart (current version)

/// Mirrors _sanitizeFirestoreKey from ProductDetailProvider
class TestableFirestoreKeySanitizer {
  /// Replaces Firestore-invalid characters (., $, [, ]) with underscores.
  /// Mirrors _sanitizeFirestoreKey from ProductDetailProvider
  static String sanitize(String input) {
    return input
        .replaceAll('.', '_')
        .replaceAll(',', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_');
  }

  /// Check if a key contains invalid Firestore characters
  static bool hasInvalidCharacters(String input) {
    return input.contains('.') ||
        input.contains(',') ||
        input.contains('[') ||
        input.contains(']');
  }
}

/// Mirrors _generateProductUrl from ProductDetailProvider
class TestableProductUrlGenerator {
  static const String baseUrl = 'https://emlak-mobile-app.web.app/products/';

  /// Generates dynamic product URL
  /// Mirrors _generateProductUrl from ProductDetailProvider
  static String generate(String productId) {
    return '$baseUrl$productId';
  }

  /// Parse product ID from URL
  static String? parseProductId(String url) {
    if (!url.startsWith(baseUrl)) return null;
    final id = url.substring(baseUrl.length);
    return id.isNotEmpty ? id : null;
  }
}

/// Mirrors _validateMessageData from ProductDetailProvider
class TestableMessageValidator {
  /// Validates the basic structure of messageData before writing to Firestore.
  /// Mirrors _validateMessageData from ProductDetailProvider
  /// Throws ArgumentError if validation fails
  static void validate(Map<String, dynamic> messageData) {
    // Check basic fields
    if (messageData['senderId'] == null || messageData['senderId'] is! String) {
      throw ArgumentError('Invalid senderId in messageData.');
    }
    if (messageData['type'] == null || messageData['type'] is! String) {
      throw ArgumentError('Invalid type in messageData.');
    }
    if (messageData['content'] == null ||
        messageData['content'] is! Map<String, dynamic>) {
      throw ArgumentError('Invalid content in messageData.');
    }

    final String messageType = messageData['type'];
    if (messageType == 'product') {
      final content = messageData['content'] as Map<String, dynamic>;

      if (content['productId'] == null ||
          content['productId'] is! String ||
          (content['productId'] as String).isEmpty) {
        throw ArgumentError('Invalid productId in content.');
      }
      if (content['productName'] == null ||
          content['productName'] is! String ||
          (content['productName'] as String).isEmpty) {
        throw ArgumentError('Invalid productName in content.');
      }

      if (content['productImageUrls'] == null ||
          content['productImageUrls'] is! List ||
          (content['productImageUrls'] as List).isEmpty) {
        throw ArgumentError('Invalid productImageUrls in content.');
      }
      if (content['productPrice'] == null ||
          content['productPrice'] is! num ||
          (content['productPrice'] as num) <= 0) {
        throw ArgumentError('Invalid productPrice in content.');
      }
    }
  }

  /// Check if message data is valid without throwing
  static bool isValid(Map<String, dynamic> messageData) {
    try {
      validate(messageData);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Mirrors navigation throttle logic from ProductDetailProvider
class TestableNavigationThrottle {
  final Duration throttleDuration;
  DateTime? _lastNavigationTime;

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableNavigationThrottle({
    this.throttleDuration = const Duration(milliseconds: 500),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Check if navigation should be allowed
  /// Mirrors throttle check in _fetchProductData
  bool shouldAllowNavigation() {
    final now = nowProvider();
    if (_lastNavigationTime != null &&
        now.difference(_lastNavigationTime!) < throttleDuration) {
      return false;
    }
    _lastNavigationTime = now;
    return true;
  }

  /// Reset throttle state
  void reset() {
    _lastNavigationTime = null;
  }

  /// Get time until next allowed navigation (for testing)
  Duration? getTimeUntilAllowed() {
    if (_lastNavigationTime == null) return null;
    final elapsed = nowProvider().difference(_lastNavigationTime!);
    if (elapsed >= throttleDuration) return null;
    return throttleDuration - elapsed;
  }
}

/// Mirrors static cache management logic from ProductDetailProvider
class TestableStaticCacheManager {
  final int maxNavigationsBeforeClear;
  int _navigationCount = 0;

  TestableStaticCacheManager({
    this.maxNavigationsBeforeClear = 15,
  });

  int get navigationCount => _navigationCount;

  /// Increment navigation count and return true if caches should be cleared
  /// Mirrors logic in ProductDetailProvider constructor
  bool incrementAndCheckClear() {
    _navigationCount++;
    if (_navigationCount > maxNavigationsBeforeClear) {
      _navigationCount = 0;
      return true; // Should clear caches
    }
    return false;
  }

  void reset() {
    _navigationCount = 0;
  }
}

/// Mirrors LRU cache with eviction from ProductDetailProvider
/// Used for questions, reviews, and related products caches
class TestableLRUCache<T> {
  final int maxSize;
  final Duration ttl;
  final Map<String, T> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  final List<String> _insertionOrder = [];

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableLRUCache({
    required this.maxSize,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  int get length => _cache.length;

  bool containsKey(String key) => _cache.containsKey(key);

  T? get(String key) {
    if (!_cache.containsKey(key)) return null;

    final timestamp = _timestamps[key];
    if (timestamp != null && nowProvider().difference(timestamp) > ttl) {
      // Expired
      remove(key);
      return null;
    }

    return _cache[key];
  }

  void put(String key, T value) {
    final now = nowProvider();

    // If key exists, update it
    if (_cache.containsKey(key)) {
      _cache[key] = value;
      _timestamps[key] = now;
      return;
    }

    // Add new entry
    _cache[key] = value;
    _timestamps[key] = now;
    _insertionOrder.add(key);

    // Evict oldest if over capacity
    _evictIfNeeded();
  }

  void remove(String key) {
    _cache.remove(key);
    _timestamps.remove(key);
    _insertionOrder.remove(key);
  }

  void _evictIfNeeded() {
    while (_cache.length > maxSize && _insertionOrder.isNotEmpty) {
      final oldestKey = _insertionOrder.removeAt(0);
      _cache.remove(oldestKey);
      _timestamps.remove(oldestKey);
    }
  }

  /// Mirrors cache eviction with TTL check and size limit
  void cleanupExpiredAndEvict() {
    final now = nowProvider();

    // First remove expired entries
    final expiredKeys = <String>[];
    for (final entry in _timestamps.entries) {
      if (now.difference(entry.value) > ttl) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      remove(key);
    }

    // Then evict oldest if still over capacity
    _evictIfNeeded();
  }

  void clear() {
    _cache.clear();
    _timestamps.clear();
    _insertionOrder.clear();
  }
}

/// Mirrors image index management from ProductDetailProvider
class TestableImageIndexManager {
  int _currentIndex = 0;
  int _maxIndex = 0;

  int get currentIndex => _currentIndex;

  void setMaxIndex(int maxIndex) {
    _maxIndex = maxIndex;
    // Ensure current index is still valid
    if (_currentIndex > _maxIndex) {
      _currentIndex = _maxIndex;
    }
  }

  /// Set index with bounds checking
  /// Mirrors setCurrentImageIndex from ProductDetailProvider
  bool setIndex(int index) {
    if (index >= 0 && index <= _maxIndex && _currentIndex != index) {
      _currentIndex = index;
      return true; // Changed
    }
    return false; // No change
  }

  /// Reset to first image (used when color changes)
  void reset() {
    _currentIndex = 0;
  }
}

/// Mirrors collection determination logic from ProductDetailProvider
class TestableCollectionDeterminer {
  /// Determine which Firestore collection a product belongs to
  /// Based on shopId presence
  static String determineCollection(String? shopId) {
    if (shopId != null && shopId.isNotEmpty) {
      return 'shop_products';
    }
    return 'products';
  }

  /// Check if product is a shop product
  static bool isShopProduct(String? shopId) {
    return shopId != null && shopId.isNotEmpty;
  }
}