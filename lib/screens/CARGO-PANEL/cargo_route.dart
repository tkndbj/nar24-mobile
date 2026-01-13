import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cargo_qr_scan.dart';

class CargoRoute extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final bool isGatherer;

  const CargoRoute({
    Key? key,
    required this.orders,
    required this.isGatherer,
  }) : super(key: key);

  @override
  State<CargoRoute> createState() => _CargoRouteState();
}

class _CargoRouteState extends State<CargoRoute> {
  GoogleMapController? _mapController;
  List<Map<String, dynamic>> _optimizedOrders = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  int _currentStopIndex = 0;
  bool _isMapLoading = true;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTrackingLocation = false;
  bool _isNavigating = false;
  bool _isLoadingDirections = false;

  // Replace with your actual Google Maps API Key
  static const String _googleApiKey = 'AIzaSyAVc9a7i36N4v582rsapin-TA1ROlRCNbM';

  @override
  void initState() {
    super.initState();
    _optimizeRoute();
    _findFirstUncompletedStop();
    _createMarkers();
    _startLocationTracking();
  }

  void _findFirstUncompletedStop() {
    // Find the first stop that hasn't been completed yet
    for (int i = 0; i < _optimizedOrders.length; i++) {
      if (!_isStopCompleted(_optimizedOrders[i])) {
        _currentStopIndex = i;
        return;
      }
    }
    // If all stops are completed, set to last index
    _currentStopIndex = _optimizedOrders.length - 1;
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showError(AppLocalizations.of(context).locationPermissionDenied);
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showError(
              AppLocalizations.of(context).locationPermissionPermanentlyDenied);
        }
        return;
      }

      setState(() => _isTrackingLocation = true);

      final position = await Geolocator.getCurrentPosition();
      _updateCurrentLocation(position);

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_updateCurrentLocation);
    } catch (e) {
      if (mounted) {
        _showError('${AppLocalizations.of(context).errorTrackingLocation}: $e');
      }
    }
  }

  void _updateCurrentLocation(Position position) {
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
    _createMarkers();
    if (_isNavigating) {
      _getDirectionsToNextStop();
    }
  }

  Future<void> _getDirectionsToNextStop() async {
    if (_currentLocation == null ||
        _currentStopIndex >= _optimizedOrders.length) {
      return;
    }

    final nextStop = _getLatLng(_optimizedOrders[_currentStopIndex]);
    if (nextStop == null) return;

    setState(() => _isLoadingDirections = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${_currentLocation!.latitude},${_currentLocation!.longitude}'
        '&destination=${nextStop.latitude},${nextStop.longitude}'
        '&mode=driving'
        '&key=$_googleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final encodedPolyline = route['overview_polyline']['points'];

          final points = PolylinePoints.decodePolyline(encodedPolyline);

          final polylineCoordinates = points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

          final polyline = Polyline(
            polylineId: const PolylineId('navigation_route'),
            points: polylineCoordinates,
            color: widget.isGatherer ? Colors.orange : Colors.blue,
            width: 5,
          );

          setState(() {
            _polylines = {polyline};
          });

          // Fit map to show route
          if (_mapController != null) {
            final bounds = _calculateBounds([_currentLocation!, nextStop]);
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 100),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showError(
            '${AppLocalizations.of(context).errorLoadingDirections}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDirections = false);
      }
    }
  }

  void _startNavigation() {
    if (_currentLocation == null) {
      _showError(AppLocalizations.of(context).waitingForLocation);
      return;
    }

    setState(() => _isNavigating = true);
    _getDirectionsToNextStop();
  }

  void _confirmArrival() async {
    if (_currentStopIndex >= _optimizedOrders.length) return;

    final currentOrder = _optimizedOrders[_currentStopIndex];
    final wasPreviouslyFailed = _isStopFailed(currentOrder);

    // For distribution mode, require QR scan verification first
    if (!widget.isGatherer) {
      final buyerId = currentOrder['buyerId'] as String?;
      final buyerName = currentOrder['buyerName'] as String? ?? 'Unknown';
      final orderId = currentOrder['orderId'] as String?;

      // Check if this is a multi-order stop
      final orderIds = currentOrder['orderIds'] as List<dynamic>? ?? [orderId];
      final isMultipleOrders = orderIds.length > 1;

      if (orderId == null || buyerId == null) {
        _showError('Order or buyer information is missing');
        return;
      }

      // Navigate to QR scan screen (scan once for all orders at this address)
      final result = await Navigator.push<QRScanResult>(
        context,
        MaterialPageRoute(
          builder: (context) => CargoQRScan(
            orderId: orderId,
            buyerId: buyerId,
            buyerName:
                '$buyerName${isMultipleOrders ? ' (${orderIds.length} orders)' : ''}',
          ),
        ),
      );

      // Handle scan result
      if (result == null || !result.success) {
        return;
      }

      // If QR scan already marked as delivered on server
      if (result.markedAsDelivered) {
        // For multi-order stops, mark all orders as delivered
        if (isMultipleOrders) {
          await _markMultipleOrdersDelivered(currentOrder, wasPreviouslyFailed);
        } else {
          await _handleSuccessfulDelivery(currentOrder, wasPreviouslyFailed);
        }
        return;
      }

      // QR was skipped - need to manually mark as delivered
      if (result.skipped) {
        if (isMultipleOrders) {
          await _markMultipleOrdersDelivered(currentOrder, wasPreviouslyFailed);
        } else {
          await _processDeliveryConfirmation(currentOrder, wasPreviouslyFailed);
        }
        return;
      }

      return;
    }

    // For gathering mode, proceed directly
    try {
      // Prepare update data
      final updateData = <String, dynamic>{
        'gatheringStatus': 'gathered',
        'gatheredAt': Timestamp.now(),
      };

      // If this item was previously marked as failed, remove failure fields
      if (wasPreviouslyFailed) {
        updateData['failedAt'] = FieldValue.delete();
        updateData['failureReason'] = FieldValue.delete();
        updateData['failureNotes'] = FieldValue.delete();
      }

      // Update item gathering status
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(currentOrder['orderId'])
          .collection('items')
          .doc(currentOrder['itemId'])
          .update(updateData);

      // Update the local order status to reflect completion and remove failure data
      setState(() {
        _optimizedOrders[_currentStopIndex]['gatheringStatus'] = 'gathered';

        // Remove failure-related fields from local state
        _optimizedOrders[_currentStopIndex].remove('failedAt');
        _optimizedOrders[_currentStopIndex].remove('failureReason');
        _optimizedOrders[_currentStopIndex].remove('failureNotes');
      });

      // Find next uncompleted stop
      int nextUncompletedIndex = -1;
      for (int i = _currentStopIndex + 1; i < _optimizedOrders.length; i++) {
        if (!_isStopCompleted(_optimizedOrders[i])) {
          nextUncompletedIndex = i;
          break;
        }
      }

      if (nextUncompletedIndex != -1) {
        // Move to next uncompleted stop
        setState(() {
          _currentStopIndex = nextUncompletedIndex;
        });
        _createMarkers();
        await _getDirectionsToNextStop();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(wasPreviouslyFailed
                  ? 'Stop recovered and marked as completed'
                  : 'Stop confirmed. Moving to next stop.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // All stops completed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).allStopsCompleted),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      _showError('Error updating status: $e');
      print('Detailed error: $e');
      print('Current order data: $currentOrder');
    }
  }

  Future<void> _markMultipleOrdersDelivered(
    Map<String, dynamic> currentOrder,
    bool wasPreviouslyFailed,
  ) async {
    final l10n = AppLocalizations.of(context);
    final orderIds =
        currentOrder['orderIds'] as List<dynamic>? ?? [currentOrder['orderId']];

    try {
      // Update all orders at this stop
      for (final orderId in orderIds) {
        final orderDoc = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .get();

        final orderData = orderDoc.data();
        final isCurrentlyIncomplete = orderData?['allItemsGathered'] == false;

        // Mark items as delivered
        final itemsSnapshot = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .collection('items')
            .where('gatheringStatus', isEqualTo: 'at_warehouse')
            .get();

        await Future.wait(
          itemsSnapshot.docs.map((itemDoc) async {
            await FirebaseFirestore.instance
                .collection('orders')
                .doc(orderId)
                .collection('items')
                .doc(itemDoc.id)
                .update({
              'deliveredInPartial': true,
              'partialDeliveryAt': Timestamp.now(),
            });
          }),
        );

        // Update order status
        final updateData = <String, dynamic>{
          'distributionStatus': 'delivered',
          'deliveredAt': Timestamp.now(),
        };

        if (isCurrentlyIncomplete) {
          updateData['distributedBy'] = null;
          updateData['distributedByName'] = null;
          updateData['distributedAt'] = null;
        }

        if (wasPreviouslyFailed) {
          updateData['failedAt'] = FieldValue.delete();
          updateData['failureReason'] = FieldValue.delete();
          updateData['failureNotes'] = FieldValue.delete();
        }

        await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .update(updateData);
      }

      // Update local state
      setState(() {
        _optimizedOrders[_currentStopIndex]['distributionStatus'] = 'delivered';
        _optimizedOrders[_currentStopIndex].remove('failedAt');
        _optimizedOrders[_currentStopIndex].remove('failureReason');
        _optimizedOrders[_currentStopIndex].remove('failureNotes');
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                    '${orderIds.length} ${l10n.ordersDelivered ?? 'orders delivered'}'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Move to next stop
      await _moveToNextStop();
    } catch (e) {
      _showError('Error updating orders: $e');
    }
  }

  Future<void> _moveToNextStop() async {
    final l10n = AppLocalizations.of(context);

    int nextUncompletedIndex = -1;
    for (int i = _currentStopIndex + 1; i < _optimizedOrders.length; i++) {
      if (!_isStopCompleted(_optimizedOrders[i])) {
        nextUncompletedIndex = i;
        break;
      }
    }

    if (nextUncompletedIndex != -1) {
      setState(() {
        _currentStopIndex = nextUncompletedIndex;
      });
      _createMarkers();
      await _getDirectionsToNextStop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.allStopsCompleted),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  /// Handle successful delivery when server already marked as delivered via QR scan
  Future<void> _handleSuccessfulDelivery(
    Map<String, dynamic> currentOrder,
    bool wasPreviouslyFailed,
  ) async {
    final l10n = AppLocalizations.of(context);

    // Update the local order status to reflect completion
    setState(() {
      _optimizedOrders[_currentStopIndex]['distributionStatus'] = 'delivered';
      _optimizedOrders[_currentStopIndex].remove('failedAt');
      _optimizedOrders[_currentStopIndex].remove('failureReason');
      _optimizedOrders[_currentStopIndex].remove('failureNotes');
    });

    // Find next uncompleted stop
    int nextUncompletedIndex = -1;
    for (int i = _currentStopIndex + 1; i < _optimizedOrders.length; i++) {
      if (!_isStopCompleted(_optimizedOrders[i])) {
        nextUncompletedIndex = i;
        break;
      }
    }

    if (nextUncompletedIndex != -1) {
      // Move to next uncompleted stop
      setState(() {
        _currentStopIndex = nextUncompletedIndex;
      });
      _createMarkers();
      await _getDirectionsToNextStop();

      // Show brief confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(l10n.stopConfirmedMovingNext),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // All stops completed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.allStopsCompleted),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  /// Process delivery confirmation after QR verification
  Future<void> _processDeliveryConfirmation(
    Map<String, dynamic> currentOrder,
    bool wasPreviouslyFailed,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      final orderId = currentOrder['orderId'];
      if (orderId == null || orderId.isEmpty) {
        _showError('Order ID is missing');
        print('Current order data: $currentOrder');
        return;
      }

      print('Updating order $orderId to delivered status');

      // First check the order status
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      final orderData = orderDoc.data();

      // Check if this is CURRENTLY an incomplete order
      final isCurrentlyIncomplete = orderData?['allItemsGathered'] == false;

      // Check if this order was PREVIOUSLY partially delivered
      final wasPreviouslyPartiallyDelivered =
          orderData?['deliveredAt'] != null &&
              orderData?['distributedBy'] == null;

      // ===== CRITICAL: Mark items that are being delivered RIGHT NOW =====
      // Get all items for this order
      final itemsSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .get();

      // Find items that are at warehouse (ready to be delivered)
      final itemsAtWarehouse = itemsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['gatheringStatus'] == 'at_warehouse';
      }).toList();

      // Mark each item at warehouse as delivered
      // CRITICAL: ALWAYS set deliveredInPartial to TRUE when actually delivering
      await Future.wait(
        itemsAtWarehouse.map((itemDoc) async {
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(orderId)
              .collection('items')
              .doc(itemDoc.id)
              .update({
            'deliveredInPartial': true,
            'partialDeliveryAt': Timestamp.now(),
          });
        }),
      );

      print('Marked ${itemsAtWarehouse.length} items as delivered');

      // Prepare update data for the order
      final updateData = <String, dynamic>{
        'distributionStatus': 'delivered',
        'deliveredAt': Timestamp.now(),
      };

      // For orders that are currently incomplete OR were previously partially delivered
      // Mark as delivered BUT unassign distributor for reassignment
      if (isCurrentlyIncomplete || wasPreviouslyPartiallyDelivered) {
        updateData['distributedBy'] = null;
        updateData['distributedByName'] = null;
        updateData['distributedAt'] = null;

        print(
            'Partial delivery detected - unassigning distributor for order $orderId');
      }

      // If this order was previously marked as failed, remove failure fields
      if (wasPreviouslyFailed) {
        updateData['failedAt'] = FieldValue.delete();
        updateData['failureReason'] = FieldValue.delete();
        updateData['failureNotes'] = FieldValue.delete();
      }

      // Update order distribution status
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update(updateData);

      print('Successfully updated order $orderId');

      // Update the local order status to reflect completion
      setState(() {
        _optimizedOrders[_currentStopIndex]['distributionStatus'] = 'delivered';
        _optimizedOrders[_currentStopIndex].remove('failedAt');
        _optimizedOrders[_currentStopIndex].remove('failureReason');
        _optimizedOrders[_currentStopIndex].remove('failureNotes');
      });

      // Show appropriate message for partial delivery
      if (mounted) {
        if (isCurrentlyIncomplete || wasPreviouslyPartiallyDelivered) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Partial delivery completed. Order unassigned for future delivery of remaining items.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          // Show QR verification success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.qrVerifiedDeliveryConfirmed)),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      // Find next uncompleted stop
      int nextUncompletedIndex = -1;
      for (int i = _currentStopIndex + 1; i < _optimizedOrders.length; i++) {
        if (!_isStopCompleted(_optimizedOrders[i])) {
          nextUncompletedIndex = i;
          break;
        }
      }

      if (nextUncompletedIndex != -1) {
        // Move to next uncompleted stop
        setState(() {
          _currentStopIndex = nextUncompletedIndex;
        });
        _createMarkers();
        await _getDirectionsToNextStop();
      } else {
        // All stops completed
        if (mounted) {
          await Future.delayed(const Duration(seconds: 2));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.allStopsCompleted),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      _showError('Error updating status: $e');
      print('Detailed error: $e');
      print('Current order data: $currentOrder');
    }
  }

  void _optimizeRoute() {
    _optimizedOrders = List.from(widget.orders);

    if (widget.isGatherer) {
      _optimizedOrders.sort((a, b) {
        final sellerCompare =
            (a['sellerId'] ?? '').compareTo(b['sellerId'] ?? '');
        if (sellerCompare != 0) return sellerCompare;
        return _getDeliveryPriority(a['deliveryOption'] ?? 'normal')
            .compareTo(_getDeliveryPriority(b['deliveryOption'] ?? 'normal'));
      });
    } else {
      _optimizedOrders.sort((a, b) {
        return _getDeliveryPriority(a['deliveryOption'] ?? 'normal')
            .compareTo(_getDeliveryPriority(b['deliveryOption'] ?? 'normal'));
      });
    }
  }

  // Add after _confirmArrival method
  Future<void> _showCouldntCompleteDialog() async {
    if (_currentStopIndex >= _optimizedOrders.length) return;

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? selectedReason;
    final customReasonController = TextEditingController();

    final reasons = [
      l10n.reasonNotResponding,
      l10n.reasonAway,
      l10n.reasonClosed,
      l10n.reasonWrongAddress,
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          FeatherIcons.alertCircle,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isGatherer
                                  ? l10n.couldntGather
                                  : l10n.couldntDeliver,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.selectReason,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reason selection cards
                        ...reasons.map((reason) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedReason = reason;
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: selectedReason == reason
                                        ? Colors.red.shade50
                                        : (isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey.shade50),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedReason == reason
                                          ? Colors.red
                                          : (isDark
                                              ? Colors.white12
                                              : Colors.grey.shade300),
                                      width: selectedReason == reason ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: selectedReason == reason
                                                ? Colors.red
                                                : (isDark
                                                    ? Colors.white38
                                                    : Colors.grey.shade400),
                                            width: 2,
                                          ),
                                          color: selectedReason == reason
                                              ? Colors.red
                                              : Colors.transparent,
                                        ),
                                        child: selectedReason == reason
                                            ? const Icon(
                                                Icons.check,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          reason,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: selectedReason == reason
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )),

                        const SizedBox(height: 20),

                        // Optional notes section
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    FeatherIcons.edit3,
                                    size: 16,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.additionalNotes,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: customReasonController,
                                maxLines: 3,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.optionalNotes,
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              l10n.cancel,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: selectedReason != null
                                ? () => Navigator.pop(context, true)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              l10n.confirm,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true && selectedReason != null) {
      await _markStopAsFailed(
        selectedReason!,
        customReasonController.text.trim(),
      );
    }
  }

  Future<void> _markStopAsFailed(String reason, String customNotes) async {
    if (_currentStopIndex >= _optimizedOrders.length) return;

    final currentOrder = _optimizedOrders[_currentStopIndex];
    final l10n = AppLocalizations.of(context);

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    print('=== MARK STOP AS FAILED DEBUG ===');
    print('Current user ID: $currentUserId');
    print('Current stop index: $_currentStopIndex');
    print('Order data: ${currentOrder.toString()}');

    try {
      if (widget.isGatherer) {
        // Check authorization
        final gatheredById = currentOrder['gatheredBy'];
        print('GatheredBy ID from order: $gatheredById');
        print('User matches gatheredBy: ${currentUserId == gatheredById}');

        if (currentUserId != gatheredById) {
          _showError(
              'You are not authorized to update this item. Current user: $currentUserId, Required: $gatheredById');
          print(
              'ERROR: User mismatch - Current: $currentUserId, Required: $gatheredById');
          return;
        }

        // Create update map with ONLY allowed fields according to Firestore rules
        final updateData = <String, dynamic>{
          'gatheringStatus': 'failed',
          'failedAt': Timestamp.now(),
          'failureReason': reason,
        };

        // Only add failureNotes if there's actual content
        // DON'T set it to null - just don't include it
        if (customNotes.isNotEmpty) {
          updateData['failureNotes'] = customNotes;
        }
        // REMOVED: else updateData['failureNotes'] = null;

        print('Update data for gatherer: ${updateData.toString()}');
        print(
            'Attempting to update: orders/${currentOrder['orderId']}/items/${currentOrder['itemId']}');

        // Update item gathering failure
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(currentOrder['orderId'])
            .collection('items')
            .doc(currentOrder['itemId'])
            .update(updateData);

        print('Successfully updated item gathering status to failed');

        // Update local state
        setState(() {
          _optimizedOrders[_currentStopIndex]['gatheringStatus'] = 'failed';
          _optimizedOrders[_currentStopIndex]['failureReason'] = reason;
          if (customNotes.isNotEmpty) {
            _optimizedOrders[_currentStopIndex]['failureNotes'] = customNotes;
          }
        });
      } else {
        // Distributor logic
        final orderId = currentOrder['orderId'];
        final distributedById = currentOrder['distributedBy'];

        print('DistributedBy ID from order: $distributedById');
        print(
            'User matches distributedBy: ${currentUserId == distributedById}');

        if (orderId == null || orderId.isEmpty) {
          _showError('Order ID is missing');
          print('ERROR: Order ID is missing from current order');
          return;
        }

        if (currentUserId != distributedById) {
          _showError('You are not authorized to update this order');
          print(
              'ERROR: User mismatch for distribution - Current: $currentUserId, Required: $distributedById');
          return;
        }

        // Create update map with ONLY allowed fields for distribution
        final updateData = <String, dynamic>{
          'distributionStatus': 'failed',
          'failedAt': Timestamp.now(),
          'failureReason': reason,
        };

        // Only add failureNotes if there's actual content
        // DON'T set it to null - just don't include it
        if (customNotes.isNotEmpty) {
          updateData['failureNotes'] = customNotes;
        }
        // REMOVED: else updateData['failureNotes'] = null;

        print('Update data for distributor: ${updateData.toString()}');
        print('Attempting to update: orders/$orderId');

        // Update order distribution failure
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .update(updateData);

        print('Successfully updated order distribution status to failed');

        // Update local state
        setState(() {
          _optimizedOrders[_currentStopIndex]['distributionStatus'] = 'failed';
          _optimizedOrders[_currentStopIndex]['failureReason'] = reason;
          if (customNotes.isNotEmpty) {
            _optimizedOrders[_currentStopIndex]['failureNotes'] = customNotes;
          }
        });
      }

      print('Local state updated successfully');

      // Find next uncompleted stop
      int nextUncompletedIndex = -1;
      for (int i = _currentStopIndex + 1; i < _optimizedOrders.length; i++) {
        if (!_isStopCompleted(_optimizedOrders[i]) &&
            !_isStopFailed(_optimizedOrders[i])) {
          nextUncompletedIndex = i;
          print('Found next uncompleted stop at index: $nextUncompletedIndex');
          break;
        }
      }

      if (nextUncompletedIndex != -1) {
        setState(() {
          _currentStopIndex = nextUncompletedIndex;
        });
        _createMarkers();
        await _getDirectionsToNextStop();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.stopMarkedAsFailed),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        print('No more uncompleted stops found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.allStopsProcessed),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e, stackTrace) {
      _showError('Error marking as failed: $e');
      print('=== ERROR DETAILS ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('Current order data: ${currentOrder.toString()}');
      print('Current user ID: $currentUserId');
      print('=== END ERROR DETAILS ===');
    }
  }

  bool _isStopFailed(Map<String, dynamic> order) {
    if (widget.isGatherer) {
      return order['gatheringStatus'] == 'failed';
    } else {
      return order['distributionStatus'] == 'failed';
    }
  }

  bool _isStopCompleted(Map<String, dynamic> order) {
    if (widget.isGatherer) {
      // For gathering, check if item is already gathered or failed
      final status = order['gatheringStatus'];
      return status == 'gathered' || status == 'failed';
    } else {
      // For distribution, check if order is already delivered or failed
      final status = order['distributionStatus'];
      return status == 'delivered' || status == 'failed';
    }
  }

  int _getDeliveryPriority(String option) {
    switch (option) {
      case 'express':
        return 1;
      case 'normal':
        return 2;
      case 'gelal':
        return 3;
      case 'pickup':
        return 4;
      default:
        return 5;
    }
  }

  LatLng? _getLatLng(Map<String, dynamic> order) {
    if (widget.isGatherer) {
      final sellerAddr = order['sellerAddress'];
      if (sellerAddr != null && sellerAddr['location'] != null) {
        final loc = sellerAddr['location'];
        return LatLng(loc['lat'], loc['lng']);
      }
    } else {
      final addr = order['address'];
      if (addr != null && addr['location'] != null) {
        final loc = addr['location'];
        if (loc is GeoPoint) {
          return LatLng(loc.latitude, loc.longitude);
        } else if (loc is Map) {
          return LatLng(loc['latitude'], loc['longitude']);
        }
      }
    }
    return null;
  }

  void _createMarkers() {
    final markers = <Marker>{};

    if (_currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(
            title: AppLocalizations.of(context).yourLocation,
            snippet: AppLocalizations.of(context).currentPosition,
          ),
        ),
      );
    }

    for (int i = 0; i < _optimizedOrders.length; i++) {
      final order = _optimizedOrders[i];
      final position = _getLatLng(order);
      final isCompleted = _isStopCompleted(order);
      final isFailed = _isStopFailed(order);

      if (position != null) {
        markers.add(
          Marker(
            markerId: MarkerId('stop_$i'),
            position: position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isFailed
                  ? BitmapDescriptor.hueRed // Failed stops
                  : isCompleted
                      ? BitmapDescriptor.hueGreen // Completed stops
                      : i == _currentStopIndex
                          ? (widget.isGatherer
                              ? BitmapDescriptor.hueOrange
                              : BitmapDescriptor.hueAzure)
                          : BitmapDescriptor.hueYellow, // Pending stops
            ),
            infoWindow: InfoWindow(
              title: '${AppLocalizations.of(context).stop} ${i + 1}'
                  '${isFailed ? ' ✗' : isCompleted ? ' ✓' : ''}',
              snippet: _getShortAddress(order),
            ),
          ),
        );
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isMapLoading = false);
        _fitMapToMarkers();
      }
    });
  }

  void _fitMapToMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    final positions = _markers.map((m) => m.position).toList();
    if (_currentLocation != null && !positions.contains(_currentLocation)) {
      positions.add(_currentLocation!);
    }

    final bounds = _calculateBounds(positions);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  LatLngBounds _calculateBounds(List<LatLng> positions) {
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (var pos in positions) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _goToStop(int index) {
    final position = _getLatLng(_optimizedOrders[index]);
    if (position != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position, zoom: 16),
        ),
      );
      setState(() {
        _currentStopIndex = index;
      });
      _createMarkers();
      if (_isNavigating) {
        _getDirectionsToNextStop();
      }
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation!, zoom: 16),
        ),
      );
    }
  }

  String _getShortAddress(Map<String, dynamic> order) {
    if (widget.isGatherer) {
      final sellerAddr = order['sellerAddress'];
      if (sellerAddr != null) {
        return '${sellerAddr['addressLine1'] ?? AppLocalizations.of(context).notAvailable}, ${sellerAddr['city'] ?? AppLocalizations.of(context).notAvailable}';
      }
    } else {
      if (order['address'] != null) {
        final addr = order['address'];
        return '${addr['addressLine1']}, ${addr['city']}';
      } else if (order['pickupPoint'] != null) {
        return order['pickupPoint']['pickupPointName'] ?? '';
      }
    }
    return '';
  }

  String _getDistanceToNextStop() {
    if (_currentLocation == null ||
        _currentStopIndex >= _optimizedOrders.length) {
      return '';
    }

    final nextStop = _getLatLng(_optimizedOrders[_currentStopIndex]);
    if (nextStop == null) return '';

    final distance = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      nextStop.latitude,
      nextStop.longitude,
    );

    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)}${AppLocalizations.of(context).metersAway}';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)}${AppLocalizations.of(context).kilometersAway}';
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final initialPosition = _currentLocation ??
        _getLatLng(_optimizedOrders.first) ??
        const LatLng(35.1856, 33.3823);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        title: Text(
          l10n.optimizedRoute,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: initialPosition,
              zoom: 12,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          if (_isMapLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
            ),

          // Start Navigation Button (Top Right)
          if (!_isNavigating)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.isGatherer ? Colors.orange : Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _startNavigation,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.start,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Center on location button
          if (_isNavigating)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.my_location,
                    color: widget.isGatherer ? Colors.orange : Colors.blue,
                    size: 20,
                  ),
                  onPressed: _centerOnCurrentLocation,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),
            ),

          // Route summary card
          if (_isNavigating)
            Positioned(
              top: 12,
              left: 12,
              right: 70,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isGatherer ? Colors.orange : Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.isGatherer
                              ? FeatherIcons.package
                              : FeatherIcons.truck,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.isGatherer
                                ? l10n.itemsToGather
                                : l10n.ordersToDeliver,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_currentStopIndex + 1}/${_optimizedOrders.length}',
                            style: TextStyle(
                              color: widget.isGatherer
                                  ? Colors.orange
                                  : Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_currentLocation != null &&
                        _currentStopIndex < _optimizedOrders.length) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.navigation,
                              color: Colors.white70, size: 12),
                          const SizedBox(width: 6),
                          Text(
                            _getDistanceToNextStop(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Loading directions indicator
          if (_isLoadingDirections)
            Positioned(
              bottom: 320,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.loadingDirections,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom sheet with stops
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.12,
            maxChildSize: 0.65,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _optimizedOrders.length,
                        itemBuilder: (context, index) {
                          final order = _optimizedOrders[index];
                          final isCurrentStop = index == _currentStopIndex;
                          final isCompleted = _isStopCompleted(order);
                          final isFailed = _isStopFailed(order);

                          return InkWell(
                            onTap: () => _goToStop(index),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isFailed
                                    ? Colors.red.shade50
                                    : isCurrentStop
                                        ? (widget.isGatherer
                                            ? Colors.orange.shade50
                                            : Colors.blue.shade50)
                                        : isCompleted
                                            ? Colors.green.shade50
                                            : (isDark
                                                ? const Color(0xFF2A2A2A)
                                                : Colors.grey.shade50),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFailed
                                      ? Colors.red
                                      : isCompleted
                                          ? Colors.green
                                          : isCurrentStop
                                              ? (widget.isGatherer
                                                  ? Colors.orange
                                                  : Colors.blue)
                                              : (isDark
                                                  ? Colors.white12
                                                  : Colors.grey.shade300),
                                  width: (isCurrentStop || isFailed) ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: isFailed
                                              ? Colors.red
                                              : isCompleted
                                                  ? Colors.green
                                                  : isCurrentStop
                                                      ? (widget.isGatherer
                                                          ? Colors.orange
                                                          : Colors.blue)
                                                      : (isDark
                                                          ? Colors.white12
                                                          : Colors
                                                              .grey.shade300),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: isFailed
                                              ? const Icon(Icons.close,
                                                  color: Colors.white, size: 14)
                                              : isCompleted
                                                  ? const Icon(Icons.check,
                                                      color: Colors.white,
                                                      size: 14)
                                                  : Text(
                                                      '${index + 1}',
                                                      style: TextStyle(
                                                        color: isCurrentStop
                                                            ? Colors.white
                                                            : (isDark
                                                                ? Colors.white70
                                                                : Colors.black),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getShortAddress(order),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                                decoration: (isCompleted ||
                                                        isFailed)
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                            if (isFailed &&
                                                order['failureReason'] !=
                                                    null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                order['failureReason'],
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                            if (!widget.isGatherer &&
                                                order['isMultipleOrders'] ==
                                                    true) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(FeatherIcons.layers,
                                                        size: 10,
                                                        color: Colors
                                                            .blue.shade700),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${order['orderCount']} orders',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .blue.shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        FeatherIcons.mapPin,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                    ],
                                  ),

                                  // Product names for gathering mode
                                  if (widget.isGatherer &&
                                      order['productName'] != null) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isFailed
                                            ? Colors.red.shade100
                                            : isCompleted
                                                ? Colors.green.shade100
                                                : Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isFailed
                                              ? Colors.red.shade300
                                              : isCompleted
                                                  ? Colors.green.shade300
                                                  : Colors.orange.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            FeatherIcons.package,
                                            size: 10,
                                            color: isFailed
                                                ? Colors.red
                                                : isCompleted
                                                    ? Colors.green
                                                    : Colors.orange,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              '${order['productName']} x${order['quantity']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: isFailed
                                                    ? Colors.red
                                                    : isCompleted
                                                        ? Colors.green
                                                        : Colors.orange,
                                                decoration: (isCompleted ||
                                                        isFailed)
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey.shade50,
                        border: Border(
                          top: BorderSide(
                            color:
                                isDark ? Colors.white12 : Colors.grey.shade200,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_isNavigating) ...[
                            Expanded(
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton(
                                  onPressed: _showCouldntCompleteDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade600,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.close, size: 18),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          widget.isGatherer
                                              ? l10n.couldntGather
                                              : l10n.couldntDeliver,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton(
                                  onPressed: _confirmArrival,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle, size: 18),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          _currentStopIndex <
                                                  _optimizedOrders.length - 1
                                              ? l10n.confirmArrival
                                              : l10n.complete,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
