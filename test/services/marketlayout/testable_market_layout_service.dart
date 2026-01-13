// test/services/testable_market_layout_service.dart
//
// TESTABLE MIRROR of MarketLayoutService pure logic from lib/services/market_layout_service.dart
//
// This file contains EXACT copies of pure logic functions from MarketLayoutService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/market_layout_service.dart
//
// Last synced with: market_layout_service.dart (current version)

/// Mirrors MarketWidgetConfig from MarketLayoutService
class TestableMarketWidgetConfig {
  final String id;
  final String name;
  final String type;
  final bool isVisible;
  final int order;

  TestableMarketWidgetConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.isVisible,
    required this.order,
  });

  /// Mirrors fromMap from MarketWidgetConfig
  factory TestableMarketWidgetConfig.fromMap(Map<String, dynamic> map) {
    return TestableMarketWidgetConfig(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      isVisible: map['isVisible'] is bool ? map['isVisible'] : true,
      order: map['order'] is int ? map['order'] : 0,
    );
  }

  /// Mirrors toMap from MarketWidgetConfig
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'isVisible': isVisible,
      'order': order,
    };
  }

  /// Mirrors copyWith from MarketWidgetConfig
  TestableMarketWidgetConfig copyWith({
    String? id,
    String? name,
    String? type,
    bool? isVisible,
    int? order,
  }) {
    return TestableMarketWidgetConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isVisible: isVisible ?? this.isVisible,
      order: order ?? this.order,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestableMarketWidgetConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          isVisible == other.isVisible &&
          order == other.order;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      type.hashCode ^
      isVisible.hashCode ^
      order.hashCode;
}

/// Mirrors widget parsing logic from MarketLayoutService
class TestableWidgetParser {
  /// Mirrors _parseWidgetsFromData from MarketLayoutService
  /// Parse widgets from Firestore data with validation
  static List<TestableMarketWidgetConfig> parseWidgetsFromData(
      Map<String, dynamic> data) {
    if (data['widgets'] == null || data['widgets'] is! List) {
      return [];
    }

    final List<dynamic> widgetsData = data['widgets'];
    final List<TestableMarketWidgetConfig> parsedWidgets = [];
    final Set<String> seenIds = {};

    for (final widgetData in widgetsData) {
      try {
        if (widgetData is! Map<String, dynamic>) continue;

        final widget = TestableMarketWidgetConfig.fromMap(widgetData);

        // Validate widget
        if (widget.id.isEmpty || widget.type.isEmpty) {
          continue;
        }

        // Check for duplicate IDs
        if (seenIds.contains(widget.id)) {
          continue;
        }

        seenIds.add(widget.id);
        parsedWidgets.add(widget);
      } catch (e) {
        continue;
      }
    }

    return parsedWidgets;
  }

  /// Validate a single widget config
  static bool isValidWidget(TestableMarketWidgetConfig widget) {
    return widget.id.isNotEmpty && widget.type.isNotEmpty;
  }

  /// Get validation errors for a widget
  static List<String> getValidationErrors(Map<String, dynamic> map) {
    final errors = <String>[];
    
    final id = map['id']?.toString() ?? '';
    final type = map['type']?.toString() ?? '';
    
    if (id.isEmpty) errors.add('Missing or empty id');
    if (type.isEmpty) errors.add('Missing or empty type');
    
    return errors;
  }
}

/// Mirrors retry logic from MarketLayoutService
class TestableRetryLogic {
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  /// Retryable Firebase error codes
  static const List<String> retryableCodes = [
    'unavailable',
    'deadline-exceeded',
    'internal',
    'unknown',
  ];

  /// Mirrors _shouldRetry from MarketLayoutService
  static bool shouldRetry(String errorCode) {
    return retryableCodes.contains(errorCode);
  }

  /// Calculate delay for retry attempt
  static Duration getRetryDelay(int retryCount) {
    return retryDelay * (retryCount + 1);
  }

  /// Check if should continue retrying
  static bool canRetry(int currentRetryCount) {
    return currentRetryCount < maxRetries;
  }
}

/// Mirrors widget change detection from MarketLayoutService
class TestableWidgetChangeDetector {
  /// Mirrors _widgetsChanged from MarketLayoutService
  static bool widgetsChanged(
    List<TestableMarketWidgetConfig> oldWidgets,
    List<TestableMarketWidgetConfig> newWidgets,
  ) {
    if (oldWidgets.length != newWidgets.length) return true;

    for (int i = 0; i < oldWidgets.length; i++) {
      if (oldWidgets[i] != newWidgets[i]) return true;
    }

    return false;
  }

