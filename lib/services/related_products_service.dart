import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'package:flutter/foundation.dart';

class RelatedProductsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, _CachedRelated> _memoryCache = {};
  static const Duration _cacheTTL = Duration(hours: 2);
  static const int _maxCacheSize = 30;

  /// Fetch up to 15 pre-computed related products by ID
  static Future<List<Product>> getRelatedProducts(List<String> relatedIds) async {
    if (relatedIds.isEmpty) return [];

    final ids = relatedIds.take(15).toList();
    final cacheKey = ids.join(',');

    // Check memory cache
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey]!;
      if (!cached.isExpired) return cached.products;
      _memoryCache.remove(cacheKey);
    }

    try {
      final docs = await Future.wait(
        ids.map((id) => _firestore.collection('shop_products').doc(id).get()),
      );

      final products = <Product>[];
      for (final doc in docs) {
        if (doc.exists) {
          try {
            products.add(Product.fromDocument(doc));
          } catch (e) {
            debugPrint('Error parsing related product ${doc.id}: $e');
          }
        }
      }

      // Cache result
      _memoryCache[cacheKey] = _CachedRelated(products: products, timestamp: DateTime.now());
      if (_memoryCache.length > _maxCacheSize) {
        final oldest = (_memoryCache.entries.toList()
              ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp)))
            .first
            .key;
        _memoryCache.remove(oldest);
      }

      return products;
    } catch (e) {
      debugPrint('Error fetching related products: $e');
      return [];
    }
  }

  static void clearCache() => _memoryCache.clear();
}

class _CachedRelated {
  final List<Product> products;
  final DateTime timestamp;
  _CachedRelated({required this.products, required this.timestamp});
  bool get isExpired =>
      DateTime.now().difference(timestamp) > RelatedProductsService._cacheTTL;
}