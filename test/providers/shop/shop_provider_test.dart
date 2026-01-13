// test/providers/shop_provider_test.dart
//
// Unit tests for ShopProvider pure logic
// Tests the EXACT logic from lib/providers/shop_provider.dart
//
// Run: flutter test test/providers/shop_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_shop_provider.dart';

void main() {
  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  group('TestableCircuitBreaker', () {
    late TestableCircuitBreaker breaker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      breaker = TestableCircuitBreaker(nowProvider: () => mockNow);
    });

    group('initial state', () {
      test('starts closed', () {
        expect(breaker.isOpen(), false);
      });

      test('starts with zero failures', () {
        expect(breaker.consecutiveFailures, 0);
      });

      test('starts with no reset time', () {
        expect(breaker.resetTime, null);
      });
    });

    group('onFailure', () {
      test('increments failure count', () {
        breaker.onFailure();
        expect(breaker.consecutiveFailures, 1);

        breaker.onFailure();
        expect(breaker.consecutiveFailures, 2);
      });

      test('opens circuit after max failures', () {
        breaker.onFailure();
        breaker.onFailure();
        expect(breaker.isOpen(), false);

        breaker.onFailure(); // 3rd failure
        expect(breaker.isOpen(), true);
      });

      test('sets reset time when opening', () {
        breaker.onFailure();
        breaker.onFailure();
        breaker.onFailure();

        expect(breaker.resetTime, isNotNull);
        expect(
          breaker.resetTime,
          mockNow.add(TestableCircuitBreaker.resetDuration),
        );
      });
    });

    group('onSuccess', () {
      test('resets failure count', () {
        breaker.onFailure();
        breaker.onFailure();
        expect(breaker.consecutiveFailures, 2);

        breaker.onSuccess();
        expect(breaker.consecutiveFailures, 0);
      });

      test('clears reset time', () {
        breaker.onFailure();
        breaker.onFailure();
        breaker.onFailure();
        expect(breaker.resetTime, isNotNull);

        breaker.onSuccess();
        expect(breaker.resetTime, null);
      });

      test('does nothing if no failures', () {
        breaker.onSuccess();
        expect(breaker.consecutiveFailures, 0);
        expect(breaker.resetTime, null);
      });
    });

    group('isOpen', () {
      test('returns false when under failure threshold', () {
        breaker.onFailure();
        breaker.onFailure();
        expect(breaker.isOpen(), false);
      });

      test('returns true after reaching threshold', () {
        for (var i = 0; i < 3; i++) {
          breaker.onFailure();
        }
        expect(breaker.isOpen(), true);
      });

      test('returns false after reset duration passes', () {
        for (var i = 0; i < 3; i++) {
          breaker.onFailure();
        }
        expect(breaker.isOpen(), true);

        // Advance time past reset duration
        mockNow = mockNow.add(const Duration(minutes: 1, seconds: 1));
        expect(breaker.isOpen(), false);
        expect(breaker.consecutiveFailures, 0);
      });

      test('stays open until reset duration passes', () {
        for (var i = 0; i < 3; i++) {
          breaker.onFailure();
        }

        // Advance time but not past reset
        mockNow = mockNow.add(const Duration(seconds: 30));
        expect(breaker.isOpen(), true);
      });
    });

    group('reset', () {
      test('clears all state', () {
        breaker.onFailure();
        breaker.onFailure();
        breaker.onFailure();

        breaker.reset();

        expect(breaker.consecutiveFailures, 0);
        expect(breaker.resetTime, null);
        expect(breaker.isOpen(), false);
      });
    });
  });

  // ============================================================================
  // RETRY BACKOFF TESTS
  // ============================================================================
  group('TestableRetryBackoff', () {
    group('calculateDelay', () {
      test('returns initial delay for attempt 0', () {
        expect(
          TestableRetryBackoff.calculateDelay(0),
          const Duration(milliseconds: 200),
        );
      });

      test('doubles delay for each attempt', () {
        expect(
          TestableRetryBackoff.calculateDelay(1),
          const Duration(milliseconds: 400),
        );
        expect(
          TestableRetryBackoff.calculateDelay(2),
          const Duration(milliseconds: 800),
        );
      });

      test('respects custom initial delay', () {
        expect(
          TestableRetryBackoff.calculateDelay(
            0,
            initialDelay: const Duration(milliseconds: 100),
          ),
          const Duration(milliseconds: 100),
        );
        expect(
          TestableRetryBackoff.calculateDelay(
            1,
            initialDelay: const Duration(milliseconds: 100),
          ),
          const Duration(milliseconds: 200),
        );
      });
    });

    group('getRetrySequence', () {
      test('returns correct sequence with defaults', () {
        final sequence = TestableRetryBackoff.getRetrySequence();

        // 3 attempts = 2 retries
        expect(sequence.length, 2);
        expect(sequence[0], const Duration(milliseconds: 200));
        expect(sequence[1], const Duration(milliseconds: 400));
      });

      test('respects custom max attempts', () {
        final sequence = TestableRetryBackoff.getRetrySequence(maxAttempts: 5);

        expect(sequence.length, 4);
      });
    });

    group('shouldRetry', () {
      test('returns true when under max', () {
        expect(TestableRetryBackoff.shouldRetry(0), true);
        expect(TestableRetryBackoff.shouldRetry(1), true);
        expect(TestableRetryBackoff.shouldRetry(2), true);
      });

      test('returns false at max', () {
        expect(TestableRetryBackoff.shouldRetry(3), false);
      });

      test('respects custom max attempts', () {
        expect(TestableRetryBackoff.shouldRetry(4, maxAttempts: 5), true);
        expect(TestableRetryBackoff.shouldRetry(5, maxAttempts: 5), false);
      });
    });
  });

  // ============================================================================
  // CACHE MANAGER TESTS
  // ============================================================================
  group('TestableCacheManager', () {
    group('isCacheSizeExceeded', () {
      test('returns false for small data', () {
        final smallJson = '{"key": "value"}';
        expect(TestableCacheManager.isCacheSizeExceeded(smallJson), false);
      });

      test('returns true for data over 5MB', () {
        // Create a string larger than 5MB
        final largeJson = 'x' * (5 * 1024 * 1024 + 1);
        expect(TestableCacheManager.isCacheSizeExceeded(largeJson), true);
      });

      test('returns false for data exactly at limit', () {
        // Exactly 5MB
        final exactJson = 'x' * (5 * 1024 * 1024);
        expect(TestableCacheManager.isCacheSizeExceeded(exactJson), false);
      });
    });

    group('getCacheSizeBytes', () {
      test('returns correct byte count for ASCII', () {
        expect(TestableCacheManager.getCacheSizeBytes('hello'), 5);
      });

      test('returns correct byte count for UTF-8', () {
        // UTF-8 multi-byte characters
        expect(TestableCacheManager.getCacheSizeBytes('مرحبا'), 10); // Arabic
      });
    });

    group('isCacheExpired', () {
      test('returns false for recent cache', () {
        final lastFetch = DateTime.now().subtract(const Duration(days: 1));
        expect(TestableCacheManager.isCacheExpired(lastFetch), false);
      });

      test('returns true for old cache', () {
        final lastFetch = DateTime.now().subtract(const Duration(days: 8));
        expect(TestableCacheManager.isCacheExpired(lastFetch), true);
      });

      test('returns false at exactly 7 days', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final lastFetch = now.subtract(const Duration(days: 7));
        expect(TestableCacheManager.isCacheExpired(lastFetch, now: now), false);
      });
    });

    group('trimListIfNeeded', () {
      test('does not trim when under limit', () {
        final items = List.generate(100, (i) => i);
        final result = TestableCacheManager.trimListIfNeeded(items);
        expect(result.length, 100);
      });

      test('trims when over limit', () {
        final items = List.generate(250, (i) => i);
        final result = TestableCacheManager.trimListIfNeeded(items);
        expect(result.length, 200);
        // Should keep the LAST 200 items (LRU eviction of oldest)
        expect(result.first, 50);
        expect(result.last, 249);
      });

      test('respects custom max', () {
        final items = List.generate(50, (i) => i);
        final result = TestableCacheManager.trimListIfNeeded(items, maxItems: 30);
        expect(result.length, 30);
        expect(result.first, 20);
      });
    });

    group('calculateExcess', () {
      test('returns 0 when under limit', () {
        expect(TestableCacheManager.calculateExcess(100), 0);
      });

      test('returns correct excess when over limit', () {
        expect(TestableCacheManager.calculateExcess(250), 50);
      });

      test('returns 0 when at exactly limit', () {
        expect(TestableCacheManager.calculateExcess(200), 0);
      });
    });
  });

  // ============================================================================
  // ROLE VERIFIER TESTS
  // ============================================================================
  group('TestableRoleVerifier', () {
    group('verifyUserRole', () {
      test('verifies owner role', () {
        final shopData = {'ownerId': 'user123'};
        expect(TestableRoleVerifier.verifyUserRole('user123', 'owner', shopData), true);
        expect(TestableRoleVerifier.verifyUserRole('otherUser', 'owner', shopData), false);
      });

      test('verifies co-owner role', () {
        final shopData = {
          'coOwners': ['user1', 'user2', 'user3']
        };
        expect(TestableRoleVerifier.verifyUserRole('user2', 'co-owner', shopData), true);
        expect(TestableRoleVerifier.verifyUserRole('user4', 'co-owner', shopData), false);
      });

      test('verifies editor role', () {
        final shopData = {
          'editors': ['editor1', 'editor2']
        };
        expect(TestableRoleVerifier.verifyUserRole('editor1', 'editor', shopData), true);
        expect(TestableRoleVerifier.verifyUserRole('other', 'editor', shopData), false);
      });

      test('verifies viewer role', () {
        final shopData = {
          'viewers': ['viewer1']
        };
        expect(TestableRoleVerifier.verifyUserRole('viewer1', 'viewer', shopData), true);
        expect(TestableRoleVerifier.verifyUserRole('other', 'viewer', shopData), false);
      });

      test('returns false for unknown role', () {
        final shopData = {'ownerId': 'user123'};
        expect(TestableRoleVerifier.verifyUserRole('user123', 'admin', shopData), false);
        expect(TestableRoleVerifier.verifyUserRole('user123', 'superuser', shopData), false);
      });

      test('handles missing arrays gracefully', () {
        final shopData = <String, dynamic>{};
        expect(TestableRoleVerifier.verifyUserRole('user1', 'co-owner', shopData), false);
        expect(TestableRoleVerifier.verifyUserRole('user1', 'editor', shopData), false);
        expect(TestableRoleVerifier.verifyUserRole('user1', 'viewer', shopData), false);
      });

      test('handles null arrays gracefully', () {
        final shopData = {
          'coOwners': null,
          'editors': null,
          'viewers': null,
        };
        expect(TestableRoleVerifier.verifyUserRole('user1', 'co-owner', shopData), false);
      });
    });

    group('isValidRole', () {
      test('returns true for valid roles', () {
        expect(TestableRoleVerifier.isValidRole('owner'), true);
        expect(TestableRoleVerifier.isValidRole('co-owner'), true);
        expect(TestableRoleVerifier.isValidRole('editor'), true);
        expect(TestableRoleVerifier.isValidRole('viewer'), true);
      });

      test('returns false for invalid roles', () {
        expect(TestableRoleVerifier.isValidRole('admin'), false);
        expect(TestableRoleVerifier.isValidRole('superuser'), false);
        expect(TestableRoleVerifier.isValidRole(''), false);
      });
    });
  });

  // ============================================================================
  // FILTER SUMMARY TESTS
  // ============================================================================
  group('TestableFilterSummary', () {
    group('generate', () {
      test('returns empty string for no filters', () {
        expect(TestableFilterSummary.generate(), '');
      });

      test('includes gender', () {
        expect(
          TestableFilterSummary.generate(selectedGender: 'Women'),
          'Women',
        );
      });

      test('pluralizes brands correctly', () {
        expect(
          TestableFilterSummary.generate(selectedBrands: ['Nike']),
          '1 brand',
        );
        expect(
          TestableFilterSummary.generate(selectedBrands: ['Nike', 'Adidas']),
          '2 brands',
        );
      });

      test('pluralizes types correctly', () {
        expect(
          TestableFilterSummary.generate(selectedTypes: ['T-Shirt']),
          '1 type',
        );
        expect(
          TestableFilterSummary.generate(selectedTypes: ['T-Shirt', 'Pants']),
          '2 types',
        );
      });

      test('pluralizes fits correctly', () {
        expect(
          TestableFilterSummary.generate(selectedFits: ['Slim']),
          '1 fit',
        );
        expect(
          TestableFilterSummary.generate(selectedFits: ['Slim', 'Regular']),
          '2 fits',
        );
      });

      test('pluralizes sizes correctly', () {
        expect(
          TestableFilterSummary.generate(selectedSizes: ['M']),
          '1 size',
        );
        expect(
          TestableFilterSummary.generate(selectedSizes: ['S', 'M', 'L']),
          '3 sizes',
        );
      });

      test('pluralizes colors correctly', () {
        expect(
          TestableFilterSummary.generate(selectedColors: ['Red']),
          '1 color',
        );
        expect(
          TestableFilterSummary.generate(selectedColors: ['Red', 'Blue']),
          '2 colors',
        );
      });

      test('formats price range correctly', () {
        expect(
          TestableFilterSummary.generate(minPrice: 100, maxPrice: 500),
          '100-500 TL',
        );
      });

      test('formats min price only', () {
        expect(
          TestableFilterSummary.generate(minPrice: 100),
          '100+ TL',
        );
      });

      test('formats max price only', () {
        expect(
          TestableFilterSummary.generate(maxPrice: 500),
          '< 500 TL',
        );
      });

      test('joins multiple filters with comma', () {
        final summary = TestableFilterSummary.generate(
          selectedGender: 'Men',
          selectedBrands: ['Nike'],
          minPrice: 50,
          maxPrice: 200,
        );
        expect(summary, 'Men, 1 brand, 50-200 TL');
      });
    });

    group('countFilters', () {
      test('returns 0 for no filters', () {
        expect(TestableFilterSummary.countFilters(), 0);
      });

      test('counts all filter types', () {
        expect(
          TestableFilterSummary.countFilters(
            selectedGender: 'Men',
            selectedBrands: ['Nike', 'Adidas'],
            selectedTypes: ['Shirt'],
            selectedFits: ['Slim'],
            selectedSizes: ['M', 'L'],
            selectedColors: ['Red'],
            minPrice: 100,
            maxPrice: 500,
          ),
          10, // 1 + 2 + 1 + 1 + 2 + 1 + 1 + 1
        );
      });
    });
  });

  // ============================================================================
  // REFRESH COOLDOWN TESTS
  // ============================================================================
  group('TestableRefreshCooldown', () {
    late TestableRefreshCooldown cooldown;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cooldown = TestableRefreshCooldown(nowProvider: () => mockNow);
    });

    group('canRefresh', () {
      test('returns true initially', () {
        expect(cooldown.canRefresh, true);
      });

      test('returns false immediately after refresh', () {
        cooldown.markRefresh();
        expect(cooldown.canRefresh, false);
      });

      test('returns true after interval passes', () {
        cooldown.markRefresh();
        mockNow = mockNow.add(const Duration(seconds: 31));
        expect(cooldown.canRefresh, true);
      });

      test('returns false before interval passes', () {
        cooldown.markRefresh();
        mockNow = mockNow.add(const Duration(seconds: 29));
        expect(cooldown.canRefresh, false);
      });

      test('returns true at exactly interval', () {
        cooldown.markRefresh();
        mockNow = mockNow.add(const Duration(seconds: 30));
        expect(cooldown.canRefresh, true);
      });
    });

    group('remainingCooldownTime', () {
      test('returns zero initially', () {
        expect(cooldown.remainingCooldownTime, Duration.zero);
      });

      test('returns full interval immediately after refresh', () {
        cooldown.markRefresh();
        expect(cooldown.remainingCooldownTime, const Duration(seconds: 30));
      });

      test('returns remaining time', () {
        cooldown.markRefresh();
        mockNow = mockNow.add(const Duration(seconds: 10));
        expect(cooldown.remainingCooldownTime, const Duration(seconds: 20));
      });

      test('returns zero after interval passes', () {
        cooldown.markRefresh();
        mockNow = mockNow.add(const Duration(seconds: 35));
        expect(cooldown.remainingCooldownTime, Duration.zero);
      });
    });

    group('reset', () {
      test('allows immediate refresh', () {
        cooldown.markRefresh();
        expect(cooldown.canRefresh, false);

        cooldown.reset();
        expect(cooldown.canRefresh, true);
      });
    });
  });

  // ============================================================================
  // TIMESTAMP CONVERTER TESTS
  // ============================================================================
  group('TestableTimestampConverter', () {
    group('isTimestampField', () {
      test('returns true for timestamp fields', () {
        expect(TestableTimestampConverter.isTimestampField('createdAt'), true);
        expect(TestableTimestampConverter.isTimestampField('boostStartTime'), true);
        expect(TestableTimestampConverter.isTimestampField('boostEndTime'), true);
        expect(TestableTimestampConverter.isTimestampField('lastClickDate'), true);
        expect(TestableTimestampConverter.isTimestampField('timestamp'), true);
      });

      test('returns false for non-timestamp fields', () {
        expect(TestableTimestampConverter.isTimestampField('name'), false);
        expect(TestableTimestampConverter.isTimestampField('price'), false);
        expect(TestableTimestampConverter.isTimestampField('created'), false);
      });
    });

    group('convertTimestampFields', () {
      test('converts int timestamp fields', () {
        final data = {
          'name': 'Test',
          'createdAt': 1718452800000,
        };

        final converted = TestableTimestampConverter.convertTimestampFields(data);

        expect(converted['name'], 'Test');
        expect(converted['createdAt']['_isTimestamp'], true);
        expect(converted['createdAt']['_milliseconds'], 1718452800000);
      });

      test('handles nested maps', () {
        final data = {
          'shop': {
            'name': 'Test Shop',
            'createdAt': 1718452800000,
          },
        };

        final converted = TestableTimestampConverter.convertTimestampFields(data);

        expect(converted['shop']['createdAt']['_isTimestamp'], true);
      });

      test('handles lists with maps', () {
        final data = {
          'items': [
            {'name': 'Item 1', 'timestamp': 1718452800000},
            {'name': 'Item 2', 'timestamp': 1718453800000},
          ],
        };

        final converted = TestableTimestampConverter.convertTimestampFields(data);

        expect(converted['items'][0]['timestamp']['_isTimestamp'], true);
        expect(converted['items'][1]['timestamp']['_isTimestamp'], true);
      });

      test('leaves non-int timestamps unchanged', () {
        final data = {
          'createdAt': 'not an int',
        };

        final converted = TestableTimestampConverter.convertTimestampFields(data);

        expect(converted['createdAt'], 'not an int');
      });
    });
  });

  // ============================================================================
  // ALGOLIA FILTER BUILDER TESTS
  // ============================================================================
  group('TestableAlgoliaFilterBuilder', () {
    group('buildFilters', () {
      test('returns empty list for no filters', () {
        expect(TestableAlgoliaFilterBuilder.buildFilters(), isEmpty);
      });

      test('builds gender filter', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedGender: 'Women',
        );
        expect(filters, contains('gender:"Women"'));
      });

      test('builds subcategory filter', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedSubcategory: 'Dresses',
        );
        expect(filters, contains('subcategory:"Dresses"'));
      });

      test('builds brand filter with OR', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedBrands: ['Nike', 'Adidas'],
        );
        expect(filters.any((f) => f.contains('brandModel:"Nike"')), true);
        expect(filters.any((f) => f.contains('brandModel:"Adidas"')), true);
        expect(filters.any((f) => f.contains(' OR ')), true);
      });

      test('builds type filter', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedTypes: ['T-Shirt'],
        );
        expect(filters.any((f) => f.contains('attributes.clothingType:"T-Shirt"')), true);
      });

      test('builds fit filter', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedFits: ['Slim'],
        );
        expect(filters.any((f) => f.contains('attributes.clothingFit:"Slim"')), true);
      });

      test('builds color filter', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          selectedColors: ['Red'],
        );
        expect(filters.any((f) => f.contains('colorImages.Red:*')), true);
      });

      test('builds price filters', () {
        final filters = TestableAlgoliaFilterBuilder.buildFilters(
          minPrice: 100,
          maxPrice: 500,
        );
        expect(filters, contains('price >= 100.0'));
        expect(filters, contains('price <= 500.0'));
      });
    });
  });

  // ============================================================================
  // PRODUCT FILTER TESTS
  // ============================================================================
  group('TestableProductFilter', () {
    late List<TestableProduct> testProducts;

    setUp(() {
      testProducts = [
        TestableProduct(
          id: '1',
          productName: 'Nike Running Shoes',
          brandModel: 'Nike',
          price: 150,
          discountPercentage: 20,
          purchaseCount: 100,
          attributes: {'clothingType': 'Shoes', 'clothingFit': 'Regular', 'clothingSizes': ['M', 'L']},
          colorImages: {'Red': 'url', 'Blue': 'url'},
        ),
        TestableProduct(
          id: '2',
          productName: 'Adidas T-Shirt',
          brandModel: 'Adidas',
          price: 50,
          discountPercentage: 0,
          purchaseCount: 50,
          attributes: {'clothingType': 'T-Shirt', 'clothingFit': 'Slim', 'clothingSizes': ['S', 'M']},
          colorImages: {'Black': 'url'},
        ),
        TestableProduct(
          id: '3',
          productName: 'Puma Jacket',
          brandModel: 'Puma',
          price: 200,
          discountPercentage: 10,
          purchaseCount: 25,
          attributes: {'clothingType': 'Jacket', 'clothingFit': 'Regular', 'clothingSizes': ['L', 'XL']},
          colorImages: {'Green': 'url', 'Black': 'url'},
        ),
      ];
    });

    group('applyFilters', () {
      test('filters by search query', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          searchQuery: 'Nike',
        );
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('filters by brand', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedBrands: ['Adidas'],
        );
        expect(result.length, 1);
        expect(result.first.id, '2');
      });

      test('filters by multiple brands', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedBrands: ['Nike', 'Puma'],
        );
        expect(result.length, 2);
      });

      test('filters by type', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedTypes: ['T-Shirt'],
        );
        expect(result.length, 1);
        expect(result.first.id, '2');
      });

      test('filters by fit', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedFits: ['Slim'],
        );
        expect(result.length, 1);
        expect(result.first.id, '2');
      });

      test('filters by size', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedSizes: ['XL'],
        );
        expect(result.length, 1);
        expect(result.first.id, '3');
      });

      test('filters by color', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedColors: ['Red'],
        );
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('filters by min price', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          minPrice: 100,
        );
        expect(result.length, 2);
      });

      test('filters by max price', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          maxPrice: 100,
        );
        expect(result.length, 1);
        expect(result.first.id, '2');
      });

      test('filters by price range', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          minPrice: 100,
          maxPrice: 180,
        );
        expect(result.length, 1);
        expect(result.first.id, '1');
      });

      test('combines multiple filters', () {
        final result = TestableProductFilter.applyFilters(
          testProducts,
          selectedColors: ['Black'],
          maxPrice: 100,
        );
        expect(result.length, 1);
        expect(result.first.id, '2');
      });
    });

    group('filterDeals', () {
      test('returns only products with discount', () {
        final deals = TestableProductFilter.filterDeals(testProducts);
        expect(deals.length, 2);
        expect(deals.every((p) => (p.discountPercentage ?? 0) > 0), true);
      });
    });

    group('sortByBestSellers', () {
      test('sorts by purchase count descending', () {
        final sorted = TestableProductFilter.sortByBestSellers(testProducts);
        expect(sorted[0].id, '1'); // 100 purchases
        expect(sorted[1].id, '2'); // 50 purchases
        expect(sorted[2].id, '3'); // 25 purchases
      });
    });
  });

  // ============================================================================
  // PAGINATION STATE TESTS
  // ============================================================================
  group('TestablePaginationState', () {
    late TestablePaginationState pagination;

    setUp(() {
      pagination = TestablePaginationState();
    });

    group('initial state', () {
      test('starts with hasMore true', () {
        expect(pagination.hasMore, true);
      });

      test('starts with isLoadingMore false', () {
        expect(pagination.isLoadingMore, false);
      });

      test('shouldLoadMore is true initially', () {
        expect(pagination.shouldLoadMore, true);
      });
    });

    group('processPage', () {
      test('sets hasMore false when empty results', () {
        pagination.processPage(0);
        expect(pagination.hasMore, false);
      });

      test('sets hasMore false when results less than limit', () {
        pagination.processPage(5);
        expect(pagination.hasMore, false);
      });

      test('keeps hasMore true when results equal limit', () {
        pagination.processPage(10);
        expect(pagination.hasMore, true);
      });

      test('accumulates loaded count', () {
        pagination.processPage(10);
        pagination.processPage(10);
        expect(pagination.loadedCount, 20);
      });
    });

    group('reset', () {
      test('resets all state', () {
        pagination.processPage(5);
        pagination.isLoadingMore = true;

        pagination.reset();

        expect(pagination.hasMore, true);
        expect(pagination.isLoadingMore, false);
        expect(pagination.loadedCount, 0);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('circuit breaker prevents retry storm after network failure', () {
      final breaker = TestableCircuitBreaker();

      // Simulate 3 network failures
      breaker.onFailure();
      breaker.onFailure();
      breaker.onFailure();

      // Should be open, blocking further requests
      expect(breaker.isOpen(), true);

      // Try to make more requests - they should be blocked
      // In production, this prevents hammering a failing service
    });

    test('shop role verification prevents privilege escalation', () {
      final shopData = {
        'ownerId': 'owner123',
        'coOwners': ['coowner1'],
        'editors': ['editor1'],
        'viewers': ['viewer1'],
      };

      // User tries to claim owner role
      expect(
        TestableRoleVerifier.verifyUserRole('attacker', 'owner', shopData),
        false,
      );

      // User tries unknown role
      expect(
        TestableRoleVerifier.verifyUserRole('attacker', 'admin', shopData),
        false,
      );

      // Legitimate owner access
      expect(
        TestableRoleVerifier.verifyUserRole('owner123', 'owner', shopData),
        true,
      );
    });

    test('cache size prevents memory exhaustion', () {
      // Simulate a shop with many products
      final largeProductList = List.generate(
        300,
        (i) => '{"id": "$i", "name": "Product $i"}',
      ).join(',');
      final largeJson = '[$largeProductList]';

      // Check if within limits
      final sizeBytes = TestableCacheManager.getCacheSizeBytes(largeJson);
      final exceeds = TestableCacheManager.isCacheSizeExceeded(largeJson);

      // For this test data, should not exceed
      expect(sizeBytes < 5 * 1024 * 1024, true);
      expect(exceeds, false);

      // But trimming should still work for in-memory list
      final items = List.generate(300, (i) => i);
      final trimmed = TestableCacheManager.trimListIfNeeded(items);
      expect(trimmed.length, 200);
    });

    test('refresh cooldown prevents API rate limiting', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cooldown = TestableRefreshCooldown(nowProvider: () => mockNow);

      // First refresh - allowed
      expect(cooldown.canRefresh, true);
      cooldown.markRefresh();

      // Immediate second refresh - blocked
      expect(cooldown.canRefresh, false);
      expect(cooldown.remainingCooldownTime.inSeconds, 30);

      // After 15 seconds - still blocked
      mockNow = mockNow.add(const Duration(seconds: 15));
      expect(cooldown.canRefresh, false);
      expect(cooldown.remainingCooldownTime.inSeconds, 15);

      // After 30 seconds - allowed
      mockNow = mockNow.add(const Duration(seconds: 15));
      expect(cooldown.canRefresh, true);
    });

    test('filter summary correctly describes complex filter state', () {
      final summary = TestableFilterSummary.generate(
        selectedGender: 'Women',
        selectedBrands: ['Zara', 'H&M', 'Mango'],
        selectedSizes: ['S', 'M'],
        selectedColors: ['Black'],
        minPrice: 50,
        maxPrice: 200,
      );

      expect(summary, 'Women, 3 brands, 2 sizes, 1 color, 50-200 TL');
    });
  });
}