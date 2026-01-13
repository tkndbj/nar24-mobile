// test/services/lifecycle_services_test.dart
//
// Unit tests for lifecycle services pure logic
// Tests the EXACT logic from:
// - lib/services/lifecycle_aware.dart
// - lib/services/app_lifecycle_manager.dart
//
// Run: flutter test test/services/lifecycle_services_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_lifecycle_services.dart';

void main() {
  // ============================================================================
  // LIFECYCLE PRIORITY TESTS
  // ============================================================================
  group('TestableLifecyclePriority', () {
    test('critical has lowest value (highest priority)', () {
      expect(TestableLifecyclePriority.critical.value, 0);
    });

    test('background has highest value (lowest priority)', () {
      expect(TestableLifecyclePriority.background.value, 4);
    });

    test('priority values are in correct order', () {
      expect(TestableLifecyclePriority.critical.value, lessThan(TestableLifecyclePriority.high.value));
      expect(TestableLifecyclePriority.high.value, lessThan(TestableLifecyclePriority.normal.value));
      expect(TestableLifecyclePriority.normal.value, lessThan(TestableLifecyclePriority.low.value));
      expect(TestableLifecyclePriority.low.value, lessThan(TestableLifecyclePriority.background.value));
    });

    test('all priority values are unique', () {
      final values = TestableLifecyclePriority.values.map((p) => p.value).toSet();
      expect(values.length, TestableLifecyclePriority.values.length);
    });
  });

  // ============================================================================
  // REFRESH DECIDER TESTS
  // ============================================================================
  group('TestableRefreshDecider', () {
    group('shouldFullRefresh', () {
      test('returns false for short pause (1 minute)', () {
        expect(
          TestableRefreshDecider.shouldFullRefresh(const Duration(minutes: 1)),
          false,
        );
      });

      test('returns false for 4 minutes pause', () {
        expect(
          TestableRefreshDecider.shouldFullRefresh(const Duration(minutes: 4)),
          false,
        );
      });

      test('returns true for exactly 5 minutes', () {
        expect(
          TestableRefreshDecider.shouldFullRefresh(const Duration(minutes: 5)),
          true,
        );
      });

      test('returns true for long pause (10 minutes)', () {
        expect(
          TestableRefreshDecider.shouldFullRefresh(const Duration(minutes: 10)),
          true,
        );
      });

      test('respects custom threshold', () {
        expect(
          TestableRefreshDecider.shouldFullRefresh(
            const Duration(minutes: 2),
            threshold: const Duration(minutes: 2),
          ),
          true,
        );
      });
    });

    group('getRefreshStrategy', () {
      test('returns noAction for very short pause', () {
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(seconds: 10)),
          RefreshStrategy.noAction,
        );
      });

      test('returns reconnectOnly for 30 seconds - 5 minutes', () {
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(seconds: 45)),
          RefreshStrategy.reconnectOnly,
        );
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 2)),
          RefreshStrategy.reconnectOnly,
        );
      });

      test('returns incrementalRefresh for 5 - 30 minutes', () {
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 5)),
          RefreshStrategy.incrementalRefresh,
        );
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 15)),
          RefreshStrategy.incrementalRefresh,
        );
      });

      test('returns fullReload for 30+ minutes', () {
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 30)),
          RefreshStrategy.fullReload,
        );
        expect(
          TestableRefreshDecider.getRefreshStrategy(const Duration(hours: 2)),
          RefreshStrategy.fullReload,
        );
      });
    });
  });

  // ============================================================================
  // LIFECYCLE STATE TESTS
  // ============================================================================
  group('TestableLifecycleState', () {
    late TestableLifecycleState state;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      state = TestableLifecycleState(nowProvider: () => currentTime);
    });

    test('starts not paused', () {
      expect(state.isPaused, false);
      expect(state.pausedAt, null);
      expect(state.pauseDuration, Duration.zero);
    });

    test('pause sets correct state', () {
      state.pause();

      expect(state.isPaused, true);
      expect(state.pausedAt, currentTime);
    });

    test('resume clears paused state', () {
      state.pause();
      state.resume();

      expect(state.isPaused, false);
      expect(state.pausedAt, null);
    });

    test('pauseDuration calculates correctly', () {
      state.pause();

      // Advance time by 3 minutes
      currentTime = currentTime.add(const Duration(minutes: 3));

      expect(state.pauseDuration, const Duration(minutes: 3));
    });

    test('markInitialized tracks initialization', () {
      expect(state.wasInitializedBeforePause, false);

      state.markInitialized();

      expect(state.wasInitializedBeforePause, true);
    });

    test('shouldFullRefresh uses 5 minute threshold', () {
      state.pause();

      // 3 minutes - should not refresh
      currentTime = currentTime.add(const Duration(minutes: 3));
      expect(state.shouldFullRefresh(), false);

      // 2 more minutes (5 total) - should refresh
      currentTime = currentTime.add(const Duration(minutes: 2));
      expect(state.shouldFullRefresh(), true);
    });
  });

  // ============================================================================
  // PROVIDER REGISTRY TESTS
  // ============================================================================
  group('TestableProviderRegistry', () {
    late TestableProviderRegistry registry;

    setUp(() {
      registry = TestableProviderRegistry();
    });

    test('starts empty', () {
      expect(registry.count, 0);
      expect(registry.providers, isEmpty);
    });

    test('register adds provider', () {
      final provider = Object();
      final result = registry.register(provider, name: 'TestProvider');

      expect(result, true);
      expect(registry.count, 1);
    });

    test('register prevents duplicates', () {
      final provider = Object();
      registry.register(provider, name: 'TestProvider');
      final result = registry.register(provider, name: 'TestProvider');

      expect(result, false);
      expect(registry.count, 1);
    });

    test('register sorts by priority', () {
      final lowPriority = Object();
      final highPriority = Object();
      final critical = Object();

      registry.register(lowPriority, name: 'Low', priority: TestableLifecyclePriority.low);
      registry.register(highPriority, name: 'High', priority: TestableLifecyclePriority.high);
      registry.register(critical, name: 'Critical', priority: TestableLifecyclePriority.critical);

      expect(registry.providers[0].name, 'Critical');
      expect(registry.providers[1].name, 'High');
      expect(registry.providers[2].name, 'Low');
    });

    test('unregister removes provider', () {
      final provider = Object();
      registry.register(provider);

      final result = registry.unregister(provider);

      expect(result, true);
      expect(registry.count, 0);
    });

    test('unregister returns false for non-existent provider', () {
      final result = registry.unregister(Object());
      expect(result, false);
    });

    test('getPauseOrder returns reverse priority', () {
      registry.register(Object(), name: 'Critical', priority: TestableLifecyclePriority.critical);
      registry.register(Object(), name: 'Low', priority: TestableLifecyclePriority.low);
      registry.register(Object(), name: 'Normal', priority: TestableLifecyclePriority.normal);

      final pauseOrder = registry.getPauseOrder();

      // Pause order: low priority first
      expect(pauseOrder[0].name, 'Low');
      expect(pauseOrder[1].name, 'Normal');
      expect(pauseOrder[2].name, 'Critical');
    });

    test('getResumeOrder returns normal priority', () {
      registry.register(Object(), name: 'Low', priority: TestableLifecyclePriority.low);
      registry.register(Object(), name: 'Critical', priority: TestableLifecyclePriority.critical);

      final resumeOrder = registry.getResumeOrder();

      // Resume order: high priority first
      expect(resumeOrder[0].name, 'Critical');
      expect(resumeOrder[1].name, 'Low');
    });

    test('isRegistered returns correct state', () {
      final provider = Object();
      expect(registry.isRegistered(provider), false);

      registry.register(provider);
      expect(registry.isRegistered(provider), true);
    });

    test('getByName finds provider', () {
      registry.register(Object(), name: 'MyProvider');

      final found = registry.getByName('MyProvider');
      expect(found?.name, 'MyProvider');
    });

    test('getByName returns null for non-existent', () {
      expect(registry.getByName('NonExistent'), null);
    });
  });

  // ============================================================================
  // PAUSE DURATION CALCULATOR TESTS
  // ============================================================================
  group('TestablePauseDurationCalculator', () {
    late TestablePauseDurationCalculator calculator;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime(2024, 6, 15, 12, 0, 0);
      calculator = TestablePauseDurationCalculator(nowProvider: () => currentTime);
    });

    test('starts not paused', () {
      expect(calculator.isPaused, false);
      expect(calculator.pausedAt, null);
      expect(calculator.pauseDuration, Duration.zero);
    });

    test('markPaused sets timestamp', () {
      calculator.markPaused();

      expect(calculator.isPaused, true);
      expect(calculator.pausedAt, currentTime);
    });

    test('markResumed clears timestamp', () {
      calculator.markPaused();
      calculator.markResumed();

      expect(calculator.isPaused, false);
      expect(calculator.pausedAt, null);
    });

    test('pauseDuration tracks elapsed time', () {
      calculator.markPaused();

      currentTime = currentTime.add(const Duration(seconds: 45));

      expect(calculator.pauseDuration, const Duration(seconds: 45));
    });
  });

  // ============================================================================
  // STAGGER CALCULATOR TESTS
  // ============================================================================
  group('TestableStaggerCalculator', () {
    test('getDelayForIndex calculates correctly', () {
      expect(
        TestableStaggerCalculator.getDelayForIndex(0),
        Duration.zero,
      );
      expect(
        TestableStaggerCalculator.getDelayForIndex(1),
        const Duration(milliseconds: 100),
      );
      expect(
        TestableStaggerCalculator.getDelayForIndex(5),
        const Duration(milliseconds: 500),
      );
    });

    test('getDelayForIndex respects custom stagger', () {
      expect(
        TestableStaggerCalculator.getDelayForIndex(
          3,
          staggerDelay: const Duration(milliseconds: 50),
        ),
        const Duration(milliseconds: 150),
      );
    });

    test('getTotalResumeTime for zero providers', () {
      expect(
        TestableStaggerCalculator.getTotalResumeTime(0),
        Duration.zero,
      );
    });

    test('getTotalResumeTime for single provider', () {
      expect(
        TestableStaggerCalculator.getTotalResumeTime(1),
        Duration.zero, // No stagger needed for 1 provider
      );
    });

    test('getTotalResumeTime for multiple providers', () {
      expect(
        TestableStaggerCalculator.getTotalResumeTime(5),
        const Duration(milliseconds: 400), // 4 * 100ms
      );
    });

    test('generateSchedule creates correct delays', () {
      final schedule = TestableStaggerCalculator.generateSchedule(4);

      expect(schedule.length, 4);
      expect(schedule[0], Duration.zero);
      expect(schedule[1], const Duration(milliseconds: 100));
      expect(schedule[2], const Duration(milliseconds: 200));
      expect(schedule[3], const Duration(milliseconds: 300));
    });
  });

  // ============================================================================
  // APP LIFECYCLE STATE HANDLER TESTS
  // ============================================================================
  group('TestableAppLifecycleStateHandler', () {
    group('shouldPause', () {
      test('returns true for paused', () {
        expect(TestableAppLifecycleStateHandler.shouldPause('paused'), true);
      });

      test('returns true for inactive', () {
        expect(TestableAppLifecycleStateHandler.shouldPause('inactive'), true);
      });

      test('returns true for detached', () {
        expect(TestableAppLifecycleStateHandler.shouldPause('detached'), true);
      });

      test('returns false for resumed', () {
        expect(TestableAppLifecycleStateHandler.shouldPause('resumed'), false);
      });
    });

    group('shouldResume', () {
      test('returns true for resumed', () {
        expect(TestableAppLifecycleStateHandler.shouldResume('resumed'), true);
      });

      test('returns false for paused', () {
        expect(TestableAppLifecycleStateHandler.shouldResume('paused'), false);
      });
    });

    group('getAction', () {
      test('returns pause for paused state', () {
        expect(
          TestableAppLifecycleStateHandler.getAction('paused'),
          LifecycleAction.pause,
        );
      });

      test('returns resume for resumed state', () {
        expect(
          TestableAppLifecycleStateHandler.getAction('resumed'),
          LifecycleAction.resume,
        );
      });

      test('returns none for unknown state', () {
        expect(
          TestableAppLifecycleStateHandler.getAction('unknown'),
          LifecycleAction.none,
        );
      });
    });
  });

  // ============================================================================
  // CALLBACK MANAGER TESTS
  // ============================================================================
  group('TestableCallbackManager', () {
    late TestableCallbackManager manager;

    setUp(() {
      manager = TestableCallbackManager();
    });

    test('starts with no callbacks', () {
      expect(manager.pauseCallbackCount, 0);
      expect(manager.resumeCallbackCount, 0);
    });

    test('addOnPauseCallback increments count', () {
      manager.addOnPauseCallback(() {});
      expect(manager.pauseCallbackCount, 1);
    });

    test('addOnResumeCallback increments count', () {
      manager.addOnResumeCallback(() {});
      expect(manager.resumeCallbackCount, 1);
    });

    test('removeOnPauseCallback decrements count', () {
      final callback = () {};
      manager.addOnPauseCallback(callback);
      manager.removeOnPauseCallback(callback);
      expect(manager.pauseCallbackCount, 0);
    });

    test('executePauseCallbacks calls all callbacks', () {
      int callCount = 0;
      manager.addOnPauseCallback(() => callCount++);
      manager.addOnPauseCallback(() => callCount++);

      final result = manager.executePauseCallbacks();

      expect(result, 2);
      expect(callCount, 2);
    });

    test('executePauseCallbacks isolates errors', () {
      int callCount = 0;
      manager.addOnPauseCallback(() => throw Exception('Error'));
      manager.addOnPauseCallback(() => callCount++);

      final result = manager.executePauseCallbacks();

      expect(result, 1); // Only one succeeded
      expect(callCount, 1); // Second callback still ran
    });

    test('clear removes all callbacks', () {
      manager.addOnPauseCallback(() {});
      manager.addOnResumeCallback(() {});
      manager.clear();

      expect(manager.pauseCallbackCount, 0);
      expect(manager.resumeCallbackCount, 0);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('provider registration order for typical app', () {
      final registry = TestableProviderRegistry();

      // Register providers as they would be in a real app
      registry.register(Object(), name: 'AuthProvider', priority: TestableLifecyclePriority.critical);
      registry.register(Object(), name: 'CartProvider', priority: TestableLifecyclePriority.normal);
      registry.register(Object(), name: 'BadgeProvider', priority: TestableLifecyclePriority.high);
      registry.register(Object(), name: 'BoostedRotation', priority: TestableLifecyclePriority.background);
      registry.register(Object(), name: 'AnalyticsProvider', priority: TestableLifecyclePriority.low);

      // Resume order should be: critical -> high -> normal -> low -> background
      final resumeOrder = registry.getResumeOrder();
      expect(resumeOrder[0].name, 'AuthProvider'); // Critical - resumes first
      expect(resumeOrder[1].name, 'BadgeProvider'); // High
      expect(resumeOrder[2].name, 'CartProvider'); // Normal
      expect(resumeOrder[3].name, 'AnalyticsProvider'); // Low
      expect(resumeOrder[4].name, 'BoostedRotation'); // Background - resumes last

      // Pause order should be reversed
      final pauseOrder = registry.getPauseOrder();
      expect(pauseOrder[0].name, 'BoostedRotation'); // Background - pauses first
      expect(pauseOrder[4].name, 'AuthProvider'); // Critical - pauses last
    });

    test('staggered resume timing for 5 providers', () {
      final schedule = TestableStaggerCalculator.generateSchedule(5);
      final totalTime = TestableStaggerCalculator.getTotalResumeTime(5);

      // Each provider should resume 100ms after the previous
      expect(schedule[0], Duration.zero); // First resumes immediately
      expect(schedule[4], const Duration(milliseconds: 400)); // Last waits 400ms
      expect(totalTime, const Duration(milliseconds: 400));
    });

    test('refresh strategy after different pause durations', () {
      // User briefly switches apps (10 seconds)
      expect(
        TestableRefreshDecider.getRefreshStrategy(const Duration(seconds: 10)),
        RefreshStrategy.noAction,
      );

      // User takes a phone call (2 minutes)
      expect(
        TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 2)),
        RefreshStrategy.reconnectOnly,
      );

      // User puts phone down for lunch (15 minutes)
      expect(
        TestableRefreshDecider.getRefreshStrategy(const Duration(minutes: 15)),
        RefreshStrategy.incrementalRefresh,
      );

      // User returns next day (overnight)
      expect(
        TestableRefreshDecider.getRefreshStrategy(const Duration(hours: 8)),
        RefreshStrategy.fullReload,
      );
    });

    test('lifecycle state transitions', () {
      var time = DateTime(2024, 6, 15, 12, 0, 0);
      final state = TestableLifecycleState(nowProvider: () => time);

      // Initialize provider
      state.markInitialized();
      expect(state.wasInitializedBeforePause, true);

      // App goes to background
      state.pause();
      expect(state.isPaused, true);

      // User returns after 3 minutes
      time = time.add(const Duration(minutes: 3));
      expect(state.shouldFullRefresh(), false); // Under 5 min threshold

      // Actually 6 minutes total
      time = time.add(const Duration(minutes: 3));
      expect(state.shouldFullRefresh(), true); // Over 5 min threshold

      // Resume
      state.resume();
      expect(state.isPaused, false);
      expect(state.pausedAt, null);
    });
  });
}