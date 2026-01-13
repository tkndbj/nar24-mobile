// test/services/algolia_service_test.dart
//
// Unit tests for AlgoliaService pure logic
// Tests the EXACT logic from lib/services/algolia_service.dart
//
// Run: flutter test test/services/algolia_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_algolia_service.dart';

void main() {
  // ============================================================================
  // ALGOLIA PAGE TESTS
  // ============================================================================
  group('TestableAlgoliaPage', () {
    test('hasMorePages returns true when not on last page', () {
      final page = TestableAlgoliaPage(ids: ['id1'], page: 0, nbPages: 3);
      expect(page.hasMorePages, true);
    });

    test('hasMorePages returns false on last page', () {
      final page = TestableAlgoliaPage(ids: ['id1'], page: 2, nbPages: 3);
      expect(page.hasMorePages, false);
    });

    test('isEmpty returns true for empty ids', () {
      final page = TestableAlgoliaPage(ids: [], page: 0, nbPages: 1);
      expect(page.isEmpty, true);
      expect(page.isNotEmpty, false);
    });

    test('count returns number of ids', () {
      final page = TestableAlgoliaPage(ids: ['a', 'b', 'c'], page: 0, nbPages: 1);
      expect(page.count, 3);
    });
  });

  // ============================================================================
  // URL BUILDER TESTS
  // ============================================================================
  group('TestableAlgoliaUrlBuilder', () {
    group('constructSearchUri', () {
      test('builds correct URI for products index', () {
        final uri = TestableAlgoliaUrlBuilder.constructSearchUri(
          applicationId: 'ABC123',
          indexName: 'products',
        );

        // Uri.https normalizes host to lowercase
        expect(uri.host, 'abc123-dsn.algolia.net');
        expect(uri.path, '/1/indexes/products/query');
        expect(uri.scheme, 'https');
      });

      test('builds correct URI for shop_products index', () {
        final uri = TestableAlgoliaUrlBuilder.constructSearchUri(
          applicationId: 'XYZ789',
          indexName: 'shop_products',
        );

        // Uri.https normalizes host to lowercase
        expect(uri.host, 'xyz789-dsn.algolia.net');
        expect(uri.path, '/1/indexes/shop_products/query');
      });

      test('handles special characters in index name', () {
        final uri = TestableAlgoliaUrlBuilder.constructSearchUri(
          applicationId: 'APP',
          indexName: 'my-index_v2',
        );

        expect(uri.path, '/1/indexes/my-index_v2/query');
      });
    });

    group('buildHost', () {
      test('appends -dsn.algolia.net', () {
        expect(
          TestableAlgoliaUrlBuilder.buildHost('MYAPP'),
          'MYAPP-dsn.algolia.net',
        );
      });
    });
  });

  // ============================================================================
  // REPLICA INDEX RESOLVER TESTS
  // ============================================================================
  group('TestableReplicaIndexResolver', () {
    group('getReplicaIndexName', () {
      test('returns original index for non-shop_products', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('products', 'date'),
          'products',
        );
      });

      test('returns original index for products with any sort', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('products', 'price_asc'),
          'products',
        );
      });

      test('returns original for shop_products with None sort', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'None'),
          'shop_products',
        );
      });

      test('returns original for shop_products with empty sort', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', ''),
          'shop_products',
        );
      });

      test('returns date replica for shop_products', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'date'),
          'shop_products_createdAt_desc',
        );
      });

      test('returns alphabetical replica for shop_products', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'alphabetical'),
          'shop_products_alphabetical',
        );
      });

      test('returns price_asc replica for shop_products', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'price_asc'),
          'shop_products_price_asc',
        );
      });

      test('returns price_desc replica for shop_products', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'price_desc'),
          'shop_products_price_desc',
        );
      });

      test('returns original for unknown sort option', () {
        expect(
          TestableReplicaIndexResolver.getReplicaIndexName('shop_products', 'unknown'),
          'shop_products',
        );
      });
    });

    group('supportsReplicas', () {
      test('returns true for shop_products', () {
        expect(TestableReplicaIndexResolver.supportsReplicas('shop_products'), true);
      });

      test('returns false for products', () {
        expect(TestableReplicaIndexResolver.supportsReplicas('products'), false);
      });

      test('returns false for orders', () {
        expect(TestableReplicaIndexResolver.supportsReplicas('orders'), false);
      });
    });
  });

  // ============================================================================
  // TIMEOUT PROGRESSION TESTS
  // ============================================================================
  group('TestableTimeoutProgression', () {
    group('getTimeoutForAttempt', () {
      test('first attempt is 3 seconds', () {
        expect(
          TestableTimeoutProgression.getTimeoutForAttempt(1),
          const Duration(seconds: 3),
        );
      });

      test('second attempt is 5 seconds', () {
        expect(
          TestableTimeoutProgression.getTimeoutForAttempt(2),
          const Duration(seconds: 5),
        );
      });

      test('third attempt is 8 seconds', () {
        expect(
          TestableTimeoutProgression.getTimeoutForAttempt(3),
          const Duration(seconds: 8),
        );
      });

      test('fourth attempt uses last timeout (8s)', () {
        expect(
          TestableTimeoutProgression.getTimeoutForAttempt(4),
          const Duration(seconds: 8),
        );
      });

      test('zero attempt clamps to first', () {
        expect(
          TestableTimeoutProgression.getTimeoutForAttempt(0),
          const Duration(seconds: 3),
        );
      });
    });

    group('totalMaxWaitTime', () {
      test('calculates total of all timeouts', () {
        // 3 + 5 + 8 = 16 seconds
        expect(
          TestableTimeoutProgression.totalMaxWaitTime,
          const Duration(seconds: 16),
        );
      });
    });
  });

  // ============================================================================
  // FILTER BUILDER TESTS
  // ============================================================================
  group('TestableAlgoliaFilterBuilder', () {
    group('joinFilters', () {
      test('joins with AND', () {
        expect(
          TestableAlgoliaFilterBuilder.joinFilters(['a:1', 'b:2']),
          'a:1 AND b:2',
        );
      });

      test('single filter returns as-is', () {
        expect(
          TestableAlgoliaFilterBuilder.joinFilters(['category:shoes']),
          'category:shoes',
        );
      });

      test('empty list returns empty string', () {
        expect(TestableAlgoliaFilterBuilder.joinFilters([]), '');
      });
    });

    group('buildShopFilter', () {
      test('builds correct filter format', () {
        expect(
          TestableAlgoliaFilterBuilder.buildShopFilter('shop123'),
          'shopId:"shop123"',
        );
      });
    });

    group('buildUserFilter', () {
      test('builds sellerId filter for isSold=true', () {
        expect(
          TestableAlgoliaFilterBuilder.buildUserFilter(
            userId: 'user123',
            isSold: true,
          ),
          'sellerId:"user123"',
        );
      });

      test('builds buyerId filter for isSold=false', () {
        expect(
          TestableAlgoliaFilterBuilder.buildUserFilter(
            userId: 'user123',
            isSold: false,
          ),
          'buyerId:"user123"',
        );
      });
    });

    group('buildLanguageFilter', () {
      test('builds correct format', () {
        expect(
          TestableAlgoliaFilterBuilder.buildLanguageFilter('en'),
          'languageCode:en',
        );
      });
    });
  });

  // ============================================================================
  // PARAM ENCODER TESTS
  // ============================================================================
  group('TestableAlgoliaParamEncoder', () {
    group('encodeParam', () {
      test('encodes simple values', () {
        expect(
          TestableAlgoliaParamEncoder.encodeParam('query', 'shoes'),
          'query=shoes',
        );
      });

      test('encodes special characters', () {
        final encoded = TestableAlgoliaParamEncoder.encodeParam(
          'query',
          'red shoes & boots',
        );
        expect(encoded.contains('%26'), true); // & encoded
        expect(encoded.contains('%20'), true); // space encoded
      });
    });

    group('encodeParams', () {
      test('encodes multiple params', () {
        final encoded = TestableAlgoliaParamEncoder.encodeParams({
          'query': 'test',
          'page': '0',
        });

        expect(encoded, contains('query=test'));
        expect(encoded, contains('page=0'));
        expect(encoded, contains('&'));
      });
    });
  });

  // ============================================================================
  // RETRY CONDITION TESTS
  // ============================================================================
  group('TestableRetryCondition', () {
    group('shouldRetry', () {
      test('returns true for SocketException', () {
        final e = Exception('SocketException: Connection refused');
        expect(TestableRetryCondition.shouldRetry(e), true);
      });

      test('returns true for TimeoutException', () {
        final e = Exception('TimeoutException after 5s');
        expect(TestableRetryCondition.shouldRetry(e), true);
      });

      test('returns true for HttpException', () {
        final e = Exception('HttpException: 503 Service Unavailable');
        expect(TestableRetryCondition.shouldRetry(e), true);
      });

      test('returns true for DNS lookup failure', () {
        final e = Exception('Failed host lookup: algolia.net');
        expect(TestableRetryCondition.shouldRetry(e), true);
      });

      test('returns false for FormatException', () {
        final e = Exception('FormatException: Invalid JSON');
        expect(TestableRetryCondition.shouldRetry(e), false);
      });

      test('returns false for generic exception', () {
        final e = Exception('Something went wrong');
        expect(TestableRetryCondition.shouldRetry(e), false);
      });
    });

    group('categorizeError', () {
      test('categorizes network errors', () {
        final e = Exception('SocketException');
        expect(TestableRetryCondition.categorizeError(e), 'network');
      });

      test('categorizes timeout errors', () {
        final e = Exception('TimeoutException');
        expect(TestableRetryCondition.categorizeError(e), 'timeout');
      });

      test('categorizes server errors', () {
        final e = Exception('HttpException');
        expect(TestableRetryCondition.categorizeError(e), 'server');
      });

      test('categorizes DNS errors', () {
        final e = Exception('Failed host lookup');
        expect(TestableRetryCondition.categorizeError(e), 'dns');
      });

      test('categorizes parse errors', () {
        final e = Exception('FormatException');
        expect(TestableRetryCondition.categorizeError(e), 'parse');
      });
    });
  });

  // ============================================================================
  // ID EXTRACTOR TESTS
  // ============================================================================
  group('TestableAlgoliaIdExtractor', () {
    group('extractId', () {
      test('extracts ilanNo when present', () {
        final hit = {'ilanNo': 'firestore_doc_123', 'objectID': 'other'};
        expect(TestableAlgoliaIdExtractor.extractId(hit), 'firestore_doc_123');
      });

      test('falls back to objectID when ilanNo missing', () {
        final hit = {'objectID': 'shop_products_abc123'};
        expect(TestableAlgoliaIdExtractor.extractId(hit), 'abc123');
      });

      test('returns null for empty ilanNo and non-prefixed objectID', () {
        final hit = {'ilanNo': '', 'objectID': 'regular_id'};
        expect(TestableAlgoliaIdExtractor.extractId(hit), null);
      });

      test('returns null for missing both fields', () {
        final hit = <String, dynamic>{};
        expect(TestableAlgoliaIdExtractor.extractId(hit), null);
      });

      test('handles null ilanNo', () {
        final hit = {'ilanNo': null, 'objectID': 'shop_products_xyz'};
        expect(TestableAlgoliaIdExtractor.extractId(hit), 'xyz');
      });
    });

    group('extractIds', () {
      test('extracts IDs from multiple hits', () {
        final hits = [
          {'ilanNo': 'id1'},
          {'ilanNo': 'id2'},
          {'objectID': 'shop_products_id3'},
        ];

        final ids = TestableAlgoliaIdExtractor.extractIds(hits);
        expect(ids, ['id1', 'id2', 'id3']);
      });

      test('skips hits without extractable ID', () {
        final hits = [
          {'ilanNo': 'id1'},
          {'objectID': 'no_prefix'}, // Can't extract
          {'ilanNo': 'id2'},
        ];

        final ids = TestableAlgoliaIdExtractor.extractIds(hits);
        expect(ids, ['id1', 'id2']);
      });
    });

    group('removeShopProductsPrefix', () {
      test('removes prefix correctly', () {
        expect(
          TestableAlgoliaIdExtractor.removeShopProductsPrefix('shop_products_abc123'),
          'abc123',
        );
      });

      test('returns null for non-prefixed', () {
        expect(
          TestableAlgoliaIdExtractor.removeShopProductsPrefix('regular_id'),
          null,
        );
      });

      test('returns null for empty result after prefix', () {
        expect(
          TestableAlgoliaIdExtractor.removeShopProductsPrefix('shop_products_'),
          null,
        );
      });
    });
  });

  // ============================================================================
  // RESPONSE HANDLER TESTS
  // ============================================================================
  group('TestableAlgoliaResponseHandler', () {
    group('isSuccess', () {
      test('returns true for 200', () {
        expect(TestableAlgoliaResponseHandler.isSuccess(200), true);
      });

      test('returns false for other codes', () {
        expect(TestableAlgoliaResponseHandler.isSuccess(201), false);
        expect(TestableAlgoliaResponseHandler.isSuccess(404), false);
      });
    });

    group('isServerError', () {
      test('returns true for 5xx', () {
        expect(TestableAlgoliaResponseHandler.isServerError(500), true);
        expect(TestableAlgoliaResponseHandler.isServerError(503), true);
        expect(TestableAlgoliaResponseHandler.isServerError(599), true);
      });

      test('returns false for non-5xx', () {
        expect(TestableAlgoliaResponseHandler.isServerError(200), false);
        expect(TestableAlgoliaResponseHandler.isServerError(404), false);
      });
    });

    group('isClientError', () {
      test('returns true for 4xx', () {
        expect(TestableAlgoliaResponseHandler.isClientError(400), true);
        expect(TestableAlgoliaResponseHandler.isClientError(404), true);
        expect(TestableAlgoliaResponseHandler.isClientError(499), true);
      });

      test('returns false for non-4xx', () {
        expect(TestableAlgoliaResponseHandler.isClientError(200), false);
        expect(TestableAlgoliaResponseHandler.isClientError(500), false);
      });
    });

    group('getActionForStatus', () {
      test('returns process for 200', () {
        expect(TestableAlgoliaResponseHandler.getActionForStatus(200), 'process');
      });

      test('returns retry for 5xx', () {
        expect(TestableAlgoliaResponseHandler.getActionForStatus(500), 'retry');
        expect(TestableAlgoliaResponseHandler.getActionForStatus(503), 'retry');
      });

      test('returns abort for 4xx', () {
        expect(TestableAlgoliaResponseHandler.getActionForStatus(400), 'abort');
        expect(TestableAlgoliaResponseHandler.getActionForStatus(404), 'abort');
      });
    });
  });

  // ============================================================================
  // DEBOUNCE TESTS
  // ============================================================================
  group('TestableAlgoliaDebounce', () {
    group('shouldExecute', () {
      test('returns true for null lastCall', () {
        expect(TestableAlgoliaDebounce.shouldExecute(null), true);
      });

      test('returns false within debounce window', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final lastCall = now.subtract(const Duration(milliseconds: 100));

        expect(
          TestableAlgoliaDebounce.shouldExecute(lastCall, now: now),
          false,
        );
      });

      test('returns true after debounce window', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final lastCall = now.subtract(const Duration(milliseconds: 400));

        expect(
          TestableAlgoliaDebounce.shouldExecute(lastCall, now: now),
          true,
        );
      });

      test('returns true at exactly 300ms', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final lastCall = now.subtract(const Duration(milliseconds: 300));

        expect(
          TestableAlgoliaDebounce.shouldExecute(lastCall, now: now),
          true,
        );
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('shop product search with filters', () {
      // Building a shop search request
      final shopFilter = TestableAlgoliaFilterBuilder.buildShopFilter('nike_official');
      final categoryFilter = 'category:"shoes"';
      final combined = TestableAlgoliaFilterBuilder.combineFilters([
        shopFilter,
        categoryFilter,
      ]);

      expect(combined, 'shopId:"nike_official" AND category:"shoes"');

      // Get correct replica for price sorting
      final replica = TestableReplicaIndexResolver.getReplicaIndexName(
        'shop_products',
        'price_asc',
      );
      expect(replica, 'shop_products_price_asc');
    });

    test('order search for seller', () {
      final filter = TestableAlgoliaFilterBuilder.buildUserFilter(
        userId: 'seller_abc',
        isSold: true,
      );

      expect(filter, 'sellerId:"seller_abc"');
    });

    test('progressive timeout on network issues', () {
      // Simulate 3 retry attempts
      final timeouts = [
        TestableTimeoutProgression.getTimeoutForAttempt(1),
        TestableTimeoutProgression.getTimeoutForAttempt(2),
        TestableTimeoutProgression.getTimeoutForAttempt(3),
      ];

      expect(timeouts[0].inSeconds, 3);
      expect(timeouts[1].inSeconds, 5);
      expect(timeouts[2].inSeconds, 8);

      // Total wait is 16 seconds max
      final total = timeouts.fold<Duration>(
        Duration.zero,
        (sum, t) => sum + t,
      );
      expect(total.inSeconds, 16);
    });

    test('ID extraction from mixed Algolia results', () {
      // Simulates real Algolia response with mixed ID formats
      final hits = [
        {'ilanNo': 'doc_from_ilanno_1', 'objectID': 'shop_products_ignored'},
        {'ilanNo': '', 'objectID': 'shop_products_extracted_from_objectid'},
        {'ilanNo': null, 'objectID': 'shop_products_also_extracted'},
        {'objectID': 'no_prefix_skipped'},
      ];

      final ids = TestableAlgoliaIdExtractor.extractIds(hits);

      expect(ids, [
        'doc_from_ilanno_1',
        'extracted_from_objectid',
        'also_extracted',
      ]);
    });

    test('retry decision based on error type', () {
      // Network error - should retry
      expect(
        TestableRetryCondition.shouldRetry(
          Exception('SocketException: Connection reset'),
        ),
        true,
      );

      // Server error - should retry
      expect(
        TestableRetryCondition.shouldRetry(
          Exception('HttpException: 503 Service Unavailable'),
        ),
        true,
      );

      // Parse error - should NOT retry (data is bad)
      expect(
        TestableRetryCondition.shouldRetry(
          Exception('FormatException: Unexpected character'),
        ),
        false,
      );
    });
  });
}