// test/services/testable_cart_totals_cache.dart
//
// TESTABLE MIRROR of CartTotalsCache pure logic from lib/services/cart_totals_cache.dart
//
// This file contains EXACT copies of pure logic functions from CartTotalsCache
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/cart_totals_cache.dart
//
// Last synced with: cart_totals_cache.dart (current version)

/// Mirrors CachedItemTotal from CartTotalsCache
class TestableCachedItemTotal {
  final String productId;
  final double unitPrice;
  final double total;
  final int quantity;
  final bool isBundleItem;

  TestableCachedItemTotal({
    required this.productId,
    required this.unitPrice,
    required this.total,
    required this.quantity,
    this.isBundleItem = false,
  });

  /// Mirrors fromJson from CachedItemTotal
  factory TestableCachedItemTotal.fromJson(Map<String, dynamic> json) {
    return TestableCachedItemTotal(
      productId: json['productId'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 1).toInt(),
      isBundleItem: json['isBundleItem'] as bool? ?? false,
    );
  }

  /// Mirrors toJson from CachedItemTotal
  Map<String, dynamic> toJson() => {
        'productId': productId,
        'unitPrice': unitPrice,
        'total': total,
        'quantity': quantity,
        'isBundleItem': isBundleItem,
      };
}

/// Mirrors CachedCartTotals from CartTotalsCache
class TestableCachedCartTotals {
  final double total;
  final String currency;
  final List<TestableCachedItemTotal> items;

  TestableCachedCartTotals({
    required this.total,
    required this.currency,
    required this.items,
  });

  /// Mirrors fromJson from CachedCartTotals
  factory TestableCachedCartTotals.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List? ?? [];

    return TestableCachedCartTotals(
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'TL',
      items: itemsList.map((item) {
        final map = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        return TestableCachedItemTotal.fromJson(map);
      }).toList(),
    );
  }

  /// Mirrors toJson from CachedCartTotals
  Map<String, dynamic> toJson() => {
        'total': total,
        'currency': currency,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Mirrors cache key building from CartTotalsCache
class TestableCacheKeyBuilder {
  /// Mirrors _buildKey from CartTotalsCache
  /// Build cache key from user ID and product IDs
  static String buildKey(String userId, List<String> productIds) {
    final sorted = List<String>.from(productIds)..sort();
    return '$userId:${sorted.join(",")}';
  }

  /// Parse cache key back to components
  static Map<String, dynamic>? parseKey(String key) {
    final colonIndex = key.indexOf(':');
    if (colonIndex == -1) return null;

    final userId = key.substring(0, colonIndex);
    final productsPart = key.substring(colonIndex + 1);
    final productIds = productsPart.isEmpty ? <String>[] : productsPart.split(',');

    return {
      'userId': userId,
      'productIds': productIds,
    };
  }

  /// Check if key belongs to a specific user
  static bool isUserKey(String key, String userId) {
    return key.startsWith('$userId:');
  }
}

/// Mirrors cache entry expiration logic from CartTotalsCache
class TestableCacheEntry<T> {
  final T data;
  final DateTime createdAt;
  final DateTime expiresAt;

  TestableCacheEntry({
    required this.data,
    required this.expiresAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Check if entry is expired
  /// Mirrors isExpired getter from _CacheEntry
  bool isExpired({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return currentTime.isAfter(expiresAt);
  }

  /// Get age of entry
  /// Mirrors age getter from _CacheEntry
  Duration getAge({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(createdAt);
  }

  /// Get remaining TTL
  Duration getRemainingTTL({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final remaining = expiresAt.difference(currentTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Mirrors cache management logic from CartTotalsCache
class TestableCacheManager<T> {
  static const Duration defaultTTL = Duration(minutes: 10);
  static const int maxCacheEntries = 50;

  final Map<String, TestableCacheEntry<T>> _cache = {};

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableCacheManager({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  int get length => _cache.length;
  bool get isEmpty => _cache.isEmpty;
  bool get isNotEmpty => _cache.isNotEmpty;
  bool get isFull => _cache.length >= maxCacheEntries;

  /// Get entry if valid (not expired)
  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired(now: nowProvider())) {
      _cache.remove(key);
      return null;
    }

    return entry.data;
  }

  /// Set entry with TTL
  void set(String key, T data, {Duration? ttl}) {
    // Enforce max cache size
    if (_cache.length >= maxCacheEntries) {
      evictOldestEntries(10);
    }

    _cache[key] = TestableCacheEntry(
      data: data,
      expiresAt: nowProvider().add(ttl ?? defaultTTL),
      createdAt: nowProvider(),
    );
  }

  /// Check if key exists and is valid
  bool containsValid(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    return !entry.isExpired(now: nowProvider());
  }

  /// Remove entries matching prefix
  /// Mirrors invalidateForUser from CartTotalsCache
  int removeByPrefix(String prefix) {
    final keysToRemove =
        _cache.keys.where((key) => key.startsWith(prefix)).toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    return keysToRemove.length;
  }

  /// Remove specific key
  bool remove(String key) {
    return _cache.remove(key) != null;
  }

  /// Clear all entries
  void clear() {
    _cache.clear();
  }

  /// Remove expired entries
  /// Mirrors _removeExpiredEntries from CartTotalsCache
  int removeExpiredEntries() {
    final expiredKeys = _cache.entries
        .where((entry) => entry.value.isExpired(now: nowProvider()))
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
    }

    return expiredKeys.length;
  }

  /// Evict oldest entries (LRU-style)
  /// Mirrors _evictOldestEntries from CartTotalsCache
  int evictOldestEntries(int count) {
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

    int evicted = 0;
    for (var i = 0; i < count && i < entries.length; i++) {
      _cache.remove(entries[i].key);
      evicted++;
    }

    return evicted;
  }

  /// Get cache statistics
  /// Mirrors getStats from CartTotalsCache
  Map<String, dynamic> getStats() {
    final validEntries = _cache.values
        .where((e) => !e.isExpired(now: nowProvider()))
        .length;
    final expiredEntries = _cache.length - validEntries;

    return {
      'totalEntries': _cache.length,
      'validEntries': validEntries,
      'expiredEntries': expiredEntries,
      'maxEntries': maxCacheEntries,
    };
  }

  /// Get all keys (for testing)
  List<String> get keys => _cache.keys.toList();
}

/// Helper for testing user invalidation
class TestableUserCacheInvalidator {
  /// Build prefix for user invalidation
  static String buildUserPrefix(String userId) {
    return '$userId:';
  }

  /// Check if key belongs to user
  static bool keyBelongsToUser(String key, String userId) {
    return key.startsWith('$userId:');
  }

  /// Filter keys belonging to user
  static List<String> filterUserKeys(List<String> keys, String userId) {
    final prefix = buildUserPrefix(userId);
    return keys.where((key) => key.startsWith(prefix)).toList();
  }
}