// lib/services/sales_config_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SalesConfig {
  final bool salesPaused;
  final DateTime? pausedAt;
  final String? pauseReason;

  SalesConfig({
    required this.salesPaused,
    this.pausedAt,
    this.pauseReason,
  });

  factory SalesConfig.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      return SalesConfig(salesPaused: false);
    }

    return SalesConfig(
      salesPaused: data['salesPaused'] ?? false,
      pausedAt: (data['pausedAt'] as Timestamp?)?.toDate(),
      pauseReason: data['pauseReason'] as String?,
    );
  }

  factory SalesConfig.defaultConfig() {
    return SalesConfig(salesPaused: false);
  }
}

class SalesConfigService {
  static final SalesConfigService _instance = SalesConfigService._internal();
  factory SalesConfigService() => _instance;
  SalesConfigService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final ValueNotifier<SalesConfig> configNotifier = ValueNotifier(
    SalesConfig.defaultConfig(),
  );

  StreamSubscription<DocumentSnapshot>? _subscription;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _subscription = _firestore
        .collection('settings')
        .doc('salesConfig')
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists) {
          configNotifier.value = SalesConfig.fromFirestore(snapshot);
        } else {
          configNotifier.value = SalesConfig.defaultConfig();
        }
        debugPrint(
            '📊 Sales config updated: paused=${configNotifier.value.salesPaused}');
      },
      onError: (error) {
        debugPrint('❌ Sales config listener error: $error');
        configNotifier.value = SalesConfig.defaultConfig();
      },
    );
  }

  bool get isSalesPaused => configNotifier.value.salesPaused;

  SalesConfig get currentConfig => configNotifier.value;

  Future<SalesConfig> refreshConfig() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('salesConfig')
          .get(const GetOptions(source: Source.server));

      if (doc.exists) {
        configNotifier.value = SalesConfig.fromFirestore(doc);
      }
      return configNotifier.value;
    } catch (e) {
      debugPrint('❌ Failed to refresh sales config: $e');
      rethrow;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}