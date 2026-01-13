// test/services/related_products_service_test.dart
//
// Unit tests for RelatedProductsService pure logic
// Tests the EXACT logic from lib/services/related_products_service.dart
//
// Run: flutter test test/services/related_products_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_related_products_service.dart';

void main() {
  // ============================================================================
  // CACHE CONFIG TESTS
  // ============================================================================
  group('TestableRelatedCacheConfig', () {
    test('cache TTL is 2 hours', () {
      expect(
        TestableRelatedCacheConfig.cacheTTL,
        const Duration(hours: 2),
      );
    });

    test('max cache size is 30', () {
      expect(TestableRelatedCacheConfig.maxCacheSize, 30);
    });

    test('batch fetch limit is 10', () {
      expect(TestableRelatedCacheConfig.batchFetchLimit, 10);
    });
  });

  // ============================================================================
  // CACHED RELATED TESTS
  // ============================================================================
  group('TestableCachedRelated', () {
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
    });

    group('isExpired', () {
      test('returns false for fresh cache', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1', 'p2'],
          timestamp: mockNow,
          nowProvider: () => mockNow,
        );

        expect(cached.isExpired, false);
      });

      test('returns false at 1 hour 59 minutes', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1', 'p2'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(hours: 1, minutes: 59)),
        );

        expect(cached.isExpired, false);
      });

      test('returns false at exactly 2 hours (not >)', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1', 'p2'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(hours: 2)),
        );

        // At exactly 2 hours, difference is NOT > TTL
        expect(cached.isExpired, false);
      });

      test('returns true after 2 hours', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1', 'p2'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(hours: 2, seconds: 1)),
        );

        expect(cached.isExpired, true);
      });

      test('returns true after 5 hours', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1', 'p2'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(hours: 5)),
        );

        expect(cached.isExpired, true);
      });
    });

    group('age', () {
      test('returns correct age', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(minutes: 30)),
        );

        expect(cached.age, const Duration(minutes: 30));
      });
    });

    group('remainingTTL', () {
      test('returns remaining time for fresh cache', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(minutes: 30)),
        );

        expect(cached.remainingTTL, const Duration(hours: 1, minutes: 30));
      });

      test('returns zero for expired cache', () {
        final cached = TestableCachedRelated<String>(
          products: ['p1'],
          timestamp: mockNow,
          nowProvider: () => mockNow.add(const Duration(hours: 5)),
        );

        expect(cached.remainingTTL, Duration.zero);
      });
    });
  });

  // ============================================================================
  // LIST CHUNKER TESTS
  // ============================================================================
  group('TestableListChunker', () {
    group('chunkList', () {
      test('chunks list into correct sizes', () {
        final list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        final chunks = TestableListChunker.chunkList(list, 5);

        expect(chunks.length, 3);
        expect(chunks[0], [1, 2, 3, 4, 5]);
        expect(chunks[1], [6, 7, 8, 9, 10]);
        expect(chunks[2], [11, 12]);
      });

      test('handles exact divisible length', () {
        final list = [1, 2, 3, 4, 5, 6];
        final chunks = TestableListChunker.chunkList(list, 3);

        expect(chunks.length, 2);
        expect(chunks[0], [1, 2, 3]);
        expect(chunks[1], [4, 5, 6]);
      });

      test('handles single chunk', () {
        final list = [1, 2, 3];
        final chunks = TestableListChunker.chunkList(list, 10);

        expect(chunks.length, 1);
        expect(chunks[0], [1, 2, 3]);
      });

      test('handles empty list', () {
        final chunks = TestableListChunker.chunkList<int>([], 5);
        expect(chunks, isEmpty);
      });

      test('handles chunk size of 1', () {
        final list = ['a', 'b', 'c'];
        final chunks = TestableListChunker.chunkList(list, 1);

        expect(chunks.length, 3);
        expect(chunks[0], ['a']);
        expect(chunks[1], ['b']);
        expect(chunks[2], ['c']);
      });

      test('handles Firestore batch limit (10)', () {
        final ids = List.generate(25, (i) => 'id_$i');
        final chunks = TestableListChunker.chunkList(ids, 10);

        expect(chunks.length, 3);
        expect(chunks[0].length, 10);
        expect(chunks[1].length, 10);
        expect(chunks[2].length, 5);
      });

      test('throws for zero chunk size', () {
        expect(
          () => TestableListChunker.chunkList([1, 2, 3], 0),
          throwsArgumentError,
        );
      });

      test('throws for negative chunk size', () {
        expect(
          () => TestableListChunker.chunkList([1, 2, 3], -1),
          throwsArgumentError,
        );
      });
    });

    group('getChunkCount', () {
      test('calculates correct count', () {
        expect(TestableListChunker.getChunkCount(25, 10), 3);
        expect(TestableListChunker.getChunkCount(20, 10), 2);
        expect(TestableListChunker.getChunkCount(5, 10), 1);
        expect(TestableListChunker.getChunkCount(0, 10), 0);
      });
    });

    group('needsChunking', () {
      test('returns true when list exceeds chunk size', () {
        expect(TestableListChunker.needsChunking(15, 10), true);
      });

      test('returns false when list fits in one chunk', () {
        expect(TestableListChunker.needsChunking(5, 10), false);
        expect(TestableListChunker.needsChunking(10, 10), false);
      });
    });
  });

  // ============================================================================
  // RELATED CACHE TESTS
  // ============================================================================
  group('TestableRelatedCache', () {
    late TestableRelatedCache<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableRelatedCache<String>(
        maxSize: 5, // Small for testing
        nowProvider: () => mockNow,
      );
    });

    group('get/set', () {
      test('stores and retrieves products', () {
        cache.set('product1', ['related1', 'related2']);

        expect(cache.get('product1'), ['related1', 'related2']);
      });

      test('returns null for missing key', () {
        expect(cache.get('nonexistent'), null);
      });

      test('returns null for expired entry', () {
        cache.set('product1', ['related1']);

        // Advance past TTL
        mockNow = mockNow.add(const Duration(hours: 3));

        expect(cache.get('product1'), null);
      });

      test('removes expired entry on access', () {
        cache.set('product1', ['related1']);
        mockNow = mockNow.add(const Duration(hours: 3));

        cache.get('product1'); // This should remove it
        expect(cache.length, 0);
      });
    });

    group('LRU eviction', () {
      test('evicts oldest when full', () {
        // Fill cache with staggered timestamps
        for (var i = 0; i < 5; i++) {
          cache.set('key_$i', ['value_$i']);
          mockNow = mockNow.add(const Duration(seconds: 1));
        }

        expect(cache.length, 5);

        // Add one more (should evict oldest)
        cache.set('key_new', ['value_new']);

        expect(cache.length, 5);
        expect(cache.get('key_0'), null); // Oldest evicted
        expect(cache.get('key_new'), ['value_new']); // Newest kept
      });

      test('oldestKey returns correct key', () {
        cache.set('first', ['v1']);
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.set('second', ['v2']);
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.set('third', ['v3']);

        expect(cache.oldestKey, 'first');
      });

      test('newestKey returns correct key', () {
        cache.set('first', ['v1']);
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.set('second', ['v2']);
        mockNow = mockNow.add(const Duration(seconds: 1));
        cache.set('third', ['v3']);

        expect(cache.newestKey, 'third');
      });
    });

    group('containsValid', () {
      test('returns true for valid entry', () {
        cache.set('product1', ['related1']);
        expect(cache.containsValid('product1'), true);
      });

      test('returns false for missing entry', () {
        expect(cache.containsValid('nonexistent'), false);
      });

      test('returns false for expired entry', () {
        cache.set('product1', ['related1']);
        mockNow = mockNow.add(const Duration(hours: 3));

        expect(cache.containsValid('product1'), false);
      });
    });

    group('getStats', () {
      test('returns correct statistics', () {
        cache.set('fresh1', ['v1']);
        cache.set('fresh2', ['v2']);
        mockNow = mockNow.add(const Duration(hours: 3));
        cache.set('fresh3', ['v3']);

        final stats = cache.getStats();

        expect(stats['totalEntries'], 3);
        expect(stats['expiredEntries'], 2);
        expect(stats['freshEntries'], 1);
      });
    });

    group('clear', () {
      test('removes all entries', () {
        cache.set('key1', ['v1']);
        cache.set('key2', ['v2']);

        cache.clear();

        expect(cache.length, 0);
        expect(cache.isEmpty, true);
      });
    });
  });

  // ============================================================================
  // RELATED ID EXTRACTOR TESTS
  // ============================================================================
  group('TestableRelatedIdExtractor', () {
    group('extractRelatedIds', () {
      test('extracts IDs from valid data', () {
        final data = {
          'relatedProductIds': ['id1', 'id2', 'id3'],
        };

        final ids = TestableRelatedIdExtractor.extractRelatedIds(data);

        expect(ids, ['id1', 'id2', 'id3']);
      });

      test('returns empty for null data', () {
        expect(TestableRelatedIdExtractor.extractRelatedIds(null), isEmpty);
      });

      test('returns empty for missing key', () {
        final data = {'otherField': 'value'};
        expect(TestableRelatedIdExtractor.extractRelatedIds(data), isEmpty);
      });

      test('returns empty for null relatedProductIds', () {
        final data = {'relatedProductIds': null};
        expect(TestableRelatedIdExtractor.extractRelatedIds(data), isEmpty);
      });
    });

    group('hasRelatedIds', () {
      test('returns true when IDs exist', () {
        final data = {'relatedProductIds': ['id1']};
        expect(TestableRelatedIdExtractor.hasRelatedIds(data), true);
      });

      test('returns false for null data', () {
        expect(TestableRelatedIdExtractor.hasRelatedIds(null), false);
      });

      test('returns false for empty array', () {
        final data = {'relatedProductIds': []};
        expect(TestableRelatedIdExtractor.hasRelatedIds(data), false);
      });

      test('returns false for non-list value', () {
        final data = {'relatedProductIds': 'not a list'};
        expect(TestableRelatedIdExtractor.hasRelatedIds(data), false);
      });
    });
  });

  // ============================================================================
  // PRODUCT FILTER TESTS
  // ============================================================================
  group('TestableProductFilter', () {
    group('excludeSourceProduct', () {
      test('removes source product from results', () {
        final products = ['p1', 'p2', 'p3', 'p4'];

        final filtered = TestableProductFilter.excludeSourceProduct(
          products,
          'p2',
          (p) => p,
        );

        expect(filtered, ['p1', 'p3', 'p4']);
      });

      test('returns all if source not in list', () {
        final products = ['p1', 'p2', 'p3'];

        final filtered = TestableProductFilter.excludeSourceProduct(
          products,
          'p999',
          (p) => p,
        );

        expect(filtered, ['p1', 'p2', 'p3']);
      });

      test('handles empty list', () {
        final filtered = TestableProductFilter.excludeSourceProduct<String>(
          [],
          'p1',
          (p) => p,
        );

        expect(filtered, isEmpty);
      });
    });

    group('limitResults', () {
      test('limits to specified count', () {
        final products = ['p1', 'p2', 'p3', 'p4', 'p5'];

        final limited = TestableProductFilter.limitResults(products, 3);

        expect(limited, ['p1', 'p2', 'p3']);
      });

      test('returns all if under limit', () {
        final products = ['p1', 'p2'];

        final limited = TestableProductFilter.limitResults(products, 10);

        expect(limited, ['p1', 'p2']);
      });

      test('returns all if exactly at limit', () {
        final products = ['p1', 'p2', 'p3'];

        final limited = TestableProductFilter.limitResults(products, 3);

        expect(limited, ['p1', 'p2', 'p3']);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('batch fetching 25 related products', () {
      final relatedIds = List.generate(25, (i) => 'related_$i');

      final chunks = TestableListChunker.chunkList(relatedIds, 10);

      expect(chunks.length, 3);
      expect(chunks[0].length, 10);
      expect(chunks[1].length, 10);
      expect(chunks[2].length, 5);

      // All IDs accounted for
      final allIds = chunks.expand((c) => c).toList();
      expect(allIds.length, 25);
    });

    test('cache eviction under memory pressure', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableRelatedCache<String>(
        maxSize: 30,
        nowProvider: () => mockNow,
      );

      // Fill cache to capacity
      for (var i = 0; i < 30; i++) {
        cache.set('product_$i', ['related_$i']);
        mockNow = mockNow.add(const Duration(seconds: 1));
      }

      expect(cache.length, 30);

      // Add one more - should evict oldest
      cache.set('product_new', ['related_new']);

      expect(cache.length, 30);
      expect(cache.containsValid('product_0'), false); // Evicted
      expect(cache.containsValid('product_new'), true); // Added
    });

    test('Cloud Function pre-computed IDs workflow', () {
      // Simulate: Product document has relatedProductIds from Cloud Function
      final productDoc = {
        'name': 'Nike Air Max',
        'category': 'Shoes',
        'relatedProductIds': ['adidas_1', 'puma_2', 'reebok_3', 'nb_4'],
      };

      expect(TestableRelatedIdExtractor.hasRelatedIds(productDoc), true);

      final relatedIds = TestableRelatedIdExtractor.extractRelatedIds(productDoc);
      expect(relatedIds.length, 4);

      // No chunking needed for 4 items
      expect(TestableListChunker.needsChunking(relatedIds.length, 10), false);
    });

    test('fallback excludes source product', () {
      // Fallback query returns products including the source
      final queryResults = ['source_product', 'related_1', 'related_2', 'related_3'];

      final filtered = TestableProductFilter.excludeSourceProduct(
        queryResults,
        'source_product',
        (p) => p,
      );

      expect(filtered, ['related_1', 'related_2', 'related_3']);
      expect(filtered.contains('source_product'), false);
    });
  });
}