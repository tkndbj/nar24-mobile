// lib/providers/market_banner_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MarketBannerProvider extends ChangeNotifier {
  static const int _batchSize = 20;

  final List<QueryDocumentSnapshot> _docs = [];
  bool _hasMore = true;
  bool _isLoading = false;
  String? _error;

  // ✅ NEW: Track if initial fetch has been triggered (prevents duplicate calls)
  bool _initialFetchTriggered = false;

  List<QueryDocumentSnapshot> get docs => _docs;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get initialFetchTriggered => _initialFetchTriggered;

  /// ✅ NEW: Full reset for pull-to-refresh or when widget is disposed/recreated
  void reset() {
    _docs.clear();
    _hasMore = true;
    _isLoading = false;
    _error = null;
    _initialFetchTriggered = false;
    notifyListeners();
  }

  /// Refresh: clears data and fetches first page
  Future<void> refresh({BuildContext? context}) async {
    reset();
    await fetchNextPage(context: context);
  }

  Future<void> fetchNextPage({BuildContext? context}) async {
    // ✅ ENHANCED: Prevent concurrent and unnecessary fetches
    if (_isLoading) {
      if (kDebugMode) {
        debugPrint('📸 MarketBannerProvider: Skipping fetch - already loading');
      }
      return;
    }

    if (!_hasMore) {
      if (kDebugMode) {
        debugPrint('📸 MarketBannerProvider: Skipping fetch - no more items');
      }
      return;
    }

    _isLoading = true;
    _initialFetchTriggered = true;
    _error = null;
    notifyListeners();

    try {
      Query query = FirebaseFirestore.instance
          .collection('market_banners')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_batchSize);

      if (_docs.isNotEmpty) {
        query = query.startAfterDocument(_docs.last);
      }

      final snap = await query.get();

      if (snap.docs.length < _batchSize) {
        _hasMore = false;
      }

      _docs.addAll(snap.docs);

      if (kDebugMode) {
        debugPrint(
            '📸 MarketBannerProvider: Fetched ${snap.docs.length} banners (total: ${_docs.length})');
      }

      // ✅ REMOVED: Aggressive prefetching here
      // The widget now handles prefetching more efficiently (only 2 images ahead)
      // This reduces initial network load and memory usage
    } catch (e) {
      _error = e.toString();

      if (e.toString().contains('index')) {
        _error =
            'Database index required. Check console for index creation link.';
        if (kDebugMode) {
          debugPrint('🔥 FIRESTORE INDEX REQUIRED 🔥');
          debugPrint('Create this index in Firebase Console:');
          debugPrint('Collection: market_banners');
          debugPrint('Fields: isActive (Ascending) + createdAt (Descending)');
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ MarketBannerProvider error: $e');
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
