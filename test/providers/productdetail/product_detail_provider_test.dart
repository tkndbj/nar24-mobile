// test/providers/product_detail_provider_test.dart
//
// Unit tests for ProductDetailProvider pure logic
// Tests the EXACT logic from lib/providers/product_detail_provider.dart
//
// Run: flutter test test/providers/product_detail_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_product_detail_provider.dart';

void main() {
  // ============================================================================
  // FIRESTORE KEY SANITIZER TESTS
  // ============================================================================
  group('TestableFirestoreKeySanitizer', () {
    group('sanitize', () {
      test('replaces dots with underscores', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('user.email@test.com'),
          'user_email@test_com',
        );
      });

      test('replaces commas with underscores', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('value1,value2,value3'),
          'value1_value2_value3',
        );
      });

      test('replaces brackets with underscores', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('array[0]'),
          'array_0_',
        );
        expect(
          TestableFirestoreKeySanitizer.sanitize('[key]'),
          '_key_',
        );
      });

      test('replaces multiple invalid characters', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('user.name[0],test'),
          'user_name_0__test',
        );
      });

      test('returns unchanged string if no invalid characters', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('valid_key-123'),
          'valid_key-123',
        );
      });

      test('handles empty string', () {
        expect(TestableFirestoreKeySanitizer.sanitize(''), '');
      });

      test('handles email addresses', () {
        expect(
          TestableFirestoreKeySanitizer.sanitize('user@example.com'),
          'user@example_com',
        );
      });
    });

    group('hasInvalidCharacters', () {
      test('returns true for strings with dots', () {
        expect(TestableFirestoreKeySanitizer.hasInvalidCharacters('a.b'), true);
      });

      test('returns true for strings with commas', () {
        expect(TestableFirestoreKeySanitizer.hasInvalidCharacters('a,b'), true);
      });

      test('returns true for strings with brackets', () {
        expect(TestableFirestoreKeySanitizer.hasInvalidCharacters('a[b]'), true);
      });

      test('returns false for valid strings', () {
        expect(
          TestableFirestoreKeySanitizer.hasInvalidCharacters('valid_key'),
          false,
        );
      });
    });
  });

  // ============================================================================
  // PRODUCT URL GENERATOR TESTS
  // ============================================================================
  group('TestableProductUrlGenerator', () {
    group('generate', () {
      test('generates correct URL for product ID', () {
        expect(
          TestableProductUrlGenerator.generate('abc123'),
          'https://emlak-mobile-app.web.app/products/abc123',
        );
      });

      test('handles IDs with special characters', () {
        expect(
          TestableProductUrlGenerator.generate('product-001_v2'),
          'https://emlak-mobile-app.web.app/products/product-001_v2',
        );
      });

      test('handles empty ID', () {
        expect(
          TestableProductUrlGenerator.generate(''),
          'https://emlak-mobile-app.web.app/products/',
        );
      });
    });

    group('parseProductId', () {
      test('extracts product ID from valid URL', () {
        expect(
          TestableProductUrlGenerator.parseProductId(
            'https://emlak-mobile-app.web.app/products/abc123',
          ),
          'abc123',
        );
      });

      test('returns null for invalid URL', () {
        expect(
          TestableProductUrlGenerator.parseProductId(
            'https://other-site.com/products/abc123',
          ),
          null,
        );
      });

      test('returns null for URL with no ID', () {
        expect(
          TestableProductUrlGenerator.parseProductId(
            'https://emlak-mobile-app.web.app/products/',
          ),
          null,
        );
      });

      test('handles complex IDs', () {
        expect(
          TestableProductUrlGenerator.parseProductId(
            'https://emlak-mobile-app.web.app/products/item-001_v2-final',
          ),
          'item-001_v2-final',
        );
      });
    });
  });

  // ============================================================================
  // MESSAGE VALIDATOR TESTS
  // ============================================================================
  group('TestableMessageValidator', () {
    group('validate', () {
      test('accepts valid product message', () {
        final validMessage = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test Product',
            'productImageUrls': ['https://example.com/img.jpg'],
            'productPrice': 99.99,
          },
        };

        expect(() => TestableMessageValidator.validate(validMessage), returnsNormally);
      });

      test('throws for null senderId', () {
        final message = {
          'senderId': null,
          'type': 'product',
          'content': {},
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid senderId in messageData.',
          )),
        );
      });

      test('throws for non-string senderId', () {
        final message = {
          'senderId': 123,
          'type': 'product',
          'content': {},
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for null type', () {
        final message = {
          'senderId': 'user123',
          'type': null,
          'content': {},
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid type in messageData.',
          )),
        );
      });

      test('throws for null content', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': null,
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid content in messageData.',
          )),
        );
      });

      test('throws for empty productId in product message', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': '',
            'productName': 'Test',
            'productImageUrls': ['url'],
            'productPrice': 10,
          },
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid productId in content.',
          )),
        );
      });

      test('throws for empty productName', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': '',
            'productImageUrls': ['url'],
            'productPrice': 10,
          },
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid productName in content.',
          )),
        );
      });

      test('throws for empty productImageUrls', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test',
            'productImageUrls': [],
            'productPrice': 10,
          },
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid productImageUrls in content.',
          )),
        );
      });

      test('throws for zero price', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test',
            'productImageUrls': ['url'],
            'productPrice': 0,
          },
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Invalid productPrice in content.',
          )),
        );
      });

      test('throws for negative price', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test',
            'productImageUrls': ['url'],
            'productPrice': -10,
          },
        };

        expect(
          () => TestableMessageValidator.validate(message),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts non-product message types without product validation', () {
        final textMessage = {
          'senderId': 'user123',
          'type': 'text',
          'content': {'text': 'Hello'},
        };

        expect(() => TestableMessageValidator.validate(textMessage), returnsNormally);
      });

      test('accepts integer price', () {
        final message = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test',
            'productImageUrls': ['url'],
            'productPrice': 100, // int instead of double
          },
        };

        expect(() => TestableMessageValidator.validate(message), returnsNormally);
      });
    });

    group('isValid', () {
      test('returns true for valid message', () {
        final validMessage = {
          'senderId': 'user123',
          'type': 'product',
          'content': {
            'productId': 'prod123',
            'productName': 'Test',
            'productImageUrls': ['url'],
            'productPrice': 10,
          },
        };

        expect(TestableMessageValidator.isValid(validMessage), true);
      });

      test('returns false for invalid message', () {
        final invalidMessage = {
          'senderId': null,
          'type': 'product',
          'content': {},
        };

        expect(TestableMessageValidator.isValid(invalidMessage), false);
      });
    });
  });

  // ============================================================================
  // NAVIGATION THROTTLE TESTS
  // ============================================================================
  group('TestableNavigationThrottle', () {
    late TestableNavigationThrottle throttle;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      throttle = TestableNavigationThrottle(
        throttleDuration: const Duration(milliseconds: 500),
        nowProvider: () => mockNow,
      );
    });

    test('allows first navigation', () {
      expect(throttle.shouldAllowNavigation(), true);
    });

    test('blocks rapid navigation', () {
      throttle.shouldAllowNavigation(); // First - allowed

      // Try again immediately
      expect(throttle.shouldAllowNavigation(), false);
    });

    test('allows navigation after throttle period', () {
      throttle.shouldAllowNavigation();

      // Advance past throttle period
      mockNow = mockNow.add(const Duration(milliseconds: 501));

      expect(throttle.shouldAllowNavigation(), true);
    });

    test('blocks navigation just before throttle expires', () {
      throttle.shouldAllowNavigation();

      // Advance to just before throttle expires
      mockNow = mockNow.add(const Duration(milliseconds: 499));

      expect(throttle.shouldAllowNavigation(), false);
    });

    test('reset allows immediate navigation', () {
      throttle.shouldAllowNavigation();

      throttle.reset();

      expect(throttle.shouldAllowNavigation(), true);
    });

    test('getTimeUntilAllowed returns correct duration', () {
      throttle.shouldAllowNavigation();

      mockNow = mockNow.add(const Duration(milliseconds: 200));

      final remaining = throttle.getTimeUntilAllowed();
      expect(remaining?.inMilliseconds, 300);
    });

    test('getTimeUntilAllowed returns null when allowed', () {
      throttle.shouldAllowNavigation();

      mockNow = mockNow.add(const Duration(milliseconds: 600));

      expect(throttle.getTimeUntilAllowed(), null);
    });

    test('getTimeUntilAllowed returns null before first navigation', () {
      expect(throttle.getTimeUntilAllowed(), null);
    });
  });

  // ============================================================================
  // STATIC CACHE MANAGER TESTS
  // ============================================================================
  group('TestableStaticCacheManager', () {
    late TestableStaticCacheManager manager;

    setUp(() {
      manager = TestableStaticCacheManager(maxNavigationsBeforeClear: 5);
    });

    test('does not clear on first navigations', () {
      expect(manager.incrementAndCheckClear(), false);
      expect(manager.incrementAndCheckClear(), false);
      expect(manager.incrementAndCheckClear(), false);
    });

    test('clears after max navigations exceeded', () {
      for (var i = 0; i < 5; i++) {
        manager.incrementAndCheckClear();
      }

      // 6th navigation should trigger clear
      expect(manager.incrementAndCheckClear(), true);
    });

    test('resets counter after clear', () {
      // Navigate to trigger clear
      for (var i = 0; i < 6; i++) {
        manager.incrementAndCheckClear();
      }

      expect(manager.navigationCount, 0);

      // Should not clear again until max reached
      expect(manager.incrementAndCheckClear(), false);
      expect(manager.navigationCount, 1);
    });

    test('tracks navigation count correctly', () {
      manager.incrementAndCheckClear();
      expect(manager.navigationCount, 1);

      manager.incrementAndCheckClear();
      expect(manager.navigationCount, 2);
    });

    test('reset clears navigation count', () {
      manager.incrementAndCheckClear();
      manager.incrementAndCheckClear();

      manager.reset();

      expect(manager.navigationCount, 0);
    });
  });

  // ============================================================================
  // LRU CACHE TESTS
  // ============================================================================
  group('TestableLRUCache', () {
    late TestableLRUCache<String> cache;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      cache = TestableLRUCache<String>(
        maxSize: 3,
        ttl: const Duration(minutes: 10),
        nowProvider: () => mockNow,
      );
    });

    test('stores and retrieves items', () {
      cache.put('key1', 'value1');
      expect(cache.get('key1'), 'value1');
    });

    test('returns null for non-existent key', () {
      expect(cache.get('nonexistent'), null);
    });

    test('evicts oldest when over capacity', () {
      cache.put('key1', 'value1');
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('key2', 'value2');
      mockNow = mockNow.add(const Duration(seconds: 1));
      cache.put('key3', 'value3');
      mockNow = mockNow.add(const Duration(seconds: 1));

      // Add 4th item - should evict key1
      cache.put('key4', 'value4');

      expect(cache.length, 3);
      expect(cache.get('key1'), null); // Evicted
      expect(cache.get('key4'), 'value4');
    });

    test('updates existing key without eviction', () {
      cache.put('key1', 'value1');
      cache.put('key2', 'value2');
      cache.put('key3', 'value3');

      // Update existing key
      cache.put('key1', 'updated');

      expect(cache.length, 3);
      expect(cache.get('key1'), 'updated');
    });

    test('returns null for expired items', () {
      cache.put('key1', 'value1');

      // Advance past TTL
      mockNow = mockNow.add(const Duration(minutes: 11));

      expect(cache.get('key1'), null);
      expect(cache.containsKey('key1'), false);
    });

    test('cleanupExpiredAndEvict removes expired entries', () {
      cache.put('key1', 'value1');
      mockNow = mockNow.add(const Duration(minutes: 11));
      cache.put('key2', 'value2');

      cache.cleanupExpiredAndEvict();

      expect(cache.get('key1'), null);
      expect(cache.get('key2'), 'value2');
    });

    test('remove removes specific entry', () {
      cache.put('key1', 'value1');
      cache.put('key2', 'value2');

      cache.remove('key1');

      expect(cache.get('key1'), null);
      expect(cache.get('key2'), 'value2');
    });

    test('clear removes all entries', () {
      cache.put('key1', 'value1');
      cache.put('key2', 'value2');

      cache.clear();

      expect(cache.length, 0);
    });
  });

  // ============================================================================
  // IMAGE INDEX MANAGER TESTS
  // ============================================================================
  group('TestableImageIndexManager', () {
    late TestableImageIndexManager manager;

    setUp(() {
      manager = TestableImageIndexManager();
    });

    test('starts at index 0', () {
      expect(manager.currentIndex, 0);
    });

    test('setIndex changes index within bounds', () {
      manager.setMaxIndex(5);

      expect(manager.setIndex(3), true);
      expect(manager.currentIndex, 3);
    });

    test('setIndex returns false for same index', () {
      manager.setMaxIndex(5);
      manager.setIndex(2);

      expect(manager.setIndex(2), false);
    });

    test('setIndex rejects negative index', () {
      manager.setMaxIndex(5);

      expect(manager.setIndex(-1), false);
      expect(manager.currentIndex, 0);
    });

    test('setIndex rejects index beyond max', () {
      manager.setMaxIndex(5);

      expect(manager.setIndex(6), false);
      expect(manager.currentIndex, 0);
    });

    test('setMaxIndex adjusts current index if needed', () {
      manager.setMaxIndex(10);
      manager.setIndex(8);

      // Reduce max index
      manager.setMaxIndex(5);

      expect(manager.currentIndex, 5);
    });

    test('reset sets index to 0', () {
      manager.setMaxIndex(5);
      manager.setIndex(3);

      manager.reset();

      expect(manager.currentIndex, 0);
    });
  });

  // ============================================================================
  // COLLECTION DETERMINER TESTS
  // ============================================================================
  group('TestableCollectionDeterminer', () {
    group('determineCollection', () {
      test('returns shop_products for non-empty shopId', () {
        expect(
          TestableCollectionDeterminer.determineCollection('shop123'),
          'shop_products',
        );
      });

      test('returns products for null shopId', () {
        expect(
          TestableCollectionDeterminer.determineCollection(null),
          'products',
        );
      });

      test('returns products for empty shopId', () {
        expect(
          TestableCollectionDeterminer.determineCollection(''),
          'products',
        );
      });
    });

    group('isShopProduct', () {
      test('returns true for non-empty shopId', () {
        expect(TestableCollectionDeterminer.isShopProduct('shop123'), true);
      });

      test('returns false for null shopId', () {
        expect(TestableCollectionDeterminer.isShopProduct(null), false);
      });

      test('returns false for empty shopId', () {
        expect(TestableCollectionDeterminer.isShopProduct(''), false);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('chat participant IDs are sanitized for Firestore', () {
      // Email-based user IDs need sanitization
      final emailIds = [
        'user@example.com',
        'test.user@domain.co.uk',
        'name[1]@test.com',
      ];

      final sanitized = emailIds
          .map((id) => TestableFirestoreKeySanitizer.sanitize(id))
          .toList();

      expect(sanitized, [
        'user@example_com',
        'test_user@domain_co_uk',
        'name_1_@test_com',
      ]);

      // Verify no invalid characters remain
      for (final id in sanitized) {
        expect(TestableFirestoreKeySanitizer.hasInvalidCharacters(id), false);
      }
    });

    test('product share message is validated before sending', () {
      // Valid product share
      final validShare = {
        'senderId': 'user123',
        'type': 'product',
        'content': {
          'productId': 'prod_abc123',
          'productName': 'iPhone 15 Pro',
          'productImageUrls': [
            'https://cdn.example.com/img1.jpg',
            'https://cdn.example.com/img2.jpg',
          ],
          'productPrice': 1199.99,
        },
      };

      expect(TestableMessageValidator.isValid(validShare), true);

      // Invalid - missing required field
      final invalidShare = {
        'senderId': 'user123',
        'type': 'product',
        'content': {
          'productId': 'prod_abc123',
          // Missing productName
          'productImageUrls': ['url'],
          'productPrice': 1199.99,
        },
      };

      expect(TestableMessageValidator.isValid(invalidShare), false);
    });

    test('rapid product navigation is throttled', () {
      var mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      final throttle = TestableNavigationThrottle(
        throttleDuration: const Duration(milliseconds: 500),
        nowProvider: () => mockNow,
      );

      // User rapidly taps on products
      final results = <bool>[];

      results.add(throttle.shouldAllowNavigation()); // Product 1
      mockNow = mockNow.add(const Duration(milliseconds: 100));

      results.add(throttle.shouldAllowNavigation()); // Product 2 (blocked)
      mockNow = mockNow.add(const Duration(milliseconds: 100));

      results.add(throttle.shouldAllowNavigation()); // Product 3 (blocked)
      mockNow = mockNow.add(const Duration(milliseconds: 400));

      results.add(throttle.shouldAllowNavigation()); // Product 4 (allowed)

      expect(results, [true, false, false, true]);
    });

    test('cache clears after browsing many products', () {
      final manager = TestableStaticCacheManager(maxNavigationsBeforeClear: 15);

      var clearCount = 0;

      // User browses 50 products
      for (var i = 0; i < 50; i++) {
        if (manager.incrementAndCheckClear()) {
          clearCount++;
        }
      }

      // Should have cleared 3 times (at 16, 32, 48)
      expect(clearCount, 3);
    });

    test('product detail provider determines correct collection', () {
      // Shop product
      final shopProduct = {'shopId': 'shop123'};
      expect(
        TestableCollectionDeterminer.determineCollection(shopProduct['shopId']),
        'shop_products',
      );

      // Individual seller product
      final individualProduct = {'shopId': null};
      expect(
        TestableCollectionDeterminer.determineCollection(individualProduct['shopId']),
        'products',
      );

      // Product with empty shopId
      final emptyShopProduct = {'shopId': ''};
      expect(
        TestableCollectionDeterminer.determineCollection(emptyShopProduct['shopId']),
        'products',
      );
    });

    test('image gallery handles color selection', () {
      final manager = TestableImageIndexManager();

      // Product has 5 main images
      manager.setMaxIndex(4);
      manager.setIndex(3);
      expect(manager.currentIndex, 3);

      // User selects a color with only 2 images
      manager.setMaxIndex(1);
      // Current index should adjust
      expect(manager.currentIndex, 1);

      // Reset when user changes color
      manager.reset();
      expect(manager.currentIndex, 0);
    });
  });
}