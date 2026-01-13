// test/services/personalized_feed_service_test.dart
//
// Unit tests for PersonalizedFeedService pure logic
// Tests the EXACT logic from lib/services/personalized_feed_service.dart
//
// Run: flutter test test/services/personalized_feed_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_personalized_feed_service.dart';

void main() {
  // ============================================================================
  // CACHE CONFIG TESTS
  // ============================================================================
  group('TestableFeedCacheConfig', () {
    test('personalized cache duration is 6 hours', () {
      expect(
        TestableFeedCacheConfig.personalizedCacheDuration,
        const Duration(hours: 6),
      );
    });

    test('trending cache duration is 2 hours', () {
      expect(
        TestableFeedCacheConfig.trendingCacheDuration,
        const Duration(hours: 2),
      );
    });

    test('max feed age is 3 days', () {
      expect(
        TestableFeedCacheConfig.maxFeedAge,
        const Duration(days: 3),
      );
    });

    test('SharedPreferences keys are defined', () {
      expect(TestableFeedCacheConfig.keyPersonalizedFeed, isNotEmpty);
      expect(TestableFeedCacheConfig.keyPersonalizedExpiry, isNotEmpty);
      expect(TestableFeedCacheConfig.keyTrendingProducts, isNotEmpty);
      expect(TestableFeedCacheConfig.keyTrendingExpiry, isNotEmpty);
    });

    test('personalized cache is longer than trending', () {
      expect(
        TestableFeedCacheConfig.personalizedCacheDuration >
            TestableFeedCacheConfig.trendingCacheDuration,
        true,
      );
    });
  });

  // ============================================================================
  // CACHE VALIDATOR TESTS
  // ============================================================================
  group('TestableFeedCacheValidator', () {
    late TestableFeedCacheValidator validator;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      validator = TestableFeedCacheValidator(nowProvider: () => mockNow);
    });

    group('isCacheValid', () {
      test('returns true for future expiry', () {
        final futureExpiry = mockNow.add(const Duration(hours: 1));
        expect(validator.isCacheValid(futureExpiry), true);
      });

      test('returns false for past expiry', () {
        final pastExpiry = mockNow.subtract(const Duration(hours: 1));
        expect(validator.isCacheValid(pastExpiry), false);
      });

      test('returns false for null expiry', () {
        expect(validator.isCacheValid(null), false);
      });

      test('returns false for exact current time (not after)', () {
        expect(validator.isCacheValid(mockNow), false);
      });

      test('returns true for 1 second in future', () {
        final justAfter = mockNow.add(const Duration(seconds: 1));
        expect(validator.isCacheValid(justAfter), true);
      });
    });

    group('calculateExpiry', () {
      test('personalized expiry is 6 hours from now', () {
        final expiry = validator.calculateExpiry(isPersonalized: true);
        expect(expiry, mockNow.add(const Duration(hours: 6)));
      });

      test('trending expiry is 2 hours from now', () {
        final expiry = validator.calculateExpiry(isPersonalized: false);
        expect(expiry, mockNow.add(const Duration(hours: 2)));
      });
    });

    group('getRemainingTime', () {
      test('returns positive duration for valid cache', () {
        final expiry = mockNow.add(const Duration(hours: 3));
        expect(validator.getRemainingTime(expiry), const Duration(hours: 3));
      });

      test('returns zero for expired cache', () {
        final expiry = mockNow.subtract(const Duration(hours: 1));
        expect(validator.getRemainingTime(expiry), Duration.zero);
      });

      test('returns zero for null expiry', () {
        expect(validator.getRemainingTime(null), Duration.zero);
      });
    });
  });

  // ============================================================================
  // STALENESS CHECKER TESTS
  // ============================================================================
  group('TestableFeedStalenessChecker', () {
    late TestableFeedStalenessChecker checker;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      checker = TestableFeedStalenessChecker(nowProvider: () => mockNow);
    });

    group('isFeedStale', () {
      test('returns false for feed computed today', () {
        final today = mockNow;
        expect(checker.isFeedStale(today), false);
      });

      test('returns false for feed computed 2 days ago', () {
        final twoDaysAgo = mockNow.subtract(const Duration(days: 2));
        expect(checker.isFeedStale(twoDaysAgo), false);
      });

      test('returns false for feed computed exactly 3 days ago', () {
        final threeDaysAgo = mockNow.subtract(const Duration(days: 3));
        // 3 days is not > 3, so not stale
        expect(checker.isFeedStale(threeDaysAgo), false);
      });

      test('returns true for feed computed 4 days ago', () {
        final fourDaysAgo = mockNow.subtract(const Duration(days: 4));
        expect(checker.isFeedStale(fourDaysAgo), true);
      });

      test('returns true for feed computed 1 week ago', () {
        final weekAgo = mockNow.subtract(const Duration(days: 7));
        expect(checker.isFeedStale(weekAgo), true);
      });

      test('returns false for null lastComputed', () {
        // Null means no timestamp - let other validation handle it
        expect(checker.isFeedStale(null), false);
      });
    });

    group('getFeedAgeInDays', () {
      test('returns 0 for today', () {
        expect(checker.getFeedAgeInDays(mockNow), 0);
      });

      test('returns correct days for old feed', () {
        final fiveDaysAgo = mockNow.subtract(const Duration(days: 5));
        expect(checker.getFeedAgeInDays(fiveDaysAgo), 5);
      });
    });

    group('needsRefreshSoon', () {
      test('returns true for null lastComputed', () {
        expect(checker.needsRefreshSoon(null), true);
      });

      test('returns false for fresh feed', () {
        final today = mockNow;
        expect(checker.needsRefreshSoon(today, warningDays: 2), false);
      });

      test('returns true when approaching staleness', () {
        final twoDaysAgo = mockNow.subtract(const Duration(days: 2));
        expect(checker.needsRefreshSoon(twoDaysAgo, warningDays: 2), true);
      });
    });
  });

  // ============================================================================
  // FALLBACK DECIDER TESTS
  // ============================================================================
  group('TestableFeedFallbackDecider', () {
    group('shouldFallbackToTrending', () {
      test('returns feedNotFound when feed does not exist', () {
        final reason = TestableFeedFallbackDecider.shouldFallbackToTrending(
          feedExists: false,
          feedIsEmpty: false,
          feedIsStale: false,
        );
        expect(reason, FallbackReason.feedNotFound);
      });

      test('returns feedEmpty when feed exists but is empty', () {
        final reason = TestableFeedFallbackDecider.shouldFallbackToTrending(
          feedExists: true,
          feedIsEmpty: true,
          feedIsStale: false,
        );
        expect(reason, FallbackReason.feedEmpty);
      });

      test('returns feedStale when feed exists but is stale', () {
        final reason = TestableFeedFallbackDecider.shouldFallbackToTrending(
          feedExists: true,
          feedIsEmpty: false,
          feedIsStale: true,
        );
        expect(reason, FallbackReason.feedStale);
      });

      test('returns null when feed is valid', () {
        final reason = TestableFeedFallbackDecider.shouldFallbackToTrending(
          feedExists: true,
          feedIsEmpty: false,
          feedIsStale: false,
        );
        expect(reason, null);
      });
    });

    group('determineFeedSource', () {
      test('returns trending for unauthenticated user', () {
        final source = TestableFeedFallbackDecider.determineFeedSource(
          isAuthenticated: false,
          hasPersonalizedFeed: true,
          personalizedFeedValid: true,
        );
        expect(source, FeedSource.trending);
      });

      test('returns trending when no personalized feed', () {
        final source = TestableFeedFallbackDecider.determineFeedSource(
          isAuthenticated: true,
          hasPersonalizedFeed: false,
          personalizedFeedValid: false,
        );
        expect(source, FeedSource.trending);
      });

      test('returns trending when personalized feed invalid', () {
        final source = TestableFeedFallbackDecider.determineFeedSource(
          isAuthenticated: true,
          hasPersonalizedFeed: true,
          personalizedFeedValid: false,
        );
        expect(source, FeedSource.trending);
      });

      test('returns personalized when all conditions met', () {
        final source = TestableFeedFallbackDecider.determineFeedSource(
          isAuthenticated: true,
          hasPersonalizedFeed: true,
          personalizedFeedValid: true,
        );
        expect(source, FeedSource.personalized);
      });
    });
  });

  // ============================================================================
  // FEED CACHE TESTS
  // ============================================================================
  group('TestableFeedCache', () {
    late TestableFeedCache cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableFeedCache(nowProvider: () => mockNow);
    });

    group('isPersonalizedValid', () {
      test('returns false initially', () {
        expect(cache.isPersonalizedValid, false);
      });

      test('returns true after setting feed', () {
        cache.setPersonalizedFeed(['p1', 'p2', 'p3']);
        expect(cache.isPersonalizedValid, true);
      });

      test('returns false for empty feed', () {
        cache.setPersonalizedFeed([]);
        expect(cache.isPersonalizedValid, false);
      });

      test('returns false after cache expires', () {
        cache.setPersonalizedFeed(['p1', 'p2']);
        
        // Advance time past 6 hours
        mockNow = mockNow.add(const Duration(hours: 7));
        
        expect(cache.isPersonalizedValid, false);
      });
    });

    group('isTrendingValid', () {
      test('returns false initially', () {
        expect(cache.isTrendingValid, false);
      });

      test('returns true after setting products', () {
        cache.setTrendingProducts(['t1', 't2']);
        expect(cache.isTrendingValid, true);
      });

      test('returns false after cache expires', () {
        cache.setTrendingProducts(['t1', 't2']);
        
        // Advance time past 2 hours
        mockNow = mockNow.add(const Duration(hours: 3));
        
        expect(cache.isTrendingValid, false);
      });
    });

    group('clear', () {
      test('clears all caches', () {
        cache.setPersonalizedFeed(['p1']);
        cache.setTrendingProducts(['t1']);

        cache.clear();

        expect(cache.personalizedFeed, null);
        expect(cache.trendingProducts, null);
        expect(cache.personalizedExpiry, null);
        expect(cache.trendingExpiry, null);
      });
    });

    group('getBestAvailable', () {
      test('returns personalized when valid', () {
        cache.setPersonalizedFeed(['p1', 'p2']);
        cache.setTrendingProducts(['t1', 't2']);

        expect(cache.getBestAvailable(), ['p1', 'p2']);
      });

      test('returns trending when personalized invalid', () {
        cache.setTrendingProducts(['t1', 't2']);
        // No personalized set

        expect(cache.getBestAvailable(), ['t1', 't2']);
      });

      test('returns expired personalized as last resort', () {
        cache.setPersonalizedFeed(['p1', 'p2']);
        
        // Expire both caches
        mockNow = mockNow.add(const Duration(hours: 10));
        
        expect(cache.getBestAvailable(), ['p1', 'p2']);
      });

      test('returns empty when nothing cached', () {
        expect(cache.getBestAvailable(), isEmpty);
      });
    });
  });

  // ============================================================================
  // EXPIRY CONVERTER TESTS
  // ============================================================================
  group('TestableExpiryConverter', () {
    group('toMilliseconds / fromMilliseconds', () {
      test('round trip preserves time', () {
        final original = DateTime(2024, 6, 15, 12, 30, 45);
        final ms = TestableExpiryConverter.toMilliseconds(original);
        final restored = TestableExpiryConverter.fromMilliseconds(ms);

        expect(restored, original);
      });
    });

    group('isValidExpiry', () {
      test('returns true for future time', () {
        final future = DateTime.now().add(const Duration(hours: 1));
        final ms = future.millisecondsSinceEpoch;

        expect(TestableExpiryConverter.isValidExpiry(ms), true);
      });

      test('returns false for past time', () {
        final past = DateTime.now().subtract(const Duration(hours: 1));
        final ms = past.millisecondsSinceEpoch;

        expect(TestableExpiryConverter.isValidExpiry(ms), false);
      });

      test('returns false for null', () {
        expect(TestableExpiryConverter.isValidExpiry(null), false);
      });
    });
  });

  // ============================================================================
  // METADATA EXTRACTOR TESTS
  // ============================================================================
  group('TestableFeedMetadataExtractor', () {
    group('extractMetadata', () {
      test('extracts all fields', () {
        final data = {
          'lastComputed': DateTime(2024, 6, 15),
          'productIds': ['p1', 'p2', 'p3'],
          'stats': {
            'avgScore': 0.85,
            'topCategories': ['Electronics', 'Fashion'],
          },
          'version': 5,
        };

        final metadata = TestableFeedMetadataExtractor.extractMetadata(data);

        expect(metadata['lastComputed'], DateTime(2024, 6, 15));
        expect(metadata['productsCount'], 3);
        expect(metadata['avgScore'], 0.85);
        expect(metadata['topCategories'], ['Electronics', 'Fashion']);
        expect(metadata['version'], 5);
      });

      test('handles missing fields', () {
        final data = <String, dynamic>{};

        final metadata = TestableFeedMetadataExtractor.extractMetadata(data);

        expect(metadata['lastComputed'], null);
        expect(metadata['productsCount'], 0);
        expect(metadata['avgScore'], null);
      });

      test('handles null productIds', () {
        final data = {'productIds': null};

        final metadata = TestableFeedMetadataExtractor.extractMetadata(data);

        expect(metadata['productsCount'], 0);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('new user gets trending products', () {
      final source = TestableFeedFallbackDecider.determineFeedSource(
        isAuthenticated: true,
        hasPersonalizedFeed: false, // New user, no activity yet
        personalizedFeedValid: false,
      );

      expect(source, FeedSource.trending);
    });

    test('returning user with fresh feed gets personalized', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableFeedCache(nowProvider: () => mockNow);
      
      cache.setPersonalizedFeed(['p1', 'p2', 'p3', 'p4', 'p5']);

      expect(cache.isPersonalizedValid, true);
      expect(cache.getBestAvailable().length, 5);
    });

    test('stale personalized feed triggers trending fallback', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final checker = TestableFeedStalenessChecker(nowProvider: () => mockNow);
      
      // Feed was computed 5 days ago
      final lastComputed = mockNow.subtract(const Duration(days: 5));
      
      expect(checker.isFeedStale(lastComputed), true);

      final fallbackReason = TestableFeedFallbackDecider.shouldFallbackToTrending(
        feedExists: true,
        feedIsEmpty: false,
        feedIsStale: true,
      );

      expect(fallbackReason, FallbackReason.feedStale);
    });

    test('cache expires correctly over time', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableFeedCache(nowProvider: () => mockNow);

      // Set both caches
      cache.setPersonalizedFeed(['p1', 'p2']);
      cache.setTrendingProducts(['t1', 't2']);

      expect(cache.isPersonalizedValid, true);
      expect(cache.isTrendingValid, true);

      // After 3 hours: trending expired, personalized still valid
      mockNow = mockNow.add(const Duration(hours: 3));
      expect(cache.isTrendingValid, false);
      expect(cache.isPersonalizedValid, true);

      // After 7 hours total: both expired
      mockNow = mockNow.add(const Duration(hours: 4));
      expect(cache.isPersonalizedValid, false);
      expect(cache.isTrendingValid, false);

      // But getBestAvailable still returns expired data as fallback
      expect(cache.getBestAvailable(), ['p1', 'p2']);
    });

    test('graceful degradation on error', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableFeedCache(nowProvider: () => mockNow);

      // Simulate: had cached data, then error occurs, cache expires
      cache.setTrendingProducts(['t1', 't2', 't3']);
      
      // Time passes, cache expires
      mockNow = mockNow.add(const Duration(hours: 5));

      // Even though expired, getBestAvailable returns it (better than nothing)
      final fallback = cache.getBestAvailable();
      expect(fallback, isNotEmpty);
      expect(fallback, ['t1', 't2', 't3']);
    });
  });
}