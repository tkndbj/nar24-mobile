// lib/screens/food/food_checkout_screen.dart
//
// Mirrors: app/food-checkout/page.tsx + FoodCheckoutContent

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../user_provider.dart';
import '../../models/food_address.dart';
import '../../providers/food_cart_provider.dart';
import '../../utils/food_localization.dart';

// =============================================================================
// TYPES
// =============================================================================

enum PaymentMethod { payAtDoor, card }

enum DeliveryType { delivery, pickup }

class _OrderSuccess {
  final String orderId;
  final int estimatedPrepTime;
  const _OrderSuccess({required this.orderId, required this.estimatedPrepTime});
}

// =============================================================================
// ENTRY POINT
// =============================================================================

class FoodCheckoutScreen extends StatelessWidget {
  const FoodCheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FoodCheckoutContent();
}

// =============================================================================
// MAIN CONTENT
// =============================================================================

class _FoodCheckoutContent extends StatefulWidget {
  const _FoodCheckoutContent();

  @override
  State<_FoodCheckoutContent> createState() => _FoodCheckoutContentState();
}

class _FoodCheckoutContentState extends State<_FoodCheckoutContent> {
  PaymentMethod _paymentMethod = PaymentMethod.payAtDoor;
  DeliveryType _deliveryType = DeliveryType.delivery;
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

  int _estimatedPrepTime(List<FoodCartItem> items) => items.fold(
      0, (m, i) => (i.preparationTime ?? 0) > m ? (i.preparationTime ?? 0) : m);

