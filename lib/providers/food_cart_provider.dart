// lib/providers/food_cart_provider.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// TYPES
// ============================================================================

/// A selected extra/add-on for a food cart item.
class SelectedExtra {
  final String name;
  final int quantity;
  final double price;

  const SelectedExtra({
    required this.name,
    required this.quantity,
    required this.price,
  });

  factory SelectedExtra.fromMap(Map<String, dynamic> map) {
    return SelectedExtra(
      name: (map['name'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'price': price,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedExtra &&
          other.name == name &&
          other.quantity == quantity &&
          other.price == price;

  @override
  int get hashCode => Object.hash(name, quantity, price);
}

/// A single food item in the cart.
class FoodCartItem {
  final String foodId;
  final String originalFoodId;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String foodCategory;
  final String foodType;
  final int? preparationTime;

  // Cart-specific
  final int quantity;
  final List<SelectedExtra> extras;
  final String specialNotes;

  // Restaurant info (denormalized)
  final String restaurantId;
  final String restaurantName;

  // Metadata
  final Timestamp? addedAt;
  final bool isOptimistic;

  const FoodCartItem({
    required this.foodId,
    required this.originalFoodId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.foodCategory,
    required this.foodType,
    this.preparationTime,
    required this.quantity,
    required this.extras,
    required this.specialNotes,
    required this.restaurantId,
    required this.restaurantName,
    this.addedAt,
    this.isOptimistic = false,
  });

  factory FoodCartItem.fromFirestore(String docId, Map<String, dynamic> data) {
    return FoodCartItem(
      foodId: docId,
      originalFoodId: (data['originalFoodId'] as String?) ?? docId,
      name: (data['name'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: (data['imageUrl'] as String?) ?? '',
      foodCategory: (data['foodCategory'] as String?) ?? '',
      foodType: (data['foodType'] as String?) ?? '',
      preparationTime: (data['preparationTime'] as num?)?.toInt(),
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      extras: (data['extras'] as List<dynamic>?)
              ?.map((e) =>
                  SelectedExtra.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      specialNotes: (data['specialNotes'] as String?) ?? '',
      restaurantId: (data['restaurantId'] as String?) ?? '',
      restaurantName: (data['restaurantName'] as String?) ?? '',
      addedAt:
          data['addedAt'] is Timestamp ? data['addedAt'] as Timestamp : null,
      isOptimistic: false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'originalFoodId': originalFoodId,
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'foodCategory': foodCategory,
        'foodType': foodType,
        'preparationTime': preparationTime,
        'quantity': quantity,
        'extras': extras.map((e) => e.toMap()).toList(),
        'specialNotes': specialNotes,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'addedAt': FieldValue.serverTimestamp(),
      };

  FoodCartItem copyWith({
    String? foodId,
    String? originalFoodId,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? foodCategory,
    String? foodType,
    int? preparationTime,
    int? quantity,
    List<SelectedExtra>? extras,
    String? specialNotes,
    String? restaurantId,
    String? restaurantName,
    Timestamp? addedAt,
    bool? isOptimistic,
  }) {
    return FoodCartItem(
      foodId: foodId ?? this.foodId,
      originalFoodId: originalFoodId ?? this.originalFoodId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      foodCategory: foodCategory ?? this.foodCategory,
      foodType: foodType ?? this.foodType,
      preparationTime: preparationTime ?? this.preparationTime,
      quantity: quantity ?? this.quantity,
      extras: extras ?? this.extras,
      specialNotes: specialNotes ?? this.specialNotes,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      addedAt: addedAt ?? this.addedAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
    );
  }
}

/// Lightweight restaurant info stored in the food cart meta.
class FoodCartRestaurant {
  final String id;
  final String name;
  final String? profileImageUrl;

  const FoodCartRestaurant({
    required this.id,
    required this.name,
    this.profileImageUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FoodCartRestaurant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Totals for the food cart.
class FoodCartTotals {
  final double subtotal;
  final int itemCount;
  final String currency;

  const FoodCartTotals({
    required this.subtotal,
    required this.itemCount,
    this.currency = 'TL',
  });

  static const empty = FoodCartTotals(subtotal: 0, itemCount: 0);
}

/// Result of calling [FoodCartProvider.addItem].
enum AddItemResult {
  added,
  quantityUpdated,
  restaurantConflict,
  error,
}

/// Result of calling [FoodCartProvider.clearAndAddFromNewRestaurant].
enum ClearAndAddResult {
  added,
  error,
}

// ============================================================================
// RATE LIMITER
// ============================================================================

class _RateLimiter {
  final Duration cooldown;
  final Map<String, DateTime> _timestamps = {};

  _RateLimiter(this.cooldown);

  bool canProceed(String key) {
    final now = DateTime.now();
    final last = _timestamps[key];
    if (last != null && now.difference(last) < cooldown) return false;
    _timestamps[key] = now;
    return true;
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

class FoodCartProvider extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  // ── State ──────────────────────────────────────────────────────────────
  FoodCartRestaurant? _currentRestaurant;
  List<FoodCartItem> _items = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  // ── Internals ──────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _cartSubscription;
  final _rateLimiter = _RateLimiter(const Duration(milliseconds: 200));

  FoodCartProvider(this._auth, this._db) {
    _auth.authStateChanges().listen(_onAuthChanged);
  }

  // ── Public getters ─────────────────────────────────────────────────────

  FoodCartRestaurant? get currentRestaurant => _currentRestaurant;
  List<FoodCartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  FoodCartTotals get totals => _computeTotals(_items);
  int get itemCount => totals.itemCount;

  // ── Firestore paths ────────────────────────────────────────────────────

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _cartCollection =>
      _db.collection('users').doc(_uid).collection('foodCart');

  DocumentReference<Map<String, dynamic>> _cartDoc(String foodId) =>
      _cartCollection.doc(foodId);

  DocumentReference<Map<String, dynamic>> get _metaDoc =>
      _db.collection('users').doc(_uid).collection('foodCartMeta').doc('info');

  // ============================================================================
  // INITIALIZATION / AUTH
  // ============================================================================

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      _stopListener();
      _items = [];
      _currentRestaurant = null;
      _isInitialized = false;
      _isLoading = false;
      notifyListeners();
    } else if (!_isInitialized) {
      await _initialize();
    }
  }

  Future<void> _initialize() async {
    if (_uid.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load restaurant meta
      final metaSnap = await _metaDoc.get();
      if (metaSnap.exists) {
        final meta = metaSnap.data()!;
        _currentRestaurant = FoodCartRestaurant(
          id: (meta['restaurantId'] as String?) ?? '',
          name: (meta['restaurantName'] as String?) ?? '',
          profileImageUrl: meta['profileImageUrl'] as String?,
        );
      }

      // 2. Load cart items
      final cartSnap = await _cartCollection.get();
      final loaded = <FoodCartItem>[];
      for (final doc in cartSnap.docs) {
        try {
          loaded.add(FoodCartItem.fromFirestore(doc.id, doc.data()));
        } catch (e) {
          debugPrint('[FoodCart] Skipping malformed item ${doc.id}: $e');
        }
      }
      _sortItems(loaded);
      _items = loaded;

      // 3. Start real-time listener
      _startListener();
    } catch (e) {
      debugPrint('[FoodCart] Init error: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // REAL-TIME LISTENER
  // ============================================================================

  void _startListener() {
    if (_uid.isEmpty) return;
    _stopListener();

    _cartSubscription = _cartCollection.snapshots().listen(
          _handleSnapshot,
          onError: (e) => debugPrint('[FoodCart] Listener error: $e'),
        );
  }

  void _stopListener() {
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  void _handleSnapshot(QuerySnapshot snapshot) {
    if (snapshot.metadata.isFromCache && snapshot.metadata.hasPendingWrites) {
      return;
    }

    if (snapshot.docs.isEmpty) {
      _items = [];
      _currentRestaurant = null;
      notifyListeners();
      return;
    }

    final map = <String, FoodCartItem>{
      for (final item in _items) item.foodId: item,
    };

    for (final change in snapshot.docChanges) {
      final id = change.doc.id;
      final data = change.doc.data() as Map<String, dynamic>?;

      if (change.type == DocumentChangeType.removed) {
        map.remove(id);
      } else if (data != null) {
        try {
          map[id] = FoodCartItem.fromFirestore(id, data);
        } catch (e) {
          debugPrint('[FoodCart] Failed to parse item $id: $e');
        }
      }
    }

    final result = map.values.toList();
    _sortItems(result);
    _items = result;

    // Update restaurant from first doc if not set
    final firstData = snapshot.docs.first.data() as Map<String, dynamic>?;
    if (firstData != null && firstData['restaurantId'] != null) {
      final rid = firstData['restaurantId'] as String;
      if (_currentRestaurant?.id != rid) {
        _currentRestaurant = FoodCartRestaurant(
          id: rid,
          name: (firstData['restaurantName'] as String?) ?? '',
        );
      }
    }

    notifyListeners();
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  /// Add a food item to the cart.
  /// Returns [AddItemResult.restaurantConflict] if item belongs to a
  /// different restaurant — the UI should then ask the user whether to
  /// switch, and call [clearAndAddFromNewRestaurant] if they confirm.
  Future<AddItemResult> addItem({
    required String foodId,
    required String foodName,
    required String foodDescription,
    required double price,
    required String imageUrl,
    required String foodCategory,
    required String foodType,
    int? preparationTime,
    required FoodCartRestaurant restaurant,
    int quantity = 1,
    List<SelectedExtra> extras = const [],
    String specialNotes = '',
  }) async {
    if (_uid.isEmpty) return AddItemResult.error;

    if (!_rateLimiter.canProceed('add_$foodId')) {
      return AddItemResult.error;
    }

    // Single-restaurant enforcement
    if (_currentRestaurant != null && _currentRestaurant!.id != restaurant.id) {
      return AddItemResult.restaurantConflict;
    }

    try {
      final cartKey = _buildCartItemKey(foodId, extras);
      final existing = _items.firstWhereOrNull((i) => i.foodId == cartKey);

      if (existing != null) {
        // Increment quantity
        final newQty = existing.quantity + quantity;
        await _cartDoc(cartKey).update({'quantity': newQty});

        _items = _items
            .map((i) => i.foodId == cartKey ? i.copyWith(quantity: newQty) : i)
            .toList();
        notifyListeners();
        return AddItemResult.quantityUpdated;
      }

      // New item
      final item = FoodCartItem(
        foodId: cartKey,
        originalFoodId: foodId,
        name: foodName,
        description: foodDescription,
        price: price,
        imageUrl: imageUrl,
        foodCategory: foodCategory,
        foodType: foodType,
        preparationTime: preparationTime,
        quantity: quantity,
        extras: extras,
        specialNotes: specialNotes,
        restaurantId: restaurant.id,
        restaurantName: restaurant.name,
        addedAt: Timestamp.now(),
      );

      await _cartDoc(cartKey).set(item.toFirestore());

      if (_currentRestaurant == null) {
        await _writeRestaurantMeta(restaurant);
      }

      // Optimistic — only add if snapshot listener hasn't already
      if (!_items.any((i) => i.foodId == cartKey)) {
        _items = [item, ..._items];
        notifyListeners();
      }

      return AddItemResult.added;
    } catch (e) {
      debugPrint('[FoodCart] addItem error: $e');
      return AddItemResult.error;
    }
  }

  /// Clear the entire cart and add an item from a new restaurant.
  /// Call this after the user confirms they want to switch restaurants.
  Future<ClearAndAddResult> clearAndAddFromNewRestaurant({
    required String foodId,
    required String foodName,
    required String foodDescription,
    required double price,
    required String imageUrl,
    required String foodCategory,
    required String foodType,
    int? preparationTime,
    required FoodCartRestaurant restaurant,
    int quantity = 1,
    List<SelectedExtra> extras = const [],
    String specialNotes = '',
  }) async {
    if (_uid.isEmpty) return ClearAndAddResult.error;

    try {
      // 1. Delete all existing items
      final snapshot = await _cartCollection.get();
      if (snapshot.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(_metaDoc);
        await batch.commit();
      }

      // 2. Reset state
      _items = [];
      _currentRestaurant = null;

      // 3. Add new item
      final cartKey = _buildCartItemKey(foodId, extras);

      final item = FoodCartItem(
        foodId: cartKey,
        originalFoodId: foodId,
        name: foodName,
        description: foodDescription,
        price: price,
        imageUrl: imageUrl,
        foodCategory: foodCategory,
        foodType: foodType,
        preparationTime: preparationTime,
        quantity: quantity,
        extras: extras,
        specialNotes: specialNotes,
        restaurantId: restaurant.id,
        restaurantName: restaurant.name,
        addedAt: Timestamp.now(),
      );

      await _cartDoc(cartKey).set(item.toFirestore());
      await _writeRestaurantMeta(restaurant);

      if (!_items.any((i) => i.foodId == cartKey)) {
        _items = [item];
        notifyListeners();
      }

      return ClearAndAddResult.added;
    } catch (e) {
      debugPrint('[FoodCart] clearAndAdd error: $e');
      return ClearAndAddResult.error;
    }
  }

  /// Remove a food item entirely from the cart.
  Future<void> removeItem(String foodId) async {
    if (_uid.isEmpty) return;

    // Optimistic
    final previous = List<FoodCartItem>.from(_items);
    _items = _items.where((i) => i.foodId != foodId).toList();
    notifyListeners();

    try {
      await _cartDoc(foodId).delete();

      if (_items.isEmpty) {
        await _metaDoc.delete().catchError((_) {});
        _currentRestaurant = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[FoodCart] removeItem error: $e');
      // Rollback
      _items = previous;
      notifyListeners();
      await refresh();
    }
  }

  /// Update quantity of an existing item. Removes the item if [newQuantity] ≤ 0.
  Future<void> updateQuantity(String foodId, int newQuantity) async {
    if (_uid.isEmpty) return;

    if (newQuantity <= 0) {
      return removeItem(foodId);
    }

    if (!_rateLimiter.canProceed('qty_$foodId')) return;

    // Optimistic
    _items = _items
        .map((i) => i.foodId == foodId ? i.copyWith(quantity: newQuantity) : i)
        .toList();
    notifyListeners();

    try {
      await _cartDoc(foodId).update({'quantity': newQuantity});
    } catch (e) {
      debugPrint('[FoodCart] updateQuantity error: $e');
      await refresh();
    }
  }

  /// Replace the entire extras array for a cart item.
  Future<void> updateExtras(String foodId, List<SelectedExtra> extras) async {
    if (_uid.isEmpty) return;

    // Optimistic
    _items = _items
        .map((i) => i.foodId == foodId ? i.copyWith(extras: extras) : i)
        .toList();
    notifyListeners();

    try {
      await _cartDoc(foodId).update({
        'extras': extras.map((e) => e.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('[FoodCart] updateExtras error: $e');
      await refresh();
    }
  }

  /// Update special notes for a cart item.
  Future<void> updateNotes(String foodId, String notes) async {
    if (_uid.isEmpty) return;

    _items = _items
        .map((i) => i.foodId == foodId ? i.copyWith(specialNotes: notes) : i)
        .toList();
    notifyListeners();

    try {
      await _cartDoc(foodId).update({'specialNotes': notes});
    } catch (e) {
      debugPrint('[FoodCart] updateNotes error: $e');
    }
  }

  /// Clear the entire food cart.
  Future<void> clearCart() async {
    if (_uid.isEmpty) return;

    // Optimistic
    _items = [];
    _currentRestaurant = null;
    notifyListeners();

    try {
      final snapshot = await _cartCollection.get();
      if (snapshot.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(_metaDoc);
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[FoodCart] clearCart error: $e');
      await refresh();
    }
  }

  /// Force refresh from Firestore.
  Future<void> refresh() async {
    if (_uid.isEmpty) return;

    try {
      final results = await Future.wait([
        _metaDoc.get(),
        _cartCollection.get(),
      ]);

      final metaSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final cartSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

      if (metaSnap.exists) {
        final meta = metaSnap.data()!;
        _currentRestaurant = FoodCartRestaurant(
          id: (meta['restaurantId'] as String?) ?? '',
          name: (meta['restaurantName'] as String?) ?? '',
          profileImageUrl: meta['profileImageUrl'] as String?,
        );
      } else {
        _currentRestaurant = null;
      }

      final loaded = <FoodCartItem>[];
      for (final doc in cartSnap.docs) {
        try {
          loaded.add(FoodCartItem.fromFirestore(doc.id, doc.data()));
        } catch (e) {
          debugPrint('[FoodCart] Skipping malformed item ${doc.id}: $e');
        }
      }
      _sortItems(loaded);
      _items = loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('[FoodCart] refresh error: $e');
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  Future<void> _writeRestaurantMeta(FoodCartRestaurant restaurant) async {
    await _metaDoc.set({
      'restaurantId': restaurant.id,
      'restaurantName': restaurant.name,
      'profileImageUrl': restaurant.profileImageUrl ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _currentRestaurant = restaurant;
  }

  /// Two items of the same food but with different extras are different cart entries.
  /// This generates a deterministic key for a food+extras combination.
  String _buildCartItemKey(String foodId, List<SelectedExtra> extras) {
    if (extras.isEmpty) return foodId;

    final sorted = List<SelectedExtra>.from(extras)
      ..sort((a, b) => a.name.compareTo(b.name));

    final extrasStr = sorted.map((e) => '${e.name}:${e.quantity}').join('|');

    // Simple hash matching the JS: (acc << 5) - acc + charCode
    var hash = 0;
    for (final ch in extrasStr.codeUnits) {
      hash = (((hash << 5) - hash) + ch) & 0xFFFFFFFF;
      // Convert to signed 32-bit to match JS |0 behavior
      if (hash > 0x7FFFFFFF) hash -= 0x100000000;
    }
    final absHash = hash.abs().toRadixString(36);
    return '${foodId}_$absHash';
  }

  FoodCartTotals _computeTotals(List<FoodCartItem> items) {
    if (items.isEmpty) return FoodCartTotals.empty;

    double subtotal = 0;
    int itemCount = 0;

    for (final item in items) {
      final extrasTotal = item.extras.fold<double>(
        0,
        (sum, ext) => sum + ext.price * ext.quantity,
      );
      subtotal += (item.price + extrasTotal) * item.quantity;
      itemCount += item.quantity;
    }

    return FoodCartTotals(
      subtotal: (subtotal * 100).roundToDouble() / 100,
      itemCount: itemCount,
    );
  }

  void _sortItems(List<FoodCartItem> items) {
    items.sort((a, b) {
      final ta = a.addedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.addedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta); // newest first
    });
  }

  @override
  void dispose() {
    _stopListener();
    super.dispose();
  }
}

// ============================================================================
// EXTENSION — Dart doesn't have firstWhere returning null by default
// ============================================================================

extension _IterableExt<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
