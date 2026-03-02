// lib/screens/food/food_checkout_screen.dart
//
// Mirrors: app/food-checkout/page.tsx + FoodCheckoutContent

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../user_provider.dart';
import '../../constants/region.dart';
import '../../providers/food_cart_provider.dart';

// =============================================================================
// TYPES  —  mirrors TypeScript interfaces
// =============================================================================

enum PaymentMethod { payAtDoor, card }

enum DeliveryType { delivery, pickup }

class DeliveryAddress {
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String phoneNumber;
  final LatLng? location;

  const DeliveryAddress({
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.phoneNumber = '',
    this.location,
  });

  DeliveryAddress copyWith({
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? phoneNumber,
    LatLng? location,
    bool clearLocation = false,
  }) =>
      DeliveryAddress(
        addressLine1: addressLine1 ?? this.addressLine1,
        addressLine2: addressLine2 ?? this.addressLine2,
        city: city ?? this.city,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        location: clearLocation ? null : (location ?? this.location),
      );
}

class SavedAddress {
  final String id;
  final String addressLine1;
  final String addressLine2;
  final String phoneNumber;
  final String city;
  final LatLng? location;

  const SavedAddress({
    required this.id,
    required this.addressLine1,
    required this.addressLine2,
    required this.phoneNumber,
    required this.city,
    this.location,
  });

  factory SavedAddress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    LatLng? loc;
    final l = d['location'] as Map<String, dynamic>?;
    if (l != null) {
      loc = LatLng(
        (l['latitude'] as num).toDouble(),
        (l['longitude'] as num).toDouble(),
      );
    }
    return SavedAddress(
      id: doc.id,
      addressLine1: (d['addressLine1'] as String?) ?? '',
      addressLine2: (d['addressLine2'] as String?) ?? '',
      phoneNumber: (d['phoneNumber'] as String?) ?? '',
      city: (d['city'] as String?) ?? '',
      location: loc,
    );
  }
}

class _OrderSuccess {
  final String orderId;
  final int estimatedPrepTime;
  const _OrderSuccess({required this.orderId, required this.estimatedPrepTime});
}

// =============================================================================
// PHONE UTILITIES  —  mirrors formatPhoneNumber / isValidPhoneNumber / normalizePhone
// =============================================================================

String _formatPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
  final buf = StringBuffer();
  for (int i = 0; i < limited.length; i++) {
    if (i == 0) buf.write('(');
    buf.write(limited[i]);
    if (i == 2) buf.write(') ');
    if (i == 5) buf.write(' ');
    if (i == 7) buf.write(' ');
  }
  return buf.toString();
}

String _formatPhoneForDisplay(String phone) {
  if (phone.isEmpty) return '';
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final d = digits.startsWith('0') ? digits.substring(1) : digits;
  if (d.length != 10) return phone;
  return '(${d.substring(0, 3)}) ${d.substring(3, 6)} ${d.substring(6, 8)} ${d.substring(8, 10)}';
}

bool _isValidPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length == 10 && digits.startsWith('5');
}

