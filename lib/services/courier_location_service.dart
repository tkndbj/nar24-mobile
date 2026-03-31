// lib/services/courier_location_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';

class CourierLocationService {
  CourierLocationService._();
  static final CourierLocationService instance = CourierLocationService._();

  // ── Config ────────────────────────────────────────────────────────────────

  /// Minimum distance (metres) the device must move before we write a new
  /// position. Keeps writes low when the courier is stationary.
  static const double _minDistanceMetres = 15.0;

  /// Even if the courier hasn't moved, force a heartbeat write every N seconds
  /// so the dashboard knows the device is still alive.
  static const int _heartbeatSeconds = 30;

  // ── Internal state ────────────────────────────────────────────────────────

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;
  Position? _lastWrittenPosition;
  DateTime _lastWriteTime = DateTime(2000); // epoch sentinel
  bool _tracking = false;
  String? _currentOrderId; // kept in sync by FoodCargoScreen
  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://emlak-mobile-app-default-rtdb.europe-west1.firebasedatabase.app',
      );
  // ── Public API ────────────────────────────────────────────────────────────

  bool get isTracking => _tracking;

  /// Call from FoodCargoScreen.initState().
  /// Requests permission if needed then starts the GPS stream.
  Future<void> startTracking() async {
    debugPrint('[CourierLocation] startTracking() called, tracking=$_tracking');
    if (_tracking) return; // already running

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final granted = await _requestPermission();
    if (!granted) {
      debugPrint('[CourierLocation] Permission denied — not tracking.');
      return;
    }

    _tracking = true;
    debugPrint('[CourierLocation] Starting for uid=$uid');


    // ── Set online presence + disconnect hook ─────────────────────────────
    final locRef = _db.ref('courier_locations/$uid');

    // onDisconnect fires automatically when the connection drops
    // (app killed, network lost, etc.) — keeps the dashboard accurate.
    await locRef.child('isOnline').onDisconnect().set(false);
    await locRef.child('isOnShift').onDisconnect().set(false);

    await locRef.update({
      'isOnline': true,
      'isOnShift': true,
      'currentOrderId': _currentOrderId,
    });

    // ── GPS stream ────────────────────────────────────────────────────────
    // distanceFilter is the OS-level filter — the device won't fire an
    // event until the user has moved at least this many metres.
    // We add a second software filter on top inside _onPosition().
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // OS-level pre-filter (metres)
      ),
    ).listen(
      (pos) => _onPosition(uid, pos),
      onError: (e) => debugPrint('[CourierLocation] Stream error: $e'),
    );

    // ── Heartbeat: force a write every 30s even if stationary ────────────
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatSeconds),
      (_) => _writeHeartbeat(uid),
    );
  }

  /// Call from FoodCargoScreen.dispose() and on logout.
  Future<void> stopTracking() async {
    if (!_tracking) return;
    _tracking = false;

    await _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastWrittenPosition = null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Mark offline immediately (don't wait for onDisconnect)
    try {
      await _db.ref('courier_locations/$uid').update({
        'isOnline': false,
        'isOnShift': false,
      });
    } catch (e) {
      debugPrint('[CourierLocation] Stop update failed (non-fatal): $e');
    }

    debugPrint('[CourierLocation] Stopped for uid=$uid');
  }

  /// Call when the app goes to background (AppLifecycleState.paused).
  /// Keeps presence alive but suspends the GPS stream to save battery.
  Future<void> onAppPaused() async {
    if (!_tracking) return;
    await _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    debugPrint('[CourierLocation] Paused (app backgrounded).');
  }

  /// Call when the app returns to foreground (AppLifecycleState.resumed).
  Future<void> onAppResumed() async {
    if (!_tracking) return; // startTracking was never called

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    debugPrint('[CourierLocation] Resuming GPS stream.');

    // Re-mark as online (onDisconnect may have fired if connection dropped)
    await _db.ref('courier_locations/$uid').update({
      'isOnline': true,
      'isOnShift': true,
    });

    _positionSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (pos) => _onPosition(uid, pos),
      onError: (e) => debugPrint('[CourierLocation] Stream error: $e'),
    );

    _heartbeatTimer ??= Timer.periodic(
      const Duration(seconds: _heartbeatSeconds),
      (_) => _writeHeartbeat(uid),
    );
  }

  /// Keep RTDB `currentOrderId` in sync.
  /// Call from FoodCargoScreen whenever the courier takes or completes an order.
  Future<void> updateCurrentOrder(String? orderId) async {
    _currentOrderId = orderId;
    if (!_tracking) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.ref('courier_locations/$uid/currentOrderId').set(orderId);
    } catch (e) {
      debugPrint('[CourierLocation] updateCurrentOrder failed: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _onPosition(String uid, Position pos) {
    final now = DateTime.now();
    final secondsSinceLast = now.difference(_lastWriteTime).inSeconds;

    // Software distance filter on top of the OS filter
    if (_lastWrittenPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastWrittenPosition!.latitude,
        _lastWrittenPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      // Skip if barely moved AND heartbeat timer will handle the next write
      if (moved < _minDistanceMetres && secondsSinceLast < _heartbeatSeconds) {
        return;
      }
    }

    _writePosition(uid, pos);
    _lastWrittenPosition = pos;
    _lastWriteTime = now;
  }

  Future<void> _writePosition(String uid, Position pos) async {
    try {
      await _db.ref('courier_locations/$uid').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'heading': pos.heading, // degrees 0–360
        'speed': (pos.speed * 3.6).roundToDouble(), // m/s → km/h
        'isOnline': true,
        'isOnShift': true,
        'currentOrderId': _currentOrderId,
        'updatedAt': ServerValue.timestamp, // server-side ms timestamp
      });
    } catch (e) {
      debugPrint('[CourierLocation] Write failed: $e');
    }
  }

  /// Writes only the timestamp + online flags — no GPS (courier hasn't moved).
  Future<void> _writeHeartbeat(String uid) async {
    try {
      await _db.ref('courier_locations/$uid').update({
        'isOnline': true,
        'isOnShift': true,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[CourierLocation] Heartbeat failed: $e');
    }
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<bool> _requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[CourierLocation] Location services disabled on device.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[CourierLocation] Permission permanently denied.');
      return false;
    }

    return true;
  }
}