  // Reads foodAddress from UserProvider profileData
  FoodAddress? _getFoodAddress() {
    final profileData = context.read<UserProvider>().profileData;
    final raw = profileData?['foodAddress'];
    if (raw == null) return null;
    return FoodAddress.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  bool _isFormValid(List<FoodCartItem> items) {
    if (items.isEmpty) return false;
    if (_deliveryType == DeliveryType.delivery) {
      return _getFoodAddress() != null;
    }
    return true;
  }

  bool _validateForm() {
    if (_deliveryType == DeliveryType.delivery && _getFoodAddress() == null) {
      setState(
          () => _error = AppLocalizations.of(context)!.foodCheckoutNoAddress);
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  void _handleSubmit(FoodCartProvider cart) {
    if (_paymentMethod == PaymentMethod.payAtDoor) {
      _handlePayAtDoor(cart);
    } else {
      _handleCardPayment(cart);
    }
  }

  Map<String, dynamic>? _buildDeliveryAddressPayload(FoodAddress? addr) {
    if (_deliveryType != DeliveryType.delivery || addr == null) return null;
    return {
      'addressLine1': addr.addressLine1,
      'addressLine2': addr.addressLine2 ?? '',
      'city': addr.city,
      'mainRegion': addr.mainRegion,
      'phoneNumber': addr.phoneNumber ?? '',
      'location': addr.location != null
          ? {
              'latitude': addr.location!.latitude,
              'longitude': addr.location!.longitude
            }
          : null,
    };
  }

  Future<void> _handlePayAtDoor(FoodCartProvider cart) async {
    if (cart.currentRestaurant == null || _isSubmitting) return;
    if (!_validateForm()) return;

    final foodAddress = _getFoodAddress();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('processFoodOrder');

      final result = await fn.call({
        'restaurantId': cart.currentRestaurant!.id,
        'items': cart.items
            .map((i) => {
                  'foodId': i.originalFoodId,
                  'quantity': i.quantity,
                  'extras': i.extras
                      .map((e) => {'name': e.name, 'quantity': e.quantity})
                      .toList(),
                  'specialNotes': i.specialNotes ?? '',
                })
            .toList(),
        'paymentMethod': 'pay_at_door',
        'deliveryType':
            _deliveryType == DeliveryType.delivery ? 'delivery' : 'pickup',
        'deliveryAddress': _buildDeliveryAddressPayload(foodAddress),
        'buyerPhone': foodAddress?.phoneNumber ?? '',
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true) {
        await cart.clearCart();
        if (mounted) {
          setState(() => _orderSuccess = _OrderSuccess(
                orderId: data['orderId'] as String,
                estimatedPrepTime:
                    (data['estimatedPrepTime'] as num?)?.toInt() ??
                        _estimatedPrepTime(cart.items),
              ));
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted)
        setState(() => _error =
            e.message ?? AppLocalizations.of(context)!.foodCheckoutError);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCardPayment(FoodCartProvider cart) async {
    if (cart.currentRestaurant == null || _isSubmitting) return;
    if (!_validateForm()) return;

    final foodAddress = _getFoodAddress();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final orderNumber =
          'FOOD-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';

      final fn = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('initializeFoodPayment');

      final result = await fn.call({
        'restaurantId': cart.currentRestaurant!.id,
        'items': cart.items
            .map((i) => {
                  'foodId': i.originalFoodId,
                  'quantity': i.quantity,
                  'extras': i.extras
                      .map((e) => {'name': e.name, 'quantity': e.quantity})
                      .toList(),
                  'specialNotes': i.specialNotes ?? '',
                })
            .toList(),
        'deliveryType':
            _deliveryType == DeliveryType.delivery ? 'delivery' : 'pickup',
        'deliveryAddress': _buildDeliveryAddressPayload(foodAddress),
        'buyerPhone': foodAddress?.phoneNumber ?? '',
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
        'orderNumber': orderNumber,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true && data['gatewayUrl'] != null) {
        if (mounted) {
          context.push('/isbankfoodpayment', extra: {
            'gatewayUrl': data['gatewayUrl'],
            'orderNumber': orderNumber,
            'paymentParams': data['paymentParams'],
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Payment failed.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _randomSuffix() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final t = DateTime.now().microsecondsSinceEpoch;
    return List.generate(6, (i) => chars[(t >> i) % chars.length]).join();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc = AppLocalizations.of(context)!;

    return Consumer<FoodCartProvider>(
      builder: (context, cart, _) {
        if (_orderSuccess != null) {
          return _OrderSuccessScreen(
              orderId: _orderSuccess!.orderId,
              estimatedPrepTime: _orderSuccess!.estimatedPrepTime,
              isDark: isDark);
        }
        if (!cart.isInitialized) {
          return Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
            body: SafeArea(child: _FoodCheckoutSkeleton(isDark: isDark)),
          );
        }
        if (cart.items.isEmpty) return _EmptyCartScreen(isDark: isDark);

        final prepTime = _estimatedPrepTime(cart.items);
        final formValid = _isFormValid(cart.items);

        // Read foodAddress fresh on each build so it reacts to profile changes
        final foodAddress = _getFoodAddress();

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
          appBar: AppBar(
            backgroundColor:
                isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[700]),
              onPressed: () => context.pop(),
            ),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                children: [
                  Text(loc.foodCheckoutTitle,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900])),
                  const SizedBox(height: 20),

                  // Restaurant Info
                  if (cart.currentRestaurant != null) ...[
                    _RestaurantInfoRow(
                        restaurant: cart.currentRestaurant!,
                        prepTime: prepTime,
                        isDark: isDark),
                    const SizedBox(height: 12),
                  ],

                  // Your Order
                  _Section(
                    title: loc.foodCheckoutYourOrder,
                    isDark: isDark,
                    child: Column(
                        children: cart.items
                            .map((item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _CartItemRow(
                                      item: item, isDark: isDark, cart: cart),
                                ))
                            .toList()),
                  ),
                  const SizedBox(height: 12),

                  // Delivery Address — read-only from profile
                  if (_deliveryType == DeliveryType.delivery) ...[
                    _Section(
                      title: loc.foodCheckoutDeliveryAddress,
                      isDark: isDark,
                      child: _FoodAddressCard(
                          foodAddress: foodAddress, isDark: isDark),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Order Notes
                  _Section(
                    title: loc.foodCheckoutOrderNotes,
                    isDark: isDark,
                    child: TextField(
                      controller: _notesController,
                      maxLines: 2,
                      maxLength: 1000,
                      onChanged: (v) => setState(() => _orderNotes = v),
                      decoration: InputDecoration(
                        hintText: loc.foodCheckoutOrderNotesHint,
                        hintStyle: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                            fontSize: 13),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1A1D2E)
                            : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF2D2B3F)
                                    : const Color(0xFFD1D5DB))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF2D2B3F)
                                    : const Color(0xFFD1D5DB))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orange)),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Payment Method
                  _Section(
                    title: loc.foodCheckoutPaymentMethod,
                    isDark: isDark,
                    child: Column(children: [
                      _PaymentMethodButton(
                          method: PaymentMethod.payAtDoor,
                          isSelected: _paymentMethod == PaymentMethod.payAtDoor,
                          isDark: isDark,
                          onTap: () => setState(
                              () => _paymentMethod = PaymentMethod.payAtDoor)),
                      const SizedBox(height: 8),
                      _PaymentMethodButton(
                          method: PaymentMethod.card,
                          isSelected: _paymentMethod == PaymentMethod.card,
                          isDark: isDark,
                          onTap: () => setState(
                              () => _paymentMethod = PaymentMethod.card)),
                    ]),
                  ),
                ],
              ),

              // Sticky bottom bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _StickyBottomBar(
                  isDark: isDark,
                  error: _error,
                  subtotal: cart.totals.subtotal,
                  currency: cart.totals.currency,
                  itemCount: cart.totals.itemCount,
                  isFormValid: formValid,
                  isSubmitting: _isSubmitting,
                  paymentMethod: _paymentMethod,
                  onSubmit: () => _handleSubmit(cart),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// FOOD ADDRESS CARD  —  read-only display of profile foodAddress
// =============================================================================

class _FoodAddressCard extends StatelessWidget {
  final FoodAddress? foodAddress;
  final bool isDark;
  const _FoodAddressCard({required this.foodAddress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
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
                color: Colors.orange.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded,
                size: 16, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(addr.addressLine1,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900])),
                if (addr.addressLine2 != null && addr.addressLine2!.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(addr.addressLine2!,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[400]))),
                if (cityLine.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(cityLine,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[500]))),
                if (addr.phoneNumber != null && addr.phoneNumber!.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(addr.phoneNumber!,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[400]))),
              ])),
        ]),
      );
    }

    // No address set
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            style: BorderStyle.solid,
            color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[300]!,
            width: 1.5),
      ),
      child: Row(children: [
        Icon(Icons.location_on_outlined,
            size: 20, color: isDark ? Colors.grey[600] : Colors.grey[400]),
        const SizedBox(width: 12),
        Expanded(
            child: Text(loc.foodCheckoutNoAddressShort,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[500]))),
        GestureDetector(
          onTap: () => context.push('/food-address'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.orange, borderRadius: BorderRadius.circular(8)),
            child: Text(loc.foodCheckoutAddAddress,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// RESTAURANT INFO ROW
// =============================================================================

class _RestaurantInfoRow extends StatelessWidget {
  final FoodCartRestaurant restaurant;
  final int prepTime;
  final bool isDark;
  const _RestaurantInfoRow(
      {required this.restaurant, required this.prepTime, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF211F31)
            : Colors.orange[50]!.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                isDark ? Colors.white.withOpacity(0.08) : Colors.orange[100]!),
      ),
      child: Row(children: [
        if (restaurant.profileImageUrl != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(restaurant.profileImageUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          ),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(restaurant.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[900]),
              overflow: TextOverflow.ellipsis),
          if (prepTime > 0)
            Row(children: [
              Icon(Icons.access_time_rounded,
                  size: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600]),
              const SizedBox(width: 4),
              Text(loc.foodCheckoutPrepTime(prepTime),
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[500] : Colors.grey[700])),
            ]),
        ])),
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
  const _Section(
      {required this.title, required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : const Color(0xFFD1D5DB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: isDark ? Colors.grey[400] : Colors.grey[800])),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

// =============================================================================
// CART ITEM ROW
// =============================================================================

class _CartItemRow extends StatelessWidget {
  final FoodCartItem item;
  final bool isDark;
  final FoodCartProvider cart;
  const _CartItemRow(
      {required this.item, required this.isDark, required this.cart});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final extrasTotal =
        item.extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    final lineTotal = (item.price + extrasTotal) * item.quantity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D2E) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? const Color(0xFF2A2D3E) : const Color(0xFFD1D5DB)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                ? Image.network(item.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _NoImgBox(isDark: isDark))
                : _NoImgBox(isDark: isDark),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(item.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900]),
                    overflow: TextOverflow.ellipsis)),
            GestureDetector(
                onTap: () => cart.removeItem(item.foodId),
                child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[400]))),
          ]),
          Text(localizeFoodType(item.foodType, loc),
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[700])),
          if (item.extras.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: item.extras
                        .map((e) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.orange.withOpacity(0.15)
                                      : Colors.orange[50],
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(localizeExtra(e.name, loc),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.orange[400]
                                          : Colors.orange[600])),
                            ))
                        .toList())),
          if (item.specialNotes != null && item.specialNotes!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 11,
                      color: isDark ? Colors.grey[500] : Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(item.specialNotes!,
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[700]),
                          overflow: TextOverflow.ellipsis)),
                ])),
          const SizedBox(height: 8),
          Row(children: [
            _InlineQty(
                quantity: item.quantity,
                isDark: isDark,
                onDecrease: () =>
                    cart.updateQuantity(item.foodId, item.quantity - 1),
                onIncrease: () =>
                    cart.updateQuantity(item.foodId, item.quantity + 1)),
            const Spacer(),
            Text(loc.foodPriceTL(lineTotal.toStringAsFixed(0)),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.orange[400] : Colors.orange[600])),
          ]),
        ])),
      ]),
    );
  }
}

