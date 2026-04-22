// lib/services/courier_tracking_handler.dart
//
// The task handler runs in a separate Dart isolate inside an Android
// foreground service (and an iOS background-location context). It owns the
// GPS stream and the RTDB writes that feed CF-54's auto-assignment, so
// tracking continues when the UI is backgrounded, the screen is locked, or
// the activity is killed by the OS.
//
// RTDB contract (must match CF-54 mirrorCourierLocation):
//   courier_locations/{uid}
//     isOnline: bool
//     isOnShift: bool
//     lat: double
//     lng: double
//     heading: double        // degrees 0–360
//     speed: double          // km/h (m/s * 3.6)
//     currentOrderId: string?
//     updatedAt: server ms timestamp
//
// UI → service protocol (via FlutterForegroundTask.sendDataToTask):
//   {type: 'current_order', orderId: String?}
//   {type: 'notif_text',    activeOrders: int}
//
// Service → UI protocol (via FlutterForegroundTask.sendDataToMain):
//   {type: 'stopped', reason: 'notification_button' | 'auth_missing'}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

const String kCourierPrefOnShift = 'courier.onShift';
const String kCourierPrefUid = 'courier.uid';
const String kCourierStopButtonId = 'stop_shift';

const String _kRtdbUrl =
    'https://emlak-mobile-app-default-rtdb.europe-west1.firebasedatabase.app';

/// Entry point used by `FlutterForegroundTask.startService(callback: ...)`.
/// Must be a top-level function annotated with `@pragma('vm:entry-point')`
/// so tree-shaking and AOT don't strip it.
@pragma('vm:entry-point')
void courierServiceCallback() {
  FlutterForegroundTask.setTaskHandler(CourierTrackingHandler());
}

class CourierTrackingHandler extends TaskHandler {
  StreamSubscription<Position>? _posSub;
  Position? _lastWrittenPosition;
  DateTime _lastWriteAt = DateTime.now();

  String? _uid;
  String? _currentOrderId;
  int _activeOrders = 0;

  // Mirrors the UI-era thresholds. Keep in sync with CF-54's
  // COURIER_STALE_MS (120 000 ms). A 30 s heartbeat gives us 4× safety margin.
  static const double _minMovedMetres = 15.0;
  static const int _heartbeatSeconds = 30;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _kRtdbUrl,
      );

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Firebase must be re-initialised inside the service isolate — main()
    // doesn't run here. SharedPrefs survives across isolates, so we stash
    // the uid at startService time and fall back to it if Auth hasn't
    // re-hydrated yet (common right after a boot autoresume).
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      debugPrint('[CourierService] Firebase init failed: $e');
    }

    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid == null) {
      final prefs = await SharedPreferences.getInstance();
      _uid = prefs.getString(kCourierPrefUid);
    }

    if (_uid == null) {
      FlutterForegroundTask.sendDataToMain(
        {'type': 'stopped', 'reason': 'auth_missing'},
      );
      await FlutterForegroundTask.stopService();
      return;
    }

    // Set up presence + disconnect hooks. onDisconnect fires server-side
    // when the RTDB connection drops (app killed, network lost, OEM kill),
    // so the dispatcher sees this courier go offline within seconds.
    final ref = _db.ref('courier_locations/$_uid');
    try {
      await ref.child('isOnline').onDisconnect().set(false);
      await ref.child('isOnShift').onDisconnect().set(false);
      await ref.update({
        'isOnline': true,
        'isOnShift': true,
        'currentOrderId': _currentOrderId,
      });
    } catch (e) {
      debugPrint('[CourierService] RTDB presence setup failed: $e');
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // OS-level pre-filter (metres)
      ),
    ).listen(
      _onPosition,
      onError: (e) => debugPrint('[CourierService] GPS stream error: $e'),
    );

    _refreshNotification();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final type = data['type'];

    if (type == 'current_order') {
      _currentOrderId = data['orderId'] as String?;
      if (_uid != null) {
        _db
            .ref('courier_locations/$_uid/currentOrderId')
            .set(_currentOrderId)
            .catchError((_) {});
      }
    } else if (type == 'notif_text') {
      final count = data['activeOrders'];
      _activeOrders = count is int ? count : 0;
      _refreshNotification();
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Forced heartbeat so the dispatcher sees us even if the courier is
    // stationary — CF-54 drops stale couriers after 2 min of silence.
    await _writeHeartbeat();
    _refreshNotification();
  }

  @override
  Future<void> onNotificationButtonPressed(String id) async {
    if (id != kCourierStopButtonId) return;

    // Persist the off-shift flag first so UI autoresume won't start us
    // again on the next launch.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kCourierPrefOnShift, false);

    await _markOffline();
    FlutterForegroundTask.sendDataToMain(
      {'type': 'stopped', 'reason': 'notification_button'},
    );
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _posSub?.cancel();
    _posSub = null;
    await _markOffline();
  }

  // ─── private ──────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    final now = DateTime.now();
    final secondsSinceLast = now.difference(_lastWriteAt).inSeconds;

    if (_lastWrittenPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastWrittenPosition!.latitude,
        _lastWrittenPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      // Skip near-stationary fixes — onRepeatEvent handles staleness.
      if (moved < _minMovedMetres && secondsSinceLast < _heartbeatSeconds) {
        return;
      }
    }

    _writePosition(pos);
    _lastWrittenPosition = pos;
    _lastWriteAt = now;
  }

  Future<void> _writePosition(Position pos) async {
    if (_uid == null) return;
    try {
      await _db.ref('courier_locations/$_uid').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'heading': pos.heading,
        'speed': (pos.speed * 3.6).roundToDouble(),
        'isOnline': true,
        'isOnShift': true,
        'currentOrderId': _currentOrderId,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[CourierService] Position write failed: $e');
    }
  }

  Future<void> _writeHeartbeat() async {
    if (_uid == null) return;
    try {
      await _db.ref('courier_locations/$_uid').update({
        'isOnline': true,
        'isOnShift': true,
        'updatedAt': ServerValue.timestamp,
      });
      _lastWriteAt = DateTime.now();
    } catch (e) {
      debugPrint('[CourierService] Heartbeat write failed: $e');
    }
  }

  Future<void> _markOffline() async {
    if (_uid == null) return;
    try {
      await _db.ref('courier_locations/$_uid').update({
        'isOnline': false,
        'isOnShift': false,
      });
    } catch (_) {/* ignore — best-effort on teardown */}
  }

  void _refreshNotification() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final body = _activeOrders > 0
        ? '$_activeOrders aktif teslimat · son güncelleme $hh:$mm'
        : 'Aktif sipariş yok · son güncelleme $hh:$mm';

    FlutterForegroundTask.updateService(
      notificationTitle: 'Nar24 Kurye — Mesaidesin',
      notificationText: body,
    );
  }
}
