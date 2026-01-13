// lib/services/algolia_service_manager.dart - PRODUCTION GRADE

import '../services/algolia_service.dart';

class AlgoliaServiceManager {
  static AlgoliaServiceManager? _instance;
  static AlgoliaServiceManager get instance {
    _instance ??= AlgoliaServiceManager._internal();
    return _instance!;
  }

  AlgoliaServiceManager._internal();

  // Service instances
  AlgoliaService? _mainService;
  AlgoliaService? _shopService;
  AlgoliaService? _ordersService;
  AlgoliaService? _shopsService; // New shops index service

  // Configuration
  static const String _applicationId = '3QVVGQH4ME';
  static const String _apiKey = 'dcca6685e21c2baed748ccea7a6ddef1';

  /// Get main products service (lazy initialization)
  AlgoliaService get mainService {
    _mainService ??= AlgoliaService(
      applicationId: _applicationId,
      apiKey: _apiKey,
      mainIndexName: 'products',
      categoryIndexName: 'categories',
    );
    return _mainService!;
  }

  /// Get shop products service (lazy initialization)
  AlgoliaService get shopService {
    _shopService ??= AlgoliaService(
      applicationId: _applicationId,
      apiKey: _apiKey,
      mainIndexName: 'shop_products',
      categoryIndexName: 'categories',
    );
    return _shopService!;
  }

  /// Get orders service (lazy initialization)
  AlgoliaService get ordersService {
    _ordersService ??= AlgoliaService(
      applicationId: _applicationId,
      apiKey: _apiKey,
      mainIndexName: 'orders',
      categoryIndexName: 'categories',
    );
    return _ordersService!;
  }

  /// Get shops service (lazy initialization) - NEW
  AlgoliaService get shopsService {
    _shopsService ??= AlgoliaService(
      applicationId: _applicationId,
      apiKey: _apiKey,
      mainIndexName: 'shops',
      categoryIndexName: 'categories', // Not used for shops, but required by constructor
    );
    return _shopsService!;
  }

  /// Check if services are initialized (for debugging)
  bool get isInitialized => 
      _mainService != null && 
      _shopService != null && 
      _ordersService != null &&
      _shopsService != null;

  /// Reset services (if needed for testing or configuration changes)
  void resetServices() {
    _mainService = null;
    _shopService = null;
    _ordersService = null;
    _shopsService = null;
  }

  /// Health check - verify services are reachable
  Future<bool> isHealthy() async {
    try {
      final results = await Future.wait([
        mainService.isServiceReachable(),
        shopService.isServiceReachable(),
        ordersService.isServiceReachable(),
        shopsService.isServiceReachable(),
      ]).timeout(const Duration(seconds: 5));
      
      return results.every((result) => result);
    } catch (e) {
      print('AlgoliaServiceManager health check failed: $e');
      return false;
    }
  }
}