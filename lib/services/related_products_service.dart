// lib/services/related_products_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'dart:async';

class RelatedProductsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================
  // TWO-TIER CACHE: Memory + TTL
  // ============================================
  static final Map<String, _CachedRelated> _memoryCache = {};
  static const Duration _cacheTTL = Duration(hours: 2);
  static const int _maxCacheSize = 30;

  /// Get related products (reads pre-computed IDs from Firestore)
  static Future<List<Product>> getRelatedProducts(Product product) async {
    final cacheKey = product.id;

    // 1️⃣ Check memory cache
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey]!;
      if (!cached.isExpired) {
        return cached.products;
      }
      _memoryCache.remove(cacheKey);
    }

    // 2️⃣ Fetch from Firestore (pre-computed by Cloud Function)
    try {
      final doc = await _firestore
          .collection('shop_products')
          .doc(product.id)
          .get();

      if (!doc.exists) {
        return await _fallbackStrategy(product);
      }

      final data = doc.data();
      final relatedIds = List<String>.from(data?['relatedProductIds'] ?? []);

      if (relatedIds.isEmpty) {
        // Product hasn't been processed by Cloud Function yet
        return await _fallbackStrategy(product);
      }

      // 3️⃣ Batch fetch related products
      final relatedProducts = await _batchFetchProducts(relatedIds);

      // 4️⃣ Cache in memory
      _cacheRelatedProducts(cacheKey, relatedProducts);

      return relatedProducts;
    } catch (e) {
      print('Error fetching related products: $e');
      return await _fallbackStrategy(product);
    }
  }

  /// Batch fetch multiple products efficiently (max 10 per batch)
  static Future<List<Product>> _batchFetchProducts(List<String> ids) async {
    if (ids.isEmpty) return [];

    final products = <Product>[];
    final chunks = _chunkList(ids, 10); // Firestore getAll limit

    for (final chunk in chunks) {
      try {
        final docs = await Future.wait(
          chunk.map((id) => 
            _firestore.collection('shop_products').doc(id).get()
          ),
        );

        for (final doc in docs) {
          if (doc.exists) {
            try {
              products.add(Product.fromDocument(doc));
            } catch (e) {
              print('Error parsing product ${doc.id}: $e');
            }
          }
        }
      } catch (e) {
        print('Error in batch fetch: $e');
      }
    }

    return products;
  }

  /// Fallback: Simple category match (if Cloud Function hasn't run yet)
  static Future<List<Product>> _fallbackStrategy(Product product) async {
    print('⚠️ Using fallback strategy for product ${product.id}');

    try {
      // Try with gender first
      if (product.gender != null) {
        final snapshot = await _firestore
            .collection('shop_products')
            .where('category', isEqualTo: product.category)
            .where('subcategory', isEqualTo: product.subcategory)
            .where('gender', isEqualTo: product.gender)
            .orderBy('promotionScore', descending: true)
            .limit(10)
            .get()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('Fallback query timeout'),
            );

        final products = snapshot.docs
            .where((doc) => doc.id != product.id)
            .map((doc) {
              try {
                return Product.fromDocument(doc);
              } catch (e) {
                print('Error parsing fallback product ${doc.id}: $e');
                return null;
              }
            })
            .whereType<Product>()
            .toList();

        if (products.isNotEmpty) return products;
      }

      // Fallback without gender
      final snapshot = await _firestore
          .collection('shop_products')
          .where('category', isEqualTo: product.category)
          .where('subcategory', isEqualTo: product.subcategory)
          .orderBy('promotionScore', descending: true)
          .limit(10)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Fallback query timeout'),
          );

      return snapshot.docs
          .where((doc) => doc.id != product.id)
          .map((doc) {
            try {
              return Product.fromDocument(doc);
            } catch (e) {
              print('Error parsing fallback product ${doc.id}: $e');
              return null;
            }
          })
          .whereType<Product>()
          .toList();
    } catch (e) {
      print('Fallback strategy failed: $e');
      return [];
    }
  }

  /// Cache management with LRU eviction
  static void _cacheRelatedProducts(String key, List<Product> products) {
    _memoryCache[key] = _CachedRelated(
      products: products,
      timestamp: DateTime.now(),
    );

    // Evict oldest if cache is full
    if (_memoryCache.length > _maxCacheSize) {
      final sortedKeys = _memoryCache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      _memoryCache.remove(sortedKeys.first.key);
    }
  }

  /// Utility: Chunk list into smaller lists
  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }

  /// Clear cache (useful for testing or memory management)
  static void clearCache() {
    _memoryCache.clear();
  }

  /// Get cache statistics (for debugging)
  static Map<String, dynamic> getCacheStats() {
    return {
      'totalEntries': _memoryCache.length,
      'expiredEntries': _memoryCache.values.where((c) => c.isExpired).length,
      'freshEntries': _memoryCache.values.where((c) => !c.isExpired).length,
    };
  }
}

/// Internal cache model
class _CachedRelated {
  final List<Product> products;
  final DateTime timestamp;

  _CachedRelated({
    required this.products,
    required this.timestamp,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) >
        RelatedProductsService._cacheTTL;
  }
}