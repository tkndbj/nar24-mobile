// lib/services/coupon_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/coupon.dart';
import '../models/user_benefit.dart';

/// Service for managing user coupons and benefits (free shipping, etc.)
///
/// This service provides:
/// - Real-time listening to user's coupons and benefits
/// - Coupon application during checkout
/// - Benefit usage tracking
class CouponService {
  static final CouponService _instance = CouponService._internal();
  factory CouponService() => _instance;
  CouponService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Reactive state
  final ValueNotifier<List<Coupon>> couponsNotifier = ValueNotifier([]);
  final ValueNotifier<List<UserBenefit>> benefitsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);

  // Stream subscriptions
  StreamSubscription<QuerySnapshot>? _couponsSubscription;
  StreamSubscription<QuerySnapshot>? _benefitsSubscription;
  StreamSubscription<User?>? _authSubscription;

  static const double freeShippingMinimum = 1000.0;
static const double couponMinimumMultiplier = 2.0;

  bool _initialized = false;

  // Public getters
  List<Coupon> get coupons => couponsNotifier.value;
  List<UserBenefit> get benefits => benefitsNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  bool get isInitialized => _initialized;
  List<Coupon> get userCoupons => coupons;

  /// Get only active (unused, non-expired) coupons
  List<Coupon> get activeCoupons => coupons.where((c) => c.isValid).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount)); // Sort by amount desc

  /// Get only active free shipping benefits
  List<UserBenefit> get activeFreeShippingBenefits => benefits
      .where((b) => b.isValid && b.type == BenefitType.freeShipping)
      .toList();

  /// Check if user has any active free shipping benefit
  bool get hasFreeShipping => activeFreeShippingBenefits.isNotEmpty;

  /// Get the first available free shipping benefit
  UserBenefit? get availableFreeShipping =>
      activeFreeShippingBenefits.isNotEmpty
          ? activeFreeShippingBenefits.first
          : null;

  /// Total available coupon value
  double get totalCouponValue =>
      activeCoupons.fold(0.0, (sum, coupon) => sum + coupon.amount);

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the service and start listening to user changes
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _authSubscription = _auth.authStateChanges().listen(_handleAuthChange);

    // If user is already logged in, start listening
    if (_auth.currentUser != null) {
      _startListening(_auth.currentUser!.uid);
    }

    debugPrint('✅ CouponService initialized');
  }

  void _handleAuthChange(User? user) {
    if (user == null) {
      _stopListening();
      _clearData();
    } else {
      _startListening(user.uid);
    }
  }

  void _startListening(String userId) {
    _stopListening(); // Clear any existing subscriptions
    isLoadingNotifier.value = true;

    // Listen to coupons
    _couponsSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('coupons')
        .where('isUsed', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          _handleCouponsUpdate,
          onError: (e) => debugPrint('❌ Coupons listener error: $e'),
        );

    // Listen to benefits
    _benefitsSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('benefits')
        .where('isUsed', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          _handleBenefitsUpdate,
          onError: (e) => debugPrint('❌ Benefits listener error: $e'),
        );

    debugPrint('🔴 Started listening to coupons & benefits for $userId');
  }

  void _stopListening() {
    _couponsSubscription?.cancel();
    _couponsSubscription = null;
    _benefitsSubscription?.cancel();
    _benefitsSubscription = null;
  }

  void _clearData() {
    couponsNotifier.value = [];
    benefitsNotifier.value = [];
    isLoadingNotifier.value = false;
  }

  bool isCouponApplicable(Coupon coupon, double cartTotal) {
  if (!coupon.isValid) return false;
  final minimumRequired = coupon.amount * couponMinimumMultiplier;
  return cartTotal >= minimumRequired;
}

/// Get minimum cart total required for a coupon
double getMinimumForCoupon(Coupon coupon) {
  return coupon.amount * couponMinimumMultiplier;
}

