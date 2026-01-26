// lib/providers/cart_provider.dart - REFACTORED v4.0 (No Redis, Local Cache)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/cart_totals_cache.dart'; // NEW: Local cache
import '../models/product.dart';
import '../services/cart_validation_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/cart_favorite_metrics_service.dart';
import '../services/user_activity_service.dart';
import '../services/lifecycle_aware.dart';
import '../services/app_lifecycle_manager.dart';

// ============================================================================
// SIMPLIFIED RATE LIMITER (Prevents spam)
// ============================================================================
class _RateLimiter {
  final Map<String, DateTime> _lastOperations = {};
  final Duration _cooldown;

  _RateLimiter(this._cooldown);

  bool canProceed(String operationKey) {
    final lastTime = _lastOperations[operationKey];
    if (lastTime == null) {
      _lastOperations[operationKey] = DateTime.now();
      return true;
    }

    final elapsed = DateTime.now().difference(lastTime);
    if (elapsed >= _cooldown) {
      _lastOperations[operationKey] = DateTime.now();
      return true;
    }
    return false;
  }
}

// ============================================================================
// CART PROVIDER - Simplified, Fast, Scalable (No Redis)
// ============================================================================
class CartProvider with ChangeNotifier, LifecycleAwareMixin {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.normal;

  // ✅ NEW: Local cache instead of Redis
  final CartTotalsCache _totalsCache = CartTotalsCache();

  bool _validating = false;

  // Rate limiters to prevent spam
  final _addToCartLimiter = _RateLimiter(Duration(milliseconds: 300));
  final _quantityLimiter = _RateLimiter(Duration(milliseconds: 200));
  final MetricsEventService _metricsService = MetricsEventService();

  // Public reactive state using ValueNotifiers (optimal for listeners)
  final ValueNotifier<Set<String>> cartProductIdsNotifier = ValueNotifier({});
  final ValueNotifier<int> cartCountNotifier = ValueNotifier(0);
  final ValueNotifier<List<Map<String, dynamic>>> cartItemsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<List<Product>> relatedProductsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isLoadingRelatedNotifier = ValueNotifier(false);
  Timer? _cleanupTimer;

  final ValueNotifier<CartTotals?> cartTotalsNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isTotalsLoadingNotifier = ValueNotifier(false);

  Set<String> _currentTotalsProductIds = {};
  Timer? _totalsVerificationTimer;

  // Optimistic updates cache (for instant UI feedback)
  final Map<String, Map<String, dynamic>> _optimisticCache = {};
  final Map<String, Timer> _optimisticTimeouts = {};
  bool _isInitializing = false;

  // Firestore listener
  StreamSubscription<QuerySnapshot>? _cartSubscription;
  StreamSubscription<User?>? _authSubscription;

  // Concurrency control for quantity updates
  final Map<String, Completer<String>> _quantityUpdateLocks = {};

  // Request coalescing (prevents duplicate fetches)
  final Map<String, Completer<void>> _pendingFetches = {};

  bool _disposed = false;

  // Public getters
  int get cartCount => cartCountNotifier.value;
  Set<String> get cartProductIds => cartProductIdsNotifier.value;
  List<Map<String, dynamic>> get cartItems => cartItemsNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  bool get isInitialized => isInitializedNotifier.value;
  List<Product> get relatedProducts => relatedProductsNotifier.value;
  bool get isLoadingRelated => isLoadingRelatedNotifier.value;

  CartProvider(this._auth, this._firestore) {
    _initializeProvider();

    // Register with lifecycle manager
    AppLifecycleManager.instance.register(this, name: 'CartProvider');
  }

