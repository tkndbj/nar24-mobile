import 'typesense_service.dart';
import 'restaurant_typesense_service.dart';
import 'market_typesense_service.dart';
export 'typesense_service.dart' show TypeSenseService, TypeSensePage;
export 'restaurant_typesense_service.dart' show RestaurantTypesenseService;
export 'market_typesense_service.dart' show MarketTypesenseService;

class TypeSenseServiceManager {
  static TypeSenseServiceManager? _instance;
  static TypeSenseServiceManager get instance {
    _instance ??= TypeSenseServiceManager._internal();
    return _instance!;
  }

  TypeSenseServiceManager._internal();

  static const String _typesenseHost = 'j0xs6ry9275tu4cop.a2.typesense.net';
  static const String _typesenseSearchKey = 'z8Ii7rZ3MUlpxLvbPLu3WOqmsZemMjBZ';

  // ── Service instances (lazy) ──────────────────────────────────────────────
  TypeSenseService? _mainService;
  TypeSenseService? _shopService;
  TypeSenseService? _ordersService;
  TypeSenseService? _shopsService;
  RestaurantTypesenseService? _restaurantService;
  MarketTypesenseService? _marketService;

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

  // ← NEW: shared host/key, dedicated collections for restaurants & foods
  RestaurantTypesenseService get restaurantService {
    _restaurantService ??= RestaurantTypesenseService(
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _restaurantService!;
  }

  MarketTypesenseService get marketService {
    _marketService ??= MarketTypesenseService(
      typesenseHost: _typesenseHost,
      typesenseSearchKey: _typesenseSearchKey,
    );
    return _marketService!;
  }

  bool get isInitialized =>
      _mainService != null &&
      _shopService != null &&
      _ordersService != null &&
      _shopsService != null;
  // Note: restaurantService is excluded — it's lazily created on first use
  // and doesn't need to be pre-warmed like the others.

  void resetServices() {
    _mainService?.dispose();
    _shopService?.dispose();
    _ordersService?.dispose();
    _shopsService?.dispose();
    _mainService = null;
    _shopService = null;
    _ordersService = null;
    _shopsService = null;
    _restaurantService?.dispose();
    _restaurantService = null;
    _marketService?.dispose();
    _marketService = null;
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
