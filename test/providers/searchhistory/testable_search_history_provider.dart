// test/providers/testable_search_history_provider.dart
//
// TESTABLE MIRROR of SearchHistoryProvider pure logic from lib/providers/search_history_provider.dart
//
// This file contains EXACT copies of pure logic functions from SearchHistoryProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/search_history_provider.dart
//
// Last synced with: search_history_provider.dart (current version)

/// Simplified SearchEntry model for testing
class TestableSearchEntry {
  final String id;
  final String searchTerm;
  final DateTime? timestamp;

  TestableSearchEntry({
    required this.id,
    required this.searchTerm,
    this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestableSearchEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Mirrors _updateCombinedEntries logic from SearchHistoryProvider
class TestableSearchHistoryCombiner {
  /// Combines entries, filters optimistic deletes, dedupes by searchTerm, sorts by timestamp
  /// Mirrors _updateCombinedEntries from SearchHistoryProvider
  static List<TestableSearchEntry> combineAndDedupe(
    List<TestableSearchEntry> rawEntries, {
    Set<String>? optimisticallyDeletedIds,
  }) {
    // Filter out optimistically deleted entries
    final filteredEntries = optimisticallyDeletedIds != null
        ? rawEntries
            .where((entry) => !optimisticallyDeletedIds.contains(entry.id))
            .toList()
        : rawEntries;

    // Deduplicate by searchTerm (keep first occurrence)
    final Map<String, TestableSearchEntry> uniqueMap = {};
    for (var entry in filteredEntries) {
      if (!uniqueMap.containsKey(entry.searchTerm)) {
        uniqueMap[entry.searchTerm] = entry;
      }
    }

    // Sort by timestamp descending (newest first)
    final result = uniqueMap.values.toList()
      ..sort((a, b) => (b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)));

    return result;
  }
}

/// Mirrors _cleanupOptimisticDeletes logic from SearchHistoryProvider
class TestableOptimisticDeleteManager {
  final Set<String> optimisticallyDeleted = {};

  /// Add an ID to optimistic delete set
  void markAsDeleted(String id) {
    optimisticallyDeleted.add(id);
  }

  /// Check if an ID is optimistically deleted
  bool isDeleted(String id) {
    return optimisticallyDeleted.contains(id);
  }

  /// Mirrors _cleanupOptimisticDeletes from SearchHistoryProvider
  /// Removes IDs that are confirmed deleted from Firestore
  void cleanup(Set<String> existingDocIds) {
    final toRemove = optimisticallyDeleted
        .where((id) => !existingDocIds.contains(id))
        .toList();
    for (final id in toRemove) {
      optimisticallyDeleted.remove(id);
    }
  }

  /// Rollback an optimistic delete (on error)
  void rollback(String id) {
    optimisticallyDeleted.remove(id);
  }

  void clear() {
    optimisticallyDeleted.clear();
  }
}

/// Mirrors exponential backoff retry logic from SearchHistoryProvider
class TestableRetryWithBackoff {
  /// Calculate delay for retry attempt
  /// Mirrors delay calculation in _deleteFromFirestore
  static Duration calculateDelay(int retryCount) {
    return Duration(milliseconds: 200 * retryCount);
  }

  /// Check if should retry
  static bool shouldRetry(int currentAttempt, int maxRetries) {
    return currentAttempt < maxRetries;
  }
}

/// Mirrors batch chunking logic from SearchHistoryProvider.deleteAllForUser
class TestableBatchChunker {
  static const int defaultBatchSize = 500;

  /// Chunks a list into batches of specified size
  /// Mirrors batching in deleteAllForUser
  static List<List<T>> chunk<T>(List<T> items, {int batchSize = defaultBatchSize}) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize > items.length) ? items.length : i + batchSize;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  /// Calculate number of batches needed
  static int batchCount(int itemCount, {int batchSize = defaultBatchSize}) {
    if (itemCount == 0) return 0;
    return (itemCount / batchSize).ceil();
  }
}

/// Mirrors delete state management from SearchHistoryProvider
class TestableDeleteStateManager {
  final Map<String, bool> _deletingEntries = {};
  final Set<String> _optimisticallyDeleted = {};

  bool isDeleting(String docId) => _deletingEntries.containsKey(docId);
  bool isOptimisticallyDeleted(String docId) =>
      _optimisticallyDeleted.contains(docId);

  /// Start a delete operation
  /// Returns false if already deleting
  bool startDelete(String docId) {
    if (_deletingEntries.containsKey(docId)) {
      return false; // Already deleting
    }
    _deletingEntries[docId] = true;
    _optimisticallyDeleted.add(docId);
    return true;
  }

  /// Complete a delete operation successfully
  void completeDelete(String docId) {
    _deletingEntries.remove(docId);
    // Keep in optimisticallyDeleted until confirmed by Firestore snapshot
  }

  /// Rollback a failed delete operation
  void rollbackDelete(String docId) {
    _deletingEntries.remove(docId);
    _optimisticallyDeleted.remove(docId);
  }

  /// Confirm deletes from Firestore snapshot
  void confirmDeletes(Set<String> existingDocIds) {
    final confirmed = _optimisticallyDeleted
        .where((id) => !existingDocIds.contains(id))
        .toList();
    for (final id in confirmed) {
      _optimisticallyDeleted.remove(id);
    }
  }

  void clear() {
    _deletingEntries.clear();
    _optimisticallyDeleted.clear();
  }
}

/// Mirrors TimeoutException from SearchHistoryProvider
class TestableTimeoutException implements Exception {
  final String message;
  final Duration timeout;

  const TestableTimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message after ${timeout.inSeconds}s';
}