String _normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('0') ? digits : '0$digits';
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
  DeliveryAddress _address = const DeliveryAddress();
  String _orderNotes = '';
  bool _saveAddress = false;

  List<SavedAddress> _savedAddresses = [];
  String? _selectedAddressId;

  bool _showMapModal = false;
  bool _showCityDropdown = false;

  final Map<String, String> _errors = {};
  bool _isSubmitting = false;
  String? _error;
  _OrderSuccess? _orderSuccess;

  final _addr1Controller = TextEditingController();
  final _addr2Controller = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _addr1Controller.dispose();
    _addr2Controller.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _estimatedPrepTime(List<FoodCartItem> items) => items.fold(
      0, (m, i) => (i.preparationTime ?? 0) > m ? (i.preparationTime ?? 0) : m);

  bool _isFormValid(List<FoodCartItem> items) {
    if (items.isEmpty) return false;
    if (_deliveryType == DeliveryType.delivery) {
      return _address.addressLine1.trim().isNotEmpty &&
          _address.phoneNumber.trim().isNotEmpty &&
          _isValidPhone(_address.phoneNumber) &&
          _address.city.trim().isNotEmpty &&
          _address.location != null;
    }
    return true;
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final uid = context.read<UserProvider>().user?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .get();
      if (mounted) {
        setState(() {
          _savedAddresses = snap.docs
              .map((d) => SavedAddress.fromDoc(
                  d as DocumentSnapshot<Map<String, dynamic>>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[FoodCheckout] Load addresses error: $e');
    }
  }

  void _handleAddressSelect(String? addressId) {
    setState(() {
      _selectedAddressId = addressId;
      _errors.clear();
      if (addressId != null) {
        final saved = _savedAddresses.firstWhere((a) => a.id == addressId);
        _address = DeliveryAddress(
          addressLine1: saved.addressLine1,
          addressLine2: saved.addressLine2,
          city: saved.city,
          phoneNumber: _formatPhoneForDisplay(saved.phoneNumber),
          location: saved.location,
        );
      } else {
        _address = const DeliveryAddress();
      }
      _addr1Controller.text = _address.addressLine1;
      _addr2Controller.text = _address.addressLine2;
      _phoneController.text = _address.phoneNumber;
    });
  }

  void _handlePhoneChange(String value) {
    final formatted = _formatPhone(value);
    setState(() {
      _address = _address.copyWith(phoneNumber: formatted);
      _errors.remove('phoneNumber');
    });
  }

  bool _validateForm() {
    final newErrors = <String, String>{};
    if (_deliveryType == DeliveryType.delivery) {
      if (_address.addressLine1.trim().isEmpty)
        newErrors['addressLine1'] = 'This field is required';
      if (_address.phoneNumber.trim().isEmpty) {
        newErrors['phoneNumber'] = 'This field is required';
      } else if (!_isValidPhone(_address.phoneNumber)) {
        newErrors['phoneNumber'] = 'Invalid phone number';
      }
      if (_address.city.trim().isEmpty)
        newErrors['city'] = 'This field is required';
      if (_address.location == null)
        newErrors['location'] = 'Please pin your location';
    } else {
      if (_address.phoneNumber.trim().isNotEmpty &&
          !_isValidPhone(_address.phoneNumber)) {
        newErrors['phoneNumber'] = 'Invalid phone number';
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(newErrors);
    });
    return newErrors.isEmpty;
  }

  void _handleSubmit(FoodCartProvider cart) {
    if (_paymentMethod == PaymentMethod.payAtDoor) {
      _handlePayAtDoor(cart);
    } else {
      _handleCardPayment(cart);
    }
  }

  Future<void> _handlePayAtDoor(FoodCartProvider cart) async {
    if (cart.currentRestaurant == null || _isSubmitting) return;
    if (!_validateForm()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final normalizedPhone = _address.phoneNumber.isNotEmpty
          ? _normalizePhone(_address.phoneNumber)
          : '';
      final fn = FirebaseFunctions.instance.httpsCallable('processFoodOrder');
      final result = await fn.call({
        'restaurantId': cart.currentRestaurant!.id,
        'items': cart.items
            .map((i) => {
                  'foodId': i.originalFoodId,
                  'quantity': i.quantity,
                  'extras': i.extras
                      .map((e) => {
                            'name': e.name,
                            'quantity': e.quantity,
                            'price': e.price
                          })
                      .toList(),
                  'specialNotes': i.specialNotes ?? '',
                })
            .toList(),
        'paymentMethod': 'pay_at_door',
        'deliveryType':
            _deliveryType == DeliveryType.delivery ? 'delivery' : 'pickup',
        'deliveryAddress': _deliveryType == DeliveryType.delivery
            ? {
                'addressLine1': _address.addressLine1,
                'addressLine2': _address.addressLine2,
                'city': _address.city,
                'phoneNumber': normalizedPhone,
                'location': _address.location != null
                    ? {
                        'latitude': _address.location!.latitude,
                        'longitude': _address.location!.longitude
                      }
                    : null,
              }
            : null,
        'buyerPhone': normalizedPhone,
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
      });
      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true) {
        if (_saveAddress &&
            _deliveryType == DeliveryType.delivery &&
            _selectedAddressId == null) {
          await _saveNewAddress(normalizedPhone);
        }
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
      if (mounted) setState(() => _error = e.message ?? 'An error occurred.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCardPayment(FoodCartProvider cart) async {
    if (cart.currentRestaurant == null || _isSubmitting) return;
    if (!_validateForm()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final orderNumber =
          'FOOD-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';
      final normalizedPhone = _address.phoneNumber.isNotEmpty
          ? _normalizePhone(_address.phoneNumber)
          : '';
      final fn =
          FirebaseFunctions.instance.httpsCallable('initializeFoodPayment');
      final result = await fn.call({
        'restaurantId': cart.currentRestaurant!.id,
        'items': cart.items
            .map((i) => {
                  'foodId': i.originalFoodId,
                  'quantity': i.quantity,
                  'extras': i.extras
                      .map((e) => {
                            'name': e.name,
                            'quantity': e.quantity,
                            'price': e.price
                          })
                      .toList(),
                  'specialNotes': i.specialNotes ?? '',
                })
            .toList(),
        'deliveryType':
            _deliveryType == DeliveryType.delivery ? 'delivery' : 'pickup',
        'deliveryAddress': _deliveryType == DeliveryType.delivery
            ? {
                'addressLine1': _address.addressLine1,
                'addressLine2': _address.addressLine2,
                'city': _address.city,
                'phoneNumber': normalizedPhone,
                'location': _address.location != null
                    ? {
                        'latitude': _address.location!.latitude,
                        'longitude': _address.location!.longitude
                      }
                    : null,
              }
            : null,
        'buyerPhone': normalizedPhone,
        'orderNotes': _orderNotes,
        'clientSubtotal': cart.totals.subtotal,
        'orderNumber': orderNumber,
      });
      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true && data['gatewayUrl'] != null) {
        if (_saveAddress &&
            _deliveryType == DeliveryType.delivery &&
            _selectedAddressId == null) {
          await _saveNewAddress(normalizedPhone);
        }
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

  Future<void> _saveNewAddress(String normalizedPhone) async {
    final uid = context.read<UserProvider>().user?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .doc()
          .set({
        'addressLine1': _address.addressLine1,
        'addressLine2': _address.addressLine2,
        'city': _address.city,
        'phoneNumber': normalizedPhone,
        'location': _address.location != null
            ? {
                'latitude': _address.location!.latitude,
                'longitude': _address.location!.longitude
              }
            : null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FoodCheckout] Save address error: $e');
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
                isDark ? const Color(0xFF030712) : const Color(0xFFF9FAFB),
            body: SafeArea(child: _FoodCheckoutSkeleton(isDark: isDark)),
          );
        }
        if (cart.items.isEmpty) return _EmptyCartScreen(isDark: isDark);

        final prepTime = _estimatedPrepTime(cart.items);
        final formValid = _isFormValid(cart.items);

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF030712) : const Color(0xFFF9FAFB),
          body: Stack(
            children: [
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                  children: [
                    // Back link
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.chevron_left_rounded,
                            size: 18,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[500]),
                        Text('Back to Menu',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500])),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    Text('Checkout',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.grey[900])),
                    const SizedBox(height: 20),

                    if (cart.currentRestaurant != null) ...[
                      _RestaurantInfoRow(
                          restaurant: cart.currentRestaurant!,
                          prepTime: prepTime,
                          isDark: isDark),
                      const SizedBox(height: 12),
                    ],

                    // Your Order
                    _Section(
                      title: 'YOUR ORDER',
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

                    // Delivery method
                    _Section(
                      title: 'DELIVERY METHOD',
                      isDark: isDark,
                      child: Row(
                          children: DeliveryType.values
                              .map((type) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                          right: type == DeliveryType.delivery
                                              ? 6
                                              : 0,
                                          left: type == DeliveryType.pickup
                                              ? 6
                                              : 0),
                                      child: _DeliveryTypeButton(
                                          type: type,
                                          isSelected: _deliveryType == type,
                                          isDark: isDark,
                                          onTap: () => setState(() {
                                                _deliveryType = type;
                                                _errors.clear();
                                              })),
                                    ),
                                  ))
                              .toList()),
                    ),
                    const SizedBox(height: 12),

                    // Delivery address
                    if (_deliveryType == DeliveryType.delivery) ...[
                      _Section(
                        title: 'DELIVERY ADDRESS',
                        isDark: isDark,
                        child: _AddressForm(
                          address: _address,
                          savedAddresses: _savedAddresses,
                          selectedAddressId: _selectedAddressId,
                          errors: _errors,
                          isDark: isDark,
                          saveAddress: _saveAddress,
                          showCityDropdown: _showCityDropdown,
                          addr1Controller: _addr1Controller,
                          addr2Controller: _addr2Controller,
                          phoneController: _phoneController,
                          onAddressSelect: _handleAddressSelect,
                          onAddr1Changed: (v) => setState(() {
                            _address = _address.copyWith(addressLine1: v);
                            _errors.remove('addressLine1');
                          }),
                          onAddr2Changed: (v) => setState(() =>
                              _address = _address.copyWith(addressLine2: v)),
                          onPhoneChanged: _handlePhoneChange,
                          onCitySelected: (city) => setState(() {
                            _address = _address.copyWith(city: city);
                            _showCityDropdown = false;
                            _errors.remove('city');
                          }),
                          onCityDropdownToggle: () => setState(
                              () => _showCityDropdown = !_showCityDropdown),
                          onOpenMap: () => setState(() => _showMapModal = true),
                          onSaveAddressToggle: (v) =>
                              setState(() => _saveAddress = v),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Phone for pickup
                    if (_deliveryType == DeliveryType.pickup) ...[
                      _Section(
                        title: 'CONTACT INFO',
                        isDark: isDark,
                        child: _PhoneField(
                            controller: _phoneController,
                            isDark: isDark,
                            error: _errors['phoneNumber'],
                            onChanged: _handlePhoneChange),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Order notes
                    _Section(
                      title: 'ORDER NOTES',
                      isDark: isDark,
                      child: TextField(
                        controller: _notesController,
                        maxLines: 2,
                        maxLength: 1000,
                        onChanged: (v) => setState(() => _orderNotes = v),
                        decoration: InputDecoration(
                          hintText: 'E.g. no spicy sauce, extra napkins…',
                          hintStyle: TextStyle(
                              color:
                                  isDark ? Colors.grey[600] : Colors.grey[400],
                              fontSize: 13),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1F2937)
                              : Colors.grey[50],
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Colors.orange)),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Payment method
                    _Section(
                      title: 'PAYMENT METHOD',
                      isDark: isDark,
                      child: Column(children: [
                        _PaymentMethodButton(
                            method: PaymentMethod.payAtDoor,
                            isSelected:
                                _paymentMethod == PaymentMethod.payAtDoor,
                            isDark: isDark,
                            onTap: () => setState(() =>
                                _paymentMethod = PaymentMethod.payAtDoor)),
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

              // Map modal
              if (_showMapModal)
                _LocationPickerModal(
                  isDark: isDark,
                  initialLocation: _address.location,
                  onClose: () => setState(() => _showMapModal = false),
                  onLocationSelect: (loc) => setState(() {
                    _address = _address.copyWith(location: loc);
                    _showMapModal = false;
                    _errors.remove('location');
                  }),
                ),
            ],
          ),
        );
      },
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[800]!.withOpacity(0.6)
            : Colors.orange[50]!.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.grey[700]!.withOpacity(0.4)
                : Colors.orange[100]!),
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
                  color: isDark ? Colors.grey[500] : Colors.grey[400]),
              const SizedBox(width: 4),
              Text('~$prepTime min prep time',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[500] : Colors.grey[400])),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.grey[700]!.withOpacity(0.4)
                : Colors.grey[200]!),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: isDark ? Colors.grey[400] : Colors.grey[500])),
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
    final extrasTotal =
        item.extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    final lineTotal = (item.price + extrasTotal) * item.quantity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]!.withOpacity(0.6) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image
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
          Text(item.foodType,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[400])),
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
                              child: Text(e.name,
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
                      color: isDark ? Colors.grey[500] : Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(item.specialNotes!,
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[400]),
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
            Text('${lineTotal.toStringAsFixed(0)} TL',
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
            color: isDark ? Colors.grey[700] : Colors.grey[200],
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
                      ? const Color(0xFF374151)
                      : const Color(0xFFE5E7EB))),
          child: Icon(icon,
              size: 12, color: isDark ? Colors.grey[400] : Colors.grey[500])));
}

