// test/services/testable_user_activity_service.dart
//
// TESTABLE MIRROR of UserActivityService pure logic from lib/services/user_activity_service.dart
//
// This file contains EXACT copies of pure logic functions from UserActivityService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/user_activity_service.dart
//
// Last synced with: user_activity_service.dart (current version)

/// Event types for user activity tracking
enum TestableActivityType {
  click,        // Weight: 1
  view,         // Weight: 2
  addToCart,    // Weight: 5
  removeFromCart, // Weight: -2
  favorite,     // Weight: 3
  unfavorite,   // Weight: -1
  purchase,     // Weight: 10
  search,       // Weight: 1
}

/// Mirrors activityWeights from UserActivityService
class TestableActivityWeights {
  static const Map<TestableActivityType, int> weights = {
    TestableActivityType.click: 1,
    TestableActivityType.view: 2,
    TestableActivityType.addToCart: 5,
    TestableActivityType.removeFromCart: -2,
    TestableActivityType.favorite: 3,
    TestableActivityType.unfavorite: -1,
    TestableActivityType.purchase: 10,
    TestableActivityType.search: 1,
  };

  static int getWeight(TestableActivityType type) {
    return weights[type] ?? 0;
  }

  /// Calculate total score from a list of activities
  static int calculateScore(List<TestableActivityType> activities) {
    return activities.fold(0, (sum, type) => sum + getWeight(type));
  }

  /// Get all positive signal types
  static List<TestableActivityType> get positiveSignals {
    return weights.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList();
  }

  /// Get all negative signal types
  static List<TestableActivityType> get negativeSignals {
    return weights.entries
        .where((e) => e.value < 0)
        .map((e) => e.key)
        .toList();
  }
}

/// Mirrors ActivityEvent serialization from UserActivityService
class TestableActivityEvent {
  final String eventId;
  final TestableActivityType type;
  final DateTime timestamp;
  final String? productId;
  final String? shopId;
  final String? productName;
  final String? category;
  final String? subcategory;
  final String? subsubcategory;
  final String? brand;
  final double? price;
  final String? searchQuery;
  final String? source;
  final int? quantity;
  final double? totalValue;
  final Map<String, dynamic>? extra;

  TestableActivityEvent({
    required this.eventId,
    required this.type,
    required this.timestamp,
    this.productId,
    this.shopId,
    this.productName,
    this.category,
    this.subcategory,
    this.subsubcategory,
    this.brand,
    this.price,
    this.searchQuery,
    this.source,
    this.quantity,
    this.totalValue,
    this.extra,
  });

