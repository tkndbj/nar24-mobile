import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Analytics service for tracking database operations with zero performance impact
/// Tracks exact read/write counts, operation durations, and performance metrics
/// All analytics failures are silently caught to never affect app functionality
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static bool _isEnabled = true;

  /// Disable analytics (useful for testing)
  static void disable() => _isEnabled = false;

  /// Enable analytics
  static void enable() => _isEnabled = true;

  /// Track a Firestore read operation (Query or Document)
  /// Returns the result unchanged, tracks reads in background
  static Future<T> trackRead<T>({
    required String operation,
    required Future<T> Function() execute,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return await execute();

    Trace? trace;
    final stopwatch = Stopwatch()..start();

    try {
      // Start performance trace (non-blocking)
      trace = FirebasePerformance.instance.newTrace(operation);
      trace.start().catchError((_) {}); // Fail silently

      // Execute the operation
      final result = await execute();
      stopwatch.stop();

      // Count reads based on result type
      int readCount = 0;
      if (result is QuerySnapshot) {
        readCount = result.docs.length;
      } else if (result is DocumentSnapshot) {
        readCount = result.exists ? 1 : 0;
      } else if (result is List) {
        readCount = result.length;
      }

      // Log analytics in background (fire-and-forget)
      _logOperationAsync(
        operation: operation,
        type: 'read',
        count: readCount,
        duration: stopwatch.elapsedMilliseconds,
        metadata: metadata,
        trace: trace,
      );

      return result;
    } catch (e) {
      // Original operation failed - rethrow without analytics
      stopwatch.stop();
      _logErrorAsync(operation, 'read', e);
      rethrow;
    }
  }

  /// Track a Firestore write operation (single document or batch)
  /// Returns the result unchanged, tracks writes in background
  static Future<T> trackWrite<T>({
    required String operation,
    required Future<T> Function() execute,
    int? writeCount,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return await execute();

    Trace? trace;
    final stopwatch = Stopwatch()..start();

    try {
      // Start performance trace (non-blocking)
      trace = FirebasePerformance.instance.newTrace(operation);
      trace.start().catchError((_) {}); // Fail silently

      // Execute the operation
      final result = await execute();
      stopwatch.stop();

      // Use provided write count or default to 1
      final count = writeCount ?? 1;

      // Log analytics in background (fire-and-forget)
      _logOperationAsync(
        operation: operation,
        type: 'write',
        count: count,
        duration: stopwatch.elapsedMilliseconds,
        metadata: metadata,
        trace: trace,
      );

      return result;
    } catch (e) {
      // Original operation failed - rethrow without analytics
      stopwatch.stop();
      _logErrorAsync(operation, 'write', e);
      rethrow;
    }
  }

  /// Track a Firestore transaction (can include reads + writes)
  /// Returns the result unchanged, tracks operations in background
  static Future<T> trackTransaction<T>({
    required String operation,
    required Future<T> Function() execute,
    int? readCount,
    int? writeCount,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return await execute();

    Trace? trace;
    final stopwatch = Stopwatch()..start();

    try {
      // Start performance trace (non-blocking)
      trace = FirebasePerformance.instance.newTrace(operation);
      trace.start().catchError((_) {}); // Fail silently

      // Execute the operation
      final result = await execute();
      stopwatch.stop();

      // Log analytics in background (fire-and-forget)
      _logOperationAsync(
        operation: operation,
        type: 'transaction',
        count: (readCount ?? 0) + (writeCount ?? 0),
        duration: stopwatch.elapsedMilliseconds,
        metadata: {
          ...?metadata,
          'reads': readCount ?? 0,
          'writes': writeCount ?? 0,
        },
        trace: trace,
      );

      return result;
    } catch (e) {
      // Original operation failed - rethrow without analytics
      stopwatch.stop();
      _logErrorAsync(operation, 'transaction', e);
      rethrow;
    }
  }

  /// Track a Cloud Function call
  /// Returns the result unchanged, tracks call in background
  static Future<T> trackCloudFunction<T>({
    required String functionName,
    required Future<T> Function() execute,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return await execute();

    Trace? trace;
    final stopwatch = Stopwatch()..start();

    try {
      // Start performance trace (non-blocking)
      trace = FirebasePerformance.instance.newTrace('cf_$functionName');
      trace.start().catchError((_) {}); // Fail silently

      // Execute the operation
      final result = await execute();
      stopwatch.stop();

      // Log analytics in background (fire-and-forget)
      _logOperationAsync(
        operation: 'cf_$functionName',
        type: 'cloud_function',
        count: 1,
        duration: stopwatch.elapsedMilliseconds,
        metadata: metadata,
        trace: trace,
      );

      return result;
    } catch (e) {
      // Original operation failed - rethrow without analytics
      stopwatch.stop();
      _logErrorAsync('cf_$functionName', 'cloud_function', e);
      rethrow;
    }
  }

  /// Track an Algolia search operation
  /// Returns the result unchanged, tracks search in background
  static Future<T> trackAlgoliaSearch<T>({
    required String operation,
    required Future<T> Function() execute,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return await execute();

    Trace? trace;
    final stopwatch = Stopwatch()..start();

    try {
      // Start performance trace (non-blocking)
      trace = FirebasePerformance.instance.newTrace(operation);
      trace.start().catchError((_) {}); // Fail silently

      // Execute the operation
      final result = await execute();
      stopwatch.stop();

      // Log analytics in background (fire-and-forget)
      _logOperationAsync(
        operation: operation,
        type: 'algolia_search',
        count: 1,
        duration: stopwatch.elapsedMilliseconds,
        metadata: metadata,
        trace: trace,
      );

      return result;
    } catch (e) {
      // Original operation failed - rethrow without analytics
      stopwatch.stop();
      _logErrorAsync(operation, 'algolia_search', e);
      rethrow;
    }
  }

  /// Log operation metrics asynchronously (fire-and-forget)
  /// Never throws errors or blocks the main operation
  static void _logOperationAsync({
    required String operation,
    required String type,
    required int count,
    required int duration,
    Map<String, dynamic>? metadata,
    Trace? trace,
  }) {
    // Run in microtask to avoid blocking
    Future.microtask(() async {
      try {
        // Update performance trace
        if (trace != null) {
          trace.setMetric('${type}_count', count);
          trace.setMetric('duration_ms', duration);
          if (metadata != null) {
            for (var entry in metadata.entries) {
              if (entry.value is int) {
                trace.setMetric(entry.key, entry.value as int);
              } else if (entry.value is String) {
                trace.putAttribute(entry.key, entry.value as String);
              }
            }
          }
          await trace.stop();
        }

        // Log to Firebase Analytics
        final params = <String, dynamic>{
          'operation': operation,
          'type': type,
          'count': count,
          'duration_ms': duration,
          ...?metadata,
        };

        // Limit parameter values to Firebase Analytics constraints and convert to Map<String, Object>
        final sanitizedParams = <String, Object>{};
        params.forEach((key, value) {
          if (value == null) return; // Skip null values
          if (value is String && value.length > 100) {
            sanitizedParams[key] = value.substring(0, 100);
          } else if (value is String) {
            sanitizedParams[key] = value;
          } else if (value is num) {
            sanitizedParams[key] = value;
          } else if (value is bool) {
            // Firebase Analytics only accepts String or num, convert bool to string
            sanitizedParams[key] = value.toString();
          } else {
            // Convert other types to String
            sanitizedParams[key] = value.toString();
          }
        });

        await _analytics.logEvent(
          name: 'db_operation',
          parameters: sanitizedParams,
        );
      } catch (e) {
        // Silently fail - analytics should never break the app
        if (kDebugMode) {
          debugPrint('Analytics logging failed (non-critical): $e');
        }
      }
    });
  }

  /// Log operation error asynchronously (fire-and-forget)
  /// Never throws errors or blocks the main operation
  static void _logErrorAsync(String operation, String type, dynamic error) {
    Future.microtask(() async {
      try {
        await _analytics.logEvent(
          name: 'db_operation_error',
          parameters: {
            'operation': operation,
            'type': type,
            'error': error.toString().substring(0, 100),
          },
        );
      } catch (e) {
        // Silently fail
        if (kDebugMode) {
          debugPrint('Analytics error logging failed (non-critical): $e');
        }
      }
    });
  }

  /// Log a custom event (for non-database operations)
  static Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
  }) async {
    if (!_isEnabled) return;

    try {
      // Convert Map<String, dynamic> to Map<String, Object>
      Map<String, Object>? convertedParams;
      if (parameters != null) {
        convertedParams = <String, Object>{};
        parameters.forEach((key, value) {
          if (value == null) return;
          if (value is String) {
            convertedParams![key] = value;
          } else if (value is num) {
            convertedParams![key] = value;
          } else if (value is bool) {
            // Firebase Analytics only accepts String or num, convert bool to string
            convertedParams![key] = value.toString();
          } else {
            convertedParams![key] = value.toString();
          }
        });
      }

      await _analytics.logEvent(name: name, parameters: convertedParams);
    } catch (e) {
      // Silently fail
      if (kDebugMode) {
        debugPrint('Analytics event logging failed (non-critical): $e');
      }
    }
  }

  /// Set user properties for segmentation
  static Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    if (!_isEnabled) return;

    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      // Silently fail
      if (kDebugMode) {
        debugPrint('Analytics user property failed (non-critical): $e');
      }
    }
  }

  /// Set user ID for tracking
  static Future<void> setUserId(String? userId) async {
    if (!_isEnabled) return;

    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      // Silently fail
      if (kDebugMode) {
        debugPrint('Analytics setUserId failed (non-critical): $e');
      }
    }
  }
}