// =============================================================================
// DELIVERY TYPE BUTTON
// =============================================================================

class _DeliveryTypeButton extends StatelessWidget {
  final DeliveryType type;
  final bool isSelected, isDark;
  final VoidCallback onTap;
  const _DeliveryTypeButton(
      {required this.type,
      required this.isSelected,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDelivery = type == DeliveryType.delivery;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.orange.withOpacity(0.10) : Colors.orange[50])
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.orange[400]!)
                  : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
        ),
        child: Row(children: [
          Icon(
              isDelivery
                  ? Icons.location_on_rounded
                  : Icons.shopping_bag_rounded,
              size: 18,
              color: isSelected
                  ? Colors.orange
                  : (isDark ? Colors.grey[500] : Colors.grey[400])),
          const SizedBox(width: 8),
          Text(isDelivery ? 'Delivery' : 'Pickup',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.orange[400] : Colors.orange[700])
                      : (isDark ? Colors.grey[300] : Colors.grey[700]))),
        ]),
      ),
    );
  }
}

// =============================================================================
// ADDRESS FORM
// =============================================================================

class _AddressForm extends StatelessWidget {
  final DeliveryAddress address;
  final List<SavedAddress> savedAddresses;
  final String? selectedAddressId;
  final Map<String, String> errors;
  final bool isDark, saveAddress, showCityDropdown;
  final TextEditingController addr1Controller, addr2Controller, phoneController;
  final ValueChanged<String?> onAddressSelect;
  final ValueChanged<String> onAddr1Changed,
      onAddr2Changed,
      onPhoneChanged,
      onCitySelected;
  final VoidCallback onCityDropdownToggle, onOpenMap;
  final ValueChanged<bool> onSaveAddressToggle;

