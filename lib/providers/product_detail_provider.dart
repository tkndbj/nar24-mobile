// lib/providers/product_detail_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/debouncer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Nar24/providers/product_repository.dart';
import 'package:Nar24/services/related_products_service.dart';
import 'dart:convert';
import 'package:Nar24/utils/memory_manager.dart';

class ProductDetailProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _productCollection;
  final Product? initialProduct;
  Product? _product;
  List<Product> _related = [];
  bool _loadingRelated = false;
  bool _relatedLoadingInitiated = false; // ✅ Track if loading has been triggered
  bool _isDisposed = false;
  bool _collectionDetermined = false;
  bool get isLoadingRelated => _loadingRelated;

  static const int _maxQuestionsCacheSize = 50;
  static final Map<String, List<Map<String, dynamic>>> _questionsCache = {};
  static final Map<String, DateTime> _questionsCacheTimestamps = {};
  static final Map<String, Timer> _questionsDebounceTimers = {};
  static const Duration _questionsCacheTTL = Duration(minutes: 10);

  static const int _maxReviewsCacheSize = 100;
  static final Map<String, List<Map<String, dynamic>>> _reviewsCache = {};
  static final Map<String, DateTime> _reviewsCacheTimestamps = {};
  static final Map<String, Timer> _reviewsDebounceTimers = {};
  static const Duration _reviewsCacheTTL = Duration(minutes: 10);
  static final Map<String, Future<DocumentSnapshot>> _pendingFetches = {};

  /// Exposes product collection name once determined.
  /// Widgets can use this to create their own streams/queries directly.
  String? get productCollection => _productCollection;

  /// Check if collection has been determined (needed for async initialization)
  bool get collectionDetermined => _collectionDetermined;

  // ✅ FIXED: Add cache size limit to prevent unbounded memory growth
  static const int _maxRelatedCacheSize = 50; // BU VE BU
  static final Map<String, List<Product>> _relatedCache = {}; // ✅ Shared
  static final List<String> _relatedCacheKeys = [];
  List<Product> get relatedProducts => _related;

  // Subscription for product data snapshots
  StreamSubscription<DocumentSnapshot>? _productSubscription;
  FirebaseFirestore get firestore => _firestore;

  double _userRating = 0.0;
  bool _isInCart = false;
  bool _isFavorite = false;
  bool _isSubmittingReview = false;

  String? _currentShopId;
  String? get currentShopId => _currentShopId;

  String? _selectedSize;
  String? get selectedSize => _selectedSize;

  // Additional state variables
  int _currentImageIndex = 0;
  double? _discountedPrice;
  int? _discountPercentage;
  int sellerTotalProductsSold = 0;
  String _sellerName = '';
  double _sellerAverageRating = 0.0;
  int _sellerTotalReviews = 0;

  // For handling product details
  final String productId;
  final ProductRepository repository;

  // Controllers and keys
  final TextEditingController reviewController = TextEditingController();

  final Debouncer _notifyDebouncer =
      Debouncer(delay: Duration(milliseconds: 300));

  // For review image
  File? _reviewImageFile;
  File? get reviewImageFile => _reviewImageFile;

  final List<File> _reviewImages = [];
  List<File> get reviewImages => _reviewImages;

  // **New State Variable for Selected Color**
  String? _selectedColor;
  String? get selectedColor => _selectedColor;

  // **New Variable for Seller's Cargo Agreement Data**
  Map<String, dynamic>? _sellerCargoAgreement;
  Map<String, dynamic>? get sellerCargoAgreement => _sellerCargoAgreement;

  static DateTime? _lastNavigationTime;
  static const _navThrottle = Duration(milliseconds: 500);

  double _shopAverageRating = 0.0;
  double get shopAverageRating => _shopAverageRating;

  bool _isSellerInfoLoading = true;
  bool get isSellerInfoLoading => _isSellerInfoLoading;

  // *** NEW: Store seller verified status ***
  bool _sellerVerified = false;
  bool get sellerIsVerified => _sellerVerified;

  DateTime? _lastSellerInfoFetch;
  static int _navigationCount = 0;
  // ✅ PROVEN: Clear caches every 7 navigations (balanced approach)
  static const int _maxNavigationsBeforeClear = 15;

  // ✅ FIXED: Cache TTL for SharedPreferences cleanup
  static const Duration _sellerCacheTTL = Duration(hours: 1);

  ProductDetailProvider({
    required this.productId,
    required this.repository,
    this.initialProduct,
  }) {
    if (productId.trim().isEmpty) {
      throw ArgumentError('ProductId cannot be empty');
    }

    _navigationCount++;
    if (_navigationCount > _maxNavigationsBeforeClear) {
      clearAllStaticCaches();
      _navigationCount = 0;

      // ADD THIS: Also check memory on navigation
      MemoryManager().checkAndClearIfNeeded();
    }

    if (initialProduct != null) {
      _product = initialProduct;
      // Determine collection based on shopId RIGHT AWAY
      _productCollection = (initialProduct!.shopId?.isNotEmpty == true)
          ? 'shop_products'
          : 'products';
      _collectionDetermined = true; // ← Set this immediately too
      _safeNotifyListeners();
    }

    _initializeProvider();
    unawaited(_cleanupOldSellerCache());
  }

  static void clearAllStaticCaches() {
    _questionsCache.clear();
    _reviewsCache.clear();
    _questionsCacheTimestamps.clear();
    _reviewsCacheTimestamps.clear();
    _questionsDebounceTimers.values.forEach((t) => t.cancel());
    _questionsDebounceTimers.clear();
    _reviewsDebounceTimers.values.forEach((t) => t.cancel());
    _reviewsDebounceTimers.clear();
    _relatedCache.clear();
    _relatedCacheKeys.clear();
    _pendingFetches.clear();
  }

  /// **CRITICAL FIX**: Safe initialization with error handling
  Future<void> _initializeProvider() async {
    try {
      await _fetchProductData();
      await _checkIfInCart();
      await _checkIfFavorite();
      // ✅ LAZY LOADING: Related products will load when widget is visible
      // Removed automatic call to _computeRelatedOnClient()
    } catch (e, stackTrace) {
      debugPrint('Error initializing ProductDetailProvider: $e');
      debugPrint('Stack trace: $stackTrace');
      // Set error state but don't crash
      _product = initialProduct; // Fall back to initial product if available
      _safeNotifyListeners();
    }
  }

  /// **CRITICAL FIX**: Safe notification that checks disposal state
  void _safeNotifyListeners() {
    if (!_isDisposed && hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _productSubscription?.cancel();
    _productSubscription = null;
    reviewController.dispose();
    _questionsDebounceTimers.values.forEach((t) => t.cancel());
    _reviewsDebounceTimers.values.forEach((t) => t.cancel());
    // ✅ REMOVE the current product from cache when leaving the screen
    _relatedCache.remove(productId);
    _relatedCacheKeys.remove(productId);

    for (final timer in _questionsDebounceTimers.values) {
      timer.cancel();
    }

    for (final timer in _reviewsDebounceTimers.values) {
      timer.cancel();
    }

    _notifyDebouncer.cancel();
    super.dispose();
  }

  // Getters with null safety
  Product? get product => _product;
  double get userRating => _userRating;
  bool get isInCart => _isInCart;
  bool get isFavorite => _isFavorite;
  bool get isSubmittingReview => _isSubmittingReview;
  double get sellerAverageRating => _sellerAverageRating;
  int get sellerTotalReviews => _sellerTotalReviews;
  String get sellerName => _sellerName;
  double? get discountedPrice => _discountedPrice;
  int? get discountPercentage => _discountPercentage;
  int get currentImageIndex => _currentImageIndex;
  String? get selectedColorState => _selectedColor;

  // **CRITICAL FIX**: Safe image URLs getter
  List<String> get currentImageUrls {
    if (_product == null) return [];

    if (_selectedColor != null &&
        _product!.colorImages[_selectedColor!] != null &&
        _product!.colorImages[_selectedColor!]!.isNotEmpty) {
      return _product!.colorImages[_selectedColor!]!;
    }
    return _product?.imageUrls ?? [];
  }

  // Setters for internal state with safety checks
  void setUserRating(double rating) {
    if (_isDisposed) return;
    if (_userRating != rating) {
      _userRating = rating;
      _safeNotifyListeners();
    }
  }

  void setCurrentImageIndex(int index) {
    if (_isDisposed || _product == null) return;

    final maxIndex = _selectedColor != null
        ? (_product!.colorImages[_selectedColor!]?.length ?? 0) - 1
        : (_product!.imageUrls.length - 1);

    if (index >= 0 && index <= maxIndex && _currentImageIndex != index) {
      _currentImageIndex = index;
      _safeNotifyListeners();
    }
  }

  // **CRITICAL FIX**: Safe color selection
  void toggleColorSelection(String color) {
    if (_isDisposed || _product == null) return;

    if (_selectedColor != color) {
      _selectedColor = color;
      _currentImageIndex = 0; // Reset image index when color changes
      _safeNotifyListeners();
    } else {
      _selectedColor = null;
      _currentImageIndex = 0; // Reset to default image index
      _safeNotifyListeners();
    }
  }

  void toggleSizeSelection(String size) {
    if (_isDisposed) return;

    print('Toggling size selection: $size');
    if (_selectedSize != size) {
      _selectedSize = size;
      print('Size selected: $_selectedSize');
    } else {
      _selectedSize = null;
      print('Size deselected: $_selectedSize');
    }
    _safeNotifyListeners();
  }

  Future<DocumentSnapshot> _fetchWithDedup(String docPath) {
    if (_pendingFetches.containsKey(docPath)) {
      return _pendingFetches[docPath]!;
    }

    final future = _firestore.doc(docPath).get();
    _pendingFetches[docPath] = future;

    future.whenComplete(() => _pendingFetches.remove(docPath));
    return future;
  }

  Future<void> _fetchSellerAndShopInfo() async {
    if (_isDisposed || _product == null) return;

    final sellerId = _product!.userId;
    final shopId = _product!.shopId;

    // ✅ Load cache asynchronously WITHOUT blocking
    _loadSellerInfoFromCache(sellerId).then((_) {
      if (!_isDisposed) _safeNotifyListeners();
    });

    _isSellerInfoLoading = true;
    _safeNotifyListeners(); // Don't wait for cache

    // Check cache freshness...
    if (_lastSellerInfoFetch != null &&
        DateTime.now().difference(_lastSellerInfoFetch!) <
            const Duration(minutes: 5)) {
      _isSellerInfoLoading = false;
      _safeNotifyListeners();
      return;
    }

    try {
      // ✅ OPTIMIZATION: Batch necessary reads only
      final futures = <Future<dynamic>>[
        // 0: Seller document (single fetch)
        _fetchWithDedup('users/$sellerId'),

        // 1: Shop document (if shopId exists)
        if (shopId != null && shopId.isNotEmpty)
          _firestore.collection('shops').doc(shopId).get()
        else
          Future.value(null),
      ];

      final results = await Future.wait(futures);
      final sellerDoc = results[0] as DocumentSnapshot;
      final shopDoc = results[1] as DocumentSnapshot?;

      if (_isDisposed) return;

      if (sellerDoc.exists) {
        final data = sellerDoc.data() as Map<String, dynamic>?;

        _sellerName = data?['displayName'] ?? 'Unknown Seller';
        _sellerVerified = data?['verified'] == true;
        _sellerCargoAgreement = data?['cargoAgreement'];
        sellerTotalProductsSold = data?['totalProductsSold']?.toInt() ?? 0;

        // ✅ Read averageRating from denormalized data in user document
        _sellerAverageRating =
            (data?['averageRating'] as num?)?.toDouble() ?? 0.0;
        _sellerTotalReviews = (data?['totalReviews'] as num?)?.toInt() ?? 0;
      } else {
        // Fallback values
        _sellerName = 'Unknown Seller';
        _sellerVerified = false;
        _sellerAverageRating = 0.0;
        _sellerTotalReviews = 0;
        _sellerCargoAgreement = null;
        sellerTotalProductsSold = 0;
      }

      if (shopDoc != null && shopDoc.exists) {
        _currentShopId = shopId;
        final shopData = shopDoc.data() as Map<String, dynamic>;
        _shopAverageRating =
            (shopData['averageRating'] as num?)?.toDouble() ?? 0.0;
      } else if (shopId == null || shopId.isEmpty) {
        // ✅ Only query for shop if shopId is null
        // Use cached query result if available
        final shopSnapshot = await _firestore
            .collection('shops')
            .where('ownerId', isEqualTo: sellerId)
            .limit(1)
            .get(const GetOptions(source: Source.cache)) // Try cache first
            .catchError((_) => _firestore
                .collection('shops')
                .where('ownerId', isEqualTo: sellerId)
                .limit(1)
                .get()); // Fallback to server

        if (_isDisposed) return;

        if (shopSnapshot.docs.isNotEmpty) {
          _currentShopId = shopSnapshot.docs.first.id;
          final shopData = shopSnapshot.docs.first.data();
          _shopAverageRating =
              (shopData['averageRating'] as num?)?.toDouble() ?? 0.0;
        } else {
          _currentShopId = null;
          _shopAverageRating = 0.0;
        }
      } else {
        _currentShopId = null;
        _shopAverageRating = 0.0;
      }

      // Save to cache
      unawaited(_saveSellerInfoToCache(sellerId));
      _lastSellerInfoFetch = DateTime.now();
    } on FirebaseException catch (e) {
      // ✅ Better error handling for Firebase-specific errors
      debugPrint(
          'Firebase error fetching seller/shop info: ${e.code} - ${e.message}');

      // Don't clear cached data on error - keep showing stale data
      if (e.code == 'unavailable') {
        debugPrint('Network unavailable - using cached seller info');
      }
    } catch (e, stackTrace) {
      // ✅ Log stack trace for debugging
      debugPrint('Error fetching seller/shop info: $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      if (!_isDisposed) {
        _isSellerInfoLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  User? get currentUser => _auth.currentUser;

  Future<void> _fetchProductData() async {
  final now = DateTime.now();
  if (_lastNavigationTime != null &&
      now.difference(_lastNavigationTime!) < _navThrottle) {
    return; // Skip if navigating too fast
  }
  _lastNavigationTime = now;
  if (_isDisposed || productId.trim().isEmpty) return;

  try {
    // ✅ OPTIMIZED: Fetch both collections in parallel
    final results = await Future.wait([
      _firestore.collection('products').doc(productId).get()
          .timeout(const Duration(seconds: 10)),
      _firestore.collection('shop_products').doc(productId).get()
          .timeout(const Duration(seconds: 10)),
    ]);

    final prodSnap = results[0];
    final shopSnap = results[1];

    // Check which collection has the product
    if (prodSnap.exists) {
      _productCollection = 'products';
      _product = Product.fromDocument(prodSnap);
    } else if (shopSnap.exists) {
      _productCollection = 'shop_products';
      _product = Product.fromDocument(shopSnap);
    } else {
      throw Exception('Product not found in any collection');
    }

    _collectionDetermined = true;
    _safeNotifyListeners();

    if (_isDisposed) return;

    // ✅ Fetch seller info once
    await _fetchSellerAndShopInfo();
    // ✅ LAZY LOADING: Related products will load when widget is visible
    // Removed automatic call to _computeRelatedOnClient()
  } catch (e) {
    debugPrint('Error fetching product data: $e');
    if (!_isDisposed) {
      _safeNotifyListeners();
    }
  }
}

  Future<void> _loadSellerInfoFromCache(String sellerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sellerName = prefs.getString('sellerName_$sellerId') ?? _sellerName;
      _sellerAverageRating = prefs.getDouble('sellerAverageRating_$sellerId') ??
          _sellerAverageRating;
      _shopAverageRating =
          prefs.getDouble('shopAverageRating_$sellerId') ?? _shopAverageRating;
      _sellerVerified =
          prefs.getBool('sellerIsVerified_$sellerId') ?? _sellerVerified;
      _currentShopId = prefs.getString('shopId_$sellerId') ?? _currentShopId;
      sellerTotalProductsSold =
          prefs.getInt('sellerTotalProductsSold_$sellerId') ??
              sellerTotalProductsSold;
      _sellerTotalReviews =
          prefs.getInt('sellerTotalReviews_$sellerId') ?? _sellerTotalReviews;
      // Immediately update UI with cached values
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('Error loading seller info from cache: $e');
    }
  }

  Future<void> _saveSellerInfoToCache(String sellerId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'name': _sellerName,
      'avgRating': _sellerAverageRating,
      'shopRating': _shopAverageRating,
      'verified': _sellerVerified,
      'shopId': _currentShopId,
      'totalSold': sellerTotalProductsSold,
      'totalReviews': _sellerTotalReviews,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString('seller_$sellerId', jsonEncode(data));
  }

  /// ✅ FIXED: Cleanup old seller cache entries to prevent unbounded storage growth
  Future<void> _cleanupOldSellerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final now = DateTime.now();

      int removedCount = 0;
      for (final key in keys) {
        // Only process seller cache time keys
        if (key.startsWith('sellerCacheTime_')) {
          final timestamp = prefs.getInt(key);
          if (timestamp != null) {
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            final age = now.difference(cacheTime);

            // Remove if older than TTL
            if (age > _sellerCacheTTL) {
              final sellerId = key.replaceFirst('sellerCacheTime_', '');

              // Remove all associated seller data
              await prefs.remove('sellerName_$sellerId');
              await prefs.remove('sellerAverageRating_$sellerId');
              await prefs.remove('shopAverageRating_$sellerId');
              await prefs.remove('sellerIsVerified_$sellerId');
              await prefs.remove('shopId_$sellerId');
              await prefs.remove('sellerTotalProductsSold_$sellerId');
              await prefs.remove('sellerTotalReviews_$sellerId');
              await prefs.remove(key); // Remove timestamp itself

              removedCount++;
            }
          }
        }
      }

      if (removedCount > 0) {
        debugPrint('🧹 Cleaned up $removedCount old seller cache entries');
      }
    } catch (e) {
      debugPrint('Error cleaning up seller cache: $e');
    }
  }

  Future<void> toggleReviewLike(String reviewId, bool currentlyLiked) async {
    final userId = currentUser?.uid;
    if (userId == null || _productCollection == null || _isDisposed) return;

    final reviewRef = firestore
        .collection(_productCollection!)
        .doc(productId)
        .collection('reviews')
        .doc(reviewId);

    try {
      if (currentlyLiked) {
        await reviewRef.update({
          'likes': FieldValue.arrayRemove([userId])
        });
      } else {
        await reviewRef.update({
          'likes': FieldValue.arrayUnion([userId])
        });
      }
    } catch (e) {
      print('Error updating like: $e');
    }
  }

  void removeReviewImage(File imageFile) {
    if (_isDisposed) return;
    reviewImages.remove(imageFile);
    _safeNotifyListeners();
  }

  Future<void> fetchSellerTotalProductsSold(String sellerId) async {
    if (_isDisposed) return;

    try {
      DocumentSnapshot sellerDoc =
          await _firestore.collection('users').doc(sellerId).get();

      if (_isDisposed) return;

      if (sellerDoc.exists) {
        sellerTotalProductsSold = sellerDoc['totalProductsSold'] ?? 0;
        print('Total Products Sold for $sellerId: $sellerTotalProductsSold');
      } else {
        sellerTotalProductsSold = 0;
      }
      _safeNotifyListeners();
    } catch (e) {
      print('Error fetching total products sold: $e');
      sellerTotalProductsSold = 0;
      if (!_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// **CRITICAL FIX**: Safe product count initialization
  Future<void> initializeProductCounts(String productId) async {
    if (_isDisposed || productId.trim().isEmpty) return;

    try {
      final prodRef = _firestore.collection('products').doc(productId);
      final shopRef = _firestore.collection('shop_products').doc(productId);

      final prodSnap = await prodRef.get();
      final String collectionName =
          prodSnap.exists ? 'products' : 'shop_products';
      final DocumentReference<Map<String, dynamic>> productRef =
          _firestore.collection(collectionName).doc(productId);

      await productRef.set({
        'purchaseCount': 0,
        'clickCount': 0,
        'cartCount': 0,
        'favoritesCount': 0,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error initializing product counts: $e');
    }
  }

  Future<void> _checkIfInCart() async {
    final user = _auth.currentUser;
    if (user == null || _isDisposed) return;

    try {
      DocumentSnapshot cartItem = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .get();

      if (_isDisposed) return;

      final inCartStatus = cartItem.exists;
      if (_isInCart != inCartStatus) {
        _isInCart = inCartStatus;
        _safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking cart status: $e');
    }
  }

  Future<void> _checkIfFavorite() async {
    final user = _auth.currentUser;
    if (user == null || _isDisposed) return;

    try {
      DocumentSnapshot favoriteItem = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .doc(productId)
          .get();

      if (_isDisposed) return;

      final isFavoriteStatus = favoriteItem.exists;
      if (_isFavorite != isFavoriteStatus) {
        _isFavorite = isFavoriteStatus;
        _safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
    }
  }

  Future<void> buyItNow(BuildContext context) async {
    User? user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to buy product')),
      );
      return;
    }
  }

  /// Validates the basic structure of messageData before writing to Firestore.
  void _validateMessageData(Map<String, dynamic> messageData) {
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

  /// Replaces Firestore-invalid characters (., $, [, ]) with underscores.
  String _sanitizeFirestoreKey(String input) {
    return input
        .replaceAll('.', '_')
        .replaceAll(',', '_')
        .replaceAll('[', '_')
        .replaceAll(']', '_');
  }

  /// Only sends { productName, brandModel, productPrice, productImageUrls }
  /// to the chat, ignoring everything else.
  Future<void> shareProductMinimal(String contactId, Product product) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('No authenticated user found.');
      return;
    }

    // Sort participants
    final List<String> sortedParticipants = [currentUser.uid, contactId];
    sortedParticipants.sort();

    // Build a deterministic chatId from these 2 user IDs
    final chatId = '${sortedParticipants[0]}_${sortedParticipants[1]}';

    // Reference the doc directly
    final chatRef = _firestore.collection('chats').doc(chatId);

    try {
      // 1) See if that doc exists
      final chatSnap = await chatRef.get();

      // If not, create it
      if (!chatSnap.exists) {
        debugPrint('Creating new chat: $chatId');
        await chatRef.set({
          'participants': sortedParticipants,
          'visibleTo': sortedParticipants,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'unreadCounts': {
            _sanitizeFirestoreKey(sortedParticipants[0]): 0,
            _sanitizeFirestoreKey(sortedParticipants[1]): 0,
          },
          'lastReadTimestamps': {
            _sanitizeFirestoreKey(sortedParticipants[0]):
                FieldValue.serverTimestamp(),
            _sanitizeFirestoreKey(sortedParticipants[1]):
                FieldValue.serverTimestamp(),
          },
          'initiated': true,
        });
      } else {
        debugPrint('Using existing chat: $chatId');
      }

      // 2) Create the product message
      final messageRef = chatRef.collection('messages').doc();
      final messageData = {
        'senderId': currentUser.uid,
        'recipientId': contactId,
        'type': 'product',
        'content': {
          'productId': product.id,
          'productName': product.productName,
          'brandModel': product.brandModel,
          'productPrice': product.price,
          'productImageUrls': product.imageUrls,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      };

      // 3) Write message & update lastMessage in a transaction
      await _firestore.runTransaction((transaction) async {
        transaction.set(messageRef, messageData);
        transaction.update(chatRef, {
          'lastMessage': 'Shared a product',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'unreadCounts.${_sanitizeFirestoreKey(contactId)}':
              FieldValue.increment(1),
        });
      });
      debugPrint('Shared product to contact successfully.');
    } catch (e) {
      debugPrint('Error sharing product: $e');
    }
  }

  // **Method to Generate Dynamic Product URL**
  String _generateProductUrl(String productId) {
    return 'https://emlak-mobile-app.web.app/products/$productId';
  }

  // **New Method to Share Product via Other Applications**
  Future<void> shareProductViaOtherApps(
      BuildContext context, Product product) async {
    String productUrl = _generateProductUrl(product.id);

    String shareText = [
      product.productName,
      '${product.brandModel}',
      '${product.price}',
      product.description,
      productUrl,
    ].where((e) => e.isNotEmpty).join('\n');

    try {
      await Share.share(shareText);
    } catch (e) {
      print('Error sharing via other apps: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing product: $e')),
      );
    }
  }

  /// ✅ LAZY LOADING: Public method to load related products on-demand
  /// Called by ProductDetailRelatedProducts widget when it becomes visible
  Future<void> loadRelatedProductsIfNeeded() async {
    // Prevent duplicate loading if already initiated
    if (_relatedLoadingInitiated || _product == null || _isDisposed) return;

    _relatedLoadingInitiated = true;

    // Prevent concurrent loading attempts
    if (_loadingRelated) return;

    _loadingRelated = true;
    _safeNotifyListeners();

    try {
      _related = await RelatedProductsService.getRelatedProducts(_product!);

      // ✅ FIXED: Implement cache eviction to limit memory usage
      final cacheKey = _product!.id;
      if (!_relatedCacheKeys.contains(cacheKey)) {
        _relatedCacheKeys.add(cacheKey);
        _relatedCache[cacheKey] = _related;

        // Evict oldest entry if cache is full
        if (_relatedCacheKeys.length > _maxRelatedCacheSize) {
          final oldestKey = _relatedCacheKeys.removeAt(0);
          _relatedCache.remove(oldestKey);
        }
      }
    } catch (e) {
      debugPrint('Error computing related products: $e');
      _related = [];
    } finally {
      _loadingRelated = false;
      if (!_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  Future<List<Map<String, dynamic>>> getProductQuestions(
    String productId,
    String questionColl,
  ) async {
    final cacheKey = '${questionColl}_$productId';
    final now = DateTime.now();

    // Check cache first
    if (_questionsCache.containsKey(cacheKey) &&
        _questionsCacheTimestamps.containsKey(cacheKey)) {
      final cacheTime = _questionsCacheTimestamps[cacheKey]!;
      if (now.difference(cacheTime) < _questionsCacheTTL) {
        return _questionsCache[cacheKey]!;
      }
      _questionsCache.remove(cacheKey);
      _questionsCacheTimestamps.remove(cacheKey);
    }

    // Cancel previous timer
    _questionsDebounceTimers[cacheKey]?.cancel();

    final completer = Completer<List<Map<String, dynamic>>>();

    _questionsDebounceTimers[cacheKey] =
        Timer(const Duration(milliseconds: 300), () async {
      try {
        final snapshot = await _firestore
            .collection(questionColl)
            .doc(productId)
            .collection('product_questions')
            .where('productId', isEqualTo: productId)
            .where('answered', isEqualTo: true)
            .orderBy('timestamp', descending: true)
            .limit(5)
            .get();

        final questions = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['questionId'] = doc.id;
          return data;
        }).toList();

        // Store in cache
        _questionsCache[cacheKey] = questions;
        _questionsCacheTimestamps[cacheKey] = DateTime.now();

        // Evict oldest if full
        if (_questionsCache.length > _maxQuestionsCacheSize) {
          final sortedKeys = _questionsCacheTimestamps.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));

          final keysToRemove = sortedKeys
              .take(_questionsCache.length - _maxQuestionsCacheSize)
              .map((e) => e.key)
              .toList();

          for (final key in keysToRemove) {
            _questionsCache.remove(key);
            _questionsCacheTimestamps.remove(key);
            _questionsDebounceTimers[key]?.cancel();
            _questionsDebounceTimers.remove(key);
          }
        }

        if (!completer.isCompleted) {
          completer.complete(questions);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    return completer.future;
  }

  Future<List<Map<String, dynamic>>> getProductReviews(
    String productId,
    String collectionName,
  ) async {
    final now = DateTime.now();

    // Check cache first
    if (_reviewsCache.containsKey(productId) &&
        _reviewsCacheTimestamps.containsKey(productId)) {
      final cacheTime = _reviewsCacheTimestamps[productId]!;
      if (now.difference(cacheTime) < _reviewsCacheTTL) {
        return _reviewsCache[productId]!;
      }
      _reviewsCache.remove(productId);
      _reviewsCacheTimestamps.remove(productId);
    }

    // Cancel previous timer
    _reviewsDebounceTimers[productId]?.cancel();

    final completer = Completer<List<Map<String, dynamic>>>();

    _reviewsDebounceTimers[productId] =
        Timer(const Duration(milliseconds: 300), () async {
      try {
        final snapshot = await _firestore
            .collection(collectionName)
            .doc(productId)
            .collection('reviews')
            .orderBy('timestamp', descending: true)
            .limit(3)
            .get();

        final reviews = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['reviewId'] = doc.id;

          // ✅ FIX: Convert Timestamp to milliseconds for serialization
          if (data['timestamp'] is Timestamp) {
            data['timestamp'] = (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
          }

          return data;
        }).toList();

        // Store in cache
        _reviewsCache[productId] = reviews;
        _reviewsCacheTimestamps[productId] = DateTime.now();

        // Evict oldest if full
        if (_reviewsCache.length > _maxReviewsCacheSize) {
          final sortedEntries = _reviewsCacheTimestamps.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          final toRemove =
              sortedEntries.take(_reviewsCache.length - _maxReviewsCacheSize);

          for (final entry in toRemove) {
            _reviewsCache.remove(entry.key);
            _reviewsCacheTimestamps.remove(entry.key);
            _reviewsDebounceTimers[entry.key]?.cancel();
            _reviewsDebounceTimers.remove(entry.key);
          }
        }

        if (!completer.isCompleted) {
          completer.complete(reviews);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    return completer.future;
  }

  void updateCurrentImageIndex(int index) {
    if (_isDisposed) return;
    if (_currentImageIndex != index) {
      _currentImageIndex = index;
      _safeNotifyListeners();
    }
  }
}
