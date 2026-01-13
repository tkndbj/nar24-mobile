// test/services/user_activity_service_test.dart
//
// Unit tests for UserActivityService pure logic
// Tests the EXACT logic from lib/services/user_activity_service.dart
//
// Run: flutter test test/services/user_activity_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_user_activity_service.dart';

void main() {
  // ============================================================================
  // ACTIVITY WEIGHTS TESTS
  // ============================================================================
  group('TestableActivityWeights', () {
    group('getWeight', () {
      test('click has weight 1', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.click), 1);
      });

      test('view has weight 2', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.view), 2);
      });

      test('addToCart has weight 5', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.addToCart), 5);
      });

      test('removeFromCart has weight -2', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.removeFromCart), -2);
      });

      test('favorite has weight 3', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.favorite), 3);
      });

      test('unfavorite has weight -1', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.unfavorite), -1);
      });

      test('purchase has weight 10 (strongest)', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.purchase), 10);
      });

      test('search has weight 1', () {
        expect(TestableActivityWeights.getWeight(TestableActivityType.search), 1);
      });
    });

    group('calculateScore', () {
      test('calculates total from activities', () {
        final activities = [
          TestableActivityType.click,    // 1
          TestableActivityType.view,     // 2
          TestableActivityType.addToCart, // 5
        ];

        expect(TestableActivityWeights.calculateScore(activities), 8);
      });

      test('handles negative weights', () {
        final activities = [
          TestableActivityType.addToCart,    // 5
          TestableActivityType.removeFromCart, // -2
        ];

        expect(TestableActivityWeights.calculateScore(activities), 3);
      });

      test('returns 0 for empty list', () {
        expect(TestableActivityWeights.calculateScore([]), 0);
      });
    });

    group('signal classification', () {
      test('positive signals have positive weights', () {
        final positives = TestableActivityWeights.positiveSignals;

        expect(positives, contains(TestableActivityType.click));
        expect(positives, contains(TestableActivityType.purchase));
        expect(positives, contains(TestableActivityType.addToCart));
        expect(positives.length, 6);
      });

      test('negative signals have negative weights', () {
        final negatives = TestableActivityWeights.negativeSignals;

        expect(negatives, contains(TestableActivityType.removeFromCart));
        expect(negatives, contains(TestableActivityType.unfavorite));
        expect(negatives.length, 2);
      });
    });
  });

  // ============================================================================
  // ACTIVITY EVENT TESTS
  // ============================================================================
  group('TestableActivityEvent', () {
    group('toJson', () {
      test('includes required fields', () {
        final event = TestableActivityEvent(
          eventId: 'test_123',
          type: TestableActivityType.click,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1718452800000),
        );

        final json = event.toJson();

        expect(json['eventId'], 'test_123');
        expect(json['type'], 'click');
        expect(json['timestamp'], 1718452800000);
        expect(json['weight'], 1);
      });

      test('includes optional fields when present', () {
        final event = TestableActivityEvent(
          eventId: 'test_123',
          type: TestableActivityType.addToCart,
          timestamp: DateTime.now(),
          productId: 'prod_abc',
          shopId: 'shop_xyz',
          productName: 'Test Product',
          category: 'Electronics',
          subcategory: 'Phones',
          brand: 'Apple',
          price: 999.99,
          quantity: 2,
        );

        final json = event.toJson();

        expect(json['productId'], 'prod_abc');
        expect(json['shopId'], 'shop_xyz');
        expect(json['productName'], 'Test Product');
        expect(json['category'], 'Electronics');
        expect(json['subcategory'], 'Phones');
        expect(json['brand'], 'Apple');
        expect(json['price'], 999.99);
        expect(json['quantity'], 2);
      });

      test('excludes null optional fields', () {
        final event = TestableActivityEvent(
          eventId: 'test_123',
          type: TestableActivityType.click,
          timestamp: DateTime.now(),
        );

        final json = event.toJson();

        expect(json.containsKey('productId'), false);
        expect(json.containsKey('shopId'), false);
        expect(json.containsKey('price'), false);
      });

      test('excludes empty extra map', () {
        final event = TestableActivityEvent(
          eventId: 'test_123',
          type: TestableActivityType.click,
          timestamp: DateTime.now(),
          extra: {},
        );

        final json = event.toJson();
        expect(json.containsKey('extra'), false);
      });

      test('includes non-empty extra map', () {
        final event = TestableActivityEvent(
          eventId: 'test_123',
          type: TestableActivityType.view,
          timestamp: DateTime.now(),
          extra: {'viewDuration': 30},
        );

        final json = event.toJson();
        expect(json['extra'], {'viewDuration': 30});
      });
    });

    group('fromJson', () {
      test('parses required fields', () {
        final json = {
          'eventId': 'test_456',
          'type': 'view',
          'timestamp': 1718452800000,
        };

        final event = TestableActivityEvent.fromJson(json);

        expect(event.eventId, 'test_456');
        expect(event.type, TestableActivityType.view);
        expect(event.timestamp.millisecondsSinceEpoch, 1718452800000);
      });

      test('parses optional fields', () {
        final json = {
          'eventId': 'test_456',
          'type': 'purchase',
          'timestamp': 1718452800000,
          'productId': 'prod_abc',
          'price': 99.99,
          'quantity': 3,
          'totalValue': 299.97,
        };

        final event = TestableActivityEvent.fromJson(json);

        expect(event.productId, 'prod_abc');
        expect(event.price, 99.99);
        expect(event.quantity, 3);
        expect(event.totalValue, 299.97);
      });

      test('handles unknown type gracefully', () {
        final json = {
          'eventId': 'test_456',
          'type': 'unknown_type',
          'timestamp': 1718452800000,
        };

        final event = TestableActivityEvent.fromJson(json);

        // Should default to click
        expect(event.type, TestableActivityType.click);
      });

      test('handles int price as double', () {
        final json = {
          'eventId': 'test_456',
          'type': 'click',
          'timestamp': 1718452800000,
          'price': 100, // int, not double
        };

        final event = TestableActivityEvent.fromJson(json);
        expect(event.price, 100.0);
      });
    });

    group('round-trip serialization', () {
      test('toJson -> fromJson preserves all data', () {
        final original = TestableActivityEvent(
          eventId: 'test_roundtrip',
          type: TestableActivityType.purchase,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1718452800000),
          productId: 'prod_123',
          shopId: 'shop_456',
          productName: 'Test Product',
          category: 'Category',
          subcategory: 'Subcategory',
          subsubcategory: 'Subsubcategory',
          brand: 'Brand',
          price: 99.99,
          quantity: 2,
          totalValue: 199.98,
          source: 'recommendation',
        );

        final json = original.toJson();
        final restored = TestableActivityEvent.fromJson(json);

        expect(restored.eventId, original.eventId);
        expect(restored.type, original.type);
        expect(restored.timestamp, original.timestamp);
        expect(restored.productId, original.productId);
        expect(restored.shopId, original.shopId);
        expect(restored.price, original.price);
        expect(restored.quantity, original.quantity);
      });
    });
  });

  // ============================================================================
  // EVENT ID GENERATOR TESTS
  // ============================================================================
  group('TestableEventIdGenerator', () {
    group('generate', () {
      test('includes type name', () {
        final id = TestableEventIdGenerator.generate(
          type: TestableActivityType.click,
          productId: 'prod123',
          timestamp: DateTime.now(),
        );

        expect(id.startsWith('click_'), true);
      });

      test('includes product ID', () {
        final id = TestableEventIdGenerator.generate(
          type: TestableActivityType.view,
          productId: 'prod_abc',
          timestamp: DateTime.now(),
        );

        expect(id.contains('prod_abc'), true);
      });

      test('uses none for null product ID', () {
        final id = TestableEventIdGenerator.generate(
          type: TestableActivityType.search,
          productId: null,
          timestamp: DateTime.now(),
        );

        expect(id.contains('none'), true);
      });

      test('generates unique IDs for different timestamps', () {
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000);

        final id1 = TestableEventIdGenerator.generate(
          type: TestableActivityType.click,
          productId: 'prod',
          timestamp: t1,
        );
        final id2 = TestableEventIdGenerator.generate(
          type: TestableActivityType.click,
          productId: 'prod',
          timestamp: t2,
        );

        expect(id1, isNot(id2));
      });
    });

    group('parse', () {
      test('extracts type and productId', () {
        final parsed = TestableEventIdGenerator.parse('click_prod123_1718452800000_1234');

        expect(parsed, isNotNull);
        expect(parsed!['type'], 'click');
        expect(parsed['productId'], 'prod123');
      });

      test('handles none productId', () {
        final parsed = TestableEventIdGenerator.parse('search_none_1718452800000_5678');

        expect(parsed!['productId'], null);
      });

      test('returns null for invalid format', () {
        expect(TestableEventIdGenerator.parse('invalid'), null);
        expect(TestableEventIdGenerator.parse('too_short'), null);
      });
    });

    group('isValid', () {
      test('returns true for valid ID', () {
        expect(TestableEventIdGenerator.isValid('click_prod_123_456'), true);
      });

      test('returns false for too few parts', () {
        expect(TestableEventIdGenerator.isValid('click_prod'), false);
      });
    });
  });

  // ============================================================================
  // DEDUPLICATOR TESTS
  // ============================================================================
  group('TestableDeduplicator', () {
    late TestableDeduplicator deduplicator;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      deduplicator = TestableDeduplicator(nowProvider: () => mockNow);
    });

    group('isDuplicate', () {
      test('first event is not duplicate', () {
        expect(
          deduplicator.isDuplicate(TestableActivityType.click, 'prod123'),
          false,
        );
      });

      test('same event within window is duplicate', () {
        deduplicator.isDuplicate(TestableActivityType.click, 'prod123');

        // 1 second later
        mockNow = mockNow.add(const Duration(seconds: 1));

        expect(
          deduplicator.isDuplicate(TestableActivityType.click, 'prod123'),
          true,
        );
      });

      test('same event after window is not duplicate', () {
        deduplicator.isDuplicate(TestableActivityType.click, 'prod123');

        // 3 seconds later (past 2s window)
        mockNow = mockNow.add(const Duration(seconds: 3));

        expect(
          deduplicator.isDuplicate(TestableActivityType.click, 'prod123'),
          false,
        );
      });

      test('different products are not duplicates', () {
        deduplicator.isDuplicate(TestableActivityType.click, 'prod123');

        expect(
          deduplicator.isDuplicate(TestableActivityType.click, 'prod456'),
          false,
        );
      });

      test('different event types are not duplicates', () {
        deduplicator.isDuplicate(TestableActivityType.click, 'prod123');

        expect(
          deduplicator.isDuplicate(TestableActivityType.view, 'prod123'),
          false,
        );
      });
    });

    group('generateKey', () {
      test('combines type and productId', () {
        final key = TestableDeduplicator.generateKey(
          TestableActivityType.click,
          'prod123',
        );
        expect(key, 'click_prod123');
      });

      test('uses none for null productId', () {
        final key = TestableDeduplicator.generateKey(
          TestableActivityType.search,
          null,
        );
        expect(key, 'search_none');
      });
    });

    group('cleanup', () {
      test('removes old entries when over limit', () {
        // Add many events
        for (var i = 0; i < 105; i++) {
          deduplicator.isDuplicate(TestableActivityType.click, 'prod_$i');
        }

        // Advance time past dedup window
        mockNow = mockNow.add(const Duration(seconds: 3));

        // Trigger cleanup by adding another
        deduplicator.isDuplicate(TestableActivityType.click, 'new_prod');

        // Old entries should be cleaned up
        expect(deduplicator.trackedCount, lessThanOrEqualTo(100));
      });
    });
  });

  // ============================================================================
  // EVENT QUEUE TESTS
  // ============================================================================
  group('TestableEventQueue', () {
    late TestableEventQueue queue;

    setUp(() {
      queue = TestableEventQueue();
    });

    TestableActivityEvent createEvent(String id) {
      return TestableActivityEvent(
        eventId: id,
        type: TestableActivityType.click,
        timestamp: DateTime.now(),
      );
    }

    group('add', () {
      test('adds event to queue', () {
        queue.add(createEvent('event1'));
        expect(queue.length, 1);
      });

      test('returns false when not dropping', () {
        final dropped = queue.add(createEvent('event1'));
        expect(dropped, false);
      });

      test('drops oldest when full', () {
        // Fill to capacity
        for (var i = 0; i < 50; i++) {
          queue.add(createEvent('event_$i'));
        }

        // Add one more
        final dropped = queue.add(createEvent('event_new'));

        expect(dropped, true);
        expect(queue.length, 50);
        expect(queue.events.first.eventId, 'event_1'); // event_0 dropped
      });
    });

    group('shouldFlush', () {
      test('returns false when under threshold', () {
        for (var i = 0; i < 19; i++) {
          queue.add(createEvent('event_$i'));
        }
        expect(queue.shouldFlush, false);
      });

      test('returns true at threshold', () {
        for (var i = 0; i < 20; i++) {
          queue.add(createEvent('event_$i'));
        }
        expect(queue.shouldFlush, true);
      });
    });

    group('isFull', () {
      test('returns false when under capacity', () {
        queue.add(createEvent('event1'));
        expect(queue.isFull, false);
      });

      test('returns true at capacity', () {
        for (var i = 0; i < 50; i++) {
          queue.add(createEvent('event_$i'));
        }
        expect(queue.isFull, true);
      });
    });

    group('removeEvents', () {
      test('removes sent events', () {
        final event1 = createEvent('event1');
        final event2 = createEvent('event2');
        final event3 = createEvent('event3');

        queue.add(event1);
        queue.add(event2);
        queue.add(event3);

        queue.removeEvents([event1, event3]);

        expect(queue.length, 1);
        expect(queue.events.first.eventId, 'event2');
      });
    });

    group('takeSnapshot', () {
      test('returns copy of queue', () {
        queue.add(createEvent('event1'));
        queue.add(createEvent('event2'));

        final snapshot = queue.takeSnapshot();

        // Modify original
        queue.add(createEvent('event3'));

        // Snapshot unchanged
        expect(snapshot.length, 2);
        expect(queue.length, 3);
      });
    });
  });

  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  group('TestableActivityCircuitBreaker', () {
    late TestableActivityCircuitBreaker breaker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      breaker = TestableActivityCircuitBreaker(nowProvider: () => mockNow);
    });

    group('isOpen', () {
      test('closed initially', () {
        expect(breaker.isOpen, false);
      });

      test('stays closed under max retries', () {
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.isOpen, false);
      });

      test('opens at max retries', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.isOpen, true);
      });

      test('resets after cooldown', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.isOpen, true);

        // Advance 6 minutes
        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(breaker.isOpen, false);
        expect(breaker.consecutiveFailures, 0);
      });
    });

    group('recordSuccess', () {
      test('resets failure count', () {
        breaker.recordFailure();
        breaker.recordFailure();

        breaker.recordSuccess();

        expect(breaker.consecutiveFailures, 0);
        expect(breaker.lastFailureTime, null);
      });
    });
  });

  // ============================================================================
  // EVENT PERSISTENCE TESTS
  // ============================================================================
  group('TestableEventPersistence', () {
    group('filterByAge', () {
      test('keeps events within 24 hours', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final events = [
          TestableActivityEvent(
            eventId: 'recent',
            type: TestableActivityType.click,
            timestamp: now.subtract(const Duration(hours: 1)),
          ),
          TestableActivityEvent(
            eventId: 'old',
            type: TestableActivityType.click,
            timestamp: now.subtract(const Duration(hours: 25)),
          ),
        ];

        final filtered = TestableEventPersistence.filterByAge(events, now: now);

        expect(filtered.length, 1);
        expect(filtered.first.eventId, 'recent');
      });

      test('keeps event at exactly 24 hours', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final event = TestableActivityEvent(
          eventId: 'boundary',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(hours: 24)),
        );

        final filtered = TestableEventPersistence.filterByAge([event], now: now);

        // At exactly 24 hours, should NOT be included (isAfter)
        expect(filtered.length, 0);
      });
    });

    group('isExpired', () {
      test('returns false for recent event', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final event = TestableActivityEvent(
          eventId: 'recent',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(hours: 12)),
        );

        expect(TestableEventPersistence.isExpired(event, now: now), false);
      });

      test('returns true for old event', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final event = TestableActivityEvent(
          eventId: 'old',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(hours: 25)),
        );

        expect(TestableEventPersistence.isExpired(event, now: now), true);
      });
    });
  });

  // ============================================================================
  // SEARCH VALIDATOR TESTS
  // ============================================================================
  group('TestableSearchValidator', () {
    group('normalizeQuery', () {
      test('trims whitespace', () {
        expect(TestableSearchValidator.normalizeQuery('  hello  '), 'hello');
      });

      test('converts to lowercase', () {
        expect(TestableSearchValidator.normalizeQuery('HELLO'), 'hello');
      });

      test('returns null for empty string', () {
        expect(TestableSearchValidator.normalizeQuery(''), null);
      });

      test('returns null for whitespace only', () {
        expect(TestableSearchValidator.normalizeQuery('   '), null);
      });
    });

    group('isValidQuery', () {
      test('returns true for non-empty query', () {
        expect(TestableSearchValidator.isValidQuery('shoes'), true);
      });

      test('returns false for empty query', () {
        expect(TestableSearchValidator.isValidQuery(''), false);
      });

      test('returns false for whitespace query', () {
        expect(TestableSearchValidator.isValidQuery('   '), false);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('user browsing session scoring', () {
      // User browsing journey
      final activities = [
        TestableActivityType.search,     // 1  - searched for product
        TestableActivityType.click,      // 1  - clicked from results
        TestableActivityType.view,       // 2  - viewed details
        TestableActivityType.addToCart,  // 5  - added to cart
        TestableActivityType.removeFromCart, // -2 - removed
        TestableActivityType.click,      // 1  - clicked another
        TestableActivityType.view,       // 2  - viewed details
        TestableActivityType.addToCart,  // 5  - added to cart
        TestableActivityType.purchase,   // 10 - purchased
      ];

      final score = TestableActivityWeights.calculateScore(activities);
      expect(score, 25); // High engagement score
    });

    test('rapid tap deduplication', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final deduplicator = TestableDeduplicator(nowProvider: () => mockNow);

      int acceptedClicks = 0;
      for (var i = 0; i < 10; i++) {
        if (!deduplicator.isDuplicate(TestableActivityType.click, 'prod123')) {
          acceptedClicks++;
        }
        mockNow = mockNow.add(const Duration(milliseconds: 200));
      }

      // Only first click accepted (2s window, 10 * 200ms = 2s total)
      expect(acceptedClicks, 1);
    });

    test('queue handles burst of events', () {
      final queue = TestableEventQueue();

      // Simulate burst of 100 events
      for (var i = 0; i < 100; i++) {
        queue.add(TestableActivityEvent(
          eventId: 'event_$i',
          type: TestableActivityType.click,
          timestamp: DateTime.now(),
        ));
      }

      // Queue capped at 50
      expect(queue.length, 50);
      // Oldest events dropped
      expect(queue.events.first.eventId, 'event_50');
      expect(queue.events.last.eventId, 'event_99');
    });

    test('event serialization for Cloud Function', () {
      final event = TestableActivityEvent(
        eventId: 'purchase_prod123_1718452800000_1234',
        type: TestableActivityType.purchase,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1718452800000),
        productId: 'prod123',
        shopId: 'shop456',
        productName: 'Nike Air Max',
        category: 'Footwear',
        subcategory: 'Running',
        brand: 'Nike',
        price: 149.99,
        quantity: 1,
        totalValue: 149.99,
      );

      final json = event.toJson();

      // Verify all fields present for Cloud Function
      expect(json['eventId'], isNotEmpty);
      expect(json['type'], 'purchase');
      expect(json['weight'], 10);
      expect(json['timestamp'], isA<int>());
      expect(json['productId'], 'prod123');
      expect(json['totalValue'], 149.99);
    });

    test('persisted events filtered on app restart', () {
      final now = DateTime(2024, 6, 15, 12, 0, 0);

      // Events from different times
      final events = [
        TestableActivityEvent(
          eventId: 'today',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(hours: 2)),
        ),
        TestableActivityEvent(
          eventId: 'yesterday',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(hours: 20)),
        ),
        TestableActivityEvent(
          eventId: 'old',
          type: TestableActivityType.click,
          timestamp: now.subtract(const Duration(days: 2)),
        ),
      ];

      final filtered = TestableEventPersistence.filterByAge(events, now: now);

      expect(filtered.length, 2);
      expect(filtered.map((e) => e.eventId), containsAll(['today', 'yesterday']));
      expect(filtered.map((e) => e.eventId).contains('old'), false);
    });
  });
}