class _NoImgBox extends StatelessWidget {
  final bool isDark;
  const _NoImgBox({required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200],
            borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.shopping_bag_outlined,
            size: 24, color: Colors.grey[400]),
      );
}

class _InlineQty extends StatelessWidget {
  final int quantity;
  final bool isDark;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  const _InlineQty(
      {required this.quantity,
      required this.isDark,
      required this.onDecrease,
      required this.onIncrease});

  @override
  Widget build(BuildContext context) => Row(children: [
        _QtyBtn(icon: Icons.remove_rounded, isDark: isDark, onTap: onDecrease),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('$quantity',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900]))),
        _QtyBtn(icon: Icons.add_rounded, isDark: isDark, onTap: onIncrease),
      ]);
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _QtyBtn(
      {required this.icon, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF2D2B3F)
                      : const Color(0xFFD1D5DB))),
          child: Icon(icon,
              size: 12, color: isDark ? Colors.grey[400] : Colors.grey[500])));
}

// =============================================================================
// PAYMENT METHOD BUTTON
// =============================================================================

class _PaymentMethodButton extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected, isDark;
  final VoidCallback onTap;
  const _PaymentMethodButton(
      {required this.method,
      required this.isSelected,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isPay = method == PaymentMethod.payAtDoor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.orange.withOpacity(0.10) : Colors.orange[50])
              : (isDark ? Colors.transparent : const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.orange[400]!)
                  : (isDark
                      ? const Color(0xFF2D2B3F)
                      : const Color(0xFFD1D5DB))),
        ),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.withOpacity(0.2)
                      : (isDark ? const Color(0xFF2D2B3F) : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                  isPay ? Icons.payments_rounded : Icons.credit_card_rounded,
                  size: 20,
                  color: isSelected
                      ? Colors.orange
                      : (isDark ? Colors.grey[500] : Colors.grey[400]))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    isPay
                        ? loc.foodCheckoutPayAtDoor
                        : loc.foodCheckoutCreditCard,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? (isDark ? Colors.orange[400] : Colors.orange[700])
                            : (isDark ? Colors.grey[200] : Colors.grey[800]))),
                Text(
                    isPay
                        ? loc.foodCheckoutPayCash
                        : loc.foodCheckoutSecurePayment,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[700])),
              ])),
        ]),
      ),
    );
  }
}

