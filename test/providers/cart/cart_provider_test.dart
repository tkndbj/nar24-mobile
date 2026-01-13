// test/providers/cart_provider_test.dart
//
// Unit tests for CartProvider and FavoriteProvider logic
// Tests run against testable_cart_provider.dart which mirrors exact production logic
//
// To run: flutter test test/providers/cart_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'testable_cart_provider.dart';

void main() {
  // ==========================================================================
  // TEST GROUP 1: Rate Limiter
  // ==========================================================================
  group('RateLimiter', () {
    test('allows first operation immediately', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      expect(limiter.canProceed('add_product123'), true);
    });

    test('blocks rapid successive operations', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      expect(limiter.canProceed('add_product123'), true);
      expect(limiter.canProceed('add_product123'), false);
      expect(limiter.canProceed('add_product123'), false);
    });

    test('allows operation after cooldown period', () async {
      final limiter = TestableRateLimiter(Duration(milliseconds: 50));

      expect(limiter.canProceed('add_product123'), true);
      expect(limiter.canProceed('add_product123'), false);

      await Future.delayed(Duration(milliseconds: 60));

      expect(limiter.canProceed('add_product123'), true);
    });

    test('tracks different operation keys independently', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      expect(limiter.canProceed('add_product1'), true);
      expect(limiter.canProceed('add_product2'), true);
      expect(limiter.canProceed('add_product3'), true);

      // All should be blocked now
      expect(limiter.canProceed('add_product1'), false);
      expect(limiter.canProceed('add_product2'), false);
      expect(limiter.canProceed('add_product3'), false);
    });

    test('reset clears specific operation', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      limiter.canProceed('add_product1');
      limiter.canProceed('add_product2');

      limiter.reset('add_product1');

      expect(limiter.canProceed('add_product1'), true); // Reset, so allowed
      expect(limiter.canProceed('add_product2'), false); // Still blocked
    });

    test('resetAll clears all operations', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      limiter.canProceed('add_product1');
      limiter.canProceed('add_product2');
      limiter.canProceed('qty_product1');

      limiter.resetAll();

      expect(limiter.canProceed('add_product1'), true);
      expect(limiter.canProceed('add_product2'), true);
      expect(limiter.canProceed('qty_product1'), true);
    });

    test('handles edge case: zero cooldown', () {
      final limiter = TestableRateLimiter(Duration.zero);

      expect(limiter.canProceed('test'), true);
      expect(limiter.canProceed('test'), true); // Should pass immediately
    });

    test('handles edge case: very long cooldown', () {
      final limiter = TestableRateLimiter(Duration(days: 365));

      expect(limiter.canProceed('test'), true);
      expect(limiter.canProceed('test'), false);
    });

    test('tracks active operations count', () {
      final limiter = TestableRateLimiter(Duration(milliseconds: 100));

      expect(limiter.activeOperationsCount, 0);

      limiter.canProceed('op1');
      expect(limiter.activeOperationsCount, 1);

      limiter.canProceed('op2');
      expect(limiter.activeOperationsCount, 2);

      limiter.reset('op1');
      expect(limiter.activeOperationsCount, 1);
    });
  });

  // ==========================================================================
  // TEST GROUP 2: Circuit Breaker (Fault Tolerance)
  // ==========================================================================
  group('CircuitBreaker', () {
    test('starts in closed state', () {
      final breaker = TestableCircuitBreaker();

      expect(breaker.isOpen, false);
      expect(breaker.failureCount, 0);
    });

    test('stays closed below threshold', () {
      final breaker = TestableCircuitBreaker(threshold: 5);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();

      expect(breaker.failureCount, 4);
      expect(breaker.isOpen, false); // Still below threshold
    });

    test('opens at threshold', () {
      final breaker = TestableCircuitBreaker(threshold: 5);

      for (int i = 0; i < 5; i++) {
        breaker.recordFailure();
      }

      expect(breaker.failureCount, 5);
      expect(breaker.isOpen, true);
    });

    test('stays open after exceeding threshold', () {
      final breaker = TestableCircuitBreaker(threshold: 3);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, true);

      breaker.recordFailure(); // Extra failure
      breaker.recordFailure();
      expect(breaker.isOpen, true);
      expect(breaker.failureCount, 5);
    });

    test('success resets failure count', () {
      final breaker = TestableCircuitBreaker(threshold: 5);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.failureCount, 3);

      breaker.recordSuccess();
      expect(breaker.failureCount, 0);
      expect(breaker.isOpen, false);
    });

    test('success resets even when open', () {
      final breaker = TestableCircuitBreaker(threshold: 3);

      // Open the breaker
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, true);

      // Success should reset
      breaker.recordSuccess();
      expect(breaker.failureCount, 0);
      expect(breaker.isOpen, false);
    });

    test('auto-closes after reset duration', () async {
      final breaker = TestableCircuitBreaker(
        threshold: 3,
        resetDuration: Duration(milliseconds: 50),
      );

      // Open the breaker
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, true);

      // Wait for reset duration
      await Future.delayed(Duration(milliseconds: 60));

      // Should auto-close and reset count
      expect(breaker.isOpen, false);
      expect(breaker.failureCount, 0);
    });

    test('stays open before reset duration expires', () async {
      final breaker = TestableCircuitBreaker(
        threshold: 3,
        resetDuration: Duration(milliseconds: 100),
      );

      // Open the breaker
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, true);

      // Wait less than reset duration
      await Future.delayed(Duration(milliseconds: 30));

      // Should still be open
      expect(breaker.isOpen, true);
    });

    test('records last failure time', () {
      final breaker = TestableCircuitBreaker();

      expect(breaker.lastFailureTime, isNull);

      final before = DateTime.now();
      breaker.recordFailure();
      final after = DateTime.now();

      expect(breaker.lastFailureTime, isNotNull);
      expect(
        breaker.lastFailureTime!.isAfter(before.subtract(Duration(seconds: 1))),
        true,
      );
      expect(
        breaker.lastFailureTime!.isBefore(after.add(Duration(seconds: 1))),
        true,
      );
    });

    test('reset clears all state', () {
      final breaker = TestableCircuitBreaker(threshold: 3);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.isOpen, true);

      breaker.reset();

      expect(breaker.failureCount, 0);
      expect(breaker.lastFailureTime, isNull);
      expect(breaker.isOpen, false);
    });

    test('handles rapid failures', () {
      final breaker = TestableCircuitBreaker(threshold: 100);

      for (int i = 0; i < 100; i++) {
        breaker.recordFailure();
      }

      expect(breaker.failureCount, 100);
      expect(breaker.isOpen, true);
    });

    test('alternating success/failure stays closed', () {
      final breaker = TestableCircuitBreaker(threshold: 3);

      breaker.recordFailure();
      breaker.recordSuccess(); // Resets to 0
      breaker.recordFailure();
      breaker.recordSuccess(); // Resets to 0
      breaker.recordFailure();

      expect(breaker.failureCount, 1);
      expect(breaker.isOpen, false);
    });
  });

  // ==========================================================================
  // TEST GROUP 3: CartTotals JSON Parsing
  // ==========================================================================
  group('CartTotals.fromJson', () {
    test('parses valid JSON correctly', () {
      final json = {
        'total': 299.99,
        'currency': 'TL',
        'items': [
          {
            'productId': 'prod1',
            'unitPrice': 99.99,
            'total': 199.98,
            'quantity': 2,
            'isBundleItem': false,
          },
          {
            'productId': 'prod2',
            'unitPrice': 100.01,
            'total': 100.01,
            'quantity': 1,
            'isBundleItem': true,
          },
        ],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.total, 299.99);
      expect(totals.currency, 'TL');
      expect(totals.items.length, 2);
      expect(totals.items[0].productId, 'prod1');
      expect(totals.items[0].quantity, 2);
      expect(totals.items[1].isBundleItem, true);
    });

    test('handles integer total (common from Firebase)', () {
      final json = {
        'total': 300, // int instead of double
        'currency': 'TL',
        'items': [],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.total, 300.0);
      expect(totals.total.runtimeType, double);
    });

    test('handles missing total with default', () {
      final json = <String, dynamic>{
        'currency': 'USD',
        'items': [],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.total, 0.0);
    });

    test('handles missing currency with default', () {
      final json = <String, dynamic>{
        'total': 100.0,
        'items': [],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.currency, 'TL');
    });

    test('handles null items list', () {
      final json = <String, dynamic>{
        'total': 100.0,
        'currency': 'TL',
        'items': null,
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.items, isEmpty);
    });

    test('handles missing items list', () {
      final json = <String, dynamic>{
        'total': 100.0,
        'currency': 'TL',
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.items, isEmpty);
    });

    test('handles non-Map<String,dynamic> item maps (Firebase quirk)', () {
      // Firebase sometimes returns Map<dynamic, dynamic>
      final json = <String, dynamic>{
        'total': 100.0,
        'currency': 'TL',
        'items': [
          <dynamic, dynamic>{
            'productId': 'prod1',
            'unitPrice': 50.0,
            'total': 50.0,
            'quantity': 1,
          },
        ],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.items.length, 1);
      expect(totals.items[0].productId, 'prod1');
    });

    test('skips malformed items without crashing', () {
      final json = <String, dynamic>{
        'total': 100.0,
        'currency': 'TL',
        'items': [
          {'productId': 'valid', 'unitPrice': 50.0, 'total': 50.0, 'quantity': 1},
          'invalid_string_item',
          123,
          null,
          {'productId': 'also_valid', 'unitPrice': 25.0, 'total': 25.0, 'quantity': 1},
        ],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.items.length, 2);
      expect(totals.items[0].productId, 'valid');
      expect(totals.items[1].productId, 'also_valid');
    });

    test('handles integer numbers in item fields', () {
      final json = <String, dynamic>{
        'total': 100.0,
        'currency': 'TL',
        'items': [
          {
            'productId': 'prod1',
            'unitPrice': 50, // int
            'total': 50, // int
            'quantity': 1, // int
          },
        ],
      };

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.items[0].unitPrice, 50.0);
      expect(totals.items[0].unitPrice.runtimeType, double);
    });

    test('handles empty JSON', () {
      final json = <String, dynamic>{};

      final totals = TestableCartTotals.fromJson(json);

      expect(totals.total, 0.0);
      expect(totals.currency, 'TL');
      expect(totals.items, isEmpty);
    });

    test('toJson produces valid output', () {
      final totals = TestableCartTotals(
        total: 150.0,
        currency: 'USD',
        items: [
          TestableCartItemTotal(
            productId: 'p1',
            unitPrice: 75.0,
            total: 150.0,
            quantity: 2,
            isBundleItem: false,
          ),
        ],
      );

      final json = totals.toJson();

      expect(json['total'], 150.0);
      expect(json['currency'], 'USD');
      expect((json['items'] as List).length, 1);
    });
  });

  // ==========================================================================
  // TEST GROUP 4: Data Transformation (CartDataTransformer)
  // ==========================================================================
  group('CartDataTransformer', () {
    group('safeGet', () {
      test('returns default for null value', () {
        final transformer = TestableCartDataTransformer({'price': null});

        expect(transformer.safeGet('price', 0.0), 0.0);
        expect(transformer.safeGet('missing', 'default'), 'default');
      });

      test('converts String to double', () {
        final transformer = TestableCartDataTransformer({'price': '99.99'});

        expect(transformer.safeGet<double>('price', 0.0), 99.99);
      });

      test('converts int to double', () {
        final transformer = TestableCartDataTransformer({'price': 100});

        expect(transformer.safeGet<double>('price', 0.0), 100.0);
      });

      test('converts String to int', () {
        final transformer = TestableCartDataTransformer({'quantity': '5'});

        expect(transformer.safeGet<int>('quantity', 0), 5);
      });

      test('converts double to int (truncates)', () {
        final transformer = TestableCartDataTransformer({'quantity': 5.7});

        expect(transformer.safeGet<int>('quantity', 0), 5);
      });

      test('converts various types to String', () {
        final transformer = TestableCartDataTransformer({
          'a': 123,
          'b': 45.67,
          'c': true,
          'd': 'already string',
        });

        expect(transformer.safeGet<String>('a', ''), '123');
        expect(transformer.safeGet<String>('b', ''), '45.67');
        expect(transformer.safeGet<String>('c', ''), 'true');
        expect(transformer.safeGet<String>('d', ''), 'already string');
      });

      test('converts String to bool', () {
        final transformer = TestableCartDataTransformer({
          'a': 'true',
          'b': 'TRUE',
          'c': 'false',
          'd': 'anything_else',
        });

        expect(transformer.safeGet<bool>('a', false), true);
        expect(transformer.safeGet<bool>('b', false), true);
        expect(transformer.safeGet<bool>('c', true), false);
        expect(transformer.safeGet<bool>('d', true), false);
      });

      test('handles invalid String to number conversion', () {
        final transformer = TestableCartDataTransformer({'price': 'not_a_number'});

        expect(transformer.safeGet<double>('price', 99.0), 99.0);
        expect(transformer.safeGet<int>('price', 10), 10);
      });

      test('handles edge case: empty string to number', () {
        final transformer = TestableCartDataTransformer({'price': ''});

        expect(transformer.safeGet<double>('price', 0.0), 0.0);
      });

      test('handles edge case: negative numbers', () {
        final transformer = TestableCartDataTransformer({
          'price': '-50.5',
          'quantity': -3,
        });

        expect(transformer.safeGet<double>('price', 0.0), -50.5);
        expect(transformer.safeGet<int>('quantity', 0), -3);
      });
    });

    group('safeStringList', () {
      test('returns empty list for null', () {
        final transformer = TestableCartDataTransformer({'colors': null});

        expect(transformer.safeStringList('colors'), isEmpty);
      });

      test('returns empty list for missing key', () {
        final transformer = TestableCartDataTransformer({});

        expect(transformer.safeStringList('colors'), isEmpty);
      });

      test('converts List to List<String>', () {
        final transformer = TestableCartDataTransformer({
          'colors': ['red', 'blue', 'green']
        });

        expect(
          transformer.safeStringList('colors'),
          ['red', 'blue', 'green'],
        );
      });

      test('converts mixed List to List<String>', () {
        final transformer = TestableCartDataTransformer({
          'mixed': [1, 2.5, 'three', true, null]
        });

        expect(
          transformer.safeStringList('mixed'),
          ['1', '2.5', 'three', 'true', 'null'],
        );
      });

      test('wraps single String in List', () {
        final transformer = TestableCartDataTransformer({
          'image': 'https://example.com/image.jpg'
        });

        expect(
          transformer.safeStringList('image'),
          ['https://example.com/image.jpg'],
        );
      });

      test('returns empty list for empty string', () {
        final transformer = TestableCartDataTransformer({'image': ''});

        expect(transformer.safeStringList('image'), isEmpty);
      });
    });

    group('safeColorQuantities', () {
      test('returns empty map for null', () {
        final transformer = TestableCartDataTransformer({'colorQuantities': null});

        expect(transformer.safeColorQuantities('colorQuantities'), isEmpty);
      });

      test('returns empty map for non-Map value', () {
        final transformer = TestableCartDataTransformer({'colorQuantities': 'not a map'});

        expect(transformer.safeColorQuantities('colorQuantities'), isEmpty);
      });

      test('parses valid color quantities', () {
        final transformer = TestableCartDataTransformer({
          'colorQuantities': {'red': 5, 'blue': 10, 'green': 3}
        });

        expect(
          transformer.safeColorQuantities('colorQuantities'),
          {'red': 5, 'blue': 10, 'green': 3},
        );
      });

      test('converts String quantities to int', () {
        final transformer = TestableCartDataTransformer({
          'colorQuantities': {'red': '5', 'blue': '10'}
        });

        expect(
          transformer.safeColorQuantities('colorQuantities'),
          {'red': 5, 'blue': 10},
        );
      });

      test('handles double quantities (truncates)', () {
        final transformer = TestableCartDataTransformer({
          'colorQuantities': {'red': 5.7, 'blue': 10.2}
        });

        expect(
          transformer.safeColorQuantities('colorQuantities'),
          {'red': 5, 'blue': 10},
        );
      });

      test('handles invalid String values', () {
        final transformer = TestableCartDataTransformer({
          'colorQuantities': {'red': 'five', 'blue': '10'}
        });

        expect(
          transformer.safeColorQuantities('colorQuantities'),
          {'red': 0, 'blue': 10},
        );
      });

      test('converts non-string keys to strings', () {
        final transformer = TestableCartDataTransformer({
          'colorQuantities': {1: 5, 2: 10}
        });

        expect(
          transformer.safeColorQuantities('colorQuantities'),
          {'1': 5, '2': 10},
        );
      });
    });

    group('safeColorImages', () {
      test('returns empty map for null', () {
        final transformer = TestableCartDataTransformer({'colorImages': null});

        expect(transformer.safeColorImages('colorImages'), isEmpty);
      });

      test('parses valid color images', () {
        final transformer = TestableCartDataTransformer({
          'colorImages': {
            'red': ['img1.jpg', 'img2.jpg'],
            'blue': ['img3.jpg'],
          }
        });

        final result = transformer.safeColorImages('colorImages');

        expect(result['red'], ['img1.jpg', 'img2.jpg']);
        expect(result['blue'], ['img3.jpg']);
      });

      test('wraps single string in list', () {
        final transformer = TestableCartDataTransformer({
          'colorImages': {
            'red': 'single_image.jpg',
          }
        });

        expect(
          transformer.safeColorImages('colorImages'),
          {'red': ['single_image.jpg']},
        );
      });

      test('ignores empty strings', () {
        final transformer = TestableCartDataTransformer({
          'colorImages': {
            'red': '',
            'blue': ['valid.jpg'],
          }
        });

        final result = transformer.safeColorImages('colorImages');

        expect(result.containsKey('red'), false);
        expect(result['blue'], ['valid.jpg']);
      });
    });

    group('safeBundleData', () {
      test('returns null for null value', () {
        final transformer = TestableCartDataTransformer({'bundleData': null});

        expect(transformer.safeBundleData('bundleData'), isNull);
      });

      test('returns null for non-List value', () {
        final transformer = TestableCartDataTransformer({'bundleData': 'not a list'});

        expect(transformer.safeBundleData('bundleData'), isNull);
      });

      test('parses valid bundle data', () {
        final transformer = TestableCartDataTransformer({
          'bundleData': [
            {'bundleId': 'b1', 'bundlePrice': 99.99},
            {'bundleId': 'b2', 'bundlePrice': 149.99},
          ]
        });

        final result = transformer.safeBundleData('bundleData');

        expect(result?.length, 2);
        expect(result?[0]['bundleId'], 'b1');
        expect(result?[1]['bundlePrice'], 149.99);
      });

      test('converts Map<dynamic,dynamic> to Map<String,dynamic>', () {
        final transformer = TestableCartDataTransformer({
          'bundleData': [
            <dynamic, dynamic>{'bundleId': 'b1', 'bundlePrice': 99.99},
          ]
        });

        final result = transformer.safeBundleData('bundleData');

        expect(result?.length, 1);
        expect(result?[0] is Map<String, dynamic>, true);
      });

      test('handles non-map items in list', () {
        final transformer = TestableCartDataTransformer({
          'bundleData': [
            {'bundleId': 'b1'},
            'invalid',
            123,
          ]
        });

        final result = transformer.safeBundleData('bundleData');

        expect(result?.length, 3);
        expect(result?[0]['bundleId'], 'b1');
        expect(result?[1], isEmpty);
        expect(result?[2], isEmpty);
      });
    });

    group('safeTimestamp', () {
      test('returns Timestamp as-is', () {
        final ts = Timestamp.now();
        final transformer = TestableCartDataTransformer({'createdAt': ts});

        expect(transformer.safeTimestamp('createdAt'), ts);
      });

      test('converts int milliseconds to Timestamp', () {
        final millis = 1700000000000;
        final transformer = TestableCartDataTransformer({'createdAt': millis});

        final result = transformer.safeTimestamp('createdAt');
        expect(result.millisecondsSinceEpoch, millis);
      });

      test('converts ISO string to Timestamp', () {
        final transformer = TestableCartDataTransformer({
          'createdAt': '2024-01-15T10:30:00.000Z'
        });

        final result = transformer.safeTimestamp('createdAt');
        expect(result.toDate().year, 2024);
        expect(result.toDate().month, 1);
        expect(result.toDate().day, 15);
      });

      test('returns now for invalid value', () {
        final transformer = TestableCartDataTransformer({'createdAt': 'invalid'});

        final before = DateTime.now();
        final result = transformer.safeTimestamp('createdAt');
        final after = DateTime.now();

        expect(
          result.toDate().isAfter(before.subtract(Duration(seconds: 1))),
          true,
        );
        expect(
          result.toDate().isBefore(after.add(Duration(seconds: 1))),
          true,
        );
      });
    });
  });

  // ==========================================================================
  // TEST GROUP 5: Field Validator (hasRequiredFields)
  // ==========================================================================
  group('FieldValidator.hasRequiredFields', () {
    test('returns true for valid cart data', () {
      final data = {
        'productId': 'prod123',
        'productName': 'Test Product',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), true);
    });

    test('returns false for missing productId', () {
      final data = {
        'productName': 'Test Product',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('returns false for null required field', () {
      final data = {
        'productId': 'prod123',
        'productName': null,
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('returns false for empty productName', () {
      final data = {
        'productId': 'prod123',
        'productName': '',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('returns false for "Unknown Product" productName', () {
      final data = {
        'productId': 'prod123',
        'productName': 'Unknown Product',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('returns false for "Unknown" sellerName', () {
      final data = {
        'productId': 'prod123',
        'productName': 'Test Product',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': 'Unknown',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('returns false for empty sellerName', () {
      final data = {
        'productId': 'prod123',
        'productName': 'Test Product',
        'unitPrice': 99.99,
        'availableStock': 10,
        'sellerName': '',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), false);
    });

    test('accepts numeric types for unitPrice and availableStock', () {
      final data = {
        'productId': 'prod123',
        'productName': 'Test Product',
        'unitPrice': 99, // int instead of double
        'availableStock': 10.0, // double instead of int
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
      };

      expect(TestableFieldValidator.hasRequiredFields(data), true);
    });
  });

  // ==========================================================================
  // TEST GROUP 6: Optimistic Update State Transitions
  // ==========================================================================
  group('OptimisticUpdateManager', () {
    test('applyAdd stores optimistic data', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod123', {'name': 'Test', 'price': 99.99}, 1);

      expect(manager.isOptimistic('prod123'), true);
      expect(manager.cache['prod123']?['name'], 'Test');
      expect(manager.cache['prod123']?['_optimistic'], true);
      expect(manager.cache['prod123']?['quantity'], 1);
    });

    test('applyRemove marks as deleted', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyRemove('prod123');

      expect(manager.isOptimistic('prod123'), true);
      expect(manager.isDeleted('prod123'), true);
    });

    test('clear removes specific product', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod1', {'name': 'Product 1'}, 1);
      manager.applyAdd('prod2', {'name': 'Product 2'}, 1);

      manager.clear('prod1');

      expect(manager.isOptimistic('prod1'), false);
      expect(manager.isOptimistic('prod2'), true);
    });

    test('clearAll removes all products', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod1', {'name': 'Product 1'}, 1);
      manager.applyAdd('prod2', {'name': 'Product 2'}, 1);
      manager.applyRemove('prod3');

      manager.clearAll();

      expect(manager.cache, isEmpty);
    });

    test('computeEffectiveIds adds optimistic adds', () {
      final manager = TestableOptimisticUpdateManager();
      final serverIds = {'prod1', 'prod2'};

      manager.applyAdd('prod3', {'name': 'New Product'}, 1);

      final effectiveIds = manager.computeEffectiveIds(serverIds);

      expect(effectiveIds, {'prod1', 'prod2', 'prod3'});
    });

    test('computeEffectiveIds removes optimistic deletes', () {
      final manager = TestableOptimisticUpdateManager();
      final serverIds = {'prod1', 'prod2', 'prod3'};

      manager.applyRemove('prod2');

      final effectiveIds = manager.computeEffectiveIds(serverIds);

      expect(effectiveIds, {'prod1', 'prod3'});
    });

    test('computeEffectiveIds handles both adds and deletes', () {
      final manager = TestableOptimisticUpdateManager();
      final serverIds = {'prod1', 'prod2'};

      manager.applyRemove('prod1'); // Remove existing
      manager.applyAdd('prod3', {}, 1); // Add new

      final effectiveIds = manager.computeEffectiveIds(serverIds);

      expect(effectiveIds, {'prod2', 'prod3'});
    });

    test('getExpiredUpdates returns expired entries', () async {
      final manager = TestableOptimisticUpdateManager(
        timeout: Duration(milliseconds: 50),
      );

      manager.applyAdd('prod1', {}, 1);

      // Not expired yet
      expect(manager.getExpiredUpdates(), isEmpty);

      await Future.delayed(Duration(milliseconds: 60));

      // Now expired
      expect(manager.getExpiredUpdates(), ['prod1']);
    });

    test('getExpiredUpdates does not return fresh entries', () async {
      final manager = TestableOptimisticUpdateManager(
        timeout: Duration(milliseconds: 100),
      );

      manager.applyAdd('prod1', {}, 1);
      await Future.delayed(Duration(milliseconds: 30));
      manager.applyAdd('prod2', {}, 1);

      await Future.delayed(Duration(milliseconds: 80));

      // prod1 should be expired (110ms), prod2 should not (80ms)
      final expired = manager.getExpiredUpdates();

      expect(expired.contains('prod1'), true);
      expect(expired.contains('prod2'), false);
    });

    test('overwriting optimistic add replaces data', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod1', {'quantity': 1}, 1);
      manager.applyAdd('prod1', {'quantity': 5}, 5);

      expect(manager.cache['prod1']?['quantity'], 5);
    });

    test('applyRemove after applyAdd marks as deleted', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod1', {'name': 'Test'}, 1);
      manager.applyRemove('prod1');

      expect(manager.isDeleted('prod1'), true);
      expect(manager.cache['prod1']?['name'], isNull);
    });

    test('rollback clears the entry', () {
      final manager = TestableOptimisticUpdateManager();

      manager.applyAdd('prod1', {'name': 'Test'}, 1);
      manager.rollback('prod1');

      expect(manager.isOptimistic('prod1'), false);
      expect(manager.cache.containsKey('prod1'), false);
    });
  });

  // ==========================================================================
  // TEST GROUP 7: Deep Converter
  // ==========================================================================
  group('DeepConverter', () {
    test('converts nested Map<dynamic,dynamic> to Map<String,dynamic>', () {
      final input = <dynamic, dynamic>{
        'level1': <dynamic, dynamic>{
          'level2': <dynamic, dynamic>{
            'value': 123,
          },
        },
      };

      final result = TestableDeepConverter.deepConvertMap(input);

      expect(result['level1'] is Map<String, dynamic>, true);
      expect(result['level1']['level2'] is Map<String, dynamic>, true);
      expect(result['level1']['level2']['value'], 123);
    });

    test('converts nested lists', () {
      final input = <dynamic, dynamic>{
        'items': [
          <dynamic, dynamic>{'id': 1},
          <dynamic, dynamic>{'id': 2},
        ],
      };

      final result = TestableDeepConverter.deepConvertMap(input);

      expect(result['items'] is List, true);
      expect(result['items'][0] is Map<String, dynamic>, true);
      expect(result['items'][0]['id'], 1);
    });

    test('handles null keys', () {
      final input = <dynamic, dynamic>{
        null: 'should be skipped',
        'valid': 'value',
      };

      final result = TestableDeepConverter.deepConvertMap(input);

      expect(result.containsKey('null'), false);
      expect(result['valid'], 'value');
    });

    test('preserves primitive values', () {
      final input = <dynamic, dynamic>{
        'string': 'hello',
        'int': 42,
        'double': 3.14,
        'bool': true,
      };

      final result = TestableDeepConverter.deepConvertMap(input);

      expect(result['string'], 'hello');
      expect(result['int'], 42);
      expect(result['double'], 3.14);
      expect(result['bool'], true);
    });
  });

  // ==========================================================================
  // TEST GROUP 8: Sale Preferences Extractor
  // ==========================================================================
  group('SalePreferencesExtractor', () {
    test('extracts all sale preferences', () {
      final data = {
        'maxQuantity': 10,
        'discountThreshold': 5,
        'bulkDiscountPercentage': 15,
        'otherField': 'ignored',
      };

      final result = TestableSalePreferencesExtractor.extract(data);

      expect(result?['maxQuantity'], 10);
      expect(result?['discountThreshold'], 5);
      expect(result?['bulkDiscountPercentage'], 15);
      expect(result?.containsKey('otherField'), false);
    });

    test('returns null for empty preferences', () {
      final data = {
        'productId': 'prod123',
        'name': 'Test',
      };

      final result = TestableSalePreferencesExtractor.extract(data);

      expect(result, isNull);
    });

    test('handles partial preferences', () {
      final data = {
        'maxQuantity': 5,
        'discountThreshold': null,
      };

      final result = TestableSalePreferencesExtractor.extract(data);

      expect(result?['maxQuantity'], 5);
      expect(result?.containsKey('discountThreshold'), false);
    });
  });

  // ==========================================================================
  // TEST GROUP 9: Quantity Calculator
  // ==========================================================================
  group('QuantityCalculator', () {
    test('returns availableStock when no color selected', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 50,
        selectedColor: null,
        colorQuantities: {'red': 10, 'blue': 20},
        maxAllowed: null,
      );

      expect(maxQty, 50);
    });

    test('returns color quantity when color selected', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 50,
        selectedColor: 'red',
        colorQuantities: {'red': 10, 'blue': 20},
        maxAllowed: null,
      );

      expect(maxQty, 10);
    });

    test('respects maxAllowed when lower than stock', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 50,
        selectedColor: null,
        colorQuantities: {},
        maxAllowed: 5,
      );

      expect(maxQty, 5);
    });

    test('returns stock when maxAllowed is higher', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 3,
        selectedColor: null,
        colorQuantities: {},
        maxAllowed: 10,
      );

      expect(maxQty, 3);
    });

    test('combines color quantity and maxAllowed', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 50,
        selectedColor: 'red',
        colorQuantities: {'red': 8},
        maxAllowed: 5,
      );

      expect(maxQty, 5); // maxAllowed is lower
    });

    test('handles missing color in quantities', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 50,
        selectedColor: 'green', // Not in colorQuantities
        colorQuantities: {'red': 10, 'blue': 20},
        maxAllowed: null,
      );

      expect(maxQty, 50); // Falls back to availableStock
    });

    test('handles zero stock', () {
      final maxQty = TestableQuantityCalculator.calculateMaxQuantity(
        availableStock: 0,
        selectedColor: null,
        colorQuantities: {},
        maxAllowed: 10,
      );

      expect(maxQty, 0);
    });
  });

  // ==========================================================================
  // TEST GROUP 10: Real-World Edge Cases
  // ==========================================================================
  group('Real-World Edge Cases', () {
    test('handles Firestore data with unexpected types', () {
      // Simulates data that might come from Firestore with type inconsistencies
      final cartData = {
        'productId': 123, // int instead of String
        'productName': 'Test Product',
        'unitPrice': '99.99', // String instead of double
        'availableStock': 10.0, // double instead of int
        'sellerName': 'Test Seller',
        'sellerId': 'seller123',
        'quantity': '3', // String instead of int
        'colorQuantities': {
          'red': '5', // String instead of int
          'blue': 10,
        },
      };

      final transformer = TestableCartDataTransformer(cartData);

      // These should all handle gracefully without throwing
      final productId = transformer.safeGet<String>('productId', '');
      final price = transformer.safeGet<double>('unitPrice', 0.0);
      final stock = transformer.safeGet<int>('availableStock', 0);
      final quantity = transformer.safeGet<int>('quantity', 1);
      final colorQty = transformer.safeColorQuantities('colorQuantities');

      expect(productId, '123');
      expect(price, 99.99);
      expect(stock, 10);
      expect(quantity, 3);
      expect(colorQty['red'], 5);
      expect(colorQty['blue'], 10);
    });

    test('handles completely empty cart data', () {
      final cartData = <String, dynamic>{};

      expect(TestableFieldValidator.hasRequiredFields(cartData), false);

      final transformer = TestableCartDataTransformer(cartData);
      expect(transformer.safeGet<String>('productId', 'default'), 'default');
      expect(transformer.safeStringList('images'), isEmpty);
      expect(transformer.safeColorQuantities('colorQuantities'), isEmpty);
    });

    test('handles cart data with all null values', () {
      final cartData = <String, dynamic>{
        'productId': null,
        'productName': null,
        'unitPrice': null,
        'availableStock': null,
        'sellerName': null,
        'sellerId': null,
      };

      expect(TestableFieldValidator.hasRequiredFields(cartData), false);
    });

    test('rapid add/remove sequence maintains consistency', () {
      final manager = TestableOptimisticUpdateManager();
      final serverIds = <String>{};

      // Simulate rapid user actions
      manager.applyAdd('prod1', {}, 1);
      var ids = manager.computeEffectiveIds(serverIds);
      expect(ids, {'prod1'});

      manager.applyRemove('prod1');
      ids = manager.computeEffectiveIds(serverIds);
      expect(ids, isEmpty);

      manager.applyAdd('prod1', {}, 1);
      ids = manager.computeEffectiveIds(serverIds);
      expect(ids, {'prod1'});

      // Server confirms the add
      serverIds.add('prod1');
      manager.clear('prod1');
      ids = manager.computeEffectiveIds(serverIds);
      expect(ids, {'prod1'});
    });

    test('race condition: server update arrives during optimistic state', () {
      final manager = TestableOptimisticUpdateManager();

      // User adds product optimistically
      manager.applyAdd('prod1', {'quantity': 1}, 1);

      // Server confirms with different quantity (another device updated it)
      final serverIds = {'prod1'};

      // Before clearing optimistic, effective IDs should include the product
      var ids = manager.computeEffectiveIds(serverIds);
      expect(ids.contains('prod1'), true);

      // Clear optimistic after server confirmation
      manager.clear('prod1');
      ids = manager.computeEffectiveIds(serverIds);
      expect(ids.contains('prod1'), true);
    });

    test('totals calculation with bundle items', () {
      final json = {
        'total': 250.0,
        'currency': 'TL',
        'items': [
          {
            'productId': 'prod1',
            'unitPrice': 100.0,
            'total': 100.0,
            'quantity': 1,
            'isBundleItem': false,
          },
          {
            'productId': 'bundle_prod',
            'unitPrice': 150.0,
            'total': 150.0,
            'quantity': 1,
            'isBundleItem': true,
          },
        ],
      };

      final totals = TestableCartTotals.fromJson(json);

      final bundleItems = totals.items.where((i) => i.isBundleItem).toList();
      final regularItems = totals.items.where((i) => !i.isBundleItem).toList();

      expect(bundleItems.length, 1);
      expect(regularItems.length, 1);
      expect(totals.total, 250.0);
    });

    test('handles very large numbers', () {
      final transformer = TestableCartDataTransformer({
        'price': 999999999.99,
        'quantity': 2147483647, // Max int32
      });

      expect(transformer.safeGet<double>('price', 0.0), 999999999.99);
      expect(transformer.safeGet<int>('quantity', 0), 2147483647);
    });

    test('handles special characters in strings', () {
      final transformer = TestableCartDataTransformer({
        'productName': 'Test "Product" with <special> & chars',
        'description': '日本語テスト', // Japanese
      });

      expect(
        transformer.safeGet<String>('productName', ''),
        'Test "Product" with <special> & chars',
      );
      expect(transformer.safeGet<String>('description', ''), '日本語テスト');
    });
  });
}