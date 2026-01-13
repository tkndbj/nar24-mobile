// test/services/testable_algolia_service.dart
//
// TESTABLE MIRROR of AlgoliaService pure logic from lib/services/algolia_service.dart
//
// This file contains EXACT copies of pure logic functions from AlgoliaService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/algolia_service.dart
//
// Last synced with: algolia_service.dart (current version)

/// Mirrors AlgoliaPage from AlgoliaService
class TestableAlgoliaPage {
  final List<String> ids;
  final int page;
  final int nbPages;

  TestableAlgoliaPage({
    required this.ids,
    required this.page,
    required this.nbPages,
  });

  bool get hasMorePages => page < nbPages - 1;
  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;
  int get count => ids.length;
}

/// Mirrors URL construction from AlgoliaService
class TestableAlgoliaUrlBuilder {
  /// Mirrors _constructSearchUri from AlgoliaService
  static Uri constructSearchUri({
    required String applicationId,
    required String indexName,
  }) {
    return Uri.https(
      '$applicationId-dsn.algolia.net',
      '/1/indexes/$indexName/query',
    );
  }

  /// Build the host string
  static String buildHost(String applicationId) {
    return '$applicationId-dsn.algolia.net';
  }

  /// Build the path for a given index
  static String buildPath(String indexName) {
    return '/1/indexes/$indexName/query';
  }
}

/// Mirrors replica index selection from AlgoliaService
class TestableReplicaIndexResolver {
  /// Mirrors _getReplicaIndexName from AlgoliaService
  /// Returns the replica index name based on the sort option.
  static String getReplicaIndexName(String indexName, String sortOption) {
    // Only use replicas for shop_products index
    // Regular products index doesn't need replicas for search
    if (!indexName.contains('shop_products')) {
      return indexName; // Return original index for non-shop searches
    }

    // Only apply replicas to shop_products when there's an actual sort option
    if (sortOption == 'None' || sortOption.isEmpty) {
      return indexName; // Return base index when no sorting
    }

    // Map sort options to replica names for shop_products only
    switch (sortOption) {
      case 'date':
        return 'shop_products_createdAt_desc';
      case 'alphabetical':
        return 'shop_products_alphabetical';
      case 'price_asc':
        return 'shop_products_price_asc';
      case 'price_desc':
        return 'shop_products_price_desc';
      default:
        return indexName; // fallback to original
    }
  }

  /// Check if index supports replicas
  static bool supportsReplicas(String indexName) {
    return indexName.contains('shop_products');
  }

  /// Get all valid sort options for shop_products
  static List<String> get validSortOptions => [
        'date',
        'alphabetical',
        'price_asc',
        'price_desc',
      ];
}

/// Mirrors timeout progression from AlgoliaService
class TestableTimeoutProgression {
  /// Mirrors _timeoutProgression from AlgoliaService
  static const List<Duration> progression = [
    Duration(seconds: 3), // First attempt: 3s
    Duration(seconds: 5), // Second attempt: 5s
    Duration(seconds: 8), // Third attempt: 8s
  ];

  /// Get timeout for a specific attempt (1-indexed)
  static Duration getTimeoutForAttempt(int attempt) {
    final idx = (attempt - 1).clamp(0, progression.length - 1);
    return progression[idx];
  }

  /// Get total maximum wait time across all retries
  static Duration get totalMaxWaitTime {
    return progression.fold(
      Duration.zero,
      (total, timeout) => total + timeout,
    );
  }
}

/// Mirrors filter building from AlgoliaService
class TestableAlgoliaFilterBuilder {
  /// Join filters with AND operator
  /// Mirrors: filters.join(' AND ')
  static String joinFilters(List<String> filters) {
    return filters.join(' AND ');
  }

  /// Build shop filter
  static String buildShopFilter(String shopId) {
    return 'shopId:"$shopId"';
  }

  /// Build user filter for orders
  static String buildUserFilter({
    required String userId,
    required bool isSold,
  }) {
    if (isSold) {
      return 'sellerId:"$userId"';
    } else {
      return 'buyerId:"$userId"';
    }
  }

  /// Build language filter
  static String buildLanguageFilter(String languageCode) {
    return 'languageCode:$languageCode';
  }

  /// Combine multiple filters
  static String combineFilters(List<String> filters) {
    if (filters.isEmpty) return '';
    return filters.join(' AND ');
  }
}

/// Mirrors URL parameter encoding from AlgoliaService
class TestableAlgoliaParamEncoder {
  /// Encode a single parameter
  static String encodeParam(String key, String value) {
    return '${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}';
  }

