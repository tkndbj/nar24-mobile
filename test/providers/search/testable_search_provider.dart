// test/providers/testable_search_provider.dart
//
// TESTABLE MIRROR of SearchProvider pure logic from lib/providers/search_provider.dart
//
// This file contains EXACT copies of pure logic functions from SearchProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/providers/search_provider.dart
//
// Last synced with: search_provider.dart (current version)

/// Simplified Suggestion model for testing
class TestableSuggestion {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;

  TestableSuggestion({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestableSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Mirrors product result combination logic from SearchProvider
class TestableProductResultCombiner {
  /// Mirrors _combineProductResults from SearchProvider
  /// Combines results from multiple indices, deduplicates by ID
  static List<TestableSuggestion> combineResults(
    List<List<TestableSuggestion>> results,
    int limit, {
    Set<String>? existingIds,
  }) {
    final combined = <TestableSuggestion>[];
    final seenIds = <String>{};

    // Also exclude already loaded suggestions
    if (existingIds != null) {
      seenIds.addAll(existingIds);
    }

    for (final list in results) {
      for (final p in list) {
        if (combined.length >= limit) break;
        if (seenIds.add(p.id)) {
          combined.add(p);
        }
      }
      if (combined.length >= limit) break;
    }

    return combined;
  }
}

/// Mirrors pagination logic from SearchProvider
class TestablePaginationManager {
  static const int initialPageSize = 10;
  static const int loadMorePageSize = 5;
  static const int maxSuggestions = 20;

  int currentProductCount = 0;
  bool hasMoreProducts = true;
  bool isLoadingMore = false;
  String? lastSearchTerm;

  /// Mirrors hasMoreProducts getter from SearchProvider
  bool get canLoadMore =>
      hasMoreProducts && currentProductCount < maxSuggestions;

  /// Check if loadMoreSuggestions should proceed
  /// Mirrors guard conditions in loadMoreSuggestions
  bool shouldAllowLoadMore({
    required bool isDisposed,
    required String currentTerm,
  }) {
    if (isDisposed) return false;
    if (isLoadingMore) return false;
    if (!hasMoreProducts) return false;
    if (currentProductCount >= maxSuggestions) return false;
    if (currentTerm.isEmpty) return false;
    return true;
  }

  /// Calculate how many more items to fetch
  /// Mirrors calculation in loadMoreSuggestions
  int calculateFetchCount() {
    final remaining = maxSuggestions - currentProductCount;
    return remaining < loadMorePageSize ? remaining : loadMorePageSize;
  }

  /// Update state after successful load
  void onLoadSuccess(int newItemsCount, int requestedCount) {
    currentProductCount += newItemsCount;

    // Check if we've reached the end
    if (newItemsCount < requestedCount || newItemsCount == 0) {
      hasMoreProducts = false;
    }
  }

  /// Reset pagination for new search
  /// Mirrors _resetPagination from SearchProvider
  void reset() {
    currentProductCount = 0;
    hasMoreProducts = true;
    isLoadingMore = false;
  }

  /// Update after initial search results
  void onInitialSearchComplete(int resultsCount) {
    currentProductCount = resultsCount;
    if (resultsCount < initialPageSize) {
      hasMoreProducts = false;
    }
  }
}

/// Mirrors search term validation from SearchProvider
class TestableSearchTermValidator {
  /// Validate and normalize search term
  static String normalize(String term) {
    return term.trim();
  }

  /// Check if term is valid for search
  static bool isValidForSearch(String term) {
    return term.trim().isNotEmpty;
  }
}