// test/providers/user_provider_test.dart
//
// Unit tests for UserProvider logic
// Tests the EXACT logic that caused the splash screen bug
//
// Run: flutter test test/providers/user_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import './user_provider_utils.dart';

void main() {
  group('UserProviderUtils', () {
    // =========================================================================
    // PROFILE COMPLETION TESTS - THE CRITICAL BUG AREA!
    // =========================================================================
    group('isProfileComplete', () {
      test('returns cached value when set to true', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: true,
          profileData: null, // Even with no data
        );
        expect(result, true);
      });

      test('returns cached value when set to false', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: false,
          profileData: {'gender': 'male', 'birthDate': '1990-01-01', 'languageCode': 'en'},
        );
        // Cached value takes precedence!
        expect(result, false);
      });

      test('returns false when no cache and no profile data', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: null,
        );
        expect(result, false);
      });

      test('returns false when profile data is incomplete - missing gender', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {
            'birthDate': '1990-01-01',
            'languageCode': 'en',
          },
        );
        expect(result, false);
      });

      test('returns false when profile data is incomplete - missing birthDate', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {
            'gender': 'male',
            'languageCode': 'en',
          },
        );
        expect(result, false);
      });

      test('returns false when profile data is incomplete - missing languageCode', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {
            'gender': 'male',
            'birthDate': '1990-01-01',
          },
        );
        expect(result, false);
      });

      test('returns true when all required fields present', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {
            'gender': 'male',
            'birthDate': '1990-01-01',
            'languageCode': 'en',
          },
        );
        expect(result, true);
      });

      test('handles null values in profile data fields', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {
            'gender': null,
            'birthDate': '1990-01-01',
            'languageCode': 'en',
          },
        );
        expect(result, false);
      });

      test('handles empty profile data map', () {
        final result = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: {},
        );
        expect(result, false);
      });
    });

    // =========================================================================
    // PROFILE STATE READY - PREVENTS PREMATURE NAVIGATION
    // =========================================================================
    group('isProfileStateReady', () {
      test('returns false when both cache and data are null', () {
        final result = UserProviderUtils.isProfileStateReady(
          cachedProfileComplete: null,
          profileData: null,
        );
        expect(result, false);
      });

      test('returns true when cache is set (even if false)', () {
        final result = UserProviderUtils.isProfileStateReady(
          cachedProfileComplete: false,
          profileData: null,
        );
        expect(result, true);
      });

      test('returns true when profile data exists', () {
        final result = UserProviderUtils.isProfileStateReady(
          cachedProfileComplete: null,
          profileData: {'gender': 'male'},
        );
        expect(result, true);
      });

      test('returns true when both exist', () {
        final result = UserProviderUtils.isProfileStateReady(
          cachedProfileComplete: true,
          profileData: {'gender': 'male'},
        );
        expect(result, true);
      });
    });

    // =========================================================================
    // EXTRACT PROFILE COMPLETE FROM DATA
    // =========================================================================
    group('extractProfileCompleteFromData', () {
      test('returns false for null data', () {
        expect(UserProviderUtils.extractProfileCompleteFromData(null), false);
      });

      test('returns false for empty data', () {
        expect(UserProviderUtils.extractProfileCompleteFromData({}), false);
      });

      test('returns true for complete data', () {
        final data = {
          'gender': 'female',
          'birthDate': '1995-05-15',
          'languageCode': 'tr',
        };
        expect(UserProviderUtils.extractProfileCompleteFromData(data), true);
      });

      test('returns false when any field is null', () {
        final data = {
          'gender': 'female',
          'birthDate': null,
          'languageCode': 'tr',
        };
        expect(UserProviderUtils.extractProfileCompleteFromData(data), false);
      });
    });

    // =========================================================================
    // EXTRACT IS ADMIN
    // =========================================================================
    group('extractIsAdminFromData', () {
      test('returns false for null data', () {
        expect(UserProviderUtils.extractIsAdminFromData(null), false);
      });

      test('returns false when isAdmin not present', () {
        expect(UserProviderUtils.extractIsAdminFromData({}), false);
      });

      test('returns false when isAdmin is false', () {
        expect(UserProviderUtils.extractIsAdminFromData({'isAdmin': false}), false);
      });

      test('returns true when isAdmin is true', () {
        expect(UserProviderUtils.extractIsAdminFromData({'isAdmin': true}), true);
      });

      test('returns false when isAdmin is string "true"', () {
        // Strict type checking - must be boolean true
        expect(UserProviderUtils.extractIsAdminFromData({'isAdmin': 'true'}), false);
      });

      test('returns false when isAdmin is 1', () {
        expect(UserProviderUtils.extractIsAdminFromData({'isAdmin': 1}), false);
      });
    });

    // =========================================================================
    // CACHE UPDATE LOGIC
    // =========================================================================
    group('shouldUpdateCache', () {
      test('returns true when values differ', () {
        expect(UserProviderUtils.shouldUpdateCache(false, true), true);
        expect(UserProviderUtils.shouldUpdateCache(true, false), true);
      });

      test('returns false when values are same', () {
        expect(UserProviderUtils.shouldUpdateCache(true, true), false);
        expect(UserProviderUtils.shouldUpdateCache(false, false), false);
      });

      test('returns true when current is null', () {
        expect(UserProviderUtils.shouldUpdateCache(null, true), true);
        expect(UserProviderUtils.shouldUpdateCache(null, false), true);
      });
    });

    // =========================================================================
    // GOOGLE USER CHECK
    // =========================================================================
    group('isGoogleUser', () {
      test('returns true when google.com in providers', () {
        expect(UserProviderUtils.isGoogleUser(['google.com']), true);
      });

      test('returns true with multiple providers including google', () {
        expect(UserProviderUtils.isGoogleUser(['password', 'google.com']), true);
      });

      test('returns false when no google provider', () {
        expect(UserProviderUtils.isGoogleUser(['password']), false);
      });

      test('returns false for empty providers', () {
        expect(UserProviderUtils.isGoogleUser([]), false);
      });
    });

    // =========================================================================
    // DEFAULT USER DOC
    // =========================================================================
    group('buildDefaultUserDoc', () {
      test('builds with all provided values', () {
        final doc = UserProviderUtils.buildDefaultUserDoc(
          displayName: 'John Doe',
          email: 'john@example.com',
          languageCode: 'en',
        );

        expect(doc['displayName'], 'John Doe');
        expect(doc['email'], 'john@example.com');
        expect(doc['isAdmin'], false);
        expect(doc['isNew'], true);
        expect(doc['languageCode'], 'en');
      });

      test('falls back to email prefix when no displayName', () {
        final doc = UserProviderUtils.buildDefaultUserDoc(
          displayName: null,
          email: 'john@example.com',
          languageCode: 'tr',
        );

        expect(doc['displayName'], 'john');
      });

      test('falls back to User when no displayName or email', () {
        final doc = UserProviderUtils.buildDefaultUserDoc(
          displayName: null,
          email: null,
          languageCode: 'tr',
        );

        expect(doc['displayName'], 'User');
      });

      test('defaults languageCode to tr', () {
        final doc = UserProviderUtils.buildDefaultUserDoc();
        expect(doc['languageCode'], 'tr');
      });
    });

    // =========================================================================
    // EXTRACT DISPLAY NAME
    // =========================================================================
    group('extractDisplayName', () {
      test('returns displayName when provided', () {
        expect(
          UserProviderUtils.extractDisplayName(
            displayName: 'John',
            email: 'john@example.com',
          ),
          'John',
        );
      });

      test('returns email prefix when no displayName', () {
        expect(
          UserProviderUtils.extractDisplayName(
            displayName: null,
            email: 'john@example.com',
          ),
          'john',
        );
      });

      test('returns User when both null', () {
        expect(
          UserProviderUtils.extractDisplayName(
            displayName: null,
            email: null,
          ),
          'User',
        );
      });

      test('returns User for empty displayName', () {
        expect(
          UserProviderUtils.extractDisplayName(
            displayName: '',
            email: null,
          ),
          'User',
        );
      });
    });

    // =========================================================================
    // MERGE PROFILE UPDATES
    // =========================================================================
    group('mergeProfileUpdates', () {
      test('preserves languageCode when not in updates', () {
        final result = UserProviderUtils.mergeProfileUpdates(
          currentData: {'languageCode': 'tr', 'gender': 'male'},
          updates: {'gender': 'female'},
        );

        expect(result['languageCode'], 'tr');
        expect(result['gender'], 'female');
      });

      test('allows languageCode update when explicitly provided', () {
        final result = UserProviderUtils.mergeProfileUpdates(
          currentData: {'languageCode': 'tr'},
          updates: {'languageCode': 'en'},
        );

        expect(result['languageCode'], 'en');
      });

      test('handles empty current data', () {
        final result = UserProviderUtils.mergeProfileUpdates(
          currentData: {},
          updates: {'gender': 'male'},
        );

        expect(result['gender'], 'male');
        expect(result.containsKey('languageCode'), false);
      });
    });

    // =========================================================================
    // RETRY LOGIC
    // =========================================================================
    group('calculateRetryDelay', () {
      test('calculates exponential backoff correctly', () {
        expect(UserProviderUtils.calculateRetryDelay(1), const Duration(milliseconds: 500));
        expect(UserProviderUtils.calculateRetryDelay(2), const Duration(milliseconds: 1000));
        expect(UserProviderUtils.calculateRetryDelay(3), const Duration(milliseconds: 2000));
      });
    });

    group('shouldRetry', () {
      test('returns true when under max retries', () {
        expect(UserProviderUtils.shouldRetry(1, 3), true);
        expect(UserProviderUtils.shouldRetry(2, 3), true);
      });

      test('returns false when at max retries', () {
        expect(UserProviderUtils.shouldRetry(3, 3), false);
      });

      test('returns false when over max retries', () {
        expect(UserProviderUtils.shouldRetry(4, 3), false);
      });
    });

    // =========================================================================
    // STATE RESET
    // =========================================================================
    group('getResetState', () {
      test('returns correct reset values', () {
        final state = UserProviderUtils.getResetState();

        expect(state['isAdmin'], false);
        expect(state['profileData'], null);
        expect(state['profileComplete'], null);
        expect(state['isLoading'], false);
      });
    });

    // =========================================================================
    // LIFECYCLE / RESUME
    // =========================================================================
    group('shouldFullRefresh', () {
      test('returns true for long pause', () {
        expect(
          UserProviderUtils.shouldFullRefresh(const Duration(minutes: 10)),
          true,
        );
      });

      test('returns false for short pause', () {
        expect(
          UserProviderUtils.shouldFullRefresh(const Duration(minutes: 2)),
          false,
        );
      });

      test('returns false at exactly threshold', () {
        expect(
          UserProviderUtils.shouldFullRefresh(const Duration(minutes: 5)),
          false,
        );
      });

      test('respects custom threshold', () {
        expect(
          UserProviderUtils.shouldFullRefresh(
            const Duration(minutes: 2),
            threshold: const Duration(minutes: 1),
          ),
          true,
        );
      });
    });

    // =========================================================================
    // AUTH STATE LOGIC
    // =========================================================================
    group('isLoginEvent', () {
      test('returns true when user logs in', () {
        expect(
          UserProviderUtils.isLoginEvent(hadUserBefore: false, hasUserNow: true),
          true,
        );
      });

      test('returns false when already logged in', () {
        expect(
          UserProviderUtils.isLoginEvent(hadUserBefore: true, hasUserNow: true),
          false,
        );
      });

      test('returns false on logout', () {
        expect(
          UserProviderUtils.isLoginEvent(hadUserBefore: true, hasUserNow: false),
          false,
        );
      });
    });

    group('isLogoutEvent', () {
      test('returns true when user logs out', () {
        expect(
          UserProviderUtils.isLogoutEvent(hadUserBefore: true, hasUserNow: false),
          true,
        );
      });

      test('returns false when user logs in', () {
        expect(
          UserProviderUtils.isLogoutEvent(hadUserBefore: false, hasUserNow: true),
          false,
        );
      });
    });

    group('didUserChange', () {
      test('returns true when uid changes', () {
        expect(
          UserProviderUtils.didUserChange(previousUid: 'uid1', currentUid: 'uid2'),
          true,
        );
      });

      test('returns false when uid same', () {
        expect(
          UserProviderUtils.didUserChange(previousUid: 'uid1', currentUid: 'uid1'),
          false,
        );
      });

      test('returns true when user logs in', () {
        expect(
          UserProviderUtils.didUserChange(previousUid: null, currentUid: 'uid1'),
          true,
        );
      });

      test('returns true when user logs out', () {
        expect(
          UserProviderUtils.didUserChange(previousUid: 'uid1', currentUid: null),
          true,
        );
      });

      test('returns false when both null', () {
        expect(
          UserProviderUtils.didUserChange(previousUid: null, currentUid: null),
          false,
        );
      });
    });

    // =========================================================================
    // CACHE VALIDATION - THE BUG YOU EXPERIENCED!
    // =========================================================================
    group('validateCacheAgainstData', () {
      test('returns true when cache matches data (both complete)', () {
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: true,
            profileData: {
              'gender': 'male',
              'birthDate': '1990-01-01',
              'languageCode': 'en',
            },
          ),
          true,
        );
      });

      test('returns true when cache matches data (both incomplete)', () {
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: false,
            profileData: {'gender': 'male'},
          ),
          true,
        );
      });

      test('returns false when cache says complete but data is incomplete', () {
        // THIS IS THE BUG YOU EXPERIENCED!
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: true,
            profileData: {'gender': 'male'}, // Missing birthDate and languageCode
          ),
          false,
        );
      });

      test('returns false when cache says incomplete but data is complete', () {
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: false,
            profileData: {
              'gender': 'male',
              'birthDate': '1990-01-01',
              'languageCode': 'en',
            },
          ),
          false,
        );
      });

      test('returns true when no cache (null)', () {
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: null,
            profileData: {'gender': 'male'},
          ),
          true,
        );
      });

      test('returns false when cache exists but no data to validate', () {
        expect(
          UserProviderUtils.validateCacheAgainstData(
            cachedValue: true,
            profileData: null,
          ),
          false,
        );
      });
    });

    group('shouldClearCache', () {
      test('returns true when no user', () {
        expect(
          UserProviderUtils.shouldClearCache(
            cachedValue: true,
            profileData: {'gender': 'male'},
            hasUser: false,
          ),
          true,
        );
      });

      test('returns true when cache is corrupted', () {
        // Cache says complete, but data is incomplete
        expect(
          UserProviderUtils.shouldClearCache(
            cachedValue: true,
            profileData: {'gender': 'male'},
            hasUser: true,
          ),
          true,
        );
      });

      test('returns false when cache is valid', () {
        expect(
          UserProviderUtils.shouldClearCache(
            cachedValue: true,
            profileData: {
              'gender': 'male',
              'birthDate': '1990-01-01',
              'languageCode': 'en',
            },
            hasUser: true,
          ),
          false,
        );
      });

      test('returns false when no cache exists', () {
        expect(
          UserProviderUtils.shouldClearCache(
            cachedValue: null,
            profileData: {'gender': 'male'},
            hasUser: true,
          ),
          false,
        );
      });
    });

    // =========================================================================
    // REAL-WORLD SCENARIOS - YOUR BUG REPRODUCED
    // =========================================================================
    group('Real-World Scenarios', () {
      test('SCENARIO: Corrupted cache causes stuck splash screen', () {
        // This is YOUR bug!
        // Cache says profile is complete, but actual data disagrees
        
        final cachedValue = true; // SharedPreferences says complete
        final profileData = <String, dynamic>{}; // But Firestore has no data!

        // Old logic would return true (from cache), causing infinite splash
        final isComplete = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: cachedValue,
          profileData: profileData,
        );

        // Cache takes precedence - this is the BUG behavior
        expect(isComplete, true); // Returns true even though data is empty!

        // Solution: Validate cache against actual data
        final isValid = UserProviderUtils.validateCacheAgainstData(
          cachedValue: cachedValue,
          profileData: profileData,
        );
        expect(isValid, false); // Detects corruption!

        final shouldClear = UserProviderUtils.shouldClearCache(
          cachedValue: cachedValue,
          profileData: profileData,
          hasUser: true,
        );
        expect(shouldClear, true); // Should clear the corrupted cache!
      });

      test('SCENARIO: Fresh login with complete profile', () {
        // User logs in, has complete profile in Firestore
        final profileData = {
          'gender': 'female',
          'birthDate': '1995-05-15',
          'languageCode': 'tr',
          'displayName': 'Ayşe',
        };

        // No cache yet (fresh login)
        final isComplete = UserProviderUtils.isProfileComplete(
          cachedProfileComplete: null,
          profileData: profileData,
        );

        expect(isComplete, true);

        // Should update cache
        final shouldUpdate = UserProviderUtils.shouldUpdateCache(null, true);
        expect(shouldUpdate, true);
      });

      test('SCENARIO: App resume with valid cache', () {
        // App was paused, resuming with valid cache
        final cachedValue = true;
        final profileData = {
          'gender': 'male',
          'birthDate': '1990-01-01',
          'languageCode': 'en',
        };

        // Cache is valid
        final isValid = UserProviderUtils.validateCacheAgainstData(
          cachedValue: cachedValue,
          profileData: profileData,
        );
        expect(isValid, true);

        // Should NOT clear cache
        final shouldClear = UserProviderUtils.shouldClearCache(
          cachedValue: cachedValue,
          profileData: profileData,
          hasUser: true,
        );
        expect(shouldClear, false);
      });

      test('SCENARIO: User logs out', () {
        // User had complete profile, now logging out
        final resetState = UserProviderUtils.getResetState();

        expect(resetState['profileComplete'], null);
        expect(resetState['profileData'], null);
        expect(resetState['isAdmin'], false);
      });

      test('SCENARIO: New user registration (incomplete profile)', () {
        // New user just signed up, no profile yet
        final defaultDoc = UserProviderUtils.buildDefaultUserDoc(
          displayName: null,
          email: 'newuser@example.com',
          languageCode: 'tr',
        );

        expect(defaultDoc['displayName'], 'newuser');
        expect(defaultDoc['isNew'], true);

        // Profile is NOT complete
        final isComplete = UserProviderUtils.extractProfileCompleteFromData(defaultDoc);
        expect(isComplete, false); // Missing gender and birthDate
      });
    });
  });
}