// lib/screens/market/market_checkout_screen.dart

import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../constants/market_categories.dart';
import '../../models/food_address.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_cart_provider.dart';
import '../../user_provider.dart';

// =============================================================================
// TYPES
// =============================================================================

enum _PaymentMethod { payAtDoor, card }

class _OrderSuccess {
  final String orderId;
  const _OrderSuccess({required this.orderId});
}

// =============================================================================
// ENTRY POINT
// =============================================================================

class MarketCheckoutScreen extends StatelessWidget {
  const MarketCheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) => const _MarketCheckoutContent();
}

// =============================================================================
// MAIN CONTENT
// =============================================================================

class _MarketCheckoutContent extends StatefulWidget {
  const _MarketCheckoutContent();

  @override
  State<_MarketCheckoutContent> createState() => _MarketCheckoutContentState();
}

class _MarketCheckoutContentState extends State<_MarketCheckoutContent> {
  _PaymentMethod _paymentMethod = _PaymentMethod.payAtDoor;
  String _orderNotes = '';

  bool _isSubmitting = false;
  String? _error;
  _OrderSuccess? _orderSuccess;

  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  FoodAddress? _getFoodAddress() {
    final raw = context.read<UserProvider>().profileData?['foodAddress'];
    if (raw == null) return null;
    return FoodAddress.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  bool _isFormValid(List<MarketCartItem> items) {
    if (items.isEmpty) return false;
    return _getFoodAddress() != null;
  }

  bool _validateForm() {
    if (_getFoodAddress() == null) {
      setState(() => _error = AppLocalizations.of(context)!.marketCheckoutAddressRequired);
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  void _handleSubmit(MarketCartProvider cart) {
    if (_paymentMethod == _PaymentMethod.payAtDoor) {
      _handlePayAtDoor(cart);
    } else {
      _handleCardPayment(cart);
    }
  }

  Future<void> _handlePayAtDoor(MarketCartProvider cart) async {
    if (_isSubmitting || cart.items.isEmpty) return;
    if (!_validateForm()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('processMarketOrder');

      final result = await fn.call({
        'items': cart.items
            .map((i) => {
                  'itemId': i.itemId,
                  'quantity': i.quantity,
                })
            .toList(),
        'paymentMethod': 'pay_at_door',
        'buyerPhone': _getFoodAddress()?.phoneNumber ?? '',
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true) {
        await cart.clearCart();
        if (mounted) {
          setState(() => _orderSuccess = _OrderSuccess(
                orderId: data['orderId'] as String,
              ));
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? AppLocalizations.of(context)!.marketCheckoutOrderCreationFailed);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCardPayment(MarketCartProvider cart) async {
    if (_isSubmitting || cart.items.isEmpty) return;
    if (!_validateForm()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final orderNumber =
          'MKT-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';

      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('initializeMarketPayment');

      final result = await fn.call({
        'items': cart.items
            .map((i) => {
                  'itemId': i.itemId,
                  'quantity': i.quantity,
                })
            .toList(),
        'buyerPhone': _getFoodAddress()?.phoneNumber ?? '',
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
        'orderNumber': orderNumber,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true && data['gatewayUrl'] != null) {
        if (mounted) {
          // TODO: Create a dedicated market payment WebView screen
          // or reuse the food payment screen with market callback URL
          context.push('/isbankmarketpayment', extra: {
            'gatewayUrl': data['gatewayUrl'],
            'orderNumber': orderNumber,
            'paymentParams': data['paymentParams'],
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? AppLocalizations.of(context)!.marketCheckoutPaymentInitFailed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _randomSuffix() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Consumer<MarketCartProvider>(
      builder: (context, cart, _) {
        if (_orderSuccess != null) {
          return _OrderSuccessScreen(
            orderId: _orderSuccess!.orderId,
            isDark: isDark,
          );
        }

        if (!cart.isInitialized) {
          return Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
            body: SafeArea(child: _CheckoutSkeleton(isDark: isDark)),
          );
        }

        if (cart.items.isEmpty) return _EmptyCartScreen(isDark: isDark);

        final formValid = _isFormValid(cart.items);
        final foodAddress = _getFoodAddress();

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
          appBar: AppBar(
            backgroundColor: const Color(0xFF00A86B),
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              children: [
                ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 140),
                  children: [
                    // Title
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(
                        l10n.marketCheckoutTitle,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Your Order ─────────────────────────────────────
                    _Section(
                      title: l10n.marketCheckoutYourOrder,
                      isDark: isDark,
                      child: Column(
                        children: cart.items
                            .map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _CartItemRow(
                                    item: item,
                                    isDark: isDark,
                                    cart: cart,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Delivery Address ───────────────────────────────
                    _Section(
                      title: l10n.marketCheckoutDeliveryAddress,
                      isDark: isDark,
                      child: _AddressCard(
                        foodAddress: foodAddress,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Order Notes ────────────────────────────────────
                    _Section(
                      title: l10n.marketCheckoutOrderNote,
                      isDark: isDark,
                      child: TextField(
                        controller: _notesController,
                        maxLines: 2,
                        maxLength: 1000,
                        onChanged: (v) => setState(() => _orderNotes = v),
                        decoration: InputDecoration(
                          hintText: l10n.marketCheckoutNoteHint,
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1A1D2E)
                              : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? const Color(0xFF2D2B3F)
                                  : const Color(0xFFD1D5DB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? const Color(0xFF2D2B3F)
                                  : const Color(0xFFD1D5DB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.green),
                          ),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Payment Method ─────────────────────────────────
                    _Section(
                      title: l10n.marketCheckoutPaymentMethod,
                      isDark: isDark,
                      child: Column(children: [
                        _PaymentMethodButton(
                          method: _PaymentMethod.payAtDoor,
                          isSelected:
                              _paymentMethod == _PaymentMethod.payAtDoor,
                          isDark: isDark,
                          onTap: () => setState(
                              () => _paymentMethod = _PaymentMethod.payAtDoor),
                        ),
                        const SizedBox(height: 8),
                        _PaymentMethodButton(
                          method: _PaymentMethod.card,
                          isSelected: _paymentMethod == _PaymentMethod.card,
                          isDark: isDark,
                          onTap: () => setState(
                              () => _paymentMethod = _PaymentMethod.card),
                        ),
                      ]),
                    ),
                  ],
                ),

                // ── Sticky bottom bar ──────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _StickyBottomBar(
                    isDark: isDark,
                    error: _error,
                    subtotal: cart.totals.subtotal,
                    itemCount: cart.totals.itemCount,
                    isFormValid: formValid,
                    isSubmitting: _isSubmitting,
                    paymentMethod: _paymentMethod,
                    onSubmit: () => _handleSubmit(cart),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// ADDRESS CARD
// =============================================================================

class _AddressCard extends StatelessWidget {
  final FoodAddress? foodAddress;
  final bool isDark;

  const _AddressCard({required this.foodAddress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (foodAddress != null) {
      final addr = foodAddress!;
      final cityLine = [addr.city, addr.mainRegion]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF211F31) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on_rounded,
                size: 16, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addr.addressLine1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
                if (addr.addressLine2 != null && addr.addressLine2!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      addr.addressLine2!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                    ),
                  ),
                if (cityLine.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      cityLine,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                  ),
                if (addr.phoneNumber != null && addr.phoneNumber!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      addr.phoneNumber!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );
    }

    // No address
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[300]!,
          width: 1.5,
        ),
      ),
      child: Row(children: [
        Icon(Icons.location_on_outlined,
            size: 20, color: isDark ? Colors.grey[600] : Colors.grey[400]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.marketCheckoutNoAddress,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/food-address'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.marketCheckoutAddAddress,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// SECTION WRAPPER
// =============================================================================

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;

  const _Section({
    required this.title,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: isDark ? Colors.grey[400] : Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// =============================================================================
// CART ITEM ROW
// =============================================================================

class _CartItemRow extends StatelessWidget {
  final MarketCartItem item;
  final bool isDark;
  final MarketCartProvider cart;

  const _CartItemRow({
    required this.item,
    required this.isDark,
    required this.cart,
  });

  @override
  Widget build(BuildContext context) {
    final category = kMarketCategoryMap[item.category];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D2E) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2D3E) : const Color(0xFFD1D5DB),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _Placeholder(category: category, isDark: isDark),
                  )
                : _Placeholder(category: category, isDark: isDark),
          ),
        ),
        const SizedBox(width: 12),

        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.brand.isNotEmpty)
                        Text(
                          item.brand,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => cart.removeItem(item.itemId),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[400]),
                  ),
                ),
              ]),
              if (item.type.isNotEmpty)
                Text(
                  item.type,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[700],
                  ),
                ),
              const SizedBox(height: 8),
              Row(children: [
                _InlineQty(
                  quantity: item.quantity,
                  isDark: isDark,
                  onDecrease: () =>
                      cart.updateQuantity(item.itemId, item.quantity - 1),
                  onIncrease: () =>
                      cart.updateQuantity(item.itemId, item.quantity + 1),
                ),
                const Spacer(),
                Text(
                  '${item.lineTotal.toStringAsFixed(2)} TL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.green[400] : Colors.green[600],
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final MarketCategory? category;
  final bool isDark;

  const _Placeholder({required this.category, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: category != null
            ? category!.color.withOpacity(isDark ? 0.15 : 0.1)
            : (isDark ? const Color(0xFF3A3850) : Colors.grey[100]),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child:
          Text(category?.emoji ?? '📦', style: const TextStyle(fontSize: 22)),
    );
  }
}

class _InlineQty extends StatelessWidget {
  final int quantity;
  final bool isDark;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _InlineQty({
    required this.quantity,
    required this.isDark,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        _QtyBtn(icon: Icons.remove_rounded, isDark: isDark, onTap: onDecrease),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '$quantity',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
        ),
        _QtyBtn(icon: Icons.add_rounded, isDark: isDark, onTap: onIncrease),
      ]);
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _QtyBtn({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB),
            ),
          ),
          child: Icon(icon,
              size: 12, color: isDark ? Colors.grey[400] : Colors.grey[500]),
        ),
      );
}

// =============================================================================
// PAYMENT METHOD BUTTON
// =============================================================================

class _PaymentMethodButton extends StatelessWidget {
  final _PaymentMethod method;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _PaymentMethodButton({
    required this.method,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPay = method == _PaymentMethod.payAtDoor;
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.green.withOpacity(0.10) : Colors.green[50])
              : (isDark ? Colors.transparent : const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.green.withOpacity(0.5) : Colors.green[400]!)
                : (isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB)),
          ),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green.withOpacity(0.2)
                  : (isDark ? const Color(0xFF2D2B3F) : Colors.grey[100]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPay ? Icons.payments_rounded : Icons.credit_card_rounded,
              size: 20,
              color: isSelected
                  ? Colors.green
                  : (isDark ? Colors.grey[500] : Colors.grey[400]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPay ? l10n.marketPaymentMethodPayAtDoor : l10n.marketPaymentMethodCard,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? (isDark ? Colors.green[400] : Colors.green[700])
                        : (isDark ? Colors.grey[200] : Colors.grey[800]),
                  ),
                ),
                Text(
                  isPay
                      ? l10n.marketPaymentMethodPayAtDoorSubtitle
                      : l10n.marketPaymentMethodCardSubtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// STICKY BOTTOM BAR
// =============================================================================

class _StickyBottomBar extends StatelessWidget {
  final bool isDark;
  final bool isFormValid;
  final bool isSubmitting;
  final String? error;
  final double subtotal;
  final int itemCount;
  final _PaymentMethod paymentMethod;
  final VoidCallback onSubmit;

  const _StickyBottomBar({
    required this.isDark,
    required this.error,
    required this.subtotal,
    required this.itemCount,
    required this.isFormValid,
    required this.isSubmitting,
    required this.paymentMethod,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = isFormValid && !isSubmitting;
    final isCard = paymentMethod == _PaymentMethod.card;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF1C1A29) : Colors.white.withOpacity(0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200]!,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Error
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.red.withOpacity(0.10) : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.error_outline_rounded,
                    size: 16, color: Colors.red[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.red[400] : Colors.red[600],
                    ),
                  ),
                ),
              ]),
            ),
          ),

        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              l10n.marketCartItemCount(itemCount),
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[700],
              ),
            ),
            Text(
              '${subtotal.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
          ]),
          const Spacer(),
          ElevatedButton(
            onPressed: canSubmit ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  isDark ? const Color(0xFF2D2B3F) : Colors.grey[300],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isCard
                          ? Icons.credit_card_rounded
                          : Icons.shopping_bag_rounded,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCard ? l10n.marketCheckoutPayButton : l10n.marketCheckoutPlaceOrder,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ]),
          ),
        ]),
      ]),
    );
  }
}

// =============================================================================
// ORDER SUCCESS SCREEN
// =============================================================================

class _OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  final bool isDark;

  const _OrderSuccessScreen({
    required this.orderId,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset(
                  'assets/images/success.gif',
                  width: 170,
                  height: 170,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 80, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.marketOrderReceivedTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.notifications_active_rounded,
                      size: 16,
                      color: isDark ? Colors.green[400] : Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.marketOrderReceivedNotifications,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.support_agent_rounded,
                      size: 16,
                      color: isDark ? Colors.green[400] : Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.marketOrderReceivedSupport,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  '${l10n.marketPaymentOrderLabel}: ${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go('/market'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.marketPaymentReturnToMarket,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EMPTY CART SCREEN
// =============================================================================

class _EmptyCartScreen extends StatelessWidget {
  final bool isDark;
  const _EmptyCartScreen({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined,
                size: 64, color: isDark ? Colors.grey[600] : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l10n.marketCartEmptyTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.marketCartEmptyStartShopping,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/market'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l10n.marketCartGoToMarket,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// SKELETON
// =============================================================================

class _CheckoutSkeleton extends StatelessWidget {
  final bool isDark;
  const _CheckoutSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF3A3850) : Colors.grey[200]!;
    final card = isDark ? const Color(0xFF2D2B3F) : Colors.white;

    Widget box(double h, double? w) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    Widget section(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.only(bottom: 10),
          color: card,
          child: child,
        );

    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: box(28, 140),
      ),
      // Items
      section(Column(children: [
        box(11, 80),
        const SizedBox(height: 12),
        ...List.generate(
          2,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF211F31) : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                box(56, 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(10, 40),
                      const SizedBox(height: 4),
                      box(14, null),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [box(28, 96), box(14, 56)],
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ])),
      // Address
      section(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [box(11, 120), const SizedBox(height: 12), box(64, null)],
      )),
      // Notes
      section(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [box(11, 100), const SizedBox(height: 12), box(56, null)],
      )),
      // Payment
      section(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(11, 120),
          const SizedBox(height: 12),
          box(64, null),
          const SizedBox(height: 8),
          box(64, null),
        ],
      )),
    ]);
  }
}
