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

  // ————————————————————————————————————————————
  // 1️⃣  Auth & favorite‐shops tracking

  bool _userOwnsShop = false;
  bool _isCheckingMembership = false;
  List<String> _userShopIds = []; // User's actual shop IDs (from memberOfShops)
  StreamSubscription<User?>? _authSub;

  // ————————————————————————————————————————————
  // 2️⃣  Featured‐shops list (for horizontal carousel)
  final List<QueryDocumentSnapshot> _shops = [];
  bool _isLoadingShops = false;

  ShopWidgetProvider() {
    // Listen for sign‐in / sign‐out:
    _authSub = _auth.authStateChanges().listen((user) {
      _userOwnsShop = false;
      _userShopIds = [];
      _isCheckingMembership = false;
      notifyListeners();

      if (user != null) {
        _checkUserMembership(user.uid);
      }
    });
    // kick off featured‐shops fetch:
    fetchFeaturedShops();
  }

  // 🚪 Expose for the widgets:

  /// Currently signed in
  User? get currentUser => _auth.currentUser;

  /// Has at least one shop where user is owner/co‐owner/editor/viewer?
  bool get userOwnsShop => _userOwnsShop;

  /// Whether we're currently checking user's shop membership
  bool get isCheckingMembership => _isCheckingMembership;

  /// User's actual shop IDs (from memberOfShops map)
  List<String> get userShopIds => List.unmodifiable(_userShopIds);

  /// First shop ID that the user has access to (safe getter, returns null if none)
  String? get firstUserShopId =>
      _userShopIds.isNotEmpty ? _userShopIds.first : null;

  /// The featured shops to show
  List<QueryDocumentSnapshot> get shops => List.unmodifiable(_shops);

  /// while we're loading that first batch
  bool get isLoadingMore => _isLoadingShops;

  // ————————————————————————————————————————————
  // 👇  Public helpers

  /// Preload the first N shops, sorted by newest first
  Future<void> fetchFeaturedShops({int limit = 10}) async {
    _isLoadingShops = true;
    notifyListeners();
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
    } catch (e) {
      debugPrint('Error fetching featured shops: $e');
    }
    _isLoadingShops = false;
    notifyListeners();
  }

  Future<void> incrementClickCount(String shopId) async {
    await ClickTrackingService.instance.trackShopClick(shopId);
  }

  Future<void> _checkUserMembership(String uid) async {
    // Prevent concurrent calls
    if (_isCheckingMembership) return;
    _isCheckingMembership = true;
    notifyListeners();

    try {
      // 1. Direct lookup on user document
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

      // 2. Check ALL shop memberships, not just the first one
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
            // Shop was deleted, mark for cleanup
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
            // User is no longer member of this shop, mark for cleanup
            shopsToCleanup.add(shopId);
          }
        } catch (e) {
          debugPrint('Error checking shop $shopId: $e');
          // On error, assume shop is still valid to avoid false negatives
          hasValidMembership = true;
          validShopIds.add(shopId);
        }
      }

      // 3. Clean up invalid memberships (fire and forget, don't block UI)
      if (shopsToCleanup.isNotEmpty) {
        _cleanupMultipleShopsFromUser(uid, shopsToCleanup);
      }

      // 4. Update state atomically
      _userShopIds = validShopIds;
      _userOwnsShop = hasValidMembership;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking shop membership: $e');
      // Fallback to old method if new approach fails
      await _checkUserMembershipFallback(uid);
    } finally {
      _isCheckingMembership = false;
      notifyListeners();
    }
  }

// Helper method to clean up multiple shops at once
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

  // Helper method to verify user is still member of shop
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

  // Fallback to original method if optimized approach fails
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

      // Collect all shop IDs from results
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
