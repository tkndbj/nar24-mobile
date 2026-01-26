// lib/widgets/coupon_selection_sheet.dart

import 'package:flutter/material.dart';
import '../models/coupon.dart';
import '../models/user_benefit.dart';
import '../services/coupon_service.dart';
import '../generated/l10n/app_localizations.dart';
import '../services/discount_selection_service.dart';

/// Bottom sheet for selecting coupons and free shipping during checkout
class CouponSelectionSheet extends StatefulWidget {
  final double cartTotal;
  final Coupon? selectedCoupon;
  final bool useFreeShipping;
  final Function(Coupon?) onCouponSelected;
  final Function(bool) onFreeShippingToggled;

  const CouponSelectionSheet({
    Key? key,
    required this.cartTotal,
    this.selectedCoupon,
    required this.useFreeShipping,
    required this.onCouponSelected,
    required this.onFreeShippingToggled,
  }) : super(key: key);

  @override
  State<CouponSelectionSheet> createState() => _CouponSelectionSheetState();
}

class _CouponSelectionSheetState extends State<CouponSelectionSheet> {
  final DiscountSelectionService _discountService = DiscountSelectionService();
  final CouponService _couponService = CouponService();
  Coupon? _tempSelectedCoupon;
  bool _tempUseFreeShipping = false;

  @override
  void initState() {
    super.initState();
    _tempSelectedCoupon = widget.selectedCoupon;
    _tempUseFreeShipping = widget.useFreeShipping;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.local_offer, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.couponsAndBenefits ?? 'Coupons & Benefits',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Free Shipping Section
                  _buildFreeShippingSection(l10n, isDark),

                  const SizedBox(height: 20),

                  // Coupons Section
                  _buildCouponsSection(l10n, isDark),
                ],
              ),
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1A29) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _applySelections,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.apply ?? 'Apply',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeShippingSection(AppLocalizations l10n, bool isDark) {
    return ValueListenableBuilder<List<UserBenefit>>(
      valueListenable: _couponService.benefitsNotifier,
      builder: (context, benefits, _) {
        final freeShippingBenefits = benefits
            .where((b) => b.isValid && b.type == BenefitType.freeShipping)
            .toList();

        if (freeShippingBenefits.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  l10n.freeShipping ?? 'Free Shipping',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${freeShippingBenefits.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Free shipping toggle card
            GestureDetector(
              onTap: () {
                setState(() {
                  _tempUseFreeShipping = !_tempUseFreeShipping;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _tempUseFreeShipping
                      ? Colors.green.withOpacity(0.1)
                      : (isDark ? Colors.grey[800] : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _tempUseFreeShipping
                        ? Colors.green
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        color: Colors.green,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.useFreeShipping ?? 'Use Free Shipping',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.freeShippingDescription ??
                                'Your shipping fee will be waived',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: _tempUseFreeShipping,
                      onChanged: (value) {
                        setState(() {
                          _tempUseFreeShipping = value ?? false;
                        });
                      },
                      activeColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCouponsSection(AppLocalizations l10n, bool isDark) {
    return ValueListenableBuilder<List<Coupon>>(
      valueListenable: _couponService.couponsNotifier,
      builder: (context, coupons, _) {
        final activeCoupons = coupons.where((c) => c.isValid).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.confirmation_number,
                    size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  l10n.discountCoupons ?? 'Discount Coupons',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${activeCoupons.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activeCoupons.isEmpty)
              _buildEmptyCouponsCard(l10n, isDark)
            else
              Column(
                children: [
                  // "No coupon" option
                  _buildCouponCard(
                    null,
                    l10n.noCoupon ?? 'No Coupon',
                    l10n.proceedWithoutDiscount ?? 'Proceed without discount',
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  // Available coupons
                  ...activeCoupons.map((coupon) {
                    final discount = _couponService.calculateCouponDiscount(
                      coupon,
                      widget.cartTotal,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildCouponCard(
                        coupon,
                        '${coupon.amount.toStringAsFixed(0)} ${coupon.currency}',
                        coupon.description ??
                            (discount < coupon.amount
                                ? '${l10n.willDeduct ?? "Will deduct"} ${discount.toStringAsFixed(2)} ${coupon.currency}'
                                : l10n.discountCouponDesc ?? 'Discount coupon'),
                        isDark,
                        expiresIn: coupon.daysUntilExpiry,
                      ),
                    );
                  }),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildCouponCard(
    Coupon? coupon,
    String title,
    String subtitle,
    bool isDark, {
    int? expiresIn,
  }) {
    final isSelected = coupon == null
        ? _tempSelectedCoupon == null
        : _tempSelectedCoupon?.id == coupon.id;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tempSelectedCoupon = coupon;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.orange.withOpacity(0.1)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: coupon == null
                    ? Colors.grey.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                coupon == null
                    ? Icons.remove_circle_outline
                    : Icons.confirmation_number,
                color: coupon == null ? Colors.grey : Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: coupon == null ? Colors.grey : null,
                          ),
                        ),
                      ),
                      if (expiresIn != null && expiresIn <= 7)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: expiresIn <= 3
                                ? Colors.red.withOpacity(0.1)
                                : Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            expiresIn == 0 ? 'Today' : '$expiresIn days',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: expiresIn <= 3
                                  ? Colors.red
                                  : Colors.amber[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Radio<String?>(
              value: coupon?.id,
              groupValue: _tempSelectedCoupon?.id,
              onChanged: (value) {
                setState(() {
                  _tempSelectedCoupon = coupon;
                });
              },
              activeColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCouponsCard(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noCouponsAvailable ?? 'No coupons available',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _applySelections() {
    widget.onCouponSelected(_tempSelectedCoupon);
    widget.onFreeShippingToggled(_tempUseFreeShipping);
    Navigator.pop(context);
  }
}

/// Compact widget to show selected discounts in checkout
class SelectedDiscountsDisplay extends StatelessWidget {
  final Coupon? selectedCoupon;
  final bool useFreeShipping;
  final double couponDiscount;
  final double shippingDiscount;
  final VoidCallback onTap;

  const SelectedDiscountsDisplay({
    Key? key,
    this.selectedCoupon,
    required this.useFreeShipping,
    required this.couponDiscount,
    required this.shippingDiscount,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDiscount = selectedCoupon != null || useFreeShipping;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasDiscount
              ? Colors.green.withOpacity(0.1)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasDiscount
                ? Colors.green.withOpacity(0.3)
                : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasDiscount ? Icons.local_offer : Icons.add_circle_outline,
              color: hasDiscount ? Colors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: hasDiscount
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedCoupon != null)
                          Row(
                            children: [
                              Text(
                                '${l10n.coupon ?? "Coupon"}: ',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                '-${couponDiscount.toStringAsFixed(2)} TL',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        if (useFreeShipping)
                          Row(
                            children: [
                              Text(
                                '${l10n.shipping ?? "Shipping"}: ',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                l10n.free ?? 'Free',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                      ],
                    )
                  : Text(
                      l10n.addCouponOrBenefit ?? 'Add coupon or benefit',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
