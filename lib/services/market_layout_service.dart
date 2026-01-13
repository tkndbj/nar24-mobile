import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

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
/// for the market screen. It handles Firestore synchronization, local caching,
/// and provides emergency reset capabilities.
class MarketLayoutService extends ChangeNotifier {
  static final MarketLayoutService _instance = MarketLayoutService._internal();
  factory MarketLayoutService() => _instance;
  MarketLayoutService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _layoutSubscription;

  List<MarketWidgetConfig> _widgets = [];
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Reference counting for subscription management
  int _activeListeners = 0;

  // Debounce timer to prevent rapid sequential operations
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Getters with null safety
  List<MarketWidgetConfig> get widgets => List.unmodifiable(_widgets);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  int get activeListeners => _activeListeners;
  bool get hasActiveSubscription => _layoutSubscription != null;

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

  /// Load layout from Firestore with retry logic
  Future<void> loadLayout({int retryCount = 0}) async {
    if (_isDisposed) return;

    try {
      final docRef = _firestore.collection('app_config').doc('market_layout');
      
      // Use source option for better offline support
      final docSnap = await docRef.get(const GetOptions(
        source: Source.serverAndCache,
      ));

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        final parsedWidgets = _parseWidgetsFromData(data);

        if (parsedWidgets.isNotEmpty) {
          _widgets = parsedWidgets;
          debugPrint('📦 Market layout loaded: ${_widgets.length} widgets');
        } else {
          debugPrint('⚠️ No valid widgets found, using defaults');
          _widgets = List.from(defaultWidgets);
        }
      } else {
        debugPrint('ℹ️ No configuration exists, using defaults');
        _widgets = List.from(defaultWidgets);
      }
    } on FirebaseException catch (e) {
      debugPrint('🔥 Firebase error loading layout: ${e.code} - ${e.message}');
      
      // Retry logic for transient errors
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

  /// Start listening with reference counting
  void startListening() {
    if (_isDisposed) {
      debugPrint('⚠️ Cannot start listening on disposed service');
      return;
    }

    _activeListeners++;
    debugPrint('👂 Active listeners: $_activeListeners');

    // Only start subscription if this is the first listener
    if (_activeListeners == 1 && _layoutSubscription == null) {
      _startFirestoreListener();
    }
  }

  /// Stop listening with reference counting
  void stopListening() {
    if (_activeListeners > 0) {
      _activeListeners--;
      debugPrint('👋 Active listeners: $_activeListeners');
    }

    // Only stop subscription when no one is listening
    if (_activeListeners == 0) {
      _debounceTimer?.cancel();
      if (_layoutSubscription != null) {
        _stopFirestoreListener();
      }
    }
  }

  /// Start Firestore real-time listener
  void _startFirestoreListener() {
    if (_isDisposed || _layoutSubscription != null) return;

    try {
      _layoutSubscription = _firestore
          .collection('app_config')
          .doc('market_layout')
          .snapshots(includeMetadataChanges: false)
          .listen(
        _handleSnapshot,
        onError: _handleSnapshotError,
        cancelOnError: false,
      );
      
      debugPrint('🎧 Firestore listener started');
    } catch (e) {
      debugPrint('❌ Error setting up listener: $e');
      _error = 'Failed to setup real-time updates';
      _safeNotifyListeners();
    }
  }

  /// Handle snapshot updates
  void _handleSnapshot(DocumentSnapshot snapshot) {
    if (_isDisposed) return;

    try {
      // Ignore metadata-only changes
      if (snapshot.metadata.hasPendingWrites) return;

      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint('⚠️ Snapshot has no data');
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final parsedWidgets = _parseWidgetsFromData(data);

      if (parsedWidgets.isEmpty) {
        debugPrint('⚠️ No valid widgets in snapshot');
        return;
      }

      // Check if widgets actually changed to avoid unnecessary rebuilds
      if (_widgetsChanged(parsedWidgets)) {
        _widgets = parsedWidgets;
        _error = null;
        
        // Debounce notifications to prevent rapid updates
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_debounceDuration, () {
          _safeNotifyListeners();
          debugPrint('🔄 Layout updated: ${_widgets.length} widgets');
        });
      }
    } catch (e) {
      debugPrint('❌ Error processing snapshot: $e');
      _error = 'Failed to process layout update';
      _safeNotifyListeners();
    }
  }

  /// Handle snapshot errors
  void _handleSnapshotError(Object error, StackTrace stackTrace) {
    if (_isDisposed) return;

    debugPrint('❌ Snapshot error: $error');
    _error = 'Connection error: ${error.toString()}';
    _safeNotifyListeners();

    // Attempt to restart listener on certain errors
    if (error is FirebaseException && _shouldRetry(error.code)) {
      debugPrint('🔄 Attempting to restart listener...');
      _stopFirestoreListener();
      Future.delayed(_retryDelay, () {
        if (!_isDisposed && _activeListeners > 0) {
          _startFirestoreListener();
        }
      });
    }
  }

  /// Check if widgets have actually changed
  bool _widgetsChanged(List<MarketWidgetConfig> newWidgets) {
    if (_widgets.length != newWidgets.length) return true;

    for (int i = 0; i < _widgets.length; i++) {
      if (_widgets[i] != newWidgets[i]) return true;
    }

    return false;
  }

  /// Stop Firestore listener
  void _stopFirestoreListener() {
    _layoutSubscription?.cancel();
    _layoutSubscription = null;
    debugPrint('🔇 Firestore listener stopped');
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

  /// Refresh layout manually
  Future<void> refresh() async {
    if (_isDisposed) return;

    try {
      _error = null;
      await loadLayout();
      _safeNotifyListeners();
      debugPrint('🔄 Layout refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing layout: $e');
      _error = 'Failed to refresh layout';
      _safeNotifyListeners();
    }
  }

  /// 🚨 EMERGENCY: Reset to default configuration
  /// This will reset both local state and Firestore to defaults
  Future<void> emergencyReset() async {
    if (_isDisposed) return;

    try {
      debugPrint('🚨 EMERGENCY RESET initiated');
      
      // Stop all listeners
      _stopFirestoreListener();
      _debounceTimer?.cancel();
      
      // Reset local state
      _widgets = List.from(defaultWidgets);
      _error = null;
      _isLoading = false;
      
      // Reset Firestore
      final docRef = _firestore.collection('app_config').doc('market_layout');
      await docRef.set({
        'widgets': defaultWidgets.map((w) => w.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'resetReason': 'Emergency reset',
        'version': DateTime.now().millisecondsSinceEpoch,
      });

      // Restart listeners if needed
      if (_activeListeners > 0) {
        _startFirestoreListener();
      }

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
✓ Active Listeners: $_activeListeners
✓ Has Subscription: $hasActiveSubscription
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
    _debounceTimer?.cancel();
    _stopFirestoreListener();
    _activeListeners = 0;
    
    super.dispose();
  }
}