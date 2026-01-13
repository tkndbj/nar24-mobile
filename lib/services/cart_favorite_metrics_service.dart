import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';


class MetricsEventService {
  static final MetricsEventService _instance = MetricsEventService._internal();
  
  factory MetricsEventService() => _instance;
  
  MetricsEventService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Cloud Functions instance (europe-west3 region)
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  Future<void> logEvent({
    required String eventType,
    required String productId,
    String? shopId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('⚠️ Cannot log metric event: User not authenticated');
      return;
    }

    // Generate deterministic batch ID
    final batchId = 'cart_fav_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('🔍 MetricsService.logEvent: type=$eventType, productId=$productId, shopId=$shopId');
    
    // ✅ Fire-and-forget: No await, returns immediately
    _functions
        .httpsCallable('batchCartFavoriteEvents')
        .call({
          'batchId': batchId,
          'events': [
            {
              'type': eventType,
              'productId': productId,
              if (shopId != null) 'shopId': shopId,
            }
          ],
        })
        .then((_) {
          debugPrint('✅ Logged $eventType event for $productId');
        })
        .catchError((error) {
          debugPrint('⚠️ Metrics event logging failed: $error (non-critical, ignored)');
        });
  }

  /// Log multiple cart/favorite events in a single batch
  /// 
  /// More efficient than calling [logEvent] multiple times.
  /// 
  /// Example:
  /// ```dart
  /// await MetricsEventService().logBatchEvents(
  ///   events: [
  ///     {'type': 'cart_removed', 'productId': 'abc123', 'shopId': 'shop456'},
  ///     {'type': 'cart_removed', 'productId': 'def789', 'shopId': 'shop456'},
  ///   ],
  /// );
  /// ```
  Future<void> logBatchEvents({
    required List<Map<String, dynamic>> events,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('⚠️ Cannot log metric events: User not authenticated');
      return;
    }

    if (events.isEmpty) {
      debugPrint('⚠️ No events to log');
      return;
    }

    // Validate event structure
    for (final event in events) {
      if (!event.containsKey('type') || !event.containsKey('productId')) {
        debugPrint('⚠️ Invalid event structure: $event');
        return;
      }
    }

    final batchId = 'cart_fav_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';
    
    // ✅ Fire-and-forget: No await, returns immediately
    _functions
        .httpsCallable('batchCartFavoriteEvents')
        .call({
          'batchId': batchId,
          'events': events,
        })
        .then((_) {
          debugPrint('✅ Logged ${events.length} batch events');
        })
        .catchError((error) {
          debugPrint('⚠️ Batch metrics logging failed: $error (non-critical, ignored)');
        });
  }

  /// Log cart addition event
  /// 
  /// Convenience wrapper for [logEvent] with eventType='cart_added'
  Future<void> logCartAdded({
    required String productId,
    String? shopId,
  }) {
    return logEvent(
      eventType: 'cart_added',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Log cart removal event
  /// 
  /// Convenience wrapper for [logEvent] with eventType='cart_removed'
  Future<void> logCartRemoved({
    required String productId,
    String? shopId,
  }) {
    return logEvent(
      eventType: 'cart_removed',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Log favorite addition event
  /// 
  /// Convenience wrapper for [logEvent] with eventType='favorite_added'
  Future<void> logFavoriteAdded({
    required String productId,
    String? shopId,
  }) {
    return logEvent(
      eventType: 'favorite_added',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Log favorite removal event
  /// 
  /// Convenience wrapper for [logEvent] with eventType='favorite_removed'
  Future<void> logFavoriteRemoved({
    required String productId,
    String? shopId,
  }) {
    return logEvent(
      eventType: 'favorite_removed',
      productId: productId,
      shopId: shopId,
    );
  }

  /// Log multiple cart removals (batch operation)
  Future<void> logBatchCartRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) {
    return logBatchEvents(
      events: productIds.map((productId) => {
        'type': 'cart_removed',
        'productId': productId,
        if (shopIds[productId] != null) 'shopId': shopIds[productId],
      }).toList(),
    );
  }

  /// Log multiple favorite removals (batch operation)
  Future<void> logBatchFavoriteRemovals({
    required List<String> productIds,
    required Map<String, String?> shopIds,
  }) {
    return logBatchEvents(
      events: productIds.map((productId) => {
        'type': 'favorite_removed',
        'productId': productId,
        if (shopIds[productId] != null) 'shopId': shopIds[productId],
      }).toList(),
    );
  }
}