// =============================================================================
// STICKY BOTTOM BAR
// =============================================================================

class _StickyBottomBar extends StatelessWidget {
  final bool isDark, isFormValid, isSubmitting;
  final String? error;
  final double subtotal;
  final String currency;
  final int itemCount;
  final PaymentMethod paymentMethod;
  final VoidCallback onSubmit;
  const _StickyBottomBar(
      {required this.isDark,
      required this.error,
      required this.subtotal,
      required this.currency,
      required this.itemCount,
      required this.isFormValid,
      required this.isSubmitting,
      required this.paymentMethod,
      required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final canSubmit = isFormValid && !isSubmitting;
    final isCard = paymentMethod == PaymentMethod.card;
    return Container(
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF1C1A29) : Colors.white.withOpacity(0.95),
        border: Border(
            top: BorderSide(
                color: isDark ? const Color(0xFF2D2B3F) : Colors.grey[200]!)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color:
                        isDark ? Colors.red.withOpacity(0.10) : Colors.red[50],
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.error_outline_rounded,
                      size: 16, color: Colors.red[400]),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(error!,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.red[400] : Colors.red[600]))),
                ]),
              )),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(loc.foodCheckoutTotalItems(itemCount),
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[700])),
            Text(loc.foodPriceTL(subtotal.toStringAsFixed(0)),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900])),
          ]),
          const Spacer(),
          ElevatedButton(
            onPressed: canSubmit ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
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
                        color: Colors.white, strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        isCard
                            ? Icons.credit_card_rounded
                            : Icons.shopping_bag_rounded,
                        size: 16),
                    const SizedBox(width: 8),
                    Text(
                        isCard
                            ? loc.foodCheckoutPayNow
                            : loc.foodCheckoutPlaceOrder,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
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
  final int estimatedPrepTime;
  final bool isDark;
  const _OrderSuccessScreen(
      {required this.orderId,
      required this.estimatedPrepTime,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      body: SafeArea(
          child: Center(
              child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey[200]!,
                  width: 2.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/images/foods/foodsuccess.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check_circle_rounded,
                            size: 40, color: Colors.green)))),
            const SizedBox(height: 16),
            Text(loc.foodCheckoutOrderPlaced,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900])),
            const SizedBox(height: 6),
            Text(loc.foodCheckoutOrderConfirmed,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[500]),
                textAlign: TextAlign.center),
            if (estimatedPrepTime > 0) ...[
              const SizedBox(height: 12),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.withOpacity(0.15)
                          : Colors.orange[50],
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.access_time_rounded,
                        size: 14,
                        color:
                            isDark ? Colors.orange[400] : Colors.orange[600]),
                    const SizedBox(width: 6),
                    Text(loc.foodCartPrepTimeApprox(estimatedPrepTime),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.orange[400]
                                : Colors.orange[600])),
                  ])),
            ],
            const SizedBox(height: 8),
            Text(
                loc.foodCheckoutOrderId(orderId
                    .substring(0, orderId.length.clamp(0, 8))
                    .toUpperCase()),
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[400])),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => context.go('/restaurants'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(loc.backToRestaurants,
                        style: const TextStyle(fontWeight: FontWeight.bold)))),
          ]),
        ),
      ))),
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
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      body: SafeArea(
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shopping_bag_outlined,
            size: 64, color: isDark ? Colors.grey[600] : Colors.grey[300]),
        const SizedBox(height: 16),
        Text(loc.foodCheckoutCartEmpty,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900])),
        const SizedBox(height: 6),
        Text(loc.foodCheckoutAddItems,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[500])),
        const SizedBox(height: 24),
        ElevatedButton(
            onPressed: () => context.go('/restaurants'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text(loc.foodCheckoutBrowse,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]))),
    );
  }
}

