// lib/services/app_lifecycle_manager.dart
// Production-grade centralized app lifecycle management

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'lifecycle_aware.dart';

/// Centralized manager for app lifecycle events.
///
/// This singleton coordinates all lifecycle-aware providers to ensure
/// smooth transitions between foreground and background states.
///
/// Key features:
/// - Staggered resume to prevent thundering herd problem
/// - Priority-based ordering for pause/resume operations
/// - Debounced state changes to handle rapid transitions
/// - Error isolation to prevent one provider from affecting others
class AppLifecycleManager with WidgetsBindingObserver {
  // Singleton pattern
  static final AppLifecycleManager _instance = AppLifecycleManager._internal();
  static AppLifecycleManager get instance => _instance;

  AppLifecycleManager._internal();

  // State tracking
  bool _isInitialized = false;
  bool _isPaused = false;
  DateTime? _pausedAt;
  AppLifecycleState _currentState = AppLifecycleState.resumed;

  // Debounce rapid state changes
  Timer? _stateChangeDebouncer;
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  // Stagger delay between provider resumes
  static const Duration _staggerDelay = Duration(milliseconds: 100);

  // Registered lifecycle-aware providers
  final List<_RegisteredProvider> _providers = [];

  // Callbacks for external listeners
  final List<VoidCallback> _onPauseCallbacks = [];
  final List<VoidCallback> _onResumeCallbacks = [];

  // Public getters
  bool get isPaused => _isPaused;
  DateTime? get pausedAt => _pausedAt;
  AppLifecycleState get currentState => _currentState;
  Duration get pauseDuration =>
      _pausedAt != null ? DateTime.now().difference(_pausedAt!) : Duration.zero;

  /// Initialize the lifecycle manager.
  /// Call this once during app startup, after WidgetsFlutterBinding.ensureInitialized()
  void initialize() {
    if (_isInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;

    if (kDebugMode) {
      debugPrint('✅ AppLifecycleManager initialized');
    }
  }

  /// Register a lifecycle-aware provider.
  ///
  /// [provider] The provider implementing LifecycleAwareMixin
  /// [name] Optional name for debugging purposes
  void register(LifecycleAwareMixin provider, {String? name}) {
    // Prevent duplicate registration
    if (_providers.any((p) => identical(p.provider, provider))) {
      if (kDebugMode) {
        debugPrint('⚠️ Provider ${name ?? provider.runtimeType} already registered');
      }
      return;
    }

    _providers.add(_RegisteredProvider(
      provider: provider,
      name: name ?? provider.runtimeType.toString(),
    ));

    // Sort by priority (lower value = higher priority)
    _providers.sort((a, b) =>
        a.provider.lifecyclePriority.value.compareTo(b.provider.lifecyclePriority.value));

    if (kDebugMode) {
      debugPrint('📝 Registered lifecycle provider: ${name ?? provider.runtimeType}');
    }
  }

  /// Unregister a provider (typically called in provider's dispose)
  void unregister(LifecycleAwareMixin provider) {
    _providers.removeWhere((p) => identical(p.provider, provider));

    if (kDebugMode) {
      debugPrint('📝 Unregistered lifecycle provider: ${provider.runtimeType}');
    }
  }

  /// Add a callback for pause events
  void addOnPauseCallback(VoidCallback callback) {
    _onPauseCallbacks.add(callback);
  }

  /// Remove a pause callback
  void removeOnPauseCallback(VoidCallback callback) {
    _onPauseCallbacks.remove(callback);
  }

  /// Add a callback for resume events
  void addOnResumeCallback(VoidCallback callback) {
    _onResumeCallbacks.add(callback);
  }

  /// Remove a resume callback
  void removeOnResumeCallback(VoidCallback callback) {
    _onResumeCallbacks.remove(callback);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Debounce rapid state changes (e.g., quick pause/resume)
    _stateChangeDebouncer?.cancel();

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // For pause, act immediately to save resources
      if (!_isPaused) {
        _handlePause();
      }
    } else if (state == AppLifecycleState.resumed) {
      // For resume, debounce to handle rapid state changes
      _stateChangeDebouncer = Timer(_debounceDelay, () {
        if (_isPaused) {
          _handleResume();
        }
      });
    }

    _currentState = state;
  }