  const _AddressForm({
    required this.address,
    required this.savedAddresses,
    required this.selectedAddressId,
    required this.errors,
    required this.isDark,
    required this.saveAddress,
    required this.showCityDropdown,
    required this.addr1Controller,
    required this.addr2Controller,
    required this.phoneController,
    required this.onAddressSelect,
    required this.onAddr1Changed,
    required this.onAddr2Changed,
    required this.onPhoneChanged,
    required this.onCitySelected,
    required this.onCityDropdownToggle,
    required this.onOpenMap,
    required this.onSaveAddressToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Saved address tiles
      if (savedAddresses.isNotEmpty) ...[
        Row(children: [
          Icon(Icons.star_rounded,
              size: 13, color: isDark ? Colors.grey[400] : Colors.grey[500]),
          const SizedBox(width: 6),
          Text('Saved Addresses',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[500])),
        ]),
        const SizedBox(height: 8),
        ...savedAddresses.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SavedAddressTile(
                saved: s,
                isSelected: selectedAddressId == s.id,
                isDark: isDark,
                onTap: () => onAddressSelect(s.id)))),
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SavedAddressTile(
                saved: null,
                isSelected: selectedAddressId == null,
                isDark: isDark,
                onTap: () => onAddressSelect(null))),
      ],

      _FormLabel('Address Line 1 *', isDark),
      _FormField(
          controller: addr1Controller,
          isDark: isDark,
          hint: 'Street, neighbourhood…',
          icon: Icons.home_rounded,
          error: errors['addressLine1'],
          onChanged: onAddr1Changed),
      const SizedBox(height: 10),

      _FormLabel('Address Line 2', isDark),
      _FormField(
          controller: addr2Controller,
          isDark: isDark,
          hint: 'Apt, floor, building…',
          icon: Icons.apartment_rounded,
          onChanged: onAddr2Changed),
      const SizedBox(height: 10),

      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _FormLabel('City *', isDark),
          const SizedBox(height: 4),
          _CityDropdown(
              city: address.city,
              isDark: isDark,
              showDropdown: showCityDropdown,
              error: errors['city'],
              onToggle: onCityDropdownToggle,
              onSelect: onCitySelected),
        ])),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _FormLabel('Phone *', isDark),
          _PhoneField(
              controller: phoneController,
              isDark: isDark,
              error: errors['phoneNumber'],
              onChanged: onPhoneChanged),
        ])),
      ]),
      const SizedBox(height: 10),

      // Location picker
      _FormLabel('Precise Location *', isDark),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: onOpenMap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: errors['location'] != null
                    ? Colors.red
                    : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
            color: isDark ? const Color(0xFF1F2937) : Colors.grey[50],
          ),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: address.location != null
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(
                    address.location != null
                        ? Icons.check_circle_rounded
                        : Icons.map_rounded,
                    size: 20,
                    color: address.location != null
                        ? Colors.green
                        : Colors.orange)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      address.location != null
                          ? 'Location pinned'
                          : 'Pin your exact location',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.grey[900])),
                  Text(
                      address.location != null
                          ? '${address.location!.latitude.toStringAsFixed(4)}, ${address.location!.longitude.toStringAsFixed(4)}'
                          : 'Helps us find you precisely',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[400])),
                ])),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: isDark ? Colors.grey[500] : Colors.grey[400]),
          ]),
        ),
      ),
      if (errors['location'] != null) _ErrorText(errors['location']!),
      const SizedBox(height: 10),

      // Save checkbox
      if (selectedAddressId == null)
        Row(children: [
          Checkbox(
              value: saveAddress,
              onChanged: (v) => onSaveAddressToggle(v!),
              activeColor: Colors.orange,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          Text('Save this address for future orders',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[500])),
        ]),
    ]);
  }
}

