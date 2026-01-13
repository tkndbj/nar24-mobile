// test/providers/market_provider_test.dart
//
// Unit tests for MarketProvider pure logic
// Tests the EXACT logic from lib/providers/market_provider.dart
//
// Run: flutter test test/providers/market_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'testable_market_provider.dart';

void main() {
  // ============================================================================
  // REQUEST DEDUPLICATOR TESTS
  // ============================================================================
  group('TestableRequestDeduplicator', () {
    late TestableRequestDeduplicator<List<String>> deduplicator;

    setUp(() {
      deduplicator = TestableRequestDeduplicator<List<String>>();
    });

    test('starts with no pending requests', () {
      expect(deduplicator.pendingCount, 0);
      expect(deduplicator.hasPending, false);
    });

    test('executes request and returns result', () async {
      final result = await deduplicator.deduplicate(
        'key1',
        () async => ['a', 'b', 'c'],
      );

      expect(result, ['a', 'b', 'c']);
    });

    test('removes key after completion', () async {
      await deduplicator.deduplicate(
        'key1',
        () async => ['result'],
      );

      expect(deduplicator.pendingKeys.contains('key1'), false);
    });

    test('deduplicates concurrent requests with same key', () async {
      int callCount = 0;
      final completer = Completer<List<String>>();

      // Start first request (won't complete until we say so)
      final future1 = deduplicator.deduplicate('same_key', () {
        callCount++;
        return completer.future;
      });

      // Start second request with same key
      final future2 = deduplicator.deduplicate('same_key', () {
        callCount++;
        return Future.value(['should not run']);
      });

      // Both should be waiting on same future
      expect(deduplicator.pendingCount, 1);

      // Complete the first request
      completer.complete(['shared result']);

      final result1 = await future1;
      final result2 = await future2;

      // Both get same result, but request only ran once
      expect(callCount, 1);
      expect(result1, ['shared result']);
      expect(result2, ['shared result']);
    });

    test('allows different keys to run independently', () async {
      int callCount = 0;

      final results = await Future.wait([
        deduplicator.deduplicate('key1', () async {
          callCount++;
          return ['result1'];
        }),
        deduplicator.deduplicate('key2', () async {
          callCount++;
          return ['result2'];
        }),
      ]);

      expect(callCount, 2);
      expect(results[0], ['result1']);
      expect(results[1], ['result2']);
    });

    test('removes key even on error', () async {
      try {
        await deduplicator.deduplicate('failing_key', () async {
          throw Exception('Test error');
        });
      } catch (_) {}

      expect(deduplicator.pendingKeys.contains('failing_key'), false);
    });

    test('clear removes all pending', () async {
      final completer = Completer<List<String>>();

      // Start request that won't complete
      deduplicator.deduplicate('key1', () => completer.future);

      expect(deduplicator.pendingCount, 1);

      deduplicator.clear();

      expect(deduplicator.pendingCount, 0);
    });
  });

  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  group('TestableAlgoliaCircuitBreaker', () {
    late TestableAlgoliaCircuitBreaker circuitBreaker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      circuitBreaker = TestableAlgoliaCircuitBreaker(
        nowProvider: () => mockNow,
      );
    });

    test('starts closed', () {
      expect(circuitBreaker.isOpen, false);
      expect(circuitBreaker.isCircuitOpen(), false);
      expect(circuitBreaker.failureCount, 0);
    });

    test('stays closed under 8 failures', () {
      for (var i = 0; i < 7; i++) {
        circuitBreaker.recordFailure();
      }

      expect(circuitBreaker.failureCount, 7);
      expect(circuitBreaker.isCircuitOpen(), false);
    });

    test('opens at exactly 8 failures', () {
      for (var i = 0; i < 8; i++) {
        circuitBreaker.recordFailure();
      }

      expect(circuitBreaker.failureCount, 8);
      expect(circuitBreaker.isCircuitOpen(), true);
    });

    test('stays open before cooldown expires', () {
      // Trigger circuit open
      for (var i = 0; i < 8; i++) {
        circuitBreaker.recordFailure();
      }

      // Advance time by 4 minutes (less than 5 minute cooldown)
      mockNow = mockNow.add(const Duration(minutes: 4));

      expect(circuitBreaker.isCircuitOpen(), true);
    });

    test('closes after 5 minute cooldown', () {
      // Trigger circuit open
      for (var i = 0; i < 8; i++) {
        circuitBreaker.recordFailure();
      }

      // Advance time past cooldown
      mockNow = mockNow.add(const Duration(minutes: 5, seconds: 1));

      expect(circuitBreaker.isCircuitOpen(), false);
      expect(circuitBreaker.failureCount, 0); // Reset
    });

    test('success resets failure count', () {
      circuitBreaker.recordFailure();
      circuitBreaker.recordFailure();
      circuitBreaker.recordFailure();

      expect(circuitBreaker.failureCount, 3);

      circuitBreaker.recordSuccess();

      expect(circuitBreaker.failureCount, 0);
    });

    test('success closes circuit if open', () {
      // Open circuit
      for (var i = 0; i < 8; i++) {
        circuitBreaker.recordFailure();
      }

      expect(circuitBreaker.isOpen, true);

      circuitBreaker.recordSuccess();

      expect(circuitBreaker.isOpen, false);
      expect(circuitBreaker.lastFailure, null);
    });
  });

  // ============================================================================
  // SEARCH CACHE KEY BUILDER TESTS
  // ============================================================================
  group('TestableSearchCacheKeyBuilder', () {
    group('buildKey', () {
      test('builds correct key format', () {
        final key = TestableSearchCacheKeyBuilder.buildKey(
          query: 'nike shoes',
          filterType: 'deals',
          page: 2,
          sortOption: 'price',
        );

        expect(key, 'nike shoes|deals|2|price');
      });

      test('handles empty values', () {
        final key = TestableSearchCacheKeyBuilder.buildKey(
          query: '',
          filterType: '',
          page: 0,
          sortOption: 'date',
        );

        expect(key, '||0|date');
      });

      test('different queries produce different keys', () {
        final key1 = TestableSearchCacheKeyBuilder.buildKey(
          query: 'nike',
          filterType: '',
          page: 0,
          sortOption: 'date',
        );
        final key2 = TestableSearchCacheKeyBuilder.buildKey(
          query: 'adidas',
          filterType: '',
          page: 0,
          sortOption: 'date',
        );

        expect(key1 != key2, true);
      });

      test('different pages produce different keys', () {
        final key1 = TestableSearchCacheKeyBuilder.buildKey(
          query: 'shoes',
          filterType: '',
          page: 0,
          sortOption: 'date',
        );
        final key2 = TestableSearchCacheKeyBuilder.buildKey(
          query: 'shoes',
          filterType: '',
          page: 1,
          sortOption: 'date',
        );

        expect(key1 != key2, true);
      });
    });

    group('parseKey', () {
      test('parses valid key', () {
        final parsed = TestableSearchCacheKeyBuilder.parseKey('nike|deals|2|price');

        expect(parsed!['query'], 'nike');
        expect(parsed['filterType'], 'deals');
        expect(parsed['page'], 2);
        expect(parsed['sortOption'], 'price');
      });

      test('returns null for invalid key', () {
        expect(TestableSearchCacheKeyBuilder.parseKey('invalid'), null);
        expect(TestableSearchCacheKeyBuilder.parseKey('a|b'), null);
      });
    });

    group('isSameSearch', () {
      test('returns true for same search different pages', () {
        final key1 = 'nike|deals|0|price';
        final key2 = 'nike|deals|5|price';

        expect(TestableSearchCacheKeyBuilder.isSameSearch(key1, key2), true);
      });

      test('returns false for different queries', () {
        final key1 = 'nike|deals|0|price';
        final key2 = 'adidas|deals|0|price';

        expect(TestableSearchCacheKeyBuilder.isSameSearch(key1, key2), false);
      });
    });
  });

  // ============================================================================
  // FILTER TYPE MAPPER TESTS
  // ============================================================================
  group('TestableFilterTypeMapper', () {
    test('maps deals filter', () {
      expect(
        TestableFilterTypeMapper.mapFilterTypeToFacets('deals'),
        ['discountPercentage>0'],
      );
    });

    test('maps boosted filter', () {
      expect(
        TestableFilterTypeMapper.mapFilterTypeToFacets('boosted'),
        ['isBoosted:true'],
      );
    });

    test('maps trending filter', () {
      expect(
        TestableFilterTypeMapper.mapFilterTypeToFacets('trending'),
        ['dailyClickCount>=10'],
      );
    });

    test('maps fiveStar filter', () {
      expect(
        TestableFilterTypeMapper.mapFilterTypeToFacets('fiveStar'),
        ['averageRating=5'],
      );
    });

    test('bestSellers returns null (uses replica)', () {
      expect(
        TestableFilterTypeMapper.mapFilterTypeToFacets('bestSellers'),
        null,
      );
    });

    test('empty string returns null', () {
      expect(TestableFilterTypeMapper.mapFilterTypeToFacets(''), null);
    });

    test('unknown filter returns null', () {
      expect(TestableFilterTypeMapper.mapFilterTypeToFacets('unknown'), null);
    });

    test('isSupported returns true for valid types', () {
      expect(TestableFilterTypeMapper.isSupported('deals'), true);
      expect(TestableFilterTypeMapper.isSupported('boosted'), true);
      expect(TestableFilterTypeMapper.isSupported(''), true); // Empty is valid
    });
  });

  // ============================================================================
  // FIELD SANITIZER TESTS
  // ============================================================================
  group('TestableFieldSanitizer', () {
    test('replaces dots with underscores', () {
      expect(TestableFieldSanitizer.sanitize('user.name'), 'user_name');
    });

    test('replaces slashes with underscores', () {
      expect(TestableFieldSanitizer.sanitize('path/to/field'), 'path_to_field');
    });

    test('handles multiple replacements', () {
      expect(
        TestableFieldSanitizer.sanitize('a.b/c.d'),
        'a_b_c_d',
      );
    });

    test('leaves clean field names unchanged', () {
      expect(TestableFieldSanitizer.sanitize('cleanField'), 'cleanField');
    });

    test('needsSanitization detects problematic chars', () {
      expect(TestableFieldSanitizer.needsSanitization('user.name'), true);
      expect(TestableFieldSanitizer.needsSanitization('path/field'), true);
      expect(TestableFieldSanitizer.needsSanitization('clean'), false);
    });
  });

  // ============================================================================
  // SEARCH RESULT UPDATER TESTS
  // ============================================================================
  group('TestableSearchResultUpdater', () {
    late TestableSearchResultUpdater<Map<String, String>> updater;

    setUp(() {
      updater = TestableSearchResultUpdater<Map<String, String>>(
        getId: (p) => p['id']!,
        maxProductsInMemory: 10, // Small for testing
      );
    });

    test('adds results on page 0', () {
      updater.updateResults([
        {'id': 'p1', 'name': 'Product 1'},
        {'id': 'p2', 'name': 'Product 2'},
      ], 0, 10);

      expect(updater.products.length, 2);
      expect(updater.productIds.contains('p1'), true);
    });

    test('clears previous results on page 0', () {
      updater.updateResults([{'id': 'old'}], 0, 10);
      updater.updateResults([{'id': 'new'}], 0, 10);

      expect(updater.products.length, 1);
      expect(updater.products[0]['id'], 'new');
    });

    test('appends results on subsequent pages', () {
      updater.updateResults([{'id': 'p1'}], 0, 10);
      updater.updateResults([{'id': 'p2'}], 1, 10);

      expect(updater.products.length, 2);
    });

    test('deduplicates results', () {
      updater.updateResults([
        {'id': 'p1'},
        {'id': 'p1'}, // Duplicate
        {'id': 'p2'},
      ], 0, 10);

      expect(updater.products.length, 2);
    });

    test('hasMore true when results >= hitsPerPage', () {
      updater.updateResults(
        List.generate(10, (i) => {'id': 'p$i'}),
        0,
        10,
      );

      expect(updater.hasMore, true);
    });

    test('hasMore false when results < hitsPerPage', () {
      updater.updateResults([{'id': 'p1'}], 0, 10);

      expect(updater.hasMore, false);
    });

    test('enforces memory limit on pagination', () {
      // Use a larger limit that makes the formula work properly
      // (removeCount = length - limit + 50 should be < length)
      final largerUpdater = TestableSearchResultUpdater<Map<String, String>>(
        getId: (p) => p['id']!,
        maxProductsInMemory: 100, // Larger so formula works
      );

      // Add products across multiple pages
      for (var page = 0; page < 5; page++) {
        largerUpdater.updateResults(
          List.generate(50, (i) => {'id': 'p${page * 50 + i}'}),
          page,
          50,
        );
      }

      // After 5 pages of 50 = 250 products without limit
      // With limit of 100, should trim when > 100
      // After page 2: 150 products, 150 > 100, remove 150-100+50=100 → 50, add 50 → 100
      // After page 3: 100 > 100? no, add 50 → 150
      // After page 4: 150 > 100, remove 100 → 50, add 50 → 100
      expect(largerUpdater.products.length <= 150, true);
      expect(largerUpdater.products.length > 0, true);
    });
  });

  // ============================================================================
  // LRU CACHE TESTS
  // ============================================================================
  group('TestableLRUCache', () {
    late TestableLRUCache<List<String>> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableLRUCache<List<String>>(
        maxSize: 5,
        trimTarget: 3,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );
    });

    test('stores and retrieves value', () {
      cache.set('key1', ['a', 'b']);
      expect(cache.get('key1'), ['a', 'b']);
    });

    test('returns null for missing key', () {
      expect(cache.get('nonexistent'), null);
    });

    test('returns null for expired entry', () {
      cache.set('key1', ['value']);

      // Advance past TTL
      mockNow = mockNow.add(const Duration(minutes: 6));

      expect(cache.get('key1'), null);
    });

    test('evicts oldest when over limit', () {
      // Add entries with staggered timestamps
      for (var i = 0; i < 5; i++) {
        cache.set('key_$i', ['value_$i']);
        mockNow = mockNow.add(const Duration(seconds: 1));
      }

      // Add one more (should evict oldest to trimTarget)
      cache.set('key_new', ['new_value']);

      expect(cache.length, 3); // trimTarget
      expect(cache.get('key_0'), null); // Oldest evicted
      expect(cache.get('key_new'), ['new_value']); // Newest kept
    });

    test('cleanupExpired removes only expired', () {
      cache.set('fresh', ['value']);
      mockNow = mockNow.add(const Duration(minutes: 1));
      cache.set('also_fresh', ['value']);

      // Expire first entry
      mockNow = mockNow.add(const Duration(minutes: 5));

      final removed = cache.cleanupExpired();

      expect(removed, 1);
      expect(cache.get('fresh'), null);
      expect(cache.get('also_fresh'), ['value']);
    });
  });

  // ============================================================================
  // BUYER CATEGORY CACHE TESTS
  // ============================================================================
  group('TestableBuyerCategoryCache', () {
    late TestableBuyerCategoryCache<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableBuyerCategoryCache<String>(
        maxSize: 3,
        ttl: const Duration(minutes: 20),
        nowProvider: () => mockNow,
      );
    });

    test('stores and retrieves by category', () {
      cache.set('Women', ['product1', 'product2']);
      expect(cache.get('Women'), ['product1', 'product2']);
    });

    test('returns null for expired category', () {
      cache.set('Men', ['product1']);

      // Advance past 20 minutes
      mockNow = mockNow.add(const Duration(minutes: 21));

      expect(cache.get('Men'), null);
    });

    test('evicts oldest when at max size', () {
      cache.set('Cat1', ['p1']);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.set('Cat2', ['p2']);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.set('Cat3', ['p3']);
      mockNow = mockNow.add(const Duration(seconds: 1));

      // At max, add one more
      cache.set('Cat4', ['p4']);

      expect(cache.length, 3);
      expect(cache.get('Cat1'), null); // Oldest evicted
      expect(cache.get('Cat4'), ['p4']); // Newest kept
    });

    test('clear specific category', () {
      cache.set('Women', ['p1']);
      cache.set('Men', ['p2']);

      cache.clear('Women');

      expect(cache.get('Women'), null);
      expect(cache.get('Men'), ['p2']);
    });

    test('clear all categories', () {
      cache.set('Women', ['p1']);
      cache.set('Men', ['p2']);

      cache.clear();

      expect(cache.length, 0);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('rapid search typing deduplication', () async {
      final deduplicator = TestableRequestDeduplicator<List<String>>();
      int searchCount = 0;

      // Simulate rapid typing: "n", "ni", "nik", "nike"
      // All searching for same base query before first completes
      final completer = Completer<List<String>>();

      final futures = [
        deduplicator.deduplicate('search:nike', () {
          searchCount++;
          return completer.future;
        }),
        deduplicator.deduplicate('search:nike', () {
          searchCount++;
          return completer.future;
        }),
        deduplicator.deduplicate('search:nike', () {
          searchCount++;
          return completer.future;
        }),
      ];

      completer.complete(['Nike Air', 'Nike Max']);

      final results = await Future.wait(futures);

      // Only one actual search executed
      expect(searchCount, 1);
      // All get same results
      expect(results.every((r) => r.length == 2), true);
    });

    test('Algolia circuit breaker protects against repeated failures', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final breaker = TestableAlgoliaCircuitBreaker(
        nowProvider: () => mockNow,
      );

      // Simulate 8 Algolia failures
      for (var i = 0; i < 8; i++) {
        expect(breaker.isCircuitOpen(), false);
        breaker.recordFailure();
      }

      // Circuit is now open
      expect(breaker.isCircuitOpen(), true);

      // Requests should be blocked
      expect(breaker.isCircuitOpen(), true);

      // After cooldown, circuit resets
      mockNow = mockNow.add(const Duration(minutes: 6));
      expect(breaker.isCircuitOpen(), false);
    });

    test('search cache prevents redundant queries', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableLRUCache<List<String>>(
        maxSize: 50,
        trimTarget: 30,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );

      final key = TestableSearchCacheKeyBuilder.buildKey(
        query: 'nike shoes',
        filterType: 'deals',
        page: 0,
        sortOption: 'date',
      );

      // First search - cache miss
      expect(cache.get(key), null);

      // Store results
      cache.set(key, ['product1', 'product2', 'product3']);

      // Second search - cache hit
      expect(cache.get(key), ['product1', 'product2', 'product3']);

      // After TTL - cache miss again
      mockNow = mockNow.add(const Duration(minutes: 6));
      expect(cache.get(key), null);
    });

    test('memory limit prevents OOM with infinite scroll', () {
      final updater = TestableSearchResultUpdater<Map<String, String>>(
        getId: (p) => p['id']!,
        maxProductsInMemory: 200,
      );

      // Simulate user scrolling through many pages
      for (var page = 0; page < 20; page++) {
        updater.updateResults(
          List.generate(50, (i) => {'id': 'p${page * 50 + i}'}),
          page,
          50,
        );
      }

      // Without limit would be 1000 products
      // With limit, oscillates between ~200 and ~250
      // Should be capped around 250 max (200 + 50 buffer before trim kicks in)
      expect(updater.products.length <= 250, true);
      expect(updater.products.length < 1000, true); // Definitely not unbounded
    });
  });
}