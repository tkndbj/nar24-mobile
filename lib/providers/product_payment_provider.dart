import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:collection/collection.dart';
import '../generated/l10n/app_localizations.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../screens/PAYMENT-RECEIPT/isbank_payment_screen.dart';
import '../models/coupon.dart';
import '../models/user_benefit.dart';
import '../services/coupon_service.dart';
import '../services/discount_selection_service.dart';

final FirebaseFunctions _functions =
    FirebaseFunctions.instanceFor(region: 'europe-west3');

class ProductPaymentProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Form Keys - ONLY ADDRESS
  final GlobalKey<FormState> addressFormKey = GlobalKey<FormState>();

  // Controllers - ONLY ADDRESS
  final TextEditingController addressLine1Controller = TextEditingController();
  final TextEditingController addressLine2Controller = TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController();

  Map<String, dynamic>? _deliverySettings;
  bool isLoadingDeliverySettings = true;

  // State Variables - Removed all payment/card state
  bool saveAddress = false;
  bool isProcessingPayment = false;
  bool hasAcceptedAgreement = false;
  String? selectedDeliveryOption = 'normal';
  List<Map<String, dynamic>> savedAddresses = [];
  String? selectedAddressId;
  String? selectedRegion;
  bool isAddressExpanded = true;
  final double cartCalculatedTotal;
  LatLng? selectedLocation;
  bool attemptedPayment = false;

  bool get isExpressAvailable => !useFreeShipping;

  final Coupon? appliedCoupon;
  final bool useFreeShipping;
  double couponDiscount = 0.0;
  UserBenefit? _usedFreeShippingBenefit;
  final String? selectedBenefitId;

  final List<Map<String, dynamic>> items;

  ProductPaymentProvider({
    required this.items,
    required this.cartCalculatedTotal,
    this.appliedCoupon, // Add this
    this.useFreeShipping = false, // Add this
    this.selectedBenefitId,
  }) {
    _calculateCouponDiscount(); // Add this
    _findFreeShippingBenefit(); // Add this
    if (useFreeShipping) {
      selectedDeliveryOption = 'normal';
    }
    fetchSavedAddresses();
    _fetchDeliverySettings();
  }

  void _calculateCouponDiscount() {
    if (appliedCoupon != null && appliedCoupon!.isValid) {
      couponDiscount = appliedCoupon!.amount > cartCalculatedTotal
          ? cartCalculatedTotal
          : appliedCoupon!.amount;
    } else {
      couponDiscount = 0.0;
    }
  }

  /// Find the free shipping benefit to use
  void _findFreeShippingBenefit() {
    if (useFreeShipping) {
      // ✅ Use the specific benefit ID if provided, otherwise fall back to first available
      if (selectedBenefitId != null) {
        _usedFreeShippingBenefit = CouponService()
            .benefitsNotifier
            .value
            .where((b) => b.id == selectedBenefitId && b.isValid)
            .firstOrNull;
      }
      // Fallback to first available if specific one not found
      _usedFreeShippingBenefit ??= CouponService().availableFreeShipping;
    }
  }

  /// Get the effective delivery price (0 if free shipping benefit is used)
  double getEffectiveDeliveryPrice() {
    if (useFreeShipping && _usedFreeShippingBenefit != null) {
      return 0.0;
    }
    return getDeliveryPrice();
  }

  /// Calculate the final total after all discounts
  double get finalTotal {
    final subtotalAfterCoupon = cartCalculatedTotal - couponDiscount;
    final shipping = getEffectiveDeliveryPrice();
    return subtotalAfterCoupon + shipping;
  }

  /// Fetch delivery settings from Firestore
  Future<void> _fetchDeliverySettings() async {
    try {
      isLoadingDeliverySettings = true;
      notifyListeners();

      final docSnap =
          await _firestore.collection('settings').doc('delivery').get();

      if (docSnap.exists && docSnap.data() != null) {
        _deliverySettings = docSnap.data();
      }
    } catch (e) {
      debugPrint('Error fetching delivery settings: $e');
    } finally {
      isLoadingDeliverySettings = false;
      notifyListeners();
    }
  }

