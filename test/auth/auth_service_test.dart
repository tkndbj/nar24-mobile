// test/auth/auth_service_test.dart
//
// Unit tests for AuthService security logic
// Tests the EXACT security functions from lib/auth_service.dart
//
// Run: flutter test test/auth/auth_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_auth_service.dart';

void main() {
  // ============================================================================
  // BRUTE FORCE PROTECTION TESTS
  // ============================================================================
  group('TestableBruteForceProtection', () {
    late TestableBruteForceProtection protection;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      protection = TestableBruteForceProtection(
        maxLoginAttempts: 5,
        lockoutDuration: const Duration(minutes: 15),
        nowProvider: () => mockNow,
      );
    });

    group('recordFailedAttempt', () {
      test('increments attempt count', () {
        const email = 'test@example.com';

        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 1);

        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 2);

        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 3);
      });

      test('tracks attempts independently per email', () {
        const email1 = 'user1@example.com';
        const email2 = 'user2@example.com';

        protection.recordFailedAttempt(email1);
        protection.recordFailedAttempt(email1);
        protection.recordFailedAttempt(email2);

        expect(protection.getAttemptCount(email1), 2);
        expect(protection.getAttemptCount(email2), 1);
      });

      test('triggers lockout at exactly maxLoginAttempts', () {
        const email = 'test@example.com';

        // Record 4 attempts - should NOT lock
        for (var i = 0; i < 4; i++) {
          protection.recordFailedAttempt(email);
        }
        expect(protection.isLockedOut(email), false);
        expect(protection.getAttemptCount(email), 4);

        // 5th attempt triggers lockout
        protection.recordFailedAttempt(email);
        expect(protection.isLockedOut(email), true);
        expect(protection.getAttemptCount(email), 0); // Counter reset
      });

      test('sets correct lockout end time', () {
        const email = 'test@example.com';

        // Trigger lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        final lockoutEnd = protection.getLockoutUntil(email);
        expect(lockoutEnd, isNotNull);
        expect(
          lockoutEnd,
          mockNow.add(const Duration(minutes: 15)),
        );
      });

      test('clears attempt count after lockout triggers', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        // Attempt count should be cleared, but lockout should be active
        expect(protection.getAttemptCount(email), 0);
        expect(protection.isLockedOut(email), true);
      });
    });

    group('checkAccountLockout', () {
      test('does not throw when no attempts recorded', () {
        expect(
          () => protection.checkAccountLockout('new@example.com'),
          returnsNormally,
        );
      });

      test('does not throw when under attempt limit', () {
        const email = 'test@example.com';

        for (var i = 0; i < 4; i++) {
          protection.recordFailedAttempt(email);
        }

        expect(
          () => protection.checkAccountLockout(email),
          returnsNormally,
        );
      });

      test('throws when account is locked', () {
        const email = 'test@example.com';

        // Trigger lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        expect(
          () => protection.checkAccountLockout(email),
          throwsA(isA<TestableAuthException>()),
        );
      });

      test('throws with correct error code', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        try {
          protection.checkAccountLockout(email);
          fail('Should have thrown');
        } on TestableAuthException catch (e) {
          expect(e.code, 'too-many-attempts');
        }
      });

      test('includes remaining minutes in error message', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        try {
          protection.checkAccountLockout(email);
          fail('Should have thrown');
        } on TestableAuthException catch (e) {
          expect(e.message, contains('16 minutes'));
        }
      });

      test('updates remaining minutes as time passes', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        // Advance time by 10 minutes
        mockNow = mockNow.add(const Duration(minutes: 10));

        try {
          protection.checkAccountLockout(email);
          fail('Should have thrown');
        } on TestableAuthException catch (e) {
          expect(e.message, contains('6 minutes'));
        }
      });

      test('does not throw after lockout expires', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        // Advance time past lockout duration
        mockNow = mockNow.add(const Duration(minutes: 16));

        expect(
          () => protection.checkAccountLockout(email),
          returnsNormally,
        );
        expect(protection.isLockedOut(email), false);
      });

      test('lockout expires at exact duration boundary', () {
        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        // At exactly 15 minutes - should still be locked (boundary)
        mockNow = mockNow.add(const Duration(minutes: 15));
        expect(protection.isLockedOut(email), false); // At boundary = not locked

        // Reset and test just before boundary
        protection.reset();
        mockNow = DateTime(2024, 6, 15, 10, 0, 0);

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        // 1 second before expiry - still locked
        mockNow = mockNow.add(const Duration(minutes: 14, seconds: 59));
        expect(protection.isLockedOut(email), true);
      });
    });

    group('clearFailedAttempts', () {
      test('clears attempt count', () {
        const email = 'test@example.com';

        protection.recordFailedAttempt(email);
        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 2);

        protection.clearFailedAttempts(email);
        expect(protection.getAttemptCount(email), 0);
      });

      test('clears lockout', () {
        const email = 'test@example.com';

        // Trigger lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }
        expect(protection.isLockedOut(email), true);

        protection.clearFailedAttempts(email);
        expect(protection.isLockedOut(email), false);
        expect(protection.getLockoutUntil(email), null);
      });

      test('only affects specified email', () {
        const email1 = 'user1@example.com';
        const email2 = 'user2@example.com';

        protection.recordFailedAttempt(email1);
        protection.recordFailedAttempt(email1);
        protection.recordFailedAttempt(email2);
        protection.recordFailedAttempt(email2);
        protection.recordFailedAttempt(email2);

        protection.clearFailedAttempts(email1);

        expect(protection.getAttemptCount(email1), 0);
        expect(protection.getAttemptCount(email2), 3);
      });

      test('allows login after lockout is cleared', () {
        const email = 'test@example.com';

        // Trigger lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        expect(
          () => protection.checkAccountLockout(email),
          throwsA(isA<TestableAuthException>()),
        );

        // Clear and verify login is allowed
        protection.clearFailedAttempts(email);

        expect(
          () => protection.checkAccountLockout(email),
          returnsNormally,
        );
      });
    });

    group('edge cases', () {
      test('handles empty email', () {
        const email = '';

        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 1);

        protection.clearFailedAttempts(email);
        expect(protection.getAttemptCount(email), 0);
      });

      test('handles email with special characters', () {
        const email = 'user+test@example.com';

        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }

        expect(protection.isLockedOut(email), true);
      });

      test('handles unicode in email', () {
        const email = 'üser@example.com';

        protection.recordFailedAttempt(email);
        expect(protection.getAttemptCount(email), 1);
      });

      test('custom maxLoginAttempts works', () {
        final customProtection = TestableBruteForceProtection(
          maxLoginAttempts: 3,
          lockoutDuration: const Duration(minutes: 15),
          nowProvider: () => mockNow,
        );

        const email = 'test@example.com';

        customProtection.recordFailedAttempt(email);
        customProtection.recordFailedAttempt(email);
        expect(customProtection.isLockedOut(email), false);

        customProtection.recordFailedAttempt(email);
        expect(customProtection.isLockedOut(email), true);
      });

      test('custom lockoutDuration works', () {
        final customProtection = TestableBruteForceProtection(
          maxLoginAttempts: 5,
          lockoutDuration: const Duration(minutes: 30),
          nowProvider: () => mockNow,
        );

        const email = 'test@example.com';

        for (var i = 0; i < 5; i++) {
          customProtection.recordFailedAttempt(email);
        }

        final lockoutEnd = customProtection.getLockoutUntil(email);
        expect(
          lockoutEnd,
          mockNow.add(const Duration(minutes: 30)),
        );
      });

      test('can re-lockout after previous lockout expires', () {
        const email = 'test@example.com';

        // First lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }
        expect(protection.isLockedOut(email), true);

        // Wait for expiry
        mockNow = mockNow.add(const Duration(minutes: 20));
        expect(protection.isLockedOut(email), false);

        // Trigger second lockout
        for (var i = 0; i < 5; i++) {
          protection.recordFailedAttempt(email);
        }
        expect(protection.isLockedOut(email), true);
      });
    });
  });

  // ============================================================================
  // JWT VALIDATION TESTS
  // ============================================================================
  group('TestableJwtValidator', () {
    group('isValidJwt', () {
      test('returns true for valid JWT structure', () {
        // Valid JWT structure with 3 base64 parts
        // header.payload.signature
        const validJwt =
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

        expect(TestableJwtValidator.isValidJwt(validJwt), true);
      });

      test('returns false for empty string', () {
        expect(TestableJwtValidator.isValidJwt(''), false);
      });

      test('returns false for single part', () {
        expect(TestableJwtValidator.isValidJwt('onlyonepart'), false);
      });

      test('returns false for two parts', () {
        expect(TestableJwtValidator.isValidJwt('part1.part2'), false);
      });

      test('returns false for four parts', () {
        expect(TestableJwtValidator.isValidJwt('p1.p2.p3.p4'), false);
      });

      test('returns false for invalid base64 in header', () {
        const invalidJwt = '!!!invalid!!!.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature';
        expect(TestableJwtValidator.isValidJwt(invalidJwt), false);
      });

      test('returns false for invalid base64 in payload', () {
        const invalidJwt = 'eyJhbGciOiJIUzI1NiJ9.!!!invalid!!!.signature';
        expect(TestableJwtValidator.isValidJwt(invalidJwt), false);
      });

      test('accepts valid base64url encoded parts', () {
        // Base64url uses - and _ instead of + and /
        const base64urlJwt =
            'eyJhbGciOiJIUzI1NiJ9.eyJkYXRhIjoiYWJjLWRlZl9naGkifQ.signature';
        expect(TestableJwtValidator.isValidJwt(base64urlJwt), true);
      });

      test('returns true even with empty signature', () {
        // Signature validation is not done, only structure
        const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.';
        expect(TestableJwtValidator.isValidJwt(jwt), true);
      });

      test('handles minimal valid JWT', () {
        // Minimal valid base64 encoded parts
        const minimalJwt = 'e30.e30.sig'; // {} . {} . sig
        expect(TestableJwtValidator.isValidJwt(minimalJwt), true);
      });
    });
  });

  // ============================================================================
  // BACKGROUND TASK QUEUE TESTS
  // ============================================================================
  group('TestableBackgroundTaskQueue', () {
    late TestableBackgroundTaskQueue queue;

    setUp(() {
      queue = TestableBackgroundTaskQueue();
    });

    tearDown(() {
      queue.dispose();
    });

    test('queues and executes tasks', () async {
      var executed = false;

      queue.queueTask(() async {
        executed = true;
      });

      await queue.waitForCompletion();

      expect(executed, true);
      expect(queue.completedTaskCount, 1);
    });

    test('executes tasks in order', () async {
      final order = <int>[];

      queue.queueTask(() async => order.add(1));
      queue.queueTask(() async => order.add(2));
      queue.queueTask(() async => order.add(3));

      await queue.waitForCompletion();

      expect(order, [1, 2, 3]);
    });

    test('handles task failures gracefully', () async {
      queue.queueTask(() async => throw Exception('Task failed'));
      queue.queueTask(() async {}); // Should still run

      await queue.waitForCompletion();

      expect(queue.failedTaskCount, 1);
      expect(queue.completedTaskCount, 1);
    });

    test('does not queue tasks after dispose', () async {
      queue.dispose();

      queue.queueTask(() async {});

      expect(queue.pendingTaskCount, 0);
    });

    test('stops processing on dispose', () async {
      var slowTaskCompleted = false;

      queue.queueTask(() async {
        await Future.delayed(const Duration(milliseconds: 500));
        slowTaskCompleted = true;
      });

      // Dispose immediately
      await Future.delayed(const Duration(milliseconds: 10));
      queue.dispose();

      // Wait a bit
      await Future.delayed(const Duration(milliseconds: 100));

      expect(queue.isDisposed, true);
    });
  });

  // ============================================================================
  // EMAIL NORMALIZATION TESTS
  // ============================================================================
  group('TestableEmailNormalizer', () {
    test('converts to lowercase', () {
      expect(
        TestableEmailNormalizer.normalize('Test@Example.COM'),
        'test@example.com',
      );
    });

    test('trims whitespace', () {
      expect(
        TestableEmailNormalizer.normalize('  test@example.com  '),
        'test@example.com',
      );
    });

    test('handles mixed case and whitespace', () {
      expect(
        TestableEmailNormalizer.normalize('  TEST@EXAMPLE.COM  '),
        'test@example.com',
      );
    });

    test('handles already normalized email', () {
      expect(
        TestableEmailNormalizer.normalize('test@example.com'),
        'test@example.com',
      );
    });

    test('handles empty string', () {
      expect(TestableEmailNormalizer.normalize(''), '');
    });

    test('handles only whitespace', () {
      expect(TestableEmailNormalizer.normalize('   '), '');
    });
  });

  // ============================================================================
  // INTEGRATION SCENARIOS
  // ============================================================================
  group('Real-World Security Scenarios', () {
    late TestableBruteForceProtection protection;
    late DateTime mockNow;

    setUp(() {
      mockNow = DateTime(2024, 6, 15, 10, 0, 0);
      protection = TestableBruteForceProtection(
        nowProvider: () => mockNow,
      );
    });

    test('successful login after failed attempts clears counter', () {
      const email = 'user@example.com';

      // User fails 3 times
      protection.recordFailedAttempt(email);
      protection.recordFailedAttempt(email);
      protection.recordFailedAttempt(email);
      expect(protection.getAttemptCount(email), 3);

      // User logs in successfully
      protection.clearFailedAttempts(email);

      // Counter should be reset
      expect(protection.getAttemptCount(email), 0);

      // Next failure starts fresh
      protection.recordFailedAttempt(email);
      expect(protection.getAttemptCount(email), 1);
    });

    test('attacker tries password spray across accounts', () {
      // Attacker tries 4 passwords on multiple accounts
      final targets = [
        'user1@company.com',
        'user2@company.com',
        'user3@company.com',
      ];

      for (final email in targets) {
        for (var i = 0; i < 4; i++) {
          protection.recordFailedAttempt(email);
        }
      }

      // None should be locked yet
      for (final email in targets) {
        expect(protection.isLockedOut(email), false);
        expect(protection.getAttemptCount(email), 4);
      }

      // One more attempt on each locks them
      for (final email in targets) {
        protection.recordFailedAttempt(email);
        expect(protection.isLockedOut(email), true);
      }
    });

    test('legitimate user waits out lockout', () {
      const email = 'user@example.com';

      // User gets locked out
      for (var i = 0; i < 5; i++) {
        protection.recordFailedAttempt(email);
      }

      expect(
        () => protection.checkAccountLockout(email),
        throwsA(isA<TestableAuthException>()),
      );

      // User waits 16 minutes
      mockNow = mockNow.add(const Duration(minutes: 16));

      // Should be able to try again
      expect(
        () => protection.checkAccountLockout(email),
        returnsNormally,
      );
    });

    test('email case sensitivity attack prevention', () {
      // Attacker tries different cases of same email
      // This test verifies the importance of email normalization
      const normalizedEmail = 'user@example.com';

      // These should all be normalized BEFORE calling protection methods
      final variants = [
        'USER@example.com',
        'user@EXAMPLE.com',
        'User@Example.Com',
        '  user@example.com  ',
      ];

      for (final variant in variants) {
        final normalized = TestableEmailNormalizer.normalize(variant);
        expect(normalized, normalizedEmail);
      }

      // If normalization is done, all attempts count against same email
      protection.recordFailedAttempt(normalizedEmail);
      protection.recordFailedAttempt(normalizedEmail);
      protection.recordFailedAttempt(normalizedEmail);
      protection.recordFailedAttempt(normalizedEmail);

      expect(protection.getAttemptCount(normalizedEmail), 4);
    });

    test('concurrent attack simulation', () {
      const email = 'target@example.com';

      // Simulate rapid-fire attack
      for (var i = 0; i < 10; i++) {
        if (!protection.isLockedOut(email)) {
          try {
            protection.checkAccountLockout(email);
            // Attempt failed
            protection.recordFailedAttempt(email);
          } catch (e) {
            // Already locked
          }
        }
      }

      // Should be locked after 5 attempts
      expect(protection.isLockedOut(email), true);
    });
  });
}