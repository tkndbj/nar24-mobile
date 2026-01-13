// lib/utils/network_utils.dart

import 'dart:async';
import 'dart:io';
import 'package:retry/retry.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  /// Enhanced retry operation with exponential backoff
  static Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    double backoffFactor = 2.0,
    Duration maxDelay = const Duration(seconds: 10),
    bool Function(Exception)? retryIf,
  }) async {
    final retryOptions = RetryOptions(
      maxAttempts: maxAttempts,
      delayFactor: initialDelay,
      randomizationFactor: 0.1,
      maxDelay: maxDelay,
    );

    return await retryOptions.retry(
      () async {
        try {
          return await operation();
        } catch (e) {
          if (e is Exception) {
            // Default retry conditions if none specified
            if (retryIf == null) {
              if (_shouldRetryByDefault(e)) {
                throw e; // Will be retried
              } else {
                rethrow; // Won't be retried
              }
            } else if (retryIf(e)) {
              throw e; // Will be retried
            } else {
              rethrow; // Won't be retried
            }
          }
          rethrow;
        }
      },
      retryIf: (e) {
        if (retryIf != null) {
          return retryIf(e);
        }
        return _shouldRetryByDefault(e);
      },
    );
  }

  /// Determine if an exception should trigger a retry
  static bool _shouldRetryByDefault(dynamic exception) {
    if (exception is SocketException) {
      // Network connectivity issues
      return true;
    }
    if (exception is TimeoutException) {
      // Timeout issues
      return true;
    }
    if (exception is HttpException) {
      // HTTP errors (500-599 should be retried)
      final message = exception.message.toLowerCase();
      return message.contains('500') || 
             message.contains('502') || 
             message.contains('503') || 
             message.contains('504');
    }
    if (exception is Exception) {
      final message = exception.toString().toLowerCase();
      // Common network-related error messages
      return message.contains('failed host lookup') ||
             message.contains('network unreachable') ||
             message.contains('connection refused') ||
             message.contains('connection reset') ||
             message.contains('no route to host');
    }
    return false;
  }

  /// Execute operation with circuit breaker pattern
  static Future<T> withCircuitBreaker<T>({
    required String serviceName,
    required Future<T> Function() operation,
    required T Function() fallback,
    int failureThreshold = 5,
    Duration cooldownPeriod = const Duration(minutes: 2),
  }) async {
    final breaker = _CircuitBreaker.getInstance(serviceName);
    
    if (breaker.isOpen) {
      if (breaker.shouldAttemptReset()) {
        try {
          final result = await operation();
          breaker.recordSuccess();
          return result;
        } catch (e) {
          breaker.recordFailure();
          return fallback();
        }
      } else {
        return fallback();
      }
    }

    try {
      final result = await operation();
      breaker.recordSuccess();
      return result;
    } catch (e) {
      breaker.recordFailure();
      if (breaker.failureCount >= failureThreshold) {
        breaker.open();
      }
      rethrow;
    }
  }

  /// Execute multiple operations concurrently with individual timeouts
  static Future<List<T?>> executeWithIndividualTimeouts<T>(
    List<Future<T> Function()> operations,
    Duration timeout,
  ) async {
    final futures = operations.map((op) =>
      op().timeout(timeout).then<T?>((value) => value).catchError((_, __) => null as T?)
    ).toList();

    return await Future.wait(futures);
  }

  /// Check if error is network-related
  static bool isNetworkError(dynamic error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }

    if (error is Exception) {
      final message = error.toString().toLowerCase();
      return message.contains('network') ||
             message.contains('connection') ||
             message.contains('timeout') ||
             message.contains('unreachable') ||
             message.contains('failed host lookup');
    }

    return false;
  }

  /// Check if device has network connectivity
  /// Returns true if connected to WiFi, mobile data, or ethernet
  static Future<bool> hasConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((status) =>
          status == ConnectivityResult.wifi ||
          status == ConnectivityResult.mobile ||
          status == ConnectivityResult.ethernet);
    } catch (e) {
      // If we can't check connectivity, assume connected and let the request fail naturally
      return true;
    }
  }

  /// Execute an authentication operation with retry and timeout
  /// Designed for Firebase Auth operations that may fail due to network issues
  static Future<T> executeAuthOperation<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 10),
    int maxAttempts = 2,
  }) async {
    return retryOperation(
      () => operation().timeout(timeout),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(milliseconds: 500),
      retryIf: (e) {
        // Retry on network-related errors
        if (e is TimeoutException) return true;
        if (e is SocketException) return true;
        if (isNetworkError(e)) return true;
        return false;
      },
    );
  }

  /// Execute operation with progressive timeout
  static Future<T> withProgressiveTimeout<T>(
    Future<T> Function() operation, {
    List<Duration> timeouts = const [
      Duration(seconds: 3),
      Duration(seconds: 6),
      Duration(seconds: 10),
    ],
  }) async {
    for (int i = 0; i < timeouts.length; i++) {
      try {
        return await operation().timeout(timeouts[i]);
      } catch (e) {
        if (i == timeouts.length - 1) rethrow;
        if (e is! TimeoutException) rethrow;
        // Continue to next timeout duration
      }
    }
    throw TimeoutException('All timeout attempts exhausted');
  }
}

/// Simple circuit breaker implementation
class _CircuitBreaker {
  static final Map<String, _CircuitBreaker> _instances = {};
  
  final String serviceName;
  int failureCount = 0;
  DateTime? lastFailureTime;
  bool isOpen = false;
  
  _CircuitBreaker._(this.serviceName);
  
  static _CircuitBreaker getInstance(String serviceName) {
    return _instances.putIfAbsent(
      serviceName, 
      () => _CircuitBreaker._(serviceName),
    );
  }
  
  void recordSuccess() {
    failureCount = 0;
    isOpen = false;
    lastFailureTime = null;
  }
  
  void recordFailure() {
    failureCount++;
    lastFailureTime = DateTime.now();
  }
  
  void open() {
    isOpen = true;
  }
  
  bool shouldAttemptReset() {
    if (!isOpen) return false;
    if (lastFailureTime == null) return true;
    
    return DateTime.now().difference(lastFailureTime!) > 
           const Duration(minutes: 2);
  }
}