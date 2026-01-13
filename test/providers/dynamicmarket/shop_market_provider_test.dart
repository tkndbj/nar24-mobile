// test/providers/shop_market_provider_test.dart
//
// Unit tests for ShopMarketProvider pure logic
// Tests the EXACT logic from lib/providers/shop_market_provider.dart
//
// Run: flutter test test/providers/shop_market_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_shop_market_provider.dart';

void main() {
  // ============================================================================
  // BACKEND DECISION TESTS
  // ============================================================================
  group('TestableBackendDecider', () {
    late TestableBackendDecider decider;

    setUp(() {
      decider = TestableBackendDecider();
    });

    group('decideBackend', () {
      test('returns Firestore with no filters', () {
        expect(decider.decideBackend(), TestableSearchBackend.firestore);
      });

      test('returns Algolia when quickFilter is set', () {
        decider.quickFilter = 'deals';
        expect(decider.decideBackend(), TestableSearchBackend.algolia);
      });

      test('returns Algolia for all quick filter types', () {
        for (final filter in ['deals', 'boosted', 'trending', 'fiveStar', 'bestSellers']) {
          decider.quickFilter = filter;
          expect(decider.decideBackend(), TestableSearchBackend.algolia,
              reason: 'quickFilter=$filter should use Algolia');
        }
      });

      test('returns Algolia for alphabetical sort with price filter', () {
        decider.sortOption = 'alphabetical';
        decider.minPrice = 10.0;
        expect(decider.decideBackend(), TestableSearchBackend.algolia);
      });

      test('returns Firestore for alphabetical sort without price filter', () {
        decider.sortOption = 'alphabetical';
        expect(decider.decideBackend(), TestableSearchBackend.firestore);
      });

      test('returns Algolia when 2+ disjunction fields have multiple values', () {
        decider.dynamicBrands = ['Brand1', 'Brand2'];
        decider.dynamicColors = ['Red', 'Blue'];
        expect(decider.decideBackend(), TestableSearchBackend.algolia);
      });

      test('returns Firestore when only 1 disjunction field has multiple values', () {
        decider.dynamicBrands = ['Brand1', 'Brand2'];
        decider.dynamicColors = ['Red']; // Only 1 value
        expect(decider.decideBackend(), TestableSearchBackend.firestore);
      });

      test('returns Algolia when more than 2 active filters', () {
        decider.dynamicBrands = ['Brand1'];
        decider.dynamicColors = ['Red'];
        decider.minPrice = 10.0;
        // 3 active filters: brands, colors, price
        expect(decider.decideBackend(), TestableSearchBackend.algolia);
      });

      test('returns Firestore when exactly 2 active filters', () {
        decider.dynamicBrands = ['Brand1'];
        decider.dynamicColors = ['Red'];
        // 2 active filters: brands, colors
        expect(decider.decideBackend(), TestableSearchBackend.firestore);
      });

      test('returns Firestore for price sort options without conflicts', () {
        decider.sortOption = 'price_asc';
        decider.dynamicBrands = ['Brand1'];
        expect(decider.decideBackend(), TestableSearchBackend.firestore);

        decider.sortOption = 'price_desc';
        expect(decider.decideBackend(), TestableSearchBackend.firestore);
      });
    });

    group('hasPriceInequality', () {
      test('returns false when no price filters', () {
        expect(decider.hasPriceInequality(), false);
      });

      test('returns true when minPrice set', () {
        decider.minPrice = 10.0;
        expect(decider.hasPriceInequality(), true);
      });

      test('returns true when maxPrice set', () {
        decider.maxPrice = 100.0;
        expect(decider.hasPriceInequality(), true);
      });

      test('returns true when both prices set', () {
        decider.minPrice = 10.0;
        decider.maxPrice = 100.0;
        expect(decider.hasPriceInequality(), true);
      });
    });

    group('disjunctionFieldCount', () {
      test('returns 0 with no multi-value filters', () {
        decider.dynamicBrands = ['Brand1'];
        decider.dynamicColors = ['Red'];
        expect(decider.disjunctionFieldCount(), 0);
      });

      test('counts fields with multiple values', () {
        decider.dynamicBrands = ['Brand1', 'Brand2'];
        expect(decider.disjunctionFieldCount(), 1);

        decider.dynamicColors = ['Red', 'Blue'];
        expect(decider.disjunctionFieldCount(), 2);

        decider.dynamicSubSubcategories = ['Sub1', 'Sub2'];
        expect(decider.disjunctionFieldCount(), 3);
      });
    });

    group('activeFilterCount', () {
      test('returns 0 with no filters', () {
        expect(decider.activeFilterCount(), 0);
      });

      test('counts each filter type once', () {
        decider.dynamicBrands = ['Brand1', 'Brand2']; // +1
        expect(decider.activeFilterCount(), 1);

        decider.dynamicColors = ['Red']; // +1
        expect(decider.activeFilterCount(), 2);

        decider.minPrice = 10.0; // +1 (price counts as one)
        expect(decider.activeFilterCount(), 3);

        decider.quickFilter = 'deals'; // +1
        expect(decider.activeFilterCount(), 4);
      });

      test('price inequality counts as single filter', () {
        decider.minPrice = 10.0;
        decider.maxPrice = 100.0;
        expect(decider.activeFilterCount(), 1);
      });
    });
  });

  // ============================================================================
  // CACHE KEY BUILDER TESTS
  // ============================================================================
  group('TestableCacheKeyBuilder', () {
    late TestableCacheKeyBuilder builder;

    setUp(() {
      builder = TestableCacheKeyBuilder();
    });

    group('buildCacheKey', () {
      test('builds basic key with category and page', () {
        builder.category = 'Electronics';
        final key = builder.buildCacheKey(0);
        expect(key, contains('Electronics'));
        expect(key, contains('|0|'));
        expect(key, contains('|v6'));
      });

      test('includes all category levels', () {
        builder.category = 'Electronics';
        builder.subcategory = 'Phones';
        builder.subSubcategory = 'Smartphones';
        final key = builder.buildCacheKey(0);
        expect(key, startsWith('Electronics|Phones|Smartphones|'));
      });

      test('includes sort option', () {
        builder.sortOption = 'price_asc';
        final key = builder.buildCacheKey(0);
        expect(key, contains('price_asc'));
      });

      test('includes dynamic filters', () {
        builder.dynamicBrands = ['Apple', 'Samsung'];
        builder.dynamicColors = ['Red', 'Blue'];
        final key = builder.buildCacheKey(0);
        expect(key, contains('brands:Apple,Samsung'));
        expect(key, contains('colors:Red,Blue'));
      });

      test('includes price filters', () {
        builder.minPrice = 10.0;
        builder.maxPrice = 100.0;
        final key = builder.buildCacheKey(0);
        expect(key, contains('minP:10.0'));
        expect(key, contains('maxP:100.0'));
      });

      test('includes quick filter', () {
        builder.quickFilter = 'deals';
        final key = builder.buildCacheKey(0);
        expect(key, contains('quick:deals'));
      });

      test('includes buyer category', () {
        builder.buyerCategory = 'Women';
        builder.buyerSubcategory = 'Clothing';
        final key = builder.buildCacheKey(0);
        expect(key, contains('buyer:Women'));
        expect(key, contains('buyerSub:Clothing'));
      });

      test('includes backend type', () {
        builder.lastBackend = TestableSearchBackend.algolia;
        final key = builder.buildCacheKey(0);
        expect(key, contains('backend:algolia'));
      });

      test('different pages produce different keys', () {
        builder.category = 'Electronics';
        final key0 = builder.buildCacheKey(0);
        final key1 = builder.buildCacheKey(1);
        final key2 = builder.buildCacheKey(2);
        expect(key0, isNot(equals(key1)));
        expect(key1, isNot(equals(key2)));
      });
    });

    group('buildFilterCacheKey', () {
      test('includes default when no quick filter', () {
        final key = builder.buildFilterCacheKey();
        expect(key, startsWith('default|'));
      });

      test('includes quick filter', () {
        builder.quickFilter = 'trending';
        final key = builder.buildFilterCacheKey();
        expect(key, startsWith('trending|'));
      });

      test('sorts brands for consistent keys', () {
        builder.dynamicBrands = ['Samsung', 'Apple', 'Google'];
        final key = builder.buildFilterCacheKey();
        expect(key, contains('b:Apple,Google,Samsung'));
      });

      test('sorts colors for consistent keys', () {
        builder.dynamicColors = ['Red', 'Blue', 'Green'];
        final key = builder.buildFilterCacheKey();
        expect(key, contains('c:Blue,Green,Red'));
      });

      test('same filters in different order produce same key', () {
        builder.dynamicBrands = ['Samsung', 'Apple'];
        final key1 = builder.buildFilterCacheKey();

        builder.dynamicBrands = ['Apple', 'Samsung'];
        final key2 = builder.buildFilterCacheKey();

        expect(key1, equals(key2));
      });

      test('includes all filter components', () {
        builder.quickFilter = 'deals';
        builder.dynamicBrands = ['Apple'];
        builder.dynamicColors = ['Red'];
        builder.minPrice = 10.0;
        builder.maxPrice = 100.0;
        builder.buyerCategory = 'Women';
        builder.category = 'Fashion';
        builder.subcategory = 'Dresses';
        builder.sortOption = 'price_asc';

        final key = builder.buildFilterCacheKey();

        expect(key, contains('deals'));
        expect(key, contains('b:Apple'));
        expect(key, contains('c:Red'));
        expect(key, contains('min:10.0'));
        expect(key, contains('max:100.0'));
        expect(key, contains('bc:Women'));
        expect(key, contains('cat:Fashion'));
        expect(key, contains('sub:Dresses'));
        expect(key, contains('sort:price_asc'));
      });
    });
  });

  // ============================================================================
  // ALGOLIA FILTER BUILDER TESTS
  // ============================================================================
  group('TestableAlgoliaFilterBuilder', () {
    late TestableAlgoliaFilterBuilder builder;

    setUp(() {
      builder = TestableAlgoliaFilterBuilder();
    });

    group('buildFacetFilters', () {
      test('returns empty list with no filters', () {
        final filters = builder.buildFacetFilters();
        expect(filters, isEmpty);
      });

      test('adds category with _en suffix', () {
        builder.category = 'Electronics';
        final filters = builder.buildFacetFilters();
        expect(filters.any((g) => g.contains('category_en:Electronics')), true);
      });

      test('adds subcategory with _en suffix', () {
        builder.subcategory = 'Phones';
        final filters = builder.buildFacetFilters();
        expect(filters.any((g) => g.contains('subcategory_en:Phones')), true);
      });

      test('adds subSubcategory with _en suffix', () {
        builder.subSubcategory = 'Smartphones';
        final filters = builder.buildFacetFilters();
        expect(filters.any((g) => g.contains('subsubcategory_en:Smartphones')), true);
      });

      test('adds gender filter with Unisex for Women', () {
        builder.buyerCategory = 'Women';
        final filters = builder.buildFacetFilters();
        final genderGroup = filters.firstWhere(
          (g) => g.any((f) => f.startsWith('gender:')),
          orElse: () => [],
        );
        expect(genderGroup, containsAll(['gender:Women', 'gender:Unisex']));
      });

      test('adds gender filter with Unisex for Men', () {
        builder.buyerCategory = 'Men';
        final filters = builder.buildFacetFilters();
        final genderGroup = filters.firstWhere(
          (g) => g.any((f) => f.startsWith('gender:')),
          orElse: () => [],
        );
        expect(genderGroup, containsAll(['gender:Men', 'gender:Unisex']));
      });

      test('does not add gender filter for other categories', () {
        builder.buyerCategory = 'Kids';
        final filters = builder.buildFacetFilters();
        final hasGenderFilter = filters.any((group) =>
            group.any((f) => f.startsWith('gender:')));
        expect(hasGenderFilter, false);
      });

      test('adds brandModel without suffix', () {
        builder.dynamicBrands = ['Apple', 'Samsung'];
        final filters = builder.buildFacetFilters();
        final brandGroup = filters.firstWhere(
          (g) => g.any((f) => f.startsWith('brandModel:')),
          orElse: () => [],
        );
        expect(brandGroup, containsAll(['brandModel:Apple', 'brandModel:Samsung']));
      });

      test('adds availableColors', () {
        builder.dynamicColors = ['Red', 'Blue'];
        final filters = builder.buildFacetFilters();
        final colorGroup = filters.firstWhere(
          (g) => g.any((f) => f.startsWith('availableColors:')),
          orElse: () => [],
        );
        expect(colorGroup, containsAll(['availableColors:Red', 'availableColors:Blue']));
      });

      test('adds dynamic subSubcategories with _en suffix', () {
        builder.dynamicSubSubcategories = ['Type1', 'Type2'];
        final filters = builder.buildFacetFilters();
        final subsubGroup = filters.firstWhere(
          (g) => g.any((f) => f.startsWith('subsubcategory_en:')),
          orElse: () => [],
        );
        expect(subsubGroup, containsAll(['subsubcategory_en:Type1', 'subsubcategory_en:Type2']));
      });

      test('adds isBoosted for boosted quick filter', () {
        builder.quickFilter = 'boosted';
        final filters = builder.buildFacetFilters();
        expect(filters.any((g) => g.contains('isBoosted:true')), true);
      });

      test('does not add isBoosted for other quick filters', () {
        builder.quickFilter = 'deals';
        final filters = builder.buildFacetFilters();
        final hasBoostedFilter = filters.any((group) =>
            group.any((f) => f.contains('isBoosted')));
        expect(hasBoostedFilter, false);
      });

      test('combines multiple filter groups', () {
        builder.category = 'Electronics';
        builder.subcategory = 'Phones';
        builder.buyerCategory = 'Women';
        builder.dynamicBrands = ['Apple'];
        builder.dynamicColors = ['Black'];

        final filters = builder.buildFacetFilters();

        expect(filters.length, 5);
        expect(filters.any((g) => g.contains('category_en:Electronics')), true);
        expect(filters.any((g) => g.contains('subcategory_en:Phones')), true);
        expect(filters.any((g) => g.contains('gender:Women') && g.contains('gender:Unisex')), true);
        expect(filters.any((g) => g.contains('brandModel:Apple')), true);
        expect(filters.any((g) => g.contains('availableColors:Black')), true);
      });
    });

    group('buildNumericFilters', () {
      test('returns empty list with no filters', () {
        final filters = builder.buildNumericFilters();
        expect(filters, isEmpty);
      });

      test('adds minPrice with floor', () {
        builder.minPrice = 10.5;
        final filters = builder.buildNumericFilters();
        expect(filters, contains('price>=10'));
      });

      test('adds maxPrice with ceil', () {
        builder.maxPrice = 99.1;
        final filters = builder.buildNumericFilters();
        expect(filters, contains('price<=100'));
      });

      test('adds both price filters', () {
        builder.minPrice = 10.0;
        builder.maxPrice = 100.0;
        final filters = builder.buildNumericFilters();
        expect(filters, containsAll(['price>=10', 'price<=100']));
      });

      test('adds discountPercentage for deals filter', () {
        builder.quickFilter = 'deals';
        final filters = builder.buildNumericFilters();
        expect(filters, contains('discountPercentage>0'));
      });

      test('adds dailyClickCount for trending filter', () {
        builder.quickFilter = 'trending';
        final filters = builder.buildNumericFilters();
        expect(filters, contains('dailyClickCount>=10'));
      });

      test('adds averageRating for fiveStar filter', () {
        builder.quickFilter = 'fiveStar';
        final filters = builder.buildNumericFilters();
        expect(filters, contains('averageRating=5'));
      });

      test('adds no extra filter for bestSellers', () {
        builder.quickFilter = 'bestSellers';
        final filters = builder.buildNumericFilters();
        expect(filters, isEmpty);
      });

      test('combines price and quick filters', () {
        builder.minPrice = 50.0;
        builder.maxPrice = 200.0;
        builder.quickFilter = 'deals';
        final filters = builder.buildNumericFilters();
        expect(filters,
            containsAll(['price>=50', 'price<=200', 'discountPercentage>0']));
      });
    });
  });

  // ============================================================================
  // ALGOLIA INDEX SELECTOR TESTS
  // ============================================================================
  group('TestableAlgoliaIndexSelector', () {
    test('returns date replica for date sort', () {
      expect(
        TestableAlgoliaIndexSelector.getIndexForSort('date'),
        'shop_products_createdAt_desc',
      );
    });

    test('returns price_asc replica', () {
      expect(
        TestableAlgoliaIndexSelector.getIndexForSort('price_asc'),
        'shop_products_price_asc',
      );
    });

    test('returns price_desc replica', () {
      expect(
        TestableAlgoliaIndexSelector.getIndexForSort('price_desc'),
        'shop_products_price_desc',
      );
    });

    test('returns alphabetical replica', () {
      expect(
        TestableAlgoliaIndexSelector.getIndexForSort('alphabetical'),
        'shop_products_alphabetical',
      );
    });

    test('returns base index for unknown sort option', () {
      expect(
        TestableAlgoliaIndexSelector.getIndexForSort('unknown'),
        'shop_products',
      );
    });
  });

  // ============================================================================
  // DOCUMENT CACHE TESTS
  // ============================================================================
  group('TestableDocumentCache', () {
    late TestableDocumentCache<Map<String, dynamic>> cache;

    setUp(() {
      cache = TestableDocumentCache<Map<String, dynamic>>(
        maxSize: 10,
        evictionPercent: 0.3,
      );
    });

    test('stores and retrieves items', () {
      cache.put('id1', {'name': 'Product 1'});
      expect(cache['id1'], {'name': 'Product 1'});
    });

    test('evicts oldest items when over capacity', () {
      // Fill cache to capacity
      for (var i = 0; i < 10; i++) {
        cache.put('id$i', {'index': i});
      }
      expect(cache.length, 10);

      // Add one more - should evict 30% (3 items)
      cache.put('id10', {'index': 10});

      expect(cache.length, 8); // 10 - 3 + 1 = 8
      expect(cache.evictedKeys.length, 3);
      expect(cache.containsKey('id0'), false);
      expect(cache.containsKey('id1'), false);
      expect(cache.containsKey('id2'), false);
      expect(cache.containsKey('id10'), true);
    });

    test('touch updates timestamp for LRU', () {
      // Use controllable time for deterministic testing
      var mockTime = DateTime(2024, 1, 1, 0, 0, 0);
      
      final smallCache = TestableDocumentCache<Map<String, dynamic>>(
        maxSize: 5,
        evictionPercent: 0.4, // Evict 2 items when over capacity
        nowProvider: () => mockTime,
      );

      // Add items with incrementing timestamps
      for (var i = 0; i < 5; i++) {
        smallCache.put('id$i', {'index': i});
        mockTime = mockTime.add(const Duration(seconds: 1));
      }
      // Now: id0(0s), id1(1s), id2(2s), id3(3s), id4(4s)
      expect(smallCache.length, 5);

      // Touch id0 to make it "recently used" (now at 5s)
      smallCache.touch('id0');
      mockTime = mockTime.add(const Duration(seconds: 1));

      // Add new item - should evict oldest 2 (id1 at 1s, id2 at 2s)
      smallCache.put('id5', {'index': 5});

      // id0 should survive because it was touched (timestamp 5s)
      expect(smallCache.containsKey('id0'), true);
      // id1 and id2 should be evicted (oldest timestamps: 1s, 2s)
      expect(smallCache.containsKey('id1'), false);
      expect(smallCache.containsKey('id2'), false);
      // id3, id4, id5 should remain
      expect(smallCache.containsKey('id3'), true);
      expect(smallCache.containsKey('id4'), true);
      expect(smallCache.containsKey('id5'), true);
    });
  });

  // ============================================================================
  // MAIN CACHE TESTS
  // ============================================================================
  group('TestableMainCache', () {
    late TestableMainCache<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      cache = TestableMainCache<String>(
        maxEntries: 5,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );
    });

    test('stores and retrieves items', () {
      cache.put('key1', ['item1', 'item2']);
      expect(cache.getIfValid('key1'), ['item1', 'item2']);
    });

    test('returns null for expired items', () {
      cache.put('key1', ['item1']);

      // Advance time past TTL
      mockNow = mockNow.add(const Duration(minutes: 6));

      expect(cache.getIfValid('key1'), null);
      expect(cache.isValid('key1'), false);
    });

    test('returns items just before expiry', () {
      cache.put('key1', ['item1']);

      // Advance time just before TTL
      mockNow = mockNow.add(const Duration(minutes: 4, seconds: 59));

      expect(cache.getIfValid('key1'), ['item1']);
      expect(cache.isValid('key1'), true);
    });

    test('prunes oldest entries when over capacity', () {
      for (var i = 0; i < 5; i++) {
        cache.put('key$i', ['item$i']);
        mockNow = mockNow.add(const Duration(seconds: 1));
      }

      // Add one more
      cache.put('key5', ['item5']);

      expect(cache.length, 5);
      expect(cache.containsKey('key0'), false); // Oldest pruned
      expect(cache.containsKey('key5'), true);
    });
  });

  // ============================================================================
  // FILTER CACHE TESTS
  // ============================================================================
  group('TestableFilterCache', () {
    late TestableFilterCache<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      cache = TestableFilterCache<String>(
        maxEntries: 3,
        ttl: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );
    });

    test('stores pages and hasMore', () {
      cache.put('filter1', {0: ['a', 'b'], 1: ['c', 'd']}, true);

      expect(cache.getPages('filter1'), {0: ['a', 'b'], 1: ['c', 'd']});
      expect(cache.getHasMore('filter1'), true);
    });

    test('returns null for expired entries', () {
      cache.put('filter1', {0: ['a']}, true);

      mockNow = mockNow.add(const Duration(minutes: 6));

      expect(cache.getPages('filter1'), null);
      expect(cache.getHasMore('filter1'), null);
    });

    test('removes expired entries on prune', () {
      cache.put('filter1', {0: ['a']}, true);
      mockNow = mockNow.add(const Duration(minutes: 6));
      cache.put('filter2', {0: ['b']}, false);

      expect(cache.containsKey('filter1'), false);
      expect(cache.containsKey('filter2'), true);
    });

    test('removes oldest when over capacity', () {
      cache.put('filter1', {0: ['a']}, true);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('filter2', {0: ['b']}, true);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('filter3', {0: ['c']}, true);
      mockNow = mockNow.add(const Duration(seconds: 1));

      // Add 4th entry
      cache.put('filter4', {0: ['d']}, true);

      expect(cache.length, 3);
      expect(cache.containsKey('filter1'), false);
      expect(cache.containsKey('filter4'), true);
    });

    test('updates timestamp on access', () {
      cache.put('filter1', {0: ['a']}, true);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('filter2', {0: ['b']}, true);
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('filter3', {0: ['c']}, true);

      // Access filter1 to update its timestamp
      cache.getPages('filter1');

      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('filter4', {0: ['d']}, true);

      // filter1 should survive because it was accessed
      expect(cache.containsKey('filter1'), true);
      expect(cache.containsKey('filter2'), false); // Oldest now
    });
  });

  // ============================================================================
  // PAGE CACHE TESTS
  // ============================================================================
  group('TestablePageCache', () {
    late TestablePageCache<String> cache;

    setUp(() {
      cache = TestablePageCache<String>(maxPages: 3);
    });

    test('stores pages with cursors', () {
      cache.put(0, ['a', 'b'], cursor: 'cursor0');
      cache.put(1, ['c', 'd'], cursor: 'cursor1');

      expect(cache[0], ['a', 'b']);
      expect(cache[1], ['c', 'd']);
      expect(cache.getCursor(0), 'cursor0');
      expect(cache.getCursor(1), 'cursor1');
    });

    test('prunes oldest pages when over capacity', () {
      cache.put(0, ['a']);
      cache.put(1, ['b']);
      cache.put(2, ['c']);
      cache.put(3, ['d']);

      expect(cache.length, 3);
      expect(cache[0], null); // Pruned
      expect(cache.prunedPages, [0]);
      expect(cache[3], ['d']);
    });

    test('keeps newer pages during pruning', () {
      cache.put(0, ['a']);
      cache.put(1, ['b']);
      cache.put(2, ['c']);
      cache.put(3, ['d']);
      cache.put(4, ['e']);

      expect(cache.length, 3);
      expect(cache.prunedPages, [0, 1]);
      expect(cache[2], ['c']);
      expect(cache[3], ['d']);
      expect(cache[4], ['e']);
    });
  });

  // ============================================================================
  // DYNAMIC FILTER STATE TESTS
  // ============================================================================
  group('TestableDynamicFilterState', () {
    late TestableDynamicFilterState state;

    setUp(() {
      state = TestableDynamicFilterState();
    });

    group('hasDynamicFilters', () {
      test('returns false when empty', () {
        expect(state.hasDynamicFilters, false);
      });

      test('returns true with brands', () {
        state.brands = ['Apple'];
        expect(state.hasDynamicFilters, true);
      });

      test('returns true with colors', () {
        state.colors = ['Red'];
        expect(state.hasDynamicFilters, true);
      });

      test('returns true with minPrice', () {
        state.minPrice = 10.0;
        expect(state.hasDynamicFilters, true);
      });

      test('returns true with maxPrice', () {
        state.maxPrice = 100.0;
        expect(state.hasDynamicFilters, true);
      });
    });

    group('activeFiltersCount', () {
      test('returns 0 when empty', () {
        expect(state.activeFiltersCount, 0);
      });

      test('counts individual brand filters', () {
        state.brands = ['Apple', 'Samsung', 'Google'];
        expect(state.activeFiltersCount, 3);
      });

      test('counts price as single filter', () {
        state.minPrice = 10.0;
        state.maxPrice = 100.0;
        expect(state.activeFiltersCount, 1);
      });

      test('counts all filter types', () {
        state.brands = ['Apple', 'Samsung'];
        state.colors = ['Red'];
        state.subSubcategories = ['Type1', 'Type2'];
        state.minPrice = 10.0;
        // 2 brands + 1 color + 2 subsubs + 1 price = 6
        expect(state.activeFiltersCount, 6);
      });
    });

    group('addFilters', () {
      test('adds new brands', () {
        final changed = state.addFilters(newBrands: ['Apple', 'Samsung']);
        expect(changed, true);
        expect(state.brands, ['Apple', 'Samsung']);
      });

      test('does not add duplicate brands', () {
        state.brands = ['Apple'];
        final changed = state.addFilters(newBrands: ['Apple', 'Samsung']);
        expect(changed, true);
        expect(state.brands, ['Apple', 'Samsung']);
      });

      test('returns false when nothing added', () {
        state.brands = ['Apple'];
        final changed = state.addFilters(newBrands: ['Apple']);
        expect(changed, false);
      });

      test('adds colors independently', () {
        state.addFilters(newBrands: ['Apple']);
        state.addFilters(newColors: ['Red']);
        expect(state.brands, ['Apple']);
        expect(state.colors, ['Red']);
      });
    });

    group('setFilters', () {
      test('replaces brands', () {
        state.brands = ['Apple'];
        final changed = state.setFilters(newBrands: ['Samsung', 'Google']);
        expect(changed, true);
        expect(state.brands, ['Samsung', 'Google']);
      });

      test('returns false when same values', () {
        state.brands = ['Apple', 'Samsung'];
        final changed = state.setFilters(newBrands: ['Apple', 'Samsung']);
        expect(changed, false);
      });
    });

    group('removeFilter', () {
      test('removes specific brand', () {
        state.brands = ['Apple', 'Samsung'];
        final changed = state.removeFilter(brand: 'Apple');
        expect(changed, true);
        expect(state.brands, ['Samsung']);
      });

      test('returns false when brand not found', () {
        state.brands = ['Apple'];
        final changed = state.removeFilter(brand: 'Samsung');
        expect(changed, false);
      });

      test('clears price when requested', () {
        state.minPrice = 10.0;
        state.maxPrice = 100.0;
        final changed = state.removeFilter(clearPrice: true);
        expect(changed, true);
        expect(state.minPrice, null);
        expect(state.maxPrice, null);
      });
    });

    group('clearAll', () {
      test('clears all filters', () {
        state.brands = ['Apple'];
        state.colors = ['Red'];
        state.minPrice = 10.0;

        final changed = state.clearAll();

        expect(changed, true);
        expect(state.hasDynamicFilters, false);
      });

      test('returns false when already empty', () {
        final changed = state.clearAll();
        expect(changed, false);
      });
    });
  });

  // ============================================================================
  // LIST UTILS TESTS
  // ============================================================================
  group('TestableListUtils', () {
    group('listEquals', () {
      test('returns true for equal lists', () {
        expect(TestableListUtils.listEquals([1, 2, 3], [1, 2, 3]), true);
        expect(TestableListUtils.listEquals(['a', 'b'], ['a', 'b']), true);
      });

      test('returns false for different lengths', () {
        expect(TestableListUtils.listEquals([1, 2], [1, 2, 3]), false);
      });

      test('returns false for different values', () {
        expect(TestableListUtils.listEquals([1, 2, 3], [1, 2, 4]), false);
      });

      test('returns false for different order', () {
        expect(TestableListUtils.listEquals([1, 2, 3], [3, 2, 1]), false);
      });

      test('returns true for empty lists', () {
        expect(TestableListUtils.listEquals([], []), true);
      });
    });

    group('chunks', () {
      test('splits list into chunks', () {
        final result = TestableListUtils.chunks([1, 2, 3, 4, 5], 2).toList();
        expect(result, [
          [1, 2],
          [3, 4],
          [5]
        ]);
      });

      test('handles exact divisible length', () {
        final result = TestableListUtils.chunks([1, 2, 3, 4], 2).toList();
        expect(result, [
          [1, 2],
          [3, 4]
        ]);
      });

      test('handles single chunk', () {
        final result = TestableListUtils.chunks([1, 2, 3], 10).toList();
        expect(result, [
          [1, 2, 3]
        ]);
      });

      test('handles empty list', () {
        final result = TestableListUtils.chunks([], 5).toList();
        expect(result, isEmpty);
      });

      test('handles chunk size of 1', () {
        final result = TestableListUtils.chunks([1, 2, 3], 1).toList();
        expect(result, [
          [1],
          [2],
          [3]
        ]);
      });
    });
  });

  // ============================================================================
  // PRODUCT DEDUPLICATOR TESTS
  // ============================================================================
  group('TestableProductDeduplicator', () {
    test('combines pages in order', () {
      final pageCache = {
        0: [
          {'id': 'a'},
          {'id': 'b'}
        ],
        1: [
          {'id': 'c'},
          {'id': 'd'}
        ],
      };

      final result = TestableProductDeduplicator.rebuildAllLoaded(
        pageCache,
        (item) => item['id'] as String,
      );

      expect(result.map((p) => p['id']), ['a', 'b', 'c', 'd']);
    });

    test('removes duplicates keeping first occurrence', () {
      final pageCache = {
        0: [
          {'id': 'a'},
          {'id': 'b'}
        ],
        1: [
          {'id': 'b'},
          {'id': 'c'}
        ], // 'b' is duplicate
      };

      final result = TestableProductDeduplicator.rebuildAllLoaded(
        pageCache,
        (item) => item['id'] as String,
      );

      expect(result.map((p) => p['id']), ['a', 'b', 'c']);
    });

    test('handles out-of-order page keys', () {
      final pageCache = {
        2: [
          {'id': 'e'}
        ],
        0: [
          {'id': 'a'}
        ],
        1: [
          {'id': 'c'}
        ],
      };

      final result = TestableProductDeduplicator.rebuildAllLoaded(
        pageCache,
        (item) => item['id'] as String,
      );

      // Should be sorted by page number
      expect(result.map((p) => p['id']), ['a', 'c', 'e']);
    });

    test('handles empty pages', () {
      final pageCache = <int, List<Map<String, String>>>{
        0: [],
        1: [
          {'id': 'a'}
        ],
      };

      final result = TestableProductDeduplicator.rebuildAllLoaded(
        pageCache,
        (item) => item['id'] as String,
      );

      expect(result.map((p) => p['id']), ['a']);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('complex filter combination selects correct backend', () {
      final decider = TestableBackendDecider();

      // Scenario: User browsing Women's clothing with brand and color filters
      decider.dynamicBrands = ['Zara', 'H&M'];
      decider.dynamicColors = ['Red', 'Black'];
      decider.minPrice = 50.0;
      decider.maxPrice = 200.0;

      // Multiple disjunction fields + price = Algolia
      expect(decider.decideBackend(), TestableSearchBackend.algolia);
    });

    test('cache key changes when filter changes', () {
      final builder = TestableCacheKeyBuilder();
      builder.category = 'Fashion';
      builder.subcategory = 'Dresses';

      final key1 = builder.buildCacheKey(0);

      builder.dynamicBrands = ['Zara'];
      final key2 = builder.buildCacheKey(0);

      expect(key1, isNot(equals(key2)));
    });

    test('Algolia facets correctly format gender with Unisex', () {
      final builder = TestableAlgoliaFilterBuilder();
      builder.category = 'Fashion';
      builder.buyerCategory = 'Women';

      final facets = builder.buildFacetFilters();

      // Should have OR condition for gender
      final genderFilter = facets.firstWhere(
        (group) => group.any((f) => f.startsWith('gender:')),
      );
      expect(genderFilter, containsAll(['gender:Women', 'gender:Unisex']));
    });

    test('deals quick filter adds discount numeric filter', () {
      final builder = TestableAlgoliaFilterBuilder();
      builder.quickFilter = 'deals';
      builder.minPrice = 20.0;

      final numeric = builder.buildNumericFilters();

      expect(numeric, containsAll(['price>=20', 'discountPercentage>0']));
    });

    test('filter cache key is consistent regardless of insertion order', () {
      final builder1 = TestableCacheKeyBuilder();
      builder1.dynamicBrands = ['Zara', 'H&M', 'Nike'];
      builder1.dynamicColors = ['Red', 'Blue'];

      final builder2 = TestableCacheKeyBuilder();
      builder2.dynamicBrands = ['Nike', 'Zara', 'H&M'];
      builder2.dynamicColors = ['Blue', 'Red'];

      // Filter cache keys should be the same (sorted internally)
      expect(
        builder1.buildFilterCacheKey(),
        equals(builder2.buildFilterCacheKey()),
      );
    });

    test('page deduplication handles refresh with overlapping data', () {
      // Simulates: Page 0 cached, then refresh brings some same items
      final pageCache = {
        0: [
          {'id': 'p1', 'name': 'Product 1'},
          {'id': 'p2', 'name': 'Product 2'},
          {'id': 'p3', 'name': 'Product 3'},
        ],
      };

      // Simulate page 1 with one duplicate
      pageCache[1] = [
        {'id': 'p3', 'name': 'Product 3 Updated'}, // Duplicate
        {'id': 'p4', 'name': 'Product 4'},
        {'id': 'p5', 'name': 'Product 5'},
      ];

      final result = TestableProductDeduplicator.rebuildAllLoaded(
        pageCache,
        (item) => item['id'] as String,
      );

      // Should have 5 unique products, keeping first occurrence of p3
      expect(result.length, 5);
      expect(result[2]['name'], 'Product 3'); // Original, not updated
    });
  });
}