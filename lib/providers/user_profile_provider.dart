import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/product_summary.dart';

class UserProfileProvider with ChangeNotifier {
  static const int _productsPageSize = 20;
  static const int _maxProductsLimit = 100;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  // User data
  Map<String, dynamic>? _userData;
  String? _currentUserId;

  // Products with pagination
  List<ProductSummary> _products = [];
  DocumentSnapshot? _lastProductDocument;
  bool _hasMoreProducts = true;

  // Loading states
  bool _isInitializing = true;
  bool _isLoadingProducts = false;
  bool _isLoadingMore = false;

  // Follow state
  bool _isFollowing = false;

  // Search
  String _searchQuery = '';

  // Stats
  double _averageRating = 0.0;
  int _reviewCount = 0;
  int _sellerTotalProductsSold = 0;

  // Error handling
  String? _error;

  UserProfileProvider(this._firebaseAuth, this._firestore);

  // Getters
  Map<String, dynamic>? get userData => _userData;
  List<ProductSummary> get products => _filteredProducts;
  bool get isLoading => _isInitializing || _isLoadingProducts;
  bool get isLoadingMore => _isLoadingMore;
  bool get isFollowing => _isFollowing;
  String get searchQuery => _searchQuery;
  double get averageRating => _averageRating;
  int get reviewCount => _reviewCount;
  int get sellerTotalProductsSold => _sellerTotalProductsSold;
  bool get isCurrentUser => _firebaseAuth.currentUser?.uid == _currentUserId;
  bool get hasMoreProducts => _hasMoreProducts;
  String? get error => _error;

  List<ProductSummary> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    return _products.where((product) {
      final name = product.productName.toLowerCase();
      final brand = product.brandModel?.toLowerCase() ?? '';
      return name.contains(_searchQuery) || brand.contains(_searchQuery);
    }).toList();
  }

  /// Initialize the provider with a user ID
  Future<void> initialize(String userId) async {
    _isInitializing = true;
    _error = null;
    _currentUserId = userId;
    _products.clear();
    _lastProductDocument = null;
    _hasMoreProducts = true;
    notifyListeners();

    try {
      // Fetch all initial data in parallel
      await Future.wait([
        _fetchUserData(userId),
        _fetchReviews(userId),
        _fetchSellerTotalProductsSold(userId),
      ], eagerError: true);

      // Check following status if not current user
      if (!isCurrentUser) {
        await _checkIfFollowing(userId);
        // ❌ DELETE: _listenToFollowingStatus(userId);
      }

      // ❌ DELETE: _listenToUserData(userId);

      // Fetch initial products with pagination
      await _fetchProducts(userId);

      _isInitializing = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing user profile: $e');
      _error = 'Failed to load user profile';
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Fetch user data once
  Future<void> _fetchUserData(String userId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        _userData = userDoc.data() as Map<String, dynamic>?;
        if (_userData != null) {
          _userData!['uid'] = userId;
        }
      } else {
        _error = 'User not found';
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      throw Exception('Failed to fetch user data');
    }
  }

  /// Fetch reviews with error handling
  Future<void> _fetchReviews(String userId) async {
    try {
      QuerySnapshot reviewsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('reviews')
          .get();

      int count = reviewsSnapshot.docs.length;
      double totalRating = 0.0;

      for (var doc in reviewsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        totalRating += _parseDouble(data?['rating']);
      }

      _reviewCount = count;
      _averageRating = count > 0 ? totalRating / count : 0.0;
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
      _reviewCount = 0;
      _averageRating = 0.0;
    }
  }

  /// Fetch total products sold
  Future<void> _fetchSellerTotalProductsSold(String userId) async {
    try {
      DocumentSnapshot sellerDoc =
          await _firestore.collection('users').doc(userId).get();
      final data = sellerDoc.data() as Map<String, dynamic>?;
      _sellerTotalProductsSold = _parseInt(data?['totalProductsSold']);
    } catch (e) {
      debugPrint('Error fetching total products sold: $e');
      _sellerTotalProductsSold = 0;
    }
  }

  /// Check if current user is following this profile
  Future<void> _checkIfFollowing(String userId) async {
    User? currentUser = _firebaseAuth.currentUser;
    if (currentUser == null || userId == currentUser.uid) return;

    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('following')
          .doc(userId)
          .get();
      _isFollowing = doc.exists;
    } catch (e) {
      debugPrint('Error checking if following: $e');
      _isFollowing = false;
    }
  }

  /// Fetch products with pagination (initial load)
  Future<void> _fetchProducts(String userId) async {
    if (_isLoadingProducts) return;

    _isLoadingProducts = true;
    _error = null;
    notifyListeners();

    try {
      Query query = _firestore
          .collection('products')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(_productsPageSize);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        _hasMoreProducts = false;
      } else {
        _lastProductDocument = snapshot.docs.last;

        final newProducts = snapshot.docs
            .map((doc) {
              try {
                return ProductSummary.fromDocument(doc);
              } catch (e) {
                debugPrint('Error parsing product ${doc.id}: $e');
                return null;
              }
            })
            .whereType<ProductSummary>()
            .toList();

        _products = newProducts;

        if (snapshot.docs.length < _productsPageSize) {
          _hasMoreProducts = false;
        }
      }

      _isLoadingProducts = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching products: $e');
      _error = 'Failed to load products';
      _isLoadingProducts = false;
      _hasMoreProducts = false;
      notifyListeners();
    }
  }

  /// Load more products (pagination)
  Future<void> loadMoreProducts() async {
    if (_isLoadingMore || !_hasMoreProducts || _currentUserId == null) return;
    if (_products.length >= _maxProductsLimit) {
      _hasMoreProducts = false;
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      Query query = _firestore
          .collection('products')
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('createdAt', descending: true)
          .limit(_productsPageSize);

      if (_lastProductDocument != null) {
        query = query.startAfterDocument(_lastProductDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        _hasMoreProducts = false;
      } else {
        _lastProductDocument = snapshot.docs.last;

        final newProducts = snapshot.docs
            .map((doc) {
              try {
                return ProductSummary.fromDocument(doc);
              } catch (e) {
                debugPrint('Error parsing product ${doc.id}: $e');
                return null;
              }
            })
            .whereType<ProductSummary>()
            .toList();

        _products.addAll(newProducts);

        if (snapshot.docs.length < _productsPageSize) {
          _hasMoreProducts = false;
        }
      }
    } catch (e) {
      debugPrint('Error loading more products: $e');
      _error = 'Failed to load more products';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Set search query for filtering products
  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase().trim();
    notifyListeners();
  }

  /// Clear search query
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  /// Toggle following status
  Future<void> toggleFollowing(String userId) async {
    User? currentUser = _firebaseAuth.currentUser;
    if (currentUser == null || userId == currentUser.uid) return;

    final previousState = _isFollowing;
    _isFollowing = !_isFollowing; // Optimistic update
    notifyListeners();

    try {
      final ref = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('following')
          .doc(userId);

      if (previousState) {
        await ref.delete();
      } else {
        await ref.set({
          'followedUserId': userId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error updating following: $e');
      _isFollowing = previousState; // Revert on error
      _error = 'Failed to update follow status';
      notifyListeners();
    }
  }

  /// Refresh all data
  Future<void> refresh() async {
    if (_currentUserId == null) return;

    _error = null;
    _products.clear();
    _lastProductDocument = null;
    _hasMoreProducts = true;

    await initialize(_currentUserId!);
  }

  /// Helper method to safely parse int
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Helper method to safely parse double
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void dispose() {
    super.dispose();
  }
}
