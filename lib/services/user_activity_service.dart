// lib/services/user_activity_service.dart
// Production-ready user activity tracking with batching, persistence, and non-blocking writes

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Event types for user activity tracking
enum ActivityType {
  // Product interactions
  click,        // Weight: 1 - Clicked from list
  view,         // Weight: 2 - Viewed product detail (>3s)
  
  // Purchase intent signals
  addToCart,    // Weight: 5 - Strong purchase intent
  removeFromCart, // Weight: -2 - Changed mind
  
  // Engagement signals
  favorite,     // Weight: 3 - Interest saved
  unfavorite,   // Weight: -1 - Lost interest
  
  // Conversion signals
  purchase,     // Weight: 10 - Strongest signal
  
  // Discovery signals
  search,       // Weight: 1 - Intent indicator
}

/// Weights for scoring user preferences
const Map<ActivityType, int> activityWeights = {
  ActivityType.click: 1,
  ActivityType.view: 2,
  ActivityType.addToCart: 5,
  ActivityType.removeFromCart: -2,
  ActivityType.favorite: 3,
  ActivityType.unfavorite: -1,
  ActivityType.purchase: 10,
  ActivityType.search: 1,
};

/// Single activity event
class ActivityEvent {
  final String eventId;
  final ActivityType type;
  final DateTime timestamp;
  final String? productId;
  final String? shopId;
  final String? productName;
  final String? category;
  final String? subcategory;
  final String? subsubcategory;
  final String? gender;
  final String? brand;
  final double? price;
  final String? searchQuery;
  final String? source; // 'search', 'category', 'recommendation', 'trending', 'direct'
  final int? quantity;
  final double? totalValue;
  final Map<String, dynamic>? extra;

  ActivityEvent({
    required this.eventId,
    required this.type,
    required this.timestamp,
    this.productId,
    this.shopId,
    this.productName,
    this.category,
    this.subcategory,
    this.subsubcategory,
    this.gender,
    this.brand,
    this.price,
    this.searchQuery,
    this.source,
    this.quantity,
    this.totalValue,
    this.extra,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'eventId': eventId,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'weight': activityWeights[type] ?? 0,
    };

    if (productId != null) map['productId'] = productId;
    if (productName != null) map['productName'] = productName;
    if (shopId != null) map['shopId'] = shopId;
    if (category != null) map['category'] = category;
    if (subcategory != null) map['subcategory'] = subcategory;
    if (subsubcategory != null) map['subsubcategory'] = subsubcategory;
    if (brand != null) map['brand'] = brand;
    if (gender != null) map['gender'] = gender;
    if (price != null) map['price'] = price;
    if (searchQuery != null) map['searchQuery'] = searchQuery;
    if (source != null) map['source'] = source;
    if (quantity != null) map['quantity'] = quantity;
    if (totalValue != null) map['totalValue'] = totalValue;
    if (extra != null && extra!.isNotEmpty) map['extra'] = extra;

    return map;
  }

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      eventId: json['eventId'] as String,
      type: ActivityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ActivityType.click,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      productId: json['productId'] as String?,
      shopId: json['shopId'] as String?,
      productName: json['productName'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      subsubcategory: json['subsubcategory'] as String?,
      brand: json['brand'] as String?,
      gender: json['gender'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      searchQuery: json['searchQuery'] as String?,
      source: json['source'] as String?,
      quantity: json['quantity'] as int?,
      totalValue: (json['totalValue'] as num?)?.toDouble(),
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
}

/// Production-ready User Activity Service
/// 
/// Features:
/// - Batched writes (reduces Firestore operations by 90%+)
/// - Local persistence (survives app crashes/restarts)
/// - Deduplication (prevents spam from rapid taps)
/// - Non-blocking (never blocks UI thread)
/// - Offline support (queues events when offline)
/// - Circuit breaker (backs off on repeated failures)
class UserActivityService {
  static UserActivityService? _instance;
  static UserActivityService get instance {
    _instance ??= UserActivityService._internal();
    return _instance!;
  }

  UserActivityService._internal();

  // Configuration
  static const int _maxQueueSize = 50;
  static const int _flushThreshold = 20;
  static const Duration _flushInterval = Duration(seconds: 30);
  static const Duration _dedupeWindow = Duration(seconds: 2);
  static const String _storageKey = 'pending_user_activities';
  static const int _maxRetries = 3;
  static const Duration _circuitBreakerCooldown = Duration(minutes: 5);

  // State
  final List<ActivityEvent> _queue = [];
  final Map<String, DateTime> _recentEvents = {}; // For deduplication
  Timer? _flushTimer;
  bool _isFlushing = false;
  bool _isInitialized = false;
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTime;
  SharedPreferences? _prefs;
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = true;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Initialize the service (call once at app startup)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedEvents();
      _startFlushTimer();
      _setupConnectivityListener();
      _isInitialized = true;
      debugPrint('✅ UserActivityService initialized with ${_queue.length} pending events');
    } catch (e) {
      debugPrint('❌ UserActivityService initialization error: $e');
    }
  }

