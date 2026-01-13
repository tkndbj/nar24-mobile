// test/providers/testable_cart_provider.dart
//
// TESTABLE MIRROR of cart_provider.dart and favorite_product_provider.dart
//
// This file contains EXACT copies of private functions from both providers
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with the source files
// When you update the providers, update the corresponding functions here.
//
// Last synced with: 
//   - cart_provider.dart v4.0
//   - favorite_product_provider.dart v2.0

import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// CIRCUIT BREAKER - Exact copy from favorite_product_provider.dart line 38-62
// ============================================================================
/// Mirrors `_CircuitBreaker` from favorite_product_provider.dart
class TestableCircuitBreaker {
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  final int threshold;
  final Duration resetDuration;

  TestableCircuitBreaker({
    this.threshold = 5,
    this.resetDuration = const Duration(minutes: 1),
  });

  bool get isOpen {
    if (_failureCount >= threshold) {
      if (_lastFailureTime != null &&
          DateTime.now().difference(_lastFailureTime!) > resetDuration) {
        _failureCount = 0;
        return false;
      }
      return true;
    }
    return false;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
  }

  void recordSuccess() {
    _failureCount = 0;
  }

  // Test helpers
  int get failureCount => _failureCount;
  DateTime? get lastFailureTime => _lastFailureTime;
  
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
  }
}

// ============================================================================
// RATE LIMITER - Exact copy from cart_provider.dart line 14-32
// ============================================================================
/// Mirrors `_RateLimiter` from cart_provider.dart
class TestableRateLimiter {
  final Map<String, DateTime> _lastOperations = {};
  final Duration cooldown;

  TestableRateLimiter(this.cooldown);

  bool canProceed(String operationKey) {
    final lastTime = _lastOperations[operationKey];
    if (lastTime == null) {
      _lastOperations[operationKey] = DateTime.now();
      return true;
    }

    final elapsed = DateTime.now().difference(lastTime);
    if (elapsed >= cooldown) {
      _lastOperations[operationKey] = DateTime.now();
      return true;
    }
    return false;
  }

  // Additional helpers for testing
  void reset(String operationKey) {
    _lastOperations.remove(operationKey);
  }

  void resetAll() {
    _lastOperations.clear();
  }

  int get activeOperationsCount => _lastOperations.length;
}

// ============================================================================
// CART TOTALS MODELS - Exact copy from cart_provider.dart line 1057-1122
// ============================================================================
/// Mirrors `CartTotals` from cart_provider.dart
class TestableCartTotals {
  final double total;
  final List<TestableCartItemTotal> items;
  final String currency;

  TestableCartTotals({
    required this.total,
    required this.items,
    required this.currency,
  });

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'currency': currency,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  /// Mirrors `CartTotals.fromJson` - exact logic from cart_provider.dart
  factory TestableCartTotals.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List? ?? [];
    final parsedItems = <TestableCartItemTotal>[];

    for (final item in itemsList) {
      try {
        Map<String, dynamic> itemMap;
        if (item is Map<String, dynamic>) {
          itemMap = item;
        } else if (item is Map) {
          itemMap = Map<String, dynamic>.from(item);
        } else {
          continue;
        }

        parsedItems.add(TestableCartItemTotal.fromJson(itemMap));
      } catch (e) {
        // Skip malformed items (matches production behavior)
      }
    }

    return TestableCartTotals(
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'TL',
      items: parsedItems,
    );
  }
}

/// Mirrors `CartItemTotal` from cart_provider.dart
class TestableCartItemTotal {
  final String productId;
  final double unitPrice;
  final double total;
  final int quantity;
  final bool isBundleItem;

  TestableCartItemTotal({
    required this.productId,
    required this.unitPrice,
    required this.total,
    required this.quantity,
    this.isBundleItem = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'unitPrice': unitPrice,
      'total': total,
      'quantity': quantity,
      'isBundleItem': isBundleItem,
    };
  }

  factory TestableCartItemTotal.fromJson(Map<String, dynamic> json) {
    return TestableCartItemTotal(
      productId: json['productId'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      quantity: (json['quantity'] as num? ?? 1).toInt(),
      isBundleItem: json['isBundleItem'] as bool? ?? false,
    );
  }
}

// ============================================================================
// DATA TRANSFORMER - Extracts helper functions from _buildProductFromCartData
// Mirrors logic from cart_provider.dart lines 862-1010
// ============================================================================
/// Contains all the safe extraction helpers used in `_buildProductFromCartData`
class TestableCartDataTransformer {
  final Map<String, dynamic> cartData;

