// lib/services/discount_selection_service.dart
// Production-grade discount selection manager with persistence

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/coupon.dart';
import '../models/user_benefit.dart';
import 'coupon_service.dart';

/// Singleton service to manage discount selection with persistence
/// Features:
/// - Persists selection across app restarts
/// - Auto-validates on load (removes expired/used coupons)
/// - Exposes ValueNotifiers for reactive UI
/// - Clears selection after successful order
class DiscountSelectionService {
  static final DiscountSelectionService _instance =
      DiscountSelectionService._internal();
  factory DiscountSelectionService() => _instance;
  DiscountSelectionService._internal();

  // Keys for SharedPreferences
  static const String _couponIdKey = 'selected_coupon_id';
  static const String _freeShippingKey = 'use_free_shipping';
  static const String _benefitIdKey = 'selected_benefit_id';

  // State notifiers
  final ValueNotifier<Coupon?> selectedCouponNotifier = ValueNotifier(null);
  final ValueNotifier<UserBenefit?> selectedBenefitNotifier =
      ValueNotifier(null);
  final ValueNotifier<bool> useFreeShippingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);

  // Dependencies
  final CouponService _couponService = CouponService();

  // Getters for convenience
  Coupon? get selectedCoupon => selectedCouponNotifier.value;
  UserBenefit? get selectedBenefit => selectedBenefitNotifier.value;
  bool get useFreeShipping => useFreeShippingNotifier.value;
  bool get hasAnyDiscount => selectedCoupon != null || useFreeShipping;

  bool _initialized = false;

  /// Initialize service and load persisted selections
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    isLoadingNotifier.value = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load persisted coupon ID
      final savedCouponId = prefs.getString(_couponIdKey);
      final savedBenefitId = prefs.getString(_benefitIdKey);
      final savedFreeShipping = prefs.getBool(_freeShippingKey) ?? false;

      // Wait for coupon service to have data
      await _waitForCouponService();

      // Validate and restore coupon selection
      if (savedCouponId != null) {
        final coupon = _findCouponById(savedCouponId);
        if (coupon != null && coupon.isValid) {
          selectedCouponNotifier.value = coupon;
          debugPrint('✅ Restored coupon selection: ${coupon.code}');
        } else {
          // Coupon no longer valid, clear from storage
          await prefs.remove(_couponIdKey);
          debugPrint('🗑️ Cleared invalid persisted coupon');
        }
      }

      // Validate and restore free shipping selection
      if (savedFreeShipping && savedBenefitId != null) {
        final benefit = _findBenefitById(savedBenefitId);
        if (benefit != null && benefit.isValid) {
          selectedBenefitNotifier.value = benefit;
          useFreeShippingNotifier.value = true;
          debugPrint('✅ Restored free shipping selection');
        } else {
          // Benefit no longer valid, clear from storage
          await prefs.remove(_freeShippingKey);
          await prefs.remove(_benefitIdKey);
          debugPrint('🗑️ Cleared invalid persisted free shipping');
        }
      }
    } catch (e) {
      debugPrint('❌ Error initializing discount selection: $e');
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// Wait for coupon service to load data
  Future<void> _waitForCouponService() async {
    // Give coupon service time to load (it starts on auth)
    int attempts = 0;
    while (attempts < 10) {
      if (_couponService.couponsNotifier.value.isNotEmpty ||
          _couponService.benefitsNotifier.value.isNotEmpty) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
    debugPrint('⚠️ Coupon service data not loaded after waiting');
  }

  /// Find coupon by ID from coupon service
  Coupon? _findCouponById(String couponId) {
    try {
      return _couponService.couponsNotifier.value.firstWhere(
        (c) => c.id == couponId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Find benefit by ID from coupon service
  UserBenefit? _findBenefitById(String benefitId) {
    try {
      return _couponService.benefitsNotifier.value.firstWhere(
        (b) => b.id == benefitId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Select a coupon (persists automatically)
  Future<void> selectCoupon(Coupon? coupon) async {
    selectedCouponNotifier.value = coupon;

    final prefs = await SharedPreferences.getInstance();
    if (coupon != null) {
      await prefs.setString(_couponIdKey, coupon.id);
      debugPrint('💾 Persisted coupon selection: ${coupon.code}');
    } else {
      await prefs.remove(_couponIdKey);
      debugPrint('🗑️ Cleared coupon selection');
    }
  }

  /// Toggle free shipping (persists automatically)
  Future<void> setFreeShipping(bool use, {UserBenefit? benefit}) async {
    useFreeShippingNotifier.value = use;
    selectedBenefitNotifier.value = use ? benefit : null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_freeShippingKey, use);

    if (use && benefit != null) {
      await prefs.setString(_benefitIdKey, benefit.id);
      debugPrint('💾 Persisted free shipping selection');
    } else {
      await prefs.remove(_benefitIdKey);
      if (!use) {
        debugPrint('🗑️ Cleared free shipping selection');
      }
    }
  }

  /// Clear all selections (call after successful order)
  Future<void> clearAllSelections() async {
    selectedCouponNotifier.value = null;
    selectedBenefitNotifier.value = null;
    useFreeShippingNotifier.value = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_couponIdKey);
    await prefs.remove(_freeShippingKey);
    await prefs.remove(_benefitIdKey);

    debugPrint('🗑️ Cleared all discount selections');
  }

  /// Calculate discount amount for given cart total
  double calculateCouponDiscount(double cartTotal) {
    final coupon = selectedCoupon;
    if (coupon == null || !coupon.isValid) return 0;

    // Cap discount at cart total
    return coupon.amount > cartTotal ? cartTotal : coupon.amount;
  }

  /// Get final total after discounts (excluding delivery)
  double calculateFinalTotal(double cartSubtotal) {
    final discount = calculateCouponDiscount(cartSubtotal);
    return (cartSubtotal - discount).clamp(0, double.infinity);
  }

  /// Validate current selections are still valid
  /// Call this periodically or when returning to cart
  Future<void> revalidateSelections() async {
    bool changed = false;

    // Revalidate coupon
    final coupon = selectedCoupon;
    if (coupon != null) {
      final freshCoupon = _findCouponById(coupon.id);
      if (freshCoupon == null || !freshCoupon.isValid) {
        await selectCoupon(null);
        changed = true;
        debugPrint('⚠️ Coupon no longer valid, cleared selection');
      }
    }

    // Revalidate free shipping
    final benefit = selectedBenefit;
    if (useFreeShipping && benefit != null) {
      final freshBenefit = _findBenefitById(benefit.id);
      if (freshBenefit == null || !freshBenefit.isValid) {
        await setFreeShipping(false);
        changed = true;
        debugPrint(
            '⚠️ Free shipping benefit no longer valid, cleared selection');
      }
    }

    if (changed) {
      debugPrint('🔄 Discount selections revalidated');
    }
  }

  /// Clear selection for a specific coupon (when it gets used)
  Future<void> clearCouponIfSelected(String couponId) async {
    if (selectedCoupon?.id == couponId) {
      await selectCoupon(null);
    }
  }

  /// Clear selection for a specific benefit (when it gets used)
  Future<void> clearBenefitIfSelected(String benefitId) async {
    if (selectedBenefit?.id == benefitId) {
      await setFreeShipping(false);
    }
  }

  /// Dispose resources
  void dispose() {
    selectedCouponNotifier.dispose();
    selectedBenefitNotifier.dispose();
    useFreeShippingNotifier.dispose();
    isLoadingNotifier.dispose();
    _initialized = false;
  }
}
