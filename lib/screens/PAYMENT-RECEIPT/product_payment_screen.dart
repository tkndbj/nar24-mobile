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

  String _getFreeDeliveryText(
    ProductPaymentProvider provider,
    double cartTotal,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final deliveryOption = provider.selectedDeliveryOption;
    final deliveryPrice = provider.getDeliveryPrice();

    if (deliveryPrice == 0.0) {
      return '${l10n.cargoPrice}: ${l10n.free}';
    }

    return '${l10n.cargoPrice}: ${deliveryPrice.toStringAsFixed(2)} TL';
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
                      // Bottom Total and Payment Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color.fromARGB(255, 33, 31, 49)
                              : Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
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
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Subtotal
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        l10n.subtotal,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '${widget.totalPrice.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Coupon discount (if applied)
                                  if (provider.appliedCoupon != null &&
                                      provider.couponDiscount > 0) ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.local_offer,
                                                size: 16, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(
                                              l10n.coupon,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.green),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '-${provider.couponDiscount.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],

                                  // Shipping
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.local_shipping_outlined,
                                            size: 16,
                                            color: provider.useFreeShipping
                                                ? Colors.green
                                                : (isDark
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            l10n.shipping,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: provider.useFreeShipping
                                                  ? Colors.green
                                                  : (isDark
                                                      ? Colors.grey.shade400
                                                      : Colors.grey.shade600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        provider.useFreeShipping
                                            ? l10n.free
                                            : '${provider.getDeliveryPrice().toStringAsFixed(2)} ${_items.first['product'].currency}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: provider.useFreeShipping
                                              ? Colors.green
                                              : (isDark
                                                  ? Colors.grey.shade400
                                                  : Colors.grey.shade600),
                                          fontWeight: provider.useFreeShipping
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Divider(
                                      height: 1,
                                      color: isDark
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade300,
                                    ),
                                  ),

                                  // Final Total
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        l10n.total,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        '${provider.finalTotal.toStringAsFixed(2)} ${_items.first['product'].currency}',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF00A86B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Distance selling agreement checkbox
                              Consumer<ProductPaymentProvider>(
                                builder: (context, provider, _) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value:
                                                provider.hasAcceptedAgreement,
                                            onChanged: (value) {
                                              provider.setAgreementAccepted(
                                                  value ?? false);
                                            },
                                            activeColor:
                                                const Color(0xFF00A86B),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      const SalesContractScreen(),
                                                ),
                                              );
                                            },
                                            child: Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: l10n.iAccept,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: isDark
                                                          ? Colors.white70
                                                          : Colors.grey[700],
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text:
                                                        ' ${l10n.distanceSellingAgreement}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: Color(0xFF00A86B),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
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