  void _initializeProvider() {
    // ✅ Initialize local cache
    _totalsCache.initialize();

    _authSubscription?.cancel();
    _authSubscription = _auth.userChanges().distinct().listen(
          _handleUserChange,
          onError: (e) => debugPrint('❌ Auth stream error: $e'),
        );
    _cleanupTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _cleanupStaleOperations();
    });

    markInitialized();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> onPause() async {
    await super.onPause();

    // Cancel real-time listener to save resources
    disableLiveUpdates();

    // Pause cleanup timer
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    if (kDebugMode) {
      debugPrint('⏸️ CartProvider: Listener and timer paused');
    }
  }

  @override
  Future<void> onResume(Duration pauseDuration) async {
    await super.onResume(pauseDuration);

    final user = _auth.currentUser;
    if (user == null) return;

    // Restart cleanup timer
    _cleanupTimer ??= Timer.periodic(Duration(seconds: 30), (_) {
      _cleanupStaleOperations();
    });

    // Re-enable real-time updates if initialized
    if (isInitializedNotifier.value) {
      enableLiveUpdates();

      // If long pause, refresh cart data
      if (shouldFullRefresh(pauseDuration)) {
        if (kDebugMode) {
          debugPrint('🔄 CartProvider: Long pause, refreshing cart...');
        }
        // Use unawaited to not block resume
        unawaited(refresh());
      }
    }

    if (kDebugMode) {
      debugPrint('▶️ CartProvider: Listener and timer resumed');
    }
  }

  Future<T> _retryWithBackoff<T>({
    required Future<T> Function() operation,
    required String operationName,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        if (attempt >= maxRetries) {
          debugPrint('❌ $operationName failed after $maxRetries attempts: $e');
          rethrow;
        }

        debugPrint(
            '⚠️ $operationName failed (attempt $attempt/$maxRetries). Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);

        delay = delay * 2;
      }
    }

    throw Exception('$operationName failed after $maxRetries attempts');
  }

  void clearLocalCache() {
    debugPrint('🗑️ Clearing cart local cache');

    // Clear local state
    cartItemsNotifier.value = [];
    cartProductIdsNotifier.value = {};
    cartCountNotifier.value = 0;

    // Mark as needing re-initialization
    isInitializedNotifier.value = false;

    // Clear optimistic updates
    _optimisticCache.clear();
    _optimisticTimeouts.values.forEach((t) => t.cancel());
    _optimisticTimeouts.clear();

    // Reset pagination
    _lastDocument = null;
    _hasMore = true;

    // ✅ Invalidate totals cache
    final user = _auth.currentUser;
    if (user != null) {
      _totalsCache.invalidateForUser(user.uid);
    }
  }

  void _cleanupStaleOperations() {
    final now = DateTime.now();
    _optimisticTimeouts.removeWhere((key, timer) {
      if (!timer.isActive) {
        _optimisticCache.remove(key);
        return true;
      }
      return false;
    });

    _quantityUpdateLocks.removeWhere((key, completer) {
      if (!completer.isCompleted) {
        completer.complete('Timeout');
        return true;
      }
      return false;
    });
  }

  // ========================================================================
  // SMART REAL-TIME LISTENER (Auto-manages connection)
  // ========================================================================

  void enableLiveUpdates() {
    final user = _auth.currentUser;
    if (user == null) return;

    _cartSubscription?.cancel();
    _cartSubscription = null;

    debugPrint('🔴 Enabling real-time cart listener');

    _cartSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cart')
        .snapshots(includeMetadataChanges: false)
        .listen(
          _handleRealtimeUpdate,
          onError: (e) => debugPrint('❌ Listener error: $e'),
        );
  }

  void disableLiveUpdates() {
    debugPrint('🔴 Disabling cart listener');
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  void _handleRealtimeUpdate(QuerySnapshot snapshot) {
    debugPrint(
        '📥 Snapshot: ${snapshot.docs.length} docs, isFromCache: ${snapshot.metadata.isFromCache}, changes: ${snapshot.docChanges.length}');

    for (final change in snapshot.docChanges) {
      debugPrint('  → ${change.type}: ${change.doc.id}');
    }
    if (_isInitializing) {
      debugPrint('⏭️ Skipping listener (initializing)');
      return;
    }

    if (snapshot.metadata.isFromCache) {
      debugPrint('⏭️ Skipping cache event');
      return;
    }

    debugPrint('🔥 Real-time update: ${snapshot.docChanges.length} changes');

    _updateCartIds(snapshot.docs);

    if (snapshot.docChanges.isNotEmpty) {
      _processCartChanges(snapshot.docChanges);
    } else if (snapshot.docs.isEmpty) {
      cartItemsNotifier.value = [];
    }
  }

  void _updateCartIds(List<QueryDocumentSnapshot> docs) {
    final ids = docs.map((doc) => doc.id).toSet();

    final effectiveIds = Set<String>.from(ids);
    for (final entry in _optimisticCache.entries) {
      if (entry.value['_deleted'] == true) {
        effectiveIds.remove(entry.key);
      } else {
        effectiveIds.add(entry.key);
      }
    }

    cartProductIdsNotifier.value = effectiveIds;
    cartCountNotifier.value = effectiveIds.length;
  }

  CartTotals _calculateOptimisticTotals(List<String> selectedProductIds) {
    final items = cartItemsNotifier.value
        .where((item) => selectedProductIds.contains(item['productId']))
        .toList();

    if (items.isEmpty) {
      return CartTotals(total: 0, items: [], currency: 'TL');
    }

    double total = 0;
    String currency = 'TL';
    final itemTotals = <CartItemTotal>[];

    for (final item in items) {
      final productId = item['productId'] as String;
      final quantity = item['quantity'] as int? ?? 1;
      final cartData = item['cartData'] as Map<String, dynamic>? ?? {};

      // Get price from cart data (denormalized)
      double unitPrice = (cartData['unitPrice'] as num?)?.toDouble() ??
          (cartData['cachedPrice'] as num?)?.toDouble() ??
          0;

      // Apply bulk discount if applicable
      final discountThreshold = cartData['discountThreshold'] as int? ??
          cartData['cachedDiscountThreshold'] as int?;
      final bulkDiscountPercentage =
          cartData['bulkDiscountPercentage'] as int? ??
              cartData['cachedBulkDiscountPercentage'] as int?;

      if (discountThreshold != null &&
          bulkDiscountPercentage != null &&
          quantity >= discountThreshold) {
        unitPrice = unitPrice * (1 - bulkDiscountPercentage / 100);
      }

      final itemTotal = unitPrice * quantity;
      total += itemTotal;
      currency = cartData['currency'] as String? ?? 'TL';

      itemTotals.add(CartItemTotal(
        productId: productId,
        unitPrice: unitPrice,
        total: itemTotal,
        quantity: quantity,
      ));
    }

    return CartTotals(
      total: (total * 100).round() / 100, // Round to 2 decimals
      items: itemTotals,
      currency: currency,
    );
  }

  Future<void> updateTotalsForSelection(List<String> selectedProductIds) async {
    if (selectedProductIds.isEmpty) {
      cartTotalsNotifier.value =
          CartTotals(total: 0, items: [], currency: 'TL');
      _currentTotalsProductIds = {};
      return;
    }

    _currentTotalsProductIds = selectedProductIds.toSet();

    // Step 1: Immediate optimistic update (instant UI feedback)
    final optimistic = _calculateOptimisticTotals(selectedProductIds);
    cartTotalsNotifier.value = optimistic;

    // Step 2: Show loading for server verification
    isTotalsLoadingNotifier.value = true; // ✅ Always show loading

    try {
      final serverTotals = await calculateCartTotals(
        selectedProductIds: selectedProductIds,
      );

      cartTotalsNotifier.value = serverTotals;
    } catch (e) {
      debugPrint('⚠️ Server totals failed, using optimistic: $e');
    } finally {
      isTotalsLoadingNotifier.value = false;
    }
  }

  Future<void> _processCartChanges(List<DocumentChange> changes) async {
    final itemsMap = <String, Map<String, dynamic>>{};

    for (final item in cartItemsNotifier.value) {
      final productId = item['productId'] as String?;
      if (productId != null && item['isOptimistic'] != true) {
        itemsMap[productId] = item;
      }
    }

    for (final change in changes) {
      final productId = change.doc.id;
      final cartData = change.doc.data() as Map<String, dynamic>?;

      switch (change.type) {
        case DocumentChangeType.added:
        case DocumentChangeType.modified:
          if (cartData != null && _hasRequiredFields(cartData)) {
            try {
              final product = _buildProductFromCartData(cartData);
              itemsMap[productId] =
                  _createCartItem(productId, cartData, product);
              debugPrint(
                  '✅ ${change.type == DocumentChangeType.added ? "Added" : "Updated"}: $productId');

              _clearOptimisticUpdate(productId);
            } catch (e) {
              debugPrint('❌ Failed to process $productId: $e');
            }
          }
          break;

        case DocumentChangeType.removed:
          itemsMap.remove(productId);
          _clearOptimisticUpdate(productId);
          debugPrint('➖ Removed: $productId');
          break;
      }
    }

    final uniqueItems = <String, Map<String, dynamic>>{};
    for (final item in itemsMap.values) {
      final productId = item['productId'] as String?;
      if (productId != null) {
        uniqueItems[productId] = item;
      }
    }

    final items = uniqueItems.values.toList();
    _sortCartItems(items);
    cartItemsNotifier.value = items;

    // ✅ Invalidate totals cache on cart changes
    final user = _auth.currentUser;
    if (user != null) {
      _totalsCache.invalidateForUser(user.uid);
    }
  }

  void _sortCartItems(List<Map<String, dynamic>> items) {
    items.sort((a, b) {
      final sellerA = a['sellerId'] as String? ?? '';
      final sellerB = b['sellerId'] as String? ?? '';
      if (sellerA != sellerB) return sellerA.compareTo(sellerB);

      final cartDataA = a['cartData'] as Map<String, dynamic>;
      final cartDataB = b['cartData'] as Map<String, dynamic>;
      final dateA = cartDataA['addedAt'] as Timestamp?;
      final dateB = cartDataB['addedAt'] as Timestamp?;
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    String? lastSeller;
    for (final item in items) {
      final sellerId = item['sellerId'] as String? ?? '';
      item['showSellerHeader'] = sellerId != lastSeller;
      lastSeller = sellerId;
    }
  }

  bool _hasRequiredFields(Map<String, dynamic> cartData) {
    final required = [
      'productId',
      'productName',
      'unitPrice',
      'availableStock',
      'sellerName',
      'sellerId'
    ];
    for (final field in required) {
      if (!cartData.containsKey(field) || cartData[field] == null) return false;
    }

    final productName = cartData['productName'] as String?;
    if (productName == null ||
        productName.isEmpty ||
        productName == 'Unknown Product') return false;

    final sellerName = cartData['sellerName'] as String?;
    if (sellerName == null || sellerName.isEmpty || sellerName == 'Unknown')
      return false;

    return true;
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  Future<void> initializeCartIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null || isInitializedNotifier.value) return;

    if (_pendingFetches.containsKey('init')) {
      debugPrint('⏳ Already initializing, waiting...');
      await _pendingFetches['init']!.future;
      return;
    }

    final completer = Completer<void>();
    _pendingFetches['init'] = completer;
    isLoadingNotifier.value = true;
    _isInitializing = true;

    cartItemsNotifier.value = [];
    cartProductIdsNotifier.value = {};
    cartCountNotifier.value = 0;

    _lastDocument = null;
    _hasMore = true;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .orderBy('addedAt', descending: true)
          .limit(20)
          .get(const GetOptions(source: Source.cache));

      if (snapshot.docs.isEmpty) {
        final serverSnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('cart')
            .orderBy('addedAt', descending: true)
            .limit(20)
            .get(const GetOptions(source: Source.server));

        await _buildCartItemsFromDocs(serverSnapshot.docs);

        if (serverSnapshot.docs.isNotEmpty) {
          _lastDocument = serverSnapshot.docs.last;
          _hasMore = serverSnapshot.docs.length >= 20;
        }
      } else {
        await _buildCartItemsFromDocs(snapshot.docs);

        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
          _hasMore = snapshot.docs.length >= 20;
        }
      }

      isInitializedNotifier.value = true;

      enableLiveUpdates();

      completer.complete();
    } catch (e) {
      debugPrint('❌ Init error: $e');
      completer.completeError(e);
    } finally {
      isLoadingNotifier.value = false;
      _isInitializing = false;
      _pendingFetches.remove('init');
    }
  }

  Future<void> _buildCartItemsFromDocs(List<QueryDocumentSnapshot> docs) async {
    final items = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final cartData = doc.data() as Map<String, dynamic>;
      if (_hasRequiredFields(cartData)) {
        try {
          final product = _buildProductFromCartData(cartData);
          items.add(_createCartItem(doc.id, cartData, product));
        } catch (e) {
          debugPrint('❌ Failed to build item ${doc.id}: $e');
        }
      }
    }

    _sortCartItems(items);
    cartItemsNotifier.value = items;
    _updateCartIds(docs);
  }

  void _handleUserChange(User? user) {
    disableLiveUpdates();

    if (user == null) {
      _clearAllData();
      return;
    }

    _clearAllData();
    initializeCartIfNeeded();
  }

  void _clearAllData() {
    cartCountNotifier.value = 0;
    cartProductIdsNotifier.value = {};
    cartItemsNotifier.value = [];
    cartTotalsNotifier.value = null;
    _currentTotalsProductIds = {};
    isInitializedNotifier.value = false;
    isLoadingNotifier.value = false;
    _optimisticCache.clear();

    // Cancel all pending timers to prevent memory leaks
    _totalsVerificationTimer?.cancel();
    _totalsVerificationTimer = null;
    for (final timer in _optimisticTimeouts.values) {
      timer.cancel();
    }
    _optimisticTimeouts.clear();
    _quantityUpdateLocks.clear();

    // Clear totals cache
    _totalsCache.clearAll();
  }

  // ========================================================================
  // ADD TO CART (Optimistic + Firestore)
  // ========================================================================

  Map<String, dynamic> _buildProductDataForCart(
    Product product, {
    String? selectedColor,
    Map<String, dynamic>? attributes,
  }) {
    double? extractedBundlePrice;
    if (product.bundleData != null && product.bundleData!.isNotEmpty) {
      extractedBundlePrice =
          product.bundleData!.first['bundlePrice'] as double?;
    }
    return {
      'productId': product.id,
      'productName': product.productName,
      'description': product.description,
      'unitPrice': product.price,
      'currency': product.currency,
      'originalPrice': product.originalPrice,
      'discountPercentage': product.discountPercentage,
      'condition': product.condition,
      'brandModel': product.brandModel,
      'category': product.category,
      'subcategory': product.subcategory,
      'subsubcategory': product.subsubcategory,
      'allImages': product.imageUrls,
      'productImage':
          product.imageUrls.isNotEmpty ? product.imageUrls.first : '',
      'colorImages': product.colorImages,
      'videoUrl': product.videoUrl,
      'availableStock': product.quantity,
      'colorQuantities': product.colorQuantities,
      'availableColors': product.availableColors,
      'averageRating': product.averageRating,
      'reviewCount': product.reviewCount,
      'maxQuantity': product.maxQuantity,
      'discountThreshold': product.discountThreshold,
      'bulkDiscountPercentage': product.bulkDiscountPercentage,
      'bundleIds': product.bundleIds,
      'bundleData': product.bundleData,
      'sellerId': product.userId,
      'sellerName': product.sellerName,
      'isShop': product.shopId != null,
      'shopId': product.shopId,
      'ilanNo': product.ilanNo,
      'createdAt': product.createdAt,
      'deliveryOption': product.deliveryOption,
      'selectedColor': selectedColor,
      'attributes': attributes,
      'cachedPrice': product.price,
      'cachedDiscountPercentage': product.discountPercentage,
      'cachedDiscountThreshold': product.discountThreshold,
      'cachedBundlePrice': extractedBundlePrice,
      'cachedBulkDiscountPercentage': product.bulkDiscountPercentage,
      'cachedMaxQuantity': product.maxQuantity,
    };
  }

  Future<String> addProductToCart(
    Product product, {
    int quantity = 1,
    String? selectedColor,
    Map<String, dynamic>? attributes,
  }) async {
    final productData = _buildProductDataForCart(
      product,
      selectedColor: selectedColor,
      attributes: attributes,
    );
    return addToCart(
      productId: product.id,
      productData: productData,
      quantity: quantity,
    );
  }

  Future<String> addToCartById(
    String productId, {
    int quantity = 1,
    String? selectedColor,
    Map<String, dynamic>? attributes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in first';

    try {
      final productDoc =
          await _firestore.collection('shop_products').doc(productId).get();

      if (!productDoc.exists) {
        return 'Product not found';
      }

      final product =
          Product.fromJson(productDoc.data() as Map<String, dynamic>);

      return addProductToCart(
        product,
        quantity: quantity,
        selectedColor: selectedColor,
        attributes: attributes,
      );
    } catch (e) {
      debugPrint('❌ Add to cart by ID error: $e');
      return 'Failed to add to cart';
    }
  }

  Future<void> _backgroundRefreshTotals() async {
    final user = _auth.currentUser;
    if (user == null || cartProductIds.isEmpty) return;

    try {
      await calculateCartTotals(
        selectedProductIds: cartProductIds.toList(),
      );
      debugPrint('⚡ Background totals cached');
    } catch (e) {
      debugPrint('⚠️ Background total refresh failed: $e');
    }
  }

  Future<String> addToCart({
    required String productId,
    required Map<String, dynamic> productData,
    int quantity = 1,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in first';

    if (!_addToCartLimiter.canProceed('add_$productId')) {
      return 'Please wait before adding again';
    }

    try {
      _applyOptimisticAdd(productId, productData, quantity);

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .set({
        ...productData,
        'quantity': quantity,
        'addedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      UserActivityService.instance.trackAddToCart(
        productId: productId,
        shopId: productData['shopId'] as String?,
        category: productData['category'] as String?,
        subcategory: productData['subcategory'] as String?,
        subsubcategory: productData['subsubcategory'] as String?,
        brand: productData['brandModel'] as String?,
        price: (productData['unitPrice'] as num?)?.toDouble(),
        quantity: quantity,
        productName: productData['productName'] as String?,
      );

      _metricsService.logCartAdded(
        productId: productId,
        shopId: productData['shopId'] as String?,
      );

      debugPrint('✅ Added to cart: $productId');

      // ✅ Invalidate cache
      _totalsCache.invalidateForUser(user.uid);

      unawaited(_backgroundRefreshTotals());

      return 'Added to cart';
    } catch (e) {
      debugPrint('❌ Add to cart error: $e');
      _rollbackOptimisticUpdate(productId);
      return 'Failed to add to cart';
    }
  }

  void _applyOptimisticAdd(
      String productId, Map<String, dynamic> productData, int quantity) {
    _clearOptimisticUpdate(productId);

    final existingItems = cartItemsNotifier.value
        .where((item) => item['productId'] != productId)
        .toList();

    // ✅ FIX: Create enriched productData with quantity FIRST
    final enrichedProductData = {
      ...productData,
      'quantity': quantity,
    };

    _optimisticCache[productId] = {
      ...enrichedProductData,
      '_optimistic': true,
    };

    final newIds = Set<String>.from(cartProductIdsNotifier.value)
      ..add(productId);
    cartProductIdsNotifier.value = newIds;
    cartCountNotifier.value = newIds.length;

    // ✅ FIX: Use enrichedProductData (with quantity)
    final optimisticProduct = _buildProductFromCartData(enrichedProductData);
    final optimisticItem = {
      ..._createCartItem(productId, enrichedProductData, optimisticProduct),
      'isOptimistic': true,
    };

    existingItems.insert(0, optimisticItem);
    cartItemsNotifier.value = existingItems;

    _optimisticTimeouts[productId]?.cancel();
    _optimisticTimeouts[productId] = Timer(Duration(seconds: 3), () {
      if (_optimisticCache.containsKey(productId)) {
        debugPrint('⚠️ Optimistic timeout: $productId');
        _clearOptimisticUpdate(productId);
      }
    });
  }

  void _rollbackOptimisticUpdate(String productId) {
    _optimisticCache.remove(productId);
    _optimisticTimeouts[productId]?.cancel();
    _optimisticTimeouts.remove(productId);

    final newIds = Set<String>.from(cartProductIdsNotifier.value)
      ..remove(productId);
    cartProductIdsNotifier.value = newIds;
    cartCountNotifier.value = newIds.length;

    debugPrint('🔄 Rolled back optimistic update: $productId');
  }

  void _clearOptimisticUpdate(String productId) {
    _optimisticCache.remove(productId);
    _optimisticTimeouts[productId]?.cancel();
    _optimisticTimeouts.remove(productId);
  }

  // ========================================================================
  // REMOVE FROM CART (Optimistic + Firestore)
  // ========================================================================

  Future<String> removeFromCart(String productId) async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in first';

    try {
      _applyOptimisticRemove(productId);

      final cartDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .get();

      final cartData = cartDoc.data();
      final shopId = cartData?['shopId'] as String?;

      debugPrint('🔍 Removing from cart: productId=$productId, shopId=$shopId');

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .delete();

      UserActivityService.instance.trackRemoveFromCart(
        productId: productId,
        shopId: shopId,
        productName: cartData?['productName'] as String?,
        category: cartData?['category'] as String?,
        brand: cartData?['brandModel'] as String?,
      );

      _metricsService.logCartRemoved(
        productId: productId,
        shopId: shopId,
      );

      // ✅ Invalidate cache
      _totalsCache.invalidateForUser(user.uid);

      unawaited(_backgroundRefreshTotals());

      return 'Removed from cart';
    } catch (e) {
      debugPrint('❌ Remove error: $e');
      _rollbackOptimisticRemove(productId);
      return 'Failed to remove from cart';
    }
  }

  void _applyOptimisticRemove(String productId) {
    _optimisticCache[productId] = {'_deleted': true};

    final newIds = Set<String>.from(cartProductIdsNotifier.value)
      ..remove(productId);
    cartProductIdsNotifier.value = newIds;
    cartCountNotifier.value = newIds.length;

    final items = cartItemsNotifier.value
        .where((item) => item['productId'] != productId)
        .toList();
    cartItemsNotifier.value = items;

    _optimisticTimeouts[productId]?.cancel();
    _optimisticTimeouts[productId] = Timer(Duration(seconds: 5), () {
      _optimisticCache.remove(productId);
      _optimisticTimeouts.remove(productId);
    });
  }

  void _rollbackOptimisticRemove(String productId) {
    _optimisticCache.remove(productId);
    _optimisticTimeouts[productId]?.cancel();
    _optimisticTimeouts.remove(productId);

    final user = _auth.currentUser;
    if (user != null) {
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .get(const GetOptions(source: Source.server))
          .then((doc) {
        if (doc.exists) {
          final newIds = Set<String>.from(cartProductIdsNotifier.value)
            ..add(productId);
          cartProductIdsNotifier.value = newIds;
          cartCountNotifier.value = newIds.length;
        }
      });
    }
  }

  // ========================================================================
  // UPDATE QUANTITY (Optimistic + Firestore)
  // ========================================================================

  Future<String> updateQuantity(String productId, int newQuantity) async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in first';

    if (newQuantity < 1) {
      return removeFromCart(productId);
    }

    if (!_quantityLimiter.canProceed('qty_$productId')) {
      return 'Please wait';
    }

    if (_quantityUpdateLocks.containsKey(productId)) {
      return await _quantityUpdateLocks[productId]!.future;
    }

    final completer = Completer<String>();
    _quantityUpdateLocks[productId] = completer;

    try {
      // Step 1: Optimistic UI update
      _applyOptimisticQuantityChange(productId, newQuantity);

      // Step 2: Immediately recalculate totals (optimistic)
      if (_currentTotalsProductIds.isNotEmpty) {
        final optimistic =
            _calculateOptimisticTotals(_currentTotalsProductIds.toList());
        cartTotalsNotifier.value = optimistic;
      }

      // Step 3: Persist to Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc(productId)
          .update({
        'quantity': newQuantity,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Updated quantity: $productId = $newQuantity');

      // Step 4: Invalidate cache & verify with server (non-blocking)
      _totalsCache.invalidateForUser(user.uid);

      // Debounced server verification (prevents spam during rapid +/- taps)
      _debouncedTotalsVerification();

      completer.complete('Quantity updated');
      return 'Quantity updated';
    } catch (e) {
      debugPrint('❌ Update quantity error: $e');
      completer.complete('Failed to update quantity');
      return 'Failed to update quantity';
    } finally {
      _quantityUpdateLocks.remove(productId);
    }
  }

  void _debouncedTotalsVerification() {
    _totalsVerificationTimer?.cancel();
    _totalsVerificationTimer =
        Timer(const Duration(milliseconds: 500), () async {
      if (_currentTotalsProductIds.isEmpty) return;

      try {
        final serverTotals = await calculateCartTotals(
          selectedProductIds: _currentTotalsProductIds.toList(),
        );
        cartTotalsNotifier.value = serverTotals;
        debugPrint('✅ Server verified totals: ${serverTotals.total}');
      } catch (e) {
        debugPrint('⚠️ Server verification failed: $e');
      }
    });
  }

  void _applyOptimisticQuantityChange(String productId, int newQuantity) {
    final items = List<Map<String, dynamic>>.from(cartItemsNotifier.value);

    final indices = <int>[];
    for (int i = 0; i < items.length; i++) {
      if (items[i]['productId'] == productId) {
        indices.add(i);
      }
    }

    if (indices.isEmpty) return;

    final firstIndex = indices.first;
    items[firstIndex] = {
      ...items[firstIndex],
      'quantity': newQuantity,
    };

    for (int i = indices.length - 1; i > 0; i--) {
      items.removeAt(indices[i]);
    }

    cartItemsNotifier.value = items;
  }

  // ========================================================================
  // BATCH REMOVE (Multiple items)
  // ========================================================================

  Future<String> removeMultipleFromCart(List<String> productIds) async {
    final user = _auth.currentUser;
    if (user == null) return 'Please log in first';
    if (productIds.isEmpty) return 'No items selected';

    try {
      final shopIds = <String, String?>{};
      for (final productId in productIds) {
        final item = cartItems.firstWhere(
          (item) => item['productId'] == productId,
          orElse: () => <String, dynamic>{},
        );
        if (item.isNotEmpty) {
          shopIds[productId] = item['cartData']?['shopId'] as String?;
        }
      }

      for (final productId in productIds) {
        _applyOptimisticRemove(productId);
      }

      final batch = _firestore.batch();
      for (final productId in productIds) {
        batch.delete(
          _firestore
              .collection('users')
              .doc(user.uid)
              .collection('cart')
              .doc(productId),
        );
      }
      await batch.commit();

      _metricsService.logBatchCartRemovals(
        productIds: productIds,
        shopIds: shopIds,
      );

      debugPrint('✅ Removed ${productIds.length} items');

      // ✅ Invalidate cache
      _totalsCache.invalidateForUser(user.uid);

      unawaited(_backgroundRefreshTotals());

      return 'Products removed from cart';
    } catch (e) {
      debugPrint('❌ Batch remove error: $e');
      return 'Failed to remove products';
    }
  }

  // ========================================================================
  // REFRESH (Manual force refresh)
  // ========================================================================

  Future<void> refresh() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _lastDocument = null;
    _hasMore = true;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .orderBy('addedAt', descending: true)
          .limit(20)
          .get(const GetOptions(source: Source.server));

      await _buildCartItemsFromDocs(snapshot.docs);

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        _hasMore = snapshot.docs.length >= 20;
      }

      debugPrint('✅ Cart refreshed with pagination reset');
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
    }
  }

  // ========================================================================
  // TOTALS CALCULATION (with Local Caching)
  // ========================================================================

  Future<CartTotals> calculateCartTotals({
    List<String>? selectedProductIds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return CartTotals(total: 0, items: [], currency: 'TL');
    }

    final productsToCalculate = selectedProductIds ??
        cartItems.map((item) => item['productId'] as String).toList();

    if (productsToCalculate.isEmpty) {
      return CartTotals(total: 0, items: [], currency: 'TL');
    }

    // ✅ Check local cache first
    final cached = _totalsCache.get(user.uid, productsToCalculate);
    if (cached != null) {
      debugPrint('⚡ Cache hit - instant total');
      return CartTotals(
        total: cached.total,
        currency: cached.currency,
        items: cached.items
            .map((i) => CartItemTotal(
                  productId: i.productId,
                  unitPrice: i.unitPrice,
                  total: i.total,
                  quantity: i.quantity,
                  isBundleItem: i.isBundleItem,
                ))
            .toList(),
      );
    }

    // Request deduplication
    final cacheKey = productsToCalculate.join(',');
    if (_pendingFetches.containsKey('totals_$cacheKey')) {
      debugPrint('⏳ Waiting for existing totals calculation...');
      await _pendingFetches['totals_$cacheKey']!.future;

      final cachedAfterWait = _totalsCache.get(user.uid, productsToCalculate);
      if (cachedAfterWait != null) {
        return CartTotals(
          total: cachedAfterWait.total,
          currency: cachedAfterWait.currency,
          items: cachedAfterWait.items
              .map((i) => CartItemTotal(
                    productId: i.productId,
                    unitPrice: i.unitPrice,
                    total: i.total,
                    quantity: i.quantity,
                    isBundleItem: i.isBundleItem,
                  ))
              .toList(),
        );
      }
    }

    final completer = Completer<void>();
    _pendingFetches['totals_$cacheKey'] = completer;

    try {
      final totals = await _retryWithBackoff(
        operation: () async {
          final token = await user.getIdToken();
          if (token == null) {
            throw Exception('No auth token available');
          }

          final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('calculateCartTotals');

          final result = await callable.call({
            'selectedProductIds': productsToCalculate,
          });

          final dynamic rawData = result.data;
          Map<String, dynamic> totalsData;

          if (rawData is Map<String, dynamic>) {
            totalsData = rawData;
          } else if (rawData is Map) {
            totalsData = _deepConvertMap(rawData);
          } else {
            throw Exception('Unexpected response type: ${rawData.runtimeType}');
          }

          final totals = CartTotals.fromJson(totalsData);

          // ✅ Cache result locally
          _totalsCache.set(
            user.uid,
            productsToCalculate,
            CachedCartTotals(
              total: totals.total,
              currency: totals.currency,
              items: totals.items
                  .map((i) => CachedItemTotal(
                        productId: i.productId,
                        unitPrice: i.unitPrice,
                        total: i.total,
                        quantity: i.quantity,
                        isBundleItem: i.isBundleItem,
                      ))
                  .toList(),
            ),
          );

          return totals;
        },
        operationName: 'Calculate Totals',
        maxRetries: 3,
      );

      debugPrint('✅ Total calculated: ${totals.total} ${totals.currency}');
      completer.complete();
      return totals;
    } catch (e, stackTrace) {
      debugPrint('❌ Cloud Function failed after retries: $e');
      debugPrint('Stack trace: $stackTrace');
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingFetches.remove('totals_$cacheKey');
    }
  }

  Map<String, dynamic> _deepConvertMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (key == null) return;

      final stringKey = key.toString();

      if (value is Map) {
        result[stringKey] = _deepConvertMap(value);
      } else if (value is List) {
        result[stringKey] = _deepConvertList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  List<dynamic> _deepConvertList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _deepConvertMap(item);
      } else if (item is List) {
        return _deepConvertList(item);
      }
      return item;
    }).toList();
  }

  Future<Map<String, dynamic>> getFullCartTotal() async {
    final totals = await calculateCartTotals();
    return {
      'total': totals.total,
      'currency': totals.currency,
      'itemCount': cartItems.length,
    };
  }

  // ========================================================================
  // PAYMENT VALIDATION
  // ========================================================================

  Future<Map<String, dynamic>> validateForPayment(
    List<String> selectedProductIds, {
    bool reserveStock = false,
  }) async {
    if (_validating) {
      return {
        'isValid': false,
        'errors': {
          '_system': {'key': 'validation_in_progress', 'params': {}},
        },
        'warnings': {},
        'validatedItems': [],
      };
    }

    _validating = true;

    try {
      final itemsToValidate = cartItems
          .where((item) => selectedProductIds.contains(item['productId']))
          .toList();

      if (itemsToValidate.isEmpty) {
        return {
          'isValid': false,
          'errors': {
            '_system': {'key': 'no_items_selected', 'params': {}},
          },
          'warnings': {},
          'validatedItems': [],
        };
      }

      final validationService = CartValidationService();

      final result = await _retryWithBackoff(
        operation: () => validationService.validateCartCheckout(
          cartItems: itemsToValidate,
          reserveStock: reserveStock,
        ),
        operationName: 'Validate Cart',
        maxRetries: 2,
        initialDelay: const Duration(milliseconds: 300),
      );

      return result;
    } catch (e) {
      debugPrint('❌ Validation failed after retries: $e');

      return {
        'isValid': false,
        'errors': {
          '_system': {
            'key': 'validation_service_unavailable',
            'params': {},
          },
        },
        'warnings': {},
        'validatedItems': [],
      };
    } finally {
      _validating = false;
    }
  }

  Future<bool> updateCartCacheFromValidation(
    List<Map<String, dynamic>> validatedItems,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final validationService = CartValidationService();

      final success = await validationService.updateCartCache(
        userId: user.uid,
        validatedItems: validatedItems,
      );

      if (success) {
        // ✅ Invalidate cache
        _totalsCache.invalidateForUser(user.uid);

        await refresh();
      }

      return success;
    } catch (e) {
      debugPrint('❌ Cache update error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllSelectedItems(
      List<String> selectedProductIds) async {
    return cartItems
        .where((item) => selectedProductIds.contains(item['productId']))
        .toList();
  }

  // ========================================================================
  // LOAD MORE (Pagination for large carts)
  // ========================================================================

  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  Future<void> loadMoreItems() async {
    final user = _auth.currentUser;
    if (user == null || !_hasMore || isLoadingNotifier.value) return;

    if (_pendingFetches.containsKey('loadMore')) {
      debugPrint('⏳ Already loading more...');
      return;
    }

    final completer = Completer<void>();
    _pendingFetches['loadMore'] = completer;

    isLoadingNotifier.value = true;

    try {
      Query query = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .orderBy('addedAt', descending: true)
          .limit(20);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      if (snapshot.docs.isEmpty) {
        _hasMore = false;
        debugPrint('📄 No more items to load');
        completer.complete();
        return;
      }

      _lastDocument = snapshot.docs.last;
      _hasMore = snapshot.docs.length >= 20;

      final newItems = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final cartData = doc.data() as Map<String, dynamic>;
        if (_hasRequiredFields(cartData)) {
          try {
            final product = _buildProductFromCartData(cartData);
            newItems.add(_createCartItem(doc.id, cartData, product));
          } catch (e) {
            debugPrint('❌ Failed to build item ${doc.id}: $e');
          }
        }
      }

      final existingIds = cartItemsNotifier.value
          .map((item) => item['productId'] as String)
          .toSet();

      final uniqueNewItems = newItems
          .where((item) => !existingIds.contains(item['productId']))
          .toList();

      if (uniqueNewItems.isNotEmpty) {
        final allItems = [...cartItemsNotifier.value, ...uniqueNewItems];
        _sortCartItems(allItems);
        cartItemsNotifier.value = allItems;

        debugPrint(
            '✅ Loaded ${uniqueNewItems.length} more items (${newItems.length - uniqueNewItems.length} duplicates skipped)');
      } else {
        debugPrint('⚠️ All ${newItems.length} items already loaded');
      }

      completer.complete();
    } catch (e) {
      debugPrint('❌ Load more error: $e');
      completer.completeError(e);
    } finally {
      isLoadingNotifier.value = false;
      _pendingFetches.remove('loadMore');
    }
  }

  // ========================================================================
  // USER INTERACTION TRACKING (Optional, for analytics)
  // ========================================================================

  void trackInteraction() {
    // No-op in simplified version
  }

  void setCheckoutFlow(bool isInCheckout) {
    // No-op in simplified version
  }

  // ========================================================================
  // PRODUCT BUILDER (from denormalized cart data)
  // ========================================================================

  Product _buildProductFromCartData(Map<String, dynamic> cartData) {
    T _safeGet<T>(String key, T defaultValue) {
      final value = cartData[key];
      if (value == null) return defaultValue;

      if (T == double) {
        if (value is num) return value.toDouble() as T;
        if (value is String)
          return (double.tryParse(value) ?? defaultValue as double) as T;
      }
      if (T == int) {
        if (value is num) return value.toInt() as T;
        if (value is String)
          return (int.tryParse(value) ?? defaultValue as int) as T;
      }
      if (T == String) return value.toString() as T;
      if (T == bool) {
        if (value is bool) return value as T;
        return (value.toString().toLowerCase() == 'true') as T;
      }

      return value as T;
    }

    List<Map<String, dynamic>>? _safeBundleData(String key) {
      final value = cartData[key];
      if (value == null) return null;
      if (value is! List) return null;

      try {
        return value.map((item) {
          if (item is Map<String, dynamic>) {
            return item;
          } else if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return <String, dynamic>{};
        }).toList();
      } catch (e) {
        debugPrint('Error parsing bundleData: $e');
        return null;
      }
    }

    List<String> _safeStringList(String key) {
      final value = cartData[key];
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      if (value is String && value.isNotEmpty) return [value];
      return [];
    }

    Map<String, List<String>> _safeColorImages(String key) {
      final value = cartData[key];
      if (value is! Map) return {};

      final result = <String, List<String>>{};
      value.forEach((k, v) {
        if (v is List) {
          result[k.toString()] = v.map((e) => e.toString()).toList();
        } else if (v is String && v.isNotEmpty) {
          result[k.toString()] = [v];
        }
      });
      return result;
    }

    Map<String, int> _safeColorQuantities(String key) {
      final value = cartData[key];
      if (value is! Map) return {};

      final result = <String, int>{};
      value.forEach((k, v) {
        if (v is num) {
          result[k.toString()] = v.toInt();
        } else if (v is String) {
          result[k.toString()] = int.tryParse(v) ?? 0;
        }
      });
      return result;
    }

    Timestamp _safeTimestamp(String key) {
      final value = cartData[key];
      if (value is Timestamp) return value;
      if (value is int) return Timestamp.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        try {
          return Timestamp.fromDate(DateTime.parse(value));
        } catch (_) {}
      }
      return Timestamp.now();
    }

    return Product(
      id: _safeGet('productId', ''),
      productName: _safeGet('productName', 'Unknown Product'),
      description: _safeGet('description', ''),
      price: _safeGet('unitPrice', 0.0),
      currency: _safeGet('currency', 'TL'),
      originalPrice: cartData['originalPrice'] != null
          ? _safeGet<double>('originalPrice', 0.0)
          : null,
      discountPercentage: cartData['discountPercentage'] != null
          ? _safeGet<int>('discountPercentage', 0)
          : null,
      condition: _safeGet('condition', 'Brand New'),
      brandModel: _safeGet('brandModel', ''),
      category: _safeGet('category', 'Uncategorized'),
      subcategory: _safeGet('subcategory', ''),
      subsubcategory: _safeGet('subsubcategory', ''),
      imageUrls: _safeStringList('allImages').isNotEmpty
          ? _safeStringList('allImages')
          : [_safeGet('productImage', '')],
      colorImages: _safeColorImages('colorImages'),
      videoUrl: cartData['videoUrl']?.toString(),
      quantity: _safeGet('availableStock', 0),
      colorQuantities: _safeColorQuantities('colorQuantities'),
      averageRating: _safeGet('averageRating', 0.0),
      reviewCount: _safeGet('reviewCount', 0),
      maxQuantity: cartData['maxQuantity'] as int?,
      discountThreshold: cartData['discountThreshold'] as int?,
      bulkDiscountPercentage: cartData['bulkDiscountPercentage'] as int?,
      bundleIds: _safeStringList('bundleIds'),
      bundleData:
          _safeBundleData('bundleData') ?? _safeBundleData('cachedBundleData'),
      userId: _safeGet('sellerId', ''),
      ownerId: _safeGet('sellerId', ''),
      shopId: cartData['isShop'] == true ? _safeGet('sellerId', null) : null,
      sellerName: _safeGet('sellerName', 'Unknown'),
      ilanNo: _safeGet('ilanNo', 'N/A'),
      createdAt: _safeTimestamp('createdAt'),
      deliveryOption: _safeGet('deliveryOption', 'Self Delivery'),
      clickCount: _safeGet('clickCount', 0),
      clickCountAtStart: _safeGet('clickCountAtStart', 0),
      favoritesCount: _safeGet('favoritesCount', 0),
      cartCount: _safeGet('cartCount', 0),
      purchaseCount: _safeGet('purchaseCount', 0),
      boostedImpressionCount: _safeGet('boostedImpressionCount', 0),
      boostImpressionCountAtStart: _safeGet('boostImpressionCountAtStart', 0),
      boostClickCountAtStart: _safeGet('boostClickCountAtStart', 0),
      dailyClickCount: _safeGet('dailyClickCount', 0),
      isFeatured: _safeGet('isFeatured', false),
      isTrending: _safeGet('isTrending', false),
      isBoosted: _safeGet('isBoosted', false),
      paused: _safeGet('paused', false),
      gender: cartData['gender']?.toString(),
      bestSellerRank: cartData['bestSellerRank'] as int?,
      availableColors: _safeStringList('availableColors'),
      campaign: cartData['campaign']?.toString(),
      campaignName: cartData['campaignName']?.toString(),
      rankingScore: _safeGet('rankingScore', 0.0),
      promotionScore: _safeGet('promotionScore', 0.0),
      boostStartTime: cartData['boostStartTime'] is Timestamp
          ? cartData['boostStartTime'] as Timestamp
          : null,
      boostEndTime: cartData['boostEndTime'] is Timestamp
          ? cartData['boostEndTime'] as Timestamp
          : null,
      lastClickDate: cartData['lastClickDate'] is Timestamp
          ? cartData['lastClickDate'] as Timestamp
          : null,
      relatedProductIds: _safeStringList('relatedProductIds'),
      relatedLastUpdated: cartData['relatedLastUpdated'] is Timestamp
          ? cartData['relatedLastUpdated'] as Timestamp
          : null,
      relatedCount: _safeGet('relatedCount', 0),
      attributes: cartData['attributes'] is Map<String, dynamic>
          ? cartData['attributes'] as Map<String, dynamic>
          : {},
    );
  }

  Map<String, dynamic> _createCartItem(
    String productId,
    Map<String, dynamic> cartData,
    Product product,
  ) {
    final Map<String, dynamic> item = {
      'product': product,
      'productId': productId,
      'quantity': cartData['quantity'] as int? ?? 1,
      'salePreferences': _extractSalePreferences(cartData),
      'selectedColorImage':
          _resolveColorImage(product, cartData['selectedColor']),
      'sellerName': cartData['sellerName'] ?? 'Unknown',
      'sellerId': cartData['sellerId'] ?? 'unknown',
      'isShop': cartData['isShop'] ?? false,
      'sellerContactNo': cartData['sellerContactNo'],
      'isOptimistic': false,
    };

    if (cartData.containsKey('selectedColor')) {
      item['selectedColor'] = cartData['selectedColor'];
    }

    if (cartData.containsKey('attributes') && cartData['attributes'] is Map) {
      final attributes = cartData['attributes'] as Map<String, dynamic>;
      attributes.forEach((key, value) {
        if (!item.containsKey(key)) {
          item[key] = value;
        }
      });
    }

    item['cartData'] = cartData;

    return item;
  }

  Map<String, dynamic>? _extractSalePreferences(Map<String, dynamic> data) {
    final salePrefs = <String, dynamic>{};
    if (data['maxQuantity'] != null)
      salePrefs['maxQuantity'] = data['maxQuantity'];
    if (data['discountThreshold'] != null)
      salePrefs['discountThreshold'] = data['discountThreshold'];
    if (data['bulkDiscountPercentage'] != null)
      salePrefs['bulkDiscountPercentage'] = data['bulkDiscountPercentage'];
    return salePrefs.isEmpty ? null : salePrefs;
  }

  String? _resolveColorImage(Product product, dynamic selectedColor) {
    if (selectedColor == null ||
        !product.colorImages.containsKey(selectedColor.toString())) {
      return null;
    }
    final images = product.colorImages[selectedColor.toString()];
    return images?.isNotEmpty == true ? images!.first : null;
  }

  // ========================================================================
  // CLEANUP
  // ========================================================================

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    debugPrint('🧹 CartProvider disposing...');

    _cleanupStaleOperations();
    _cleanupTimer?.cancel();

    disableLiveUpdates();
    _authSubscription?.cancel();
    for (final timer in _optimisticTimeouts.values) {
      timer.cancel();
    }
    _optimisticTimeouts.clear();
    _optimisticCache.clear();
    _quantityUpdateLocks.clear();

    // ✅ Dispose cache
    _totalsCache.dispose();
    _totalsVerificationTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// CART TOTALS MODELS
