import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product_summary.dart';

class TerasProductListProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Products state
  List<ProductSummary> _products = [];

  List<ProductSummary> get products => _products;

  // Pagination state
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 20;
  static const int _maxPages = 10;

  bool _isDisposed = false; 

  bool get hasMore => _hasMore && _currentPage < _maxPages;
  bool get isLoadingMore => _isLoadingMore;
  bool get isEmpty => _products.isEmpty;

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
           _products.isNotEmpty &&
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
    _lastDocument = null;
    _currentPage = 0;
    _hasMore = true;
    _cacheTimestamp = null;
    _isInitialized = false;

    _safeNotifyListeners();

    try {
      await _fetchProducts();

      if (_isDisposed) return;

      _isInitialized = true;
      _setCacheTimestamp();

      debugPrint('✅ Teras products loaded: ${_products.length} products');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Fetch products with pagination (promotionScore handles boosted ordering)
  Future<void> _fetchProducts() async {
    if (_isLoadingMore || _isDisposed) return;

    _isLoadingMore = true;
    _safeNotifyListeners();

    try {
      Query query = _firestore
          .collection('products')
          .orderBy('promotionScore', descending: true)
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (_isDisposed) return;

      if (snapshot.docs.isEmpty) {
        _hasMore = false;
      } else {
        final newProducts = snapshot.docs
            .map((doc) => ProductSummary.fromDocument(doc))
            .toList();

        _products.addAll(newProducts);
        _lastDocument = snapshot.docs.last;
        _currentPage++;
        _hasMore = snapshot.docs.length == _pageSize;

        debugPrint('Fetched page $_currentPage: ${newProducts.length} products');
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
    _cacheTimestamp = null;
    _isInitialized = false;
    _safeNotifyListeners();  // ✅ CHANGE
  });
}

}