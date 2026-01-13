// test/services/market_layout_service_test.dart
//
// Unit tests for MarketLayoutService pure logic
// Tests the EXACT logic from lib/services/market_layout_service.dart
//
// Run: flutter test test/services/market_layout_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'testable_market_layout_service.dart';

void main() {
  // ============================================================================
  // MARKET WIDGET CONFIG TESTS
  // ============================================================================
  group('TestableMarketWidgetConfig', () {
    group('fromMap', () {
      test('parses complete map', () {
        final map = {
          'id': 'widget_1',
          'name': 'Test Widget',
          'type': 'banner',
          'isVisible': true,
          'order': 5,
        };

        final config = TestableMarketWidgetConfig.fromMap(map);

        expect(config.id, 'widget_1');
        expect(config.name, 'Test Widget');
        expect(config.type, 'banner');
        expect(config.isVisible, true);
        expect(config.order, 5);
      });

      test('handles missing fields with defaults', () {
        final map = <String, dynamic>{};

        final config = TestableMarketWidgetConfig.fromMap(map);

        expect(config.id, '');
        expect(config.name, '');
        expect(config.type, '');
        expect(config.isVisible, true); // Default true
        expect(config.order, 0); // Default 0
      });

      test('handles null values', () {
        final map = {
          'id': null,
          'name': null,
          'type': null,
          'isVisible': null,
          'order': null,
        };

        final config = TestableMarketWidgetConfig.fromMap(map);

        expect(config.id, '');
        expect(config.isVisible, true); // null → default true
        expect(config.order, 0); // null → default 0
      });

      test('converts non-string id/name/type to string', () {
        final map = {
          'id': 123,
          'name': 456,
          'type': 789,
          'isVisible': true,
          'order': 0,
        };

        final config = TestableMarketWidgetConfig.fromMap(map);

        expect(config.id, '123');
        expect(config.name, '456');
        expect(config.type, '789');
      });

      test('handles non-bool isVisible', () {
        final map = {
          'id': 'test',
          'name': 'test',
          'type': 'test',
          'isVisible': 'true', // String, not bool
          'order': 0,
        };

        final config = TestableMarketWidgetConfig.fromMap(map);

        // Non-bool defaults to true
        expect(config.isVisible, true);
      });

      test('handles non-int order', () {
        final map = {
          'id': 'test',
          'name': 'test',
          'type': 'test',
          'isVisible': true,
          'order': '5', // String, not int
        };

        final config = TestableMarketWidgetConfig.fromMap(map);

        // Non-int defaults to 0
        expect(config.order, 0);
      });
    });

    group('toMap', () {
      test('serializes all fields', () {
        final config = TestableMarketWidgetConfig(
          id: 'widget_1',
          name: 'Test Widget',
          type: 'carousel',
          isVisible: false,
          order: 3,
        );

        final map = config.toMap();

        expect(map['id'], 'widget_1');
        expect(map['name'], 'Test Widget');
        expect(map['type'], 'carousel');
        expect(map['isVisible'], false);
        expect(map['order'], 3);
      });
    });

    group('copyWith', () {
      test('copies with single change', () {
        final original = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget 1',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final copied = original.copyWith(isVisible: false);

        expect(copied.id, 'w1');
        expect(copied.name, 'Widget 1');
        expect(copied.isVisible, false);
      });

      test('copies with multiple changes', () {
        final original = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget 1',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final copied = original.copyWith(
          name: 'Updated Widget',
          order: 5,
        );

        expect(copied.id, 'w1'); // Unchanged
        expect(copied.name, 'Updated Widget');
        expect(copied.order, 5);
      });

      test('returns new instance', () {
        final original = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget 1',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final copied = original.copyWith();

        expect(identical(original, copied), false);
        expect(original == copied, true);
      });
    });

    group('equality', () {
      test('equal configs are equal', () {
        final config1 = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final config2 = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        expect(config1 == config2, true);
        expect(config1.hashCode == config2.hashCode, true);
      });

      test('different id means not equal', () {
        final config1 = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final config2 = TestableMarketWidgetConfig(
          id: 'w2', // Different
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        expect(config1 == config2, false);
      });

      test('different visibility means not equal', () {
        final config1 = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        final config2 = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: false, // Different
          order: 0,
        );

        expect(config1 == config2, false);
      });
    });

    group('round-trip', () {
      test('toMap -> fromMap preserves data', () {
        final original = TestableMarketWidgetConfig(
          id: 'roundtrip_widget',
          name: 'Roundtrip Test',
          type: 'special_type',
          isVisible: false,
          order: 42,
        );

        final map = original.toMap();
        final restored = TestableMarketWidgetConfig.fromMap(map);

        expect(restored, original);
      });
    });
  });

  // ============================================================================
  // WIDGET PARSER TESTS
  // ============================================================================
  group('TestableWidgetParser', () {
    group('parseWidgetsFromData', () {
      test('parses valid widgets', () {
        final data = {
          'widgets': [
            {'id': 'w1', 'name': 'Widget 1', 'type': 'banner', 'isVisible': true, 'order': 0},
            {'id': 'w2', 'name': 'Widget 2', 'type': 'carousel', 'isVisible': true, 'order': 1},
          ],
        };

        final widgets = TestableWidgetParser.parseWidgetsFromData(data);

        expect(widgets.length, 2);
        expect(widgets[0].id, 'w1');
        expect(widgets[1].id, 'w2');
      });

      test('returns empty for null widgets', () {
        final data = {'widgets': null};
        expect(TestableWidgetParser.parseWidgetsFromData(data), isEmpty);
      });

      test('returns empty for non-list widgets', () {
        final data = {'widgets': 'not a list'};
        expect(TestableWidgetParser.parseWidgetsFromData(data), isEmpty);
      });

      test('returns empty for missing widgets key', () {
        final data = <String, dynamic>{};
        expect(TestableWidgetParser.parseWidgetsFromData(data), isEmpty);
      });

      test('skips widgets with empty id', () {
        final data = {
          'widgets': [
            {'id': '', 'name': 'No ID', 'type': 'banner', 'isVisible': true, 'order': 0},
            {'id': 'valid', 'name': 'Valid', 'type': 'banner', 'isVisible': true, 'order': 1},
          ],
        };

        final widgets = TestableWidgetParser.parseWidgetsFromData(data);

        expect(widgets.length, 1);
        expect(widgets[0].id, 'valid');
      });

      test('skips widgets with empty type', () {
        final data = {
          'widgets': [
            {'id': 'w1', 'name': 'No Type', 'type': '', 'isVisible': true, 'order': 0},
            {'id': 'w2', 'name': 'Valid', 'type': 'banner', 'isVisible': true, 'order': 1},
          ],
        };

        final widgets = TestableWidgetParser.parseWidgetsFromData(data);

        expect(widgets.length, 1);
        expect(widgets[0].id, 'w2');
      });

      test('skips duplicate widget IDs', () {
        final data = {
          'widgets': [
            {'id': 'duplicate', 'name': 'First', 'type': 'banner', 'isVisible': true, 'order': 0},
            {'id': 'duplicate', 'name': 'Second', 'type': 'carousel', 'isVisible': true, 'order': 1},
            {'id': 'unique', 'name': 'Unique', 'type': 'list', 'isVisible': true, 'order': 2},
          ],
        };

        final widgets = TestableWidgetParser.parseWidgetsFromData(data);

        expect(widgets.length, 2);
        expect(widgets[0].name, 'First'); // Keeps first occurrence
        expect(widgets[1].id, 'unique');
      });

      test('skips non-map entries', () {
        final data = {
          'widgets': [
            'not a map',
            123,
            null,
            {'id': 'valid', 'name': 'Valid', 'type': 'banner', 'isVisible': true, 'order': 0},
          ],
        };

        final widgets = TestableWidgetParser.parseWidgetsFromData(data);

        expect(widgets.length, 1);
        expect(widgets[0].id, 'valid');
      });
    });

    group('isValidWidget', () {
      test('returns true for valid widget', () {
        final widget = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        expect(TestableWidgetParser.isValidWidget(widget), true);
      });

      test('returns false for empty id', () {
        final widget = TestableMarketWidgetConfig(
          id: '',
          name: 'Widget',
          type: 'banner',
          isVisible: true,
          order: 0,
        );

        expect(TestableWidgetParser.isValidWidget(widget), false);
      });

      test('returns false for empty type', () {
        final widget = TestableMarketWidgetConfig(
          id: 'w1',
          name: 'Widget',
          type: '',
          isVisible: true,
          order: 0,
        );

        expect(TestableWidgetParser.isValidWidget(widget), false);
      });
    });
  });

  // ============================================================================
  // RETRY LOGIC TESTS
  // ============================================================================
  group('TestableRetryLogic', () {
    group('shouldRetry', () {
      test('returns true for unavailable', () {
        expect(TestableRetryLogic.shouldRetry('unavailable'), true);
      });

      test('returns true for deadline-exceeded', () {
        expect(TestableRetryLogic.shouldRetry('deadline-exceeded'), true);
      });

      test('returns true for internal', () {
        expect(TestableRetryLogic.shouldRetry('internal'), true);
      });

      test('returns true for unknown', () {
        expect(TestableRetryLogic.shouldRetry('unknown'), true);
      });

      test('returns false for permission-denied', () {
        expect(TestableRetryLogic.shouldRetry('permission-denied'), false);
      });

      test('returns false for not-found', () {
        expect(TestableRetryLogic.shouldRetry('not-found'), false);
      });

      test('returns false for invalid-argument', () {
        expect(TestableRetryLogic.shouldRetry('invalid-argument'), false);
      });
    });

    group('getRetryDelay', () {
      test('increases with retry count', () {
        final delay0 = TestableRetryLogic.getRetryDelay(0);
        final delay1 = TestableRetryLogic.getRetryDelay(1);
        final delay2 = TestableRetryLogic.getRetryDelay(2);

        expect(delay0, const Duration(seconds: 2));
        expect(delay1, const Duration(seconds: 4));
        expect(delay2, const Duration(seconds: 6));
      });
    });

    group('canRetry', () {
      test('returns true under max retries', () {
        expect(TestableRetryLogic.canRetry(0), true);
        expect(TestableRetryLogic.canRetry(1), true);
        expect(TestableRetryLogic.canRetry(2), true);
      });

      test('returns false at max retries', () {
        expect(TestableRetryLogic.canRetry(3), false);
        expect(TestableRetryLogic.canRetry(4), false);
      });
    });
  });

  // ============================================================================
  // WIDGET CHANGE DETECTOR TESTS
  // ============================================================================
  group('TestableWidgetChangeDetector', () {
    group('widgetsChanged', () {
      test('returns false for identical lists', () {
        final widgets1 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        ];
        final widgets2 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        ];

        expect(TestableWidgetChangeDetector.widgetsChanged(widgets1, widgets2), false);
      });

      test('returns true for different length', () {
        final widgets1 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        ];
        final widgets2 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
          TestableMarketWidgetConfig(id: 'w2', name: 'W2', type: 't2', isVisible: true, order: 1),
        ];

        expect(TestableWidgetChangeDetector.widgetsChanged(widgets1, widgets2), true);
      });

      test('returns true for changed visibility', () {
        final widgets1 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        ];
        final widgets2 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: false, order: 0),
        ];

        expect(TestableWidgetChangeDetector.widgetsChanged(widgets1, widgets2), true);
      });

      test('returns true for changed order', () {
        final widgets1 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        ];
        final widgets2 = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 5),
        ];

        expect(TestableWidgetChangeDetector.widgetsChanged(widgets1, widgets2), true);
      });

      test('returns false for empty lists', () {
        expect(TestableWidgetChangeDetector.widgetsChanged([], []), false);
      });
    });
  });

  // ============================================================================
  // VISIBLE WIDGETS FILTER TESTS
  // ============================================================================
  group('TestableVisibleWidgetsFilter', () {
    group('getVisibleWidgets', () {
      test('filters out invisible widgets', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'Visible', type: 't1', isVisible: true, order: 0),
          TestableMarketWidgetConfig(id: 'w2', name: 'Hidden', type: 't2', isVisible: false, order: 1),
          TestableMarketWidgetConfig(id: 'w3', name: 'Also Visible', type: 't3', isVisible: true, order: 2),
        ];

        final visible = TestableVisibleWidgetsFilter.getVisibleWidgets(widgets);

        expect(visible.length, 2);
        expect(visible.every((w) => w.isVisible), true);
      });

      test('sorts by order', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w3', name: 'Third', type: 't3', isVisible: true, order: 2),
          TestableMarketWidgetConfig(id: 'w1', name: 'First', type: 't1', isVisible: true, order: 0),
          TestableMarketWidgetConfig(id: 'w2', name: 'Second', type: 't2', isVisible: true, order: 1),
        ];

        final visible = TestableVisibleWidgetsFilter.getVisibleWidgets(widgets);

        expect(visible[0].id, 'w1');
        expect(visible[1].id, 'w2');
        expect(visible[2].id, 'w3');
      });

      test('returns empty for all hidden', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'Hidden', type: 't1', isVisible: false, order: 0),
        ];

        final visible = TestableVisibleWidgetsFilter.getVisibleWidgets(widgets);

        expect(visible, isEmpty);
      });
    });

    group('isWidgetVisible', () {
      test('returns true for visible widget', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 'banner', isVisible: true, order: 0),
        ];

        expect(TestableVisibleWidgetsFilter.isWidgetVisible(widgets, 'banner'), true);
      });

      test('returns false for hidden widget', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 'banner', isVisible: false, order: 0),
        ];

        expect(TestableVisibleWidgetsFilter.isWidgetVisible(widgets, 'banner'), false);
      });

      test('returns false for missing widget type', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 'banner', isVisible: true, order: 0),
        ];

        expect(TestableVisibleWidgetsFilter.isWidgetVisible(widgets, 'carousel'), false);
      });
    });

    group('getWidgetOrder', () {
      test('returns correct order', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 'banner', isVisible: true, order: 5),
        ];

        expect(TestableVisibleWidgetsFilter.getWidgetOrder(widgets, 'banner'), 5);
      });

      test('returns 999 for missing widget', () {
        final widgets = [
          TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 'banner', isVisible: true, order: 5),
        ];

        expect(TestableVisibleWidgetsFilter.getWidgetOrder(widgets, 'carousel'), 999);
      });
    });
  });

  // ============================================================================
  // LISTENER MANAGER TESTS
  // ============================================================================
  group('TestableListenerManager', () {
    late TestableListenerManager manager;

    setUp(() {
      manager = TestableListenerManager();
    });

    test('starts with no listeners', () {
      expect(manager.activeListeners, 0);
      expect(manager.hasSubscription, false);
    });

    test('startListening increments count', () {
      manager.startListening();
      expect(manager.activeListeners, 1);
    });

    test('first listener starts subscription', () {
      manager.startListening();
      expect(manager.hasSubscription, true);
    });

    test('second listener does not restart subscription', () {
      manager.startListening();
      manager.startListening();

      expect(manager.activeListeners, 2);
      expect(manager.hasSubscription, true);
    });

    test('stopListening decrements count', () {
      manager.startListening();
      manager.startListening();
      manager.stopListening();

      expect(manager.activeListeners, 1);
    });

    test('last listener stops subscription', () {
      manager.startListening();
      manager.stopListening();

      expect(manager.activeListeners, 0);
      expect(manager.hasSubscription, false);
    });

    test('stopListening does not go below zero', () {
      manager.stopListening();
      manager.stopListening();

      expect(manager.activeListeners, 0);
    });
  });

  // ============================================================================
  // DEFAULT WIDGETS TESTS
  // ============================================================================
  group('TestableDefaultWidgets', () {
    test('has 8 default widgets', () {
      expect(TestableDefaultWidgets.count, 8);
    });

    test('all defaults are visible', () {
      final widgets = TestableDefaultWidgets.defaultWidgets;
      expect(widgets.every((w) => w.isVisible), true);
    });

    test('all defaults have unique IDs', () {
      final ids = TestableDefaultWidgets.defaultWidgets.map((w) => w.id).toSet();
      expect(ids.length, 8);
    });

    test('all defaults have sequential orders', () {
      final widgets = TestableDefaultWidgets.defaultWidgets;
      for (int i = 0; i < widgets.length; i++) {
        expect(widgets[i].order, i);
      }
    });

    test('getDefaultByType finds widget', () {
      final banner = TestableDefaultWidgets.getDefaultByType('ads_banner');
      expect(banner, isNotNull);
      expect(banner!.id, 'ads_banner');
    });

    test('getDefaultByType returns null for unknown', () {
      final unknown = TestableDefaultWidgets.getDefaultByType('unknown_type');
      expect(unknown, null);
    });
  });

  // ============================================================================
  // REAL-WORLD SCENARIOS
  // ============================================================================
  group('Real-World Scenarios', () {
    test('market screen layout rendering order', () {
      final widgets = [
        TestableMarketWidgetConfig(id: 'banner', name: 'Banner', type: 'banner', isVisible: true, order: 2),
        TestableMarketWidgetConfig(id: 'carousel', name: 'Carousel', type: 'carousel', isVisible: true, order: 0),
        TestableMarketWidgetConfig(id: 'hidden', name: 'Hidden', type: 'hidden', isVisible: false, order: 1),
        TestableMarketWidgetConfig(id: 'list', name: 'List', type: 'list', isVisible: true, order: 3),
      ];

      final visible = TestableVisibleWidgetsFilter.getVisibleWidgets(widgets);

      // Should be sorted by order, with hidden removed
      expect(visible.length, 3);
      expect(visible[0].type, 'carousel'); // order 0
      expect(visible[1].type, 'banner');   // order 2
      expect(visible[2].type, 'list');     // order 3
    });

    test('admin reorders widgets', () {
      final before = [
        TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 0),
        TestableMarketWidgetConfig(id: 'w2', name: 'W2', type: 't2', isVisible: true, order: 1),
      ];

      final after = [
        TestableMarketWidgetConfig(id: 'w1', name: 'W1', type: 't1', isVisible: true, order: 1), // Changed
        TestableMarketWidgetConfig(id: 'w2', name: 'W2', type: 't2', isVisible: true, order: 0), // Changed
      ];

      expect(TestableWidgetChangeDetector.widgetsChanged(before, after), true);
    });

    test('corrupted Firestore data handled gracefully', () {
      final corruptedData = {
        'widgets': [
          null,
          'not a map',
          {'id': '', 'type': 'banner'}, // Empty ID
          {'id': 'valid', 'type': ''}, // Empty type
          {'id': 'good', 'type': 'banner', 'isVisible': true, 'order': 0},
          {'id': 'good', 'type': 'carousel', 'isVisible': true, 'order': 1}, // Duplicate ID
        ],
      };

      final widgets = TestableWidgetParser.parseWidgetsFromData(corruptedData);

      // Only the first 'good' widget should survive
      expect(widgets.length, 1);
      expect(widgets[0].id, 'good');
      expect(widgets[0].type, 'banner');
    });

    test('transient Firebase error triggers retry', () {
      expect(TestableRetryLogic.shouldRetry('unavailable'), true);
      expect(TestableRetryLogic.canRetry(0), true);
      expect(TestableRetryLogic.getRetryDelay(0), const Duration(seconds: 2));
    });

    test('permanent Firebase error does not retry', () {
      expect(TestableRetryLogic.shouldRetry('permission-denied'), false);
    });
  });
}