class _SavedAddressTile extends StatelessWidget {
  final SavedAddress? saved;
  final bool isSelected, isDark;
  final VoidCallback onTap;
  const _SavedAddressTile(
      {required this.saved,
      required this.isSelected,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.orange.withOpacity(0.10) : Colors.orange[50])
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.orange[400]!)
                  : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: Colors.orange,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          const SizedBox(width: 6),
          if (saved == null)
            Text('Enter new address',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[900]))
          else
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(saved!.addressLine1,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.grey[900]),
                      overflow: TextOverflow.ellipsis),
                  if (saved!.addressLine2.isNotEmpty || saved!.city.isNotEmpty)
                    Text(
                        [saved!.addressLine2, saved!.city]
                            .where((s) => s.isNotEmpty)
                            .join(', '),
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[400])),
                  if (saved!.phoneNumber.isNotEmpty)
                    Text(saved!.phoneNumber,
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[400])),
                  if (saved!.location != null)
                    Row(children: [
                      Icon(Icons.location_on_rounded,
                          size: 10,
                          color: isDark ? Colors.grey[600] : Colors.grey[300]),
                      const SizedBox(width: 2),
                      Text(
                          '${saved!.location!.latitude.toStringAsFixed(4)}, ${saved!.location!.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.grey[600]
                                  : Colors.grey[300])),
                    ]),
                ])),
        ]),
      ),
    );
  }
}

