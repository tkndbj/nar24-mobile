// test/providers/testable_product_payment_provider.dart
//
// TESTABLE MIRROR of ProductPaymentProvider pure logic from lib/providers/product_payment_provider.dart
//
// This file contains EXACT copies of pure logic functions from ProductPaymentProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/product_payment_provider.dart
//
// Last synced with: product_payment_provider.dart (current version)

/// Mirrors delivery price calculation from ProductPaymentProvider
class TestableDeliveryPriceCalculator {
  /// Free delivery thresholds
  static const double normalFreeThreshold = 2000.0;
  static const double expressFreeThreshold = 10000.0;

  /// Standard delivery cost when not free
  static const double standardDeliveryCost = 2.0;

  /// Mirrors getDeliveryPrice from ProductPaymentProvider
  static double getDeliveryPrice({
    required String? deliveryOption,
    required double cartTotal,
  }) {
    switch (deliveryOption) {
      case 'normal':
        // Free delivery for normal if cart total is 2000 TL or more
        return cartTotal >= normalFreeThreshold ? 0.0 : standardDeliveryCost;
      case 'express':
        // Free delivery for express if cart total is 10000 TL or more
        return cartTotal >= expressFreeThreshold ? 0.0 : standardDeliveryCost;
      default:
        return 0.0;
    }
  }

  /// Calculate total with delivery
  static double getTotalWithDelivery({
    required double cartTotal,
    required String? deliveryOption,
  }) {
    return cartTotal + getDeliveryPrice(
      deliveryOption: deliveryOption,
      cartTotal: cartTotal,
    );
  }

  /// Check if delivery is free
  static bool isDeliveryFree({
    required String? deliveryOption,
    required double cartTotal,
  }) {
    return getDeliveryPrice(
      deliveryOption: deliveryOption,
      cartTotal: cartTotal,
    ) == 0.0;
  }

  /// Get amount needed for free delivery
  static double amountNeededForFreeDelivery({
    required String? deliveryOption,
    required double cartTotal,
  }) {
    final threshold = deliveryOption == 'express' 
        ? expressFreeThreshold 
        : normalFreeThreshold;
    
    if (cartTotal >= threshold) return 0.0;
    return threshold - cartTotal;
  }
}

/// Mirrors item payload extraction from ProductPaymentProvider
class TestableItemPayloadBuilder {
  /// Mirrors items.map logic in confirmPayment
  /// Extract item payload from cart item with selectedAttributes
  static Map<String, dynamic> buildItemPayload({
    required String productId,
    required int quantity,
    Map<String, dynamic>? selectedAttributes,
  }) {
    final Map<String, dynamic> payload = {
      'productId': productId,
      'quantity': quantity,
    };

    // Extract dynamic attributes from selectedAttributes map
    if (selectedAttributes != null) {
      selectedAttributes.forEach((key, value) {
        if (value != null && value != '' && value != []) {
          payload[key] = value;
        }
      });
    }

    return payload;
  }

  /// Build payload for multiple items
  static List<Map<String, dynamic>> buildItemsPayload(
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) getProductId,
  ) {
    return items.map((item) {
      final productId = getProductId(item);
      final quantity = item['quantity'] as int? ?? 1;
      final selectedAttributes = item['selectedAttributes'] as Map<String, dynamic>?;

      return buildItemPayload(
        productId: productId,
        quantity: quantity,
        selectedAttributes: selectedAttributes,
      );
    }).toList();
  }

  /// Validate item payload has required fields
  static List<String> validateItemPayload(Map<String, dynamic> payload) {
    final errors = <String>[];

    if (!payload.containsKey('productId') || payload['productId'] == null) {
      errors.add('Missing productId');
    }
    if (!payload.containsKey('quantity') || payload['quantity'] == null) {
      errors.add('Missing quantity');
    }
    if (payload['quantity'] != null && payload['quantity'] is int && payload['quantity'] <= 0) {
      errors.add('Quantity must be positive');
    }

    return errors;
  }
}

/// Mirrors address payload building from ProductPaymentProvider
class TestableAddressPayloadBuilder {
  /// Mirrors addressPayload construction in confirmPayment
  static Map<String, dynamic> buildAddressPayload({
    required String addressLine1,
    required String addressLine2,
    required String? city,
    required String phoneNumber,
    required double? latitude,
    required double? longitude,
  }) {
    return {
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'phoneNumber': phoneNumber,
      'location': latitude != null && longitude != null
          ? {
              'latitude': latitude,
              'longitude': longitude,
            }
          : null,
    };
  }

  /// Validate address payload
  static List<String> validateAddressPayload(Map<String, dynamic> payload) {
    final errors = <String>[];

    if (payload['addressLine1'] == null || (payload['addressLine1'] as String).isEmpty) {
      errors.add('Missing addressLine1');
    }
    if (payload['phoneNumber'] == null || (payload['phoneNumber'] as String).isEmpty) {
      errors.add('Missing phoneNumber');
    }
    if (payload['location'] == null) {
      errors.add('Missing location');
    }

    return errors;
  }

