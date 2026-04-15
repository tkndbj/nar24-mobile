// lib/providers/market_cart_provider.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/market_typesense_service.dart';

// ============================================================================
// TYPES
// ============================================================================

class MarketCartItem {
  final String itemId; // Firestore doc ID in market-items
  final String name;
  final String brand;
  final String type;
  final String category;
  final double price;
  final String imageUrl;
  final int quantity;
  final Timestamp? addedAt;
  final bool isOptimistic;

  const MarketCartItem({
    required this.itemId,
    required this.name,
    required this.brand,
    required this.type,
    required this.category,
    required this.price,
    required this.imageUrl,
    required this.quantity,
    this.addedAt,
    this.isOptimistic = false,
  });

  factory MarketCartItem.fromFirestore(
      String docId, Map<String, dynamic> data) {
    return MarketCartItem(
      itemId: docId,
      name: (data['name'] as String?) ?? '',
      brand: (data['brand'] as String?) ?? '',
      type: (data['type'] as String?) ?? '',
      category: (data['category'] as String?) ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: (data['imageUrl'] as String?) ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      addedAt:
          data['addedAt'] is Timestamp ? data['addedAt'] as Timestamp : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'brand': brand,
        'type': type,
        'category': category,
        'price': price,
        'imageUrl': imageUrl,
        'quantity': quantity,
        'addedAt': FieldValue.serverTimestamp(),
      };

  MarketCartItem copyWith({
    String? itemId,
    String? name,
    String? brand,
    String? type,
    String? category,
    double? price,
    String? imageUrl,
    int? quantity,
    Timestamp? addedAt,
    bool? isOptimistic,
  }) {
    return MarketCartItem(
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      type: type ?? this.type,
      category: category ?? this.category,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity ?? this.quantity,
      addedAt: addedAt ?? this.addedAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
    );
  }

  double get lineTotal => price * quantity;
}

class MarketCartTotals {
  final double subtotal;
  final int itemCount;

  const MarketCartTotals({required this.subtotal, required this.itemCount});

  static const empty = MarketCartTotals(subtotal: 0, itemCount: 0);
}

enum MarketAddResult { added, quantityUpdated, outOfStock, error }

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

class MarketCartProvider extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  // ── State ──────────────────────────────────────────────────────────────
  List<MarketCartItem> _items = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  // ── Internals ──────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _cartSubscription;
  StreamSubscription<User?>? _authSubscription;
  final _rateLimiter = _RateLimiter(const Duration(milliseconds: 200));
  Completer<void>? _mutationLock;

  MarketCartProvider(this._auth, this._db) {
    _authSubscription = _auth.authStateChanges().listen(_onAuthChanged);
  }

  // ── Lock ───────────────────────────────────────────────────────────────

  Future<void> _acquireLock() async {
    while (_mutationLock != null) {
      await _mutationLock!.future;
    }
    _mutationLock = Completer<void>();
  }

  void _releaseLock() {
    final lock = _mutationLock;
    _mutationLock = null;
    lock?.complete();
  }

  // ── Getters ────────────────────────────────────────────────────────────

  List<MarketCartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  int get itemCount => _items.fold(0, (sum, i) => sum + i.quantity);

  MarketCartTotals get totals {
    if (_items.isEmpty) return MarketCartTotals.empty;
    double subtotal = 0;
    int count = 0;
    for (final item in _items) {
      subtotal += item.lineTotal;
      count += item.quantity;
    }
    return MarketCartTotals(
      subtotal: (subtotal * 100).roundToDouble() / 100,
      itemCount: count,
    );
  }

  /// Quick check: how many of this item are in the cart?
  int quantityOf(String itemId) {
    final match = _items.where((i) => i.itemId == itemId);
    return match.isEmpty ? 0 : match.first.quantity;
  }

  // ── Firestore paths ────────────────────────────────────────────────────

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _cartCollection =>
      _db.collection('users').doc(_uid).collection('marketCart');

  DocumentReference<Map<String, dynamic>> _cartDoc(String itemId) =>
      _cartCollection.doc(itemId);

