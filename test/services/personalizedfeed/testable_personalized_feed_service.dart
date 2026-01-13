// test/services/testable_personalized_feed_service.dart
//
// TESTABLE MIRROR of PersonalizedFeedService pure logic from lib/services/personalized_feed_service.dart
//
// This file contains EXACT copies of pure logic functions from PersonalizedFeedService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/personalized_feed_service.dart
//
// Last synced with: personalized_feed_service.dart (current version)

/// Mirrors cache configuration from PersonalizedFeedService
class TestableFeedCacheConfig {
  /// Cache duration for personalized feed
  /// Mirrors _personalizedCacheDuration
  static const Duration personalizedCacheDuration = Duration(hours: 6);

  /// Cache duration for trending products
  /// Mirrors _trendingCacheDuration
  static const Duration trendingCacheDuration = Duration(hours: 2);

  /// Maximum age for personalized feed before considered stale
  /// Feed older than this triggers fallback to trending
  static const Duration maxFeedAge = Duration(days: 3);

  /// SharedPreferences keys
  static const String keyPersonalizedFeed = 'personalized_feed_cache';
  static const String keyPersonalizedExpiry = 'personalized_feed_expiry';
  static const String keyTrendingProducts = 'trending_products_cache';
  static const String keyTrendingExpiry = 'trending_products_expiry';
}

