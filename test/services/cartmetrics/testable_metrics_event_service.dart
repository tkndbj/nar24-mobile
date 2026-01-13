// test/services/testable_metrics_event_service.dart
//
// TESTABLE MIRROR of MetricsEventService pure logic from lib/services/metrics_event_service.dart
//
// This file contains EXACT copies of pure logic functions from MetricsEventService
// made public for unit testing. If tests pass here, the same logic works in production.
//
// ⚠️ IMPORTANT: Keep this in sync with lib/services/metrics_event_service.dart
//
// Last synced with: metrics_event_service.dart (current version)

/// Mirrors batch ID generation from MetricsEventService
class TestableBatchIdGenerator {
  /// Generate batch ID for metrics events
  /// Mirrors: 'cart_fav_${user.uid}_${DateTime.now().millisecondsSinceEpoch}'
  static String generate({
    required String userId,
    required DateTime timestamp,
  }) {
    return 'cart_fav_${userId}_${timestamp.millisecondsSinceEpoch}';
  }

  /// Parse batch ID to extract components
  static Map<String, dynamic>? parse(String batchId) {
    final regex = RegExp(r'^cart_fav_(.+)_(\d+)$');
    final match = regex.firstMatch(batchId);
    
    if (match == null) return null;
    
    return {
      'userId': match.group(1),
      'timestamp': int.tryParse(match.group(2) ?? ''),
    };
  }

  /// Check if batch ID has correct format
  static bool isValid(String batchId) {
    return batchId.startsWith('cart_fav_') && 
           RegExp(r'^cart_fav_.+_\d+$').hasMatch(batchId);
  }
}

/// Mirrors event validation from MetricsEventService.logBatchEvents
class TestableEventValidator {
  static const List<String> requiredFields = ['type', 'productId'];
  
  static const List<String> validEventTypes = [
    'cart_added',
    'cart_removed',
    'favorite_added',
    'favorite_removed',
  ];

  /// Validate a single event has required fields
  /// Mirrors validation in logBatchEvents
  static bool isValidEvent(Map<String, dynamic> event) {
    return event.containsKey('type') && event.containsKey('productId');
  }

  /// Validate all events in a batch
  static bool areAllEventsValid(List<Map<String, dynamic>> events) {
    if (events.isEmpty) return false;
    return events.every(isValidEvent);
  }

  /// Get validation errors for an event
  static List<String> getValidationErrors(Map<String, dynamic> event) {
    final errors = <String>[];
    
    if (!event.containsKey('type')) {
      errors.add('Missing required field: type');
    }
    if (!event.containsKey('productId')) {
      errors.add('Missing required field: productId');
    }
    
    return errors;
  }

  /// Check if event type is valid
  static bool isValidEventType(String type) {
    return validEventTypes.contains(type);
  }
}

/// Mirrors event building from MetricsEventService
class TestableEventBuilder {
  /// Build a single event
  static Map<String, dynamic> buildEvent({
    required String eventType,
    required String productId,
    String? shopId,
  }) {
    return {
      'type': eventType,
      'productId': productId,
      if (shopId != null) 'shopId': shopId,
    };
  }

  /// Build cart added event
  static Map<String, dynamic> buildCartAdded({
    required String productId,
    String? shopId,
  }) {
    return buildEvent(
      eventType: 'cart_added',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Build cart removed event
  static Map<String, dynamic> buildCartRemoved({
    required String productId,
    String? shopId,
  }) {
    return buildEvent(
      eventType: 'cart_removed',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Build favorite added event
  static Map<String, dynamic> buildFavoriteAdded({
    required String productId,
    String? shopId,
  }) {
    return buildEvent(
      eventType: 'favorite_added',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Build favorite removed event
  static Map<String, dynamic> buildFavoriteRemoved({
    required String productId,
    String? shopId,
  }) {
    return buildEvent(
      eventType: 'favorite_removed',
      productId: productId,
      shopId: shopId,
    );
  }
}

/// Mirrors batch event building from MetricsEventService
class TestableBatchEventBuilder {
  /// Build batch cart removal events
  /// Mirrors logBatchCartRemovals
  static List<Map<String, dynamic>> buildBatchCartRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) {
    return productIds.map((productId) => {
      'type': 'cart_removed',
      'productId': productId,
      if (shopIds[productId] != null) 'shopId': shopIds[productId],
    }).toList();
  }

  /// Build batch favorite removal events
  /// Mirrors logBatchFavoriteRemovals
  static List<Map<String, dynamic>> buildBatchFavoriteRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) {
    return productIds.map((productId) => {
      'type': 'favorite_removed',
      'productId': productId,
      if (shopIds[productId] != null) 'shopId': shopIds[productId],
    }).toList();
  }

  /// Build batch events of any type
  static List<Map<String, dynamic>> buildBatchEvents({
    required String eventType,
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) {
    return productIds.map((productId) => {
      'type': eventType,
      'productId': productId,
      if (shopIds[productId] != null) 'shopId': shopIds[productId],
    }).toList();
  }
}

/// Mirrors the full request payload structure
class TestableMetricsPayload {
  /// Build complete payload for Cloud Function
  static Map<String, dynamic> build({
    required String batchId,
    required List<Map<String, dynamic>> events,
  }) {
    return {
      'batchId': batchId,
      'events': events,
    };
  }

  /// Validate payload structure
  static bool isValid(Map<String, dynamic> payload) {
    if (!payload.containsKey('batchId')) return false;
    if (!payload.containsKey('events')) return false;
    
    final batchId = payload['batchId'];
    if (batchId is! String || batchId.isEmpty) return false;
    
    final events = payload['events'];
    if (events is! List || events.isEmpty) return false;
    
    return true;
  }
}