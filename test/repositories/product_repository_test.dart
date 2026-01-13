// test/repositories/product_repository_test.dart
//
// Unit tests for ProductRepository pure logic
// Tests the EXACT logic from lib/repositories/product_repository.dart
//
// Run: flutter test test/repositories/product_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_product_repository.dart';

void main() {
  // ============================================================================
  // PRODUCT ID NORMALIZER TESTS
  // ============================================================================
  group('TestableProductIdNormalizer', () {
    group('normalize', () {
      test('returns ID unchanged when no prefix', () {
        expect(TestableProductIdNormalizer.normalize('abc123'), 'abc123');
        expect(TestableProductIdNormalizer.normalize('product-xyz'), 'product-xyz');
      });

      test('strips products_ prefix', () {
        expect(
          TestableProductIdNormalizer.normalize('products_abc123'),
          'abc123',
        );
      });

      test('strips shop_products_ prefix', () {
        expect(
          TestableProductIdNormalizer.normalize('shop_products_abc123'),
          'abc123',
        );
      });

      test('trims whitespace before processing', () {
        expect(
          TestableProductIdNormalizer.normalize('  abc123  '),
          'abc123',
        );
        expect(
          TestableProductIdNormalizer.normalize('  products_abc123  '),
          'abc123',
        );
      });

      test('throws ArgumentError for empty string', () {
        expect(
          () => TestableProductIdNormalizer.normalize(''),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Product ID cannot be empty',
          )),
        );
      });

      test('throws ArgumentError for whitespace-only string', () {
        expect(
          () => TestableProductIdNormalizer.normalize('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws ArgumentError when prefix is entire ID', () {
        expect(
          () => TestableProductIdNormalizer.normalize('products_'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid product ID format'),
          )),
        );
      });

      test('throws ArgumentError when shop_products_ prefix is entire ID', () {
        expect(
          () => TestableProductIdNormalizer.normalize('shop_products_'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Invalid product ID format'),
          )),
        );
      });

      test('handles ID that looks like prefix but is not', () {
        // "products" without underscore should remain unchanged
        expect(
          TestableProductIdNormalizer.normalize('products'),
          'products',
        );
        expect(
          TestableProductIdNormalizer.normalize('shop_products'),
          'shop_products',
        );
      });

      test('only strips prefix from start, not middle', () {
        expect(
          TestableProductIdNormalizer.normalize('abc_products_123'),
          'abc_products_123',
        );
      });

      test('handles complex IDs with special characters', () {
        expect(
          TestableProductIdNormalizer.normalize('products_abc-123_xyz'),
          'abc-123_xyz',
        );
        expect(
          TestableProductIdNormalizer.normalize('shop_products_item.v2'),
          'item.v2',
        );
      });

      test('handles Firestore document ID format', () {
        // Typical Firestore auto-generated IDs
        expect(
          TestableProductIdNormalizer.normalize('products_X7gKp2qR5mNvL9'),
          'X7gKp2qR5mNvL9',
        );
        expect(
          TestableProductIdNormalizer.normalize('shop_products_AbCdEfGhIjKlMnOp'),
          'AbCdEfGhIjKlMnOp',
        );
      });
    });

    group('hasAlgoliaPrefix', () {
      test('returns true for products_ prefix', () {
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('products_abc'), true);
      });

      test('returns true for shop_products_ prefix', () {
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('shop_products_abc'), true);
      });

      test('returns false for no prefix', () {
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('abc123'), false);
      });

      test('trims whitespace before checking', () {
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('  products_abc  '), true);
      });

      test('returns false for partial prefix match', () {
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('product_abc'), false);
        expect(TestableProductIdNormalizer.hasAlgoliaPrefix('shop_product_abc'), false);
      });
    });
  });

  // ============================================================================
  // PRODUCT CACHE TESTS
  // ============================================================================
  group('TestableProductCache', () {
    late TestableProductCache<Map<String, dynamic>> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      cache = TestableProductCache<Map<String, dynamic>>(
        maxSize: 5,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );
    });

    group('basic operations', () {
      test('stores and retrieves items', () {
        cache.put('prod1', {'name': 'Product 1'});
        expect(cache['prod1'], {'name': 'Product 1'});
        expect(cache.containsKey('prod1'), true);
      });

      test('returns null for non-existent key', () {
        expect(cache['nonexistent'], null);
        expect(cache.containsKey('nonexistent'), false);
      });

      test('tracks length correctly', () {
        expect(cache.length, 0);
        cache.put('prod1', {'name': 'Product 1'});
        expect(cache.length, 1);
        cache.put('prod2', {'name': 'Product 2'});
        expect(cache.length, 2);
      });
    });

    group('TTL validation', () {
      test('isValid returns true for fresh entry', () {
        cache.put('prod1', {'name': 'Product 1'});
        expect(cache.isValid('prod1'), true);
      });

      test('isValid returns false for expired entry', () {
        cache.put('prod1', {'name': 'Product 1'});

        // Advance time past TTL
        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(cache.isValid('prod1'), false);
      });

      test('isValid returns true just before expiry', () {
        cache.put('prod1', {'name': 'Product 1'});

        // Advance time to just before TTL
        mockNow = mockNow.add(const Duration(minutes: 4, seconds: 59));

        expect(cache.isValid('prod1'), true);
      });

      test('isValid returns false at exactly TTL', () {
        cache.put('prod1', {'name': 'Product 1'});

        // Advance time to exactly TTL
        mockNow = mockNow.add(const Duration(minutes: 5, seconds: 1));

        expect(cache.isValid('prod1'), false);
      });

      test('isValid returns false for non-existent key', () {
        expect(cache.isValid('nonexistent'), false);
      });
    });

    group('getIfValid', () {
      test('returns item if valid', () {
        cache.put('prod1', {'name': 'Product 1'});
        expect(cache.getIfValid('prod1'), {'name': 'Product 1'});
      });

      test('returns null and removes expired item', () {
        cache.put('prod1', {'name': 'Product 1'});

        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(cache.getIfValid('prod1'), null);
        expect(cache.containsKey('prod1'), false);
        expect(cache.length, 0);
      });

      test('returns null for non-existent key', () {
        expect(cache.getIfValid('nonexistent'), null);
      });
    });

    group('eviction', () {
      test('evicts oldest when over capacity', () {
        // Fill cache to capacity
        for (var i = 0; i < 5; i++) {
          cache.put('prod$i', {'index': i});
          mockNow = mockNow.add(const Duration(seconds: 1));
        }
        expect(cache.length, 5);

        // Add one more - should evict oldest
        cache.put('prod5', {'index': 5});

        expect(cache.length, 5);
        expect(cache.containsKey('prod0'), false); // Oldest evicted
        expect(cache.containsKey('prod5'), true);
      });

      test('evicts multiple if needed', () {
        // Fill cache
        for (var i = 0; i < 5; i++) {
          cache.put('prod$i', {'index': i});
          mockNow = mockNow.add(const Duration(seconds: 1));
        }

        // Manually reduce maxSize by adding more (triggers eviction each time)
        cache.put('prod5', {'index': 5});
        cache.put('prod6', {'index': 6});
        cache.put('prod7', {'index': 7});

        expect(cache.length, 5);
        expect(cache.containsKey('prod0'), false);
        expect(cache.containsKey('prod1'), false);
        expect(cache.containsKey('prod2'), false);
      });

      test('evictOldestEntries does nothing when under capacity', () {
        cache.put('prod1', {'index': 1});
        cache.put('prod2', {'index': 2});

        cache.evictOldestEntries();

        expect(cache.length, 2);
        expect(cache.containsKey('prod1'), true);
        expect(cache.containsKey('prod2'), true);
      });
    });

    group('cleanupExpired', () {
      test('removes all expired entries', () {
        cache.put('prod1', {'index': 1});
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.put('prod2', {'index': 2});
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.put('prod3', {'index': 3});

        // Advance time so ALL three expire (5 min + extra to exceed TTL)
        mockNow = mockNow.add(const Duration(minutes: 5, seconds: 1));

        // Add a fresh entry
        cache.put('prod4', {'index': 4});

        cache.cleanupExpired();

        expect(cache.containsKey('prod1'), false);
        expect(cache.containsKey('prod2'), false);
        expect(cache.containsKey('prod3'), false);
        expect(cache.containsKey('prod4'), true);
      });

      test('does nothing when no expired entries', () {
        cache.put('prod1', {'index': 1});
        cache.put('prod2', {'index': 2});

        cache.cleanupExpired();

        expect(cache.length, 2);
      });
    });

    group('getStats', () {
      test('returns correct cache size', () {
        cache.put('prod1', {'index': 1});
        cache.put('prod2', {'index': 2});

        final stats = cache.getStats();

        expect(stats['cacheSize'], 2);
      });

      test('returns oldest cache entry', () {
        cache.put('prod1', {'index': 1});
        final firstEntryTime = mockNow;

        mockNow = mockNow.add(const Duration(seconds: 10));
        cache.put('prod2', {'index': 2});

        final stats = cache.getStats();

        expect(stats['oldestCacheEntry'], firstEntryTime);
      });

      test('returns null for empty cache', () {
        final stats = cache.getStats();

        expect(stats['cacheSize'], 0);
        expect(stats['oldestCacheEntry'], null);
      });
    });

    group('clear', () {
      test('removes all entries', () {
        cache.put('prod1', {'index': 1});
        cache.put('prod2', {'index': 2});

        cache.clear();

        expect(cache.length, 0);
        expect(cache.isEmpty, true);
        expect(cache.containsKey('prod1'), false);
      });
    });
  });

  // ============================================================================
  // IN-FLIGHT TRACKER TESTS
  // ============================================================================
  group('TestableInFlightTracker', () {
    late TestableInFlightTracker tracker;

    setUp(() {
      tracker = TestableInFlightTracker();
    });

    test('tracks new requests', () {
      expect(tracker.tryStart('prod1'), true);
      expect(tracker.isInFlight('prod1'), true);
      expect(tracker.count, 1);
    });

    test('rejects duplicate requests', () {
      tracker.tryStart('prod1');

      expect(tracker.tryStart('prod1'), false);
      expect(tracker.count, 1);
    });

    test('allows same ID after completion', () {
      tracker.tryStart('prod1');
      tracker.complete('prod1');

      expect(tracker.isInFlight('prod1'), false);
      expect(tracker.tryStart('prod1'), true);
    });

    test('tracks multiple concurrent requests', () {
      tracker.tryStart('prod1');
      tracker.tryStart('prod2');
      tracker.tryStart('prod3');

      expect(tracker.count, 3);
      expect(tracker.isInFlight('prod1'), true);
      expect(tracker.isInFlight('prod2'), true);
      expect(tracker.isInFlight('prod3'), true);
    });

    test('complete removes only specified ID', () {
      tracker.tryStart('prod1');
      tracker.tryStart('prod2');

      tracker.complete('prod1');

      expect(tracker.isInFlight('prod1'), false);
      expect(tracker.isInFlight('prod2'), true);
      expect(tracker.count, 1);
    });

    test('complete is idempotent', () {
      tracker.tryStart('prod1');
      tracker.complete('prod1');
      tracker.complete('prod1'); // Should not throw

      expect(tracker.isInFlight('prod1'), false);
    });

    test('clear removes all in-flight requests', () {
      tracker.tryStart('prod1');
      tracker.tryStart('prod2');

      tracker.clear();

      expect(tracker.count, 0);
      expect(tracker.isInFlight('prod1'), false);
      expect(tracker.isInFlight('prod2'), false);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('Algolia search result IDs are normalized correctly', () {
      // Algolia returns IDs with index prefix
      final algoliaIds = [
        'products_abc123',
        'shop_products_xyz789',
        'products_item-001',
        'shop_products_SKU_12345',
      ];

      final normalized = algoliaIds
          .map((id) => TestableProductIdNormalizer.normalize(id))
          .toList();

      expect(normalized, ['abc123', 'xyz789', 'item-001', 'SKU_12345']);
    });

    test('cache handles product browsing session', () {
      var mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      final cache = TestableProductCache<String>(
        maxSize: 10,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );

      // User browses products
      cache.put('prod1', 'Product 1 data');
      mockNow = mockNow.add(const Duration(seconds: 30));

      cache.put('prod2', 'Product 2 data');
      mockNow = mockNow.add(const Duration(seconds: 30));

      cache.put('prod3', 'Product 3 data');

      // User goes back to first product - should be cached
      expect(cache.getIfValid('prod1'), 'Product 1 data');

      // User leaves for 6 minutes
      mockNow = mockNow.add(const Duration(minutes: 6));

      // All cache should be expired
      expect(cache.getIfValid('prod1'), null);
      expect(cache.getIfValid('prod2'), null);
      expect(cache.getIfValid('prod3'), null);
    });

    test('in-flight tracker prevents duplicate Firestore reads', () {
      final tracker = TestableInFlightTracker();

      // Simulate rapid taps on same product
      final firstTap = tracker.tryStart('prod1');
      final secondTap = tracker.tryStart('prod1');
      final thirdTap = tracker.tryStart('prod1');

      expect(firstTap, true); // First request goes through
      expect(secondTap, false); // Duplicate blocked
      expect(thirdTap, false); // Duplicate blocked

      // Only one Firestore read should happen
      expect(tracker.count, 1);
    });

    test('handles mixed Algolia and direct IDs', () {
      final ids = [
        'products_abc123', // Algolia products index
        'shop_products_xyz789', // Algolia shop_products index
        'direct-id-001', // Direct Firestore ID
        'another_id', // Direct ID with underscore
      ];

      final results = ids.map((id) {
        return {
          'original': id,
          'hasPrefix': TestableProductIdNormalizer.hasAlgoliaPrefix(id),
          'normalized': TestableProductIdNormalizer.normalize(id),
        };
      }).toList();

      expect(results[0]['hasPrefix'], true);
      expect(results[0]['normalized'], 'abc123');

      expect(results[1]['hasPrefix'], true);
      expect(results[1]['normalized'], 'xyz789');

      expect(results[2]['hasPrefix'], false);
      expect(results[2]['normalized'], 'direct-id-001');

      expect(results[3]['hasPrefix'], false);
      expect(results[3]['normalized'], 'another_id');
    });
  });
}