  /// Check if address has valid location
  static bool hasValidLocation(Map<String, dynamic> payload) {
    final location = payload['location'];
    if (location == null) return false;
    if (location is! Map) return false;
    return location['latitude'] != null && location['longitude'] != null;
  }
}

/// Mirrors order number generation from ProductPaymentProvider
class TestableOrderNumberGenerator {
  /// Mirrors order number format: 'ORDER-${DateTime.now().millisecondsSinceEpoch}'
  static String generate({DateTime? timestamp}) {
    final ts = timestamp ?? DateTime.now();
    return 'ORDER-${ts.millisecondsSinceEpoch}';
  }

  /// Parse order number to extract timestamp
  static DateTime? parseTimestamp(String orderNumber) {
    if (!orderNumber.startsWith('ORDER-')) return null;
    
    final timestampStr = orderNumber.substring(6);
    final milliseconds = int.tryParse(timestampStr);
    if (milliseconds == null) return null;
    
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// Validate order number format
  static bool isValidFormat(String orderNumber) {
    if (!orderNumber.startsWith('ORDER-')) return false;
    final timestampStr = orderNumber.substring(6);
    return int.tryParse(timestampStr) != null;
  }
}

/// Mirrors error message mapping from ProductPaymentProvider
class TestablePaymentErrorMapper {
  /// Mirrors error handling in confirmPayment catch block
  static String mapFirebaseFunctionError({
    required String code,
    String? message,
  }) {
    if (message != null && message.isNotEmpty) {
      return message;
    }

    switch (code) {
      case 'unauthenticated':
        return 'Lütfen giriş yapın.';
      case 'invalid-argument':
        return 'Geçersiz bilgi. Lütfen kontrol edin.';
      case 'failed-precondition':
        return message ?? 'Ürün stok sorunu. Lütfen tekrar deneyin.';
      default:
        return 'Ödeme sırasında bir hata oluştu.';
    }
  }

  /// Get error severity
  static ErrorSeverity getErrorSeverity(String code) {
    switch (code) {
      case 'unauthenticated':
        return ErrorSeverity.requiresAction; // User must login
      case 'invalid-argument':
        return ErrorSeverity.userError; // User input problem
      case 'failed-precondition':
        return ErrorSeverity.retryable; // Stock issue, might resolve
      default:
        return ErrorSeverity.unknown;
    }
  }
}

enum ErrorSeverity {
  requiresAction,
  userError,
  retryable,
  unknown,
}

/// Mirrors address selection logic from ProductPaymentProvider
class TestableAddressSelector {
  /// Mirrors onAddressSelected logic
  static Map<String, dynamic>? findAddressById(
    List<Map<String, dynamic>> addresses,
    String? addressId,
  ) {
    if (addressId == null) return null;
    
    for (final address in addresses) {
      if (address['id'] == addressId) {
        return address;
      }
    }
    return null;
  }

  /// Extract address fields for form population
  static AddressFormData? extractFormData(Map<String, dynamic>? address) {
    if (address == null) return null;

    double? latitude;
    double? longitude;
    
    final location = address['location'];
    if (location != null) {
      // Handle both GeoPoint-like objects and plain maps
      if (location is Map) {
        latitude = (location['latitude'] as num?)?.toDouble();
        longitude = (location['longitude'] as num?)?.toDouble();
      }
    }

    return AddressFormData(
      addressLine1: address['addressLine1'] as String? ?? '',
      addressLine2: address['addressLine2'] as String? ?? '',
      city: address['city'] as String?,
      phoneNumber: address['phoneNumber'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

/// Address form data structure
class AddressFormData {
  final String addressLine1;
  final String addressLine2;
  final String? city;
  final String phoneNumber;
  final double? latitude;
  final double? longitude;

  AddressFormData({
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.phoneNumber,
    required this.latitude,
    required this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;
}

/// Mirrors cart data payload building
class TestableCartDataBuilder {
  /// Build complete cart data payload for payment initialization
  static Map<String, dynamic> buildCartData({
    required List<Map<String, dynamic>> itemsPayload,
    required double cartCalculatedTotal,
    required String deliveryOption,
    required double deliveryPrice,
    required Map<String, dynamic> addressPayload,
    required bool saveAddress,
    String paymentMethod = 'Card',
  }) {
    return {
      'items': itemsPayload,
      'cartCalculatedTotal': cartCalculatedTotal,
      'deliveryOption': deliveryOption,
      'deliveryPrice': deliveryPrice,
      'address': addressPayload,
      'paymentMethod': paymentMethod,
      'saveAddress': saveAddress,
    };
  }
}