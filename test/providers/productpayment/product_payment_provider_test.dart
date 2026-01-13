// test/providers/product_payment_provider_test.dart
//
// Unit tests for ProductPaymentProvider pure logic
// Tests the EXACT logic from lib/providers/product_payment_provider.dart
//
// Run: flutter test test/providers/product_payment_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_product_payment_provider.dart';

void main() {
  // ============================================================================
  // DELIVERY PRICE CALCULATOR TESTS
  // ============================================================================
  group('TestableDeliveryPriceCalculator', () {
    group('getDeliveryPrice', () {
      group('normal delivery', () {
        test('charges 2.0 TL under 2000 TL threshold', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'normal',
              cartTotal: 1999.99,
            ),
            2.0,
          );
        });

        test('free at exactly 2000 TL', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'normal',
              cartTotal: 2000.0,
            ),
            0.0,
          );
        });

        test('free above 2000 TL', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'normal',
              cartTotal: 5000.0,
            ),
            0.0,
          );
        });

        test('charges for small cart', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'normal',
              cartTotal: 100.0,
            ),
            2.0,
          );
        });
      });

      group('express delivery', () {
        test('charges 2.0 TL under 10000 TL threshold', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'express',
              cartTotal: 9999.99,
            ),
            2.0,
          );
        });

        test('free at exactly 10000 TL', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'express',
              cartTotal: 10000.0,
            ),
            0.0,
          );
        });

        test('free above 10000 TL', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'express',
              cartTotal: 15000.0,
            ),
            0.0,
          );
        });

        test('express still costs under normal threshold', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'express',
              cartTotal: 2000.0, // Free for normal, but not express
            ),
            2.0,
          );
        });
      });

      group('null/unknown option', () {
        test('null option returns 0', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: null,
              cartTotal: 100.0,
            ),
            0.0,
          );
        });

        test('unknown option returns 0', () {
          expect(
            TestableDeliveryPriceCalculator.getDeliveryPrice(
              deliveryOption: 'pickup',
              cartTotal: 100.0,
            ),
            0.0,
          );
        });
      });
    });

    group('amountNeededForFreeDelivery', () {
      test('calculates remaining for normal delivery', () {
        expect(
          TestableDeliveryPriceCalculator.amountNeededForFreeDelivery(
            deliveryOption: 'normal',
            cartTotal: 1500.0,
          ),
          500.0, // Need 500 more to reach 2000
        );
      });

      test('returns 0 when threshold met', () {
        expect(
          TestableDeliveryPriceCalculator.amountNeededForFreeDelivery(
            deliveryOption: 'normal',
            cartTotal: 2500.0,
          ),
          0.0,
        );
      });

      test('calculates for express delivery', () {
        expect(
          TestableDeliveryPriceCalculator.amountNeededForFreeDelivery(
            deliveryOption: 'express',
            cartTotal: 8000.0,
          ),
          2000.0, // Need 2000 more to reach 10000
        );
      });
    });
  });

  // ============================================================================
  // ITEM PAYLOAD BUILDER TESTS
  // ============================================================================
  group('TestableItemPayloadBuilder', () {
    group('buildItemPayload', () {
      test('builds basic payload', () {
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 2,
        );

        expect(payload['productId'], 'prod_123');
        expect(payload['quantity'], 2);
      });

      test('includes selectedAttributes', () {
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 1,
          selectedAttributes: {
            'size': 'M',
            'color': 'Red',
          },
        );

        expect(payload['productId'], 'prod_123');
        expect(payload['size'], 'M');
        expect(payload['color'], 'Red');
      });

      test('filters out null values from attributes', () {
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 1,
          selectedAttributes: {
            'size': 'M',
            'color': null,
          },
        );

        expect(payload.containsKey('size'), true);
        expect(payload.containsKey('color'), false);
      });

      test('filters out empty string values', () {
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 1,
          selectedAttributes: {
            'size': 'M',
            'color': '',
          },
        );

        expect(payload.containsKey('size'), true);
        expect(payload.containsKey('color'), false);
      });

      test('does NOT filter empty lists (Dart equality quirk)', () {
        // NOTE: In Dart, [] != [] is TRUE (different instances)
        // So the production code check `value != []` does NOT filter empty lists
        // This is a known quirk - empty lists will be included
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 1,
          selectedAttributes: {
            'size': 'M',
            'tags': [],
          },
        );

        expect(payload.containsKey('size'), true);
        // Empty list IS included due to Dart's equality behavior
        expect(payload.containsKey('tags'), true);
        expect(payload['tags'], []);
      });

      test('includes non-empty list values', () {
        final payload = TestableItemPayloadBuilder.buildItemPayload(
          productId: 'prod_123',
          quantity: 1,
          selectedAttributes: {
            'tags': ['new', 'sale'],
          },
        );

        expect(payload['tags'], ['new', 'sale']);
      });
    });

    group('validateItemPayload', () {
      test('valid payload has no errors', () {
        final errors = TestableItemPayloadBuilder.validateItemPayload({
          'productId': 'prod_123',
          'quantity': 2,
        });

        expect(errors, isEmpty);
      });

      test('missing productId is error', () {
        final errors = TestableItemPayloadBuilder.validateItemPayload({
          'quantity': 2,
        });

        expect(errors, contains('Missing productId'));
      });

      test('missing quantity is error', () {
        final errors = TestableItemPayloadBuilder.validateItemPayload({
          'productId': 'prod_123',
        });

        expect(errors, contains('Missing quantity'));
      });

      test('zero quantity is error', () {
        final errors = TestableItemPayloadBuilder.validateItemPayload({
          'productId': 'prod_123',
          'quantity': 0,
        });

        expect(errors, contains('Quantity must be positive'));
      });

      test('negative quantity is error', () {
        final errors = TestableItemPayloadBuilder.validateItemPayload({
          'productId': 'prod_123',
          'quantity': -1,
        });

        expect(errors, contains('Quantity must be positive'));
      });
    });
  });

  // ============================================================================
  // ADDRESS PAYLOAD BUILDER TESTS
  // ============================================================================
  group('TestableAddressPayloadBuilder', () {
    group('buildAddressPayload', () {
      test('builds complete payload', () {
        final payload = TestableAddressPayloadBuilder.buildAddressPayload(
          addressLine1: '123 Main St',
          addressLine2: 'Apt 4B',
          city: 'Istanbul',
          phoneNumber: '+905551234567',
          latitude: 41.0082,
          longitude: 28.9784,
        );

        expect(payload['addressLine1'], '123 Main St');
        expect(payload['addressLine2'], 'Apt 4B');
        expect(payload['city'], 'Istanbul');
        expect(payload['phoneNumber'], '+905551234567');
        expect(payload['location']['latitude'], 41.0082);
        expect(payload['location']['longitude'], 28.9784);
      });

      test('handles null location', () {
        final payload = TestableAddressPayloadBuilder.buildAddressPayload(
          addressLine1: '123 Main St',
          addressLine2: '',
          city: 'Istanbul',
          phoneNumber: '+905551234567',
          latitude: null,
          longitude: null,
        );

        expect(payload['location'], null);
      });
    });

    group('validateAddressPayload', () {
      test('valid payload has no errors', () {
        final errors = TestableAddressPayloadBuilder.validateAddressPayload({
          'addressLine1': '123 Main St',
          'phoneNumber': '+905551234567',
          'location': {'latitude': 41.0, 'longitude': 28.9},
        });

        expect(errors, isEmpty);
      });

      test('missing addressLine1 is error', () {
        final errors = TestableAddressPayloadBuilder.validateAddressPayload({
          'addressLine1': '',
          'phoneNumber': '+905551234567',
          'location': {'latitude': 41.0, 'longitude': 28.9},
        });

        expect(errors, contains('Missing addressLine1'));
      });

      test('missing phoneNumber is error', () {
        final errors = TestableAddressPayloadBuilder.validateAddressPayload({
          'addressLine1': '123 Main St',
          'phoneNumber': '',
          'location': {'latitude': 41.0, 'longitude': 28.9},
        });

        expect(errors, contains('Missing phoneNumber'));
      });

      test('missing location is error', () {
        final errors = TestableAddressPayloadBuilder.validateAddressPayload({
          'addressLine1': '123 Main St',
          'phoneNumber': '+905551234567',
          'location': null,
        });

        expect(errors, contains('Missing location'));
      });
    });
  });

  // ============================================================================
  // ORDER NUMBER GENERATOR TESTS
  // ============================================================================
  group('TestableOrderNumberGenerator', () {
    group('generate', () {
      test('generates correct format', () {
        final timestamp = DateTime(2024, 6, 15, 12, 30, 45);
        final orderNumber = TestableOrderNumberGenerator.generate(
          timestamp: timestamp,
        );

        expect(orderNumber, startsWith('ORDER-'));
        expect(orderNumber, 'ORDER-${timestamp.millisecondsSinceEpoch}');
      });

      test('generates unique numbers for different timestamps', () {
        final ts1 = DateTime(2024, 6, 15, 12, 0, 0);
        final ts2 = DateTime(2024, 6, 15, 12, 0, 1);

        final order1 = TestableOrderNumberGenerator.generate(timestamp: ts1);
        final order2 = TestableOrderNumberGenerator.generate(timestamp: ts2);

        expect(order1 != order2, true);
      });
    });

    group('parseTimestamp', () {
      test('parses valid order number', () {
        final original = DateTime(2024, 6, 15, 12, 30, 45);
        final orderNumber = TestableOrderNumberGenerator.generate(
          timestamp: original,
        );

        final parsed = TestableOrderNumberGenerator.parseTimestamp(orderNumber);

        expect(parsed, original);
      });

      test('returns null for invalid format', () {
        expect(TestableOrderNumberGenerator.parseTimestamp('INVALID-123'), null);
        expect(TestableOrderNumberGenerator.parseTimestamp('ORDER-abc'), null);
      });
    });

    group('isValidFormat', () {
      test('returns true for valid format', () {
        expect(
          TestableOrderNumberGenerator.isValidFormat('ORDER-1718450445000'),
          true,
        );
      });

      test('returns false for missing prefix', () {
        expect(
          TestableOrderNumberGenerator.isValidFormat('1718450445000'),
          false,
        );
      });

      test('returns false for non-numeric suffix', () {
        expect(
          TestableOrderNumberGenerator.isValidFormat('ORDER-invalid'),
          false,
        );
      });
    });
  });

  // ============================================================================
  // PAYMENT ERROR MAPPER TESTS
  // ============================================================================
  group('TestablePaymentErrorMapper', () {
    group('mapFirebaseFunctionError', () {
      test('returns message when provided', () {
        expect(
          TestablePaymentErrorMapper.mapFirebaseFunctionError(
            code: 'failed-precondition',
            message: 'Custom error message',
          ),
          'Custom error message',
        );
      });

      test('maps unauthenticated code', () {
        expect(
          TestablePaymentErrorMapper.mapFirebaseFunctionError(
            code: 'unauthenticated',
            message: null,
          ),
          'Lütfen giriş yapın.',
        );
      });

      test('maps invalid-argument code', () {
        expect(
          TestablePaymentErrorMapper.mapFirebaseFunctionError(
            code: 'invalid-argument',
            message: null,
          ),
          'Geçersiz bilgi. Lütfen kontrol edin.',
        );
      });

      test('maps failed-precondition code', () {
        expect(
          TestablePaymentErrorMapper.mapFirebaseFunctionError(
            code: 'failed-precondition',
            message: null,
          ),
          'Ürün stok sorunu. Lütfen tekrar deneyin.',
        );
      });

      test('returns default for unknown code', () {
        expect(
          TestablePaymentErrorMapper.mapFirebaseFunctionError(
            code: 'unknown-error',
            message: null,
          ),
          'Ödeme sırasında bir hata oluştu.',
        );
      });
    });

    group('getErrorSeverity', () {
      test('unauthenticated requires action', () {
        expect(
          TestablePaymentErrorMapper.getErrorSeverity('unauthenticated'),
          ErrorSeverity.requiresAction,
        );
      });

      test('invalid-argument is user error', () {
        expect(
          TestablePaymentErrorMapper.getErrorSeverity('invalid-argument'),
          ErrorSeverity.userError,
        );
      });

      test('failed-precondition is retryable', () {
        expect(
          TestablePaymentErrorMapper.getErrorSeverity('failed-precondition'),
          ErrorSeverity.retryable,
        );
      });

      test('unknown code is unknown severity', () {
        expect(
          TestablePaymentErrorMapper.getErrorSeverity('something-else'),
          ErrorSeverity.unknown,
        );
      });
    });
  });

  // ============================================================================
  // ADDRESS SELECTOR TESTS
  // ============================================================================
  group('TestableAddressSelector', () {
    final addresses = [
      {
        'id': 'addr_1',
        'addressLine1': '123 Main St',
        'addressLine2': 'Apt 4B',
        'city': 'Istanbul',
        'phoneNumber': '+905551234567',
        'location': {'latitude': 41.0082, 'longitude': 28.9784},
      },
      {
        'id': 'addr_2',
        'addressLine1': '456 Oak Ave',
        'addressLine2': '',
        'city': 'Ankara',
        'phoneNumber': '+905559876543',
        'location': null,
      },
    ];

    group('findAddressById', () {
      test('finds existing address', () {
        final found = TestableAddressSelector.findAddressById(addresses, 'addr_1');
        expect(found?['addressLine1'], '123 Main St');
      });

      test('returns null for non-existent id', () {
        final found = TestableAddressSelector.findAddressById(addresses, 'addr_999');
        expect(found, null);
      });

      test('returns null for null id', () {
        final found = TestableAddressSelector.findAddressById(addresses, null);
        expect(found, null);
      });
    });

    group('extractFormData', () {
      test('extracts all fields', () {
        final formData = TestableAddressSelector.extractFormData(addresses[0]);

        expect(formData!.addressLine1, '123 Main St');
        expect(formData.addressLine2, 'Apt 4B');
        expect(formData.city, 'Istanbul');
        expect(formData.phoneNumber, '+905551234567');
        expect(formData.latitude, 41.0082);
        expect(formData.longitude, 28.9784);
        expect(formData.hasLocation, true);
      });

      test('handles null location', () {
        final formData = TestableAddressSelector.extractFormData(addresses[1]);

        expect(formData!.addressLine1, '456 Oak Ave');
        expect(formData.latitude, null);
        expect(formData.longitude, null);
        expect(formData.hasLocation, false);
      });

      test('returns null for null address', () {
        final formData = TestableAddressSelector.extractFormData(null);
        expect(formData, null);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('cart checkout with selected attributes', () {
      final items = [
        {
          'productId': 'shoe_001',
          'quantity': 2,
          'selectedAttributes': {
            'size': '42',
            'color': 'Black',
            'width': null, // Should be filtered
          },
        },
        {
          'productId': 'shirt_002',
          'quantity': 1,
          'selectedAttributes': {
            'size': 'L',
            'color': '', // Should be filtered
          },
        },
      ];

      final payloads = items.map((item) {
        return TestableItemPayloadBuilder.buildItemPayload(
          productId: item['productId'] as String,
          quantity: item['quantity'] as int,
          selectedAttributes: item['selectedAttributes'] as Map<String, dynamic>?,
        );
      }).toList();

      // First item should have size and color
      expect(payloads[0]['productId'], 'shoe_001');
      expect(payloads[0]['size'], '42');
      expect(payloads[0]['color'], 'Black');
      expect(payloads[0].containsKey('width'), false);

      // Second item should only have size
      expect(payloads[1]['productId'], 'shirt_002');
      expect(payloads[1]['size'], 'L');
      expect(payloads[1].containsKey('color'), false);
    });

    test('free delivery threshold calculation', () {
      // Customer with cart total of 1800 TL, normal delivery
      final cartTotal = 1800.0;
      final deliveryPrice = TestableDeliveryPriceCalculator.getDeliveryPrice(
        deliveryOption: 'normal',
        cartTotal: cartTotal,
      );
      final amountNeeded = TestableDeliveryPriceCalculator.amountNeededForFreeDelivery(
        deliveryOption: 'normal',
        cartTotal: cartTotal,
      );

      expect(deliveryPrice, 2.0); // Not free yet
      expect(amountNeeded, 200.0); // Need 200 more for free delivery
    });

    test('complete order payload building', () {
      final itemPayload = TestableItemPayloadBuilder.buildItemPayload(
        productId: 'prod_123',
        quantity: 1,
        selectedAttributes: {'size': 'M'},
      );

      final addressPayload = TestableAddressPayloadBuilder.buildAddressPayload(
        addressLine1: '123 Main St',
        addressLine2: '',
        city: 'Istanbul',
        phoneNumber: '+905551234567',
        latitude: 41.0,
        longitude: 28.9,
      );

      final cartData = TestableCartDataBuilder.buildCartData(
        itemsPayload: [itemPayload],
        cartCalculatedTotal: 2500.0,
        deliveryOption: 'normal',
        deliveryPrice: 0.0, // Free because over 2000
        addressPayload: addressPayload,
        saveAddress: true,
      );

      expect(cartData['items'], hasLength(1));
      expect(cartData['cartCalculatedTotal'], 2500.0);
      expect(cartData['deliveryPrice'], 0.0);
      expect(cartData['address']['city'], 'Istanbul');
      expect(cartData['saveAddress'], true);
    });
  });
}