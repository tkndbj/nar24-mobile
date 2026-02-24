// lib/providers/favorite_product_provider.dart - REFACTORED v2.0 (Production Grade + Simplified)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../generated/l10n/app_localizations.dart';
import '../services/cart_favorite_metrics_service.dart';
import '../services/user_activity_service.dart';
import '../services/lifecycle_aware.dart';
import '../services/app_lifecycle_manager.dart';

// ============================================================================
// RATE LIMITER (Prevents spam)
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
// CIRCUIT BREAKER (Fault tolerance)
// ============================================================================
class _CircuitBreaker {
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  static const int _threshold = 5;
  static const Duration _resetDuration = Duration(minutes: 1);

  bool get isOpen {
    if (_failureCount >= _threshold) {
      if (_lastFailureTime != null &&
          DateTime.now().difference(_lastFailureTime!) > _resetDuration) {
        _failureCount = 0;
        return false;
      }
      return true;
    }
    return false;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
  }

  void recordSuccess() {
    _failureCount = 0;
  }
}

// ============================================================================
// FAVORITE PROVIDER - Simplified, Fast, Scalable
// ============================================================================
class FavoriteProvider with ChangeNotifier, LifecycleAwareMixin {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final MetricsEventService _metricsService = MetricsEventService.instance;

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.normal;
  // Rate limiters
  final _addFavoriteLimiter = _RateLimiter(Duration(milliseconds: 300));
  final _removeFavoriteLimiter = _RateLimiter(Duration(milliseconds: 200));

  // Circuit breaker
  final _circuitBreaker = _CircuitBreaker();
  final ValueNotifier<Set<String>> globalFavoriteIdsNotifier =
      ValueNotifier({});
  // Public reactive state
  final ValueNotifier<Set<String>> favoriteIdsNotifier = ValueNotifier({});
  final ValueNotifier<int> favoriteCountNotifier = ValueNotifier(0);
  final ValueNotifier<List<Map<String, dynamic>>> paginatedFavoritesNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> selectedBasketNotifier = ValueNotifier(null);
  final ValueNotifier<bool> hasMoreDataNotifier = ValueNotifier(true);
  final ValueNotifier<bool> isLoadingMoreNotifier = ValueNotifier(false);

  // Individual product notifiers (for surgical updates)
  final Map<String, ValueNotifier<bool>> _favoriteStatusNotifiers = {};
  static const int _maxNotifiers = 200;

  // Concurrency control
  final Map<String, Completer<void>> _favoriteLocks = {};

  // Request coalescing
  final Map<String, Completer<void>> _pendingFetches = {};

  // Pagination state
  DocumentSnapshot? _lastDocument;
  final Map<String, Map<String, dynamic>> _paginatedFavoritesMap = {};
  static const int _maxPaginatedCache = 200;
  String? _currentBasketId;
  bool _isInitialLoadComplete = false;

  // Firestore listeners
  StreamSubscription<QuerySnapshot>? _favoriteSubscription;
  StreamSubscription<User?>? _authSubscription;

  // Timers
  Timer? _removeFavoriteTimer;
  Timer? _cleanupTimer;

  bool _disposed = false;

  // Public getters
  int get favoriteCount => favoriteCountNotifier.value;
  Set<String> get favoriteProductIds => favoriteIdsNotifier.value;
  List<Map<String, dynamic>> get paginatedFavorites =>
      paginatedFavoritesNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  bool get hasMoreData => hasMoreDataNotifier.value;
  bool get isLoadingMore => isLoadingMoreNotifier.value;
  bool get isInitialLoadComplete => _isInitialLoadComplete;
  String? get selectedBasketId => selectedBasketNotifier.value;

  FavoriteProvider(this._auth, this._firestore) {
    _initializeProvider();

    // Register with lifecycle manager
    AppLifecycleManager.instance.register(this, name: 'FavoriteProvider');
  }

  void _initializeProvider() {
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
      debugPrint('⏸️ FavoriteProvider: Listener and timer paused');
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

    // Re-enable real-time updates
    if (favoriteIdsNotifier.value.isNotEmpty || _isInitialLoadComplete) {
      enableLiveUpdates();

      // If long pause, reload favorite IDs
      if (shouldFullRefresh(pauseDuration)) {
        if (kDebugMode) {
          debugPrint(
              '🔄 FavoriteProvider: Long pause, refreshing favorites...');
        }
        // Background reload - don't block UI.
        // _loadGlobalFavoriteIds also sets favoriteIdsNotifier when no basket is selected.
        _loadGlobalFavoriteIds();
        if (selectedBasketNotifier.value != null) {
          _loadFavoriteIds();
        }
      }
    }

    if (kDebugMode) {
      debugPrint('▶️ FavoriteProvider: Listener and timer resumed');
    }
  }

