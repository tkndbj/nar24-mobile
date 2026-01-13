import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyProductsProvider extends ChangeNotifier {
  // Configuration constants
  static const int _maxCacheSize = 1000;
  static const int _batchSize = 10;
  static const Duration _cacheExpiryDuration = Duration(minutes: 30);
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  // State management
  DateTimeRange? selectedDateRange;
  String searchQuery = '';
  String transactionSearchQuery = '';

  // Search mode state
  bool _isSearchMode = false;
  bool get isSearchMode => _isSearchMode;

  // Caching system
  final LinkedHashMap<String, _CachedProduct> _productCache = LinkedHashMap();
  final Map<String, _CachedTransactionPage> _transactionCache = {};
  final Map<String, DateTime> _lastSyncTimes = {};

  // Product management
  List<Product> _products = [];
  bool _isLoading = true;

  // Request deduplication
  final Map<String, Future<Map<String, dynamic>>> _pendingTransactionRequests =
      {};
  final Map<String, Future<Map<String, Product>>> _pendingProductRequests = {};

  // Debouncing
  Timer? _searchDebounce;
  Timer? _cacheCleanupTimer;

  MyProductsProvider() {
    _initialize();
    _startCacheCleanup();
  }

  // Getters
  List<Product> get products => _filteredProducts;
  bool get isLoading => _isLoading;

  List<Product> get _filteredProducts {
    var filtered = _products;

    if (selectedDateRange != null) {
      filtered = filtered.where((p) {
        final date = p.createdAt.toDate();
        return _isDateInRange(date, selectedDateRange!);
      }).toList();
    }

    if (searchQuery.isNotEmpty && !_isSearchMode) {
      filtered = filtered.where((p) {
        final name = p.productName.toLowerCase();
        final brand = p.brandModel?.toLowerCase() ?? '';
        return name.contains(searchQuery) || brand.contains(searchQuery);
      }).toList();
    }

    return filtered;
  }

  void _initialize() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _listenToProducts(userId);
    }
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _cleanupExpiredCache();
    });
  }

  void _cleanupExpiredCache() {
    final now = DateTime.now();

    // Clean product cache
    _productCache.removeWhere((key, cached) {
      return now.difference(cached.cachedAt) > _cacheExpiryDuration;
    });

    // Clean transaction cache
    _transactionCache.removeWhere((key, cached) {
      return now.difference(cached.cachedAt) > _cacheExpiryDuration;
    });

    // Enforce cache size limits
    _enforceCacheSizeLimit();
  }

  void _enforceCacheSizeLimit() {
    while (_productCache.length > _maxCacheSize) {
      _productCache.remove(_productCache.keys.first);
    }
  }

  void _listenToProducts(String userId) {
    FirebaseFirestore.instance
        .collection('products')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snapshot) {
        _products =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();
        _isLoading = false;

        // Update product cache with fresh data
        for (final doc in snapshot.docs) {
          final product = Product.fromDocument(doc);
          _productCache[product.id] = _CachedProduct(product, DateTime.now());
        }

        notifyListeners();
      },
      onError: (e) {
        debugPrint('Error listening to products: $e');
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void updateSelectedDateRange(DateTimeRange? range) {
    selectedDateRange = range;
    // Clear transaction cache when date range changes
    _transactionCache.clear();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setTransactionSearchQuery(String query) {
    transactionSearchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setSearchMode(bool isSearchMode) {
    _isSearchMode = isSearchMode;
    notifyListeners();
  }

  List<Map<String, dynamic>> filterTransactions(
      List<Map<String, dynamic>> transactions, String searchQuery) {
    if (searchQuery.isEmpty) return transactions;

    return transactions.where((tx) {
      final data = tx['data'] as Map<String, dynamic>;
      final productName = (data['productName'] as String? ?? '').toLowerCase();
      final brandModel = (data['brandModel'] as String? ?? '').toLowerCase();
      final sellerName = (data['sellerName'] as String? ?? '').toLowerCase();
      final buyerName = (data['buyerName'] as String? ?? '').toLowerCase();
      final shopName = (data['shopName'] as String? ?? '').toLowerCase();

      final query = searchQuery.toLowerCase();

      return productName.contains(query) ||
          brandModel.contains(query) ||
          sellerName.contains(query) ||
          buyerName.contains(query) ||
          shopName.contains(query);
    }).toList();
  }

  bool matchesSelectedDateRange(dynamic ts) {
    if (ts == null) return false;
    if (ts is! Timestamp) return false; // Add this line
    if (selectedDateRange == null) return true;
    final date = ts.toDate();
    return _isDateInRange(date, selectedDateRange!);
  }

  bool _isDateInRange(DateTime date, DateTimeRange range) {
    return (date.isAfter(range.start) || _isSameDay(date, range.start)) &&
        (date.isBefore(range.end) || _isSameDay(date, range.end));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<Map<String, dynamic>> loadTransactions({
    required FirebaseFirestore firestore,
    required String userId,
    required bool isSold,
    int pageSize = 20,
    DocumentSnapshot? lastTransactionDoc,
  }) async {
    final cacheKey =
        _buildTransactionCacheKey(userId, isSold, lastTransactionDoc?.id);

    // Check if we already have a pending request for this data
    if (_pendingTransactionRequests.containsKey(cacheKey)) {
      return await _pendingTransactionRequests[cacheKey]!;
    }

    // Check cache first
    final cached = _transactionCache[cacheKey];
    if (cached != null && !_isCacheExpired(cached.cachedAt)) {
      return {
        'transactions': cached.transactions,
        'lastDoc': cached.lastDoc,
      };
    }

    // Create and store the pending request
    final future = _loadTransactionsFromFirestore(
      firestore: firestore,
      userId: userId,
      isSold: isSold,
      pageSize: pageSize,
      lastTransactionDoc: lastTransactionDoc,
      cacheKey: cacheKey,
    );

    _pendingTransactionRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingTransactionRequests.remove(cacheKey);
    }
  }

  Future<Map<String, dynamic>> _loadTransactionsFromFirestore({
    required FirebaseFirestore firestore,
    required String userId,
    required bool isSold,
    required int pageSize,
    required DocumentSnapshot? lastTransactionDoc,
    required String cacheKey,
  }) async {
    try {
      Query<Map<String, dynamic>> query = firestore.collectionGroup('items');

      if (isSold) {
        query = query
            .where('sellerId', isEqualTo: userId)
            .where('shopId', isNull: true);
      } else {
        query = query.where('buyerId', isEqualTo: userId);
      }

      query = query.orderBy('timestamp', descending: true);

      if (lastTransactionDoc != null) {
        query = query.startAfterDocument(lastTransactionDoc);
      }

      query = query.limit(pageSize);

      final snapshot = await query.get();

      final transactions = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'data': doc.data(),
              })
          .where((tx) {
        final ts =
            (tx['data'] as Map<String, dynamic>)['timestamp'] as Timestamp?;
        return matchesSelectedDateRange(ts);
      }).toList();

      // Cache the results
      final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _transactionCache[cacheKey] = _CachedTransactionPage(
        transactions: transactions,
        lastDoc: lastDoc,
        cachedAt: DateTime.now(),
      );

      // Fetch products for this page
      final productIds = transactions
          .map((tx) =>
              (tx['data'] as Map<String, dynamic>)['productId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();

      if (productIds.isNotEmpty) {
        // Fire and forget - update cache in background
        unawaited(_fetchAndCacheProducts(firestore, productIds));
      }

      return {
        'transactions': transactions,
        'lastDoc': lastDoc,
      };
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      return {
        'transactions': <Map<String, dynamic>>[],
        'lastDoc': null,
      };
    }
  }

  Future<Map<String, Product>> fetchProducts(
    FirebaseFirestore firestore,
    Set<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};

    final cacheKey = productIds.join(',');

    // Check pending requests
    if (_pendingProductRequests.containsKey(cacheKey)) {
      return await _pendingProductRequests[cacheKey]!;
    }

    // Check cache
    final result = <String, Product>{};
    final missingIds = <String>{};

    for (final id in productIds) {
      final cached = _productCache[id];
      if (cached != null && !_isCacheExpired(cached.cachedAt)) {
        result[id] = cached.product;
      } else {
        missingIds.add(id);
      }
    }

    if (missingIds.isEmpty) {
      return result;
    }

    // Fetch missing products
    final future = _fetchProductsFromFirestore(firestore, missingIds, result);
    _pendingProductRequests[cacheKey] = future;

    try {
      return await future;
    } finally {
      _pendingProductRequests.remove(cacheKey);
    }
  }

  Future<Map<String, Product>> _fetchProductsFromFirestore(
    FirebaseFirestore firestore,
    Set<String> productIds,
    Map<String, Product> existingResults,
  ) async {
    try {
      final result = Map<String, Product>.from(existingResults);
      final ids = productIds.toList();

      // Batch requests to avoid overwhelming Firestore
      for (int i = 0; i < ids.length; i += _batchSize) {
        final end = (i + _batchSize > ids.length) ? ids.length : i + _batchSize;
        final batchIds = ids.sublist(i, end);

        try {
          final snapshot = await firestore
              .collection('products')
              .where(FieldPath.documentId, whereIn: batchIds)
              .get();

          for (final doc in snapshot.docs) {
            final product = Product.fromDocument(doc);
            result[product.id] = product;

            // Update cache
            _productCache[product.id] = _CachedProduct(product, DateTime.now());
          }
        } catch (e) {
          debugPrint('Error fetching product batch: $e');
        }
      }

      _enforceCacheSizeLimit();
      return result;
    } catch (e) {
      debugPrint('Error in fetchProducts: $e');
      return existingResults;
    }
  }

  Future<void> _fetchAndCacheProducts(
    FirebaseFirestore firestore,
    Set<String> productIds,
  ) async {
    await fetchProducts(firestore, productIds);
  }

  Future<Map<String, Product>> fetchShopProducts(
    FirebaseFirestore firestore,
    Set<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};

    final result = <String, Product>{};
    final missingIds = <String>{};

    // Check cache first
    for (final id in productIds) {
      final cached = _productCache[id];
      if (cached != null && !_isCacheExpired(cached.cachedAt)) {
        result[id] = cached.product;
      } else {
        missingIds.add(id);
      }
    }

    if (missingIds.isEmpty) return result;

    try {
      final ids = missingIds.toList();

      for (int i = 0; i < ids.length; i += _batchSize) {
        final end = (i + _batchSize > ids.length) ? ids.length : i + _batchSize;
        final batchIds = ids.sublist(i, end);

        try {
          final snapshot = await firestore
              .collection('shop_products')
              .where(FieldPath.documentId, whereIn: batchIds)
              .get();

          for (final doc in snapshot.docs) {
            final product = Product.fromDocument(doc);
            result[product.id] = product;

            // Update cache
            _productCache[product.id] = _CachedProduct(product, DateTime.now());
          }
        } catch (e) {
          debugPrint('Error fetching shop product batch: $e');
        }
      }

      _enforceCacheSizeLimit();
      return result;
    } catch (e) {
      debugPrint('Error in fetchShopProducts: $e');
      return result;
    }
  }

  String _buildTransactionCacheKey(
      String userId, bool isSold, String? lastDocId) {
    final dateRangeKey = selectedDateRange != null
        ? '${selectedDateRange!.start.millisecondsSinceEpoch}_${selectedDateRange!.end.millisecondsSinceEpoch}'
        : 'no_date_filter';
    return '${userId}_${isSold}_${lastDocId ?? 'first_page'}_$dateRangeKey';
  }

  bool _isCacheExpired(DateTime cachedAt) {
    return DateTime.now().difference(cachedAt) > _cacheExpiryDuration;
  }

  void clearCache() {
    _productCache.clear();
    _transactionCache.clear();
    _lastSyncTimes.clear();
    _pendingTransactionRequests.clear();
    _pendingProductRequests.clear();
  }

  void clearTransactionCache() {
    _transactionCache.clear();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cacheCleanupTimer?.cancel();
    clearCache();
    super.dispose();
  }
}

// Helper classes for caching
class _CachedProduct {
  final Product product;
  final DateTime cachedAt;

  _CachedProduct(this.product, this.cachedAt);
}

class _CachedTransactionPage {
  final List<Map<String, dynamic>> transactions;
  final DocumentSnapshot? lastDoc;
  final DateTime cachedAt;

  _CachedTransactionPage({
    required this.transactions,
    required this.lastDoc,
    required this.cachedAt,
  });
}

// Extension for unawaited futures
extension UnawaiteExtension on Future {
  void get unawaited => null;
}
