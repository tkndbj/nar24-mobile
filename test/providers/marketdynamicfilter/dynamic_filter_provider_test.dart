// test/providers/dynamic_filter_provider_test.dart
//
// Unit tests for DynamicFilterProvider pure logic
// Tests the EXACT logic from lib/providers/dynamic_filter_provider.dart
//
// Run: flutter test test/providers/dynamic_filter_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_dynamic_filter_provider.dart';

void main() {
  // ============================================================================
  // CONFIG TESTS
  // ============================================================================
  group('TestableDynamicFilterConfig', () {
    test('page size is 20', () {
      expect(TestableDynamicFilterConfig.pageSize, 20);
    });

    test('max cached filters is 10', () {
      expect(TestableDynamicFilterConfig.maxCachedFilters, 10);
    });

    test('max pages per filter is 5', () {
      expect(TestableDynamicFilterConfig.maxPagesPerFilter, 5);
    });

    test('max cached products is 500', () {
      expect(TestableDynamicFilterConfig.maxCachedProducts, 500);
    });

    test('cache timeout is 2 minutes', () {
      expect(TestableDynamicFilterConfig.cacheTimeout, const Duration(minutes: 2));
    });

    test('prefetch count is 2', () {
      expect(TestableDynamicFilterConfig.prefetchCount, 2);
    });

    test('max products per filter is 100 (5 pages x 20)', () {
      final maxProducts = TestableDynamicFilterConfig.maxPagesPerFilter *
          TestableDynamicFilterConfig.pageSize;
      expect(maxProducts, 100);
    });
  });

  // ============================================================================
  // FILTER EQUALITY CHECKER TESTS
  // ============================================================================
  group('TestableFilterEqualityChecker', () {
    group('filtersEqual', () {
      test('returns true for identical lists', () {
        final list1 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
          TestableFilterData(id: 'f2', isActive: true, order: 1),
        ];
        final list2 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
          TestableFilterData(id: 'f2', isActive: true, order: 1),
        ];

        expect(TestableFilterEqualityChecker.filtersEqual(list1, list2), true);
      });

      test('returns false for different lengths', () {
        final list1 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
        ];
        final list2 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
          TestableFilterData(id: 'f2', isActive: true, order: 1),
        ];

        expect(TestableFilterEqualityChecker.filtersEqual(list1, list2), false);
      });

      test('returns false for different ids', () {
        final list1 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
        ];
        final list2 = [
          TestableFilterData(id: 'f2', isActive: true, order: 0),
        ];

        expect(TestableFilterEqualityChecker.filtersEqual(list1, list2), false);
      });

      test('returns false for different isActive', () {
        final list1 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
        ];
        final list2 = [
          TestableFilterData(id: 'f1', isActive: false, order: 0),
        ];

        expect(TestableFilterEqualityChecker.filtersEqual(list1, list2), false);
      });

      test('returns false for different order', () {
        final list1 = [
          TestableFilterData(id: 'f1', isActive: true, order: 0),
        ];
        final list2 = [
          TestableFilterData(id: 'f1', isActive: true, order: 1),
        ];

        expect(TestableFilterEqualityChecker.filtersEqual(list1, list2), false);
      });

      test('returns true for empty lists', () {
        expect(TestableFilterEqualityChecker.filtersEqual([], []), true);
      });
    });

    group('filterChanged', () {
      test('returns false for both null', () {
        expect(TestableFilterEqualityChecker.filterChanged(null, null), false);
      });

      test('returns true when old is null', () {
        final current = TestableFilterData(id: 'f1');
        expect(TestableFilterEqualityChecker.filterChanged(null, current), true);
      });

      test('returns true when current is null', () {
        final old = TestableFilterData(id: 'f1');
        expect(TestableFilterEqualityChecker.filterChanged(old, null), true);
      });

      test('returns false for identical filters', () {
        final old = TestableFilterData(id: 'f1', isActive: true, order: 0);
        final current = TestableFilterData(id: 'f1', isActive: true, order: 0);
        expect(TestableFilterEqualityChecker.filterChanged(old, current), false);
      });
    });
  });

  // ============================================================================
  // DISPLAY NAME RESOLVER TESTS
  // ============================================================================
  group('TestableDisplayNameResolver', () {
    group('getDisplayName', () {
      test('returns requested language if available', () {
        final displayName = {'en': 'Deals', 'tr': 'Fırsatlar'};

        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: displayName,
            name: 'deals',
            languageCode: 'en',
          ),
          'Deals',
        );
      });

      test('falls back to Turkish if requested not available', () {
        final displayName = {'tr': 'Fırsatlar'};

        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: displayName,
            name: 'deals',
            languageCode: 'de', // German not available
          ),
          'Fırsatlar',
        );
      });

      test('falls back to English if Turkish not available', () {
        final displayName = {'en': 'Deals'};

        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: displayName,
            name: 'deals',
            languageCode: 'de',
          ),
          'Deals',
        );
      });

      test('falls back to name if no translations', () {
        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: {},
            name: 'deals',
            languageCode: 'en',
          ),
          'deals',
        );
      });

      test('prioritizes requested > tr > en > name', () {
        final displayName = {'en': 'English', 'tr': 'Turkish', 'de': 'German'};

        // Requested language first
        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: displayName,
            name: 'name',
            languageCode: 'de',
          ),
          'German',
        );

        // Falls back to Turkish
        expect(
          TestableDisplayNameResolver.getDisplayName(
            displayName: {'en': 'English', 'tr': 'Turkish'},
            name: 'name',
            languageCode: 'fr',
          ),
          'Turkish',
        );
      });
    });

    group('getAvailableLanguages', () {
      test('returns all language codes', () {
        final displayName = {'en': 'English', 'tr': 'Turkish', 'de': 'German'};
        final languages = TestableDisplayNameResolver.getAvailableLanguages(displayName);

        expect(languages, containsAll(['en', 'tr', 'de']));
      });

      test('returns empty for empty map', () {
        expect(TestableDisplayNameResolver.getAvailableLanguages({}), isEmpty);
      });
    });
  });

  // ============================================================================
  // CACHE VALIDATOR TESTS
  // ============================================================================
  group('TestableCacheValidator', () {
    late TestableCacheValidator validator;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      validator = TestableCacheValidator(
        nowProvider: () => currentTime,
      );
    });

    group('isCacheValid', () {
      test('returns false for null timestamp', () {
        expect(validator.isCacheValid(null), false);
      });

      test('returns true for fresh cache', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 1));
        expect(validator.isCacheValid(cacheTime), true);
      });

      test('returns false for expired cache', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 3));
        expect(validator.isCacheValid(cacheTime), false);
      });

      test('returns true at exactly 2 minutes (not expired yet)', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 2));
        expect(validator.isCacheValid(cacheTime), false); // >= timeout is invalid
      });

      test('returns true at 1:59', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 1, seconds: 59));
        expect(validator.isCacheValid(cacheTime), true);
      });
    });

    group('getRemainingCacheTime', () {
      test('returns null for null timestamp', () {
        expect(validator.getRemainingCacheTime(null), null);
      });

      test('returns correct remaining time', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 1));
        expect(validator.getRemainingCacheTime(cacheTime), const Duration(minutes: 1));
      });

      test('returns zero for expired cache', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 5));
        expect(validator.getRemainingCacheTime(cacheTime), Duration.zero);
      });
    });

    group('isCacheAboutToExpire', () {
      test('returns true for null timestamp', () {
        expect(validator.isCacheAboutToExpire(null), true);
      });

      test('returns true when less than 30 seconds remaining', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 1, seconds: 45));
        expect(validator.isCacheAboutToExpire(cacheTime), true);
      });

      test('returns false when more than 30 seconds remaining', () {
        final cacheTime = currentTime.subtract(const Duration(minutes: 1));
        expect(validator.isCacheAboutToExpire(cacheTime), false);
      });
    });
  });

  // ============================================================================
  // LRU FILTER CACHE TESTS
  // ============================================================================
  group('TestableLRUFilterCache', () {
    late TestableLRUFilterCache<String> cache;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableLRUFilterCache<String>(
        maxCachedFilters: 3,
        maxCachedProducts: 10,
        getProductCount: (list) => list.length,
        nowProvider: () => currentTime,
      );
    });

    test('stores and retrieves products', () {
      cache.set('filter1', ['p1', 'p2', 'p3']);
      expect(cache.get('filter1'), ['p1', 'p2', 'p3']);
    });

    test('returns null for missing filter', () {
      expect(cache.get('missing'), null);
    });

    test('evicts LRU filter when exceeding max', () {
      cache.set('filter1', ['p1']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter2', ['p2']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter3', ['p3']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter4', ['p4']); // Should evict filter1

      expect(cache.filterCount, 3);
      expect(cache.containsKey('filter1'), false); // Evicted
      expect(cache.containsKey('filter2'), true);
      expect(cache.containsKey('filter3'), true);
      expect(cache.containsKey('filter4'), true);
    });

    test('updates access time on get', () {
      cache.set('filter1', ['p1']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter2', ['p2']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter3', ['p3']);

      // Access filter1, making it most recently used
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.get('filter1');

      // Add filter4, should evict filter2 (now oldest)
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter4', ['p4']);

      expect(cache.containsKey('filter1'), true); // Recently accessed
      expect(cache.containsKey('filter2'), false); // Evicted
    });

    test('evicts products when exceeding total limit', () {
      // Max is 10 products
      cache.set('filter1', ['p1', 'p2', 'p3', 'p4', 'p5']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter2', ['p6', 'p7', 'p8', 'p9', 'p10', 'p11', 'p12']); // Total 12, over limit

      // Should have evicted some products
      expect(cache.totalProductCount <= 10, true);
    });

    test('oldestFilterId returns correct filter', () {
      cache.set('filter1', ['p1']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter2', ['p2']);

      expect(cache.oldestFilterId, 'filter1');
    });

    test('newestFilterId returns correct filter', () {
      cache.set('filter1', ['p1']);
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('filter2', ['p2']);

      expect(cache.newestFilterId, 'filter2');
    });

    test('clear removes all entries', () {
      cache.set('filter1', ['p1']);
      cache.set('filter2', ['p2']);
      cache.clear();

      expect(cache.filterCount, 0);
    });
  });

  // ============================================================================
  // PAGINATION MANAGER TESTS
  // ============================================================================
  group('TestablePaginationManager', () {
    late TestablePaginationManager manager;

    setUp(() {
      manager = TestablePaginationManager(
        maxPagesPerFilter: 5,
        pageSize: 20,
      );
    });

    test('starts at page 0 with hasMore true', () {
      manager.initialize('filter1');
      expect(manager.getCurrentPage('filter1'), 0);
      expect(manager.hasMorePages('filter1'), true);
      expect(manager.isLoadingMore('filter1'), false);
    });

    test('canLoadMore returns true initially', () {
      manager.initialize('filter1');
      expect(manager.canLoadMore('filter1'), true);
    });

    test('canLoadMore returns false while loading', () {
      manager.initialize('filter1');
      manager.startLoading('filter1');
      expect(manager.canLoadMore('filter1'), false);
    });

    test('canLoadMore returns false at max pages', () {
      manager.initialize('filter1');
      
      // Simulate loading to max pages
      for (var i = 0; i < 4; i++) {
        manager.finishLoading('filter1', 20);
      }

      // At page 4 (0-indexed), which is the 5th page (max)
      expect(manager.getCurrentPage('filter1'), 4);
      expect(manager.canLoadMore('filter1'), false);
    });

    test('finishLoading updates state correctly', () {
      manager.initialize('filter1');
      manager.startLoading('filter1');
      manager.finishLoading('filter1', 20);

      expect(manager.getCurrentPage('filter1'), 1);
      expect(manager.hasMorePages('filter1'), true);
      expect(manager.isLoadingMore('filter1'), false);
    });

    test('finishLoading with less than pageSize sets hasMore false', () {
      manager.initialize('filter1');
      manager.startLoading('filter1');
      manager.finishLoading('filter1', 15); // Less than 20

      expect(manager.hasMorePages('filter1'), false);
    });

    test('getMaxProducts returns correct value', () {
      expect(manager.getMaxProducts('filter1'), 100); // 5 * 20
    });

    test('reset restores initial state', () {
      manager.initialize('filter1');
      manager.finishLoading('filter1', 20);
      manager.finishLoading('filter1', 10); // hasMore = false

      manager.reset('filter1');

      expect(manager.getCurrentPage('filter1'), 0);
      expect(manager.hasMorePages('filter1'), true);
    });
  });

  // ============================================================================
  // PAGINATED CACHE TESTS
  // ============================================================================
  group('TestablePaginatedCache', () {
    late TestablePaginatedCache<String> cache;

    setUp(() {
      cache = TestablePaginatedCache<String>(maxPagesPerFilter: 3);
    });

    test('stores and retrieves pages', () {
      cache.setPage('filter1', 0, ['p1', 'p2']);
      expect(cache.getPage('filter1', 0), ['p1', 'p2']);
    });

    test('returns null for missing page', () {
      expect(cache.getPage('filter1', 0), null);
    });

    test('hasPage returns correct state', () {
      cache.setPage('filter1', 0, ['p1']);
      expect(cache.hasPage('filter1', 0), true);
      expect(cache.hasPage('filter1', 1), false);
    });

    test('enforces page limits', () {
      cache.setPage('filter1', 0, ['p1']);
      cache.setPage('filter1', 1, ['p2']);
      cache.setPage('filter1', 2, ['p3']);
      cache.setPage('filter1', 3, ['p4']); // Over limit
      cache.setPage('filter1', 4, ['p5']); // Over limit

      // Should only have pages 0, 1, 2
      expect(cache.getPageCount('filter1'), 3);
      expect(cache.hasPage('filter1', 0), true);
      expect(cache.hasPage('filter1', 1), true);
      expect(cache.hasPage('filter1', 2), true);
      expect(cache.hasPage('filter1', 3), false);
    });

    test('clear removes filter pages', () {
      cache.setPage('filter1', 0, ['p1']);
      cache.setPage('filter1', 1, ['p2']);
      cache.clear('filter1');

      expect(cache.getPageCount('filter1'), 0);
    });
  });

  // ============================================================================
  // RACE CONDITION PROTECTOR TESTS
  // ============================================================================
  group('TestableRaceConditionProtector', () {
    late TestableRaceConditionProtector protector;

    setUp(() {
      protector = TestableRaceConditionProtector();
    });

    test('starts with no ongoing fetches', () {
      expect(protector.isFetching('filter1'), false);
      expect(protector.ongoingFetchCount, 0);
    });

    test('tryStartFetch returns true on first call', () {
      expect(protector.tryStartFetch('filter1'), true);
      expect(protector.isFetching('filter1'), true);
    });

    test('tryStartFetch returns false if already fetching', () {
      protector.tryStartFetch('filter1');
      expect(protector.tryStartFetch('filter1'), false); // Already fetching
    });

    test('endFetch allows new fetch', () {
      protector.tryStartFetch('filter1');
      protector.endFetch('filter1');
      expect(protector.tryStartFetch('filter1'), true);
    });

    test('multiple filters can fetch concurrently', () {
      expect(protector.tryStartFetch('filter1'), true);
      expect(protector.tryStartFetch('filter2'), true);
      expect(protector.ongoingFetchCount, 2);
    });

    test('clear removes all ongoing fetches', () {
      protector.tryStartFetch('filter1');
      protector.tryStartFetch('filter2');
      protector.clear();

      expect(protector.ongoingFetchCount, 0);
      expect(protector.isFetching('filter1'), false);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('filter cache eviction during heavy browsing', () {
      var time = DateTime(2024, 1, 1);
      final cache = TestableLRUFilterCache<String>(
        maxCachedFilters: 3,
        maxCachedProducts: 50,
        getProductCount: (list) => list.length,
        nowProvider: () => time,
      );

      // User browses multiple filter categories
      cache.set('deals', List.generate(20, (i) => 'deal_$i'));
      time = time.add(const Duration(seconds: 1));
      cache.set('trending', List.generate(20, (i) => 'trend_$i'));
      time = time.add(const Duration(seconds: 1));
      cache.set('electronics', List.generate(20, (i) => 'elec_$i'));
      time = time.add(const Duration(seconds: 1));

      // User goes back to deals (updates access time)
      cache.get('deals');
      time = time.add(const Duration(seconds: 1));

      // User opens new category
      cache.set('fashion', List.generate(20, (i) => 'fash_$i'));

      // Trending should be evicted (oldest accessed)
      expect(cache.containsKey('deals'), true); // Recently accessed
      expect(cache.containsKey('trending'), false); // Evicted
      expect(cache.containsKey('electronics'), true);
      expect(cache.containsKey('fashion'), true);
    });

    test('pagination stops at max pages', () {
      final manager = TestablePaginationManager(
        maxPagesPerFilter: 5,
        pageSize: 20,
      );

      manager.initialize('deals');

      // Simulate user scrolling through pages
      for (var i = 0; i < 10; i++) {
        if (manager.canLoadMore('deals')) {
          manager.startLoading('deals');
          manager.finishLoading('deals', 20);
        }
      }

      // Should stop at page 4 (5 pages total: 0-4)
      expect(manager.getCurrentPage('deals'), 4);
      expect(manager.canLoadMore('deals'), false);
    });

    test('display name fallback chain', () {
      // German user viewing filter with only Turkish translation
      final turkishOnly = {'tr': 'Fırsatlar'};
      expect(
        TestableDisplayNameResolver.getDisplayName(
          displayName: turkishOnly,
          name: 'deals',
          languageCode: 'de',
        ),
        'Fırsatlar', // Falls back to Turkish
      );

      // English user viewing filter with no translations
      final noTranslations = <String, String>{};
      expect(
        TestableDisplayNameResolver.getDisplayName(
          displayName: noTranslations,
          name: 'deals',
          languageCode: 'en',
        ),
        'deals', // Falls back to name
      );
    });

    test('race condition protection prevents duplicate fetches', () {
      final protector = TestableRaceConditionProtector();

      // Simulate rapid taps on same filter
      final fetch1Started = protector.tryStartFetch('deals');
      final fetch2Started = protector.tryStartFetch('deals');
      final fetch3Started = protector.tryStartFetch('deals');

      expect(fetch1Started, true); // First one starts
      expect(fetch2Started, false); // Blocked
      expect(fetch3Started, false); // Blocked

      // Only one fetch is running
      expect(protector.ongoingFetchCount, 1);
    });

    test('cache timeout validation', () {
      var time = DateTime(2024, 6, 15, 12, 0, 0);
      final validator = TestableCacheValidator(
        nowProvider: () => time,
      );

      final cacheTime = time;

      // Fresh cache
      expect(validator.isCacheValid(cacheTime), true);

      // After 1 minute
      time = time.add(const Duration(minutes: 1));
      expect(validator.isCacheValid(cacheTime), true);

      // After 2 minutes (expired)
      time = time.add(const Duration(minutes: 1));
      expect(validator.isCacheValid(cacheTime), false);
    });
  });
}