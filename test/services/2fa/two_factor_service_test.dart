// test/services/two_factor_service_test.dart
//
// Unit tests for TwoFactorService pure logic
// Tests the EXACT logic from lib/services/two_factor_service.dart
//
// Run: flutter test test/services/two_factor_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_two_factor_service.dart';

void main() {
  // ============================================================================
  // CODE VALIDATOR TESTS
  // ============================================================================
  group('TestableTwoFactorCodeValidator', () {
    group('normalizeCode', () {
      test('trims whitespace', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('  123456  '), '123456');
      });

      test('removes spaces in middle', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('123 456'), '123456');
      });

      test('removes dashes', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('123-456'), '123456');
      });

      test('removes letters', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('12a34b56'), '123456');
      });

      test('handles code with mixed non-digits', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('1-2-3-4-5-6'), '123456');
      });

      test('returns empty for all non-digits', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode('abcdef'), '');
      });

      test('handles empty string', () {
        expect(TestableTwoFactorCodeValidator.normalizeCode(''), '');
      });
    });

    group('isValidCode', () {
      test('returns true for 6 digits', () {
        expect(TestableTwoFactorCodeValidator.isValidCode('123456'), true);
      });

      test('returns false for 5 digits', () {
        expect(TestableTwoFactorCodeValidator.isValidCode('12345'), false);
      });

      test('returns false for 7 digits', () {
        expect(TestableTwoFactorCodeValidator.isValidCode('1234567'), false);
      });

      test('returns false for empty string', () {
        expect(TestableTwoFactorCodeValidator.isValidCode(''), false);
      });
    });

    group('validate', () {
      test('valid code with spaces passes', () {
        final result = TestableTwoFactorCodeValidator.validate('123 456');
        
        expect(result.isValid, true);
        expect(result.normalizedCode, '123456');
        expect(result.errorMessage, null);
      });

      test('valid code with dashes passes', () {
        final result = TestableTwoFactorCodeValidator.validate('123-456');
        
        expect(result.isValid, true);
        expect(result.normalizedCode, '123456');
      });

      test('short code fails', () {
        final result = TestableTwoFactorCodeValidator.validate('12345');
        
        expect(result.isValid, false);
        expect(result.normalizedCode, '12345');
        expect(result.errorMessage, 'invalidCodeFormat');
      });

      test('long code fails', () {
        final result = TestableTwoFactorCodeValidator.validate('1234567');
        
        expect(result.isValid, false);
        expect(result.errorMessage, 'invalidCodeFormat');
      });

      test('letters stripped then validated', () {
        // '12ab34cd56' -> '123456' -> valid
        final result = TestableTwoFactorCodeValidator.validate('12ab34cd56');
        
        expect(result.isValid, true);
        expect(result.normalizedCode, '123456');
      });

      test('all letters fails', () {
        final result = TestableTwoFactorCodeValidator.validate('abcdef');
        
        expect(result.isValid, false);
        expect(result.normalizedCode, '');
      });
    });

    group('isNumericOnly', () {
      test('returns true for all digits', () {
        expect(TestableTwoFactorCodeValidator.isNumericOnly('123456'), true);
      });

      test('returns false for mixed', () {
        expect(TestableTwoFactorCodeValidator.isNumericOnly('123abc'), false);
      });

      test('returns false for spaces', () {
        expect(TestableTwoFactorCodeValidator.isNumericOnly('123 456'), false);
      });
    });
  });

  // ============================================================================
  // RESPONSE BUILDER TESTS
  // ============================================================================
  group('TestableTwoFactorResponseBuilder', () {
    group('buildSuccess', () {
      test('builds basic success response', () {
        final response = TestableTwoFactorResponseBuilder.buildSuccess(
          message: 'twoFactorEnabledSuccess',
        );

        expect(response['success'], true);
        expect(response['message'], 'twoFactorEnabledSuccess');
      });

      test('includes method when provided', () {
        final response = TestableTwoFactorResponseBuilder.buildSuccess(
          message: 'success',
          method: TwoFactorMethod.totp,
        );

        expect(response['method'], 'totp');
      });

      test('includes otpauth for setup', () {
        final response = TestableTwoFactorResponseBuilder.buildSuccess(
          message: 'totp_setup_started',
          method: TwoFactorMethod.totp,
          otpauth: 'otpauth://totp/App:user@example.com?secret=ABC123',
          secretBase32: 'ABC123',
        );

        expect(response['otpauth'], startsWith('otpauth://'));
        expect(response['secretBase32'], 'ABC123');
      });
    });

    group('buildFailure', () {
      test('builds basic failure response', () {
        final response = TestableTwoFactorResponseBuilder.buildFailure(
          message: 'invalidCode',
        );

        expect(response['success'], false);
        expect(response['message'], 'invalidCode');
      });

      test('includes remaining attempts when provided', () {
        final response = TestableTwoFactorResponseBuilder.buildFailure(
          message: 'invalidCode',
          remaining: 2,
        );

        expect(response['remaining'], 2);
      });
    });

    group('buildInvalidCodeFormat', () {
      test('returns correct structure', () {
        final response = TestableTwoFactorResponseBuilder.buildInvalidCodeFormat();

        expect(response['success'], false);
        expect(response['message'], 'invalidCodeFormat');
      });
    });

    group('parseCloudFunctionResponse', () {
      test('parses Map response', () {
        final data = {'success': true, 'message': 'ok'};
        final parsed = TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(data);

        expect(parsed['success'], true);
        expect(parsed['message'], 'ok');
      });

      test('returns empty map for non-Map', () {
        expect(TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(null), {});
        expect(TestableTwoFactorResponseBuilder.parseCloudFunctionResponse('string'), {});
        expect(TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(123), {});
      });

      test('handles Map<Object?, Object?>', () {
        final data = <Object?, Object?>{'success': true};
        final parsed = TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(data);

        expect(parsed['success'], true);
      });
    });

    group('extractSuccess', () {
      test('returns true for success: true', () {
        expect(TestableTwoFactorResponseBuilder.extractSuccess({'success': true}), true);
      });

      test('returns false for success: false', () {
        expect(TestableTwoFactorResponseBuilder.extractSuccess({'success': false}), false);
      });

      test('returns false for missing success', () {
        expect(TestableTwoFactorResponseBuilder.extractSuccess({}), false);
      });

      test('returns false for success: "true" (string)', () {
        expect(TestableTwoFactorResponseBuilder.extractSuccess({'success': 'true'}), false);
      });
    });
  });

  // ============================================================================
  // TYPE NORMALIZER TESTS
  // ============================================================================
  group('TestableTwoFactorTypeNormalizer', () {
    group('normalizeType', () {
      test('returns type when provided', () {
        expect(TestableTwoFactorTypeNormalizer.normalizeType('setup', 'login'), 'setup');
      });

      test('falls back to currentType when type is null', () {
        expect(TestableTwoFactorTypeNormalizer.normalizeType(null, 'disable'), 'disable');
      });

      test('falls back to login when both null', () {
        expect(TestableTwoFactorTypeNormalizer.normalizeType(null, null), 'login');
      });
    });

    group('parseFlowType', () {
      test('parses setup', () {
        expect(TestableTwoFactorTypeNormalizer.parseFlowType('setup'), TwoFactorFlowType.setup);
      });

      test('parses login', () {
        expect(TestableTwoFactorTypeNormalizer.parseFlowType('login'), TwoFactorFlowType.login);
      });

      test('parses disable', () {
        expect(TestableTwoFactorTypeNormalizer.parseFlowType('disable'), TwoFactorFlowType.disable);
      });

      test('returns null for unknown', () {
        expect(TestableTwoFactorTypeNormalizer.parseFlowType('invalid'), null);
        expect(TestableTwoFactorTypeNormalizer.parseFlowType(null), null);
      });
    });

    group('isValidFlowType', () {
      test('returns true for valid types', () {
        expect(TestableTwoFactorTypeNormalizer.isValidFlowType('setup'), true);
        expect(TestableTwoFactorTypeNormalizer.isValidFlowType('login'), true);
        expect(TestableTwoFactorTypeNormalizer.isValidFlowType('disable'), true);
      });

      test('returns false for invalid types', () {
        expect(TestableTwoFactorTypeNormalizer.isValidFlowType('enable'), false);
        expect(TestableTwoFactorTypeNormalizer.isValidFlowType(''), false);
      });
    });
  });

  // ============================================================================
  // METHOD RESOLVER TESTS
  // ============================================================================
  group('TestableTwoFactorMethodResolver', () {
    group('resolveMethod', () {
      test('returns totp when enabled', () {
        expect(
          TestableTwoFactorMethodResolver.resolveMethod(totpEnabled: true),
          TwoFactorMethod.totp,
        );
      });

      test('returns email when totp not enabled', () {
        expect(
          TestableTwoFactorMethodResolver.resolveMethod(totpEnabled: false),
          TwoFactorMethod.email,
        );
      });
    });

    group('canResendCode', () {
      test('returns true for email', () {
        expect(TestableTwoFactorMethodResolver.canResendCode(TwoFactorMethod.email), true);
      });

      test('returns false for totp', () {
        expect(TestableTwoFactorMethodResolver.canResendCode(TwoFactorMethod.totp), false);
      });
    });

    group('getResendNotApplicableMessage', () {
      test('returns correct message', () {
        expect(
          TestableTwoFactorMethodResolver.getResendNotApplicableMessage(),
          'resendNotApplicableForTotp',
        );
      });
    });
  });

  // ============================================================================
  // MESSAGES TESTS
  // ============================================================================
  group('TestableTwoFactorMessages', () {
    group('getDefaultMessage', () {
      test('returns correct success messages', () {
        expect(
          TestableTwoFactorMessages.getDefaultMessage(true, 'setup'),
          'twoFactorEnabledSuccess',
        );
        expect(
          TestableTwoFactorMessages.getDefaultMessage(true, 'login'),
          'twoFactorLoginSuccess',
        );
        expect(
          TestableTwoFactorMessages.getDefaultMessage(true, 'disable'),
          'twoFactorDisabledSuccess',
        );
      });

      test('returns error message for failure', () {
        expect(
          TestableTwoFactorMessages.getDefaultMessage(false, 'setup'),
          'twoFactorVerificationError',
        );
        expect(
          TestableTwoFactorMessages.getDefaultMessage(false, 'login'),
          'twoFactorVerificationError',
        );
      });
    });
  });

  // ============================================================================
  // STATE TESTS
  // ============================================================================
  group('TestableTwoFactorState', () {
    late TestableTwoFactorState state;

    setUp(() {
      state = TestableTwoFactorState();
    });

    test('starts with null state', () {
      expect(state.currentType, null);
      expect(state.currentMethod, null);
      expect(state.otpauthUri, null);
    });

    test('setTotpSetup sets correct state', () {
      state.setTotpSetup('otpauth://totp/test');

      expect(state.currentType, 'setup');
      expect(state.currentMethod, 'totp');
      expect(state.otpauthUri, 'otpauth://totp/test');
      expect(state.isInSetup, true);
    });

    test('setEmailSetup sets correct state', () {
      state.setEmailSetup();

      expect(state.currentType, 'setup');
      expect(state.currentMethod, 'email');
      expect(state.otpauthUri, null);
    });

    test('setLogin sets correct state', () {
      state.setLogin(TwoFactorMethod.totp);

      expect(state.currentType, 'login');
      expect(state.currentMethod, 'totp');
      expect(state.isInLogin, true);
    });

    test('setDisable sets correct state', () {
      state.setDisable(TwoFactorMethod.email);

      expect(state.currentType, 'disable');
      expect(state.currentMethod, 'email');
      expect(state.isInDisable, true);
    });

    test('reset clears all state', () {
      state.setTotpSetup('otpauth://test');
      state.reset();

      expect(state.currentType, null);
      expect(state.currentMethod, null);
      expect(state.otpauthUri, null);
    });

    test('clearSensitiveData clears only otpauth', () {
      state.setTotpSetup('otpauth://sensitive');
      state.clearSensitiveData();

      expect(state.otpauthUri, null);
      expect(state.currentType, 'setup'); // Still set
      expect(state.currentMethod, 'totp'); // Still set
    });

    test('isInFlow checks correctly', () {
      state.setLogin(TwoFactorMethod.totp);

      expect(state.isInFlow('login'), true);
      expect(state.isInFlow('setup'), false);
      expect(state.isInFlow('disable'), false);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('user enters code with spaces from SMS', () {
      // User copies "123 456" from SMS
      final result = TestableTwoFactorCodeValidator.validate('123 456');

      expect(result.isValid, true);
      expect(result.normalizedCode, '123456');
    });

    test('user enters code with leading/trailing whitespace', () {
      final result = TestableTwoFactorCodeValidator.validate('  123456  ');

      expect(result.isValid, true);
      expect(result.normalizedCode, '123456');
    });

    test('authenticator app code validation', () {
      // TOTP codes are always 6 digits
      final validCode = TestableTwoFactorCodeValidator.validate('482917');
      expect(validCode.isValid, true);

      // Partial code (user still typing)
      final partialCode = TestableTwoFactorCodeValidator.validate('4829');
      expect(partialCode.isValid, false);
    });

    test('TOTP setup flow state management', () {
      final state = TestableTwoFactorState();

      // 1. Start setup
      state.setTotpSetup('otpauth://totp/MyApp:user@example.com?secret=JBSWY3DPEHPK3PXP');

      expect(state.isInSetup, true);
      expect(state.currentMethod, 'totp');
      expect(state.otpauthUri, isNotNull);

      // 2. After successful verification, clear sensitive data
      state.clearSensitiveData();

      expect(state.otpauthUri, null);
      expect(state.currentMethod, 'totp'); // Flow state preserved
    });

    test('email fallback from TOTP', () {
      // User has TOTP but wants email code instead
      final state = TestableTwoFactorState();

      // Started with TOTP
      state.setLogin(TwoFactorMethod.totp);
      expect(state.currentMethod, 'totp');

      // User clicks "Send email instead"
      state.setLogin(TwoFactorMethod.email);
      expect(state.currentMethod, 'email');

      // Now can resend
      expect(TestableTwoFactorMethodResolver.canResendCode(TwoFactorMethod.email), true);
    });

    test('resend not allowed for TOTP', () {
      // TOTP codes are time-based, no "resend"
      expect(TestableTwoFactorMethodResolver.canResendCode(TwoFactorMethod.totp), false);

      final message = TestableTwoFactorMethodResolver.getResendNotApplicableMessage();
      expect(message, 'resendNotApplicableForTotp');
    });

    test('Cloud Function response parsing', () {
      // Success response
      final successData = {'success': true, 'message': 'emailCodeSent'};
      final successParsed = TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(successData);
      expect(TestableTwoFactorResponseBuilder.extractSuccess(successParsed), true);

      // Failure with remaining attempts
      final failureData = {'success': false, 'message': 'invalidCode', 'remaining': 2};
      final failureParsed = TestableTwoFactorResponseBuilder.parseCloudFunctionResponse(failureData);
      expect(TestableTwoFactorResponseBuilder.extractSuccess(failureParsed), false);
      expect(failureParsed['remaining'], 2);

      // Malformed response
      final malformed = TestableTwoFactorResponseBuilder.parseCloudFunctionResponse('not a map');
      expect(malformed, {});
    });
  });
}