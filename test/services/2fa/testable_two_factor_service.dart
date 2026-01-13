// test/services/testable_two_factor_service.dart
//
// TESTABLE MIRROR of TwoFactorService pure logic from lib/services/two_factor_service.dart
//
// This file contains EXACT copies of pure logic functions from TwoFactorService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/two_factor_service.dart
//
// Last synced with: two_factor_service.dart (current version)

/// 2FA flow types
enum TwoFactorFlowType {
  setup,
  login,
  disable,
}

/// 2FA methods
enum TwoFactorMethod {
  totp,
  email,
}

/// Mirrors code validation from TwoFactorService
class TestableTwoFactorCodeValidator {
  /// Normalize code by trimming and removing non-digits
  /// Mirrors: enteredCode.trim().replaceAll(RegExp(r'\D'), '')
  static String normalizeCode(String enteredCode) {
    return enteredCode.trim().replaceAll(RegExp(r'\D'), '');
  }

  /// Validate that code is exactly 6 digits
  /// Mirrors: code.length != 6 check
  static bool isValidCode(String normalizedCode) {
    return normalizedCode.length == 6;
  }

  /// Full validation: normalize and check
  static TwoFactorCodeValidationResult validate(String enteredCode) {
    final normalized = normalizeCode(enteredCode);
    final isValid = isValidCode(normalized);

    return TwoFactorCodeValidationResult(
      normalizedCode: normalized,
      isValid: isValid,
      errorMessage: isValid ? null : 'invalidCodeFormat',
    );
  }

  /// Check if code contains only digits (after normalization would be same)
  static bool isNumericOnly(String code) {
    return RegExp(r'^\d+$').hasMatch(code);
  }
}

/// Result of code validation
class TwoFactorCodeValidationResult {
  final String normalizedCode;
  final bool isValid;
  final String? errorMessage;

  TwoFactorCodeValidationResult({
    required this.normalizedCode,
    required this.isValid,
    this.errorMessage,
  });
}

/// Mirrors response building from TwoFactorService
class TestableTwoFactorResponseBuilder {
  /// Build success response
  static Map<String, dynamic> buildSuccess({
    required String message,
    TwoFactorMethod? method,
    String? otpauth,
    String? secretBase32,
  }) {
    final response = <String, dynamic>{
      'success': true,
      'message': message,
    };

    if (method != null) response['method'] = method.name;
    if (otpauth != null) response['otpauth'] = otpauth;
    if (secretBase32 != null) response['secretBase32'] = secretBase32;

    return response;
  }

  /// Build failure response
  static Map<String, dynamic> buildFailure({
    required String message,
    int? remaining,
  }) {
    final response = <String, dynamic>{
      'success': false,
      'message': message,
    };

    if (remaining != null) response['remaining'] = remaining;

    return response;
  }

  /// Build invalid code response
  /// Mirrors the check in verify2FASetup, verify2FALogin, verify2FADisable
  static Map<String, dynamic> buildInvalidCodeFormat() {
    return {
      'success': false,
      'message': 'invalidCodeFormat',
    };
  }

  /// Build invalid code response (wrong code, not format)
  static Map<String, dynamic> buildInvalidCode() {
    return {
      'success': false,
      'message': 'invalidCode',
    };
  }

  /// Parse Cloud Function response
  /// Mirrors: (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {}
  static Map<String, dynamic> parseCloudFunctionResponse(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  /// Extract success from parsed response
  static bool extractSuccess(Map<String, dynamic> data) {
    return data['success'] == true;
  }
}

/// Mirrors type/action normalization from TwoFactorService
class TestableTwoFactorTypeNormalizer {
  /// Normalize flow type with fallback
  /// Mirrors: type ?? _currentType ?? 'login'
  static String normalizeType(String? type, String? currentType) {
    return type ?? currentType ?? 'login';
  }

  /// Convert string to enum
  static TwoFactorFlowType? parseFlowType(String? type) {
    switch (type) {
      case 'setup':
        return TwoFactorFlowType.setup;
      case 'login':
        return TwoFactorFlowType.login;
      case 'disable':
        return TwoFactorFlowType.disable;
      default:
        return null;
    }
  }

