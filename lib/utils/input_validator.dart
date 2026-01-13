// lib/utils/input_validator.dart

class InputValidator {
  // Email validation with better regex
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email.trim().toLowerCase());
  }

  // Password strength check
  static String? validatePassword(String password) {
    if (password.length < 6) {
      return 'Password must be at least 6 characters';
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    return null;
  }

  // Sanitize 2FA codes
  static String sanitize2FACode(String code) {
    // Remove all non-digits and trim
    return code.trim().replaceAll(RegExp(r'\D'), '');
  }

  // Normalize email for consistency
  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }
}
