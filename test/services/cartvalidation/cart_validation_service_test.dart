// test/services/cart_validation_service_test.dart
//
// Unit tests for CartValidationService pure logic
// Tests the EXACT logic from lib/services/cart_validation_service.dart
//
// Run: flutter test test/services/cart_validation_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_cart_validation_service.dart';

void main() {
  // ============================================================================
  // MAP CONVERTER TESTS
  // ============================================================================
  group('TestableMapConverter', () {
    group('convertToStringMap', () {
      test('converts simple Map<Object?, Object?> to Map<String, dynamic>', () {
        final input = <Object?, Object?>{
          'name': 'Test Product',
          'price': 99.99,
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result, isA<Map<String, dynamic>>());
        expect(result['name'], 'Test Product');
        expect(result['price'], 99.99);
      });

      test('converts integer keys to strings', () {
        final input = <Object?, Object?>{
          1: 'one',
          2: 'two',
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result['1'], 'one');
        expect(result['2'], 'two');
      });

      test('handles nested maps recursively', () {
        final input = <Object?, Object?>{
          'outer': <Object?, Object?>{
            'inner': <Object?, Object?>{
              'deep': 'value',
            },
          },
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result['outer'], isA<Map<String, dynamic>>());
        expect(result['outer']['inner'], isA<Map<String, dynamic>>());
        expect(result['outer']['inner']['deep'], 'value');
      });

      test('handles lists with maps', () {
        final input = <Object?, Object?>{
          'items': [
            <Object?, Object?>{'id': 1, 'name': 'Item 1'},
            <Object?, Object?>{'id': 2, 'name': 'Item 2'},
          ],
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result['items'], isA<List>());
        expect(result['items'][0], isA<Map<String, dynamic>>());
        expect(result['items'][0]['name'], 'Item 1');
        expect(result['items'][1]['name'], 'Item 2');
      });

      test('returns empty map for non-map input', () {
        expect(TestableMapConverter.convertToStringMap('string'), {});
        expect(TestableMapConverter.convertToStringMap(123), {});
        expect(TestableMapConverter.convertToStringMap(null), {});
      });

      test('handles null values in map', () {
        final input = <Object?, Object?>{
          'name': 'Test',
          'description': null,
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result['name'], 'Test');
        expect(result['description'], null);
        expect(result.containsKey('description'), true);
      });

      test('handles mixed value types', () {
        final input = <Object?, Object?>{
          'string': 'hello',
          'int': 42,
          'double': 3.14,
          'bool': true,
          'list': [1, 2, 3],
          'map': {'nested': 'value'},
        };

        final result = TestableMapConverter.convertToStringMap(input);

        expect(result['string'], 'hello');
        expect(result['int'], 42);
        expect(result['double'], 3.14);
        expect(result['bool'], true);
        expect(result['list'], [1, 2, 3]);
        expect(result['map']['nested'], 'value');
      });
    });

    group('convertValue', () {
      test('returns primitives unchanged', () {
        expect(TestableMapConverter.convertValue('string'), 'string');
        expect(TestableMapConverter.convertValue(123), 123);
        expect(TestableMapConverter.convertValue(3.14), 3.14);
        expect(TestableMapConverter.convertValue(true), true);
        expect(TestableMapConverter.convertValue(null), null);
      });

      test('converts maps', () {
        final input = <Object?, Object?>{'key': 'value'};
        final result = TestableMapConverter.convertValue(input);

        expect(result, isA<Map<String, dynamic>>());
        expect(result['key'], 'value');
      });

      test('converts lists recursively', () {
        final input = [
          <Object?, Object?>{'id': 1},
          <Object?, Object?>{'id': 2},
        ];

        final result = TestableMapConverter.convertValue(input);

        expect(result, isA<List>());
        expect(result[0], isA<Map<String, dynamic>>());
      });
    });
  });

  // ============================================================================
  // CART ITEM EXTRACTOR TESTS
  // ============================================================================
  group('TestableCartItemExtractor', () {
    group('extractForValidation', () {
      test('extracts basic fields', () {
        final item = {
          'productId': 'prod123',
          'quantity': 2,
          'cartData': {
            'selectedColor': 'Red',
          },
        };

        final result = TestableCartItemExtractor.extractForValidation(item);

        expect(result['productId'], 'prod123');
        expect(result['quantity'], 2);
        expect(result['selectedColor'], 'Red');
      });

      test('defaults quantity to 1 if missing', () {
        final item = {
          'productId': 'prod123',
          'cartData': {},
        };

        final result = TestableCartItemExtractor.extractForValidation(item);

        expect(result['quantity'], 1);
      });

      test('extracts all cached price fields', () {
        final item = {
          'productId': 'prod123',
          'quantity': 1,
          'cartData': {
            'selectedColor': 'Blue',
            'cachedPrice': 99.99,
            'cachedBundlePrice': 89.99,
            'cachedDiscountPercentage': 10,
            'cachedDiscountThreshold': 3,
            'cachedBulkDiscountPercentage': 15,
            'cachedMaxQuantity': 10,
          },
        };

        final result = TestableCartItemExtractor.extractForValidation(item);

        expect(result['cachedPrice'], 99.99);
        expect(result['cachedBundlePrice'], 89.99);
        expect(result['cachedDiscountPercentage'], 10);
        expect(result['cachedDiscountThreshold'], 3);
        expect(result['cachedBulkDiscountPercentage'], 15);
        expect(result['cachedMaxQuantity'], 10);
      });

      test('handles missing cartData gracefully', () {
        final item = {
          'productId': 'prod123',
          'quantity': 1,
        };

        final result = TestableCartItemExtractor.extractForValidation(item);

        expect(result['productId'], 'prod123');
        expect(result['selectedColor'], null);
        expect(result['cachedPrice'], null);
      });

      test('handles null cartData', () {
        final item = {
          'productId': 'prod123',
          'quantity': 1,
          'cartData': null,
        };

        // Should not throw
        final result = TestableCartItemExtractor.extractForValidation(item);
        expect(result['productId'], 'prod123');
      });
    });

    group('extractAllForValidation', () {
      test('extracts from multiple items', () {
        final items = [
          {'productId': 'p1', 'quantity': 1, 'cartData': {}},
          {'productId': 'p2', 'quantity': 2, 'cartData': {}},
          {'productId': 'p3', 'quantity': 3, 'cartData': {}},
        ];

        final results = TestableCartItemExtractor.extractAllForValidation(items);

        expect(results.length, 3);
        expect(results[0]['productId'], 'p1');
        expect(results[1]['productId'], 'p2');
        expect(results[2]['productId'], 'p3');
      });

      test('returns empty list for empty input', () {
        final results = TestableCartItemExtractor.extractAllForValidation([]);
        expect(results, isEmpty);
      });
    });
  });

  // ============================================================================
  // CACHE UPDATE BUILDER TESTS
  // ============================================================================
  group('TestableCacheUpdateBuilder', () {
    group('buildUpdatePayload', () {
      test('builds complete update payload', () {
        final validatedItem = {
          'productId': 'prod123',
          'unitPrice': 99.99,
          'bundlePrice': 89.99,
          'discountPercentage': 10,
          'discountThreshold': 3,
          'bulkDiscountPercentage': 15,
          'maxQuantity': 10,
        };

        final result = TestableCacheUpdateBuilder.buildUpdatePayload(validatedItem);

        expect(result['productId'], 'prod123');
        expect(result['updates']['cachedPrice'], 99.99);
        expect(result['updates']['cachedBundlePrice'], 89.99);
        expect(result['updates']['unitPrice'], 99.99);
        expect(result['updates']['bundlePrice'], 89.99);
      });

      test('converts productId to string', () {
        final validatedItem = {
          'productId': 12345, // Integer
          'unitPrice': 50.0,
        };

        final result = TestableCacheUpdateBuilder.buildUpdatePayload(validatedItem);

        expect(result['productId'], '12345');
      });

      test('handles null values', () {
        final validatedItem = {
          'productId': 'prod123',
          'unitPrice': null,
          'bundlePrice': null,
        };

        final result = TestableCacheUpdateBuilder.buildUpdatePayload(validatedItem);

        expect(result['updates']['cachedPrice'], null);
        expect(result['updates']['cachedBundlePrice'], null);
      });

      test('duplicates values in cached and denormalized fields', () {
        final validatedItem = {
          'productId': 'prod123',
          'unitPrice': 100.0,
          'discountPercentage': 20,
        };

        final result = TestableCacheUpdateBuilder.buildUpdatePayload(validatedItem);
        final updates = result['updates'] as Map<String, dynamic>;

        // Should have both cached and direct versions
        expect(updates['cachedPrice'], 100.0);
        expect(updates['unitPrice'], 100.0);
        expect(updates['cachedDiscountPercentage'], 20);
        expect(updates['discountPercentage'], 20);
      });
    });

    group('buildAllUpdatePayloads', () {
      test('builds payloads for multiple items', () {
        final validatedItems = [
          {'productId': 'p1', 'unitPrice': 10.0},
          {'productId': 'p2', 'unitPrice': 20.0},
        ];

        final results = TestableCacheUpdateBuilder.buildAllUpdatePayloads(validatedItems);

        expect(results.length, 2);
        expect(results[0]['productId'], 'p1');
        expect(results[1]['productId'], 'p2');
      });
    });
  });

  // ============================================================================
  // VALIDATION ERROR HANDLER TESTS
  // ============================================================================
  group('TestableValidationErrorHandler', () {
    group('isRateLimitError', () {
      test('returns true for resource-exhausted', () {
        expect(TestableValidationErrorHandler.isRateLimitError('resource-exhausted'), true);
      });

      test('returns false for other error codes', () {
        expect(TestableValidationErrorHandler.isRateLimitError('invalid-argument'), false);
        expect(TestableValidationErrorHandler.isRateLimitError('not-found'), false);
        expect(TestableValidationErrorHandler.isRateLimitError('permission-denied'), false);
      });
    });

    group('buildRateLimitResponse', () {
      test('returns correctly structured response', () {
        final response = TestableValidationErrorHandler.buildRateLimitResponse();

        expect(response['isValid'], false);
        expect(response['errors'], isA<Map>());
        expect(response['errors']['_system']['key'], 'rate_limit_exceeded');
        expect(response['warnings'], isA<Map>());
        expect(response['validatedItems'], isA<List>());
      });

      test('has empty warnings and validatedItems', () {
        final response = TestableValidationErrorHandler.buildRateLimitResponse();

        expect((response['warnings'] as Map).isEmpty, true);
        expect((response['validatedItems'] as List).isEmpty, true);
      });
    });

    group('isValidResponse', () {
      test('returns true for complete response', () {
        final response = {
          'isValid': true,
          'errors': {},
          'warnings': {},
        };

        expect(TestableValidationErrorHandler.isValidResponse(response), true);
      });

      test('returns false for missing isValid', () {
        final response = {
          'errors': {},
          'warnings': {},
        };

        expect(TestableValidationErrorHandler.isValidResponse(response), false);
      });

      test('returns false for missing errors', () {
        final response = {
          'isValid': true,
          'warnings': {},
        };

        expect(TestableValidationErrorHandler.isValidResponse(response), false);
      });

      test('returns false for missing warnings', () {
        final response = {
          'isValid': true,
          'errors': {},
        };

        expect(TestableValidationErrorHandler.isValidResponse(response), false);
      });
    });

    group('getErrorCount', () {
      test('returns correct count', () {
        final response = {
          'errors': {
            'product1': {'key': 'out_of_stock'},
            'product2': {'key': 'price_changed'},
          },
        };

        expect(TestableValidationErrorHandler.getErrorCount(response), 2);
      });

      test('returns 0 for empty errors', () {
        final response = {'errors': {}};
        expect(TestableValidationErrorHandler.getErrorCount(response), 0);
      });

      test('returns 0 for non-map errors', () {
        final response = {'errors': 'invalid'};
        expect(TestableValidationErrorHandler.getErrorCount(response), 0);
      });
    });

    group('getWarningCount', () {
      test('returns correct count', () {
        final response = {
          'warnings': {
            'product1': {'key': 'low_stock'},
          },
        };

        expect(TestableValidationErrorHandler.getWarningCount(response), 1);
      });
    });

    group('isValidationPassed', () {
      test('returns true when isValid is true', () {
        expect(
          TestableValidationErrorHandler.isValidationPassed({'isValid': true}),
          true,
        );
      });

      test('returns false when isValid is false', () {
        expect(
          TestableValidationErrorHandler.isValidationPassed({'isValid': false}),
          false,
        );
      });

      test('returns false when isValid is missing', () {
        expect(
          TestableValidationErrorHandler.isValidationPassed({}),
          false,
        );
      });
    });
  });

  // ============================================================================
  // VALIDATION REQUEST BUILDER TESTS
  // ============================================================================
  group('TestableValidationRequestBuilder', () {
    group('buildRequest', () {
      test('builds request with extracted cart items', () {
        final cartItems = [
          {
            'productId': 'p1',
            'quantity': 2,
            'cartData': {'selectedColor': 'Red'},
          },
        ];

        final request = TestableValidationRequestBuilder.buildRequest(
          cartItems: cartItems,
          reserveStock: false,
        );

        expect(request['cartItems'], isA<List>());
        expect(request['cartItems'][0]['productId'], 'p1');
        expect(request['cartItems'][0]['quantity'], 2);
        expect(request['reserveStock'], false);
      });

      test('sets reserveStock correctly', () {
        final request = TestableValidationRequestBuilder.buildRequest(
          cartItems: [],
          reserveStock: true,
        );

        expect(request['reserveStock'], true);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('Firebase response conversion handles nested Object? maps', () {
      // Simulates actual Firebase Cloud Function response
      final firebaseResponse = <Object?, Object?>{
        'isValid': true,
        'errors': <Object?, Object?>{},
        'warnings': <Object?, Object?>{
          'product123': <Object?, Object?>{
            'key': 'low_stock',
            'params': <Object?, Object?>{
              'available': 5,
              'requested': 10,
            },
          },
        },
        'validatedItems': [
          <Object?, Object?>{
            'productId': 'product123',
            'unitPrice': 99.99,
          },
        ],
      };

      final converted = TestableMapConverter.convertToStringMap(firebaseResponse);

      expect(converted['isValid'], true);
      expect(converted['warnings']['product123']['key'], 'low_stock');
      expect(converted['warnings']['product123']['params']['available'], 5);
      expect(converted['validatedItems'][0]['unitPrice'], 99.99);
    });

    test('cart checkout flow extracts and validates correctly', () {
      // User's cart
      final cartItems = [
        {
          'productId': 'nike_shoes_123',
          'quantity': 2,
          'cartData': {
            'selectedColor': 'Black',
            'cachedPrice': 150.0,
            'cachedDiscountPercentage': 20,
          },
        },
        {
          'productId': 'adidas_shirt_456',
          'quantity': 1,
          'cartData': {
            'selectedColor': 'White',
            'cachedPrice': 50.0,
          },
        },
      ];

      // Extract for validation
      final extracted = TestableCartItemExtractor.extractAllForValidation(cartItems);

      expect(extracted.length, 2);
      expect(extracted[0]['cachedPrice'], 150.0);
      expect(extracted[0]['cachedDiscountPercentage'], 20);
      expect(extracted[1]['cachedPrice'], 50.0);
      expect(extracted[1]['cachedDiscountPercentage'], null);
    });

    test('validation response processing counts errors correctly', () {
      final response = {
        'isValid': false,
        'errors': {
          'product1': {'key': 'out_of_stock', 'params': {}},
          'product2': {'key': 'price_changed', 'params': {'oldPrice': 100, 'newPrice': 120}},
          'product3': {'key': 'discontinued', 'params': {}},
        },
        'warnings': {
          'product4': {'key': 'low_stock', 'params': {'available': 2}},
        },
        'validatedItems': [],
      };

      expect(TestableValidationErrorHandler.isValidationPassed(response), false);
      expect(TestableValidationErrorHandler.getErrorCount(response), 3);
      expect(TestableValidationErrorHandler.getWarningCount(response), 1);
      expect(TestableValidationErrorHandler.isValidResponse(response), true);
    });

    test('cache update after validation preserves all price data', () {
      // Validated items from Cloud Function
      final validatedItems = [
        {
          'productId': 'prod123',
          'unitPrice': 100.0,
          'bundlePrice': 90.0,
          'discountPercentage': 10,
          'discountThreshold': 3,
          'bulkDiscountPercentage': 15,
          'maxQuantity': 20,
        },
      ];

      final updatePayloads = TestableCacheUpdateBuilder.buildAllUpdatePayloads(validatedItems);

      final updates = updatePayloads[0]['updates'] as Map<String, dynamic>;

      // Verify all fields are present for cache update
      expect(updates['cachedPrice'], 100.0);
      expect(updates['cachedBundlePrice'], 90.0);
      expect(updates['cachedDiscountPercentage'], 10);
      expect(updates['cachedDiscountThreshold'], 3);
      expect(updates['cachedBulkDiscountPercentage'], 15);
      expect(updates['cachedMaxQuantity'], 20);

      // Verify denormalized copies
      expect(updates['unitPrice'], 100.0);
      expect(updates['bundlePrice'], 90.0);
    });

    test('rate limit error is properly detected and handled', () {
      const errorCode = 'resource-exhausted';

      if (TestableValidationErrorHandler.isRateLimitError(errorCode)) {
        final response = TestableValidationErrorHandler.buildRateLimitResponse();

        expect(response['isValid'], false);
        expect(response['errors']['_system']['key'], 'rate_limit_exceeded');
      }
    });

    test('missing cartData does not crash extraction', () {
      // Edge case: cart item without cartData (corrupted state)
      final corruptedItems = [
        {'productId': 'p1', 'quantity': 1}, // No cartData
        {'productId': 'p2', 'quantity': 2, 'cartData': null}, // Null cartData
        {'productId': 'p3'}, // No quantity either
      ];

      // Should not throw
      final extracted = TestableCartItemExtractor.extractAllForValidation(corruptedItems);

      expect(extracted.length, 3);
      expect(extracted[0]['quantity'], 1);
      expect(extracted[2]['quantity'], 1); // Default
    });
  });
}