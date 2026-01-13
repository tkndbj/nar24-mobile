// test/auth/testable_auth_service.dart
//
// TESTABLE MIRROR of AuthService security logic from lib/auth_service.dart
//
// This file contains EXACT copies of security-critical functions from AuthService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/auth_service.dart
//
// Last synced with: auth_service.dart (current version)

import 'dart:convert' show base64;

/// Custom exception mirroring FirebaseAuthException for testing
class TestableAuthException implements Exception {
  final String code;
  final String message;

  TestableAuthException({required this.code, required this.message});

  @override
  String toString() => 'TestableAuthException($code): $message';
}

/// Testable brute force protection logic
/// Mirrors the exact implementation from AuthService
class TestableBruteForceProtection {
  final Map<String, int> _loginAttempts = {};
  final Map<String, DateTime> _lockoutUntil = {};

  final int maxLoginAttempts;
  final Duration lockoutDuration;

  /// For testing: allow custom time provider
  DateTime Function() nowProvider;

  TestableBruteForceProtection({
    this.maxLoginAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    DateTime Function()? nowProvider,
  }) : nowProvider = nowProvider ?? DateTime.now;

  /// Get current login attempts for an email (for testing inspection)
  int getAttemptCount(String email) => _loginAttempts[email] ?? 0;

  /// Get lockout end time for an email (for testing inspection)
  DateTime? getLockoutUntil(String email) => _lockoutUntil[email];

  /// Check if account is currently locked out
  bool isLockedOut(String email) {
    final lockoutEnd = _lockoutUntil[email];
    if (lockoutEnd == null) return false;
    return lockoutEnd.isAfter(nowProvider());
  }

  /// Mirrors `_checkAccountLockout` from AuthService
  /// Throws if account is locked
  void checkAccountLockout(String email) {
    final lockoutEnd = _lockoutUntil[email];
    if (lockoutEnd != null && lockoutEnd.isAfter(nowProvider())) {
      final remainingMinutes =
          lockoutEnd.difference(nowProvider()).inMinutes + 1;
      throw TestableAuthException(
        code: 'too-many-attempts',
        message: 'Account locked. Try again in $remainingMinutes minutes.',
      );
    }
  }

  /// Mirrors `_recordFailedAttempt` from AuthService
  void recordFailedAttempt(String email) {
    final attempts = (_loginAttempts[email] ?? 0) + 1;
    _loginAttempts[email] = attempts;

    if (attempts >= maxLoginAttempts) {
      _lockoutUntil[email] = nowProvider().add(lockoutDuration);
      _loginAttempts.remove(email);
    }
  }

  /// Mirrors `_clearFailedAttempts` from AuthService
  void clearFailedAttempts(String email) {
    _loginAttempts.remove(email);
    _lockoutUntil.remove(email);
  }

  /// Reset all state (for testing)
  void reset() {
    _loginAttempts.clear();
    _lockoutUntil.clear();
  }
}

/// Testable JWT validation logic
/// Mirrors the exact implementation from AuthService
class TestableJwtValidator {
  /// Mirrors `_isValidJwt` from AuthService
  /// Validates JWT token format (basic structural check)
  static bool isValidJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      // Check each part is valid base64
      for (final part in parts.take(2)) {
        final normalized = base64.normalize(part);
        base64.decode(normalized);
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Testable background task queue logic
/// Mirrors the queue management from AuthService
class TestableBackgroundTaskQueue {
  final List<Future<void> Function()> _tasks = [];
  bool _isProcessing = false;
  bool _isDisposed = false;

  /// For testing: track completed tasks
  int completedTaskCount = 0;
  int failedTaskCount = 0;

  /// Get pending task count
  int get pendingTaskCount => _tasks.length;

  /// Check if currently processing
  bool get isProcessing => _isProcessing;

  /// Check if disposed
  bool get isDisposed => _isDisposed;

  /// Mirrors `_queueBackgroundTask` from AuthService
  void queueTask(Future<void> Function() task) {
    if (_isDisposed) return;
    _tasks.add(task);
    _processBackgroundTasks();
  }

  /// Mirrors `_processBackgroundTasks` from AuthService
  Future<void> _processBackgroundTasks() async {
    if (_isDisposed || _isProcessing || _tasks.isEmpty) {
      return;
    }

    _isProcessing = true;

    while (_tasks.isNotEmpty && !_isDisposed) {
      final task = _tasks.removeAt(0);
      try {
        await task();
        completedTaskCount++;
      } catch (e) {
        failedTaskCount++;
      }

      if (_tasks.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    _isProcessing = false;
  }

  /// Wait for all tasks to complete (for testing)
  Future<void> waitForCompletion() async {
    while (_isProcessing || _tasks.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Dispose the queue
  void dispose() {
    _isDisposed = true;
    _tasks.clear();
  }

  /// Reset for testing
  void reset() {
    _tasks.clear();
    _isProcessing = false;
    _isDisposed = false;
    completedTaskCount = 0;
    failedTaskCount = 0;
  }
}

/// Testable email normalization
/// Mirrors email handling from AuthService
class TestableEmailNormalizer {
  /// Normalize email for consistent comparison
  static String normalize(String email) {
    return email.trim().toLowerCase();
  }
}