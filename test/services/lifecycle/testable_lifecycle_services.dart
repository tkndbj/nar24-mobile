// test/services/testable_lifecycle_services.dart
//
// TESTABLE MIRROR of lifecycle services pure logic from:
// - lib/services/lifecycle_aware.dart
// - lib/services/app_lifecycle_manager.dart
//
// This file contains EXACT copies of pure logic functions made public for unit testing.
// If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with the source files
//
// Last synced with: lifecycle_aware.dart, app_lifecycle_manager.dart (current version)

/// Mirrors LifecyclePriority from lifecycle_aware.dart
enum TestableLifecyclePriority {
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
  const TestableLifecyclePriority(this.value);
}

/// Mirrors shouldFullRefresh logic from LifecycleAwareMixin
class TestableRefreshDecider {
  /// Default threshold for full refresh (5 minutes)
  static const Duration defaultRefreshThreshold = Duration(minutes: 5);

  /// Mirrors shouldFullRefresh from LifecycleAwareMixin
  /// Default: refresh if paused for more than 5 minutes
  static bool shouldFullRefresh(
    Duration pauseDuration, {
    Duration threshold = defaultRefreshThreshold,
  }) {
    return pauseDuration.inMinutes >= threshold.inMinutes;
  }

  /// Get refresh strategy based on pause duration
  static RefreshStrategy getRefreshStrategy(Duration pauseDuration) {
    if (pauseDuration.inMinutes >= 30) {
      return RefreshStrategy.fullReload;
    } else if (pauseDuration.inMinutes >= 5) {
      return RefreshStrategy.incrementalRefresh;
    } else if (pauseDuration.inSeconds >= 30) {
      return RefreshStrategy.reconnectOnly;
    } else {
      return RefreshStrategy.noAction;
    }
  }
}

/// Refresh strategy based on pause duration
enum RefreshStrategy {
  /// No action needed (very short pause)
  noAction,

  /// Just reconnect listeners without fetching new data
  reconnectOnly,

  /// Fetch incremental updates
  incrementalRefresh,

  /// Full data reload
  fullReload,
}

/// Mirrors lifecycle state management from LifecycleAwareMixin
class TestableLifecycleState {
  bool _isPaused = false;
  DateTime? _pausedAt;
  bool _wasInitialized = false;
  final DateTime Function() nowProvider;