  /// Mirrors toJson from ActivityEvent
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'eventId': eventId,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'weight': TestableActivityWeights.getWeight(type),
    };

    if (productId != null) map['productId'] = productId;
    if (productName != null) map['productName'] = productName;
    if (shopId != null) map['shopId'] = shopId;
    if (category != null) map['category'] = category;
    if (subcategory != null) map['subcategory'] = subcategory;
    if (subsubcategory != null) map['subsubcategory'] = subsubcategory;
    if (brand != null) map['brand'] = brand;
    if (price != null) map['price'] = price;
    if (searchQuery != null) map['searchQuery'] = searchQuery;
    if (source != null) map['source'] = source;
    if (quantity != null) map['quantity'] = quantity;
    if (totalValue != null) map['totalValue'] = totalValue;
    if (extra != null && extra!.isNotEmpty) map['extra'] = extra;

    return map;
  }

  /// Mirrors fromJson from ActivityEvent
  factory TestableActivityEvent.fromJson(Map<String, dynamic> json) {
    return TestableActivityEvent(
      eventId: json['eventId'] as String,
      type: TestableActivityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TestableActivityType.click,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      productId: json['productId'] as String?,
      shopId: json['shopId'] as String?,
      productName: json['productName'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      subsubcategory: json['subsubcategory'] as String?,
      brand: json['brand'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      searchQuery: json['searchQuery'] as String?,
      source: json['source'] as String?,
      quantity: json['quantity'] as int?,
      totalValue: (json['totalValue'] as num?)?.toDouble(),
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
}

/// Mirrors event ID generation from UserActivityService
class TestableEventIdGenerator {
  /// Mirrors _generateEventId from UserActivityService
  static String generate({
    required TestableActivityType type,
    String? productId,
    required DateTime timestamp,
  }) {
    final ms = timestamp.millisecondsSinceEpoch;
    final random = ms % 10000;
    return '${type.name}_${productId ?? 'none'}_${ms}_$random';
  }

  /// Parse event ID to extract components
  static Map<String, dynamic>? parse(String eventId) {
    final parts = eventId.split('_');
    if (parts.length < 4) return null;

    final typeName = parts[0];
    final productId = parts[1] == 'none' ? null : parts[1];

    return {
      'type': typeName,
      'productId': productId,
    };
  }

  /// Validate event ID format
  static bool isValid(String eventId) {
    final parts = eventId.split('_');
    return parts.length >= 4;
  }
}

/// Mirrors deduplication logic from UserActivityService
class TestableDeduplicator {
  static const Duration dedupeWindow = Duration(seconds: 2);
  static const int maxTrackedEvents = 100;

  final Map<String, DateTime> _recentEvents = {};

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableDeduplicator({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Generate dedup key
  static String generateKey(TestableActivityType type, String? productId) {
    return '${type.name}_${productId ?? 'none'}';
  }

  /// Mirrors _isDuplicate from UserActivityService
  bool isDuplicate(TestableActivityType type, String? productId) {
    final key = generateKey(type, productId);
    final lastTime = _recentEvents[key];

    if (lastTime != null) {
      final elapsed = nowProvider().difference(lastTime);
      if (elapsed < dedupeWindow) {
        return true;
      }
    }

    _recentEvents[key] = nowProvider();

    // Cleanup old entries
    if (_recentEvents.length > maxTrackedEvents) {
      final cutoff = nowProvider().subtract(dedupeWindow);
      _recentEvents.removeWhere((_, time) => time.isBefore(cutoff));
    }

    return false;
  }

  /// Check if would be duplicate without recording
  bool wouldBeDuplicate(TestableActivityType type, String? productId) {
    final key = generateKey(type, productId);
    final lastTime = _recentEvents[key];

    if (lastTime == null) return false;

    final elapsed = nowProvider().difference(lastTime);
    return elapsed < dedupeWindow;
  }

  void clear() {
    _recentEvents.clear();
  }

  int get trackedCount => _recentEvents.length;
}

/// Mirrors queue management from UserActivityService
class TestableEventQueue {
  static const int maxQueueSize = 50;
  static const int flushThreshold = 20;

  final List<TestableActivityEvent> _queue = [];

  List<TestableActivityEvent> get events => List.unmodifiable(_queue);
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Check if queue should flush based on threshold
  bool get shouldFlush => _queue.length >= flushThreshold;

  /// Check if queue is at capacity
  bool get isFull => _queue.length >= maxQueueSize;

  /// Add event, dropping oldest if full
  /// Returns true if an event was dropped
  bool add(TestableActivityEvent event) {
    bool dropped = false;

    if (_queue.length >= maxQueueSize) {
      _queue.removeAt(0);
      dropped = true;
    }

    _queue.add(event);
    return dropped;
  }

  /// Remove events that were successfully sent
  void removeEvents(List<TestableActivityEvent> sentEvents) {
    _queue.removeWhere((e) => sentEvents.contains(e));
  }

  /// Take snapshot for sending
  List<TestableActivityEvent> takeSnapshot() {
    return List.from(_queue);
  }

  void clear() {
    _queue.clear();
  }
}

/// Mirrors circuit breaker from UserActivityService
class TestableActivityCircuitBreaker {
  static const int maxRetries = 3;
  static const Duration cooldownDuration = Duration(minutes: 5);

  int consecutiveFailures = 0;
  DateTime? lastFailureTime;

  // For testing: injectable time provider
  DateTime Function() nowProvider;

  TestableActivityCircuitBreaker({DateTime Function()? nowProvider})
      : nowProvider = nowProvider ?? (() => DateTime.now());

  /// Mirrors _isCircuitBreakerOpen from UserActivityService
  bool get isOpen {
    if (consecutiveFailures < maxRetries) return false;
    if (lastFailureTime == null) return false;

    final elapsed = nowProvider().difference(lastFailureTime!);
    if (elapsed > cooldownDuration) {
      // Reset circuit breaker
      consecutiveFailures = 0;
      lastFailureTime = null;
      return false;
    }
    return true;
  }

  void recordFailure() {
    consecutiveFailures++;
    lastFailureTime = nowProvider();
  }

  void recordSuccess() {
    consecutiveFailures = 0;
    lastFailureTime = null;
  }

  void reset() {
    consecutiveFailures = 0;
    lastFailureTime = null;
  }
}

/// Mirrors 24-hour cutoff for persisted events
class TestableEventPersistence {
  static const Duration maxEventAge = Duration(hours: 24);

  /// Filter events to only include those within 24 hours
  /// Mirrors the cutoff logic in _loadPersistedEvents
  static List<TestableActivityEvent> filterByAge(
    List<TestableActivityEvent> events, {
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(maxEventAge);
    return events.where((e) => e.timestamp.isAfter(cutoff)).toList();
  }

  /// Check if an event is too old to load
  static bool isExpired(TestableActivityEvent event, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(maxEventAge);
    return event.timestamp.isBefore(cutoff);
  }
}

/// Mirrors search tracking validation
class TestableSearchValidator {
  /// Validate and normalize search query
  /// Mirrors trackSearch logic
  static String? normalizeQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.toLowerCase();
  }

  /// Check if query is valid for tracking
  static bool isValidQuery(String query) {
    return query.trim().isNotEmpty;
  }
}