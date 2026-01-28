import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// Widget configuration model
class MarketWidgetConfig {
  final String id;
  final String name;
  final String type;
  final bool isVisible;
  final int order;

  MarketWidgetConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.isVisible,
    required this.order,
  });

  factory MarketWidgetConfig.fromMap(Map<String, dynamic> map) {
    return MarketWidgetConfig(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      isVisible: map['isVisible'] is bool ? map['isVisible'] : true,
      order: map['order'] is int ? map['order'] : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'isVisible': isVisible,
      'order': order,
    };
  }

  MarketWidgetConfig copyWith({
    String? id,
    String? name,
    String? type,
    bool? isVisible,
    int? order,
  }) {
    return MarketWidgetConfig(
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
      other is MarketWidgetConfig &&
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

/// Layout service to manage market screen layout
/// 
/// This is a singleton service that manages the dynamic layout configuration
/// for the market screen. It handles Firestore synchronization with one-time
/// fetch (no real-time listeners to minimize reads).
class MarketLayoutService extends ChangeNotifier {
  static final MarketLayoutService _instance = MarketLayoutService._internal();
  factory MarketLayoutService() => _instance;
  MarketLayoutService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<MarketWidgetConfig> _widgets = [];
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Firestore document paths
  static const String _collectionPath = 'app_config';
  static const String _docFlutter = 'market_layout_flutter'; // Flutter-specific (priority)
  static const String _docShared = 'market_layout'; // Shared/fallback

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Getters
  List<MarketWidgetConfig> get widgets => List.unmodifiable(_widgets);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

  /// Get visible widgets sorted by order
  List<MarketWidgetConfig> get visibleWidgets {
    try {
      return _widgets.where((widget) => widget.isVisible).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    } catch (e) {
      debugPrint('Error getting visible widgets: $e');
      return [];
    }
  }

  /// Default widget configuration
  static List<MarketWidgetConfig> get defaultWidgets => [
        MarketWidgetConfig(
          id: 'ads_banner',
          name: 'Ads Banner',
          type: 'ads_banner',
          isVisible: true,
          order: 0,
        ),
        MarketWidgetConfig(
          id: 'market_bubbles',
          name: 'Market Bubbles',
          type: 'market_bubbles',
          isVisible: true,
          order: 1,
        ),
        MarketWidgetConfig(
          id: 'thin_banner',
          name: 'Thin Banner',
          type: 'thin_banner',
          isVisible: true,
          order: 2,
        ),
        MarketWidgetConfig(
          id: 'preference_product',
          name: 'Preference Products',
          type: 'preference_product',
          isVisible: true,
          order: 3,
        ),
        MarketWidgetConfig(
          id: 'boosted_product_carousel',
          name: 'Boosted Products',
          type: 'boosted_product_carousel',
          isVisible: true,
          order: 4,
        ),
        MarketWidgetConfig(
          id: 'dynamic_product_list',
          name: 'Dynamic Product Lists',
          type: 'dynamic_product_list',
          isVisible: true,
          order: 5,
        ),
        MarketWidgetConfig(
          id: 'market_banner',
          name: 'Market Banner',
          type: 'market_banner',
          isVisible: true,
          order: 6,
        ),
        MarketWidgetConfig(
          id: 'shop_horizontal_list',
          name: 'Shop Horizontal List',
          type: 'shop_horizontal_list',
          isVisible: true,
          order: 7,
        ),
      ];

  /// Initialize the service
  /// Safe to call multiple times - will only initialize once
  Future<void> initialize() async {
    if (_isDisposed) {
      debugPrint('⚠️ Cannot initialize disposed service');
      return;
    }

    if (_isInitialized) {
      debugPrint('ℹ️ MarketLayoutService already initialized');
      return;
    }

    try {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();

      await loadLayout();
      _isInitialized = true;
      debugPrint('✅ MarketLayoutService initialized successfully');
    } catch (e) {
      _error = 'Initialization failed: ${e.toString()}';
      debugPrint('❌ Error initializing market layout: $e');
      // Fallback to defaults on error
      _widgets = List.from(defaultWidgets);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Load layout from Firestore (one-time fetch with retry logic)
  /// Priority: flutter-specific → shared → defaults
  Future<void> loadLayout({int retryCount = 0}) async {
    if (_isDisposed) return;

    try {
      // ========================================
      // 1. Try flutter-specific document first
      // ========================================
      final flutterDocRef = _firestore.collection(_collectionPath).doc(_docFlutter);

      var docSnap = await flutterDocRef.get(const GetOptions(
        source: Source.serverAndCache,
      ));

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        final parsedWidgets = _parseWidgetsFromData(data);

        if (parsedWidgets.isNotEmpty) {
          _widgets = parsedWidgets;
          debugPrint('📦 Market layout loaded from flutter-specific: ${_widgets.length} widgets');
          return;
        }
      }

      // ========================================
      // 2. Fallback to shared document
      // ========================================
      debugPrint('⚠️ No flutter-specific layout, trying shared fallback...');

      final sharedDocRef = _firestore.collection(_collectionPath).doc(_docShared);
      docSnap = await sharedDocRef.get(const GetOptions(
        source: Source.serverAndCache,
      ));

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        final parsedWidgets = _parseWidgetsFromData(data);

        if (parsedWidgets.isNotEmpty) {
          _widgets = parsedWidgets;
          debugPrint('📦 Market layout loaded from shared: ${_widgets.length} widgets');
          return;
        }
      }

      // ========================================
      // 3. No config found, use defaults
      // ========================================
      debugPrint('ℹ️ No configuration exists, using defaults');
      _widgets = List.from(defaultWidgets);

    } on FirebaseException catch (e) {
      debugPrint('🔥 Firebase error loading layout: ${e.code} - ${e.message}');

      if (retryCount < _maxRetries && _shouldRetry(e.code)) {
        debugPrint('🔄 Retrying... (${retryCount + 1}/$_maxRetries)');
        await Future.delayed(_retryDelay * (retryCount + 1));
        return loadLayout(retryCount: retryCount + 1);
      }

      _widgets = List.from(defaultWidgets);
      rethrow;
    } catch (e) {
      debugPrint('❌ Unexpected error loading layout: $e');
      _widgets = List.from(defaultWidgets);
      rethrow;
    }
  }

  /// Parse widgets from Firestore data with validation
  List<MarketWidgetConfig> _parseWidgetsFromData(Map<String, dynamic> data) {
    if (data['widgets'] == null || data['widgets'] is! List) {
      return [];
    }

    final List<dynamic> widgetsData = data['widgets'];
    final List<MarketWidgetConfig> parsedWidgets = [];
    final Set<String> seenIds = {};

    for (final widgetData in widgetsData) {
      try {
        if (widgetData is! Map<String, dynamic>) continue;

        final widget = MarketWidgetConfig.fromMap(widgetData);

        // Validate widget
        if (widget.id.isEmpty || widget.type.isEmpty) {
          debugPrint('⚠️ Skipping invalid widget: empty id or type');
          continue;
        }

        // Check for duplicate IDs
        if (seenIds.contains(widget.id)) {
          debugPrint('⚠️ Skipping duplicate widget ID: ${widget.id}');
          continue;
        }

        seenIds.add(widget.id);
        parsedWidgets.add(widget);
      } catch (e) {
        debugPrint('⚠️ Error parsing widget: $e');
        continue;
      }
    }

    return parsedWidgets;
  }

  /// Determine if error should trigger retry
  bool _shouldRetry(String errorCode) {
    const retryableCodes = [
      'unavailable',
      'deadline-exceeded',
      'internal',
      'unknown',
    ];
    return retryableCodes.contains(errorCode);
  }

  /// Check if a specific widget is visible
  bool isWidgetVisible(String widgetType) {
    if (_isDisposed) return false;

    try {
      return _widgets.any((w) => w.type == widgetType && w.isVisible);
    } catch (e) {
      debugPrint('⚠️ Error checking visibility: $e');
      return false;
    }
  }

  /// Get widget order
  int getWidgetOrder(String widgetType) {
    if (_isDisposed) return 999;

    try {
      final widget = _widgets.firstWhere(
        (w) => w.type == widgetType,
        orElse: () => MarketWidgetConfig(
          id: '',
          name: '',
          type: widgetType,
          isVisible: false,
          order: 999,
        ),
      );
      return widget.order;
    } catch (e) {
      debugPrint('⚠️ Error getting widget order: $e');
      return 999;
    }
  }

  /// Refresh layout manually (re-fetches from Firestore)
  Future<void> refresh() async {
    if (_isDisposed) return;

    try {
      _isLoading = true;
      _error = null;
      _safeNotifyListeners();

      await loadLayout();
      debugPrint('🔄 Layout refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing layout: $e');
      _error = 'Failed to refresh layout';
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// 🚨 EMERGENCY: Reset to default configuration
  /// This will reset both local state and Firestore to defaults
  Future<void> emergencyReset() async {
    if (_isDisposed) return;

    try {
      debugPrint('🚨 EMERGENCY RESET initiated');

      // Reset local state
      _widgets = List.from(defaultWidgets);
      _error = null;
      _isLoading = false;

      // Reset Firestore (flutter-specific document)
      final docRef = _firestore.collection(_collectionPath).doc(_docFlutter);
      await docRef.set({
        'widgets': defaultWidgets.map((w) => w.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'resetReason': 'Emergency reset',
        'version': DateTime.now().millisecondsSinceEpoch,
      });

      _safeNotifyListeners();
      debugPrint('✅ Emergency reset completed');
    } catch (e) {
      debugPrint('❌ Emergency reset failed: $e');
      // Still update local state even if Firestore update fails
      _widgets = List.from(defaultWidgets);
      _safeNotifyListeners();
    }
  }

  /// 🔧 Reset only local state (keeps Firestore unchanged)
  void resetLocalState() {
    if (_isDisposed) return;

    debugPrint('🔧 Resetting local state');
    _widgets = List.from(defaultWidgets);
    _error = null;
    _safeNotifyListeners();
  }

  /// Safe notification that checks disposal state
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Debug service state
  void debugServiceState() {
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 MarketLayoutService State
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Initialized: $_isInitialized
✓ Loading: $_isLoading
✓ Error: ${_error ?? 'None'}
✓ Disposed: $_isDisposed
✓ Widgets Count: ${_widgets.length}
✓ Visible Widgets: ${visibleWidgets.length}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ''');
  }

  @override
  void dispose() {
    if (_isDisposed) return;

    debugPrint('🧹 Disposing MarketLayoutService');
    _isDisposed = true;
    super.dispose();
  }
}