  /// Encode multiple parameters
  static String encodeParams(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Encode for facet filters (special JSON encoding)
  static String encodeFacetFilters(List<List<String>> facetFilters) {
    return Uri.encodeQueryComponent(
      facetFilters.map((f) => f).toList().toString(),
    );
  }
}

/// Mirrors retry condition logic from AlgoliaService
class TestableRetryCondition {
  /// Check if exception should trigger retry
  /// Mirrors retryIf logic from AlgoliaService
  static bool shouldRetry(Exception e) {
    final errorString = e.toString();

    // SocketException - network issues
    if (errorString.contains('SocketException')) return true;

    // TimeoutException - request took too long
    if (errorString.contains('TimeoutException')) return true;

    // HttpException - server errors (5xx)
    if (errorString.contains('HttpException')) return true;

    // DNS lookup failure
    if (errorString.contains('Failed host lookup')) return true;

    return false;
  }

  /// Categorize error type
  static String categorizeError(Exception e) {
    final errorString = e.toString();

    if (errorString.contains('SocketException')) return 'network';
    if (errorString.contains('TimeoutException')) return 'timeout';
    if (errorString.contains('HttpException')) return 'server';
    if (errorString.contains('Failed host lookup')) return 'dns';
    if (errorString.contains('FormatException')) return 'parse';

    return 'unknown';
  }
}

/// Mirrors ID extraction from Algolia hits
class TestableAlgoliaIdExtractor {
  /// Extract Firestore document ID from Algolia hit
  /// Mirrors the logic in searchIdsWithFacets
  static String? extractId(Map<String, dynamic> hit) {
    // Primary: use ilanNo field (contains actual Firestore doc ID)
    final ilanNo = hit['ilanNo']?.toString();
    if (ilanNo != null && ilanNo.isNotEmpty) {
      return ilanNo;
    }

    // Fallback: extract from objectID
    final objectId = (hit['objectID'] ?? '').toString();
    if (objectId.startsWith('shop_products_')) {
      final extractedId = objectId.substring('shop_products_'.length);
      if (extractedId.isNotEmpty) {
        return extractedId;
      }
    }

    return null;
  }

  /// Extract IDs from multiple hits
  static List<String> extractIds(List<Map<String, dynamic>> hits) {
    final ids = <String>[];
    for (final hit in hits) {
      final id = extractId(hit);
      if (id != null) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// Check if objectID has shop_products prefix
  static bool hasShopProductsPrefix(String objectId) {
    return objectId.startsWith('shop_products_');
  }

  /// Remove shop_products prefix from objectID
  static String? removeShopProductsPrefix(String objectId) {
    if (!hasShopProductsPrefix(objectId)) return null;
    final id = objectId.substring('shop_products_'.length);
    return id.isEmpty ? null : id;
  }
}

/// Mirrors response status handling
class TestableAlgoliaResponseHandler {
  /// Check if status code indicates success
  static bool isSuccess(int statusCode) {
    return statusCode == 200;
  }

  /// Check if status code indicates server error (should retry)
  static bool isServerError(int statusCode) {
    return statusCode >= 500;
  }

  /// Check if status code indicates client error (should NOT retry)
  static bool isClientError(int statusCode) {
    return statusCode >= 400 && statusCode < 500;
  }

  /// Determine action based on status code
  static String getActionForStatus(int statusCode) {
    if (statusCode == 200) return 'process';
    if (statusCode >= 500) return 'retry';
    if (statusCode >= 400) return 'abort';
    return 'unknown';
  }
}

/// Mirrors debounce duration
class TestableAlgoliaDebounce {
  static const Duration debounceDuration = Duration(milliseconds: 300);

  /// Check if enough time has passed since last call
  static bool shouldExecute(DateTime? lastCall, {DateTime? now}) {
    if (lastCall == null) return true;
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(lastCall) >= debounceDuration;
  }
}

/// Mirrors attributes to retrieve configuration
class TestableAlgoliaAttributes {
  /// Product attributes to retrieve
  static const List<String> productAttributes = [
    'objectID',
    'productName',
    'price',
    'imageUrls',
    'campaignName',
    'discountPercentage',
    'isBoosted',
    'dailyClickCount',
    'averageRating',
    'purchaseCount',
    'createdAt',
    'isFeatured',
    'isTrending',
    'colorImages',
    'brandModel',
    'category',
    'subcategory',
    'subsubcategory',
    'condition',
    'userId',
    'sellerName',
    'reviewCount',
    'originalPrice',
    'currency',
    'clickCount',
    'rankingScore',
    'collection',
    'deliveryOption',
    'shopId',
    'quantity',
  ];

  /// Order attributes to retrieve
  static const List<String> orderAttributes = [
    'objectID',
    'productName',
    'brandModel',
    'buyerName',
    'sellerName',
    'orderId',
    'productId',
    'price',
    'currency',
    'quantity',
    'productImage',
    'selectedColorImage',
    'selectedColor',
    'productAverageRating',
    'buyerId',
    'sellerId',
    'shopId',
    'timestamp',
  ];

  /// Category attributes to retrieve
  static const List<String> categoryAttributes = [
    'objectID',
    'categoryKey',
    'subcategoryKey',
    'subsubcategoryKey',
    'displayName',
    'type',
    'level',
    'languageCode',
  ];

  /// Build comma-separated attribute string
  static String buildAttributeString(List<String> attributes) {
    return attributes.join(',');
  }
}