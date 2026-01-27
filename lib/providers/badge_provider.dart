import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // for ChangeNotifier and ValueNotifier
import '../services/lifecycle_aware.dart';
import '../services/app_lifecycle_manager.dart';

class BadgeProvider extends ChangeNotifier with LifecycleAwareMixin {
  /// For controlling unread Notifications badge count
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  StreamSubscription<User?>? _authSubscription;

  // Track the current user ID for reconnection
  String? _currentUserId;

  @override
  LifecyclePriority get lifecyclePriority => LifecyclePriority.high;

  BadgeProvider() {
    _init();

    // Register with lifecycle manager
    AppLifecycleManager.instance.register(this, name: 'BadgeProvider');
  }

  /// Call this when the app starts (or when user logs in/out) so it sets up listeners.
  void _init() {
    // Listen to auth state changes.
    _authSubscription?.cancel();
    _authSubscription = _auth.userChanges().listen((User? user) {
      if (user == null) {
        // User logged out
        _currentUserId = null;
        _cancelSubscriptions();
        unreadNotificationsCount.value = 0;
      } else {
        // User logged in; set up Firestore listeners.
        _currentUserId = user.uid;
        _setupFirestoreListeners(user.uid);
      }
    });

    markInitialized();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> onPause() async {
    await super.onPause();

    // Cancel Firestore listeners to save resources
    _cancelSubscriptions();

    if (kDebugMode) {
      debugPrint('⏸️ BadgeProvider: Listeners paused');
    }
  }

  @override
  Future<void> onResume(Duration pauseDuration) async {
    await super.onResume(pauseDuration);

    // Re-setup listeners if user is logged in
    if (_currentUserId != null) {
      _setupFirestoreListeners(_currentUserId!);
    }

    if (kDebugMode) {
      debugPrint('▶️ BadgeProvider: Listeners resumed');
    }
  }

  /// Sets up Firestore listeners.
  void _setupFirestoreListeners(String userId) {
    _cancelSubscriptions();

    // (B) Listen to the 'notifications' subcollection.
    _notificationsSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .orderBy('type')
        .where('type', isNotEqualTo: 'message')
        .snapshots()
        .listen((QuerySnapshot querySnapshot) {
      unreadNotificationsCount.value = querySnapshot.docs.length;
    }, onError: (error) {
      debugPrint('Error listening to notifications subcollection: $error');
    });
  }

  /// Cancel all previously attached listeners.
  void _cancelSubscriptions() {
    _notificationsSubscription?.cancel();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cancelSubscriptions();
    super.dispose();
  }
}
