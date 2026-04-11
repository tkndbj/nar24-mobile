import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../providers/product_payment_provider.dart';
import '../../widgets/productpayment/address_section_widget.dart';
import '../../widgets/productpayment/complete_payment_button.dart';
import '../../widgets/productpayment/delivery_options_widget.dart';
import '../AGREEMENTS/mesafeli_satis_sozlesmesi.dart';
import '../../models/coupon.dart';

class ProductPaymentScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double totalPrice;
  final Coupon? appliedCoupon;
  final bool useFreeShipping;
  final String? selectedBenefitId;

  const ProductPaymentScreen({
    Key? key,
    required this.items,
    required this.totalPrice,
    this.appliedCoupon,
    this.useFreeShipping = false,
    this.selectedBenefitId,
  }) : super(key: key);

  @override
  _ProductPaymentScreenState createState() => _ProductPaymentScreenState();
}

class _ProductPaymentScreenState extends State<ProductPaymentScreen> {
  final Map<String, bool> _selectedProducts = {};
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();

    // Make a simple copy without recalculating prices
    _items = widget.items.map((item) {
      final product = item['product'] as Product;
      final salePrefs = item['salePreferences'] as Map<String, dynamic>?;

      // Stock calculation (keep this part)
      final String? selColor = item['selectedColor'] as String?;
      final bool isValidColor = selColor != null &&
          selColor.isNotEmpty &&
          product.colorQuantities.containsKey(selColor);

      final int availableStock = isValidColor
          ? product.colorQuantities[selColor]!
          : (product.quantity ?? 0);

      final int? maxAllowed = salePrefs?['maxQuantity'] as int?;
      final int ceiling =
          maxAllowed != null ? min(maxAllowed, availableStock) : availableStock;

      final int rawQty = item['quantity'] as int? ?? 1;
      final int qty = ceiling > 0 ? rawQty.clamp(1, ceiling) : 0;

      return {
        ...item,
        'quantity': qty,
        // DON'T recalculate finalPrice - trust the cart's calculation
        'salePreferences': salePrefs,
      };
    }).toList();

    for (var item in _items) {
      _selectedProducts[item['product'].id] = false;
    }
  }

  void _deleteSelectedProducts(BuildContext context) {
    final selectedIds = _selectedProducts.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    setState(() {
      _items.removeWhere((item) => selectedIds.contains(item['product'].id));
      _selectedProducts
        ..clear()
        ..addEntries(_items.map((item) => MapEntry(item['product'].id, false)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasSelected = _selectedProducts.values.any((v) => v);
    final isDark = theme.brightness == Brightness.dark;

    return ChangeNotifierProvider(
      create: (_) => ProductPaymentProvider(
          items: _items,
          cartCalculatedTotal: widget.totalPrice,
          appliedCoupon: widget.appliedCoupon,
          useFreeShipping: widget.useFreeShipping,
          selectedBenefitId: widget.selectedBenefitId),
      child: Consumer<ProductPaymentProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                l10n.payment,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                if (hasSelected)
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                      onPressed: () => _deleteSelectedProducts(context),
                    ),
                  ),
              ],
            ),
            body: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noProductsSelected,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const DeliveryOptionsWidget(),
                                const SizedBox(height: 16),

                                // Conditionally show address section only when NOT pickup
                                Consumer<ProductPaymentProvider>(
                                  builder: (context, provider, _) {
                                    if (provider.selectedDeliveryOption !=
                                        'pickup') {
                                      return Column(
                                        children: [
                                          const AddressSectionWidget(),
                                          const SizedBox(height: 16),
                                        ],
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            )),
                      ),
                      // Bottom checkout section
                      Container(
                        padding:
                            const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color.fromARGB(255, 33, 31, 49)
                              : Colors.white,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              offset: const Offset(0, -4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Subtotal ─────────────────────────────
                              _CheckoutRow(
                                label: l10n.subtotal,
                                value:
                                    '${widget.totalPrice.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                isDark: isDark,
                              ),

                              // ── Coupon discount ───────────────────────
                              if (provider.appliedCoupon != null &&
                                  provider.couponDiscount > 0) ...[
                                const SizedBox(height: 5),
                                _CheckoutRow(
                                  label: l10n.coupon,
                                  value:
                                      '-${provider.couponDiscount.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                  isDark: isDark,
                                  accent: Colors.green,
                                  leadingIcon: Icons.local_offer_rounded,
                                ),
                              ],

                              // ── Shipping ──────────────────────────────
                              const SizedBox(height: 5),
                              _ShippingRow(
                                isFree: provider.getDeliveryPrice() == 0.0 &&
                                    provider.selectedDeliveryOption != 'pickup',
                                price: provider.getDeliveryPrice(),
                                currency:
                                    _items.first['product'].currency as String,
                                isDark: isDark,
                                l10n: l10n,
                              ),

                              // ── Divider ───────────────────────────────
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.grey.shade200,
                                ),
                              ),

                              // ── Total ─────────────────────────────────
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    l10n.total,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    '${provider.finalTotal.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00A86B),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // ── Agreement ─────────────────────────────
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Checkbox(
                                      value: provider.hasAcceptedAgreement,
                                      onChanged: (v) =>
                                          provider.setAgreementAccepted(
                                              v ?? false),
                                      activeColor: const Color(0xFF00A86B),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const SalesContractScreen(),
                                        ),
                                      ),
                                      child: Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: l10n.iAccept,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                ' ${l10n.distanceSellingAgreement}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF00A86B),
                                              fontWeight: FontWeight.w600,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),
                              const CompletePaymentButton(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
            ),
          );
        },
      ),
    );
  }
}

// ── Reusable compact price row ────────────────────────────────────────────────

class _CheckoutRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? accent;
  final IconData? leadingIcon;

  const _CheckoutRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.accent,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ??
        (isDark ? Colors.grey.shade400 : Colors.grey.shade600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight:
                accent != null ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ── Shipping row with optional "Free" pill ────────────────────────────────────

class _ShippingRow extends StatelessWidget {
  final bool isFree;
  final double price;
  final String currency;
  final bool isDark;
  final AppLocalizations l10n;

  const _ShippingRow({
    required this.isFree,
    required this.price,
    required this.currency,
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 14, color: labelColor),
            const SizedBox(width: 4),
            Text(
              l10n.shipping,
              style: TextStyle(fontSize: 13, color: labelColor),
            ),
          ],
        ),
        if (isFree)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00A86B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              l10n.free,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          )
        else
          Text(
            '${price.toStringAsFixed(2)} $currency',
            style: TextStyle(fontSize: 13, color: labelColor),
          ),
      ],
    );
  }
}