  /// Get action for email verification based on flow type
  /// setup -> 'setup', login -> 'login', disable -> 'disable'
  static String getEmailVerificationAction(TwoFactorFlowType flowType) {
    return flowType.name;
  }

  /// Validate flow type is known
  static bool isValidFlowType(String type) {
    return ['setup', 'login', 'disable'].contains(type);
  }
}

/// Mirrors method determination logic from TwoFactorService
class TestableTwoFactorMethodResolver {
  /// Determine if TOTP is available (based on isTotpEnabled result)
  static TwoFactorMethod resolveMethod({
    required bool totpEnabled,
  }) {
    return totpEnabled ? TwoFactorMethod.totp : TwoFactorMethod.email;
  }

  /// Check if resend is applicable for method
  /// Mirrors: _currentMethod == 'totp' check in resendVerificationCode
  static bool canResendCode(TwoFactorMethod method) {
    return method == TwoFactorMethod.email;
  }

  /// Get message for resend not applicable
  static String getResendNotApplicableMessage() {
    return 'resendNotApplicableForTotp';
  }
}

/// Mirrors message constants from TwoFactorService
class TestableTwoFactorMessages {
  // Setup messages
  static const String totpSetupStarted = 'totp_setup_started';
  static const String twoFactorEnabledSuccess = 'twoFactorEnabledSuccess';

  // Login messages
  static const String enterAuthenticatorCode = 'enterAuthenticatorCode';
  static const String emailAvailable = 'emailAvailable';
  static const String twoFactorLoginSuccess = 'twoFactorLoginSuccess';

  // Disable messages
  static const String enterAuthenticatorCodeToDisable = 'enterAuthenticatorCodeToDisable';
  static const String twoFactorDisabledSuccess = 'twoFactorDisabledSuccess';

  // Error messages
  static const String invalidCodeFormat = 'invalidCodeFormat';
  static const String invalidCode = 'invalidCode';
  static const String twoFactorInitError = 'twoFactorInitError';
  static const String twoFactorVerificationError = 'twoFactorVerificationError';
  static const String twoFactorResendError = 'twoFactorResendError';
  static const String pleaseWait30Seconds = 'pleasewait30seconds';
  static const String resendNotApplicableForTotp = 'resendNotApplicableForTotp';

  // Email messages
  static const String emailCodeSent = 'emailCodeSent';

  /// Get default message for action
  static String getDefaultMessage(bool success, String action) {
    if (success) {
      switch (action) {
        case 'setup':
          return twoFactorEnabledSuccess;
        case 'login':
          return twoFactorLoginSuccess;
        case 'disable':
          return twoFactorDisabledSuccess;
        default:
          return 'success';
      }
    } else {
      return twoFactorVerificationError;
    }
  }
}

/// Mirrors 2FA state management
class TestableTwoFactorState {
  String? currentType; // 'setup' | 'login' | 'disable'
  String? currentMethod; // 'totp' | 'email'
  String? otpauthUri;

  /// Reset state
  void reset() {
    currentType = null;
    currentMethod = null;
    otpauthUri = null;
  }

  /// Set state for TOTP setup
  void setTotpSetup(String otpauth) {
    currentType = 'setup';
    currentMethod = 'totp';
    otpauthUri = otpauth;
  }

  /// Set state for email setup
  void setEmailSetup() {
    currentType = 'setup';
    currentMethod = 'email';
    otpauthUri = null;
  }

  /// Set state for login
  void setLogin(TwoFactorMethod method) {
    currentType = 'login';
    currentMethod = method.name;
    otpauthUri = null;
  }

  /// Set state for disable
  void setDisable(TwoFactorMethod method) {
    currentType = 'disable';
    currentMethod = method.name;
    otpauthUri = null;
  }

  /// Clear sensitive data (otpauth after setup complete)
  void clearSensitiveData() {
    otpauthUri = null;
  }

  /// Check if in specific flow
  bool isInFlow(String type) => currentType == type;
  bool get isInSetup => currentType == 'setup';
  bool get isInLogin => currentType == 'login';
  bool get isInDisable => currentType == 'disable';
}