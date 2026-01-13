// test/providers/testable_profile_provider.dart
//
// TESTABLE MIRROR of ProfileProvider pure logic from lib/profile_provider.dart
//
// This file contains EXACT copies of pure logic functions from ProfileProvider
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/profile_provider.dart
//
// Last synced with: profile_provider.dart (current version)

/// Mirrors exponential backoff calculation from ProfileProvider._fetchUserData
class TestableProfileBackoff {
  static const int maxRetries = 3;
  static const int baseDelayMs = 250;

  /// Calculate delay for retry attempt
  /// Mirrors: Duration(milliseconds: 250 * (1 << retryCount))
  /// retryCount 1 → 500ms, retryCount 2 → 1000ms, retryCount 3 → 2000ms
  static Duration calculateDelay(int retryCount) {
    return Duration(milliseconds: baseDelayMs * (1 << retryCount));
  }

  /// Check if should retry
  static bool shouldRetry(int currentAttempt) {
    return currentAttempt < maxRetries;
  }

  /// Get all delays for a full retry sequence
  static List<Duration> getRetrySequence() {
    final delays = <Duration>[];
    for (var i = 1; i <= maxRetries; i++) {
      delays.add(calculateDelay(i));
    }
    return delays;
  }

  /// Calculate total wait time for all retries
  static Duration totalRetryTime() {
    int totalMs = 0;
    for (var i = 1; i <= maxRetries; i++) {
      totalMs += baseDelayMs * (1 << i);
    }
    return Duration(milliseconds: totalMs);
  }
}

/// Mirrors default user data structure from ProfileProvider._fetchUserData
class TestableDefaultUserData {
  /// Creates default user data when Firestore document doesn't exist
  /// Mirrors the structure in ProfileProvider._fetchUserData
  static Map<String, dynamic> create({
    String? displayName,
    String? email,
  }) {
    return {
      'displayName': displayName ?? 'No Name',
      'email': email ?? 'No Email',
      'profileImage': null,
      'isVerified': false,
      'isNew': false,
    };
  }

  /// Validate that a user data map has all required fields
  static bool hasRequiredFields(Map<String, dynamic> data) {
    return data.containsKey('displayName') &&
        data.containsKey('email') &&
        data.containsKey('profileImage') &&
        data.containsKey('isVerified') &&
        data.containsKey('isNew');
  }

  /// Get list of required field names
  static List<String> get requiredFields => [
        'displayName',
        'email',
        'profileImage',
        'isVerified',
        'isNew',
      ];
}

/// Mirrors profile image path generation from ProfileProvider.uploadProfileImage
class TestableProfileImagePath {
  /// Generates the storage path for a profile image
  /// Mirrors: 'profileImages/${_currentUser!.uid}'
  static String generate(String uid) {
    if (uid.trim().isEmpty) {
      throw ArgumentError('UID cannot be empty');
    }
    return 'profileImages/$uid';
  }

  /// Extract UID from a profile image path
  static String? extractUid(String path) {
    const prefix = 'profileImages/';
    if (!path.startsWith(prefix)) return null;
    final uid = path.substring(prefix.length);
    return uid.isNotEmpty ? uid : null;
  }
}

/// Mirrors retry state management
class TestableRetryManager {
  final int maxRetries;
  int _currentAttempt = 0;
  bool _succeeded = false;

  TestableRetryManager({this.maxRetries = 3});

  int get currentAttempt => _currentAttempt;
  bool get succeeded => _succeeded;
  bool get exhausted => _currentAttempt >= maxRetries;

  /// Attempt an operation, returns true if should continue trying
  bool attempt() {
    if (_succeeded || exhausted) return false;
    _currentAttempt++;
    return true;
  }

  /// Mark operation as successful
  void markSuccess() {
    _succeeded = true;
  }

  /// Check if should retry after failure
  bool shouldRetryAfterFailure() {
    return !_succeeded && _currentAttempt < maxRetries;
  }

  /// Get delay for current retry
  Duration getDelayForCurrentRetry() {
    return TestableProfileBackoff.calculateDelay(_currentAttempt);
  }

  void reset() {
    _currentAttempt = 0;
    _succeeded = false;
  }
}