  TestableCartDataTransformer(this.cartData);

  /// Mirrors `_safeGet<T>` nested function from _buildProductFromCartData
  /// Exact copy from cart_provider.dart lines 863-882
  T safeGet<T>(String key, T defaultValue) {
    final value = cartData[key];
    if (value == null) return defaultValue;

    if (T == double) {
      if (value is num) return value.toDouble() as T;
      if (value is String) {
        return (double.tryParse(value) ?? defaultValue as double) as T;
      }
    }
    if (T == int) {
      if (value is num) return value.toInt() as T;
      if (value is String) {
        return (int.tryParse(value) ?? defaultValue as int) as T;
      }
    }
    if (T == String) return value.toString() as T;
    if (T == bool) {
      if (value is bool) return value as T;
      return (value.toString().toLowerCase() == 'true') as T;
    }

    return value as T;
  }

  /// Mirrors `_safeBundleData` nested function
  /// Exact copy from cart_provider.dart lines 884-901
  List<Map<String, dynamic>>? safeBundleData(String key) {
    final value = cartData[key];
    if (value == null) return null;
    if (value is! List) return null;

    try {
      return value.map((item) {
        if (item is Map<String, dynamic>) {
          return item;
        } else if (item is Map) {
          return Map<String, dynamic>.from(item);
        }
        return <String, dynamic>{};
      }).toList();
    } catch (e) {
      return null;
    }
  }

  /// Mirrors `_safeStringList` nested function
  /// Exact copy from cart_provider.dart lines 903-909
  List<String> safeStringList(String key) {
    final value = cartData[key];
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  /// Mirrors `_safeColorImages` nested function
  /// Exact copy from cart_provider.dart lines 911-924
  Map<String, List<String>> safeColorImages(String key) {
    final value = cartData[key];
    if (value is! Map) return {};

    final result = <String, List<String>>{};
    value.forEach((k, v) {
      if (v is List) {
        result[k.toString()] = v.map((e) => e.toString()).toList();
      } else if (v is String && v.isNotEmpty) {
        result[k.toString()] = [v];
      }
    });
    return result;
  }

  /// Mirrors `_safeColorQuantities` nested function
  /// Exact copy from cart_provider.dart lines 926-939
  Map<String, int> safeColorQuantities(String key) {
    final value = cartData[key];
    if (value is! Map) return {};

    final result = <String, int>{};
    value.forEach((k, v) {
      if (v is num) {
        result[k.toString()] = v.toInt();
      } else if (v is String) {
        result[k.toString()] = int.tryParse(v) ?? 0;
      }
    });
    return result;
  }

  /// Mirrors `_safeTimestamp` nested function
  /// Exact copy from cart_provider.dart lines 941-952
  Timestamp safeTimestamp(String key) {
    final value = cartData[key];
    if (value is Timestamp) return value;
    if (value is int) return Timestamp.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        return Timestamp.fromDate(DateTime.parse(value));
      } catch (_) {}
    }
    return Timestamp.now();
  }
}

// ============================================================================
// FIELD VALIDATOR - Mirrors _hasRequiredFields
// Exact copy from cart_provider.dart lines 273-293
// ============================================================================
/// Mirrors `_hasRequiredFields` from cart_provider.dart
class TestableFieldValidator {
  /// Exact copy of _hasRequiredFields logic
  static bool hasRequiredFields(Map<String, dynamic> cartData) {
    final required = [
      'productId',
      'productName',
      'unitPrice',
      'availableStock',
      'sellerName',
      'sellerId'
    ];
    for (final field in required) {
      if (!cartData.containsKey(field) || cartData[field] == null) return false;
    }

    final productName = cartData['productName'] as String?;
    if (productName == null ||
        productName.isEmpty ||
        productName == 'Unknown Product') return false;

    final sellerName = cartData['sellerName'] as String?;
    if (sellerName == null || sellerName.isEmpty || sellerName == 'Unknown') {
      return false;
    }

    return true;
  }
}

// ============================================================================
// OPTIMISTIC UPDATE MANAGER - Mirrors optimistic update logic
// Based on cart_provider.dart lines 62-67, 224-268, 550-590, 620-660
// ============================================================================
/// Mirrors the optimistic update state management from CartProvider
class TestableOptimisticUpdateManager {
  final Map<String, Map<String, dynamic>> cache = {};
  final Map<String, DateTime> timestamps = {};
  final Duration timeout;

  TestableOptimisticUpdateManager({
    this.timeout = const Duration(seconds: 3),
  });

