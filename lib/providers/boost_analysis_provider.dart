// lib/providers/boost_analysis_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';

/// Represents an ongoing boosted item from products/properties/cars
class BoostedItem {
  final String id;
  final String itemName;
  final String itemType; // 'product', 'property', 'car', etc.
  final List<String> imageUrls;
  final int clickCount;
  final int boostedImpressionCount;
  final int boostImpressionCountAtStart;
  final int? boostClickCountAtStart;
  final Timestamp? boostStartTime;
  final Timestamp? boostEndTime;
  final Product? product;

  BoostedItem({
    required this.id,
    required this.itemName,
    required this.itemType,
    required this.imageUrls,
    required this.clickCount,
    required this.boostedImpressionCount,
    required this.boostImpressionCountAtStart,
    this.boostClickCountAtStart,
    required this.boostStartTime,
    required this.boostEndTime,
    this.product,
  });
}

/// Provider that manages ongoing boosts vs. past boosts with pagination
class BoostAnalysisProvider with ChangeNotifier {
  static const int _pageSize = 20; // Items per page
  static const int _ongoingBoostLimit = 50; // Max ongoing boosts to fetch

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Search functionality
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // Date range filtering
  DateTimeRange? _selectedDateRange;
  DateTimeRange? get selectedDateRange => _selectedDateRange;

  // Loading states
  bool _isLoadingOngoing = false;
  bool _isLoadingHistory = false;
  bool _isLoadingMore = false;

  bool get isLoading => _isLoadingOngoing || _isLoadingHistory;
  bool get isLoadingMore => _isLoadingMore;

  // Ongoing boosts
  List<BoostedItem> _allOngoingBoosts = [];
  List<BoostedItem> get allOngoingBoosts => _allOngoingBoosts;

  // Past boost history with pagination
  List<Map<String, dynamic>> _pastBoostHistoryDocs = [];
  List<Map<String, dynamic>> get pastBoostHistoryDocs => _pastBoostHistoryDocs;

  DocumentSnapshot? _lastHistoryDocument;
  bool _hasMoreHistory = true;
  bool get hasMoreHistory => _hasMoreHistory;

  // Subscriptions
  StreamSubscription<QuerySnapshot>? _productSubscription;
  StreamSubscription<QuerySnapshot>? _propertySubscription;
  StreamSubscription<QuerySnapshot>? _carSubscription;

  // Error handling
  String? _error;
  String? get error => _error;

  BoostAnalysisProvider() {
    _initialize();
  }

  void _initialize() {
    _fetchOngoingBoosts();
    _fetchPastBoostHistory();
  }

  // -------------------------
  // Search Functionality
  // -------------------------