  /// Setup connectivity listener for offline support
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = result != ConnectivityResult.none;
      
      // Flush when coming back online
      if (wasOffline && _isOnline && _queue.isNotEmpty) {
        debugPrint('📶 Back online, flushing ${_queue.length} pending events');
        _flushQueue();
      }
    });
  }

  /// Load persisted events from SharedPreferences
  Future<void> _loadPersistedEvents() async {
    try {
      final stored = _prefs?.getString(_storageKey);
      if (stored != null && stored.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(stored);
        final events = decoded
            .map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        
        // Only load events from last 24 hours
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        _queue.addAll(events.where((e) => e.timestamp.isAfter(cutoff)));
        
        debugPrint('📥 Loaded ${_queue.length} persisted events');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading persisted events: $e');
      // Clear corrupted data
      await _prefs?.remove(_storageKey);
    }
  }

  /// Persist events to SharedPreferences
  Future<void> _persistEvents() async {
    if (_queue.isEmpty) {
      await _prefs?.remove(_storageKey);
      return;
    }

    try {
      final encoded = jsonEncode(_queue.map((e) => e.toJson()).toList());
      await _prefs?.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('⚠️ Error persisting events: $e');
    }
  }

  /// Start the periodic flush timer
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      if (_queue.isNotEmpty) {
        _flushQueue();
      }
    });
  }

  /// Check if circuit breaker is open (too many failures)
  bool get _isCircuitBreakerOpen {
    if (_consecutiveFailures < _maxRetries) return false;
    if (_lastFailureTime == null) return false;
    
    final elapsed = DateTime.now().difference(_lastFailureTime!);
    if (elapsed > _circuitBreakerCooldown) {
      // Reset circuit breaker
      _consecutiveFailures = 0;
      _lastFailureTime = null;
      return false;
    }
    return true;
  }

  /// Generate a unique event ID
  String _generateEventId(ActivityType type, String? productId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 10000;
    return '${type.name}_${productId ?? 'none'}_${timestamp}_$random';
  }

  /// Check for duplicate events (prevents spam from rapid taps)
  bool _isDuplicate(ActivityType type, String? productId) {
    final key = '${type.name}_${productId ?? 'none'}';
    final lastTime = _recentEvents[key];
    
    if (lastTime != null) {
      final elapsed = DateTime.now().difference(lastTime);
      if (elapsed < _dedupeWindow) {
        return true;
      }
    }
    
    _recentEvents[key] = DateTime.now();
    
    // Cleanup old entries
    if (_recentEvents.length > 100) {
      final cutoff = DateTime.now().subtract(_dedupeWindow);
      _recentEvents.removeWhere((_, time) => time.isBefore(cutoff));
    }
    
    return false;
  }

  // ============================================================================
  // PUBLIC API - Non-blocking event tracking methods
  // ============================================================================

  /// Track a product click (from list view)
  void trackClick({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? gender,
    String? brand,
    double? price,
    String? source,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.click, productId),
      type: ActivityType.click,
      timestamp: DateTime.now(),
      productId: productId,
      shopId: shopId,
      productName: productName,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      gender: gender,
      brand: brand,
      price: price,
      source: source,
    ));
  }

  /// Track a product view (detail page, >3s viewing time)
  void trackView({
    required String productId,
    String? shopId,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? brand,
    String? gender,
    double? price,
    String? source,
    int? viewDurationSeconds,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.view, productId),
      type: ActivityType.view,
      timestamp: DateTime.now(),
      productId: productId,
      shopId: shopId,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      brand: brand,
      gender: gender,
      price: price,
      source: source,
      extra: viewDurationSeconds != null ? {'viewDuration': viewDurationSeconds} : null,
    ));
  }

  /// Track add to cart
  void trackAddToCart({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? gender,
    String? brand,
    double? price,
    int quantity = 1,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.addToCart, productId),
      type: ActivityType.addToCart,
      timestamp: DateTime.now(),
      productId: productId,
      productName: productName,
      shopId: shopId,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      gender: gender,
      brand: brand,
      price: price,
      quantity: quantity,
    ));
  }

  /// Track remove from cart
  void trackRemoveFromCart({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? gender,
    String? brand,
    double? price,
    int quantity = 1,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.removeFromCart, productId),
      type: ActivityType.removeFromCart,
      timestamp: DateTime.now(),
      productId: productId,
      productName: productName,
      shopId: shopId,
      category: category,
      gender: gender,
      brand: brand,
      price: price,
      quantity: quantity,
    ));
  }

  /// Track add to favorites
  void trackFavorite({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? gender,
    String? brand,
    double? price,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.favorite, productId),
      type: ActivityType.favorite,
      timestamp: DateTime.now(),
      productId: productId,
      productName: productName,
      shopId: shopId,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      gender: gender,
      brand: brand,
      price: price,
    ));
  }

  /// Track remove from favorites
  void trackUnfavorite({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? gender,
    String? brand,
    double? price,
  }) {
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.unfavorite, productId),
      type: ActivityType.unfavorite,
      timestamp: DateTime.now(),
      productId: productId,
      productName: productName,
      shopId: shopId,
      category: category,
      gender: gender,
      brand: brand,
      price: price,
    ));
  }

  /// Track purchase (call for each item in order)
  void trackPurchase({
    required String productId,
    String? shopId,
    String? productName,
    String? category,
    String? subcategory,
    String? subsubcategory,
    String? brand,
    required double price,
    required int quantity,
    required double totalValue,
    String? orderId,
  }) {
    // Don't dedupe purchases - each one is unique
    final event = ActivityEvent(
      eventId: _generateEventId(ActivityType.purchase, productId),
      type: ActivityType.purchase,
      timestamp: DateTime.now(),
      productId: productId,
      productName: productName,
      shopId: shopId,
      category: category,
      subcategory: subcategory,
      subsubcategory: subsubcategory,
      brand: brand,
      price: price,
      quantity: quantity,
      totalValue: totalValue,
      extra: orderId != null ? {'orderId': orderId} : null,
    );
    
    _queue.add(event);
    _checkFlushThreshold();
  }

  /// Track search query
  void trackSearch({
    required String query,
    int? resultCount,
    String? selectedCategory,
  }) {
    if (query.trim().isEmpty) return;
    
    _queueEvent(ActivityEvent(
      eventId: _generateEventId(ActivityType.search, query.hashCode.toString()),
      type: ActivityType.search,
      timestamp: DateTime.now(),
      searchQuery: query.trim().toLowerCase(),
      category: selectedCategory,
      extra: resultCount != null ? {'resultCount': resultCount} : null,
    ));
  }

  // ============================================================================
  // INTERNAL QUEUE MANAGEMENT
  // ============================================================================

  /// Add event to queue with deduplication
  void _queueEvent(ActivityEvent event) {
    // Skip if not initialized
    if (!_isInitialized) {
      debugPrint('⚠️ UserActivityService not initialized, skipping event');
      return;
    }

    // Skip if no user (anonymous tracking could be added later)
    if (_auth.currentUser == null) {
      return;
    }

    // Skip duplicates (except purchases)
    if (event.type != ActivityType.purchase && 
        _isDuplicate(event.type, event.productId ?? event.searchQuery)) {
      debugPrint('⏭️ Skipping duplicate ${event.type.name} event');
      return;
    }

    // Enforce max queue size (drop oldest if full)
    if (_queue.length >= _maxQueueSize) {
      _queue.removeAt(0);
      debugPrint('⚠️ Queue full, dropped oldest event');
    }

    _queue.add(event);
    _checkFlushThreshold();
  }

  /// Check if we should flush based on queue size
  void _checkFlushThreshold() {
    if (_queue.length >= _flushThreshold) {
      _flushQueue();
    } else {
      // Persist to survive crashes
      _persistEvents();
    }
  }

  /// Flush the queue to the server
  Future<void> _flushQueue() async {
    if (_isFlushing || _queue.isEmpty) return;
    if (!_isOnline) {
      debugPrint('📵 Offline, deferring flush');
      return;
    }
    if (_isCircuitBreakerOpen) {
      debugPrint('🔴 Circuit breaker open, deferring flush');
      return;
    }

    _isFlushing = true;
    final user = _auth.currentUser;
    
    if (user == null) {
      _isFlushing = false;
      return;
    }

    // Take a snapshot of events to send
    final eventsToSend = List<ActivityEvent>.from(_queue);
    final eventCount = eventsToSend.length;

    try {
      debugPrint('📤 Flushing $eventCount activity events...');

      final callable = _functions.httpsCallable(
        'batchUserActivity',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call({
        'events': eventsToSend.map((e) => e.toJson()).toList(),
        'clientTimestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Success - clear sent events
      _queue.removeWhere((e) => eventsToSend.contains(e));
      await _persistEvents();
      
      _consecutiveFailures = 0;
      _lastFailureTime = null;
      
      debugPrint('✅ Flushed $eventCount activity events');
    } catch (e) {
      debugPrint('❌ Failed to flush activity events: $e');
      
      _consecutiveFailures++;
      _lastFailureTime = DateTime.now();
      
      // Don't remove events on failure - they'll be retried
      await _persistEvents();
    } finally {
      _isFlushing = false;
    }
  }

  /// Force flush (call on app pause/background)
  Future<void> forceFlush() async {
    if (_queue.isNotEmpty) {
      await _flushQueue();
    }
  }

  /// Cleanup (call on logout)
  void clearUserData() {
    _queue.clear();
    _recentEvents.clear();
    _prefs?.remove(_storageKey);
    debugPrint('🧹 Cleared user activity data');
  }

  /// Dispose (call on app termination)
  void dispose() {
    _flushTimer?.cancel();
    _connectivitySubscription?.cancel();
    _persistEvents(); // Save any pending events
    _isInitialized = false;
  }

  // ============================================================================
  // CONVENIENCE METHODS FOR INTEGRATION
  // ============================================================================

  /// Track from Product object (convenience method)
  void trackProductClick(dynamic product, {String? source}) {
    try {
      trackClick(
        productId: product.id as String,
        shopId: product.shopId as String?,
        category: product.category as String?,
        subcategory: product.subcategory as String?,
        subsubcategory: product.subsubcategory as String?,
        gender: product.gender as String?,
        brand: product.brandModel as String?,
        price: (product.price as num?)?.toDouble(),
        source: source,
      );
    } catch (e) {
      debugPrint('⚠️ Error tracking product click: $e');
    }
  }

  /// Track from Product object (convenience method)
  void trackProductView(dynamic product, {String? source, int? viewDuration}) {
    try {
      trackView(
        productId: product.id as String,
        shopId: product.shopId as String?,
        category: product.category as String?,
        subcategory: product.subcategory as String?,
        subsubcategory: product.subsubcategory as String?,
        gender: product.gender as String?,
        brand: product.brandModel as String?,
        price: (product.price as num?)?.toDouble(),
        source: source,
        viewDurationSeconds: viewDuration,
      );
    } catch (e) {
      debugPrint('⚠️ Error tracking product view: $e');
    }
  }

  /// Track from cart data map (convenience method)
  void trackCartAdd(Map<String, dynamic> cartData, {int quantity = 1}) {
    try {
      trackAddToCart(
        productId: cartData['productId'] as String,
        shopId: cartData['shopId'] as String?,
        productName: cartData['productName'] as String?,
        category: cartData['category'] as String?,
        subcategory: cartData['subcategory'] as String?,
        subsubcategory: cartData['subsubcategory'] as String?,
        gender: cartData['gender'] as String?,
        brand: cartData['brandModel'] as String?,
        price: (cartData['unitPrice'] as num?)?.toDouble(),
        quantity: quantity,
      );
    } catch (e) {
      debugPrint('⚠️ Error tracking cart add: $e');
    }
  }

  /// Get queue size (for debugging/monitoring)
  int get pendingEventCount => _queue.length;
  
  /// Check if service is healthy
  bool get isHealthy => _isInitialized && !_isCircuitBreakerOpen;
}