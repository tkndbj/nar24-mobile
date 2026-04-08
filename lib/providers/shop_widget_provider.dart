// lib/providers/shop_widget_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/click_tracking_service.dart';
import '../user_provider.dart';
import '../services/firestore_read_tracker.dart';

class ShopWidgetProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserProvider _userProvider;

  static const String _configCollection = 'app_config';
  static const String _configDoc = 'featured_shops';

  // ————————————————————————————————————————————
  // 1️⃣  Auth & favorite‐shops tracking

  bool _userOwnsShop = false;
  bool _isCheckingMembership = false;
  List<String> _userShopIds = [];
  List<String> _userRestaurantIds = []; // 🔧 ADDED

  // Track last checked uid to avoid re-checking when UserProvider notifies
  // for non-auth-related changes (e.g. profile field updates).
  String? _lastCheckedUid;

  // ————————————————————————————————————————————
  // 2️⃣  Featured‐shops list (for horizontal carousel)
  final List<DocumentSnapshot> _shops = [];
  bool _isLoadingShops = false;

  ShopWidgetProvider(this._userProvider) {
    // Check membership using data already loaded by UserProvider
    _onUserProviderChanged();
    _userProvider.addListener(_onUserProviderChanged);
    fetchFeaturedShops();
  }

  /// Reacts to UserProvider changes. Only triggers membership check
  /// when the user identity actually changes or profileData becomes available.
  void _onUserProviderChanged() {
    final user = _userProvider.user;
    final profileData = _userProvider.profileData;

    if (user == null) {
      // Logged out
      if (_lastCheckedUid != null || _userOwnsShop) {
        _lastCheckedUid = null;
        _userOwnsShop = false;
        _userShopIds = [];
        _userRestaurantIds = []; // 🔧 ADDED
        _isCheckingMembership = false;
        notifyListeners();
      }
      return;
    }

    // Only re-check when:
    // 1. This is a new user (uid changed), OR
    // 2. profileData just became available for the first time for this user
    final uid = user.uid;
    if (uid == _lastCheckedUid && !_isCheckingMembership) {
      // 🔧 CHANGED: Also watch memberOfRestaurants for changes
      final memberOfShops =
          profileData?['memberOfShops'] as Map<String, dynamic>? ?? {};
      final memberOfRestaurants =
          profileData?['memberOfRestaurants'] as Map<String, dynamic>? ?? {};
      final currentIds = {...memberOfShops.keys, ...memberOfRestaurants.keys};
      final previousIds = {..._userShopIds, ..._userRestaurantIds};
      if (currentIds.length == previousIds.length &&
          currentIds.containsAll(previousIds)) {
        return; // No change
      }
    }

    if (profileData != null) {
      _lastCheckedUid = uid;
      _checkUserMembershipFromProfile(uid, profileData);
    }
  }

  // 🚪 Expose for the widgets:

  User? get currentUser => _userProvider.user;
  bool get userOwnsShop => _userOwnsShop;
  bool get isCheckingMembership => _isCheckingMembership;
  List<String> get userShopIds => List.unmodifiable(_userShopIds);
  String? get firstUserShopId =>
      _userShopIds.isNotEmpty ? _userShopIds.first : null;

  // 🔧 ADDED: Restaurant getters
  List<String> get userRestaurantIds => List.unmodifiable(_userRestaurantIds);
  String? get firstUserRestaurantId =>
      _userRestaurantIds.isNotEmpty ? _userRestaurantIds.first : null;

  List<DocumentSnapshot> get shops => List.unmodifiable(_shops);
  bool get isLoadingMore => _isLoadingShops;

  // ————————————————————————————————————————————
  // 👇  Public helpers

  Future<void> fetchFeaturedShops({int limit = 10}) async {
    _isLoadingShops = true;
    notifyListeners();

    try {
      // First, try to get configured featured shops
      final configDoc = await _firestore
          .collection(_configCollection)
          .doc(_configDoc)
          .get();

      if (configDoc.exists && configDoc.data() != null) {
        final data = configDoc.data()!;
        final shopIds = (data['shopIds'] as List<dynamic>?)?.cast<String>() ?? [];

        if (shopIds.isNotEmpty) {
          // Fetch shops in the configured order
          final shops = await _fetchShopsByIds(shopIds);

          if (shops.isNotEmpty) {
            _shops
              ..clear()
              ..addAll(shops);
            _isLoadingShops = false;
            notifyListeners();
            FirestoreReadTracker.instance.trackRead('ShopWidgetProvider', 'app_config/featured_shops + ${shops.length} shop docs', shops.length + 1);
            return;
          }
        }
      }

      // Fallback: fetch default shops if no config or no valid shops
      debugPrint('ℹ️ No featured shops config, using fallback query');
      await _fetchDefaultFeaturedShops(limit);
    } catch (e) {
      debugPrint('❌ Error fetching featured shops config: $e');
      // Fallback on error
      await _fetchDefaultFeaturedShops(limit);
    }
  }

  Future<List<DocumentSnapshot>> _fetchShopsByIds(List<String> shopIds) async {
    final List<DocumentSnapshot> shops = [];

    for (final shopId in shopIds) {
      try {
        final shopDoc = await _firestore.collection('shops').doc(shopId).get();

        if (shopDoc.exists) {
          final data = shopDoc.data();
          // Only include active shops
          if (data?['isActive'] != false) {
            shops.add(shopDoc);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching shop $shopId: $e');
      }
    }

    return shops;
  }

  /// Fallback: fetch shops sorted by createdAt (original behavior)
  Future<void> _fetchDefaultFeaturedShops(int limit) async {
    try {
      final snap = await _firestore
          .collection('shops')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      _shops
        ..clear()
        ..addAll(snap.docs);

      FirestoreReadTracker.instance.trackRead('ShopWidgetProvider', 'shops (default fallback)', snap.docs.length);
    } catch (e) {
      debugPrint('❌ Error fetching default shops: $e');
    } finally {
      _isLoadingShops = false;
      notifyListeners();
    }
  }

  Future<void> incrementClickCount(String shopId) async {
    await ClickService.instance.trackShopClick(shopId);
  }

  /// Uses the already-loaded profileData from UserProvider instead of
  /// making a separate Firestore read for users/{uid}.
  Future<void> _checkUserMembershipFromProfile(
      String uid, Map<String, dynamic> profileData) async {
    if (_isCheckingMembership) return;
    _isCheckingMembership = true;
    notifyListeners();

    try {
      final memberOfShops =
          profileData['memberOfShops'] as Map<String, dynamic>? ?? {};
      // 🔧 ADDED: Read memberOfRestaurants too
      final memberOfRestaurants =
          profileData['memberOfRestaurants'] as Map<String, dynamic>? ?? {};

      // 🔧 CHANGED: Check both maps are empty
      if (memberOfShops.isEmpty && memberOfRestaurants.isEmpty) {
        _userOwnsShop = false;
        _userShopIds = [];
        _userRestaurantIds = [];
        notifyListeners();
        return;
      }

    List<String> validShopIds = [];
      List<String> validRestaurantIds = [];
      List<String> shopsToCleanup = [];
      List<String> restaurantsToCleanup = [];

      // Build a unified list: (entityId, role, collection)
      final allEntries = [
        ...memberOfShops.entries.map((e) => (e.key, e.value as String, 'shops')),
        ...memberOfRestaurants.entries.map((e) => (e.key, e.value as String, 'restaurants')),
      ];

      // Fetch ALL docs in parallel instead of sequential awaits
      final docs = await Future.wait(
        allEntries.map((entry) =>
          _firestore.collection(entry.$3).doc(entry.$1).get()),
      );

      for (int i = 0; i < allEntries.length; i++) {
        final (entityId, userRole, collection) = allEntries[i];
        final isShop = collection == 'shops';

        try {
          final doc = docs[i];
          if (!doc.exists) {
            (isShop ? shopsToCleanup : restaurantsToCleanup).add(entityId);
            continue;
          }
          final data = doc.data() as Map<String, dynamic>;
          if (_verifyUserStillMemberOfShop(uid, userRole, data)) {
            (isShop ? validShopIds : validRestaurantIds).add(entityId);
          } else {
            (isShop ? shopsToCleanup : restaurantsToCleanup).add(entityId);
          }
        } catch (e) {
          debugPrint('Error checking $collection $entityId: $e');
          (isShop ? validShopIds : validRestaurantIds).add(entityId);
        }
      }

      if (shopsToCleanup.isNotEmpty) {
        _cleanupMembershipsFromUser(uid, shopsToCleanup, 'memberOfShops'); // 🔧 CHANGED
      }
      // 🔧 ADDED: Cleanup invalid restaurant memberships
      if (restaurantsToCleanup.isNotEmpty) {
        _cleanupMembershipsFromUser(uid, restaurantsToCleanup, 'memberOfRestaurants');
      }

      _userShopIds = validShopIds;
      _userRestaurantIds = validRestaurantIds; // 🔧 ADDED
      // 🔧 CHANGED: true if user has access to ANY shop or restaurant
      _userOwnsShop = validShopIds.isNotEmpty || validRestaurantIds.isNotEmpty;
      
    } catch (e) {
      debugPrint('Error checking shop membership: $e');
      await _checkUserMembershipFallback(uid);
    } finally {
      _isCheckingMembership = false;
      notifyListeners();
    }
  }

  // 🔧 CHANGED: Renamed from _cleanupMultipleShopsFromUser → generalized
  Future<void> _cleanupMembershipsFromUser(
      String uid, List<String> entityIds, String fieldName) async {
    try {
      final Map<String, dynamic> updates = {};
      for (final id in entityIds) {
        updates['$fieldName.$id'] = FieldValue.delete();
      }

      await _firestore.collection('users').doc(uid).update(updates);
      debugPrint('Cleaned up ${entityIds.length} invalid memberships from $fieldName');
    } catch (e) {
      debugPrint('Error cleaning up $fieldName: $e');
    }
  }

  bool _verifyUserStillMemberOfShop(
      String uid, String role, Map<String, dynamic> shopData) {
    switch (role) {
      case 'owner':
        return shopData['ownerId'] == uid;
      case 'co-owner':
        final coOwners = (shopData['coOwners'] as List?)?.cast<String>() ?? [];
        return coOwners.contains(uid);
      case 'editor':
        final editors = (shopData['editors'] as List?)?.cast<String>() ?? [];
        return editors.contains(uid);
      case 'viewer':
        final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
        return viewers.contains(uid);
      default:
        return false;
    }
  }

  Future<void> _checkUserMembershipFallback(String uid) async {
  try {
    // Just read the user doc — 1 read instead of 8 queries
    final userDoc = await _firestore.collection('users').doc(uid).get();

    if (!userDoc.exists) {
      _userOwnsShop = false;
      _userShopIds = [];
      _userRestaurantIds = [];
      notifyListeners();
      return;
    }

    final data = userDoc.data() as Map<String, dynamic>;
    final memberOfShops =
        data['memberOfShops'] as Map<String, dynamic>? ?? {};
    final memberOfRestaurants =
        data['memberOfRestaurants'] as Map<String, dynamic>? ?? {};

    _userShopIds = memberOfShops.keys.toList();
    _userRestaurantIds = memberOfRestaurants.keys.toList();
    _userOwnsShop = _userShopIds.isNotEmpty || _userRestaurantIds.isNotEmpty;
    notifyListeners();
  } catch (e) {
    debugPrint('Fallback membership check failed: $e');
    _userOwnsShop = false;
    _userShopIds = [];
    _userRestaurantIds = [];
    notifyListeners();
  }
}

  @override
  void dispose() {
    _userProvider.removeListener(_onUserProviderChanged);
    super.dispose();
  }
}