  /// Mirrors `_applyOptimisticAdd` partial logic (state management only)
  void applyAdd(String productId, Map<String, dynamic> productData, int quantity) {
    cache[productId] = {
      ...productData,
      'quantity': quantity,
      '_optimistic': true,
    };
    timestamps[productId] = DateTime.now();
  }

  /// Mirrors `_applyOptimisticRemove` logic
  void applyRemove(String productId) {
    cache[productId] = {'_deleted': true};
    timestamps[productId] = DateTime.now();
  }

  /// Mirrors `_clearOptimisticUpdate` logic
  void clear(String productId) {
    cache.remove(productId);
    timestamps.remove(productId);
  }

  /// Mirrors `_rollbackOptimisticUpdate` partial logic (state management only)
  void rollback(String productId) {
    cache.remove(productId);
    timestamps.remove(productId);
  }

  void clearAll() {
    cache.clear();
    timestamps.clear();
  }

  bool isOptimistic(String productId) => cache.containsKey(productId);
  bool isDeleted(String productId) => cache[productId]?['_deleted'] == true;

  /// Mirrors `_updateCartIds` effective IDs computation
  /// Exact logic from cart_provider.dart lines 224-236
  Set<String> computeEffectiveIds(Set<String> serverIds) {
    final effectiveIds = Set<String>.from(serverIds);
    for (final entry in cache.entries) {
      if (entry.value['_deleted'] == true) {
        effectiveIds.remove(entry.key);
      } else {
        effectiveIds.add(entry.key);
      }
    }
    return effectiveIds;
  }

  /// Returns expired updates based on timeout
  List<String> getExpiredUpdates() {
    final now = DateTime.now();
    final expired = <String>[];

    timestamps.forEach((productId, timestamp) {
      if (now.difference(timestamp) >= timeout) {
        expired.add(productId);
      }
    });

    return expired;
  }
}

// ============================================================================
// DEEP CONVERT UTILITIES - Mirrors _deepConvertMap and _deepConvertList
// Exact copy from cart_provider.dart lines 756-782
// ============================================================================
/// Mirrors deep conversion utilities from CartProvider
class TestableDeepConverter {
  /// Mirrors `_deepConvertMap` from cart_provider.dart
  static Map<String, dynamic> deepConvertMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (key == null) return;

      final stringKey = key.toString();

      if (value is Map) {
        result[stringKey] = deepConvertMap(value);
      } else if (value is List) {
        result[stringKey] = deepConvertList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  /// Mirrors `_deepConvertList` from cart_provider.dart
  static List<dynamic> deepConvertList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return deepConvertMap(item);
      } else if (item is List) {
        return deepConvertList(item);
      }
      return item;
    }).toList();
  }
}

// ============================================================================
// SALE PREFERENCES EXTRACTOR - Mirrors _extractSalePreferences
// Exact copy from cart_provider.dart lines 1030-1039
// ============================================================================
/// Mirrors `_extractSalePreferences` from cart_provider.dart
class TestableSalePreferencesExtractor {
  static Map<String, dynamic>? extract(Map<String, dynamic> data) {
    final salePrefs = <String, dynamic>{};
    if (data['maxQuantity'] != null) {
      salePrefs['maxQuantity'] = data['maxQuantity'];
    }
    if (data['discountThreshold'] != null) {
      salePrefs['discountThreshold'] = data['discountThreshold'];
    }
    if (data['bulkDiscountPercentage'] != null) {
      salePrefs['bulkDiscountPercentage'] = data['bulkDiscountPercentage'];
    }
    return salePrefs.isEmpty ? null : salePrefs;
  }
}

// ============================================================================
// QUANTITY CALCULATION HELPER - Mirrors logic from my_cart_screen.dart
// For testing max quantity computation
// ============================================================================
/// Mirrors quantity calculation logic from my_cart_screen.dart lines 340-350
class TestableQuantityCalculator {
  /// Calculates the effective max quantity a user can select
  static int calculateMaxQuantity({
    required int availableStock,
    required String? selectedColor,
    required Map<String, int> colorQuantities,
    int? maxAllowed,
  }) {
    int effectiveStock;

    if (selectedColor != null && colorQuantities.containsKey(selectedColor)) {
      effectiveStock = colorQuantities[selectedColor] ?? 0;
    } else {
      effectiveStock = availableStock;
    }

    if (maxAllowed != null) {
      return effectiveStock < maxAllowed ? effectiveStock : maxAllowed;
    }

    return effectiveStock;
  }
}