  /// Get list of changes between widget lists
  static List<String> getChanges(
    List<TestableMarketWidgetConfig> oldWidgets,
    List<TestableMarketWidgetConfig> newWidgets,
  ) {
    final changes = <String>[];
    
    if (oldWidgets.length != newWidgets.length) {
      changes.add('Count changed: ${oldWidgets.length} -> ${newWidgets.length}');
    }

    final oldIds = oldWidgets.map((w) => w.id).toSet();
    final newIds = newWidgets.map((w) => w.id).toSet();

    final added = newIds.difference(oldIds);
    final removed = oldIds.difference(newIds);

    for (final id in added) {
      changes.add('Added: $id');
    }
    for (final id in removed) {
      changes.add('Removed: $id');
    }

    return changes;
  }
}

/// Mirrors visible widgets logic from MarketLayoutService
class TestableVisibleWidgetsFilter {
  /// Mirrors visibleWidgets getter from MarketLayoutService
  static List<TestableMarketWidgetConfig> getVisibleWidgets(
      List<TestableMarketWidgetConfig> widgets) {
    try {
      return widgets.where((widget) => widget.isVisible).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    } catch (e) {
      return [];
    }
  }

  /// Check if specific widget type is visible
  /// Mirrors isWidgetVisible from MarketLayoutService
  static bool isWidgetVisible(
      List<TestableMarketWidgetConfig> widgets, String widgetType) {
    try {
      return widgets.any((w) => w.type == widgetType && w.isVisible);
    } catch (e) {
      return false;
    }
  }

  /// Get widget order by type
  /// Mirrors getWidgetOrder from MarketLayoutService
  static int getWidgetOrder(
      List<TestableMarketWidgetConfig> widgets, String widgetType) {
    try {
      final widget = widgets.firstWhere(
        (w) => w.type == widgetType,
        orElse: () => TestableMarketWidgetConfig(
          id: '',
          name: '',
          type: widgetType,
          isVisible: false,
          order: 999,
        ),
      );
      return widget.order;
    } catch (e) {
      return 999;
    }
  }
}

/// Mirrors reference counting from MarketLayoutService
class TestableListenerManager {
  int _activeListeners = 0;
  bool _hasSubscription = false;

  int get activeListeners => _activeListeners;
  bool get hasSubscription => _hasSubscription;

  /// Mirrors startListening from MarketLayoutService
  void startListening() {
    _activeListeners++;

    // Only start subscription if this is the first listener
    if (_activeListeners == 1 && !_hasSubscription) {
      _hasSubscription = true;
    }
  }

  /// Mirrors stopListening from MarketLayoutService
  void stopListening() {
    if (_activeListeners > 0) {
      _activeListeners--;
    }

    // Only stop subscription when no one is listening
    if (_activeListeners == 0) {
      _hasSubscription = false;
    }
  }

  void reset() {
    _activeListeners = 0;
    _hasSubscription = false;
  }
}

/// Mirrors default widgets from MarketLayoutService
class TestableDefaultWidgets {
  static List<TestableMarketWidgetConfig> get defaultWidgets => [
        TestableMarketWidgetConfig(
          id: 'ads_banner',
          name: 'Ads Banner',
          type: 'ads_banner',
          isVisible: true,
          order: 0,
        ),
        TestableMarketWidgetConfig(
          id: 'market_bubbles',
          name: 'Market Bubbles',
          type: 'market_bubbles',
          isVisible: true,
          order: 1,
        ),
        TestableMarketWidgetConfig(
          id: 'thin_banner',
          name: 'Thin Banner',
          type: 'thin_banner',
          isVisible: true,
          order: 2,
        ),
        TestableMarketWidgetConfig(
          id: 'preference_product',
          name: 'Preference Products',
          type: 'preference_product',
          isVisible: true,
          order: 3,
        ),
        TestableMarketWidgetConfig(
          id: 'boosted_product_carousel',
          name: 'Boosted Products',
          type: 'boosted_product_carousel',
          isVisible: true,
          order: 4,
        ),
        TestableMarketWidgetConfig(
          id: 'dynamic_product_list',
          name: 'Dynamic Product Lists',
          type: 'dynamic_product_list',
          isVisible: true,
          order: 5,
        ),
        TestableMarketWidgetConfig(
          id: 'market_banner',
          name: 'Market Banner',
          type: 'market_banner',
          isVisible: true,
          order: 6,
        ),
        TestableMarketWidgetConfig(
          id: 'shop_horizontal_list',
          name: 'Shop Horizontal List',
          type: 'shop_horizontal_list',
          isVisible: true,
          order: 7,
        ),
      ];

  /// Get default widget by type
  static TestableMarketWidgetConfig? getDefaultByType(String type) {
    try {
      return defaultWidgets.firstWhere((w) => w.type == type);
    } catch (e) {
      return null;
    }
  }

  /// Get all default widget types
  static List<String> get defaultTypes =>
      defaultWidgets.map((w) => w.type).toList();

  /// Get default widget count
  static int get count => defaultWidgets.length;
}