  TestableLifecycleState({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? DateTime.now;

  bool get isPaused => _isPaused;
  DateTime? get pausedAt => _pausedAt;
  bool get wasInitializedBeforePause => _wasInitialized;

  /// Calculate how long the provider has been paused
  Duration get pauseDuration {
    if (_pausedAt == null) return Duration.zero;
    return nowProvider().difference(_pausedAt!);
  }

  /// Mark as paused
  void pause() {
    _isPaused = true;
    _pausedAt = nowProvider();
  }

  /// Mark as resumed
  void resume() {
    _isPaused = false;
    _pausedAt = null;
  }

  /// Mark as initialized
  void markInitialized() {
    _wasInitialized = true;
  }

  /// Check if should do full refresh after resume
  bool shouldFullRefresh() {
    return TestableRefreshDecider.shouldFullRefresh(pauseDuration);
  }
}

/// Mirrors provider registration logic from AppLifecycleManager
class TestableProviderRegistry {
  final List<RegisteredProvider> _providers = [];

  List<RegisteredProvider> get providers => List.unmodifiable(_providers);
  int get count => _providers.length;

  /// Register a provider (prevents duplicates)
  /// Returns true if registered, false if already exists
  bool register(Object provider, {String? name, TestableLifecyclePriority priority = TestableLifecyclePriority.normal}) {
    // Prevent duplicate registration
    if (_providers.any((p) => identical(p.provider, provider))) {
      return false;
    }

    _providers.add(RegisteredProvider(
      provider: provider,
      name: name ?? provider.runtimeType.toString(),
      priority: priority,
    ));

    // Sort by priority (lower value = higher priority)
    _providers.sort((a, b) => a.priority.value.compareTo(b.priority.value));

    return true;
  }

  /// Unregister a provider
  bool unregister(Object provider) {
    final lengthBefore = _providers.length;
    _providers.removeWhere((p) => identical(p.provider, provider));
    return _providers.length < lengthBefore;
  }

  /// Get providers in pause order (reverse priority - low priority first)
  List<RegisteredProvider> getPauseOrder() {
    return _providers.reversed.toList();
  }

  /// Get providers in resume order (normal priority - high priority first)
  List<RegisteredProvider> getResumeOrder() {
    return List.from(_providers);
  }

  /// Clear all providers
  void clear() {
    _providers.clear();
  }

  /// Check if provider is registered
  bool isRegistered(Object provider) {
    return _providers.any((p) => identical(p.provider, provider));
  }

  /// Get provider by name
  RegisteredProvider? getByName(String name) {
    try {
      return _providers.firstWhere((p) => p.name == name);
    } catch (_) {
      return null;
    }
  }
}

/// Registered provider data
class RegisteredProvider {
  final Object provider;
  final String name;
  final TestableLifecyclePriority priority;

  RegisteredProvider({
    required this.provider,
    required this.name,
    required this.priority,
  });
}

/// Mirrors pause duration calculation from AppLifecycleManager
class TestablePauseDurationCalculator {
  DateTime? _pausedAt;
  final DateTime Function() nowProvider;

  TestablePauseDurationCalculator({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? DateTime.now;

  DateTime? get pausedAt => _pausedAt;

  /// Set paused timestamp
  void markPaused() {
    _pausedAt = nowProvider();
  }

  /// Clear paused timestamp
  void markResumed() {
    _pausedAt = null;
  }

  /// Calculate pause duration
  Duration get pauseDuration {
    if (_pausedAt == null) return Duration.zero;
    return nowProvider().difference(_pausedAt!);
  }

  /// Check if currently paused
  bool get isPaused => _pausedAt != null;
}

/// Mirrors stagger delay calculation from AppLifecycleManager
class TestableStaggerCalculator {
  static const Duration defaultStaggerDelay = Duration(milliseconds: 100);

  /// Calculate delay for provider at given index
  static Duration getDelayForIndex(int index, {Duration staggerDelay = defaultStaggerDelay}) {
    return staggerDelay * index;
  }

  /// Calculate total resume time for n providers
  static Duration getTotalResumeTime(int providerCount, {Duration staggerDelay = defaultStaggerDelay}) {
    if (providerCount <= 0) return Duration.zero;
    return staggerDelay * (providerCount - 1);
  }

  /// Generate stagger schedule for providers
  static List<Duration> generateSchedule(int providerCount, {Duration staggerDelay = defaultStaggerDelay}) {
    return List.generate(providerCount, (index) => staggerDelay * index);
  }
}

/// Mirrors lifecycle state enum handling
class TestableAppLifecycleStateHandler {
  /// Check if state should trigger pause
  static bool shouldPause(String state) {
    return ['paused', 'inactive', 'detached'].contains(state);
  }

  /// Check if state should trigger resume
  static bool shouldResume(String state) {
    return state == 'resumed';
  }

  /// Map state string to action
  static LifecycleAction getAction(String state) {
    if (shouldResume(state)) {
      return LifecycleAction.resume;
    } else if (shouldPause(state)) {
      return LifecycleAction.pause;
    }
    return LifecycleAction.none;
  }
}

/// Lifecycle action to take
enum LifecycleAction {
  none,
  pause,
  resume,
}

/// Mirrors callback management from AppLifecycleManager
class TestableCallbackManager {
  final List<void Function()> _onPauseCallbacks = [];
  final List<void Function()> _onResumeCallbacks = [];

  int get pauseCallbackCount => _onPauseCallbacks.length;
  int get resumeCallbackCount => _onResumeCallbacks.length;

  void addOnPauseCallback(void Function() callback) {
    _onPauseCallbacks.add(callback);
  }

  void removeOnPauseCallback(void Function() callback) {
    _onPauseCallbacks.remove(callback);
  }

  void addOnResumeCallback(void Function() callback) {
    _onResumeCallbacks.add(callback);
  }

  void removeOnResumeCallback(void Function() callback) {
    _onResumeCallbacks.remove(callback);
  }

  /// Execute all pause callbacks, returns count of successful executions
  int executePauseCallbacks() {
    int successCount = 0;
    for (final callback in _onPauseCallbacks) {
      try {
        callback();
        successCount++;
      } catch (_) {
        // Isolated error handling
      }
    }
    return successCount;
  }

  /// Execute all resume callbacks, returns count of successful executions
  int executeResumeCallbacks() {
    int successCount = 0;
    for (final callback in _onResumeCallbacks) {
      try {
        callback();
        successCount++;
      } catch (_) {
        // Isolated error handling
      }
    }
    return successCount;
  }

  void clear() {
    _onPauseCallbacks.clear();
    _onResumeCallbacks.clear();
  }
}