/// Check if free shipping is applicable for given cart total
bool isFreeShippingApplicable(double cartTotal) {
  return cartTotal >= freeShippingMinimum;
}

  void _handleCouponsUpdate(QuerySnapshot snapshot) {
    final coupons = snapshot.docs
        .map((doc) =>
            Coupon.fromJson(doc.data() as Map<String, dynamic>, doc.id))
        .where((c) => c.isValid) // Filter out expired ones
        .toList();

    couponsNotifier.value = coupons;
    isLoadingNotifier.value = false;

    debugPrint('📦 Coupons updated: ${coupons.length} active');
  }

  void _handleBenefitsUpdate(QuerySnapshot snapshot) {
    final benefits = snapshot.docs
        .map((doc) =>
            UserBenefit.fromJson(doc.data() as Map<String, dynamic>, doc.id))
        .where((b) => b.isValid) // Filter out expired ones
        .toList();

    benefitsNotifier.value = benefits;
    isLoadingNotifier.value = false;

    debugPrint('🎁 Benefits updated: ${benefits.length} active');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COUPON OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all coupons for current user (including used ones)
  Future<List<Coupon>> fetchAllCoupons() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('coupons')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Coupon.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching all coupons: $e');
      return [];
    }
  }

 double calculateCouponDiscount(Coupon coupon, double cartTotal) {
  if (!coupon.isValid) return 0.0;
  
  // Check minimum cart total requirement (2x coupon amount)
  if (!isCouponApplicable(coupon, cartTotal)) return 0.0;
  
  // Coupon cannot exceed cart total
  return coupon.amount > cartTotal ? cartTotal : coupon.amount;
}

  /// Find the best coupon for a given cart total
  /// Returns the coupon that provides maximum discount without exceeding cart total
  Coupon? findBestCoupon(double cartTotal) {
    if (activeCoupons.isEmpty) return null;

    // Find coupons that don't exceed cart total, sorted by amount desc
    final usableCoupons =
        activeCoupons.where((c) => c.amount <= cartTotal).toList();

    if (usableCoupons.isNotEmpty) {
      return usableCoupons.first; // Already sorted by amount desc
    }

    // If all coupons exceed cart total, return the smallest one
    // (user still gets full cart covered)
    return activeCoupons.last;
  }

  /// Mark a coupon as used after successful order
  Future<bool> useCoupon(String couponId, String orderId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('coupons')
          .doc(couponId)
          .update({
        'isUsed': true,
        'usedAt': FieldValue.serverTimestamp(),
        'orderId': orderId,
      });

      debugPrint('✅ Coupon $couponId marked as used for order $orderId');
      return true;
    } catch (e) {
      debugPrint('❌ Error marking coupon as used: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BENEFIT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all benefits for current user (including used ones)
  Future<List<UserBenefit>> fetchAllBenefits() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('benefits')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => UserBenefit.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching all benefits: $e');
      return [];
    }
  }

  /// Mark a benefit as used after successful order
  Future<bool> useBenefit(String benefitId, String orderId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('benefits')
          .doc(benefitId)
          .update({
        'isUsed': true,
        'usedAt': FieldValue.serverTimestamp(),
        'orderId': orderId,
      });

      debugPrint('✅ Benefit $benefitId marked as used for order $orderId');
      return true;
    } catch (e) {
      debugPrint('❌ Error marking benefit as used: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECKOUT HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate final totals with coupon and free shipping applied
  CheckoutDiscounts calculateCheckoutDiscounts({
    required double subtotal,
    required double shippingCost,
    Coupon? selectedCoupon,
    bool useFreeShipping = false,
  }) {
    double couponDiscount = 0.0;
    double shippingDiscount = 0.0;
    UserBenefit? usedFreeShipping;

    // Apply coupon discount
    if (selectedCoupon != null && selectedCoupon.isValid) {
      couponDiscount = calculateCouponDiscount(selectedCoupon, subtotal);
    }

    // Apply free shipping
    if (useFreeShipping && hasFreeShipping) {
      shippingDiscount = shippingCost;
      usedFreeShipping = availableFreeShipping;
    }

    final finalSubtotal = subtotal - couponDiscount;
    final finalShipping = shippingCost - shippingDiscount;
    final finalTotal = finalSubtotal + finalShipping;

    return CheckoutDiscounts(
      originalSubtotal: subtotal,
      originalShipping: shippingCost,
      couponDiscount: couponDiscount,
      shippingDiscount: shippingDiscount,
      finalSubtotal: finalSubtotal,
      finalShipping: finalShipping,
      finalTotal: finalTotal,
      appliedCoupon: selectedCoupon,
      appliedFreeShipping: usedFreeShipping,
    );
  }

  /// Mark all applied discounts as used after successful order
  Future<void> markDiscountsAsUsed({
    required String orderId,
    Coupon? usedCoupon,
    UserBenefit? usedFreeShipping,
  }) async {
    final futures = <Future>[];

    if (usedCoupon != null) {
      futures.add(useCoupon(usedCoupon.id, orderId));
    }

    if (usedFreeShipping != null) {
      futures.add(useBenefit(usedFreeShipping.id, orderId));
    }

    await Future.wait(futures);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REFRESH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Force refresh coupons and benefits from server
  Future<void> refresh() async {
    final user = _auth.currentUser;
    if (user == null) return;

    isLoadingNotifier.value = true;

    try {
      // Fetch coupons
      final couponsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('coupons')
          .where('isUsed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.server));

      final coupons = couponsSnapshot.docs
          .map((doc) => Coupon.fromJson(doc.data(), doc.id))
          .where((c) => c.isValid)
          .toList();

      couponsNotifier.value = coupons;

      // Fetch benefits
      final benefitsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('benefits')
          .where('isUsed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.server));

      final benefits = benefitsSnapshot.docs
          .map((doc) => UserBenefit.fromJson(doc.data(), doc.id))
          .where((b) => b.isValid)
          .toList();

      benefitsNotifier.value = benefits;

      debugPrint(
          '✅ Refreshed: ${coupons.length} coupons, ${benefits.length} benefits');
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _stopListening();
    _authSubscription?.cancel();
    _initialized = false;
    debugPrint('🧹 CouponService disposed');
  }
}

/// Result of checkout discount calculations
class CheckoutDiscounts {
  final double originalSubtotal;
  final double originalShipping;
  final double couponDiscount;
  final double shippingDiscount;
  final double finalSubtotal;
  final double finalShipping;
  final double finalTotal;
  final Coupon? appliedCoupon;
  final UserBenefit? appliedFreeShipping;

  CheckoutDiscounts({
    required this.originalSubtotal,
    required this.originalShipping,
    required this.couponDiscount,
    required this.shippingDiscount,
    required this.finalSubtotal,
    required this.finalShipping,
    required this.finalTotal,
    this.appliedCoupon,
    this.appliedFreeShipping,
  });

  bool get hasCouponDiscount => couponDiscount > 0;
  bool get hasFreeShipping => shippingDiscount > 0;
  bool get hasAnyDiscount => hasCouponDiscount || hasFreeShipping;
  double get totalSavings => couponDiscount + shippingDiscount;
}
