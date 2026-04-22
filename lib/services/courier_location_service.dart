// lib/services/courier_location_service.dart
//
// Thin UI-side controller for the courier foreground service.
//
// The actual GPS stream + RTDB writes live in CourierTrackingHandler
// (service isolate — see `courier_tracking_handler.dart`) so that tracking
// survives the Flutter activity being backgrounded, screen-locked, or
// killed by the OS. This class only:
//
//   1. Funnels permissions (locationWhenInUse → locationAlways →
//      POST_NOTIFICATIONS → ignoreBatteryOptimizations) in the right order.
//   2. Starts / stops the foreground service when the courier toggles shift.
//   3. Sends live `currentOrderId` and active-order-count updates to the
//      service so the persistent notification stays useful.
//   4. Resumes tracking at app start if the shift flag was persisted ON —
//      this covers both "app re-opened" and "phone rebooted mid-shift".
//
// Shift state is the courier's explicit opt-in to receive auto-assignments.
// It is independent of `isOnline` (which follows device connectivity).
// The auto-assigner in CF-54 requires BOTH online and on-shift to dispatch.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'courier_tracking_handler.dart';

class CourierLocationService {
  CourierLocationService._();
  static final CourierLocationService instance = CourierLocationService._();

  final _shiftController = StreamController<bool>.broadcast();
  bool _onShift = false;
  String? _currentOrderId;
  int _lastSentOrderCount = -1;
  bool _initialised = false;

  // Unique service id — any int, just has to be stable across invocations.
  static const int _serviceId = 554411;

  // ── Public API ────────────────────────────────────────────────────────