  void _cleanupStaleOperations() {
    // Force cleanup locks older than 10 seconds
    _favoriteLocks.removeWhere((key, completer) {
      if (!completer.isCompleted) {
        completer.complete();
        return true;
      }
      return false;
    });

    // Cleanup old notifiers
    final activeIds = favoriteIdsNotifier.value;
    _favoriteStatusNotifiers.removeWhere((id, _) => !activeIds.contains(id));

    // Cleanup pagination cache if too large
    if (_paginatedFavoritesMap.length > _maxPaginatedCache) {
      final keysToRemove = _paginatedFavoritesMap.keys.take(50).toList();
      for (final key in keysToRemove) {
        _paginatedFavoritesMap.remove(key);
      }
    }
  }

  // ========================================================================
  // SMART REAL-TIME LISTENER (Auto-manages connection)
  // ========================================================================

  /// Enable real-time updates (Firestore snapshots)
  void enableLiveUpdates() {
    final user = _auth.currentUser;
    if (user == null) return;

    _favoriteSubscription?.cancel();
    _favoriteSubscription = null;

    debugPrint('🔴 Enabling real-time favorites listener');

    final basketId = selectedBasketNotifier.value;
    final collection =
        basketId == null ? 'favorites' : 'favorite_baskets/$basketId/favorites';

    _favoriteSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .collection(collection)
        .snapshots(includeMetadataChanges: false)
        .listen(
          _handleRealtimeUpdate,
          onError: (e) => debugPrint('❌ Listener error: $e'),
        );
  }

  /// Disable real-time updates (save battery/bandwidth)
  void disableLiveUpdates() {
    debugPrint('🔴 Disabling favorites listener');
    _favoriteSubscription?.cancel();
    _favoriteSubscription = null;
  }

  void _handleRealtimeUpdate(QuerySnapshot snapshot) {
    if (snapshot.metadata.isFromCache) {
      debugPrint('⏭️ Skipping cache event');
      return;
    }

    debugPrint('🔥 Real-time update: ${snapshot.docChanges.length} changes');

    final ids = snapshot.docs
        .map((doc) =>
            (doc.data() as Map<String, dynamic>)['productId'] as String?)
        .whereType<String>()
        .toSet();

    favoriteIdsNotifier.value = ids;
    favoriteCountNotifier.value = ids.length;

    // Update individual notifiers
    for (final id in ids) {
      _updateProductFavoriteStatus(id, true);
    }

    notifyListeners();
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  Future<void> initializeIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Request coalescing
    if (_pendingFetches.containsKey('init')) {
      debugPrint('⏳ Already initializing, waiting...');
      await _pendingFetches['init']!.future;
      return;
    }

    final completer = Completer<void>();
    _pendingFetches['init'] = completer;

    try {
      // _loadGlobalFavoriteIds reads default + all baskets, and also populates
      // favoriteIdsNotifier when no basket is selected (avoids duplicate read).
      await _loadGlobalFavoriteIds();

      // Only read the specific basket collection if a basket is actively selected,
      // since _loadGlobalFavoriteIds already covered the default case.
      if (selectedBasketNotifier.value != null) {
        await _loadFavoriteIds();
      }

      enableLiveUpdates();
      completer.complete();
    } catch (e) {
      debugPrint('❌ Init error: $e');
      completer.completeError(e);
    } finally {
      _pendingFetches.remove('init');
    }
  }

  /// Loads all favorite IDs across default + all baskets.
  /// Also populates [favoriteIdsNotifier] from the default collection
  /// when no basket is selected, avoiding a redundant Firestore read.
  Future<void> _loadGlobalFavoriteIds() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final allIds = <String>{};
      final defaultIds = <String>{};

      // 1. Load default favorites
      final defaultSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .get();

      for (final doc in defaultSnapshot.docs) {
        final productId = doc.data()['productId'] as String?;
        if (productId != null) {
          defaultIds.add(productId);
          allIds.add(productId);
        }
      }

      // 2. Load ALL basket favorites
      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .get();

      for (final basketDoc in basketsSnapshot.docs) {
        final basketFavoritesSnapshot =
            await basketDoc.reference.collection('favorites').get();

        for (final favDoc in basketFavoritesSnapshot.docs) {
          final productId = favDoc.data()['productId'] as String?;
          if (productId != null) allIds.add(productId);
        }
      }

      globalFavoriteIdsNotifier.value = allIds;

      // If no basket is selected, reuse the default favorites we already fetched
      // instead of making a separate _loadFavoriteIds() call.
      if (selectedBasketNotifier.value == null) {
        favoriteIdsNotifier.value = defaultIds;
        favoriteCountNotifier.value = defaultIds.length;
        notifyListeners();
      }