  /// Handle app going to background
  Future<void> _handlePause() async {
    if (_isPaused) return;

    _isPaused = true;
    _pausedAt = DateTime.now();

    if (kDebugMode) {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('⏸️  APP PAUSED - Suspending ${_providers.length} providers');
      debugPrint('═══════════════════════════════════════════');
    }

    // Notify external listeners first
    for (final callback in _onPauseCallbacks) {
      try {
        callback();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Pause callback error: $e');
        }
      }
    }

    // Pause providers in reverse priority order (low priority first)
    // This ensures critical providers stay active longest
    final reversedProviders = _providers.reversed.toList();

    for (final registered in reversedProviders) {
      try {
        await registered.provider.onPause();
      } catch (e, stackTrace) {
        // Isolate errors - don't let one provider affect others
        if (kDebugMode) {
          debugPrint('❌ Error pausing ${registered.name}: $e');
          debugPrint('Stack: $stackTrace');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('✅ All providers paused');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('');
    }
  }

  /// Handle app returning to foreground
  Future<void> _handleResume() async {
    if (!_isPaused) return;

    final actualPauseDuration = this.pauseDuration;

    if (kDebugMode) {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('▶️  APP RESUMED after ${actualPauseDuration.inSeconds}s');
      debugPrint('    Resuming ${_providers.length} providers with stagger');
      debugPrint('═══════════════════════════════════════════');
    }

    _isPaused = false;

    // Notify external listeners first
    for (final callback in _onResumeCallbacks) {
      try {
        callback();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Resume callback error: $e');
        }
      }
    }

    // Resume providers with staggered delays based on priority
    // High priority providers resume first with shorter delays
    int delayMultiplier = 0;

    for (final registered in _providers) {
      final delay = _staggerDelay * delayMultiplier;

      // Schedule resume with staggered delay
      Future.delayed(delay, () async {
        try {
          await registered.provider.onResume(actualPauseDuration);
        } catch (e, stackTrace) {
          // Isolate errors - don't let one provider affect others
          if (kDebugMode) {
            debugPrint('❌ Error resuming ${registered.name}: $e');
            debugPrint('Stack: $stackTrace');
          }
        }
      });

      delayMultiplier++;

      if (kDebugMode) {
        debugPrint('  📍 ${registered.name} scheduled to resume in ${delay.inMilliseconds}ms');
      }
    }

    final totalResumeTime = _staggerDelay * (_providers.length - 1);
    if (kDebugMode) {
      debugPrint('');
      debugPrint('⏱️  Total resume time: ~${totalResumeTime.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('');
    }

    _pausedAt = null;
  }

  /// Force an immediate resume (useful for testing or manual trigger)
  Future<void> forceResume() async {
    _stateChangeDebouncer?.cancel();
    await _handleResume();
  }

  /// Force an immediate pause (useful for testing or manual trigger)
  Future<void> forcePause() async {
    _stateChangeDebouncer?.cancel();
    await _handlePause();
  }

  /// Dispose the lifecycle manager (typically never called in production)
  void dispose() {
    _stateChangeDebouncer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _providers.clear();
    _onPauseCallbacks.clear();
    _onResumeCallbacks.clear();
    _isInitialized = false;

    if (kDebugMode) {
      debugPrint('🧹 AppLifecycleManager disposed');
    }
  }

  /// Get debug info about registered providers
  String getDebugInfo() {
    final buffer = StringBuffer();
    buffer.writeln('AppLifecycleManager Status:');
    buffer.writeln('  Initialized: $_isInitialized');
    buffer.writeln('  Paused: $_isPaused');
    buffer.writeln('  Current State: $_currentState');
    buffer.writeln('  Providers (${_providers.length}):');

    for (final p in _providers) {
      buffer.writeln('    - ${p.name} (priority: ${p.provider.lifecyclePriority.name})');
    }

    return buffer.toString();
  }
}

/// Internal class to track registered providers
class _RegisteredProvider {
  final LifecycleAwareMixin provider;
  final String name;

  _RegisteredProvider({
    required this.provider,
    required this.name,
  });
}