// Getters for UI
  double get normalPrice =>
      (_deliverySettings?['normal']?['price'] ?? 150.0).toDouble();
  double get normalFreeThreshold =>
      (_deliverySettings?['normal']?['freeThreshold'] ?? 2000.0).toDouble();
  double get expressPrice =>
      (_deliverySettings?['express']?['price'] ?? 350.0).toDouble();
  double get expressFreeThreshold =>
      (_deliverySettings?['express']?['freeThreshold'] ?? 10000.0).toDouble();
  String get normalEstimatedDays =>
      _deliverySettings?['normal']?['estimatedDays'] ?? '3-5';
  String get expressEstimatedDays =>
      _deliverySettings?['express']?['estimatedDays'] ?? '1-2';

  void setRegion(String region) {
    selectedRegion = region;
    notifyListeners();
  }

  // Dispose controllers - Only address controllers
  void disposeControllers() {
    addressLine1Controller.dispose();
    addressLine2Controller.dispose();
    phoneNumberController.dispose();
  }

  void setDeliveryOption(String? option) {
    // Prevent express selection when free shipping is active
    if (useFreeShipping && option == 'express') {
      return;
    }
    selectedDeliveryOption = option;
    notifyListeners();
  }

  void setAgreementAccepted(bool value) {
    hasAcceptedAgreement = value;
    notifyListeners();
  }

  double getDeliveryPrice() {
    switch (selectedDeliveryOption) {
      case 'normal':
        return cartCalculatedTotal >= normalFreeThreshold ? 0.0 : normalPrice;
      case 'express':
        return cartCalculatedTotal >= expressFreeThreshold ? 0.0 : expressPrice;
      default:
        return 0.0;
    }
  }

  double get totalPrice => cartCalculatedTotal;

  // Fetch Saved Addresses
  Future<void> fetchSavedAddresses() async {
    User? user = _auth.currentUser;
    if (user != null) {
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('addresses')
          .get();

      savedAddresses = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'addressLine1': data['addressLine1'] ?? '',
          'addressLine2': data['addressLine2'] ?? '',
          'city': data['city'] ?? '',
          'phoneNumber': data['phoneNumber'] ?? '',
          'location': data['location'],
        };
      }).toList();

      notifyListeners();
    }
  }

  // Handle Address Selection
  void onAddressSelected(String? addressId) {
    selectedAddressId = addressId;
    if (addressId != null) {
      Map<String, dynamic>? selectedAddress = savedAddresses
          .firstWhereOrNull((address) => address['id'] == addressId);
      if (selectedAddress != null) {
        addressLine1Controller.text = selectedAddress['addressLine1'];
        addressLine2Controller.text = selectedAddress['addressLine2'];
        selectedRegion = selectedAddress['city'];
        phoneNumberController.text = selectedAddress['phoneNumber'];
        selectedLocation = selectedAddress['location'] != null
            ? LatLng(
                selectedAddress['location'].latitude,
                selectedAddress['location'].longitude,
              )
            : null;
      }
    } else {
      addressLine1Controller.clear();
      addressLine2Controller.clear();
      phoneNumberController.clear();
      selectedLocation = null;
      selectedRegion = null;
    }
    notifyListeners();
  }

  // Remove Address
  Future<void> removeAddress(String addressId) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('addresses')
          .doc(addressId)
          .delete();
      await fetchSavedAddresses();
      if (selectedAddressId == addressId) {
        onAddressSelected(null);
      }
    }
  }

  // Toggle Address Expansion
  void toggleAddressExpansion() {
    isAddressExpanded = !isAddressExpanded;
    notifyListeners();
  }

  // Set Selected Location
  void setSelectedLocation(LatLng location) {
    selectedLocation = location;
    notifyListeners();
  }

  Future<bool> confirmPayment(BuildContext context) async {
    // Mark that user attempted payment (for showing validation feedback)
    attemptedPayment = true;
    notifyListeners();

    User? user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).pleaseLogin)),
      );
      return false;
    }

    // Validate address
    bool isAddressValid = addressFormKey.currentState?.validate() ?? false;
    if (!isAddressValid) {
      return false;
    }

    if (selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pinLocationRequired),
        ),
      );
      return false;
    }

    isProcessingPayment = true;
    notifyListeners();

    String? orderNumber;

    try {
      // ✅ Prepare items payload - extract ONLY from selectedAttributes
      final itemsPayload = items.map((item) {
        final p = item['product'] as Product;
        final Map<String, dynamic> payload = {
          'productId': p.id,
          'quantity': item['quantity'] as int,
        };

        // ✅ Extract dynamic attributes from selectedAttributes map
        if (item.containsKey('selectedAttributes') &&
            item['selectedAttributes'] is Map<String, dynamic>) {
          final attrs = item['selectedAttributes'] as Map<String, dynamic>;

          attrs.forEach((key, value) {
            if (value != null && value != '' && value != []) {
              payload[key] = value;
            }
          });
        }

        return payload;
      }).toList();

      // Prepare address payload
      // Normalize phone: "(5XX) XXX XX XX" -> "05XXXXXXXXX"
      final normalizedPhone =
          '0${phoneNumberController.text.replaceAll(RegExp(r'\D'), '')}';
      final addressPayload = {
        'addressLine1': addressLine1Controller.text,
        'addressLine2': addressLine2Controller.text,
        'city': selectedRegion,
        'phoneNumber': normalizedPhone,
        'location': {
          'latitude': selectedLocation!.latitude,
          'longitude': selectedLocation!.longitude,
        },
      };

      orderNumber = 'ORDER-${DateTime.now().millisecondsSinceEpoch}';

      // Get user info
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final customerName =
          userData?['displayName'] ?? userData?['name'] ?? 'Customer';
      final customerEmail = user.email ?? '';

      // Prepare cart data
      final cartData = {
        'items': itemsPayload,
        'cartCalculatedTotal': cartCalculatedTotal,
        'deliveryOption': selectedDeliveryOption ?? 'normal',
        'deliveryPrice':
            getEffectiveDeliveryPrice(), // Changed from getDeliveryPrice()
        'address': addressPayload,
        'paymentMethod': 'Card',
        'saveAddress': saveAddress,
        'couponId': appliedCoupon?.id,
        'freeShippingBenefitId':
            useFreeShipping ? _usedFreeShippingBenefit?.id : null,
        'clientDeliveryPrice': getDeliveryPrice(),
      };

      // Initialize İşbank payment
      final HttpsCallable initPayment =
          _functions.httpsCallable('initializeIsbankPayment');
      final initResponse = await initPayment.call({
        'amount':
            finalTotal, // Server will recalculate — this is for logging/comparison only
        'orderNumber': orderNumber,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': phoneNumberController.text,
        'cartData': cartData,
      });

      final initData = initResponse.data as Map<String, dynamic>;

      if (initData['success'] != true) {
        throw Exception('Payment initialization failed');
      }

      isProcessingPayment = false;
      notifyListeners();

      if (!context.mounted) return false;

      final paymentResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IsbankPaymentScreen(
            gatewayUrl: initData['gatewayUrl'],
            paymentParams: Map<String, dynamic>.from(initData['paymentParams']),
            orderNumber: orderNumber ?? '',
          ),
        ),
      );

      if (paymentResult == true) {
        if (!context.mounted) return false;

        await DiscountSelectionService().clearAllSelections();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ödeme başarılı! Siparişiniz oluşturuldu.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        return true;
      } else {
        return false;
      }
    } catch (e) {
      isProcessingPayment = false;
      notifyListeners();

      if (e is FirebaseFunctionsException) {
        String errorMessage = 'Ödeme sırasında bir hata oluştu.';

        if (e.message != null) {
          errorMessage = e.message!;
        } else if (e.code == 'unauthenticated') {
          errorMessage = 'Lütfen giriş yapın.';
        } else if (e.code == 'invalid-argument') {
          errorMessage = 'Geçersiz bilgi. Lütfen kontrol edin.';
        } else if (e.code == 'failed-precondition') {
          final msg = e.message ?? '';

          // ✅ ADD: Clear invalid coupon/benefit from local storage
          final discountService = DiscountSelectionService();

          if (msg.contains('Coupon has already been used') ||
              msg.contains('Coupon has expired') ||
              msg.contains('Coupon not found')) {
            errorMessage = msg.contains('already been used')
                ? AppLocalizations.of(context).couponAlreadyUsed
                : msg.contains('expired')
                    ? AppLocalizations.of(context).couponExpired
                    : AppLocalizations.of(context).couponNotFound;
            // Clear the invalid coupon selection
            discountService.selectCoupon(null);
          } else if (msg.contains('Free shipping has already been used') ||
              msg.contains('Free shipping benefit has expired')) {
            errorMessage = msg.contains('already been used')
                ? AppLocalizations.of(context).freeShippingAlreadyUsed
                : AppLocalizations.of(context).freeShippingExpired;
            // Clear the invalid free shipping selection
            discountService.setFreeShipping(false);
          } else {
            errorMessage = e.message ?? AppLocalizations.of(context).stockIssue;
          }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      // Log error to Firestore (fire-and-forget, non-blocking)
      _logClientError(
        userId: user?.uid,
        context: 'confirmPayment',
        error: e.toString(),
        orderNumber:
            orderNumber, // ← Now captures the real one (or null if it failed before that line)
      );
      return false;
    }
  }

  void _logClientError({
    String? userId,
    required String context,
    required String error,
    String? orderNumber,
  }) {
    try {
      _firestore.collection('_client_errors').add({
        'userId': userId,
        'context': context,
        'error': error,
        'orderNumber': orderNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silent — logging should never break the app
    }
  }

  @override
  void dispose() {
    disposeControllers();
    super.dispose();
  }
}
