// test/services/testable_cart_validation_service.dart
//
// TESTABLE MIRROR of CartValidationService pure logic from lib/services/cart_validation_service.dart
//
// This file contains EXACT copies of pure logic functions from CartValidationService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/cart_validation_service.dart
//
// Last synced with: cart_validation_service.dart (current version)

/// Mirrors map conversion logic from CartValidationService
class TestableMapConverter {
  /// Mirrors _convertToStringMap from CartValidationService
  /// CRITICAL: Recursively convert Map<Object?, Object?> to Map<String, dynamic>
  static Map<String, dynamic> convertToStringMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.fromEntries(
        data.entries.map((entry) {
          final key = entry.key.toString();
          final value = convertValue(entry.value);
          return MapEntry(key, value);
        }),
      );
    }
    return {};
  }

  /// Mirrors _convertValue from CartValidationService
  /// Recursively convert nested values
  static dynamic convertValue(dynamic value) {
    if (value is Map) {
      return convertToStringMap(value);
    } else if (value is List) {
      return value.map((item) => convertValue(item)).toList();
    }
    return value;
  }
}

/// Mirrors cart item preparation logic from CartValidationService.validateCartCheckout
class TestableCartItemExtractor {
  /// Extract validation data from cart item
  /// Mirrors the itemsToValidate mapping in validateCartCheckout
  static Map<String, dynamic> extractForValidation(Map<String, dynamic> item) {
    final rawCartData = item['cartData'];
    final cartData = rawCartData is Map 
        ? Map<String, dynamic>.from(rawCartData) 
        : <String, dynamic>{};

    return {
      'productId': item['productId'],
      'quantity': item['quantity'] ?? 1,
      'selectedColor': cartData['selectedColor'],

      // Extract cached values (null if not present)
      'cachedPrice': cartData['cachedPrice'],
      'cachedBundlePrice': cartData['cachedBundlePrice'],
      'cachedDiscountPercentage': cartData['cachedDiscountPercentage'],
      'cachedDiscountThreshold': cartData['cachedDiscountThreshold'],
      'cachedBulkDiscountPercentage': cartData['cachedBulkDiscountPercentage'],
      'cachedMaxQuantity': cartData['cachedMaxQuantity'],
    };
  }

  /// Extract validation data from multiple cart items
  static List<Map<String, dynamic>> extractAllForValidation(
      List<Map<String, dynamic>> cartItems) {
    return cartItems.map(extractForValidation).toList();
  }

  /// Get list of required fields for validation
  static List<String> get requiredFields => [
        'productId',
        'quantity',
        'selectedColor',
      ];

  /// Get list of cached price fields
  static List<String> get cachedPriceFields => [
        'cachedPrice',
        'cachedBundlePrice',
        'cachedDiscountPercentage',
        'cachedDiscountThreshold',
        'cachedBulkDiscountPercentage',
        'cachedMaxQuantity',
      ];
}

/// Mirrors cache update payload building from CartValidationService.updateCartCache
class TestableCacheUpdateBuilder {
  /// Build update payload for a validated item
  /// Mirrors the updates mapping in updateCartCache
  static Map<String, dynamic> buildUpdatePayload(Map<String, dynamic> validatedItem) {
    final productId = validatedItem['productId']?.toString();
    final unitPrice = validatedItem['unitPrice'];
    final bundlePrice = validatedItem['bundlePrice'];
    final discountPercentage = validatedItem['discountPercentage'];
    final discountThreshold = validatedItem['discountThreshold'];
    final bulkDiscountPercentage = validatedItem['bulkDiscountPercentage'];
    final maxQuantity = validatedItem['maxQuantity'];

    return {
      'productId': productId,
      'updates': {
        // Cached values (for future validations)
        'cachedPrice': unitPrice,
        'cachedBundlePrice': bundlePrice,
        'cachedDiscountPercentage': discountPercentage,
        'cachedDiscountThreshold': discountThreshold,
        'cachedBulkDiscountPercentage': bulkDiscountPercentage,
        'cachedMaxQuantity': maxQuantity,

        // Denormalized fields (for quick access)
        'unitPrice': unitPrice,
        'bundlePrice': bundlePrice,
        'discountPercentage': discountPercentage,
        'discountThreshold': discountThreshold,
        'bulkDiscountPercentage': bulkDiscountPercentage,
        'maxQuantity': maxQuantity,
      },
    };
  }

  /// Build update payloads for multiple validated items
  static List<Map<String, dynamic>> buildAllUpdatePayloads(
      List<Map<String, dynamic>> validatedItems) {
    return validatedItems.map(buildUpdatePayload).toList();
  }
}

/// Mirrors error response handling from CartValidationService
class TestableValidationErrorHandler {
  /// Check if error code indicates rate limiting
  static bool isRateLimitError(String errorCode) {
    return errorCode == 'resource-exhausted';
  }

  /// Build rate limit error response
  /// Mirrors the rate limit handling in validateCartCheckout
  static Map<String, dynamic> buildRateLimitResponse() {
    return {
      'isValid': false,
      'errors': {
        '_system': {
          'key': 'rate_limit_exceeded',
          'params': {},
        }
      },
      'warnings': {},
      'validatedItems': [],
    };
  }

  /// Validate that a response has required fields
  static bool isValidResponse(Map<String, dynamic> response) {
    return response.containsKey('isValid') &&
        response.containsKey('errors') &&
        response.containsKey('warnings');
  }

  /// Extract error count from response
  static int getErrorCount(Map<String, dynamic> response) {
    final errors = response['errors'];
    if (errors is Map) {
      return errors.length;
    }
    return 0;
  }

  /// Extract warning count from response
  static int getWarningCount(Map<String, dynamic> response) {
    final warnings = response['warnings'];
    if (warnings is Map) {
      return warnings.length;
    }
    return 0;
  }

  /// Check if response indicates validation passed
  static bool isValidationPassed(Map<String, dynamic> response) {
    return response['isValid'] == true;
  }
}

/// Mirrors validation request building
class TestableValidationRequestBuilder {
  /// Build the full validation request payload
  static Map<String, dynamic> buildRequest({
    required List<Map<String, dynamic>> cartItems,
    bool reserveStock = false,
  }) {
    final itemsToValidate = TestableCartItemExtractor.extractAllForValidation(cartItems);

    return {
      'cartItems': itemsToValidate,
      'reserveStock': reserveStock,
    };
  }
}