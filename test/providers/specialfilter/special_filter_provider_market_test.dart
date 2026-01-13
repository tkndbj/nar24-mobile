// test/providers/special_filter_provider_market_test.dart
//
// Unit tests for SpecialFilterProviderMarket pure logic
// Tests the EXACT logic from lib/providers/special_filter_provider_market.dart
//
// Run: flutter test test/providers/special_filter_provider_market_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_special_filter_provider_market.dart';

void main() {
  // ============================================================================
  // CONFIG TESTS
  // ============================================================================
  group('TestableSpecialFilterConfig', () {
    test('cache TTL is 5 minutes', () {
      expect(TestableSpecialFilterConfig.cacheTTL, const Duration(minutes: 5));
    });

    test('max cache size is 30', () {
      expect(TestableSpecialFilterConfig.maxCacheSize, 30);
    });

    test('max products per filter is 500', () {
      expect(TestableSpecialFilterConfig.maxProductsPerFilter, 500);
    });

    test('max notifiers per type is 20', () {
      expect(TestableSpecialFilterConfig.maxNotifiersPerType, 20);
    });

    test('permanent filters includes expected categories', () {
      expect(TestableSpecialFilterConfig.permanentFilters, contains('Women'));
      expect(TestableSpecialFilterConfig.permanentFilters, contains('Men'));
      expect(TestableSpecialFilterConfig.permanentFilters, contains('Electronics'));
    });

    test('gender filters are Women and Men', () {
      expect(TestableSpecialFilterConfig.genderFilters, ['Women', 'Men']);
    });
  });

  // ============================================================================
  // CACHE STALENESS CHECKER TESTS
  // ============================================================================
  group('TestableCacheStalenessChecker', () {
    late TestableCacheStalenessChecker checker;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      checker = TestableCacheStalenessChecker(
        nowProvider: () => currentTime,
      );
    });

    test('never fetched filter is stale', () {
      expect(checker.isStale('Women'), true);
    });

    test('just fetched filter is not stale', () {
      checker.markFetched('Women');
      expect(checker.isStale('Women'), false);
    });

    test('filter becomes stale after TTL', () {
      checker.markFetched('Women');
      expect(checker.isStale('Women'), false);

      // Advance time past TTL (5 minutes + 1 second)
      currentTime = currentTime.add(const Duration(minutes: 5, seconds: 1));
      expect(checker.isStale('Women'), true);
    });

    test('filter not stale at exactly TTL', () {
      checker.markFetched('Women');

      // Advance time to exactly TTL
      currentTime = currentTime.add(const Duration(minutes: 5));
      expect(checker.isStale('Women'), false);
    });

    test('hasBeenFetched returns correct state', () {
      expect(checker.hasBeenFetched('Women'), false);
      checker.markFetched('Women');
      expect(checker.hasBeenFetched('Women'), true);
    });

    test('clearFetchTime makes filter stale again', () {
      checker.markFetched('Women');
      expect(checker.isStale('Women'), false);

      checker.clearFetchTime('Women');
      expect(checker.isStale('Women'), true);
    });

    test('getTimeSinceLastFetch returns correct duration', () {
      checker.markFetched('Women');
      expect(checker.getTimeSinceLastFetch('Women'), Duration.zero);

      currentTime = currentTime.add(const Duration(minutes: 2));
      expect(checker.getTimeSinceLastFetch('Women'), const Duration(minutes: 2));
    });
  });

  // ============================================================================
  // CACHE KEY BUILDER TESTS
  // ============================================================================
  group('TestableCacheKeyBuilder', () {
    group('buildFilterPageKey', () {
      test('builds correct format', () {
        expect(
          TestableCacheKeyBuilder.buildFilterPageKey('Women', 0),
          'Women|0',
        );
      });

      test('handles different pages', () {
        expect(
          TestableCacheKeyBuilder.buildFilterPageKey('Women', 5),
          'Women|5',
        );
      });
    });

    group('buildSubcategoryKey', () {
      test('builds correct format', () {
        expect(
          TestableCacheKeyBuilder.buildSubcategoryKey('Electronics', 'Phones'),
          'Electronics|Phones',
        );
      });
    });

    group('buildSubcategoryPageKey', () {
      test('builds correct format', () {
        expect(
          TestableCacheKeyBuilder.buildSubcategoryPageKey('Electronics', 'Phones', 2),
          'Electronics|Phones|2',
        );
      });
    });

    group('parseFilterType', () {
      test('extracts filter type from key', () {
        expect(TestableCacheKeyBuilder.parseFilterType('Women|0'), 'Women');
      });

      test('handles subcategory keys', () {
        expect(
          TestableCacheKeyBuilder.parseFilterType('Electronics|Phones|2'),
          'Electronics',
        );
      });
    });

    group('parsePage', () {
      test('extracts page from simple key', () {
        expect(TestableCacheKeyBuilder.parsePage('Women|3'), 3);
      });

      test('extracts page from subcategory key', () {
        expect(TestableCacheKeyBuilder.parsePage('Electronics|Phones|2'), 2);
      });
    });

    group('matchesFilterType', () {
      test('returns true for matching prefix', () {
        expect(
          TestableCacheKeyBuilder.matchesFilterType('Women|0', 'Women'),
          true,
        );
      });

      test('returns false for non-matching prefix', () {
        expect(
          TestableCacheKeyBuilder.matchesFilterType('Women|0', 'Men'),
          false,
        );
      });
    });
  });

  // ============================================================================
  // NUMERIC FIELD DETECTOR TESTS
  // ============================================================================
  group('TestableNumericFieldDetector', () {
    group('isNumericField', () {
      test('returns true for numeric fields', () {
        expect(TestableNumericFieldDetector.isNumericField('averageRating'), true);
        expect(TestableNumericFieldDetector.isNumericField('price'), true);
        expect(TestableNumericFieldDetector.isNumericField('discountPercentage'), true);
        expect(TestableNumericFieldDetector.isNumericField('stockQuantity'), true);
        expect(TestableNumericFieldDetector.isNumericField('purchaseCount'), true);
      });

      test('returns false for non-numeric fields', () {
        expect(TestableNumericFieldDetector.isNumericField('title'), false);
        expect(TestableNumericFieldDetector.isNumericField('category'), false);
        expect(TestableNumericFieldDetector.isNumericField('brandModel'), false);
      });
    });

    group('convertToNumber', () {
      test('converts string to double', () {
        expect(TestableNumericFieldDetector.convertToNumber('4.5'), 4.5);
      });

      test('converts string to int when no decimal', () {
        expect(TestableNumericFieldDetector.convertToNumber('100'), 100);
      });

      test('returns original string if not numeric', () {
        expect(TestableNumericFieldDetector.convertToNumber('abc'), 'abc');
      });

      test('returns non-string values unchanged', () {
        expect(TestableNumericFieldDetector.convertToNumber(42), 42);
        expect(TestableNumericFieldDetector.convertToNumber(3.14), 3.14);
      });
    });

    group('convertIfNumeric', () {
      test('converts value for numeric field', () {
        expect(
          TestableNumericFieldDetector.convertIfNumeric('price', '99.99'),
          99.99,
        );
      });

      test('does not convert value for non-numeric field', () {
        expect(
          TestableNumericFieldDetector.convertIfNumeric('title', '99.99'),
          '99.99',
        );
      });
    });
  });

  // ============================================================================
  // PRODUCT VALIDATOR TESTS
  // ============================================================================
  group('TestableProductValidator', () {
    group('isValidProduct', () {
      test('returns true for valid product', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 99.99,
            averageRating: 4.5,
          ),
          true,
        );
      });

      test('returns false for empty id', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: '',
            productName: 'Test Product',
            price: 99.99,
            averageRating: 4.5,
          ),
          false,
        );
      });

      test('returns false for empty product name', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: '',
            price: 99.99,
            averageRating: 4.5,
          ),
          false,
        );
      });

      test('returns false for negative price', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: -10.0,
            averageRating: 4.5,
          ),
          false,
        );
      });

      test('returns true for zero price (free product)', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 0.0,
            averageRating: 4.5,
          ),
          true,
        );
      });

      test('returns false for rating below 0', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 99.99,
            averageRating: -1.0,
          ),
          false,
        );
      });

      test('returns false for rating above 5', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 99.99,
            averageRating: 5.1,
          ),
          false,
        );
      });

      test('returns true for rating exactly 0', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 99.99,
            averageRating: 0.0,
          ),
          true,
        );
      });

      test('returns true for rating exactly 5', () {
        expect(
          TestableProductValidator.isValidProduct(
            id: 'prod_123',
            productName: 'Test Product',
            price: 99.99,
            averageRating: 5.0,
          ),
          true,
        );
      });
    });

    group('getValidationErrors', () {
      test('returns all errors for invalid product', () {
        final errors = TestableProductValidator.getValidationErrors(
          id: '',
          productName: '',
          price: -10.0,
          averageRating: 6.0,
        );

        expect(errors, contains('Empty ID'));
        expect(errors, contains('Empty product name'));
        expect(errors, contains('Negative price'));
        expect(errors, contains('Rating above 5'));
      });

      test('returns empty for valid product', () {
        final errors = TestableProductValidator.getValidationErrors(
          id: 'prod_123',
          productName: 'Test',
          price: 10.0,
          averageRating: 4.0,
        );

        expect(errors, isEmpty);
      });
    });
  });

  // ============================================================================
  // SORT OPTION MAPPER TESTS
  // ============================================================================
  group('TestableSortOptionMapper', () {
    group('getSortField', () {
      test('returns title for alphabetical', () {
        expect(TestableSortOptionMapper.getSortField('alphabetical'), 'title');
      });

      test('returns price for price_asc', () {
        expect(TestableSortOptionMapper.getSortField('price_asc'), 'price');
      });

      test('returns price for price_desc', () {
        expect(TestableSortOptionMapper.getSortField('price_desc'), 'price');
      });

      test('returns promotionScore for date', () {
        expect(TestableSortOptionMapper.getSortField('date'), 'promotionScore');
      });

      test('returns promotionScore for unknown', () {
        expect(TestableSortOptionMapper.getSortField('unknown'), 'promotionScore');
      });
    });

    group('isSortDescending', () {
      test('alphabetical is ascending', () {
        expect(TestableSortOptionMapper.isSortDescending('alphabetical'), false);
      });

      test('price_asc is ascending', () {
        expect(TestableSortOptionMapper.isSortDescending('price_asc'), false);
      });

      test('price_desc is descending', () {
        expect(TestableSortOptionMapper.isSortDescending('price_desc'), true);
      });

      test('date is descending', () {
        expect(TestableSortOptionMapper.isSortDescending('date'), true);
      });
    });

    group('needsSecondarySort', () {
      test('date needs secondary sort', () {
        expect(TestableSortOptionMapper.needsSecondarySort('date'), true);
      });

      test('other options dont need secondary sort', () {
        expect(TestableSortOptionMapper.needsSecondarySort('alphabetical'), false);
        expect(TestableSortOptionMapper.needsSecondarySort('price_asc'), false);
      });
    });
  });

  // ============================================================================
  // QUICK FILTER MAPPER TESTS
  // ============================================================================
  group('TestableQuickFilterMapper', () {
    group('getFilterCondition', () {
      test('deals filter condition', () {
        final condition = TestableQuickFilterMapper.getFilterCondition('deals');
        expect(condition?.field, 'discountPercentage');
        expect(condition?.operator, '>');
        expect(condition?.value, 0);
      });

      test('boosted filter condition', () {
        final condition = TestableQuickFilterMapper.getFilterCondition('boosted');
        expect(condition?.field, 'isBoosted');
        expect(condition?.operator, '==');
        expect(condition?.value, true);
      });

      test('trending filter condition', () {
        final condition = TestableQuickFilterMapper.getFilterCondition('trending');
        expect(condition?.field, 'dailyClickCount');
        expect(condition?.operator, '>=');
        expect(condition?.value, 10);
      });

      test('fiveStar filter condition', () {
        final condition = TestableQuickFilterMapper.getFilterCondition('fiveStar');
        expect(condition?.field, 'averageRating');
        expect(condition?.operator, '==');
        expect(condition?.value, 5);
      });

      test('bestSellers filter condition', () {
        final condition = TestableQuickFilterMapper.getFilterCondition('bestSellers');
        expect(condition?.field, 'purchaseCount');
        expect(condition?.operator, '>');
        expect(condition?.value, 0);
      });

      test('null for unknown filter', () {
        expect(TestableQuickFilterMapper.getFilterCondition('unknown'), null);
      });

      test('null for null filter', () {
        expect(TestableQuickFilterMapper.getFilterCondition(null), null);
      });
    });

    group('isValidFilterKey', () {
      test('returns true for valid keys', () {
        expect(TestableQuickFilterMapper.isValidFilterKey('deals'), true);
        expect(TestableQuickFilterMapper.isValidFilterKey('boosted'), true);
        expect(TestableQuickFilterMapper.isValidFilterKey('trending'), true);
        expect(TestableQuickFilterMapper.isValidFilterKey('fiveStar'), true);
        expect(TestableQuickFilterMapper.isValidFilterKey('bestSellers'), true);
      });

      test('returns false for invalid keys', () {
        expect(TestableQuickFilterMapper.isValidFilterKey('invalid'), false);
        expect(TestableQuickFilterMapper.isValidFilterKey(''), false);
      });
    });
  });

  // ============================================================================
  // LRU CACHE ENFORCER TESTS
  // ============================================================================
  group('TestableLRUCacheEnforcer', () {
    late TestableLRUCacheEnforcer<String> cache;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableLRUCacheEnforcer<String>(
        maxSize: 3,
        nowProvider: () => currentTime,
      );
    });

    test('stores and retrieves values', () {
      cache.set('key1', 'value1');
      expect(cache.get('key1'), 'value1');
    });

    test('returns null for missing key', () {
      expect(cache.get('missing'), null);
    });

    test('evicts oldest when exceeding max size', () {
      cache.set('key1', 'value1');
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('key2', 'value2');
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('key3', 'value3');
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('key4', 'value4');

      expect(cache.size, 3);
      expect(cache.get('key1'), null); // Oldest, evicted
      expect(cache.get('key2'), 'value2');
      expect(cache.get('key3'), 'value3');
      expect(cache.get('key4'), 'value4');
    });

    test('removeByPrefix removes matching keys', () {
      cache.set('Women|0', 'w0');
      cache.set('Women|1', 'w1');
      cache.set('Men|0', 'm0');

      cache.removeByPrefix('Women');

      expect(cache.get('Women|0'), null);
      expect(cache.get('Women|1'), null);
      expect(cache.get('Men|0'), 'm0');
    });

    test('clear removes all entries', () {
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      cache.clear();

      expect(cache.size, 0);
    });

    test('oldestKey returns correct key', () {
      cache.set('key1', 'value1');
      currentTime = currentTime.add(const Duration(seconds: 1));
      cache.set('key2', 'value2');

      expect(cache.oldestKey, 'key1');
    });
  });

  // ============================================================================
  // HAS MORE CALCULATOR TESTS
  // ============================================================================
  group('TestableHasMoreCalculator', () {
    test('hasMore true when results equal limit', () {
      expect(TestableHasMoreCalculator.calculateHasMore(20, 20), true);
    });

    test('hasMore false when results less than limit', () {
      expect(TestableHasMoreCalculator.calculateHasMore(15, 20), false);
    });

    test('hasMore true when results exceed limit', () {
      expect(TestableHasMoreCalculator.calculateHasMore(25, 20), true);
    });

    test('subcategory hasMore calculation', () {
      expect(TestableHasMoreCalculator.calculateHasMoreForSubcategories(10, 5), true);
      expect(TestableHasMoreCalculator.calculateHasMoreForSubcategories(5, 10), false);
    });
  });

  // ============================================================================
  // ORPHANED DATA CLEANER TESTS
  // ============================================================================
  group('TestableOrphanedDataCleaner', () {
    test('findOrphanedKeys identifies invalid keys', () {
      final existing = {'Women', 'Men', 'OldFilter', 'DeletedFilter'};
      final valid = {'Women', 'Men', 'Electronics'};

      final orphaned = TestableOrphanedDataCleaner.findOrphanedKeys(existing, valid);

      expect(orphaned, containsAll(['OldFilter', 'DeletedFilter']));
      expect(orphaned, isNot(contains('Women')));
      expect(orphaned, isNot(contains('Men')));
    });

    test('findNotifiersToCleanup keeps permanent filters', () {
      final existing = {'Women', 'Men', 'CustomFilter1', 'CustomFilter2'};
      final active = <String>{}; // No active custom filters

      final toCleanup = TestableOrphanedDataCleaner.findNotifiersToCleanup(
        existing,
        active,
      );

      // Women and Men are permanent, should not be cleaned
      expect(toCleanup, containsAll(['CustomFilter1', 'CustomFilter2']));
      expect(toCleanup, isNot(contains('Women')));
      expect(toCleanup, isNot(contains('Men')));
    });

    test('findSubcategoryNotifiersToCleanup extracts filter type', () {
      final existing = {'Women|Dresses', 'CustomFilter|Items'};
      final active = <String>{};

      final toCleanup = TestableOrphanedDataCleaner.findSubcategoryNotifiersToCleanup(
        existing,
        active,
      );

      expect(toCleanup, contains('CustomFilter|Items'));
      expect(toCleanup, isNot(contains('Women|Dresses')));
    });
  });

  // ============================================================================
  // SUBCATEGORY FILTER LOGIC TESTS
  // ============================================================================
  group('TestableSubcategoryFilterLogic', () {
    group('shouldApplySubcategoryFilter', () {
      test('returns true when subcategoryId differs from category', () {
        expect(
          TestableSubcategoryFilterLogic.shouldApplySubcategoryFilter(
            'Electronics',
            'Phones',
          ),
          true,
        );
      });

      test('returns false when subcategoryId equals category', () {
        expect(
          TestableSubcategoryFilterLogic.shouldApplySubcategoryFilter(
            'Electronics',
            'Electronics',
          ),
          false,
        );
      });

      test('returns false when subcategoryId is empty', () {
        expect(
          TestableSubcategoryFilterLogic.shouldApplySubcategoryFilter(
            'Electronics',
            '',
          ),
          false,
        );
      });
    });

    group('isSubsubcategoryActingAsSubcategory', () {
      test('returns true when at top level', () {
        expect(
          TestableSubcategoryFilterLogic.isSubsubcategoryActingAsSubcategory(
            'Electronics',
            'Electronics',
          ),
          true,
        );
      });

      test('returns false when in subcategory', () {
        expect(
          TestableSubcategoryFilterLogic.isSubsubcategoryActingAsSubcategory(
            'Electronics',
            'Phones',
          ),
          false,
        );
      });
    });

    group('getSubsubcategoryFilterField', () {
      test('returns subcategory when at top level', () {
        expect(
          TestableSubcategoryFilterLogic.getSubsubcategoryFilterField(
            'Electronics',
            'Electronics',
          ),
          'subcategory',
        );
      });

      test('returns subsubcategory when in subcategory', () {
        expect(
          TestableSubcategoryFilterLogic.getSubsubcategoryFilterField(
            'Electronics',
            'Phones',
          ),
          'subsubcategory',
        );
      });
    });
  });

  // ============================================================================
  // ATTRIBUTE FILTER OPERATOR TESTS
  // ============================================================================
  group('TestableAttributeFilterOperator', () {
    test('all expected operators are valid', () {
      expect(TestableAttributeFilterOperator.isValidOperator('=='), true);
      expect(TestableAttributeFilterOperator.isValidOperator('!='), true);
      expect(TestableAttributeFilterOperator.isValidOperator('>'), true);
      expect(TestableAttributeFilterOperator.isValidOperator('>='), true);
      expect(TestableAttributeFilterOperator.isValidOperator('<'), true);
      expect(TestableAttributeFilterOperator.isValidOperator('<='), true);
      expect(TestableAttributeFilterOperator.isValidOperator('array-contains'), true);
      expect(TestableAttributeFilterOperator.isValidOperator('array-contains-any'), true);
      expect(TestableAttributeFilterOperator.isValidOperator('in'), true);
      expect(TestableAttributeFilterOperator.isValidOperator('not-in'), true);
    });

    test('invalid operator returns false', () {
      expect(TestableAttributeFilterOperator.isValidOperator('LIKE'), false);
      expect(TestableAttributeFilterOperator.isValidOperator(''), false);
    });

    test('requiresArrayValue identifies correct operators', () {
      expect(TestableAttributeFilterOperator.requiresArrayValue('array-contains-any'), true);
      expect(TestableAttributeFilterOperator.requiresArrayValue('in'), true);
      expect(TestableAttributeFilterOperator.requiresArrayValue('not-in'), true);
      expect(TestableAttributeFilterOperator.requiresArrayValue('=='), false);
      expect(TestableAttributeFilterOperator.requiresArrayValue('array-contains'), false);
    });

    test('isComparisonOperator identifies correct operators', () {
      expect(TestableAttributeFilterOperator.isComparisonOperator('>'), true);
      expect(TestableAttributeFilterOperator.isComparisonOperator('>='), true);
      expect(TestableAttributeFilterOperator.isComparisonOperator('<'), true);
      expect(TestableAttributeFilterOperator.isComparisonOperator('<='), true);
      expect(TestableAttributeFilterOperator.isComparisonOperator('=='), false);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('filtering products in Women category top-level', () {
      // User navigates to Women category (subcategoryId == 'Women')
      final shouldFilterSubcategory =
          TestableSubcategoryFilterLogic.shouldApplySubcategoryFilter('Women', 'Women');
      expect(shouldFilterSubcategory, false);

      // User selects "Dresses" from filter - this acts as subcategory filter
      final isActingAsSubcategory =
          TestableSubcategoryFilterLogic.isSubsubcategoryActingAsSubcategory('Women', 'Women');
      expect(isActingAsSubcategory, true);

      final filterField =
          TestableSubcategoryFilterLogic.getSubsubcategoryFilterField('Women', 'Women');
      expect(filterField, 'subcategory');
    });

    test('cache eviction under memory pressure', () {
      var time = DateTime(2024, 1, 1);
      final cache = TestableLRUCacheEnforcer<List<String>>(
        maxSize: 3,
        nowProvider: () => time,
      );

      // Fill cache
      cache.set('Women|0', ['p1', 'p2']);
      time = time.add(const Duration(seconds: 1));
      cache.set('Men|0', ['p3', 'p4']);
      time = time.add(const Duration(seconds: 1));
      cache.set('Electronics|0', ['p5', 'p6']);

      // Add new entry, oldest should be evicted
      time = time.add(const Duration(seconds: 1));
      cache.set('Home|0', ['p7', 'p8']);

      expect(cache.size, 3);
      expect(cache.containsKey('Women|0'), false); // Evicted
    });

    test('quick filter query building', () {
      // User taps "Deals" quick filter
      final condition = TestableQuickFilterMapper.getFilterCondition('deals');
      expect(condition, isNotNull);
      expect(condition!.field, 'discountPercentage');
      expect(condition.operator, '>');
      expect(condition.value, 0);

      // Validate the condition would be applied correctly
      final isValidOperator = TestableAttributeFilterOperator.isValidOperator(condition.operator);
      expect(isValidOperator, true);
    });

    test('numeric field conversion from string input', () {
      // Firebase sometimes returns numbers as strings
      final priceString = '99.99';
      final ratingString = '4';

      final price = TestableNumericFieldDetector.convertIfNumeric('price', priceString);
      final rating = TestableNumericFieldDetector.convertIfNumeric('averageRating', ratingString);
      final title = TestableNumericFieldDetector.convertIfNumeric('title', 'Product Name');

      expect(price, 99.99);
      expect(rating, 4);
      expect(title, 'Product Name'); // Not converted
    });

    test('product validation catches invalid data', () {
      // Product with rating of 6 (invalid)
      final isValid = TestableProductValidator.isValidProduct(
        id: 'prod_123',
        productName: 'Test',
        price: 100.0,
        averageRating: 6.0, // Invalid!
      );

      expect(isValid, false);

      final errors = TestableProductValidator.getValidationErrors(
        id: 'prod_123',
        productName: 'Test',
        price: 100.0,
        averageRating: 6.0,
      );

      expect(errors, contains('Rating above 5'));
    });
  });
}