class _CityDropdown extends StatelessWidget {
  final String city;
  final bool isDark, showDropdown;
  final String? error;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelect;
  const _CityDropdown(
      {required this.city,
      required this.isDark,
      required this.showDropdown,
      required this.onToggle,
      required this.onSelect,
      this.error});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: error != null
                    ? Colors.red
                    : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
          ),
          child: Row(children: [
            Expanded(
                child: Text(city.isNotEmpty ? city : 'Select city',
                    style: TextStyle(
                        fontSize: 13,
                        color: city.isNotEmpty
                            ? (isDark ? Colors.white : Colors.grey[900])
                            : (isDark ? Colors.grey[600] : Colors.grey[400])))),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: isDark ? Colors.grey[500] : Colors.grey[400]),
          ]),
        ),
      ),
      if (showDropdown)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? const Color(0xFF374151) : Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: ListView.builder(
              shrinkWrap: true,
              itemCount: allRegionsList.length,
              itemBuilder: (_, i) => InkWell(
                  onTap: () => onSelect(allRegionsList[i]),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(allRegionsList[i],
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white : Colors.grey[900]))))),
        ),
      if (error != null) _ErrorText(error!),
    ]);
  }
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String? error;
  final ValueChanged<String> onChanged;
  const _PhoneField(
      {required this.controller,
      required this.isDark,
      required this.onChanged,
      this.error});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: error != null
                  ? Colors.red
                  : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
        ),
        child: Row(children: [
          Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(Icons.phone_rounded,
                  size: 16,
                  color: isDark ? Colors.grey[500] : Colors.grey[400])),
          Expanded(
              child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  onChanged: onChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-]'))
                  ],
                  decoration: InputDecoration(
                      hintText: '(5__) ___ __ __',
                      hintStyle: TextStyle(
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                          fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10)),
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.grey[900]))),
        ]),
      ),
      Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Turkish format: 5XX XXX XX XX',
              style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey[600] : Colors.grey[400]))),
      if (error != null) _ErrorText(error!),
    ]);
  }
}

