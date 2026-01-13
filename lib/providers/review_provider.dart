import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:collection';
import 'dart:async';

class ReviewProvider with ChangeNotifier {
  static const int _pageSize = 20;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot>? _txSub;
  final _pending = <PendingReview>[];

  int _limit = _pageSize;
  bool get canLoadMore => _pending.length >= _limit;

  // Add filter properties
  String? _currentProductFilter;
  String? _currentSellerFilter;

  UnmodifiableListView<PendingReview> get pending {
    // ✅ No client-side filtering needed anymore
    return UnmodifiableListView(_pending);
  }

  // Add filter methods
  void applyFilters({String? productFilter, String? sellerFilter}) {
    _currentProductFilter = productFilter;
    _currentSellerFilter = sellerFilter;
    notifyListeners();
  }

  void clearFilters() {
    _currentProductFilter = null;
    _currentSellerFilter = null;
    notifyListeners();
  }

  ReviewProvider() {
    // watch sign-in
    _authSub = _auth.authStateChanges().listen((user) {
      _txSub?.cancel();
      _pending.clear();
      _limit = _pageSize;
      if (user != null) {
        _subscribe(user.uid);
      } else {
        notifyListeners();
      }
    });
  }

  void _subscribe(String uid) {
    Query query = _db.collectionGroup('items')
    .where('buyerId', isEqualTo: uid)
    .where('deliveryStatus', isEqualTo: 'delivered')  // ✅ ADD THIS
    .where('needsAnyReview', isEqualTo: true);

    // ✅ Apply product filter SERVER-SIDE
    if (_currentProductFilter != null) {
      query = query.where('productId', isEqualTo: _currentProductFilter);
    }

    // ✅ Apply seller filter SERVER-SIDE
    if (_currentSellerFilter != null) {
      query = query.where('sellerId', isEqualTo: _currentSellerFilter);
    }

    query = query.orderBy('timestamp', descending: true).limit(_limit);

    _txSub = query.snapshots().listen(_onSnapshot, onError: (e) {
      debugPrint('Error in ReviewProvider subscription: $e');
    });
  }

  void _onSnapshot(QuerySnapshot snap) {
    final updated = <PendingReview>[];
    for (final tx in snap.docs) {
      final d = tx.data()! as Map<String, dynamic>;
      final np = d['needsProductReview'] as bool? ?? false;
      final ns = d['needsSellerReview'] as bool? ?? false;
      if (np || ns) {
        updated.add(PendingReview(
          txDoc: tx,
          isShopProduct: d['shopId'] != null,
          productReviewed: !np,
          sellerReviewed: !ns,
          productId: d['productId'] as String,
          sellerId: d['sellerId'] as String,
          shopId: d['shopId'] as String?,
          imageUrl: d['productImage'] as String?, // Use productImage directly
          orderId: d['orderId'] as String,
        ));
      }
    }
    _pending
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  /// Manually refresh pending reviews for a specific user
  /// This method can be called after a review is submitted to refresh the list
  void loadPendingReviews(String uid) {
    _pending.clear();
    _limit = _pageSize;
    _txSub?.cancel();
    _subscribe(uid);
    notifyListeners();
  }

  /// Refresh the current user's pending reviews
  void refreshPendingReviews() {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      loadPendingReviews(uid);
    }
  }

  /// Call this when you hit the bottom of the list
  void loadMore() {
    _limit += _pageSize;
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _txSub?.cancel();
      _subscribe(uid);
    }
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

class PendingReview {
  DocumentSnapshot txDoc;
  bool isShopProduct;
  bool productReviewed;
  bool sellerReviewed;
  String productId;
  String sellerId;
  String? shopId;
  String? imageUrl;
  bool submitting;
  final String orderId;

  PendingReview({
    required this.txDoc,
    required this.isShopProduct,
    required this.productReviewed,
    required this.sellerReviewed,
    required this.productId,
    required this.sellerId,
    this.shopId,
    this.imageUrl,
    this.submitting = false,
    required this.orderId,
  });
}
