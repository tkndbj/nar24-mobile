// lib/services/cart_validation_service.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class CartValidationService {
  static final CartValidationService _instance =
      CartValidationService._internal();
  factory CartValidationService() => _instance;
  CartValidationService._internal();

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  Future<Map<String, dynamic>> validateCartCheckout({
    required List<Map<String, dynamic>> cartItems,
    bool reserveStock = false,
  }) async {
    try {
      debugPrint(
          '🔍 Validating ${cartItems.length} items via Cloud Function...');

      // ✅ Prepare cart items for validation (include cached values)
      final itemsToValidate = cartItems.map((item) {
        final cartData = item['cartData'] as Map<String, dynamic>? ?? {};

        // ✅ SIMPLE: Just extract from cartData (always has these fields)
        return {
          'productId': item['productId'],
          'quantity': item['quantity'] ?? 1,
          'selectedColor': cartData['selectedColor'],

          // ✅ Extract cached values (null if not present)
          'cachedPrice': cartData['cachedPrice'],
          'cachedBundlePrice': cartData['cachedBundlePrice'],
          'cachedDiscountPercentage': cartData['cachedDiscountPercentage'],
          'cachedDiscountThreshold': cartData['cachedDiscountThreshold'],
          'cachedBulkDiscountPercentage':
              cartData['cachedBulkDiscountPercentage'],
          'cachedMaxQuantity': cartData['cachedMaxQuantity'],
        };
      }).toList();

      // Call Cloud Function
      final result =
          await _functions.httpsCallable('validateCartCheckout').call({
        'cartItems': itemsToValidate,
        'reserveStock': reserveStock,
      });

      // ✅ Safe type conversion
      final rawData = result.data;
      final data = _convertToStringMap(rawData);

      debugPrint('✅ Validation completed: isValid=${data['isValid']}, '
          'errors=${(data['errors'] as Map).length}, '
          'warnings=${(data['warnings'] as Map).length}');

      return data;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Validation function error: ${e.code} - ${e.message}');

      // Handle rate limiting
      if (e.code == 'resource-exhausted') {
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

      rethrow;
    } catch (e) {
      debugPrint('❌ Validation error: $e');
      rethrow;
    }
  }

  /// Update cart cache after validation (sync fresh data)
  Future<bool> updateCartCache({
    required String userId,
    required List<Map<String, dynamic>> validatedItems,
  }) async {
    try {
      debugPrint(
          '🔄 Updating cart cache for ${validatedItems.length} items...');

      final updates = validatedItems.map((item) {
        // ✅ FIX: Safe extraction with null handling
        final productId = item['productId']?.toString();
        final unitPrice = item['unitPrice'];
        final bundlePrice =
            item['bundlePrice']; // ✅ This is the NEW bundle price
        final discountPercentage = item['discountPercentage'];
        final discountThreshold = item['discountThreshold'];
        final bulkDiscountPercentage = item['bulkDiscountPercentage'];
        final maxQuantity = item['maxQuantity'];

        return {
          'productId': productId,
          'updates': {
            // ✅ Update cached values (for future validations)
            'cachedPrice': unitPrice,
            'cachedBundlePrice': bundlePrice, // ✅ NEW bundle price (if exists)
            'cachedDiscountPercentage': discountPercentage,
            'cachedDiscountThreshold': discountThreshold,
            'cachedBulkDiscountPercentage': bulkDiscountPercentage,
            'cachedMaxQuantity': maxQuantity,

            // ✅ Also update denormalized fields (for quick access)
            'unitPrice': unitPrice,
            'bundlePrice': bundlePrice,
            'discountPercentage': discountPercentage,
            'discountThreshold': discountThreshold,
            'bulkDiscountPercentage': bulkDiscountPercentage,
            'maxQuantity': maxQuantity,
          },
        };
      }).toList();

      final result = await _functions.httpsCallable('updateCartCache').call({
        'productUpdates': updates,
      });

      // ✅ Safe type conversion
      final rawData = result.data;
      final data = _convertToStringMap(rawData);

      debugPrint('✅ Cache updated: ${data['updated']} items');

      return data['success'] == true;
    } catch (e) {
      debugPrint('❌ Cache update error: $e');
      return false;
    }
  }

  /// ✅ CRITICAL: Recursively convert Map<Object?, Object?> to Map<String, dynamic>
  Map<String, dynamic> _convertToStringMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.fromEntries(
        data.entries.map((entry) {
          final key = entry.key.toString();
          final value = _convertValue(entry.value);
          return MapEntry(key, value);
        }),
      );
    }
    return {};
  }

  /// ✅ Recursively convert nested values
  dynamic _convertValue(dynamic value) {
    if (value is Map) {
      return _convertToStringMap(value);
    } else if (value is List) {
      return value.map((item) => _convertValue(item)).toList();
    }
    return value;
  }
}
