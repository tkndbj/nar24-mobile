// test/providers/shop_widget_provider_test.dart
//
// Unit tests for ShopWidgetProvider pure logic
// Tests the EXACT logic from lib/providers/shop_widget_provider.dart
//
// Run: flutter test test/providers/shop_widget_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_shop_widget_provider.dart';

void main() {
  // ============================================================================
  // CONFIG TESTS
  // ============================================================================
  group('TestableShopWidgetConfig', () {
    test('max shop buffer size is 500', () {
      expect(TestableShopWidgetConfig.maxShopBufferSize, 500);
    });

    test('default featured shop limit is 10', () {
      expect(TestableShopWidgetConfig.defaultFeaturedShopLimit, 10);
    });
  });

  // ============================================================================
  // MEMBERSHIP VERIFIER TESTS
  // ============================================================================
  group('TestableShopMembershipVerifier', () {
    group('verifyUserStillMemberOfShop', () {
      group('owner role', () {
        test('returns true when user is owner', () {
          final shopData = {'ownerId': 'user_123'};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'owner',
              shopData: shopData,
            ),
            true,
          );
        });

        test('returns false when user is not owner', () {
          final shopData = {'ownerId': 'other_user'};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'owner',
              shopData: shopData,
            ),
            false,
          );
        });

        test('returns false when ownerId is missing', () {
          final shopData = <String, dynamic>{};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'owner',
              shopData: shopData,
            ),
            false,
          );
        });
      });

      group('co-owner role', () {
        test('returns true when user is in coOwners list', () {
          final shopData = {
            'coOwners': ['user_123', 'user_456'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'co-owner',
              shopData: shopData,
            ),
            true,
          );
        });

        test('returns false when user not in coOwners list', () {
          final shopData = {
            'coOwners': ['user_456', 'user_789'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'co-owner',
              shopData: shopData,
            ),
            false,
          );
        });

        test('returns false when coOwners is null', () {
          final shopData = {'coOwners': null};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'co-owner',
              shopData: shopData,
            ),
            false,
          );
        });

        test('returns false when coOwners is empty', () {
          final shopData = {'coOwners': <String>[]};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'co-owner',
              shopData: shopData,
            ),
            false,
          );
        });
      });

      group('editor role', () {
        test('returns true when user is in editors list', () {
          final shopData = {
            'editors': ['user_123'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'editor',
              shopData: shopData,
            ),
            true,
          );
        });

        test('returns false when user not in editors list', () {
          final shopData = {
            'editors': ['other_user'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'editor',
              shopData: shopData,
            ),
            false,
          );
        });
      });

      group('viewer role', () {
        test('returns true when user is in viewers list', () {
          final shopData = {
            'viewers': ['user_123', 'user_456'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'viewer',
              shopData: shopData,
            ),
            true,
          );
        });

        test('returns false when user not in viewers list', () {
          final shopData = {
            'viewers': ['other_user'],
          };

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'viewer',
              shopData: shopData,
            ),
            false,
          );
        });
      });

      group('unknown role', () {
        test('returns false for unknown role', () {
          final shopData = {'ownerId': 'user_123'};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: 'admin', // Invalid role
              shopData: shopData,
            ),
            false,
          );
        });

        test('returns false for empty role', () {
          final shopData = {'ownerId': 'user_123'};

          expect(
            TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
              uid: 'user_123',
              role: '',
              shopData: shopData,
            ),
            false,
          );
        });
      });
    });

    group('parseRole', () {
      test('parses owner', () {
        expect(TestableShopMembershipVerifier.parseRole('owner'), ShopRole.owner);
      });

      test('parses co-owner', () {
        expect(TestableShopMembershipVerifier.parseRole('co-owner'), ShopRole.coOwner);
      });

      test('parses editor', () {
        expect(TestableShopMembershipVerifier.parseRole('editor'), ShopRole.editor);
      });

      test('parses viewer', () {
        expect(TestableShopMembershipVerifier.parseRole('viewer'), ShopRole.viewer);
      });

      test('returns null for invalid role', () {
        expect(TestableShopMembershipVerifier.parseRole('admin'), null);
        expect(TestableShopMembershipVerifier.parseRole(''), null);
      });
    });

    group('isValidRole', () {
      test('returns true for valid roles', () {
        expect(TestableShopMembershipVerifier.isValidRole('owner'), true);
        expect(TestableShopMembershipVerifier.isValidRole('co-owner'), true);
        expect(TestableShopMembershipVerifier.isValidRole('editor'), true);
        expect(TestableShopMembershipVerifier.isValidRole('viewer'), true);
      });

      test('returns false for invalid roles', () {
        expect(TestableShopMembershipVerifier.isValidRole('admin'), false);
        expect(TestableShopMembershipVerifier.isValidRole(''), false);
        expect(TestableShopMembershipVerifier.isValidRole('Owner'), false); // Case sensitive
      });
    });

    group('getUserRoles', () {
      test('returns all roles user has', () {
        final shopData = {
          'ownerId': 'user_123',
          'coOwners': ['user_123'], // Same user has multiple roles
          'editors': ['other_user'],
          'viewers': ['user_123'],
        };

        final roles = TestableShopMembershipVerifier.getUserRoles(
          uid: 'user_123',
          shopData: shopData,
        );

        expect(roles, contains('owner'));
        expect(roles, contains('co-owner'));
        expect(roles, contains('viewer'));
        expect(roles, isNot(contains('editor')));
      });

      test('returns empty for user with no roles', () {
        final shopData = {
          'ownerId': 'other_user',
          'coOwners': ['other_user'],
        };

        final roles = TestableShopMembershipVerifier.getUserRoles(
          uid: 'user_123',
          shopData: shopData,
        );

        expect(roles, isEmpty);
      });
    });

    group('hasAnyRole', () {
      test('returns true if user has any role', () {
        final shopData = {
          'viewers': ['user_123'],
        };

        expect(
          TestableShopMembershipVerifier.hasAnyRole(
            uid: 'user_123',
            shopData: shopData,
          ),
          true,
        );
      });

      test('returns false if user has no roles', () {
        final shopData = {
          'ownerId': 'other_user',
        };

        expect(
          TestableShopMembershipVerifier.hasAnyRole(
            uid: 'user_123',
            shopData: shopData,
          ),
          false,
        );
      });
    });
  });

  // ============================================================================
  // FAVORITE MANAGER TESTS
  // ============================================================================
  group('TestableFavoriteManager', () {
    late TestableFavoriteManager manager;

    setUp(() {
      manager = TestableFavoriteManager();
    });

    test('starts empty', () {
      expect(manager.count, 0);
      expect(manager.favoriteShopIds, isEmpty);
    });

    test('initializes with existing favorites', () {
      manager = TestableFavoriteManager({'shop_1', 'shop_2'});
      expect(manager.count, 2);
      expect(manager.isFavorite('shop_1'), true);
    });

    group('isFavorite', () {
      test('returns true for favorited shop', () {
        manager.addFavorite('shop_123');
        expect(manager.isFavorite('shop_123'), true);
      });

      test('returns false for non-favorited shop', () {
        expect(manager.isFavorite('shop_123'), false);
      });
    });

    group('shouldAddOnToggle', () {
      test('returns true if not currently favorite', () {
        expect(manager.shouldAddOnToggle('shop_123'), true);
      });

      test('returns false if currently favorite', () {
        manager.addFavorite('shop_123');
        expect(manager.shouldAddOnToggle('shop_123'), false);
      });
    });

    group('toggle', () {
      test('adds if not favorite', () {
        manager.toggle('shop_123');
        expect(manager.isFavorite('shop_123'), true);
      });

      test('removes if already favorite', () {
        manager.addFavorite('shop_123');
        manager.toggle('shop_123');
        expect(manager.isFavorite('shop_123'), false);
      });
    });
  });

  // ============================================================================
  // MEMBERSHIP PROCESSOR TESTS
  // ============================================================================
  group('TestableMembershipProcessor', () {
    group('extractShopIds', () {
      test('extracts shop IDs from map', () {
        final memberOfShops = {
          'shop_1': 'owner',
          'shop_2': 'editor',
          'shop_3': 'viewer',
        };

        final ids = TestableMembershipProcessor.extractShopIds(memberOfShops);

        expect(ids, containsAll(['shop_1', 'shop_2', 'shop_3']));
      });

      test('returns empty for null', () {
        expect(TestableMembershipProcessor.extractShopIds(null), isEmpty);
      });

      test('returns empty for empty map', () {
        expect(TestableMembershipProcessor.extractShopIds({}), isEmpty);
      });
    });

    group('getRoleForShop', () {
      test('returns role for shop', () {
        final memberOfShops = {'shop_1': 'owner', 'shop_2': 'editor'};

        expect(
          TestableMembershipProcessor.getRoleForShop(memberOfShops, 'shop_1'),
          'owner',
        );
      });

      test('returns null for non-member shop', () {
        final memberOfShops = {'shop_1': 'owner'};

        expect(
          TestableMembershipProcessor.getRoleForShop(memberOfShops, 'shop_999'),
          null,
        );
      });
    });

    group('hasAnyMembership', () {
      test('returns true when has memberships', () {
        expect(
          TestableMembershipProcessor.hasAnyMembership({'shop_1': 'owner'}),
          true,
        );
      });

      test('returns false for null', () {
        expect(TestableMembershipProcessor.hasAnyMembership(null), false);
      });

      test('returns false for empty', () {
        expect(TestableMembershipProcessor.hasAnyMembership({}), false);
      });
    });
  });

  // ============================================================================
  // FOLLOWER COUNT CALCULATOR TESTS
  // ============================================================================
  group('TestableFollowerCountCalculator', () {
    test('returns -1 for unfollow (currently favorite)', () {
      expect(
        TestableFollowerCountCalculator.getFollowerCountDelta(
          isCurrentlyFavorite: true,
        ),
        -1,
      );
    });

    test('returns +1 for follow (not currently favorite)', () {
      expect(
        TestableFollowerCountCalculator.getFollowerCountDelta(
          isCurrentlyFavorite: false,
        ),
        1,
      );
    });
  });

  // ============================================================================
  // SHOP LIST MANAGER TESTS
  // ============================================================================
  group('TestableShopListManager', () {
    late TestableShopListManager<String> manager;

    setUp(() {
      manager = TestableShopListManager<String>(maxSize: 5);
    });

    test('starts empty', () {
      expect(manager.isEmpty, true);
      expect(manager.length, 0);
    });

    test('setShops replaces existing', () {
      manager.setShops(['shop_1', 'shop_2']);
      expect(manager.length, 2);

      manager.setShops(['shop_3']);
      expect(manager.length, 1);
      expect(manager.shops, ['shop_3']);
    });

    test('enforces max size', () {
      manager.setShops(['1', '2', '3', '4', '5', '6', '7']);

      expect(manager.length, 5); // Max size
      expect(manager.isAtCapacity, true);
    });

    test('clear removes all', () {
      manager.setShops(['shop_1', 'shop_2']);
      manager.clear();

      expect(manager.isEmpty, true);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('user removed from co-owners loses access', () {
      // Before removal
      final shopDataBefore = {
        'ownerId': 'owner_user',
        'coOwners': ['user_123', 'user_456'],
      };

      expect(
        TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
          uid: 'user_123',
          role: 'co-owner',
          shopData: shopDataBefore,
        ),
        true,
      );

      // After removal
      final shopDataAfter = {
        'ownerId': 'owner_user',
        'coOwners': ['user_456'], // user_123 removed
      };

      expect(
        TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
          uid: 'user_123',
          role: 'co-owner',
          shopData: shopDataAfter,
        ),
        false,
      );
    });

    test('shop owner transfers ownership', () {
      // User was owner
      final shopDataBefore = {'ownerId': 'user_123'};

      expect(
        TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
          uid: 'user_123',
          role: 'owner',
          shopData: shopDataBefore,
        ),
        true,
      );

      // Ownership transferred to someone else
      final shopDataAfter = {'ownerId': 'new_owner'};

      expect(
        TestableShopMembershipVerifier.verifyUserStillMemberOfShop(
          uid: 'user_123',
          role: 'owner',
          shopData: shopDataAfter,
        ),
        false,
      );
    });

    test('follow/unfollow shop', () {
      final manager = TestableFavoriteManager();

      // User follows shop
      expect(manager.shouldAddOnToggle('shop_123'), true);
      manager.toggle('shop_123');
      expect(manager.isFavorite('shop_123'), true);

      // User unfollows shop
      expect(manager.shouldAddOnToggle('shop_123'), false);
      manager.toggle('shop_123');
      expect(manager.isFavorite('shop_123'), false);
    });

    test('cleanup identifies invalid memberships', () {
      final memberOfShops = {
        'valid_shop': 'owner',
        'deleted_shop_1': 'editor',
        'deleted_shop_2': 'viewer',
      };

      final shopsToCleanup = ['deleted_shop_1', 'deleted_shop_2'];
      final cleanupKeys = TestableMembershipProcessor.buildCleanupKeys(shopsToCleanup);

      expect(cleanupKeys.length, 2);
      expect(cleanupKeys['memberOfShops.deleted_shop_1'], 'DELETE');
      expect(cleanupKeys['memberOfShops.deleted_shop_2'], 'DELETE');
    });
  });
}