  List<BoostedItem> get filteredOngoingBoosts {
    if (_searchQuery.isEmpty) {
      return _allOngoingBoosts;
    }
    return _allOngoingBoosts.where((item) {
      return item.itemName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  List<Map<String, dynamic>> get filteredPastBoostHistoryDocs {
    if (_searchQuery.isEmpty) {
      return _pastBoostHistoryDocs;
    }
    return _pastBoostHistoryDocs.where((doc) {
      final itemName = (doc['itemName'] ?? '').toString().toLowerCase();
      return itemName.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void updateSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  // -------------------------
  // Date Range Filtering
  // -------------------------

  /// Update date range and re-fetch past boosts with server-side filtering
  Future<void> updateDateRange(DateTimeRange? range) async {
    _selectedDateRange = range;
    // Re-fetch past boosts with the new date range filter
    await _fetchPastBoostHistory(refresh: true);
  }

  /// Clear date range filter
  Future<void> clearDateRange() async {
    _selectedDateRange = null;
    await _fetchPastBoostHistory(refresh: true);
  }

  // -------------------------
  // 1) Fetch Ongoing Boosts (Real-time with limit)
  // -------------------------

  void _fetchOngoingBoosts() {
    final user = _auth.currentUser;
    if (user == null) {
      _error = 'User not authenticated';
      notifyListeners();
      return;
    }

    _isLoadingOngoing = true;
    _error = null;
    notifyListeners();

    // PRODUCTS - with limit to prevent excessive reads
    _productSubscription = _firestore
        .collection('products')
        .where('userId', isEqualTo: user.uid)
        .where('boostStartTime', isNotEqualTo: null)
        .orderBy('boostStartTime', descending: true)
        .limit(_ongoingBoostLimit)
        .snapshots()
        .listen(
      (snapshot) => _processSnapshot(snapshot, 'product'),
      onError: (err) {
        debugPrint('Error fetching products: $err');
        _error = 'Failed to load ongoing boosts';
        _isLoadingOngoing = false;
        notifyListeners();
      },
    );

    // Add CARS and PROPERTIES subscriptions here similarly if needed
  }

  /// Convert each doc -> BoostedItem, filter ongoing boosts
  void _processSnapshot(QuerySnapshot snapshot, String itemType) {
    final now = DateTime.now();

    List<BoostedItem> items = [];

    for (var doc in snapshot.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;

        Product? product;
        if (itemType == 'product') {
          try {
            product = Product.fromDocument(doc);
          } catch (e) {
            debugPrint('Error parsing Product from document ${doc.id}: $e');
          }
        }

        items.add(BoostedItem(
          id: doc.id,
          itemName: data['productName'] ?? 'Unnamed',
          itemType: itemType,
          imageUrls: _parseImageUrls(data),
          clickCount: _parseInt(data['clickCount']),
          boostedImpressionCount: _parseInt(data['boostedImpressionCount']),
          boostImpressionCountAtStart:
              _parseInt(data['boostImpressionCountAtStart']),
          boostClickCountAtStart: data['boostClickCountAtStart']?.toInt(),
          boostStartTime: data['boostStartTime'] as Timestamp?,
          boostEndTime: data['boostEndTime'] as Timestamp?,
          product: product,
        ));
      } catch (e) {
        debugPrint('Error processing document ${doc.id}: $e');
        // Continue processing other documents
      }
    }

    // Remove existing boosts of the same type to avoid duplicates
    _allOngoingBoosts.removeWhere((b) => b.itemType == itemType);

    // Filter ongoing boosts where boostEndTime is in the future
    final ongoing = items.where((item) {
      final endTime = item.boostEndTime?.toDate();
      return endTime != null && endTime.isAfter(now);
    }).toList();

    debugPrint(
        'Fetched ${ongoing.length} ongoing boosts for type "$itemType".');

    _allOngoingBoosts.addAll(ongoing);
    _isLoadingOngoing = false;
    notifyListeners();
  }

  // -------------------------
  // 2) Fetch Past BoostHistory (Paginated)
  // -------------------------

  Future<void> _fetchPastBoostHistory({bool refresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _error = 'User not authenticated';
      notifyListeners();
      return;
    }

    if (refresh) {
      _lastHistoryDocument = null;
      _hasMoreHistory = true;
      _pastBoostHistoryDocs.clear();
    }

    if (!_hasMoreHistory) return;

    _isLoadingHistory = true;
    _error = null;
    notifyListeners();

    try {
      final now = Timestamp.fromDate(DateTime.now());

      Query query = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('boostHistory');

      // Apply date range filter if selected (server-side filtering)
      if (_selectedDateRange != null) {
        // Filter by boostEndTime within the selected date range
        final startTimestamp = Timestamp.fromDate(
          DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day),
        );
        final endTimestamp = Timestamp.fromDate(
          DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59),
        );

        query = query
            .where('boostEndTime', isGreaterThanOrEqualTo: startTimestamp)
            .where('boostEndTime', isLessThanOrEqualTo: endTimestamp);
      } else {
        // Default: only show past boosts (ended before now)
        query = query.where('boostEndTime', isLessThan: now);
      }

      query = query
          .orderBy('boostEndTime', descending: true)
          .limit(_pageSize);

      // Add cursor for pagination
      if (_lastHistoryDocument != null) {
        query = query.startAfterDocument(_lastHistoryDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        _hasMoreHistory = false;
      } else {
        _lastHistoryDocument = snapshot.docs.last;

        final newDocs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        _pastBoostHistoryDocs.addAll(newDocs);

        // Check if we got less than page size (means no more data)
        if (snapshot.docs.length < _pageSize) {
          _hasMoreHistory = false;
        }
      }

      _isLoadingHistory = false;
      notifyListeners();
    } catch (err) {
      debugPrint('Error fetching past boostHistory: $err');
      _error = 'Failed to load boost history';
      _isLoadingHistory = false;
      _hasMoreHistory = false;
      notifyListeners();
    }
  }

  /// Load more past boosts (for infinite scroll)
  Future<void> loadMorePastBoosts() async {
    if (_isLoadingMore || !_hasMoreHistory) return;

    _isLoadingMore = true;
    notifyListeners();

    final user = _auth.currentUser;
    if (user == null) {
      _isLoadingMore = false;
      notifyListeners();
      return;
    }

    try {
      final now = Timestamp.fromDate(DateTime.now());

      Query query = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('boostHistory');

      // Apply date range filter if selected (server-side filtering)
      if (_selectedDateRange != null) {
        final startTimestamp = Timestamp.fromDate(
          DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day),
        );
        final endTimestamp = Timestamp.fromDate(
          DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59),
        );

        query = query
            .where('boostEndTime', isGreaterThanOrEqualTo: startTimestamp)
            .where('boostEndTime', isLessThanOrEqualTo: endTimestamp);
      } else {
        query = query.where('boostEndTime', isLessThan: now);
      }

      query = query
          .orderBy('boostEndTime', descending: true)
          .limit(_pageSize);

      if (_lastHistoryDocument != null) {
        query = query.startAfterDocument(_lastHistoryDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        _hasMoreHistory = false;
      } else {
        _lastHistoryDocument = snapshot.docs.last;

        final newDocs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        _pastBoostHistoryDocs.addAll(newDocs);

        if (snapshot.docs.length < _pageSize) {
          _hasMoreHistory = false;
        }
      }
    } catch (err) {
      debugPrint('Error loading more boosts: $err');
      _error = 'Failed to load more boosts';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Refresh all data
  Future<void> refresh() async {
    _allOngoingBoosts.clear();
    _pastBoostHistoryDocs.clear();
    _lastHistoryDocument = null;
    _hasMoreHistory = true;
    _error = null;

    // Cancel existing subscriptions
    await _productSubscription?.cancel();
    await _propertySubscription?.cancel();
    await _carSubscription?.cancel();

    // Reinitialize
    _fetchOngoingBoosts();
    await _fetchPastBoostHistory(refresh: true);
  }

  // -------------------------
  // Helper Methods
  // -------------------------

  List<String> _parseImageUrls(Map<String, dynamic> data) {
    final imageUrls = data['imageUrls'] ?? data['fileUrls'];
    if (imageUrls is List) {
      return List<String>.from(imageUrls);
    }
    return <String>[];
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void dispose() {
    _productSubscription?.cancel();
    _propertySubscription?.cancel();
    _carSubscription?.cancel();
    super.dispose();
  }
}
