// lib/services/lifecycle_aware.dart
// Production-grade lifecycle management mixin for providers

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Priority levels for lifecycle operations.
/// Lower numbers = higher priority (resumes first, pauses last)
enum LifecyclePriority {
  /// Critical providers that need immediate attention (e.g., auth, user data)
  critical(0),

  /// High priority providers (e.g., badges, notifications)
  high(1),

  /// Normal priority providers (e.g., cart, favorites)
  normal(2),

  /// Low priority providers (e.g., recommendations, analytics)
  low(3),

  /// Background providers that can wait (e.g., boosted products)
  background(4);

  final int value;
  const LifecyclePriority(this.value);
}

/// Mixin that provides lifecycle awareness to providers.
///
/// Providers implementing this mixin can pause their Firestore listeners
/// and timers when the app goes to background, and resume them when
/// the app comes back to foreground.
///
/// Usage:
/// ```dart
/// class MyProvider with ChangeNotifier, LifecycleAwareMixin {
///   @override
///   LifecyclePriority get lifecyclePriority => LifecyclePriority.normal;
///
///   @override
///   Future<void> onPause() async {
///     // Cancel listeners, pause timers
///   }
///
///   @override
///   Future<void> onResume() async {
///     // Restart listeners, resume timers
///   }
/// }
/// ```
mixin LifecycleAwareMixin {
  /// The priority of this provider in lifecycle operations.
  /// Override to set custom priority.
  LifecyclePriority get lifecyclePriority => LifecyclePriority.normal;

  /// Whether this provider is currently paused
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Timestamp when the app was paused
  DateTime? _pausedAt;
  DateTime? get pausedAt => _pausedAt;

  /// Whether the provider was properly initialized before pause
  bool _wasInitialized = false;

  /// Called when the app goes to background.
  /// Override to cancel Firestore listeners, pause timers, etc.
  ///
  /// Returns a Future that completes when pause operations are done.
  @mustCallSuper
  Future<void> onPause() async {
    _isPaused = true;
    _pausedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint('⏸️ ${runtimeType} paused');
    }
  }

  /// Called when the app returns to foreground.
  /// Override to restart Firestore listeners, resume timers, etc.
  ///
  /// [pauseDuration] indicates how long the app was in background.
  /// Use this to decide whether to do a full refresh or just reconnect.
  ///
  /// Returns a Future that completes when resume operations are done.
  @mustCallSuper
  Future<void> onResume(Duration pauseDuration) async {
    _isPaused = false;
    _pausedAt = null;
    if (kDebugMode) {
      debugPrint('▶️ ${runtimeType} resumed after ${pauseDuration.inSeconds}s');
    }
  }

  /// Called before pause to check if provider should save state
  bool get shouldSaveStateOnPause => true;

  /// Called after resume to check if provider needs full refresh
  /// Default: refresh if paused for more than 5 minutes
  bool shouldFullRefresh(Duration pauseDuration) {
    return pauseDuration.inMinutes >= 5;
  }

  /// Marks the provider as initialized (call after initial setup)
  void markInitialized() {
    _wasInitialized = true;
  }

  /// Whether the provider was initialized before being paused
  bool get wasInitializedBeforePause => _wasInitialized;
}

/// Extension to help with timer management
extension TimerLifecycle on Timer? {
  /// Safely cancels the timer if it exists
  void safeCancel() {
    this?.cancel();
  }
}

/// Extension to help with StreamSubscription management
extension StreamSubscriptionLifecycle<T> on StreamSubscription<T>? {
  /// Safely cancels the subscription if it exists
  Future<void> safeCancel() async {
    await this?.cancel();
  }
}
