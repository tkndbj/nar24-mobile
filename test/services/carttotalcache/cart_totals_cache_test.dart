// test/services/cart_totals_cache_test.dart
//
// Unit tests for CartTotalsCache pure logic
// Tests the EXACT logic from lib/services/cart_totals_cache.dart
//
// Run: flutter test test/services/cart_totals_cache_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_cart_totals_cache.dart';

void main() {
  // ============================================================================
  // CACHED ITEM TOTAL TESTS
  // ============================================================================
  group('TestableCachedItemTotal', () {
    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'productId': 'prod123',
          'unitPrice': 99.99,
          'total': 199.98,
          'quantity': 2,
          'isBundleItem': true,
        };

        final item = TestableCachedItemTotal.fromJson(json);

        expect(item.productId, 'prod123');
        expect(item.unitPrice, 99.99);
        expect(item.total, 199.98);
        expect(item.quantity, 2);
        expect(item.isBundleItem, true);
      });

      test('handles missing fields with defaults', () {
        final json = <String, dynamic>{};

        final item = TestableCachedItemTotal.fromJson(json);

        expect(item.productId, '');
        expect(item.unitPrice, 0.0);
        expect(item.total, 0.0);
        expect(item.quantity, 1);
        expect(item.isBundleItem, false);
      });

      test('handles int prices as double', () {
        final json = {
          'productId': 'p1',
          'unitPrice': 100, // int
          'total': 200, // int
          'quantity': 2,
        };

        final item = TestableCachedItemTotal.fromJson(json);

        expect(item.unitPrice, 100.0);
        expect(item.total, 200.0);
      });

      test('handles null values', () {
        final json = {
          'productId': null,
          'unitPrice': null,
          'total': null,
          'quantity': null,
          'isBundleItem': null,
        };

        final item = TestableCachedItemTotal.fromJson(json);

        expect(item.productId, '');
        expect(item.unitPrice, 0.0);
        expect(item.quantity, 1);
        expect(item.isBundleItem, false);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final item = TestableCachedItemTotal(
          productId: 'prod123',
          unitPrice: 50.0,
          total: 150.0,
          quantity: 3,
          isBundleItem: true,
        );

        final json = item.toJson();

        expect(json['productId'], 'prod123');
        expect(json['unitPrice'], 50.0);
        expect(json['total'], 150.0);
        expect(json['quantity'], 3);
        expect(json['isBundleItem'], true);
      });
    });

    group('round-trip', () {
      test('toJson -> fromJson preserves data', () {
        final original = TestableCachedItemTotal(
          productId: 'roundtrip_prod',
          unitPrice: 75.50,
          total: 226.50,
          quantity: 3,
          isBundleItem: true,
        );

        final json = original.toJson();
        final restored = TestableCachedItemTotal.fromJson(json);

        expect(restored.productId, original.productId);
        expect(restored.unitPrice, original.unitPrice);
        expect(restored.total, original.total);
        expect(restored.quantity, original.quantity);
        expect(restored.isBundleItem, original.isBundleItem);
      });
    });
  });

  // ============================================================================
  // CACHED CART TOTALS TESTS
  // ============================================================================
  group('TestableCachedCartTotals', () {
    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'total': 299.99,
          'currency': 'USD',
          'items': [
            {'productId': 'p1', 'unitPrice': 100.0, 'total': 100.0, 'quantity': 1},
            {'productId': 'p2', 'unitPrice': 99.99, 'total': 199.99, 'quantity': 2},
          ],
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.total, 299.99);
        expect(totals.currency, 'USD');
        expect(totals.items.length, 2);
        expect(totals.items[0].productId, 'p1');
        expect(totals.items[1].productId, 'p2');
      });

      test('defaults currency to TL', () {
        final json = {
          'total': 100.0,
          'items': [],
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.currency, 'TL');
      });

      test('handles empty items', () {
        final json = {
          'total': 0.0,
          'currency': 'TL',
          'items': [],
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.items, isEmpty);
      });

      test('handles null items', () {
        final json = {
          'total': 0.0,
          'currency': 'TL',
          'items': null,
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.items, isEmpty);
      });

      test('handles Map<Object?, Object?> items (Firebase response)', () {
        final json = {
          'total': 150.0,
          'currency': 'TL',
          'items': [
            <Object?, Object?>{'productId': 'p1', 'unitPrice': 50, 'total': 50, 'quantity': 1},
          ],
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.items.length, 1);
        expect(totals.items[0].productId, 'p1');
      });

      test('handles int total as double', () {
        final json = {
          'total': 100, // int
          'currency': 'TL',
          'items': [],
        };

        final totals = TestableCachedCartTotals.fromJson(json);

        expect(totals.total, 100.0);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final totals = TestableCachedCartTotals(
          total: 250.0,
          currency: 'EUR',
          items: [
            TestableCachedItemTotal(
              productId: 'p1',
              unitPrice: 125.0,
              total: 250.0,
              quantity: 2,
            ),
          ],
        );

        final json = totals.toJson();

        expect(json['total'], 250.0);
        expect(json['currency'], 'EUR');
        expect(json['items'], isA<List>());
        expect((json['items'] as List).length, 1);
      });
    });
  });

  // ============================================================================
  // CACHE KEY BUILDER TESTS
  // ============================================================================
  group('TestableCacheKeyBuilder', () {
    group('buildKey', () {
      test('combines userId and productIds', () {
        final key = TestableCacheKeyBuilder.buildKey('user123', ['p1', 'p2']);
        expect(key, 'user123:p1,p2');
      });

      test('sorts productIds for consistent keys', () {
        final key1 = TestableCacheKeyBuilder.buildKey('user', ['c', 'a', 'b']);
        final key2 = TestableCacheKeyBuilder.buildKey('user', ['b', 'c', 'a']);
        final key3 = TestableCacheKeyBuilder.buildKey('user', ['a', 'b', 'c']);

        expect(key1, key2);
        expect(key2, key3);
        expect(key1, 'user:a,b,c');
      });

      test('handles single product', () {
        final key = TestableCacheKeyBuilder.buildKey('user', ['only_one']);
        expect(key, 'user:only_one');
      });

      test('handles empty products', () {
        final key = TestableCacheKeyBuilder.buildKey('user', []);
        expect(key, 'user:');
      });

      test('does not modify original list', () {
        final products = ['z', 'a', 'm'];
        TestableCacheKeyBuilder.buildKey('user', products);

        expect(products, ['z', 'a', 'm']); // Unchanged
      });
    });

    group('parseKey', () {
      test('extracts userId and productIds', () {
        final parsed = TestableCacheKeyBuilder.parseKey('user123:p1,p2,p3');

        expect(parsed!['userId'], 'user123');
        expect(parsed['productIds'], ['p1', 'p2', 'p3']);
      });

      test('handles empty products', () {
        final parsed = TestableCacheKeyBuilder.parseKey('user:');

        expect(parsed!['userId'], 'user');
        expect(parsed['productIds'], isEmpty);
      });

      test('returns null for invalid key', () {
        expect(TestableCacheKeyBuilder.parseKey('no_colon'), null);
      });
    });

    group('isUserKey', () {
      test('returns true for matching user', () {
        expect(
          TestableCacheKeyBuilder.isUserKey('user123:p1,p2', 'user123'),
          true,
        );
      });

      test('returns false for different user', () {
        expect(
          TestableCacheKeyBuilder.isUserKey('user123:p1,p2', 'user456'),
          false,
        );
      });

      test('handles partial match correctly', () {
        // 'user1' should not match 'user123:...'
        expect(
          TestableCacheKeyBuilder.isUserKey('user123:p1', 'user1'),
          false,
        );
      });
    });
  });

  // ============================================================================
  // CACHE ENTRY TESTS
  // ============================================================================
  group('TestableCacheEntry', () {
    group('isExpired', () {
      test('returns false before expiry', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: now.add(const Duration(minutes: 10)),
          createdAt: now,
        );

        expect(entry.isExpired(now: now), false);
      });

      test('returns true after expiry', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          createdAt: now.subtract(const Duration(minutes: 11)),
        );

        expect(entry.isExpired(now: now), true);
      });

      test('returns true at exact expiry time', () {
        final now = DateTime(2024, 6, 15, 12, 0, 0);
        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: now,
          createdAt: now.subtract(const Duration(minutes: 10)),
        );

        // isAfter is exclusive, so exactly at expiry is NOT expired
        expect(entry.isExpired(now: now), false);

        // But 1ms later it is
        expect(
          entry.isExpired(now: now.add(const Duration(milliseconds: 1))),
          true,
        );
      });
    });

    group('getAge', () {
      test('calculates age correctly', () {
        final createdAt = DateTime(2024, 6, 15, 12, 0, 0);
        final now = DateTime(2024, 6, 15, 12, 5, 0); // 5 minutes later
        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: createdAt.add(const Duration(minutes: 10)),
          createdAt: createdAt,
        );

        expect(entry.getAge(now: now), const Duration(minutes: 5));
      });
    });

    group('getRemainingTTL', () {
      test('calculates remaining TTL', () {
        final createdAt = DateTime(2024, 6, 15, 12, 0, 0);
        final expiresAt = createdAt.add(const Duration(minutes: 10));
        final now = createdAt.add(const Duration(minutes: 3));

        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: expiresAt,
          createdAt: createdAt,
        );

        expect(entry.getRemainingTTL(now: now), const Duration(minutes: 7));
      });

      test('returns zero for expired entry', () {
        final createdAt = DateTime(2024, 6, 15, 12, 0, 0);
        final expiresAt = createdAt.add(const Duration(minutes: 10));
        final now = createdAt.add(const Duration(minutes: 15));

        final entry = TestableCacheEntry(
          data: 'test',
          expiresAt: expiresAt,
          createdAt: createdAt,
        );

        expect(entry.getRemainingTTL(now: now), Duration.zero);
      });
    });
  });

  // ============================================================================
  // CACHE MANAGER TESTS
  // ============================================================================
  group('TestableCacheManager', () {
    late TestableCacheManager<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      cache = TestableCacheManager<String>(nowProvider: () => mockNow);
    });

    group('get/set', () {
      test('stores and retrieves value', () {
        cache.set('key1', 'value1');
        expect(cache.get('key1'), 'value1');
      });

      test('returns null for missing key', () {
        expect(cache.get('nonexistent'), null);
      });

      test('returns null for expired entry', () {
        cache.set('key1', 'value1', ttl: const Duration(minutes: 5));

        // Advance time past TTL
        mockNow = mockNow.add(const Duration(minutes: 6));

        expect(cache.get('key1'), null);
      });

      test('removes expired entry on access', () {
        cache.set('key1', 'value1', ttl: const Duration(minutes: 5));
        mockNow = mockNow.add(const Duration(minutes: 6));

        cache.get('key1'); // This should remove it
        expect(cache.length, 0);
      });
    });

    group('max entries enforcement', () {
      test('evicts oldest when full', () {
        // Fill cache to max
        for (var i = 0; i < 50; i++) {
          cache.set('key_$i', 'value_$i');
          // Stagger creation times
          mockNow = mockNow.add(const Duration(seconds: 1));
        }

        expect(cache.length, 50);

        // Add one more
        cache.set('key_new', 'value_new');

        // Should have evicted 10 oldest + added 1 = 41
        expect(cache.length, 41);

        // Oldest entries should be gone
        expect(cache.get('key_0'), null);
        expect(cache.get('key_9'), null);

        // Newer entries should remain
        expect(cache.get('key_10'), 'value_10');
        expect(cache.get('key_new'), 'value_new');
      });
    });

    group('removeByPrefix', () {
      test('removes entries matching prefix', () {
        cache.set('user1:p1', 'v1');
        cache.set('user1:p2', 'v2');
        cache.set('user2:p1', 'v3');

        final removed = cache.removeByPrefix('user1:');

        expect(removed, 2);
        expect(cache.get('user1:p1'), null);
        expect(cache.get('user1:p2'), null);
        expect(cache.get('user2:p1'), 'v3');
      });

      test('returns 0 for no matches', () {
        cache.set('user1:p1', 'v1');
        final removed = cache.removeByPrefix('user999:');
        expect(removed, 0);
      });
    });

    group('removeExpiredEntries', () {
      test('removes only expired entries', () {
        cache.set('short', 'v1', ttl: const Duration(minutes: 1));
        cache.set('long', 'v2', ttl: const Duration(minutes: 10));

        // Advance 5 minutes
        mockNow = mockNow.add(const Duration(minutes: 5));

        final removed = cache.removeExpiredEntries();

        expect(removed, 1);
        expect(cache.get('short'), null);
        expect(cache.get('long'), 'v2');
      });
    });

    group('evictOldestEntries', () {
      test('evicts specified count of oldest', () {
        for (var i = 0; i < 10; i++) {
          cache.set('key_$i', 'value_$i');
          mockNow = mockNow.add(const Duration(seconds: 1));
        }

        final evicted = cache.evictOldestEntries(3);

        expect(evicted, 3);
        expect(cache.length, 7);
        expect(cache.get('key_0'), null);
        expect(cache.get('key_1'), null);
        expect(cache.get('key_2'), null);
        expect(cache.get('key_3'), 'value_3');
      });
    });

    group('getStats', () {
      test('returns correct statistics', () {
        cache.set('valid1', 'v1', ttl: const Duration(minutes: 10));
        cache.set('valid2', 'v2', ttl: const Duration(minutes: 10));
        cache.set('expired', 'v3', ttl: const Duration(minutes: 1));

        // Expire one entry
        mockNow = mockNow.add(const Duration(minutes: 5));

        final stats = cache.getStats();

        expect(stats['totalEntries'], 3);
        expect(stats['validEntries'], 2);
        expect(stats['expiredEntries'], 1);
        expect(stats['maxEntries'], 50);
      });
    });
  });

  // ============================================================================
  // USER CACHE INVALIDATOR TESTS
  // ============================================================================
  group('TestableUserCacheInvalidator', () {
    group('buildUserPrefix', () {
      test('appends colon', () {
        expect(TestableUserCacheInvalidator.buildUserPrefix('user123'), 'user123:');
      });
    });

    group('filterUserKeys', () {
      test('filters keys for user', () {
        final keys = ['user1:p1', 'user1:p2', 'user2:p1', 'user3:p1'];
        final filtered = TestableUserCacheInvalidator.filterUserKeys(keys, 'user1');

        expect(filtered, ['user1:p1', 'user1:p2']);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('cart total caching workflow', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableCacheManager<TestableCachedCartTotals>(
        nowProvider: () => mockNow,
      );

      // User adds items to cart
      final totals = TestableCachedCartTotals(
        total: 299.99,
        currency: 'TL',
        items: [
          TestableCachedItemTotal(
            productId: 'nike_shoes',
            unitPrice: 199.99,
            total: 199.99,
            quantity: 1,
          ),
          TestableCachedItemTotal(
            productId: 'adidas_shirt',
            unitPrice: 100.0,
            total: 100.0,
            quantity: 1,
          ),
        ],
      );

      // Cache the totals
      final key = TestableCacheKeyBuilder.buildKey(
        'user123',
        ['nike_shoes', 'adidas_shirt'],
      );
      cache.set(key, totals);

      // Same cart (different order) should hit cache
      final key2 = TestableCacheKeyBuilder.buildKey(
        'user123',
        ['adidas_shirt', 'nike_shoes'], // Different order
      );
      expect(key, key2); // Keys should match due to sorting

      final cached = cache.get(key);
      expect(cached!.total, 299.99);
      expect(cached.items.length, 2);
    });

    test('cache invalidation on cart change', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableCacheManager<String>(
        nowProvider: () => mockNow,
      );

      // User has multiple cached cart states
      cache.set('user123:p1,p2', 'totals1');
      cache.set('user123:p1,p2,p3', 'totals2');
      cache.set('user456:p1', 'other_user');

      // User123 modifies cart - invalidate all their caches
      final removed = cache.removeByPrefix('user123:');

      expect(removed, 2);
      expect(cache.get('user123:p1,p2'), null);
      expect(cache.get('user123:p1,p2,p3'), null);
      expect(cache.get('user456:p1'), 'other_user'); // Untouched
    });

    test('Cloud Function response parsing', () {
      // Simulates actual Cloud Function response
      final cloudFunctionResponse = {
        'total': 549.97,
        'currency': 'TL',
        'items': [
          {
            'productId': 'prod_abc123',
            'unitPrice': 199.99,
            'total': 399.98,
            'quantity': 2,
            'isBundleItem': false,
          },
          {
            'productId': 'prod_xyz789',
            'unitPrice': 149.99,
            'total': 149.99,
            'quantity': 1,
            'isBundleItem': true,
          },
        ],
      };

      final totals = TestableCachedCartTotals.fromJson(cloudFunctionResponse);

      expect(totals.total, 549.97);
      expect(totals.currency, 'TL');
      expect(totals.items.length, 2);
      expect(totals.items[0].quantity, 2);
      expect(totals.items[1].isBundleItem, true);
    });

    test('TTL expiration prevents stale prices', () {
      var mockNow = DateTime(2024, 6, 15, 12, 0, 0);
      final cache = TestableCacheManager<TestableCachedCartTotals>(
        nowProvider: () => mockNow,
      );

      final totals = TestableCachedCartTotals(
        total: 100.0,
        currency: 'TL',
        items: [],
      );

      // Cache with 10 minute TTL
      cache.set('user:p1', totals);

      // 9 minutes later - still valid
      mockNow = mockNow.add(const Duration(minutes: 9));
      expect(cache.get('user:p1'), isNotNull);

      // 11 minutes later - expired (stale price protection)
      mockNow = mockNow.add(const Duration(minutes: 2));
      expect(cache.get('user:p1'), null);
    });
  });
}