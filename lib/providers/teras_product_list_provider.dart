import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';

class TerasProductListProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Products state
  List<Product> _products = [];
  List<Product> _boostedProducts = [];

  List<Product> get products => _products;
  List<Product> get boostedProducts => _boostedProducts;

  // Pagination state
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  bool _isFetchingBoosted = false;
  static const int _pageSize = 20;
  static const int _maxPages = 10;

  bool _isDisposed = false; 

  bool get hasMore => _hasMore && _currentPage < _maxPages;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _products.isEmpty && _boostedProducts.isEmpty;

  // ✅ ENHANCED: Cache state with better validation
  DateTime? _cacheTimestamp;
  Timer? _cacheTimer;
  static const Duration _cacheDuration = Duration(minutes: 20);
  bool _isInitialized = false; // ✅ ADD: Track initialization state
  bool get isInitialized => _isInitialized; // Expose initialization state

  bool _isRefreshing = false;

  bool get isCacheValid {
    if (_cacheTimestamp == null || !_isInitialized) return false;
    return DateTime.now().difference(_cacheTimestamp!) < _cacheDuration;
  }

  // ✅ ADD: Check if we have usable cached data
  bool get hasCachedData {
    return _isInitialized && 
           (_products.isNotEmpty || _boostedProducts.isNotEmpty) &&
           isCacheValid;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cacheTimer?.cancel();
    super.dispose();
  }

   void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// ✅ ENHANCED: Initialize with proper cache checking
  Future<void> initialize() async {
    // ✅ CHECK: If we have valid cache, skip loading
    if (hasCachedData) {
      debugPrint('✅ Using cached Teras products (${_products.length} items)');
      return;
    }

    debugPrint('🔄 Loading fresh Teras products...');
    await _resetAndFetch();
  }

  /// Refresh the list (pull-to-refresh)
  Future<void> refresh() async {
    await _resetAndFetch();
  }

  /// Reset state and fetch first page
  Future<void> _resetAndFetch() async {
    if (_isRefreshing || _isDisposed) return; 

    _isRefreshing = true;

    _products.clear();
    _boostedProducts.clear();
    _lastDocument = null;
    _currentPage = 0;
    _hasMore = true;
    _cacheTimestamp = null;
    _isInitialized = false; // ✅ RESET initialization flag

    _safeNotifyListeners();

    try {
      await Future.wait([
        _fetchBoostedProducts(),
        _fetchProducts(),
      ]);

       if (_isDisposed) return;

      _isInitialized = true; // ✅ MARK: Successfully initialized
      _setCacheTimestamp();
      
      debugPrint('✅ Teras products loaded: ${_products.length} regular, ${_boostedProducts.length} boosted');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Fetch boosted products (promotionScore > 1000)
  Future<void> _fetchBoostedProducts() async {
    if (_isFetchingBoosted || _isDisposed) return;
    _isFetchingBoosted = true;
    try {
      final query = _firestore
          .collection('products')
          .where('promotionScore', isGreaterThan: 1000)
          .where('quantity', isGreaterThan: 0)
          .orderBy('promotionScore', descending: true)
          .orderBy('createdAt', descending: true)
          .limit(10);

      final snapshot = await query.get();

      if (_isDisposed) return;

      _boostedProducts =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

      debugPrint('Fetched ${_boostedProducts.length} boosted products');
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('Error fetching boosted products: $e');
    } finally {
      _isFetchingBoosted = false;
    }
  }

  /// Fetch regular products with pagination
  Future<void> _fetchProducts() async {
    if (_isLoadingMore || _isDisposed) return;

    _isLoadingMore = true;
    _safeNotifyListeners();

    try {
      Query query = _firestore
          .collection('products')
          .where('quantity', isGreaterThan: 0)
          .orderBy('quantity')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (_isDisposed) return;

      if (snapshot.docs.isEmpty) {
        _hasMore = false;
      } else {
        final newProducts =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        // Filter out boosted products to avoid duplicates
        final boostedIds = _boostedProducts.map((p) => p.id).toSet();
        final filteredProducts =
            newProducts.where((p) => !boostedIds.contains(p.id)).toList();

        _products.addAll(filteredProducts);
        _lastDocument = snapshot.docs.last;
        _currentPage++;
        _hasMore = snapshot.docs.length == _pageSize;

        debugPrint(
            'Fetched page $_currentPage: ${filteredProducts.length} products');
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
      _hasMore = false;
    } finally {
      _isLoadingMore = false;
     _safeNotifyListeners();
    }
  }

  /// Load more products (infinite scroll)
  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore) return;

    debugPrint('Loading more products...');
    await _fetchProducts();
  }

  /// ✅ ENHANCED: Set cache timestamp with better lifecycle management
 void _setCacheTimestamp() {
  _cacheTimestamp = DateTime.now();

  _cacheTimer?.cancel();

  _cacheTimer = Timer(_cacheDuration, () {
    if (_isDisposed) return;  // ✅ ADD: Check before timer callback executes
    
    debugPrint('⏰ Teras cache expired, clearing products');
    _products.clear();
    _boostedProducts.clear();
    _cacheTimestamp = null;
    _isInitialized = false;
    _safeNotifyListeners();  // ✅ CHANGE
  });
}

  /// Get combined products list (boosted first, then regular)
  List<Product> getCombinedProducts() {
    return [..._boostedProducts, ..._products];
  }
}