// test/services/metrics_event_service_test.dart
//
// Unit tests for MetricsEventService pure logic
// Tests the EXACT logic from lib/services/metrics_event_service.dart
//
// Run: flutter test test/services/metrics_event_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_metrics_event_service.dart';

void main() {
  // ============================================================================
  // BATCH ID GENERATOR TESTS
  // ============================================================================
  group('TestableBatchIdGenerator', () {
    group('generate', () {
      test('generates correct format', () {
        final batchId = TestableBatchIdGenerator.generate(
          userId: 'user123',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1718452800000),
        );

        expect(batchId, 'cart_fav_user123_1718452800000');
      });

      test('includes user ID', () {
        final batchId = TestableBatchIdGenerator.generate(
          userId: 'abc_xyz_123',
          timestamp: DateTime.now(),
        );

        expect(batchId.contains('abc_xyz_123'), true);
      });

      test('generates unique IDs for different timestamps', () {
        final time1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final time2 = DateTime.fromMillisecondsSinceEpoch(2000);

        final id1 = TestableBatchIdGenerator.generate(userId: 'user', timestamp: time1);
        final id2 = TestableBatchIdGenerator.generate(userId: 'user', timestamp: time2);

        expect(id1, isNot(id2));
      });

      test('generates unique IDs for different users', () {
        final time = DateTime.now();

        final id1 = TestableBatchIdGenerator.generate(userId: 'user1', timestamp: time);
        final id2 = TestableBatchIdGenerator.generate(userId: 'user2', timestamp: time);

        expect(id1, isNot(id2));
      });
    });

    group('parse', () {
      test('extracts userId and timestamp', () {
        final parsed = TestableBatchIdGenerator.parse('cart_fav_user123_1718452800000');

        expect(parsed, isNotNull);
        expect(parsed!['userId'], 'user123');
        expect(parsed['timestamp'], 1718452800000);
      });

      test('returns null for invalid format', () {
        expect(TestableBatchIdGenerator.parse('invalid'), null);
        expect(TestableBatchIdGenerator.parse('cart_user_123'), null);
        expect(TestableBatchIdGenerator.parse(''), null);
      });

      test('handles userId with underscores', () {
        final parsed = TestableBatchIdGenerator.parse('cart_fav_user_with_underscores_1718452800000');

        expect(parsed, isNotNull);
        expect(parsed!['userId'], 'user_with_underscores');
      });
    });

    group('isValid', () {
      test('returns true for valid batch ID', () {
        expect(TestableBatchIdGenerator.isValid('cart_fav_user123_1718452800000'), true);
      });

      test('returns false for missing prefix', () {
        expect(TestableBatchIdGenerator.isValid('user123_1718452800000'), false);
      });

      test('returns false for missing timestamp', () {
        expect(TestableBatchIdGenerator.isValid('cart_fav_user123'), false);
      });

      test('returns false for non-numeric timestamp', () {
        expect(TestableBatchIdGenerator.isValid('cart_fav_user123_abc'), false);
      });
    });
  });

  // ============================================================================
  // EVENT VALIDATOR TESTS
  // ============================================================================
  group('TestableEventValidator', () {
    group('isValidEvent', () {
      test('returns true for valid event', () {
        final event = {'type': 'cart_added', 'productId': 'prod123'};
        expect(TestableEventValidator.isValidEvent(event), true);
      });

      test('returns true with optional shopId', () {
        final event = {
          'type': 'cart_added',
          'productId': 'prod123',
          'shopId': 'shop456',
        };
        expect(TestableEventValidator.isValidEvent(event), true);
      });

      test('returns false for missing type', () {
        final event = {'productId': 'prod123'};
        expect(TestableEventValidator.isValidEvent(event), false);
      });

      test('returns false for missing productId', () {
        final event = {'type': 'cart_added'};
        expect(TestableEventValidator.isValidEvent(event), false);
      });

      test('returns false for empty map', () {
        expect(TestableEventValidator.isValidEvent({}), false);
      });
    });

    group('areAllEventsValid', () {
      test('returns true when all events valid', () {
        final events = [
          {'type': 'cart_added', 'productId': 'p1'},
          {'type': 'cart_removed', 'productId': 'p2'},
        ];
        expect(TestableEventValidator.areAllEventsValid(events), true);
      });

      test('returns false when one event invalid', () {
        final events = [
          {'type': 'cart_added', 'productId': 'p1'},
          {'productId': 'p2'}, // Missing type
        ];
        expect(TestableEventValidator.areAllEventsValid(events), false);
      });

      test('returns false for empty list', () {
        expect(TestableEventValidator.areAllEventsValid([]), false);
      });
    });

    group('getValidationErrors', () {
      test('returns empty list for valid event', () {
        final event = {'type': 'cart_added', 'productId': 'prod123'};
        expect(TestableEventValidator.getValidationErrors(event), isEmpty);
      });

      test('returns error for missing type', () {
        final event = {'productId': 'prod123'};
        final errors = TestableEventValidator.getValidationErrors(event);
        expect(errors, contains('Missing required field: type'));
      });

      test('returns error for missing productId', () {
        final event = {'type': 'cart_added'};
        final errors = TestableEventValidator.getValidationErrors(event);
        expect(errors, contains('Missing required field: productId'));
      });

      test('returns multiple errors for empty event', () {
        final errors = TestableEventValidator.getValidationErrors({});
        expect(errors.length, 2);
      });
    });

    group('isValidEventType', () {
      test('returns true for cart_added', () {
        expect(TestableEventValidator.isValidEventType('cart_added'), true);
      });

      test('returns true for cart_removed', () {
        expect(TestableEventValidator.isValidEventType('cart_removed'), true);
      });

      test('returns true for favorite_added', () {
        expect(TestableEventValidator.isValidEventType('favorite_added'), true);
      });

      test('returns true for favorite_removed', () {
        expect(TestableEventValidator.isValidEventType('favorite_removed'), true);
      });

      test('returns false for invalid type', () {
        expect(TestableEventValidator.isValidEventType('unknown'), false);
        expect(TestableEventValidator.isValidEventType('purchase'), false);
      });
    });
  });

  // ============================================================================
  // EVENT BUILDER TESTS
  // ============================================================================
  group('TestableEventBuilder', () {
    group('buildEvent', () {
      test('builds event with required fields', () {
        final event = TestableEventBuilder.buildEvent(
          eventType: 'cart_added',
          productId: 'prod123',
        );

        expect(event['type'], 'cart_added');
        expect(event['productId'], 'prod123');
        expect(event.containsKey('shopId'), false);
      });

      test('includes shopId when provided', () {
        final event = TestableEventBuilder.buildEvent(
          eventType: 'cart_added',
          productId: 'prod123',
          shopId: 'shop456',
        );

        expect(event['shopId'], 'shop456');
      });

      test('excludes shopId when null', () {
        final event = TestableEventBuilder.buildEvent(
          eventType: 'cart_added',
          productId: 'prod123',
          shopId: null,
        );

        expect(event.containsKey('shopId'), false);
      });
    });

    group('convenience methods', () {
      test('buildCartAdded sets correct type', () {
        final event = TestableEventBuilder.buildCartAdded(productId: 'p1');
        expect(event['type'], 'cart_added');
      });

      test('buildCartRemoved sets correct type', () {
        final event = TestableEventBuilder.buildCartRemoved(productId: 'p1');
        expect(event['type'], 'cart_removed');
      });

      test('buildFavoriteAdded sets correct type', () {
        final event = TestableEventBuilder.buildFavoriteAdded(productId: 'p1');
        expect(event['type'], 'favorite_added');
      });

      test('buildFavoriteRemoved sets correct type', () {
        final event = TestableEventBuilder.buildFavoriteRemoved(productId: 'p1');
        expect(event['type'], 'favorite_removed');
      });
    });
  });

  // ============================================================================
  // BATCH EVENT BUILDER TESTS
  // ============================================================================
  group('TestableBatchEventBuilder', () {
    group('buildBatchCartRemovals', () {
      test('builds events for all product IDs', () {
        final events = TestableBatchEventBuilder.buildBatchCartRemovals(
          productIds: ['p1', 'p2', 'p3'],
          shopIds: {'p1': 'shop1', 'p2': 'shop2', 'p3': null},
        );

        expect(events.length, 3);
        expect(events.every((e) => e['type'] == 'cart_removed'), true);
      });

      test('includes shopId only when not null', () {
        final events = TestableBatchEventBuilder.buildBatchCartRemovals(
          productIds: ['p1', 'p2'],
          shopIds: {'p1': 'shop1', 'p2': null},
        );

        expect(events[0]['shopId'], 'shop1');
        expect(events[1].containsKey('shopId'), false);
      });

      test('handles missing shopId entries', () {
        final events = TestableBatchEventBuilder.buildBatchCartRemovals(
          productIds: ['p1', 'p2'],
          shopIds: {'p1': 'shop1'}, // p2 not in map
        );

        expect(events[0]['shopId'], 'shop1');
        expect(events[1].containsKey('shopId'), false);
      });
    });

    group('buildBatchFavoriteRemovals', () {
      test('builds events with favorite_removed type', () {
        final events = TestableBatchEventBuilder.buildBatchFavoriteRemovals(
          productIds: ['p1', 'p2'],
          shopIds: {},
        );

        expect(events.length, 2);
        expect(events.every((e) => e['type'] == 'favorite_removed'), true);
      });
    });

    group('buildBatchEvents', () {
      test('uses provided event type', () {
        final events = TestableBatchEventBuilder.buildBatchEvents(
          eventType: 'cart_added',
          productIds: ['p1'],
          shopIds: {},
        );

        expect(events[0]['type'], 'cart_added');
      });
    });
  });

  // ============================================================================
  // METRICS PAYLOAD TESTS
  // ============================================================================
  group('TestableMetricsPayload', () {
    group('build', () {
      test('creates correct structure', () {
        final payload = TestableMetricsPayload.build(
          batchId: 'batch_123',
          events: [
            {'type': 'cart_added', 'productId': 'p1'},
          ],
        );

        expect(payload['batchId'], 'batch_123');
        expect(payload['events'], isA<List>());
        expect(payload['events'].length, 1);
      });
    });

    group('isValid', () {
      test('returns true for valid payload', () {
        final payload = {
          'batchId': 'batch_123',
          'events': [
            {'type': 'cart_added', 'productId': 'p1'},
          ],
        };
        expect(TestableMetricsPayload.isValid(payload), true);
      });

      test('returns false for missing batchId', () {
        final payload = {
          'events': [{'type': 'cart_added', 'productId': 'p1'}],
        };
        expect(TestableMetricsPayload.isValid(payload), false);
      });

      test('returns false for empty batchId', () {
        final payload = {
          'batchId': '',
          'events': [{'type': 'cart_added', 'productId': 'p1'}],
        };
        expect(TestableMetricsPayload.isValid(payload), false);
      });

      test('returns false for missing events', () {
        final payload = {'batchId': 'batch_123'};
        expect(TestableMetricsPayload.isValid(payload), false);
      });

      test('returns false for empty events', () {
        final payload = {
          'batchId': 'batch_123',
          'events': [],
        };
        expect(TestableMetricsPayload.isValid(payload), false);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('user clears entire cart - batch removal', () {
      final productIds = ['nike_shoes', 'adidas_shirt', 'puma_jacket'];
      final shopIds = {
        'nike_shoes': 'nike_store',
        'adidas_shirt': 'adidas_store',
        'puma_jacket': null, // Direct product, no shop
      };

      final events = TestableBatchEventBuilder.buildBatchCartRemovals(
        productIds: productIds,
        shopIds: shopIds,
      );

      expect(events.length, 3);
      expect(events[0]['shopId'], 'nike_store');
      expect(events[1]['shopId'], 'adidas_store');
      expect(events[2].containsKey('shopId'), false);

      // Validate all events
      expect(TestableEventValidator.areAllEventsValid(events), true);
    });

    test('batch ID uniqueness across requests', () {
      final user = 'user123';
      final ids = <String>{};

      // Simulate multiple requests
      for (var i = 0; i < 100; i++) {
        final id = TestableBatchIdGenerator.generate(
          userId: user,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000 + i),
        );
        ids.add(id);
      }

      // All should be unique
      expect(ids.length, 100);
    });

    test('event validation catches malformed events', () {
      final events = [
        {'type': 'cart_added', 'productId': 'p1'}, // Valid
        {'type': 'cart_removed'}, // Missing productId
        {'productId': 'p3'}, // Missing type
      ];

      final invalidEvents = events.where(
        (e) => !TestableEventValidator.isValidEvent(e),
      ).toList();

      expect(invalidEvents.length, 2);
    });

    test('complete payload for Cloud Function', () {
      // User adds item to cart
      final event = TestableEventBuilder.buildCartAdded(
        productId: 'prod_abc123',
        shopId: 'shop_xyz',
      );

      final batchId = TestableBatchIdGenerator.generate(
        userId: 'user_456',
        timestamp: DateTime.now(),
      );

      final payload = TestableMetricsPayload.build(
        batchId: batchId,
        events: [event],
      );

      // Validate complete payload
      expect(TestableMetricsPayload.isValid(payload), true);
      expect(TestableBatchIdGenerator.isValid(payload['batchId']), true);
      expect(TestableEventValidator.isValidEvent(payload['events'][0]), true);
    });

    test('shopId conditional inclusion saves bandwidth', () {
      // Some products are from shops, some are direct
      final event1 = TestableEventBuilder.buildCartAdded(
        productId: 'p1',
        shopId: 'shop1',
      );
      final event2 = TestableEventBuilder.buildCartAdded(
        productId: 'p2',
        shopId: null,
      );

      // event1 has 3 keys, event2 has 2 keys
      expect(event1.keys.length, 3);
      expect(event2.keys.length, 2);
    });
  });
}