import 'typesense_service.dart';

export 'typesense_service.dart' show TypeSenseService, TypeSensePage;

class TypeSenseServiceManager {
  static TypeSenseServiceManager? _instance;
  static TypeSenseServiceManager get instance {
    _instance ??= TypeSenseServiceManager._internal();
    return _instance!;
  }

  TypeSenseServiceManager._internal();

  // ── Typesense configuration ───────────────────────────────────────────────
  // Get your Search-Only API key from:
  // Typesense Cloud → your cluster → API Keys → "Search-only API Key"
  static const String _typesenseHost = 'o17xr5q8psytcabup-1.a2.typesense.net';
  static const String _typesenseSearchKey =
      'wYjR4e0aCTTy9GVCImW1U30xlBQTYK51'; // ← replace this

  // ── Service instances (lazy) ──────────────────────────────────────────────
  TypeSenseService? _mainService;
  TypeSenseService? _shopService;
  TypeSenseService? _ordersService;
  TypeSenseService? _shopsService;

  TypeSenseService get mainService {
    _mainService ??= TypeSenseService(
      applicationId: '',
      apiKey: '',
      mainIndexName: 'products',
      categoryIndexName: 'categories',
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _mainService!;
  }

  TypeSenseService get shopService {
    _shopService ??= TypeSenseService(
      applicationId: '',
      apiKey: '',
      mainIndexName: 'shop_products',
      categoryIndexName: 'categories',
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _shopService!;
  }

  TypeSenseService get ordersService {
    _ordersService ??= TypeSenseService(
      applicationId: '',
      apiKey: '',
      mainIndexName: 'orders',
      categoryIndexName: 'categories',
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _ordersService!;
  }

  TypeSenseService get shopsService {
    _shopsService ??= TypeSenseService(
      applicationId: '',
      apiKey: '',
      mainIndexName: 'shops',
      categoryIndexName: 'categories',
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _shopsService!;
  }

  bool get isInitialized =>
      _mainService != null &&
      _shopService != null &&
      _ordersService != null &&
      _shopsService != null;

  void resetServices() {
    _mainService = null;
    _shopService = null;
    _ordersService = null;
    _shopsService = null;
  }

  Future<bool> isHealthy() async {
    try {
      final results = await Future.wait([
        mainService.isServiceReachable(),
        shopService.isServiceReachable(),
        ordersService.isServiceReachable(),
        shopsService.isServiceReachable(),
      ]).timeout(const Duration(seconds: 5));
      return results.every((r) => r);
    } catch (e) {
      print('TypesenseServiceManager health check failed: $e');
      return false;
    }
  }
}
