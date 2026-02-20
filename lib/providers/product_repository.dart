// lib/repositories/product_repository.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class ProductRepository {
  static const int _maxCacheSize = 30;
  final FirebaseFirestore _firestore;

  /// In-memory cache of already-fetched products.
  final Map<String, Product> _cache = {};

  /// Tracks in-flight fetches to dedupe concurrent calls.
  final Map<String, Completer<Product>> _inFlight = {};
  Timer? _cleanupTimer;

  /// Cache TTL to prevent stale data
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 5);

  ProductRepository(this._firestore) {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      cleanupExpiredCache();
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
    clearCache();
  }

  Future<Product> fetchById(String id) {
    // 1️⃣ Validate input
    if (id.trim().isEmpty) {
      return Future.error(ArgumentError('Product ID cannot be empty'));
    }

    // Normalize out any search index prefix:
    var rawId = id.trim();
    const p1 = 'products_';
    const p2 = 'shop_products_';
    if (rawId.startsWith(p1)) {
      rawId = rawId.substring(p1.length);
    } else if (rawId.startsWith(p2)) {
      rawId = rawId.substring(p2.length);
    }

    // Validate normalized ID
    if (rawId.isEmpty) {
      return Future.error(ArgumentError('Invalid product ID format: $id'));
    }

    // 3️⃣ Check cache freshness
    final now = DateTime.now();
    if (_cache.containsKey(rawId) && _cacheTimestamps.containsKey(rawId)) {
      final cacheTime = _cacheTimestamps[rawId]!;
      if (now.difference(cacheTime) < _cacheTTL) {
        return Future.value(_cache[rawId]!);
      } else {
        // Cache expired, remove it
        _cache.remove(rawId);
        _cacheTimestamps.remove(rawId);
      }
    }

    // 4️⃣ If a fetch is already in flight, return its future
    if (_inFlight.containsKey(rawId)) {
      return _inFlight[rawId]!.future;
    }

    // 5️⃣ Otherwise start a new fetch
    final completer = Completer<Product>();
    _inFlight[rawId] = completer;

    // Kick off both reads in parallel with timeout
    final prodGet = _firestore
        .collection('products')
        .doc(rawId)
        .get()
        .timeout(const Duration(seconds: 10));

    final shopGet = _firestore // **FIXED**: Removed syntax error
        .collection('shop_products')
        .doc(rawId)
        .get()
        .timeout(const Duration(seconds: 10));

    Future.wait([prodGet, shopGet]).then((snaps) {
      final prodSnap = snaps[0] as DocumentSnapshot;
      final shopSnap = snaps[1] as DocumentSnapshot;

      DocumentSnapshot? doc;
      if (prodSnap.exists) {
        doc = prodSnap;
      } else if (shopSnap.exists) {
        doc = shopSnap;
      }

      if (doc == null || !doc.exists) {
        completer.completeError(
            StateError('Product "$id" not found in either collection'));
        return;
      }

      try {
        final product = Product.fromDocument(doc);

        // Cache for next time with timestamp
        _cache[rawId] = product;
        _cacheTimestamps[rawId] = now;

        if (_cache.length > _maxCacheSize) {
          _evictOldestEntries();
        }

        completer.complete(product);
      } catch (e, st) {
        completer.completeError(
            StateError('Failed to parse product "$id": $e'), st);
      }
    }).catchError((e, st) {
      completer.completeError(e, st);
    }).whenComplete(() {
      _inFlight.remove(rawId);
    });

    return completer.future;
  }

  void _evictOldestEntries() {
    if (_cache.length <= _maxCacheSize) return;

    final sortedEntries = _cacheTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemove = sortedEntries.take(_cache.length - _maxCacheSize);
    for (final entry in toRemove) {
      _cache.remove(entry.key);
      _cacheTimestamps.remove(entry.key);
    }
  }

  /// Optional: clear entire cache (e.g. on sign-out or memory warning).
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Remove expired entries from cache
  void cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTTL) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  /// Get cache stats for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'cacheSize': _cache.length,
      'inFlightRequests': _inFlight.length,
      'oldestCacheEntry': _cacheTimestamps.values.isEmpty
          ? null
          : _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
    };
  }
}
