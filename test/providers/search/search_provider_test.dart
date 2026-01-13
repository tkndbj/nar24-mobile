// test/providers/search_provider_test.dart
//
// Unit tests for SearchProvider pure logic
// Tests the EXACT logic from lib/providers/search_provider.dart
//
// Run: flutter test test/providers/search_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_search_provider.dart';

void main() {
  // ============================================================================
  // PRODUCT RESULT COMBINER TESTS
  // ============================================================================
  group('TestableProductResultCombiner', () {
    group('combineResults', () {
      test('combines results from multiple indices', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
        ];
        final shopResults = [
          TestableSuggestion(id: 'p3', name: 'Product 3', price: 30.0),
          TestableSuggestion(id: 'p4', name: 'Product 4', price: 40.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults, shopResults],
          10,
        );

        expect(combined.length, 4);
        expect(combined.map((p) => p.id), ['p1', 'p2', 'p3', 'p4']);
      });

      test('deduplicates by ID across indices', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
        ];
        final shopResults = [
          TestableSuggestion(id: 'p2', name: 'Product 2 Shop', price: 25.0), // Duplicate ID
          TestableSuggestion(id: 'p3', name: 'Product 3', price: 30.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults, shopResults],
          10,
        );

        expect(combined.length, 3);
        expect(combined.map((p) => p.id), ['p1', 'p2', 'p3']);
        // First occurrence wins - main index version
        expect(combined[1].price, 20.0);
      });

      test('respects limit parameter', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
          TestableSuggestion(id: 'p3', name: 'Product 3', price: 30.0),
        ];
        final shopResults = [
          TestableSuggestion(id: 'p4', name: 'Product 4', price: 40.0),
          TestableSuggestion(id: 'p5', name: 'Product 5', price: 50.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults, shopResults],
          3,
        );

        expect(combined.length, 3);
        expect(combined.map((p) => p.id), ['p1', 'p2', 'p3']);
      });

      test('excludes existing IDs', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
          TestableSuggestion(id: 'p3', name: 'Product 3', price: 30.0),
        ];

        final existingIds = {'p1', 'p2'};

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults],
          10,
          existingIds: existingIds,
        );

        expect(combined.length, 1);
        expect(combined[0].id, 'p3');
      });

      test('handles empty results from one index', () {
        final mainResults = <TestableSuggestion>[];
        final shopResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults, shopResults],
          10,
        );

        expect(combined.length, 2);
        expect(combined.map((p) => p.id), ['p1', 'p2']);
      });

      test('handles empty results from all indices', () {
        final combined = TestableProductResultCombiner.combineResults(
          [<TestableSuggestion>[], <TestableSuggestion>[]],
          10,
        );

        expect(combined, isEmpty);
      });

      test('stops early when limit reached mid-list', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0),
        ];
        final shopResults = [
          TestableSuggestion(id: 'p3', name: 'Product 3', price: 30.0),
          TestableSuggestion(id: 'p4', name: 'Product 4', price: 40.0),
          TestableSuggestion(id: 'p5', name: 'Product 5', price: 50.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults, shopResults],
          4,
        );

        expect(combined.length, 4);
        // Should stop at p4, not include p5
        expect(combined.map((p) => p.id), ['p1', 'p2', 'p3', 'p4']);
      });

      test('handles limit of zero', () {
        final mainResults = [
          TestableSuggestion(id: 'p1', name: 'Product 1', price: 10.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults],
          0,
        );

        expect(combined, isEmpty);
      });

      test('preserves order from first index', () {
        final mainResults = [
          TestableSuggestion(id: 'p3', name: 'Third', price: 30.0),
          TestableSuggestion(id: 'p1', name: 'First', price: 10.0),
          TestableSuggestion(id: 'p2', name: 'Second', price: 20.0),
        ];

        final combined = TestableProductResultCombiner.combineResults(
          [mainResults],
          10,
        );

        // Should preserve original order
        expect(combined.map((p) => p.id), ['p3', 'p1', 'p2']);
      });
    });
  });

  // ============================================================================
  // PAGINATION MANAGER TESTS
  // ============================================================================
  group('TestablePaginationManager', () {
    late TestablePaginationManager manager;

    setUp(() {
      manager = TestablePaginationManager();
    });

    group('initial state', () {
      test('starts with correct defaults', () {
        expect(manager.currentProductCount, 0);
        expect(manager.hasMoreProducts, true);
        expect(manager.isLoadingMore, false);
        expect(manager.lastSearchTerm, null);
      });

      test('canLoadMore is true initially', () {
        expect(manager.canLoadMore, true);
      });
    });

    group('canLoadMore', () {
      test('returns true when under max and hasMore', () {
        manager.currentProductCount = 10;
        manager.hasMoreProducts = true;

        expect(manager.canLoadMore, true);
      });

      test('returns false when at max suggestions', () {
        manager.currentProductCount = 20;
        manager.hasMoreProducts = true;

        expect(manager.canLoadMore, false);
      });

      test('returns false when hasMoreProducts is false', () {
        manager.currentProductCount = 10;
        manager.hasMoreProducts = false;

        expect(manager.canLoadMore, false);
      });

      test('returns false when over max suggestions', () {
        manager.currentProductCount = 25;
        manager.hasMoreProducts = true;

        expect(manager.canLoadMore, false);
      });
    });

    group('shouldAllowLoadMore', () {
      test('returns true when all conditions met', () {
        manager.currentProductCount = 10;
        manager.hasMoreProducts = true;
        manager.isLoadingMore = false;

        expect(
          manager.shouldAllowLoadMore(
            isDisposed: false,
            currentTerm: 'search term',
          ),
          true,
        );
      });

      test('returns false when disposed', () {
        expect(
          manager.shouldAllowLoadMore(
            isDisposed: true,
            currentTerm: 'search',
          ),
          false,
        );
      });

      test('returns false when already loading', () {
        manager.isLoadingMore = true;

        expect(
          manager.shouldAllowLoadMore(
            isDisposed: false,
            currentTerm: 'search',
          ),
          false,
        );
      });

      test('returns false when no more products', () {
        manager.hasMoreProducts = false;

        expect(
          manager.shouldAllowLoadMore(
            isDisposed: false,
            currentTerm: 'search',
          ),
          false,
        );
      });

      test('returns false when at max suggestions', () {
        manager.currentProductCount = 20;

        expect(
          manager.shouldAllowLoadMore(
            isDisposed: false,
            currentTerm: 'search',
          ),
          false,
        );
      });

      test('returns false when term is empty', () {
        expect(
          manager.shouldAllowLoadMore(
            isDisposed: false,
            currentTerm: '',
          ),
          false,
        );
      });

    });

    group('calculateFetchCount', () {
      test('returns loadMorePageSize when plenty of room', () {
        manager.currentProductCount = 10;

        expect(manager.calculateFetchCount(), 5); // loadMorePageSize
      });

      test('returns remaining when less than loadMorePageSize', () {
        manager.currentProductCount = 18;

        expect(manager.calculateFetchCount(), 2); // 20 - 18
      });

      test('returns 0 when at max', () {
        manager.currentProductCount = 20;

        expect(manager.calculateFetchCount(), 0);
      });

      test('returns loadMorePageSize when exactly loadMorePageSize remaining', () {
        manager.currentProductCount = 15;

        expect(manager.calculateFetchCount(), 5);
      });
    });

    group('onLoadSuccess', () {
      test('updates count and keeps hasMore true', () {
        manager.currentProductCount = 10;

        manager.onLoadSuccess(5, 5);

        expect(manager.currentProductCount, 15);
        expect(manager.hasMoreProducts, true);
      });

      test('sets hasMore false when received less than requested', () {
        manager.currentProductCount = 10;

        manager.onLoadSuccess(3, 5); // Requested 5, got 3

        expect(manager.currentProductCount, 13);
        expect(manager.hasMoreProducts, false);
      });

      test('sets hasMore false when received zero', () {
        manager.currentProductCount = 10;

        manager.onLoadSuccess(0, 5);

        expect(manager.currentProductCount, 10);
        expect(manager.hasMoreProducts, false);
      });
    });

    group('reset', () {
      test('resets all pagination state', () {
        manager.currentProductCount = 15;
        manager.hasMoreProducts = false;
        manager.isLoadingMore = true;

        manager.reset();

        expect(manager.currentProductCount, 0);
        expect(manager.hasMoreProducts, true);
        expect(manager.isLoadingMore, false);
      });
    });

    group('onInitialSearchComplete', () {
      test('updates count and keeps hasMore when full page', () {
        manager.onInitialSearchComplete(10);

        expect(manager.currentProductCount, 10);
        expect(manager.hasMoreProducts, true);
      });

      test('sets hasMore false when less than initial page size', () {
        manager.onInitialSearchComplete(7);

        expect(manager.currentProductCount, 7);
        expect(manager.hasMoreProducts, false);
      });

      test('sets hasMore false when zero results', () {
        manager.onInitialSearchComplete(0);

        expect(manager.currentProductCount, 0);
        expect(manager.hasMoreProducts, false);
      });
    });
  });

  // ============================================================================
  // SEARCH TERM VALIDATOR TESTS
  // ============================================================================
  group('TestableSearchTermValidator', () {
    group('normalize', () {
      test('trims whitespace', () {
        expect(TestableSearchTermValidator.normalize('  hello  '), 'hello');
      });

      test('handles empty string', () {
        expect(TestableSearchTermValidator.normalize(''), '');
      });

      test('handles whitespace only', () {
        expect(TestableSearchTermValidator.normalize('   '), '');
      });

      test('preserves internal whitespace', () {
        expect(TestableSearchTermValidator.normalize('  hello world  '), 'hello world');
      });
    });

    group('isValidForSearch', () {
      test('returns true for non-empty term', () {
        expect(TestableSearchTermValidator.isValidForSearch('hello'), true);
      });

      test('returns false for empty string', () {
        expect(TestableSearchTermValidator.isValidForSearch(''), false);
      });

      test('returns false for whitespace only', () {
        expect(TestableSearchTermValidator.isValidForSearch('   '), false);
      });

      test('returns true for term with internal spaces', () {
        expect(TestableSearchTermValidator.isValidForSearch('hello world'), true);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('search across main and shop indices with duplicates', () {
      // Simulates real Algolia response where same product exists in both indices
      final mainResults = [
        TestableSuggestion(id: 'ABC123', name: 'iPhone 15', price: 999.0),
        TestableSuggestion(id: 'DEF456', name: 'Samsung Galaxy', price: 899.0),
        TestableSuggestion(id: 'GHI789', name: 'Pixel 8', price: 699.0),
      ];
      final shopResults = [
        TestableSuggestion(id: 'ABC123', name: 'iPhone 15 Pro', price: 1099.0), // Duplicate
        TestableSuggestion(id: 'JKL012', name: 'OnePlus 12', price: 799.0),
        TestableSuggestion(id: 'MNO345', name: 'Xiaomi 14', price: 599.0),
      ];

      final combined = TestableProductResultCombiner.combineResults(
        [mainResults, shopResults],
        10,
      );

      // Should have 5 unique products
      expect(combined.length, 5);
      // ABC123 should be from main index (first occurrence)
      expect(combined.firstWhere((p) => p.id == 'ABC123').price, 999.0);
    });

    test('pagination flow: initial search then load more', () {
      final manager = TestablePaginationManager();

      // Initial search returns 10 products
      manager.onInitialSearchComplete(10);
      expect(manager.currentProductCount, 10);
      expect(manager.canLoadMore, true);

      // First load more: request 5, get 5
      manager.onLoadSuccess(5, 5);
      expect(manager.currentProductCount, 15);
      expect(manager.canLoadMore, true);

      // Second load more: request 5, get 3 (end of results)
      manager.onLoadSuccess(3, 5);
      expect(manager.currentProductCount, 18);
      expect(manager.canLoadMore, false);
    });

    test('pagination respects max suggestions limit', () {
      final manager = TestablePaginationManager();

      // Initial search returns 10
      manager.onInitialSearchComplete(10);

      // User loads more until reaching max
      manager.onLoadSuccess(5, 5); // Now at 15
      expect(manager.calculateFetchCount(), 5);

      manager.onLoadSuccess(5, 5); // Now at 20 (max)
      expect(manager.canLoadMore, false);
      expect(manager.calculateFetchCount(), 0);
    });

    test('load more with existing suggestions excludes duplicates', () {
      final existingIds = {'p1', 'p2', 'p3'};

      final newResults = [
        TestableSuggestion(id: 'p2', name: 'Product 2', price: 20.0), // Duplicate
        TestableSuggestion(id: 'p4', name: 'Product 4', price: 40.0), // New
        TestableSuggestion(id: 'p5', name: 'Product 5', price: 50.0), // New
      ];

      final combined = TestableProductResultCombiner.combineResults(
        [newResults],
        5,
        existingIds: existingIds,
      );

      expect(combined.length, 2);
      expect(combined.map((p) => p.id), ['p4', 'p5']);
    });

    test('new search resets pagination completely', () {
      final manager = TestablePaginationManager();

      // User did previous search and loaded more
      manager.onInitialSearchComplete(10);
      manager.onLoadSuccess(5, 5);
      manager.isLoadingMore = true;
      manager.lastSearchTerm = 'old search';

      // New search starts
      manager.reset();
      manager.lastSearchTerm = 'new search';

      expect(manager.currentProductCount, 0);
      expect(manager.hasMoreProducts, true);
      expect(manager.isLoadingMore, false);
    });
  });
}