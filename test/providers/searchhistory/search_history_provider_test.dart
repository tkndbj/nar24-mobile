// test/providers/search_history_provider_test.dart
//
// Unit tests for SearchHistoryProvider pure logic
// Tests the EXACT logic from lib/providers/search_history_provider.dart
//
// Run: flutter test test/providers/search_history_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_search_history_provider.dart';

void main() {
  // ============================================================================
  // SEARCH HISTORY COMBINER TESTS
  // ============================================================================
  group('TestableSearchHistoryCombiner', () {
    group('combineAndDedupe', () {
      test('deduplicates by searchTerm keeping first occurrence', () {
        final entries = [
          TestableSearchEntry(
            id: 'doc1',
            searchTerm: 'iphone',
            timestamp: DateTime(2024, 6, 15, 10, 0),
          ),
          TestableSearchEntry(
            id: 'doc2',
            searchTerm: 'iphone', // Duplicate term
            timestamp: DateTime(2024, 6, 15, 9, 0),
          ),
          TestableSearchEntry(
            id: 'doc3',
            searchTerm: 'samsung',
            timestamp: DateTime(2024, 6, 15, 8, 0),
          ),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(entries);

        expect(result.length, 2);
        expect(result.map((e) => e.searchTerm), ['iphone', 'samsung']);
        // First occurrence (doc1) should be kept
        expect(result.firstWhere((e) => e.searchTerm == 'iphone').id, 'doc1');
      });

      test('sorts by timestamp descending (newest first)', () {
        final entries = [
          TestableSearchEntry(
            id: 'doc1',
            searchTerm: 'old search',
            timestamp: DateTime(2024, 6, 10),
          ),
          TestableSearchEntry(
            id: 'doc2',
            searchTerm: 'newest search',
            timestamp: DateTime(2024, 6, 15),
          ),
          TestableSearchEntry(
            id: 'doc3',
            searchTerm: 'middle search',
            timestamp: DateTime(2024, 6, 12),
          ),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(entries);

        expect(result.map((e) => e.searchTerm), [
          'newest search',
          'middle search',
          'old search',
        ]);
      });

      test('filters out optimistically deleted entries', () {
        final entries = [
          TestableSearchEntry(id: 'doc1', searchTerm: 'keep me', timestamp: DateTime(2024, 6, 15)),
          TestableSearchEntry(id: 'doc2', searchTerm: 'delete me', timestamp: DateTime(2024, 6, 14)),
          TestableSearchEntry(id: 'doc3', searchTerm: 'keep me too', timestamp: DateTime(2024, 6, 13)),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(
          entries,
          optimisticallyDeletedIds: {'doc2'},
        );

        expect(result.length, 2);
        expect(result.map((e) => e.searchTerm), ['keep me', 'keep me too']);
      });

      test('handles null timestamps', () {
        final entries = [
          TestableSearchEntry(id: 'doc1', searchTerm: 'no timestamp', timestamp: null),
          TestableSearchEntry(id: 'doc2', searchTerm: 'with timestamp', timestamp: DateTime(2024, 6, 15)),
          TestableSearchEntry(id: 'doc3', searchTerm: 'also no timestamp', timestamp: null),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(entries);

        // Entries with timestamps should come first
        expect(result.first.searchTerm, 'with timestamp');
      });

      test('handles empty list', () {
        final result = TestableSearchHistoryCombiner.combineAndDedupe([]);
        expect(result, isEmpty);
      });

      test('handles all entries deleted optimistically', () {
        final entries = [
          TestableSearchEntry(id: 'doc1', searchTerm: 'test1', timestamp: DateTime(2024, 6, 15)),
          TestableSearchEntry(id: 'doc2', searchTerm: 'test2', timestamp: DateTime(2024, 6, 14)),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(
          entries,
          optimisticallyDeletedIds: {'doc1', 'doc2'},
        );

        expect(result, isEmpty);
      });

      test('preserves entries when no optimistic deletes', () {
        final entries = [
          TestableSearchEntry(id: 'doc1', searchTerm: 'test', timestamp: DateTime(2024, 6, 15)),
        ];

        final result = TestableSearchHistoryCombiner.combineAndDedupe(
          entries,
          optimisticallyDeletedIds: {},
        );

        expect(result.length, 1);
      });
    });
  });

  // ============================================================================
  // OPTIMISTIC DELETE MANAGER TESTS
  // ============================================================================
  group('TestableOptimisticDeleteManager', () {
    late TestableOptimisticDeleteManager manager;

    setUp(() {
      manager = TestableOptimisticDeleteManager();
    });

    test('markAsDeleted adds ID to set', () {
      manager.markAsDeleted('doc1');
      expect(manager.isDeleted('doc1'), true);
      expect(manager.isDeleted('doc2'), false);
    });

    test('cleanup removes confirmed deletes', () {
      manager.markAsDeleted('doc1');
      manager.markAsDeleted('doc2');
      manager.markAsDeleted('doc3');

      // Simulate Firestore snapshot with doc1 and doc3 still existing
      manager.cleanup({'doc1', 'doc3', 'doc4'});

      // doc2 was deleted (not in existingDocIds), so remove from optimistic set
      expect(manager.isDeleted('doc2'), false);
      // doc1 and doc3 still exist, keep in optimistic set
      expect(manager.isDeleted('doc1'), true);
      expect(manager.isDeleted('doc3'), true);
    });

    test('rollback removes ID from set', () {
      manager.markAsDeleted('doc1');
      expect(manager.isDeleted('doc1'), true);

      manager.rollback('doc1');
      expect(manager.isDeleted('doc1'), false);
    });

    test('clear removes all IDs', () {
      manager.markAsDeleted('doc1');
      manager.markAsDeleted('doc2');

      manager.clear();

      expect(manager.optimisticallyDeleted, isEmpty);
    });
  });

  // ============================================================================
  // RETRY WITH BACKOFF TESTS
  // ============================================================================
  group('TestableRetryWithBackoff', () {
    group('calculateDelay', () {
      test('returns 200ms for retry 1', () {
        expect(
          TestableRetryWithBackoff.calculateDelay(1),
          const Duration(milliseconds: 200),
        );
      });

      test('returns 400ms for retry 2', () {
        expect(
          TestableRetryWithBackoff.calculateDelay(2),
          const Duration(milliseconds: 400),
        );
      });

      test('returns 600ms for retry 3', () {
        expect(
          TestableRetryWithBackoff.calculateDelay(3),
          const Duration(milliseconds: 600),
        );
      });

      test('returns 0ms for retry 0', () {
        expect(
          TestableRetryWithBackoff.calculateDelay(0),
          const Duration(milliseconds: 0),
        );
      });
    });

    group('shouldRetry', () {
      test('returns true when under max retries', () {
        expect(TestableRetryWithBackoff.shouldRetry(1, 3), true);
        expect(TestableRetryWithBackoff.shouldRetry(2, 3), true);
      });

      test('returns false when at max retries', () {
        expect(TestableRetryWithBackoff.shouldRetry(3, 3), false);
      });

      test('returns false when over max retries', () {
        expect(TestableRetryWithBackoff.shouldRetry(4, 3), false);
      });

      test('returns false when max is zero', () {
        expect(TestableRetryWithBackoff.shouldRetry(0, 0), false);
      });
    });
  });

  // ============================================================================
  // BATCH CHUNKER TESTS
  // ============================================================================
  group('TestableBatchChunker', () {
    group('chunk', () {
      test('chunks list into correct batch sizes', () {
        final items = List.generate(1200, (i) => 'item$i');

        final chunks = TestableBatchChunker.chunk(items, batchSize: 500);

        expect(chunks.length, 3);
        expect(chunks[0].length, 500);
        expect(chunks[1].length, 500);
        expect(chunks[2].length, 200);
      });

      test('handles list smaller than batch size', () {
        final items = List.generate(100, (i) => 'item$i');

        final chunks = TestableBatchChunker.chunk(items, batchSize: 500);

        expect(chunks.length, 1);
        expect(chunks[0].length, 100);
      });

      test('handles list exactly batch size', () {
        final items = List.generate(500, (i) => 'item$i');

        final chunks = TestableBatchChunker.chunk(items, batchSize: 500);

        expect(chunks.length, 1);
        expect(chunks[0].length, 500);
      });

      test('handles empty list', () {
        final chunks = TestableBatchChunker.chunk(<String>[], batchSize: 500);

        expect(chunks, isEmpty);
      });

      test('handles batch size of 1', () {
        final items = ['a', 'b', 'c'];

        final chunks = TestableBatchChunker.chunk(items, batchSize: 1);

        expect(chunks.length, 3);
        expect(chunks.every((c) => c.length == 1), true);
      });
    });

    group('batchCount', () {
      test('calculates correct batch count', () {
        expect(TestableBatchChunker.batchCount(1200, batchSize: 500), 3);
        expect(TestableBatchChunker.batchCount(1000, batchSize: 500), 2);
        expect(TestableBatchChunker.batchCount(501, batchSize: 500), 2);
        expect(TestableBatchChunker.batchCount(500, batchSize: 500), 1);
        expect(TestableBatchChunker.batchCount(100, batchSize: 500), 1);
      });

      test('returns 0 for empty list', () {
        expect(TestableBatchChunker.batchCount(0, batchSize: 500), 0);
      });
    });
  });

  // ============================================================================
  // DELETE STATE MANAGER TESTS
  // ============================================================================
  group('TestableDeleteStateManager', () {
    late TestableDeleteStateManager manager;

    setUp(() {
      manager = TestableDeleteStateManager();
    });

    test('startDelete marks entry as deleting and optimistically deleted', () {
      final started = manager.startDelete('doc1');

      expect(started, true);
      expect(manager.isDeleting('doc1'), true);
      expect(manager.isOptimisticallyDeleted('doc1'), true);
    });

    test('startDelete returns false if already deleting', () {
      manager.startDelete('doc1');

      final secondStart = manager.startDelete('doc1');

      expect(secondStart, false);
    });

    test('completeDelete removes from deleting but keeps optimistically deleted', () {
      manager.startDelete('doc1');

      manager.completeDelete('doc1');

      expect(manager.isDeleting('doc1'), false);
      expect(manager.isOptimisticallyDeleted('doc1'), true);
    });

    test('rollbackDelete removes from both sets', () {
      manager.startDelete('doc1');

      manager.rollbackDelete('doc1');

      expect(manager.isDeleting('doc1'), false);
      expect(manager.isOptimisticallyDeleted('doc1'), false);
    });

    test('confirmDeletes removes confirmed from optimistically deleted', () {
      manager.startDelete('doc1');
      manager.completeDelete('doc1');
      manager.startDelete('doc2');
      manager.completeDelete('doc2');

      // Firestore snapshot says doc1 is gone, doc2 still exists
      manager.confirmDeletes({'doc2', 'doc3'});

      expect(manager.isOptimisticallyDeleted('doc1'), false); // Confirmed deleted
      expect(manager.isOptimisticallyDeleted('doc2'), true); // Still pending
    });

    test('clear removes all state', () {
      manager.startDelete('doc1');
      manager.startDelete('doc2');

      manager.clear();

      expect(manager.isDeleting('doc1'), false);
      expect(manager.isDeleting('doc2'), false);
      expect(manager.isOptimisticallyDeleted('doc1'), false);
      expect(manager.isOptimisticallyDeleted('doc2'), false);
    });
  });

  // ============================================================================
  // TIMEOUT EXCEPTION TESTS
  // ============================================================================
  group('TestableTimeoutException', () {
    test('formats toString correctly', () {
      final exception = TestableTimeoutException(
        'Delete operation timed out',
        const Duration(seconds: 10),
      );

      expect(
        exception.toString(),
        'TimeoutException: Delete operation timed out after 10s',
      );
    });

    test('stores message and timeout', () {
      final exception = TestableTimeoutException(
        'Test message',
        const Duration(seconds: 5),
      );

      expect(exception.message, 'Test message');
      expect(exception.timeout, const Duration(seconds: 5));
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('user deletes search entry then cancels', () {
      final manager = TestableDeleteStateManager();

      // User taps delete
      manager.startDelete('search123');
      expect(manager.isOptimisticallyDeleted('search123'), true);

      // Network fails, rollback
      manager.rollbackDelete('search123');
      expect(manager.isOptimisticallyDeleted('search123'), false);

      // Entry should reappear in UI
    });

    test('search history combines multiple duplicate searches', () {
      final now = DateTime.now();
      final entries = [
        TestableSearchEntry(id: 'd1', searchTerm: 'iphone 15', timestamp: now),
        TestableSearchEntry(id: 'd2', searchTerm: 'samsung', timestamp: now.subtract(const Duration(hours: 1))),
        TestableSearchEntry(id: 'd3', searchTerm: 'iphone 15', timestamp: now.subtract(const Duration(hours: 2))),
        TestableSearchEntry(id: 'd4', searchTerm: 'pixel', timestamp: now.subtract(const Duration(hours: 3))),
        TestableSearchEntry(id: 'd5', searchTerm: 'samsung', timestamp: now.subtract(const Duration(hours: 4))),
      ];

      final result = TestableSearchHistoryCombiner.combineAndDedupe(entries);

      // Should have 3 unique terms: iphone 15, samsung, pixel
      expect(result.length, 3);
      expect(result.map((e) => e.searchTerm), ['iphone 15', 'samsung', 'pixel']);
    });

    test('delete all search history with many entries batches correctly', () {
      final docIds = List.generate(1523, (i) => 'doc$i');

      final batches = TestableBatchChunker.chunk(docIds, batchSize: 500);
      final batchCount = TestableBatchChunker.batchCount(1523, batchSize: 500);

      expect(batchCount, 4);
      expect(batches.length, 4);
      expect(batches[0].length, 500);
      expect(batches[1].length, 500);
      expect(batches[2].length, 500);
      expect(batches[3].length, 23);
    });

    test('retry backoff increases delay appropriately', () {
      final delays = <Duration>[];
      for (var attempt = 1; attempt <= 3; attempt++) {
        delays.add(TestableRetryWithBackoff.calculateDelay(attempt));
      }

      expect(delays, [
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 600),
      ]);

      // Total wait time: 1200ms for 3 retries
      final totalWait = delays.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
      expect(totalWait, 1200);
    });

    test('optimistic delete with Firestore confirmation', () {
      final manager = TestableDeleteStateManager();

      // User deletes 3 entries
      manager.startDelete('doc1');
      manager.completeDelete('doc1');
      manager.startDelete('doc2');
      manager.completeDelete('doc2');
      manager.startDelete('doc3');
      manager.completeDelete('doc3');

      // All marked as optimistically deleted
      expect(manager.isOptimisticallyDeleted('doc1'), true);
      expect(manager.isOptimisticallyDeleted('doc2'), true);
      expect(manager.isOptimisticallyDeleted('doc3'), true);

      // Firestore snapshot arrives: doc1 and doc3 confirmed deleted, doc2 still exists (retry needed?)
      manager.confirmDeletes({'doc2', 'doc4', 'doc5'});

      // doc1 and doc3 confirmed gone
      expect(manager.isOptimisticallyDeleted('doc1'), false);
      expect(manager.isOptimisticallyDeleted('doc3'), false);
      // doc2 still pending
      expect(manager.isOptimisticallyDeleted('doc2'), true);
    });

    test('concurrent delete attempts are blocked', () {
      final manager = TestableDeleteStateManager();

      // First delete starts
      expect(manager.startDelete('doc1'), true);

      // Concurrent attempts blocked
      expect(manager.startDelete('doc1'), false);
      expect(manager.startDelete('doc1'), false);

      // Complete first delete
      manager.completeDelete('doc1');

      // Now new delete can start
      expect(manager.startDelete('doc1'), true);
    });
  });
}