      debugPrint('✅ Loaded ${allIds.length} global favorite IDs');
    } catch (e) {
      debugPrint('❌ Error loading global favorites: $e');
    }
  }

  Future<void> _loadFavoriteIds() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final basketId = selectedBasketNotifier.value;

      // Fetch from Firestore (with cache-first strategy built-in)
      final collection = basketId == null
          ? 'favorites'
          : 'favorite_baskets/$basketId/favorites';

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection(collection)
          .get(); // Firestore automatically uses cache when offline

      final ids = snapshot.docs
          .map((doc) => (doc.data()['productId'] as String?))
          .whereType<String>()
          .toSet();

      favoriteIdsNotifier.value = ids;
      favoriteCountNotifier.value = ids.length;

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Load favorites error: $e');
    }
  }

  void _handleUserChange(User? user) {
    disableLiveUpdates();

    if (user == null) {
      _clearAllData();
      return;
    }

    _clearAllData();
    initializeIfNeeded();
  }

  void _clearAllData() {
    favoriteCountNotifier.value = 0;
    favoriteIdsNotifier.value = {};
    globalFavoriteIdsNotifier.value = {};
    paginatedFavoritesNotifier.value = [];
    isLoadingNotifier.value = false;
    selectedBasketNotifier.value = null;
    _paginatedFavoritesMap.clear();
    _isInitialLoadComplete = false;
  }

  // ========================================================================
  // ADD/REMOVE FAVORITES (Optimistic + Firestore)
  // ========================================================================

  Future<Map<String, String?>> _getProductMetadata(String productId) async {
    try {
      // Parallel fetch from both collections
      final results = await Future.wait([
        _firestore.collection('products').doc(productId).get(),
        _firestore.collection('shop_products').doc(productId).get(),
      ]);

      final productDoc = results[0];
      final shopProductDoc = results[1];

      // Use whichever exists (prefer products collection)
      final Map<String, dynamic>? data = productDoc.exists
          ? productDoc.data()
          : shopProductDoc.exists
              ? shopProductDoc.data()
              : null;

      if (data == null) return {};

      return {
        'shopId': data['shopId'] as String?,
        'productName': data['productName'] as String?,
        'category': data['category'] as String?,
        'subcategory': data['subcategory'] as String?, // ✅ ADD
        'subsubcategory': data['subsubcategory'] as String?,
        'brand': data['brandModel'] as String?,
        'gender': data['gender'] as String?,
      };
    } catch (e) {
      debugPrint('⚠️ Failed to get product metadata: $e');
      return {};
    }
  }

  Future<void> addToFavorites(
    String productId, {
    required BuildContext context,
    String? selectedColor,
    String? selectedColorImage,
    int? quantity,
    Map<String, dynamic>? additionalAttributes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Rate limiting
    if (!_addFavoriteLimiter.canProceed('add_$productId')) {
      debugPrint('⏱️ Rate limit: Please wait before adding again');
      return;
    }

    // Concurrency control
    if (_favoriteLocks.containsKey(productId)) {
      debugPrint('⏳ Operation already in progress for $productId');
      await _favoriteLocks[productId]!.future;
      return;
    }

    final completer = Completer<void>();
    _favoriteLocks[productId] = completer;

    // Circuit breaker
    if (_circuitBreaker.isOpen) {
      debugPrint('⚠️ Circuit breaker open - rejecting operation');
      _favoriteLocks.remove(productId);
      completer.complete();
      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar(context, l10n.serviceTemporarilyUnavailable);
      return;
    }

    final basketId = selectedBasketNotifier.value;
    final collection = basketId == null
        ? _firestore.collection('users').doc(user.uid).collection('favorites')
        : _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorite_baskets')
            .doc(basketId)
            .collection('favorites');

    // Store previous state for rollback
    final wasFavorited = favoriteIdsNotifier.value.contains(productId);
    bool isRemoving = false;

    try {
      // Check if already favorited
      final existingSnap =
          await collection.where('productId', isEqualTo: productId).get();
      isRemoving = existingSnap.docs.isNotEmpty;

      if (isRemoving) {
        // STEP 1: Optimistic removal
        final newIds = Set<String>.from(favoriteIdsNotifier.value)
          ..remove(productId);
        favoriteIdsNotifier.value = newIds;
        favoriteCountNotifier.value = newIds.length;
        _updateProductFavoriteStatus(productId, false);
        removeItemFromPaginatedCache(productId);

        // STEP 2: Delete from Firestore
        await existingSnap.docs.first.reference.delete();

        final newGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value)
          ..remove(productId);
        globalFavoriteIdsNotifier.value = newGlobalIds;

        final metadata = await _getProductMetadata(productId);
        final shopId = metadata['shopId'];
        final productName =
            existingSnap.docs.first.data()['productName'] as String?;
        UserActivityService.instance.trackUnfavorite(
          productId: productId,
          shopId: shopId,
          productName: productName,
          category: metadata['category'],
          brand: metadata['brand'],
          gender: metadata['gender'],
        );
        _metricsService.logFavoriteRemoved(
          productId: productId,
          shopId: shopId,
        );

        _circuitBreaker.recordSuccess();
        showDebouncedRemoveFavoriteSnackbar(context);
      } else {
        // STEP 1: Optimistic add
        final newIds = Set<String>.from(favoriteIdsNotifier.value)
          ..add(productId);
        favoriteIdsNotifier.value = newIds;
        favoriteCountNotifier.value = newIds.length;
        _updateProductFavoriteStatus(productId, true);

        // STEP 2: Add to Firestore
        final favoriteData = <String, dynamic>{
          'productId': productId,
          'addedAt': FieldValue.serverTimestamp(),
          'quantity': quantity ?? 1,
        };

        if (selectedColor != null) {
          favoriteData['selectedColor'] = selectedColor;
          if (selectedColorImage != null) {
            favoriteData['selectedColorImage'] = selectedColorImage;
          }
        }

        if (additionalAttributes != null) {
          additionalAttributes.forEach((k, v) {
            if (!['addedAt', 'productId', 'quantity'].contains(k)) {
              favoriteData[k] = v;
            }
          });
        }

        await collection.add(favoriteData);

        final newGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value)
          ..add(productId);
        globalFavoriteIdsNotifier.value = newGlobalIds;

        final metadata = await _getProductMetadata(productId);
        final shopId = metadata['shopId'];
        UserActivityService.instance.trackFavorite(
          productId: productId,
          shopId: metadata['shopId'],
          productName: metadata['productName'],
          category: metadata['category'],
          subcategory: metadata['subcategory'],
          subsubcategory: metadata['subsubcategory'],
          brand: metadata['brand'],
          gender: metadata['gender'],
        );
        _metricsService.logFavoriteAdded(
          productId: productId,
          shopId: shopId,
        );

        // STEP 4: Add to pagination cache
        await addItemToPaginatedCache(productId);

        _circuitBreaker.recordSuccess();
        _showSuccessSnackbar(context, 'Added to favorites');
      }
    } catch (e) {
      debugPrint('❌ Favorite operation error: $e');
      _circuitBreaker.recordFailure();

      // Rollback
      if (wasFavorited) {
        favoriteIdsNotifier.value = Set<String>.from(favoriteIdsNotifier.value)
          ..add(productId);
        _updateProductFavoriteStatus(productId, true);
        if (isRemoving) addItemToPaginatedCache(productId);
      } else {
        favoriteIdsNotifier.value = Set<String>.from(favoriteIdsNotifier.value)
          ..remove(productId);
        _updateProductFavoriteStatus(productId, false);
        if (!isRemoving) removeItemFromPaginatedCache(productId);
      }
      favoriteCountNotifier.value = favoriteIdsNotifier.value.length;

      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar(context, l10n.failedToUpdateFavorites);
    } finally {
      _favoriteLocks.remove(productId);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  // ========================================================================
  // BATCH OPERATIONS
  // ========================================================================

  Future<String> removeMultipleFromFavorites(List<String> productIds) async {
    final user = _auth.currentUser;
    if (user == null) return 'pleaseLoginFirst';
    if (productIds.isEmpty) return 'noProductsSelected';

    if (!_removeFavoriteLimiter.canProceed('batch_remove')) {
      return 'pleaseWait';
    }

    final previousIds = Set<String>.from(favoriteIdsNotifier.value);
    final previousGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value);

    try {
      // Fetch metadata for all products
      final metadataMap = <String, Map<String, String?>>{};
      for (final productId in productIds) {
        metadataMap[productId] = await _getProductMetadata(productId);
      }

      // Extract shopIds for metrics
      final shopIds = Map.fromEntries(
        productIds.map((id) => MapEntry(id, metadataMap[id]?['shopId'])),
      );

      // Optimistic removal from BOTH notifiers
      final newIds = Set<String>.from(favoriteIdsNotifier.value)
        ..removeAll(productIds);
      favoriteIdsNotifier.value = newIds;
      favoriteCountNotifier.value = newIds.length;

      final newGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value)
        ..removeAll(productIds);
      globalFavoriteIdsNotifier.value = newGlobalIds;

      for (final id in productIds) {
        _updateProductFavoriteStatus(id, false);
      }
      removePaginatedItems(productIds);

      // Batch delete from Firestore
      const batchSize = 50;
      for (var i = 0; i < productIds.length; i += batchSize) {
        final chunk = productIds.skip(i).take(batchSize).toList();
        await _removeMultipleBatch(chunk);
      }

      _metricsService.logBatchFavoriteRemovals(
        productIds: productIds,
        shopIds: shopIds,
      );

      return 'Products removed from favorites';
    } catch (e) {
      debugPrint('❌ Batch remove error: $e');

      // Rollback BOTH notifiers
      favoriteIdsNotifier.value = previousIds;
      favoriteCountNotifier.value = previousIds.length;
      globalFavoriteIdsNotifier.value = previousGlobalIds;

      return 'errorRemovingFavorites';
    }
  }

  Future<void> _removeMultipleBatch(List<String> productIds) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final basketId = selectedBasketNotifier.value;
    final collection = basketId == null
        ? _firestore.collection('users').doc(user.uid).collection('favorites')
        : _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorite_baskets')
            .doc(basketId)
            .collection('favorites');

    final batch = _firestore.batch();

    // Process in chunks of 10 (Firestore limit for whereIn)
    for (var i = 0; i < productIds.length; i += 10) {
      final chunk = productIds.skip(i).take(10).toList();
      final snap = await collection.where('productId', whereIn: chunk).get();

      for (var doc in snap.docs) {
        batch.delete(doc.reference);
      }
    }

    // ✅ ONLY delete favorites - metrics handled by Cloud Functions
    await batch.commit();
  }

  // ========================================================================
  // BASKET MANAGEMENT
  // ========================================================================

  void setSelectedBasket(String? basketId) {
    selectedBasketNotifier.value = basketId;
    if (_currentBasketId != basketId) {
      _currentBasketId = basketId;
      resetPagination();
    }
    notifyListeners();
  }

  // ✅ ENHANCED VERSION: Transfer to basket OR default favorites
  Future<String> transferToBasket(
      String productId, String? targetBasketId) async {
    final user = _auth.currentUser;
    if (user == null) return 'pleaseLoginFirst';

    try {
      // Step 1: Get the favorite item data from current location
      CollectionReference currentCollection;
      final currentBasketId = selectedBasketNotifier.value;

      if (currentBasketId == null) {
        // From default favorites
        currentCollection = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorites');
      } else {
        // From another basket
        currentCollection = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorite_baskets')
            .doc(currentBasketId)
            .collection('favorites');
      }

      // Find the item
      final itemSnapshot = await currentCollection
          .where('productId', isEqualTo: productId)
          .limit(1)
          .get();

      if (itemSnapshot.docs.isEmpty) {
        return 'itemNotFound';
      }

      final itemData = itemSnapshot.docs.first.data() as Map<String, dynamic>;

      // Step 2: Add to target location
      if (targetBasketId == null) {
        // Transfer to default favorites
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorites')
            .add({
          ...itemData,
          'addedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Transfer to basket
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favorite_baskets')
            .doc(targetBasketId)
            .collection('favorites')
            .add({
          ...itemData,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }

      // Step 3: Remove from current location
      await itemSnapshot.docs.first.reference.delete();

      // Step 4: Update cache
      removeItemFromPaginatedCache(productId);

      debugPrint(
          '✅ Transferred $productId to ${targetBasketId ?? "default favorites"}');
      return 'Transferred successfully';
    } catch (e) {
      debugPrint('❌ Transfer error: $e');
      return 'errorTransferringItem';
    }
  }

  Future<String> createFavoriteBasket(
    String name, {
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'pleaseLoginFirst';

    try {
      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .get();

      if (basketsSnapshot.docs.length >= 10) {
        return 'maximumBasketLimit';
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .add({'name': name, 'createdAt': FieldValue.serverTimestamp()});

      if (context != null && context.mounted) {
        _showSuccessSnackbar(context, 'Basket created');
      }

      return 'Basket created';
    } catch (e) {
      debugPrint('Error creating basket: $e');
      return 'errorCreatingBasket';
    }
  }

  Future<String> deleteFavoriteBasket(
    String basketId, {
    BuildContext? context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 'pleaseLoginFirst';

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .doc(basketId)
          .delete();

      if (selectedBasketNotifier.value == basketId) {
        setSelectedBasket(null);
      }

      if (context != null && context.mounted) {
        _showDebouncedBasketDeletionSnackbar(context);
      }

      return 'Basket deleted';
    } catch (e) {
      debugPrint('Error deleting basket: $e');
      return 'errorDeletingBasket';
    }
  }

  // ========================================================================
  // PAGINATION
  // ========================================================================

  Future<Map<String, dynamic>> fetchPaginatedFavorites({
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return {'docs': <DocumentSnapshot>[], 'hasMore': false};

    final basketId = selectedBasketNotifier.value;
    final collection =
        basketId == null ? 'favorites' : 'favorite_baskets/$basketId/favorites';

    debugPrint(
        '🟡 fetchPaginatedFavorites: limit=$limit, collection=$collection');

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection(collection)
        .orderBy('addedAt', descending: true)
        .limit(limit + 1);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final hasMore = snapshot.docs.length > limit;
    final docs = hasMore ? snapshot.docs.take(limit).toList() : snapshot.docs;

    debugPrint(
        '🟡 fetchPaginatedFavorites RESULT: fetched=${snapshot.docs.length}, limit=$limit, hasMore=$hasMore (${snapshot.docs.length} > $limit), returning ${docs.length} docs');

    return {
      'docs': docs,
      'hasMore': hasMore,
      'productIds': docs
          .map((d) => d.data()['productId'] as String?)
          .whereType<String>()
          .toSet(),
    };
  }

  Future<Map<String, dynamic>> loadNextPage({int limit = 50}) async {
    debugPrint(
        '🔵 loadNextPage START: isLoading=${isLoadingMoreNotifier.value}, hasMore=${hasMoreDataNotifier.value}');

    if (isLoadingMoreNotifier.value || !hasMoreDataNotifier.value) {
      debugPrint('🔵 loadNextPage SKIP: Already loading or no more data');
      return {
        'docs': <DocumentSnapshot>[],
        'hasMore': false,
        'error': null,
      };
    }

    isLoadingMoreNotifier.value = true;
    notifyListeners();
    debugPrint('🔵 loadNextPage: Set isLoading=true, called notifyListeners()');

    try {
      final result = await fetchPaginatedFavorites(
        startAfter: _lastDocument,
        limit: limit,
      );

      final docs = result['docs'] as List<DocumentSnapshot>;
      final hasMore = result['hasMore'] as bool;

      debugPrint(
          '🔵 loadNextPage RESULT: docs=${docs.length}, hasMore=$hasMore, limit=$limit');

      if (docs.isNotEmpty) {
        _lastDocument = docs.last;
        hasMoreDataNotifier.value = hasMore;
        debugPrint(
            '🔵 loadNextPage: Set hasMoreData=$hasMore (docs not empty)');
      } else {
        hasMoreDataNotifier.value = false;
        debugPrint('🔵 loadNextPage: Set hasMoreData=false (docs empty)');
      }

      isLoadingMoreNotifier.value = false;
      notifyListeners();
      debugPrint(
          '🔵 loadNextPage END: Set isLoading=false, hasMore=${hasMoreDataNotifier.value}, called notifyListeners()');

      return {
        'docs': docs,
        'hasMore': hasMore,
        'productIds': result['productIds'],
        'error': null,
      };
    } catch (e) {
      debugPrint('❌ loadNextPage ERROR: $e');
      isLoadingMoreNotifier.value = false;
      hasMoreDataNotifier.value = false;
      notifyListeners();

      return {
        'docs': <DocumentSnapshot>[],
        'hasMore': false,
        'error': e.toString(),
      };
    }
  }

  void addPaginatedItems(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final productId = item['productId'] as String;
      if (!_paginatedFavoritesMap.containsKey(productId)) {
        if (_paginatedFavoritesMap.length >= _maxPaginatedCache) {
          final firstKey = _paginatedFavoritesMap.keys.first;
          _paginatedFavoritesMap.remove(firstKey);
        }
        _paginatedFavoritesMap[productId] = item;
      }
    }
    paginatedFavoritesNotifier.value = _paginatedFavoritesMap.values.toList();

    if (paginatedFavoritesNotifier.value.isNotEmpty &&
        !_isInitialLoadComplete) {
      _isInitialLoadComplete = true;
    }
  }

  void removePaginatedItems(List<String> productIds) {
    for (final id in productIds) {
      _paginatedFavoritesMap.remove(id);
    }
    paginatedFavoritesNotifier.value = _paginatedFavoritesMap.values.toList();
  }

  Future<void> addItemToPaginatedCache(String productId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final currentBasket = selectedBasketNotifier.value;
    if (_currentBasketId != currentBasket) return;
    if (_paginatedFavoritesMap.containsKey(productId)) return;

    try {
      final collection = currentBasket == null
          ? 'favorites'
          : 'favorite_baskets/$currentBasket/favorites';

      final favDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection(collection)
          .where('productId', isEqualTo: productId)
          .limit(1)
          .get();

      if (favDoc.docs.isEmpty) return;

      final favoriteData = favDoc.docs.first.data();

      // Fetch product
      final productRefs = await Future.wait([
        _firestore.collection('products').doc(productId).get(),
        _firestore.collection('shop_products').doc(productId).get(),
      ]);

      DocumentSnapshot? productDoc;
      if (productRefs[0].exists) {
        productDoc = productRefs[0];
      } else if (productRefs[1].exists) {
        productDoc = productRefs[1];
      }

      if (productDoc == null || !productDoc.exists) return;

      final product = Product.fromDocument(productDoc);
      final attributes = Map<String, dynamic>.from(favoriteData)
        ..remove('productId');

      final newItem = {
        'product': product,
        'attributes': attributes,
        'productId': productId,
      };

      _paginatedFavoritesMap[productId] = newItem;
      paginatedFavoritesNotifier.value = _paginatedFavoritesMap.values.toList();

      debugPrint('✅ Added $productId to cache');
    } catch (e) {
      debugPrint('Error adding item to cache: $e');
    }
  }

  void removeItemFromPaginatedCache(String productId) {
    if (_paginatedFavoritesMap.containsKey(productId)) {
      _paginatedFavoritesMap.remove(productId);
      paginatedFavoritesNotifier.value = _paginatedFavoritesMap.values.toList();
      debugPrint('✅ Removed $productId from cache');
    }
  }

  void resetPagination() {
    debugPrint('🟣 resetPagination: Resetting pagination state');
    _lastDocument = null;
    hasMoreDataNotifier.value = true;
    isLoadingMoreNotifier.value = false;
    _paginatedFavoritesMap.clear();
    paginatedFavoritesNotifier.value = [];
    _isInitialLoadComplete = false;
    notifyListeners();
    debugPrint(
        '🟣 resetPagination END: hasMore=true, isLoading=false, cleared all data');
  }

  bool shouldReloadFavorites(String? basketId) {
    // Always reload if basket changed
    if (_currentBasketId != basketId) return true;
    // Always reload if initial full load was never completed
    // (handles case where only optimistic cache exists from addToFavorites)
    if (!_isInitialLoadComplete) return true;
    return false;
  }

  void markInitialLoadComplete() {
    if (!_isInitialLoadComplete) {
      _isInitialLoadComplete = true;
      notifyListeners();
    }
  }

  // ========================================================================
  // INDIVIDUAL PRODUCT NOTIFIERS (Surgical updates)
  // ========================================================================

  ValueNotifier<bool> getFavoriteStatusNotifier(String productId) {
    if (!_favoriteStatusNotifiers.containsKey(productId)) {
      if (_favoriteStatusNotifiers.length >= _maxNotifiers) {
        final firstKey = _favoriteStatusNotifiers.keys.first;
        _favoriteStatusNotifiers[firstKey]?.dispose();
        _favoriteStatusNotifiers.remove(firstKey);
      }
      _favoriteStatusNotifiers[productId] = ValueNotifier<bool>(
        favoriteIdsNotifier.value.contains(productId),
      );
    }
    return _favoriteStatusNotifiers[productId]!;
  }

  void _updateProductFavoriteStatus(String productId, bool isFavorited) {
    if (_favoriteStatusNotifiers.containsKey(productId)) {
      _favoriteStatusNotifiers[productId]!.value = isFavorited;
    }
  }

  // ========================================================================
  // UI FEEDBACK
  // ========================================================================

  void showDebouncedRemoveFavoriteSnackbar(BuildContext context) {
    _removeFavoriteTimer?.cancel();
    _removeFavoriteTimer = Timer(const Duration(milliseconds: 500), () {
      _showSuccessSnackbar(context, 'Removed from favorites');
    });
  }

  void _showDebouncedBasketDeletionSnackbar(BuildContext context) {
    Timer(const Duration(milliseconds: 500), () {
      _showSuccessSnackbar(context, 'Basket deleted');
    });
  }

  void _showSuccessSnackbar(BuildContext context, String messageKey) {
    if (!context.mounted) return;

    try {
      final l10n = AppLocalizations.of(context);
      String localizedMessage;

      switch (messageKey) {
        case 'Added to favorites':
          localizedMessage = l10n.addedToFavorites ?? 'Added to favorites';
          break;
        case 'Removed from favorites':
          localizedMessage =
              l10n.removedFromFavorites ?? 'Removed from favorites';
          break;
        case 'Basket created':
          localizedMessage = l10n.basketCreated ?? 'Basket created';
          break;
        case 'Basket deleted':
          localizedMessage = l10n.basketDeleted ?? 'Basket deleted';
          break;
        case 'productsRemovedFromFavorites':
          localizedMessage = l10n.productsRemovedFromFavorites;
          break;
        case 'errorRemovingFavorites':
          localizedMessage = l10n.errorRemovingFavorites;
          break;
        case 'errorTransferringItem':
          localizedMessage = l10n.errorTransferringItem;
          break;
        case 'maximumBasketLimit':
          localizedMessage = l10n.maximumBasketLimit;
          break;
        case 'errorCreatingBasket':
          localizedMessage = l10n.errorCreatingBasket;
          break;
        case 'errorDeletingBasket':
          localizedMessage = l10n.errorDeletingBasket;
          break;
        default:
          localizedMessage = messageKey;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(localizedMessage),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint('Error showing success message: $e');
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ========================================================================
  // HELPER METHODS (Backward Compatibility)
  // ========================================================================

  void addToGlobalFavorites(Set<String> productIds) {
    if (productIds.isEmpty) return;

    final newGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value)
      ..addAll(productIds);
    globalFavoriteIdsNotifier.value = newGlobalIds;

    debugPrint('✅ Added ${productIds.length} products to global favorites');
  }

  /// Refresh global favorites from Firestore (useful after external changes)
  Future<void> refreshGlobalFavorites() async {
    await _loadGlobalFavoriteIds();
  }

  /// Check if product is favorited (default favorites or any basket)
  bool isGloballyFavorited(String productId) {
    return globalFavoriteIdsNotifier.value
        .contains(productId); // Checks ALL favorites
  }

  /// Check if product is favorited in a basket (not default favorites)
  Future<bool> isFavoritedInBasket(String productId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .get();

      for (final basketDoc in basketsSnapshot.docs) {
        final favoriteSnapshot = await basketDoc.reference
            .collection('favorites')
            .where('productId', isEqualTo: productId)
            .limit(1)
            .get();

        if (favoriteSnapshot.docs.isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking basket favorites: $e');
      return false;
    }
  }

  /// Get basket name for a product
  Future<String?> getBasketNameForProduct(String productId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .get();

      for (final basketDoc in basketsSnapshot.docs) {
        final favoriteSnapshot = await basketDoc.reference
            .collection('favorites')
            .where('productId', isEqualTo: productId)
            .limit(1)
            .get();

        if (favoriteSnapshot.docs.isNotEmpty) {
          final basketData = basketDoc.data();
          return basketData['name'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting basket name: $e');
      return null;
    }
  }

  /// Remove from favorites (works for default and baskets)
  Future<void> removeGloballyFromFavorites(String productId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Optimistic removal from BOTH notifiers
    final previousIds = Set<String>.from(favoriteIdsNotifier.value);
    final previousGlobalIds = Set<String>.from(globalFavoriteIdsNotifier.value);

    favoriteIdsNotifier.value = Set<String>.from(previousIds)
      ..remove(productId);
    favoriteCountNotifier.value = favoriteIdsNotifier.value.length;
    globalFavoriteIdsNotifier.value = Set<String>.from(previousGlobalIds)
      ..remove(productId);
    _updateProductFavoriteStatus(productId, false);
    removeItemFromPaginatedCache(productId);

    try {
      final metadata = await _getProductMetadata(productId);
      final shopId = metadata['shopId'];

      // Remove from default favorites
      final defaultFavsSnap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .where('productId', isEqualTo: productId)
          .get();

      for (final doc in defaultFavsSnap.docs) {
        await doc.reference.delete();
      }

      // Remove from all baskets
      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favorite_baskets')
          .get();

      for (final basketDoc in basketsSnapshot.docs) {
        final favoriteSnapshot = await basketDoc.reference
            .collection('favorites')
            .where('productId', isEqualTo: productId)
            .get();

        for (final favDoc in favoriteSnapshot.docs) {
          await favDoc.reference.delete();
        }
      }

      _metricsService.logFavoriteRemoved(
        productId: productId,
        shopId: shopId,
      );

      debugPrint('✅ Removed $productId from all favorites');
    } catch (e) {
      debugPrint('❌ Error removing from favorites: $e');

      // Rollback BOTH notifiers
      favoriteIdsNotifier.value = previousIds;
      favoriteCountNotifier.value = previousIds.length;
      globalFavoriteIdsNotifier.value = previousGlobalIds;
      _updateProductFavoriteStatus(productId, true);
    }
  }

  // ========================================================================
  // CLEANUP
  // ========================================================================

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    debugPrint('🧹 FavoriteProvider disposing...');

    _cleanupTimer?.cancel();
    _removeFavoriteTimer?.cancel();
    disableLiveUpdates();
    _authSubscription?.cancel();

    favoriteIdsNotifier.dispose();
    favoriteCountNotifier.dispose();
    paginatedFavoritesNotifier.dispose();
    globalFavoriteIdsNotifier.dispose();
    isLoadingNotifier.dispose();
    selectedBasketNotifier.dispose();
    hasMoreDataNotifier.dispose();
    isLoadingMoreNotifier.dispose();

    for (final notifier in _favoriteStatusNotifiers.values) {
      notifier.dispose();
    }
    _favoriteStatusNotifiers.clear();

    _favoriteLocks.clear();
    _paginatedFavoritesMap.clear();

    super.dispose();
  }
}