class _FormLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _FormLabel(this.text, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[500] : Colors.grey[400])));
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String hint;
  final IconData icon;
  final String? error;
  final ValueChanged<String> onChanged;
  const _FormField(
      {required this.controller,
      required this.isDark,
      required this.hint,
      required this.icon,
      required this.onChanged,
      this.error});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: error != null
                  ? Colors.red
                  : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
        ),
        child: Row(children: [
          Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(icon,
                  size: 16,
                  color: isDark ? Colors.grey[500] : Colors.grey[400])),
          Expanded(
              child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                          fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10)),
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.grey[900]))),
        ]),
      ),
      if (error != null) _ErrorText(error!),
    ]);
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        const Icon(Icons.close_rounded, size: 11, color: Colors.red),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.red)),
      ]));
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
    final isPay = method == PaymentMethod.payAtDoor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.orange.withOpacity(0.10) : Colors.orange[50])
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.orange[400]!)
                  : (isDark ? const Color(0xFF374151) : Colors.grey[200]!)),
        ),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.withOpacity(0.2)
                      : (isDark ? const Color(0xFF1F2937) : Colors.grey[100]),
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
                Text(isPay ? 'Pay at Door' : 'Credit / Debit Card',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? (isDark ? Colors.orange[400] : Colors.orange[700])
                            : (isDark ? Colors.grey[200] : Colors.grey[800]))),
                Text(
                    isPay
                        ? 'Pay with cash when your order arrives'
                        : 'Secure online payment via İşbank 3D',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[400])),
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
    final canSubmit = isFormValid && !isSubmitting;
    final isCard = paymentMethod == PaymentMethod.card;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[900]!.withOpacity(0.95)
            : Colors.white.withOpacity(0.95),
        border: Border(
            top: BorderSide(
                color: isDark ? const Color(0xFF1F2937) : Colors.grey[200]!)),
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
            Text('Total ($itemCount item${itemCount == 1 ? '' : 's'})',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[400])),
            Text('${subtotal.toStringAsFixed(0)} $currency',
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
                  isDark ? Colors.grey[700] : Colors.grey[300],
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
                    Text(isCard ? 'Pay Now' : 'Place Order',
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
// LOCATION PICKER MODAL  —  mirrors LocationPickerModal using google_maps_flutter
// =============================================================================

class _LocationPickerModal extends StatefulWidget {
  final bool isDark;
  final LatLng? initialLocation;
  final VoidCallback onClose;
  final ValueChanged<LatLng> onLocationSelect;
  const _LocationPickerModal(
      {required this.isDark,
      required this.onClose,
      required this.onLocationSelect,
      this.initialLocation});

  @override
  State<_LocationPickerModal> createState() => _LocationPickerModalState();
}

class _LocationPickerModalState extends State<_LocationPickerModal> {
  LatLng? _selected;
  GoogleMapController? _mapController;
  static const _defaultCenter = LatLng(35.1855, 33.3823);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isDark
                          ? Colors.grey[700]!.withOpacity(0.5)
                          : Colors.grey[200]!)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Select Location',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.grey[900])),
                            Text('Tap anywhere on the map',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600])),
                          ])),
                      IconButton(
                          onPressed: widget.onClose,
                          icon: Icon(Icons.close_rounded,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600])),
                    ])),
                // Map
                ClipRRect(
                    child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.45,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                              target: _selected ?? _defaultCenter,
                              zoom: _selected != null ? 15 : 10),
                          onMapCreated: (c) => _mapController = c,
                          onTap: (ll) => setState(() => _selected = ll),
                          markers: _selected != null
                              ? {
                                  Marker(
                                      markerId: const MarkerId('sel'),
                                      position: _selected!)
                                }
                              : {},
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ))),
                // Selected coords
                if (_selected != null)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: isDark
                          ? Colors.grey[800]!.withOpacity(0.8)
                          : Colors.grey[50],
                      child: Row(children: [
                        Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.check_circle_rounded,
                                size: 16, color: Colors.green)),
                        const SizedBox(width: 10),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Location selected',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.grey[900])),
                              Text(
                                  '${_selected!.latitude.toStringAsFixed(6)}, ${_selected!.longitude.toStringAsFixed(6)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600])),
                            ]),
                      ])),
                // Footer
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: widget.onClose,
                              style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(
                                      color: isDark
                                          ? Colors.grey[600]!
                                          : Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              child: Text('Cancel',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700])))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: ElevatedButton(
                              onPressed: _selected != null
                                  ? () => widget.onLocationSelect(_selected!)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              child: const Text('Confirm Location',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)))),
                    ])),
              ]),
            )),
      ),
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
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF030712) : const Color(0xFFF9FAFB),
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
                      ? Colors.grey[700]!.withOpacity(0.4)
                      : Colors.grey[200]!)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded,
                    size: 32, color: Colors.green)),
            const SizedBox(height: 16),
            Text('Order Placed!',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900])),
            const SizedBox(height: 6),
            Text('Your order has been confirmed.',
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
                    Text('~$estimatedPrepTime min',
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
                'Order: ${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[400])),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => context.go('/food-orders'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('View My Orders',
                        style: TextStyle(fontWeight: FontWeight.bold)))),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                    onPressed: () => context.go('/restaurants'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                            color:
                                isDark ? Colors.grey[600]! : Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text('Back to Restaurants',
                        style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w500)))),
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
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF030712) : const Color(0xFFF9FAFB),
      body: SafeArea(
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shopping_bag_outlined,
            size: 64, color: isDark ? Colors.grey[600] : Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Your cart is empty',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900])),
        const SizedBox(height: 6),
        Text('Add items from a restaurant to checkout',
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
            child: const Text('Browse Restaurants',
                style: TextStyle(fontWeight: FontWeight.w600))),
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
    final bg = isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
    final border =
        isDark ? Colors.grey[700]!.withOpacity(0.4) : Colors.grey[200]!;
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
      card(Row(children: [
        box(40, 40),
        const SizedBox(width: 12),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [box(14, 140), const SizedBox(height: 6), box(11, 100)])
      ])),
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
                        color: isDark
                            ? Colors.grey[800]!.withOpacity(0.6)
                            : Colors.grey[50],
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
                                children: [box(28, 96), box(14, 56)]),
                          ]))
                    ]))))
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 120),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: box(48, null)),
          const SizedBox(width: 10),
          Expanded(child: box(48, null))
        ])
      ])),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        box(11, 140),
        const SizedBox(height: 12),
        box(44, null),
        const SizedBox(height: 10),
        box(44, null),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: box(44, null)),
          const SizedBox(width: 10),
          Expanded(child: box(44, null))
        ])
      ])),
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