// =============================================================================
// FOOD CHECKOUT SKELETON
// =============================================================================

class _FoodCheckoutSkeleton extends StatelessWidget {
  final bool isDark;
  const _FoodCheckoutSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2D2B3F) : const Color(0xFFE5E7EB);
    final border = isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!;
    Widget box(double h, double? w) => Container(
        height: h,
        width: w,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)));
    Widget card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border)),
        child: child);

    return ListView(padding: const EdgeInsets.all(16), children: [
      box(14, 96),
      const SizedBox(height: 16),
      box(28, 120),
      const SizedBox(height: 20),
      // Restaurant row
      card(Row(children: [
        box(40, 40),
        const SizedBox(width: 12),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [box(14, 140), const SizedBox(height: 6), box(11, 100)])
      ])),
      // Order items
      card(Column(children: [
        box(11, 80),
        const SizedBox(height: 12),
        ...List.generate(
            2,
            (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF211F31) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      box(64, 64),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            box(14, null),
                            const SizedBox(height: 6),
                            box(11, 80),
                            const SizedBox(height: 8),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [box(28, 96), box(14, 56)])
                          ]))
                    ]))))
      ])),
      // Delivery method
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 120),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: box(48, null)),
          const SizedBox(width: 10),
          Expanded(child: box(48, null))
        ])
      ])),
      // Address card
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 140),
        const SizedBox(height: 12),
        box(64, null),
      ])),
      // Notes
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 100),
        const SizedBox(height: 12),
        box(56, null),
      ])),
      // Payment
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 120),
        const SizedBox(height: 12),
        box(64, null),
        const SizedBox(height: 8),
        box(64, null)
      ])),
    ]);
  }
}
