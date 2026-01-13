import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/lifecycle_aware.dart';
import '../services/app_lifecycle_manager.dart';

/// Highly optimized provider for managing boosted product rotation
/// Uses real-time listeners and caching for maximum performance
class BoostedRotationProvider extends ChangeNotifier with LifecycleAwareMixin {
  final FirebaseFirestore _firestore;

  // State management
  List<String> _boostedSlots = [];
  List<Product> _boostedProducts = []; // Changed to List<Product>
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdate;
  int _totalBoosted = 0;

  // Cache management
  final Map<String, _CacheEntry> _productCache = {};
  static const Duration _cacheExpiry = Duration(minutes: 10);
  static const int _maxCacheSize = 100;

  // Listener management
  dynamic _slotsListener;
  bool _isDisposed = false;
  bool _isInitializing = false; // Race condition fix
  bool _wasInitializedBeforePause = false;

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.background;

  // Getters
  List<Product> get boostedProducts => _boostedProducts;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasProducts => _boostedProducts.isNotEmpty;
  int get totalBoosted => _totalBoosted;
  DateTime? get lastUpdate => _lastUpdate;

  BoostedRotationProvider({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    // Register with lifecycle manager
    AppLifecycleManager.instance.register(this, name: 'BoostedRotationProvider');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> onPause() async {
    await super.onPause();

    // Track if we were initialized before pause
    _wasInitializedBeforePause = _slotsListener != null;

    // Cancel the slots listener to save resources
    _slotsListener?.cancel();
    _slotsListener = null;

    if (kDebugMode) {
      debugPrint('⏸️ BoostedRotationProvider: Listener paused');
    }
  }

  @override
  Future<void> onResume(Duration pauseDuration) async {
    await super.onResume(pauseDuration);

    // Only re-initialize if we were previously initialized
    if (_wasInitializedBeforePause) {
      // Clear cache if long pause
      if (shouldFullRefresh(pauseDuration)) {
        _productCache.clear();
        if (kDebugMode) {
          debugPrint('🔄 BoostedRotationProvider: Long pause, clearing cache');
        }
      }

      // Re-initialize the listener
      await initialize();
    }

    if (kDebugMode) {
      debugPrint('▶️ BoostedRotationProvider: Listener resumed');
    }
  }

  /// Initialize the provider and start listening to slot changes
  Future<void> initialize() async {
    // Thread-safe check
    if (_slotsListener != null || _isInitializing) return;

    _isInitializing = true;
    _isLoading = true;
    notifyListeners();

    try {
      // Set up real-time listener for slots document
      _slotsListener = _firestore
          .collection('boosted_rotation')
          .doc('boosted_slots')
          .snapshots()
          .listen(
            _onSlotsUpdate,
            onError: _onSlotsError,
            cancelOnError: false,
          );
    } catch (e) {
      _error = 'Failed to initialize: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    } finally {
      _isInitializing = false;
    }
  }

  /// Handle real-time updates to slots document
  Future<void> _onSlotsUpdate(DocumentSnapshot snapshot) async {
    if (_isDisposed) return;

    try {
      if (!snapshot.exists || snapshot.data() == null) {
        _boostedSlots = [];
        _boostedProducts = [];
        _totalBoosted = 0;
        _error = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final List<String> newSlots = List<String>.from(data['slots'] ?? []);

      _totalBoosted = data['totalBoosted'] ?? 0;
      _lastUpdate = (data['lastUpdate'] as Timestamp?)?.toDate();

      // Check if slots actually changed
      if (_slotsChanged(newSlots)) {
        _boostedSlots = newSlots;
        await _fetchProducts();
      } else {
        // Slots didn't change, just update metadata
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to process slots: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Handle errors from slots listener
  void _onSlotsError(dynamic error) {
    if (_isDisposed) return;

    _error = 'Connection error: ${error.toString()}';
    _isLoading = false;
    notifyListeners();
  }

  /// Check if slots have actually changed
  bool _slotsChanged(List<String> newSlots) {
    if (_boostedSlots.length != newSlots.length) return true;

    for (int i = 0; i < newSlots.length; i++) {
      if (_boostedSlots[i] != newSlots[i]) return true;
    }

    return false;
  }

  /// Fetch products for current slots with aggressive caching
  Future<void> _fetchProducts() async {
    if (_boostedSlots.isEmpty) {
      _boostedProducts = [];
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Check cache first
      final cachedProducts = _getFromCache(_boostedSlots);
      final missingIds =
          _boostedSlots.where((id) => !_productCache.containsKey(id)).toList();

      if (missingIds.isEmpty) {
        // All products in cache
        _boostedProducts = cachedProducts;
        _error = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fetch missing products in batches (Firestore 'in' supports up to 30)
      final List<Product> fetchedProducts = [];

      for (int i = 0; i < missingIds.length; i += 30) {
        final batch = missingIds.skip(i).take(30).toList();

        final querySnapshot = await _firestore
            .collection('shop_products')
            .where(FieldPath.documentId, whereIn: batch)
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw TimeoutException('Product fetch timed out'),
            );

        for (var doc in querySnapshot.docs) {
          final productData = doc.data();
          productData['id'] = doc.id;

          // Convert to Product immediately
          final product = Product.fromJson(productData);

          // Cache the product with size limit
          _addToCache(doc.id, product);

          fetchedProducts.add(product);
        }
      }

      // Combine cached and fetched products, maintain slot order
      final Map<String, Product> allProductsMap = {};

      for (var cached in cachedProducts) {
        allProductsMap[cached.id] = cached;
      }

      for (var fetched in fetchedProducts) {
        allProductsMap[fetched.id] = fetched;
      }

      // Maintain the order from slots
      _boostedProducts = _boostedSlots
          .map((id) => allProductsMap[id])
          .whereType<Product>()
          .toList();

      _error = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch products: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add product to cache with size limit
  void _addToCache(String id, Product product) {
    // Enforce max cache size
    if (_productCache.length >= _maxCacheSize) {
      // Remove oldest entry
      String? oldestKey;
      DateTime? oldestTime;

      _productCache.forEach((key, entry) {
        if (oldestTime == null || entry.timestamp.isBefore(oldestTime!)) {
          oldestTime = entry.timestamp;
          oldestKey = key;
        }
      });

      if (oldestKey != null) {
        _productCache.remove(oldestKey);
      }
    }

    _productCache[id] = _CacheEntry(
      product: product,
      timestamp: DateTime.now(),
    );
  }

  /// Get products from cache if they exist and are not expired
  List<Product> _getFromCache(List<String> ids) {
    final now = DateTime.now();
    final List<Product> cached = [];

    for (var id in ids) {
      if (_productCache.containsKey(id)) {
        final cacheEntry = _productCache[id]!;

        if (now.difference(cacheEntry.timestamp) < _cacheExpiry) {
          cached.add(cacheEntry.product);
        } else {
          // Remove expired cache entry
          _productCache.remove(id);
        }
      }
    }

    return cached;
  }

  /// Manually refresh products (pull-to-refresh support)
  Future<void> refresh() async {
    _productCache.clear(); // Clear cache to force fresh fetch
    await _fetchProducts();
  }

  /// Clear cache (useful for memory management)
  void clearCache() {
    _productCache.clear();
    notifyListeners();
  }

  /// Clean up expired cache entries
  void cleanupCache() {
    final now = DateTime.now();
    _productCache.removeWhere((key, value) {
      return now.difference(value.timestamp) >= _cacheExpiry;
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _slotsListener?.cancel();
    _productCache.clear();
    super.dispose();
  }
}

/// Cache entry wrapper
class _CacheEntry {
  final Product product;
  final DateTime timestamp;

  _CacheEntry({
    required this.product,
    required this.timestamp,
  });
}

/// Exception for timeout scenarios
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
