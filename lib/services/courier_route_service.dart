// lib/services/courier_route_service.dart

import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class RouteStop {
  final String orderId;
  final String label;
  final double lat;
  final double lng;
  final StopType type;
  final Map<String, dynamic>? orderData;

  const RouteStop({
    required this.orderId,
    required this.label,
    required this.lat,
    required this.lng,
    required this.type,
    this.orderData,
  });
}

enum StopType { pickup, delivery }

class RouteResult {
  final List<RouteStop> orderedStops;
  final List<LatLngPoint> polylinePoints;
  final List<int> legDurationsSec;
  final List<int> cumulativeEtaSec;
  final double totalDistanceM;
  final double totalDurationSec;
  final String signature;

  const RouteResult({
    required this.orderedStops,
    required this.polylinePoints,
    required this.legDurationsSec,
    required this.cumulativeEtaSec,
    required this.totalDistanceM,
    required this.totalDurationSec,
    required this.signature,
  });
}

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class CourierRouteService {
  CourierRouteService._();
  static final CourierRouteService instance = CourierRouteService._();

  RouteResult? _cachedResult;
  DateTime _lastFetchTime = DateTime(2000);
  static const int _minRefetchIntervalSec = 10;

  Future<RouteResult?> getRoute({
    required List<Map<String, dynamic>> orders,
    required double courierLat,
    required double courierLng,
  }) async {
    if (orders.isEmpty) {
      _cachedResult = null;
      return null;
    }

    final sig = _buildSignature(orders);

    if (_cachedResult != null && _cachedResult!.signature == sig) {
      debugPrint('[CourierRoute] Cache hit');
      return _cachedResult;
    }

    final elapsed = DateTime.now().difference(_lastFetchTime).inSeconds;
    if (elapsed < _minRefetchIntervalSec && _cachedResult != null && _cachedResult!.signature == sig) {
      debugPrint('[CourierRoute] Throttled (same signature)');
      return _cachedResult;
    }

    debugPrint('[CourierRoute] Fetching new route (${orders.length} orders)');

    try {
      final result = await _computeRoute(
        orders: orders,
        courierLat: courierLat,
        courierLng: courierLng,
        signature: sig,
      );
      _cachedResult = result;
      _lastFetchTime = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('[CourierRoute] Failed: $e');
      return _cachedResult;
    }
  }

  void clearCache() {
    _cachedResult = null;
  }

  RouteResult? get cachedRoute => _cachedResult;

  // ── Signature includes pickup status so route recalculates on pickup ──
  String _buildSignature(List<Map<String, dynamic>> orders) {
    final parts = orders.map((o) {
      final id = o['orderId'] as String? ?? '';
      final pickedUp = o['pickedUpFromRestaurant'] == true ? '1' : '0';
      return '$id:$pickedUp';
    }).toList()
      ..sort();
    return parts.join(',');
  }

  Future<RouteResult?> _computeRoute({
    required List<Map<String, dynamic>> orders,
    required double courierLat,
    required double courierLng,
    required String signature,
  }) async {
    final stops = <RouteStop>[];

    for (final order in orders) {
      final orderId = order['orderId'] as String? ?? '';
      final restaurantName = order['restaurantName'] as String? ?? '—';
      final buyerName = order['buyerName'] as String? ?? '—';
      final pickedUp = order['pickedUpFromRestaurant'] == true;
      final rLat = (order['restaurantLat'] as num?)?.toDouble();
      final rLng = (order['restaurantLng'] as num?)?.toDouble();

      // Skip restaurant stop if already picked up
      if (!pickedUp && rLat != null && rLng != null) {
        stops.add(RouteStop(
          orderId: orderId,
          label: restaurantName,
          lat: rLat,
          lng: rLng,
          type: StopType.pickup,
          orderData: order,
        ));
      }

      final addr = order['deliveryAddress'] as Map<String, dynamic>?;
      final loc = addr?['location'];
      double? dLat, dLng;
      if (loc is GeoPoint) {
        dLat = loc.latitude;
        dLng = loc.longitude;
      } else if (loc is Map) {
        dLat = (loc['latitude'] as num?)?.toDouble();
        dLng = (loc['longitude'] as num?)?.toDouble();
      }

      if (dLat != null && dLng != null) {
        stops.add(RouteStop(
          orderId: orderId,
          label: buyerName,
          lat: dLat,
          lng: dLng,
          type: StopType.delivery,
          orderData: order,
        ));
      }
    }

    if (stops.isEmpty) return null;

    // ── Nearest-neighbor with pickup-before-delivery constraint ──
    final ordered = <RouteStop>[];
    final visited = <int>{};
    final pickedUpSet = <String>{};
    double curLat = courierLat;
    double curLng = courierLng;

    // Pre-populate for orders already picked up
    for (final order in orders) {
      if (order['pickedUpFromRestaurant'] == true) {
        pickedUpSet.add(order['orderId'] as String? ?? '');
      }
    }

    while (ordered.length < stops.length) {
      int bestIdx = -1;
      double bestDist = double.infinity;

      for (int i = 0; i < stops.length; i++) {
        if (visited.contains(i)) continue;
        final stop = stops[i];
        if (stop.type == StopType.delivery && !pickedUpSet.contains(stop.orderId)) continue;

        final d = _haversineMeters(curLat, curLng, stop.lat, stop.lng);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }

      if (bestIdx == -1) break;

      final chosen = stops[bestIdx];
      ordered.add(chosen);
      visited.add(bestIdx);
      curLat = chosen.lat;
      curLng = chosen.lng;

      if (chosen.type == StopType.pickup) {
        pickedUpSet.add(chosen.orderId);
      }
    }

    if (ordered.isEmpty) return null;

    // ── OSRM ────────────────────────────────────────────────────
    final coords = [
      '$courierLng,$courierLat',
      ...ordered.map((s) => '${s.lng},${s.lat}'),
    ].join(';');

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coords'
      '?overview=full&geometries=geojson&steps=false',
    );

    final response = await http.get(url).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('OSRM timeout'),
    );

    if (response.statusCode != 200) throw Exception('OSRM ${response.statusCode}');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') throw Exception('OSRM: ${data['code']}');

    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordsList = geometry['coordinates'] as List;
    final legs = route['legs'] as List;

    final polylinePoints = coordsList.map((c) {
      final pair = c as List;
      return LatLngPoint((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();

    final legDurations = legs.map((leg) => ((leg as Map)['duration'] as num).round()).toList();

    final cumulativeEta = <int>[];
    int cumSec = 0;
    for (final dur in legDurations) {
      cumSec += dur;
      cumulativeEta.add(cumSec);
    }

    return RouteResult(
      orderedStops: ordered,
      polylinePoints: polylinePoints,
      legDurationsSec: legDurations,
      cumulativeEtaSec: cumulativeEta,
      totalDistanceM: (route['distance'] as num).toDouble(),
      totalDurationSec: (route['duration'] as num).toDouble(),
      signature: signature,
    );
  }

  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _degToRad(double deg) => deg * (pi / 180);
}