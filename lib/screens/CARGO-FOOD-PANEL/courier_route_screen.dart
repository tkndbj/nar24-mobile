// lib/screens/food/courier_route_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/courier_route_service.dart';
import '../../services/courier_location_service.dart';

class CourierRouteScreen extends StatefulWidget {
  const CourierRouteScreen({super.key});

  @override
  State<CourierRouteScreen> createState() => _CourierRouteScreenState();
}

class _CourierRouteScreenState extends State<CourierRouteScreen> {
  GoogleMapController? _mapController;
  RouteResult? _route;
  bool _loading = true;
  String? _error;
  Position? _currentPosition;
  StreamSubscription? _ordersSubscription;
  String _lastOrderSignature = '';

  // Action busy states
  String? _pickupBusyOrderId;
  String? _deliverBusyOrderId;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  static const _pickupColor = Color(0xFF7C3AED);
  static const _deliveryColor = Color(0xFFF97316);
  static const _routeColor = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _getCurrentPosition();
    _listenToOrders();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentPosition() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      _currentPosition = await Geolocator.getLastKnownPosition();
    }
  }

  // ── Listen to orders ──────────────────────────────────────────────────────

  void _listenToOrders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() { _error = 'Giriş yapılmamış'; _loading = false; });
      return;
    }

    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders-food')
        .where('cargoUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'out_for_delivery')
        .snapshots()
        .listen((snap) {
      final orders = snap.docs.map((d) {
        final data = d.data();
        return {
          'orderId': d.id,
          'restaurantName': data['restaurantName'] ?? '—',
          'restaurantLat': data['restaurantLat'],
          'restaurantLng': data['restaurantLng'],
          'buyerName': data['buyerName'] ?? '—',
          'buyerPhone': data['buyerPhone'] ?? '',
          'totalPrice': data['totalPrice'] ?? 0,
          'currency': data['currency'] ?? 'TL',
          'isPaid': data['isPaid'] ?? false,
          'deliveryAddress': data['deliveryAddress'],
          'items': data['items'] ?? [],
          'pickedUpFromRestaurant': data['pickedUpFromRestaurant'] ?? false,
        };
      }).toList();

      // Signature includes pickup status
      final sig = orders.map((o) {
        final id = o['orderId'];
        final p = o['pickedUpFromRestaurant'] == true ? '1' : '0';
        return '$id:$p';
      }).toList()
        ..sort();
      final sigStr = sig.join(',');

      if (sigStr == _lastOrderSignature && _route != null) return;
      _lastOrderSignature = sigStr;

      _computeRoute(orders);
    }, onError: (e) {
      setState(() { _error = 'Siparişler yüklenemedi'; _loading = false; });
    });
  }

  // ── Compute route ─────────────────────────────────────────────────────────

  Future<void> _computeRoute(List<Map<String, dynamic>> orders) async {
    if (orders.isEmpty) {
      setState(() { _route = null; _markers.clear(); _polylines.clear(); _loading = false; _error = null; });
      return;
    }

    await _getCurrentPosition();
    if (_currentPosition == null) {
      setState(() { _error = 'Konum alınamadı'; _loading = false; });
      return;
    }

    final result = await CourierRouteService.instance.getRoute(
      orders: orders,
      courierLat: _currentPosition!.latitude,
      courierLng: _currentPosition!.longitude,
    );

    if (!mounted) return;

    if (result == null) {
      setState(() { _error = 'Rota hesaplanamadı'; _loading = false; });
      return;
    }

    _buildMapElements(result);
    setState(() { _route = result; _loading = false; _error = null; });
    _fitBounds(result);
  }

  // ── Mark pickup ───────────────────────────────────────────────────────────

  Future<void> _markPickedUp(String orderId, String restaurantName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restorandan Alındı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          '"$restaurantName" restoranından siparişi aldınız mı?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _pickupColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Evet, Aldım', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _pickupBusyOrderId = orderId);
    try {
      await FirebaseFirestore.instance
          .collection('orders-food')
          .doc(orderId)
          .update({
        'pickedUpFromRestaurant': true,
        'pickedUpAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$restaurantName — alındı ✓'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      // Stream auto-updates → route recalculates
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('İşlem başarısız, tekrar deneyin'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _pickupBusyOrderId = null);
    }
  }

  // ── Mark delivered (with payment sheet) ───────────────────────────────────

  Future<void> _markDelivered(String orderId, String buyerName) async {
    final paymentMethod = await _showPaymentSheet();
    if (paymentMethod == null || !mounted) return;

    setState(() => _deliverBusyOrderId = orderId);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateFoodOrderStatus');
      await callable.call({ 'orderId': orderId, 'newStatus': 'delivered' });

      await FirebaseFirestore.instance
          .collection('orders-food')
          .doc(orderId)
          .update({'paymentReceivedMethod': paymentMethod});

      CourierLocationService.instance.updateCurrentOrder(null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$buyerName — teslim edildi ✓'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      // Stream auto-updates → order disappears → route recalculates
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Teslimat işlemi başarısız, tekrar deneyin'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _deliverBusyOrderId = null);
    }
  }

  Future<String?> _showPaymentSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF211F31) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Müşteri Nasıl Ödedi?',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ödeme yöntemini seçin',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _PaymentBtn(emoji: '💳', label: 'Kart', color: Colors.blue, isDark: isDark,
                      onTap: () => Navigator.of(context).pop('card')),
                  const SizedBox(width: 12),
                  _PaymentBtn(emoji: '💵', label: 'Nakit', color: Colors.green, isDark: isDark,
                      onTap: () => Navigator.of(context).pop('cash')),
                  const SizedBox(width: 12),
                  _PaymentBtn(emoji: '🏦', label: 'IBAN', color: Colors.purple, isDark: isDark,
                      onTap: () => Navigator.of(context).pop('iban')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Navigate with Google Maps ─────────────────────────────────────────────

  Future<void> _openGoogleMapsNavigation() async {
    if (_route == null || _route!.orderedStops.isEmpty) return;
    final stops = _route!.orderedStops;
    final destination = stops.last;
    final waypoints = stops.length > 1
        ? stops.sublist(0, stops.length - 1).map((s) => '${s.lat},${s.lng}').join('|')
        : null;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${destination.lat},${destination.lng}'
      '${waypoints != null ? '&waypoints=$waypoints' : ''}'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _refreshRoute() async {
    setState(() => _loading = true);
    CourierRouteService.instance.clearCache();
    _lastOrderSignature = '';
  }

  // ── Build map elements ────────────────────────────────────────────────────

  void _buildMapElements(RouteResult route) {
    _markers.clear();
    _polylines.clear();

    if (_currentPosition != null) {
      _markers.add(Marker(
        markerId: const MarkerId('courier'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Sen buradasın'),
        zIndex: 10,
      ));
    }

    for (int i = 0; i < route.orderedStops.length; i++) {
      final stop = route.orderedStops[i];
      final isPickup = stop.type == StopType.pickup;
      final etaMin = i < route.cumulativeEtaSec.length
          ? (route.cumulativeEtaSec[i] / 60).round() : 0;

      final items = stop.orderData?['items'] as List? ?? [];
      final itemsSummary = items.take(2).map((item) {
        final m = item as Map<String, dynamic>;
        final qty = (m['quantity'] as num?)?.toInt() ?? 1;
        final name = m['name'] as String? ?? '';
        return '$qty× $name';
      }).join(', ');

      final snippet = isPickup
          ? 'Restoran · ~$etaMin dk'
          : '$itemsSummary${itemsSummary.isNotEmpty ? ' · ' : ''}~$etaMin dk';

      _markers.add(Marker(
        markerId: MarkerId('stop_$i'),
        position: LatLng(stop.lat, stop.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isPickup ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(title: '${i + 1}. ${stop.label}', snippet: snippet),
        zIndex: 5,
      ));
    }

    if (route.polylinePoints.isNotEmpty) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: route.polylinePoints.map((p) => LatLng(p.lat, p.lng)).toList(),
        color: _routeColor,
        width: 4,
      ));
    }
  }

  void _fitBounds(RouteResult route) {
    if (_mapController == null) return;
    final points = <LatLng>[];
    if (_currentPosition != null) {
      points.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }
    for (final stop in route.orderedStops) {
      points.add(LatLng(stop.lat, stop.lng));
    }
    if (points.length < 2) return;

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      64,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        elevation: 0, scrolledUnderElevation: 0,
        title: const Text('Teslimat Rotam', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refreshRoute,
          ),
          if (_route != null && _route!.orderedStops.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.navigation_rounded, color: Colors.blue),
              onPressed: _openGoogleMapsNavigation,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_route != null) _buildSummaryStrip(isDark),
          Expanded(flex: 3, child: _buildMap(isDark)),
          if (_route != null && _route!.orderedStops.isNotEmpty)
            Expanded(flex: 2, child: _buildStopList(isDark)),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(bool isDark) {
    final route = _route!;
    final totalMin = (route.totalDurationSec / 60).round();
    final totalKm = (route.totalDistanceM / 1000).toStringAsFixed(1);
    final stopCount = route.orderedStops.where((s) => s.type == StopType.delivery).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        border: Border(bottom: BorderSide(
          color: isDark ? const Color(0xFF2D2B3F) : const Color(0xFFE5E7EB),
        )),
      ),
      child: Row(
        children: [
          _SummaryChip(icon: Icons.timer_outlined, label: '~$totalMin dk', color: Colors.orange, isDark: isDark),
          const SizedBox(width: 10),
          _SummaryChip(icon: Icons.straighten_rounded, label: '$totalKm km', color: Colors.blue, isDark: isDark),
          const SizedBox(width: 10),
          _SummaryChip(icon: Icons.location_on_rounded, label: '$stopCount teslimat', color: Colors.green, isDark: isDark),
          const Spacer(),
          GestureDetector(
            onTap: _openGoogleMapsNavigation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Başla', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(bool isDark) {
    if (_loading && _route == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.orange, strokeWidth: 2.5),
        const SizedBox(height: 16),
        Text('Rota hesaplanıyor...', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ]));
    }
    if (_error != null && _route == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 40, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _refreshRoute,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Tekrar Dene'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
        ),
      ]));
    }
    if (_route == null || _route!.orderedStops.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🛵', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('Aktif teslimat yok', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[600])),
      ]));
    }

    final initialPos = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(_route!.orderedStops.first.lat, _route!.orderedStops.first.lng);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialPos, zoom: 13),
      markers: _markers, polylines: _polylines,
      myLocationEnabled: true, myLocationButtonEnabled: true,
      zoomControlsEnabled: false, mapToolbarEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        if (_route != null) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _route != null) _fitBounds(_route!);
          });
        }
      },
    );
  }

  // ── Stop list with action buttons ─────────────────────────────────────────

  Widget _buildStopList(bool isDark) {
    final route = _route!;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF211F31) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Icon(Icons.route_rounded, size: 15, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text('Duraklar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[300] : Colors.grey[800])),
                const Spacer(),
                Text('${route.orderedStops.length} durak', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: route.orderedStops.length,
                itemBuilder: (_, i) => _buildStopCard(i, route, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopCard(int index, RouteResult route, bool isDark) {
    final stop = route.orderedStops[index];
    final isPickup = stop.type == StopType.pickup;
    final etaMin = index < route.cumulativeEtaSec.length
        ? (route.cumulativeEtaSec[index] / 60).round() : 0;
    final isLast = index == route.orderedStops.length - 1;
    final color = isPickup ? _pickupColor : _deliveryColor;
    final orderId = stop.orderId;

    final isBusy = isPickup
        ? _pickupBusyOrderId == orderId
        : _deliverBusyOrderId == orderId;

    // Items summary for delivery
    String? itemsSummary;
    if (!isPickup) {
      final items = stop.orderData?['items'] as List? ?? [];
      if (items.isNotEmpty) {
        itemsSummary = items.take(3).map((item) {
          final m = item as Map<String, dynamic>;
          final qty = (m['quantity'] as num?)?.toInt() ?? 1;
          final name = m['name'] as String? ?? '';
          return '$qty× $name';
        }).join(', ');
        if (items.length > 3) itemsSummary = '$itemsSummary +${items.length - 3}';
      }
    }

    final price = stop.orderData?['totalPrice'] as num?;
    final currency = stop.orderData?['currency'] as String? ?? 'TL';
    final isPaid = stop.orderData?['isPaid'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          SizedBox(width: 28, child: Column(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15), shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Center(child: Text('${index + 1}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))),
            ),
            if (!isLast) Container(width: 2, height: 52, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          ])),
          const SizedBox(width: 10),
          // Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? color.withOpacity(0.06) : color.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(children: [
                    Icon(isPickup ? Icons.restaurant_rounded : Icons.person_rounded, size: 13, color: color),
                    const SizedBox(width: 5),
                    Expanded(child: Text(stop.label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                            color: isDark ? Colors.grey[200] : Colors.grey[900]),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(isPickup ? 'AL' : 'TESLİM',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                    ),
                    const SizedBox(width: 6),
                    Text('~$etaMin dk', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.orange[300] : Colors.orange[700])),
                  ]),

                  // Items for delivery
                  if (!isPickup && itemsSummary != null) ...[
                    const SizedBox(height: 4),
                    Text(itemsSummary, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],

                  // Price for delivery
                  if (!isPickup && price != null && price > 0) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Text('${price.toStringAsFixed(0)} $currency',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[300] : Colors.grey[800])),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isPaid ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text(isPaid ? 'ÖDENDİ' : 'NAKİT',
                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold,
                                color: isPaid ? Colors.green : Colors.orange)),
                      ),
                    ]),
                  ],

                  // ── Action button ──────────────────────────────
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: isBusy
                          ? null
                          : isPickup
                              ? () => _markPickedUp(orderId, stop.label)
                              : () => _markDelivered(orderId, stop.label),
                      icon: isBusy
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Icon(isPickup ? Icons.check_circle_rounded : Icons.delivery_dining_rounded, size: 16),
                      label: Text(
                        isPickup ? 'Aldım' : 'Teslim Et',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPickup ? _pickupColor : Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: (isPickup ? _pickupColor : Colors.green).withOpacity(0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  const _SummaryChip({required this.icon, required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _PaymentBtn extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _PaymentBtn({required this.emoji, required this.label, required this.color, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(isDark ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ),
    );
  }
}