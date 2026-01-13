// lib/services/cart_totals_cache.dart - Production Grade Local Cache

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Production-grade in-memory cache for cart totals
/// Features:
/// - Automatic TTL expiration
/// - Memory-efficient (only stores computed totals)
/// - Instant invalidation on cart changes
/// - No external dependencies or exposed credentials
class CartTotalsCache {
  static final CartTotalsCache _instance = CartTotalsCache._internal();
  factory CartTotalsCache() => _instance;
  CartTotalsCache._internal();

  // Cache storage
  final Map<String, _CacheEntry> _cache = {};

  // Configuration
  static const Duration _defaultTTL = Duration(minutes: 10);
  static const int _maxCacheEntries = 50; // Prevent memory bloat

  // Cleanup timer
  Timer? _cleanupTimer;
  bool _initialized = false;

  /// Initialize the cache with periodic cleanup
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Run cleanup every 5 minutes
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _removeExpiredEntries(),
    );

    debugPrint('✅ CartTotalsCache initialized');
  }

  /// Build cache key from user ID and product IDs
  String _buildKey(String userId, List<String> productIds) {
    final sorted = List<String>.from(productIds)..sort();
    return '$userId:${sorted.join(",")}';
  }

  /// Get cached totals if valid
  CachedCartTotals? get(String userId, List<String> productIds) {
    if (productIds.isEmpty) return null;

    final key = _buildKey(userId, productIds);
    final entry = _cache[key];

    if (entry == null) {
      debugPrint('📭 Cache miss: totals');
      return null;
    }

    // Check if expired
    if (entry.isExpired) {
      _cache.remove(key);
      debugPrint('⏰ Cache expired: totals');
      return null;
    }

    debugPrint('⚡ Cache hit: totals (${entry.age.inSeconds}s old)');
    return entry.data;
  }

  /// Store totals in cache
  void set(
    String userId,
    List<String> productIds,
    CachedCartTotals totals, {
    Duration? ttl,
  }) {
    if (productIds.isEmpty) return;

    // Enforce max cache size (LRU-style: remove oldest entries)
    if (_cache.length >= _maxCacheEntries) {
      _evictOldestEntries(10); // Remove 10 oldest
    }

    final key = _buildKey(userId, productIds);
    _cache[key] = _CacheEntry(
      data: totals,
      expiresAt: DateTime.now().add(ttl ?? _defaultTTL),
    );

    debugPrint('💾 Cached totals: ${totals.total} ${totals.currency}');
  }

  /// Invalidate all cached totals for a user
  /// Called when cart contents change (add/remove/update quantity)
  void invalidateForUser(String userId) {
    final keysToRemove =
        _cache.keys.where((key) => key.startsWith('$userId:')).toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      debugPrint(
          '🗑️ Invalidated ${keysToRemove.length} cached totals for user');
    }
  }

  /// Invalidate specific product combination
  void invalidateSpecific(String userId, List<String> productIds) {
    final key = _buildKey(userId, productIds);
    if (_cache.remove(key) != null) {
      debugPrint('🗑️ Invalidated specific cached total');
    }
  }

  /// Clear all cache (e.g., on logout)
  void clearAll() {
    _cache.clear();
    debugPrint('🗑️ Cleared all cached totals');
  }

  /// Remove expired entries
  void _removeExpiredEntries() {
    final expiredKeys = _cache.entries
        .where((entry) => entry.value.isExpired)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      debugPrint('🧹 Removed ${expiredKeys.length} expired cache entries');
    }
  }

  /// Evict oldest entries when cache is full
  void _evictOldestEntries(int count) {
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

    for (var i = 0; i < count && i < entries.length; i++) {
      _cache.remove(entries[i].key);
    }

    debugPrint('🧹 Evicted $count oldest cache entries');
  }

  /// Get cache statistics (for debugging)
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final validEntries = _cache.values.where((e) => !e.isExpired).length;
    final expiredEntries = _cache.length - validEntries;

    return {
      'totalEntries': _cache.length,
      'validEntries': validEntries,
      'expiredEntries': expiredEntries,
      'maxEntries': _maxCacheEntries,
    };
  }

  /// Dispose the cache
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
    _initialized = false;
    debugPrint('🧹 CartTotalsCache disposed');
  }
}

/// Cache entry with expiration
class _CacheEntry {
  final CachedCartTotals data;
  final DateTime createdAt;
  final DateTime expiresAt;

  _CacheEntry({
    required this.data,
    required this.expiresAt,
  }) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get age => DateTime.now().difference(createdAt);
}

/// Lightweight totals model for caching
/// Only stores what's needed - no heavy Product objects
class CachedCartTotals {
  final double total;
  final String currency;
  final List<CachedItemTotal> items;

  CachedCartTotals({
    required this.total,
    required this.currency,
    required this.items,
  });

  /// Create from Cloud Function response
  factory CachedCartTotals.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List? ?? [];

    return CachedCartTotals(
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'TL',
      items: itemsList.map((item) {
        final map = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        return CachedItemTotal.fromJson(map);
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'total': total,
        'currency': currency,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Individual item total (lightweight)
class CachedItemTotal {
  final String productId;
  final double unitPrice;
  final double total;
  final int quantity;
  final bool isBundleItem;

  CachedItemTotal({
    required this.productId,
    required this.unitPrice,
    required this.total,
    required this.quantity,
    this.isBundleItem = false,
  });

  factory CachedItemTotal.fromJson(Map<String, dynamic> json) {
    return CachedItemTotal(
      productId: json['productId'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 1).toInt(),
      isBundleItem: json['isBundleItem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'unitPrice': unitPrice,
        'total': total,
        'quantity': quantity,
        'isBundleItem': isBundleItem,
      };
}