  // ============================================================================
  // INIT / AUTH
  // ============================================================================

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      _stopListener();
      _items = [];
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
      final snap = await _cartCollection.get();
      final loaded = <MarketCartItem>[];
      for (final doc in snap.docs) {
        try {
          loaded.add(MarketCartItem.fromFirestore(doc.id, doc.data()));
        } catch (e) {
          debugPrint('[MarketCart] Skipping malformed item ${doc.id}: $e');
        }
      }
      _sortItems(loaded);
      _items = loaded;
      _startListener();
    } catch (e) {
      debugPrint('[MarketCart] Init error: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // LISTENER
  // ============================================================================

  void _startListener() {
    if (_uid.isEmpty) return;
    _stopListener();

    _cartSubscription = _cartCollection.snapshots().listen(
          _handleSnapshot,
          onError: (e) => debugPrint('[MarketCart] Listener error: $e'),
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
      notifyListeners();
      return;
    }

    final map = <String, MarketCartItem>{
      for (final item in _items) item.itemId: item,
    };

    for (final change in snapshot.docChanges) {
      final id = change.doc.id;
      final data = change.doc.data() as Map<String, dynamic>?;

      if (change.type == DocumentChangeType.removed) {
        map.remove(id);
      } else if (data != null) {
        try {
          map[id] = MarketCartItem.fromFirestore(id, data);
        } catch (e) {
          debugPrint('[MarketCart] Parse error $id: $e');
        }
      }
    }

    final result = map.values.toList();
    _sortItems(result);
    _items = result;
    notifyListeners();
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  /// Add a market item to the cart. If already present, increments quantity.
  Future<MarketAddResult> addItem(MarketItem product,
      {int quantity = 1}) async {
    if (_uid.isEmpty) return MarketAddResult.error;
    if (!_rateLimiter.canProceed('add_${product.id}'))
      return MarketAddResult.error;
    if (product.stock <= 0) return MarketAddResult.outOfStock;

    await _acquireLock();
    String? optimisticKey;
    try {
      final existing = _items.where((i) => i.itemId == product.id);

      if (existing.isNotEmpty) {
        final current = existing.first;
        final newQty = current.quantity + quantity;
        await _cartDoc(product.id).update({'quantity': newQty});

        _items = _items
            .map((i) =>
                i.itemId == product.id ? i.copyWith(quantity: newQty) : i)
            .toList();
        notifyListeners();
        return MarketAddResult.quantityUpdated;
      }

      // New item — optimistic insert
      final item = MarketCartItem(
        itemId: product.id,
        name: product.name,
        brand: product.brand,
        type: product.type,
        category: product.category,
        price: product.price,
        imageUrl: product.imageUrl,
        quantity: quantity,
        addedAt: Timestamp.now(),
        isOptimistic: true,
      );

      optimisticKey = product.id;
      _items = [item, ..._items];
      notifyListeners();

      await _cartDoc(product.id).set(item.toFirestore());

      // Clear optimistic flag
      final idx =
          _items.indexWhere((i) => i.itemId == product.id && i.isOptimistic);
      if (idx != -1) {
        _items = List.of(_items)
          ..[idx] = _items[idx].copyWith(isOptimistic: false);
        notifyListeners();
      }

      return MarketAddResult.added;
    } catch (e) {
      debugPrint('[MarketCart] addItem error: $e');
      if (optimisticKey != null) {
        _items = _items.where((i) => i.itemId != optimisticKey).toList();
        notifyListeners();
      }
      return MarketAddResult.error;
    } finally {
      _releaseLock();
    }
  }

  /// Update quantity. Removes if newQuantity <= 0.
  Future<void> updateQuantity(String itemId, int newQuantity) async {
    if (_uid.isEmpty) return;

    if (newQuantity <= 0) return removeItem(itemId);
    if (newQuantity > 99) newQuantity = 99;
    if (!_rateLimiter.canProceed('qty_$itemId')) return;

    // Optimistic
    _items = _items
        .map((i) => i.itemId == itemId ? i.copyWith(quantity: newQuantity) : i)
        .toList();
    notifyListeners();

    try {
      await _cartDoc(itemId).update({'quantity': newQuantity});
    } catch (e) {
      debugPrint('[MarketCart] updateQuantity error: $e');
      await refresh();
    }
  }

  /// Remove an item entirely.
  Future<void> removeItem(String itemId) async {
    if (_uid.isEmpty) return;

    final previous = List<MarketCartItem>.from(_items);
    _items = _items.where((i) => i.itemId != itemId).toList();
    notifyListeners();

    try {
      await _cartDoc(itemId).delete();
    } catch (e) {
      debugPrint('[MarketCart] removeItem error: $e');
      _items = previous;
      notifyListeners();
    }
  }

  /// Clear the entire market cart.
  Future<void> clearCart() async {
    if (_uid.isEmpty) return;

    _items = [];
    notifyListeners();

    try {
      final snap = await _cartCollection.get();
      if (snap.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[MarketCart] clearCart error: $e');
      await refresh();
    }
  }

  /// Force refresh from Firestore.
  Future<void> refresh() async {
    if (_uid.isEmpty) return;

    try {
      final snap = await _cartCollection.get();
      final loaded = <MarketCartItem>[];
      for (final doc in snap.docs) {
        try {
          loaded.add(MarketCartItem.fromFirestore(doc.id, doc.data()));
        } catch (e) {
          debugPrint('[MarketCart] Skipping ${doc.id}: $e');
        }
      }
      _sortItems(loaded);
      _items = loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('[MarketCart] refresh error: $e');
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  void _sortItems(List<MarketCartItem> items) {
    items.sort((a, b) {
      final ta = a.addedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.addedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta); // newest first
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _stopListener();
    super.dispose();
  }
}
