// lib/providers/shop_widget_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/click_tracking_service.dart';

class ShopWidgetProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _configCollection = 'app_config';
  static const String _configDoc = 'featured_shops';

  // ————————————————————————————————————————————
  // 1️⃣  Auth & favorite‐shops tracking

  bool _userOwnsShop = false;
  bool _isCheckingMembership = false;
  List<String> _userShopIds = [];
  StreamSubscription<User?>? _authSub;

  // ————————————————————————————————————————————
  // 2️⃣  Featured‐shops list (for horizontal carousel)
  // ✅ FIXED: Changed from QueryDocumentSnapshot to DocumentSnapshot
  final List<DocumentSnapshot> _shops = [];
  bool _isLoadingShops = false;

  ShopWidgetProvider() {
    _authSub = _auth.authStateChanges().listen((user) {
      _userOwnsShop = false;
      _userShopIds = [];
      _isCheckingMembership = false;
      notifyListeners();

      if (user != null) {
        _checkUserMembership(user.uid);
      }
    });
    fetchFeaturedShops();
  }

  // 🚪 Expose for the widgets:

  User? get currentUser => _auth.currentUser;
  bool get userOwnsShop => _userOwnsShop;
  bool get isCheckingMembership => _isCheckingMembership;
  List<String> get userShopIds => List.unmodifiable(_userShopIds);
  String? get firstUserShopId =>
      _userShopIds.isNotEmpty ? _userShopIds.first : null;

  // ✅ FIXED: Changed return type
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
            debugPrint('✅ Loaded ${shops.length} configured featured shops');
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

  // ✅ FIXED: Changed return type and removed invalid cast
  Future<List<DocumentSnapshot>> _fetchShopsByIds(List<String> shopIds) async {
    final List<DocumentSnapshot> shops = [];

    for (final shopId in shopIds) {
      try {
        final shopDoc = await _firestore.collection('shops').doc(shopId).get();
        
        if (shopDoc.exists) {
          final data = shopDoc.data();
          // Only include active shops
          if (data?['isActive'] != false) {
            shops.add(shopDoc);  // ✅ No casting needed - it's already DocumentSnapshot
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
        ..addAll(snap.docs);  // ✅ QueryDocumentSnapshot extends DocumentSnapshot, so this works
      
      debugPrint('✅ Loaded ${snap.docs.length} default featured shops');
    } catch (e) {
      debugPrint('❌ Error fetching default shops: $e');
    } finally {
      _isLoadingShops = false;
      notifyListeners();
    }
  }

  Future<void> incrementClickCount(String shopId) async {
    await ClickTrackingService.instance.trackShopClick(shopId);
  }

  Future<void> _checkUserMembership(String uid) async {
    if (_isCheckingMembership) return;
    _isCheckingMembership = true;
    notifyListeners();

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        _userOwnsShop = false;
        _userShopIds = [];
        notifyListeners();
        return;
      }

      final userData = userDoc.data();
      final memberOfShops =
          userData?['memberOfShops'] as Map<String, dynamic>? ?? {};

      if (memberOfShops.isEmpty) {
        _userOwnsShop = false;
        _userShopIds = [];
        notifyListeners();
        return;
      }

      bool hasValidMembership = false;
      List<String> validShopIds = [];
      List<String> shopsToCleanup = [];

      for (final entry in memberOfShops.entries) {
        final shopId = entry.key;
        final userRole = entry.value as String;

        try {
          final shopDoc =
              await _firestore.collection('shops').doc(shopId).get();

          if (!shopDoc.exists) {
            shopsToCleanup.add(shopId);
            continue;
          }

          final shopData = shopDoc.data() as Map<String, dynamic>;
          final stillMember =
              _verifyUserStillMemberOfShop(uid, userRole, shopData);

          if (stillMember) {
            hasValidMembership = true;
            validShopIds.add(shopId);
          } else {
            shopsToCleanup.add(shopId);
          }
        } catch (e) {
          debugPrint('Error checking shop $shopId: $e');
          hasValidMembership = true;
          validShopIds.add(shopId);
        }
      }

      if (shopsToCleanup.isNotEmpty) {
        _cleanupMultipleShopsFromUser(uid, shopsToCleanup);
      }

      _userShopIds = validShopIds;
      _userOwnsShop = hasValidMembership;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking shop membership: $e');
      await _checkUserMembershipFallback(uid);
    } finally {
      _isCheckingMembership = false;
      notifyListeners();
    }
  }

  Future<void> _cleanupMultipleShopsFromUser(
      String uid, List<String> shopIds) async {
    try {
      final Map<String, dynamic> updates = {};
      for (final shopId in shopIds) {
        updates['memberOfShops.$shopId'] = FieldValue.delete();
      }

      await _firestore.collection('users').doc(uid).update(updates);
      debugPrint('Cleaned up ${shopIds.length} invalid shop memberships');
    } catch (e) {
      debugPrint('Error cleaning up multiple shops from user: $e');
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
      final futures = [
        _firestore
            .collection('shops')
            .where('ownerId', isEqualTo: uid)
            .limit(5)
            .get(),
        _firestore
            .collection('shops')
            .where('coOwners', arrayContains: uid)
            .limit(5)
            .get(),
        _firestore
            .collection('shops')
            .where('editors', arrayContains: uid)
            .limit(5)
            .get(),
        _firestore
            .collection('shops')
            .where('viewers', arrayContains: uid)
            .limit(5)
            .get(),
      ];
      final results = await Future.wait(futures);

      final shopIds = <String>{};
      for (final result in results) {
        for (final doc in result.docs) {
          shopIds.add(doc.id);
        }
      }

      final owns = shopIds.isNotEmpty;
      _userShopIds = shopIds.toList();
      _userOwnsShop = owns;
      notifyListeners();
    } catch (e) {
      debugPrint('Fallback membership check failed: $e');
      _userOwnsShop = false;
      _userShopIds = [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}