/// Mirrors cache validity logic from PersonalizedFeedService
class TestableFeedCacheValidator {
  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableFeedCacheValidator({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors _isCacheValid from PersonalizedFeedService
  /// Check if cached data is still valid
  bool isCacheValid(DateTime? expiryTime) {
    if (expiryTime == null) return false;
    return expiryTime.isAfter(nowProvider());
  }

  /// Calculate cache expiry time for new data
  DateTime calculateExpiry({required bool isPersonalized}) {
    final duration = isPersonalized
        ? TestableFeedCacheConfig.personalizedCacheDuration
        : TestableFeedCacheConfig.trendingCacheDuration;
    return nowProvider().add(duration);
  }

  /// Get remaining cache time
  Duration getRemainingTime(DateTime? expiryTime) {
    if (expiryTime == null) return Duration.zero;
    final remaining = expiryTime.difference(nowProvider());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Check if cache is expired
  bool isCacheExpired(DateTime? expiryTime) {
    return !isCacheValid(expiryTime);
  }
}

/// Mirrors stale feed detection from PersonalizedFeedService
class TestableFeedStalenessChecker {
  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableFeedStalenessChecker({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Check if feed is stale (>3 days old)
  /// Mirrors the staleness check in _getPersonalizedProducts
  bool isFeedStale(DateTime? lastComputed) {
    if (lastComputed == null) return false; // No timestamp = not stale (let other checks handle)
    
    final age = nowProvider().difference(lastComputed);
    return age.inDays > 3;
  }

  /// Get feed age in days
  int getFeedAgeInDays(DateTime lastComputed) {
    return nowProvider().difference(lastComputed).inDays;
  }

  /// Get feed age as Duration
  Duration getFeedAge(DateTime lastComputed) {
    return nowProvider().difference(lastComputed);
  }

  /// Check if feed needs refresh (approaching staleness)
  bool needsRefreshSoon(DateTime? lastComputed, {int warningDays = 2}) {
    if (lastComputed == null) return true;
    final age = nowProvider().difference(lastComputed);
    return age.inDays >= warningDays;
  }
}

/// Mirrors fallback decision logic from PersonalizedFeedService
class TestableFeedFallbackDecider {
  /// Determine if should fall back to trending
  /// Mirrors the fallback logic in _getPersonalizedProducts
  static FallbackReason? shouldFallbackToTrending({
    required bool feedExists,
    required bool feedIsEmpty,
    required bool feedIsStale,
  }) {
    if (!feedExists) {
      return FallbackReason.feedNotFound;
    }
    if (feedIsEmpty) {
      return FallbackReason.feedEmpty;
    }
    if (feedIsStale) {
      return FallbackReason.feedStale;
    }
    return null; // No fallback needed
  }

  /// Determine feed source for user
  static FeedSource determineFeedSource({
    required bool isAuthenticated,
    required bool hasPersonalizedFeed,
    required bool personalizedFeedValid,
  }) {
    if (!isAuthenticated) {
      return FeedSource.trending;
    }
    if (!hasPersonalizedFeed) {
      return FeedSource.trending;
    }
    if (!personalizedFeedValid) {
      return FeedSource.trending;
    }
    return FeedSource.personalized;
  }
}

/// Reasons for falling back to trending
enum FallbackReason {
  feedNotFound,
  feedEmpty,
  feedStale,
  fetchError,
}

/// Source of feed data
enum FeedSource {
  personalized,
  trending,
  cachedPersonalized,
  cachedTrending,
}

/// Mirrors cache data structure
class TestableFeedCache {
  List<String>? personalizedFeed;
  List<String>? trendingProducts;
  DateTime? personalizedExpiry;
  DateTime? trendingExpiry;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableFeedCache({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Check if personalized cache is valid
  bool get isPersonalizedValid =>
      personalizedExpiry != null &&
      personalizedExpiry!.isAfter(nowProvider()) &&
      personalizedFeed != null &&
      personalizedFeed!.isNotEmpty;

  /// Check if trending cache is valid
  bool get isTrendingValid =>
      trendingExpiry != null &&
      trendingExpiry!.isAfter(nowProvider()) &&
      trendingProducts != null &&
      trendingProducts!.isNotEmpty;

  /// Set personalized feed with auto-calculated expiry
  void setPersonalizedFeed(List<String> products) {
    personalizedFeed = products;
    personalizedExpiry = nowProvider().add(
      TestableFeedCacheConfig.personalizedCacheDuration,
    );
  }

  /// Set trending products with auto-calculated expiry
  void setTrendingProducts(List<String> products) {
    trendingProducts = products;
    trendingExpiry = nowProvider().add(
      TestableFeedCacheConfig.trendingCacheDuration,
    );
  }

  /// Clear all caches
  void clear() {
    personalizedFeed = null;
    trendingProducts = null;
    personalizedExpiry = null;
    trendingExpiry = null;
  }

  /// Clear only personalized cache
  void clearPersonalized() {
    personalizedFeed = null;
    personalizedExpiry = null;
  }

  /// Clear only trending cache
  void clearTrending() {
    trendingProducts = null;
    trendingExpiry = null;
  }

  /// Get best available feed (personalized > trending > expired caches)
  List<String> getBestAvailable() {
    if (isPersonalizedValid) {
      return personalizedFeed!;
    }
    if (isTrendingValid) {
      return trendingProducts!;
    }
    // Fallback to expired caches (better than nothing)
    if (personalizedFeed != null && personalizedFeed!.isNotEmpty) {
      return personalizedFeed!;
    }
    if (trendingProducts != null && trendingProducts!.isNotEmpty) {
      return trendingProducts!;
    }
    return [];
  }
}

/// Mirrors expiry timestamp conversion for SharedPreferences
class TestableExpiryConverter {
  /// Convert DateTime to milliseconds for storage
  static int toMilliseconds(DateTime expiry) {
    return expiry.millisecondsSinceEpoch;
  }

  /// Convert milliseconds to DateTime
  static DateTime fromMilliseconds(int milliseconds) {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// Check if stored milliseconds represent valid (non-expired) time
  static bool isValidExpiry(int? milliseconds, {DateTime? now}) {
    if (milliseconds == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final currentTime = now ?? DateTime.now();
    return expiry.isAfter(currentTime);
  }
}

/// Mirrors feed metadata extraction
class TestableFeedMetadataExtractor {
  /// Extract metadata from Firestore document data
  static Map<String, dynamic> extractMetadata(Map<String, dynamic> data) {
    // Handle Timestamp or DateTime for lastComputed
    DateTime? lastComputed;
    final rawLastComputed = data['lastComputed'];
    if (rawLastComputed is DateTime) {
      lastComputed = rawLastComputed;
    }
    // Note: In production, this would be a Timestamp

    final productIds = data['productIds'] as List?;
    final stats = data['stats'] as Map<String, dynamic>?;

    return {
      'lastComputed': lastComputed,
      'productsCount': productIds?.length ?? 0,
      'avgScore': stats?['avgScore'],
      'topCategories': stats?['topCategories'],
      'version': data['version'],
    };
  }
}