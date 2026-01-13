// test/providers/seller_panel_provider_test.dart
//
// Unit tests for SellerPanelProvider pure logic
// Tests the EXACT logic from lib/providers/seller_panel_provider.dart
//
// Run: flutter test test/providers/seller_panel_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_seller_panel_provider.dart';

void main() {
  // ============================================================================
  // STOCK MEMOIZED DATA TESTS
  // ============================================================================
  group('TestableStockMemoizedData', () {
    late TestableStockMemoizedData memoized;

    setUp(() {
      memoized = TestableStockMemoizedData();
    });

    test('isUnchanged returns true when all params match', () {
      memoized.searchQuery = 'test';
      memoized.category = 'Electronics';
      memoized.subcategory = 'Phones';
      memoized.outOfStock = true;
      memoized.lastDoc = 'doc123';

      expect(
        memoized.isUnchanged('test', 'Electronics', 'Phones', true, 'doc123'),
        true,
      );
    });

    test('isUnchanged returns false when searchQuery differs', () {
      memoized.searchQuery = 'test';
      memoized.category = 'Electronics';

      expect(
        memoized.isUnchanged('different', 'Electronics', null, null, null),
        false,
      );
    });

    test('isUnchanged returns false when category differs', () {
      memoized.searchQuery = 'test';
      memoized.category = 'Electronics';

      expect(
        memoized.isUnchanged('test', 'Fashion', null, null, null),
        false,
      );
    });

    test('isUnchanged returns false when subcategory differs', () {
      memoized.subcategory = 'Phones';

      expect(
        memoized.isUnchanged(null, null, 'Tablets', null, null),
        false,
      );
    });

    test('isUnchanged returns false when outOfStock differs', () {
      memoized.outOfStock = true;

      expect(
        memoized.isUnchanged(null, null, null, false, null),
        false,
      );
    });

    test('isUnchanged returns false when lastDoc differs', () {
      memoized.lastDoc = 'doc1';

      expect(
        memoized.isUnchanged(null, null, null, null, 'doc2'),
        false,
      );
    });

    test('isUnchanged handles all nulls', () {
      expect(
        memoized.isUnchanged(null, null, null, null, null),
        true,
      );
    });

    test('reset clears all fields', () {
      memoized.searchQuery = 'test';
      memoized.category = 'Electronics';
      memoized.subcategory = 'Phones';
      memoized.outOfStock = true;
      memoized.lastDoc = 'doc123';
      memoized.products = ['p1', 'p2'];

      memoized.reset();

      expect(memoized.searchQuery, null);
      expect(memoized.category, null);
      expect(memoized.subcategory, null);
      expect(memoized.outOfStock, null);
      expect(memoized.lastDoc, null);
      expect(memoized.products, null);
    });
  });

  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  group('TestableCircuitBreaker', () {
    late TestableCircuitBreaker breaker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      breaker = TestableCircuitBreaker(
        threshold: 3,
        resetDuration: const Duration(minutes: 1),
        nowProvider: () => mockNow,
      );
    });

    group('isCircuitOpen', () {
      test('returns false when no failures', () {
        expect(breaker.isCircuitOpen('operation1'), false);
      });

      test('returns false when failures below threshold', () {
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');

        expect(breaker.getFailureCount('operation1'), 2);
        expect(breaker.isCircuitOpen('operation1'), false);
      });

      test('returns true when failures reach threshold', () {
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');

        expect(breaker.getFailureCount('operation1'), 3);
        expect(breaker.isCircuitOpen('operation1'), true);
      });

      test('resets after duration passes', () {
        // Trigger circuit open
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        expect(breaker.isCircuitOpen('operation1'), true);

        // Advance time past reset duration
        mockNow = mockNow.add(const Duration(minutes: 2));

        expect(breaker.isCircuitOpen('operation1'), false);
        expect(breaker.getFailureCount('operation1'), 0);
      });

      test('stays open before duration passes', () {
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');

        // Advance time but not past duration
        mockNow = mockNow.add(const Duration(seconds: 30));

        expect(breaker.isCircuitOpen('operation1'), true);
      });

      test('tracks operations independently', () {
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation2');

        expect(breaker.isCircuitOpen('operation1'), true);
        expect(breaker.isCircuitOpen('operation2'), false);
      });
    });

    group('recordSuccess', () {
      test('resets failure count to zero', () {
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        expect(breaker.getFailureCount('operation1'), 2);

        breaker.recordSuccess('operation1');
        expect(breaker.getFailureCount('operation1'), 0);
      });

      test('clears last failure time', () {
        breaker.recordFailure('operation1');
        expect(breaker.getLastFailureTime('operation1'), isNotNull);

        breaker.recordSuccess('operation1');
        expect(breaker.getLastFailureTime('operation1'), null);
      });

      test('allows operation after success resets circuit', () {
        // Open circuit
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        breaker.recordFailure('operation1');
        expect(breaker.isCircuitOpen('operation1'), true);

        // Success resets it
        breaker.recordSuccess('operation1');
        expect(breaker.isCircuitOpen('operation1'), false);
      });
    });

    group('edge cases', () {
      test('handles custom threshold', () {
        final customBreaker = TestableCircuitBreaker(
          threshold: 5,
          resetDuration: const Duration(minutes: 1),
          nowProvider: () => mockNow,
        );

        for (var i = 0; i < 4; i++) {
          customBreaker.recordFailure('op');
        }
        expect(customBreaker.isCircuitOpen('op'), false);

        customBreaker.recordFailure('op');
        expect(customBreaker.isCircuitOpen('op'), true);
      });

      test('handles custom reset duration', () {
        final customBreaker = TestableCircuitBreaker(
          threshold: 3,
          resetDuration: const Duration(seconds: 30),
          nowProvider: () => mockNow,
        );

        customBreaker.recordFailure('op');
        customBreaker.recordFailure('op');
        customBreaker.recordFailure('op');
        expect(customBreaker.isCircuitOpen('op'), true);

        // 20 seconds - still open
        mockNow = mockNow.add(const Duration(seconds: 20));
        expect(customBreaker.isCircuitOpen('op'), true);

        // 35 seconds - should be reset
        mockNow = mockNow.add(const Duration(seconds: 15));
        expect(customBreaker.isCircuitOpen('op'), false);
      });
    });
  });

  // ============================================================================
  // RETRY WITH BACKOFF TESTS
  // ============================================================================
  group('TestableRetryWithBackoff', () {
    late TestableCircuitBreaker breaker;
    late TestableRetryWithBackoff retry;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      breaker = TestableCircuitBreaker(
        threshold: 3,
        nowProvider: () => mockNow,
      );
      retry = TestableRetryWithBackoff(breaker);
    });

    test('executes successfully on first attempt', () async {
      var callCount = 0;
      final result = await retry.execute<String>(
        () async {
          callCount++;
          return 'success';
        },
        operationKey: 'test_op',
      );

      expect(result, 'success');
      expect(callCount, 1);
      expect(retry.attempts.length, 1);
      expect(retry.attempts.first.success, true);
      expect(retry.attempts.first.attemptNumber, 1);
    });

    test('retries on failure and succeeds', () async {
      var callCount = 0;
      final result = await retry.execute<String>(
        () async {
          callCount++;
          if (callCount < 3) throw Exception('Temporary error');
          return 'success';
        },
        maxAttempts: 3,
        operationKey: 'test_op',
      );

      expect(result, 'success');
      expect(callCount, 3);
      expect(retry.attempts.length, 3);
      expect(retry.attempts[0].success, false);
      expect(retry.attempts[1].success, false);
      expect(retry.attempts[2].success, true);
    });

    test('throws after max attempts', () async {
      var callCount = 0;

      await expectLater(
        retry.execute<String>(
          () async {
            callCount++;
            throw Exception('Persistent error');
          },
          maxAttempts: 3,
          operationKey: 'test_op',
        ),
        throwsException,
      );

      expect(callCount, 3);
      expect(retry.attempts.length, 3);
      expect(retry.attempts.every((a) => !a.success), true);
    });

    test('throws immediately when circuit is open', () async {
      // Open the circuit
      breaker.recordFailure('test_op');
      breaker.recordFailure('test_op');
      breaker.recordFailure('test_op');

      await expectLater(
        retry.execute<String>(
          () async => 'success',
          operationKey: 'test_op',
        ),
        throwsA(isA<CircuitBreakerOpenException>()),
      );

      // Should not have made any attempts
      expect(retry.attempts.isEmpty, true);
    });

    test('records success in circuit breaker on success', () async {
      // Add some failures
      breaker.recordFailure('test_op');
      breaker.recordFailure('test_op');

      await retry.execute<String>(
        () async => 'success',
        operationKey: 'test_op',
      );

      // Success should have reset the failure count
      expect(breaker.getFailureCount('test_op'), 0);
    });

    test('records failures in circuit breaker on failure', () async {
      try {
        await retry.execute<String>(
          () async => throw Exception('error'),
          maxAttempts: 2,
          operationKey: 'test_op',
        );
      } catch (_) {}

      // Should have recorded 2 failures
      expect(breaker.getFailureCount('test_op'), 2);
    });

    group('calculateDelay', () {
      test('returns 0 for first attempt', () {
        expect(TestableRetryWithBackoff.calculateDelay(1), 0);
      });

      test('returns base delay for second attempt', () {
        expect(TestableRetryWithBackoff.calculateDelay(2, baseDelayMs: 200), 200);
      });

      test('doubles delay for each subsequent attempt', () {
        expect(TestableRetryWithBackoff.calculateDelay(2, baseDelayMs: 200), 200);
        expect(TestableRetryWithBackoff.calculateDelay(3, baseDelayMs: 200), 400);
        expect(TestableRetryWithBackoff.calculateDelay(4, baseDelayMs: 200), 800);
      });

      test('works with custom base delay', () {
        expect(TestableRetryWithBackoff.calculateDelay(2, baseDelayMs: 100), 100);
        expect(TestableRetryWithBackoff.calculateDelay(3, baseDelayMs: 100), 200);
        expect(TestableRetryWithBackoff.calculateDelay(4, baseDelayMs: 100), 400);
      });
    });
  });

  // ============================================================================
  // LRU CACHE TESTS
  // ============================================================================
  group('TestableLRUCache', () {
    late TestableLRUCache<String, Map<String, dynamic>> cache;

    setUp(() {
      cache = TestableLRUCache<String, Map<String, dynamic>>(maxSize: 5);
    });

    test('stores and retrieves values', () {
      cache.put('key1', {'data': 'value1'});
      expect(cache.get('key1'), {'data': 'value1'});
    });

    test('evicts oldest entry when full', () {
      cache.put('key1', {'data': '1'});
      cache.put('key2', {'data': '2'});
      cache.put('key3', {'data': '3'});
      cache.put('key4', {'data': '4'});
      cache.put('key5', {'data': '5'});

      expect(cache.length, 5);

      // Add one more, should evict key1
      cache.put('key6', {'data': '6'});

      expect(cache.length, 5);
      expect(cache.containsKey('key1'), false);
      expect(cache.containsKey('key6'), true);
    });

    test('get refreshes LRU order', () {
      cache.put('key1', {'data': '1'});
      cache.put('key2', {'data': '2'});
      cache.put('key3', {'data': '3'});
      cache.put('key4', {'data': '4'});
      cache.put('key5', {'data': '5'});

      // Access key1, moving it to end
      cache.get('key1');

      // Add new key, should evict key2 (now oldest)
      cache.put('key6', {'data': '6'});

      expect(cache.containsKey('key1'), true); // Was refreshed
      expect(cache.containsKey('key2'), false); // Was evicted
    });

    test('peek does not refresh LRU order', () {
      cache.put('key1', {'data': '1'});
      cache.put('key2', {'data': '2'});
      cache.put('key3', {'data': '3'});
      cache.put('key4', {'data': '4'});
      cache.put('key5', {'data': '5'});

      // Peek at key1, should NOT move it
      cache.peek('key1');

      // Add new key, should evict key1 (still oldest)
      cache.put('key6', {'data': '6'});

      expect(cache.containsKey('key1'), false); // Was evicted
      expect(cache.containsKey('key2'), true);
    });

    test('returns null for missing keys', () {
      expect(cache.get('nonexistent'), null);
      expect(cache.peek('nonexistent'), null);
    });

    test('isFull returns correct value', () {
      expect(cache.isFull, false);

      for (var i = 0; i < 5; i++) {
        cache.put('key$i', {'data': '$i'});
      }

      expect(cache.isFull, true);
    });

    test('clear removes all entries', () {
      cache.put('key1', {'data': '1'});
      cache.put('key2', {'data': '2'});

      cache.clear();

      expect(cache.isEmpty, true);
      expect(cache.length, 0);
    });
  });

  // ============================================================================
  // PRODUCT MAP TESTS
  // ============================================================================
  group('TestableProductMap', () {
    late TestableProductMap<String, Map<String, dynamic>> productMap;

    setUp(() {
      productMap = TestableProductMap<String, Map<String, dynamic>>(
        maxSize: 10,
        evictionCount: 3,
      );
    });

    test('stores and retrieves products', () {
      productMap.put('prod1', {'name': 'Product 1'});
      expect(productMap['prod1'], {'name': 'Product 1'});
    });

    test('evicts oldest entries when full', () {
      // Fill to capacity
      for (var i = 0; i < 10; i++) {
        productMap.put('prod$i', {'name': 'Product $i'});
      }
      expect(productMap.length, 10);

      // Add one more, should evict 3 oldest
      productMap.put('prod10', {'name': 'Product 10'});

      expect(productMap.length, 8); // 10 - 3 + 1 = 8
      expect(productMap.containsKey('prod0'), false);
      expect(productMap.containsKey('prod1'), false);
      expect(productMap.containsKey('prod2'), false);
      expect(productMap.containsKey('prod3'), true);
      expect(productMap.containsKey('prod10'), true);
    });

    test('tracks evicted keys', () {
      for (var i = 0; i < 10; i++) {
        productMap.put('prod$i', {'name': 'Product $i'});
      }

      productMap.put('prod10', {'name': 'Product 10'});

      expect(productMap.evictedKeys, ['prod0', 'prod1', 'prod2']);
    });

    test('does not evict when updating existing key', () {
      for (var i = 0; i < 10; i++) {
        productMap.put('prod$i', {'name': 'Product $i'});
      }

      // Update existing key
      productMap.put('prod5', {'name': 'Updated Product 5'});

      expect(productMap.length, 10);
      expect(productMap.evictedKeys, isEmpty);
      expect(productMap['prod5'], {'name': 'Updated Product 5'});
    });
  });

  // ============================================================================
  // SALES CALCULATOR TESTS
  // ============================================================================
  group('TestableSalesCalculator', () {
    late TestableSalesCalculator calculator;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 14, 30, 0); // 2:30 PM on June 15, 2024
      calculator = TestableSalesCalculator(nowProvider: () => mockNow);
    });

    test('calculates today sales from calculatedTotal', () {
      final transactions = [
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0), // Today 10 AM
          'selectedAttributes': {'calculatedTotal': 100.0},
          'price': 50.0,
          'quantity': 1,
        },
        {
          'timestamp': DateTime(2024, 6, 15, 12, 0, 0), // Today 12 PM
          'selectedAttributes': {'calculatedTotal': 75.50},
          'price': 40.0,
          'quantity': 2,
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 175.50); // 100 + 75.50
    });

    test('falls back to price * quantity when no calculatedTotal', () {
      final transactions = [
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0),
          'price': 50.0,
          'quantity': 2,
        },
        {
          'timestamp': DateTime(2024, 6, 15, 12, 0, 0),
          'price': 30.0,
          'quantity': 3,
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 190.0); // (50*2) + (30*3) = 100 + 90
    });

    test('excludes transactions from other days', () {
      final transactions = [
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0), // Today
          'selectedAttributes': {'calculatedTotal': 100.0},
        },
        {
          'timestamp': DateTime(2024, 6, 14, 10, 0, 0), // Yesterday
          'selectedAttributes': {'calculatedTotal': 200.0},
        },
        {
          'timestamp': DateTime(2024, 6, 16, 10, 0, 0), // Tomorrow
          'selectedAttributes': {'calculatedTotal': 300.0},
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 100.0); // Only today's transaction
    });

    test('handles timestamp as milliseconds', () {
      final todayMs = DateTime(2024, 6, 15, 10, 0, 0).millisecondsSinceEpoch;
      final yesterdayMs = DateTime(2024, 6, 14, 10, 0, 0).millisecondsSinceEpoch;

      final transactions = [
        {
          'timestamp': todayMs,
          'selectedAttributes': {'calculatedTotal': 50.0},
        },
        {
          'timestamp': yesterdayMs,
          'selectedAttributes': {'calculatedTotal': 100.0},
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 50.0);
    });

    test('handles missing price/quantity gracefully', () {
      final transactions = [
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0),
          // No price, no quantity, no calculatedTotal
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 0.0); // price defaults to 0, quantity to 1 -> 0*1=0
    });

    test('handles null timestamp gracefully', () {
      final transactions = [
        {
          'timestamp': null,
          'selectedAttributes': {'calculatedTotal': 100.0},
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 0.0); // Excluded due to null timestamp
    });

    test('handles empty transactions list', () {
      final total = calculator.calculateTodaySales([]);
      expect(total, 0.0);
    });

    test('uses int calculatedTotal', () {
      final transactions = [
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0),
          'selectedAttributes': {'calculatedTotal': 100}, // int not double
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      expect(total, 100.0);
    });

    group('filterByDateRange', () {
      test('filters transactions within range', () {
        final transactions = [
          {'timestamp': DateTime(2024, 6, 10, 10, 0, 0), 'id': '1'},
          {'timestamp': DateTime(2024, 6, 12, 10, 0, 0), 'id': '2'},
          {'timestamp': DateTime(2024, 6, 15, 10, 0, 0), 'id': '3'},
          {'timestamp': DateTime(2024, 6, 18, 10, 0, 0), 'id': '4'},
        ];

        final filtered = calculator.filterByDateRange(
          transactions,
          DateTime(2024, 6, 11),
          DateTime(2024, 6, 16),
        );

        expect(filtered.length, 2);
        expect(filtered.map((t) => t['id']), ['2', '3']);
      });
    });
  });

  // ============================================================================
  // PRODUCT NORMALIZER TESTS
  // ============================================================================
  group('TestableProductNormalizer', () {
    test('trims category whitespace', () {
      final product = {
        'category': '  Electronics  ',
        'subcategory': '  Phones  ',
        'subsubcategory': '  Smartphones  ',
      };

      final normalized = TestableProductNormalizer.normalize(product);

      expect(normalized['category'], 'Electronics');
      expect(normalized['subcategory'], 'Phones');
      expect(normalized['subsubcategory'], 'Smartphones');
    });

    test('handles null values', () {
      final product = {
        'category': null,
        'subcategory': null,
        'subsubcategory': null,
        'name': 'Test Product',
      };

      final normalized = TestableProductNormalizer.normalize(product);

      expect(normalized['category'], null);
      expect(normalized['subcategory'], null);
      expect(normalized['subsubcategory'], null);
      expect(normalized['name'], 'Test Product');
    });

    test('preserves other fields', () {
      final product = {
        'id': 'prod123',
        'name': 'Test Product',
        'price': 99.99,
        'category': '  Fashion  ',
      };

      final normalized = TestableProductNormalizer.normalize(product);

      expect(normalized['id'], 'prod123');
      expect(normalized['name'], 'Test Product');
      expect(normalized['price'], 99.99);
      expect(normalized['category'], 'Fashion');
    });
  });

  // ============================================================================
  // TRANSACTION FILTER TESTS
  // ============================================================================
  group('TestableTransactionFilter', () {
    test('returns all transactions when query is empty', () {
      final transactions = [
        {'productName': 'Product 1', 'customerName': 'John'},
        {'productName': 'Product 2', 'customerName': 'Jane'},
      ];

      final filtered =
          TestableTransactionFilter.filterTransactions(transactions, '');

      expect(filtered.length, 2);
    });

    test('filters by product name', () {
      final transactions = [
        {'productName': 'iPhone 15', 'customerName': 'John'},
        {'productName': 'Samsung Galaxy', 'customerName': 'Jane'},
        {'productName': 'iPhone 14', 'customerName': 'Bob'},
      ];

      final filtered =
          TestableTransactionFilter.filterTransactions(transactions, 'iPhone');

      expect(filtered.length, 2);
      expect(filtered[0]['productName'], 'iPhone 15');
      expect(filtered[1]['productName'], 'iPhone 14');
    });

    test('filters by customer name', () {
      final transactions = [
        {'productName': 'Product 1', 'customerName': 'John Smith'},
        {'productName': 'Product 2', 'customerName': 'Jane Doe'},
        {'productName': 'Product 3', 'customerName': 'Johnny Appleseed'},
      ];

      final filtered =
          TestableTransactionFilter.filterTransactions(transactions, 'john');

      expect(filtered.length, 2);
    });

    test('filters by order ID', () {
      final transactions = [
        {'productName': 'Product 1', 'orderId': 'ORD-001'},
        {'productName': 'Product 2', 'orderId': 'ORD-002'},
        {'productName': 'Product 3', 'orderId': 'INV-001'},
      ];

      final filtered =
          TestableTransactionFilter.filterTransactions(transactions, 'ORD');

      expect(filtered.length, 2);
    });

    test('uses product map when available', () {
      final transactions = [
        {'productId': 'prod1', 'customerName': 'John'},
        {'productId': 'prod2', 'customerName': 'Jane'},
      ];

      final productMap = {
        'prod1': {'productName': 'Special Widget'},
        'prod2': {'productName': 'Regular Item'},
      };

      final filtered = TestableTransactionFilter.filterTransactions(
        transactions,
        'widget',
        productMap: productMap,
      );

      expect(filtered.length, 1);
      expect(filtered[0]['productId'], 'prod1');
    });

    test('case insensitive search', () {
      final transactions = [
        {'productName': 'UPPERCASE PRODUCT'},
        {'productName': 'lowercase product'},
        {'productName': 'MiXeD CaSe Product'},
      ];

      final filtered =
          TestableTransactionFilter.filterTransactions(transactions, 'PRODUCT');

      expect(filtered.length, 3);
    });
  });

  // ============================================================================
  // STOCK PRODUCT FILTER TESTS
  // ============================================================================
  group('TestableStockProductFilter', () {
    test('returns all products when query is empty', () {
      final products = [
        {'productName': 'Product 1'},
        {'productName': 'Product 2'},
      ];

      final filtered = TestableStockProductFilter.filterProducts(products, '');
      expect(filtered.length, 2);
    });

    test('filters by product name', () {
      final products = [
        {'productName': 'iPhone Case'},
        {'productName': 'Samsung Case'},
        {'productName': 'iPhone Screen Protector'},
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'iPhone');
      expect(filtered.length, 2);
    });

    test('filters by brand model', () {
      final products = [
        {'productName': 'Case', 'brandModel': 'Apple iPhone 15'},
        {'productName': 'Case', 'brandModel': 'Samsung Galaxy S24'},
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'Apple');
      expect(filtered.length, 1);
    });

    test('filters by category', () {
      final products = [
        {'productName': 'Item 1', 'category': 'Electronics'},
        {'productName': 'Item 2', 'category': 'Fashion'},
        {'productName': 'Item 3', 'category': 'Electronics'},
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'Electronics');
      expect(filtered.length, 2);
    });

    test('filters by subcategory', () {
      final products = [
        {'productName': 'Item 1', 'subcategory': 'Phones'},
        {'productName': 'Item 2', 'subcategory': 'Tablets'},
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'Phones');
      expect(filtered.length, 1);
    });

    test('filters by subsubcategory', () {
      final products = [
        {'productName': 'Item 1', 'subsubcategory': 'Smartphones'},
        {'productName': 'Item 2', 'subsubcategory': 'Feature Phones'},
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'Smartphones');
      expect(filtered.length, 1);
    });

    test('matches across multiple fields', () {
      final products = [
        {
          'productName': 'Basic Phone',
          'brandModel': 'Nokia',
          'category': 'Electronics',
        },
        {
          'productName': 'Smart Device',
          'brandModel': 'Apple',
          'category': 'Phone Accessories', // Contains 'Phone'
        },
      ];

      final filtered =
          TestableStockProductFilter.filterProducts(products, 'Phone');
      expect(filtered.length, 2);
    });
  });

  // ============================================================================
  // OUT OF STOCK CHECKER TESTS
  // ============================================================================
  group('TestableOutOfStockChecker', () {
    test('returns false when all products in stock', () {
      final products = [
        {'quantity': 10},
        {'quantity': 5},
        {'quantity': 1},
      ];

      expect(TestableOutOfStockChecker.hasOutOfStock(products), false);
    });

    test('returns true when product has zero quantity', () {
      final products = [
        {'quantity': 10},
        {'quantity': 0},
        {'quantity': 5},
      ];

      expect(TestableOutOfStockChecker.hasOutOfStock(products), true);
    });

    test('returns true when color variant is out of stock', () {
      final products = [
        {
          'quantity': 10,
          'colorQuantities': {'Red': 5, 'Blue': 0, 'Green': 3},
        },
      ];

      expect(TestableOutOfStockChecker.hasOutOfStock(products), true);
    });

    test('returns false when all color variants in stock', () {
      final products = [
        {
          'quantity': 10,
          'colorQuantities': {'Red': 5, 'Blue': 3, 'Green': 2},
        },
      ];

      expect(TestableOutOfStockChecker.hasOutOfStock(products), false);
    });

    test('handles null quantity', () {
      final products = [
        {'quantity': null},
      ];

      // null quantity defaults to 0
      expect(TestableOutOfStockChecker.hasOutOfStock(products), true);
    });

    test('handles empty products list', () {
      expect(TestableOutOfStockChecker.hasOutOfStock([]), false);
    });
  });

  // ============================================================================
  // METRICS CACHE TESTS
  // ============================================================================
  group('TestableMetricsCache', () {
    late TestableMetricsCache cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      cache = TestableMetricsCache(
        cacheDuration: const Duration(minutes: 5),
        nowProvider: () => mockNow,
      );
    });

    test('returns null when cache is empty', () {
      expect(cache.getIfValid(), null);
      expect(cache.isCacheValid(), false);
    });

    test('returns cached metrics when valid', () {
      final metrics = {'views': 100, 'sales': 50};
      cache.update(metrics);

      expect(cache.getIfValid(), metrics);
      expect(cache.isCacheValid(), true);
    });

    test('returns null when cache expires', () {
      final metrics = {'views': 100, 'sales': 50};
      cache.update(metrics);

      // Advance time past cache duration
      mockNow = mockNow.add(const Duration(minutes: 6));

      expect(cache.getIfValid(), null);
      expect(cache.isCacheValid(), false);
    });

    test('returns metrics just before expiry', () {
      final metrics = {'views': 100, 'sales': 50};
      cache.update(metrics);

      // Advance time just before expiry
      mockNow = mockNow.add(const Duration(minutes: 4, seconds: 59));

      expect(cache.getIfValid(), metrics);
      expect(cache.isCacheValid(), true);
    });

    test('invalidate forces cache refresh', () {
      final metrics = {'views': 100, 'sales': 50};
      cache.update(metrics);

      cache.invalidate();

      expect(cache.isCacheValid(), false);
      expect(cache.cachedMetrics, metrics); // Data still there
    });

    test('clear removes all data', () {
      final metrics = {'views': 100, 'sales': 50};
      cache.update(metrics);

      cache.clear();

      expect(cache.cachedMetrics, null);
      expect(cache.lastFetched, null);
      expect(cache.hasCachedMetrics, false);
    });
  });

  // ============================================================================
  // SEARCH DEBOUNCER TESTS
  // ============================================================================
  group('TestableSearchDebouncer', () {
    late TestableSearchDebouncer debouncer;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      debouncer = TestableSearchDebouncer(
        debounceDuration: const Duration(milliseconds: 300),
        nowProvider: () => mockNow,
      );
    });

    test('first query should trigger search', () {
      expect(debouncer.shouldTriggerSearch('test'), true);
    });

    test('same query should not trigger search', () {
      debouncer.recordSearch('test');

      expect(debouncer.shouldTriggerSearch('test'), false);
    });

    test('different query should trigger search after debounce', () {
      debouncer.recordSearch('test');

      // Advance time past debounce
      mockNow = mockNow.add(const Duration(milliseconds: 400));

      expect(debouncer.shouldTriggerSearch('different'), true);
    });

    test('different query should not trigger within debounce period', () {
      debouncer.recordSearch('test');

      // Advance time but within debounce
      mockNow = mockNow.add(const Duration(milliseconds: 200));

      expect(debouncer.shouldTriggerSearch('different'), false);
    });

    test('recordSearch updates last query', () {
      debouncer.recordSearch('first');
      expect(debouncer.lastQuery, 'first');

      mockNow = mockNow.add(const Duration(milliseconds: 400));
      debouncer.recordSearch('second');
      expect(debouncer.lastQuery, 'second');
    });

    test('recordSearch increments query count', () {
      expect(debouncer.queryCount, 0);

      debouncer.recordSearch('test1');
      expect(debouncer.queryCount, 1);

      mockNow = mockNow.add(const Duration(milliseconds: 400));
      debouncer.recordSearch('test2');
      expect(debouncer.queryCount, 2);
    });

    test('reset clears all state', () {
      debouncer.recordSearch('test');

      debouncer.reset();

      expect(debouncer.lastQuery, '');
      expect(debouncer.queryCount, 0);
      expect(debouncer.shouldTriggerSearch('test'), true);
    });
  });

  // ============================================================================
  // RACE GUARD TESTS
  // ============================================================================
  group('TestableRaceGuard', () {
    late TestableRaceGuard guard;

    setUp(() {
      guard = TestableRaceGuard();
    });

    test('startQuery increments ID', () {
      expect(guard.currentId, 0);

      final id1 = guard.startQuery();
      expect(id1, 1);
      expect(guard.currentId, 1);

      final id2 = guard.startQuery();
      expect(id2, 2);
      expect(guard.currentId, 2);
    });

    test('isActive returns true for current query', () {
      final id = guard.startQuery();
      expect(guard.isActive(id), true);
    });

    test('isActive returns false for stale query', () {
      final id1 = guard.startQuery();
      guard.startQuery(); // id2

      expect(guard.isActive(id1), false);
    });

    test('invalidateAll makes all previous queries stale', () {
      final id1 = guard.startQuery();
      final id2 = guard.startQuery();

      guard.invalidateAll();

      expect(guard.isActive(id1), false);
      expect(guard.isActive(id2), false);
    });

    test('new query after invalidateAll is active', () {
      guard.startQuery();
      guard.invalidateAll();

      final newId = guard.startQuery();
      expect(guard.isActive(newId), true);
    });

    test('reset sets ID back to 0', () {
      guard.startQuery();
      guard.startQuery();
      guard.startQuery();

      guard.reset();

      expect(guard.currentId, 0);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('circuit breaker protects against cascading failures', () {
      final mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      final breaker = TestableCircuitBreaker(
        threshold: 3,
        resetDuration: const Duration(minutes: 1),
        nowProvider: () => mockNow,
      );

      // Simulate 3 rapid failures
      breaker.recordFailure('fetchProducts');
      breaker.recordFailure('fetchProducts');
      breaker.recordFailure('fetchProducts');

      // Circuit should be open, preventing more calls
      expect(breaker.isCircuitOpen('fetchProducts'), true);

      // Other operations should still work
      expect(breaker.isCircuitOpen('fetchTransactions'), false);
    });

    test('LRU cache prevents memory bloat with many product images', () {
      final cache = TestableLRUCache<String, Map<String, dynamic>>(maxSize: 100);

      // Simulate loading 150 product images
      for (var i = 0; i < 150; i++) {
        cache.put('product_$i', {'imageUrl': 'https://example.com/$i.jpg'});
      }

      // Should only have 100 entries
      expect(cache.length, 100);

      // Oldest entries should be evicted
      expect(cache.containsKey('product_0'), false);
      expect(cache.containsKey('product_49'), false);
      expect(cache.containsKey('product_50'), true);
      expect(cache.containsKey('product_149'), true);
    });

    test('sales calculation handles mixed transaction data', () {
      final mockNow = DateTime(2024, 6, 15, 14, 0, 0);
      final calculator = TestableSalesCalculator(nowProvider: () => mockNow);

      final transactions = [
        // Transaction with calculatedTotal (discounted)
        {
          'timestamp': DateTime(2024, 6, 15, 9, 0, 0),
          'selectedAttributes': {'calculatedTotal': 85.0},
          'price': 100.0,
          'quantity': 1,
        },
        // Transaction without calculatedTotal
        {
          'timestamp': DateTime(2024, 6, 15, 10, 0, 0),
          'price': 50.0,
          'quantity': 2,
        },
        // Transaction from yesterday (should be excluded)
        {
          'timestamp': DateTime(2024, 6, 14, 10, 0, 0),
          'selectedAttributes': {'calculatedTotal': 500.0},
        },
        // Transaction with int price
        {
          'timestamp': DateTime(2024, 6, 15, 11, 0, 0),
          'price': 25,
          'quantity': 4,
        },
      ];

      final total = calculator.calculateTodaySales(transactions);
      // 85 + (50*2) + (25*4) = 85 + 100 + 100 = 285
      expect(total, 285.0);
    });

    test('race guard prevents stale responses from updating UI', () {
      final guard = TestableRaceGuard();

      // Simulate 3 rapid search queries
      final query1Id = guard.startQuery();
      final query2Id = guard.startQuery();
      final query3Id = guard.startQuery();

      // Only the last query should be considered active
      expect(guard.isActive(query1Id), false);
      expect(guard.isActive(query2Id), false);
      expect(guard.isActive(query3Id), true);

      // Responses from query1 and query2 should be dropped
    });

    test('memoization prevents redundant fetches', () {
      final memoized = TestableStockMemoizedData();

      // First fetch
      memoized.searchQuery = 'phone';
      memoized.category = 'Electronics';
      memoized.outOfStock = false;

      // Same params - should use cache
      expect(
        memoized.isUnchanged('phone', 'Electronics', null, false, null),
        true,
      );

      // Different search - should fetch
      expect(
        memoized.isUnchanged('tablet', 'Electronics', null, false, null),
        false,
      );
    });
  });
}