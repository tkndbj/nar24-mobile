// lib/utils/connectivity_helper.dart

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityHelper {
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isConnected = true;
  static DateTime? _lastConnectivityCheck;
  static const Duration _checkCooldown = Duration(seconds: 30);

  /// Initialize connectivity monitoring
  static void initialize() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        // Device is connected if any connection type is not 'none'
        _isConnected = results.any((result) => result != ConnectivityResult.none);
      },
    );
  }

  /// Dispose connectivity monitoring
  static void dispose() {
    _connectivitySubscription?.cancel();
  }

  /// Check if device is connected to internet
  static Future<bool> isConnected() async {
    final now = DateTime.now();
    
    // Use cached result if check was recent
    if (_lastConnectivityCheck != null &&
        now.difference(_lastConnectivityCheck!) < _checkCooldown) {
      return _isConnected;
    }

    try {
      // Check connectivity status - now returns a list
      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none
      );
      
      if (!hasConnection) {
        _isConnected = false;
        _lastConnectivityCheck = now;
        return false;
      }

      // Perform actual internet reach test
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      
      _isConnected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _lastConnectivityCheck = now;
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      _lastConnectivityCheck = now;
      return false;
    }
  }

  /// Get current connectivity status without performing network check
  static bool get isCurrentlyConnected => _isConnected;

  /// Check specific service reachability
  static Future<bool> canReachAlgolia() async {
    if (!await isConnected()) return false;
    
    try {
      final result = await InternetAddress.lookup('3qvvgqh4me-dsn.algolia.net')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check Firebase reachability
  static Future<bool> canReachFirebase() async {
    if (!await isConnected()) return false;
    
    try {
      final result = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}