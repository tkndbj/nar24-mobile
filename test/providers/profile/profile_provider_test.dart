// test/providers/profile_provider_test.dart
//
// Unit tests for ProfileProvider pure logic
// Tests the EXACT logic from lib/profile_provider.dart
//
// Run: flutter test test/providers/profile_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_profile_provider.dart';

void main() {
  // ============================================================================
  // EXPONENTIAL BACKOFF TESTS
  // ============================================================================
  group('TestableProfileBackoff', () {
    group('calculateDelay', () {
      test('returns 500ms for retry 1', () {
        expect(
          TestableProfileBackoff.calculateDelay(1),
          const Duration(milliseconds: 500),
        );
      });

      test('returns 1000ms for retry 2', () {
        expect(
          TestableProfileBackoff.calculateDelay(2),
          const Duration(milliseconds: 1000),
        );
      });

      test('returns 2000ms for retry 3', () {
        expect(
          TestableProfileBackoff.calculateDelay(3),
          const Duration(milliseconds: 2000),
        );
      });

      test('returns 250ms for retry 0 (edge case)', () {
        expect(
          TestableProfileBackoff.calculateDelay(0),
          const Duration(milliseconds: 250),
        );
      });

      test('doubles delay with each retry (exponential)', () {
        final delay1 = TestableProfileBackoff.calculateDelay(1);
        final delay2 = TestableProfileBackoff.calculateDelay(2);
        final delay3 = TestableProfileBackoff.calculateDelay(3);

        expect(delay2.inMilliseconds, delay1.inMilliseconds * 2);
        expect(delay3.inMilliseconds, delay2.inMilliseconds * 2);
      });
    });

    group('shouldRetry', () {
      test('returns true for attempts 0, 1, 2', () {
        expect(TestableProfileBackoff.shouldRetry(0), true);
        expect(TestableProfileBackoff.shouldRetry(1), true);
        expect(TestableProfileBackoff.shouldRetry(2), true);
      });

      test('returns false for attempt 3 (maxRetries)', () {
        expect(TestableProfileBackoff.shouldRetry(3), false);
      });

      test('returns false for attempts beyond maxRetries', () {
        expect(TestableProfileBackoff.shouldRetry(4), false);
        expect(TestableProfileBackoff.shouldRetry(10), false);
      });
    });

    group('getRetrySequence', () {
      test('returns correct sequence of delays', () {
        final sequence = TestableProfileBackoff.getRetrySequence();

        expect(sequence.length, 3);
        expect(sequence[0], const Duration(milliseconds: 500));
        expect(sequence[1], const Duration(milliseconds: 1000));
        expect(sequence[2], const Duration(milliseconds: 2000));
      });
    });

    group('totalRetryTime', () {
      test('returns sum of all retry delays', () {
        final total = TestableProfileBackoff.totalRetryTime();

        // 500 + 1000 + 2000 = 3500ms
        expect(total, const Duration(milliseconds: 3500));
      });
    });
  });

  // ============================================================================
  // DEFAULT USER DATA TESTS
  // ============================================================================
  group('TestableDefaultUserData', () {
    group('create', () {
      test('creates with provided values', () {
        final data = TestableDefaultUserData.create(
          displayName: 'John Doe',
          email: 'john@example.com',
        );

        expect(data['displayName'], 'John Doe');
        expect(data['email'], 'john@example.com');
        expect(data['profileImage'], null);
        expect(data['isVerified'], false);
        expect(data['isNew'], false);
      });

      test('uses defaults for null displayName', () {
        final data = TestableDefaultUserData.create(
          displayName: null,
          email: 'test@example.com',
        );

        expect(data['displayName'], 'No Name');
      });

      test('uses defaults for null email', () {
        final data = TestableDefaultUserData.create(
          displayName: 'Test User',
          email: null,
        );

        expect(data['email'], 'No Email');
      });

      test('uses defaults for all null values', () {
        final data = TestableDefaultUserData.create();

        expect(data['displayName'], 'No Name');
        expect(data['email'], 'No Email');
        expect(data['profileImage'], null);
        expect(data['isVerified'], false);
        expect(data['isNew'], false);
      });

      test('always sets profileImage to null initially', () {
        final data = TestableDefaultUserData.create(
          displayName: 'User',
          email: 'user@test.com',
        );

        expect(data['profileImage'], isNull);
      });

      test('always sets isVerified to false initially', () {
        final data = TestableDefaultUserData.create();
        expect(data['isVerified'], false);
      });

      test('always sets isNew to false initially', () {
        final data = TestableDefaultUserData.create();
        expect(data['isNew'], false);
      });
    });

    group('hasRequiredFields', () {
      test('returns true for complete data', () {
        final data = {
          'displayName': 'Test',
          'email': 'test@test.com',
          'profileImage': null,
          'isVerified': false,
          'isNew': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), true);
      });

      test('returns false for missing displayName', () {
        final data = {
          'email': 'test@test.com',
          'profileImage': null,
          'isVerified': false,
          'isNew': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), false);
      });

      test('returns false for missing email', () {
        final data = {
          'displayName': 'Test',
          'profileImage': null,
          'isVerified': false,
          'isNew': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), false);
      });

      test('returns false for missing profileImage', () {
        final data = {
          'displayName': 'Test',
          'email': 'test@test.com',
          'isVerified': false,
          'isNew': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), false);
      });

      test('returns false for missing isVerified', () {
        final data = {
          'displayName': 'Test',
          'email': 'test@test.com',
          'profileImage': null,
          'isNew': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), false);
      });

      test('returns false for missing isNew', () {
        final data = {
          'displayName': 'Test',
          'email': 'test@test.com',
          'profileImage': null,
          'isVerified': false,
        };

        expect(TestableDefaultUserData.hasRequiredFields(data), false);
      });

      test('returns false for empty map', () {
        expect(TestableDefaultUserData.hasRequiredFields({}), false);
      });
    });

    group('requiredFields', () {
      test('returns all required field names', () {
        expect(
          TestableDefaultUserData.requiredFields,
          ['displayName', 'email', 'profileImage', 'isVerified', 'isNew'],
        );
      });
    });
  });

  // ============================================================================
  // PROFILE IMAGE PATH TESTS
  // ============================================================================
  group('TestableProfileImagePath', () {
    group('generate', () {
      test('generates correct path for UID', () {
        expect(
          TestableProfileImagePath.generate('abc123'),
          'profileImages/abc123',
        );
      });

      test('handles complex UIDs', () {
        expect(
          TestableProfileImagePath.generate('user_123-ABC'),
          'profileImages/user_123-ABC',
        );
      });

      test('throws for empty UID', () {
        expect(
          () => TestableProfileImagePath.generate(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for whitespace-only UID', () {
        expect(
          () => TestableProfileImagePath.generate('   '),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('extractUid', () {
      test('extracts UID from valid path', () {
        expect(
          TestableProfileImagePath.extractUid('profileImages/abc123'),
          'abc123',
        );
      });

      test('returns null for invalid path prefix', () {
        expect(
          TestableProfileImagePath.extractUid('otherFolder/abc123'),
          null,
        );
      });

      test('returns null for path with no UID', () {
        expect(
          TestableProfileImagePath.extractUid('profileImages/'),
          null,
        );
      });

      test('handles complex UIDs', () {
        expect(
          TestableProfileImagePath.extractUid('profileImages/user_123-ABC'),
          'user_123-ABC',
        );
      });
    });
  });

  // ============================================================================
  // RETRY MANAGER TESTS
  // ============================================================================
  group('TestableRetryManager', () {
    late TestableRetryManager manager;

    setUp(() {
      manager = TestableRetryManager(maxRetries: 3);
    });

    group('initial state', () {
      test('starts at attempt 0', () {
        expect(manager.currentAttempt, 0);
      });

      test('starts not succeeded', () {
        expect(manager.succeeded, false);
      });

      test('starts not exhausted', () {
        expect(manager.exhausted, false);
      });
    });

    group('attempt', () {
      test('increments attempt count', () {
        manager.attempt();
        expect(manager.currentAttempt, 1);

        manager.attempt();
        expect(manager.currentAttempt, 2);
      });

      test('returns true while retries available', () {
        expect(manager.attempt(), true);
        expect(manager.attempt(), true);
        expect(manager.attempt(), true);
      });

      test('returns false when exhausted', () {
        manager.attempt();
        manager.attempt();
        manager.attempt();

        expect(manager.attempt(), false);
        expect(manager.exhausted, true);
      });

      test('returns false after success', () {
        manager.attempt();
        manager.markSuccess();

        expect(manager.attempt(), false);
      });
    });

    group('markSuccess', () {
      test('sets succeeded to true', () {
        manager.attempt();
        manager.markSuccess();

        expect(manager.succeeded, true);
      });

      test('stops further attempts', () {
        manager.attempt();
        manager.markSuccess();

        expect(manager.shouldRetryAfterFailure(), false);
      });
    });

    group('shouldRetryAfterFailure', () {
      test('returns true when retries remain', () {
        manager.attempt();
        expect(manager.shouldRetryAfterFailure(), true);

        manager.attempt();
        expect(manager.shouldRetryAfterFailure(), true);
      });

      test('returns false when exhausted', () {
        manager.attempt();
        manager.attempt();
        manager.attempt();

        expect(manager.shouldRetryAfterFailure(), false);
      });

      test('returns false after success', () {
        manager.attempt();
        manager.markSuccess();

        expect(manager.shouldRetryAfterFailure(), false);
      });
    });

    group('getDelayForCurrentRetry', () {
      test('returns correct delay based on attempt', () {
        manager.attempt(); // attempt 1
        expect(
          manager.getDelayForCurrentRetry(),
          const Duration(milliseconds: 500),
        );

        manager.attempt(); // attempt 2
        expect(
          manager.getDelayForCurrentRetry(),
          const Duration(milliseconds: 1000),
        );

        manager.attempt(); // attempt 3
        expect(
          manager.getDelayForCurrentRetry(),
          const Duration(milliseconds: 2000),
        );
      });
    });

    group('reset', () {
      test('resets all state', () {
        manager.attempt();
        manager.attempt();
        manager.markSuccess();

        manager.reset();

        expect(manager.currentAttempt, 0);
        expect(manager.succeeded, false);
        expect(manager.exhausted, false);
      });
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('profile fetch retry sequence timing', () {
  final manager = TestableRetryManager(maxRetries: 3);
  final delays = <Duration>[];

  // Simulate failed attempts - delay only happens before NEXT retry
  while (manager.attempt()) {
    if (manager.shouldRetryAfterFailure()) {
      delays.add(manager.getDelayForCurrentRetry());
    }
  }

  // Only 2 delays: after attempt 1 and 2, not after final attempt 3
  expect(delays, [
    const Duration(milliseconds: 500),
    const Duration(milliseconds: 1000),
  ]);

  // Total wait time before giving up: 1.5 seconds
  final totalWait = delays.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
  expect(totalWait, 1500);
});

    test('new user gets correct default data structure', () {
      // User signs in with Google, has displayName but profile doc doesn't exist
      final googleUser = TestableDefaultUserData.create(
        displayName: 'John Doe',
        email: 'john@gmail.com',
      );

      expect(googleUser['displayName'], 'John Doe');
      expect(googleUser['email'], 'john@gmail.com');
      expect(googleUser['profileImage'], null);
      expect(googleUser['isVerified'], false);
      expect(googleUser['isNew'], false);
      expect(TestableDefaultUserData.hasRequiredFields(googleUser), true);
    });

    test('anonymous user gets fallback values', () {
      // Anonymous user has no displayName or email
      final anonUser = TestableDefaultUserData.create(
        displayName: null,
        email: null,
      );

      expect(anonUser['displayName'], 'No Name');
      expect(anonUser['email'], 'No Email');
      expect(TestableDefaultUserData.hasRequiredFields(anonUser), true);
    });

    test('profile image path is consistent', () {
      const uid = 'user123ABC';

      // Upload generates path
      final uploadPath = TestableProfileImagePath.generate(uid);

      // Later, extract UID from path
      final extractedUid = TestableProfileImagePath.extractUid(uploadPath);

      expect(extractedUid, uid);
    });

    test('successful fetch stops retry loop', () {
      final manager = TestableRetryManager(maxRetries: 3);

      // First attempt fails
      manager.attempt();
      expect(manager.shouldRetryAfterFailure(), true);

      // Second attempt succeeds
      manager.attempt();
      manager.markSuccess();

      // No more retries
      expect(manager.shouldRetryAfterFailure(), false);
      expect(manager.attempt(), false);
      expect(manager.currentAttempt, 2);
    });

    test('validates user data from Firestore before use', () {
      // Complete data from Firestore
      final validData = {
        'displayName': 'Test User',
        'email': 'test@test.com',
        'profileImage': 'https://example.com/img.jpg',
        'isVerified': true,
        'isNew': false,
        'extraField': 'ignored', // Extra fields are fine
      };

      expect(TestableDefaultUserData.hasRequiredFields(validData), true);

      // Corrupted data from Firestore (missing isNew)
      final invalidData = {
        'displayName': 'Test User',
        'email': 'test@test.com',
        'profileImage': null,
        'isVerified': false,
        // missing 'isNew'
      };

      expect(TestableDefaultUserData.hasRequiredFields(invalidData), false);
    });
  });
}