// ============================================================================

class CartTotals {
  final double total;
  final List<CartItemTotal> items;
  final String currency;

  CartTotals({
    required this.total,
    required this.items,
    required this.currency,
  });

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'currency': currency,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory CartTotals.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List? ?? [];
    final parsedItems = <CartItemTotal>[];

    for (final item in itemsList) {
      try {
        Map<String, dynamic> itemMap;
        if (item is Map<String, dynamic>) {
          itemMap = item;
        } else if (item is Map) {
          itemMap = Map<String, dynamic>.from(item);
        } else {
          continue;
        }

        parsedItems.add(CartItemTotal.fromJson(itemMap));
      } catch (e) {
        debugPrint('⚠️ Failed to parse cart item: $e');
      }
    }

    return CartTotals(
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String,
      items: parsedItems,
    );
  }
}

class CartItemTotal {
  final String productId;
  final double unitPrice;
  final double total;
  final int quantity;
  final bool isBundleItem;

  CartItemTotal({
    required this.productId,
    required this.unitPrice,
    required this.total,
    required this.quantity,
    this.isBundleItem = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'unitPrice': unitPrice,
      'total': total,
      'quantity': quantity,
      'isBundleItem': isBundleItem,
    };
  }

  factory CartItemTotal.fromJson(Map<String, dynamic> json) {
    return CartItemTotal(
      productId: json['productId'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 1).toInt(),
      isBundleItem: json['isBundleItem'] as bool? ?? false,
    );
  }
}
