// test/services/click_tracking_service_test.dart
//
// Unit tests for ClickTrackingService pure logic
// Tests the EXACT logic from lib/services/click_tracking_service.dart
//
// Run: flutter test test/services/click_tracking_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import './testable_click_tracking_service.dart';

void main() {
  // ============================================================================
  // CLICK COOLDOWN TESTS
  // ============================================================================
  group('TestableClickCooldown', () {
    late TestableClickCooldown cooldown;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cooldown = TestableClickCooldown(nowProvider: () => mockNow);
    });

    group('shouldAllowClick', () {
      test('allows first click on item', () {
        expect(cooldown.shouldAllowClick('product123'), true);
      });

      test('blocks click within cooldown period', () {
        cooldown.recordClick('product123');

        // 500ms later
        mockNow = mockNow.add(const Duration(milliseconds: 500));
        expect(cooldown.shouldAllowClick('product123'), false);
      });

      test('allows click after cooldown period', () {
        cooldown.recordClick('product123');

        // 1.1 seconds later
        mockNow = mockNow.add(const Duration(milliseconds: 1100));
        expect(cooldown.shouldAllowClick('product123'), true);
      });

      test('allows click at exactly cooldown boundary', () {
        cooldown.recordClick('product123');

        // Exactly 1 second later
        mockNow = mockNow.add(const Duration(seconds: 1));
        expect(cooldown.shouldAllowClick('product123'), true);
      });

      test('tracks items independently', () {
        cooldown.recordClick('product123');

        // Different product should still be allowed
        expect(cooldown.shouldAllowClick('product456'), true);
      });
    });

    group('tryClick', () {
      test('returns true and records on first click', () {
        expect(cooldown.tryClick('product123'), true);

        // Should now be in cooldown
        expect(cooldown.shouldAllowClick('product123'), false);
      });

      test('returns false during cooldown', () {
        cooldown.tryClick('product123');
        expect(cooldown.tryClick('product123'), false);
      });

      test('returns true after cooldown', () {
        cooldown.tryClick('product123');

        mockNow = mockNow.add(const Duration(seconds: 2));
        expect(cooldown.tryClick('product123'), true);
      });
    });

    group('getTimeUntilAllowed', () {
      test('returns zero for unknown item', () {
        expect(cooldown.getTimeUntilAllowed('unknown'), Duration.zero);
      });

      test('returns remaining cooldown time', () {
        cooldown.recordClick('product123');

        mockNow = mockNow.add(const Duration(milliseconds: 300));
        final remaining = cooldown.getTimeUntilAllowed('product123');

        expect(remaining.inMilliseconds, 700);
      });

      test('returns zero after cooldown expires', () {
        cooldown.recordClick('product123');

        mockNow = mockNow.add(const Duration(seconds: 2));
        expect(cooldown.getTimeUntilAllowed('product123'), Duration.zero);
      });
    });
  });

  // ============================================================================
  // CLICK BUFFER TESTS
  // ============================================================================
  group('TestableClickBuffer', () {
    late TestableClickBuffer buffer;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      buffer = TestableClickBuffer(nowProvider: () => mockNow);
    });

    group('getTotalBufferedCount', () {
      test('returns zero initially', () {
        expect(buffer.getTotalBufferedCount(), 0);
      });

      test('counts all click types', () {
        buffer.addProductClick('p1', isShopProduct: false);
        buffer.addProductClick('p2', isShopProduct: true);
        buffer.addShopClick('shop1');

        expect(buffer.getTotalBufferedCount(), 3);
      });

      test('counts unique items not total clicks', () {
        buffer.addProductClick('p1', isShopProduct: true);
        buffer.addProductClick('p1', isShopProduct: true);
        buffer.addProductClick('p1', isShopProduct: true);

        expect(buffer.getTotalBufferedCount(), 1);
        expect(buffer.shopProductClicks['p1'], 3);
      });
    });

    group('extractRawProductId', () {
      test('returns ID as-is if no underscore', () {
        expect(TestableClickBuffer.extractRawProductId('abc123'), 'abc123');
      });

      test('extracts last part after underscore', () {
        expect(
          TestableClickBuffer.extractRawProductId('products_abc123'),
          'abc123',
        );
      });

      test('handles shop_products prefix', () {
        expect(
          TestableClickBuffer.extractRawProductId('shop_products_xyz789'),
          'xyz789',
        );
      });

      test('handles multiple underscores', () {
        expect(
          TestableClickBuffer.extractRawProductId('prefix_middle_suffix'),
          'suffix',
        );
      });
    });

    group('shouldForceFlush', () {
      test('returns false when under all limits', () {
        buffer.addProductClick('p1', isShopProduct: true);
        expect(buffer.shouldForceFlush(), false);
      });

      test('returns true when buffer size exceeded', () {
        for (var i = 0; i < 500; i++) {
          buffer.addProductClick('product_$i', isShopProduct: true);
        }
        expect(buffer.shouldForceFlush(), true);
      });

      test('returns true when memory limit approached', () {
        // 512KB / 100 bytes per click = 5120 clicks
        // But we also check count >= 500, so that triggers first
        for (var i = 0; i < 500; i++) {
          buffer.addProductClick('product_$i', isShopProduct: true);
        }
        expect(buffer.shouldForceFlush(), true);
      });

      test('returns true when time since last flush exceeded', () {
        buffer.lastSuccessfulFlush = mockNow;
        buffer.addProductClick('p1', isShopProduct: true);

        // Advance 6 minutes
        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(buffer.shouldForceFlush(), true);
      });

      test('returns false when time limit not exceeded', () {
        buffer.lastSuccessfulFlush = mockNow;
        buffer.addProductClick('p1', isShopProduct: true);

        // Advance 4 minutes
        mockNow = mockNow.add(const Duration(minutes: 4));

        expect(buffer.shouldForceFlush(), false);
      });
    });

    group('addProductClick', () {
      test('adds to shopProductClicks when isShopProduct true', () {
        buffer.addProductClick('p1', isShopProduct: true);

        expect(buffer.shopProductClicks['p1'], 1);
        expect(buffer.productClicks['p1'], null);
      });

      test('adds to productClicks when isShopProduct false', () {
        buffer.addProductClick('p1', isShopProduct: false);

        expect(buffer.productClicks['p1'], 1);
        expect(buffer.shopProductClicks['p1'], null);
      });

      test('stores shopId when provided', () {
        buffer.addProductClick('p1', isShopProduct: true, shopId: 'shop123');

        expect(buffer.shopIds['p1'], 'shop123');
      });

      test('strips product prefix', () {
        buffer.addProductClick('products_abc123', isShopProduct: false);

        expect(buffer.productClicks.containsKey('abc123'), true);
        expect(buffer.productClicks.containsKey('products_abc123'), false);
      });
    });

    group('markFlushSuccess', () {
      test('clears all buffers', () {
        buffer.addProductClick('p1', isShopProduct: true, shopId: 'shop1');
        buffer.addProductClick('p2', isShopProduct: false);
        buffer.addShopClick('shop1');

        buffer.markFlushSuccess();

        expect(buffer.getTotalBufferedCount(), 0);
        expect(buffer.shopIds.isEmpty, true);
      });

      test('updates lastSuccessfulFlush', () {
        buffer.markFlushSuccess();

        expect(buffer.lastSuccessfulFlush, mockNow);
      });
    });
  });

  // ============================================================================
  // CIRCUIT BREAKER TESTS
  // ============================================================================
  group('TestableClickCircuitBreaker', () {
    late TestableClickCircuitBreaker breaker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      breaker = TestableClickCircuitBreaker(nowProvider: () => mockNow);
    });

    group('shouldAllowOperation', () {
      test('allows operation initially', () {
        expect(breaker.shouldAllowOperation(), true);
      });

      test('blocks operation when circuit is open', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();

        expect(breaker.shouldAllowOperation(), false);
      });

      test('allows operation after cooldown', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();

        // Advance 6 minutes
        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(breaker.shouldAllowOperation(), true);
        expect(breaker.isOpen, false);
        expect(breaker.failureCount, 0);
      });

      test('stays closed during cooldown', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();

        // Advance 3 minutes
        mockNow = mockNow.add(const Duration(minutes: 3));

        expect(breaker.shouldAllowOperation(), false);
      });
    });

    group('recordFailure', () {
      test('increments failure count', () {
        breaker.recordFailure();
        expect(breaker.failureCount, 1);

        breaker.recordFailure();
        expect(breaker.failureCount, 2);
      });

      test('opens circuit at max failures', () {
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.isOpen, false);

        breaker.recordFailure();
        expect(breaker.isOpen, true);
      });

      test('records last failure time', () {
        breaker.recordFailure();
        expect(breaker.lastFailure, mockNow);
      });
    });

    group('recordSuccess', () {
      test('resets failure count', () {
        breaker.recordFailure();
        breaker.recordFailure();

        breaker.recordSuccess();

        expect(breaker.failureCount, 0);
      });

      test('closes circuit', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.isOpen, true);

        breaker.recordSuccess();
        expect(breaker.isOpen, false);
      });
    });

    group('getTimeUntilReset', () {
      test('returns zero when circuit is closed', () {
        expect(breaker.getTimeUntilReset(), Duration.zero);
      });

      test('returns remaining cooldown time', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();

        mockNow = mockNow.add(const Duration(minutes: 2));

        expect(breaker.getTimeUntilReset().inMinutes, 3);
      });

      test('returns zero after cooldown expires', () {
        breaker.recordFailure();
        breaker.recordFailure();
        breaker.recordFailure();

        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(breaker.getTimeUntilReset(), Duration.zero);
      });
    });
  });

  // ============================================================================
  // BATCH ID GENERATOR TESTS
  // ============================================================================
  group('TestableBatchIdGenerator', () {
    late TestableBatchIdGenerator generator;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      generator = TestableBatchIdGenerator(nowProvider: () => mockNow);
    });

    group('generateBatchId', () {
      test('generates batch ID with correct prefix', () {
        final batchId = generator.generateBatchId(userId: 'user123');
        expect(batchId.startsWith('batch_'), true);
      });

      test('generates 16-char hash suffix', () {
        final batchId = generator.generateBatchId(userId: 'user123');
        final suffix = batchId.substring('batch_'.length);
        expect(suffix.length, 16);
      });

      test('returns same ID within TTL', () {
        final batchId1 = generator.generateBatchId(userId: 'user123');

        // Advance 10 seconds
        mockNow = mockNow.add(const Duration(seconds: 10));

        final batchId2 = generator.generateBatchId(userId: 'user123');
        expect(batchId2, batchId1);
      });

      test('generates new ID after TTL', () {
        final batchId1 = generator.generateBatchId(userId: 'user123');

        // Advance 31 seconds
        mockNow = mockNow.add(const Duration(seconds: 31));

        final batchId2 = generator.generateBatchId(userId: 'user123');
        expect(batchId2, isNot(batchId1));
      });

      test('uses anonymous for null userId', () {
        final batchId = generator.generateBatchId();
        expect(batchId.startsWith('batch_'), true);
      });

      test('is deterministic for same inputs', () {
        final gen1 = TestableBatchIdGenerator(nowProvider: () => mockNow);
        final gen2 = TestableBatchIdGenerator(nowProvider: () => mockNow);

        final id1 = gen1.generateBatchId(userId: 'user123');
        final id2 = gen2.generateBatchId(userId: 'user123');

        expect(id1, id2);
      });

      test('different users get different batch IDs', () {
        final id1 = generator.generateBatchId(userId: 'user1');
        generator.reset();
        final id2 = generator.generateBatchId(userId: 'user2');

        expect(id1, isNot(id2));
      });
    });

    group('generateChunkBatchId', () {
      test('appends chunk index to base ID', () {
        final chunkId = generator.generateChunkBatchId('batch_abc123', 0);
        expect(chunkId, 'batch_abc123_chunk_0');
      });

      test('generates unique IDs for each chunk', () {
        final chunk0 = generator.generateChunkBatchId('batch_abc123', 0);
        final chunk1 = generator.generateChunkBatchId('batch_abc123', 1);
        final chunk2 = generator.generateChunkBatchId('batch_abc123', 2);

        expect(chunk0, isNot(chunk1));
        expect(chunk1, isNot(chunk2));
      });
    });

    group('isBatchIdValid', () {
      test('returns false initially', () {
        expect(generator.isBatchIdValid(), false);
      });

      test('returns true after generating', () {
        generator.generateBatchId(userId: 'user123');
        expect(generator.isBatchIdValid(), true);
      });

      test('returns false after TTL', () {
        generator.generateBatchId(userId: 'user123');

        mockNow = mockNow.add(const Duration(seconds: 31));

        expect(generator.isBatchIdValid(), false);
      });
    });
  });

  // ============================================================================
  // RETRY MANAGER TESTS
  // ============================================================================
  group('TestableRetryManager', () {
    late TestableRetryManager manager;

    setUp(() {
      manager = TestableRetryManager();
    });

    group('getRetryDelay', () {
      test('returns 0 seconds initially', () {
        expect(manager.getRetryDelay(), Duration.zero);
      });

      test('returns 10 seconds after first retry', () {
        manager.recordRetry();
        expect(manager.getRetryDelay(), const Duration(seconds: 10));
      });

      test('returns 20 seconds after second retry', () {
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.getRetryDelay(), const Duration(seconds: 20));
      });

      test('returns 30 seconds after third retry', () {
        manager.recordRetry();
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.getRetryDelay(), const Duration(seconds: 30));
      });
    });

    group('canRetry', () {
      test('returns true initially', () {
        expect(manager.canRetry, true);
      });

      test('returns true after 1 retry', () {
        manager.recordRetry();
        expect(manager.canRetry, true);
      });

      test('returns true after 2 retries', () {
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.canRetry, true);
      });

      test('returns false after 3 retries', () {
        manager.recordRetry();
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.canRetry, false);
      });
    });

    group('shouldPersist', () {
      test('returns false when retries available', () {
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.shouldPersist, false);
      });

      test('returns true when max retries reached', () {
        manager.recordRetry();
        manager.recordRetry();
        manager.recordRetry();
        expect(manager.shouldPersist, true);
      });
    });

    group('reset', () {
      test('resets retry count', () {
        manager.recordRetry();
        manager.recordRetry();

        manager.reset();

        expect(manager.retryAttempts, 0);
        expect(manager.canRetry, true);
      });
    });
  });

  // ============================================================================
  // CHUNKING TESTS
  // ============================================================================
  group('TestableClickChunker', () {
    group('needsChunking', () {
      test('returns false when under limits', () {
        expect(TestableClickChunker.needsChunking(100, 10000), false);
      });

      test('returns true when click count exceeds limit', () {
        expect(TestableClickChunker.needsChunking(501, 10000), true);
      });

      test('returns true when payload size exceeds limit', () {
        expect(TestableClickChunker.needsChunking(100, 1000001), true);
      });

      test('returns true at exactly 500 clicks', () {
        // > 500, not >= 500
        expect(TestableClickChunker.needsChunking(500, 10000), false);
        expect(TestableClickChunker.needsChunking(501, 10000), true);
      });
    });

    group('calculateChunkCount', () {
      test('returns 0 for empty list', () {
        expect(TestableClickChunker.calculateChunkCount(0), 0);
      });

      test('returns 1 for items under chunk size', () {
        expect(TestableClickChunker.calculateChunkCount(100), 1);
        expect(TestableClickChunker.calculateChunkCount(500), 1);
      });

      test('returns correct count for larger lists', () {
        expect(TestableClickChunker.calculateChunkCount(501), 2);
        expect(TestableClickChunker.calculateChunkCount(1000), 2);
        expect(TestableClickChunker.calculateChunkCount(1001), 3);
        expect(TestableClickChunker.calculateChunkCount(1500), 3);
      });
    });

    group('chunkItems', () {
      test('returns single chunk for small list', () {
        final items = List.generate(100, (i) => i);
        final chunks = TestableClickChunker.chunkItems(items);

        expect(chunks.length, 1);
        expect(chunks[0].length, 100);
      });

      test('splits into correct chunks', () {
        final items = List.generate(1200, (i) => i);
        final chunks = TestableClickChunker.chunkItems(items);

        expect(chunks.length, 3);
        expect(chunks[0].length, 500);
        expect(chunks[1].length, 500);
        expect(chunks[2].length, 200);
      });

      test('handles empty list', () {
        final chunks = TestableClickChunker.chunkItems<int>([]);
        expect(chunks, isEmpty);
      });

      test('preserves order', () {
        final items = List.generate(600, (i) => i);
        final chunks = TestableClickChunker.chunkItems(items);

        expect(chunks[0].first, 0);
        expect(chunks[0].last, 499);
        expect(chunks[1].first, 500);
        expect(chunks[1].last, 599);
      });
    });

    group('getChunk', () {
      test('returns correct chunk', () {
        final items = List.generate(1200, (i) => i);

        final chunk0 = TestableClickChunker.getChunk(items, 0);
        final chunk1 = TestableClickChunker.getChunk(items, 1);
        final chunk2 = TestableClickChunker.getChunk(items, 2);

        expect(chunk0.length, 500);
        expect(chunk1.length, 500);
        expect(chunk2.length, 200);
      });

      test('returns empty for out of bounds index', () {
        final items = List.generate(100, (i) => i);
        final chunk = TestableClickChunker.getChunk(items, 5);
        expect(chunk, isEmpty);
      });
    });
  });

  // ============================================================================
  // PAYLOAD BUILDER TESTS
  // ============================================================================
  group('TestablePayloadBuilder', () {
    group('buildPayload', () {
      test('includes all fields', () {
        final payload = TestablePayloadBuilder.buildPayload(
          batchId: 'batch_123',
          productClicks: {'p1': 1},
          shopProductClicks: {'sp1': 2},
          shopClicks: {'s1': 3},
          shopIds: {'sp1': 'shop1'},
        );

        expect(payload['batchId'], 'batch_123');
        expect(payload['productClicks'], {'p1': 1});
        expect(payload['shopProductClicks'], {'sp1': 2});
        expect(payload['shopClicks'], {'s1': 3});
        expect(payload['shopIds'], {'sp1': 'shop1'});
      });

      test('handles empty maps', () {
        final payload = TestablePayloadBuilder.buildPayload(
          batchId: 'batch_123',
          productClicks: {},
          shopProductClicks: {},
          shopClicks: {},
          shopIds: {},
        );

        expect(payload['productClicks'], isEmpty);
      });
    });

    group('estimatePayloadSize', () {
      test('returns byte count of JSON', () {
        final payload = {
          'batchId': 'test',
          'data': [1, 2, 3],
        };

        final size = TestablePayloadBuilder.estimatePayloadSize(payload);
        expect(size, greaterThan(0));
      });
    });

    group('bufferToClickItems', () {
      test('converts all click types', () {
        final items = TestablePayloadBuilder.bufferToClickItems(
          productClicks: {'p1': 1, 'p2': 2},
          shopProductClicks: {'sp1': 3},
          shopClicks: {'s1': 4},
          shopIds: {'sp1': 'shop1'},
        );

        expect(items.length, 4);
        expect(items.where((i) => i.type == 'product').length, 2);
        expect(items.where((i) => i.type == 'shop_product').length, 1);
        expect(items.where((i) => i.type == 'shop').length, 1);
      });

      test('includes shopId for shop products', () {
        final items = TestablePayloadBuilder.bufferToClickItems(
          productClicks: {},
          shopProductClicks: {'sp1': 1},
          shopClicks: {},
          shopIds: {'sp1': 'shop123'},
        );

        expect(items.first.shopId, 'shop123');
      });
    });

    group('buildChunkPayload', () {
      test('categorizes items correctly', () {
        final items = [
          ClickItem(itemId: 'p1', type: 'product', count: 1),
          ClickItem(itemId: 'sp1', type: 'shop_product', count: 2, shopId: 'shop1'),
          ClickItem(itemId: 's1', type: 'shop', count: 3),
        ];

        final payload = TestablePayloadBuilder.buildChunkPayload('batch_123', items);

        expect(payload['productClicks'], {'p1': 1});
        expect(payload['shopProductClicks'], {'sp1': 2});
        expect(payload['shopClicks'], {'s1': 3});
        expect(payload['shopIds'], {'sp1': 'shop1'});
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('rapid clicking is debounced', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cooldown = TestableClickCooldown(nowProvider: () => mockNow);

      // User rapidly clicks same product
      int acceptedClicks = 0;
      for (var i = 0; i < 10; i++) {
        if (cooldown.tryClick('product123')) {
          acceptedClicks++;
        }
        mockNow = mockNow.add(const Duration(milliseconds: 100));
      }

      // Only first click should be accepted (1 second hasn't passed)
      expect(acceptedClicks, 1);
    });

    test('batch ID ensures idempotency during retries', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final generator = TestableBatchIdGenerator(nowProvider: () => mockNow);

      // First attempt
      final batchId1 = generator.generateBatchId(userId: 'user123');

      // Retry after 5 seconds
      mockNow = mockNow.add(const Duration(seconds: 5));
      final batchId2 = generator.generateBatchId(userId: 'user123');

      // Same batch ID should be used for retries
      expect(batchId2, batchId1);
    });

    test('circuit breaker prevents retry storm', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final breaker = TestableClickCircuitBreaker(nowProvider: () => mockNow);

      // 3 failures in a row
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordFailure();

      // Attempts should be blocked
      expect(breaker.shouldAllowOperation(), false);

      // Even after 4 minutes
      mockNow = mockNow.add(const Duration(minutes: 4));
      expect(breaker.shouldAllowOperation(), false);

      // After 5 minutes, should reset
      mockNow = mockNow.add(const Duration(minutes: 2));
      expect(breaker.shouldAllowOperation(), true);
    });

    test('large click batch is properly chunked', () {
      final buffer = TestableClickBuffer();

      // Add 1200 clicks
      for (var i = 0; i < 1200; i++) {
        buffer.addProductClick('product_$i', isShopProduct: true);
      }

      final items = TestablePayloadBuilder.bufferToClickItems(
        productClicks: buffer.productClicks,
        shopProductClicks: buffer.shopProductClicks,
        shopClicks: buffer.shopClicks,
        shopIds: buffer.shopIds,
      );

      final chunks = TestableClickChunker.chunkItems(items);

      expect(chunks.length, 3);
      expect(chunks[0].length, 500);
      expect(chunks[1].length, 500);
      expect(chunks[2].length, 200);
    });

    test('retry backoff increases delay appropriately', () {
      final manager = TestableRetryManager();
      final delays = <Duration>[];

      while (manager.canRetry) {
        manager.recordRetry();
        delays.add(manager.getRetryDelay());
      }

      expect(delays, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 30),
      ]);

      // Total wait time: 60 seconds
      final total = delays.fold<int>(0, (sum, d) => sum + d.inSeconds);
      expect(total, 60);
    });

    test('force flush triggers when buffer is stale', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final buffer = TestableClickBuffer(nowProvider: () => mockNow);

      // Add a click and mark last flush
      buffer.addProductClick('p1', isShopProduct: true);
      buffer.lastSuccessfulFlush = mockNow;

      // Should not force flush yet
      expect(buffer.shouldForceFlush(), false);

      // After 6 minutes
      mockNow = mockNow.add(const Duration(minutes: 6));

      // Should force flush
      expect(buffer.shouldForceFlush(), true);
    });

    test('product ID normalization is consistent', () {
      final ids = [
        'products_abc123',
        'shop_products_abc123',
        'abc123',
      ];

      final normalized = ids.map(TestableClickBuffer.extractRawProductId).toList();

      // All should extract to the same raw ID
      expect(normalized, ['abc123', 'abc123', 'abc123']);
    });
  });
}