  bool get isOnShift => _onShift;
  bool get isTracking => _onShift;
  Stream<bool> get shiftStream => _shiftController.stream;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://emlak-mobile-app-default-rtdb.europe-west1.firebasedatabase.app',
      );

  /// Live RTDB connection state — true when the device has an active
  /// connection to Firebase. Drives the offline banner in FoodCargoScreen.
  Stream<bool> get connectionStream => _db
      .ref('.info/connected')
      .onValue
      .map((event) => event.snapshot.value as bool? ?? false);

  /// Lazy — called automatically from `bootOnShift` and `setOnShift` the
  /// first time a courier interacts with this service. Buyers and other
  /// non-courier roles never trigger this, so no notification channel is
  /// registered on their devices and the foreground-service plugin stays
  /// entirely dormant in their install.
  ///
  /// Idempotent; subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;

    // Opens the port used by sendDataToTask / addTaskDataCallback.
    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'courier_tracking',
        channelName: 'Kurye konum takibi',
        channelDescription:
            'Mesai açıkken konumunuz dispatcher\'a canlı gönderilir.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        // Keep the "son güncelleme HH:mm" indicator readable on the lock
        // screen regardless of the courier's device-level privacy settings.
        // The body is work-status only (order count + timestamp) — no PII.
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30 * 1000), // 30 s
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
  }

  /// Reads the persisted shift flag. If it was ON (either from the last
  /// session or from before a reboot), re-start the foreground service.
  /// Off-shift is the safe default — no dispatches land until opt-in.
  ///
  /// Call from FoodCargoScreen.initState(). Fast-paths out before touching
  /// the foreground-service plugin if the courier has never been on shift,
  /// so a courier who just opens the panel to look around pays nothing.
  Future<void> bootOnShift() async {
    final prefs = await SharedPreferences.getInstance();
    final wasOn = prefs.getBool(kCourierPrefOnShift) ?? false;
    _onShift = wasOn;
    _shiftController.add(wasOn);
    if (!wasOn) return;

    // First courier-side touch of the plugin — register the channel and
    // options now, not at app startup.
    await initialize();

    // flutter_foreground_task's autoRunOnBoot may have already restarted
    // the service after reboot. Only start if not already running.
    final running = await FlutterForegroundTask.isRunningService;
    if (running) return;

    final ok = await _startService(fromBoot: true);
    if (!ok) {
      // Permissions were revoked between sessions — fall back to off-shift
      // and let the user re-toggle so they see the permission prompt again.
      _onShift = false;
      await prefs.setBool(kCourierPrefOnShift, false);
      _shiftController.add(false);
    }
  }

  /// Toggles shift on or off. On → foreground service starts and CF-54
  /// can route orders here. Off → service stops, RTDB flags cleared, CF-54
  /// removes the courier from the geo index on the next mirror tick.
  Future<void> setOnShift(bool value) async {
    if (_onShift == value) return;
    // Lazy — plugin state is only created on the first shift-on. No-op
    // for subsequent calls in the same process.
    await initialize();
    final prefs = await SharedPreferences.getInstance();

    if (value) {
      final ok = await _startService(fromBoot: false);
      if (!ok) return; // permission rejected — keep state off
      _onShift = true;
      await prefs.setBool(kCourierPrefOnShift, true);
      _shiftController.add(true);

      // Flush any known state into the service so the first notification
      // update doesn't show stale "starting…" text.
      if (_currentOrderId != null) {
        FlutterForegroundTask.sendDataToTask({
          'type': 'current_order',
          'orderId': _currentOrderId,
        });
      }
      if (_lastSentOrderCount >= 0) {
        FlutterForegroundTask.sendDataToTask({
          'type': 'notif_text',
          'activeOrders': _lastSentOrderCount,
        });
      }
    } else {
      await prefs.setBool(kCourierPrefOnShift, false);
      _onShift = false;
      _shiftController.add(false);
      await FlutterForegroundTask.stopService();
      await _markOfflineFromUi();
    }
  }

  /// UI tells the service which order the courier is currently carrying.
  /// Mirrored to RTDB `courier_locations/{uid}/currentOrderId` by the
  /// service so the ops dashboard can render driver-to-order links.
  Future<void> updateCurrentOrder(String? orderId) async {
    _currentOrderId = orderId;
    if (!_onShift) return;
    FlutterForegroundTask.sendDataToTask({
      'type': 'current_order',
      'orderId': orderId,
    });
  }

  /// UI tells the service how many deliveries the courier is holding so
  /// the persistent notification can show "3 aktif teslimat" instead of
  /// a generic "on shift" message. Debounced to skip redundant sends.
  Future<void> updateActiveOrderCount(int count) async {
    if (count == _lastSentOrderCount) return;
    _lastSentOrderCount = count;
    if (!_onShift) return;
    FlutterForegroundTask.sendDataToTask({
      'type': 'notif_text',
      'activeOrders': count,
    });
  }

  // The service isolate owns GPS now, so app lifecycle transitions are
  // no-ops here — kept for source compatibility with FoodCargoScreen's
  // existing WidgetsBindingObserver hooks.
  Future<void> onAppPaused() async {}
  Future<void> onAppResumed() async {}

  // ── Internal ──────────────────────────────────────────────────────────

  Future<bool> _startService({required bool fromBoot}) async {
    final permsOk = await _ensurePermissions(fromBoot: fromBoot);
    if (!permsOk) return false;

    // Stash uid so the service isolate can initialise before Firebase Auth
    // has re-hydrated its session (common on boot autoresume).
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null && !fromBoot) {
      debugPrint('[CourierLocation] Cannot start shift — not signed in.');
      return false;
    }
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kCourierPrefUid, uid);
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Nar24 Kurye — Mesaidesin',
      notificationText: 'Başlatılıyor…',
      notificationButtons: const [
        NotificationButton(id: kCourierStopButtonId, text: 'Mesaiyi Bitir'),
      ],
      callback: courierServiceCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// Runs the permission funnel in the correct OS order:
  ///   1. Location when-in-use (hard requirement)
  ///   2. Location always (recommended; fallback works on foreground-service-grade)
  ///   3. Notifications (Android 13+)
  ///   4. Ignore battery optimisations (Android only)
  ///
  /// On a boot autoresume we skip *prompts* but still verify the
  /// permissions haven't been revoked — a prompt during boot would dismiss
  /// itself before the user sees it.
  Future<bool> _ensurePermissions({required bool fromBoot}) async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      if (fromBoot) return false;
      final req = await Permission.locationWhenInUse.request();
      if (!req.isGranted) return false;
    }

    // Location services on the device (GPS toggle) — Permission.location
    // grant doesn't help if the user has GPS disabled system-wide.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final always = await Permission.locationAlways.status;
    if (!always.isGranted && !fromBoot) {
      // Non-fatal if denied — foreground-service grade location still works
      // while the service notification is visible. Request once, don't block
      // on refusal.
      await Permission.locationAlways.request();
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final notif = await FlutterForegroundTask.checkNotificationPermission();
      if (notif != NotificationPermission.granted && !fromBoot) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final ignoringBatt =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!ignoringBatt && !fromBoot) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    return true;
  }

  void _onServiceData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'stopped') {
      // Service told us it stopped itself (user tapped "Mesaiyi Bitir" on
      // the notification, or the isolate couldn't find the uid). Sync UI.
      _onShift = false;
      _shiftController.add(false);
      SharedPreferences.getInstance()
          .then((p) => p.setBool(kCourierPrefOnShift, false));
    }
  }

  Future<void> _markOfflineFromUi() async {
    // Belt-and-suspenders: the service already writes isOnline=false on
    // destroy, but if stopService races ahead we still guarantee the flag
    // flips so auto-assignment doesn't route to a no-longer-on-shift courier.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.ref('courier_locations/$uid').update({
        'isOnline': false,
        'isOnShift': false,
      });
    } catch (_) {/* best-effort */}
  }
}
